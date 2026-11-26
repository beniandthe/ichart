#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Mounted UIKit handler timings, including any requested backing redraw. These
/// are repeatable synthetic input samples, not a physical Pencil/GPU frame-rate claim.
@MainActor
final class PaperInteractionPerformanceTests: XCTestCase {
    private enum Operation: String {
        case measureMove, measureResize, chordResize
    }

    func testPopulatedMeasureMovementReusesPreviewUntilOneCommit() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            try exercise(.measureMove, style: style)
        }
    }

    func testPopulatedMeasureResizeReusesPreviewUntilOneCommit() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            try exercise(.measureResize, style: style)
        }
    }

    func testPopulatedChordResizeReusesPreviewUntilOneCommit() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            try exercise(.chordResize, style: style)
        }
    }

    private func exercise(_ operation: Operation, style: ChartLayoutStyle) throws {
        let original = try populatedChart(style)
        let host = mount(original)
        defer { host.close() }
        let measureID = original.measures[operation == .measureMove ? 3 : 1].id
        let chordID = try XCTUnwrap(original.measure(id: measureID)?.chordEvents.first?.id)
        if operation == .chordResize {
            host.canvas.selectedChordID = chordID
        } else {
            host.canvas.selectedMeasureID = measureID
        }
        let page = LeadSheetPageLayoutEngine.pageLayout(for: original, pageSize: host.canvas.bounds.size)
        let measure = try XCTUnwrap(page.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
        let context = RenderedEditContext(pageLayout: page, layoutStyle: style,
            selection: RenderedEditSelectionState(selectedObjectID: operation == .chordResize
                ? .chord(chordID) : .measure(measureID)),
            allowsUnselectedChordMove: true, allowsSelectedMeasureMove: true)
        let start: CGPoint
        switch operation {
        case .measureMove:
            let frame = LeadSheetMeasureResizeGeometry.moveHandleFrame(for: measure)
            start = CGPoint(x: frame.midX, y: frame.midY)
        case .measureResize:
            let frame = LeadSheetMeasureResizeGeometry.handleFrames(for: measure).right
            start = CGPoint(x: frame.midX, y: frame.midY)
        case .chordResize:
            // Use the actual provider's protected/relocated handle target. The
            // simple controlFrames overload ignores neighboring glyph bodies.
            let target = try XCTUnwrap(ChordRenderedEditHitTargetProvider().hitTargets(in: context)
                .first { $0.objectID == .chord(chordID) && $0.action == .resizeTrailing })
            start = CGPoint(x: target.frame.midX, y: target.frame.midY)
        }

        if operation != .measureResize {
            let resolved = try XCTUnwrap(RenderedEditRouter().dragTarget(at: start, in: context))
            XCTAssertEqual(resolved.objectID, operation == .chordResize ? .chord(chordID) : .measure(measureID))
            XCTAssertEqual(resolved.action, operation == .chordResize ? .resizeTrailing : .move)
            guard host.canvas.beginRenderedObjectMoveTouch(at: start, touchType: .pencil) else {
                XCTFail("The real Pencil drag must be admitted before recording timings")
                return
            }
        }
        let pan = PaperPerformancePan(point: start, state: .began, coordinateView: host.canvas)
        var writes = [Chart]()
        host.canvas.onChartChanged = { writes.append($0) }
        dispatch(pan, operation: operation, canvas: host.canvas)
        host.canvas.layer.displayIfNeeded()
        XCTAssertFalse(host.canvas.layer.needsDisplay())
        XCTAssertTrue(writes.isEmpty)
        if operation == .measureMove {
            _ = try XCTUnwrap(host.canvas.layer.sublayers?.first { $0.name == "measureMove.snapshot" },
                "The real measure move handler must start before timing samples")
        }
        // BEGIN HOST DIAGNOSTICS
        host.canvas.resetInteractionPerformanceTestCounters()
        // END HOST DIAGNOSTICS

        var samples = [Double]()
        var backingInvalidationSamples = 0
        pan.simulatedState = .changed
        for index in 0..<96 {
            // Keep every sample inside the row and above meaningful-translation
            // thresholds; finish away from the original position/width.
            let magnitude = operation == .measureMove
                ? measure.frame.width * 1.5 + CGFloat(index % 37)
                : 24 + CGFloat(index % 37)
            let delta = operation == .chordResize ? magnitude : -magnitude
            pan.point = CGPoint(x: start.x + delta, y: start.y)
            pan.movement = CGPoint(x: delta, y: 0)
            let began = ProcessInfo.processInfo.systemUptime
            dispatch(pan, operation: operation, canvas: host.canvas)
            if host.canvas.layer.needsDisplay() { backingInvalidationSamples += 1 }
            host.canvas.layer.displayIfNeeded()
            samples.append((ProcessInfo.processInfo.systemUptime - began) * 1_000)
        }
        // BEGIN HOST DIAGNOSTICS
        let previewCounters = host.canvas.interactionPerformanceTestSnapshot
        // END HOST DIAGNOSTICS
        XCTAssertEqual(backingInvalidationSamples, 0,
            "Changed samples must update cached preview layers rather than redraw the chart")
        // BEGIN HOST DIAGNOSTICS
        for key in ["backing_draws", "layout_builds", "chart_writebacks", "paper_move_model_updates"] {
            XCTAssertEqual(previewCounters[key], 0,
                "\(operation.rawValue) must not rebuild \(key) for each changed sample")
        }
        // END HOST DIAGNOSTICS
        XCTAssertTrue(host.canvas.chart == original,
            "The saved model must stay untouched until the Pencil lifts")
        XCTAssertTrue(writes.isEmpty)

        pan.simulatedState = .ended
        dispatch(pan, operation: operation, canvas: host.canvas)
        XCTAssertEqual(writes.count, 1, "One completed gesture commits exactly once")
        // BEGIN HOST DIAGNOSTICS
        let committedCounters = host.canvas.interactionPerformanceTestSnapshot
        XCTAssertEqual(committedCounters["chart_writebacks"], 1)
        XCTAssertEqual(committedCounters["paper_move_model_updates"], operation == .measureMove ? 1 : 0)
        // END HOST DIAGNOSTICS
        let saved = host.canvas.chart
        let meaningfulEdit: Bool
        switch operation {
        case .measureMove:
            meaningfulEdit = saved.measure(id: measureID)?.paperLayout?.startFraction
                != original.measure(id: measureID)?.paperLayout?.startFraction
        case .measureResize:
            meaningfulEdit = saved.measure(id: measureID)?.paperLayout?.widthFraction
                != original.measure(id: measureID)?.paperLayout?.widthFraction
        case .chordResize:
            meaningfulEdit = saved.chordEvent(id: chordID)?.manualHorizontalScale
                != original.chordEvent(id: chordID)?.manualHorizontalScale
        }
        guard writes.count == 1, meaningfulEdit else {
            XCTFail("The intended \(operation.rawValue) did not commit; no timings are valid")
            return
        }
        // BEGIN HOST DIAGNOSTICS
        try record(samples, operation: operation, chart: original,
            backingInvalidationSamples: backingInvalidationSamples, counters: previewCounters)
        // END HOST DIAGNOSTICS
        let originalIDs = Set(original.measures.map(\.id))
        XCTAssertTrue(originalIDs.isSubset(of: Set(saved.measures.map(\.id))))
        XCTAssertTrue(saved.measures.filter { !originalIDs.contains($0.id) }.allSatisfy { $0.chordEvents.isEmpty },
            "A newly enclosed gap may become a blank measure, without replacing an existing owner")
        XCTAssertEqual(saved.pageHandwrittenNotationData, original.pageHandwrittenNotationData)
        XCTAssertEqual(saved.measures.flatMap(\.chordEvents).count, 64)
        for event in original.measures.flatMap(\.chordEvents) {
            let retained = try XCTUnwrap(saved.chordEvent(id: event.id))
            XCTAssertEqual(retained.symbol, event.symbol)
            XCTAssertEqual(retained.sourceInkData, event.sourceInkData)
        }
        if operation == .chordResize {
            XCTAssertNotEqual(saved.chordEvent(id: chordID)?.manualHorizontalScale,
                original.chordEvent(id: chordID)?.manualHorizontalScale)
        } else {
            XCTAssertEqual(saved.measure(id: measureID)?.chordEvents,
                original.measure(id: measureID)?.chordEvents)
        }
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(saved))
        XCTAssertEqual(reopened, saved)
    }

    private func dispatch(_ pan: UIPanGestureRecognizer, operation: Operation,
                          canvas: LeadSheetCanvasUIKitView) {
        if operation == .measureResize {
            let selector = NSSelectorFromString("handleMeasureResizePan:")
            XCTAssertTrue(canvas.responds(to: selector))
            canvas.perform(selector, with: pan)
        } else {
            canvas.handleRenderedObjectMovePan(pan)
        }
    }

    private func record(_ samples: [Double], operation: Operation, chart: Chart,
                        backingInvalidationSamples: Int, counters: [String: Int]) throws {
        let ordered = samples.sorted()
        let report: [String: Any] = [
            "operation": operation.rawValue,
            "layoutStyle": chart.layoutStyle.rawValue,
            "measureCount": chart.measures.count,
            "chordCount": chart.measures.flatMap(\.chordEvents).count,
            "sampleCount": samples.count,
            "backingInvalidationSamples": backingInvalidationSamples,
            "previewCounters": counters,
            "p50Milliseconds": ordered[ordered.count / 2],
            "p95Milliseconds": ordered[Int(Double(ordered.count - 1) * 0.95)],
            "maximumMilliseconds": ordered.last!,
            "totalMilliseconds": samples.reduce(0, +)
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("paper_interaction_diagnostic \(String(decoding: data, as: UTF8.self))")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "paper-interaction-\(operation.rawValue)-\(chart.layoutStyle.rawValue)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func populatedChart(_ style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Paper interaction diagnostic", measureCount: 32, layoutStyle: style)
        chart.hasCompletedInitialSetup = true
        let source = drawing(at: CGPoint(x: 10, y: 10)).dataRepresentation()
        let symbols = try ["Cmaj7", "Bbmaj7", "D7", "G7"].map(ChordSymbolParser.parse)
        var rows = [[UUID: ClosedRange<Double>]]()
        let ids = chart.measures.map(\.id)
        for row in 0..<8 {
            var spans = [UUID: ClosedRange<Double>]()
            for column in 0..<4 {
                let id = ids[row * 4 + column]
                spans[id] = (Double(column) / 4)...(Double(column + 1) / 4)
            }
            rows.append(spans)
        }
        for system in chart.systems.indices {
            for measure in chart.systems[system].measures.indices {
                let index = try XCTUnwrap(ids.firstIndex(of: chart.systems[system].measures[measure].id))
                chart.systems[system].measures[measure].authoringState = .committed
                chart.systems[system].measures[measure].chordEvents = (0..<2).map { offset in
                    ChordEvent(id: UUID(), symbol: symbols[(index + offset) % symbols.count],
                        spellingIntent: .explicit,
                        startPosition: BeatPosition(beat: offset * 2 + 1, subdivision: 0, subdivisionsPerBeat: 1),
                        duration: .half, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
                        rawInput: nil, sourceInkData: source)
                }
            }
        }
        XCTAssertTrue(chart.adoptPaperMeasureLayout(rows))
        let page = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_800))
        let space = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: page, relativeTo: LeadSheetActiveInkScope.pageWritingFrame(for: page)))
        let archives = (space.chordAnchors ?? []).map { anchor in
            drawing(at: CGPoint(x: anchor.frame.rect.midX, y: anchor.frame.rect.maxY + 8))
        }
        chart.pageHandwrittenNotationData = PKDrawing(strokes: archives.flatMap(\.strokes)).dataRepresentation()
        chart.pageHandwrittenNotationCoordinateSpace = space
        return chart
    }

    private func drawing(at point: CGPoint) -> PKDrawing {
        let path = PKStrokePath(controlPoints: [point, CGPoint(x: point.x + 6, y: point.y + 3)]
            .enumerated().map { index, location in
                PKStrokePoint(location: location, timeOffset: Double(index) * 0.02,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1,
                    azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 20))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: path, transform: .identity, mask: nil, randomSeed: 21)])
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
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 900, height: 1_800),
            chordInkRecognizer: ChordInkMaximumTrustRecognizer(), inputEnvironment: .simulator)
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
        canvas.layoutIfNeeded()
        return Host(canvas: canvas, window: window, previousWindow: previous)
    }
}

@MainActor
private final class PaperPerformancePan: UIPanGestureRecognizer {
    var point: CGPoint
    var movement: CGPoint = .zero
    var simulatedState: UIGestureRecognizer.State
    let coordinateView: UIView
    init(point: CGPoint, state: UIGestureRecognizer.State, coordinateView: UIView) {
        self.point = point
        simulatedState = state
        self.coordinateView = coordinateView
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { coordinateView.convert(point, to: view) }
    override func translation(in view: UIView?) -> CGPoint { movement }
}
#endif
