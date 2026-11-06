#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class RepeatPreviewFeedbackTests: XCTestCase {
    func testChordOrderingUsesItsVisibleLaneCoordinates() {
        var input = ChordInkDraftInput(measureID: UUID(), measureIndex: 9, targetFraction: 0.85,
            visualOrder: 8.85, laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.3),
            drawingData: Data(), candidateTexts: ["C"], bestCandidateText: "C", confidence: 4, strokeCount: 1)
        let laneDraft = ChordInkDraft(input: input)
        XCTAssertEqual(ChordDiagnosticPreviewOrderPolicy.visualOrder(for: laneDraft), 1.3, accuracy: 0.001,
            "A chord must keep its second visual lane ordering regardless of its stored measure index.")
        input.laneLocation = nil
        XCTAssertEqual(ChordDiagnosticPreviewOrderPolicy.visualOrder(for: ChordInkDraft(input: input)), 8.85, accuracy: 0.001)
        input.visualOrder = nil
        XCTAssertEqual(ChordDiagnosticPreviewOrderPolicy.visualOrder(for: ChordInkDraft(input: input)), 9.85, accuracy: 0.001)
    }

    func testSingleBarlineAndUnavailableSourceKeepLegacySelectionGeometry() {
        let laneFrame = CGRect(x: 100, y: 200, width: 300, height: 80)
        let origin = CGPoint(x: 120, y: 200)
        let single = sourceSign()
        var missingSource = sourceSign()
        missingSource.sourceStrokeGeometry = []
        let sourceWithoutOrigin = sourceSign()
        let cases: [(DraftBarline, CGPoint?)] = [(single, origin), (missingSource, origin), (sourceWithoutOrigin, nil)]
        for (sign, sourceOrigin) in cases {
            let legacy = ChordDraftBarlineOverlayGeometry.lineFrame(for: sign, in: laneFrame).insetBy(dx: 3, dy: 8)
            XCTAssertEqual(ChordDraftBarlineOverlayGeometry.selectionFrame(for: sign, in: laneFrame, sourceOrigin: sourceOrigin), legacy)
            let point = CGPoint(x: legacy.midX, y: legacy.midY)
            XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
                at: point, barlines: [sign], laneFrameForBarline: { _ in laneFrame },
                selectedBarlineID: nil, sourceOrigin: sourceOrigin),
                ChordDraftBarlineHitTarget(barlineID: sign.id, action: .select))
            XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
                at: point, barlines: [sign], laneFrameForBarline: { _ in laneFrame },
                selectedBarlineID: sign.id, sourceOrigin: sourceOrigin),
                ChordDraftBarlineHitTarget(barlineID: sign.id, action: .delete))
        }
        let defaultPoint = ChordDraftBarlineOverlayGeometry.lineFrame(for: single, in: laneFrame)
        XCTAssertEqual(ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: defaultPoint.midX, y: defaultPoint.midY), barlines: [single],
            laneFrameForBarline: { _ in laneFrame }, selectedBarlineID: nil),
            ChordDraftBarlineHitTarget(barlineID: single.id, action: .select),
            "Callers that omit the new trailing source origin must keep the legacy API behavior.")
    }

    private func sourceSign() -> DraftBarline {
        let geometry = [stroke([(44, 10), (41, 30), (43, 60)])]
        return DraftBarline(measureID: UUID(), measureIndex: 1, fraction: 0.5,
            sourceStrokeIndex: 0,
            metrics: DraftBarlineGestureMetrics(height: 50, width: 3, angleDegreesFromVertical: 3,
                straightness: 0.96, laneCoverage: 0.85),
            sourceStrokeIndices: [0], sourceStrokeGeometry: geometry)
    }

    private func stroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(points: points.enumerated().map { index, point in
            InkPoint(x: point.0, y: point.1, timeOffset: Double(index) * 0.05)
        })
    }
}
#endif
