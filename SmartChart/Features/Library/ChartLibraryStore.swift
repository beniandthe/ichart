import Combine
import Foundation

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

    private let repository: ChartRepository?
    private let chordDiagnosticsResetter: (() -> Void)?
    private var persistenceEnabled = false

    init(
        charts: [Chart],
        entitlements: AppEntitlements = .free,
        selectedChartID: Chart.ID? = nil,
        repository: ChartRepository? = nil,
        chordDiagnosticsResetter: (() -> Void)? = nil
    ) {
        self.charts = charts
        self.entitlements = entitlements
        self.selectedChartID = Self.sanitizedSelection(selectedChartID, charts: charts)
        self.repository = repository
        self.chordDiagnosticsResetter = chordDiagnosticsResetter
        persistenceEnabled = true
    }

    convenience init(snapshot: ChartLibrarySnapshot, repository: ChartRepository? = nil) {
        self.init(
            charts: snapshot.charts,
            entitlements: snapshot.entitlements,
            selectedChartID: snapshot.selectedChartID,
            repository: repository
        )
    }

    var canCreateChart: Bool {
        entitlements.canCreateChart(currentChartCount: charts.count)
    }

    var chartCapacityText: String {
        entitlements.chartCapacityText(currentChartCount: charts.count)
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

        performPersistedBatch {
            charts = updatedCharts
            selectedChartID = Self.sanitizedSelection(proposedSelection, charts: updatedCharts)
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
            entitlements: entitlements
        )
    }

    static func live(repository: ChartRepository = FileChartRepository.live()) -> ChartLibraryStore {
        let snapshot = (try? repository.loadSnapshot()) ?? .preview
        return ChartLibraryStore(
            charts: snapshot.charts,
            entitlements: snapshot.entitlements,
            selectedChartID: snapshot.selectedChartID,
            repository: repository,
            chordDiagnosticsResetter: {
                try? ChordEntryDiagnosticsRecorder.live().reset()
            }
        )
    }

    static var preview: ChartLibraryStore {
        ChartLibraryStore(snapshot: .preview)
    }

    private func persistIfNeeded() {
        guard persistenceEnabled, let repository else {
            return
        }

        do {
            try repository.saveSnapshot(snapshot)
        } catch {
            print("SmartChart persistence error: \(error)")
        }
    }

    private func performPersistedBatch(_ mutation: () -> Void) {
        let wasPersistenceEnabled = persistenceEnabled
        persistenceEnabled = false
        mutation()
        persistenceEnabled = wasPersistenceEnabled
        persistIfNeeded()
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
}
