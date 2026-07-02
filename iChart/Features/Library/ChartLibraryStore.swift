import Combine
import Foundation

enum ChartLibraryPersistenceStatus: Equatable {
    case notTracking
    case ready
    case saved(at: Date)
    case failed(message: String)
}

final class ChartLibraryStore: ObservableObject {
    @Published var charts: [Chart] {
        didSet { persistIfNeeded() }
    }
    @Published var selectedChartID: Chart.ID? {
        didSet { persistIfNeeded() }
    }
    @Published var entitlements: AppEntitlements {
        didSet { persistIfNeeded() }
    }
    @Published var deletionTombstones: [ChartDeletionTombstone] {
        didSet { persistIfNeeded() }
    }
    @Published var cloudMetadata: ChartCloudMetadata {
        didSet { persistIfNeeded() }
    }
    @Published var projects: [ChartProject] {
        didSet { persistIfNeeded() }
    }
    @Published private(set) var persistenceStatus: ChartLibraryPersistenceStatus = .notTracking

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
        chordDiagnosticsResetter: (() -> Void)? = nil
    ) {
        self.charts = charts
        self.entitlements = entitlements
        self.selectedChartID = Self.sanitizedSelection(selectedChartID, charts: charts)
        self.deletionTombstones = Self.normalizedTombstones(deletionTombstones)
        self.cloudMetadata = cloudMetadata
        self.projects = Self.normalizedProjects(projects, charts: charts)
        self.repository = repository
        self.chordDiagnosticsResetter = chordDiagnosticsResetter
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

    func setPlan(_ plan: IChartPlan) {
        var updatedEntitlements = entitlements
        updatedEntitlements.applyLegacyPlan(plan)
        guard updatedEntitlements != entitlements else {
            return
        }
        entitlements = updatedEntitlements
    }

    func applySubscriptionState(_ subscription: IChartSubscriptionEntitlement) {
        guard !entitlements.subscription.hasSameLibraryAccess(as: subscription) else {
            return
        }

        var updatedEntitlements = entitlements
        updatedEntitlements.applySubscription(subscription)
        entitlements = updatedEntitlements
    }

    @discardableResult
    func createBlankChart(
        in key: DocumentKey = .cMajor,
        layoutStyle: ChartLayoutStyle = .leadSheet,
        projectID: ChartProject.ID? = nil
    ) -> Bool {
        guard canCreateChart else {
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
        guard canCreateChart,
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
        guard let chartIndex = charts.firstIndex(where: { $0.id == chartID }) else {
            return false
        }

        var updatedCharts = charts
        updatedCharts.remove(at: chartIndex)
        let fallbackSelection = chartIndex < updatedCharts.count
            ? updatedCharts[chartIndex].id
            : updatedCharts.last?.id
        let proposedSelection = selectedChartID == chartID ? fallbackSelection : selectedChartID

        let deletedAt = Date()
        performPersistedBatch {
            charts = updatedCharts
            removeChartFromAllProjectsInPlace(chartID)
            upsertTombstone(chartID: chartID, deletedAt: deletedAt)
            selectedChartID = Self.sanitizedSelection(proposedSelection, charts: updatedCharts)
        }
        return true
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

    #if DEBUG || targetEnvironment(simulator)
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
        performPersistedBatch(notifyCloudSync: false) {
            charts = snapshot.charts
            entitlements = snapshot.entitlements
            deletionTombstones = Self.normalizedTombstones(snapshot.deletionTombstones)
            cloudMetadata = snapshot.cloudMetadata
            projects = Self.normalizedProjects(snapshot.projects, charts: snapshot.charts)
            selectedChartID = Self.sanitizedSelection(snapshot.selectedChartID, charts: snapshot.charts)
        }
    }

    func updateCloudMetadataFromSync(ownerID: UUID, lastSyncAt: Date, lastRemoteBackupAt: Date?) {
        applyCloudPushResult(
            ownerID: ownerID,
            lastSyncAt: lastSyncAt,
            lastRemoteBackupAt: lastRemoteBackupAt,
            syncedDeletionTombstones: []
        )
    }

    func applyCloudPushResult(
        ownerID: UUID,
        lastSyncAt: Date,
        lastRemoteBackupAt: Date?,
        syncedDeletionTombstones: [ChartDeletionTombstone]
    ) {
        var updatedMetadata = cloudMetadata
        updatedMetadata.ownerID = ownerID
        updatedMetadata.lastSyncAt = lastSyncAt
        if let lastRemoteBackupAt {
            updatedMetadata.lastRemoteBackupAt = lastRemoteBackupAt
        }
        let syncedTombstonesByChartID = Dictionary(
            grouping: syncedDeletionTombstones,
            by: \.chartID
        ).compactMapValues { tombstones in
            tombstones.max { $0.deletedAt < $1.deletedAt }
        }

        performPersistedBatch(notifyCloudSync: false) {
            cloudMetadata = updatedMetadata
            if !syncedTombstonesByChartID.isEmpty {
                deletionTombstones = Self.normalizedTombstones(
                    deletionTombstones.filter { tombstone in
                        guard let syncedTombstone = syncedTombstonesByChartID[tombstone.chartID] else {
                            return true
                        }

                        return tombstone.deletedAt > syncedTombstone.deletedAt
                    }
                )
            }
        }
    }

    static func live(repository: ChartRepository = FileChartRepository.live()) -> ChartLibraryStore {
        let loadedSnapshot: ChartLibrarySnapshot?
        let loadError: Error?
        do {
            loadedSnapshot = try repository.loadSnapshot()
            loadError = nil
        } catch {
            loadedSnapshot = nil
            loadError = error
        }

        let snapshot = loadedSnapshot ?? (loadError == nil ? .empty : .preview)
        let store = ChartLibraryStore(
            charts: snapshot.charts,
            entitlements: snapshot.entitlements,
            selectedChartID: snapshot.selectedChartID,
            deletionTombstones: snapshot.deletionTombstones,
            cloudMetadata: snapshot.cloudMetadata,
            projects: snapshot.projects,
            repository: repository,
            chordDiagnosticsResetter: {
                try? ChordEntryDiagnosticsRecorder.live().reset()
            }
        )
        if let loadError {
            store.persistenceStatus = .failed(message: loadError.localizedDescription)
        } else if loadedSnapshot != nil {
            store.persistenceStatus = .saved(at: .now)
        }
        return store
    }

    static var preview: ChartLibraryStore {
        ChartLibraryStore(snapshot: .preview)
    }

    private func persistIfNeeded() {
        guard persistenceEnabled else {
            return
        }
        guard let repository else {
            persistenceStatus = .notTracking
            return
        }

        let snapshotToPersist = snapshot
        let shouldNotifyCloudSync = cloudSyncNotificationsEnabled
        guard repository.savesSnapshotsOffMainThread else {
            persistSnapshotSynchronously(
                snapshotToPersist,
                repository: repository,
                notifyCloudSync: shouldNotifyCloudSync
            )
            return
        }

        persistenceGeneration += 1
        pendingAsyncPersistence = (
            snapshot: snapshotToPersist,
            notifyCloudSync: shouldNotifyCloudSync,
            generation: persistenceGeneration
        )
        scheduleAsyncPersistenceIfNeeded(repository: repository)
    }

    private func scheduleAsyncPersistenceIfNeeded(repository: ChartRepository) {
        guard !asyncPersistenceInFlight,
              let pendingPersistence = pendingAsyncPersistence else {
            return
        }

        pendingAsyncPersistence = nil
        asyncPersistenceInFlight = true
        asyncPersistenceQueue.async { [weak self, repository] in
            let result: Result<Void, Error>
            do {
                try repository.saveSnapshot(pendingPersistence.snapshot)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.asyncPersistenceInFlight = false
                switch result {
                case .success:
                    if pendingPersistence.generation == self.persistenceGeneration {
                        self.persistenceStatus = .saved(at: .now)
                        if pendingPersistence.notifyCloudSync {
                            self.onSnapshotSaved?(pendingPersistence.snapshot)
                        }
                    }
                case let .failure(error):
                    if pendingPersistence.generation == self.persistenceGeneration {
                        self.persistenceStatus = .failed(message: error.localizedDescription)
                    }
                }

                self.scheduleAsyncPersistenceIfNeeded(repository: repository)
            }
        }
    }

    private func persistSnapshotSynchronously(
        _ snapshot: ChartLibrarySnapshot,
        repository: ChartRepository,
        notifyCloudSync: Bool
    ) {
        do {
            try repository.saveSnapshot(snapshot)
            persistenceStatus = .saved(at: .now)
            if notifyCloudSync {
                onSnapshotSaved?(snapshot)
            }
        } catch {
            persistenceStatus = .failed(message: error.localizedDescription)
        }
    }

    private func performPersistedBatch(notifyCloudSync: Bool = true, _ mutation: () -> Void) {
        let wasPersistenceEnabled = persistenceEnabled
        let wasCloudSyncNotificationsEnabled = cloudSyncNotificationsEnabled
        persistenceEnabled = false
        cloudSyncNotificationsEnabled = notifyCloudSync
        mutation()
        persistenceEnabled = wasPersistenceEnabled
        cloudSyncNotificationsEnabled = wasCloudSyncNotificationsEnabled && notifyCloudSync
        persistIfNeeded()
        cloudSyncNotificationsEnabled = wasCloudSyncNotificationsEnabled
    }

    private func upsertTombstone(chartID: Chart.ID, deletedAt: Date) {
        deletionTombstones.removeAll { $0.chartID == chartID }
        deletionTombstones.append(ChartDeletionTombstone(chartID: chartID, deletedAt: deletedAt))
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

private extension IChartSubscriptionEntitlement {
    func hasSameLibraryAccess(as other: IChartSubscriptionEntitlement) -> Bool {
        status == other.status && graceEndsAt == other.graceEndsAt
    }
}
