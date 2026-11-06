#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Uses synthetic charts to check the optional font controls remain reachable
/// through the new disclosure without changing any chart content on entry.
@MainActor
final class SheetClarityWorkflowTests: XCTestCase {
    func testFontsKeepsCustomizationReachableForBothChartLayouts() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Disposable font choices", layoutStyle: style)
            let original = chart
            let host = UIHostingController(rootView: ChartTypographySheetView(chart: Binding(
                get: { chart }, set: { chart = $0 }
            )).environment(\.accessibilityEnabled, true))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousWindow?.makeKey()
            }
            try await settle(window)

            let initial = try NativeAccessibilityLookup.nodes(in: window)
            for text in ["Choose a font set", "Tap a matched set to update this chart and its PDF immediately.",
                "Open Customize to change individual parts."] {
                XCTAssertTrue(initial.contains {
                    !$0.isButton && $0.element.accessibilityLabel?.contains(text) == true
                }, "The visible Fonts helper must explain \(text)")
            }
            XCTAssertFalse(initial.contains {
                ($0.element.accessibilityLabel ?? "").hasPrefix("Use Matched Set")
            }, "Individual overrides should start collapsed")

            let customize = try await find("Customize", in: window)
            XCTAssertTrue(customize.isEnabled)
            if let button = customize.element as? UIButton {
                button.sendActions(for: .touchUpInside)
            } else {
                XCTAssertTrue(customize.element.accessibilityActivate())
            }
            try await settle(window)

            // Each group used to be permanently exposed. The disclosure must
            // retain all four destinations and their standard row controls.
            for heading in ["Chord Font", "Header Font", "Text / Cue Font", "Notation Symbols"] {
                _ = try await find(heading, in: window)
            }
            XCTAssertEqual(chart, original, "Reading or expanding font choices must not mutate the chart")
        }
    }

    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<3 {
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func find(_ label: String, in window: UIWindow) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<24 {
            let nodes = try NativeAccessibilityLookup.nodes(in: window)
            if let found = nodes.first(where: { $0.element.accessibilityLabel == label }) {
                return found
            }
            let scrollViews = descendants(window).compactMap { $0 as? UIScrollView }
                .filter { $0.contentSize.height > $0.bounds.height + 1 }
            let scrollView = try XCTUnwrap(scrollViews.max { $0.bounds.height < $1.bounds.height })
            let maximumOffset = max(-scrollView.adjustedContentInset.top,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x,
                y: min(maximumOffset, scrollView.contentOffset.y + scrollView.bounds.height * 0.45)), animated: false)
            try await settle(window)
        }
        XCTFail("Missing reachable font control: \(label)")
        throw MissingControl.notFound
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private enum MissingControl: Error { case notFound }
}
#endif
