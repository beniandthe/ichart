import Combine
import Foundation

enum ChartLibraryPersistenceStatus: Equatable {
    case notTracking
    case ready
    case saved(at: Date)
    case failed(message: String)

    var displayText: String {
        switch self {
        case .notTracking:
            "Local preview"
        case .ready:
            "Autosave ready"
        case .saved(let date):
            "Saved locally \(date.formatted(date: .omitted, time: .shortened))"
        case .failed:
            "Save issue"
        }
    }

    var accessibilityText: String {
        switch self {
        case .notTracking:
            "Local preview state is not being saved."
        case .ready:
            "Autosave is ready."
        case .saved(let date):
            "Chart library saved locally at \(date.formatted(date: .omitted, time: .shortened))."
        case .failed(let message):
            "Chart library save issue. \(message)"
        }
    }

    var systemImageName: String {
        switch self {
        case .notTracking:
            "externaldrive"
        case .ready:
            "checkmark.circle"
        case .saved:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }
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
    @Published private(set) var persistenceStatus: ChartLibraryPersistenceStatus = .notTracking

    var onSnapshotSaved: ((ChartLibrarySnapshot) -> Void)?

    private let repository: ChartRepository?
    private let chordDiagnosticsResetter: (() -> Void)?
    private var persistenceEnabled = false
    private var cloudSyncNotificationsEnabled = true

    init(
        charts: [Chart],
        entitlements: AppEntitlements = .free,
        selectedChartID: Chart.ID? = nil,
        deletionTombstones: [ChartDeletionTombstone] = [],
        cloudMetadata: ChartCloudMetadata = ChartCloudMetadata(),
        repository: ChartRepository? = nil,
        chordDiagnosticsResetter: (() -> Void)? = nil
    ) {
        self.charts = charts
        self.entitlements = entitlements
        self.selectedChartID = Self.sanitizedSelection(selectedChartID, charts: charts)
        self.deletionTombstones = Self.normalizedTombstones(deletionTombstones)
        self.cloudMetadata = cloudMetadata
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
            repository: repository
        )
    }

    var canCreateChart: Bool {
        entitlements.canCreateChart(currentChartCount: charts.count)
    }

    var chartCapacityText: String {
        entitlements.chartCapacityText(currentChartCount: charts.count)
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

    var localChartOverflowCount: Int {
        guard let localChartLimit else {
            return 0
        }

        return max(0, charts.count - localChartLimit)
    }

    func canUse(_ feature: EntitledFeature) -> Bool {
        entitlements.includes(feature)
    }

    func setPlan(_ plan: SmartChartPlan) {
        var updatedEntitlements = entitlements
        updatedEntitlements.activePlan = plan
        entitlements = updatedEntitlements
    }

    @discardableResult
    func createBlankChart(
        in key: DocumentKey = .cMajor,
        layoutStyle: ChartLayoutStyle = .leadSheet
    ) -> Bool {
        guard canCreateChart else {
            return false
        }

        let newChart = Chart.draft(title: "Untitled Chart", key: key, layoutStyle: layoutStyle)
        charts.insert(newChart, at: 0)
        selectedChartID = newChart.id
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
    func duplicateChart(id chartID: Chart.ID) -> Chart.ID? {
        guard canCreateChart,
              let chartIndex = charts.firstIndex(where: { $0.id == chartID }) else {
            return nil
        }

        var duplicate = charts[chartIndex]
        let now = Date()
        duplicate.id = UUID()
        duplicate.title = Self.duplicateTitle(
            for: duplicate.title,
            existingTitles: Set(charts.map(\.title))
        )
        duplicate.createdAt = now
        duplicate.updatedAt = now

        performPersistedBatch {
            charts.insert(duplicate, at: min(chartIndex + 1, charts.endIndex))
            selectedChartID = duplicate.id
        }
        return duplicate.id
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
            cloudMetadata: cloudMetadata
        )
    }

    func applySyncedSnapshot(_ snapshot: ChartLibrarySnapshot) {
        performPersistedBatch(notifyCloudSync: false) {
            charts = snapshot.charts
            entitlements = snapshot.entitlements
            deletionTombstones = Self.normalizedTombstones(snapshot.deletionTombstones)
            cloudMetadata = snapshot.cloudMetadata
            selectedChartID = Self.sanitizedSelection(snapshot.selectedChartID, charts: snapshot.charts)
        }
    }

    func updateCloudMetadataFromSync(ownerID: UUID, lastSyncAt: Date, lastRemoteBackupAt: Date?) {
        var updatedMetadata = cloudMetadata
        updatedMetadata.ownerID = ownerID
        updatedMetadata.lastSyncAt = lastSyncAt
        if let lastRemoteBackupAt {
            updatedMetadata.lastRemoteBackupAt = lastRemoteBackupAt
        }

        performPersistedBatch(notifyCloudSync: false) {
            cloudMetadata = updatedMetadata
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

        do {
            try repository.saveSnapshot(snapshot)
            persistenceStatus = .saved(at: .now)
            if cloudSyncNotificationsEnabled {
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
}
