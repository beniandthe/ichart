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

    func testMergePreservesLocalProjects() {
        let date = Date(timeIntervalSinceReferenceDate: 2_500)
        var chart = Chart.blank(title: "Project Chart", measureCount: 4)
        chart.id = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
        chart.updatedAt = date
        let project = ChartProject(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000212")!,
            title: "Show Folder",
            chartIDs: [chart.id],
            createdAt: date,
            updatedAt: date
        )
        let local = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: .free,
            projects: [project]
        )
        let remote = ChartCloudRemoteLibrary(
            charts: [chart],
            deletionTombstones: [],
            lastRemoteBackupAt: date.addingTimeInterval(30)
        )

        let merged = ChartCloudMerge.mergedSnapshot(local: local, remote: remote, now: date.addingTimeInterval(60))

        XCTAssertEqual(merged.projects, [project])
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

    func testMergeStampsOwnerMetadataWhenProvided() {
        let date = Date(timeIntervalSinceReferenceDate: 5_000)
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let local = ChartLibrarySnapshot(
            charts: [],
            selectedChartID: nil,
            entitlements: .free
        )
        let remote = ChartCloudRemoteLibrary(
            charts: [],
            deletionTombstones: [],
            lastRemoteBackupAt: date.addingTimeInterval(30)
        )

        let merged = ChartCloudMerge.mergedSnapshot(local: local, remote: remote, ownerID: ownerID, now: date)

        XCTAssertEqual(merged.cloudMetadata.ownerID, ownerID)
        XCTAssertEqual(merged.cloudMetadata.lastSyncAt, date)
        XCTAssertEqual(merged.cloudMetadata.lastRemoteBackupAt, date.addingTimeInterval(30))
    }

    func testOwnerlessLocalSnapshotIsPreservedForFirstSync() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let chart = Chart.blank(title: "First Backup")
        let snapshot = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: .free
        )

        let scoped = ChartCloudMerge.localSnapshotForSync(snapshot, ownerID: ownerID)

        XCTAssertEqual(scoped.charts.map(\.id), [chart.id])
        XCTAssertEqual(scoped.selectedChartID, chart.id)
        XCTAssertNil(scoped.cloudMetadata.ownerID)
    }

    func testLocalSnapshotForDifferentOwnerClearsChartsAndTombstones() {
        let previousOwnerID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        let nextOwnerID = UUID(uuidString: "00000000-0000-0000-0000-000000000204")!
        let chart = Chart.blank(title: "Previous Owner")
        let tombstone = ChartDeletionTombstone(chartID: UUID(), deletedAt: Date(timeIntervalSinceReferenceDate: 6_000))
        let snapshot = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: AppEntitlements(activePlan: .proLifetime),
            deletionTombstones: [tombstone],
            cloudMetadata: ChartCloudMetadata(ownerID: previousOwnerID, lastSyncAt: Date(), lastRemoteBackupAt: Date())
        )

        let scoped = ChartCloudMerge.localSnapshotForSync(snapshot, ownerID: nextOwnerID)

        XCTAssertTrue(scoped.charts.isEmpty)
        XCTAssertNil(scoped.selectedChartID)
        XCTAssertEqual(scoped.entitlements, AppEntitlements(activePlan: .proLifetime))
        XCTAssertTrue(scoped.deletionTombstones.isEmpty)
        XCTAssertEqual(scoped.cloudMetadata.ownerID, nextOwnerID)
        XCTAssertNil(scoped.cloudMetadata.lastSyncAt)
        XCTAssertNil(scoped.cloudMetadata.lastRemoteBackupAt)
    }

    func testEmptySnapshotForOwnerPreservesEntitlementsOnly() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000205")!
        let chart = Chart.blank(title: "Legacy Cloud")
        let snapshot = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: AppEntitlements(activePlan: .studioSubscription),
            deletionTombstones: [
                ChartDeletionTombstone(chartID: UUID(), deletedAt: Date(timeIntervalSinceReferenceDate: 7_000))
            ],
            cloudMetadata: ChartCloudMetadata(lastSyncAt: Date(), lastRemoteBackupAt: Date())
        )

        let empty = ChartCloudMerge.emptySnapshotForOwner(basedOn: snapshot, ownerID: ownerID)

        XCTAssertTrue(empty.charts.isEmpty)
        XCTAssertNil(empty.selectedChartID)
        XCTAssertEqual(empty.entitlements, AppEntitlements(activePlan: .studioSubscription))
        XCTAssertTrue(empty.deletionTombstones.isEmpty)
        XCTAssertEqual(empty.cloudMetadata.ownerID, ownerID)
    }
}
