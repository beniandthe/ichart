#if canImport(UIKit)
import PencilKit
import UIKit

struct FreeInkArticulationSelection: Identifiable, Equatable {
    let id: UUID
    var kind: FreeInkArticulationKind?
    var measureID: UUID
    var beatIndex: Int
}

enum FreeInkArticulationSelectionError: LocalizedError {
    case empty
    case ambiguous
    case outsideMeasure
    case canvasNotReady

    var errorDescription: String? {
        switch self {
        case .empty: return "Drag a box around one complete handwritten fermata or accent."
        case .ambiguous: return "Select one complete fermata or accent with space around its strokes."
        case .outsideMeasure: return "Select a mark over a measure on the staff."
        case .canvasNotReady: return "Let the current stroke finish, then drag a box around the mark again."
        }
    }
}

/// Keep the full drag extent so a box or a loop selects the same ink.
struct FreeInkArticulationMarquee {
    static let touchTypes: [UITouch.TouchType] = [.direct, .pencil, .indirectPointer]

    private(set) var bounds: CGRect

    init(start: CGPoint) {
        bounds = CGRect(origin: start, size: .zero)
    }

    mutating func include(_ point: CGPoint) {
        let x = min(bounds.minX, point.x)
        let y = min(bounds.minY, point.y)
        bounds = CGRect(x: x, y: y,
            width: max(bounds.maxX, point.x) - x,
            height: max(bounds.maxY, point.y) - y)
    }
}

@MainActor
final class FreeInkArticulationCoordinator {
    var conversion: ((UUID, FreeInkArticulationKind, UUID, Int) -> Bool)?
    var restoration: ((UUID) -> Bool)?
    var cancellation: (() -> Void)?

    func convert(
        selectionID: UUID, kind: FreeInkArticulationKind, measureID: UUID, beatIndex: Int
    ) -> Bool {
        conversion?(selectionID, kind, measureID, beatIndex) ?? false
    }

    func restore(articulationID: UUID) -> Bool {
        restoration?(articulationID) ?? false
    }

    func cancel() {
        cancellation?()
    }
}

struct FreeInkArticulationStrokeSelection {
    let indices: [Int]
    let drawing: PKDrawing

    static func select(in rect: CGRect, drawing: PKDrawing) throws -> Self {
        var indices: [Int] = []
        var strokes: [PKStroke] = []
        for (index, stroke) in drawing.strokes.enumerated() where rect.intersects(stroke.renderBounds) {
            guard rect.contains(stroke.renderBounds), strokes.count < 2 else {
                throw FreeInkArticulationSelectionError.ambiguous
            }
            indices.append(index)
            strokes.append(stroke)
        }
        guard !strokes.isEmpty else { throw FreeInkArticulationSelectionError.empty }
        return Self(indices: indices, drawing: PKDrawing(strokes: strokes))
    }

    func remainingDrawing(in source: PKDrawing) -> PKDrawing {
        let removed = Set(indices)
        return PKDrawing(strokes: source.strokes.enumerated().compactMap {
            removed.contains($0.offset) ? nil : $0.element
        })
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
