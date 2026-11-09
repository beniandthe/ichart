#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkStructuralMaturityTrackerTests: XCTestCase {
    private let chartID = UUID()
    private let measureID = UUID()
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testNewMarkUsesObservationTimeAndExpiredDeadlineDoesNotLoop() {
        let tracker = ChordInkStructuralMaturityTracker()
        let bar = barline()
        let source = PKDrawing(strokes: [stroke()])
        let state = ChordPreviewState(draftBarlines: [bar])
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: source, now: start), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(2))
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: source,
            now: start.addingTimeInterval(1.99)), [])
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: source,
            now: start.addingTimeInterval(2)), [bar.id])
        XCTAssertNil(tracker.nextDeadline)
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: source,
            now: start.addingTimeInterval(3)), [bar.id])
        XCTAssertNil(tracker.nextDeadline)
    }

    func testSourceReplacementWithIdenticalBoundsResetsAge() {
        let tracker = ChordInkStructuralMaturityTracker()
        let bar = barline()
        let state = ChordPreviewState(draftBarlines: [bar])
        let source = PKDrawing(strokes: [stroke()])
        _ = tracker.observe(chartID: chartID, state: state, drawing: source, now: start)
        let replacement = PKDrawing(strokes: [stroke(force: 0.6)])
        XCTAssertEqual(source.bounds, replacement.bounds)
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: replacement))
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: replacement,
            now: start.addingTimeInterval(1.5)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(3.5))
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: replacement,
            now: start.addingTimeInterval(2.1)), [])
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: replacement,
            now: start.addingTimeInterval(3.5)), [bar.id])
    }

    func testDisappearancePrunesAgeBeforeSameSourceReturns() {
        let tracker = ChordInkStructuralMaturityTracker()
        let bar = barline()
        let source = PKDrawing(strokes: [stroke()])
        let state = ChordPreviewState(draftBarlines: [bar])
        _ = tracker.observe(chartID: chartID, state: state, drawing: source, now: start)
        XCTAssertEqual(tracker.observe(chartID: chartID, state: ChordPreviewState(), drawing: source,
            now: start.addingTimeInterval(1)), [])
        XCTAssertNil(tracker.nextDeadline)
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: source,
            now: start.addingTimeInterval(3)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(5))
    }

    func testNewDraftIDAndSourceIndexRebaseRetainExactSourceAge() {
        let tracker = ChordInkStructuralMaturityTracker()
        var bar = barline(index: 1)
        let ink = stroke()
        let original = PKDrawing(strokes: [stroke(x: 20, seed: 2), ink])
        _ = tracker.observe(chartID: chartID, state: ChordPreviewState(draftBarlines: [bar]),
            drawing: original, now: start)
        let previousID = bar.id
        bar.id = UUID()
        bar.sourceStrokeIndex = 0
        bar.sourceStrokeIndices = [0]
        bar.measureIndex = 9 // Ordinals are not the semantic target's identity.
        bar.sourceStrokeGeometry = [] // Relative drawing chronology may rebase.
        let rebased = PKDrawing(strokes: [ink])
        XCTAssertEqual(tracker.observe(chartID: chartID, state: ChordPreviewState(draftBarlines: [bar]),
            drawing: rebased, now: start.addingTimeInterval(2)), [bar.id])
        XCTAssertNotEqual(bar.id, previousID)
        XCTAssertNil(tracker.nextDeadline)
    }

    func testUnrelatedLaterInkDoesNotResetOlderMark() {
        let tracker = ChordInkStructuralMaturityTracker()
        let bar = barline()
        let state = ChordPreviewState(draftBarlines: [bar])
        let first = stroke()
        _ = tracker.observe(chartID: chartID, state: state, drawing: PKDrawing(strokes: [first]), now: start)
        let expanded = PKDrawing(strokes: [first, stroke(x: 250, seed: 2)])
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: expanded,
            now: start.addingTimeInterval(1.5)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(2))
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: expanded,
            now: start.addingTimeInterval(2)), [bar.id])
    }

    func testMarksKeepIndependentAgesAndNextFutureDeadline() {
        let tracker = ChordInkStructuralMaturityTracker()
        let old = barline()
        let newer = barline(index: 1, fraction: 0.8)
        let first = stroke()
        _ = tracker.observe(chartID: chartID, state: ChordPreviewState(draftBarlines: [old]),
            drawing: PKDrawing(strokes: [first]), now: start)
        let state = ChordPreviewState(draftBarlines: [old, newer])
        let source = PKDrawing(strokes: [first, stroke(x: 250, seed: 2)])
        _ = tracker.observe(chartID: chartID, state: state, drawing: source, now: start.addingTimeInterval(1))
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(2))
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: source,
            now: start.addingTimeInterval(2)), [old.id])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(3))
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: source,
            now: start.addingTimeInterval(3)), [old.id, newer.id])
        XCTAssertNil(tracker.nextDeadline)
    }

    func testChartSwitchAndExplicitResetStartNewObservation() {
        let tracker = ChordInkStructuralMaturityTracker()
        let bar = barline()
        let state = ChordPreviewState(draftBarlines: [bar])
        let source = PKDrawing(strokes: [stroke()])
        _ = tracker.observe(chartID: chartID, state: state, drawing: source, now: start)
        let otherChart = UUID()
        XCTAssertEqual(tracker.observe(chartID: otherChart, state: state, drawing: source,
            now: start.addingTimeInterval(4)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(6))
        tracker.reset()
        XCTAssertNil(tracker.nextDeadline)
        XCTAssertEqual(tracker.observe(chartID: otherChart, state: state, drawing: source,
            now: start.addingTimeInterval(6)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(8))
    }

    func testInvalidAndAmbiguousClaimsPruneAge() {
        let tracker = ChordInkStructuralMaturityTracker()
        var bar = barline()
        let source = PKDrawing(strokes: [stroke()])
        let validState = ChordPreviewState(draftBarlines: [bar])
        _ = tracker.observe(chartID: chartID, state: validState, drawing: source, now: start)
        bar.ambiguity = .tooClose
        XCTAssertEqual(tracker.observe(chartID: chartID, state: ChordPreviewState(draftBarlines: [bar]),
            drawing: source, now: start.addingTimeInterval(1)), [])
        XCTAssertNil(tracker.nextDeadline)
        XCTAssertEqual(tracker.observe(chartID: chartID, state: validState, drawing: source,
            now: start.addingTimeInterval(3)), [])
        var duplicate = validState.draftBarlines[0]
        duplicate.id = UUID()
        XCTAssertEqual(tracker.observe(chartID: chartID,
            state: ChordPreviewState(draftBarlines: [validState.draftBarlines[0], duplicate]),
            drawing: source, now: start.addingTimeInterval(5)), [])
        XCTAssertNil(tracker.nextDeadline)
        XCTAssertEqual(tracker.observe(chartID: chartID, state: validState, drawing: PKDrawing(),
            now: start.addingTimeInterval(6)), [])
        XCTAssertNil(tracker.nextDeadline)
        XCTAssertEqual(tracker.observe(chartID: chartID, state: validState, drawing: source,
            now: start.addingTimeInterval(7)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(9))
    }

    func testEraseThenRestoreBeforeCensusStartsNewAge() {
        let tracker = ChordInkStructuralMaturityTracker()
        let bar = barline(index: 1)
        let ink = stroke()
        let unrelated = stroke(x: 250, seed: 2)
        let source = PKDrawing(strokes: [unrelated, ink])
        let state = ChordPreviewState(draftBarlines: [bar])
        _ = tracker.observe(chartID: chartID, state: state, drawing: source, now: start)
        tracker.retainPresentSource(in: PKDrawing(strokes: [unrelated]))
        XCTAssertNil(tracker.nextDeadline)
        tracker.retainPresentSource(in: source) // Undo before the next census.
        XCTAssertEqual(tracker.observe(chartID: chartID, state: state, drawing: source,
            now: start.addingTimeInterval(3)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(5))
    }

    func testSourcePresenceRetainsAgeThroughIndexRebaseAndAddedInk() {
        let tracker = ChordInkStructuralMaturityTracker()
        var bar = barline(index: 1)
        let ink = stroke()
        let source = PKDrawing(strokes: [stroke(x: 20, seed: 2), ink])
        _ = tracker.observe(chartID: chartID, state: ChordPreviewState(draftBarlines: [bar]),
            drawing: source, now: start)
        let rebased = PKDrawing(strokes: [ink, stroke(x: 250, seed: 3)])
        tracker.retainPresentSource(in: rebased)
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(2))
        bar.sourceStrokeIndex = 0
        bar.sourceStrokeIndices = [0]
        XCTAssertEqual(tracker.observe(chartID: chartID, state: ChordPreviewState(draftBarlines: [bar]),
            drawing: rebased, now: start.addingTimeInterval(2)), [bar.id])
        XCTAssertNil(tracker.nextDeadline)
    }

    func testChangedSemanticBoundaryResetsEvenWithIdenticalSource() {
        let tracker = ChordInkStructuralMaturityTracker()
        var bar = barline()
        let source = PKDrawing(strokes: [stroke()])
        _ = tracker.observe(chartID: chartID, state: ChordPreviewState(draftBarlines: [bar]),
            drawing: source, now: start)
        bar.fraction = 0.7
        XCTAssertEqual(tracker.observe(chartID: chartID, state: ChordPreviewState(draftBarlines: [bar]),
            drawing: source, now: start.addingTimeInterval(3)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(5))
    }

    func testEndingKeepsAgeAcrossReviewAndRebaseButNewEndpointResets() {
        let tracker = ChordInkStructuralMaturityTracker()
        let ink = stroke()
        let extra = stroke(x: 250, seed: 2)
        var ending = ending(indices: [1, 2])
        _ = tracker.observe(chartID: chartID, state: ChordPreviewState(draftEndings: [ending]),
            drawing: PKDrawing(strokes: [stroke(x: 20, seed: 3), ink, extra]), now: start)
        ending.id = UUID()
        ending.sourceStrokeIndices = [0, 1]
        ending.label = "1."
        ending.isReviewed = true
        ending.reviewedSourceInkData = PKDrawing(strokes: [ink, extra]).dataRepresentation()
        let source = PKDrawing(strokes: [ink, extra])
        XCTAssertEqual(tracker.observe(chartID: chartID, state: ChordPreviewState(draftEndings: [ending]),
            drawing: source, now: start.addingTimeInterval(2)), [ending.id])
        XCTAssertNil(tracker.nextDeadline)
        ending.end.fraction = 0.9
        XCTAssertEqual(tracker.observe(chartID: chartID, state: ChordPreviewState(draftEndings: [ending]),
            drawing: source, now: start.addingTimeInterval(3)), [])
        XCTAssertEqual(tracker.nextDeadline, start.addingTimeInterval(5))
    }

    private func barline(index: Int = 0, fraction: Double = 0.4) -> DraftBarline {
        DraftBarline(measureID: measureID, measureIndex: 1, fraction: fraction,
            laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: fraction),
            layoutPageSize: CGSize(width: 932, height: 1_400), sourceStrokeIndex: index,
            metrics: DraftBarlineGestureMetrics(height: 40, width: 0, angleDegreesFromVertical: 0,
                straightness: 1, laneCoverage: 0.9), sourceStrokeIndices: [index])
    }

    private func ending(indices: Set<Int>) -> DraftEnding {
        let left = DraftEndingEndpoint(measureID: measureID, measureIndex: 1, fraction: 0.1,
            laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.1))
        let right = DraftEndingEndpoint(measureID: measureID, measureIndex: 1, fraction: 0.8,
            laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.8))
        return DraftEnding(start: left, end: right, layoutPageSize: CGSize(width: 932, height: 1_400),
            sourceStrokeIndices: indices, sourceStrokeGeometry: [], endStyle: .closed)
    }

    private func stroke(x: CGFloat = 100, seed: UInt32 = 1, force: CGFloat = 1) -> PKStroke {
        let points = [CGPoint(x: x, y: 20), CGPoint(x: x, y: 60)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 2.5, height: 2.5),
                opacity: 1, force: force, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 10)),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif
