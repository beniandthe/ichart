#if canImport(UIKit)
import PencilKit
import UIKit

final class LeadSheetScopedInkCanvasView: PKCanvasView {
    var manualEraseEnabled = false {
        didSet {
            guard oldValue != manualEraseEnabled else {
                return
            }

            lastManualEraseLocation = nil
        }
    }

    var manualEraseHandler: ((CGPoint, CGPoint) -> Void)?
    var localInputFrames: [CGRect] = [] {
        didSet {
            guard oldValue != localInputFrames else {
                return
            }

            setNeedsLayout()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else {
            return false
        }
        guard !localInputFrames.isEmpty else {
            return true
        }

        return localInputFrames.contains { inputFrame in
            inputFrame.insetBy(dx: -2, dy: -2).contains(point)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard handleManualErase(touches, with: event) else {
            super.touchesBegan(touches, with: event)
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard handleManualErase(touches, with: event) else {
            super.touchesMoved(touches, with: event)
            return
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if handleManualErase(touches, with: event) {
            lastManualEraseLocation = nil
            return
        }

        lastManualEraseLocation = nil
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastManualEraseLocation = nil
        guard manualEraseEnabled else {
            super.touchesCancelled(touches, with: event)
            return
        }
    }

    private var lastManualEraseLocation: CGPoint?

    private func handleManualErase(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard manualEraseEnabled,
              let touch = touches.first else {
            return false
        }

        let location = touch.location(in: self)
        guard point(inside: location, with: event) else {
            lastManualEraseLocation = nil
            return false
        }

        let previousLocation = lastManualEraseLocation ?? touch.previousLocation(in: self)
        lastManualEraseLocation = location
        manualEraseHandler?(previousLocation, location)
        return true
    }
}
#endif
