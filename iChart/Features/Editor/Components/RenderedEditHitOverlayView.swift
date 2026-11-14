#if canImport(UIKit)
import UIKit

final class RenderedEditHitOverlayView: UIView {
    var containsEditableControl: ((CGPoint) -> Bool)?
    var editableTouchMoved: ((CGPoint, UITouch.TouchType) -> Void)?

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // A Pencil can leave and return between delivered positions. Keep
            // all available samples so that returning cannot revive deletion.
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                editableTouchMoved?(sample.location(in: self), touch.type)
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, isUserInteractionEnabled else {
            return false
        }

        return containsEditableControl?(point) ?? false
    }
}
#endif
