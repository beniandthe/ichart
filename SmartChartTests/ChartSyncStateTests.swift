import XCTest
@testable import SmartChart

final class ChartSyncStateTests: XCTestCase {
    func testRequiresProStateExplainsCloudBackupGateAndDisablesManualSync() {
        let state = ChartSyncState.requiresPro

        XCTAssertEqual(state.displayText, "Cloud backup requires Pro")
        XCTAssertEqual(
            state.detailText,
            "Upgrade to Pro to back up and restore from cloud."
        )
        XCTAssertEqual(state.systemImageName, "lock.icloud")
        XCTAssertEqual(state.manualSyncTitle, "Requires Pro")
        XCTAssertFalse(state.allowsManualSync)
        XCTAssertEqual(state.manualSyncDisabledReason, "Cloud backup and restore require Pro.")
    }

    func testManualSyncOnlyRunsForActionableCloudStates() {
        XCTAssertFalse(ChartSyncState.unconfigured.allowsManualSync)
        XCTAssertFalse(ChartSyncState.signedOut.allowsManualSync)
        XCTAssertFalse(ChartSyncState.requiresPro.allowsManualSync)
        XCTAssertFalse(ChartSyncState.syncing.allowsManualSync)

        XCTAssertTrue(ChartSyncState.offline.allowsManualSync)
        XCTAssertTrue(ChartSyncState.synced(Date(timeIntervalSinceReferenceDate: 1)).allowsManualSync)
        XCTAssertTrue(ChartSyncState.failed("Retry later.").allowsManualSync)
    }

    func testDisabledReasonsStaySpecificForNonActionableStates() {
        XCTAssertEqual(
            ChartSyncState.unconfigured.manualSyncDisabledReason,
            "Cloud backup is unavailable right now."
        )
        XCTAssertEqual(
            ChartSyncState.signedOut.manualSyncDisabledReason,
            "Sign in to enable cloud backup."
        )
        XCTAssertEqual(
            ChartSyncState.requiresPro.manualSyncDisabledReason,
            "Cloud backup and restore require Pro."
        )
        XCTAssertNil(ChartSyncState.syncing.manualSyncDisabledReason)
        XCTAssertNil(ChartSyncState.offline.manualSyncDisabledReason)
        XCTAssertNil(ChartSyncState.synced(Date(timeIntervalSinceReferenceDate: 1)).manualSyncDisabledReason)
        XCTAssertNil(ChartSyncState.failed("Retry later.").manualSyncDisabledReason)
    }
}
