#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkAutomaticSourcePrefixPolicyTests: XCTestCase {
    func testAppendKeepsOriginalOrderedSourceAndNeverCallsExpandedDrawingCurrent() {
        let a = stroke(at: .zero, seed: 1)
        let b = stroke(at: CGPoint(x: 120, y: 0), seed: 2)
        let before = PKDrawing(strokes: [a])
        let after = PKDrawing(strokes: [a, b])
        XCTAssertEqual(ChordInkAutomaticSourcePrefixPolicy.unchangedLeadingStrokeCount(
            snapshot: before, current: after), 1)
        XCTAssertFalse(ChordInkAutomaticSourcePrefixPolicy.hasIdenticalOrderedSource(snapshot: before, current: after))
        XCTAssertTrue(ChordInkAutomaticSourcePrefixPolicy.hasIdenticalOrderedSource(snapshot: before, current: before))
    }

    func testSameBoundsInteriorEditInvalidatesItsOriginalTarget() {
        let original = stroke(at: .zero, seed: 3)
        let edited = stroke(at: .zero, seed: 3, interior: CGPoint(x: 12, y: 17))
        XCTAssertEqual(original.renderBounds, edited.renderBounds)
        XCTAssertFalse(ChordInkAutomaticSourcePrefixPolicy.hasIdenticalOrderedSource(
            snapshot: PKDrawing(strokes: [original]), current: PKDrawing(strokes: [edited])))
        XCTAssertNil(ChordInkAutomaticSourcePrefixPolicy.unchangedLeadingStrokeCount(
            snapshot: PKDrawing(strokes: [original]), current: PKDrawing(strokes: [edited])))
    }

    func testChangingOnlyLastCapturedStrokeKeepsEarlierTargetButDropsChangedTarget() {
        let a = stroke(at: .zero, seed: 4)
        let b = stroke(at: CGPoint(x: 120, y: 0), seed: 5)
        let editedB = stroke(at: CGPoint(x: 120, y: 0), seed: 5, interior: CGPoint(x: 12, y: 17))
        let before = PKDrawing(strokes: [a, b])
        let current = PKDrawing(strokes: [a, editedB])
        let count = ChordInkAutomaticSourcePrefixPolicy.unchangedLeadingStrokeCount(snapshot: before, current: current)
        XCTAssertEqual(count, 1)
        let first = draft(a, index: 0), second = draft(b, index: 1)
        let retained = ChordInkAutomaticSourcePrefixPolicy.retainingUnchangedTargets(
            in: ChordPreviewState(draftChords: [first, second]), current: current, prefixCount: count ?? 0)
        XCTAssertEqual(retained.draftChords.map(\.id), [first.id])
        XCTAssertEqual(current.strokes.count, 2)
    }

    func testChangingEarlierStrokeOrReorderingInvalidatesWholePrefix() {
        let a = stroke(at: .zero, seed: 6)
        let b = stroke(at: CGPoint(x: 120, y: 0), seed: 7)
        let editedA = stroke(at: .zero, seed: 6, interior: CGPoint(x: 12, y: 17))
        let snapshot = PKDrawing(strokes: [a, b])
        for changed in [PKDrawing(strokes: [editedA, b]), PKDrawing(strokes: [b, a]), PKDrawing(strokes: [a])] {
            XCTAssertNil(ChordInkAutomaticSourcePrefixPolicy.unchangedLeadingStrokeCount(snapshot: snapshot, current: changed))
        }
    }

    func testChangedMaskCannotReuseMaskedTargetOrAnEarlierSourceClaim() {
        let a = stroke(at: .zero, seed: 8)
        let b = stroke(at: CGPoint(x: 120, y: 0), seed: 9)
        let maskedA = stroke(at: .zero, seed: 8, mask: UIBezierPath(rect: CGRect(x: 0, y: 0, width: 10, height: 30)))
        XCTAssertNil(ChordInkAutomaticSourcePrefixPolicy.unchangedLeadingStrokeCount(
            snapshot: PKDrawing(strokes: [a, b]), current: PKDrawing(strokes: [maskedA, b])))
        XCTAssertFalse(ChordInkAutomaticSourcePrefixPolicy.hasIdenticalOrderedSource(
            snapshot: PKDrawing(strokes: [a]), current: PKDrawing(strokes: [maskedA])))
    }

    func testSourceChronologyAndTransformRemainPartOfIdentity() {
        let a = stroke(at: .zero, seed: 10)
        let retimed = PKStroke(ink: a.ink,
            path: PKStrokePath(controlPoints: Array(a.path), creationDate: a.path.creationDate.addingTimeInterval(1)),
            transform: a.transform, mask: a.mask, randomSeed: a.randomSeed)
        let moved = PKStroke(ink: a.ink, path: a.path,
            transform: CGAffineTransform(translationX: 1, y: 0), mask: a.mask, randomSeed: a.randomSeed)
        for changed in [retimed, moved] {
            XCTAssertFalse(ChordInkAutomaticSourcePrefixPolicy.hasIdenticalOrderedSource(
                snapshot: PKDrawing(strokes: [a]), current: PKDrawing(strokes: [changed])))
        }
    }

    func testOnlyRightwardSeparatedInkOrLaterVerifiedRowsAreEligibleInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try layoutFixture(style)
            let first = fixture.rows[0]
            let second = fixture.rows[1]
            let origin = CGPoint(x: first.minX + 160 - fixture.frame.minX,
                y: first.midY - 15 - fixture.frame.minY)
            let selected = stroke(at: origin, seed: 11)
            let right = stroke(at: CGPoint(x: origin.x + 100, y: origin.y), seed: 12)
            let near = stroke(at: CGPoint(x: origin.x + 25, y: origin.y), seed: 13)
            let left = stroke(at: CGPoint(x: origin.x - 120, y: origin.y), seed: 14)
            let laterRow = stroke(at: CGPoint(x: second.minX + 30 - fixture.frame.minX,
                y: second.midY - 15 - fixture.frame.minY), seed: 15)
            XCTAssertTrue(independent(selected, right, fixture))
            XCTAssertTrue(independent(selected, laterRow, fixture))
            XCTAssertFalse(independent(selected, near, fixture), "A late extension must remain attached to its chord")
            XCTAssertFalse(independent(selected, left, fixture), "An added left boundary can change the older target's measure")
            XCTAssertFalse(independent(laterRow, selected, fixture), "An earlier writing row is not trailing ink")
        }
    }

    private struct LayoutFixture {
        var layout: LeadSheetPageLayout
        var frame: CGRect
        var rows: [CGRect]
    }

    private func layoutFixture(_ style: ChartLayoutStyle) throws -> LayoutFixture {
        var chart = Chart.draft(title: "Disposable source-prefix policy", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 900, height: 1_400), includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        XCTAssertGreaterThanOrEqual(region.inputFrames.count, 2)
        return LayoutFixture(layout: layout, frame: region.frame, rows: region.inputFrames)
    }

    private func independent(_ selected: PKStroke, _ unknown: PKStroke, _ fixture: LayoutFixture) -> Bool {
        ChordInkAutomaticSourcePrefixPolicy.trailingInkIsIndependent(unknownIndices: [1], selectedIndices: [0],
            drawing: PKDrawing(strokes: [selected, unknown]), layout: fixture.layout, sourceFrame: fixture.frame)
    }

    private func draft(_ source: PKStroke, index: Int) -> ChordInkDraft {
        ChordInkDraft(input: ChordInkDraftInput(measureID: UUID(), measureIndex: index + 1,
            targetFraction: 0, layoutPageSize: CGSize(width: 900, height: 1_400),
            drawingData: PKDrawing(strokes: [source]).dataRepresentation(), candidateTexts: ["C"],
            bestCandidateText: "C", confidence: 4, strokeCount: 1))
    }

    private func stroke(at origin: CGPoint, seed: UInt32, interior: CGPoint = CGPoint(x: 10, y: 15),
        mask: UIBezierPath? = nil) -> PKStroke {
        let locations = [CGPoint.zero, CGPoint(x: 20, y: 0), interior, CGPoint(x: 0, y: 30)]
        let points = locations.enumerated().map { index, point in
            PKStrokePoint(location: CGPoint(x: point.x + origin.x, y: point.y + origin.y),
                timeOffset: Double(index) * 0.01, size: CGSize(width: 3, height: 3), opacity: 1,
                force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: mask, randomSeed: seed)
    }
}
#endif
