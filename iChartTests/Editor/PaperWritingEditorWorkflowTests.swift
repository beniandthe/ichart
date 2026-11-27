#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Uses the ordinary setup and Done actions so the paper layout cannot exist
/// only in model helpers while the editor still starts or finishes an old grid.
@MainActor
final class PaperWritingEditorWorkflowTests: XCTestCase {
    func testSimpleCreationStartsWithEmptyWritingRows() async throws {
        try await assertCreation(style: .simpleChordSheet)
    }

    func testRhythmCreationStartsWithEmptyWritingRowsAndVisibleStaff() async throws {
        try await assertCreation(style: .rhythmSectionSheet)
    }

    func testSimpleAutomaticDoneFitsTheWrittenMeasures() async throws {
        try await assertDone(style: .simpleChordSheet, manual: false)
    }

    func testRhythmManualDoneFitsTheWrittenMeasures() async throws {
        try await assertDone(style: .rhythmSectionSheet, manual: true)
    }

    func testNarrowSimpleManualWritingKeepsGuidanceAndDoneReachable() async throws {
        try await assertDone(style: .simpleChordSheet, manual: true, width: 425)
    }

    func testNarrowRhythmAutomaticWritingKeepsGuidanceAndDoneReachable() async throws {
        try await assertDone(style: .rhythmSectionSheet, manual: false, width: 425)
    }

    private func assertCreation(style: ChartLayoutStyle) async throws {
        let box = PaperSetupBox(chart: Chart.draft(title: "Disposable blank page", layoutStyle: style))
        let root = PaperSetupHarness(box: box)
            .environment(\.accessibilityEnabled, true)
        let mounted = try await mount(root)

        XCTAssertTrue(try NativeAccessibilityLookup.matching("Starting Measures", in: mounted.window).isEmpty,
            "New paper charts begin with rows rather than a preselected measure count")
        let create = try await node("Create Blank Page", in: mounted.window, buttonsOnly: true)
        assertVisible(create, in: mounted.window)
        try activate(create, in: mounted.host)
        for _ in 0..<60 {
            if box.createdChart != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let chart = try XCTUnwrap(box.createdChart, "The normal Create action must deliver the blank paper chart")
        XCTAssertTrue(chart.hasCompletedInitialSetup)
        XCTAssertTrue(chart.usesPaperMeasureLayout)
        XCTAssertEqual(chart.layoutStyle, style)
        XCTAssertEqual(chart.systems.count, 8)
        XCTAssertTrue(chart.systems.allSatisfy { row in
            row.measures.count == 1 && row.measures[0].authoringState == .open
                && row.measures[0].chordEvents.isEmpty && row.measures[0].paperLayout?.leadingBarline == nil
        })
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 1000, height: 1400), includesChordInkContinuationLanes: true)
        XCTAssertEqual(layout.systems.count, 8)
        for row in layout.systems {
            let placeholder = try XCTUnwrap(row.measures.first)
            XCTAssertTrue(placeholder.isPaperWritingPlaceholder)
            XCTAssertNil(placeholder.explicitPaperLeadingBarline(after: nil))
            XCTAssertFalse(placeholder.preservesOpenMeasureBoundary)
            XCTAssertNotNil(row.paperWritingFrame)
            XCTAssertEqual(row.staffLineYPositions.count, style == .rhythmSectionSheet ? 5 : 0)
        }
    }

    private func assertDone(style: ChartLayoutStyle, manual: Bool, width: CGFloat? = nil) async throws {
        let defaults = IChartStorageNamespace.defaults
        let key = ChordInkWorkflowSettings.manualRenderWithPreviewKey
        let previous = defaults.object(forKey: key)
        let previousTour = defaults.object(forKey: "iChartPendingSimpleChartTour")
        defaults.set(manual, forKey: key)
        defaults.set(false, forKey: "iChartPendingSimpleChartTour")
        addTeardownBlock {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
            if let previousTour { defaults.set(previousTour, forKey: "iChartPendingSimpleChartTour") }
            else { defaults.removeObject(forKey: "iChartPendingSimpleChartTour") }
        }

        var chart = Chart.blank(title: "Disposable paper workflow", layoutStyle: style)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 2))
        XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.1, kind: .double))
        XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.35, kind: .single))
        XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.7, kind: .double))
        let written = chart.systems[0].measures.filter { $0.authoringState == .committed }
        XCTAssertEqual(written.count, 2)
        XCTAssertTrue(written.contains { $0.paperLayout?.needsSystemFit == true })

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        let store = ChartLibraryStore(charts: [chart], selectedChartID: chart.id, repository: repository)
        let binding = try XCTUnwrap(store.editorBinding(for: chart.id))
        let editor = NavigationStack {
            EditorView(chart: binding,
                chordInkUserCorrectionMemoryStore: .init(url: directory.appendingPathComponent("corrections.json")),
                initialCanvasMode: .chordEntry, recognizesChordInk: false)
        }
        .environmentObject(store)
        .environmentObject(IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library")))
        .environment(\.accessibilityEnabled, true)
        let mounted = try await mount(editor, width: width)
        let canvas = try XCTUnwrap(descendants(mounted.host.view).compactMap { $0 as? LeadSheetCanvasUIKitView }.first)
        XCTAssertEqual(canvas.interactionMode, .chordEntry)
        let guide = EditorCanvasMode.chordEntry.toolGuidance(layoutStyle: style,
            manualRenderWithPreview: manual, usesPaperMeasureLayout: true)
        let instruction = try await node(guide.steps[0], in: mounted.window)
        assertVisible(instruction, in: mounted.window)
        let done = try await node("Done", in: mounted.window, buttonsOnly: true)
        assertVisible(done, in: mounted.window)
        XCTAssertGreaterThan(canvas.convert(canvas.bounds, to: mounted.window).intersection(mounted.window.bounds).height, 100)
        attach(mounted.window, name: "\(style.rawValue) \(manual ? "manual" : "automatic") paper writing \(width == nil ? "regular" : "narrow")")
        try activate(done, in: mounted.host)

        for _ in 0..<60 {
            if canvas.interactionMode == .browse,
               binding.wrappedValue.systems[0].measures.allSatisfy({ $0.paperLayout?.needsSystemFit == false }) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(canvas.interactionMode, .browse)
        let finished = binding.wrappedValue
        let row = finished.systems[0].measures
        XCTAssertEqual(row.count, 2, "Done removes the unused trailing writing placeholder")
        XCTAssertEqual(row.map(\.id), written.map(\.id), "Fitting keeps the authored measures")
        let first = try XCTUnwrap(row.first)
        let second = try XCTUnwrap(row.dropFirst().first)
        XCTAssertEqual(try XCTUnwrap(first.paperLayout).startFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(first.paperLayout).endFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(second.paperLayout).startFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(second.paperLayout).endFraction, 1, accuracy: 0.0001)
        XCTAssertTrue(row.allSatisfy { $0.paperLayout?.needsSystemFit == false })
        XCTAssertEqual(first.paperLayout?.leadingBarline, .double)
        XCTAssertEqual(first.barlineAfter, .single)
        XCTAssertEqual(second.barlineAfter, .double)
        try repository.saveSnapshot(store.snapshot)
        XCTAssertEqual(try repository.loadSnapshot()?.charts.first { $0.id == chart.id }, finished)
    }

    private func mount<Content: View>(_ content: Content, width: CGFloat? = nil) async throws -> Mounted {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let host = PaperWorkflowHostingController(rootView: content
            .frame(width: width)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKeyAndVisible()
        }
        for _ in 0..<100 {
            if !window.isKeyWindow { window.makeKeyAndVisible() }
            window.layoutIfNeeded()
            if host.hasAppeared, window.isKeyWindow { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(host.hasAppeared && window.isKeyWindow)
        return Mounted(window: window, host: host)
    }

    private func node(_ label: String, in window: UIWindow,
                      buttonsOnly: Bool = false) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<60 {
            window.layoutIfNeeded()
            if let match = try NativeAccessibilityLookup.matching(label, in: window, buttonsOnly: buttonsOnly).first {
                return match
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(window, name: "Missing paper workflow control \(label)")
        return try XCTUnwrap(nil as NativeAccessibilityLookup.Node?, "Missing control \(label)")
    }

    private func activate(_ node: NativeAccessibilityLookup.Node, in host: UIViewController) throws {
        XCTAssertTrue(node.isEnabled)
        if let button = node.element as? UIButton {
            button.sendActions(for: .touchUpInside)
            return
        }
        if node.element.accessibilityActivate() { return }
        func controllers(_ viewController: UIViewController) -> [UIViewController] {
            [viewController] + viewController.children.flatMap(controllers)
        }
        let items = controllers(host).flatMap { controller -> [UIBarButtonItem] in
            let item = (controller as? UINavigationController)?.navigationBar.topItem ?? controller.navigationItem
            return (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? [])
        }
        let button = try XCTUnwrap(items.first {
            $0.title == node.element.accessibilityLabel || $0.accessibilityLabel == node.element.accessibilityLabel
        })
        let action = try XCTUnwrap(button.action)
        XCTAssertTrue(UIApplication.shared.sendAction(action, to: button.target, from: button, for: nil))
    }

    private func assertVisible(_ node: NativeAccessibilityLookup.Node, in window: UIWindow,
                               file: StaticString = #filePath, line: UInt = #line) {
        let rect = node.frame(in: window)
        XCTAssertFalse(rect.isEmpty, file: file, line: line)
        XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(rect), file: file, line: line)
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

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private struct Mounted {
        let window: UIWindow
        let host: UIViewController
    }
}

@MainActor
private final class PaperSetupBox: ObservableObject {
    @Published var chart: Chart
    var createdChart: Chart?
    init(chart: Chart) { self.chart = chart }
}

@MainActor
private struct PaperSetupHarness: View {
    @ObservedObject var box: PaperSetupBox
    var body: some View {
        ChartSetupSheetView(chart: $box.chart, onCreatePreparedChart: { chart in
            box.createdChart = chart
            box.chart = chart
            return true
        })
    }
}

@MainActor
private final class PaperWorkflowHostingController<Content: View>: UIHostingController<Content> {
    private(set) var hasAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}
#endif
