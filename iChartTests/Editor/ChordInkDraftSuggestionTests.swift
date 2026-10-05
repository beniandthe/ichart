#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkDraftSuggestionTests: XCTestCase {
    func testSupportedNoReadHasSameBestSuggestionInPreviewAndReviewForBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style)
            let drawingData = drawing().dataRepresentation()
            _ = chart.setPageHandwrittenChordDrawing(drawingData)
            let originalChart = chart
            let result = ChordInkRecognitionResult(
                rawCandidates: ["J", "D7", "D9"], glyphCandidates: [], match: nil, confidence: 0,
                rejectedCandidateConfidence: 5.0,
                reviewCandidateScores: [score("D9", 4.1), score("D7", 4.6)]
            )
            let resolution = ChordInkRenderResolutionPolicy.resolution(
                for: result, drawingData: drawingData, correctionMemory: ChordInkUserCorrectionMemory()
            )
            let draft = ChordInkDraft(input: input(chart: chart, drawingData: drawingData, result: result))
            let state = ChordPreviewState(draftChords: [draft])
            let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
            let confirmation = try XCTUnwrap(batch.confirmations.first)

            XCTAssertEqual(resolution.bestCandidateText, "D7", style.rawValue)
            XCTAssertEqual(draft.previewText, "D7")
            XCTAssertEqual(draft.previewDisplayText, "D7")
            XCTAssertEqual(confirmation.bestCandidateText, draft.previewText)
            XCTAssertEqual(confirmation.visibleCandidateTexts, ["D7", "D9"])
            XCTAssertFalse(confirmation.requiresDirectEntry)
            XCTAssertEqual(resolution.decision.action, .confirm)
            XCTAssertNil(resolution.decision.acceptedText)
            XCTAssertEqual(confirmation.decision.action, .confirm)
            XCTAssertNil(draft.selectedText)
            XCTAssertNil(draft.recognitionResult?.match)
            XCTAssertEqual(draft.confidence, 0)
            XCTAssertEqual(draft.drawingData, drawingData)
            XCTAssertTrue(state.requiresChordConfirmation)
            XCTAssertEqual(chart, originalChart, "Showing a suggestion must not render or clear ink")

            let reviewed = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(
                from: state, batch: batch,
                candidateTextByDraftID: [draft.id: try XCTUnwrap(confirmation.bestCandidateText)]
            ))
            XCTAssertEqual(reviewed.draftChords[0].recognitionResult, result)
            XCTAssertEqual(reviewed.draftChords[0].recognitionDecision, draft.recognitionDecision)
            XCTAssertEqual(reviewed.draftChords[0].drawingData, drawingData)
            let committed = chart.commitChordInkDraftBatch(reviewed)
            XCTAssertEqual(committed.renderedChordCount, 1, style.rawValue)
            XCTAssertFalse(committed.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["D7"])
        }
    }

    func testRejectedAndRawOnlyEvidenceOffersAddChordWithoutInventingSuggestionForBothStyles() throws {
        let results = [
            ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0),
            ChordInkRecognitionResult(rawCandidates: ["C7"], glyphCandidates: [], match: nil, confidence: 0),
            ChordInkRecognitionResult(
                rawCandidates: ["ñ", "J", "1"], glyphCandidates: [], match: nil, confidence: 0,
                candidateScores: [score("ñ", 5), score("J", 4.9), score("1", 4.8)],
                rejectedCandidateConfidence: 5
            ),
            ChordInkRecognitionResult(
                rawCandidates: ["ñ"], glyphCandidates: [], match: nil, confidence: 0,
                reviewCandidateScores: [.init(text: "ñ", displayText: "C", confidence: 5)]
            ),
            ChordInkRecognitionResult(
                rawCandidates: ["J"], glyphCandidates: [], match: nil, confidence: 0,
                candidateScores: [.init(text: "J", displayText: "C", confidence: 5)]
            )
        ]
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for result in results {
                var chart = makeChart(style)
                let drawingData = drawing().dataRepresentation()
                _ = chart.setPageHandwrittenChordDrawing(drawingData)
                let originalChart = chart
                let draft = ChordInkDraft(input: input(chart: chart, drawingData: drawingData, result: result))
                let state = ChordPreviewState(draftChords: [draft])
                let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
                let confirmation = try XCTUnwrap(batch.confirmations.first)

                XCTAssertNil(draft.previewText)
                XCTAssertEqual(draft.previewDisplayText, "Add chord")
                XCTAssertTrue(draft.candidateTexts.isEmpty)
                XCTAssertNil(confirmation.bestCandidateText)
                XCTAssertTrue(confirmation.requiresDirectEntry)
                XCTAssertEqual(confirmation.decision.action, .confirm)
                XCTAssertFalse(state.canRenderAllDraftChords)
                XCTAssertTrue(state.canReviewChordDrafts)
                let committed = chart.commitChordInkDraftBatch(state)
                XCTAssertEqual(committed.renderedChordCount, 0)
                XCTAssertEqual(committed.unresolvedDraftIDs, [draft.id])
                XCTAssertEqual(chart, originalChart, "No suggestion must leave exact source ink intact")
            }
        }
    }

    func testInvalidPreferredTextDoesNotHideActualValidChoicesOrReachConfirmation() throws {
        let result = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        let chart = makeChart(.simpleChordSheet)
        var draftInput = input(chart: chart, drawingData: drawing().dataRepresentation(), result: result)
        draftInput.bestCandidateText = "J"
        draftInput.candidateTexts = ["ñ", "1", " D7 ", "D9"]
        let draft = ChordInkDraft(input: draftInput)
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: ChordPreviewState(draftChords: [draft])))
        XCTAssertEqual(draft.previewText, "D7")
        XCTAssertEqual(draft.candidateTexts, ["D7", "D9"])
        XCTAssertEqual(batch.confirmations.first?.bestCandidateText, "D7")
        XCTAssertEqual(batch.confirmations.first?.candidateTexts, ["D7", "D9"])
    }

    func testEmptyEntryHintKeepsActualValidReviewSuggestionAndRejectsIllegalPrefill() {
        let result = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let confirmation = PendingChordInkConfirmation(
            measureID: UUID(), measureIndex: 0, result: result, drawingData: Data(), targetFraction: 0.2,
            primaryDecision: decision, decision: decision, candidateTexts: ["J", "D7"],
            initialEntryText: "ñ", startsWithEmptyEntry: true
        )
        XCTAssertEqual(confirmation.candidateTexts, ["D7"])
        XCTAssertEqual(confirmation.bestCandidateText, "D7")
        XCTAssertFalse(confirmation.requiresDirectEntry)
        XCTAssertEqual(confirmation.decision, decision)
    }

    func testInvalidExplicitSelectionCannotFallBackToRecognitionAndRenderAnotherChord() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style)
            let drawingData = drawing().dataRepresentation()
            _ = chart.setPageHandwrittenChordDrawing(drawingData)
            let originalChart = chart
            let result = ChordInkRecognitionResult(
                rawCandidates: ["C7"], glyphCandidates: [], match: ChordRecognitionCompendium.match("C7"),
                confidence: 3.8, candidateScores: [score("C7", 3.8)]
            )
            let draft = ChordInkDraft(
                input: input(chart: chart, drawingData: drawingData, result: result), selectedText: "J"
            )
            XCTAssertNil(draft.previewText)
            XCTAssertEqual(draft.previewDisplayText, "Add chord")
            XCTAssertFalse(draft.isRenderable)
            let committed = chart.commitChordInkDraftBatch(ChordPreviewState(draftChords: [draft]))
            XCTAssertEqual(committed.renderedChordCount, 0)
            XCTAssertEqual(committed.unresolvedDraftIDs, [draft.id])
            XCTAssertEqual(chart, originalChart)
        }
    }

    func testNativeSuggestionAndTrustDecisionStayUnchangedWhenReviewAlternativeScoresHigher() throws {
        let result = ChordInkRecognitionResult(
            rawCandidates: ["C7"], glyphCandidates: [], match: ChordRecognitionCompendium.match("C7"),
            confidence: 3.8, candidateScores: [score("C7", 3.8)],
            reviewCandidateScores: [score("D7", 4.8)]
        )
        let originalDecision = ChordInkRecognitionPolicy.decision(for: result)
        let resolution = ChordInkRenderResolutionPolicy.resolution(
            for: result, drawingData: Data(), correctionMemory: ChordInkUserCorrectionMemory()
        )
        let chart = makeChart(.rhythmSectionSheet)
        let draft = ChordInkDraft(input: input(chart: chart, drawingData: drawing().dataRepresentation(), result: result))
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: ChordPreviewState(draftChords: [draft])))
        XCTAssertEqual(draft.previewText, "C7")
        XCTAssertEqual(batch.confirmations.first?.bestCandidateText, "C7")
        XCTAssertEqual(resolution.bestCandidateText, "C7")
        XCTAssertEqual(resolution.decision, originalDecision)
        XCTAssertEqual(draft.recognitionDecision, originalDecision)
        XCTAssertEqual(originalDecision.action, .confirm)
    }

    func testStaleAbsorbedTargetDoesNotReuseResultSuggestionUntilOwnershipIsReviewed() throws {
        let result = ChordInkRecognitionResult(
            rawCandidates: ["C7"], glyphCandidates: [], match: ChordRecognitionCompendium.match("C7"),
            confidence: 4.8, candidateScores: [score("C7", 4.8)]
        )
        let chart = makeChart(.simpleChordSheet)
        let draft = ChordInkDraft(
            input: input(chart: chart, drawingData: drawing().dataRepresentation(), result: result), isStale: true
        )
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: ChordPreviewState(draftChords: [draft])))
        XCTAssertNil(draft.previewText)
        XCTAssertEqual(draft.previewDisplayText, "Add chord")
        XCTAssertTrue(draft.candidateTexts.isEmpty)
        XCTAssertNil(batch.confirmations.first?.bestCandidateText)
        XCTAssertTrue(batch.confirmations.first?.requiresDirectEntry == true)
        XCTAssertEqual(draft.recognitionResult, result)
    }

    private func score(_ text: String, _ confidence: Double) -> ChordInkCandidateScore {
        .init(text: text, displayText: ChordRecognitionCompendium.match(text)?.displayText, confidence: confidence)
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Draft suggestions", layoutStyle: style)
        chart.completeInitialSetup(title: "Draft suggestions", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func input(chart: Chart, drawingData: Data, result: ChordInkRecognitionResult) -> ChordInkDraftInput {
        .init(measureID: chart.measures[0].id, measureIndex: 0, targetFraction: 0.25,
            drawingData: drawingData, candidateTexts: [], bestCandidateText: nil,
            confidence: result.confidence, strokeCount: 1, recognitionResult: result,
            recognitionDecision: ChordInkRecognitionPolicy.decision(for: result))
    }

    private func drawing() -> PKDrawing {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 40)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1, size: CGSize(width: 2, height: 2),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1)))])
    }
}
#endif
