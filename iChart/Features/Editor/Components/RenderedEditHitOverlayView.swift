#if canImport(UIKit)
import UIKit

final class RenderedEditHitOverlayView: UIView {
    var containsEditableControl: ((CGPoint) -> Bool)?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, isUserInteractionEnabled else {
            return false
        }

        return containsEditableControl?(point) ?? false
    }
}
#endif
