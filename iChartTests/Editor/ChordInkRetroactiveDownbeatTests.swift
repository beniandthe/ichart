#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkRetroactiveDownbeatTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let authoringStates: [MeasureAuthoringState] = [.open, .committed]

    func testSplitsAnchorEachResultingSingletonAndPreserveOriginalChordReceipts() throws {
        for style in styles {
            for state in authoringStates {
                var chart = makeChart(style, state: state)
                let measureID = chart.measures[0].id
                let originals = try [event("C", fraction: 0.2, seed: 1),
                    event("G7", fraction: 0.8, seed: 2)]
                chart.systems[0].measures[0].chordEvents = originals
                let pageInk = drawing(seed: 30).dataRepresentation()
                chart.pageHandwrittenNotationData = pageInk

                let rightID = try XCTUnwrap(split(&chart, id: measureID, fraction: 0.5))
                let reopened = try reopen(chart)

                XCTAssertEqual(reopened.measures.map(\.id), [measureID, rightID])
                XCTAssertEqual(reopened.measures.map { $0.chordEvents.map(\.id) },
                    [[originals[0].id], [originals[1].id]])
                XCTAssertEqual(reopened.pageHandwrittenNotationData, pageInk)
                for original in originals {
                    let actual = try XCTUnwrap(reopened.chordEvent(id: original.id))
                    assertReceipt(actual, matches: original)
                    assertDownbeat(actual)
                    try assertVisibleDownbeat(actual.id, chart: reopened)
                }
            }
        }
    }

    func testMultiChordResultKeepsItsRelativePlacementBesideAnAnchoredSingleton() throws {
        for style in styles {
            for state in authoringStates {
                var chart = makeChart(style, state: state)
                let measureID = chart.measures[0].id
                let originals = try [event("C", fraction: 0.1, seed: 3),
                    event("D7", fraction: 0.3, seed: 4), event("G7", fraction: 0.8, seed: 5)]
                chart.systems[0].measures[0].chordEvents = originals

                let rightID = try XCTUnwrap(split(&chart, id: measureID, fraction: 0.5))
                let reopened = try reopen(chart)
                let left = try XCTUnwrap(reopened.measure(id: measureID))
                let right = try XCTUnwrap(reopened.measure(id: rightID))

                XCTAssertEqual(left.chordEvents.map(\.id), Array(originals.prefix(2)).map(\.id))
                for (index, expectedFraction) in [0.2, 0.6].enumerated() {
                    let actual = left.chordEvents[index]
                    assertReceipt(actual, matches: originals[index])
                    XCTAssertFalse(actual.anchorsToMeasureStart)
                    XCTAssertEqual(try XCTUnwrap(actual.manualVisualLaneFraction), expectedFraction, accuracy: 0.0001)
                }
                let singleton = try XCTUnwrap(right.chordEvents.first)
                assertReceipt(singleton, matches: originals[2])
                assertDownbeat(singleton)
                try assertVisibleDownbeat(singleton.id, chart: reopened)
            }
        }
    }

    func testTwoBarlinesUseOriginalPositionBeforeAnchoringFinalSingleton() throws {
        for style in styles {
            for state in authoringStates {
                var chart = makeChart(style, state: state)
                let measureID = chart.measures[0].id
                let original = try event("G7", fraction: 0.8, seed: 6)
                chart.systems[0].measures[0].chordEvents = [original]
                let drafts = [0.4, 0.7].map { fraction in
                    DraftBarline(measureID: measureID, measureIndex: 1, fraction: fraction,
                        layoutPageSize: pageSize, metrics: metrics)
                }
                let state = ChordPreviewState(draftBarlines: drafts, layoutPageSize: pageSize)

                let result = chart.commitChordInkDraftBatch(state)
                let reopened = try reopen(chart)

                XCTAssertEqual(result.renderedBarlineCount, 2)
                XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
                XCTAssertEqual(reopened.measures.count, 3)
                guard reopened.measures.count == 3 else { continue }
                XCTAssertTrue(reopened.measures[0].chordEvents.isEmpty)
                XCTAssertTrue(reopened.measures[1].chordEvents.isEmpty)
                XCTAssertEqual(reopened.measures[2].chordEvents.map(\.id), [original.id],
                    "An intermediate downbeat adjustment must not send the original 0.8 chord into the middle segment")
                let actual = try XCTUnwrap(reopened.chordEvent(id: original.id))
                assertReceipt(actual, matches: original)
                assertDownbeat(actual)
                try assertVisibleDownbeat(actual.id, chart: reopened)
            }
        }
    }

    func testNewDraftInSameResultingMeasurePreventsAnchoringExistingChord() throws {
        for style in styles {
            for authoringState in authoringStates {
                var chart = makeChart(style, state: authoringState)
                let measureID = chart.measures[0].id
                let original = try event("C", fraction: 0.3, seed: 60)
                chart.systems[0].measures[0].chordEvents = [original]
                let originalPageX = try XCTUnwrap(layout(chart).systems.flatMap(\.measures)
                    .flatMap(\.chordLayouts).first { $0.id == original.id }).frame.minX
                let draft = draftInput("D7", measureID: measureID, fraction: 0.15, seed: 61)
                let line = DraftBarline(measureID: measureID, measureIndex: 1, fraction: 0.5,
                    layoutPageSize: pageSize, metrics: metrics)
                let preview = ChordPreviewState(draftChords: [ChordInkDraft(input: draft)],
                    draftBarlines: [line], layoutPageSize: pageSize)

                let result = chart.commitChordInkDraftBatch(preview)
                let reopened = try reopen(chart)

                XCTAssertEqual(result.renderedBarlineCount, 1)
                XCTAssertEqual(result.renderedChordCount, 1)
                XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
                let left = try XCTUnwrap(reopened.measure(id: measureID))
                XCTAssertEqual(left.chordEvents.count, 2,
                    "The singleton decision must use the final measure after its new chord draft renders")
                let actual = try XCTUnwrap(left.chordEvents.first { $0.id == original.id })
                assertReceipt(actual, matches: original)
                XCTAssertFalse(actual.anchorsToMeasureStart)
                if style == .rhythmSectionSheet && authoringState == .committed {
                    XCTAssertNotNil(actual.manualVisualLaneFraction)
                    let actualPageX = try XCTUnwrap(layout(reopened).systems.flatMap(\.measures)
                        .flatMap(\.chordLayouts).first { $0.id == original.id }).frame.minX
                    XCTAssertEqual(actualPageX, originalPageX, accuracy: 0.01,
                        "Committed Rhythm retains the existing glyph's page position when the final measure contains two chords")
                } else {
                    XCTAssertEqual(try XCTUnwrap(actual.manualVisualLaneFraction), 0.6, accuracy: 0.0001)
                }
                XCTAssertTrue(left.chordEvents.contains { $0.id != original.id && $0.rawInput == "D7" })
            }
        }
    }

    func testExistingLeadingDividerDoesNotMoveUnsplitSingleton() throws {
        for style in styles {
            for authoringState in authoringStates {
                var chart = makeChart(style, state: authoringState)
                let measureID = chart.measures[0].id
                let original = try event("G7", fraction: 0.7, seed: 62)
                chart.systems[0].measures[0].chordEvents = [original]
                let line = DraftBarline(measureID: measureID, measureIndex: 1, fraction: 0,
                    layoutPageSize: pageSize, metrics: metrics)

                let result = chart.commitChordInkDraftBatch(ChordPreviewState(
                    draftBarlines: [line], layoutPageSize: pageSize))
                let reopened = try reopen(chart)

                XCTAssertEqual(result.renderedBarlineCount, 1)
                XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
                XCTAssertEqual(reopened.measures.map(\.id), [measureID])
                XCTAssertEqual(reopened.chordEvent(id: original.id), original,
                    "Confirming an existing boundary creates no measure and must not normalize its chord")
            }
        }
    }

    func testSimpleContinuationWaitsForNewDraftBeforeDecidingClosedMeasureIsSingleton() throws {
        var chart = makeChart(.simpleChordSheet, state: .open)
        let measureID = chart.measures[0].id
        let original = try event("C", fraction: 0.3, seed: 63)
        chart.systems[0].measures[0].chordEvents = [original]
        let currentRow = draftInput("D7", measureID: measureID, fraction: 0.7, seed: 64,
            laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.7))
        let nextRow = draftInput("F7", measureID: measureID, fraction: 0.3, seed: 65,
            laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.3))
        let preview = ChordPreviewState(draftChords: [currentRow, nextRow].map { ChordInkDraft(input: $0) },
            layoutPageSize: pageSize)

        let result = chart.commitChordInkDraftBatch(preview)
        let reopened = try reopen(chart)

        XCTAssertEqual(result.renderedChordCount, 2)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(reopened.measures.count, 2)
        let closed = try XCTUnwrap(reopened.measure(id: measureID))
        XCTAssertEqual(closed.authoringState, .committed)
        XCTAssertEqual(closed.chordEvents.count, 2)
        XCTAssertEqual(reopened.chordEvent(id: original.id), original,
            "Materializing the next row must not anchor a provisional singleton before the current-row draft is inserted")
        XCTAssertTrue(closed.chordEvents.contains { $0.id != original.id && $0.rawInput == "D7" })
        XCTAssertEqual(reopened.measures.last?.chordEvents.first?.rawInput, "F7")
    }

    func testAutomaticAndManualBarlineTransactionsKeepRetroactiveDownbeatsVisible() throws {
        for style in styles {
            for authoringState in authoringStates {
                for manual in [true, false] {
                    var chart = makeChart(style, state: authoringState)
                    let originals = try [event("C", fraction: 0.18, seed: 7),
                        event("G7", fraction: 0.78, seed: 8)]
                    chart.systems[0].measures[0].chordEvents = originals
                    let sourceLayout = layout(chart)
                    let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
                    let system = try XCTUnwrap(sourceLayout.systems.first)
                    let measure = try XCTUnwrap(system.measures.first)
                    let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                        for: system, paperFrame: sourceLayout.paperFrame(for: system)))
                    let x = measure.staffFrame.midX - sourceFrame.minX
                    let source = LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: [stroke([
                        CGPoint(x: x, y: lane.minY + lane.height * 0.08 - sourceFrame.minY),
                        CGPoint(x: x, y: lane.maxY - lane.height * 0.08 - sourceFrame.minY)
                    ], seed: 40)]))
                    let coordinateSpace = PersistentInkCoordinateSpace(size: sourceFrame.size)
                    _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation(), coordinateSpace: coordinateSpace)
                    let preparation = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(),
                        scheduledAt: inputAt, requestedDelay: 0, drawingData: source.dataRepresentation(),
                        chordFrame: sourceFrame, pageLayout: sourceLayout, flow: .draftPreview,
                        options: .live, layoutStyle: style))
                    XCTAssertEqual(preparation.barlines.count, 1)
                    XCTAssertEqual(preparation.recognitionStrokeCount, 0)
                    let preview = ChordPreviewState(draftBarlines: preparation.barlines, layoutPageSize: pageSize)
                    let outcome: ChordInkDraftRenderCoordinator.Outcome
                    if manual {
                        outcome = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: preview,
                            currentDrawing: source, coordinateSpace: coordinateSpace,
                            sourcePageLayout: sourceLayout, sourceChordFrame: sourceFrame)
                    } else {
                        let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: preview,
                            currentDrawing: source, coordinateSpace: coordinateSpace,
                            now: inputAt.addingTimeInterval(10), lastInputAt: inputAt, isUsingTool: false,
                            sourcePageLayout: sourceLayout, sourceChordFrame: sourceFrame)
                        outcome = ChordInkDraftRenderCoordinator.explicitOutcome(try XCTUnwrap(attempt.outcome,
                            "\(style.rawValue), \(authoringState.rawValue): \(attempt.feedback)"))
                    }

                    XCTAssertTrue(outcome.canConsumeSource)
                    XCTAssertEqual(outcome.result.renderedBarlineCount, 1)
                    XCTAssertEqual(outcome.chart.measures.count, 2)
                    XCTAssertNil(outcome.chart.pageHandwrittenChordData)
                    let reopened = try reopen(outcome.chart)
                    for original in originals {
                        let actual = try XCTUnwrap(reopened.chordEvent(id: original.id))
                        assertReceipt(actual, matches: original)
                        assertDownbeat(actual)
                        try assertVisibleDownbeat(actual.id, chart: reopened)
                    }
                }
            }
        }
    }

    func testClosingOpenMeasureAnchorsItsOnlyChordAndPreservesReceipts() throws {
        for style in styles {
            var chart = makeChart(style, state: .open)
            let measureID = chart.measures[0].id
            let original = try event("F7", fraction: 0.68, seed: 9)
            chart.systems[0].measures[0].chordEvents = [original]

            let nextID = try XCTUnwrap(chart.commitOpenMeasure(barlineAfter: .double))
            let reopened = try reopen(chart)

            XCTAssertEqual(reopened.measures.map(\.id), [measureID, nextID])
            XCTAssertEqual(reopened.measures[0].authoringState, .committed)
            XCTAssertEqual(reopened.measures[0].barlineAfter, .double)
            XCTAssertEqual(reopened.measures[1].authoringState, .open)
            XCTAssertTrue(reopened.measures[1].chordEvents.isEmpty)
            let actual = try XCTUnwrap(reopened.chordEvent(id: original.id))
            assertReceipt(actual, matches: original)
            assertDownbeat(actual)
            try assertVisibleDownbeat(actual.id, chart: reopened)
        }
    }

    func testClosingOpenMeasureLeavesMultipleChordPlacementsUntouched() throws {
        for style in styles {
            var chart = makeChart(style, state: .open)
            let originals = try [event("C", fraction: 0.2, seed: 10),
                event("G7", fraction: 0.7, seed: 11)]
            chart.systems[0].measures[0].chordEvents = originals

            XCTAssertNotNil(chart.commitOpenMeasure())

            XCTAssertEqual(try reopen(chart).measures[0].chordEvents, originals)
        }
    }

    func testTimedRhythmSplitMovesOnlyHarmonyToOpeningRestAndPreservesNotesAndTies() throws {
        var chart = makeChart(.rhythmSectionSheet, state: .committed)
        let measureID = chart.measures[0].id
        let values: [RhythmValue] = [.quarterRest, .eighth, .eighth, .quarter, .quarter]
        chart.systems[0].measures[0].rhythmMap = MeasureRhythmMap(values: values, tieOutSlotIndices: [1])
        let notes = [1, 2, 4].enumerated().map { index, slot in
            LeadSheetPitchedNoteEvent(rhythmSlotIndex: slot,
                staffPosition: LeadSheetStaffPosition(staffStep: index * 2),
                sourceInkData: drawing(seed: 50 + index).dataRepresentation())
        }
        chart.systems[0].measures[0].pitchedNoteEvents = notes
        var original = try event("F7", fraction: 0.35, seed: 12)
        original.startPosition = BeatPosition(beat: 2, subdivision: 1, subdivisionsPerBeat: 2)
        original.duration = .eighth
        original.mappedRhythmSlotIndex = 2
        chart.systems[0].measures[0].chordEvents = [original]

        let rightID = try XCTUnwrap(chart.splitCommittedRhythmSectionMeasure(measureID, atFraction: 0.5,
            visualChordFractions: [original.id: 0.35]))
        let reopened = try reopen(chart)
        let left = try XCTUnwrap(reopened.measure(id: measureID))
        let right = try XCTUnwrap(reopened.measure(id: rightID))

        XCTAssertEqual(left.rhythmMap?.values, [.quarterRest, .eighth, .eighth, .halfRest])
        XCTAssertEqual(right.rhythmMap?.values, [.quarter, .quarter, .halfRest])
        XCTAssertEqual(left.rhythmMap?.tieOutSlotIndices, [1])
        XCTAssertEqual(right.rhythmMap?.tieOutSlotIndices, [])
        XCTAssertEqual(left.pitchedNoteEvents, Array(notes.prefix(2)))
        var movedNote = notes[2]
        movedNote.rhythmSlotIndex = 1
        XCTAssertEqual(right.pitchedNoteEvents, [movedNote])
        let actual = try XCTUnwrap(left.chordEvents.first)
        assertReceipt(actual, matches: original)
        assertDownbeat(actual)
        XCTAssertNil(actual.mappedRhythmSlotIndex, "A chord above the opening rest must not keep its old sounding-note slot")
        let placed = try XCTUnwrap(layout(reopened).systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
        let openingRest = try XCTUnwrap(placed.noteLayouts.first)
        XCTAssertEqual(openingRest.symbolStyle, .quarterRest)
        try assertVisibleDownbeat(actual.id, chart: reopened)
    }

    private func makeChart(_ style: ChartLayoutStyle, state: MeasureAuthoringState) -> Chart {
        var chart = Chart.blank(title: "Retroactive downbeat", measureCount: 1, layoutStyle: style)
        chart.systems[0].measures[0].authoringState = state
        chart.systems[0].measures[0].manualLayoutWidth = 600
        return chart
    }

    private func event(_ text: String, fraction: Double, seed: Int) throws -> ChordEvent {
        ChordEvent(id: UUID(), symbol: try ChordSymbolParser.parse(text),
            spellingIntent: .explicit, startPosition: BeatPosition(beat: 3, subdivision: 1, subdivisionsPerBeat: 2),
            duration: .half, rhythmPlacement: .inline, tieOut: true, hitStyle: .accent,
            rawInput: text, sourceInkData: drawing(seed: seed).dataRepresentation(),
            sourceCandidateSignature: [text, "C△7"], sourceRecognitionPipelineVersion: "downbeat-test",
            manualDisplayWidth: 44, manualLaneFraction: fraction, manualVisualLaneFraction: fraction)
    }

    private func draftInput(_ text: String, measureID: UUID, fraction: Double, seed: Int,
        laneLocation: ChordInkDraftLaneLocation? = nil) -> ChordInkDraftInput {
        ChordInkDraftInput(measureID: measureID, measureIndex: 1, targetFraction: fraction,
            laneLocation: laneLocation, layoutPageSize: pageSize,
            drawingData: drawing(seed: seed).dataRepresentation(), candidateTexts: [text],
            bestCandidateText: text, confidence: 4.5, strokeCount: 1)
    }

    private func split(_ chart: inout Chart, id: UUID, fraction: Double) -> UUID? {
        if chart.layoutStyle == .simpleChordSheet {
            return chart.splitSimpleChordMeasure(id, atFraction: fraction)
        }
        if chart.measure(id: id)?.authoringState == .open {
            return chart.splitOpenRhythmSectionMeasure(id, atFraction: fraction)
        }
        return chart.splitCommittedRhythmSectionMeasure(id, atFraction: fraction)
    }

    private func assertDownbeat(_ event: ChordEvent, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(event.startPosition.beat, 1, file: file, line: line)
        XCTAssertEqual(event.startPosition.subdivision, 0, file: file, line: line)
        XCTAssertTrue(event.anchorsToMeasureStart, file: file, line: line)
        XCTAssertNil(event.manualLaneFraction, file: file, line: line)
        XCTAssertNil(event.manualVisualLaneFraction, file: file, line: line)
    }

    private func assertReceipt(_ actual: ChordEvent, matches original: ChordEvent,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, original.id, file: file, line: line)
        XCTAssertEqual(actual.symbol, original.symbol, file: file, line: line)
        XCTAssertEqual(actual.rawInput, original.rawInput, file: file, line: line)
        XCTAssertEqual(actual.sourceInkData, original.sourceInkData, file: file, line: line)
        XCTAssertEqual(actual.sourceCandidateSignature, original.sourceCandidateSignature, file: file, line: line)
        XCTAssertEqual(actual.sourceRecognitionPipelineVersion, original.sourceRecognitionPipelineVersion, file: file, line: line)
        XCTAssertEqual(actual.duration, original.duration, file: file, line: line)
        XCTAssertEqual(actual.tieOut, original.tieOut, file: file, line: line)
        XCTAssertEqual(actual.hitStyle, original.hitStyle, file: file, line: line)
        XCTAssertEqual(actual.rhythmPlacement, original.rhythmPlacement, file: file, line: line)
        XCTAssertEqual(actual.manualDisplayWidth, original.manualDisplayWidth, file: file, line: line)
        XCTAssertEqual(actual.spellingIntent, original.spellingIntent, file: file, line: line)
        XCTAssertEqual(actual.spellingOverrideSource, original.spellingOverrideSource, file: file, line: line)
    }

    private func assertVisibleDownbeat(_ id: UUID, chart: Chart,
        file: StaticString = #filePath, line: UInt = #line) throws {
        for size in [pageSize, CGSize(width: 1_400, height: 900)] {
            let measure = try XCTUnwrap(layout(chart, size: size).systems.flatMap(\.measures).first {
                $0.chordLayouts.contains { $0.id == id }
            }, file: file, line: line)
            let glyph = try XCTUnwrap(measure.chordLayouts.first { $0.id == id }, file: file, line: line)
            XCTAssertFalse(glyph.usesManualVisualPlacement, file: file, line: line)
            if chart.layoutStyle == .simpleChordSheet {
                let guide = LeadSheetChordPlacementGuidePolicy.guideFrame(
                    for: measure, referenceFrame: measure.chordBandFrame)
                XCTAssertEqual(glyph.snapGuideTarget.x, guide.minX, accuracy: 0.01,
                    "A lone Simple chord must use the first beat guide after reserved leading artifacts",
                    file: file, line: line)
            } else {
                let model = try XCTUnwrap(measure.sourceMeasureID.flatMap { chart.measure(id: $0) },
                    file: file, line: line)
                let meter = model.resolvedMeter(defaultMeter: chart.defaultMeter)
                let placement = try XCTUnwrap(model.renderedChordPlacements(defaultMeter: chart.defaultMeter)
                    .first { $0.id == id }, file: file, line: line)
                let durationLength = max(0, (placement.duration ?? .quarter).wholeNoteLength(in: meter))
                let attackLength = durationLength > 0
                    ? min(durationLength, meter.beatUnitWholeNoteLength)
                    : meter.beatUnitWholeNoteLength
                let expectedX = measure.staffFrame.minX + 8
                    + (measure.staffFrame.width - 16)
                        * CGFloat(attackLength / (2 * meter.measureLengthInWholeNotes))
                XCTAssertEqual(glyph.snapGuideTarget.x, expectedX, accuracy: 0.01,
                    "A Rhythm downbeat uses the first attack center for the chord's retained duration",
                    file: file, line: line)
            }
        }
    }

    private func layout(_ chart: Chart, size: CGSize? = nil) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size ?? pageSize,
            includesChordInkContinuationLanes: true)
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
    }

    private var metrics: DraftBarlineGestureMetrics {
        .init(height: 54, width: 2, angleDegreesFromVertical: 1, straightness: 0.98, laneCoverage: 0.9)
    }

    private func drawing(seed: Int) -> PKDrawing {
        LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: [stroke([
            CGPoint(x: 10, y: 12), CGPoint(x: 14, y: 24), CGPoint(x: 23, y: 15)
        ], seed: seed)]))
    }

    private func stroke(_ points: [CGPoint], seed: Int) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 2.5, height: 2.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
    }
}
#endif
