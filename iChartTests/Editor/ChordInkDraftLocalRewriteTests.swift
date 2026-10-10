#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkDraftLocalRewriteTests: XCTestCase {
    func testRewritingOneChordPreservesNeighborInkExactlyAndDoesNotUseBoundsAsOwnership() throws {
        let source = PKDrawing(strokes: [stroke(10), stroke(80), stroke(140)])
        let target = draft(PKDrawing(strokes: [source.strokes[1]]))
        let plan = try XCTUnwrap(ChordInkDraftLocalRewritePolicy.plan(for: target, source: source))
        XCTAssertEqual(plan.draftID, target.id)
        XCTAssertEqual(plan.originalStrokeIndices, [1])
        let rewritten = try XCTUnwrap(plan.rewrittenDrawing(ifCurrentSource: source))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [source.strokes[0], source.strokes[2]]), current: rewritten))
        let lookalike = draft(PKDrawing(strokes: [stroke(80, seed: 18)]))
        XCTAssertNil(ChordInkDraftLocalRewritePolicy.plan(for: lookalike, source: source))
    }

    func testAChangedOrReorderedCanvasCannotApplyEarlierDeletionIndices() throws {
        let source = PKDrawing(strokes: [stroke(10), stroke(80)])
        let plan = try XCTUnwrap(ChordInkDraftLocalRewritePolicy.plan(
            for: draft(PKDrawing(strokes: [source.strokes[0]])), source: source))
        XCTAssertNil(plan.rewrittenDrawing(ifCurrentSource: PKDrawing(strokes: source.strokes + [stroke(150)])))
        XCTAssertNil(plan.rewrittenDrawing(ifCurrentSource: PKDrawing(strokes: Array(source.strokes.reversed()))))
        XCTAssertNil(plan.rewrittenDrawing(ifCurrentSource: PKDrawing(strokes: [stroke(10, seed: 19), source.strokes[1]])))
        XCTAssertEqual(source.strokes.count, 2)
    }

    func testDuplicateSourceIdentityAndRepeatedTargetClaimsFailWithoutDeletingEitherStroke() {
        let original = stroke(10)
        let duplicate = PKDrawing(strokes: [original, original])
        XCTAssertNil(ChordInkDraftLocalRewritePolicy.plan(for: draft(PKDrawing(strokes: [original])), source: duplicate))
        XCTAssertNil(ChordInkDraftLocalRewritePolicy.plan(for: draft(duplicate), source: PKDrawing(strokes: [original])))
        XCTAssertEqual(duplicate.strokes.count, 2)
    }

    func testStaleNeighborThatSharesSelectedSourceOwnershipPreventsLocalRewrite() {
        let source = PKDrawing(strokes: [stroke(10), stroke(80)])
        let selected = draft(PKDrawing(strokes: [source.strokes[0]]))
        let independent = draft(PKDrawing(strokes: [source.strokes[1]]))
        XCTAssertNotNil(ChordInkDraftLocalRewritePolicy.plan(for: selected,
            in: ChordPreviewState(draftChords: [selected, independent]), source: source))
        var stale = draft(source)
        stale.isStale = true
        XCTAssertNil(ChordInkDraftLocalRewritePolicy.plan(for: selected,
            in: ChordPreviewState(draftChords: [selected, stale]), source: source))
        XCTAssertEqual(source.strokes.count, 2)
    }

    func testPartialBitmapFragmentCannotDeleteSharedOriginalStroke() throws {
        let mask = UIBezierPath()
        mask.append(UIBezierPath(rect: CGRect(x: -2, y: -8, width: 16, height: 16)))
        mask.append(UIBezierPath(rect: CGRect(x: 36, y: -8, width: 16, height: 16)))
        let points = stride(from: 0, through: 50, by: 10).map { CGPoint(x: CGFloat($0), y: 0) }
        let original = stroke(points: points, mask: mask)
        let source = PKDrawing(strokes: [original, stroke(90)])
        let fragments = PencilKitInkAdapter.visibleStrokeFragments(from: original)
        XCTAssertEqual(fragments.count, 2)
        XCTAssertNil(ChordInkDraftLocalRewritePolicy.plan(for: draft(PKDrawing(strokes: [fragments[0]])), source: source))
        let complete = try XCTUnwrap(ChordInkDraftLocalRewritePolicy.plan(
            for: draft(PKDrawing(strokes: fragments)), source: source))
        let rewritten = try XCTUnwrap(complete.rewrittenDrawing(ifCurrentSource: source))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [source.strokes[1]]), current: rewritten))
    }

    func testMalformedTargetAndEmptyTargetCannotBecomeSuccessfulRewrite() {
        let source = PKDrawing(strokes: [stroke(10)])
        var invalid = draft(source)
        invalid.drawingData = Data("invalid ink".utf8)
        XCTAssertNil(ChordInkDraftLocalRewritePolicy.plan(for: invalid, source: source))
        XCTAssertNil(ChordInkDraftLocalRewritePolicy.plan(for: draft(PKDrawing()), source: source))
    }

    private func draft(_ drawing: PKDrawing) -> ChordInkDraft {
        ChordInkDraft(input: ChordInkDraftInput(measureID: UUID(), measureIndex: 0,
            targetFraction: 0.25, drawingData: drawing.dataRepresentation(), candidateTexts: [],
            bestCandidateText: nil, confidence: 0, strokeCount: drawing.strokes.count))
    }

    private func stroke(_ x: CGFloat, seed: UInt32 = 17) -> PKStroke {
        stroke(points: [CGPoint(x: x, y: 10), CGPoint(x: x + 20, y: 40)], seed: seed)
    }

    private func stroke(points: [CGPoint], mask: UIBezierPath? = nil, seed: UInt32 = 17) -> PKStroke {
        let controls = points.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1, size: CGSize(width: 2, height: 2),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSinceReferenceDate: 100)),
            transform: .identity, mask: mask, randomSeed: seed)
    }
}
#endif
