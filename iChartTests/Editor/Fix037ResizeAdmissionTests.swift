#if canImport(UIKit)
import UIKit
import PencilKit
import XCTest
@testable import iChart

@MainActor
final class Fix037ResizeAdmissionTests: XCTestCase {
    func testInstalledPencilPanResizesSelectedChordAcrossBarlineAndPreservesNeighborInBothStyles() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            let original = try overlappingChart(style: style)
            let selected = original.systems[0].measures[0].chordEvents[0]
            let neighbor = original.systems[0].measures[1].chordEvents[0]
            let host = mount(original)
            defer { host.close() }
            host.canvas.selectedChordID = selected.id
            let page = layout(host.canvas)
            let glyph = try chord(selected.id, in: page)
            let neighborGlyph = try chord(neighbor.id, in: page)
            let boundary = try XCTUnwrap(page.systems.first?.measures.first).trailingBarlineFrame.midX
            XCTAssertLessThan(glyph.frame.minX, boundary)
            XCTAssertGreaterThan(glyph.frame.maxX, boundary)
            XCTAssertTrue(glyph.frame.intersects(neighborGlyph.frame),
                "The regression must contain genuinely overlapping rendered chords")
            let legacyHandleCenter = CGPoint(x: glyph.frame.maxX + 31, y: glyph.frame.midY)
            XCTAssertTrue(LeadSheetChordEditOverlayGeometry.bodySelectionFrame(for: neighborGlyph)
                .contains(legacyHandleCenter), "The neighbor must cover the former resize control")

            let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: glyph, in: page)
            let start = CGPoint(x: controls.trailingResize.midX, y: controls.trailingResize.midY)
            XCTAssertFalse(LeadSheetChordEditOverlayGeometry.bodySelectionFrame(for: neighborGlyph).contains(start))
            XCTAssertTrue(host.canvas.bounds.contains(controls.trailingResize))
            let pan = try XCTUnwrap(host.canvas.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }
                .first { $0.maximumNumberOfTouches == 1 })
            XCTAssertTrue(pan.isEnabled)
            let touch = Fix037PencilTouch(point: start, coordinateView: host.canvas)
            XCTAssertTrue(try XCTUnwrap(pan.delegate?.gestureRecognizer?(pan, shouldReceive: touch)),
                "The installed UIKit delegate must admit the visible control at touch-down")
            XCTAssertTrue(host.canvas.gestureRecognizerShouldBegin(pan))

            // Selection may update while UIKit waits for the pan threshold.
            // It must not change the chord/action already admitted at touch-down.
            host.canvas.selectedChordID = neighbor.id
            var writes = [Chart]()
            host.canvas.onChartChanged = { writes.append($0) }
            // The current Pencil position has left the handle before began and
            // translation is reset. The admitted object and action must persist.
            let movement = min(20, glyph.frame.width * 0.15)
            let event = Fix037Pan(point: CGPoint(x: start.x - movement, y: start.y),
                coordinateView: host.canvas)
            host.canvas.handleRenderedObjectMovePan(event)
            XCTAssertTrue(writes.isEmpty)
            XCTAssertEqual(host.canvas.selectedChordID, selected.id)
            XCTAssertEqual(host.canvas.chart, original)
            event.simulatedState = .changed
            event.point.x -= 2
            host.canvas.handleRenderedObjectMovePan(event)
            XCTAssertTrue(writes.isEmpty, "A resize preview must not persist every input event")
            event.simulatedState = .ended
            host.canvas.handleRenderedObjectMovePan(event)

            XCTAssertEqual(writes.count, 1)
            let resized = try XCTUnwrap(host.canvas.chart.chordEvent(id: selected.id))
            XCTAssertLessThan(try XCTUnwrap(resized.manualHorizontalScale),
                try XCTUnwrap(selected.manualHorizontalScale))
            XCTAssertEqual(resized.startPosition, selected.startPosition)
            XCTAssertEqual(resized.manualLaneFraction, selected.manualLaneFraction)
            XCTAssertEqual(try XCTUnwrap(resized.manualVisualLaneFraction),
                try XCTUnwrap(selected.manualVisualLaneFraction), accuracy: 0.000_001)
            XCTAssertEqual(resized.sourceInkData, selected.sourceInkData)
            XCTAssertEqual(host.canvas.chart.chordEvent(id: neighbor.id), neighbor)
            var expected = original
            expected.systems[0].measures[0].chordEvents[0] = resized
            XCTAssertGreaterThanOrEqual(host.canvas.chart.updatedAt, original.updatedAt)
            expected.updatedAt = host.canvas.chart.updatedAt
            XCTAssertEqual(host.canvas.chart, expected, "Only the selected chord record may change")
            let updatedGlyph = try chord(selected.id, in: layout(host.canvas))
            XCTAssertLessThan(updatedGlyph.frame.width, glyph.frame.width)
            XCTAssertEqual(updatedGlyph.frame.minX, glyph.frame.minX, accuracy: 0.001)
            XCTAssertEqual(updatedGlyph.frame.height, glyph.frame.height, accuracy: 0.001)
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(host.canvas.chart))
            XCTAssertEqual(reopened, expected)
            XCTAssertEqual(try PKDrawing(data: XCTUnwrap(reopened.chordEvent(id: selected.id)?.sourceInkData)).strokes.count, 1)

            // A normal drag on the neighbor remains a neighbor move. It must
            // neither inherit the selected resize action nor change the chart
            // when cancelled.
            let neighborStart = CGPoint(x: neighborGlyph.frame.maxX - 1, y: neighborGlyph.frame.midY)
            XCTAssertTrue(try XCTUnwrap(pan.delegate?.gestureRecognizer?(pan,
                shouldReceive: Fix037PencilTouch(point: neighborStart, coordinateView: host.canvas))))
            XCTAssertTrue(host.canvas.gestureRecognizerShouldBegin(pan))
            let neighborEvent = Fix037Pan(point: CGPoint(x: neighborStart.x + 8, y: neighborStart.y),
                coordinateView: host.canvas)
            host.canvas.handleRenderedObjectMovePan(neighborEvent)
            XCTAssertEqual(host.canvas.selectedChordID, neighbor.id)
            XCTAssertNotNil(host.canvas.chordMovePreviewFrame)
            neighborEvent.simulatedState = .cancelled
            host.canvas.handleRenderedObjectMovePan(neighborEvent)
            XCTAssertEqual(host.canvas.chart, expected)
            XCTAssertEqual(writes.count, 1)
        }
    }

    private func overlappingChart(style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Selected resize at a neighboring chord", measureCount: 2, layoutStyle: style)
        for index in chart.systems[0].measures.indices {
            chart.systems[0].measures[index].authoringState = .committed
            chart.systems[0].measures[index].manualLayoutWidth = 280
        }
        chart.systems[0].measures[0].chordEvents = [try event("Bbmaj7(#11)/D", beat: 3, seed: 37)]
        chart.systems[0].measures[1].chordEvents = [try event("Bbmaj7(#11)/D", beat: 1, seed: 38)]
        var page = layout(chart)
        let selectedID = chart.systems[0].measures[0].chordEvents[0].id
        let neighborID = chart.systems[0].measures[1].chordEvents[0].id
        let firstMeasure = try XCTUnwrap(page.systems.first?.measures.first)
        let width = try chord(selectedID, in: page).frame.width
        let selectedX = firstMeasure.trailingBarlineFrame.midX - width * 0.45
        chart.systems[0].measures[0].chordEvents[0].manualVisualLaneFraction =
            Double((selectedX - firstMeasure.chordBandFrame.minX) / firstMeasure.chordBandFrame.width)
        page = layout(chart)
        let selectedGlyph = try chord(selectedID, in: page)
        let secondMeasure = try XCTUnwrap(page.systems.first?.measures.last)
        let neighborX = selectedGlyph.frame.maxX - 10
        chart.systems[0].measures[1].chordEvents[0].manualVisualLaneFraction =
            Double((neighborX - secondMeasure.chordBandFrame.minX) / secondMeasure.chordBandFrame.width)
        XCTAssertNotEqual(selectedID, neighborID)
        return chart
    }

    private func event(_ text: String, beat: Int, seed: UInt32) throws -> ChordEvent {
        let points = [CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 15), CGPoint(x: 25, y: 5)]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.02,
                size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed)))
        let archive = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path,
            transform: .identity, mask: nil, randomSeed: seed)]).dataRepresentation()
        return ChordEvent(id: UUID(), symbol: try ChordSymbolParser.parse(text), spellingIntent: .explicit,
            startPosition: BeatPosition(beat: beat, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .quarter, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
            rawInput: text, sourceInkData: archive, manualHorizontalScale: 0.85,
            manualLaneFraction: 0.5, manualVisualLaneFraction: 0.5)
    }

    private func layout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_400))
    }

    private func layout(_ canvas: LeadSheetCanvasUIKitView) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: canvas.chart, pageSize: canvas.bounds.size)
    }

    private func chord(_ id: UUID, in page: LeadSheetPageLayout) throws -> LeadSheetChordLayout {
        try XCTUnwrap(page.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == id })
    }

    @MainActor
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
        canvas.interactionMode = .browse
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
private final class Fix037PencilTouch: UITouch {
    let point: CGPoint
    let coordinateView: UIView
    init(point: CGPoint, coordinateView: UIView) {
        self.point = point
        self.coordinateView = coordinateView
        super.init()
    }
    override var type: UITouch.TouchType { .pencil }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
}

@MainActor
private final class Fix037Pan: UIPanGestureRecognizer {
    var point: CGPoint
    var simulatedState: UIGestureRecognizer.State = .began
    let coordinateView: UIView
    init(point: CGPoint, coordinateView: UIView) {
        self.point = point
        self.coordinateView = coordinateView
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
    override var numberOfTouches: Int { 1 }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
    override func translation(in view: UIView?) -> CGPoint { .zero }
}
#endif
