#if canImport(UIKit)
import Foundation
import PencilKit
import UIKit

struct LeadSheetChordInkRecognitionBatchTarget {
    var measureID: UUID
    var fraction: Double
    var strokes: [InkStroke]
    var drawingData: Data
    var drawing: PKDrawing
}

enum LeadSheetChordInkRecognitionTargeting {
    static func target(
        for drawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> (measureID: UUID, fraction: Double)? {
        guard let pageLayout else {
            return nil
        }

        let inkBounds = LeadSheetChordInkImageRenderer.renderBounds(for: drawing)
        guard !inkBounds.isNull,
              inkBounds.width >= 4 || inkBounds.height >= 4 else {
            return nil
        }

        return target(forInkBounds: inkBounds, chordFrame: chordFrame, pageLayout: pageLayout)
    }

    static func batchTargets(
        for drawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> [LeadSheetChordInkRecognitionBatchTarget] {
        guard let pageLayout else {
            return []
        }

        let inkStrokes = PencilKitInkAdapter.inkStrokes(from: drawing)
        let clusters = ChordInkBatchClusterer.clusters(for: inkStrokes)
        guard clusters.count > 1,
              clusters.count <= ChordInkBatchClusterer.maximumClusterCount else {
            return []
        }

        return clusters.compactMap { cluster in
            guard let target = target(forInkBounds: cluster.bounds.cgRect, chordFrame: chordFrame, pageLayout: pageLayout) else {
                return nil
            }

            let strokePairs = cluster.strokeIndices.compactMap { index -> (PKStroke, InkStroke)? in
                guard drawing.strokes.indices.contains(index),
                      inkStrokes.indices.contains(index) else {
                    return nil
                }

                return (drawing.strokes[index], inkStrokes[index])
            }
            guard !strokePairs.isEmpty else {
                return nil
            }

            let clusterDrawing = PKDrawing(strokes: strokePairs.map(\.0))
            return LeadSheetChordInkRecognitionBatchTarget(
                measureID: target.measureID,
                fraction: target.fraction,
                strokes: strokePairs.map(\.1),
                drawingData: clusterDrawing.dataRepresentation(),
                drawing: clusterDrawing
            )
        }
    }

    private static func target(
        forInkBounds inkBounds: CGRect,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout
    ) -> (measureID: UUID, fraction: Double)? {
        guard !inkBounds.isNull,
              inkBounds.width >= 4 || inkBounds.height >= 4 else {
            return nil
        }

        let inkBoundsInView = inkBounds.offsetBy(dx: chordFrame.minX, dy: chordFrame.minY)
        let inkCenter = CGPoint(x: inkBoundsInView.midX, y: inkBoundsInView.midY)
        let candidateMeasures = pageLayout.systems.flatMap(\.measures).compactMap { measure -> LeadSheetMeasureLayout? in
            guard measure.sourceMeasureID != nil else {
                return nil
            }

            return measure
        }

        let targetMeasure = candidateMeasures.max { lhs, rhs in
            score(inkBoundsInView, center: inkCenter, for: lhs)
                < score(inkBoundsInView, center: inkCenter, for: rhs)
        }
        guard let targetMeasure,
              let measureID = targetMeasure.sourceMeasureID,
              score(inkBoundsInView, center: inkCenter, for: targetMeasure) > 0 else {
            return nil
        }

        let fraction = (inkCenter.x - targetMeasure.chordBandFrame.minX)
            / max(1, targetMeasure.chordBandFrame.width)
        return (measureID, Double(min(max(fraction, 0), 0.9999)))
    }

    private static func score(
        _ inkBounds: CGRect,
        center: CGPoint,
        for measure: LeadSheetMeasureLayout
    ) -> CGFloat {
        let generousBandFrame = measure.chordWritingFrame.insetBy(dx: -14, dy: -18)
        let intersection = generousBandFrame.intersection(inkBounds)
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let centerBonus: CGFloat = generousBandFrame.contains(center) ? 10_000 : 0

        return intersectionArea + centerBonus
    }
}

private extension InkBounds {
    var cgRect: CGRect {
        CGRect(
            x: minX,
            y: minY,
            width: width,
            height: height
        )
    }
}
#endif
