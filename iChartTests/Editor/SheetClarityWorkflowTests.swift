#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Uses synthetic charts to check the optional font controls remain reachable
/// through the new disclosure without changing any chart content on entry.
@MainActor
final class SheetClarityWorkflowTests: XCTestCase {
    func testSelectDragGuidanceWrapsAndKeepsGuideReachableAtLargestText() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for textSize in [DynamicTypeSize.large, .accessibility5] {
                let guidance = EditorCanvasMode.browse.toolGuidance(
                    layoutStyle: style, manualRenderWithPreview: false)
                let host = UIHostingController(rootView: VStack {
                    EditorToolGuidanceView(guidance: guidance)
                    Spacer(minLength: 0)
                }.background(Color(UIColor.systemBackground))
                    .dynamicTypeSize(textSize).environment(\.accessibilityEnabled, true))
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
                let previousWindow = scene.windows.first(where: \.isKeyWindow)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    previousWindow?.makeKey()
                }
                try await settle(window)
                let step = try await headerNode("editor-guidance-step-1", in: host.view, window: window)
                let guide = try await headerNode("editor-tool-guide-button", in: host.view, window: window)
                let purpose = try await headerNode("editor-guidance-purpose", in: host.view, window: window)
                XCTAssertEqual(step.element.accessibilityLabel, guidance.steps[0])
                for node in [purpose, guide, step] {
                    let frame = node.frame(in: window)
                    XCTAssertFalse(frame.isEmpty)
                    XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(frame))
                }
                XCTAssertGreaterThanOrEqual(guide.frame(in: window).width, 44)
                XCTAssertGreaterThanOrEqual(guide.frame(in: window).height, 44)
                XCTAssertGreaterThan(step.frame(in: window).minY, guide.frame(in: window).minY)
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "select-drag-guide-\(style)-\(textSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testToolGuidanceHeaderKeepsGuideReadableAndPurposeCenteredAtLargestText() async throws {
        let configurations: [(size: DynamicTypeSize, category: UIContentSizeCategory, isDark: Bool)] = [
            (.large, .large, false),
            (.accessibility5, .accessibilityExtraExtraExtraLarge, true)
        ]
        let guidance = EditorCanvasMode.chordEntry.toolGuidance(
            layoutStyle: .rhythmSectionSheet, manualRenderWithPreview: false)

        for configuration in configurations {
            var guideOpenCount = 0
            let host = UIHostingController(rootView: VStack {
                EditorToolGuidanceHeader(guidance: guidance) { guideOpenCount += 1 }
                Spacer(minLength: 0)
            }
            .padding(10)
            .dynamicTypeSize(configuration.size)
            .environment(\.colorScheme, configuration.isDark ? .dark : .light)
            .environment(\.accessibilityEnabled, true))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let container = UIViewController()
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.overrideUserInterfaceStyle = configuration.isDark ? .dark : .light
            window.rootViewController = container
            window.makeKeyAndVisible()
            container.addChild(host)
            host.view.frame = CGRect(x: 20, y: 20, width: 400,
                height: min(800, window.bounds.height - 40))
            host.view.autoresizingMask = []
            container.view.addSubview(host.view)
            host.didMove(toParent: container)
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousWindow?.makeKey()
            }
            try await settle(window)

            let purpose = try await headerNode("editor-guidance-purpose", in: host.view, window: window)
            let context = try await headerNode("editor-guidance-context", in: host.view, window: window)
            let guide = try await headerNode("editor-tool-guide-button", in: host.view, window: window)
            let hostFrame = host.view.convert(host.view.bounds, to: window)
            let purposeFrame = purpose.frame(in: window)
            let guideFrame = guide.frame(in: window)
            XCTAssertEqual(hostFrame.width, 400, accuracy: 1)
            XCTAssertEqual(purpose.element.accessibilityLabel, guidance.title)
            XCTAssertEqual(context.element.accessibilityLabel, guidance.context)
            XCTAssertEqual(guide.element.accessibilityLabel, guidance.detailsTitle)
            for node in [purpose, context, guide] {
                let frame = node.frame(in: window)
                XCTAssertFalse(frame.isEmpty)
                XCTAssertTrue(hostFrame.insetBy(dx: -1, dy: -1).contains(frame),
                    "The complete header control remains inside the narrow viewport")
            }
            XCTAssertEqual(purposeFrame.midX, hostFrame.midX, accuracy: 2,
                "The purpose stays centered on the whole helper")
            XCTAssertFalse(purposeFrame.intersects(guideFrame))
            XCTAssertGreaterThanOrEqual(guideFrame.width, 44)
            XCTAssertGreaterThanOrEqual(guideFrame.height, 44)
            let font = UIFont.preferredFont(forTextStyle: .caption1,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: configuration.category))
            let textWidth = ("Guide" as NSString).size(withAttributes: [.font: font]).width
            XCTAssertGreaterThanOrEqual(guideFrame.width, textWidth,
                "The Guide label must have room for its full text at the selected size")
            XCTAssertGreaterThanOrEqual(guideFrame.height, font.lineHeight)
            if configuration.size.isAccessibilitySize {
                XCTAssertGreaterThanOrEqual(guideFrame.minY, context.frame(in: window).maxY,
                    "Accessibility text gets a full-width purpose and a separate Guide row")
                XCTAssertEqual(guideFrame.midX, hostFrame.midX, accuracy: 2)
            }

            XCTAssertEqual(guideOpenCount, 0)
            XCTAssertTrue(guide.isButton)
            XCTAssertTrue(guide.isEnabled)
            if let button = guide.element as? UIButton {
                button.sendActions(for: .touchUpInside)
            } else {
                XCTAssertTrue(guide.element.accessibilityActivate())
            }
            try await settle(window)
            XCTAssertEqual(guideOpenCount, 1, "The real Guide action fires exactly once")
        }
    }

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

    private func headerNode(_ identifier: String, in root: UIView,
                            window: UIWindow) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<12 {
            if let node = try NativeAccessibilityLookup.nodes(in: root).first(where: { $0.identifier == identifier }) {
                return node
            }
            try await settle(window)
        }
        XCTFail("Missing rendered guidance header control: \(identifier)")
        throw MissingControl.notFound
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
