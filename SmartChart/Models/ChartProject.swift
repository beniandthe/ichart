import Foundation

struct ChartProject: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var chartIDs: [Chart.ID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        chartIDs: [Chart.ID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.chartIDs = Self.uniqueChartIDs(chartIDs)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var chartCountText: String {
        chartIDs.count == 1 ? "1 chart" : "\(chartIDs.count) charts"
    }

    mutating func addChart(_ chartID: Chart.ID, atFront: Bool = false) {
        chartIDs.removeAll { $0 == chartID }
        if atFront {
            chartIDs.insert(chartID, at: 0)
        } else {
            chartIDs.append(chartID)
        }
        updatedAt = Date()
    }

    mutating func removeChart(_ chartID: Chart.ID) {
        let originalCount = chartIDs.count
        chartIDs.removeAll { $0 == chartID }
        if chartIDs.count != originalCount {
            updatedAt = Date()
        }
    }

    static func sanitizedTitle(_ proposedTitle: String) -> String? {
        let sanitized = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    static func uniqueChartIDs(_ chartIDs: [Chart.ID]) -> [Chart.ID] {
        var seen = Set<Chart.ID>()
        return chartIDs.filter { seen.insert($0).inserted }
    }
}
