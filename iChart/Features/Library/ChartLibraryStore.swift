import Combine
import Foundation
import SwiftUI

enum ChartLibraryPersistenceStatus: Equatable {
    case notTracking
    case ready
    case saved(at: Date)
    case failed(message: String)
}

/// Enough to report a startup I/O failure after optional telemetry is ready.
/// It contains no chart, ink, repository, identifier, or error description.
struct ChartLibraryLoadOutcome: Equatable, Sendable {
    let succeeded: Bool
    let durationMilliseconds: Double
}

final class ChartLibraryStore: ObservableObject {
    @Published var charts: [Chart] {
        didSet { persistIfNeeded() }
    }
    @Published var selectedChartID: Chart.ID? {
        didSet { if selectedChartID != oldValue { persistIfNeeded() } }
    }
    @Published var entitlements: AppEntitlements {
        didSet { if entitlements != oldValue { persistIfNeeded() } }
    }
    @Published var deletionTombstones: [ChartDeletionTombstone] {
        didSet { persistIfNeeded() }
    }
    @Published var cloudMetadata: ChartCloudMetadata {
        didSet { if cloudMetadata != oldValue { persistIfNeeded() } }
    }
    @Published var projects: [ChartProject] {
        didSet { persistIfNeeded() }
    }
    @Published private(set) var persistenceStatus: ChartLibraryPersistenceStatus = .notTracking
    // Updated before persistenceStatus publishes so observers can tell a
    // failed write from a failed startup load, even for a repeated error.
    private(set) var retryableSaveFailureMessage: String?
    private(set) var initialLoadOutcome: ChartLibraryLoadOutcome?
    @Published private(set) var libraryLoadFailureMessage: String?

    var hasUnresolvedLoadFailure: Bool { libraryLoadFailureMessage != nil }

    var onSnapshotSaved: ((ChartLibrarySnapshot) -> Void)?

    private let repository: ChartRepository?
    private let chordDiagnosticsResetter: (() -> Void)?
    private var persistenceEnabled = false
    private var cloudSyncNotificationsEnabled = true
    private let asyncPersistenceQueue = DispatchQueue(label: "com.ichart.chart-library-store.persistence", qos: .utility)
    private var pendingAsyncPersistence: (
        snapshot: ChartLibrarySnapshot,
        notifyCloudSync: Bool,
        generation: Int
    )?
    private var asyncPersistenceInFlight = false
    private var persistenceGeneration = 0

    init(
        charts: [Chart],
        entitlements: AppEntitlements = .free,
        selectedChartID: Chart.ID? = nil,
        deletionTombstones: [ChartDeletionTombstone] = [],
        cloudMetadata: ChartCloudMetadata = ChartCloudMetadata(),
        projects: [ChartProject] = [],
        repository: ChartRepository? = nil,
        chordDiagnosticsResetter: (() -> Void)? = nil,
        persistenceDiagnostics: ChartPersistenceContractDiagnostics? = nil
    ) {
        self.charts = charts
        self.entitlements = entitlements
        self.selectedChartID = Self.sanitizedSelection(selectedChartID, charts: charts)
        self.deletionTombstones = Self.normalizedTombstones(deletionTombstones)
        self.cloudMetadata = cloudMetadata
        self.projects = Self.normalizedProjects(projects, charts: charts)
        self.repository = repository
        self.chordDiagnosticsResetter = chordDiagnosticsResetter
        // Legacy callers may supply the former observer. It is intentionally
        // never retained or invoked: diagnostics cannot reread/hash the library
        // or occupy the serial queue needed by the next real save.
        _ = persistenceDiagnostics
        self.persistenceStatus = repository == nil ? .notTracking : .ready
        persistenceEnabled = true
    }

    convenience init(snapshot: ChartLibrarySnapshot, repository: ChartRepository? = nil) {
        self.init(
            charts: snapshot.charts,
            entitlements: snapshot.entitlements,
            selectedChartID: snapshot.selectedChartID,
            deletionTombstones: snapshot.deletionTombstones,
            cloudMetadata: snapshot.cloudMetadata,
            projects: snapshot.projects,
            repository: repository
        )
    }

    var canCreateChart: Bool {
        entitlements.canCreateChart(currentChartCount: charts.count)
    }

    var chartCapacityText: String {
        entitlements.chartCapacityText(currentChartCount: charts.count)
    }

    var subscriptionState: IChartSubscriptionEntitlement {
        entitlements.subscription
    }

    var localChartLimit: Int? {
        entitlements.localChartLimit
    }

    var requiresLocalChartPruningForCurrentPlan: Bool {
        // Voluntarily leaving free Pro must not force deletion or lock editing
        // of existing charts. Only new-chart capacity is limited in Beta Basic.
        guard !entitlements.accessPolicy.isFreeBeta else { return false }
        guard let localChartLimit else {
            return false
        }

        return charts.count > localChartLimit
    }

    var isChartEditingLockedByCurrentPlan: Bool {
        requiresLocalChartPruningForCurrentPlan
    }

    var canOpenChartsForEditing: Bool {
        !isChartEditingLockedByCurrentPlan
    }

    var localChartOverflowCount: Int {
        guard let localChartLimit else {
            return 0
        }

        return max(0, charts.count - localChartLimit)
    }

    func canUse(_ feature: EntitledFeature) -> Bool {
        entitlements.includes(feature)
    }

    var projectChartIDSet: Set<Chart.ID> {
        Set(projects.flatMap(\.chartIDs))
    }

    func editorBinding(for chartID: Chart.ID) -> Binding<Chart>? {
        guard let initialChart = charts.first(where: { $0.id == chartID }) else {
            return nil
        }

        // PencilKit callbacks can outlive a library refresh or chart reorder.
        // Resolve the chart again on each access so a late edit cannot hit a different row.
        return Binding(
            get: { self.charts.first(where: { $0.id == chartID }) ?? initialChart },
            set: { updatedChart in
                guard updatedChart.id == chartID,
                      let index = self.charts.firstIndex(where: { $0.id == chartID }),
                      self.charts.lastIndex(where: { $0.id == chartID }) == index else {
                    return
                }

                self.charts[index] = updatedChart
            }
        )
    }

    func setPlan(_ plan: IChartPlan) {
        var updatedEntitlements = entitlements
        updatedEntitlements.applyLegacyPlan(plan)
        guard updatedEntitlements != entitlements else { return }
        entitlements = updatedEntitlements
    }

    func applySubscriptionState(_ subscription: IChartSubscriptionEntitlement) {
        var updatedEntitlements = entitlements
        updatedEntitlements.applySubscription(subscription)
        guard updatedEntitlements != entitlements else { return }
        entitlements = updatedEntitlements
    }

    func applyAccessPolicy(_ accessPolicy: IChartProductAccessPolicy) {
        guard entitlements.accessPolicy != accessPolicy else { return }
        entitlements = AppEntitlements(
            subscription: entitlements.subscription,
            accessPolicy: accessPolicy
        )
    }

    @discardableResult
    func createPreparedChart(
        _ preparedChart: Chart,
        projectID: ChartProject.ID? = nil
    ) -> Bool {
        // New-chart setup is local until its final Create action. Admit the
        // completed value once, with the same limits and project access used
        // by the existing blank-chart path.
        guard !hasUnresolvedLoadFailure,
              preparedChart.hasCompletedInitialSetup,
              !charts.contains(where: { $0.id == preparedChart.id }),
              canCreateChart,
              projectID == nil || canUse(.projects),
              projectID == nil || projects.contains(where: { $0.id == projectID }) else {
            return false
        }

        performPersistedBatch {
            charts.insert(preparedChart, at: 0)
            if let projectID {
                addChartToProjectInPlace(chartID: preparedChart.id, projectID: projectID, atFront: true)
            }
            selectedChartID = preparedChart.id
        }
        return true
    }

    @discardableResult
    func createBlankChart(
        in key: DocumentKey = .cMajor,
        layoutStyle: ChartLayoutStyle = .leadSheet,
        projectID: ChartProject.ID? = nil
    ) -> Bool {
        let traceSpan = IChartPerformanceTrace.start(
            "chartLibrary.createBlankChart",
            metadata: [
                "layoutStyle": layoutStyle.rawValue,
                "chartCountBefore": "\(charts.count)",
                "targetProject": projectID == nil ? "none" : "present"
            ]
        )
        var didCreateChart = false
        defer {
            IChartPerformanceTrace.end(
                traceSpan,
                metadata: [
                    "result": didCreateChart ? "created" : "blocked",
                    "chartCountAfter": "\(charts.count)"
                ]
            )
        }

        guard canCreateChart, projectID == nil || canUse(.projects) else {
            return false
        }

        let newChart = Chart.draft(title: "Untitled Chart", key: key, layoutStyle: layoutStyle)
        performPersistedBatch {
            charts.insert(newChart, at: 0)
            if let projectID {
                addChartToProjectInPlace(chartID: newChart.id, projectID: projectID, atFront: true)
            }
            selectedChartID = newChart.id
        }
        didCreateChart = true
        return true
    }

    @discardableResult
    func renameChart(id chartID: Chart.ID, to proposedTitle: String) -> Bool {
        let sanitizedTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty,
              let chartIndex = charts.firstIndex(where: { $0.id == chartID }) else {
            return false
        }

        performPersistedBatch {
            charts[chartIndex].title = sanitizedTitle
            charts[chartIndex].updatedAt = .now
        }
        return true
    }

    @discardableResult
    func duplicateChart(
        id chartID: Chart.ID,
        title proposedTitle: String? = nil,
        documentKey: DocumentKey? = nil,
        transpositionView: TranspositionView? = nil,
        projectID: ChartProject.ID? = nil
    ) -> Chart.ID? {
        guard canCreateChart, projectID == nil || canUse(.projects),
              let chartIndex = charts.firstIndex(where: { $0.id == chartID }) else {
            return nil
        }

        var duplicate = charts[chartIndex]
        let now = Date()
        duplicate.id = UUID()
        duplicate.title = proposedTitle.flatMap(Self.sanitizedTitle)
            ?? Self.duplicateTitle(for: duplicate.title, existingTitles: Set(charts.map(\.title)))
        if let documentKey {
            duplicate.documentKey = documentKey
        }
        if let transpositionView {
            duplicate.setInstrumentTranspositionView(transpositionView)
        }
        duplicate.cloudBackupStatus = .included
        duplicate.createdAt = now
        duplicate.updatedAt = now

        performPersistedBatch {
            charts.insert(duplicate, at: min(chartIndex + 1, charts.endIndex))
            if let projectID {
                addChartToProjectInPlace(chartID: duplicate.id, projectID: projectID, atFront: false)
            }
            selectedChartID = duplicate.id
        }
        return duplicate.id
    }

    @discardableResult
    func createProject(title proposedTitle: String, chartIDs: [Chart.ID] = []) -> ChartProject.ID? {
        guard canUse(.projects),
              let title = ChartProject.sanitizedTitle(proposedTitle) else {
            return nil
        }

        let availableChartIDs = Set(charts.map(\.id))
        let validChartIDs = ChartProject.uniqueChartIDs(chartIDs).filter { availableChartIDs.contains($0) }
        let now = Date()
        let project = ChartProject(
            title: title,
            chartIDs: validChartIDs,
            createdAt: now,
            updatedAt: now
        )
        projects.insert(project, at: 0)
        return project.id
    }

    @discardableResult
    func renameProject(id projectID: ChartProject.ID, to proposedTitle: String) -> Bool {
        guard canUse(.projects),
              let title = ChartProject.sanitizedTitle(proposedTitle),
              let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return false
        }

        projects[projectIndex].title = title
        projects[projectIndex].updatedAt = Date()
        return true
    }

    @discardableResult
    func deleteProject(id projectID: ChartProject.ID) -> Bool {
        guard canUse(.projects),
              projects.contains(where: { $0.id == projectID }) else {
            return false
        }

        projects.removeAll { $0.id == projectID }
        return true
    }

    @discardableResult
    func addChartToProject(chartID: Chart.ID, projectID: ChartProject.ID) -> Bool {
        guard canUse(.projects),
              charts.contains(where: { $0.id == chartID }) else {
            return false
        }

        return addChartToProjectInPlace(chartID: chartID, projectID: projectID, atFront: false)
    }

    @discardableResult
    func removeChartFromProject(chartID: Chart.ID, projectID: ChartProject.ID) -> Bool {
        guard canUse(.projects),
              let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              projects[projectIndex].chartIDs.contains(chartID) else {
            return false
        }

        projects[projectIndex].removeChart(chartID)
        return true
    }

    func charts(in project: ChartProject) -> [Chart] {
        project.chartIDs.compactMap { chartID in
            charts.first { $0.id == chartID }
        }
    }

    @discardableResult
    func deleteChart(id chartID: Chart.ID) -> Bool {
        deleteCharts(ids: [chartID]) > 0
    }

    /// Returns the accepted deletion count. Repositories that save asynchronously
    /// report the eventual save result through `persistenceStatus`.
    @discardableResult
    func deleteCharts(ids chartIDs: Set<Chart.ID>) -> Int {
        let deletedCharts = charts.filter { chartIDs.contains($0.id) }
        guard !deletedCharts.isEmpty else {
            return 0
        }

        let previousSnapshot = snapshot
        let deletedChartIDs = Set(deletedCharts.map(\.id))
        let updatedCharts = charts.filter { !deletedChartIDs.contains($0.id) }
        var proposedSelection = selectedChartID
        if let selectedChartID,
           deletedChartIDs.contains(selectedChartID),
           let selectedIndex = charts.firstIndex(where: { $0.id == selectedChartID }) {
            proposedSelection = charts.dropFirst(selectedIndex + 1)
                .first { !deletedChartIDs.contains($0.id) }?.id
                ?? updatedCharts.last?.id
        }

        let deletedAt = Date()
        let didAcceptPersistence = performPersistedBatch {
            charts = updatedCharts
            for chart in deletedCharts {
                removeChartFromAllProjectsInPlace(chart.id)
                upsertTombstone(
                    chartID: chart.id,
                    deletedAt: deletedAt,
                    shouldSyncToCloud: chart.hasCloudBackupRecord
                )
            }
            selectedChartID = Self.sanitizedSelection(proposedSelection, charts: updatedCharts)
        }

        if !didAcceptPersistence {
            // Keep the failure visible without saving or syncing a rollback.
            let wasPersistenceEnabled = persistenceEnabled
            persistenceEnabled = false
            charts = previousSnapshot.charts
            projects = previousSnapshot.projects
            deletionTombstones = previousSnapshot.deletionTombstones
            selectedChartID = previousSnapshot.selectedChartID
            persistenceEnabled = wasPersistenceEnabled
            return 0
        }
        return deletedCharts.count
    }

    @discardableResult
    func pruneLocalChartForCurrentPlan(id chartID: Chart.ID) -> Bool {
        guard requiresLocalChartPruningForCurrentPlan,
              charts.contains(where: { $0.id == chartID }) else {
            return false
        }

        let proposedSelection = selectedChartID == chartID
            ? charts.first(where: { $0.id != chartID })?.id
            : selectedChartID

        performPersistedBatch(notifyCloudSync: false) {
            charts.removeAll { $0.id == chartID }
            removeChartFromAllProjectsInPlace(chartID)
            selectedChartID = Self.sanitizedSelection(proposedSelection, charts: charts)
        }
        return true
    }

    #if DEBUG
    @discardableResult
    func createChordWritingTestChart() -> Chart.ID {
        let testChartTitle = "Chord Writing Test Chart"
        var testChart = Chart.blank(title: testChartTitle, key: .cMajor, measureCount: 8)
        testChart.styleNote = "CHORD TEST LOOP"
        chordDiagnosticsResetter?()

        var updatedCharts = charts.filter { $0.title != testChartTitle }
        updatedCharts.insert(testChart, at: 0)
        charts = updatedCharts
        selectedChartID = testChart.id
        return testChart.id
    }
    #endif

    var snapshot: ChartLibrarySnapshot {
        ChartLibrarySnapshot(
            charts: charts,
            selectedChartID: selectedChartID,
            entitlements: entitlements,
            deletionTombstones: deletionTombstones,
            cloudMetadata: cloudMetadata,
            projects: projects
        )
    }

    func applySyncedSnapshot(_ snapshot: ChartLibrarySnapshot) {
        let accessPolicy = entitlements.accessPolicy
        performPersistedBatch(notifyCloudSync: false) {
            charts = snapshot.charts
            // Saved snapshots carry billing evidence, never account Beta mode.
            if accessPolicy.isFreeBeta {
                entitlements = AppEntitlements(
                    subscription: snapshot.entitlements.subscription,
                    accessPolicy: accessPolicy
                )
            } else {
                entitlements = snapshot.entitlements
            }
            deletionTombstones = Self.normalizedTombstones(snapshot.deletionTombstones)
            cloudMetadata = snapshot.cloudMetadata
            projects = Self.normalizedProjects(snapshot.projects, charts: snapshot.charts)
            selectedChartID = Self.sanitizedSelection(snapshot.selectedChartID, charts: snapshot.charts)
        }
    }

    @discardableResult
    func applySyncedSnapshot(
        _ snapshot: ChartLibrarySnapshot,
        ifUnchangedFrom expectedSnapshot: ChartLibrarySnapshot
    ) -> Bool {
        guard self.snapshot == expectedSnapshot else {
            return false
        }

        applySyncedSnapshot(snapshot)
        return true
    }

    func updateCloudMetadataFromSync(ownerID: UUID, lastSyncAt: Date, lastRemoteBackupAt: Date?) {
        var updatedMetadata = cloudMetadata
        updatedMetadata.ownerID = ownerID
        updatedMetadata.lastSyncAt = lastSyncAt
        if let lastRemoteBackupAt {
            updatedMetadata.lastRemoteBackupAt = lastRemoteBackupAt
        }
        guard updatedMetadata != cloudMetadata else { return }

        performPersistedBatch(notifyCloudSync: false) {
            cloudMetadata = updatedMetadata
        }
    }

    func enrollLocalChartsForCloudBackup() -> ChartLibrarySnapshot {
        let chartIndices = charts.indices.filter {
            charts[$0].cloudBackupStatus.intent != .included
                || charts[$0].cloudBackupStatus.schemaVersion != ChartCloudBackupStatus.schemaVersion
        }
        guard !chartIndices.isEmpty else { return snapshot }
        performPersistedBatch(notifyCloudSync: false) {
            for chartIndex in chartIndices {
                charts[chartIndex].includeInCloudBackup()
            }
        }

        return snapshot
    }

    func markChartsBackedUpToCloud(
        chartIDs: Set<Chart.ID>,
        ownerID: UUID,
        backedUpAt: Date,
        from uploadedSnapshot: ChartLibrarySnapshot,
        acknowledgedContentSHA256ByChartID: [Chart.ID: String] = [:]
    ) {
        guard !chartIDs.isEmpty else {
            return
        }

        let uploadedChartsByID = Dictionary(grouping: uploadedSnapshot.charts, by: \.id)
        let currentChartCounts = Dictionary(grouping: charts, by: \.id).mapValues(\.count)
        let matchingUpdates = charts.indices.compactMap { chartIndex -> (Int, ChartCloudBackupStatus)? in
            let chartID = charts[chartIndex].id
            guard chartIDs.contains(chartID),
                  currentChartCounts[chartID] == 1,
                  let uploadedCharts = uploadedChartsByID[chartID],
                  uploadedCharts.count == 1,
                  let uploadedChart = uploadedCharts.first,
                  charts[chartIndex].shouldBackUpToCloud(for: ownerID),
                  uploadedChart.shouldBackUpToCloud(for: ownerID),
                  ChartCloudContentIdentity.matchesContent(charts[chartIndex], uploadedChart) else {
                return nil
            }
            let acknowledgement = acknowledgedContentSHA256ByChartID[chartID]
            guard acknowledgement == nil || ChartCloudContentIdentity.isValidSHA256(acknowledgement) else {
                return nil
            }
            var updatedStatus = charts[chartIndex].cloudBackupStatus
            updatedStatus.markBackedUp(ownerID: ownerID, at: backedUpAt)
            updatedStatus.acknowledgedContentSHA256 = acknowledgement
            guard updatedStatus != charts[chartIndex].cloudBackupStatus else { return nil }
            return (chartIndex, updatedStatus)
        }

        guard !matchingUpdates.isEmpty else {
            return
        }

        performPersistedBatch(notifyCloudSync: false) {
            for (chartIndex, updatedStatus) in matchingUpdates {
                charts[chartIndex].cloudBackupStatus = updatedStatus
            }
        }
    }

    static func live(
        repository: ChartRepository = FileChartRepository.live(),
        persistenceDiagnostics: ChartPersistenceContractDiagnostics? = nil
    ) -> ChartLibraryStore {
        let loadStartedAt = ProcessInfo.processInfo.systemUptime
        let loadedSnapshot: ChartLibrarySnapshot?
        let loadError: Error?
        do {
            loadedSnapshot = try repository.loadSnapshot()
            loadError = nil
        } catch {
            loadedSnapshot = nil
            loadError = error
        }
        let loadDurationMilliseconds = (ProcessInfo.processInfo.systemUptime - loadStartedAt) * 1_000

        let snapshot: ChartLibrarySnapshot
        #if DEBUG && targetEnvironment(simulator)
        let showsEditorUIFixture = IChartSimulatorPreviewLaunch.showsEditorUIFixture
        #else
        // SwiftPM excludes app-only helpers; previews are also unavailable
        // outside Debug Simulator builds. Preserve normal loading everywhere.
        let showsEditorUIFixture = false
        #endif
        if showsEditorUIFixture {
            let charts = [
                ChartSamples.straightAheadSwing,
                Chart.blank(
                    title: "Simple Sheet UI Fixture",
                    key: .eFlatMajor,
                    measureCount: 8,
                    layoutStyle: .simpleChordSheet
                ),
                Chart.blank(
                    title: "Rhythm Section UI Fixture",
                    key: .eFlatMajor,
                    measureCount: 8,
                    layoutStyle: .rhythmSectionSheet
                )
            ]
            snapshot = ChartLibrarySnapshot(
                charts: charts,
                selectedChartID: charts.first?.id,
                entitlements: .free
            )
        } else if let loadedSnapshot {
            snapshot = loadedSnapshot
        } else {
            snapshot = loadError == nil ? .empty : .preview
        }
        #if DEBUG && targetEnvironment(simulator)
        let chordDiagnosticsResetter: (() -> Void)? = {
            try? ChordEntryDiagnosticsRecorder.live().reset()
        }
        #else
        let chordDiagnosticsResetter: (() -> Void)? = nil
        #endif

        let store = ChartLibraryStore(
            charts: snapshot.charts,
            entitlements: snapshot.entitlements,
            selectedChartID: snapshot.selectedChartID,
            deletionTombstones: snapshot.deletionTombstones,
            cloudMetadata: snapshot.cloudMetadata,
            projects: snapshot.projects,
            repository: repository,
            chordDiagnosticsResetter: chordDiagnosticsResetter,
            persistenceDiagnostics: persistenceDiagnostics
        )
        if let loadError {
            store.libraryLoadFailureMessage = loadError.localizedDescription
            store.persistenceStatus = .failed(message: loadError.localizedDescription)
        } else if loadedSnapshot != nil {
            store.persistenceStatus = .saved(at: .now)
        }
        if !showsEditorUIFixture {
            store.initialLoadOutcome = ChartLibraryLoadOutcome(
                succeeded: loadError == nil, durationMilliseconds: loadDurationMilliseconds
            )
        }
        return store
    }

    static var preview: ChartLibraryStore {
        ChartLibraryStore(snapshot: .preview)
    }

    func retrySavingCurrentSnapshot() {
        guard retryableSaveFailureMessage != nil else { return }
        persistIfNeeded()
    }

    /// A failed initial read never grants permission to replace the unread
    /// library with the in-memory fallback. Recovery reads the existing file
    /// again and enables writes only after that complete snapshot was decoded.
    @discardableResult
    func retryLoadingSavedSnapshot() -> Bool {
        guard hasUnresolvedLoadFailure, let repository else { return false }
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            guard let loaded = try repository.loadSnapshot() else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let wasPersistenceEnabled = persistenceEnabled
            persistenceEnabled = false
            charts = loaded.charts
            selectedChartID = Self.sanitizedSelection(loaded.selectedChartID, charts: loaded.charts)
            entitlements = AppEntitlements(subscription: loaded.entitlements.subscription,
                                           accessPolicy: entitlements.accessPolicy)
            deletionTombstones = Self.normalizedTombstones(loaded.deletionTombstones)
            cloudMetadata = loaded.cloudMetadata
            projects = Self.normalizedProjects(loaded.projects, charts: loaded.charts)
            persistenceEnabled = wasPersistenceEnabled
            libraryLoadFailureMessage = nil
            retryableSaveFailureMessage = nil
            persistenceStatus = .saved(at: .now)
            initialLoadOutcome = ChartLibraryLoadOutcome(succeeded: true,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            return true
        } catch {
            libraryLoadFailureMessage = error.localizedDescription
            persistenceStatus = .failed(message: error.localizedDescription)
            initialLoadOutcome = ChartLibraryLoadOutcome(succeeded: false,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            return false
        }
    }

    @discardableResult
    private func persistIfNeeded() -> Bool {
        guard persistenceEnabled else {
            return true
        }
        if let libraryLoadFailureMessage {
            // Subscription refresh, selection and editor bindings can all
            // publish after bootstrap. None may overwrite a library that was
            // never successfully read, or notify cloud using fallback charts.
            persistenceStatus = .failed(message: libraryLoadFailureMessage)
            return false
        }
        guard let repository else {
            retryableSaveFailureMessage = nil
            persistenceStatus = .notTracking
            return true
        }

        let snapshotToPersist = snapshot
        let shouldNotifyCloudSync = cloudSyncNotificationsEnabled
        guard repository.savesSnapshotsOffMainThread else {
            return persistSnapshotSynchronously(
                snapshotToPersist,
                repository: repository,
                notifyCloudSync: shouldNotifyCloudSync
            )
        }

        persistenceGeneration += 1
        pendingAsyncPersistence = (
            snapshot: snapshotToPersist,
            notifyCloudSync: shouldNotifyCloudSync,
            generation: persistenceGeneration
        )
        scheduleAsyncPersistenceIfNeeded(repository: repository)
        return true
    }

    private func scheduleAsyncPersistenceIfNeeded(repository: ChartRepository) {
        guard !asyncPersistenceInFlight,
              let pendingPersistence = pendingAsyncPersistence else {
            return
        }

        pendingAsyncPersistence = nil
        asyncPersistenceInFlight = true
        asyncPersistenceQueue.async { [weak self, repository] in
            let saveStartedAt = ProcessInfo.processInfo.systemUptime
            let result: Result<Void, Error>
            do {
                try repository.saveSnapshot(pendingPersistence.snapshot)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            let saveDurationMilliseconds = (ProcessInfo.processInfo.systemUptime - saveStartedAt) * 1_000

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.asyncPersistenceInFlight = false
                switch result {
                case .success:
                    if pendingPersistence.generation == self.persistenceGeneration {
                        self.markSaveSucceeded()
                        if pendingPersistence.notifyCloudSync {
                            self.onSnapshotSaved?(pendingPersistence.snapshot)
                        }
                    }
                case let .failure(error):
                    if pendingPersistence.generation == self.persistenceGeneration {
                        self.markSaveFailed(error)
                    }
                }

                self.scheduleAsyncPersistenceIfNeeded(repository: repository)
            }
            if case .success = result {
                Self.recordPersistenceResult(.save, succeeded: true,
                                             durationMilliseconds: saveDurationMilliseconds)
            } else {
                Self.recordPersistenceResult(.save, succeeded: false,
                                             durationMilliseconds: saveDurationMilliseconds)
            }
        }
    }

    private func persistSnapshotSynchronously(
        _ snapshot: ChartLibrarySnapshot,
        repository: ChartRepository,
        notifyCloudSync: Bool
    ) -> Bool {
        let saveStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            try repository.saveSnapshot(snapshot)
            markSaveSucceeded()
            if notifyCloudSync {
                onSnapshotSaved?(snapshot)
            }
            Self.recordPersistenceResult(.save, succeeded: true,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - saveStartedAt) * 1_000)
            return true
        } catch {
            markSaveFailed(error)
            Self.recordPersistenceResult(.save, succeeded: false,
                durationMilliseconds: (ProcessInfo.processInfo.systemUptime - saveStartedAt) * 1_000)
            return false
        }
    }

    private enum PersistenceOperation: String {
        case load, save
    }

    static func recordBasicLoadOutcome(_ outcome: ChartLibraryLoadOutcome) {
        recordPersistenceResult(.load, succeeded: outcome.succeeded,
                                 durationMilliseconds: outcome.durationMilliseconds)
    }

    /// Only scalar outcomes and elapsed time cross this boundary. Never pass a
    /// snapshot, repository, chart identifier, error text, or ink to telemetry.
    private static func recordPersistenceResult(
        _ operation: PersistenceOperation,
        succeeded: Bool,
        durationMilliseconds: Double
    ) {
        IChartPerformanceTrace.record(
            "library.\(operation.rawValue)",
            durationMilliseconds: durationMilliseconds,
            result: succeeded ? .succeeded : .failed,
            errorCategory: succeeded ? nil : (operation == .load ? .storageRead : .storageWrite)
        )
        #if canImport(UIKit)
        if !succeeded {
            IChartTelemetry.record("app.error", properties: [
                "operation": .string("library_\(operation.rawValue)"),
                "result": .string("failed"),
                "error_code": .string("library_\(operation.rawValue)_failed"),
                "duration_ms": .double(durationMilliseconds)
            ])
        }
        #endif
    }

    private func markSaveSucceeded() {
        retryableSaveFailureMessage = nil
        persistenceStatus = .saved(at: .now)
    }

    private func markSaveFailed(_ error: Error) {
        let message = error.localizedDescription
        retryableSaveFailureMessage = message
        persistenceStatus = .failed(message: message)
    }

    @discardableResult
    private func performPersistedBatch(notifyCloudSync: Bool = true, _ mutation: () -> Void) -> Bool {
        let wasPersistenceEnabled = persistenceEnabled
        let wasCloudSyncNotificationsEnabled = cloudSyncNotificationsEnabled
        persistenceEnabled = false
        cloudSyncNotificationsEnabled = notifyCloudSync
        mutation()
        persistenceEnabled = wasPersistenceEnabled
        cloudSyncNotificationsEnabled = wasCloudSyncNotificationsEnabled && notifyCloudSync
        let didAcceptPersistence = persistIfNeeded()
        cloudSyncNotificationsEnabled = wasCloudSyncNotificationsEnabled
        return didAcceptPersistence
    }

    private func upsertTombstone(
        chartID: Chart.ID,
        deletedAt: Date,
        shouldSyncToCloud: Bool
    ) {
        deletionTombstones.removeAll { $0.chartID == chartID }
        deletionTombstones.append(
            ChartDeletionTombstone(
                chartID: chartID,
                deletedAt: deletedAt,
                shouldSyncToCloud: shouldSyncToCloud
            )
        )
        deletionTombstones = Self.normalizedTombstones(deletionTombstones)
    }

    @discardableResult
    private func addChartToProjectInPlace(
        chartID: Chart.ID,
        projectID: ChartProject.ID,
        atFront: Bool
    ) -> Bool {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return false
        }

        projects[projectIndex].addChart(chartID, atFront: atFront)
        return true
    }

    private func removeChartFromAllProjectsInPlace(_ chartID: Chart.ID) {
        for projectIndex in projects.indices {
            projects[projectIndex].removeChart(chartID)
        }
    }

    private static func sanitizedTitle(_ proposedTitle: String) -> String? {
        let sanitizedTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizedTitle.isEmpty ? nil : sanitizedTitle
    }

    private static func duplicateTitle(for title: String, existingTitles: Set<String>) -> String {
        let baseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateBase = baseTitle.isEmpty ? "Untitled Chart Copy" : "\(baseTitle) Copy"
        var candidate = candidateBase
        var suffix = 2

        while existingTitles.contains(candidate) {
            candidate = "\(candidateBase) \(suffix)"
            suffix += 1
        }

        return candidate
    }

    private static func sanitizedSelection(_ selectedChartID: Chart.ID?, charts: [Chart]) -> Chart.ID? {
        if let selectedChartID,
           charts.contains(where: { $0.id == selectedChartID }) {
            return selectedChartID
        }

        return charts.first?.id
    }

    private static func normalizedTombstones(
        _ tombstones: [ChartDeletionTombstone]
    ) -> [ChartDeletionTombstone] {
        Dictionary(grouping: tombstones, by: \.chartID)
            .compactMap { _, grouped in grouped.max { $0.deletedAt < $1.deletedAt } }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    private static func normalizedProjects(_ projects: [ChartProject], charts: [Chart]) -> [ChartProject] {
        let availableChartIDs = Set(charts.map(\.id))
        var seenProjectIDs = Set<ChartProject.ID>()

        return projects.compactMap { project in
            guard seenProjectIDs.insert(project.id).inserted else {
                return nil
            }

            var normalizedProject = project
            normalizedProject.chartIDs = ChartProject.uniqueChartIDs(project.chartIDs)
                .filter { availableChartIDs.contains($0) }
            return normalizedProject
        }
    }
}
