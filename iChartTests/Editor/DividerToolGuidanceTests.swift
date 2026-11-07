#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Enters the tools through the editor's normal primary controls. The fixture
/// uses the foreground scene's real size rather than a detached test viewport.
@MainActor
final class DividerToolGuidanceTests: XCTestCase {
    func testSimpleSelectShowsWrappedDividerAndMarkGuidanceWithoutEditing() async throws {
        try await assertGuidance(style: .simpleChordSheet, tool: .browse)
    }

    func testRhythmSelectShowsWrappedDividerAndMarkGuidanceWithoutEditing() async throws {
        try await assertGuidance(style: .rhythmSectionSheet, tool: .browse)
    }

    func testSimpleMeasuresShowsWrappedMergeGuidanceAndReachableControlsWithoutEditing() async throws {
        try await assertGuidance(style: .simpleChordSheet, tool: .measureEdit)
    }

    func testRhythmMeasuresShowsWrappedMergeGuidanceAndReachableControlsWithoutEditing() async throws {
        try await assertGuidance(style: .rhythmSectionSheet, tool: .measureEdit)
    }

    private func assertGuidance(style: ChartLayoutStyle, tool: EditorCanvasMode) async throws {
        let chart = try fixture(style)
        let mounted = try await mount(chart)
        let title = tool == .browse ? "Select" : "Measures"
        try activate(await node(title, in: mounted.window, button: true))
        let expected = tool.toolGuidance(layoutStyle: style,
            manualRenderWithPreview: false, hasFreeInkArticulations: true)
        let purpose = try await node(expected.title, in: mounted.window)
        let nextActionText = tool == .measureEdit && style == .rhythmSectionSheet
            ? "Tap a measure and choose Add, Layout or Delete. If a converted mark blocks an edit, use Restore Ink in Free Ink first."
            : expected.steps[0]
        let nextAction = try await node(nextActionText, in: mounted.window)
        assertVisible(purpose, in: mounted.window)
        assertVisible(nextAction, in: mounted.window)
        XCTAssertLessThan(purpose.frame(in: mounted.window).minY,
            nextAction.frame(in: mounted.window).maxY,
            "A concise purpose must introduce the tool's next action")
        let guide = try await node(expected.detailsTitle, in: mounted.window, button: true)
        assertVisible(guide, in: mounted.window)
        try activate(guide)
        let guideDone = try await presentedPanelButton("Done", in: mounted.window)
        XCTAssertTrue(guideDone.isEnabled)
        try activate(guideDone)
        for _ in 0..<40 {
            if mounted.window.rootViewController?.presentedViewController == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(mounted.window.rootViewController?.presentedViewController,
            "Local help returns to the tool without changing the chart")

        if tool == .browse {
            XCTAssertTrue(expected.referenceText.contains("Tap a converted mark"))
            XCTAssertTrue(expected.referenceText.contains("Tap an eligible divider, then its red X to merge the measures."))
            XCTAssertEqual(mounted.canvas.interactionMode, .browse)
            let measureID = chart.measures[0].id
            XCTAssertTrue(chart.canDeleteCommittedChordBarline(after: measureID))
            let page = LeadSheetPageLayoutEngine.pageLayout(for: mounted.canvas.chart,
                pageSize: mounted.canvas.bounds.size)
            let measure = try XCTUnwrap(page.systems.flatMap(\.measures).first {
                $0.sourceMeasureID == measureID
            })
            let frame = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: measure, layoutStyle: style)
            let selector = NSSelectorFromString("handleRenderedEditTapGesture:")
            XCTAssertTrue(mounted.canvas.responds(to: selector))
            _ = mounted.canvas.perform(selector, with: GuidanceTapFixture(
                point: CGPoint(x: frame.midX, y: frame.midY), coordinateView: mounted.canvas))
            for _ in 0..<30 {
                if mounted.canvas.selectedCommittedBarlineMeasureID == measureID { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(mounted.canvas.selectedCommittedBarlineMeasureID, measureID,
                "The instruction must describe a divider the real Select canvas can select")
            let delete = try await node("Delete", in: mounted.window, button: true)
            assertVisible(delete, in: mounted.window)
            XCTAssertTrue(delete.isEnabled)
            let redX = LeadSheetCommittedChordBarlineOverlayGeometry.controlFrames(
                for: measure, layoutStyle: style).delete
            let overlay = try XCTUnwrap(mounted.canvas.subviews.compactMap {
                $0 as? RenderedEditHitOverlayView
            }.first)
            XCTAssertTrue(overlay.point(inside: overlay.convert(
                CGPoint(x: redX.midX, y: redX.midY), from: mounted.canvas), with: nil),
                "The selected divider's red X must be reachable through the actual hit overlay")
        } else {
            XCTAssertTrue(expected.referenceText.contains("Open Layout to compare each action"))
            XCTAssertTrue(expected.referenceText.contains("Merge with Next Measure"))
            XCTAssertEqual(mounted.canvas.interactionMode, .measureEdit)
            for label in ["Add", "Layout", "Delete", "Done"] {
                let control = try await node(label, in: mounted.window, button: true)
                assertVisible(control, in: mounted.window)
                XCTAssertTrue(control.isEnabled, "\(label) must remain reachable below the helper")
            }
        }

        // Tool entry and selection may intentionally add controls. Once those
        // have appeared, repeated layout must leave the writing canvas steady.
        let stableFrame = try await settledCanvasFrame(mounted)
        for _ in 0..<5 {
            mounted.window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(mounted.canvas.convert(mounted.canvas.bounds, to: mounted.window), stableFrame)
            assertVisible(try await node(expected.title, in: mounted.window), in: mounted.window)
            assertVisible(try await node(nextActionText, in: mounted.window), in: mounted.window)
        }
        XCTAssertGreaterThan(stableFrame.intersection(mounted.window.bounds).height, 100,
            "The helper and controls must leave usable canvas space")
        XCTAssertEqual(mounted.canvas.chart, chart)
        XCTAssertEqual(mounted.binding.wrappedValue, chart,
            "Reading guidance and selecting a boundary must not mutate chart content")
        try mounted.repository.saveSnapshot(mounted.store.snapshot)
        XCTAssertEqual(try mounted.repository.loadSnapshot()?.charts.first { $0.id == chart.id }, chart)
        attach(mounted.window, name: "\(style.rawValue) \(title) normal entry guidance and controls")
    }

    private func mount(_ chart: Chart) async throws -> Mounted {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        let store = ChartLibraryStore(charts: [chart], selectedChartID: chart.id, repository: repository)
        try repository.saveSnapshot(store.snapshot)
        let binding = try XCTUnwrap(store.editorBinding(for: chart.id))
        let root = NavigationStack {
            EditorView(chart: binding,
                chordInkUserCorrectionMemoryStore: .init(url: directory.appendingPathComponent("corrections.json")),
                initialCanvasMode: .chordEntry)
        }
        .environmentObject(store)
        .environmentObject(IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library")))
        .environment(\.accessibilityEnabled, true)
        .dynamicTypeSize(.xxxLarge)
        let host = GuidanceHostingController(rootView: root)
        host.onLayout = { view in
            Self.descendants(view).compactMap { $0 as? LeadSheetCanvasUIKitView }
                .forEach { $0.recognizesChordInk = false }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in
            window.endEditing(true)
            try? await Task.sleep(nanoseconds: 50_000_000)
            host.onLayout = nil
            window.isHidden = true
            window.rootViewController = nil
            try? await Task.sleep(nanoseconds: 50_000_000)
            previousWindow?.makeKey()
            try? FileManager.default.removeItem(at: directory)
        }
        // A cold app launch can finish connecting its normal SwiftUI window
        // after this fixture is installed. Keep the real fixture window key
        // while waiting for UIKit's actual appearance callback.
        for _ in 0..<100 {
            if !window.isKeyWindow, scene.activationState == .foregroundActive {
                window.makeKeyAndVisible()
            }
            window.layoutIfNeeded()
            if host.hasAppeared, window.isKeyWindow, host.view.bounds.size == window.bounds.size { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(host.hasAppeared && window.isKeyWindow,
            "The actual fixture must appear and own input: appeared=\(host.hasAppeared), key=\(window.isKeyWindow), scene=\(scene.activationState.rawValue)")
        XCTAssertEqual(window.bounds.size, scene.coordinateSpace.bounds.size)
        XCTAssertEqual(host.view.bounds.size, window.bounds.size)
        let canvas = try XCTUnwrap(Self.descendants(host.view).compactMap { $0 as? LeadSheetCanvasUIKitView }.first)
        canvas.recognizesChordInk = false
        return Mounted(window: window, canvas: canvas, binding: binding, store: store, repository: repository)
    }

    private func node(_ label: String, in window: UIWindow, button: Bool = false) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<40 {
            window.layoutIfNeeded()
            if let result = try NativeAccessibilityLookup.matching(label, in: window,
                buttonsOnly: button).first { return result }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(window, name: "Missing divider guidance control - \(String(label.prefix(40)))")
        let diagnostics = try NativeAccessibilityLookup.nodes(in: window).prefix(100).map {
            "\($0.element.accessibilityLabel ?? "-") frame=\($0.frame(in: window))"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: diagnostics)
        attachment.name = "Divider guidance accessibility nodes"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("The actual editor did not expose \(label)")
        throw GuidanceFailure.missingControl
    }

    private func presentedPanelButton(_ label: String, in window: UIWindow) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<40 {
            window.layoutIfNeeded()
            if let panel = window.rootViewController?.presentedViewController?.view,
               let result = try NativeAccessibilityLookup.nodes(in: panel).first(where: {
                   $0.isButton && $0.element.accessibilityLabel == label
               }) { return result }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(window, name: "Missing local guide action - \(label)")
        XCTFail("The presented guide did not expose \(label)")
        throw GuidanceFailure.missingControl
    }

    private func assertVisible(_ node: NativeAccessibilityLookup.Node, in window: UIWindow,
        file: StaticString = #filePath, line: UInt = #line) {
        let frame = node.frame(in: window)
        XCTAssertFalse(frame.isEmpty, file: file, line: line)
        XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(frame),
            "\(node.element.accessibilityLabel ?? "Control") must be fully visible: \(frame)", file: file, line: line)
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
        if let button = node.element as? UIButton { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(node.element.accessibilityActivate()) }
    }

    private func settledCanvasFrame(_ mounted: Mounted) async throws -> CGRect {
        var previous = CGRect.null
        var stable = 0
        for _ in 0..<25 {
            mounted.window.layoutIfNeeded()
            let current = mounted.canvas.convert(mounted.canvas.bounds, to: mounted.window)
            stable = current == previous ? stable + 1 : 0
            if stable >= 3 { return current }
            previous = current
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The actual editor canvas did not settle after entering the tool")
        throw GuidanceFailure.unstableCanvas
    }

    private func fixture(_ style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Disposable divider guidance", measureCount: 3, layoutStyle: style)
        for (index, text) in ["Cmaj7", "G7", "Dm7"].enumerated() {
            chart.systems[0].measures[index].authoringState = .committed
            chart.systems[0].measures[index].manualLayoutWidth = 180
            chart.systems[0].measures[index].chordEvents = [ChordEvent(id: UUID(),
                symbol: try ChordSymbolParser.parse(text), spellingIntent: .explicit,
                startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
                duration: .whole, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
                rawInput: text, sourceInkData: archive(seed: index + 1))]
        }
        let last = chart.measures[2]
        let point = FreeInkArticulationPagePoint(pageIndex: 0, x: 500, y: 200)
        chart.freeInkArticulations = [FreeInkArticulation(kind: .accent, measureID: last.id,
            sourceInkData: archive(seed: 5), attachment: .chord(id: last.chordEvents[0].id),
            pagePoint: point, sourcePagePoint: point)]
        return chart
    }

    private func archive(seed: Int) -> Data {
        let path = PKStrokePath(controlPoints: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 30),
            CGPoint(x: 20, y: 40)].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed)))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: path, transform: .identity, mask: nil, randomSeed: UInt32(seed))]).dataRepresentation()
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private struct Mounted {
        let window: UIWindow
        let canvas: LeadSheetCanvasUIKitView
        let binding: Binding<Chart>
        let store: ChartLibraryStore
        let repository: FileChartRepository
    }
    private enum GuidanceFailure: Error { case missingControl, unstableCanvas }
}

@MainActor
private final class GuidanceHostingController<Content: View>: UIHostingController<Content> {
    var onLayout: ((UIView) -> Void)?
    private(set) var hasAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?(view)
    }
}

@MainActor
private final class GuidanceTapFixture: UITapGestureRecognizer {
    private let point: CGPoint
    private let coordinateView: UIView
    init(point: CGPoint, coordinateView: UIView) {
        self.point = point
        self.coordinateView = coordinateView
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State { get { .ended } set { } }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}
#endif
