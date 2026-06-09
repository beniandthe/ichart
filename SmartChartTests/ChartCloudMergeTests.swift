import XCTest
@testable import SmartChart

final class ChartCloudMergeTests: XCTestCase {
    func testMergePrefersNewestRemoteChartUpdate() {
        let baseDate = Date(timeIntervalSinceReferenceDate: 1_000)
        var localChart = Chart.blank(title: "Local", measureCount: 4)
        localChart.id = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        localChart.updatedAt = baseDate
        var remoteChart = localChart
        remoteChart.title = "Remote"
        remoteChart.updatedAt = baseDate.addingTimeInterval(60)
        let local = ChartLibrarySnapshot(
            charts: [localChart],
            selectedChartID: localChart.id,
            entitlements: .free
        )
        let remote = ChartCloudRemoteLibrary(
            charts: [remoteChart],
            deletionTombstones: [],
            lastRemoteBackupAt: baseDate.addingTimeInterval(70)
        )

        let merged = ChartCloudMerge.mergedSnapshot(local: local, remote: remote, now: baseDate.addingTimeInterval(80))

        XCTAssertEqual(merged.charts.first?.title, "Remote")
        XCTAssertEqual(merged.selectedChartID, localChart.id)
        XCTAssertEqual(merged.cloudMetadata.lastRemoteBackupAt, baseDate.addingTimeInterval(70))
    }

    func testMergeKeepsLocalChartWhenTimestampsTie() {
        let date = Date(timeIntervalSinceReferenceDate: 2_000)
        var localChart = Chart.blank(title: "Local Tie", measureCount: 4)
        localChart.id = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        localChart.updatedAt = date
        var remoteChart = localChart
        remoteChart.title = "Remote Tie"
        remoteChart.updatedAt = date
        let local = ChartLibrarySnapshot(
            charts: [localChart],
            selectedChartID: localChart.id,
            entitlements: .free
        )
        let remote = ChartCloudRemoteLibrary(
            charts: [remoteChart],
            deletionTombstones: [],
            lastRemoteBackupAt: nil
        )

        let merged = ChartCloudMerge.mergedSnapshot(local: local, remote: remote, now: date)

        XCTAssertEqual(merged.charts.first?.title, "Local Tie")
    }

    func testNewerLocalTombstonePreventsRemoteResurrection() {
        let baseDate = Date(timeIntervalSinceReferenceDate: 3_000)
        var remoteChart = Chart.blank(title: "Remote Old", measureCount: 4)
        remoteChart.id = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        remoteChart.updatedAt = baseDate
        let tombstone = ChartDeletionTombstone(
            chartID: remoteChart.id,
            deletedAt: baseDate.addingTimeInterval(120)
        )
        let local = ChartLibrarySnapshot(
            charts: [],
            selectedChartID: nil,
            entitlements: .free,
            deletionTombstones: [tombstone]
        )
        let remote = ChartCloudRemoteLibrary(
            charts: [remoteChart],
            deletionTombstones: [],
            lastRemoteBackupAt: nil
        )

        let merged = ChartCloudMerge.mergedSnapshot(local: local, remote: remote, now: baseDate)

        XCTAssertTrue(merged.charts.isEmpty)
        XCTAssertEqual(merged.deletionTombstones.first?.chartID, remoteChart.id)
    }

    func testNewerRemoteTombstoneDeletesOlderLocalChart() {
        let baseDate = Date(timeIntervalSinceReferenceDate: 4_000)
        var localChart = Chart.blank(title: "Local Old", measureCount: 4)
        localChart.id = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        localChart.updatedAt = baseDate
        let tombstone = ChartDeletionTombstone(
            chartID: localChart.id,
            deletedAt: baseDate.addingTimeInterval(90)
        )
        let local = ChartLibrarySnapshot(
            charts: [localChart],
            selectedChartID: localChart.id,
            entitlements: .free
        )
        let remote = ChartCloudRemoteLibrary(
            charts: [],
            deletionTombstones: [tombstone],
            lastRemoteBackupAt: nil
        )

        let merged = ChartCloudMerge.mergedSnapshot(local: local, remote: remote, now: baseDate)

        XCTAssertTrue(merged.charts.isEmpty)
        XCTAssertNil(merged.selectedChartID)
    }
}
