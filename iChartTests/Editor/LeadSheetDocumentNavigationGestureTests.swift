#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// The installed viewport gestures must ask the live canvas who owns a contact.
/// A static touch-count policy cannot detect a disconnected routing delegate.
@MainActor
final class LeadSheetDocumentNavigationGestureTests: XCTestCase {
    private let documentSize = CGSize(width: 932, height: 2_400)
    private let viewportSize = CGSize(width: 820, height: 620)

    func testInstalledNavigationRecognizersKeepSingleContactVerticalAndTwoFingerNativeNavigation() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        let vertical = try verticalPan(in: host.viewport)
        let nativePan = host.viewport.panGestureRecognizer
        let nativeDelegate = nativePan.delegate
        let pinch = try XCTUnwrap(host.viewport.pinchGestureRecognizer)

        XCTAssertNotNil(vertical.delegate)
        XCTAssertFalse(vertical.delegate === host.viewport)
        XCTAssertFalse(vertical.delegate === nativeDelegate,
            "Owned input routing must not replace UIKit's native navigation delegate")
        XCTAssertEqual(vertical.minimumNumberOfTouches, 1)
        XCTAssertEqual(vertical.maximumNumberOfTouches, 1)
        XCTAssertEqual(Set(vertical.allowedTouchTypes.map(\.intValue)),
            Set([UITouch.TouchType.direct.rawValue, UITouch.TouchType.pencil.rawValue]))
        XCTAssertTrue(vertical.requiresExclusiveTouchType)
        XCTAssertEqual(vertical.delegate?.gestureRecognizer?(vertical,
            shouldRecognizeSimultaneouslyWith: nativePan), true)
        XCTAssertEqual(vertical.delegate?.gestureRecognizer?(vertical,
            shouldRecognizeSimultaneouslyWith: pinch), true)
        XCTAssertEqual(vertical.delegate?.gestureRecognizer?(vertical,
            shouldRecognizeSimultaneouslyWith: host.inkCanvas.drawingGestureRecognizer), false,
            "Vertical navigation cannot simultaneously claim a PencilKit writing contact")

        for mode in [EditorCanvasMode.chordEntry, .freeHand, .headerEntry, .noteEdit, .browse] {
            setMode(mode, on: host)
            XCTAssertTrue(try verticalPan(in: host.viewport) === vertical,
                "Tool changes must retain one installed vertical recognizer")
            XCTAssertTrue(nativePan.delegate === nativeDelegate,
                "UIKit must retain ownership of the native pan's delegate")
            XCTAssertEqual(nativePan.minimumNumberOfTouches, 2, mode.telemetryValue)
            XCTAssertEqual(nativePan.maximumNumberOfTouches, 2, mode.telemetryValue)
            XCTAssertEqual(nativePan.allowedTouchTypes,
                [NSNumber(value: UITouch.TouchType.direct.rawValue)], mode.telemetryValue)
            XCTAssertEqual(pinch.allowedTouchTypes,
                [NSNumber(value: UITouch.TouchType.direct.rawValue)], mode.telemetryValue)
            XCTAssertTrue(pinch.isEnabled)
            XCTAssertEqual(host.viewport.gestureRecognizers?.filter {
                $0.name == "LeadSheetDocumentVerticalScroll"
            }.count, 1)
        }
    }

    func testActiveVerticalDelegateAcceptsFingerOnPaperAndPencilMarginButRejectsPencilWriting() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        let vertical = try verticalPan(in: host.viewport)
        let writing = try firstWritingPoint(in: host)
        let margin = CGPoint(x: 2, y: writing.y)
        host.inkCanvas.drawing = sourceDrawing()
        let sourceBefore = host.inkCanvas.drawing.dataRepresentation()

        XCTAssertTrue(try receives(vertical, touchType: .direct, at: writing, in: host.canvas))
        XCTAssertTrue(try receives(vertical, touchType: .pencil, at: margin, in: host.canvas))
        XCTAssertEqual(vertical.delegate?.gestureRecognizerShouldBegin?(vertical), false,
            "The active start delegate must reject a stationary contact before a vertical drag exists")
        XCTAssertFalse(try receives(vertical, touchType: .pencil, at: writing, in: host.canvas),
            "Pencil inside the actual current input frame must stay with PencilKit")
        XCTAssertFalse(try receives(vertical, touchType: .indirect, at: margin, in: host.canvas))
        XCTAssertEqual(host.inkCanvas.drawing.dataRepresentation(), sourceBefore)

        host.inkCanvas.drawingPolicy = .anyInput
        XCTAssertFalse(try receives(vertical, touchType: .direct, at: writing, in: host.canvas),
            "An intentionally finger-enabled canvas must retain finger drawing")
        XCTAssertTrue(try receives(vertical, touchType: .direct, at: margin, in: host.canvas))
    }

    func testModeChangesRouteAgainstTheCurrentFreeInkHeaderAndNoteSelectionRegions() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        let vertical = try verticalPan(in: host.viewport)

        for mode in [EditorCanvasMode.freeHand, .headerEntry, .noteEdit, .chordEntry] {
            setMode(mode, on: host)
            let writing = try firstWritingPoint(in: host)
            let margin = CGPoint(x: 2, y: writing.y)
            XCTAssertFalse(try receives(vertical, touchType: .pencil, at: writing, in: host.canvas), mode.telemetryValue)
            XCTAssertTrue(try receives(vertical, touchType: .direct, at: writing, in: host.canvas), mode.telemetryValue)
            XCTAssertTrue(try receives(vertical, touchType: .pencil, at: margin, in: host.canvas), mode.telemetryValue)
        }
    }

    func testVerticalActionChangesOnlyYOffsetAndPreservesExactInkAndChartWhileHonoringScrollLocks() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        host.inkCanvas.drawing = sourceDrawing()
        let inkBefore = host.inkCanvas.drawing.dataRepresentation()
        let snapshotBefore = LeadSheetInkDrawingSnapshot(drawing: host.inkCanvas.drawing)
        let chartBefore = host.canvas.chart
        host.viewport.setZoomScale(host.viewport.fitWidthScale * 1.8, animated: false)
        host.viewport.setContentOffset(CGPoint(x: 70, y: 230), animated: false)
        host.viewport.layoutIfNeeded()
        let start = host.viewport.contentOffset

        let gesture = NavigationPanFixture()
        gesture.simulatedState = .began
        host.viewport.handleDocumentVerticalScroll(gesture)
        gesture.simulatedState = .changed
        gesture.movement = CGPoint(x: 200, y: -140)
        host.viewport.handleDocumentVerticalScroll(gesture)
        XCTAssertEqual(host.viewport.contentOffset.x, start.x, accuracy: 0.001)
        XCTAssertEqual(host.viewport.contentOffset.y, start.y + 140, accuracy: 1)

        gesture.movement = CGPoint(x: -500, y: 20_000)
        host.viewport.handleDocumentVerticalScroll(gesture)
        XCTAssertEqual(host.viewport.contentOffset.x, start.x, accuracy: 0.001)
        XCTAssertEqual(host.viewport.contentOffset.y, -host.viewport.adjustedContentInset.top, accuracy: 1)
        gesture.simulatedState = .ended
        host.viewport.handleDocumentVerticalScroll(gesture)

        let lockedOffset = host.viewport.contentOffset
        host.viewport.panGestureRecognizer.isEnabled = false
        gesture.simulatedState = .began
        host.viewport.handleDocumentVerticalScroll(gesture)
        gesture.simulatedState = .changed
        gesture.movement = CGPoint(x: 0, y: -300)
        host.viewport.handleDocumentVerticalScroll(gesture)
        XCTAssertEqual(host.viewport.contentOffset, lockedOffset)
        let vertical = try verticalPan(in: host.viewport)
        XCTAssertFalse(try receives(vertical, touchType: .pencil,
            at: CGPoint(x: 2, y: 100), in: host.canvas))

        XCTAssertEqual(host.inkCanvas.drawing.dataRepresentation(), inkBefore)
        XCTAssertEqual(LeadSheetInkDrawingSnapshot(drawing: host.inkCanvas.drawing), snapshotBefore)
        XCTAssertEqual(host.canvas.chart, chartBefore,
            "Navigation must not consume or reclassify source ink")
    }

    func testActiveVerticalDelegateLeavesRenderedChordAndMeasureResizeContactsWithTheirOwners() throws {
        let host = try makeHost(withRenderedChord: true)
        defer { host.window.isHidden = true }
        let vertical = try verticalPan(in: host.viewport)
        let layout = self.layout(for: host)
        let chord = try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first)
        let body = CGPoint(x: chord.frame.midX, y: chord.frame.midY)
        XCTAssertFalse(try receives(vertical, touchType: .pencil, at: body, in: host.canvas))
        XCTAssertFalse(try receives(vertical, touchType: .direct, at: body, in: host.canvas),
            "A finger on an explicit rendered edit target must not start page scrolling")

        for mode in [EditorCanvasMode.browse, .measureEdit] {
            setMode(mode, on: host)
            host.canvas.selectedMeasureID = nil
            let modeLayout = self.layout(for: host)
            // An empty source measure can still contain a neighboring long
            // chord's visible overhang. Use genuinely unoccupied visible paper;
            // the rendered chord owner checks above must remain effective.
            let occupiedFrames = modeLayout.systems.flatMap(\.measures)
                .flatMap(\.chordLayouts).flatMap { chord -> [CGRect] in
                    let controls = LeadSheetChordEditOverlayGeometry.controlFrames(
                        for: chord, within: modeLayout.pageBounds)
                    let outset = LeadSheetChordEditOverlayGeometry.controlHitOutset
                    return [
                        LeadSheetChordEditOverlayGeometry.selectedMoveBodyFrame(for: chord),
                        controls.delete.insetBy(dx: -outset, dy: -outset),
                        controls.trailingResize.insetBy(dx: -outset, dy: -outset)
                    ]
                }
            let bodyPoint = try XCTUnwrap(modeLayout.systems.flatMap(\.measures)
                .filter { $0.sourceMeasureID != nil && $0.chordLayouts.isEmpty }
                .map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
                .first { point in
                    !occupiedFrames.contains { $0.contains(point) }
                        && host.viewport.bounds.contains(host.canvas.convert(point, to: host.viewport))
                }, "The fixture must offer visible blank paper outside every chord and control")
            XCTAssertFalse(occupiedFrames.contains { $0.contains(bodyPoint) })
            XCTAssertTrue(host.viewport.bounds.contains(host.canvas.convert(bodyPoint, to: host.viewport)))
            XCTAssertTrue(try receives(vertical, touchType: .direct, at: bodyPoint, in: host.canvas),
                "A broad measure selection target must not block scrolling across blank paper: \(mode.telemetryValue)")
            XCTAssertTrue(try receives(vertical, touchType: .pencil, at: bodyPoint, in: host.canvas), mode.telemetryValue)
        }
        let measureLayout = self.layout(for: host)
        let measure = try XCTUnwrap(measureLayout.systems.flatMap(\.measures)
            .first { $0.sourceMeasureID != nil && $0.chordLayouts.isEmpty })
        host.canvas.selectedMeasureID = measure.sourceMeasureID
        let handle = LeadSheetMeasureResizeGeometry.handleFrames(for: measure).left
        let handlePoint = CGPoint(x: handle.midX, y: handle.midY)
        XCTAssertFalse(try receives(vertical, touchType: .pencil, at: handlePoint, in: host.canvas))
        XCTAssertFalse(try receives(vertical, touchType: .direct, at: handlePoint, in: host.canvas))
    }

    func testRenderedChordDoubleTapRoutesExactEventForFingerAndPencilWithoutDrawingOrConsumingSource() throws {
        let host = try makeHost(withRenderedChord: true)
        defer { host.window.isHidden = true }
        let overlay = try XCTUnwrap(host.canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
        let doubleTap = try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 2 })
        XCTAssertTrue(doubleTap.isEnabled)
        XCTAssertTrue(doubleTap.delegate === host.canvas)
        let layout = self.layout(for: host)
        let chord = try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first)
        let chordPoint = CGPoint(x: chord.frame.midX, y: chord.frame.midY)
        XCTAssertEqual(LeadSheetChordEditOverlayGeometry.hitTarget(at: chordPoint, in: layout)?.action, .review,
            "The fixture must address the review body rather than a resize or delete control")
        let inputFrame = try XCTUnwrap(host.inkCanvas.localInputFrames.first)
        let emptyWriting = host.inkCanvas.convert(CGPoint(x: inputFrame.maxX - 30, y: inputFrame.midY), to: host.canvas)
        XCTAssertTrue(try receives(doubleTap, touchType: .direct, at: chordPoint, in: host.canvas))
        XCTAssertTrue(try receives(doubleTap, touchType: .pencil, at: chordPoint, in: host.canvas))
        XCTAssertFalse(try receives(doubleTap, touchType: .direct, at: emptyWriting, in: host.canvas))
        XCTAssertFalse(try receives(doubleTap, touchType: .pencil, at: emptyWriting, in: host.canvas))

        let sourceBefore = host.canvas.chart.measures.flatMap(\.chordEvents).map(\.sourceInkData)
        let pendingInkBefore = host.inkCanvas.drawing.dataRepresentation()
        var correctedEventIDs: [UUID] = []
        host.canvas.onChordCorrectionRequested = { correctedEventIDs.append($0) }
        let completedTap = NavigationTapFixture(point: chordPoint, coordinateView: host.canvas)
        let selector = NSSelectorFromString("handleChordCorrectionDoubleTap:")
        XCTAssertTrue(host.canvas.responds(to: selector))
        _ = host.canvas.perform(selector, with: completedTap)
        XCTAssertEqual(correctedEventIDs, [chord.id])
        XCTAssertEqual(host.canvas.selectedChordID, chord.id)
        XCTAssertEqual(host.canvas.chart.measures.flatMap(\.chordEvents).map(\.sourceInkData), sourceBefore)
        XCTAssertEqual(host.inkCanvas.drawing.dataRepresentation(), pendingInkBefore)
    }

    func testNarrowCDoubleTapUsesVisibleGlyphInsteadOfPaddedDeleteOrResizeControls() throws {
        try assertNarrowChordDoubleTap("C")
    }

    func testNarrowGDoubleTapUsesVisibleGlyphInsteadOfPaddedDeleteOrResizeControls() throws {
        try assertNarrowChordDoubleTap("G")
    }

    private func assertNarrowChordDoubleTap(_ text: String) throws {
        let host = try makeHost(withRenderedChord: true, renderedChordText: text)
        defer { host.window.isHidden = true }
        host.inkCanvas.drawing = sourceDrawing()
        let sourceBefore = host.canvas.chart.measures.flatMap(\.chordEvents).map(\.sourceInkData)
        let eventSource = try XCTUnwrap(host.canvas.chart.measures.flatMap(\.chordEvents).first?.sourceInkData)
        XCTAssertFalse(eventSource.isEmpty,
            "The rendered event must carry actual source ink")
        let pendingInkBefore = host.inkCanvas.drawing.dataRepresentation()
        XCTAssertFalse(host.inkCanvas.drawing.strokes.isEmpty)
        let chartBefore = host.canvas.chart
        let overlay = try XCTUnwrap(host.canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
        let doubleTap = try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 2 })
        let singleTap = try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 1 })
        XCTAssertTrue(doubleTap.isEnabled)
        XCTAssertTrue(doubleTap.delegate === host.canvas)
        let currentLayout = self.layout(for: host)
        let chord = try XCTUnwrap(currentLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first)
        XCTAssertGreaterThan(chord.frame.width, 2)
        XCTAssertLessThan(chord.frame.width,
            LeadSheetChordEditOverlayGeometry.controlSize + 2 * LeadSheetChordEditOverlayGeometry.controlHitOutset,
            "This regression fixture must exercise a narrow visible \(text) glyph")
        let glyphPoints = [
            CGPoint(x: chord.frame.minX + 1, y: chord.frame.midY),
            CGPoint(x: chord.frame.midX, y: chord.frame.midY),
            CGPoint(x: chord.frame.maxX - 1, y: chord.frame.midY)
        ]
        let sourceMeasure = try XCTUnwrap(currentLayout.systems.flatMap(\.measures)
            .first { $0.chordLayouts.contains { $0.id == chord.id } }?.sourceMeasureID)
        let actualControls = LeadSheetChordEditOverlayGeometry.controlFrames(
            for: chord, within: currentLayout.pageBounds)
        let outset = LeadSheetChordEditOverlayGeometry.controlHitOutset
        for control in [actualControls.delete, actualControls.trailingResize] {
            XCTAssertFalse(control.insetBy(dx: -outset, dy: -outset)
                .intersects(LeadSheetChordEditOverlayGeometry.bodySelectionFrame(for: chord)),
                "Padded controls must stay outside the complete narrow glyph body")
        }
        for glyphPoint in glyphPoints {
            let target = try XCTUnwrap(LeadSheetChordEditOverlayGeometry.hitTarget(
                at: glyphPoint, in: currentLayout))
            XCTAssertEqual(target.action, .review,
                "Visible glyph samples must no longer be intercepted by padded controls")
            XCTAssertEqual(target.chordID, chord.id)
            XCTAssertEqual(target.measureID, sourceMeasure)
        }

        var correctedEventIDs: [UUID] = []
        host.canvas.onChordCorrectionRequested = { correctedEventIDs.append($0) }
        let selector = NSSelectorFromString("handleChordCorrectionDoubleTap:")
        XCTAssertTrue(host.canvas.responds(to: selector))
        for wasSelected in [false, true] {
            for glyphPoint in glyphPoints {
                XCTAssertTrue(chord.frame.contains(glyphPoint))
                XCTAssertTrue(overlay.point(inside: overlay.convert(glyphPoint, from: host.canvas), with: nil),
                    "The actual overlay must receive the narrow visible glyph")
                for touchType in [UITouch.TouchType.direct, .pencil] {
                    host.canvas.selectedChordID = wasSelected ? chord.id : nil
                    XCTAssertTrue(try receives(doubleTap, touchType: touchType, at: glyphPoint, in: host.canvas),
                        "\(text), selected=\(wasSelected), touch=\(touchType), point=\(glyphPoint)")
                    let countBefore = correctedEventIDs.count
                    let completedTap = NavigationTapFixture(point: glyphPoint, coordinateView: host.canvas)
                    _ = host.canvas.perform(selector, with: completedTap)
                    XCTAssertEqual(Array(correctedEventIDs.dropFirst(countBefore)), [chord.id])
                    XCTAssertEqual(host.canvas.selectedChordID, chord.id)
                }
            }
        }

        let controls = actualControls
        let outsideControls: [(CGPoint, ChordEditHitTarget.Action)] = [
            (CGPoint(x: controls.delete.midX, y: controls.delete.midY), .delete),
            (CGPoint(x: controls.trailingResize.midX, y: controls.trailingResize.midY), .resizeTrailing)
        ]
        for (point, expectedAction) in outsideControls {
            XCTAssertFalse(chord.frame.contains(point))
            XCTAssertEqual(LeadSheetChordEditOverlayGeometry.hitTarget(at: point, in: currentLayout)?.action,
                expectedAction, "The generic single-tap control geometry must remain intact")
            XCTAssertTrue(try receives(singleTap, touchType: .pencil, at: point, in: host.canvas))
            for touchType in [UITouch.TouchType.direct, .pencil] {
                XCTAssertFalse(try receives(doubleTap, touchType: touchType, at: point, in: host.canvas),
                    "A control outside the visible glyph must not open chord correction")
            }
            let countBefore = correctedEventIDs.count
            _ = host.canvas.perform(selector,
                with: NavigationTapFixture(point: point, coordinateView: host.canvas))
            XCTAssertEqual(correctedEventIDs.count, countBefore)
        }
        XCTAssertEqual(host.canvas.chart.measures.flatMap(\.chordEvents).map(\.sourceInkData), sourceBefore)
        XCTAssertEqual(host.inkCanvas.drawing.dataRepresentation(), pendingInkBefore)
        XCTAssertEqual(host.canvas.chart, chartBefore,
            "Double-tap routing may select an event, but must not alter its label, timing, or source")
    }

    private struct Host {
        let window: UIWindow
        let viewport: LeadSheetDocumentViewport
        let canvas: LeadSheetCanvasUIKitView
        let inkCanvas: LeadSheetScopedInkCanvasView
    }

    private func makeHost(withRenderedChord: Bool = false, renderedChordText: String = "Cmaj7/E") throws -> Host {
        var chart = Chart.draft(title: "Document navigation", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 32)
        if withRenderedChord {
            let symbol = try XCTUnwrap(ChordRecognitionCompendium.match(renderedChordText)?.symbol)
            _ = try XCTUnwrap(chart.appendRecognizedChordEvent(symbol, rawInput: renderedChordText,
                to: chart.measures[0].id, atFraction: 0.15))
            chart.systems[0].measures[0].chordEvents[0].sourceInkData = sourceDrawing().dataRepresentation()
        }
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: documentSize))
        canvas.recognizesChordInk = false
        canvas.chart = chart
        canvas.interactionMode = .chordEntry
        let viewport = LeadSheetDocumentViewport(documentView: canvas)
        viewport.frame = CGRect(origin: .zero, size: viewportSize)
        let controller = UIViewController()
        controller.view.addSubview(viewport)
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewportSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        viewport.update(documentID: chart.id, documentSize: documentSize, interactionMode: .chordEntry)
        viewport.layoutIfNeeded()
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        let ink = try XCTUnwrap(canvas.subviews.compactMap { $0 as? LeadSheetScopedInkCanvasView }.first)
        ink.drawingPolicy = .pencilOnly
        XCTAssertFalse(ink.isHidden)
        XCTAssertTrue(ink.isUserInteractionEnabled)
        return Host(window: window, viewport: viewport, canvas: canvas, inkCanvas: ink)
    }

    private func setMode(_ mode: EditorCanvasMode, on host: Host) {
        host.canvas.interactionMode = mode
        host.viewport.update(documentID: host.canvas.chart.id, documentSize: documentSize, interactionMode: mode)
        host.viewport.layoutIfNeeded()
        host.canvas.setNeedsLayout()
        host.canvas.layoutIfNeeded()
        // The simulator deliberately permits finger ink. This fixture checks
        // the physical iPad's Pencil-only routing without changing that policy.
        host.inkCanvas.drawingPolicy = .pencilOnly
    }

    private func layout(for host: Host) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: host.canvas.chart, pageSize: documentSize,
            includesChordInkContinuationLanes: host.canvas.interactionMode.allowsChordInkEditing)
    }

    private func firstWritingPoint(in host: Host) throws -> CGPoint {
        let visibleDocument = host.canvas.convert(host.viewport.bounds, from: host.viewport)
        let visibleInk = host.inkCanvas.convert(visibleDocument, from: host.canvas)
        let frame = try XCTUnwrap(host.inkCanvas.localInputFrames.map {
            $0.intersection(visibleInk)
        }.first { !$0.isNull && !$0.isEmpty })
        return host.inkCanvas.convert(CGPoint(x: frame.midX,
            y: frame.minY + min(20, frame.height / 2)), to: host.canvas)
    }

    private func verticalPan(in viewport: LeadSheetDocumentViewport) throws -> UIPanGestureRecognizer {
        try XCTUnwrap(viewport.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }
            .first { $0.name == "LeadSheetDocumentVerticalScroll" })
    }

    private func receives(_ gesture: UIGestureRecognizer, touchType: UITouch.TouchType,
        at point: CGPoint, in coordinateView: UIView) throws -> Bool {
        let touch = NavigationTouchFixture(type: touchType, point: point, coordinateView: coordinateView)
        return try XCTUnwrap(gesture.delegate?.gestureRecognizer?(gesture, shouldReceive: touch),
            "The installed recognizer must expose a live touch-routing delegate")
    }

    private func sourceDrawing() -> PKDrawing {
        let points = [CGPoint(x: 24, y: 24), CGPoint(x: 40, y: 12), CGPoint(x: 52, y: 40)]
            .enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 10)),
            transform: .identity, mask: nil, randomSeed: 17)])
    }
}

@MainActor
private final class NavigationTouchFixture: UITouch {
    let simulatedType: UITouch.TouchType
    let point: CGPoint
    let coordinateView: UIView

    init(type: UITouch.TouchType, point: CGPoint, coordinateView: UIView) {
        simulatedType = type
        self.point = point
        self.coordinateView = coordinateView
        super.init()
    }

    override var type: UITouch.TouchType { simulatedType }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}

@MainActor
private final class NavigationPanFixture: UIPanGestureRecognizer {
    var simulatedState: UIGestureRecognizer.State = .possible
    var movement = CGPoint.zero

    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
    override var numberOfTouches: Int { 1 }
    override func translation(in view: UIView?) -> CGPoint { movement }
}

@MainActor
private final class NavigationTapFixture: UITapGestureRecognizer {
    let point: CGPoint
    let coordinateView: UIView

    init(point: CGPoint, coordinateView: UIView) {
        self.point = point
        self.coordinateView = coordinateView
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { .ended }
        set { }
    }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}
#endif
