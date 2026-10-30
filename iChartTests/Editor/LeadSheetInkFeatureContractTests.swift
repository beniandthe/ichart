#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class LeadSheetInkFeatureContractTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)

    func testSuccessfulRenderArchivesSourceBeforeIntentionalCanvasConsumption() throws {
        let chart = makeChart()
        let source = PKDrawing(strokes: [stroke(10), stroke(90)])
        let state = makeState(chart, source: source)
        let rendered = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: pageSize))
        XCTAssertTrue(rendered.canConsumeSource)
        XCTAssertNil(rendered.chart.pageHandwrittenChordData)

        let assessment = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: rendered, remainingCanvasDrawing: PKDrawing())

        XCTAssertEqual(assessment.outcome, "passed")
        XCTAssertEqual(assessment.reason, "render_complete")
        XCTAssertEqual(assessment.expectedCount, 2)
        XCTAssertEqual(assessment.actualCount, 2)
        XCTAssertEqual(assessment.contentMatches, true)
    }

    func testMissingCommittedReceiptIsDetectedDespiteSuccessfulRenderAndEmptyCanvas() throws {
        let chart = makeChart()
        let source = PKDrawing(strokes: [stroke(10), stroke(90)])
        let state = makeState(chart, source: source)
        let rendered = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: pageSize))
        var missingReceipt = rendered.chart
        missingReceipt.systems[0].measures[0].chordEvents[0].sourceInkData = nil
        let broken = ChordInkDraftRenderCoordinator.Outcome(chart: missingReceipt, result: rendered.result)

        let assessment = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: broken, remainingCanvasDrawing: PKDrawing())

        XCTAssertEqual(assessment.outcome, "violated")
        XCTAssertEqual(assessment.reason, "render_source_missing")
        XCTAssertEqual(assessment.contentMatches, false)
    }

    func testRejectedStaleReviewPreservingChartAndLiveInkIsProtectedRejection() {
        let chart = makeChart()
        let reviewed = PKDrawing(strokes: [stroke(10)])
        let source = PKDrawing(strokes: reviewed.strokes + [stroke(90)])
        let state = makeState(chart, source: reviewed)
        let rejected = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: pageSize))
        XCTAssertTrue(rejected.result.didRejectIncompleteSourceCoverage)

        let assessment = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: rejected, remainingCanvasDrawing: source)

        XCTAssertEqual(assessment.outcome, "protected_rejection")
        XCTAssertEqual(assessment.reason, "render_incomplete_coverage")
        XCTAssertEqual(assessment.contentMatches, true)
    }

    func testRejectedTransactionThatChangesLiveInkOrChartIsViolation() {
        let chart = makeChart()
        let source = PKDrawing(strokes: [stroke(10)])
        let state = makeState(chart, source: source)
        let result = ChordInkDraftBatchRenderResult(renderedChordIDs: [], renderedBarlineIDs: [],
            unresolvedDraftIDs: [], didRejectIncompleteSourceCoverage: true)
        let rejected = ChordInkDraftRenderCoordinator.Outcome(chart: chart, result: result)
        let missingInk = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: rejected, remainingCanvasDrawing: PKDrawing())
        XCTAssertEqual(missingInk.reason, "render_rejected_mutated")
        XCTAssertEqual(missingInk.outcome, "violated")

        var mutated = chart
        mutated.title = "Changed by rejected transaction"
        let changedChart = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: .init(chart: mutated, result: result), remainingCanvasDrawing: source)
        XCTAssertEqual(changedChart.outcome, "violated")
        XCTAssertEqual(changedChart.reason, "render_rejected_mutated")
    }

    func testUnexpectedUnconsumedCanvasDoesNotGetReportedAsSourceLoss() {
        let chart = makeChart()
        let source = PKDrawing(strokes: [stroke(10)])
        let state = makeState(chart, source: source)
        let rendered = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: nil)
        let assessment = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: rendered, remainingCanvasDrawing: source)
        XCTAssertEqual(assessment.outcome, "violated")
        XCTAssertEqual(assessment.reason, "render_canvas_not_cleared")
        XCTAssertEqual(assessment.expectedCount, 0)
        XCTAssertEqual(assessment.actualCount, 1)
        XCTAssertEqual(assessment.contentMatches, true)
    }

    func testOrdinaryBarlineConsumptionDoesNotRequireAnArchivedReceipt() {
        let chart = makeChart()
        let source = PKDrawing(strokes: [stroke(10)])
        let barline = makeBarline(chart: chart, kind: .single, sourceIndex: 0)
        let state = ChordPreviewState(draftBarlines: [barline], layoutPageSize: pageSize)
        let result = ChordInkDraftBatchRenderResult(renderedChordIDs: [], renderedBarlineIDs: [barline.id],
            unresolvedDraftIDs: [])
        let assessment = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: .init(chart: chart, result: result), remainingCanvasDrawing: PKDrawing())
        XCTAssertEqual(assessment.outcome, "passed")
        XCTAssertEqual(assessment.reason, "render_complete")
    }

    func testSharedRepeatReceiptMayDuplicateSourceWhileMissingReceiptIsDetected() throws {
        let chart = makeChart(measureCount: 2)
        let source = PKDrawing(strokes: [stroke(10), stroke(90), stroke(170)])
        let signs = [makeBarline(chart: chart, kind: .repeatStart, sourceIndex: 0),
            makeBarline(chart: chart, kind: .repeatBoth, sourceIndex: 1),
            makeBarline(chart: chart, kind: .repeatEnd, sourceIndex: 2)]
        let state = ChordPreviewState(draftBarlines: signs, layoutPageSize: pageSize)
        var updated = chart
        let first = try XCTUnwrap(updated.addRepeatSpan(startMeasureID: chart.measures[0].id,
            endMeasureID: chart.measures[0].id))
        let second = try XCTUnwrap(updated.addRepeatSpan(startMeasureID: chart.measures[1].id,
            endMeasureID: chart.measures[1].id))
        updated.roadmapObjects[try XCTUnwrap(updated.roadmapObjects.firstIndex { $0.id == first })].sourceInkData =
            PKDrawing(strokes: Array(source.strokes[0...1])).dataRepresentation()
        updated.roadmapObjects[try XCTUnwrap(updated.roadmapObjects.firstIndex { $0.id == second })].sourceInkData =
            PKDrawing(strokes: Array(source.strokes[1...2])).dataRepresentation()
        let result = ChordInkDraftBatchRenderResult(renderedChordIDs: [], renderedBarlineIDs: signs.map(\.id),
            unresolvedDraftIDs: [])
        let assessment = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: .init(chart: updated, result: result), remainingCanvasDrawing: PKDrawing())
        XCTAssertEqual(assessment.outcome, "passed")
        XCTAssertEqual(assessment.expectedCount, 3)
        XCTAssertEqual(assessment.actualCount, 4, "A combined repeat sign belongs to both span receipts")

        updated.roadmapObjects[try XCTUnwrap(updated.roadmapObjects.firstIndex { $0.id == second })].sourceInkData = nil
        let missing = LeadSheetInkFeatureContract.renderAssessment(originalChart: chart, state: state,
            sourceDrawing: source, outcome: .init(chart: updated, result: result), remainingCanvasDrawing: PKDrawing())
        XCTAssertEqual(missing.outcome, "violated")
        XCTAssertEqual(missing.reason, "render_source_missing")
    }

    func testProjectionAllowsCoordinateChangeAndDetectsMissingStrokesOrPoints() {
        let source = PKDrawing(strokes: [stroke(10), stroke(90)])
        let projected = source.transformed(using: CGAffineTransform(scaleX: 1.7, y: 0.7))
        let valid = LeadSheetInkFeatureContract.rotationAssessment(source: source, projected: projected)
        XCTAssertEqual(valid.outcome, "passed")
        XCTAssertEqual(valid.expectedPointCount, valid.actualPointCount)
        XCTAssertEqual(valid.contentMatches, true,
            "This contract verifies count conservation and finite geometry, not exact coordinates or screen placement")

        let missingStroke = LeadSheetInkFeatureContract.rotationAssessment(source: source,
            projected: PKDrawing(strokes: [source.strokes[0]]))
        XCTAssertEqual(missingStroke.outcome, "violated")
        XCTAssertEqual(missingStroke.reason, "rotation_stroke_count_changed")
        XCTAssertEqual(missingStroke.contentMatches, false)

        let fewerPoints = PKDrawing(strokes: [stroke(10, pointCount: 1), stroke(90)])
        let missingPoint = LeadSheetInkFeatureContract.rotationAssessment(source: source, projected: fewerPoints)
        XCTAssertEqual(missingPoint.outcome, "violated")
        XCTAssertEqual(missingPoint.reason, "rotation_point_count_changed")
        XCTAssertEqual(missingPoint.contentMatches, false)
    }

    func testRenderAndRotationEnvelopesSurviveContractSanitizerWithAllRequiredFields() {
        let chart = makeChart()
        let operationID = UUID()
        let source = PKDrawing(strokes: [stroke(10)])
        let assessment = LeadSheetInkFeatureContract.rotationAssessment(source: source, projected: source)
        let envelopes = [
            LeadSheetInkFeatureContract.properties(for: assessment, contractID: "ink.rotation_preservation",
                chart: chart, scope: "page", operationID: operationID),
            LeadSheetInkFeatureContract.properties(
                for: .init(outcome: "passed", reason: "render_complete", expectedCount: 1,
                    actualCount: 1, contentMatches: true),
                contractID: "ink.render_preservation", chart: chart, scope: "chords", operationID: operationID)
        ]
        for (index, var envelope) in envelopes.enumerated() {
            envelope["build_source"] = .string("debug_build") // The service normally injects this field.
            let sanitized = IChartTelemetryPrivacy.sanitizedProperties(envelope, forEventName: "feature.contract_checked")
            XCTAssertTrue(IChartTelemetryPrivacy.hasRequiredContractFields(sanitized))
            XCTAssertEqual(sanitized, envelope, "Required metadata and count evidence must survive the sanitizer")
            XCTAssertEqual(sanitized["operation"], .string(index == 0 ? "rotate" : "render"))
            XCTAssertEqual(sanitized["operation_id"], .string(operationID.uuidString.lowercased()))
        }
    }

    func testProtectedAndUnavailableRenderGuardEnvelopesRemainValidWithoutCountEvidence() {
        let chart = makeChart()
        for unavailable in [false, true] {
            let reason = unavailable ? "render_canvas_unavailable" : "render_repeat_review_required"
            var envelope = LeadSheetInkFeatureContract.renderGuardProperties(
                chart: chart, reason: reason, unavailable: unavailable
            )
            envelope["build_source"] = .string("release_build")
            let sanitized = IChartTelemetryPrivacy.sanitizedProperties(envelope, forEventName: "feature.contract_checked")
            XCTAssertTrue(IChartTelemetryPrivacy.hasRequiredContractFields(sanitized))
            XCTAssertEqual(sanitized["operation"], .string("render"))
            XCTAssertEqual(sanitized["reason"], .string(reason))
            XCTAssertEqual(sanitized["outcome"], .string(unavailable ? "unknown" : "protected_rejection"))
            XCTAssertNil(sanitized["content_matches"], "Unavailable source cannot claim verified preservation")
            XCTAssertNil(sanitized["expected_count"])
        }
    }

    private func makeChart(measureCount: Int = 1) -> Chart {
        var chart = Chart.draft(title: "Feature contract fixture", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: "Feature contract fixture", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: measureCount)
        return chart
    }

    private func makeState(_ chart: Chart, source: PKDrawing) -> ChordPreviewState {
        let normalized = LeadSheetPersistentInkColorPolicy.normalizedDrawing(source)
        let drafts = normalized.strokes.enumerated().map { index, stroke in
            ChordInkDraft(input: ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: Double(index + 1) / Double(normalized.strokes.count + 1), layoutPageSize: pageSize,
                drawingData: PKDrawing(strokes: [stroke]).dataRepresentation(), candidateTexts: ["C"],
                bestCandidateText: "C", confidence: 4, strokeCount: 1))
        }
        return ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
    }

    private func makeBarline(chart: Chart, kind: DraftBarlineKind, sourceIndex: Int) -> DraftBarline {
        DraftBarline(measureID: chart.measures[0].id, measureIndex: 1, fraction: 0.5,
            sourceStrokeIndex: sourceIndex,
            metrics: .init(height: 50, width: 0, angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 0.9),
            kind: kind)
    }

    private func stroke(_ x: CGFloat, pointCount: Int = 2) -> PKStroke {
        let points = (0..<pointCount).map { index in
            PKStrokePoint(location: CGPoint(x: x + CGFloat(index) * 14, y: 10 + CGFloat(index) * 20),
                timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.marker, color: .red),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 100)),
            transform: .identity, mask: nil, randomSeed: 17)
    }
}
#endif
