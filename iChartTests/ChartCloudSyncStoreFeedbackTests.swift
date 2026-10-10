#if canImport(UIKit)
import Combine
import Foundation
import Supabase
import XCTest
@testable import iChart

@MainActor
final class ChartCloudSyncStoreFeedbackTests: XCTestCase {
    func testZeroCloudRestoreReceiptSurvivesFollowingAutomaticBackup() async throws {
        let (store, library, service) = await configuredStore(chartCount: 4)
        let restored = expectation(description: "Zero cloud restore completed")
        let restoreObserver = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in restored.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [restored], timeout: 2)
        restoreObserver.cancel()
        let receipt = try XCTUnwrap(store.lastRestoreResult)
        XCTAssertEqual(receipt.remoteChartCount, 0)
        XCTAssertEqual(receipt.libraryChartCount, 4)
        XCTAssertEqual(receipt.didApplySnapshot, true)
        XCTAssertNil(store.progress)

        let backedUp = expectation(description: "Following automatic backup completed")
        let backupObserver = store.$lastOperationResult.compactMap { $0 }.filter { $0.operation == .backup }.first().sink { _ in backedUp.fulfill() }
        library.onSnapshotSaved?(library.snapshot)
        await fulfillment(of: [backedUp], timeout: 4)
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
        await fulfillment(of: [completed], timeout: 2)
        first.cancel()
        await service.holdNextRestore()
        let downloading = expectation(description: "New restore downloading")
        let progress = store.$progress.compactMap { $0 }.filter { $0.operation == .restore && $0.stage == .readingSnapshots }.first().sink { _ in downloading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [downloading], timeout: 2)
        progress.cancel()
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertEqual(store.progress?.displayTitle, "Restoring charts")
        XCTAssertEqual(store.progress?.detailText, "Downloading charts…")
        let finished = expectation(description: "Second restore completed")
        let second = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in finished.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [finished], timeout: 2)
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
        await fulfillment(of: [downloading], timeout: 2)
        progress.cancel()
        library.charts[0].title = "Local change during restore"
        let completed = expectation(description: "Restore conditional apply finished")
        let receiptObserver = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [completed], timeout: 2)
        receiptObserver.cancel()
        let receipt = try XCTUnwrap(store.lastRestoreResult)
        XCTAssertEqual(receipt.remoteChartCount, 1)
        XCTAssertEqual(receipt.libraryChartCount, 1)
        XCTAssertEqual(receipt.didApplySnapshot, false)
        XCTAssertEqual(receipt.displayTitle, "Restore not applied")
        XCTAssertEqual(library.charts.map(\.title), ["Local change during restore"])
        store.authStateChanged(.signedOut) // Cancel the existing queued retry.
    }

    func testAccountResetRejectsLateRestoreFeedbackWithoutChangingCancellationAlgorithm() async {
        let (store, library, service) = await configuredStore()
        await service.holdNextRestore()
        let downloading = expectation(description: "Restore began")
        let progress = store.$progress.compactMap { $0 }.filter { $0.stage == .readingSnapshots }.first().sink { _ in downloading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [downloading], timeout: 2)
        progress.cancel()
        store.authStateChanged(.signedOut)
        XCTAssertNil(store.progress)
        XCTAssertNil(store.lastRestoreResult)
        let finished = expectation(description: "Old restore finished")
        let working = store.$isWorking.dropFirst().filter { !$0 }.first().sink { _ in finished.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [finished], timeout: 2)
        working.cancel()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.progress)
        XCTAssertNil(store.lastOperationResult)
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertNil(store.lastFailure)
        XCTAssertEqual(library.charts.count, 1)
    }

    func testAccountResetRejectsLateRestoreFailureStatus() async {
        let (store, library, service) = await configuredStore()
        await service.holdNextRestore()
        await service.setRestoreError(ChartCloudSyncStageError(stage: .readingSnapshots, underlyingError: URLError(.cancelled)))
        let downloading = expectation(description: "Restore began before sign-out")
        let progress = store.$progress.compactMap { $0 }.filter { $0.stage == .readingSnapshots }.first().sink { _ in downloading.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [downloading], timeout: 2)
        progress.cancel()
        store.authStateChanged(.signedOut)
        let finished = expectation(description: "Old restore failed after sign-out")
        let working = store.$isWorking.dropFirst().filter { !$0 }.first().sink { _ in finished.fulfill() }
        await service.releaseRestore()
        await fulfillment(of: [finished], timeout: 2)
        working.cancel()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.progress)
        XCTAssertNil(store.lastOperationResult)
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertNil(store.lastFailure)
        XCTAssertEqual(library.charts.count, 1)
    }

    func testAccessLossClearsRestoreReceiptWithoutRemovingCharts() async {
        let (store, library, _) = await configuredStore()
        let completed = expectation(description: "Restore completed")
        let observer = store.$lastRestoreResult.compactMap { $0 }.first().sink { _ in completed.fulfill() }
        store.restoreChartsFromCloud()
        await fulfillment(of: [completed], timeout: 2)
        observer.cancel()
        let charts = library.charts
        library.entitlements = .free
        store.authStateChanged(.signedIn(account()))
        XCTAssertEqual(store.state, .requiresPro)
        XCTAssertNil(store.lastRestoreResult)
        XCTAssertNil(store.lastOperationResult)
        XCTAssertEqual(library.charts, charts)
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
        await fulfillment(of: [failed], timeout: 2)
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
        await fulfillment(of: [ready], timeout: 2)
        observer.cancel()
        return (store, library, service)
    }

    private func account() -> IChartAccountSession {
        IChartAccountSession(id: UUID(uuidString: "00000000-0000-0000-0000-000000000777")!, email: nil, phone: nil, isEmailVerified: true)
    }
}

private actor FeedbackCloudService: ChartCloudSyncServicing {
    let ownerID: UUID
    private(set) var pushCount = 0
    private var holdsRestore = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var extraCharts: [Chart] = []
    private var restoreError: Error?

    init(ownerID: UUID) { self.ownerID = ownerID }

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
        await onProgress?(.readingSnapshots)
        if holdsRestore { await withCheckedContinuation { continuation = $0 } }
        if let restoreError { throw restoreError }
        var restored = localSnapshot
        restored.charts.append(contentsOf: extraCharts)
        return ChartCloudRestoreOutcome(
            syncResult: ChartCloudSyncResult(snapshot: restored, lastRemoteBackupAt: Date()),
            remoteChartCount: extraCharts.count, backedUpChartCount: 0, tombstonedChartCount: 0
        )
    }

    func pushLocalSnapshot(_ snapshot: ChartLibrarySnapshot, onProgress: ChartCloudSyncProgressHandler?) async throws -> ChartCloudPushResult {
        pushCount += 1
        await onProgress?(.writingDocument)
        return ChartCloudPushResult(ownerID: ownerID, lastRemoteBackupAt: Date(), backedUpChartIDs: Set(snapshot.charts.map(\.id)), tombstonedChartIDs: [])
    }
}
#endif
