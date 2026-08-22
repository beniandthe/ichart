import CoreGraphics
import Foundation

enum RenderedEditObjectID: Hashable {
    case measure(UUID)
    case chord(UUID)
    case committedChordBarline(afterMeasureID: UUID)
    case cueText(UUID)
    case roadmapMarker(UUID)
    case repeatSpan(UUID)
    case endingSpan(UUID)
    case timeSignatureChange(afterMeasureID: UUID)
    case keyChange(measureID: UUID)
    case header
}

enum RenderedEditAction: Hashable {
    case select
    case move
    case resizeLeading
    case resizeTrailing
    case resizeLeft
    case resizeRight
    case grow
    case shrink
    case editText
    case correctChord
    case delete
    case openInspector

    var isDestructive: Bool {
        self == .delete
    }

    var isMove: Bool {
        self == .move
    }

    var isSelection: Bool {
        self == .select
    }
}

enum RenderedEditHitPriority: Int, Comparable {
    case pageFallback = 0
    case measureSelect = 10
    case objectBodySelect = 20
    case selectedObjectMoveBody = 30
    case selectedObjectEditControl = 40
    case selectedObjectResizeHandle = 50
    case selectedObjectDestructiveControl = 60

    static func < (lhs: RenderedEditHitPriority, rhs: RenderedEditHitPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum RenderedEditMutationRisk: Int, Comparable {
    case nonMutating = 0
    case visual = 10
    case content = 20
    case structural = 30
    case destructive = 40

    static func < (lhs: RenderedEditMutationRisk, rhs: RenderedEditMutationRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct RenderedEditHitTarget: Hashable {
    var objectID: RenderedEditObjectID
    var action: RenderedEditAction
    var priority: RenderedEditHitPriority
    var frame: CGRect
    var requiresSelection: Bool
    var mutationRisk: RenderedEditMutationRisk

    static func highestPriority(in candidates: [RenderedEditHitTarget]) -> RenderedEditHitTarget? {
        candidates.reduce(nil) { bestCandidate, candidate in
            guard let bestCandidate else {
                return candidate
            }

            return candidate.priority > bestCandidate.priority ? candidate : bestCandidate
        }
    }

    func selectingOnly() -> RenderedEditHitTarget {
        RenderedEditHitTarget(
            objectID: objectID,
            action: .select,
            priority: selectionPriority,
            frame: frame,
            requiresSelection: false,
            mutationRisk: .nonMutating
        )
    }

    private var selectionPriority: RenderedEditHitPriority {
        switch objectID {
        case .measure:
            return .measureSelect
        default:
            return .objectBodySelect
        }
    }
}

struct RenderedEditSelectionState: Equatable {
    var selectedObjectID: RenderedEditObjectID? = nil

    var isEmpty: Bool {
        selectedObjectID == nil
    }

    func contains(_ objectID: RenderedEditObjectID) -> Bool {
        selectedObjectID == objectID
    }

    mutating func select(_ objectID: RenderedEditObjectID) {
        selectedObjectID = objectID
    }

    mutating func clear() {
        selectedObjectID = nil
    }
}

enum RenderedEditSelectionPolicy {
    static func resolvedTapTarget(
        _ hitTarget: RenderedEditHitTarget?,
        selection: RenderedEditSelectionState
    ) -> RenderedEditHitTarget? {
        guard let hitTarget else {
            return nil
        }

        guard hitTarget.requiresSelection,
              !selection.contains(hitTarget.objectID) else {
            return hitTarget
        }

        return hitTarget.selectingOnly()
    }

    static func resolvedDragTarget(
        _ hitTarget: RenderedEditHitTarget?,
        selection: RenderedEditSelectionState
    ) -> RenderedEditHitTarget? {
        guard let hitTarget,
              hitTarget.action.isMove || isResizeAction(hitTarget.action) else {
            return nil
        }

        guard hitTarget.requiresSelection else {
            return hitTarget
        }

        return selection.contains(hitTarget.objectID) ? hitTarget : nil
    }

    private static func isResizeAction(_ action: RenderedEditAction) -> Bool {
        switch action {
        case .resizeLeading, .resizeTrailing, .resizeLeft, .resizeRight:
            return true
        case .select, .move, .grow, .shrink, .editText, .correctChord, .delete, .openInspector:
            return false
        }
    }
}
