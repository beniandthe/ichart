#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkAutomaticRenderTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)

    func testTrustedCompleteSourceRendersAfterIdleAndRetainsCanonicalAcceptedChordSpelling() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let chart = chart(style)
            let drawing = normalized([stroke(10), stroke(110)])
            // Use the reader's canonical accepted spelling. The renderer draws
            // the sharp glyph; raw recognition text uses an ASCII #.
            let state = state(chart, drawing, texts: ["D/F#", "Cmaj7"])
            let outcome = try XCTUnwrap(prepare(chart, state, drawing, elapsed: 1.2))
            XCTAssertEqual(outcome.result.renderedChordCount, 2)
            XCTAssertEqual(Set(outcome.chart.measures.flatMap(\.chordEvents).compactMap(\.rawInput)), Set(["D/F#", "Cmaj7"]))
            XCTAssertTrue(outcome.drawing.strokes.isEmpty)
            XCTAssertTrue(outcome.remainingState.isEmpty)
            XCTAssertNil(outcome.chart.pageHandwrittenChordData)
            XCTAssertNil(chart.pageHandwrittenChordData)
            XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
        }
    }

    func testSpaceCompletionCommitsPreviousChordAndPreservesNewestSource() async throws {
        let chart = chart()
        let drawing = normalized([stroke(10), stroke(110)])
        let state = state(chart, drawing)
        let outcome = try XCTUnwrap(prepare(chart, state, drawing, elapsed: 0.4))
        XCTAssertEqual(outcome.result.renderedChordCount, 1)
        XCTAssertEqual(outcome.consumedDraftIDs, [state.draftChords[0].id])
        XCTAssertEqual(outcome.remainingState.draftChords.map(\.id), [state.draftChords[1].id])
        let expectedRemaining = PKDrawing(strokes: [drawing.strokes[1]])
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedRemaining, current: outcome.drawing))
        let persisted = try PKDrawing(data: XCTUnwrap(outcome.chart.pageHandwrittenChordData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedRemaining, current: persisted))
        XCTAssertEqual(outcome.chart.pageHandwrittenChordCoordinateSpace, PersistentInkCoordinateSpace(size: pageSize))
    }

    func testNewestChordWaitsForIdleAndEveryTargetWaitsForSpaceDelay() async throws {
        let chart = chart()
        let single = normalized([stroke(10)])
        let singleState = state(chart, single)
        XCTAssertNil(prepare(chart, singleState, single, elapsed: 0.4))
        let pair = normalized([stroke(10), stroke(110)])
        XCTAssertNil(prepare(chart, state(chart, pair), pair, elapsed: 0.34))
        XCTAssertNil(prepare(chart, singleState, single, elapsed: -1))
        XCTAssertNil(ChordInkDraftRenderCoordinator.prepareAutomatic(chart: chart, state: singleState,
            currentDrawing: single, coordinateSpace: nil, now: inputAt.addingTimeInterval(3),
            lastInputAt: nil, isUsingTool: false))
    }

    func testUnrepresentedSlashOrExtensionPreventsPrematureRootCommitAfterIdle() async throws {
        let chart = chart()
        let root = normalized([stroke(10)])
        let state = state(chart, root)
        // Nearby additions model a slash/bass continuation and a raised suffix.
        for suffix in [stroke(28), stroke(20, y: -5), stroke(20, y: -45), stroke(20, y: 65)] {
            let current = PKDrawing(strokes: root.strokes + normalized([suffix]).strokes)
            XCTAssertNil(prepare(chart, state, current, elapsed: 2),
                "New continuation ink must not be orphaned by rendering the old root")
            XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
        }
    }

    func testSupportedUncertainNeighborRendersAlongsideTrustedChordAfterIdle() async throws {
        let chart = chart()
        let drawing = normalized([stroke(10), stroke(110)])
        var state = state(chart, drawing)
        state.draftChords[1].recognitionDecision?.action = .confirm
        state.draftChords[1].recognitionDecision?.acceptedText = nil
        let originalUncertain = state.draftChords[1]
        let outcome = try XCTUnwrap(prepare(chart, state, drawing, elapsed: 2))
        XCTAssertEqual(outcome.result.renderedChordCount, 2)
        XCTAssertTrue(outcome.remainingState.isEmpty)
        XCTAssertTrue(outcome.drawing.strokes.isEmpty)
        XCTAssertEqual(state.draftChords[1], originalUncertain)
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(originalUncertain),
            "An editable automatic guess does not promote the reader's decision to trusted")
    }

    func testDistantUnrepresentedInkWaitsForGroupingBeforeAnyAutomaticCommit() async throws {
        let chart = chart()
        let snapshot = normalized([stroke(10)])
        let state = state(chart, snapshot)
        // Geometry alone cannot decide whether this is a next chord or a
        // widely spaced slash bass. Neither source may be consumed yet.
        for added in [normalized([stroke(150)]), normalized([stroke(70, y: 45)])] {
            let current = PKDrawing(strokes: snapshot.strokes + added.strokes)
            XCTAssertNil(prepare(chart, state, current, elapsed: 0.4))
            XCTAssertNil(prepare(chart, state, current, elapsed: 3))
        }
        XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertNil(chart.pageHandwrittenChordData)
    }

    func testChangedLiveTargetAndDuplicateOwnershipCannotConsumeSource() async throws {
        let chart = chart()
        let snapshot = normalized([stroke(10)])
        var state = state(chart, snapshot)
        XCTAssertNil(prepare(chart, state, normalized([stroke(11)]), elapsed: 2))
        var duplicate = state.draftChords[0]
        duplicate.id = UUID()
        state.draftChords.append(duplicate)
        XCTAssertNil(prepare(chart, state, snapshot, elapsed: 2))
    }

    func testStaleCollectingAndMissingLifecycleStayInkWhileSupportedUncertainReadsAreEditable() async throws {
        let chart = chart()
        let drawing = normalized([stroke(10)])
        let baseline = state(chart, drawing)
        var variants = [ChordPreviewState]()
        var manualOnly = baseline
        manualOnly.draftChords[0].requiresManualReviewOnly = true
        var stale = baseline
        stale.draftChords[0].isStale = true
        variants.append(stale)
        var collecting = baseline
        collecting.draftChords[0].targetLifecycle?.stage = .collecting
        variants.append(collecting)
        var missingLifecycle = baseline
        missingLifecycle.draftChords[0].targetLifecycle = nil
        variants.append(missingLifecycle)
        var confirmation = baseline
        confirmation.draftChords[0].recognitionDecision?.action = .confirm
        for candidate in variants {
            XCTAssertNil(prepare(chart, candidate, drawing, elapsed: 3))
        }
        for candidate in [manualOnly, confirmation] {
            XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(candidate.draftChords[0]))
            let rendered = try XCTUnwrap(prepare(chart, candidate, drawing, elapsed: 3))
            XCTAssertEqual(rendered.result.renderedChordCount, 1)
            XCTAssertTrue(rendered.drawing.strokes.isEmpty)
        }
        // Explicit manual rendering still accepts the user's reviewed text.
        let manual = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: confirmation,
            currentDrawing: drawing, coordinateSpace: nil)
        XCTAssertTrue(manual.canConsumeSource)
        XCTAssertEqual(manual.result.renderedChordCount, 1)
    }

    func testActiveStrokeAndAdjacentUnresolvedTargetPreventAutomaticConsumption() async throws {
        let chart = chart()
        let drawing = normalized([stroke(10)])
        XCTAssertNil(prepare(chart, state(chart, drawing), drawing, elapsed: 3, isUsingTool: true))
        let adjacent = normalized([stroke(10), stroke(28)])
        var unresolvedState = state(chart, adjacent)
        unresolvedState.draftChords[1].recognitionDecision?.action = .confirm
        unresolvedState.draftChords[1].targetLifecycle?.stage = .collecting
        XCTAssertNil(prepare(chart, unresolvedState, adjacent, elapsed: 3))
    }

    func testPendingRepeatConfirmationCannotBeBypassedByAutomaticNeighborCommit() async throws {
        let chart = chart()
        let drawing = normalized([stroke(10)])
        var state = state(chart, drawing)
        state.draftBarlines = [DraftBarline(measureID: chart.measures[0].id, measureIndex: 1,
            fraction: 0.9, sourceStrokeIndex: 0,
            metrics: DraftBarlineGestureMetrics(height: 50, width: 0,
                angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 0.9),
            kind: .repeatEnd)]
        XCTAssertNotNil(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: state))
        XCTAssertNil(prepare(chart, state, drawing, elapsed: 3))
    }

    private func prepare(
        _ chart: Chart, _ state: ChordPreviewState, _ drawing: PKDrawing,
        elapsed: TimeInterval, isUsingTool: Bool = false
    ) -> ChordInkDraftRenderCoordinator.AutomaticOutcome? {
        ChordInkDraftRenderCoordinator.prepareAutomatic(chart: chart, state: state,
            currentDrawing: drawing, coordinateSpace: PersistentInkCoordinateSpace(size: pageSize),
            now: inputAt.addingTimeInterval(elapsed), lastInputAt: inputAt, isUsingTool: isUsingTool)
    }

    private func chart(_ style: ChartLayoutStyle = .simpleChordSheet) -> Chart {
        var chart = Chart.draft(title: "Automatic render", layoutStyle: style)
        chart.completeInitialSetup(title: "Automatic render", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func state(_ chart: Chart, _ drawing: PKDrawing, texts: [String]? = nil) -> ChordPreviewState {
        let drafts = drawing.strokes.enumerated().map { index, stroke in
            let text = texts?[index] ?? "C"
            var input = ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: Double(index + 1) / Double(drawing.strokes.count + 1),
                layoutPageSize: pageSize, drawingData: PKDrawing(strokes: [stroke]).dataRepresentation(),
                candidateTexts: [text], bestCandidateText: text, confidence: 4.5, strokeCount: 1,
                recognitionDecision: ChordInkRecognitionDecision(action: .trusted, acceptedText: text,
                    reason: "Trusted test read", isCloseRace: false, competingCandidateText: nil, confidenceGap: nil))
            input.targetLifecycle = ChordInkRecognitionTargetLifecycle(generationID: UUID(), anchor: input.anchor,
                ownership: ChordInkRecognitionTargetOwnership(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: [stroke]))),
                stage: .frozen)
            return ChordInkDraft(input: input)
        }
        return ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
    }

    private func normalized(_ strokes: [PKStroke]) -> PKDrawing {
        LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes))
    }

    private func stroke(_ x: CGFloat, y: CGFloat = 10) -> PKStroke {
        let points = [CGPoint(x: x, y: y), CGPoint(x: x + 14, y: y + 20)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: inputAt),
            transform: .identity, mask: nil, randomSeed: 17)
    }
}
#endif
