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

    var isResize: Bool {
        switch self {
        case .resizeLeading, .resizeTrailing, .resizeLeft, .resizeRight:
            return true
        case .select, .move, .grow, .shrink, .editText, .correctChord, .delete, .openInspector:
            return false
        }
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
    case objectBodyMove = 35
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
    // Padded controls must never consume a visible object's body. Keep the
    // generous outer target while reserving these regions for that object.
    var excludedFrames: [CGRect] = []

    func contains(_ location: CGPoint) -> Bool {
        frame.contains(location) && !excludedFrames.contains { $0.contains(location) }
    }

    static func highestPriority(in candidates: [RenderedEditHitTarget]) -> RenderedEditHitTarget? {
        candidates.reduce(nil) { bestCandidate, candidate in
            guard let bestCandidate else {
                return candidate
            }

            return candidate.priority > bestCandidate.priority ? candidate : bestCandidate
        }
    }

    static func highestPriority(
        in candidates: [RenderedEditHitTarget],
        nearestTo location: CGPoint
    ) -> RenderedEditHitTarget? {
        candidates.reduce(nil) { bestCandidate, candidate in
            guard let bestCandidate else {
                return candidate
            }

            if candidate.priority != bestCandidate.priority {
                return candidate.priority > bestCandidate.priority ? candidate : bestCandidate
            }

            let candidateDistance = candidate.frame.centerSquaredDistance(to: location)
            let bestDistance = bestCandidate.frame.centerSquaredDistance(to: location)
            return candidateDistance < bestDistance ? candidate : bestCandidate
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

struct RenderedEditTapIntent {
    private var initialTarget: RenderedEditHitTarget?
    private var wasCancelledByDrag = false
    private var startLocation: CGPoint?
    private var screenPointsPerDisplayedPoint: CGFloat = 1
    private var maximumScreenMovement: CGFloat = 4

    mutating func begin(target: RenderedEditHitTarget?, startLocation: CGPoint? = nil,
        screenPointsPerDisplayedPoint: CGFloat = 1, maximumScreenMovement: CGFloat = 4) {
        initialTarget = target
        wasCancelledByDrag = false
        self.startLocation = startLocation
        self.screenPointsPerDisplayedPoint = max(screenPointsPerDisplayedPoint, 0.1)
        self.maximumScreenMovement = maximumScreenMovement
    }

    mutating func cancelForDrag() {
        wasCancelledByDrag = true
    }

    mutating func recordMovement(to location: CGPoint) {
        guard let startLocation else { return }
        if hypot(location.x - startLocation.x, location.y - startLocation.y)
            * screenPointsPerDisplayedPoint > maximumScreenMovement {
            wasCancelledByDrag = true
        }
    }

    mutating func reset() {
        initialTarget = nil
        wasCancelledByDrag = false
        startLocation = nil
    }

    func resolvedTarget(at endTarget: RenderedEditHitTarget?, endLocation: CGPoint? = nil) -> RenderedEditHitTarget? {
        guard !wasCancelledByDrag, let endTarget else { return nil }
        guard endTarget.action.isDestructive else { return endTarget }
        guard let initialTarget,
              initialTarget.objectID == endTarget.objectID,
              initialTarget.action == endTarget.action else { return nil }
        if let startLocation {
            guard let endLocation,
                  hypot(endLocation.x - startLocation.x, endLocation.y - startLocation.y)
                    * screenPointsPerDisplayedPoint <= maximumScreenMovement else { return nil }
        }
        return endTarget
    }
}

private extension CGRect {
    func centerSquaredDistance(to point: CGPoint) -> CGFloat {
        let deltaX = midX - point.x
        let deltaY = midY - point.y
        return deltaX * deltaX + deltaY * deltaY
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

struct RenderedEditDragState: Equatable {
    var target: RenderedEditHitTarget
    var startLocation: CGPoint

    init?(target: RenderedEditHitTarget, startLocation: CGPoint) {
        guard target.action.isMove || target.action.isResize else {
            return nil
        }

        self.target = target
        self.startLocation = startLocation
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
              hitTarget.action.isMove || hitTarget.action.isResize else {
            return nil
        }

        guard hitTarget.requiresSelection else {
            return hitTarget
        }

        return selection.contains(hitTarget.objectID) ? hitTarget : nil
    }
}
