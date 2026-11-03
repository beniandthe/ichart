#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkStructuralAutomaticRenderTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)

    func testCompleteSingleBarlineRendersAutomaticallyWithoutAnyChordDraft() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style)
            let fixture = try fixture(chart)
            let drawing = PKDrawing(strokes: strokes(.single, x: fixture.lane.midX, fixture: fixture))
            let source = try install(drawing, in: &chart, fixture: fixture)
            XCTAssertTrue(source.state.draftChords.isEmpty)
            XCTAssertEqual(source.state.draftBarlines.count, 1)
            let original = chart

            let rendered = try XCTUnwrap(attempt(chart, source, elapsed: 4).outcome, style.rawValue)
            XCTAssertEqual(rendered.result.renderedBarlineCount, 1)
            XCTAssertEqual(rendered.result.renderedChordCount, 0)
            XCTAssertEqual(rendered.chart.measures.count, 2)
            XCTAssertTrue(rendered.drawing.strokes.isEmpty)
            XCTAssertTrue(rendered.remainingState.isEmpty)
            XCTAssertEqual(rendered.consumedDraftIDs, Set(source.state.draftBarlines.map(\.id)))
            XCTAssertNil(rendered.chart.pageHandwrittenChordData)
            XCTAssertEqual(chart, original, "The automatic preparation remains a value transaction")
        }
    }

    func testPlainBarlinesExtendShortRhythmRowWithoutMovingItsChordsOrStaffInk() throws {
        var chart = makeChart(.rhythmSectionSheet, startingMeasureCount: 8)
        chart.setEngravingPreset(.bold)
        let originalIDs = chart.measures.map(\.id)
        let tailID = originalIDs[3]
        XCTAssertTrue(chart.insertSystemBreak(before: tailID))
        XCTAssertTrue(chart.insertSystemBreak(before: originalIDs[4]))
        for id in originalIDs.prefix(4) { _ = chart.setMeasureManualLayoutWidth(184, for: id) }
        _ = chart.setMeasureManualLayoutWidth(147.2, for: originalIDs[4])

        let source = PKDrawing(strokes: [stroke([CGPoint(x: 12, y: 12), CGPoint(x: 24, y: 35)])])
        for (text, fraction) in [("C", 0.08), ("G", 0.48), ("F", 0.96)] {
            let match = try XCTUnwrap(ChordRecognitionCompendium.match(text))
            let id = try XCTUnwrap(chart.appendRecognizedChordEvent(match.symbol, rawInput: text,
                to: tailID, atFraction: fraction, sourceInkData: source.dataRepresentation()))
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(id, to: tailID, atFraction: nil,
                visualFraction: fraction, preserveMusicalPlacement: true))
        }
        let originalTail = try XCTUnwrap(chart.measure(id: tailID))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let row = try XCTUnwrap(layout.systems.first { $0.measures.last?.sourceMeasureID == tailID })
        let tail = try XCTUnwrap(row.measures.last)
        XCTAssertEqual(row.measures.compactMap(\.sourceMeasureID), [tailID])
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: row, paperFrame: layout.paperFrame(for: row)))
        let fixture = Fixture(layout: layout, system: row,
            chordFrame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), lane: lane)
        let pageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        let staff = try XCTUnwrap(layout.systems.first?.measures.first?.staffFrame)
        let staffStroke = stroke([
            CGPoint(x: staff.minX + 20 - pageFrame.minX, y: staff.midY - pageFrame.minY),
            CGPoint(x: staff.minX + 28 - pageFrame.minX, y: staff.midY - 15 - pageFrame.minY)
        ])
        let staffSpace = LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(for: layout, relativeTo: pageFrame)
        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(
            PKDrawing(strokes: [staffStroke]).dataRepresentation(), coordinateSpace: staffSpace))
        let staffInk = try XCTUnwrap(chart.pageHandwrittenNotationData)

        // The iPad wrote three vertical separators beyond the existing row,
        // out of chronological order and closer than the manual resize floor.
        let positions = [50.5, 108.0, 181.5].map { tail.trailingBarlineFrame.midX + $0 }
        let drawing = PKDrawing(strokes: [positions[0], positions[2], positions[1]].flatMap {
            strokes(.single, x: $0, fixture: fixture)
        })
        let input = try prepareBarline(drawing, chart: &chart, fixture: fixture, expectedCount: 3)
        XCTAssertEqual(input.state.draftBarlines.map(\.kind), [.single, .single, .single])
        XCTAssertEqual(input.state.draftBarlines.map(\.measureID), [tailID, tailID, tailID])
        let manual = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: input.state,
            currentDrawing: input.drawing, coordinateSpace: .init(size: fixture.chordFrame.size))
        XCTAssertTrue(manual.canConsumeSource)
        XCTAssertEqual(manual.result.renderedBarlineCount, 3)
        let result = try XCTUnwrap(attempt(chart, input, elapsed: 4).outcome)
        XCTAssertEqual(result.result.renderedBarlineCount, 3)
        XCTAssertTrue(result.drawing.strokes.isEmpty)
        XCTAssertNil(result.chart.pageHandwrittenChordData)
        XCTAssertEqual(result.chart.measure(id: tailID), originalTail)
        XCTAssertEqual(result.chart.pageHandwrittenNotationData, staffInk)
        XCTAssertEqual(result.chart.pageHandwrittenNotationCoordinateSpace, staffSpace)
        XCTAssertEqual(result.chart.measures.filter { originalIDs.contains($0.id) }.map(\.id), originalIDs)
        XCTAssertEqual(result.chart.measures.filter { $0.authoringState == .open }.map(\.id), [originalIDs[7]])
        XCTAssertTrue(result.chart.systems.contains {
            $0.lineBreakRule == .forced && $0.measures.first?.id == originalIDs[4]
        })

        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(result.chart))
        XCTAssertEqual(reopened, result.chart)
        let reopenedLayout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let reopenedRow = try XCTUnwrap(reopenedLayout.systems.first { $0.index == row.index })
        XCTAssertEqual(reopenedRow.measures.first?.sourceMeasureID, tailID)
        XCTAssertEqual(reopenedRow.measures.first?.chordLayouts, tail.chordLayouts)
        XCTAssertEqual(reopenedRow.measures.count, 4)
        for (new, expected) in zip(reopenedRow.measures.dropFirst(), positions) {
            XCTAssertEqual(new.trailingBarlineFrame.midX, expected, accuracy: 0.01)
        }

        var dividerChart = chart
        let dividerInput = try prepareBarline(PKDrawing(strokes: strokes(.single,
            x: tail.trailingBarlineFrame.midX + 1, fixture: fixture)), chart: &dividerChart, fixture: fixture)
        XCTAssertNil(attempt(dividerChart, dividerInput, elapsed: 4).outcome)
        let refused = ChordInkDraftRenderCoordinator.prepare(chart: dividerChart, state: dividerInput.state,
            currentDrawing: dividerInput.drawing, coordinateSpace: .init(size: fixture.chordFrame.size))
        XCTAssertFalse(refused.canConsumeSource)
        XCTAssertEqual(refused.chart, dividerChart)
    }

    func testStructuralGraceCannotBeShortenedBySpatialCompletionAndResetsForNewInput() throws {
        var chart = makeChart()
        let fixture = try fixture(chart)
        let source = try install(PKDrawing(strokes: strokes(.single, x: fixture.lane.midX, fixture: fixture)),
            in: &chart, fixture: fixture)
        XCTAssertEqual(ChordInkAutomaticRenderPolicy.requiredIdleDelay(for: .init()), 1.2)
        XCTAssertEqual(ChordInkAutomaticRenderPolicy.requiredIdleDelay(for: source.state), 2)
        for elapsed in [0.4, 1.2, 1.99] {
            let early = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: source.state,
                currentDrawing: source.drawing, coordinateSpace: .init(size: fixture.chordFrame.size),
                now: inputAt.addingTimeInterval(elapsed), lastInputAt: inputAt, isUsingTool: false,
                allowsImmediateSpatialCompletion: true, sourcePageLayout: fixture.layout,
                sourceChordFrame: fixture.chordFrame)
            XCTAssertNil(early.outcome, "A horizontal gap must not consume the vertical stroke before repeat dots arrive")
            XCTAssertEqual(early.feedback.globalReason, .waiting)
        }
        XCTAssertNotNil(attempt(chart, source, elapsed: 2).outcome)
        let reset = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: source.state,
            currentDrawing: source.drawing, coordinateSpace: .init(size: fixture.chordFrame.size),
            now: inputAt.addingTimeInterval(3.5), lastInputAt: inputAt.addingTimeInterval(2), isUsingTool: false,
            sourcePageLayout: fixture.layout, sourceChordFrame: fixture.chordFrame)
        XCTAssertNil(reset.outcome, "The next stroke restarts the complete structural pause")
    }

    func testExplicitManualStructuralRenderDoesNotInheritAutomaticGrace() throws {
        var chart = makeChart()
        let fixture = try fixture(chart)
        let source = try install(PKDrawing(strokes: strokes(.single, x: fixture.lane.midX, fixture: fixture)),
            in: &chart, fixture: fixture)
        XCTAssertNil(attempt(chart, source, elapsed: 0.4).outcome)
        let manual = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: source.state,
            currentDrawing: source.drawing, coordinateSpace: .init(size: fixture.chordFrame.size))
        XCTAssertTrue(manual.canConsumeSource)
        XCTAssertEqual(manual.result.renderedBarlineCount, 1)
    }

    func testPairedRepeatSignsRenderAutomaticallyAndArchiveExactSource() throws {
        var chart = makeChart()
        let fixture = try fixture(chart)
        let drawing = PKDrawing(strokes:
            strokes(.repeatStart, x: fixture.lane.minX + fixture.lane.width * 0.25, fixture: fixture)
            + strokes(.repeatEnd, x: fixture.lane.minX + fixture.lane.width * 0.75, fixture: fixture))
        let source = try install(drawing, in: &chart, fixture: fixture)
        XCTAssertEqual(source.state.draftBarlines.map(\.kind), [.repeatStart, .repeatEnd])

        let rendered = try XCTUnwrap(attempt(chart, source, elapsed: 4).outcome)
        XCTAssertEqual(rendered.result.renderedBarlineCount, 2)
        XCTAssertEqual(rendered.chart.measures.count, 3)
        let span = try XCTUnwrap(rendered.chart.roadmapObjects.first { $0.type == .repeatSpan })
        let archived = try PKDrawing(data: XCTUnwrap(span.sourceInkData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: source.drawing, current: archived))
        XCTAssertNil(rendered.chart.pageHandwrittenChordData)
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(rendered.chart))
        XCTAssertEqual(reopened, rendered.chart)
    }

    func testSlantedBarlineBetweenRenderedChordsRoutesToStructureAndPreservesChords() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style)
            let firstID = try XCTUnwrap(chart.measures.first?.id)
            let archivedInk = PKDrawing(strokes: [stroke([CGPoint(x: 12, y: 12), CGPoint(x: 24, y: 35)])])
            let c = try XCTUnwrap(ChordRecognitionCompendium.match("C"))
            let g = try XCTUnwrap(ChordRecognitionCompendium.match("G7"))
            let cID = try XCTUnwrap(chart.appendRecognizedChordEvent(c.symbol, rawInput: "C", to: firstID,
                atFraction: 0.2, sourceInkData: archivedInk.dataRepresentation()))
            let gID = try XCTUnwrap(chart.appendRecognizedChordEvent(g.symbol, rawInput: "G7", to: firstID,
                atFraction: 0.2, sourceInkData: archivedInk.dataRepresentation()))
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(cID, to: firstID, atFraction: nil,
                visualFraction: 0.25, preserveMusicalPlacement: true))
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(gID, to: firstID, atFraction: nil,
                visualFraction: 0.75, preserveMusicalPlacement: true))
            let gIndex = try XCTUnwrap(chart.systems[0].measures[0].chordEvents.firstIndex { $0.id == gID })
            chart.systems[0].measures[0].chordEvents[gIndex].duration = .half
            chart.systems[0].measures[0].chordEvents[gIndex].tieOut = true
            let originalEvents = Dictionary(uniqueKeysWithValues: chart.measures.flatMap(\.chordEvents).map { ($0.id, $0) })
            let fixture = try fixture(chart)
            let chordFrames = fixture.system.measures.flatMap(\.chordLayouts)
                .map { $0.frame.union($0.naturalFrame) }
                .sorted { $0.minX < $1.minX }
            XCTAssertEqual(chordFrames.count, 2)
            let left = try XCTUnwrap(chordFrames.first)
            let right = try XCTUnwrap(chordFrames.last)
            let gapX = (left.maxX + right.minX) / 2
            let drawing = slantedBarline(at: gapX, fixture: fixture)
            let overlapping = slantedBarline(at: left.midX, fixture: fixture)
            let overlappingResult = ChordDraftBarlineRecognizer.recognize(
                strokes: PencilKitInkAdapter.inkStrokes(from: overlapping), chordFrame: fixture.chordFrame,
                pageLayout: fixture.layout)
            XCTAssertTrue(overlappingResult.barlines.isEmpty, "The relaxed shape must fit between rendered chords")
            let source = try prepareBarline(drawing, chart: &chart, fixture: fixture)
            let beforeFrames = Dictionary(uniqueKeysWithValues: fixture.layout.systems.flatMap(\.measures)
                .flatMap(\.chordLayouts).map { ($0.id, $0.naturalFrame) })

            let manual = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: source.state,
                currentDrawing: source.drawing, coordinateSpace: .init(size: fixture.chordFrame.size))
            XCTAssertTrue(manual.canConsumeSource, style.rawValue)
            XCTAssertEqual(manual.result.renderedBarlineCount, 1)
            XCTAssertEqual(manual.result.renderedChordCount, 0)
            XCTAssertEqual(manual.chart.measures.flatMap(\.chordEvents).map(\.id), [cID, gID])

            let rendered = try XCTUnwrap(attempt(chart, source, elapsed: 4).outcome)
            XCTAssertEqual(rendered.result.renderedBarlineCount, 1)
            XCTAssertEqual(rendered.result.renderedChordCount, 0)
            let events = Dictionary(uniqueKeysWithValues: rendered.chart.measures.flatMap(\.chordEvents).map { ($0.id, $0) })
            XCTAssertEqual(Set(events.keys), Set([cID, gID]))
            for id in [cID, gID] {
                XCTAssertEqual(events[id]?.sourceInkData, originalEvents[id]?.sourceInkData)
                XCTAssertEqual(events[id]?.rawInput, originalEvents[id]?.rawInput)
                XCTAssertEqual(events[id]?.symbol, originalEvents[id]?.symbol)
                XCTAssertEqual(events[id]?.startPosition, originalEvents[id]?.startPosition)
                XCTAssertEqual(events[id]?.duration, originalEvents[id]?.duration)
                XCTAssertEqual(events[id]?.rhythmPlacement, originalEvents[id]?.rhythmPlacement)
                var expected = try XCTUnwrap(originalEvents[id])
                expected.manualVisualLaneFraction = events[id]?.manualVisualLaneFraction
                XCTAssertEqual(events[id], expected, "Only the visual fraction may change within the redistributed event")
            }
            XCTAssertEqual(rendered.chart.measures.count, 2)
            XCTAssertEqual(rendered.chart.measures[0].chordEvents.map(\.id), [cID])
            XCTAssertEqual(rendered.chart.measures[1].chordEvents.map(\.id), [gID],
                "The visible glyph position must choose its segment even when its provisional beat slot is on the left")
            let afterLayout = LeadSheetPageLayoutEngine.pageLayout(for: rendered.chart, pageSize: pageSize,
                includesChordInkContinuationLanes: true)
            let afterFrames = Dictionary(uniqueKeysWithValues: afterLayout.systems.flatMap(\.measures)
                .flatMap(\.chordLayouts).map { ($0.id, $0.naturalFrame) })
            for id in [cID, gID] {
                XCTAssertEqual(try XCTUnwrap(afterFrames[id]).minX, try XCTUnwrap(beforeFrames[id]).minX, accuracy: 0.01)
            }
            XCTAssertEqual(try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(rendered.chart)), rendered.chart)
            XCTAssertTrue(rendered.drawing.strokes.isEmpty)
        }
    }

    private func slantedBarline(at x: CGFloat, fixture: Fixture) -> PKDrawing {
        let center = CGPoint(x: x - fixture.chordFrame.minX, y: fixture.lane.midY - fixture.chordFrame.minY)
        let halfHeight = fixture.lane.height * 0.42
        let halfWidth = halfHeight * 0.38
        return PKDrawing(strokes: [stroke([
            CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
            CGPoint(x: center.x + halfWidth, y: center.y + halfHeight)
        ])])
    }

    func testSlantedBarlineToleranceDoesNotCreateSplitAtExistingMeasureBoundary() throws {
        var chart = makeChart(startingMeasureCount: 2)
        let c = try XCTUnwrap(ChordRecognitionCompendium.match("C"))
        let g = try XCTUnwrap(ChordRecognitionCompendium.match("G7"))
        let firstID = chart.measures[0].id
        let secondID = chart.measures[1].id
        _ = try XCTUnwrap(chart.appendRecognizedChordEvent(c.symbol, rawInput: "C", to: firstID, atFraction: 0.25))
        _ = try XCTUnwrap(chart.appendRecognizedChordEvent(g.symbol, rawInput: "G7", to: secondID, atFraction: 0.75))
        let fixture = try fixture(chart)
        let first = try XCTUnwrap(fixture.system.measures.first { $0.id == firstID })
        let drawing = slantedBarline(at: first.trailingBarlineFrame.midX, fixture: fixture)

        let result = ChordDraftBarlineRecognizer.recognize(
            strokes: PencilKitInkAdapter.inkStrokes(from: drawing), chordFrame: fixture.chordFrame,
            pageLayout: fixture.layout)

        XCTAssertTrue(result.barlines.isEmpty)
    }

    private func prepareBarline(
        _ drawing: PKDrawing, chart: inout Chart, fixture: Fixture, expectedCount: Int = 1
    ) throws -> Input {
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let data = try XCTUnwrap(chart.pageHandwrittenChordData)
        let prepared = ChordInkRecognitionPreparation.prepare(ChordInkRecognitionPreparationRequest(
            requestID: UUID(), scheduledAt: inputAt, requestedDelay: 0, drawingData: data,
            chordFrame: fixture.chordFrame, pageLayout: fixture.layout, flow: .draftPreview,
            options: .live, layoutStyle: chart.layoutStyle))
        XCTAssertEqual(prepared.recognitionStrokeCount, 0, "Barline ink must stay out of chord recognition")
        XCTAssertEqual(prepared.barlines.count, expectedCount)
        XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), Set(0..<expectedCount))
        let state = ChordPreviewState(draftBarlines: prepared.barlines, layoutPageSize: pageSize)
        return Input(drawing: try PKDrawing(data: data), state: state, fixture: fixture)
    }
    func testExistingRepeatReceiptIsUnchangedWhenAnotherPairRenders() throws {
        var chart = makeChart(startingMeasureCount: 2)
        let firstID = chart.measures[0].id
        let existingID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: firstID, endMeasureID: firstID))
        let existingSource = PKDrawing(strokes: [stroke([CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 40)])]).dataRepresentation()
        let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == existingID })
        chart.roadmapObjects[index].sourceInkData = existingSource
        let original = chart.roadmapObjects[index]
        let fixture = try fixture(chart)
        let last = try XCTUnwrap(fixture.system.measures.last)
        let drawing = PKDrawing(strokes:
            strokes(.repeatStart, x: last.frame.minX + last.frame.width * 0.25, fixture: fixture)
            + strokes(.repeatEnd, x: last.frame.minX + last.frame.width * 0.75, fixture: fixture))
        let source = try install(drawing, in: &chart, fixture: fixture)

        let rendered = try XCTUnwrap(attempt(chart, source, elapsed: 4).outcome)
        XCTAssertEqual(rendered.chart.roadmapObjects.first { $0.id == existingID }, original)
        XCTAssertEqual(rendered.chart.roadmapObjects.filter { $0.type == .repeatSpan }.count, 2)
        XCTAssertTrue(rendered.drawing.strokes.isEmpty)
    }

    func testNewRepeatDotCannotBeConsumedFromEarlierSingleBarlinePreview() throws {
        var chart = makeChart()
        let fixture = try fixture(chart)
        let line = PKDrawing(strokes: strokes(.single, x: fixture.lane.midX, fixture: fixture))
        let source = try install(line, in: &chart, fixture: fixture)
        let original = chart
        let extraDot = stroke([CGPoint(x: fixture.lane.midX - fixture.chordFrame.minX + 10,
            y: fixture.lane.midY - fixture.chordFrame.minY - 8)], size: 1.4)
        let live = PKDrawing(strokes: source.drawing.strokes + [extraDot])
        let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: source.state,
            currentDrawing: live, coordinateSpace: .init(size: fixture.chordFrame.size),
            now: inputAt.addingTimeInterval(4), lastInputAt: inputAt, isUsingTool: false,
            sourcePageLayout: fixture.layout, sourceChordFrame: fixture.chordFrame)
        XCTAssertNil(attempt.outcome)
        XCTAssertEqual(chart, original)
        XCTAssertEqual(live.strokes.count, 2)
    }

    func testActiveToolAndStaleBarlineGeometryCannotConsumeStructuralSource() throws {
        var chart = makeChart()
        let fixture = try fixture(chart)
        let drawing = PKDrawing(strokes: strokes(.single, x: fixture.lane.midX, fixture: fixture))
        let source = try install(drawing, in: &chart, fixture: fixture)
        let original = chart
        XCTAssertNil(attempt(chart, source, elapsed: 4, isUsingTool: true).outcome)
        let changed = PKDrawing(strokes: strokes(.single, x: fixture.lane.midX + 3, fixture: fixture))
        let stale = Input(drawing: changed, state: source.state, fixture: fixture)
        XCTAssertNil(attempt(chart, stale, elapsed: 4).outcome)
        XCTAssertEqual(chart, original)
    }

    func testUnpairedRepeatSignsRemainExplicitChoicesAfterGrace() throws {
        for kind in [DraftBarlineKind.repeatStart, .repeatEnd] {
            var chart = makeChart()
            let fixture = try fixture(chart)
            let source = try install(PKDrawing(strokes: strokes(kind, x: fixture.lane.midX, fixture: fixture)),
                in: &chart, fixture: fixture)
            let original = chart
            let outcome = attempt(chart, source, elapsed: 4)
            XCTAssertNil(outcome.outcome)
            XCTAssertEqual(outcome.feedback.globalReason, .repeatReview)
            XCTAssertEqual(chart, original)
            XCTAssertEqual(source.drawing.strokes.count, 3)
        }
    }

    func testSplitBoundaryAssignsPinnedChordToRightWithoutDuplicatingSourceOrTiming() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = makeChart(style)
            let measureID = chart.measures[0].id
            let source = PKDrawing(strokes: [stroke([CGPoint(x: 12, y: 12), CGPoint(x: 20, y: 32)])])
            let match = try XCTUnwrap(ChordRecognitionCompendium.match("F"))
            let id = try XCTUnwrap(chart.appendRecognizedChordEvent(match.symbol, rawInput: "F", to: measureID,
                atFraction: 0.1, sourceInkData: source.dataRepresentation()))
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(id, to: measureID, atFraction: nil,
                visualFraction: 0.5, preserveMusicalPlacement: true))
            let original = try XCTUnwrap(chart.measure(id: measureID)?.chordEvents.first)
            _ = chart.setMeasureManualLayoutWidth(300, for: measureID)
            let rightID = try XCTUnwrap(style == .simpleChordSheet
                ? chart.splitSimpleChordMeasure(measureID, atFraction: 0.5)
                : chart.splitOpenRhythmSectionMeasure(measureID, atFraction: 0.5))
            XCTAssertTrue(try XCTUnwrap(chart.measure(id: measureID)).chordEvents.isEmpty)
            let right = try XCTUnwrap(chart.measure(id: rightID))
            XCTAssertEqual(right.chordEvents.count, 1)
            var expected = original
            expected.manualVisualLaneFraction = 0
            XCTAssertEqual(right.chordEvents.first, expected)
            XCTAssertEqual(chart.measure(id: measureID)?.manualLayoutWidth, 150)
            XCTAssertEqual(right.manualLayoutWidth, 150)
            XCTAssertEqual(chart.measure(id: measureID)?.authoringState, .committed)
            XCTAssertEqual(right.authoringState, .open)
            XCTAssertEqual(try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart)), chart)
        }
    }

    private struct Fixture {
        var layout: LeadSheetPageLayout
        var system: LeadSheetSystemLayout
        var chordFrame: CGRect
        var lane: CGRect
    }
    private struct Input {
        var drawing: PKDrawing
        var state: ChordPreviewState
        var fixture: Fixture
    }

    private func makeChart(_ style: ChartLayoutStyle = .simpleChordSheet,
        startingMeasureCount: Int = 1) -> Chart {
        var chart = Chart.draft(title: "Structural automatic", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: .init(numerator: 4, denominator: 4), staffStyle: .fiveLine,
            startingMeasureCount: startingMeasureCount)
        return chart
    }

    private func fixture(_ chart: Chart) throws -> Fixture {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        return Fixture(layout: layout, system: try XCTUnwrap(layout.systems.first),
            chordFrame: region.frame, lane: try XCTUnwrap(region.inputFrames.first))
    }

    private func install(_ drawing: PKDrawing, in chart: inout Chart, fixture: Fixture) throws -> Input {
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let stored = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.repeatAwareVisibleDrawingContext(
            from: stored, chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        let fresh = ChordDraftBarlineRecognizer.recognizeIncludingRepeats(
            strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing),
            chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(fresh)
        let signs = context.remappedBarlineRecognition(safe).barlines
        XCTAssertFalse(signs.isEmpty)
        let state = ChordPreviewState(draftBarlines: signs, layoutPageSize: pageSize)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        return Input(drawing: stored, state: state, fixture: fixture)
    }

    private func attempt(_ chart: Chart, _ input: Input, elapsed: TimeInterval,
        isUsingTool: Bool = false) -> ChordInkDraftRenderCoordinator.AutomaticAttempt {
        ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: input.state,
            currentDrawing: input.drawing, coordinateSpace: .init(size: input.fixture.chordFrame.size),
            now: inputAt.addingTimeInterval(elapsed), lastInputAt: inputAt, isUsingTool: isUsingTool,
            sourcePageLayout: input.fixture.layout, sourceChordFrame: input.fixture.chordFrame)
    }

    private func strokes(_ kind: DraftBarlineKind, x: CGFloat, fixture: Fixture) -> [PKStroke] {
        let center = CGPoint(x: x - fixture.chordFrame.minX,
            y: fixture.lane.midY - fixture.chordFrame.minY)
        let height = fixture.lane.height * 0.84
        var result = [stroke([CGPoint(x: center.x, y: center.y - height / 2),
            CGPoint(x: center.x, y: center.y + height / 2)])]
        for side in [-1.0, 1.0] where (side < 0 ? kind.endsRepeat : kind.startsRepeat) {
            for vertical in [-1.0, 1.0] {
                result.append(stroke([CGPoint(x: center.x + CGFloat(side) * height * 0.20,
                    y: center.y + CGFloat(vertical) * height * 0.18)], size: 1.4))
            }
        }
        return result
    }

    private func stroke(_ points: [CGPoint], size: CGFloat = 3) -> PKStroke {
        PKStroke(ink: .init(.pen, color: .black),
            path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.05,
                    size: .init(width: size, height: size), opacity: 1, force: 1,
                    azimuth: 0, altitude: .pi / 2)
            }, creationDate: inputAt))
    }
}
#endif
