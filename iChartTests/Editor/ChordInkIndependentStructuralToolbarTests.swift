#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Exercises the real manual toolbar admission and live canvas transaction.
/// Synthetic structural strokes are not fresh physical Pencil acceptance.
@MainActor
final class ChordInkIndependentStructuralToolbarTests: XCTestCase {
    func testSimpleManualToolbarRendersRepeatWhileUnreviewedEndingStays() async throws {
        try await assertIndependentRepeat(style: .simpleChordSheet)
    }

    func testRhythmManualToolbarRendersRepeatWhileUnreviewedEndingStays() async throws {
        try await assertIndependentRepeat(style: .rhythmSectionSheet)
    }

    func testOnlyUnreviewedEndingStillRequiresReviewInBothStyles() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let mounted = try await mount(style)
            let source = try structuralSource(in: mounted, includesRepeat: false)
            write(source.all, in: mounted)
            try await waitUntil(in: mounted.window) {
                mounted.canvas.chordPreviewState.draftEndings.count == 1
                    && mounted.canvas.chordPreviewState.draftChords.isEmpty
            }
            try await waitUntil(in: mounted.window) {
                (try? mounted.repository.loadSnapshot()?.charts.first?.pageHandwrittenChordData) != nil
            }
            let review = try await button("Review & Render", in: mounted.window)
            XCTAssertTrue(review.isEnabled)
            XCTAssertTrue(try NativeAccessibilityLookup.matching("Render Chords", in: mounted.window,
                buttonsOnly: true).isEmpty, "Unreviewed ending-only ink must not acquire an independent render action")
            XCTAssertTrue(mounted.store.charts[0].roadmapObjects.isEmpty)
            let saved = try XCTUnwrap(mounted.repository.loadSnapshot()?.charts.first)
            assertSameInk(source.all, try PKDrawing(data: XCTUnwrap(saved.pageHandwrittenChordData)))
            assertSameInk(source.all, mounted.live.drawing)
            mounted.window.isHidden = true
            mounted.window.rootViewController = nil
        }
    }

    private func assertIndependentRepeat(style: ChartLayoutStyle) async throws {
        let mounted = try await mount(style)
        let source = try structuralSource(in: mounted, includesRepeat: true)
        let measureIDs = mounted.store.charts[0].measures.map(\.id)
        write(source.all, in: mounted)
        try await waitUntil(in: mounted.window) {
            let state = mounted.canvas.chordPreviewState
            return state.draftChords.isEmpty && state.draftBarlines.map(\.kind) == [.repeatStart, .repeatEnd]
                && state.draftEndings.count == 1 && !state.draftEndings[0].isReviewed
        }
        let before = mounted.canvas.chordPreviewState
        XCTAssertFalse(ChordInkDraftRenderCoordinator.independentlyRenderableStructuralIDs(in: before).isEmpty)
        let render = try await button("Render Chords", in: mounted.window)
        XCTAssertTrue(render.isEnabled)
        try activate(render)

        try await waitUntil(in: mounted.window) {
            guard let saved = try? mounted.repository.loadSnapshot()?.charts.first else { return false }
            return saved.roadmapObjects.filter { $0.type == .repeatSpan }.count == 1
                && mounted.canvas.chordPreviewState.draftBarlines.isEmpty
        }
        let saved = try XCTUnwrap(mounted.repository.loadSnapshot()?.charts.first)
        XCTAssertEqual(saved.layoutStyle, style)
        XCTAssertEqual(saved.measures.map(\.id), measureIDs)
        XCTAssertTrue(saved.measures.flatMap(\.chordEvents).isEmpty)
        XCTAssertEqual(saved.roadmapObjects.count, 1, "The unrelated ending must remain unrendered")
        let repeatSpan = try XCTUnwrap(saved.roadmapObjects.first { $0.type == .repeatSpan })
        assertSameInk(source.repeats, try PKDrawing(data: XCTUnwrap(repeatSpan.sourceInkData)))
        assertSameInk(source.ending, try PKDrawing(data: XCTUnwrap(saved.pageHandwrittenChordData)))
        assertSameInk(source.ending, mounted.live.drawing)
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftEndings.count, 1)
        XCTAssertFalse(try XCTUnwrap(mounted.canvas.chordPreviewState.draftEndings.first).isReviewed)
        XCTAssertNil(mounted.window.rootViewController?.presentedViewController,
            "Independent structural progress must not require an unrelated review sheet")
        let review = try await button("Review & Render", in: mounted.window)
        XCTAssertTrue(review.isEnabled, "The retained ending must remain available for deliberate review")
    }

    private func structuralSource(in mounted: Mounted, includesRepeat: Bool) throws -> Source {
        let chart = mounted.store.charts[0]
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: mounted.canvas.bounds.size,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let first = try XCTUnwrap(system.measures.first)
        let last = try XCTUnwrap(system.measures.last)
        XCTAssertNotEqual(first.sourceMeasureID, last.sourceMeasureID)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        func stroke(_ points: [CGPoint], seed: UInt32, width: CGFloat = 2.5) -> PKStroke {
            let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY),
                    timeOffset: Double(index) * 0.05, size: CGSize(width: width, height: width),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed)))
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: path, transform: .identity, mask: nil, randomSeed: seed)
        }
        func repeatSign(at x: CGFloat, starts: Bool, seed: UInt32) -> [PKStroke] {
            let height = lane.height * 0.84
            let side: CGFloat = starts ? 1 : -1
            return [stroke([CGPoint(x: x, y: lane.midY - height / 2),
                CGPoint(x: x, y: lane.midY + height / 2)], seed: seed),
                stroke([CGPoint(x: x + side * height * 0.20, y: lane.midY - height * 0.18)],
                    seed: seed + 1, width: 1.4),
                stroke([CGPoint(x: x + side * height * 0.20, y: lane.midY + height * 0.18)],
                    seed: seed + 2, width: 1.4)]
        }
        let roof = lane.minY + lane.height * 0.12
        let left = last.staffFrame.minX + 3
        let right = last.staffFrame.maxX - 3
        let bracket = [stroke([CGPoint(x: left, y: roof + lane.height * 0.20),
            CGPoint(x: left, y: roof)], seed: 50),
            stroke([CGPoint(x: left, y: roof), CGPoint(x: right, y: roof)], seed: 51)]
        let repeats = includesRepeat
            ? repeatSign(at: first.staffFrame.minX + 1, starts: true, seed: 10)
                + repeatSign(at: first.staffFrame.maxX - 1, starts: false, seed: 20)
            : []
        func normalized(_ strokes: [PKStroke]) -> PKDrawing {
            LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes))
        }
        return Source(all: normalized(repeats + bracket), repeats: normalized(repeats), ending: normalized(bracket))
    }

    private func write(_ source: PKDrawing, in mounted: Mounted) {
        mounted.canvas.canvasViewDidBeginUsingTool(mounted.live)
        mounted.live.drawing = source
        mounted.canvas.canvasViewDrawingDidChange(mounted.live)
        mounted.canvas.canvasViewDidEndUsingTool(mounted.live)
    }

    private func mount(_ style: ChartLayoutStyle) async throws -> Mounted {
        let key = ChordInkWorkflowSettings.manualRenderWithPreviewKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var chart = Chart.draft(title: "Disposable independent toolbar", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor, meter: .init(numerator: 4, denominator: 4),
            staffStyle: .fiveLine, startingMeasureCount: 3)
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
        let host = StructuralToolbarHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            previousWindow?.makeKey()
            try? FileManager.default.removeItem(at: directory)
        }
        try await waitUntil(in: window) { host.hasAppeared && window.isKeyWindow }
        let canvas = try XCTUnwrap(Self.descendants(host.view).compactMap { $0 as? LeadSheetCanvasUIKitView }.first)
        let live = try XCTUnwrap(canvas.subviews.compactMap { $0 as? LeadSheetScopedInkCanvasView }.last)
        XCTAssertTrue(canvas.manualRenderWithPreview)
        XCTAssertTrue(canvas.recognizesChordInk)
        return Mounted(window: window, canvas: canvas, live: live, store: store, repository: repository)
    }

    private func button(_ label: String, in window: UIWindow) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<80 {
            window.layoutIfNeeded()
            if let node = try NativeAccessibilityLookup.matching(label, in: window, buttonsOnly: true).first {
                return node
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The real editor did not expose \(label)")
        throw FixtureFailure.missingControl
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
        if let button = node.element as? UIButton { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(node.element.accessibilityActivate()) }
    }

    private func waitUntil(in window: UIWindow, _ predicate: () -> Bool) async throws {
        for _ in 0..<120 {
            window.layoutIfNeeded()
            if predicate() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The real editor did not reach the expected structural state")
        throw FixtureFailure.stateNotReached
    }

    private func assertSameInk(_ expected: PKDrawing, _ actual: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: actual),
            file: file, line: line)
    }

    private static func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private struct Mounted {
        let window: UIWindow
        let canvas: LeadSheetCanvasUIKitView
        let live: LeadSheetScopedInkCanvasView
        let store: ChartLibraryStore
        let repository: FileChartRepository
    }
    private struct Source { let all: PKDrawing; let repeats: PKDrawing; let ending: PKDrawing }
    private enum FixtureFailure: Error { case missingControl, stateNotReached }
}

@MainActor
private final class StructuralToolbarHostingController<Content: View>: UIHostingController<Content> {
    private(set) var hasAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}
#endif
