#if canImport(UIKit)
import UIKit

enum LeadSheetFreeInkNavigationPolicy {
    static let hintText = "Pinch to zoom. Use two fingers to pan."

    static func usesTwoFingerPan(in interactionMode: EditorCanvasMode) -> Bool {
        interactionMode == .freeHand
    }

    static func configureParentPan(_ recognizer: UIPanGestureRecognizer) {
        setTouchCounts(minimum: 2, maximum: 2, on: recognizer)
        let directTouches = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        if recognizer.allowedTouchTypes != directTouches {
            recognizer.allowedTouchTypes = directTouches
        }
        if !recognizer.requiresExclusiveTouchType {
            recognizer.requiresExclusiveTouchType = true
        }
    }

    /// Preserve the enclosing scroll view's configuration across tool changes,
    /// detachments and moves to another parent; never assume UIKit defaults.
    struct ParentPanConfiguration {
        let minimumNumberOfTouches: Int
        let maximumNumberOfTouches: Int
        let allowedTouchTypes: [NSNumber]
        let requiresExclusiveTouchType: Bool

        init(_ recognizer: UIPanGestureRecognizer) {
            minimumNumberOfTouches = recognizer.minimumNumberOfTouches
            maximumNumberOfTouches = recognizer.maximumNumberOfTouches
            allowedTouchTypes = recognizer.allowedTouchTypes
            requiresExclusiveTouchType = recognizer.requiresExclusiveTouchType
        }

        func restore(to recognizer: UIPanGestureRecognizer) {
            setTouchCounts(minimum: minimumNumberOfTouches,
                maximum: maximumNumberOfTouches, on: recognizer)
            if recognizer.allowedTouchTypes != allowedTouchTypes {
                recognizer.allowedTouchTypes = allowedTouchTypes
            }
            if recognizer.requiresExclusiveTouchType != requiresExclusiveTouchType {
                recognizer.requiresExclusiveTouchType = requiresExclusiveTouchType
            }
        }
    }

    private static func setTouchCounts(minimum: Int, maximum: Int, on recognizer: UIPanGestureRecognizer) {
        // Keep the interval valid even when restoring a parent's unusual range.
        let transitionMaximum = max(recognizer.maximumNumberOfTouches, minimum, maximum)
        if recognizer.maximumNumberOfTouches != transitionMaximum {
            recognizer.maximumNumberOfTouches = transitionMaximum
        }
        if recognizer.minimumNumberOfTouches != minimum {
            recognizer.minimumNumberOfTouches = minimum
        }
        if recognizer.maximumNumberOfTouches != maximum {
            recognizer.maximumNumberOfTouches = maximum
        }
    }
}
#endif
