import Foundation
import XCTest
@testable import iChart

final class ChartCloudSyncFeedbackTests: XCTestCase {
    func testZeroCloudChartsIsNotReportedAsLocalChartsRestored() {
        let result = result(operation: .restore, remoteCount: 0, localCount: 4, applied: true)
        XCTAssertEqual(result.displayTitle, "Restore complete — no cloud charts")
        XCTAssertTrue(result.detailText.contains("Found 0 charts in cloud"))
        XCTAssertTrue(result.detailText.contains("this iPad now has 4 charts"))
        XCTAssertFalse(result.detailText.contains("Restored 4"))
    }

    func testAvailableCloudCountAndFinalLocalCountRemainDistinct() {
        let result = result(operation: .restore, remoteCount: 3, localCount: 7, applied: true)
        XCTAssertTrue(result.detailText.contains("Found 3 charts in cloud"))
        XCTAssertTrue(result.detailText.contains("this iPad now has 7 charts"))
        XCTAssertFalse(result.detailText.contains("Restored 7"))
    }

    func testLocalEditsPreventFalseRestoreCompletionClaim() {
        let result = result(operation: .restore, remoteCount: 2, localCount: 4, applied: false)
        XCTAssertEqual(result.displayTitle, "Restore not applied")
        XCTAssertTrue(result.detailText.contains("Your current library was kept"))
        XCTAssertTrue(result.detailText.contains("Retry restore"))
        XCTAssertFalse(result.detailText.contains("Restore applied"))
    }

    func testZeroEligibleBackupHasExplicitCompletion() {
        let result = result(operation: .backup, remoteCount: nil, localCount: 4, applied: nil)
        XCTAssertEqual(result.displayTitle, "Backup complete")
        XCTAssertEqual(result.detailText, "No eligible charts or cloud deletions were included in this backup.")
    }

    func testPermissionFailureDoesNotInventMissingSignInOrRLSCause() {
        let failure = ChartCloudSyncFailure(operation: .restore, stage: .writingDocument, category: .permissionDenied)
        XCTAssertTrue(failure.detailText.contains("Cloud permissions blocked cloud restore"))
        XCTAssertFalse(failure.detailText.lowercased().contains("sign in"))
        XCTAssertFalse(failure.detailText.lowercased().contains("rls"))
        XCTAssertEqual(failure.diagnosticStage, "cloud_stage_writing_document")
    }

    func testFoundationFailureClassificationDoesNotReadRawDescriptions() {
        let unknown = NSError(domain: "TestUnknown", code: 401, userInfo: [
            NSLocalizedDescriptionKey: "JWT permission denied chart-title@example.invalid"
        ])
        XCTAssertEqual(ChartCloudSyncFailureCategory.foundationCategory(for: unknown), .unknown)
        XCTAssertEqual(ChartCloudSyncFailureCategory.foundationCategory(for: CancellationError()), .cancelled)
        XCTAssertEqual(ChartCloudSyncFailureCategory.foundationCategory(for: URLError(.cancelled)), .cancelled)
        XCTAssertEqual(ChartCloudSyncFailureCategory.foundationCategory(for: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(ChartCloudSyncFailureCategory.foundationCategory(for: URLError(.timedOut)), .timeout)
        XCTAssertEqual(ChartCloudSyncFailureCategory.foundationCategory(for: NSError(domain: NSOSStatusErrorDomain, code: -25308)), .localStorage)
    }

    func testStageReportingPublishesBeforeOperationAndPreservesOriginalError() async {
        let recorder = StageRecorder()
        let original = TestFailure.unavailable
        do {
            let _: Int = try await ChartCloudSyncStageReporting.perform(.readingSnapshots, onProgress: { stage in
                await recorder.record(stage)
            }) {
                let recorded = await recorder.stages
                XCTAssertEqual(recorded, [.readingSnapshots])
                throw original
            }
            XCTFail("Expected the original failure")
        } catch let error as ChartCloudSyncStageError {
            XCTAssertEqual(error.stage, .readingSnapshots)
            XCTAssertEqual(error.underlyingError as? TestFailure, original)
        } catch {
            XCTFail("Expected a fixed stage wrapper")
        }
    }

    func testNestedStageReportingKeepsTheActualFailingStage() async {
        do {
            let _: Int = try await ChartCloudSyncStageReporting.perform(.mergingCharts, onProgress: nil) {
                try await ChartCloudSyncStageReporting.perform(.writingSnapshot, onProgress: nil) {
                    throw TestFailure.unavailable
                }
            }
            XCTFail("Expected failure")
        } catch let error as ChartCloudSyncStageError {
            XCTAssertEqual(error.stage, .writingSnapshot)
            XCTAssertEqual(error.underlyingError as? TestFailure, .unavailable)
        } catch {
            XCTFail("Expected a fixed stage wrapper")
        }
    }

    private func result(operation: ChartCloudSyncOperation, remoteCount: Int?, localCount: Int, applied: Bool?) -> ChartCloudSyncOperationResult {
        ChartCloudSyncOperationResult(
            operation: operation, completedAt: Date(timeIntervalSince1970: 1_800_000_000),
            remoteChartCount: remoteCount, backedUpChartCount: 0, tombstonedChartCount: 0,
            libraryChartCount: localCount, didApplySnapshot: applied
        )
    }

    private enum TestFailure: Error, Equatable { case unavailable }
    private actor StageRecorder {
        private(set) var stages: [ChartCloudSyncStage] = []
        func record(_ stage: ChartCloudSyncStage) { stages.append(stage) }
    }
}
