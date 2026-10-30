#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Exercise the real EditorView sizing boundary. Resizing a bare ink canvas
/// cannot prove that the production document stops following viewport width.
@MainActor
final class FreeInkFixedPaperEditorIntegrationTests: XCTestCase {
    func testSavedWidePaperKeepsInkAndNotationFixedAndItsRightEdgeReachableInPortrait() async throws {
        let chart = makeChart(sourceCanvasWidth: 1_160, withInk: true)
        let originalInk = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenNotationData))
        let mounted = try await mount(chart, viewport: CGSize(width: 1_200, height: 900))
        defer { mounted.close() }
        let baseline = try snapshot(mounted.canvas)
        assertSameDrawing(originalInk, try authoringCanvas(mounted.canvas).drawing)
        try assertInitialFitWidth(in: mounted)

        try await resize(mounted, to: CGSize(width: 800, height: 1_180))
        assertSamePaper(baseline, try snapshot(mounted.canvas))
        let inkCanvas = try authoringCanvas(mounted.canvas)
        assertSameDrawing(originalInk, inkCanvas.drawing)
        let scroll = try parentScrollView(of: mounted.canvas)
        let zoomTarget = try assertNativeZoomAvailable(in: mounted)
        scroll.setZoomScale(2 * fitWidthScale(in: scroll, zoomTarget: zoomTarget), animated: false)
        await settle(mounted.window)
        XCTAssertGreaterThan(scroll.contentSize.width, scroll.bounds.width + 200,
            "A zoomed portrait viewport must expose the original document through horizontal scrolling.")

        let rightStroke = try XCTUnwrap(inkCanvas.drawing.strokes.last)
        let farRightInkPoint = try XCTUnwrap(rightStroke.path.last?.location.applying(rightStroke.transform))
        let pointInScroll = inkCanvas.convert(farRightInkPoint, to: scroll)
        let maximumOffset = max(-scroll.adjustedContentInset.left,
            scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right)
        scroll.setContentOffset(clampedOffset(CGPoint(x: maximumOffset,
            y: pointInScroll.y - scroll.bounds.height / 2), in: scroll), animated: false)
        await settle(mounted.window)
        XCTAssertTrue(scroll.bounds.insetBy(dx: -1, dy: 0).contains(inkCanvas.convert(farRightInkPoint, to: scroll)),
            "The far-right original ink must become visible without rewriting its coordinates.")
        assertSameDrawing(originalInk, inkCanvas.drawing)
        assertSamePaper(baseline, try snapshot(mounted.canvas))

        // Use actual toolbar actions rather than assigning UIKit mode directly.
        try await activate("Select", in: mounted)
        try await activate("Free Ink", in: mounted)
        assertSamePaper(baseline, try snapshot(mounted.canvas))
        assertSameDrawing(originalInk, try authoringCanvas(mounted.canvas).drawing)
        try await resize(mounted, to: CGSize(width: 1_200, height: 900))
        assertSamePaper(baseline, try snapshot(mounted.canvas))
        assertSameDrawing(originalInk, try authoringCanvas(mounted.canvas).drawing)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenNotationCoordinateSpace, chart.pageHandwrittenNotationCoordinateSpace)
    }

    func testPortraitOriginPaperFillsLandscapeViewportWithoutChangingItsLogicalGeometry() async throws {
        let chart = makeChart(sourceCanvasWidth: 800, withInk: true)
        let originalInk = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenNotationData))
        let mounted = try await mount(chart, viewport: CGSize(width: 1_200, height: 900))
        defer { mounted.close() }
        let baseline = try snapshot(mounted.canvas)
        XCTAssertEqual(baseline.documentWidth, 800, accuracy: 0.01,
            "Opening a portrait-origin document in landscape must retain its original paper width.")
        let portraitPaper = try XCTUnwrap(baseline.paperFrames.first)
        XCTAssertGreaterThan(portraitPaper.height, portraitPaper.width)
        let scroll = try parentScrollView(of: mounted.canvas)
        try assertInitialFitWidth(in: mounted)
        XCTAssertGreaterThan(scroll.zoomScale, 1,
            "Landscape must display an enlarged section of the original portrait document.")
        XCTAssertLessThan(scroll.bounds.height / scroll.zoomScale, portraitPaper.height,
            "Fit width must show a vertical section, rather than shrinking the whole portrait page to fit height.")
        assertSameDrawing(originalInk, try authoringCanvas(mounted.canvas).drawing)
        attachViewport(mounted.window, name: "Synthetic portrait paper - landscape fit width")
        let initialLandscapeChrome = try viewportChromeSnapshot(in: mounted)
        var attachedPortrait = false
        for size in [CGSize(width: 800, height: 1_180), CGSize(width: 1_200, height: 900),
                     CGSize(width: 800, height: 1_180)] {
            try await resize(mounted, to: size)
            assertSamePaper(baseline, try snapshot(mounted.canvas))
            assertSameDrawing(originalInk, try authoringCanvas(mounted.canvas).drawing)
            try assertInitialFitWidth(in: mounted)
            if size.width == 800, !attachedPortrait {
                attachViewport(mounted.window, name: "Synthetic portrait paper - portrait fit width")
                attachedPortrait = true
            }
        }
        try await resize(mounted, to: CGSize(width: 1_200, height: 900))
        let wholePageScroll = try parentScrollView(of: mounted.canvas)
        let wholePageTarget = try assertNativeZoomAvailable(in: mounted)
        let wholePageScale = min(wholePageScroll.bounds.width / wholePageTarget.bounds.width,
            wholePageScroll.bounds.height / wholePageTarget.bounds.height)
        let chromeBeforeZoom = try viewportChromeSnapshot(in: mounted)
        attachChromeMeasurements(before: initialLandscapeChrome, after: chromeBeforeZoom,
            name: "Actual viewport and toolbar geometry after landscape roundtrip")
        assertUnchangedViewportAndChrome(before: initialLandscapeChrome, after: chromeBeforeZoom)
        wholePageScroll.setZoomScale(max(wholePageScroll.minimumZoomScale, wholePageScale), animated: false)
        await settle(mounted.window)
        let chromeAfterZoom = try viewportChromeSnapshot(in: mounted)
        attachChromeMeasurements(before: chromeBeforeZoom, after: chromeAfterZoom)
        assertUnchangedViewportAndChrome(before: chromeBeforeZoom, after: chromeAfterZoom)
        attachViewport(mounted.window, name: "Synthetic portrait paper - landscape whole document zoom")
    }

    func testNativeZoomPanAndRotationPreservePaperFocusAndCameraThroughModelAndToolUpdates() async throws {
        let chart = makeChart(sourceCanvasWidth: 800, withInk: true)
        let originalInk = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenNotationData))
        let mounted = try await mount(chart, viewport: CGSize(width: 800, height: 1_180))
        defer { mounted.close() }
        let baseline = try snapshot(mounted.canvas)
        let scroll = try parentScrollView(of: mounted.canvas)
        let zoomTarget = try assertNativeZoomAvailable(in: mounted)
        let requestedRatio = CGFloat(1.75)
        scroll.setZoomScale(requestedRatio * fitWidthScale(in: scroll, zoomTarget: zoomTarget), animated: false)
        await settle(mounted.window)
        let paperPoint = CGPoint(x: mounted.canvas.bounds.width / 2, y: 600)
        let mapped = mounted.canvas.convert(paperPoint, to: scroll)
        let proposed = CGPoint(x: mapped.x - scroll.bounds.width / 2, y: mapped.y - scroll.bounds.height / 2)
        let admitted = clampedOffset(proposed, in: scroll)
        XCTAssertEqual(admitted.x, proposed.x, accuracy: 0.01,
            "The focal-point fixture must avoid horizontal edge clamping.")
        XCTAssertEqual(admitted.y, proposed.y, accuracy: 0.01,
            "The focal-point fixture must avoid vertical edge clamping.")
        scroll.setContentOffset(admitted, animated: false)
        await settle(mounted.window)
        assertPaperPoint(paperPoint, atViewportCenterOf: scroll, canvas: mounted.canvas)
        let firstMapped = mounted.canvas.convert(paperPoint, to: scroll)
        let secondMapped = mounted.canvas.convert(CGPoint(x: paperPoint.x + 40, y: paperPoint.y + 20), to: scroll)
        XCTAssertEqual(secondMapped.x - firstMapped.x, 40 * scroll.zoomScale, accuracy: 0.01)
        XCTAssertEqual(secondMapped.y - firstMapped.y, 20 * scroll.zoomScale, accuracy: 0.01)

        // Drive a real parent model publication, so updateUIView must reconcile
        // its content without recreating the user's camera state.
        let echoDate = chart.updatedAt.addingTimeInterval(88)
        mounted.model.chart.updatedAt = echoDate
        await settle(mounted.window)
        XCTAssertEqual(mounted.canvas.chart.updatedAt, echoDate)
        assertPaperPoint(paperPoint, atViewportCenterOf: try parentScrollView(of: mounted.canvas), canvas: mounted.canvas)
        try await activate("Select", in: mounted)
        try await activate("Free Ink", in: mounted)
        assertPaperPoint(paperPoint, atViewportCenterOf: try parentScrollView(of: mounted.canvas), canvas: mounted.canvas)

        try await resize(mounted, to: CGSize(width: 1_200, height: 900))
        let rotatedScroll = try parentScrollView(of: mounted.canvas)
        let rotatedZoomTarget = try assertNativeZoomAvailable(in: mounted)
        XCTAssertEqual(rotatedScroll.zoomScale / fitWidthScale(in: rotatedScroll, zoomTarget: rotatedZoomTarget),
            requestedRatio, accuracy: 0.005,
            "Rotation must retain the user's zoom ratio relative to fit width.")
        assertPaperPoint(paperPoint, atViewportCenterOf: rotatedScroll, canvas: mounted.canvas)
        assertSamePaper(baseline, try snapshot(mounted.canvas))
        assertSameDrawing(originalInk, try authoringCanvas(mounted.canvas).drawing)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenNotationCoordinateSpace, chart.pageHandwrittenNotationCoordinateSpace)
    }

    func testEnteringFreeInkBeforeFirstStrokeRetainsThatPaperThroughRotationAndReopen() async throws {
        let chart = makeChart(sourceCanvasWidth: 1_160, withInk: false)
        let mounted = try await mount(chart, viewport: CGSize(width: 1_200, height: 900), mode: .browse)
        defer { mounted.close() }
        try await activate("Free Ink", in: mounted)
        let baseline = try snapshot(mounted.canvas)
        XCTAssertEqual(baseline.documentWidth, 932, accuracy: 0.01,
            "A new document must start with the same portrait logical width in either orientation.")
        let scroll = try parentScrollView(of: mounted.canvas)
        let zoomTarget = try assertNativeZoomAvailable(in: mounted)
        scroll.setZoomScale(1.5 * fitWidthScale(in: scroll, zoomTarget: zoomTarget), animated: false)
        await settle(mounted.window)
        scroll.setContentOffset(clampedOffset(CGPoint(x: 150, y: 100), in: scroll), animated: false)
        await settle(mounted.window)
        let inkCanvas = try authoringCanvas(mounted.canvas)
        let drawing = drawing(rightEdge: inkCanvas.bounds.width - 40)
        inkCanvas.drawing = drawing
        mounted.canvas.canvasViewDrawingDidChange(inkCanvas)

        // The first orientation change occurs after an actual drawing callback,
        // without requiring a prior mode exit or persisted-coordinate seed.
        try await resize(mounted, to: CGSize(width: 800, height: 1_180))
        assertSamePaper(baseline, try snapshot(mounted.canvas))
        assertSameDrawing(drawing, try authoringCanvas(mounted.canvas).drawing)
        try await activate("Select", in: mounted)
        let saved = mounted.model.chart
        XCTAssertNotNil(saved.pageHandwrittenNotationCoordinateSpace)
        let reopenedChart = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(saved))
        let reopened = try await mount(reopenedChart, viewport: CGSize(width: 800, height: 1_180))
        defer { reopened.close() }
        assertSamePaper(baseline, try snapshot(reopened.canvas))
        assertSameDrawing(drawing, try authoringCanvas(reopened.canvas).drawing)
        try await resize(reopened, to: CGSize(width: 1_200, height: 900))
        assertSamePaper(baseline, try snapshot(reopened.canvas))
        assertSameDrawing(drawing, try authoringCanvas(reopened.canvas).drawing)
    }

    private struct PaperSnapshot {
        let documentWidth: CGFloat
        let paperFrames: [CGRect]
        let headerFrame: CGRect
        let systemFrames: [CGRect]
        let measureIDs: [UUID?]
        let measureFrames: [CGRect]
        let inkOrigin: CGPoint
    }

    private func snapshot(_ canvas: LeadSheetCanvasUIKitView) throws -> PaperSnapshot {
        // Read the layout actually retained by the production canvas, rather
        // than computing a fresh expected layout from the policy under test.
        let stored = try XCTUnwrap(Mirror(reflecting: canvas).children.first { $0.label == "pageLayout" }?.value)
        let layout: LeadSheetPageLayout
        let mirror = Mirror(reflecting: stored)
        if mirror.displayStyle == .optional {
            layout = try XCTUnwrap(mirror.children.first?.value as? LeadSheetPageLayout)
        } else {
            layout = try XCTUnwrap(stored as? LeadSheetPageLayout)
        }
        let ink = try authoringCanvas(canvas)
        return PaperSnapshot(documentWidth: canvas.bounds.width,
            paperFrames: layout.pages.map(\.frame), headerFrame: layout.header.frame,
            systemFrames: layout.systems.map(\.frame),
            measureIDs: layout.systems.flatMap(\.measures).map(\.sourceMeasureID),
            measureFrames: layout.systems.flatMap(\.measures).map(\.frame), inkOrigin: ink.frame.origin)
    }

    private func assertSamePaper(_ expected: PaperSnapshot, _ actual: PaperSnapshot,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.documentWidth, expected.documentWidth, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.paperFrames, expected.paperFrames, "Paper moved or resized during rotation.", file: file, line: line)
        XCTAssertEqual(actual.headerFrame, expected.headerFrame, file: file, line: line)
        XCTAssertEqual(actual.systemFrames, expected.systemFrames, "Notation rows moved underneath Free Ink.", file: file, line: line)
        XCTAssertEqual(actual.measureIDs, expected.measureIDs, "Rotation repacked the document's measure rows.", file: file, line: line)
        XCTAssertEqual(actual.measureFrames, expected.measureFrames, "Measures moved relative to existing ink.", file: file, line: line)
        XCTAssertEqual(actual.inkOrigin, expected.inkOrigin, "The ink layer moved relative to its paper.", file: file, line: line)
    }

    private func assertSameDrawing(_ expected: PKDrawing, _ actual: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.strokes.count, expected.strokes.count, file: file, line: line)
        for (source, target) in zip(expected.strokes, actual.strokes) {
            XCTAssertEqual(target.path.count, source.path.count, file: file, line: line)
            for (first, second) in zip(source.path, target.path) {
                let before = first.location.applying(source.transform)
                let after = second.location.applying(target.transform)
                XCTAssertEqual(after.x, before.x, accuracy: 0.01, "Ink moved horizontally on paper.", file: file, line: line)
                XCTAssertEqual(after.y, before.y, accuracy: 0.01, "Ink moved vertically on paper.", file: file, line: line)
                XCTAssertEqual(second.size.width * hypot(target.transform.a, target.transform.b),
                    first.size.width * hypot(source.transform.a, source.transform.b), accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(second.size.height * hypot(target.transform.c, target.transform.d),
                    first.size.height * hypot(source.transform.c, source.transform.d), accuracy: 0.01, file: file, line: line)
            }
        }
    }

    private func makeChart(sourceCanvasWidth: CGFloat, withInk: Bool) -> Chart {
        var chart = Chart.draft(title: "Disposable fixed paper", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 8)
        if withInk {
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: CGSize(width: sourceCanvasWidth, height: 1_400))
            let frame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
            chart.pageHandwrittenNotationData = drawing(rightEdge: frame.width - 40).dataRepresentation()
            chart.pageHandwrittenNotationCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                for: layout, relativeTo: frame)
        }
        return chart
    }

    private func drawing(rightEdge: CGFloat) -> PKDrawing {
        PKDrawing(strokes: [CGFloat(100), rightEdge].enumerated().map { index, x in
            let points = [CGPoint(x: x, y: 400), CGPoint(x: x + 12, y: 420), CGPoint(x: x + 22, y: 402)]
                .enumerated().map { offset, location in
                    PKStrokePoint(location: location, timeOffset: Double(offset) * 0.1,
                        size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(index))),
                transform: .identity, mask: nil, randomSeed: UInt32(101 + index))
        })
    }

    private func mount(_ chart: Chart, viewport: CGSize, mode: EditorCanvasMode = .freeHand) async throws -> MountedEditor {
        let model = FixedPaperEditorChartModel(chart)
        let isolatedRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = FixedPaperEditorHarness(model: model,
            correctionsURL: isolatedRoot.appendingPathComponent("corrections.json"), initialMode: mode)
            .environmentObject(ChartLibraryStore(charts: [chart], selectedChartID: chart.id))
            .environmentObject(IChartPDFLibraryStore(baseDirectory: isolatedRoot.appendingPathComponent("PDF Library")))
            .environment(\.accessibilityEnabled, true)
        let controller = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: viewport)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        for _ in 0..<60 {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            if let canvas = descendants(controller.view).compactMap({ $0 as? LeadSheetCanvasUIKitView }).first,
               canvas.bounds.width > 0, canvas.window != nil {
                let mounted = MountedEditor(model: model, window: window, previousKeyWindow: previousKeyWindow,
                    canvas: canvas, isolatedRoot: isolatedRoot)
                await settle(window)
                return mounted
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        throw Failure.canvasDidNotMount
    }

    private func resize(_ mounted: MountedEditor, to size: CGSize) async throws {
        mounted.window.frame = CGRect(origin: .zero, size: size)
        mounted.window.rootViewController?.view.frame = mounted.window.bounds
        mounted.window.setNeedsLayout()
        await settle(mounted.window)
        XCTAssertEqual(mounted.window.bounds.width, size.width, accuracy: 0.01)
        XCTAssertTrue(descendants(mounted.window).contains { $0 === mounted.canvas },
            "The production canvas must still belong to the resized editor.")
    }

    private func activate(_ label: String, in mounted: MountedEditor) async throws {
        for _ in 0..<40 {
            await settle(mounted.window)
            if let node = try NativeAccessibilityLookup.matching(label, in: mounted.window, buttonsOnly: true)
                .first(where: \.isEnabled) {
                if let button = node.element as? UIButton {
                    button.sendActions(for: .touchUpInside)
                } else {
                    XCTAssertTrue(node.element.accessibilityActivate(), "The actual \(label) toolbar action must activate.")
                }
                await settle(mounted.window)
                XCTAssertEqual(mounted.canvas.interactionMode, label == "Select" ? .browse : .freeHand)
                return
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTFail("The production editor did not expose \(label).")
        throw Failure.toolbarUnavailable
    }

    private func authoringCanvas(_ canvas: LeadSheetCanvasUIKitView) throws -> PKCanvasView {
        try XCTUnwrap(canvas.subviews.compactMap { $0 as? PKCanvasView }.last)
    }

    private func parentScrollView(of canvas: UIView) throws -> UIScrollView {
        var parent = canvas.superview
        while let current = parent {
            if let scroll = current as? UIScrollView { return scroll }
            parent = current.superview
        }
        XCTFail("The actual editor canvas must be mounted in a document viewport.")
        throw Failure.viewportUnavailable
    }

    @discardableResult
    private func assertNativeZoomAvailable(in mounted: MountedEditor,
        file: StaticString = #filePath, line: UInt = #line) throws -> UIView {
        let scroll = try parentScrollView(of: mounted.canvas)
        let target = try XCTUnwrap(scroll.delegate?.viewForZooming?(in: scroll),
            "The actual editor must supply a native UIScrollView zoom target.", file: file, line: line)
        XCTAssertTrue(mounted.canvas.isDescendant(of: target), file: file, line: line)
        let pinch = try XCTUnwrap(scroll.pinchGestureRecognizer, file: file, line: line)
        XCTAssertTrue(pinch.isEnabled, "The real pinch recognizer must be enabled.", file: file, line: line)
        XCTAssertTrue(pinch.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.direct.rawValue)),
            "Direct-finger pinches must reach the native zoom path.", file: file, line: line)
        let competingPinches = (scroll.gestureRecognizers ?? []).compactMap { $0 as? UIPinchGestureRecognizer }
            .filter { $0 !== pinch && $0.isEnabled }
        XCTAssertTrue(competingPinches.isEmpty,
            "An enabled parent pinch blocker must not intercept Free Ink navigation.", file: file, line: line)
        let fit = fitWidthScale(in: scroll, zoomTarget: target)
        XCTAssertLessThan(scroll.minimumZoomScale, fit * 0.75, file: file, line: line)
        XCTAssertGreaterThan(scroll.maximumZoomScale, fit * 2.5, file: file, line: line)
        return target
    }

    private func assertInitialFitWidth(in mounted: MountedEditor,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let scroll = try parentScrollView(of: mounted.canvas)
        let target = try assertNativeZoomAvailable(in: mounted, file: file, line: line)
        XCTAssertEqual(target.bounds.width * scroll.zoomScale, scroll.bounds.width, accuracy: 1,
            "Initial fit-width must fill the viewport without changing the document's logical width.", file: file, line: line)
    }

    private func fitWidthScale(in scroll: UIScrollView, zoomTarget: UIView) -> CGFloat {
        scroll.bounds.width / zoomTarget.bounds.width
    }

    private func clampedOffset(_ proposed: CGPoint, in scroll: UIScrollView) -> CGPoint {
        let inset = scroll.adjustedContentInset
        let minimum = CGPoint(x: -inset.left, y: -inset.top)
        let maximum = CGPoint(x: max(minimum.x, scroll.contentSize.width - scroll.bounds.width + inset.right),
            y: max(minimum.y, scroll.contentSize.height - scroll.bounds.height + inset.bottom))
        return CGPoint(x: min(maximum.x, max(minimum.x, proposed.x)),
            y: min(maximum.y, max(minimum.y, proposed.y)))
    }

    private func assertPaperPoint(_ point: CGPoint, atViewportCenterOf scroll: UIScrollView,
        canvas: LeadSheetCanvasUIKitView, file: StaticString = #filePath, line: UInt = #line) {
        let mapped = canvas.convert(point, to: scroll)
        XCTAssertEqual(mapped.x - scroll.bounds.minX, scroll.bounds.width / 2, accuracy: 1,
            "The same paper focal point must remain horizontally centered.", file: file, line: line)
        XCTAssertEqual(mapped.y - scroll.bounds.minY, scroll.bounds.height / 2, accuracy: 1,
            "The same paper focal point must remain vertically centered.", file: file, line: line)
    }

    private func settle(_ window: UIWindow) async {
        for _ in 0..<4 {
            window.layoutIfNeeded()
            window.rootViewController?.view.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private struct ViewportChromeSnapshot {
        let windowFrame: CGRect
        let windowBounds: CGRect
        let rootFrame: CGRect
        let rootBounds: CGRect
        let viewportFrameInWindow: CGRect
        let chromeFrames: [String: CGRect]
        let ancestorGeometry: [String]
    }

    private let chromeLabels = ["Exit Chart", "Select", "Free Ink", "Measures", "Tools"]

    private func viewportChromeSnapshot(in mounted: MountedEditor) throws -> ViewportChromeSnapshot {
        let scroll = try parentScrollView(of: mounted.canvas)
        // Enumerate even offscreen elements. A visibility-filtered lookup would
        // hide the very chrome displacement this regression needs to diagnose.
        let nodes = try NativeAccessibilityLookup.nodes(in: mounted.window)
        var frames: [String: CGRect] = [:]
        for label in chromeLabels {
            if let node = nodes.first(where: { $0.isButton && $0.element.accessibilityLabel == label }) {
                frames[label] = node.frame(in: mounted.window)
            }
        }
        var ancestors: [String] = []
        var current: UIView? = scroll
        while let view = current {
            ancestors.append("\(type(of: view)): frame=\(view.frame), bounds=\(view.bounds), transform=\(view.transform)")
            current = view.superview
        }
        let root = try XCTUnwrap(mounted.window.rootViewController?.view)
        return ViewportChromeSnapshot(windowFrame: mounted.window.frame, windowBounds: mounted.window.bounds,
            rootFrame: root.frame, rootBounds: root.bounds,
            viewportFrameInWindow: scroll.convert(scroll.bounds, to: mounted.window),
            chromeFrames: frames, ancestorGeometry: ancestors)
    }

    private func assertUnchangedViewportAndChrome(before: ViewportChromeSnapshot, after: ViewportChromeSnapshot,
        file: StaticString = #filePath, line: UInt = #line) {
        assertSameRect(after.windowFrame, before.windowFrame, message: "Zoom changed the outer window.", file: file, line: line)
        assertSameRect(after.windowBounds, before.windowBounds, message: "Zoom changed the window coordinate origin.", file: file, line: line)
        assertSameRect(after.rootFrame, before.rootFrame, message: "Zoom moved the root editor.", file: file, line: line)
        assertSameRect(after.rootBounds, before.rootBounds, message: "Zoom changed the root editor bounds.", file: file, line: line)
        assertSameRect(after.viewportFrameInWindow, before.viewportFrameInWindow,
            message: "Zoom resized or moved the outer viewport and displaced the chrome.", file: file, line: line)
        for label in chromeLabels {
            XCTAssertNotNil(before.chromeFrames[label], "Missing pre-zoom \(label) control.", file: file, line: line)
            XCTAssertNotNil(after.chromeFrames[label], "Zoom removed the \(label) control.", file: file, line: line)
            if let oldFrame = before.chromeFrames[label], let newFrame = after.chromeFrames[label] {
                assertSameRect(newFrame, oldFrame, message: "Zoom moved the \(label) chrome.", file: file, line: line)
                XCTAssertGreaterThanOrEqual(newFrame.minX, after.windowBounds.minX - 0.5, label, file: file, line: line)
                XCTAssertGreaterThanOrEqual(newFrame.minY, after.windowBounds.minY - 0.5,
                    "Zoom pushed \(label) above the visible editor.", file: file, line: line)
                XCTAssertLessThanOrEqual(newFrame.maxX, after.windowBounds.maxX + 0.5, label, file: file, line: line)
                XCTAssertLessThanOrEqual(newFrame.maxY, after.windowBounds.maxY + 0.5, label, file: file, line: line)
            }
        }
    }

    private func assertSameRect(_ actual: CGRect, _ expected: CGRect, message: String,
        file: StaticString, line: UInt) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.5, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.5, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, message, file: file, line: line)
    }

    private func attachChromeMeasurements(before: ViewportChromeSnapshot, after: ViewportChromeSnapshot,
        name: String = "Actual viewport and toolbar geometry around document zoom") {
        func describe(_ snapshot: ViewportChromeSnapshot) -> String {
            var lines = ["windowFrame=\(snapshot.windowFrame)", "windowBounds=\(snapshot.windowBounds)",
                "rootFrame=\(snapshot.rootFrame)", "rootBounds=\(snapshot.rootBounds)",
                "viewportFrameInWindow=\(snapshot.viewportFrameInWindow)"]
            lines += snapshot.chromeFrames.keys.sorted().map { "\($0)=\(snapshot.chromeFrames[$0]!)" }
            lines += snapshot.ancestorGeometry
            return lines.joined(separator: "\n")
        }
        let attachment = XCTAttachment(string: "BEFORE ZOOM\n\(describe(before))\n\nAFTER ZOOM\n\(describe(after))")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachViewport(_ window: UIWindow, name: String) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: window.bounds.size))
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

    private struct MountedEditor {
        let model: FixedPaperEditorChartModel
        let window: UIWindow
        let previousKeyWindow: UIWindow?
        let canvas: LeadSheetCanvasUIKitView
        let isolatedRoot: URL
        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
            try? FileManager.default.removeItem(at: isolatedRoot)
        }
    }

    private enum Failure: Error { case canvasDidNotMount, toolbarUnavailable, viewportUnavailable }
}

@MainActor
private final class FixedPaperEditorChartModel: ObservableObject {
    @Published var chart: Chart
    init(_ chart: Chart) { self.chart = chart }
}

@MainActor
private struct FixedPaperEditorHarness: View {
    @ObservedObject var model: FixedPaperEditorChartModel
    let correctionsURL: URL
    let initialMode: EditorCanvasMode

    var body: some View {
        NavigationStack {
            EditorView(chart: $model.chart,
                chordInkUserCorrectionMemoryStore: .init(url: correctionsURL),
                initialCanvasMode: initialMode)
        }
    }
}
#endif
