#if canImport(UIKit)
import UIKit

/// Test-only discovery of rendered UIKit and SwiftUI controls. A container may
/// vend children dynamically without ever populating accessibilityElements.
@MainActor
enum NativeAccessibilityLookup {
    @MainActor
    struct Node {
        let element: NSObject
        let owner: UIView

        var isButton: Bool {
            element is UIButton || element.accessibilityTraits.contains(.button)
        }

        var isEnabled: Bool {
            (element as? UIButton)?.isEnabled != false &&
                !element.accessibilityTraits.contains(.notEnabled)
        }

        func frame(in window: UIWindow) -> CGRect {
            if let view = element as? UIView { return view.convert(view.bounds, to: window) }
            return window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace)
        }
    }

    enum LookupError: Error { case traversalLimitExceeded }

    static func nodes(in root: UIView, limit: Int = 4_096) throws -> [Node] {
        var visited = Set<ObjectIdentifier>()
        var result: [Node] = []

        func visit(_ element: NSObject, owner: UIView) throws {
            guard visited.insert(ObjectIdentifier(element)).inserted else { return }
            guard visited.count <= limit else { throw LookupError.traversalLimitExceeded }
            let owner = (element as? UIView) ?? owner
            guard isVisible(owner), !element.accessibilityElementsHidden else { return }
            result.append(Node(element: element, owner: owner))
            if let view = element as? UIView {
                for child in view.subviews { try visit(child, owner: view) }
            }
            let count = element.accessibilityElementCount()
            if count > 0 && count != NSNotFound && count > limit {
                throw LookupError.traversalLimitExceeded
            }
            // UIKit's automation getter can enumerate the dynamic provider
            // internally. Never feed it an invalid negative count or an
            // oversized provider before enforcing our own traversal budget.
            let automation = count < 0 ? nil : element.automationElements
            for children in [element.accessibilityElements, automation] {
                guard let children else { continue }
                guard children.count <= limit else { throw LookupError.traversalLimitExceeded }
                for child in children {
                    if let child = child as? NSObject { try visit(child, owner: owner) }
                }
            }
            // NSNotFound/negative counts mean this object does not vend a container.
            if count > 0 && count != NSNotFound {
                guard count <= limit else { throw LookupError.traversalLimitExceeded }
                for index in 0..<count {
                    if let child = element.accessibilityElement(at: index) as? NSObject {
                        try visit(child, owner: owner)
                    }
                }
            }
        }

        try visit(root, owner: root)
        return result
    }

    static func matching(_ label: String, in root: UIView, buttonsOnly: Bool = false) throws -> [Node] {
        guard let window = (root as? UIWindow) ?? root.window else { return [] }
        return try nodes(in: root).filter { node in
            guard ((node.owner as? UIWindow) ?? node.owner.window) === window,
                  node.element.accessibilityLabel == label,
                  !buttonsOnly || node.isButton else { return false }
            let frame = node.frame(in: window)
            return frame.origin.x.isFinite && frame.origin.y.isFinite &&
                frame.width.isFinite && frame.height.isFinite && !frame.isEmpty &&
                !frame.intersection(window.bounds).isEmpty
        }
    }

    private static func isVisible(_ view: UIView) -> Bool {
        guard (view is UIWindow || view.window != nil), !view.bounds.isEmpty else { return false }
        var ancestor: UIView? = view
        while let current = ancestor {
            if current.isHidden || current.alpha == 0 { return false }
            ancestor = current.superview
        }
        return true
    }
}
#endif
