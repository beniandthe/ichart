#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ForumPublishGuidanceTests: XCTestCase {
    func testSimpleSubmitSheetKeepsInstrumentGuidanceAndActionsReadableAndStable() async throws {
        try await assertGuidance(style: .simpleChordSheet)
    }

    func testRhythmSubmitSheetKeepsInstrumentGuidanceAndActionsReadableAndStable() async throws {
        try await assertGuidance(style: .rhythmSectionSheet)
    }

    private func assertGuidance(style: ChartLayoutStyle) async throws {
        for category in [ContentSizeCategory.large, .accessibilityExtraExtraLarge] {
            var chart = Chart.blank(title: "Forum guidance fixture", measureCount: 2, layoutStyle: style)
            chart.defaultTranspositionView = .bb
            chart.chordTranspositionSemitones = 2
            let original = chart
            var publishCount = 0
            let root = IChartForumPublishSheet(request: IChartForumPublishRequest(chart: chart),
                theme: IChartHomeTheme(mode: .light)) { _, _ in publishCount += 1 }
                .environment(\.sizeCategory, category)
            let host = UIHostingController(rootView: root)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let container = UIViewController()
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = container
            window.makeKeyAndVisible()
            container.addChild(host)
            let frame = CGRect(x: 20, y: 60, width: min(500, window.bounds.width - 40),
                height: min(680, window.bounds.height - 120))
            host.view.frame = frame
            container.view.addSubview(host.view)
            host.didMove(toParent: container)
            defer {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
                window.isHidden = true
                window.rootViewController = nil
                previousWindow?.makeKey()
            }
            let helper = try await waitForNode(window) {
                $0.element.accessibilityLabel?.contains("The PDF keeps this chart's current instrument view") == true
            }
            let submit = try await waitForNode(window) {
                $0.isButton && $0.element.accessibilityLabel == "Submit"
            }
            let cancel = try await waitForNode(window) {
                $0.isButton && $0.element.accessibilityLabel == "Cancel"
            }
            let viewport = host.view.convert(host.view.bounds, to: window).insetBy(dx: -1, dy: -1)
            let helperFrame = helper.frame(in: window)
            let submitFrame = submit.frame(in: window)
            let cancelFrame = cancel.frame(in: window)
            XCTAssertEqual(helper.element.accessibilityLabel,
                "The PDF keeps this chart's current instrument view and transposition. To change them, return to the chart before submitting.")
            XCTAssertTrue(viewport.contains(helperFrame), "The full wrapped guidance must remain visible at entry")
            XCTAssertGreaterThan(helperFrame.height, 30, "Exercise wrapped text in the actual form")
            XCTAssertTrue(viewport.contains(submitFrame))
            XCTAssertTrue(viewport.contains(cancelFrame))
            XCTAssertTrue(submit.isEnabled)
            XCTAssertTrue(cancel.isEnabled)

            let scroll = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }
                .max { $0.contentSize.height < $1.contentSize.height })
            let scrollFrame = scroll.convert(scroll.bounds, to: window)
            let offset = scroll.contentOffset
            let maximumY = max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let targetY = min(maximumY, offset.y + 80)
            if category == .accessibilityExtraExtraLarge {
                XCTAssertGreaterThan(targetY, offset.y, "The large-text fixture must exercise real form scrolling")
            }
            scroll.setContentOffset(CGPoint(x: offset.x, y: targetY), animated: false)
            for _ in 0..<5 {
                window.layoutIfNeeded()
                XCTAssertEqual(scroll.convert(scroll.bounds, to: window), scrollFrame)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            scroll.setContentOffset(offset, animated: false)
            let restoredHelper = try await waitForNode(window) {
                $0.element.accessibilityLabel?.contains("The PDF keeps this chart's current instrument view") == true
            }
            for _ in 0..<5 {
                window.layoutIfNeeded()
                XCTAssertEqual(restoredHelper.frame(in: window).minY, helperFrame.minY, accuracy: 0.5)
                XCTAssertEqual(scroll.contentOffset.y, offset.y, accuracy: 0.5)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(publishCount, 0, "Opening and scrolling guidance must not submit a post")
            XCTAssertEqual(chart, original)
            attach(window, name: "Forum submit \(style.rawValue) \(category)")
        }
    }

    private func waitForNode(_ window: UIWindow,
        matching predicate: (NativeAccessibilityLookup.Node) -> Bool) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<40 {
            window.layoutIfNeeded()
            if let node = try NativeAccessibilityLookup.nodes(in: window).first(where: predicate) { return node }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(try NativeAccessibilityLookup.nodes(in: window).first(where: predicate))
    }

    private func descendants(_ root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap(descendants)
    }

    private func attach(_ window: UIWindow, name: String) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
