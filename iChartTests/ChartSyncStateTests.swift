import XCTest
@testable import iChart

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
            "Sign in to enable cloud backup and restore."
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

    func testCloudRestoreOnlyRunsAfterKnownCloudState() {
        XCTAssertFalse(ChartSyncState.unconfigured.allowsCloudRestore)
        XCTAssertFalse(ChartSyncState.signedOut.allowsCloudRestore)
        XCTAssertFalse(ChartSyncState.requiresPro.allowsCloudRestore)
        XCTAssertFalse(ChartSyncState.offline.allowsCloudRestore)
        XCTAssertFalse(ChartSyncState.syncing.allowsCloudRestore)

        XCTAssertTrue(ChartSyncState.synced(Date(timeIntervalSinceReferenceDate: 1)).allowsCloudRestore)
        XCTAssertTrue(ChartSyncState.failed("Retry later.").allowsCloudRestore)
    }

    func testCloudRestoreDisabledReasonsStaySpecificForBlockedStates() {
        XCTAssertEqual(
            ChartSyncState.unconfigured.cloudRestoreDisabledReason,
            "Cloud restore is unavailable right now."
        )
        XCTAssertEqual(
            ChartSyncState.signedOut.cloudRestoreDisabledReason,
            "Sign in to restore charts from cloud."
        )
        XCTAssertEqual(
            ChartSyncState.requiresPro.cloudRestoreDisabledReason,
            "Cloud backup and restore require Pro."
        )
        XCTAssertEqual(
            ChartSyncState.offline.cloudRestoreDisabledReason,
            "Reconnect to restore charts from cloud."
        )
        XCTAssertNil(ChartSyncState.syncing.cloudRestoreDisabledReason)
        XCTAssertNil(ChartSyncState.synced(Date(timeIntervalSinceReferenceDate: 1)).cloudRestoreDisabledReason)
        XCTAssertNil(ChartSyncState.failed("Retry later.").cloudRestoreDisabledReason)
    }
}
