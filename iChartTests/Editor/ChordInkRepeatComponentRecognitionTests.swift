#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Procedural controls derived from chart layout, with no captured handwriting.
final class ChordInkRepeatComponentRecognitionTests: XCTestCase {
    func testCompleteSimpleRepeatsOwnTheirSourceAtHalfLaneCoverageAndAbove() throws {
        for preset in [EngravingPreset.compact, .balanced, .wide, .bold] {
            for coverage in [0.50, 0.55, 0.60, 0.62] {
                for bars in [1, 2] {
                    for kind in [DraftBarlineKind.repeatStart, .repeatEnd, .repeatBoth] {
                        let fixture = try makeFixture(preset: preset, coverage: coverage)
                        let drawing = PKDrawing(strokes: fixture.sign(kind: kind, bars: bars))
                        let result = recognize(drawing, fixture: fixture)
                        let note = "\(preset.rawValue), \(coverage), \(bars) bars, \(kind.rawValue)"
                        XCTAssertEqual(result.barlines.map(\.kind), [kind], note)
                        XCTAssertEqual(result.strokeIndices, Set(drawing.strokes.indices), note)
                        let prepared = prepare(drawing, fixture: fixture)
                        XCTAssertEqual(prepared.barlines.map(\.kind), [kind], note)
                        XCTAssertEqual(prepared.recognitionStrokeCount, 0, note)
                    }
                }
            }
        }
    }

    func testBarsBelowHalfLaneCoverageDoNotBecomeRepeats() throws {
        let fixture = try makeFixture(coverage: 0.49)
        let drawing = PKDrawing(strokes: fixture.sign(kind: .repeatEnd, bars: 2))
        let result = recognize(drawing, fixture: fixture)
        XCTAssertTrue(result.barlines.isEmpty)
        XCTAssertTrue(result.strokeIndices.isEmpty)
    }

    func testShortPlainSimpleBarDoesNotAcquireRepeatCoverageAllowance() throws {
        for coverage in [0.50, 0.55, 0.60] {
            let fixture = try makeFixture(coverage: coverage)
            let drawing = PKDrawing(strokes: [fixture.sign(kind: .repeatStart, bars: 1)[0]])
            let ink = PencilKitInkAdapter.inkStrokes(from: drawing)
            XCTAssertNil(ChordDraftBarlineRecognizer.candidate(for: ink[0],
                chordFrame: fixture.frame, pageLayout: fixture.layout))
            let all = ChordDraftBarlineRecognizer.recognizeIncludingRepeats(strokes: ink,
                chordFrame: fixture.frame, pageLayout: fixture.layout)
            XCTAssertTrue(all.barlines.isEmpty)
            XCTAssertTrue(all.strokeIndices.isEmpty)
        }
        let ordinary = try makeFixture(coverage: 0.70)
        let ink = PencilKitInkAdapter.inkStrokes(from:
            PKDrawing(strokes: [ordinary.sign(kind: .repeatStart, bars: 1)[0]]))
        XCTAssertNotNil(ChordDraftBarlineRecognizer.candidate(for: ink[0],
            chordFrame: ordinary.frame, pageLayout: ordinary.layout))
    }

    func testOtherChartStylesKeepTheirExistingRepeatCoverageGate() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .leadSheet] {
            for coverage in [0.50, 0.55, 0.60] {
                let fixture = try makeFixture(style: style, coverage: coverage)
                let result = recognize(PKDrawing(strokes: fixture.sign(kind: .repeatEnd, bars: 1)), fixture: fixture)
                XCTAssertTrue(result.barlines.isEmpty, "\(style.rawValue), \(coverage)")
                XCTAssertTrue(result.strokeIndices.isEmpty)
            }
            let fixture = try makeFixture(style: style, coverage: 0.80)
            let drawing = PKDrawing(strokes: fixture.sign(kind: .repeatEnd, bars: 1))
            let result = recognize(drawing, fixture: fixture)
            XCTAssertEqual(result.barlines.map(\.kind), [.repeatEnd], style.rawValue)
            XCTAssertEqual(result.strokeIndices, Set(drawing.strokes.indices))
        }
    }

    func testShortRepeatStillRequiresTwoAlignedCenteredDotsOnEachPopulatedSide() throws {
        let f = try makeFixture(coverage: 0.55)
        for kind in [DraftBarlineKind.repeatStart, .repeatEnd] {
            let source = f.sign(kind: kind, bars: 1)
            let dotX = f.x + (kind == .repeatStart ? f.height * 0.20 : -f.height * 0.20)
            let invalid: [[PKStroke]] = [
                Array(source.dropLast()),
                source + [Self.stroke([CGPoint(x: dotX, y: f.y)])],
                [source[0], source[1], Self.stroke([CGPoint(x: dotX + f.height * 0.20, y: f.y + f.height * 0.18)])],
                [source[0], Self.stroke([CGPoint(x: dotX, y: f.y - f.height * 0.40)]),
                 Self.stroke([CGPoint(x: dotX, y: f.y - f.height * 0.20)])]
            ]
            for strokes in invalid {
                let result = recognize(PKDrawing(strokes: strokes), fixture: f)
                XCTAssertTrue(result.barlines.isEmpty)
                XCTAssertTrue(result.strokeIndices.isEmpty)
            }
        }
    }

    func testShortRepeatStillRejectsConnectedLetterBodiesAndSlashConstructions() throws {
        let f = try makeFixture(coverage: 0.55)
        let source = f.sign(kind: .repeatStart, bars: 1)
        let h = f.height, x = f.x, y = f.y
        let fBody = Self.stroke([CGPoint(x: x, y: y - h * 0.45), CGPoint(x: x + h * 0.35, y: y - h * 0.45),
                                CGPoint(x: x, y: y), CGPoint(x: x + h * 0.25, y: y)])
        let bBody = Self.stroke([CGPoint(x: x, y: y - h * 0.5), CGPoint(x: x + h * 0.32, y: y - h * 0.25),
                                CGPoint(x: x, y: y), CGPoint(x: x + h * 0.32, y: y + h * 0.25),
                                CGPoint(x: x, y: y + h * 0.5)])
        let cap = Self.stroke([CGPoint(x: x - h * 0.20, y: y - h * 0.40), CGPoint(x: x, y: y - h * 0.5)])
        let slash = Self.stroke([CGPoint(x: x - h * 0.30, y: y + h * 0.5), CGPoint(x: x + h * 0.30, y: y - h * 0.5)])
        let invalid = [source + [fBody], source + [bBody], source + [cap], [slash] + Array(source.dropFirst())]
        for strokes in invalid {
            let result = recognize(PKDrawing(strokes: strokes), fixture: f)
            XCTAssertTrue(result.barlines.isEmpty)
            XCTAssertTrue(result.strokeIndices.isEmpty)
        }
    }

    func testDistantChordInkRemainsOutsideShortRepeatOwnershipAndReachesPreparation() throws {
        let f = try makeFixture(coverage: 0.55)
        let sign = f.sign(kind: .repeatStart, bars: 2)
        let h = f.height, x = f.x - h * 1.5
        let neighbor = Self.stroke([CGPoint(x: x + h * 0.35, y: f.y - h * 0.30),
                                   CGPoint(x: x, y: f.y - h * 0.30), CGPoint(x: x, y: f.y + h * 0.30),
                                   CGPoint(x: x + h * 0.35, y: f.y + h * 0.30)], ordinal: 10)
        let drawing = PKDrawing(strokes: sign + [neighbor])
        let allInk = PencilKitInkAdapter.inkStrokes(from: drawing)
        let result = recognize(drawing, fixture: f)
        XCTAssertEqual(result.barlines.map(\.kind), [.repeatStart])
        XCTAssertEqual(result.strokeIndices, Set(sign.indices))
        let prepared = prepare(drawing, fixture: f)
        XCTAssertEqual(prepared.recognitionStrokeCount, 1)
        guard case .ready(let requests, _) = prepared.outcome else {
            return XCTFail("The distant chord construction must remain available to chord targeting")
        }
        XCTAssertEqual(requests.flatMap(\.strokes), [try XCTUnwrap(allInk.last)])
    }

    func testCompletedRepeatTakesOverPrefixSourceBeforeChordTargetingWithoutChangingIdlePolicy() throws {
        let f = try makeFixture(coverage: 0.55)
        let complete = f.sign(kind: .repeatStart, bars: 1)
        for length in [1, 2] {
            let prefix = PKDrawing(strokes: Array(complete.prefix(length)))
            let result = recognize(prefix, fixture: f)
            XCTAssertTrue(result.barlines.isEmpty)
            XCTAssertTrue(result.strokeIndices.isEmpty, "An incomplete repeat must not claim its provisional bar")
        }
        let drawing = PKDrawing(strokes: complete)
        let prepared = prepare(drawing, fixture: f)
        XCTAssertEqual(prepared.barlines.map(\.kind), [.repeatStart])
        XCTAssertEqual(prepared.barlines.first?.ownedSourceStrokeIndices, Set(complete.indices))
        XCTAssertEqual(prepared.sourceStrokeCount, complete.count)
        XCTAssertEqual(prepared.visibleStrokeCount, complete.count, "Complete repeat dots must be promoted")
        XCTAssertEqual(prepared.recognitionStrokeCount, 0)
        var state = ChordPreviewState()
        state.replaceDraftBarlines(with: prepared.barlines)
        XCTAssertEqual(ChordInkAutomaticRenderPolicy.requiredIdleDelay(for: state),
                       ChordInkAutomaticRenderPolicy.structuralIdleDelay)
    }

    @MainActor
    func testShortRepeatPairCommitsAndReopensWithoutChangingExistingChordSources() throws {
        for manual in [true, false] {
            var chart = Chart.blank(title: "Procedural repeat persistence", measureCount: 2,
                                    layoutStyle: .simpleChordSheet)
            chart.engravingPreset = .compact
            let measureIDs = chart.measures.map(\.id)
            for (index, text) in ["C", "G7"].enumerated() {
                let match = try XCTUnwrap(ChordRecognitionCompendium.match(text))
                let priorInk = PKDrawing(strokes: [Self.stroke([
                    CGPoint(x: CGFloat(12 + index * 9), y: 15), CGPoint(x: CGFloat(24 + index * 9), y: 33)
                ], ordinal: index)])
                _ = try XCTUnwrap(chart.appendRecognizedChordEvent(match.symbol, rawInput: text,
                    to: measureIDs[index], atFraction: 0.25, sourceInkData: priorInk.dataRepresentation()))
            }
            let priorChords = chart.measures.flatMap(\.chordEvents)
            XCTAssertEqual(priorChords.count, 2)
            XCTAssertTrue(priorChords.allSatisfy { $0.sourceInkData != nil })

            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: CGSize(width: 900, height: 1400), includesChordInkContinuationLanes: true)
            let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
            let system = try XCTUnwrap(layout.systems.first)
            let paper = layout.paperFrame(for: system)
            let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system, paperFrame: paper))
            let first = try XCTUnwrap(system.measures.first)
            let last = try XCTUnwrap(system.measures.last)
            let firstDisplay = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(first,
                in: system, paperFrame: paper, layoutStyle: .simpleChordSheet)
            let lastDisplay = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(last,
                in: system, paperFrame: paper, layoutStyle: .simpleChordSheet)
            let start = Fixture(chart: chart, layout: layout, frame: frame,
                x: firstDisplay.frame.minX + 1 - frame.minX, y: lane.midY - frame.minY,
                height: lane.height * 0.55)
            let end = Fixture(chart: chart, layout: layout, frame: frame,
                x: min(lastDisplay.frame.maxX - 1, lane.maxX - max(2, lane.height * 0.55 * 0.10) / 2 - 2) - frame.minX, y: lane.midY - frame.minY,
                height: lane.height * 0.55)
            let drawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes:
                start.sign(kind: .repeatStart, bars: 1) + end.sign(kind: .repeatEnd, bars: 2)))
            let coordinateSpace = try XCTUnwrap(PersistentInkCoordinateSpace(size: frame.size))
            _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation(), coordinateSpace: coordinateSpace)
            let storedDrawing = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            let prepared = prepare(storedDrawing, fixture: start)
            XCTAssertEqual(prepared.barlines.map(\.kind), [.repeatStart, .repeatEnd])
            XCTAssertEqual(prepared.recognitionStrokeCount, 0)
            XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), Set(storedDrawing.strokes.indices))
            let startSign = try XCTUnwrap(prepared.barlines.first { $0.kind == .repeatStart })
            let endSign = try XCTUnwrap(prepared.barlines.first { $0.kind == .repeatEnd })
            XCTAssertTrue(startSign.ownedSourceStrokeIndices.isDisjoint(with: endSign.ownedSourceStrokeIndices))
            var state = ChordPreviewState()
            state.replaceDraftBarlines(with: prepared.barlines)
            state.layoutPageSize = layout.pageBounds.size
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))

            let outcome: ChordInkDraftRenderCoordinator.Outcome
            if manual {
                outcome = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: state,
                    currentDrawing: storedDrawing, coordinateSpace: coordinateSpace,
                    sourcePageLayout: layout, sourceChordFrame: frame)
            } else {
                let inputAt = Date(timeIntervalSinceReferenceDate: 100)
                let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
                    currentDrawing: storedDrawing, coordinateSpace: coordinateSpace,
                    now: inputAt.addingTimeInterval(10), lastInputAt: inputAt, isUsingTool: false,
                    sourcePageLayout: layout, sourceChordFrame: frame)
                outcome = ChordInkDraftRenderCoordinator.explicitOutcome(try XCTUnwrap(attempt.outcome))
            }
            XCTAssertTrue(outcome.canConsumeSource)
            XCTAssertFalse(outcome.result.didRejectIncompleteSourceCoverage)
            XCTAssertTrue(outcome.result.unresolvedDraftIDs.isEmpty)
            XCTAssertEqual(outcome.result.renderedBarlineCount, 2)
            XCTAssertEqual(outcome.result.renderedChordCount, 0)
            XCTAssertNil(outcome.retainedDraft)
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(outcome.chart))
            XCTAssertEqual(reopened, outcome.chart)
            XCTAssertEqual(reopened.measures.map(\.id), measureIDs, "Existing endpoints must not create sliver measures")
            XCTAssertEqual(reopened.measures.flatMap(\.chordEvents), priorChords,
                "Every prior chord and its original source archive must remain exact; no chord may be added from repeat ink")
            let spans = reopened.roadmapObjects.filter { $0.type == .repeatSpan }
            XCTAssertEqual(spans.count, 1)
            let span = try XCTUnwrap(spans.first)
            XCTAssertEqual(span.startMeasureID, measureIDs.first)
            XCTAssertEqual(span.endMeasureID, measureIDs.last)
            let archived = try PKDrawing(data: XCTUnwrap(span.sourceInkData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: storedDrawing, current: archived))
            XCTAssertNil(reopened.pageHandwrittenChordData)
            XCTAssertNil(reopened.pageHandwrittenChordCoordinateSpace)
        }
    }

    private struct Fixture {
        let chart: Chart
        let layout: LeadSheetPageLayout
        let frame: CGRect
        let x: CGFloat
        let y: CGFloat
        let height: CGFloat

        func sign(kind: DraftBarlineKind, bars: Int) -> [PKStroke] {
            let separation = max(2, height * 0.10)
            let left = x - (bars == 2 ? separation / 2 : 0)
            let right = left + (bars == 2 ? separation : 0)
            var paths = [[CGPoint(x: left, y: y - height / 2), CGPoint(x: left, y: y + height / 2)]]
            if bars == 2 {
                paths.append([CGPoint(x: right, y: y - height / 2), CGPoint(x: right, y: y + height / 2)])
            }
            for side in [-1, 1] where (side < 0 ? kind.endsRepeat : kind.startsRepeat) {
                let dotX = side < 0 ? left - height * 0.20 : right + height * 0.20
                paths.append([CGPoint(x: dotX, y: y - height * 0.18)])
                paths.append([CGPoint(x: dotX, y: y + height * 0.18)])
            }
            return paths.enumerated().map { ChordInkRepeatComponentRecognitionTests.stroke($0.element, ordinal: $0.offset) }
        }
    }

    private func makeFixture(style: ChartLayoutStyle = .simpleChordSheet,
                             preset: EngravingPreset = .compact, coverage: Double) throws -> Fixture {
        var chart = Chart.draft(title: "Procedural repeat control", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 3)
        chart.engravingPreset = preset
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 900, height: 1400), includesChordInkContinuationLanes: true)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        return Fixture(chart: chart, layout: layout, frame: frame,
            x: lane.minX + lane.width * 0.57 - frame.minX, y: lane.midY - frame.minY,
            height: lane.height * CGFloat(coverage))
    }

    private func recognize(_ drawing: PKDrawing, fixture: Fixture) -> ChordDraftBarlineRecognition {
        ChordDraftRepeatSignRecognizer.recognize(strokes: PencilKitInkAdapter.inkStrokes(from: drawing),
            chordFrame: fixture.frame, pageLayout: fixture.layout)
    }

    private func prepare(_ drawing: PKDrawing, fixture: Fixture) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            drawingData: drawing.dataRepresentation(), chordFrame: fixture.frame, pageLayout: fixture.layout,
            flow: .draftPreview, options: .live, layoutStyle: fixture.chart.layoutStyle))
    }

    private static func stroke(_ points: [CGPoint], ordinal: Int = 0) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints:
            points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 1.5, height: 1.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(ordinal))))
    }
}
#endif
