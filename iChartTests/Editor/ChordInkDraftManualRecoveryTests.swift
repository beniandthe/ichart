#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkDraftManualRecoveryTests: XCTestCase {
    func testGrowingRecognizedChordPastLoadLimitReplacesStandInWithOneCoveredManualTarget() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var (chart, state) = try fixture(style: style)
            let previousID = state.draftChords[0].id
            state.draftChords[0].selectedText = "C7"
            let originalSource = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            let expanded = [originalSource.strokes[0]] + (0..<16).map { stroke(10 + CGFloat($0 + 1) * 0.2) }
            _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: expanded + [originalSource.strokes[1]]).dataRepresentation())
            let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            let targetDrawing = PKDrawing(strokes: Array(source.strokes.prefix(17)))
            let unread = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil,
                confidence: 0, requiresEditReview: true)
            var incoming = ChordInkDraftInput(measureID: state.draftChords[0].measureID, measureIndex: 0,
                targetFraction: 0.25, drawingData: targetDrawing.dataRepresentation(), candidateTexts: [],
                bestCandidateText: nil, confidence: 0, strokeCount: 17, recognitionResult: unread,
                recognitionDecision: ChordInkRecognitionPolicy.decision(for: unread), requiresManualReviewOnly: true)
            let ownership = ChordInkRecognitionTargetOwnership(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: targetDrawing))
            incoming.targetLifecycle = .init(generationID: UUID(), anchor: incoming.anchor,
                ownership: ownership, stage: .stable)
            let neighbor = ChordInkDraftInput(measureID: state.draftChords[1].measureID, measureIndex: 1,
                targetFraction: 0.25, drawingData: PKDrawing(strokes: [source.strokes[17]]).dataRepresentation(),
                candidateTexts: [], bestCandidateText: nil, confidence: 0, strokeCount: 1)
            XCTAssertFalse(ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
                strokes: ownership.preparedStrokes, flow: .draftPreview))
            state.replaceDraftChords(with: [incoming, neighbor])
            XCTAssertEqual(state.draftChords.count, 2, "One full-source target plus the independent neighboring chord")
            XCTAssertEqual(state.draftChords.filter { $0.measureIndex == 0 }.count, 1)
            XCTAssertEqual(state.draftChords[0].id, previousID)
            XCTAssertNil(state.draftChords[0].selectedText, "An earlier correction cannot label expanded source ink")
            XCTAssertNil(state.draftChords[0].previewText)
            XCTAssertTrue(state.draftChords[0].requiresManualReviewOnly)
            XCTAssertEqual(state.draftChords[0].targetLifecycle?.stage, .frozen)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
            let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
            let reviewed = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
                candidateTextByDraftID: [state.draftChords[0].id: "C9", state.draftChords[1].id: "D7"]))
            let result = chart.commitChordInkDraftBatch(reviewed)
            XCTAssertEqual(result.renderedChordCount, 2, style.rawValue)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
            XCTAssertNil(chart.pageHandwrittenChordData)
        }
    }

    func testUnreadDraftsCanBeReviewedAndManuallyRenderedInBothStylesWithoutRecognitionPromotion() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var (chart, state) = try fixture(style: style)
            let originalState = state
            let source = chart.pageHandwrittenChordData
            let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
            XCTAssertEqual(batch.confirmations.count, 2)
            XCTAssertTrue(state.requiresChordConfirmation)
            XCTAssertTrue(state.canReviewChordDrafts)
            XCTAssertFalse(state.canRenderAllDraftChords)
            XCTAssertNil(batch.confirmations[1].bestCandidateText)
            XCTAssertEqual(batch.confirmations[1].decision.action, .confirm)
            XCTAssertEqual(chart.pageHandwrittenChordData, source)
            state = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
                candidateTextByDraftID: [state.draftChords[0].id: "C", state.draftChords[1].id: "D7"]))
            XCTAssertEqual(state.draftChords[1].drawingData, originalState.draftChords[1].drawingData)
            XCTAssertEqual(state.draftChords[1].recognitionResult, originalState.draftChords[1].recognitionResult)
            XCTAssertEqual(state.draftChords[1].recognitionDecision, originalState.draftChords[1].recognitionDecision)
            XCTAssertEqual(state.draftChords[1].confidence, 0)
            let committed = chart.commitChordInkDraftBatch(state)
            XCTAssertEqual(committed.renderedChordCount, 2, style.rawValue)
            XCTAssertTrue(committed.unresolvedDraftIDs.isEmpty)
            XCTAssertNil(chart.pageHandwrittenChordData)
            XCTAssertEqual(chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["C", "D7"])
        }
    }

    func testInvalidMissingAndUnexpectedReviewLabelsPreserveEveryDraftAndChart() throws {
        let (chart, state) = try fixture(style: .simpleChordSheet)
        let originalChart = chart
        let originalState = state
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        for labels in [
            [state.draftChords[0].id: "C", state.draftChords[1].id: "J"],
            [state.draftChords[0].id: "C"],
            [state.draftChords[0].id: "C", state.draftChords[1].id: "D7", UUID(): "G"]
        ] {
            XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
                candidateTextByDraftID: labels))
            XCTAssertEqual(state, originalState)
            XCTAssertEqual(chart, originalChart)
        }
    }

    func testChangedTargetOrLayoutSnapshotCannotReusePreviouslyEnteredLabels() throws {
        let (_, state) = try fixture(style: .rhythmSectionSheet)
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let labels = [state.draftChords[0].id: "C", state.draftChords[1].id: "D7"]
        var changed = state
        changed.draftChords[1].drawingData = PKDrawing(strokes: [stroke(190)]).dataRepresentation()
        XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: changed, batch: batch,
            candidateTextByDraftID: labels))
        changed = state
        changed.draftChords[1].id = UUID()
        XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: changed, batch: batch,
            candidateTextByDraftID: labels))
        changed = state
        changed.layoutPageSize = CGSize(width: 1200, height: 900)
        XCTAssertNil(ChordInkDraftReviewPolicy.reviewedState(from: changed, batch: batch,
            candidateTextByDraftID: labels))
    }

    func testDirectBatchCommitWithOneUnreadTargetIsAtomicInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var (chart, state) = try fixture(style: style)
            let original = chart
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
            let result = chart.commitChordInkDraftBatch(state)
            XCTAssertEqual(result.renderedChordCount, 0)
            XCTAssertEqual(result.unresolvedDraftIDs, [state.draftChords[1].id])
            XCTAssertEqual(chart, original, "A valid neighbor must not render before a later target fails")
        }
    }

    func testChangedLiveSourceRejectsReviewedCommitWithoutClearingOrMaterializingAnything() throws {
        var (chart, state) = try fixture(style: .simpleChordSheet)
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        let reviewed = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: state, batch: batch,
            candidateTextByDraftID: [state.draftChords[0].id: "C", state.draftChords[1].id: "D7"]))
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: source.strokes + [stroke(250)]).dataRepresentation())
        let original = chart
        let result = chart.commitChordInkDraftBatch(reviewed)
        XCTAssertTrue(result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(result.renderedChordCount, 0)
        XCTAssertEqual(chart, original)
    }

    private func fixture(style: ChartLayoutStyle) throws -> (Chart, ChordPreviewState) {
        var chart = Chart.draft(title: "Manual recovery", layoutStyle: style)
        chart.completeInitialSetup(title: "Manual recovery", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
            startingMeasureCount: 2)
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [stroke(10), stroke(90)]).dataRepresentation())
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let drafts = chart.measures.prefix(2).enumerated().map { index, measure in
            ChordInkDraft(input: ChordInkDraftInput(measureID: measure.id, measureIndex: measure.index,
                targetFraction: 0.25, drawingData: PKDrawing(strokes: [source.strokes[index]]).dataRepresentation(),
                candidateTexts: index == 0 ? ["C"] : [], bestCandidateText: index == 0 ? "C" : nil,
                confidence: index == 0 ? 4.6 : 0, strokeCount: 1))
        }
        XCTAssertEqual(drafts.count, 2)
        return (chart, ChordPreviewState(draftChords: drafts))
    }

    private func stroke(_ x: CGFloat) -> PKStroke {
        let points = [CGPoint(x: x, y: 10), CGPoint(x: x + 20, y: 40)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1, size: CGSize(width: 2, height: 2),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(x))),
            transform: .identity, mask: nil, randomSeed: 17)
    }
}
#endif
