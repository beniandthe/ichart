#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import PencilKit
import XCTest
@testable import iChart

final class PaperBarlineRecognitionTests: XCTestCase {
    func testTwoParallelStrokesBecomeOneDoubleBarlineOwningBothSources() throws {
        for style in chartStyles {
            let fixture = try makeFixture(style)
            let x = fixture.lane.minX + fixture.lane.width * 0.35
            let strokes = [line(at: x, in: fixture), line(at: x + 7, in: fixture)]

            let recognition = recognize(strokes, in: fixture)

            XCTAssertEqual(recognition.barlines.count, 1, style.rawValue)
            let barline = try XCTUnwrap(recognition.barlines.first)
            XCTAssertEqual(barline.kind, .double, style.rawValue)
            XCTAssertEqual(barline.ownedSourceStrokeIndices, [0, 1])
            XCTAssertEqual(recognition.strokeIndices, [0, 1])
            XCTAssertTrue(barline.isRenderable)
        }
    }

    func testRetracingOneDividerRemainsSingleAndRetainsBothSources() throws {
        for style in chartStyles {
            let fixture = try makeFixture(style)
            let x = fixture.lane.minX + fixture.lane.width * 0.40
            let strokes = [
                line(at: x, in: fixture),
                line(at: x + 1, in: fixture, reversed: true)
            ]

            let recognition = recognize(strokes, in: fixture)

            XCTAssertEqual(recognition.barlines.count, 1, style.rawValue)
            let barline = try XCTUnwrap(recognition.barlines.first)
            XCTAssertEqual(barline.kind, .single, style.rawValue)
            XCTAssertEqual(barline.ownedSourceStrokeIndices, [0, 1])
            XCTAssertEqual(recognition.strokeIndices, [0, 1])
        }
    }

    func testTwoDistinctDoubleBoundariesRetainAllFourStrokes() throws {
        for style in chartStyles {
            let fixture = try makeFixture(style)
            let first = fixture.lane.minX + fixture.lane.width * 0.20
            let second = fixture.lane.minX + fixture.lane.width * 0.75
            let strokes = [
                line(at: first, in: fixture), line(at: first + 7, in: fixture),
                line(at: second, in: fixture), line(at: second + 7, in: fixture)
            ]

            let recognition = recognize(strokes, in: fixture)

            XCTAssertEqual(recognition.barlines.map(\.kind), [.double, .double], style.rawValue)
            XCTAssertEqual(recognition.barlines.map(\.ownedSourceStrokeIndices), [[0, 1], [2, 3]])
            XCTAssertEqual(recognition.strokeIndices, [0, 1, 2, 3])
            let firstBoundary = try XCTUnwrap(recognition.barlines.first)
            let lastBoundary = try XCTUnwrap(recognition.barlines.last)
            XCTAssertLessThan(firstBoundary.laneFraction, lastBoundary.laneFraction)
        }
    }

    func testSeparatedSingleBoundariesStayDistinctAndKeepTheirPositions() throws {
        for style in chartStyles {
            let fixture = try makeFixture(style)
            let fractions = [0.22, 0.74]
            let strokes = fractions.map {
                line(at: fixture.lane.minX + fixture.lane.width * CGFloat($0), in: fixture)
            }

            let recognition = recognize(strokes, in: fixture)

            XCTAssertEqual(recognition.barlines.map(\.kind), [.single, .single], style.rawValue)
            XCTAssertEqual(recognition.strokeIndices, [0, 1])
            XCTAssertEqual(recognition.barlines.count, fractions.count)
            for (barline, fraction) in zip(recognition.barlines, fractions) {
                XCTAssertEqual(barline.laneFraction, fraction, accuracy: 0.001)
            }
        }
    }

    func testDoubleBoundaryNearRightEdgeUsesTheFullWritingLane() throws {
        for style in chartStyles {
            let fixture = try makeFixture(style)
            let strokes = [
                line(at: fixture.lane.maxX - 11, in: fixture),
                line(at: fixture.lane.maxX - 4, in: fixture)
            ]

            let recognition = recognize(strokes, in: fixture)

            XCTAssertEqual(recognition.barlines.count, 1, style.rawValue)
            let barline = try XCTUnwrap(recognition.barlines.first)
            XCTAssertEqual(barline.kind, .double)
            XCTAssertGreaterThan(barline.laneFraction, 0.90)
            XCTAssertLessThanOrEqual(barline.laneFraction, 1)
            XCTAssertEqual(recognition.strokeIndices, [0, 1])
        }
    }

    private let chartStyles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    private struct Fixture {
        var layout: LeadSheetPageLayout
        var chordFrame: CGRect
        var lane: CGRect
    }

    private func makeFixture(_ style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.draft(title: "Paper barline recognition", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
            startingMeasureCount: 1)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
        XCTAssertTrue(chart.usesPaperMeasureLayout)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 900, height: 1_400), includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        return Fixture(layout: layout,
            chordFrame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), lane: lane)
    }

    private func line(at x: CGFloat, in fixture: Fixture, reversed: Bool = false) -> InkStroke {
        let top = CGPoint(x: x - fixture.chordFrame.minX,
            y: fixture.lane.minY + 2 - fixture.chordFrame.minY)
        let bottom = CGPoint(x: top.x, y: fixture.lane.maxY - 2 - fixture.chordFrame.minY)
        let points = reversed ? [bottom, top] : [top, bottom]
        return InkStroke(points: points.enumerated().map {
            InkPoint(x: Double($0.element.x), y: Double($0.element.y),
                timeOffset: Double($0.offset) * 0.2)
        })
    }

    private func recognize(_ strokes: [InkStroke], in fixture: Fixture) -> ChordDraftBarlineRecognition {
        ChordDraftBarlineRecognizer.recognize(strokes: strokes,
            chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
    }
}
#endif
