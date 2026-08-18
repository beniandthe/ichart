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

private struct DraftBarlineLaneClusterKey: Hashable {
    var systemIndex: Int
    var segmentIndex: Int
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
        pageLayout: LeadSheetPageLayout?,
        draftBarlines: [DraftBarline] = []
    ) -> [LeadSheetChordInkRecognitionBatchTarget] {
        guard let pageLayout else {
            return []
        }

        let inkStrokes = PencilKitInkAdapter.inkStrokes(from: drawing)
        let draftBarlineClusters = draftBarlineLaneClusters(
            for: inkStrokes,
            chordFrame: chordFrame,
            pageLayout: pageLayout,
            draftBarlines: draftBarlines
        )
        let measureLaneClusters = measureLaneClusters(
            for: inkStrokes,
            chordFrame: chordFrame,
            pageLayout: pageLayout
        )
        let clusters = draftBarlineClusters.count > 1
            && draftBarlineClusters.count <= ChordInkBatchClusterer.maximumClusterCount
            ? draftBarlineClusters
            : measureLaneClusters.count > 1
            && measureLaneClusters.count <= ChordInkBatchClusterer.maximumClusterCount
            ? measureLaneClusters
            : ChordInkBatchClusterer.clusters(for: inkStrokes)
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

            let clusterDrawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(
                PKDrawing(strokes: strokePairs.map(\.0))
            )
            return LeadSheetChordInkRecognitionBatchTarget(
                measureID: target.measureID,
                fraction: target.fraction,
                strokes: strokePairs.map(\.1),
                drawingData: clusterDrawing.dataRepresentation(),
                drawing: clusterDrawing
            )
        }
    }

    private static func draftBarlineLaneClusters(
        for strokes: [InkStroke],
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout,
        draftBarlines: [DraftBarline]
    ) -> [ChordInkBatchCluster] {
        guard !draftBarlines.isEmpty else {
            return []
        }

        let lanePositions = draftBarlineLanePositions(
            for: draftBarlines,
            pageLayout: pageLayout
        )
        guard !lanePositions.isEmpty else {
            return []
        }

        let indexedStrokes = strokes.enumerated()
            .filter { _, stroke in
                stroke.bounds.width >= 1 || stroke.bounds.height >= 1
            }
            .sorted { lhs, rhs in
                if lhs.element.bounds.minX == rhs.element.bounds.minX {
                    return lhs.offset < rhs.offset
                }

                return lhs.element.bounds.minX < rhs.element.bounds.minX
            }
        guard indexedStrokes.count > 1 else {
            return []
        }

        var bucketByKey = [DraftBarlineLaneClusterKey: (strokeIndices: [Int], bounds: InkBounds)]()
        for indexedStroke in indexedStrokes {
            let strokeBoundsInView = indexedStroke.element.bounds.cgRect
                .offsetBy(dx: chordFrame.minX, dy: chordFrame.minY)
            guard let laneMatch = laneMatch(
                for: strokeBoundsInView,
                in: pageLayout
            ) else {
                return []
            }

            let positions = lanePositions[laneMatch.systemIndex] ?? []
            guard !positions.isEmpty else {
                return []
            }

            let centerX = strokeBoundsInView.midX
            let segmentIndex = positions.firstIndex { centerX < $0 } ?? positions.count
            let key = DraftBarlineLaneClusterKey(
                systemIndex: laneMatch.systemIndex,
                segmentIndex: segmentIndex
            )
            if let existing = bucketByKey[key] {
                bucketByKey[key] = (
                    strokeIndices: existing.strokeIndices + [indexedStroke.offset],
                    bounds: existing.bounds.union(indexedStroke.element.bounds)
                )
            } else {
                bucketByKey[key] = (
                    strokeIndices: [indexedStroke.offset],
                    bounds: indexedStroke.element.bounds
                )
            }
        }

        return bucketByKey
            .sorted { lhs, rhs in
                if lhs.key.systemIndex == rhs.key.systemIndex {
                    return lhs.key.segmentIndex < rhs.key.segmentIndex
                }

                return lhs.key.systemIndex < rhs.key.systemIndex
            }
            .map { _, value in
                ChordInkBatchCluster(
                    strokeIndices: value.strokeIndices,
                    bounds: value.bounds
                )
            }
            .filter(\.isUsable)
    }

    private static func draftBarlineLanePositions(
        for draftBarlines: [DraftBarline],
        pageLayout: LeadSheetPageLayout
    ) -> [Int: [CGFloat]] {
        var positionsBySystemIndex = [Int: [CGFloat]]()

        for barline in draftBarlines where barline.isRenderable {
            guard let match = systemLaneMatch(
                containing: barline.measureID,
                in: pageLayout
            ) else {
                continue
            }

            let xPosition = match.laneFrame.minX + match.laneFrame.width * CGFloat(barline.fraction)
            positionsBySystemIndex[match.systemIndex, default: []].append(xPosition)
        }

        return positionsBySystemIndex.mapValues { positions in
            Array(Set(positions.map { ($0 * 10).rounded() / 10 })).sorted()
        }
    }

    private static func systemLaneMatch(
        containing measureID: UUID,
        in pageLayout: LeadSheetPageLayout
    ) -> (systemIndex: Int, laneFrame: CGRect)? {
        for system in pageLayout.systems {
            guard system.measures.contains(where: { $0.sourceMeasureID == measureID }),
                  let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                    for: system,
                    paperFrame: pageLayout.paperFrame
                  ) else {
                continue
            }

            return (system.index, laneFrame)
        }

        return nil
    }

    private static func laneMatch(
        for boundsInView: CGRect,
        in pageLayout: LeadSheetPageLayout
    ) -> (systemIndex: Int, laneFrame: CGRect)? {
        pageLayout.systems
            .compactMap { system -> (systemIndex: Int, laneFrame: CGRect, area: CGFloat)? in
                guard let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                    for: system,
                    paperFrame: pageLayout.paperFrame
                ) else {
                    return nil
                }

                let expandedLaneFrame = laneFrame.insetBy(dx: -8, dy: -10)
                let intersection = expandedLaneFrame.intersection(boundsInView)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                guard area > 0 || expandedLaneFrame.contains(CGPoint(x: boundsInView.midX, y: boundsInView.midY)) else {
                    return nil
                }

                return (system.index, laneFrame, area)
            }
            .max { lhs, rhs in
                lhs.area < rhs.area
            }
            .map { match in
                (match.systemIndex, match.laneFrame)
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
        if let targetMeasure,
           let measureID = targetMeasure.sourceMeasureID,
           score(inkBoundsInView, center: inkCenter, for: targetMeasure) > 0 {
            let fraction = (inkCenter.x - targetMeasure.chordBandFrame.minX)
                / max(1, targetMeasure.chordBandFrame.width)
            return (measureID, Double(min(max(fraction, 0), 0.9999)))
        }

        return openLaneFallbackTarget(at: inkCenter, in: pageLayout)
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

    private static func openLaneFallbackTarget(
        at center: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> (measureID: UUID, fraction: Double)? {
        for system in pageLayout.systems {
            let measures = system.measures.compactMap { measure -> LeadSheetMeasureLayout? in
                guard measure.sourceMeasureID != nil else {
                    return nil
                }

                return measure
            }
            guard let targetMeasure = measures.last,
                  let measureID = targetMeasure.sourceMeasureID,
                  let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                    for: system,
                    paperFrame: pageLayout.paperFrame
                  ),
                  laneFrame.insetBy(dx: -8, dy: -8).contains(center) else {
                continue
            }

            let fraction = (center.x - laneFrame.minX) / max(1, laneFrame.width)
            return (measureID, Double(min(max(fraction, 0), 0.9999)))
        }

        return nil
    }

    private static func measureLaneClusters(
        for strokes: [InkStroke],
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout
    ) -> [ChordInkBatchCluster] {
        let indexedStrokes = strokes.enumerated()
            .filter { _, stroke in
                stroke.bounds.width >= 1 || stroke.bounds.height >= 1
            }
            .sorted { lhs, rhs in
                if lhs.element.bounds.minX == rhs.element.bounds.minX {
                    return lhs.offset < rhs.offset
                }

                return lhs.element.bounds.minX < rhs.element.bounds.minX
            }

        guard indexedStrokes.count > 1 else {
            return []
        }

        var clusters = [ChordInkBatchCluster]()
        var currentMeasureID: UUID?
        var currentIndices = [Int]()
        var currentBounds: InkBounds?

        for indexedStroke in indexedStrokes {
            let stroke = indexedStroke.element
            guard let target = target(
                forInkBounds: stroke.bounds.cgRect,
                chordFrame: chordFrame,
                pageLayout: pageLayout
            ) else {
                return []
            }

            if let measureID = currentMeasureID,
               measureID != target.measureID,
               let bounds = currentBounds {
                clusters.append(
                    ChordInkBatchCluster(
                        strokeIndices: currentIndices,
                        bounds: bounds
                    )
                )
                currentMeasureID = target.measureID
                currentIndices = [indexedStroke.offset]
                currentBounds = stroke.bounds
            } else {
                currentMeasureID = target.measureID
                currentIndices.append(indexedStroke.offset)
                currentBounds = currentBounds?.union(stroke.bounds) ?? stroke.bounds
            }
        }

        if let currentBounds {
            clusters.append(
                ChordInkBatchCluster(
                    strokeIndices: currentIndices,
                    bounds: currentBounds
                )
            )
        }

        return clusters.filter(\.isUsable)
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
