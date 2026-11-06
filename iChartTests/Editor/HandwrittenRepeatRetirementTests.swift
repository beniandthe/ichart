#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class HandwrittenRepeatRetirementTests: XCTestCase {
    @MainActor
    func testHandwrittenChordRepeatRecognizesAndCommitsInBothStylesAndRenderModes() throws {
        let captured = try InkFixtureLoader.load("ChordRepeatCaptured01", file: #filePath)
        let bounds = InkBounds.enclosing(captured.strokes.map(\.bounds))
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try workflowFixture(style: style)
            // This public legacy fixture is a regression input, not evidence
            // of recognition accuracy across writers or physical iPad input.
            let strokes = captured.strokes.map { capturedStroke in
                stroke(points: capturedStroke.points.map { point in
                    CGPoint(
                        x: fixture.lane.midX + CGFloat(point.x - (bounds.minX + bounds.maxX) / 2) * 0.5 - fixture.chordFrame.minX,
                        y: fixture.lane.midY + CGFloat(point.y - (bounds.minY + bounds.maxY) / 2) * 0.5 - fixture.chordFrame.minY
                    )
                })
            }
            let source = LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes))
            var chart = fixture.chart
            _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation(),
                coordinateSpace: .init(size: fixture.chordFrame.size))
            let storedSource = try XCTUnwrap(chart.pageHandwrittenChordData)
            let drawing = try PKDrawing(data: storedSource)
            let originalSource = drawing.dataRepresentation()

            for flow in [ChordInkRecognitionFlow.draftPreview, .tapToConfirm] {
                let prepared = ChordInkRecognitionPreparation.prepare(.init(
                    requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
                    drawingData: originalSource, chordFrame: fixture.chordFrame,
                    pageLayout: fixture.layout, flow: flow, options: .live, layoutStyle: style))
                guard case .ready(let requests, _) = prepared.outcome else {
                    XCTFail("Chord-repeat ink must prepare a recognition target in \(style.rawValue), \(flow)")
                    continue
                }
                XCTAssertEqual(requests.count, 1, style.rawValue)
                XCTAssertTrue(prepared.barlines.isEmpty)
                XCTAssertTrue(prepared.endings.isEmpty)
                let request = try XCTUnwrap(requests.first)
                XCTAssertEqual(request.strokes.count, captured.strokes.count)
                let result = ChordInkMaximumTrustRecognizer().recognize(strokes: request.strokes, options: request.options)
                let match = try XCTUnwrap(result.match, style.rawValue)
                XCTAssertEqual(match.displayText, captured.expectedDisplayText)
                XCTAssertTrue(ChordSymbolParser.isChordRepeatText(match.displayText))
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                var input = ChordInkDraftInput(measureID: request.target.measureID,
                    measureIndex: try XCTUnwrap(chart.measure(id: request.target.measureID)).index,
                    targetFraction: request.target.fraction, visualOrder: request.visualOrder,
                    laneLocation: request.laneLocation, layoutPageSize: request.layoutPageSize,
                    drawingData: request.drawingData,
                    candidateTexts: ChordInkRenderResolutionPolicy.candidateTexts(for: result),
                    bestCandidateText: match.displayText, confidence: result.confidence,
                    strokeCount: request.strokes.count, recognitionResult: result,
                    primaryDecision: decision, recognitionDecision: decision,
                    requiresManualReviewOnly: request.requiresManualReviewOnly)
                input.targetLifecycle = .init(generationID: request.requestID, anchor: input.anchor,
                    ownership: .init(preparedStrokes: request.strokes), stage: .frozen)
                let draft = ChordInkDraft(input: input)
                let state = ChordPreviewState(draftChords: [draft], layoutPageSize: fixture.layout.pageBounds.size)
                // Manual mode follows the real review requirement by choosing
                // the recognized suggestion; the original decision stays intact.
                var reviewed = state
                if draft.requiresConfirmation { reviewed.draftChords[0].selectedText = match.displayText }
                XCTAssertEqual(reviewed.draftChords[0].recognitionDecision, decision)
                let manual = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: reviewed,
                    currentDrawing: drawing, coordinateSpace: .init(size: fixture.chordFrame.size),
                    sourcePageLayout: fixture.layout, sourceChordFrame: fixture.chordFrame)
                let inputAt = Date(timeIntervalSinceReferenceDate: 100)
                let automatic = try XCTUnwrap(ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(
                    chart: chart, state: state, currentDrawing: drawing,
                    coordinateSpace: .init(size: fixture.chordFrame.size), now: inputAt.addingTimeInterval(4),
                    lastInputAt: inputAt, isUsingTool: false, sourcePageLayout: fixture.layout,
                    sourceChordFrame: fixture.chordFrame).outcome, style.rawValue)
                for outcome in [manual, ChordInkDraftRenderCoordinator.explicitOutcome(automatic)] {
                    XCTAssertTrue(outcome.canConsumeSource, style.rawValue)
                    XCTAssertEqual(outcome.result.renderedChordCount, 1)
                    XCTAssertEqual(outcome.result.renderedBarlineCount, 0)
                    XCTAssertEqual(outcome.result.renderedEndingCount, 0)
                    XCTAssertNil(outcome.chart.pageHandwrittenChordData)
                    XCTAssertFalse(outcome.chart.roadmapObjects.contains { $0.type == .repeatSpan })
                    let chords = outcome.chart.measures.flatMap(\.chordEvents)
                    XCTAssertEqual(chords.count, 1)
                    let chord = try XCTUnwrap(chords.first)
                    XCTAssertEqual(chord.symbol.kind, .chordRepeat)
                    XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: drawing,
                        current: try PKDrawing(data: XCTUnwrap(chord.sourceInkData))))
                    let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                        from: ChartPersistenceCoders.encoder.encode(outcome.chart))
                    XCTAssertEqual(reopened, outcome.chart)
                    XCTAssertEqual(reopened.chordEvent(id: chord.id)?.sourceInkData, chord.sourceInkData)
                }
                XCTAssertEqual(drawing.dataRepresentation(), originalSource,
                    "Preparation and staged rendering must not alter the live source")
                XCTAssertEqual(chart.pageHandwrittenChordData, storedSource)
            }
        }
    }

    @MainActor
    func testBothRenderModesCannotCreateRepeatSpansFromHandwrittenSigns() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try workflowFixture(style: style)
            let opening = repeatStrokes(in: fixture, centerX: fixture.lane.minX + fixture.lane.width * 0.25,
                startsRepeat: true)
            let closing = repeatStrokes(in: fixture, centerX: fixture.lane.minX + fixture.lane.width * 0.75,
                startsRepeat: false)
            let combined = closing + Array(repeatStrokes(in: fixture,
                centerX: fixture.lane.minX + fixture.lane.width * 0.75, startsRepeat: true).suffix(2))
            let sourceCases = [opening, closing, combined, opening + closing, Array(closing.dropLast())]
            for source in sourceCases {
                let drawing = PKDrawing(strokes: source)
                var chart = fixture.chart
                _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation(),
                    coordinateSpace: PersistentInkCoordinateSpace(size: fixture.chordFrame.size))
                let preparation = prepare(drawing, fixture: fixture)
                var state = ChordPreviewState()
                state.replaceDraftBarlines(with: preparation.barlines)
                state.layoutPageSize = fixture.layout.pageBounds.size
                let manual = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: state,
                    currentDrawing: drawing, coordinateSpace: .init(size: fixture.chordFrame.size),
                    sourcePageLayout: fixture.layout, sourceChordFrame: fixture.chordFrame)
                XCTAssertFalse(manual.chart.roadmapObjects.contains { $0.type == .repeatSpan }, style.rawValue)
                let inputAt = Date(timeIntervalSinceReferenceDate: 100)
                let automatic = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
                    currentDrawing: drawing, coordinateSpace: .init(size: fixture.chordFrame.size),
                    now: inputAt.addingTimeInterval(4), lastInputAt: inputAt, isUsingTool: false,
                    sourcePageLayout: fixture.layout, sourceChordFrame: fixture.chordFrame)
                if let outcome = automatic.outcome {
                    XCTAssertFalse(outcome.chart.roadmapObjects.contains { $0.type == .repeatSpan }, style.rawValue)
                }
            }
        }
    }


    func testMeasureBasedRepeatsAndPreviouslySavedSourceArchivesSurviveReopen() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Saved repeat compatibility", measureCount: 4, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[2]))
            let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == repeatID })
            let savedSource = PKDrawing(strokes: [pointStroke(x: 30, y: 30)]).dataRepresentation()
            chart.roadmapObjects[index].sourceInkData = savedSource
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart))
            XCTAssertEqual(reopened, chart)
            let repeatSpan = try XCTUnwrap(reopened.roadmapObjects.first { $0.id == repeatID })
            XCTAssertEqual(repeatSpan.startMeasureID, ids[0])
            XCTAssertEqual(repeatSpan.endMeasureID, ids[2])
            XCTAssertEqual(repeatSpan.sourceInkData, savedSource)
        }
    }

    func testPlainBarlineOwnsOnlyAnImmediateTapOnItsEndpoint() throws {
        let fixture = try workflowFixture(style: .rhythmSectionSheet)
        let measure = try XCTUnwrap(fixture.layout.systems.first?.measures.first)
        let x = measure.staffFrame.midX - fixture.chordFrame.minX
        let top = fixture.lane.minY + 4 - fixture.chordFrame.minY
        let bottom = fixture.lane.maxY - 4 - fixture.chordFrame.minY
        let line = stroke(points: [CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)])

        for (offset, delay, attached) in [(0.3, 0.10, true), (3.0, 0.10, false), (0.3, 0.30, false)] {
            let tap = stroke(points: [CGPoint(x: x + offset, y: bottom)], size: 1.4,
                creationOffset: delay)
            let drawing = PKDrawing(strokes: [line, tap])
            let barline = try XCTUnwrap(prepare(drawing, fixture: fixture).barlines.first)
            XCTAssertEqual(barline.kind, .single)
            XCTAssertEqual(barline.ownedSourceStrokeIndices, attached ? [0, 1] : [0])

            var chart = fixture.chart
            _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
            let state = ChordPreviewState(draftBarlines: [barline], layoutPageSize: fixture.layout.pageBounds.size)
            XCTAssertEqual(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state), attached)
        }
    }

    func testLegacyRoadmapWithoutSourceInkDecodesAndNewSourceRoundTrips() throws {
        var chart = Chart.blank(title: "Legacy repeat provenance", measureCount: 2, layoutStyle: .simpleChordSheet)
        let ids = chart.measures.map(\.id)
        let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[1]))
        let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == repeatID })
        chart.roadmapObjects[index].sourceInkData = PKDrawing(strokes: [pointStroke(x: 30, y: 30)]).dataRepresentation()
        let object = chart.roadmapObjects[index]
        XCTAssertEqual(try JSONDecoder().decode(RoadmapObject.self, from: JSONEncoder().encode(object)), object)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(object)) as? [String: Any])
        legacy.removeValue(forKey: "sourceInkData")
        let decoded = try JSONDecoder().decode(RoadmapObject.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.sourceInkData)
        XCTAssertEqual(decoded.id, object.id)
        XCTAssertEqual(decoded.startMeasureID, object.startMeasureID)
        XCTAssertEqual(decoded.endMeasureID, object.endMeasureID)
    }

    private struct Fixture {
        var chart: Chart
        var layout: LeadSheetPageLayout
        var chordFrame: CGRect
        var lane: CGRect
    }


    private func workflowFixture(style: ChartLayoutStyle = .simpleChordSheet, startingMeasureCount: Int = 1) throws -> Fixture {
        var chart = Chart.draft(title: "Repeat source workflow", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor, meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine, startingMeasureCount: startingMeasureCount)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_400), includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        return Fixture(chart: chart, layout: layout, chordFrame: region.frame, lane: try XCTUnwrap(region.inputFrames.first))
    }

    private func repeatStrokes(
        in fixture: Fixture, centerX: CGFloat, startsRepeat: Bool, barSeparation: CGFloat? = nil
    ) -> [PKStroke] {
        let lane = fixture.lane
        let origin = fixture.chordFrame.origin
        let top = lane.minY + lane.height * 0.08 - origin.y
        let bottom = lane.maxY - lane.height * 0.08 - origin.y
        let centerY = lane.midY - origin.y
        let height = bottom - top
        let separation = barSeparation ?? max(2, height * 0.12)
        let x = centerX - origin.x - separation / 2
        let dotOffset = max(5, height * 0.20)
        let dotX = startsRepeat ? x + separation + dotOffset : x - dotOffset
        let dotSeparation = height * 0.18
        return [
            stroke(points: [CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)]),
            stroke(points: [CGPoint(x: x + separation, y: top), CGPoint(x: x + separation, y: bottom)]),
            pointStroke(x: dotX, y: centerY - dotSeparation, size: 1.4),
            pointStroke(x: dotX, y: centerY + dotSeparation, size: 1.4)
        ]
    }

    private func prepare(_ drawing: PKDrawing, fixture: Fixture) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(ChordInkRecognitionPreparationRequest(
            requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            drawingData: drawing.dataRepresentation(), chordFrame: fixture.chordFrame,
            pageLayout: fixture.layout, flow: .draftPreview, options: .live, layoutStyle: fixture.chart.layoutStyle
        ))
    }

    private func pointStroke(x: CGFloat, y: CGFloat, size: CGFloat = 3) -> PKStroke {
        stroke(points: [CGPoint(x: x, y: y)], size: size)
    }

    private func stroke(points: [CGPoint], size: CGFloat = 3, creationOffset: TimeInterval = 0) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.05,
                size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000 + creationOffset)))
    }
}
#endif
