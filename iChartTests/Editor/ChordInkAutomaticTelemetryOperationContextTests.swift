#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import XCTest
@testable import iChart

final class ChordInkAutomaticTelemetryOperationContextTests: XCTestCase {
    private typealias Context = ChordInkAutomaticRenderTelemetry.OperationContext

    func testUnchangedSourceSharesOperationAcrossCompletionAndRenderRetries() {
        var context = Context()
        let chartID = UUID()
        let completionOperation = context.operationID(chartID: chartID, sourceRevision: 7)

        XCTAssertEqual(context.operationID(chartID: chartID, sourceRevision: 7), completionOperation)
        XCTAssertEqual(context.operationID(chartID: chartID, sourceRevision: 7), completionOperation)
    }

    func testChangedSourceStartsNewOperationAndDoesNotKeepRevisionHistory() {
        var context = Context()
        let chartID = UUID()
        let original = context.operationID(chartID: chartID, sourceRevision: 7)
        let appended = context.operationID(chartID: chartID, sourceRevision: 8)

        XCTAssertNotEqual(appended, original)
        XCTAssertEqual(context.operationID(chartID: chartID, sourceRevision: 8), appended)
        XCTAssertNotEqual(context.operationID(chartID: chartID, sourceRevision: 7), original,
            "An earlier revision cannot resume a retired operation")
    }

    func testDifferentChartCannotAdoptOperationAtSameRevision() {
        var context = Context()
        let firstChartID = UUID()
        let original = context.operationID(chartID: firstChartID, sourceRevision: 7)
        let otherChart = context.operationID(chartID: UUID(), sourceRevision: 7)

        XCTAssertNotEqual(otherChart, original)
        XCTAssertNotEqual(context.operationID(chartID: firstChartID, sourceRevision: 7), original)
    }

    func testPartialTransactionUsesCapturedRevisionAndRemainingSourceStartsNewOperation() {
        var context = Context()
        let chartID = UUID()
        let capturedSourceRevision: UInt64 = 7
        let noReadOperation = context.operationID(chartID: chartID, sourceRevision: capturedSourceRevision)
        let residentRevisionAfterConsumption: UInt64 = 8

        XCTAssertEqual(context.operationID(chartID: chartID, sourceRevision: capturedSourceRevision),
            noReadOperation, "The transaction identifies its source before partial consumption")
        let retainedSourceOperation = context.operationID(chartID: chartID,
            sourceRevision: residentRevisionAfterConsumption)
        XCTAssertNotEqual(retainedSourceOperation, noReadOperation,
            "Safe partial progress must not label the remaining source fully recovered")
        XCTAssertEqual(context.operationID(chartID: chartID, sourceRevision: residentRevisionAfterConsumption),
            retainedSourceOperation)
    }

    func testAuthorizationResetStartsNewOperationForIdenticalSource() {
        var context = Context()
        let chartID = UUID()
        let priorConsentOperation = context.operationID(chartID: chartID, sourceRevision: 7)
        context.reset()

        let currentConsentOperation = context.operationID(chartID: chartID, sourceRevision: 7)
        XCTAssertNotEqual(currentConsentOperation, priorConsentOperation)
        XCTAssertEqual(context.operationID(chartID: chartID, sourceRevision: 7), currentConsentOperation)
    }

    func testNewCanvasOwnerDoesNotResumeAnotherOwnersOperation() {
        var first = Context()
        var second = Context()
        let chartID = UUID()

        XCTAssertNotEqual(first.operationID(chartID: chartID, sourceRevision: 7),
            second.operationID(chartID: chartID, sourceRevision: 7))
    }
}
#endif
