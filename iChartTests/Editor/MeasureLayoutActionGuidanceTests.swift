#if canImport(UIKit)
import UIKit
import SwiftUI
import XCTest
@testable import iChart

final class MeasureLayoutActionGuidanceTests: XCTestCase {
    func testAvailabilityUsesOwningPredicatesInBothLayouts() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Layout actions", measureCount: 8, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            XCTAssertTrue(chart.insertSystemBreak(before: ids[4]))
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
            for id in ids {
                let newRow = MeasureLayoutActionGuidance.availability(for: .startNewRow, chart: chart, measureID: id, pageLayout: layout)
                XCTAssertEqual(newRow.isEnabled, chart.canInsertSystemBreak(before: id))
                let move = MeasureLayoutActionGuidance.availability(for: .moveToRowBelow, chart: chart, measureID: id, pageLayout: layout)
                XCTAssertEqual(move.isEnabled, LeadSheetMoveMeasureToRowBelowPolicy.plan(for: id, in: layout, chart: chart) != nil)
                let join = MeasureLayoutActionGuidance.availability(for: .joinRowAbove, chart: chart, measureID: id, pageLayout: layout)
                XCTAssertEqual(join.isEnabled, chart.measureIDsForJoiningRow(startingAt: id) != nil && !LeadSheetJoinRowEqualizationPolicy.manualLayoutWidths(startingAt: id, in: layout, chart: chart).isEmpty)
                for action in MeasureLayoutAction.allCases {
                    let result = MeasureLayoutActionGuidance.availability(for: action, chart: chart, measureID: id, pageLayout: layout)
                    XCTAssertEqual(result.reason == nil, result.isEnabled)
                }
            }
            XCTAssertEqual(MeasureLayoutActionGuidance.availability(for: .moveToRowBelow, chart: chart, measureID: ids[1], pageLayout: layout).reason, "Select the last measure in this row.")
        }
    }

    func testMissingSelectionAndKeyBoundaryExplainNextStepWithoutMutation() throws {
        var chart = Chart.blank(title: "Layout reasons", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let id = chart.measures[4].id
        XCTAssertTrue(chart.setKeyChange(.fMajor, atStartOf: id))
        let original = chart
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
        let empty = MeasureLayoutActionGuidance.availability(for: .joinRowAbove, chart: chart, measureID: nil, pageLayout: layout)
        XCTAssertEqual(empty.reason, "Select a measure first.")
        let key = MeasureLayoutActionGuidance.availability(for: .joinRowAbove, chart: chart, measureID: id, pageLayout: layout)
        XCTAssertFalse(key.isEnabled)
        XCTAssertEqual(key.reason, "Keep the row boundary at this key change.")
        XCTAssertEqual(chart, original)
    }

    func testNewRowKeepsOwningPredicateForEveryLayoutAndRejectsMissingTargets() {
        for style in ChartLayoutStyle.allCases {
            let chart = Chart.blank(title: "New row availability", measureCount: 8, layoutStyle: style)
            let original = chart
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
            for measure in chart.measures {
                let result = MeasureLayoutActionGuidance.availability(for: .startNewRow,
                    chart: chart, measureID: measure.id, pageLayout: layout)
                XCTAssertEqual(result.isEnabled, chart.canInsertSystemBreak(before: measure.id))
                XCTAssertEqual(result.reason == nil, result.isEnabled)
            }
            for missingID in [nil, UUID()] as [UUID?] {
                let result = MeasureLayoutActionGuidance.availability(for: .startNewRow,
                    chart: chart, measureID: missingID, pageLayout: layout)
                XCTAssertFalse(result.isEnabled)
                XCTAssertEqual(result.reason, "Select a measure first.")
            }
            XCTAssertEqual(chart, original)
        }
    }

    @MainActor
    func testLayoutSheetWrapsAndKeepsEveryActionReachableAtNarrowLargestTextInDarkMode() async throws {
        let chart = Chart.blank(title: "Disposable narrow layout sheet", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
        let options = MeasureLayoutAction.allCases.map { action in
            MeasureLayoutActionOption(action: action,
                availability: MeasureLayoutActionGuidance.availability(for: action,
                    chart: chart, measureID: chart.measures.first?.id, pageLayout: layout))
        }
        XCTAssertTrue(options.contains { $0.availability.isEnabled })
        XCTAssertTrue(options.contains { !$0.availability.isEnabled })
        var invokedActions: [MeasureLayoutAction] = []
        let host = UIHostingController(rootView: MeasureLayoutSheetView(measureNumber: 1,
            options: options, onSelect: { invokedActions.append($0) })
            .dynamicTypeSize(.accessibility5)
            .environment(\.colorScheme, .dark)
            .environment(\.accessibilityEnabled, true))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let container = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(host)
        host.view.frame = CGRect(x: 20, y: 20, width: 400,
            height: min(1000, window.bounds.height - 40))
        host.view.autoresizingMask = []
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await settle(window)
        XCTAssertEqual(host.view.bounds.width, 400, accuracy: 1)
        let lineHeight = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight
        for option in options {
            let button = try await reveal("measure-layout-action-\(option.action.rawValue)",
                in: window, host: host.view)
            XCTAssertEqual(button.isEnabled, option.availability.isEnabled)
            let description = try await reveal("measure-layout-explanation-\(option.action.rawValue)",
                in: window, host: host.view)
            let textFrame = description.frame(in: window)
            XCTAssertGreaterThan(textFrame.height, lineHeight,
                "The action explanation must use multiple lines at 400 points and the largest text size")
            XCTAssertLessThanOrEqual(textFrame.width, 400)
            XCTAssertTrue((description.element.accessibilityLabel ?? "").contains(
                option.action.explanation()), "The full explanation remains available to accessibility")
            if let reason = option.availability.reason {
                let node = try await reveal("measure-layout-reason-\(option.action.rawValue)",
                    in: window, host: host.view)
                XCTAssertTrue((node.element.accessibilityLabel ?? "").contains(reason),
                    "The complete unavailable reason must remain readable")
                XCTAssertLessThanOrEqual(node.frame(in: window).width, 400)
            }
        }
        XCTAssertTrue(invokedActions.isEmpty, "Reading and scrolling the choices must not apply an action")

        let chosenAction = try XCTUnwrap(options.first { $0.availability.isEnabled }?.action)
        let actionButton = try await reveal("measure-layout-action-\(chosenAction.rawValue)",
            in: window, host: host.view)
        XCTAssertTrue(actionButton.isButton)
        XCTAssertTrue(actionButton.isEnabled)
        if let button = actionButton.element as? UIButton {
            button.sendActions(for: .touchUpInside)
        } else {
            XCTAssertTrue(actionButton.element.accessibilityActivate(),
                "The native accessibility provider must activate the actual layout action button")
        }
        try await settle(window)
        XCTAssertEqual(invokedActions, [chosenAction],
            "One deliberate tap must dispatch exactly the action shown on the chosen card")
    }

    @MainActor
    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<3 {
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    private func reveal(_ identifier: String, in window: UIWindow, host: UIView) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<48 {
            let nodes = try NativeAccessibilityLookup.nodes(in: host)
            let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? UIScrollView }
                .filter { $0.contentSize.height > $0.bounds.height + 1 }
                .max { $0.bounds.height < $1.bounds.height })
            let viewport = scroll.convert(scroll.bounds, to: window)
                .intersection(host.convert(host.bounds, to: window))
            var delta = scroll.bounds.height * 0.5
            if let node = nodes.first(where: { $0.identifier == identifier }) {
                let frame = node.frame(in: window)
                if frame.width > 0, frame.height > 0,
                   viewport.insetBy(dx: -1, dy: -1).contains(frame) {
                    return node
                }
                delta = frame.midY - viewport.midY
            }
            let minimum = -scroll.adjustedContentInset.top
            let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let next = min(maximum, max(minimum, scroll.contentOffset.y + delta))
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
            try await settle(window)
        }
        XCTFail("Layout content is not reachable at the largest text size: \(identifier)")
        throw MissingLayoutContent.notFound
    }

    @MainActor
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private enum MissingLayoutContent: Error { case notFound }
}
#endif
