#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkRepeatSignWorkflowTests: XCTestCase {
    func testRepeatOwnershipRemapsEveryBarAndDotToItsExactOriginalStroke() throws {
        let context = ChordInkDraftVisibleDrawingContext(
            drawing: PKDrawing(strokes: (0..<4).map { pointStroke(x: CGFloat($0 * 10), y: 20) }),
            originalStrokeIndices: [1, 3, 4, 6], invisibleStrokeIndices: [0, 2, 5]
        )
        var repeatSign = draftBarline(measureID: UUID())
        repeatSign.kind = .repeatEnd
        repeatSign.sourceStrokeIndex = 0
        repeatSign.sourceStrokeIndices = [0, 1, 2, 3]
        let remapped = context.remappedBarlineRecognition(
            ChordDraftBarlineRecognition(barlines: [repeatSign], strokeIndices: [0, 1, 2, 3])
        )

        let sign = try XCTUnwrap(remapped.barlines.first)
        XCTAssertEqual(sign.sourceStrokeIndex, 1)
        XCTAssertEqual(sign.sourceStrokeIndices, [1, 3, 4, 6])
        XCTAssertEqual(sign.ownedSourceStrokeIndices, [1, 3, 4, 6])
        XCTAssertEqual(remapped.strokeIndices, sign.ownedSourceStrokeIndices)
        XCTAssertTrue(remapped.strokeIndices.isDisjoint(with: context.invisibleStrokeIndices))
    }

    func testOneOriginalStrokeWithMultipleMaskFragmentsCannotBeOwnedByARepeat() {
        let context = ChordInkDraftVisibleDrawingContext(
            drawing: PKDrawing(strokes: (0..<5).map { pointStroke(x: CGFloat($0 * 10), y: 20) }),
            originalStrokeIndices: [0, 0, 1, 2, 3], invisibleStrokeIndices: []
        )
        var sign = draftBarline(measureID: UUID())
        sign.kind = .repeatEnd
        sign.sourceStrokeIndex = 0
        sign.sourceStrokeIndices = [0, 2, 3, 4]

        let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(
            ChordDraftBarlineRecognition(barlines: [sign], strokeIndices: sign.ownedSourceStrokeIndices)
        )

        XCTAssertTrue(safe.barlines.isEmpty)
        XCTAssertTrue(safe.strokeIndices.isEmpty)
    }

    func testPreparationRemovesAllRepeatSourceBeforePreparingChordTargets() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try workflowFixture(style: style)
            let chord = try rootStrokes(in: fixture)
            let drawing = PKDrawing(strokes: chord + repeatEndStrokes(in: fixture))
            let preparation = prepare(drawing, fixture: fixture)
            let repeatSign = try XCTUnwrap(preparation.barlines.first { $0.kind == .repeatEnd }, style.rawValue)
            let expectedIndices = Set(chord.count..<(chord.count + 4))

            XCTAssertEqual(preparation.barlines.count, 1, style.rawValue)
            XCTAssertEqual(repeatSign.ownedSourceStrokeIndices, expectedIndices, style.rawValue)
            XCTAssertEqual(preparation.recognitionStrokeCount, chord.count, style.rawValue)
            guard case .ready(let requests, _) = preparation.outcome else {
                XCTFail("Expected the remaining typed-template root to reach chord targeting: \(preparation.outcome)")
                continue
            }
            XCTAssertFalse(requests.isEmpty, style.rawValue)
            XCTAssertEqual(requests.reduce(0) { $0 + $1.strokes.count }, chord.count, style.rawValue)
            let expected = PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: chord))
            XCTAssertEqual(requests.flatMap(\.strokes), expected, style.rawValue)
        }
    }

    func testTinyRepeatDotsArePromotedWithoutClaimingAnUnrelatedTinyMark() throws {
        let fixture = try workflowFixture()
        let unrelated = pointStroke(
            x: fixture.lane.minX + 24 - fixture.chordFrame.minX,
            y: fixture.lane.midY - fixture.chordFrame.minY,
            size: 1.2
        )
        let repeatStrokes = repeatEndStrokes(in: fixture)
        XCTAssertFalse(ChordInkDraftVisibleStrokePolicy.isVisible(unrelated))
        XCTAssertFalse(ChordInkDraftVisibleStrokePolicy.isVisible(repeatStrokes[2]))
        let drawing = PKDrawing(strokes: [unrelated] + repeatStrokes)
        let context = ChordInkDraftVisibleStrokePolicy.repeatAwareVisibleDrawingContext(
            from: drawing, chordFrame: fixture.chordFrame, pageLayout: fixture.layout
        )

        XCTAssertEqual(context.originalStrokeIndices, [1, 2, 3, 4])
        XCTAssertEqual(context.invisibleStrokeIndices, [0])
        let preparation = prepare(drawing, fixture: fixture)
        let sign = try XCTUnwrap(preparation.barlines.first { $0.kind == .repeatEnd })
        XCTAssertEqual(sign.ownedSourceStrokeIndices, [1, 2, 3, 4])
        XCTAssertFalse(sign.ownedSourceStrokeIndices.contains(0))

        var chart = fixture.chart
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let before = chart
        var reviewed = sign
        reviewed.repeatFromBeginningConfirmed = true
        let state = previewState([reviewed], pageSize: fixture.layout.pageBounds.size)
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertTrue(result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(chart, before, "Recognition's visibility threshold never authorizes clearing unrelated tiny ink.")
    }

    func testStaleRepeatGeometryRejectsTheWholeCommitWithoutClearingInk() throws {
        let fixture = try workflowFixture()
        let drawing = PKDrawing(strokes: repeatEndStrokes(in: fixture))
        var sign = try XCTUnwrap(prepare(drawing, fixture: fixture).barlines.first { $0.kind == .repeatEnd })
        sign.repeatFromBeginningConfirmed = true
        var movedStrokes = drawing.strokes
        let moved = movedStrokes[0]
        movedStrokes[0] = PKStroke(ink: moved.ink, path: moved.path,
            transform: moved.transform.translatedBy(x: 8, y: 0), mask: moved.mask, randomSeed: moved.randomSeed)
        var chart = fixture.chart
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: movedStrokes).dataRepresentation())
        let state = previewState([sign], pageSize: fixture.layout.pageBounds.size)
        let before = chart

        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertTrue(result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(result.renderedBarlineCount, 0)
        XCTAssertEqual(result.renderedChordCount, 0)
        XCTAssertEqual(chart, before)
    }

    func testMovingOnlyOneRepeatDotInvalidatesItsDraftAndResetsBeginningConfirmation() throws {
        let fixture = try workflowFixture()
        var chart = fixture.chart
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: repeatEndStrokes(in: fixture)).dataRepresentation())
        let originalDrawing = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        var confirmed = try XCTUnwrap(prepare(originalDrawing, fixture: fixture).barlines.first { $0.kind == .repeatEnd })
        confirmed.repeatFromBeginningConfirmed = true
        var state = previewState([confirmed], pageSize: fixture.layout.pageBounds.size)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))

        // Both bars, the anchor, stroke indices, and the accepted repeat kind
        // remain unchanged. Only one still-valid dot moves within its pair.
        var movedStrokes = originalDrawing.strokes
        let dot = movedStrokes[2]
        movedStrokes[2] = PKStroke(ink: dot.ink, path: dot.path,
            transform: dot.transform.translatedBy(x: 2, y: 0), mask: dot.mask, randomSeed: dot.randomSeed)
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: movedStrokes).dataRepresentation())
        let currentDrawing = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let fresh = try XCTUnwrap(prepare(currentDrawing, fixture: fixture).barlines.first { $0.kind == .repeatEnd })
        XCTAssertEqual(fresh.sourceStrokeIndex, confirmed.sourceStrokeIndex)
        XCTAssertEqual(fresh.ownedSourceStrokeIndices, confirmed.ownedSourceStrokeIndices)
        XCTAssertEqual(fresh.metrics, confirmed.metrics)
        XCTAssertEqual(fresh.fraction, confirmed.fraction)
        XCTAssertEqual(fresh.laneLocation, confirmed.laneLocation)
        XCTAssertEqual(confirmed.sourceStrokeGeometry.count, 4)
        XCTAssertNotEqual(fresh.sourceStrokeGeometry, confirmed.sourceStrokeGeometry)
        XCTAssertNotEqual(fresh.identitySignature, confirmed.identitySignature)
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))

        let before = chart
        let rejected = chart.commitChordInkDraftBatch(state)
        XCTAssertTrue(rejected.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(rejected.renderedBarlineCount, 0)
        XCTAssertEqual(rejected.renderedChordCount, 0)
        XCTAssertEqual(chart, before)

        state.replaceDraftBarlines(with: [fresh])
        let replaced = try XCTUnwrap(state.draftBarlines.first)
        XCTAssertFalse(replaced.repeatFromBeginningConfirmed)
        XCTAssertNotEqual(replaced.id, confirmed.id)
        XCTAssertEqual(replaced.identitySignature, fresh.identitySignature)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
    }

    func testPartiallyErasedRepeatRejectsTheOldDraftAndPreservesRemainingSource() throws {
        let fixture = try workflowFixture()
        let drawing = PKDrawing(strokes: repeatEndStrokes(in: fixture))
        var sign = try XCTUnwrap(prepare(drawing, fixture: fixture).barlines.first { $0.kind == .repeatEnd })
        sign.repeatFromBeginningConfirmed = true
        let original = drawing.strokes[0]
        let bounds = original.renderBounds
        let mask = UIBezierPath(rect: CGRect(x: bounds.minX - 2, y: bounds.minY - 2, width: bounds.width + 4, height: bounds.height * 0.30))
        mask.append(UIBezierPath(rect: CGRect(x: bounds.minX - 2, y: bounds.maxY - bounds.height * 0.30, width: bounds.width + 4, height: bounds.height * 0.30 + 2)))
        var masked = drawing.strokes
        masked[0] = PKStroke(ink: original.ink, path: original.path, transform: original.transform, mask: mask, randomSeed: original.randomSeed)
        XCTAssertGreaterThan(PencilKitInkAdapter.visibleStrokeFragments(from: masked[0]).count, 1)
        var chart = fixture.chart
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: masked).dataRepresentation())
        let before = chart
        let state = previewState([sign], pageSize: fixture.layout.pageBounds.size)

        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertTrue(result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(chart, before)
    }

    func testPartialRepeatStrokeOwnershipCannotPassCoverage() throws {
        let fixture = try workflowFixture()
        let drawing = PKDrawing(strokes: repeatEndStrokes(in: fixture))
        var sign = try XCTUnwrap(prepare(drawing, fixture: fixture).barlines.first { $0.kind == .repeatEnd })
        sign.sourceStrokeIndices.remove(3)
        sign.repeatFromBeginningConfirmed = true
        var chart = fixture.chart
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let before = chart
        let state = previewState([sign], pageSize: fixture.layout.pageBounds.size)

        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        XCTAssertTrue(chart.commitChordInkDraftBatch(state).didRejectIncompleteSourceCoverage)
        XCTAssertEqual(chart, before)
    }

    func testDuplicateRepeatClaimsCannotConsumeTheSameSourceTwice() throws {
        let fixture = try workflowFixture()
        let drawing = PKDrawing(strokes: repeatEndStrokes(in: fixture))
        var sign = try XCTUnwrap(prepare(drawing, fixture: fixture).barlines.first { $0.kind == .repeatEnd })
        sign.repeatFromBeginningConfirmed = true
        var duplicate = sign
        duplicate.id = UUID()
        var chart = fixture.chart
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let before = chart
        let state = previewState([sign, duplicate], pageSize: fixture.layout.pageBounds.size)

        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        XCTAssertTrue(chart.commitChordInkDraftBatch(state).didRejectIncompleteSourceCoverage)
        XCTAssertEqual(chart, before)
    }

    func testUnconfirmedEndRepeatRemainsUnresolvedWithoutChangingChartOrSource() throws {
        let fixture = try workflowFixture()
        let drawing = PKDrawing(strokes: repeatEndStrokes(in: fixture))
        let sign = try XCTUnwrap(prepare(drawing, fixture: fixture).barlines.first { $0.kind == .repeatEnd })
        var chart = fixture.chart
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let before = chart
        let state = previewState([sign], pageSize: fixture.layout.pageBounds.size)

        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertEqual(result.renderedBarlineCount, 0)
        XCTAssertTrue(result.unresolvedDraftIDs.contains(sign.id))
        XCTAssertEqual(chart, before)
    }

    func testConfirmedRepeatOnlyCommitStoresSourceOnTheRepeatAndSurvivesSaveReopen() throws {
        let fixture = try workflowFixture()
        let drawing = PKDrawing(strokes: repeatEndStrokes(in: fixture))
        var chart = fixture.chart
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let storedSource = try XCTUnwrap(chart.pageHandwrittenChordData)
        let currentDrawing = try PKDrawing(data: storedSource)
        var sign = try XCTUnwrap(prepare(currentDrawing, fixture: fixture).barlines.first { $0.kind == .repeatEnd })
        sign.repeatFromBeginningConfirmed = true
        let result = chart.commitChordInkDraftBatch(previewState([sign], pageSize: fixture.layout.pageBounds.size))

        XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(result.renderedBarlineCount, 1)
        XCTAssertEqual(result.renderedChordCount, 0)
        XCTAssertNil(chart.pageHandwrittenChordData)
        let repeatObject = try XCTUnwrap(chart.roadmapObjects.first { $0.type == .repeatSpan })
        let repeatSource = try XCTUnwrap(repeatObject.sourceInkData)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: currentDrawing, current: try PKDrawing(data: repeatSource)
        ))
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
        XCTAssertEqual(reopened, chart)
        XCTAssertEqual(reopened.roadmapObjects.first { $0.id == repeatObject.id }?.sourceInkData, repeatSource)
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

    private func workflowFixture(style: ChartLayoutStyle = .simpleChordSheet) throws -> Fixture {
        var chart = Chart.draft(title: "Repeat source workflow", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor, meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_400), includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        return Fixture(chart: chart, layout: layout, chordFrame: region.frame, lane: try XCTUnwrap(region.inputFrames.first))
    }

    private func repeatEndStrokes(in fixture: Fixture) -> [PKStroke] {
        let lane = fixture.lane
        let origin = fixture.chordFrame.origin
        let x = lane.minX + lane.width * 0.65 - origin.x
        let top = lane.minY + lane.height * 0.08 - origin.y
        let bottom = lane.maxY - lane.height * 0.08 - origin.y
        let centerY = lane.midY - origin.y
        let height = bottom - top
        let separation = max(2, height * 0.12)
        let dotOffset = max(5, height * 0.20)
        let dotSeparation = height * 0.18
        return [
            stroke(points: [CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)]),
            stroke(points: [CGPoint(x: x + separation, y: top), CGPoint(x: x + separation, y: bottom)]),
            pointStroke(x: x - dotOffset, y: centerY - dotSeparation, size: 1.4),
            pointStroke(x: x - dotOffset, y: centerY + dotSeparation, size: 1.4)
        ]
    }

    private func rootStrokes(in fixture: Fixture) throws -> [PKStroke] {
        let template = try XCTUnwrap(ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == "C" })
        return template.strokes.map { ink in
            stroke(points: ink.points.map { point in
                CGPoint(x: fixture.lane.minX + 40 + CGFloat(point.x) * 0.72 - fixture.chordFrame.minX,
                        y: fixture.lane.midY + CGFloat(point.y - 36) * 0.72 - fixture.chordFrame.minY)
            })
        }
    }

    private func prepare(_ drawing: PKDrawing, fixture: Fixture) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(ChordInkRecognitionPreparationRequest(
            requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            drawingData: drawing.dataRepresentation(), chordFrame: fixture.chordFrame,
            pageLayout: fixture.layout, flow: .draftPreview, options: .live, layoutStyle: fixture.chart.layoutStyle
        ))
    }

    private func previewState(_ barlines: [DraftBarline], pageSize: CGSize) -> ChordPreviewState {
        var state = ChordPreviewState()
        state.replaceDraftBarlines(with: barlines)
        state.layoutPageSize = pageSize
        return state
    }

    private func draftBarline(measureID: UUID) -> DraftBarline {
        DraftBarline(measureID: measureID, measureIndex: 1, fraction: 0.65,
            laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.65),
            metrics: DraftBarlineGestureMetrics(height: 50, width: 0, angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 0.9))
    }

    private func pointStroke(x: CGFloat, y: CGFloat, size: CGFloat = 3) -> PKStroke {
        stroke(points: [CGPoint(x: x, y: y)], size: size)
    }

    private func stroke(points: [CGPoint], size: CGFloat = 3) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.05,
                size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }
}
#endif
