#if canImport(UIKit)
import UIKit
import XCTest

@MainActor
final class NativeAccessibilityLookupTests: XCTestCase {
    func testDynamicContainerWithoutStaticElementsExposesNestedButton() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let nested = DynamicLookupContainer()
        let button = makeElement(in: fixture.root, label: "Clear Draft Ink", traits: .button)
        nested.children = [button]
        fixture.root.children = [nested]
        XCTAssertNil(fixture.root.accessibilityElements)
        let nodes = try NativeAccessibilityLookup.nodes(in: fixture.root)
        XCTAssertTrue(nodes.contains { $0.element === button }, "Nodes: \(nodes.map { String(describing: type(of: $0.element)) })")
        XCTAssertFalse(button.accessibilityFrame.isEmpty, "Container frame: \(button.accessibilityFrameInContainerSpace), window: \(fixture.window.frame), root: \(fixture.root.bounds)")
        let match = try XCTUnwrap(NativeAccessibilityLookup.matching("Clear Draft Ink", in: fixture.root, buttonsOnly: true).first)
        XCTAssertTrue(match.element === button)
        XCTAssertTrue(match.isEnabled)
        XCTAssertEqual(try NativeAccessibilityLookup.matching("Clear Draft Ink", in: fixture.window, buttonsOnly: true).count, 1,
            "A UIWindow search must include the mounted view's accessibility children.")
    }

    func testAutomationOnlyChildrenAreDiscovered() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let button = makeElement(in: fixture.root, label: "Done", traits: .button)
        fixture.root.automationElements = [button]
        XCTAssertEqual(try NativeAccessibilityLookup.matching("Done", in: fixture.root, buttonsOnly: true).count, 1)
    }

    func testDuplicateAndCyclicContainersTerminateWithoutDuplicatingMatches() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let nested = DynamicLookupContainer()
        defer { nested.children = [] }
        let button = makeElement(in: fixture.root, label: "Done", traits: .button)
        nested.children = [nested, fixture.root, button]
        fixture.root.children = [nested, button]
        fixture.root.accessibilityElements = [button, nested]
        fixture.root.automationElements = [button]
        XCTAssertEqual(try NativeAccessibilityLookup.matching("Done", in: fixture.root, buttonsOnly: true).count, 1)
    }

    func testDisabledButtonCannotBeReplacedBySameTitleTextDecoy() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let text = makeElement(in: fixture.root, label: "Clear Draft Ink", traits: .staticText)
        let button = makeElement(in: fixture.root, label: "Clear Draft Ink", traits: [.button, .notEnabled])
        fixture.root.children = [text, button]
        let matches = try NativeAccessibilityLookup.matching("Clear Draft Ink", in: fixture.root, buttonsOnly: true)
        XCTAssertEqual(matches.count, 1)
        XCTAssertFalse(try XCTUnwrap(matches.first).isEnabled)
    }

    func testHiddenDetachedAndOffscreenControlsDoNotSatisfyLookup() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let hidden = UIButton(frame: CGRect(x: 0, y: 0, width: 90, height: 40))
        hidden.accessibilityLabel = "Done"
        hidden.isHidden = true
        fixture.root.addSubview(hidden)
        let offscreen = makeElement(in: fixture.root, label: "Done", traits: .button)
        offscreen.accessibilityFrame = CGRect(x: -500, y: -500, width: 50, height: 40)
        fixture.root.children = [offscreen]
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Done", in: fixture.root).isEmpty)
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Done", in: hidden).isEmpty)
        let detached = UIButton(frame: hidden.frame)
        detached.accessibilityLabel = "Done"
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Done", in: detached).isEmpty)
    }

    func testInvalidCountsAndTraversalBudgetFailSafely() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.root.reportedCount = NSNotFound
        XCTAssertEqual(try NativeAccessibilityLookup.nodes(in: fixture.root).count, 1)
        fixture.root.reportedCount = -1
        XCTAssertEqual(try NativeAccessibilityLookup.nodes(in: fixture.root).count, 1)
        fixture.root.reportedCount = 5_000
        XCTAssertThrowsError(try NativeAccessibilityLookup.nodes(in: fixture.root))
        fixture.root.reportedCount = nil
        fixture.root.children = [DynamicLookupContainer(), DynamicLookupContainer()]
        XCTAssertThrowsError(try NativeAccessibilityLookup.nodes(in: fixture.root, limit: 2))
    }

    private func makeElement(in root: UIView, label: String, traits: UIAccessibilityTraits) -> UIAccessibilityElement {
        let element = UIAccessibilityElement(accessibilityContainer: root)
        element.accessibilityLabel = label
        element.accessibilityTraits = traits
        element.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(
            CGRect(x: 20, y: 20, width: 90, height: 40), in: root)
        return element
    }

    private func makeFixture() throws -> LookupWindowFixture {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        let root = DynamicLookupView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        host.view = root
        window.frame = root.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return LookupWindowFixture(window: window, root: root, previousKeyWindow: previousKeyWindow)
    }

    @MainActor
    private struct LookupWindowFixture {
        let window: UIWindow
        let root: DynamicLookupView
        let previousKeyWindow: UIWindow?
        func close() {
            root.children = []
            root.accessibilityElements = nil
            root.automationElements = nil
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
    }
}

@MainActor
private final class DynamicLookupView: UIView {
    var children: [NSObject] = []
    var reportedCount: Int?
    override func accessibilityElementCount() -> Int { reportedCount ?? children.count }
    override func accessibilityElement(at index: Int) -> Any? { children.indices.contains(index) ? children[index] : nil }
}

@MainActor
private final class DynamicLookupContainer: NSObject {
    var children: [NSObject] = []
    override func accessibilityElementCount() -> Int { children.count }
    override func accessibilityElement(at index: Int) -> Any? { children.indices.contains(index) ? children[index] : nil }
}
#endif
