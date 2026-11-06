#if canImport(UIKit)
import Combine
import Foundation
import Supabase
import XCTest
@testable import iChart

@MainActor
final class ChartCloudSyncStoreFeedbackTests: XCTestCase {
    // Allow hosted simulator scheduling delays while retaining all feedback,
    // receipt, chart, and backup-count assertions below.
    private let operationCompletionTimeout: TimeInterval = 30

    func testZeroCloudRestoreReceiptSurvivesFollowingAutomaticBackup() async throws {
        let (store, library, service) = await configuredStore(chartCount: 4)
        let restored = expectation(description: "Zero cloud restore completed")
        let restoreObserver = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in restored.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [restored], timeout: operationCompletionTimeout)
        restoreObserver.cancel()
        let receipt = try XCTUnwrap(store.lastRestoreResult)
        XCTAssertEqual(receipt.remoteChartCount, 0)
        XCTAssertEqual(receipt.libraryChartCount, 4)
        XCTAssertEqual(receipt.didApplySnapshot, true)
        XCTAssertNil(store.progress)

        let backedUp = expectation(description: "Following automatic backup completed")
        let backupObserver = store.$lastOperationResult.compactMap { $0 }.filter { $0.operation == .backup }.first().sink { _ in backedUp.fulfill() }
        library.onSnapshotSaved?(library.snapshot)
        await fulfillment(of: [backedUp], timeout: operationCompletionTimeout)
        backupObserver.cancel()
        XCTAssertEqual(store.lastRestoreResult, receipt)
        XCTAssertEqual(store.lastOperationResult?.operation, .backup)
        let pushCount = await service.pushCount
        XCTAssertEqual(pushCount, 2)
    }

    func testRestoreProgressAndNewRestoreClearPreviousReceipt() async {
        let (store, library, service) = await configuredStore()
        let completed = expectation(description: "First restore completed")
        let first = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        first.cancel()
        await service.holdNextRestore()
        let downloading = expectation(description: "New restore downloading")
        let progress = store.$progress.compactMap { $0 }.filter { $0.operation == .restore && $0.stage == .readingSnapshots }.first().sink { _ in downloading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [downloading], timeout: operationCompletionTimeout)
        progress.cancel()
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertEqual(store.progress?.displayTitle, "Restoring charts")
        XCTAssertEqual(store.progress?.detailText, "Downloading charts…")
        let finished = expectation(description: "Second restore completed")
        let second = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in finished.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [finished], timeout: operationCompletionTimeout)
        second.cancel()
        XCTAssertNil(store.progress)
        XCTAssertEqual(library.charts.count, 1)
    }

    func testLocalEditDuringRestoreIsPreservedAndReceiptDoesNotClaimApply() async throws {
        let (store, library, service) = await configuredStore()
        await service.holdNextRestore(extraCharts: [Chart.blank(title: "Remote fixture")])
        let downloading = expectation(description: "Restore began")
        let progress = store.$progress.compactMap { $0 }.filter { $0.stage == .readingSnapshots }.first().sink { _ in downloading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [downloading], timeout: operationCompletionTimeout)
        progress.cancel()
        library.charts[0].title = "Local change during restore"
        let completed = expectation(description: "Restore conditional apply finished")
        let receiptObserver = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        receiptObserver.cancel()
        let receipt = try XCTUnwrap(store.lastRestoreResult)
        XCTAssertEqual(receipt.remoteChartCount, 1)
        XCTAssertEqual(receipt.libraryChartCount, 1)
        XCTAssertEqual(receipt.didApplySnapshot, false)
        XCTAssertEqual(receipt.displayTitle, "Restore not applied")
        XCTAssertEqual(library.charts.map(\.title), ["Local change during restore"])
        store.authStateChanged(.signedOut) // Cancel the existing queued retry.
    }

    func testAccountResetRejectsLateRestoreDataAndFeedbackFromNoncooperativeService() async {
        let (store, library, service) = await configuredStore()
        let original = library.snapshot
        await service.holdNextRestore(extraCharts: [Chart.blank(title: "Old-account remote chart")])
        let downloading = expectation(description: "Restore began")
        let progress = store.$progress.compactMap { $0 }.filter { $0.stage == .readingSnapshots }.first().sink { _ in downloading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [downloading], timeout: operationCompletionTimeout)
        progress.cancel()
        store.authStateChanged(.signedOut)
        XCTAssertNil(store.progress)
        XCTAssertNil(store.lastRestoreResult)
        let noLatePublication = expectation(description: "Cancelled restore cannot publish a late busy state")
        noLatePublication.isInverted = true
        let working = store.$isWorking.dropFirst().sink { _ in noLatePublication.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [noLatePublication], timeout: 0.2)
        working.cancel()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.progress)
        XCTAssertNil(store.lastOperationResult)
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertNil(store.lastFailure)
        XCTAssertEqual(library.snapshot, original)
    }

    func testAccountResetRejectsLateRestoreFailureStatus() async {
        let (store, library, service) = await configuredStore()
        await service.holdNextRestore()
        await service.setRestoreError(ChartCloudSyncStageError(stage: .readingSnapshots, underlyingError: URLError(.cancelled)))
        let downloading = expectation(description: "Restore began before sign-out")
        let progress = store.$progress.compactMap { $0 }.filter { $0.stage == .readingSnapshots }.first().sink { _ in downloading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [downloading], timeout: operationCompletionTimeout)
        progress.cancel()
        store.authStateChanged(.signedOut)
        let noLatePublication = expectation(description: "Cancelled restore failure cannot publish a late busy state")
        noLatePublication.isInverted = true
        let working = store.$isWorking.dropFirst().sink { _ in noLatePublication.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [noLatePublication], timeout: 0.2)
        working.cancel()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.progress)
        XCTAssertNil(store.lastOperationResult)
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertNil(store.lastFailure)
        XCTAssertEqual(library.charts.count, 1)
    }

    func testAccountChangeRejectsOldRestoreWithoutClearingNewAccountsActiveBackup() async {
        let (store, library, service) = await configuredStore()
        await service.holdNextRestore(extraCharts: [Chart.blank(title: "Remote chart from previous account")])
        let reading = expectation(description: "Old account restore held")
        let reader = store.$progress.compactMap { $0 }.filter { $0.operation == .restore && $0.stage == .readingSnapshots }.first().sink { _ in reading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [reading], timeout: operationCompletionTimeout)
        reader.cancel()

        let newAccount = account(id: UUID(uuidString: "00000000-0000-0000-0000-000000000778")!)
        await service.setOwnerID(newAccount.id)
        let heldPush = await service.holdNextPush()
        let writing = expectation(description: "New account backup held")
        let writer = store.$progress.compactMap { $0 }.filter { $0.operation == .backup && $0.stage == .writingDocument }.first().sink { _ in writing.fulfill() }
        store.authStateChanged(.signedIn(newAccount))
        await fulfillment(of: [writing], timeout: operationCompletionTimeout)
        writer.cancel()
        let whileNewBackupIsActive = library.snapshot
        let noOldData = expectation(description: "Old restore must not apply charts or clear the current busy state")
        noOldData.isInverted = true
        let oldCharts = library.$charts.dropFirst().sink { _ in noOldData.fulfill() }
        let oldBusy = store.$isWorking.dropFirst().filter { !$0 }.sink { _ in noOldData.fulfill() }

        await service.releaseRestore()
        await fulfillment(of: [noOldData], timeout: 0.2)
        oldCharts.cancel(); oldBusy.cancel()
        XCTAssertEqual(library.snapshot, whileNewBackupIsActive)
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.progress?.operation, .backup)
        XCTAssertNil(store.lastRestoreResult)

        let completed = expectation(description: "Current account backup completes")
        let receipt = store.$lastOperationResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        await service.releasePush(heldPush)
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        receipt.cancel()
        XCTAssertEqual(library.cloudMetadata.ownerID, newAccount.id)
        XCTAssertEqual(library.charts.count, 1)
    }

    func testSignOutRejectsLatePushOwnershipMetadataAndFeedback() async {
        let (store, library, service) = await configuredStore()
        let heldPush = await service.holdNextPush()
        let writing = expectation(description: "Push held before sign-out")
        let writer = store.$progress.compactMap { $0 }.filter { $0.operation == .backup && $0.stage == .writingDocument }.first().sink { _ in writing.fulfill() }
        store.backUpNow()
        await fulfillment(of: [writing], timeout: operationCompletionTimeout)
        writer.cancel()
        let original = library.snapshot
        let previousBackupDate = store.lastRemoteBackupAt
        store.authStateChanged(.signedOut)
        let noLateMutation = expectation(description: "Old push cannot publish after sign-out")
        noLateMutation.isInverted = true
        let changes = library.$cloudMetadata.dropFirst().sink { _ in noLateMutation.fulfill() }
        let busy = store.$isWorking.dropFirst().sink { _ in noLateMutation.fulfill() }

        await service.releasePush(heldPush)
        await fulfillment(of: [noLateMutation], timeout: 0.2)
        changes.cancel(); busy.cancel()

        XCTAssertEqual(library.snapshot, original)
        XCTAssertEqual(store.lastRemoteBackupAt, previousBackupDate)
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.lastOperationResult)
        XCTAssertNil(store.lastFailure)
        XCTAssertFalse(store.isWorking)
    }

    func testAccountChangeRejectsOldPushWithoutClobberingNewBackupBusyState() async {
        let (store, library, service) = await configuredStore()
        let oldPush = await service.holdNextPush()
        let oldWriting = expectation(description: "Old account push held")
        let oldWriter = store.$progress.compactMap { $0 }.filter { $0.stage == .writingDocument }.first().sink { _ in oldWriting.fulfill() }
        store.backUpNow()
        await fulfillment(of: [oldWriting], timeout: operationCompletionTimeout)
        oldWriter.cancel()

        let newAccount = account(id: UUID(uuidString: "00000000-0000-0000-0000-000000000779")!)
        await service.setOwnerID(newAccount.id)
        let newPush = await service.holdNextPush()
        let newWriting = expectation(description: "New account push held")
        let newWriter = store.$progress.compactMap { $0 }.filter { $0.stage == .writingDocument }.first().sink { _ in newWriting.fulfill() }
        store.authStateChanged(.signedIn(newAccount))
        await fulfillment(of: [newWriting], timeout: operationCompletionTimeout)
        newWriter.cancel()
        let original = library.snapshot
        let noOldMutation = expectation(description: "Old push cannot mutate a new operation")
        noOldMutation.isInverted = true
        let changes = library.$cloudMetadata.dropFirst().sink { _ in noOldMutation.fulfill() }
        let busy = store.$isWorking.dropFirst().filter { !$0 }.sink { _ in noOldMutation.fulfill() }

        await service.releasePush(oldPush)
        await fulfillment(of: [noOldMutation], timeout: 0.2)
        changes.cancel(); busy.cancel()
        XCTAssertEqual(library.snapshot, original)
        XCTAssertTrue(store.isWorking)
        XCTAssertEqual(store.progress?.operation, .backup)
        XCTAssertNil(store.lastOperationResult)

        let completed = expectation(description: "New account backup commits its own result")
        let receipt = store.$lastOperationResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        await service.releasePush(newPush)
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        receipt.cancel()
        XCTAssertEqual(library.cloudMetadata.ownerID, newAccount.id)
        XCTAssertFalse(store.isWorking)
    }

    func testPushResultForUnexpectedOwnerCannotChangeLocalOwnership() async {
        let (store, library, service) = await configuredStore()
        let original = library.snapshot
        await service.setOwnerID(UUID())
        let failed = expectation(description: "Mismatched owner rejected")
        let failure = store.$lastFailure.compactMap { $0 }.first().sink { _ in failed.fulfill() }
        store.backUpNow()
        await fulfillment(of: [failed], timeout: operationCompletionTimeout)
        failure.cancel()
        XCTAssertEqual(library.snapshot, original)
        XCTAssertEqual(store.lastFailure?.category, .sessionRequired)
        XCTAssertNil(store.lastOperationResult)
        XCTAssertFalse(store.isWorking)
    }

    func testUnreadLibraryBlocksCloudBackupRestoreAndFallbackUploads() async {
        let library = ChartLibraryStore.live(repository: UnreadableLibraryRepository())
        let original = library.snapshot
        let service = FeedbackCloudService(ownerID: account().id)
        let store = ChartCloudSyncStore(service: service)
        store.attach(libraryStore: library)
        store.authStateChanged(.signedIn(account()))
        store.restoreChartsFromCloud()
        let rejected = expectation(description: "Fallback auto-upload rejected before reaching service")
        let observer = store.$lastFailure.dropFirst().compactMap { $0 }
            .filter { $0.operation == .backup && $0.category == .localStorage }.first()
            .sink { _ in rejected.fulfill() }
        library.onSnapshotSaved?(library.snapshot)
        await fulfillment(of: [rejected], timeout: operationCompletionTimeout)
        observer.cancel()
        let pushes = await service.pushCount
        let restores = await service.restoreCount
        XCTAssertEqual(pushes, 0)
        XCTAssertEqual(restores, 0)
        XCTAssertTrue(library.hasUnresolvedLoadFailure)
        XCTAssertEqual(library.snapshot, original)
        XCTAssertEqual(store.lastFailure?.category, .localStorage)
        XCTAssertEqual(store.lastFailure?.stage, .validatingLocalCharts)
    }

    func testCachedAcknowledgementDoesNotRewriteLibraryOrRefreshBackupDate() async {
        let (store, library, service) = await configuredStore()
        let original = library.snapshot
        let previousState = store.state
        let previousDate = store.lastRemoteBackupAt
        await service.setPushDidPerformRemoteWrites(false)
        let completed = expectation(description: "Unchanged content completes without a new remote write")
        let observer = store.$lastOperationResult.dropFirst().compactMap { $0 }.first().sink { _ in completed.fulfill() }

        store.backUpNow(enrollLocalCharts: false)
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        observer.cancel()

        XCTAssertEqual(library.snapshot, original)
        XCTAssertEqual(store.lastRemoteBackupAt, previousDate)
        XCTAssertEqual(store.state, previousState)
        XCTAssertEqual(store.lastOperationResult?.didPerformRemoteWrites, false)
        XCTAssertEqual(store.lastOperationResult?.detailText, "No chart changes to back up.")
    }

    func testNoRemoteWritesCannotClearPriorFailureOrClaimFreshBackupDate() async {
        let (store, library, service) = await configuredStore()
        await service.setPushError(CocoaError(.fileWriteUnknown))
        let failed = expectation(description: "Prior remote attempt failed")
        let failure = store.$lastFailure.compactMap { $0 }.first().sink { _ in failed.fulfill() }
        store.backUpNow(enrollLocalCharts: false)
        await fulfillment(of: [failed], timeout: operationCompletionTimeout)
        failure.cancel()
        let failedState = store.state
        let previousFailure = store.lastFailure
        let original = library.snapshot
        let previousDate = store.lastRemoteBackupAt
        await service.setPushError(nil)
        await service.setPushDidPerformRemoteWrites(false)
        let completed = expectation(description: "Local no-change decision completed")
        let observer = store.$lastOperationResult.dropFirst().compactMap { $0 }.first().sink { _ in completed.fulfill() }

        store.backUpNow(enrollLocalCharts: false)
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        observer.cancel()

        XCTAssertEqual(store.state, failedState)
        XCTAssertEqual(store.lastFailure, previousFailure)
        XCTAssertEqual(library.snapshot, original)
        XCTAssertEqual(store.lastRemoteBackupAt, previousDate)
        XCTAssertEqual(store.lastOperationResult?.didPerformRemoteWrites, false)
    }

    func testEmptyNeverBackedUpLibraryUsesIdleAndKeepsRestoreAvailable() async {
        let library = ChartLibraryStore(charts: [], entitlements: AppEntitlements(activePlan: .studioSubscription))
        let service = FeedbackCloudService(ownerID: account().id)
        await service.setPushDidPerformRemoteWrites(false)
        let store = ChartCloudSyncStore(service: service)
        store.attach(libraryStore: library)
        let original = library.snapshot
        let completed = expectation(description: "Empty library has no remote writes")
        let observer = store.$lastOperationResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }

        store.authStateChanged(.signedIn(account()))
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        observer.cancel()

        XCTAssertEqual(store.state, .idle)
        XCTAssertNil(store.lastRemoteBackupAt)
        XCTAssertNil(library.cloudMetadata.lastRemoteBackupAt)
        XCTAssertEqual(library.snapshot, original)
        XCTAssertTrue(store.state.allowsCloudRestore)
        XCTAssertTrue(store.state.allowsManualSync)
    }

    func testRepeatedEquivalentAuthDoesNotRestartFirstUploadOrCancelManualRestore() async {
        let library = ChartLibraryStore(charts: [Chart.blank(title: "First upload")],
            entitlements: AppEntitlements(activePlan: .studioSubscription))
        let service = FeedbackCloudService(ownerID: account().id)
        let firstPush = await service.holdNextPush()
        let store = ChartCloudSyncStore(service: service)
        store.attach(libraryStore: library)
        let writing = expectation(description: "First upload held before any acknowledgement")
        let writer = store.$progress.compactMap { $0 }.filter { $0.stage == .writingDocument }.first().sink { _ in writing.fulfill() }
        store.authStateChanged(.signedIn(account()))
        await fulfillment(of: [writing], timeout: operationCompletionTimeout)
        writer.cancel()
        let noRestart = expectation(description: "Equivalent auth observation cannot start another push")
        noRestart.isInverted = true
        let restarted = store.$progress.dropFirst().compactMap { $0 }.filter { $0.stage == .writingDocument }.sink { _ in noRestart.fulfill() }
        store.authStateChanged(.signedIn(account()))
        store.authStateChanged(.passwordRecovery(account()))
        store.authStateChanged(.signedIn(account()))
        await fulfillment(of: [noRestart], timeout: 0.2)
        restarted.cancel()
        let firstPushCount = await service.pushCount
        XCTAssertEqual(firstPushCount, 1)
        XCTAssertTrue(store.isWorking)
        let backedUp = expectation(description: "Original first upload finishes")
        let backupReceipt = store.$lastOperationResult.compactMap { $0 }.first().sink { _ in backedUp.fulfill() }
        await service.releasePush(firstPush)
        await fulfillment(of: [backedUp], timeout: operationCompletionTimeout)
        backupReceipt.cancel()

        await service.holdNextRestore(extraCharts: [Chart.blank(title: "Explicit cloud restore")])
        let reading = expectation(description: "Manual restore is held")
        let reader = store.$progress.compactMap { $0 }.filter { $0.operation == .restore && $0.stage == .readingSnapshots }.first().sink { _ in reading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [reading], timeout: operationCompletionTimeout)
        reader.cancel()
        store.authStateChanged(.signedIn(account()))
        let restored = expectation(description: "Equivalent auth does not cancel the explicit restore")
        let restoreReceipt = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in restored.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [restored], timeout: operationCompletionTimeout)
        restoreReceipt.cancel()
        let finalPushCount = await service.pushCount
        XCTAssertEqual(finalPushCount, 1)
        XCTAssertEqual(library.charts.count, 2)
        XCTAssertEqual(store.lastRestoreResult?.didApplySnapshot, true)
    }

    func testOfflineRecoveryIsARealContextChangeAndStartsNewBackup() async {
        let (store, library, service) = await configuredStore()
        store.authStateChanged(.temporarilyOffline(account()))
        XCTAssertEqual(store.state, .offline)
        let completed = expectation(description: "Recovered online account starts backup")
        let receipt = store.$lastOperationResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        store.authStateChanged(.signedIn(account()))
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        receipt.cancel()
        let pushCount = await service.pushCount
        XCTAssertEqual(pushCount, 2)
        XCTAssertEqual(library.charts.count, 1, "The live app retains its library throughout offline recovery")
    }

    func testLibraryReadRecoveryReevaluatesSameAccountAndStartsRealBackup() async {
        let repository = RecoverableLibraryRepository()
        let library = ChartLibraryStore.live(repository: repository)
        let service = FeedbackCloudService(ownerID: account().id)
        let store = ChartCloudSyncStore(service: service)
        store.attach(libraryStore: library)
        store.authStateChanged(.signedIn(account()))
        let originalPushCount = await service.pushCount
        XCTAssertEqual(originalPushCount, 0)
        repository.readable = true
        XCTAssertTrue(library.retryLoadingSavedSnapshot())
        let completed = expectation(description: "Successful disk reload permits first backup")
        let receipt = store.$lastOperationResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        store.authStateChanged(.signedIn(account()))
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        receipt.cancel()
        let pushCount = await service.pushCount
        XCTAssertEqual(pushCount, 1)
        XCTAssertFalse(library.hasUnresolvedLoadFailure)
        XCTAssertEqual(library.charts.map(\.id), repository.snapshot.charts.map(\.id))
        XCTAssertEqual(library.charts.map(\.title), repository.snapshot.charts.map(\.title))
        XCTAssertEqual(library.charts.first?.cloudBackupStatus.ownerID, account().id)
    }

    func testExplicitBackupRequestsRemoteRevalidationWhileAutomaticContextMaySkip() async {
        let (store, library, service) = await configuredStore()
        await service.setPushDidPerformRemoteWrites(false)
        let unchanged = expectation(description: "Automatic context may use durable acknowledgement")
        let first = store.$lastOperationResult.dropFirst().compactMap { $0 }.first().sink { _ in unchanged.fulfill() }
        store.backUpNow(enrollLocalCharts: false)
        await fulfillment(of: [unchanged], timeout: operationCompletionTimeout)
        first.cancel()
        await service.setPushDidPerformRemoteWrites(true)
        let forced = expectation(description: "Explicit backup forwards force request")
        let second = store.$lastOperationResult.dropFirst().compactMap { $0 }.first().sink { _ in forced.fulfill() }
        store.backUpNow()
        await fulfillment(of: [forced], timeout: operationCompletionTimeout)
        second.cancel()
        let forceRequests = await service.forceRemoteWriteRequests
        XCTAssertEqual(forceRequests, [false, false, true])
        XCTAssertEqual(library.charts.count, 1, "Keep the authorized library alive through both backup requests")
    }

    func testAccessLossClearsRestoreReceiptWithoutRemovingCharts() async {
        let (store, library, _) = await configuredStore()
        let completed = expectation(description: "Restore completed")
        let observer = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        observer.cancel()
        let charts = library.charts
        library.entitlements = AppEntitlements(activePlan: .free, accessPolicy: .paidSubscription)
        store.authStateChanged(.signedIn(account()))
        XCTAssertEqual(store.state, .requiresPro)
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertNil(store.lastOperationResult)
        XCTAssertEqual(library.charts, charts)
    }

    func testFreeAccountCanRestoreAfterBillingExpiresWithoutLosingCharts() async {
        let (store, library, _) = await configuredStore(chartCount: 4)
        library.entitlements = AppEntitlements(subscription: .proExpired(), accessPolicy: .freeAllFeatures)
        store.authStateChanged(.signedIn(account()))
        let completed = expectation(description: "Expired-billing free account restored")
        let observer = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }

        store.restoreChartsFromCloud()

        await fulfillment(of: [completed], timeout: operationCompletionTimeout)
        observer.cancel()
        XCTAssertNotEqual(store.state, .requiresPro)
        XCTAssertNotNil(store.lastRestoreResult)
        XCTAssertEqual(library.charts.count, 4)
        XCTAssertEqual(library.subscriptionState.status, .proExpired)
        XCTAssertNil(library.localChartLimit)
    }

    func testRestoreFailureHasActualStageAndNoRawErrorOrUnsupportedSignInAdvice() async throws {
        let (store, library, service) = await configuredStore()
        await service.setRestoreError(ChartCloudSyncStageError(
            stage: .writingDocument,
            underlyingError: PostgrestError(code: "42501", message: "private-chart@example.invalid JWT 401")
        ))
        let failed = expectation(description: "Restore failure feedback")
        let observer = store.$lastFailure.compactMap { $0 }.first().sink { _ in failed.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [failed], timeout: operationCompletionTimeout)
        observer.cancel()
        let failure = try XCTUnwrap(store.lastFailure)
        XCTAssertEqual(failure.operation, .restore)
        XCTAssertEqual(failure.stage, .writingDocument)
        XCTAssertEqual(failure.category, .permissionDenied)
        XCTAssertFalse(failure.detailText.contains("private-chart"))
        XCTAssertFalse(failure.detailText.lowercased().contains("sign in"))
        XCTAssertNil(store.progress)
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertEqual(library.charts.count, 1)
    }

    func testDuplicateLocalChartIDsBlockBackupAndRestoreWithoutChangingCharts() async {
        let (store, library, service) = await configuredStore()
        var duplicate = library.charts[0]
        duplicate.title = "Distinct chart contents under a duplicate ID"
        duplicate.cloudBackupStatus = .legacyLocal
        library.charts.append(duplicate)
        let corruptedSnapshot = library.snapshot

        store.backUpNow()
        XCTAssertEqual(store.lastFailure, ChartCloudSyncFailure(
            operation: .backup, stage: .validatingLocalCharts, category: .invalidLocalLibrary
        ))
        XCTAssertEqual(library.snapshot, corruptedSnapshot)

        store.restoreChartsFromCloud()
        XCTAssertEqual(store.lastFailure, ChartCloudSyncFailure(
            operation: .restore, stage: .validatingLocalCharts, category: .invalidLocalLibrary
        ))
        XCTAssertNil(store.lastRestoreResult)

        let rejected = expectation(description: "Automatic backup rejected the conflicting chart IDs")
        let observer = store.$lastFailure.compactMap { $0 }
            .filter { $0.operation == .backup && $0.category == .invalidLocalLibrary }
            .first().sink { _ in rejected.fulfill() }
        library.onSnapshotSaved?(corruptedSnapshot)
        await fulfillment(of: [rejected], timeout: operationCompletionTimeout)
        observer.cancel()

        let pushCount = await service.pushCount
        let restoreCount = await service.restoreCount
        XCTAssertEqual(pushCount, 1) // Initial valid signed-in backup only.
        XCTAssertEqual(restoreCount, 0)
        XCTAssertNil(store.progress)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(library.snapshot, corruptedSnapshot)
    }

    func testSDKClassificationUsesTypedEvidenceAndKeepsSessionPreparationStage() {
        let permission = ChartCloudSyncStore.failureFeedback(for: PostgrestError(code: "42501", message: "JWT 401"), operation: .backup)
        XCTAssertEqual(permission.category, .permissionDenied)
        XCTAssertEqual(ChartCloudSyncStore.failureFeedback(for: PostgrestError(code: "PGRST301", message: "fixture"), operation: .backup).category, .sessionRequired)
        XCTAssertEqual(ChartCloudSyncStore.failureFeedback(for: PostgrestError(code: "PGRST300", message: "JWT"), operation: .backup).category, .server)
        let missing = ChartCloudSyncStore.failureFeedback(for: ChartCloudSyncStageError(stage: .preparingSession, underlyingError: AuthError.sessionMissing), operation: .restore)
        XCTAssertEqual(missing.category, .sessionRequired)
        XCTAssertEqual(missing.stage, .preparingSession)
        let cancelled = ChartCloudSyncStore.failureFeedback(for: ChartCloudSyncStageError(stage: .writingSnapshot, underlyingError: URLError(.cancelled)), operation: .backup)
        XCTAssertEqual(cancelled.category, .cancelled)
        XCTAssertEqual(cancelled.stage, .writingSnapshot)
        XCTAssertEqual(ChartCloudSyncStore.failureFeedback(for: NSError(domain: "Unknown", code: 401, userInfo: [NSLocalizedDescriptionKey: "missing session RLS"]), operation: .backup).category, .unknown)
    }

    private func configuredStore(chartCount: Int = 1) async -> (ChartCloudSyncStore, ChartLibraryStore, FeedbackCloudService) {
        let library = ChartLibraryStore(charts: (0..<chartCount).map { Chart.blank(title: "Local fixture \($0)") }, entitlements: AppEntitlements(activePlan: .studioSubscription))
        let service = FeedbackCloudService(ownerID: account().id)
        let store = ChartCloudSyncStore(service: service)
        store.attach(libraryStore: library)
        let ready = expectation(description: "Initial signed-in backup completed")
        let observer = store.$lastOperationResult.compactMap { $0 }.first().sink { _ in ready.fulfill() }
        store.authStateChanged(.signedIn(account()))
        await fulfillment(of: [ready], timeout: operationCompletionTimeout)
        observer.cancel()
        return (store, library, service)
    }

    private func account(id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000777")!) -> IChartAccountSession {
        IChartAccountSession(id: id, email: nil, phone: nil, isEmailVerified: true)
    }
}

private struct UnreadableLibraryRepository: ChartRepository {
    func loadSnapshot() throws -> ChartLibrarySnapshot? { throw CocoaError(.fileReadCorruptFile) }
    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws { XCTFail("Unread library must never be replaced") }
}

private final class RecoverableLibraryRepository: ChartRepository {
    var readable = false
    let snapshot = ChartLibrarySnapshot(charts: [Chart.blank(title: "Recovered source")],
        selectedChartID: nil, entitlements: AppEntitlements(activePlan: .studioSubscription))
    func loadSnapshot() throws -> ChartLibrarySnapshot? {
        guard readable else { throw CocoaError(.fileReadCorruptFile) }
        return snapshot
    }
    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {}
}

private actor FeedbackCloudService: ChartCloudSyncServicing {
    private var ownerID: UUID
    private(set) var pushCount = 0
    private(set) var restoreCount = 0
    private var holdsRestore = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var extraCharts: [Chart] = []
    private var restoreError: Error?
    private var heldPushNumbers = Set<Int>()
    private var pushContinuations = [Int: CheckedContinuation<Void, Never>]()
    private var pushDidPerformRemoteWrites = true
    private var pushError: Error?
    private(set) var forceRemoteWriteRequests: [Bool] = []

    init(ownerID: UUID) { self.ownerID = ownerID }

    func setOwnerID(_ ownerID: UUID) { self.ownerID = ownerID }
    func setPushDidPerformRemoteWrites(_ value: Bool) { pushDidPerformRemoteWrites = value }
    func setPushError(_ error: Error?) { pushError = error }

    func holdNextPush() -> Int {
        let number = pushCount + 1
        heldPushNumbers.insert(number)
        return number
    }

    func releasePush(_ number: Int) {
        heldPushNumbers.remove(number)
        pushContinuations.removeValue(forKey: number)?.resume()
    }

    func holdNextRestore(extraCharts: [Chart] = []) {
        holdsRestore = true
        self.extraCharts = extraCharts
    }

    func releaseRestore() {
        holdsRestore = false
        continuation?.resume()
        continuation = nil
    }

    func setRestoreError(_ error: Error) { restoreError = error }

    func restoreFromCloud(localSnapshot: ChartLibrarySnapshot, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudRestoreOutcome {
        restoreCount += 1
        let expectedOwnerID = ownerID
        await onProgress?(.readingSnapshots)
        if holdsRestore { await withCheckedContinuation { continuation = $0 } }
        if let restoreError { throw restoreError }
        var restored = localSnapshot
        restored.charts.append(contentsOf: extraCharts)
        restored.cloudMetadata.ownerID = expectedOwnerID
        return ChartCloudRestoreOutcome(
            syncResult: ChartCloudSyncResult(snapshot: restored, lastRemoteBackupAt: Date()),
            remoteChartCount: extraCharts.count, backedUpChartCount: 0, tombstonedChartCount: 0
        )
    }

    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudPushResult {
        pushCount += 1
        let number = pushCount
        let expectedOwnerID = ownerID
        let didWrite = pushDidPerformRemoteWrites
        let error = pushError
        if didWrite { await onProgress?(.writingDocument) }
        if heldPushNumbers.contains(number) {
            await withCheckedContinuation { pushContinuations[number] = $0 }
        }
        if let error { throw error }
        return ChartCloudPushResult(ownerID: expectedOwnerID,
            lastRemoteBackupAt: didWrite ? Date() : .distantPast,
            backedUpChartIDs: didWrite ? Set(snapshot.charts.map(\.id)) : [],
            tombstonedChartIDs: [], didPerformRemoteWrites: didWrite)
    }

    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, forceRemoteWrite: Bool,
                           onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudPushResult {
        forceRemoteWriteRequests.append(forceRemoteWrite)
        return try await pushLocalSnapshot(snapshot, onProgress: onProgress)
    }
}
#endif
