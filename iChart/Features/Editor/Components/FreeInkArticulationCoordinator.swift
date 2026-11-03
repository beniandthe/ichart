#if canImport(UIKit)
import PencilKit
import UIKit

@MainActor
final class FreeInkArticulationCoordinator {
    var restoration: ((UUID) -> Bool)?
    var undoLastDeletion: (() -> Bool)?

    func restore(articulationID: UUID) -> Bool {
        restoration?(articulationID) ?? false
    }

    func undoDeletion() -> Bool {
        undoLastDeletion?() ?? false
    }
}

enum FreeInkArticulationSourceInk {
    struct Candidate {
        let kind: FreeInkArticulationKind
        let source: PKDrawing
        let remaining: PKDrawing
    }

    static func automaticCandidate(in drawing: PKDrawing, firstNewStrokeIndex: Int) -> Candidate? {
        let strokes = drawing.strokes
        guard firstNewStrokeIndex >= 0, let last = strokes.indices.last,
              last >= firstNewStrokeIndex else { return nil }
        let eligible = Set((max(firstNewStrokeIndex, last - 1)...last).filter {
            strokes[$0].mask == nil
        })
        guard eligible.contains(last) else { return nil }
        let timelineOrigin = strokes[last].path.creationDate
        let input = strokes.enumerated().map { index, stroke in
            if eligible.contains(index) {
                return PencilKitInkAdapter.inkStroke(from: stroke, timelineOrigin: timelineOrigin)
            }
            // Existing strokes can veto a nearby match. Only materialize the
            // centerlines of new strokes to keep the idle check inexpensive.
            let bounds = stroke.renderBounds
            return InkStroke(points: [], bounds: InkBounds(minX: bounds.minX,
                minY: bounds.minY, maxX: bounds.maxX, maxY: bounds.maxY))
        }
        guard let match = FreeInkArticulationRecognizer.automaticCandidate(
            in: input, eligibleStrokeIndices: eligible
        ) else { return nil }
        return Candidate(kind: match.kind,
            source: PKDrawing(strokes: match.indices.map { strokes[$0] }),
            remaining: PKDrawing(strokes: strokes.enumerated().compactMap {
                match.indices.contains($0.offset) ? nil : $0.element
            }))
    }

    static func restore(
        _ drawing: PKDrawing,
        source: PersistentInkCoordinateSpace?,
        destination: PersistentInkCoordinateSpace
    ) -> PKDrawing? {
        guard !drawing.strokes.isEmpty,
              let sourceAnchors = source?.measureAnchors, sourceAnchors.count == 1,
              let sourceAnchor = sourceAnchors.first,
              let targetAnchor = destination.measureAnchors?.first(where: { $0.measureID == sourceAnchor.measureID }),
              (sourceAnchor.staffFrame == nil) == (targetAnchor.staffFrame == nil) else { return nil }

        let sourceFrame = (sourceAnchor.staffFrame ?? sourceAnchor.frame).rect
        let targetFrame = (targetAnchor.staffFrame ?? targetAnchor.frame).rect
        guard let transform = LeadSheetPersistentInkCoordinateSpacePolicy.frameTransform(
            from: sourceFrame, to: targetFrame) else { return nil }
        guard !transform.isIdentity else { return drawing }
        return drawing.transformed(using: transform)
    }
}
#endif
