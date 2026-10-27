#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordDraftRepeatDeletionTests: XCTestCase {
    func testFreshGroupedDeleteOwnsEveryBarAndDotAndPreservesUnrelatedInk() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try Fixture(style: style)
            let unrelated = fixture.stroke(points: [
                CGPoint(x: fixture.lane.minX + 24 - fixture.chordFrame.minX, y: fixture.lane.midY - 6 - fixture.chordFrame.minY),
                CGPoint(x: fixture.lane.minX + 34 - fixture.chordFrame.minX, y: fixture.lane.midY + 6 - fixture.chordFrame.minY)
            ])
            let drawing = PKDrawing(strokes: [unrelated] + fixture.repeatEndStrokes())
            let state = fixture.state(for: drawing)
            let sign = try XCTUnwrap(state.draftBarlines.first { $0.kind == .repeatEnd }, style.rawValue)
            let before = drawing.dataRepresentation()
            let indices = try XCTUnwrap(ChordDraftBarlineDeletionPolicy.validatedSourceIndices(
                for: sign, state: state, chart: fixture.chart, currentDrawing: drawing, pageLayout: fixture.layout), style.rawValue)

            XCTAssertEqual(indices, [1, 2, 3, 4], style.rawValue)
            let removal = drawing.removingStrokesAndSummarizing(at: indices)
            XCTAssertEqual(removal.strokeCount, 1)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: PKDrawing(strokes: [unrelated]), current: removal.drawing))
            XCTAssertEqual(drawing.dataRepresentation(), before, "Validation and the value-returning deletion helper leave the source snapshot intact.")
        }
    }

    func testMovingOnlyADotRejectsOldGroupedDeleteWithoutChangingSource() throws {
        let fixture = try Fixture()
        let drawing = PKDrawing(strokes: fixture.repeatEndStrokes())
        let state = fixture.state(for: drawing)
        let sign = try XCTUnwrap(state.draftBarlines.first { $0.kind == .repeatEnd })
        var strokes = drawing.strokes
        let dot = strokes[2]
        strokes[2] = PKStroke(ink: dot.ink, path: dot.path,
            transform: dot.transform.translatedBy(x: 2, y: 0), mask: dot.mask, randomSeed: dot.randomSeed)
        let moved = PKDrawing(strokes: strokes)
        let before = moved.dataRepresentation()
        let fresh = try XCTUnwrap(fixture.state(for: moved).draftBarlines.first { $0.kind == .repeatEnd })

        XCTAssertEqual(fresh.ownedSourceStrokeIndices, sign.ownedSourceStrokeIndices)
        XCTAssertNotEqual(fresh.sourceStrokeGeometry, sign.sourceStrokeGeometry)
        XCTAssertNil(ChordDraftBarlineDeletionPolicy.validatedSourceIndices(
            for: sign, state: state, chart: fixture.chart, currentDrawing: moved, pageLayout: fixture.layout))
        XCTAssertEqual(moved.dataRepresentation(), before)
    }

    func testBitmapErasedBarWithTwoVisibleFragmentsRejectsGroupedDelete() throws {
        let fixture = try Fixture()
        let drawing = PKDrawing(strokes: fixture.repeatEndStrokes())
        let state = fixture.state(for: drawing)
        let sign = try XCTUnwrap(state.draftBarlines.first { $0.kind == .repeatEnd })
        let original = drawing.strokes[0]
        let bounds = original.renderBounds
        let mask = UIBezierPath(rect: CGRect(x: bounds.minX - 2, y: bounds.minY - 2,
            width: bounds.width + 4, height: bounds.height * 0.3))
        mask.append(UIBezierPath(rect: CGRect(x: bounds.minX - 2, y: bounds.maxY - bounds.height * 0.3,
            width: bounds.width + 4, height: bounds.height * 0.3 + 2)))
        var strokes = drawing.strokes
        strokes[0] = PKStroke(ink: original.ink, path: original.path, transform: original.transform,
            mask: mask, randomSeed: original.randomSeed)
        XCTAssertGreaterThan(PencilKitInkAdapter.visibleStrokeFragments(from: strokes[0]).count, 1)
        let masked = PKDrawing(strokes: strokes)
        let before = masked.dataRepresentation()

        XCTAssertNil(ChordDraftBarlineDeletionPolicy.validatedSourceIndices(
            for: sign, state: state, chart: fixture.chart, currentDrawing: masked, pageLayout: fixture.layout))
        XCTAssertEqual(masked.dataRepresentation(), before)
    }

    func testTinySiblingMaskFragmentIsStillCountedBeforeGroupedDelete() throws {
        let fixture = try Fixture()
        var strokes = fixture.repeatEndStrokes()
        let bar = strokes[0]
        let top = try XCTUnwrap(bar.path.first?.location)
        let bottom = try XCTUnwrap(bar.path.last?.location)
        // The affine scale keeps the sibling below the recognition visibility
        // threshold while preserving the same full-size source bar on the page.
        let scale: CGFloat = 10
        let densePoints = (0...200).map { index in
            CGPoint(x: top.x * scale, y: (top.y + (bottom.y - top.y) * CGFloat(index) / 200) * scale)
        }
        let source = fixture.stroke(points: densePoints, size: 1)
        let transform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
        let scaled = try XCTUnwrap(PKDrawing(strokes: [source]).transformed(using: transform).strokes.first)
        strokes[0] = scaled
        let drawing = PKDrawing(strokes: strokes)
        let state = fixture.state(for: drawing)
        let sign = try XCTUnwrap(state.draftBarlines.first { $0.kind == .repeatEnd })
        let scaledHeight = (bottom.y - top.y) * scale
        let mask = UIBezierPath(rect: CGRect(x: top.x * scale - 4, y: top.y * scale - 4,
            width: 8, height: scaledHeight * 0.88 + 4))
        mask.append(UIBezierPath(rect: CGRect(x: top.x * scale - 4, y: bottom.y * scale - 2,
            width: 8, height: 5)))
        // Apply the mask in the original path plane before transforming the
        // drawing, matching PencilKitInkAdapterTests' verified mask fixture.
        let maskedSource = PKStroke(ink: source.ink, path: source.path, transform: source.transform,
            mask: mask, randomSeed: source.randomSeed)
        strokes[0] = try XCTUnwrap(PKDrawing(strokes: [maskedSource]).transformed(using: transform).strokes.first)
        let fragments = PencilKitInkAdapter.visibleStrokeFragments(from: strokes[0])
        XCTAssertEqual(fragments.count, 2)
        XCTAssertTrue(fragments.contains { !ChordInkDraftVisibleStrokePolicy.isVisible($0) },
            "The fixture must include a sibling that recognition would otherwise filter out.")
        let masked = PKDrawing(strokes: strokes)
        let before = masked.dataRepresentation()

        XCTAssertNil(ChordDraftBarlineDeletionPolicy.validatedSourceIndices(
            for: sign, state: state, chart: fixture.chart, currentDrawing: masked, pageLayout: fixture.layout))
        XCTAssertEqual(masked.dataRepresentation(), before)
    }

    func testRemainingGroupedIndicesRemapTogetherAndKeepReviewIdentity() throws {
        let fixture = try Fixture()
        let source = PKDrawing(strokes: fixture.repeatEndStrokes())
        var sign = try XCTUnwrap(fixture.state(for: source).draftBarlines.first { $0.kind == .repeatEnd })
        sign.sourceStrokeIndex = 5
        sign.sourceStrokeIndices = [5, 6, 7, 8]
        sign.repeatFromBeginningConfirmed = true
        let remapped = try XCTUnwrap(ChordDraftBarlineDeletionPolicy.remappingSourceIndices(
            [sign], afterRemoving: [0, 2, 3, 4]).first)

        XCTAssertEqual(remapped.sourceStrokeIndex, 1)
        XCTAssertEqual(remapped.ownedSourceStrokeIndices, [1, 2, 3, 4])
        XCTAssertEqual(remapped.id, sign.id)
        XCTAssertEqual(remapped.sourceStrokeGeometry, sign.sourceStrokeGeometry)
        XCTAssertTrue(remapped.repeatFromBeginningConfirmed)
        XCTAssertTrue(ChordDraftBarlineDeletionPolicy.remappingSourceIndices([sign], afterRemoving: [6]).isEmpty,
            "An overlapping source claim cannot survive as a partial sign.")
    }

    private struct Fixture {
        let chart: Chart
        let layout: LeadSheetPageLayout
        let chordFrame: CGRect
        let lane: CGRect

        init(style: ChartLayoutStyle = .simpleChordSheet) throws {
            var chart = Chart.draft(title: "Repeat deletion source", layoutStyle: style)
            chart.completeInitialSetup(title: chart.title, key: .cMajor,
                meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: CGSize(width: 900, height: 1_400), includesChordInkContinuationLanes: true)
            let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
            self.chart = chart
            self.layout = layout
            chordFrame = region.frame
            lane = try XCTUnwrap(region.inputFrames.first)
        }

        func repeatEndStrokes() -> [PKStroke] {
            let x = lane.minX + lane.width * 0.65 - chordFrame.minX
            let top = lane.minY + lane.height * 0.08 - chordFrame.minY
            let bottom = lane.maxY - lane.height * 0.08 - chordFrame.minY
            let midY = lane.midY - chordFrame.minY
            let height = bottom - top
            let separation = max(2, height * 0.12)
            let dotOffset = max(5, height * 0.20)
            return [
                stroke(points: [CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)]),
                stroke(points: [CGPoint(x: x + separation, y: top), CGPoint(x: x + separation, y: bottom)]),
                stroke(points: [CGPoint(x: x - dotOffset, y: midY - height * 0.18)], size: 1.4),
                stroke(points: [CGPoint(x: x - dotOffset, y: midY + height * 0.18)], size: 1.4)
            ]
        }

        func state(for drawing: PKDrawing) -> ChordPreviewState {
            let context = ChordInkDraftVisibleStrokePolicy.repeatAwareVisibleDrawingContext(
                from: drawing, chordFrame: chordFrame, pageLayout: layout)
            let recognition = ChordDraftBarlineRecognizer.recognizeIncludingRepeats(
                strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing), chordFrame: chordFrame, pageLayout: layout)
            let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(recognition)
            return ChordPreviewState(draftBarlines: context.remappedBarlineRecognition(safe).barlines,
                layoutPageSize: layout.pageBounds.size)
        }

        func stroke(points: [CGPoint], size: CGFloat = 3, transform: CGAffineTransform = .identity) -> PKStroke {
            PKStroke(ink: PKInk(.pen, color: .black),
                path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                    PKStrokePoint(location: point, timeOffset: Double(index) * 0.05,
                        size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000)), transform: transform, mask: nil)
        }
    }
}
#endif
