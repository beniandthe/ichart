#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

/// Drives the installed canvas recognizers' touch-admission delegate and the
/// corresponding target actions. These are synthetic UIKit inputs, not physical
/// Pencil timing or an end-to-end SwiftUI repeat workflow.
@MainActor
final class ToolMeasureSelectionRoutingTests: XCTestCase {
    func testMeasureTargetingToolsAdmitFingerAndPencilAndSelectAnotherMeasureInBothStyles() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            let original = chart(style: style)
            let host = mount(original)
            defer { host.close() }
            let measureIDs = original.measures.map(\.id)
            let selectionTap = try selectionRecognizer(in: host.canvas)
            let overlay = try overlay(in: host.canvas)

            for mode in [EditorCanvasMode.repeatEdit, .measureEdit, .timeSignatureEdit, .rhythmicNotationEdit] {
                host.canvas.interactionMode = mode
                host.canvas.layoutIfNeeded()
                XCTAssertTrue(selectionTap.isEnabled)
                XCTAssertTrue(overlay.isHidden)
                XCTAssertFalse(overlay.isUserInteractionEnabled)
                for touchType in [UITouch.TouchType.direct, .pencil] {
                    for targetID in [measureIDs[1], measureIDs[0], measureIDs[2]] {
                        let point = try measurePoint(targetID, in: host.canvas)
                        XCTAssertTrue(try receives(selectionTap, at: point, type: touchType, in: host.canvas),
                            "\(mode) must not give measure selection to its hidden edit overlay (\(style), \(touchType))")
                        try sendSelectionTap(at: point, in: host.canvas)
                        XCTAssertEqual(host.canvas.selectedMeasureID, targetID)
                        XCTAssertEqual(host.canvas.interactionMode, mode,
                            "Choosing a repeat endpoint or measure target must keep the current tool")
                        XCTAssertEqual(host.canvas.chart, original,
                            "Selecting an endpoint must not modify chart content")
                    }
                }
            }
        }
    }

    func testRepeatSelectionSurvivesToolReentryWithoutAStaleOverlayOwner() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            let original = chart(style: style)
            let host = mount(original)
            defer { host.close() }
            let selectionTap = try selectionRecognizer(in: host.canvas)
            let ids = original.measures.map(\.id)
            for interveningMode in [EditorCanvasMode.browse, .textEdit, .measureEdit, .timeSignatureEdit] {
                host.canvas.interactionMode = interveningMode
                host.canvas.interactionMode = .repeatEdit
                let point = try measurePoint(ids[1], in: host.canvas)
                XCTAssertTrue(try receives(selectionTap, at: point, type: .pencil, in: host.canvas))
                try sendSelectionTap(at: point, in: host.canvas)
                XCTAssertEqual(host.canvas.selectedMeasureID, ids[1])
                XCTAssertEqual(host.canvas.interactionMode, .repeatEdit)
                XCTAssertEqual(host.canvas.chart, original)
            }
        }
    }

    func testBrowseOverlayRetainsChordBodyDeleteAndWidthControlOwnershipInBothStyles() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            var original = chart(style: style)
            let chord = ChordEvent(id: UUID(), symbol: try ChordSymbolParser.parse("C"),
                spellingIntent: .explicit,
                startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
                duration: .quarter, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
                rawInput: "C", sourceInkData: nil, manualDisplayWidth: 20)
            original.systems[0].measures[0].chordEvents = [chord]
            let host = mount(original)
            defer { host.close() }
            host.canvas.selectedChordID = chord.id
            let page = layout(host.canvas)
            let glyph = try XCTUnwrap(page.systems.flatMap(\.measures).flatMap(\.chordLayouts)
                .first { $0.id == chord.id })
            let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph, within: host.canvas.bounds)
            let selectionTap = try selectionRecognizer(in: host.canvas)
            let overlay = try overlay(in: host.canvas)
            XCTAssertFalse(overlay.isHidden)
            XCTAssertTrue(overlay.isUserInteractionEnabled)

            for frame in [glyph.frame, controls.delete, controls.trailingResize] {
                let point = CGPoint(x: frame.midX, y: frame.midY)
                XCTAssertTrue(overlay.point(inside: overlay.convert(point, from: host.canvas), with: nil))
                for touchType in [UITouch.TouchType.direct, .pencil] {
                    XCTAssertFalse(try receives(selectionTap, at: point, type: touchType, in: host.canvas),
                        "A live object overlay keeps ownership so measure selection cannot interrupt chord actions")
                }
            }
            XCTAssertEqual(host.canvas.selectedChordID, chord.id)
            XCTAssertEqual(host.canvas.chart, original)
        }
    }

    func testTextOverlayStillOwnsAndRoutesMeasureAndCueTapsInBothStyles() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            var original = chart(style: style)
            let cueID = try XCTUnwrap(original.addCueText("On cue", anchorMeasureID: original.measures[0].id))
            let host = mount(original)
            defer { host.close() }
            host.canvas.interactionMode = .textEdit
            let overlay = try overlay(in: host.canvas)
            let selectionTap = try selectionRecognizer(in: host.canvas)
            let overlayTap = try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
                .first { $0.numberOfTapsRequired == 1 })
            XCTAssertTrue(overlayTap.isEnabled)
            XCTAssertFalse(overlay.isHidden)
            let measureID = original.measures[1].id
            let measurePoint = try measurePoint(measureID, in: host.canvas)
            let cue = try XCTUnwrap(layout(host.canvas).systems.flatMap(\.measures)
                .flatMap(\.cueTextLayouts).first { $0.id == cueID })
            let cuePoint = CGPoint(x: cue.frame.midX, y: cue.frame.midY)

            for point in [measurePoint, cuePoint] {
                XCTAssertFalse(try receives(selectionTap, at: point, type: .pencil, in: host.canvas))
                XCTAssertTrue(try receives(overlayTap, at: point, type: .pencil, in: host.canvas))
                host.canvas.handleRenderedEditTapGesture(MeasureRoutingTap(point: point, coordinateView: host.canvas))
            }
            XCTAssertEqual(host.canvas.selectedCueTextID, cueID)
            XCTAssertEqual(host.canvas.selectedMeasureID, original.measures[0].id)
            XCTAssertEqual(host.canvas.interactionMode, .textEdit)
            XCTAssertEqual(host.canvas.chart, original)
        }
    }

    func testHiddenOrDisabledOverlayDoesNotSuppressTheAvailableMeasureTap() throws {
        let host = mount(chart(style: .rhythmSectionSheet))
        defer { host.close() }
        let selectionTap = try selectionRecognizer(in: host.canvas)
        let overlay = try overlay(in: host.canvas)
        let point = try measurePoint(host.canvas.chart.measures[1].id, in: host.canvas)
        XCTAssertFalse(try receives(selectionTap, at: point, type: .direct, in: host.canvas))

        overlay.isHidden = true
        XCTAssertTrue(try receives(selectionTap, at: point, type: .direct, in: host.canvas))
        overlay.isHidden = false
        overlay.isUserInteractionEnabled = false
        XCTAssertTrue(try receives(selectionTap, at: point, type: .direct, in: host.canvas))
        overlay.isUserInteractionEnabled = true
        let overlayTap = try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 1 })
        overlayTap.isEnabled = false
        XCTAssertTrue(try receives(selectionTap, at: point, type: .direct, in: host.canvas))
    }

    private func chart(style: ChartLayoutStyle) -> Chart {
        var value = Chart.blank(title: "Measure routing fixture", measureCount: 4, layoutStyle: style)
        for systemIndex in value.systems.indices {
            for measureIndex in value.systems[systemIndex].measures.indices {
                value.systems[systemIndex].measures[measureIndex].authoringState = .committed
            }
        }
        return value
    }

    private func layout(_ canvas: LeadSheetCanvasUIKitView) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: canvas.chart, pageSize: canvas.bounds.size)
    }

    private func measurePoint(_ id: UUID, in canvas: LeadSheetCanvasUIKitView) throws -> CGPoint {
        let measure = try XCTUnwrap(layout(canvas).systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
        return CGPoint(x: measure.frame.midX, y: measure.frame.midY)
    }

    private func selectionRecognizer(in canvas: LeadSheetCanvasUIKitView) throws -> UITapGestureRecognizer {
        try XCTUnwrap(canvas.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
    }

    private func overlay(in canvas: LeadSheetCanvasUIKitView) throws -> RenderedEditHitOverlayView {
        try XCTUnwrap(canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
    }

    private func receives(_ recognizer: UIGestureRecognizer, at point: CGPoint,
        type: UITouch.TouchType, in canvas: LeadSheetCanvasUIKitView) throws -> Bool {
        try XCTUnwrap(recognizer.delegate?.gestureRecognizer?(recognizer,
            shouldReceive: MeasureRoutingTouch(point: point, coordinateView: canvas, touchType: type)))
    }

    private func sendSelectionTap(at point: CGPoint, in canvas: LeadSheetCanvasUIKitView) throws {
        let selector = NSSelectorFromString("handleTap:")
        XCTAssertTrue(canvas.responds(to: selector))
        _ = canvas.perform(selector, with: MeasureRoutingTap(point: point, coordinateView: canvas))
    }

    private struct Host {
        let canvas: LeadSheetCanvasUIKitView
        let window: UIWindow
        let previousWindow: UIWindow?
        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
    }

    private func mount(_ chart: Chart) -> Host {
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 900, height: 1_400))
        canvas.recognizesChordInk = false
        canvas.chart = chart
        let controller = UIViewController()
        controller.view = canvas
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(frame: canvas.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        return Host(canvas: canvas, window: window, previousWindow: previous)
    }
}

@MainActor
private final class MeasureRoutingTouch: UITouch {
    let point: CGPoint
    let coordinateView: UIView
    let touchType: UITouch.TouchType
    init(point: CGPoint, coordinateView: UIView, touchType: UITouch.TouchType) {
        self.point = point
        self.coordinateView = coordinateView
        self.touchType = touchType
        super.init()
    }
    override var type: UITouch.TouchType { touchType }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}

@MainActor
private final class MeasureRoutingTap: UITapGestureRecognizer {
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
