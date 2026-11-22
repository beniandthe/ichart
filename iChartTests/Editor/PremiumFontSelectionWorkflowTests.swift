#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class PremiumFontSelectionWorkflowTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testFreePaidChoicesPresentUpgradeAndPreserveSavedSelectionsInBothSheetsAndStyles() async throws {
        for style in styles {
            for notationOnly in [false, true] {
                var chart = Chart.blank(title: "Saved paid typography", layoutStyle: style)
                chart.setMatchedFontFamily(.museJazz)
                let original = chart
                let mounted = try mount(chart: Binding(get: { chart }, set: { chart = $0 }),
                    premiumFontAccess: { false }, notationOnly: notationOnly)
                defer { mounted.close() }
                let prefix = notationOnly ? "appearance-font-" : "font-matched-"
                let existing = try await find(prefix + "museJazz", in: mounted.window)
                XCTAssertTrue(existing.element.accessibilityTraits.contains(.selected),
                    "A saved paid font must remain visibly selected on Basic")
                let paidChoice = try await find(prefix + "petaluma", in: mounted.window)
                XCTAssertTrue(paidChoice.isEnabled, "Paid choices remain available to open the upgrade")
                XCTAssertTrue(paidChoice.element.accessibilityHint?.contains("Pro font options") == true)
                activate(paidChoice)
                try await wait(in: mounted.window) { mounted.window.rootViewController?.presentedViewController != nil }
                XCTAssertEqual(chart, original, "Opening the font upgrade must preserve the entire chart")
            }
        }
    }

    func testProCanApplyPaidMatchedFontsInBothStyles() async throws {
        for style in styles {
            var chart = Chart.blank(title: "Pro typography", layoutStyle: style)
            let mounted = try mount(chart: Binding(get: { chart }, set: { chart = $0 }),
                premiumFontAccess: { true }, notationOnly: false)
            defer { mounted.close() }
            let paidChoice = try await find("font-matched-petaluma", in: mounted.window)
            XCTAssertFalse(paidChoice.element.accessibilityHint?.contains("Pro font options") == true)
            activate(paidChoice)
            try await wait(in: mounted.window) { chart.typography.matchedSet == .petaluma }
            XCTAssertEqual(chart.notationFont, .petaluma)
            XCTAssertNil(mounted.window.rootViewController?.presentedViewController)
        }
    }

    func testFreeCanApplyOrdinaryFontInBothSheetsAndStyles() async throws {
        for style in styles {
            for notationOnly in [false, true] {
                var chart = Chart.blank(title: "Basic typography", layoutStyle: style)
                chart.setMatchedFontFamily(.museJazz)
                chart.setHeaderFontOverride(.petaluma)
                let originalTypography = chart.typography
                let mounted = try mount(chart: Binding(get: { chart }, set: { chart = $0 }),
                    premiumFontAccess: { false }, notationOnly: notationOnly)
                defer { mounted.close() }
                let prefix = notationOnly ? "appearance-font-" : "font-matched-"
                activate(try await find(prefix + "leland", in: mounted.window))
                try await wait(in: mounted.window) { chart.notationFont == .leland }
                XCTAssertNil(mounted.window.rootViewController?.presentedViewController)
                if notationOnly {
                    XCTAssertEqual(chart.typography, originalTypography)
                } else {
                    XCTAssertEqual(chart.typography.matchedSet, .leland)
                    XCTAssertEqual(chart.typography.headerOverride, .petaluma,
                        "Choosing an available font must preserve saved paid overrides")
                }
            }
        }
    }

    func testAccessRevokedAfterTapPreventsDelayedPaidFontApplyInBothSheetsAndStyles() async throws {
        for style in styles {
            for notationOnly in [false, true] {
                var chart = Chart.blank(title: "Access changes during font edit", layoutStyle: style)
                let original = chart
                var hasAccess = true
                let mounted = try mount(chart: Binding(get: { chart }, set: { chart = $0 }),
                    premiumFontAccess: { hasAccess }, notationOnly: notationOnly)
                defer { mounted.close() }
                let prefix = notationOnly ? "appearance-font-" : "font-matched-"
                let paidChoice = try await find(prefix + "petaluma", in: mounted.window)
                activate(paidChoice)
                // Revoke synchronously before the existing 50ms progress yield.
                hasAccess = false
                try await wait(in: mounted.window) { mounted.window.rootViewController?.presentedViewController != nil }
                XCTAssertEqual(chart, original, "The delayed mutation must use current access, including chart timestamps")
                let labels = try NativeAccessibilityLookup.nodes(in: mounted.window)
                    .compactMap { $0.element.accessibilityLabel }
                XCTAssertFalse(labels.contains("Updating fonts..."), "A denied delayed edit must clear the progress overlay")
            }
        }
    }

    private func mount(chart: Binding<Chart>, premiumFontAccess: @escaping () -> Bool, notationOnly: Bool) throws -> MountedWindow {
        let store = ChartLibraryStore(charts: [chart.wrappedValue])
        let content = Group {
            if notationOnly {
                ChartAppearanceSheetView(chart: chart, panel: .notationFont, premiumFontAccess: premiumFontAccess)
            } else {
                ChartTypographySheetView(chart: chart, premiumFontAccess: premiumFontAccess)
            }
        }
        .environmentObject(store)
        .environmentObject(IChartStoreKitSubscriptionStore.live())
        .environment(\.accessibilityEnabled, true)
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        return MountedWindow(window: window, previous: previous)
    }

    private func find(_ identifier: String, in window: UIWindow) async throws -> NativeAccessibilityLookup.Node {
        for view in descendants(window).compactMap({ $0 as? UIScrollView }) {
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: -view.adjustedContentInset.top), animated: false)
        }
        for attempt in 0..<35 {
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            if let node = try NativeAccessibilityLookup.nodes(in: window).first(where: {
                $0.identifier == identifier && $0.isButton && window.bounds.intersects($0.frame(in: window))
            }) {
                return node
            }
            if attempt > 3 {
                for view in descendants(window).compactMap({ $0 as? UIScrollView })
                    where view.contentSize.height > view.bounds.height + 1 {
                    let maximum = max(-view.adjustedContentInset.top,
                        view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
                    view.setContentOffset(CGPoint(x: view.contentOffset.x,
                        y: min(maximum, view.contentOffset.y + view.bounds.height * 0.35)), animated: false)
                }
            }
        }
        XCTFail("Missing reachable font choice: \(identifier)")
        throw WorkflowError.missingControl
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) {
        if let button = node.element as? UIButton {
            button.sendActions(for: .touchUpInside)
        } else {
            XCTAssertTrue(node.element.accessibilityActivate())
        }
    }

    private func wait(in window: UIWindow, until ready: () -> Bool) async throws {
        for _ in 0..<40 {
            window.layoutIfNeeded()
            if ready() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(ready(), "Font action did not complete")
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private enum WorkflowError: Error { case missingControl }

    @MainActor
    private struct MountedWindow {
        let window: UIWindow
        let previous: UIWindow?

        func close() {
            window.endEditing(true)
            window.rootViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
    }
}
#endif
