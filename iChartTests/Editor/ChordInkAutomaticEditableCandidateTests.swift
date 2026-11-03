#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Automatic entry may choose a wrong supported chord. That workflow choice
/// must retain the reader's uncertainty and the exact source for later editing.
@MainActor
final class ChordInkAutomaticEditableCandidateTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_200)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)

    func testUnclearTriangleKeepsItsInkForExplicitReviewDespiteFallbackSuggestion() throws {
        let chart = makeChart()
        let source = drawing(x: 106)
        var draft = makeDraft(chart, source: source, text: "Bbø7")
        draft.recognitionResult?.requiresTriangleQualityReview = true
        draft.recognitionResult?.reviewCandidateScores = [
            .init(text: "Bbø7", displayText: "Bbø7", confidence: 4)
        ]

        let blocked = attempt(chart, drafts: [draft], source: source)
        XCTAssertNil(blocked.outcome)
        XCTAssertNil(draft.previewText)
        XCTAssertEqual(blocked.feedback.reasonsByDraftID[draft.id], .triangleQualityReview)
        let status = ChordInkAutomaticFeedbackPresentationPolicy.status(
            for: draft, activity: nil, feedback: blocked.feedback, now: inputAt
        )
        XCTAssertEqual(status?.title, "Review Chord")
        XCTAssertEqual(status?.canReview, true)

        let page = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: page)
        func reviewed(_ draft: ChordInkDraft) -> ChordInkDraftRenderCoordinator.AutomaticAttempt {
            ChordInkDraftRenderCoordinator.prepareReviewedAutomaticAttempt(
                chart: chart, state: .init(draftChords: [draft], layoutPageSize: pageSize),
                currentDrawing: source, coordinateSpace: .init(size: frame.size), isUsingTool: false,
                sourcePageLayout: page, sourceChordFrame: frame
            )
        }
        XCTAssertNil(reviewed(draft).outcome)
        draft.selectedText = "Bbø7"
        let rendered = try XCTUnwrap(reviewed(draft).outcome)
        let event = try XCTUnwrap(rendered.chart.measures.flatMap(\.chordEvents).first)
        XCTAssertEqual(event.symbol.displayText, "Bbø7")
        assertSameInk(source, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
    }

    func testCapturedHalfDiminishedStillRendersAutomatically() throws {
        let chart = makeChart()
        let fixture = try InkFixtureLoader.load("BFlatHalfDiminished7Captured01", file: #filePath)
        let bounds = InkBounds.enclosing(fixture.strokes.map(\.bounds))
        let source = PKDrawing(strokes: fixture.strokes.enumerated().map { index, stroke in
            let points = stroke.points.enumerated().map { pointIndex, point in
                PKStrokePoint(location: CGPoint(x: 106 + point.x - bounds.minX, y: 45 + point.y - bounds.minY),
                    timeOffset: Double(pointIndex) * 0.01, size: CGSize(width: 3, height: 3),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: PKStrokePath(controlPoints: points, creationDate: inputAt.addingTimeInterval(Double(index))),
                transform: .identity, mask: nil, randomSeed: UInt32(index))
        })
        let result = ChordInkMaximumTrustRecognizer().recognize(strokes: PencilKitInkAdapter.inkStrokes(from: source))
        XCTAssertEqual(result.match?.displayText, "Bbø7")
        XCTAssertFalse(result.requiresTriangleQualityReview)
        var draft = makeDraft(chart, source: source, text: result.match?.displayText)
        draft.recognitionResult = result
        let rendered = try XCTUnwrap(attempt(chart, drafts: [draft], source: source).outcome)
        let event = try XCTUnwrap(rendered.chart.measures.flatMap(\.chordEvents).first)
        XCTAssertEqual(event.symbol.displayText, "Bbø7")
        assertSameInk(source, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
    }

    func testSettledSupportedGuessRendersWithoutPromotingConfidenceOrConfirmationToTrust() throws {
        let chart = makeChart()
        let source = drawing(x: 106)
        var draft = makeDraft(chart, source: source, text: "Bb")
        draft.requiresManualReviewOnly = true
        let original = draft
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(draft))
        XCTAssertEqual(ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft), "Bb")
        let outcome = try XCTUnwrap(attempt(chart, drafts: [draft], source: source).outcome)
        let event = try XCTUnwrap(outcome.chart.chordEvent(id: XCTUnwrap(outcome.result.renderedChordIDs.first)))
        XCTAssertEqual(event.rawInput, "Bb")
        XCTAssertEqual(event.symbol, ChordRecognitionCompendium.match("Bb")?.symbol)
        XCTAssertNotNil(event.manualVisualLaneFraction)
        XCTAssertTrue(outcome.drawing.strokes.isEmpty)
        XCTAssertNil(outcome.chart.pageHandwrittenChordData)
        assertSameInk(source, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
        XCTAssertEqual(draft, original)
        XCTAssertEqual(draft.confidence, 0)
        XCTAssertEqual(draft.recognitionDecision?.action, .confirm)
        XCTAssertNil(draft.recognitionDecision?.acceptedText)
        XCTAssertNil(draft.selectedText, "Automatic placement is not a writer-verified selection")
    }

    func testCurrentSupportedScoreAndRawCandidateFallbacksRemainEditableWithoutAResultMatch() throws {
        let chart = makeChart()
        let source = drawing(x: 106)
        for scored in [true, false] {
            var draft = makeDraft(chart, source: source, text: nil)
            draft.recognitionResult = .init(rawCandidates: scored ? ["unreadable"] : ["unreadable", "D/F#"],
                glyphCandidates: [], match: nil, confidence: 0,
                candidateScores: scored ? [.init(text: "D/F#", displayText: "D/F#", confidence: 0.01)] : [])
            XCTAssertFalse(draft.isRenderable, "The workflow must recover actual reader evidence, not invent a name")
            let original = draft
            XCTAssertEqual(ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft), "D/F#")
            let outcome = try XCTUnwrap(attempt(chart, drafts: [draft], source: source).outcome)
            let event = try XCTUnwrap(outcome.chart.chordEvent(id: XCTUnwrap(outcome.result.renderedChordIDs.first)))
            XCTAssertEqual(event.rawInput, "D/F#")
            XCTAssertTrue(event.sourceCandidateSignature.contains("D/F#"))
            assertSameInk(source, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
            XCTAssertEqual(draft, original)
            XCTAssertNil(draft.recognitionResult?.match)
            XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(draft))
        }
    }

    func testSourceChangeCollectingAndExplicitInvalidEditCannotUseAnOldSupportedGuess() {
        let chart = makeChart()
        let source = drawing(x: 106)
        let baseline = makeDraft(chart, source: source, text: "G")
        var stale = baseline
        stale.isStale = true
        var collecting = baseline
        collecting.targetLifecycle?.stage = .collecting
        var absentLifecycle = baseline
        absentLifecycle.targetLifecycle = nil
        var invalidEdit = baseline
        invalidEdit.selectedText = "not a chord"
        for draft in [stale, collecting, absentLifecycle, invalidEdit] {
            XCTAssertNil(ChordInkAutomaticRenderPolicy.automaticCandidateText(for: draft))
            XCTAssertNil(attempt(chart, drafts: [draft], source: source).outcome)
        }
        XCTAssertNil(attempt(chart, drafts: [baseline], source: drawing(x: 107)).outcome)
        var duplicate = baseline
        duplicate.id = UUID()
        XCTAssertNil(attempt(chart, drafts: [baseline, duplicate], source: source).outcome)
        let expanded = PKDrawing(strokes: source.strokes + drawing(x: 400).strokes)
        XCTAssertNil(attempt(chart, drafts: [baseline], source: expanded).outcome,
            "An editable guess cannot authorize consumption of source the current census does not own")
        XCTAssertTrue(chart.measures.flatMap(\.chordEvents).isEmpty)
    }

    func testUncertainEarlierChordCanRenderWhileNewestReaderStillOwnsItsCollectingSource() throws {
        let chart = makeChart()
        let first = drawing(x: 106)
        let newest = drawing(x: 300, seed: 2)
        let firstDraft = makeDraft(chart, source: first, text: "G")
        var newestDraft = makeDraft(chart, source: newest, text: nil, fraction: 0.5)
        newestDraft.targetLifecycle?.stage = .collecting
        let source = PKDrawing(strokes: first.strokes + newest.strokes)
        let outcome = try XCTUnwrap(attempt(chart, drafts: [firstDraft, newestDraft], source: source,
            elapsed: 0.4).outcome)
        XCTAssertEqual(outcome.consumedDraftIDs, [firstDraft.id])
        XCTAssertEqual(outcome.remainingState.draftChords, [newestDraft])
        assertSameInk(newest, outcome.drawing)
        assertSameInk(newest, try PKDrawing(data: XCTUnwrap(outcome.chart.pageHandwrittenChordData)))
        let event = try XCTUnwrap(outcome.chart.measures.flatMap(\.chordEvents).first)
        assertSameInk(first, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(firstDraft))
    }

    func testEditableGuessStillCannotCoverUnfinishedNeighborWithItsProspectiveGlyph() {
        let chart = makeChart()
        let first = drawing(x: 106)
        let neighbor = drawing(x: 159, top: 0, bottom: 90, seed: 2)
        let firstDraft = makeDraft(chart, source: first, text: "Cmaj7/E")
        var pending = makeDraft(chart, source: neighbor, text: nil, fraction: 0.3)
        pending.targetLifecycle?.stage = .collecting
        let source = PKDrawing(strokes: first.strokes + neighbor.strokes)
        let bytes = source.dataRepresentation()
        XCTAssertEqual(ChordInkAutomaticRenderPolicy.automaticCandidateText(for: firstDraft), "Cmaj7/E")
        let result = attempt(chart, drafts: [firstDraft, pending], source: source)
        XCTAssertNil(result.outcome)
        XCTAssertEqual(result.feedback.reasonsByDraftID[firstDraft.id], .needsSpace)
        XCTAssertEqual(source.dataRepresentation(), bytes)
        XCTAssertTrue(chart.measures.flatMap(\.chordEvents).isEmpty)
    }

    func testCorrectingTheRenderedGuessPreservesEventIdentitySourceTimingAndVisualAnchorAcrossReopen() throws {
        let chart = makeChart()
        let source = drawing(x: 106)
        let outcome = try XCTUnwrap(attempt(chart, drafts: [makeDraft(chart, source: source, text: "Bb")],
            source: source).outcome)
        let id = try XCTUnwrap(outcome.result.renderedChordIDs.first)
        let original = try XCTUnwrap(outcome.chart.chordEvent(id: id))
        let originalLayout = layout(outcome.chart)
        let glyph = try XCTUnwrap(originalLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
            .first { $0.id == id })
        let hit = LeadSheetChordEditOverlayGeometry.hitTarget(at: CGPoint(x: glyph.frame.midX, y: glyph.frame.midY),
            in: originalLayout)
        XCTAssertEqual(hit?.chordID, id)
        XCTAssertEqual(hit?.action, .review, "The rendered guess must expose the normal double-tap edit target")
        var edited = outcome.chart
        let corrected = try XCTUnwrap(ChordRecognitionCompendium.match("B7"))
        XCTAssertTrue(edited.replaceChordEvent(id, with: corrected.symbol, rawInput: "B7"))
        let changed = try XCTUnwrap(edited.chordEvent(id: id))
        var expected = original
        expected.symbol = corrected.symbol
        expected.rawInput = "B7"
        expected.spellingIntent = .explicit
        expected.spellingOverrideSource = .userSelection
        XCTAssertEqual(changed, expected, "Editing replaces the label on the same source-owning musical event")
        let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(edited))
        XCTAssertEqual(reopened.chordEvent(id: id), expected)
        assertSameInk(source, try PKDrawing(data: XCTUnwrap(reopened.chordEvent(id: id)?.sourceInkData)))
        XCTAssertNil(reopened.pageHandwrittenChordData)
    }

    func testOptionalCapturedTwentyEightStrokesRenderTheFourObservedSupportedGuessesWithExactOwnership() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = ProcessInfo.processInfo.environment["ICHART_AUTOMATIC_EDITABLE_LIBRARY"].map(URL.init(fileURLWithPath:))
            ?? root.appendingPathComponent(".build/automatic-editable100-2026-10-31/app-support/library-state.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Optional local editable-automatic capture is not present")
        }
        guard let chartID = ProcessInfo.processInfo.environment["ICHART_AUTOMATIC_EDITABLE_CHART_ID"].flatMap(UUID.init(uuidString:)) else {
            throw XCTSkip("Optional local replay requires an explicit chart identifier")
        }
        let bytes = try Data(contentsOf: fixture)
        let snapshot = try XCTUnwrap(try FileChartRepository(url: fixture).loadSnapshot())
        let chart = try XCTUnwrap(snapshot.charts.first { $0.id == chartID })
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertEqual(source.strokes.count, 28)
        let sourceLayout = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        XCTAssertEqual(frame.size, try XCTUnwrap(chart.pageHandwrittenChordCoordinateSpace).size,
            "Captured coordinates are local to the chord canvas, not page bounds")
        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(for: source,
            chordFrame: frame, pageLayout: sourceLayout).sorted { $0.visualOrder < $1.visualOrder }
        XCTAssertEqual(targets.map { $0.drawing.strokes.count }, [6, 5, 10, 7])
        let texts = ["Bb7(b5)", "F-7", "G7(#11)", "A7(b9)"]
        guard targets.count == texts.count else { return XCTFail("Capture must reproduce its four actual source groups") }
        // These exact names were observed in the capture's final debug record.
        // This is a workflow replay, not a fresh reader or handwriting accuracy test.
        let drafts = try targets.enumerated().map { index, target -> ChordInkDraft in
            var draft = makeDraft(chart, source: target.drawing, text: texts[index], fraction: target.fraction)
            draft.measureID = target.measureID
            draft.measureIndex = try XCTUnwrap(chart.measure(id: target.measureID)).index
            draft.visualOrder = target.visualOrder
            draft.laneLocation = target.laneLocation
            draft.anchor = .init(measureID: draft.measureID, laneLocation: draft.laneLocation,
                visualOrder: draft.visualOrder, fraction: draft.targetFraction)
            draft.targetLifecycle?.anchor = draft.anchor
            return draft
        }
        XCTAssertTrue(drafts.allSatisfy { !ChordInkAutomaticRenderPolicy.isTrusted($0) })
        let oldEvents = chart.measures.flatMap(\.chordEvents)
        let outcome = try XCTUnwrap(attempt(chart, drafts: drafts, source: source).outcome)
        XCTAssertEqual(outcome.result.renderedChordCount, 4)
        let rendered = outcome.result.renderedChordIDs.compactMap(outcome.chart.chordEvent(id:))
        XCTAssertEqual(rendered.compactMap(\.rawInput), texts)
        XCTAssertTrue(outcome.remainingState.isEmpty)
        XCTAssertTrue(outcome.drawing.strokes.isEmpty)
        XCTAssertNil(outcome.chart.pageHandwrittenChordData)
        for (target, event) in zip(targets, rendered) {
            assertSameInk(target.drawing, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
        }
        for old in oldEvents { XCTAssertEqual(outcome.chart.chordEvent(id: old.id), old) }
        XCTAssertEqual(try Data(contentsOf: fixture), bytes, "The private capture remains read-only")
    }

    private func makeChart() -> Chart {
        var chart = Chart.draft(title: "Editable automatic read", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func layout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
    }

    private func makeDraft(_ chart: Chart, source: PKDrawing, text: String?, fraction: Double = 0.15) -> ChordInkDraft {
        let decision = ChordInkRecognitionDecision(action: .confirm, acceptedText: nil,
            reason: "Frozen uncertain test evidence", isCloseRace: false,
            competingCandidateText: nil, confidenceGap: nil)
        let result = ChordInkRecognitionResult(rawCandidates: text.map { [$0] } ?? [], glyphCandidates: [],
            match: text.flatMap(ChordRecognitionCompendium.match), confidence: 0)
        var input = ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: chart.measures[0].index,
            targetFraction: fraction, layoutPageSize: pageSize, drawingData: source.dataRepresentation(),
            candidateTexts: text.map { [$0] } ?? [], bestCandidateText: text, confidence: 0,
            strokeCount: source.strokes.count, recognitionResult: result,
            primaryDecision: decision, recognitionDecision: decision)
        input.targetLifecycle = .init(generationID: UUID(), anchor: input.anchor,
            ownership: .init(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: source)), stage: .frozen)
        return ChordInkDraft(input: input)
    }

    private func attempt(_ chart: Chart, drafts: [ChordInkDraft], source: PKDrawing,
        elapsed: TimeInterval = 2) -> ChordInkDraftRenderCoordinator.AutomaticAttempt {
        let sourceLayout = layout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        return ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart,
            state: .init(draftChords: drafts, layoutPageSize: pageSize), currentDrawing: source,
            coordinateSpace: .init(size: frame.size), now: inputAt.addingTimeInterval(elapsed),
            lastInputAt: inputAt, isUsingTool: false, sourcePageLayout: sourceLayout, sourceChordFrame: frame)
    }

    private func assertSameInk(_ expected: PKDrawing, _ current: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: current),
            file: file, line: line)
    }

    private func drawing(x: CGFloat, top: CGFloat = 48, bottom: CGFloat = 80, seed: UInt32 = 1) -> PKDrawing {
        let points = [CGPoint(x: x, y: bottom), CGPoint(x: x + 22, y: top)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: inputAt), transform: .identity,
            mask: nil, randomSeed: seed)])
    }
}
#endif
