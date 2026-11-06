#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class LibraryLoadRecoveryLayoutTests: XCTestCase {
    func testRecoveryGuidanceAndRetryRemainReachableInNarrowLargestTextLayout() async throws {
        var retryCount = 0
        let mounted = try await mount(IChartLibraryLoadRecoveryView { retryCount += 1 })
        let expectedText: Set<String> = [
            "Your Saved Library Couldn’t Be Opened",
            "Editing and cloud sync are paused to protect your saved charts. Retry loading your saved library; your saved file has not been replaced.",
            "If loading still fails, keep this installation and contact support@useichart.com."
        ]
        var reachedText: Set<String> = []
        var activatedRetry = false

        for _ in 0..<32 {
            try await settle(mounted.window)
            for node in try NativeAccessibilityLookup.nodes(in: mounted.host.view) {
                let frame = node.frame(in: mounted.window)
                guard !frame.intersection(mounted.viewport).isEmpty else { continue }
                if let label = node.element.accessibilityLabel, expectedText.contains(label) {
                    assertHorizontallyContained(frame, in: mounted.viewport)
                    reachedText.insert(label)
                }
                if !activatedRetry, node.isButton,
                   node.element.accessibilityLabel == "Retry Loading",
                   mounted.viewport.insetBy(dx: -1, dy: -1).contains(frame) {
                    XCTAssertTrue(node.isEnabled)
                    if let control = node.element as? UIButton {
                        control.sendActions(for: .touchUpInside)
                    } else {
                        XCTAssertTrue(node.element.accessibilityActivate())
                    }
                    activatedRetry = true
                }
            }

            let maximum = max(0, mounted.scroll.contentSize.height - mounted.scroll.bounds.height)
            let next = min(maximum, mounted.scroll.contentOffset.y + mounted.scroll.bounds.height * 0.55)
            if next <= mounted.scroll.contentOffset.y + 0.5 { break }
            mounted.scroll.setContentOffset(CGPoint(x: 0, y: next), animated: false)
        }

        try await settle(mounted.window)
        XCTAssertEqual(reachedText, expectedText, "The complete production recovery guidance must remain reachable by scrolling.")
        XCTAssertTrue(activatedRetry, "The real Retry Loading button must fit within the narrow viewport.")
        XCTAssertEqual(retryCount, 1, "Activating Retry Loading invokes its supplied recovery action exactly once.")
        await mounted.close()
    }

    private func mount(_ content: IChartLibraryLoadRecoveryView) async throws -> Mounted {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let container = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = container
        let host = UIHostingController(rootView: AnyView(content
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            .environment(\.accessibilityEnabled, true)))
        container.addChild(host)
        host.view.frame = CGRect(x: 18, y: 54, width: 360,
            height: min(420, window.bounds.height - 108))
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        window.makeKeyAndVisible()

        for _ in 0..<40 {
            window.layoutIfNeeded()
            if window.isKeyWindow, host.view.window === window,
               descendants(host.view).contains(where: { $0 is UIScrollView }) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await settle(window)
        let scroll = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }
            .max { $0.bounds.height < $1.bounds.height })
        let mounted = Mounted(window: window, host: host, scroll: scroll, previousWindow: previous)
        addTeardownBlock { @MainActor in await mounted.close() }
        XCTAssertEqual(mounted.viewport.width, 360, accuracy: 0.5)
        return mounted
    }

    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<5 {
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func assertHorizontallyContained(_ frame: CGRect, in viewport: CGRect,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 1, file: file, line: line)
    }

    private func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(descendants) }

    @MainActor
    private final class Mounted {
        let window: UIWindow
        let host: UIHostingController<AnyView>
        let scroll: UIScrollView
        let previousWindow: UIWindow?
        private var closed = false
        var viewport: CGRect { host.view.convert(host.view.bounds, to: window) }

        init(window: UIWindow, host: UIHostingController<AnyView>, scroll: UIScrollView, previousWindow: UIWindow?) {
            self.window = window
            self.host = host
            self.scroll = scroll
            self.previousWindow = previousWindow
        }

        func close() async {
            guard !closed else { return }
            closed = true
            window.endEditing(true)
            try? await Task.sleep(nanoseconds: 50_000_000)
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
    }
}
#endif
