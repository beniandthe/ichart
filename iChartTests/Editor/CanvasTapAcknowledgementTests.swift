#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Installed UIKit routing plus synthetic Pencil/Finger callbacks. This does
/// not claim physical Pencil timing or the enclosing SwiftUI tool workflow.
@MainActor
final class CanvasTapAcknowledgementTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testMeasureTargetsAndTextPlacementAcknowledgeTheirActualCallbacksInBothStyles() throws {
        for style in styles {
            var original = try chart(style)
            let cueID = try XCTUnwrap(original.addCueText("On cue", anchorMeasureID: original.measures[0].id))
            let host = mount(original)
            defer { host.close() }
            let canvas = host.canvas
            let ids = original.measures.map(\.id)
            let recognizerCount = canvas.gestureRecognizers?.count
            for mode in [EditorCanvasMode.repeatEdit, .measureEdit, .timeSignatureEdit] {
                canvas.interactionMode = mode
                var selected: [UUID?] = []
                var signatureTargets: [UUID] = []
                canvas.onMeasureSelectionChanged = { selected.append($0) }
                canvas.onTimeSignatureTargetRequested = { signatureTargets.append($0) }
                // These are the real start/end target callbacks used by Repeats.
                for (id, touch) in [(ids[0], UITouch.TouchType.pencil), (ids[2], .direct), (ids[2], .pencil)] {
                    let target = try measure(id, in: canvas)
                    let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
                    let count = canvas.tapAcknowledgementPresentationCount
                    try selectionTap(at: point, type: touch, in: canvas)
                    XCTAssertEqual(canvas.selectedMeasureID, id)
                    XCTAssertEqual(canvas.interactionMode, mode)
                    XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, count + 1)
                    XCTAssertEqual(canvas.tapAcknowledgementSnapshot?.center, point)
                }
                XCTAssertEqual(selected, [ids[0], ids[2], ids[2]])
                XCTAssertEqual(signatureTargets, mode == .timeSignatureEdit ? [ids[0], ids[2], ids[2]] : [])
                XCTAssertEqual(canvas.chart, original)
            }
            canvas.interactionMode = .textEdit
            var placements: [(UUID, Double)] = []
            canvas.onCueTextPlacementRequested = { placements.append(($0, $1)) }
            let target = try measure(ids[1], in: canvas)
            let point = CGPoint(x: target.staffFrame.minX + target.staffFrame.width * 0.37, y: target.frame.midY)
            var count = canvas.tapAcknowledgementPresentationCount
            try renderedTap(at: point, in: canvas)
            XCTAssertEqual(placements.count, 1)
            XCTAssertEqual(placements.first?.0, ids[1])
            XCTAssertEqual(try XCTUnwrap(placements.first?.1), 0.37, accuracy: 0.001)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, count + 1)
            let cue = try XCTUnwrap(layout(canvas).systems.flatMap(\.measures).flatMap(\.cueTextLayouts).first { $0.id == cueID })
            count = canvas.tapAcknowledgementPresentationCount
            try renderedTap(at: CGPoint(x: cue.frame.midX, y: cue.frame.midY), in: canvas)
            XCTAssertEqual(canvas.selectedCueTextID, cueID)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, count + 1)
            XCTAssertEqual(placements.count, 1)
            XCTAssertEqual(canvas.chart, original)
            XCTAssertEqual(canvas.gestureRecognizers?.count, recognizerCount,
                "Feedback must not install recognizers or change routing")
        }
    }

    func testRenderedSelectionAndDeletionAcknowledgeOnlyAcceptedIntentInBothStyles() throws {
        for style in styles {
            let original = try chart(style)
            let host = mount(original)
            defer { host.close() }
            let canvas = host.canvas
            let chordID = try XCTUnwrap(original.measures[0].chordEvents.first?.id)
            let page = layout(canvas)
            let glyph = try XCTUnwrap(page.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == chordID })
            let body = CGPoint(x: glyph.frame.midX, y: glyph.frame.midY)
            var inspected: [UUID] = []
            canvas.onChordSelectedFromCanvas = { inspected.append($0) }
            for _ in 0..<2 {
                let count = canvas.tapAcknowledgementPresentationCount
                try renderedTap(at: body, in: canvas)
                XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, count + 1)
                XCTAssertEqual(canvas.selectedChordID, chordID)
                XCTAssertEqual(canvas.chart, original)
            }
            XCTAssertEqual(inspected, [chordID, chordID], "Reselecting an existing chord is still accepted")
            let control = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph, in: page).delete
            let delete = CGPoint(x: control.midX, y: control.midY)
            let count = canvas.tapAcknowledgementPresentationCount
            canvas.beginRenderedEditTap(at: delete)
            canvas.handleRenderedEditTapGesture(TapFixture(point: CGPoint(x: delete.x + 8, y: delete.y), view: canvas))
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, count)
            XCTAssertEqual(canvas.chart, original)
            canvas.beginRenderedEditTap(at: delete)
            canvas.handleRenderedEditTapGesture(TapFixture(point: delete, view: canvas, state: .cancelled))
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, count)
            XCTAssertNil(canvas.tapAcknowledgementSnapshot)
            XCTAssertEqual(canvas.chart, original)
            try renderedTap(at: delete, in: canvas)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, count + 1)
            XCTAssertNil(canvas.chart.chordEvent(id: chordID))
            XCTAssertEqual(canvas.chart.measures.map(\.id), original.measures.map(\.id))
        }
    }

    func testIgnoredWritingAndDragInputsStaySilentAndClearAnyPreviousReceipt() throws {
        for style in styles {
            let original = try chart(style)
            let host = mount(original)
            defer { host.close() }
            let canvas = host.canvas
            let emptyPoint = CGPoint(x: 5, y: canvas.bounds.maxY - 20)
            try sendSelectionAction(at: emptyPoint, in: canvas)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, 0)
            canvas.selectedChordID = original.measures[0].chordEvents[0].id
            try sendSelectionAction(at: emptyPoint, in: canvas)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, 0,
                "A blank tap that leaves the chord selected has not accepted a deselection")
            canvas.interactionMode = .chordEntry
            let emptyMeasure = try measure(original.measures[2].id, in: canvas)
            let writingPoint = CGPoint(x: emptyMeasure.chordBandFrame.midX, y: emptyMeasure.chordBandFrame.midY)
            try sendSelectionAction(at: writingPoint, in: canvas)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, 0)
            canvas.interactionMode = .noteEdit
            try sendSelectionAction(at: writingPoint, in: canvas)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, 0, "A bare tap is not a completed lasso")
            canvas.interactionMode = .repeatEdit
            let target = try measure(original.measures[1].id, in: canvas)
            try selectionTap(at: CGPoint(x: target.frame.midX, y: target.frame.midY), type: .pencil, in: canvas)
            XCTAssertNotNil(canvas.tapAcknowledgementSnapshot)
            let count = canvas.tapAcknowledgementPresentationCount
            canvas.interactionMode = .freeHand
            let authoring = try XCTUnwrap(canvas.subviews.compactMap { $0 as? PKCanvasView }.last)
            canvas.canvasViewDidBeginUsingTool(authoring)
            XCTAssertNil(canvas.tapAcknowledgementSnapshot)
            canvas.canvasViewDidEndUsingTool(authoring)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, count)
            canvas.interactionMode = .browse
            let glyph = try XCTUnwrap(layout(canvas).systems.flatMap(\.measures).flatMap(\.chordLayouts).first)
            let body = CGPoint(x: glyph.frame.midX, y: glyph.frame.midY)
            let overlayTap = try installedRenderedTap(canvas)
            XCTAssertFalse(try receives(overlayTap, at: body, type: .direct, in: canvas),
                "Device palm/finger protection must stay in force")
            try renderedTap(at: body, in: canvas)
            let beforeDrag = canvas.tapAcknowledgementPresentationCount
            XCTAssertTrue(canvas.beginRenderedObjectMoveTouch(at: body, touchType: .pencil))
            let pan = PanFixture(point: CGPoint(x: body.x + 20, y: body.y), view: canvas)
            canvas.handleRenderedObjectMovePan(pan)
            XCTAssertNil(canvas.tapAcknowledgementSnapshot)
            pan.simulatedState = .cancelled
            canvas.handleRenderedObjectMovePan(pan)
            XCTAssertEqual(canvas.tapAcknowledgementPresentationCount, beforeDrag)
            XCTAssertEqual(canvas.chart, original)
        }
    }

    func testLayerReceiptReadsAsAShapeScalesWithZoomAndHonorsReduceMotion() async throws {
        let feedback = LeadSheetCanvasTapAcknowledgement()
        let parent = CALayer()
        let point = CGPoint(x: 40, y: 60)
        feedback.present(at: point, in: parent, screenPointsPerDisplayedPoint: 2, reducesMotion: true)
        XCTAssertEqual(feedback.snapshot?.center, point)
        XCTAssertEqual(feedback.snapshot?.frame.size, CGSize(width: 14, height: 14))
        XCTAssertTrue(try XCTUnwrap(feedback.snapshot?.reducesMotion))
        XCTAssertNil(feedback.layer.animationKeys())
        let shapes = try XCTUnwrap(feedback.layer.sublayers?.compactMap { $0 as? CAShapeLayer })
        XCTAssertEqual(shapes.count, 4, "Ring and check have separate white contrast edges")
        XCTAssertTrue(shapes.allSatisfy { $0.path != nil && $0.lineWidth > 0 })
        XCTAssertEqual(shapes[1].strokeColor, IChartInterfaceStyle.actionUIColor.cgColor)
        feedback.present(at: point, in: parent, screenPointsPerDisplayedPoint: 1, reducesMotion: false)
        XCTAssertEqual(parent.sublayers?.count, 1, "Rapid accepted taps reuse one noninteractive layer")
        XCTAssertEqual(feedback.presentationCount, 2)
        XCTAssertEqual(feedback.layer.animationKeys(), ["acceptedTapFade"])
        feedback.present(at: point, in: parent, screenPointsPerDisplayedPoint: 1, reducesMotion: true)
        XCTAssertNil(feedback.layer.animationKeys())
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(feedback.snapshot)
        XCTAssertNil(feedback.layer.superlayer)
    }

    private func chart(_ style: ChartLayoutStyle) throws -> Chart {
        var value = Chart.blank(title: "Tap acknowledgement", measureCount: 4, layoutStyle: style)
        for system in value.systems.indices {
            for measure in value.systems[system].measures.indices {
                value.systems[system].measures[measure].authoringState = .committed
            }
        }
        XCTAssertNotNil(value.appendRecognizedChordEvent(try ChordSymbolParser.parse("Cmaj7"),
            rawInput: "Cmaj7", to: value.measures[0].id, atFraction: 0.25))
        return value
    }
    private func layout(_ canvas: LeadSheetCanvasUIKitView) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: canvas.chart, pageSize: canvas.bounds.size)
    }
    private func measure(_ id: UUID, in canvas: LeadSheetCanvasUIKitView) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(layout(canvas).systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }
    private func receives(_ recognizer: UIGestureRecognizer, at point: CGPoint,
        type: UITouch.TouchType, in canvas: LeadSheetCanvasUIKitView) throws -> Bool {
        try XCTUnwrap(recognizer.delegate?.gestureRecognizer?(recognizer,
            shouldReceive: TouchFixture(point: point, view: canvas, type: type)))
    }
    private func installedRenderedTap(_ canvas: LeadSheetCanvasUIKitView) throws -> UITapGestureRecognizer {
        let overlay = try XCTUnwrap(canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
        return try XCTUnwrap(overlay.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 1 })
    }
    private func renderedTap(at point: CGPoint, in canvas: LeadSheetCanvasUIKitView) throws {
        XCTAssertTrue(try receives(installedRenderedTap(canvas), at: point, type: .pencil, in: canvas))
        canvas.handleRenderedEditTapGesture(TapFixture(point: point, view: canvas))
    }
    private func selectionTap(at point: CGPoint, type: UITouch.TouchType, in canvas: LeadSheetCanvasUIKitView) throws {
        let tap = try XCTUnwrap(canvas.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
        XCTAssertTrue(try receives(tap, at: point, type: type, in: canvas))
        try sendSelectionAction(at: point, in: canvas)
    }
    private func sendSelectionAction(at point: CGPoint, in canvas: LeadSheetCanvasUIKitView) throws {
        let selector = NSSelectorFromString("handleTap:")
        XCTAssertTrue(canvas.responds(to: selector))
        _ = canvas.perform(selector, with: TapFixture(point: point, view: canvas))
    }
    private struct Host {
        let canvas: LeadSheetCanvasUIKitView
        let window: UIWindow
        let previous: UIWindow?
        func close() { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
    }
    private func mount(_ chart: Chart) -> Host {
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 900, height: 1_400),
            chordInkRecognizer: ChordInkMaximumTrustRecognizer(), inputEnvironment: .device)
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
        return Host(canvas: canvas, window: window, previous: previous)
    }
}

@MainActor
private final class TouchFixture: UITouch {
    let point: CGPoint
    let coordinateView: UIView
    let touchType: UITouch.TouchType
    init(point: CGPoint, view: UIView, type: UITouch.TouchType) {
        self.point = point; coordinateView = view; touchType = type
        super.init()
    }
    override var type: UITouch.TouchType { touchType }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}

@MainActor
private final class TapFixture: UITapGestureRecognizer {
    let point: CGPoint
    let coordinateView: UIView
    let simulatedState: UIGestureRecognizer.State
    init(point: CGPoint, view: UIView, state: UIGestureRecognizer.State = .ended) {
        self.point = point; coordinateView = view; simulatedState = state
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State { get { simulatedState } set { } }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}

@MainActor
private final class PanFixture: UIPanGestureRecognizer {
    let point: CGPoint
    let coordinateView: UIView
    var simulatedState: UIGestureRecognizer.State = .began
    init(point: CGPoint, view: UIView) { self.point = point; coordinateView = view; super.init(target: nil, action: nil) }
    override var state: UIGestureRecognizer.State { get { simulatedState } set { simulatedState = newValue } }
    override var numberOfTouches: Int { 1 }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
    override func translation(in view: UIView?) -> CGPoint { CGPoint(x: 20, y: 0) }
}
#endif
