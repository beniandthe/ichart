#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkAutomaticReadinessTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_200)

    func testFreshRestoredCensusArmsReadinessOnceWithoutInventingPencilInput() throws {
        let host = try makeHost()
        defer { cleanup(host) }
        XCTAssertNil(host.coordinator.lastInputAt)
        XCTAssertNil(host.coordinator.renderSessionReadyAt)
        XCTAssertNil(host.coordinator.automaticRenderReferenceAt)
        let request = try request(for: host)
        let before = Date()
        XCTAssertTrue(host.view.installAutomaticChordCensus([request],
            forInkRevision: host.view.automaticChordInputRevision))
        let ready = try XCTUnwrap(host.coordinator.renderSessionReadyAt)
        XCTAssertGreaterThanOrEqual(ready, before)
        XCTAssertLessThanOrEqual(ready, Date())
        XCTAssertNil(host.coordinator.lastInputAt)
        XCTAssertEqual(host.coordinator.automaticRenderReferenceAt, ready)
        XCTAssertTrue(host.view.hasCurrentAutomaticChordCensus)

        var repeated = request
        repeated.requestID = UUID()
        repeated.scheduledAt = Date()
        XCTAssertTrue(host.view.installAutomaticChordCensus([repeated],
            forInkRevision: host.view.automaticChordInputRevision))
        XCTAssertTrue(host.view.replayCurrentAutomaticChordCensus())
        XCTAssertEqual(host.coordinator.renderSessionReadyAt, ready,
            "An unchanged census or replay cannot keep postponing the automatic deadline")
        XCTAssertNil(host.coordinator.lastInputAt)
        XCTAssertEqual(host.coordinator.automaticRenderReferenceAt, ready)
    }

    func testCachedTrustedPreviewWithoutCurrentCensusCannotAuthorizeRestoredInkConsumption() throws {
        let host = try makeHost()
        defer { cleanup(host) }
        let cached = trustedState(try request(for: host), chart: host.view.chart)
        host.view.chordPreviewState = cached
        let originalInk = host.canvas.drawing.dataRepresentation()
        let originalChart = host.view.chart
        XCTAssertFalse(host.view.hasCurrentAutomaticChordCensus)
        XCTAssertNil(host.coordinator.automaticRenderReferenceAt)

        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart, state: cached,
            now: Date().addingTimeInterval(10), lastInputAt: nil))
        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart, state: cached,
            now: Date().addingTimeInterval(10), lastInputAt: Date()))
        XCTAssertNil(host.coordinator.lastInputAt)
        XCTAssertNil(host.coordinator.renderSessionReadyAt)
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), originalInk)
        XCTAssertEqual(host.view.chart, originalChart)
    }

    func testChangedSourceInvalidatesReadinessAndRejectsThePriorCensusRevision() throws {
        let host = try makeHost()
        defer { cleanup(host) }
        let oldRequest = try request(for: host)
        let oldRevision = host.view.automaticChordInputRevision
        XCTAssertTrue(host.view.installAutomaticChordCensus([oldRequest], forInkRevision: oldRevision))
        XCTAssertNotNil(host.coordinator.renderSessionReadyAt)

        host.canvas.drawing = PKDrawing(strokes: host.canvas.drawing.strokes + sourceDrawing(xOffset: 200).strokes)
        host.view.canvasViewDrawingDidChange(host.canvas)
        XCTAssertNotEqual(host.view.automaticChordInputRevision, oldRevision)
        XCTAssertNil(host.coordinator.renderSessionReadyAt)
        XCTAssertNotNil(host.coordinator.lastInputAt)
        XCTAssertEqual(host.coordinator.automaticRenderReferenceAt, host.coordinator.lastInputAt)
        XCTAssertFalse(host.view.hasCurrentAutomaticChordCensus)
        XCTAssertFalse(host.view.installAutomaticChordCensus([oldRequest], forInkRevision: oldRevision))
        XCTAssertNil(host.coordinator.renderSessionReadyAt)
    }

    func testModeWorkflowAndChartChangesInvalidateRestoredReadiness() throws {
        for change in ["mode", "workflow", "chart"] {
            let host = try makeHost()
            defer { cleanup(host) }
            XCTAssertTrue(host.view.installAutomaticChordCensus([try request(for: host)],
                forInkRevision: host.view.automaticChordInputRevision))
            XCTAssertNotNil(host.coordinator.renderSessionReadyAt)
            switch change {
            case "mode": host.view.interactionMode = .headerEntry
            case "workflow": host.view.manualRenderWithPreview = true
            default: host.view.chart = restoredChart()
            }
            XCTAssertNil(host.coordinator.renderSessionReadyAt, change)
            XCTAssertNil(host.coordinator.lastInputAt, change)
            XCTAssertNil(host.coordinator.automaticRenderReferenceAt, change)
            XCTAssertFalse(host.view.hasCurrentAutomaticChordCensus, change)
        }
    }

    func testPencilBeginDisarmsReadinessAndActiveToolCannotConsumeItsSource() throws {
        let host = try makeHost()
        defer { cleanup(host) }
        let currentRequest = try request(for: host)
        XCTAssertTrue(host.view.installAutomaticChordCensus([currentRequest],
            forInkRevision: host.view.automaticChordInputRevision))
        XCTAssertNotNil(host.coordinator.renderSessionReadyAt)
        let state = trustedState(currentRequest, chart: host.view.chart)
        let originalInk = host.canvas.drawing.dataRepresentation()

        host.view.canvasViewDidBeginUsingTool(host.canvas)
        XCTAssertNil(host.coordinator.renderSessionReadyAt)
        let actualInputAt = try XCTUnwrap(host.coordinator.lastInputAt)
        XCTAssertEqual(host.coordinator.automaticRenderReferenceAt, actualInputAt)
        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart, state: state,
            now: actualInputAt.addingTimeInterval(10), lastInputAt: actualInputAt))
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), originalInk)
        XCTAssertTrue(host.view.chart.measures.allSatisfy(\.chordEvents.isEmpty))
    }

    func testActualFreshPreparationAndReadRenderRestoredInkUsingReadinessRatherThanPencilTime() async throws {
        let host = try makeHost()
        defer { cleanup(host) }
        let rendered = expectation(description: "Fresh restored read reaches the real chart")
        var didRender = false
        host.view.onChordInkDraftPreviewChanged = { payloads in
            XCTAssertNil(host.coordinator.lastInputAt,
                "Preparing and reading saved ink must not fabricate a Pencil callback")
            guard !didRender, let payload = payloads.first,
                  ChordInkRecognitionPolicy.decision(for: payload.result).action == .trusted,
                  let ready = host.coordinator.renderSessionReadyAt else { return }
            XCTAssertTrue(host.view.hasCurrentAutomaticChordCensus)
            XCTAssertEqual(host.coordinator.automaticRenderReferenceAt, ready)
            let currentState = self.state(from: payload, chart: host.view.chart)
            host.view.chordPreviewState = currentState
            guard let outcome = host.view.renderChordDraftAutomatically(chart: host.view.chart,
                state: currentState, now: ready.addingTimeInterval(2), lastInputAt: nil) else { return }
            didRender = true
            XCTAssertEqual(outcome.result.renderedChordCount, 1)
            rendered.fulfill()
        }
        // Enabling recognition schedules the production current-source census;
        // this test never installs ownership or reports a Pencil event itself.
        host.view.recognizesChordInk = false
        host.view.recognizesChordInk = true
        await fulfillment(of: [rendered], timeout: 5)
        XCTAssertTrue(didRender)
        XCTAssertNil(host.coordinator.lastInputAt)
        XCTAssertEqual(host.view.chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["F"])
        XCTAssertTrue(host.canvas.drawing.strokes.isEmpty)
        XCTAssertNil(host.view.chart.pageHandwrittenChordData)
    }

    func testManualReviewWaitsForCurrentReaderAndInvalidatesWhenWritingChanges() async throws {
        let readStarted = expectation(description: "Manual recognition starts on the reader worker")
        let previewReady = expectation(description: "The current manual preview can resume a pending review action")
        let recognizer = DelayedReadinessPrimaryRecognizer(readStarted: readStarted)
        let host = try makeHost(manual: true, recognizer: recognizer)
        defer {
            cleanup(host)
            recognizer.releaseFirstRead()
        }
        let original = host.canvas.drawing
        var delivered: [ChordInkRecognitionProposalPayload] = []
        host.view.onChordInkDraftPreviewChanged = { payloads in
            guard delivered.isEmpty, let payload = payloads.first else { return }
            delivered = payloads
            host.view.chordPreviewState = self.state(from: payload, chart: host.view.chart)
        }
        var ready = false
        host.view.onManualChordPreviewReady = {
            XCTAssertFalse(delivered.isEmpty, "Publish the preview before waking a pending review action")
            XCTAssertTrue(host.view.prepareManualPreviewForReview())
            ready = true
            previewReady.fulfill()
        }

        XCTAssertTrue(host.view.recognizesChordInk)
        XCTAssertFalse(host.view.prepareManualPreviewForReview(), "Restored ink needs a current preview before review")
        await fulfillment(of: [readStarted], timeout: 5)
        XCTAssertFalse(host.view.prepareManualPreviewForReview(), "Review must wait while recognition is in flight")
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertFalse(ready)
        let pendingSource = try XCTUnwrap(host.view.currentManualPreviewDrawing())
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: original, current: pendingSource))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: original, current: host.canvas.drawing))

        recognizer.releaseFirstRead()
        await fulfillment(of: [previewReady], timeout: 5)
        let current = try XCTUnwrap(delivered.first)
        XCTAssertEqual(current.result.match?.displayText, "F")
        XCTAssertEqual(delivered.count, 1)
        let represented = try PKDrawing(data: current.drawingData)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: pendingSource, current: represented))
        XCTAssertTrue(host.view.prepareManualPreviewForReview())

        host.view.onManualChordPreviewReady = nil
        let oldRevision = host.view.automaticChordInputRevision
        let changed = PKDrawing(strokes: original.strokes + sourceDrawing(xOffset: 200).strokes)
        host.canvas.drawing = changed
        host.view.canvasViewDrawingDidChange(host.canvas)
        XCTAssertNotEqual(host.view.automaticChordInputRevision, oldRevision)
        XCTAssertFalse(host.view.prepareManualPreviewForReview(), "The old read must not authorize review after a stroke is added")
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: changed, current: host.canvas.drawing))
        XCTAssertTrue(host.view.chart.measures.allSatisfy(\.chordEvents.isEmpty))
    }

    func testManualPreviewReadyCannotResumeAnActionBoundToChangedInk() async throws {
        let oldReadStarted = expectation(description: "The original manual read is still in flight")
        let latestPreviewReady = expectation(description: "Only the replacement drawing becomes ready")
        let recognizer = DelayedReadinessPrimaryRecognizer(readStarted: oldReadStarted)
        let host = try makeHost(manual: true, recognizer: recognizer)
        defer {
            cleanup(host)
            recognizer.releaseFirstRead()
        }
        var delivered: [ChordInkRecognitionProposalPayload] = []
        host.view.onChordInkDraftPreviewChanged = { payloads in
            guard let payload = payloads.first else { return }
            delivered = payloads
            host.view.chordPreviewState = self.state(from: payload, chart: host.view.chart)
        }
        XCTAssertFalse(host.view.prepareManualPreviewForReview())
        await fulfillment(of: [oldReadStarted], timeout: 5)
        let pendingSource = try XCTUnwrap(host.view.currentManualPreviewDrawing())
        let oldRevision = host.view.automaticChordInputRevision
        let replacement = sourceDrawing(xOffset: 12)
        host.view.onManualChordPreviewReady = {
            guard let currentSource = host.view.currentManualPreviewDrawing(),
                  let payload = delivered.first,
                  let previewSource = try? PKDrawing(data: payload.drawingData) else {
                XCTFail("A ready preview must publish its current source first")
                latestPreviewReady.fulfill()
                return
            }
            XCTAssertTrue(host.view.prepareManualPreviewForReview())
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: pendingSource, current: currentSource))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: replacement, current: currentSource))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: replacement, current: previewSource))
            latestPreviewReady.fulfill()
        }

        host.view.canvasViewDidBeginUsingTool(host.canvas)
        host.canvas.drawing = replacement
        host.view.canvasViewDrawingDidChange(host.canvas)
        host.view.canvasViewDidEndUsingTool(host.canvas)
        XCTAssertNotEqual(host.view.automaticChordInputRevision, oldRevision)
        XCTAssertFalse(host.view.prepareManualPreviewForReview())
        XCTAssertTrue(delivered.isEmpty)
        recognizer.releaseFirstRead()
        await fulfillment(of: [latestPreviewReady], timeout: 5)
        XCTAssertTrue(host.view.chart.measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: replacement, current: host.canvas.drawing))
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let coordinator: ChordInkDraftRenderCoordinator
        let window: UIWindow
    }

    private func makeHost(manual: Bool = false, recognizer: any ChordInkRecognizing = ReadinessPrimaryRecognizer()) throws -> Host {
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize),
            chordInkRecognizer: recognizer, automaticFallbackRecognizers: [])
        view.recognizesChordInk = false
        let coordinator = ChordInkDraftRenderCoordinator()
        view.chordDraftRenderCoordinator = coordinator
        view.chart = restoredChart()
        view.interactionMode = .chordEntry
        view.manualRenderWithPreview = manual
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: CGRect(origin: .zero, size: pageSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let canvas = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        XCTAssertFalse(canvas.isHidden)
        XCTAssertFalse(canvas.drawing.strokes.isEmpty)
        view.recognizesChordInk = true
        return Host(view: view, canvas: canvas, coordinator: coordinator, window: window)
    }

    private func cleanup(_ host: Host) {
        host.view.onChordInkDraftPreviewChanged = nil
        host.view.onManualChordPreviewReady = nil
        host.view.onChordInkAutomaticActivityChanged = nil
        host.view.onChordInkDraftBarlinesChanged = nil
        host.view.recognizesChordInk = false
        host.window.isHidden = true
    }

    private func restoredChart() -> Chart {
        var chart = Chart.draft(title: "Restored automatic readiness", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 4)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: pageLayout)
        _ = chart.setPageHandwrittenChordDrawing(sourceDrawing().dataRepresentation(),
            coordinateSpace: PersistentInkCoordinateSpace(size: frame.size))
        return chart
    }

    private func request(for host: Host) throws -> ChordInkRecognitionSessionRequest {
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(for: host.view.chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: pageLayout)
        let source = host.canvas.drawing
        let target = try XCTUnwrap(LeadSheetChordInkRecognitionTargeting.target(for: source,
            chordFrame: frame, pageLayout: pageLayout))
        return ChordInkRecognitionSessionRequest(requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            strokes: PencilKitInkAdapter.inkStrokes(from: source), drawingData: source.dataRepresentation(),
            target: target, layoutPageSize: pageSize, options: .live)
    }

    private func trustedState(_ request: ChordInkRecognitionSessionRequest, chart: Chart) -> ChordPreviewState {
        let result = ReadinessPrimaryRecognizer.result
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        var lifecycle = request.collectingTargetLifecycle
        lifecycle.stage = .frozen
        let input = ChordInkDraftInput(measureID: request.target.measureID,
            measureIndex: chart.measure(id: request.target.measureID)?.index ?? 1,
            targetFraction: request.target.fraction, layoutPageSize: pageSize,
            drawingData: request.drawingData, candidateTexts: result.rawCandidates, bestCandidateText: "F",
            confidence: result.confidence, strokeCount: request.strokes.count, recognitionResult: result,
            primaryDecision: decision, recognitionDecision: decision, targetLifecycle: lifecycle)
        return ChordPreviewState(draftChords: [ChordInkDraft(input: input)], layoutPageSize: pageSize)
    }

    private func state(from payload: ChordInkRecognitionProposalPayload, chart: Chart) -> ChordPreviewState {
        let decision = ChordInkRecognitionPolicy.decision(for: payload.result)
        let input = ChordInkDraftInput(measureID: payload.target.measureID,
            measureIndex: chart.measure(id: payload.target.measureID)?.index ?? 1,
            targetFraction: payload.target.fraction, visualOrder: payload.visualOrder,
            laneLocation: payload.laneLocation, layoutPageSize: payload.layoutPageSize,
            drawingData: payload.drawingData, candidateTexts: payload.result.rawCandidates,
            bestCandidateText: decision.acceptedText, confidence: payload.result.confidence,
            strokeCount: payload.timing.strokeCount, recognitionResult: payload.result,
            primaryDecision: decision, recognitionDecision: decision, targetLifecycle: payload.targetLifecycle,
            requiresManualReviewOnly: payload.requiresManualReviewOnly)
        var state = ChordPreviewState()
        state.replaceDraftChords(with: [input])
        return state
    }

    private func sourceDrawing(xOffset: CGFloat = 0) -> PKDrawing {
        let locations = [CGPoint(x: 20, y: 44), CGPoint(x: 20, y: 12), CGPoint(x: 42, y: 12),
            CGPoint(x: 20, y: 12), CGPoint(x: 20, y: 27), CGPoint(x: 37, y: 27)]
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: CGPoint(x: location.x + xOffset, y: location.y),
                timeOffset: Double(index) * 0.01, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 100)),
            transform: .identity, mask: nil, randomSeed: 17)])
    }
}

private struct ReadinessPrimaryRecognizer: ChordInkRecognizing {
    static var result: ChordInkRecognitionResult {
        ChordInkRecognitionResult(rawCandidates: ["F"], glyphCandidates: [],
            match: ChordRecognitionCompendium.match("F"), confidence: 4.5,
            candidateScores: [ChordInkCandidateScore(text: "F", displayText: "F", confidence: 4.5)])
    }

    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        Self.result
    }
}

private final class DelayedReadinessPrimaryRecognizer: ChordInkRecognizing {
    private let readStarted: XCTestExpectation
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var hasStarted = false

    init(readStarted: XCTestExpectation) { self.readStarted = readStarted }

    func releaseFirstRead() { gate.signal() }

    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        let isFirst = lock.withLock {
            guard !hasStarted else { return false }
            hasStarted = true
            return true
        }
        if isFirst {
            readStarted.fulfill()
            _ = gate.wait(timeout: .now() + 5)
        }
        return ReadinessPrimaryRecognizer.result
    }
}
#endif
