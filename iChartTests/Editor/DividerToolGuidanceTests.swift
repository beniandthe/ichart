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

    func testRhythmMeasuresShowsResizeGuidanceAndReachableControls() async throws {
        try await assertGuidance(style: .rhythmSectionSheet, tool: .measureEdit, hasConvertedMarks: false)
    }

    func testSimpleMeasuresShowsDirectChoicesAtAClosingRepeat() async throws {
        try await assertRepeatInsertionGuidance(style: .simpleChordSheet)
    }

    func testRhythmMeasuresShowsDirectChoicesAtAClosingRepeat() async throws {
        try await assertRepeatInsertionGuidance(style: .rhythmSectionSheet)
    }

    func testSimpleTextPlacesAtChosenBeatAndEditsWithoutSwitchingTools() async throws {
        try await assertTextPlacementAndEditing(style: .simpleChordSheet)
    }

    func testRhythmTextPlacesAtChosenBeatAndEditsWithoutSwitchingTools() async throws {
        try await assertTextPlacementAndEditing(style: .rhythmSectionSheet)
    }

    private func assertRepeatInsertionGuidance(style: ChartLayoutStyle) async throws {
        var chart = try fixture(style)
        chart.freeInkArticulations = []
        let lastMeasure = try XCTUnwrap(chart.measures.last)
        _ = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: lastMeasure.id, endMeasureID: lastMeasure.id))
        let mounted = try await mount(chart)
        try activate(await node("Measures", in: mounted.window, button: true))

        let prompt = try await node("Choose Add Inside Repeat or Add After Repeat.", in: mounted.window)
        assertVisible(prompt, in: mounted.window)
        for label in ["Add Inside Repeat", "Add After Repeat", "Add Multiple…"] {
            let action = try await node(label, in: mounted.window, button: true)
            assertVisible(action, in: mounted.window)
            XCTAssertTrue(action.isEnabled)
            XCTAssertGreaterThanOrEqual(action.frame(in: mounted.window).height, 44)
        }
        XCTAssertTrue(try NativeAccessibilityLookup.matching(
            "Add One After", in: mounted.window, buttonsOnly: true).isEmpty)
        XCTAssertEqual(mounted.binding.wrappedValue, chart, "Showing insertion choices must leave the chart unchanged")
    }

    private func assertTextPlacementAndEditing(style: ChartLayoutStyle) async throws {
        var original = try fixture(style)
        original.freeInkArticulations = []
        let measureID = original.measures[1].id
        let neighborID = try XCTUnwrap(original.addCueText("Hold", anchorMeasureID: measureID, position: .above))
        let mounted = try await mount(original, initialTool: .textEdit)
        let guide = EditorCanvasMode.textEdit.toolGuidance(layoutStyle: style, manualRenderWithPreview: false)
        assertVisible(try await node(guide.steps[0], in: mounted.window), in: mounted.window)
        let measure = try XCTUnwrap(LeadSheetPageLayoutEngine.pageLayout(for: mounted.canvas.chart,
            pageSize: mounted.canvas.bounds.size).systems.flatMap(\.measures)
            .first { $0.sourceMeasureID == measureID })
        let location = CGPoint(x: measure.staffFrame.minX + 0.53 * measure.staffFrame.width,
            y: measure.staffFrame.midY)
        sendEditorTap(at: location, in: mounted.canvas)
        let below = try await node("Below", in: mounted.window, button: true)
        let viewport = try await settledCanvasFrame(mounted)
        try activate(below)

        let field = try await cueInput(in: mounted.window)
        XCTAssertEqual(mounted.canvas.cueTextPlacementPreview,
            EditorCueTextPlacementPreview(measureID: measureID, position: .below, beatFraction: 0.5))
        let destination = try await node("Below measure 2 · beat 3", in: mounted.window)
        assertVisible(destination, in: mounted.window)
        let openedViewport = try await settledCanvasFrame(mounted)
        XCTAssertEqual(openedViewport, viewport)
        field.requestKeyboard()
        enterCueText("Basses only", in: field)
        _ = try await settledCanvasFrame(mounted)
        let oneLineFrame = field.convert(field.bounds, to: mounted.window)
        field.selectedRange = NSRange(location: ("Basses only" as NSString).length, length: 0)
        field.insertText("\n")
        let multilineFrame = try await cueInputFrame(in: mounted.window, tallerThan: oneLineFrame.height)
        let multilineInput = try await cueInput(in: mounted.window)
        XCTAssertTrue(multilineInput === field)
        XCTAssertEqual(field.text, "Basses only\n")
        XCTAssertEqual(multilineFrame.minY, oneLineFrame.minY, accuracy: 0.5)
        XCTAssertEqual(multilineFrame.width, oneLineFrame.width, accuracy: 0.5)
        field.insertText("Light pickups")
        XCTAssertEqual(field.text, "Basses only\nLight pickups")
        enterCueText("Basses only", in: field)
        _ = try await settledCanvasFrame(mounted)
        XCTAssertEqual(field.bounds.height, oneLineFrame.height, accuracy: 0.5,
            "Removing a line returns the same input to its one-line height")
        enterCueText("Basses only\nLight pickups", in: field)
        field.scribbleModeButton.sendActions(for: .touchUpInside)
        field.prepareScribble()
        XCTAssertTrue(field.isScribbleEnabled)
        XCTAssertEqual(field.text, "Basses only\nLight pickups")
        let scribbleViewport = try await settledCanvasFrame(mounted)
        XCTAssertEqual(scribbleViewport, viewport,
            "The paper viewport must stay fixed when entering text or switching input modes")
        XCTAssertEqual(mounted.binding.wrappedValue, original, "The placement preview must not save a cue")
        try activate(await node("Add", in: mounted.window, button: true))
        let selectedEdit = try await node("Edit", in: mounted.window, button: true)
        XCTAssertTrue(selectedEdit.isEnabled)
        let firstSave = mounted.binding.wrappedValue
        let placed = try XCTUnwrap(firstSave.cueTexts.first { $0.id != neighborID })
        XCTAssertEqual(placed.anchorMeasureID, measureID)
        XCTAssertEqual(placed.position, .below)
        XCTAssertEqual(placed.beatFraction, 0.5)
        XCTAssertEqual(placed.text, "Basses only\nLight pickups")
        XCTAssertEqual(firstSave.cueText(id: neighborID), original.cueText(id: neighborID))

        try activate(await node("Select", in: mounted.window, button: true))
        let cue = try XCTUnwrap(LeadSheetPageLayoutEngine.pageLayout(for: firstSave,
            pageSize: mounted.canvas.bounds.size).systems.flatMap(\.measures).flatMap(\.cueTextLayouts)
            .first { $0.id == placed.id })
        sendEditorTap(at: CGPoint(x: cue.frame.midX, y: cue.frame.midY), in: mounted.canvas)
        try activate(await node("Edit", in: mounted.window, button: true))
        let cancelledInput = try await cueInput(in: mounted.window)
        XCTAssertEqual(cancelledInput.text, "Basses only\nLight pickups")
        XCTAssertEqual(mounted.canvas.interactionMode, .browse)
        enterCueText("Discard this draft", in: cancelledInput)
        try activate(await node("Cancel", in: mounted.window, button: true))
        try activate(await node("Edit", in: mounted.window, button: true))
        let editInput = try await cueInput(in: mounted.window)
        XCTAssertEqual(editInput.text, "Basses only\nLight pickups", "Cancel leaves the original cue text intact")
        XCTAssertEqual(mounted.binding.wrappedValue, firstSave)
        enterCueText("Basses enter\nDrums out", in: editInput)
        try activate(await node("Apply", in: mounted.window, button: true))
        _ = try await node("Edit", in: mounted.window, button: true)
        let final = mounted.binding.wrappedValue
        var expected = placed
        expected.text = "Basses enter\nDrums out"
        expected.rawInput = expected.text
        XCTAssertEqual(final.cueText(id: placed.id), expected)
        XCTAssertEqual(final.cueText(id: neighborID), original.cueText(id: neighborID))
        XCTAssertEqual(final.measures.flatMap(\.chordEvents), original.measures.flatMap(\.chordEvents))
        XCTAssertEqual(mounted.canvas.interactionMode, .browse)
        try mounted.repository.saveSnapshot(mounted.store.snapshot)
        XCTAssertEqual(try mounted.repository.loadSnapshot()?.charts.first { $0.id == original.id }, final)
    }

    private func cueInput(in window: UIWindow) async throws -> IChartTypedUITextView {
        for _ in 0..<40 {
            window.layoutIfNeeded()
            if let input = Self.descendants(window).compactMap({ $0 as? IChartTypedUITextView }).first(where: {
                $0.accessibilityIdentifier == "editor-cue-text-entry" && $0.window === window
            }) { return input }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The editor did not present the Text entry field")
        throw GuidanceFailure.missingControl
    }

    private func cueInputFrame(in window: UIWindow, tallerThan height: CGFloat) async throws -> CGRect {
        for _ in 0..<25 {
            let field = try await cueInput(in: window)
            let frame = field.convert(field.bounds, to: window)
            if frame.height > height + 1 { return frame }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        XCTFail("Entering a new line should grow the existing cue field")
        throw GuidanceFailure.missingControl
    }

    private func enterCueText(_ text: String, in field: IChartTypedUITextView) {
        field.text = text
        field.delegate?.textViewDidChange?(field)
    }

    private func sendEditorTap(at point: CGPoint, in canvas: LeadSheetCanvasUIKitView) {
        canvas.handleRenderedEditTapGesture(GuidanceTapFixture(point: point, coordinateView: canvas))
    }

    private func assertGuidance(style: ChartLayoutStyle, tool: EditorCanvasMode,
                                hasConvertedMarks: Bool = true) async throws {
        var chart = try fixture(style)
        if !hasConvertedMarks { chart.freeInkArticulations.removeAll() }
        let mounted = try await mount(chart)
        let title = tool == .browse ? "Select" : "Measures"
        try activate(await node(title, in: mounted.window, button: true))
        let expected = tool.toolGuidance(layoutStyle: style,
            manualRenderWithPreview: false, hasFreeInkArticulations: hasConvertedMarks)
        let purpose = try await node(expected.title, in: mounted.window)
        let nextActionText = tool == .measureEdit && style == .rhythmSectionSheet && hasConvertedMarks
            ? "Choose a measure action. If a converted mark blocks an edit, use Restore Ink in Free Ink first."
            : expected.steps[0]
        let nextAction = try await node(nextActionText, in: mounted.window)
        assertVisible(purpose, in: mounted.window)
        assertVisible(nextAction, in: mounted.window)
        if tool == .browse {
            let resizeInstruction = try await node("Tap a chord for width handles. Drag its body to move it.",
                                                   in: mounted.window)
            assertVisible(resizeInstruction, in: mounted.window)
        }
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
            XCTAssertTrue(expected.referenceText.contains("Row actions sit to the left of the chart."))
            XCTAssertTrue(expected.referenceText.contains("Merge with Next Measure"))
            XCTAssertEqual(mounted.canvas.interactionMode, .measureEdit)
            for label in ["Add One After", "Delete Range…", "Done"] {
                let control = try await node(label, in: mounted.window, button: true)
                assertVisible(control, in: mounted.window)
            }
            let startNewRow = try await node("Start New Row", in: mounted.window, button: true)
            assertVisible(startNewRow, in: mounted.window)
            XCTAssertTrue(startNewRow.isEnabled)
            XCTAssertGreaterThanOrEqual(startNewRow.frame(in: mounted.window).height, 44)
            let joinRowAbove = try await node("Join Row Above", in: mounted.window, button: true)
            assertVisible(joinRowAbove, in: mounted.window)
            XCTAssertFalse(joinRowAbove.isEnabled, "A chart with one row has no row above to join")
            XCTAssertTrue(try NativeAccessibilityLookup.matching("Layout", in: mounted.window,
                buttonsOnly: true).isEmpty)
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

    private func mount(_ chart: Chart, initialTool: EditorCanvasMode = .chordEntry) async throws -> Mounted {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        let store = ChartLibraryStore(charts: [chart], selectedChartID: chart.id, repository: repository)
        try repository.saveSnapshot(store.snapshot)
        let binding = try XCTUnwrap(store.editorBinding(for: chart.id))
        let root = NavigationStack {
            EditorView(chart: binding,
                chordInkUserCorrectionMemoryStore: .init(url: directory.appendingPathComponent("corrections.json")),
                initialCanvasMode: initialTool)
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
