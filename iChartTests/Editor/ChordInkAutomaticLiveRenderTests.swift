#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Exercises the resident PencilKit owner, including its mode and input clock.
/// Recognition decisions are constructed here; this is not an accuracy test.
@MainActor
final class ChordInkAutomaticLiveRenderTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)

    func testActiveToolRejectsAutomaticConsumptionUntilFreshPenUp() async throws {
        let host = try makeHost(chart())
        defer { host.window.isHidden = true }
        installDrawing(on: host)
        let state = state(host.view.chart, drawing: host.canvas.drawing)
        let original = host.canvas.drawing.dataRepresentation()
        installCensus(state, on: host)
        host.view.canvasViewDidBeginUsingTool(host.canvas)
        let downAt = try XCTUnwrap(host.coordinator.lastInputAt)

        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: downAt.addingTimeInterval(2), lastInputAt: downAt))
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), original)
        XCTAssertTrue(host.view.chart.measures.allSatisfy(\.chordEvents.isEmpty))

        host.view.canvasViewDidEndUsingTool(host.canvas)
        let upAt = try XCTUnwrap(host.coordinator.lastInputAt)
        installCensus(state, on: host)
        let outcome = try XCTUnwrap(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: upAt.addingTimeInterval(2), lastInputAt: upAt))
        XCTAssertEqual(outcome.result.renderedChordCount, 2)
        XCTAssertTrue(host.canvas.drawing.strokes.isEmpty)
    }

    func testChangingWorkflowDisarmsOldDeadlineAndFreshInputCanRender() async throws {
        let host = try makeHost(chart())
        defer { host.window.isHidden = true }
        installDrawing(on: host)
        let state = state(host.view.chart, drawing: host.canvas.drawing)
        host.coordinator.lastInputAt = inputAt
        let original = host.canvas.drawing.dataRepresentation()

        host.view.manualRenderWithPreview = true
        XCTAssertNil(host.coordinator.lastInputAt)
        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: inputAt.addingTimeInterval(2), lastInputAt: inputAt))
        host.view.manualRenderWithPreview = false
        XCTAssertNil(host.coordinator.lastInputAt)
        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: inputAt.addingTimeInterval(2), lastInputAt: inputAt))
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), original)

        host.view.canvasViewDidBeginUsingTool(host.canvas)
        host.view.canvasViewDidEndUsingTool(host.canvas)
        let freshInputAt = try XCTUnwrap(host.coordinator.lastInputAt)
        installCensus(state, on: host)
        let outcome = try XCTUnwrap(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: freshInputAt.addingTimeInterval(2), lastInputAt: freshInputAt))
        XCTAssertEqual(outcome.result.renderedChordCount, 2)
        XCTAssertTrue(host.canvas.drawing.strokes.isEmpty)
    }

    func testRestoredInkWithoutNewInputNeverAuthorizesAutomaticConsumption() async throws {
        var savedChart = chart()
        _ = savedChart.setPageHandwrittenChordDrawing(drawing().dataRepresentation(),
            coordinateSpace: PersistentInkCoordinateSpace(size: pageSize))
        let host = try makeHost(savedChart)
        defer { host.window.isHidden = true }
        XCTAssertFalse(host.canvas.drawing.strokes.isEmpty)
        let state = state(host.view.chart, drawing: host.canvas.drawing)
        let original = host.canvas.drawing.dataRepresentation()
        XCTAssertNil(host.coordinator.lastInputAt)
        installCensus(state, on: host)

        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: inputAt.addingTimeInterval(2), lastInputAt: nil))
        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: inputAt.addingTimeInterval(2), lastInputAt: inputAt))
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), original)
        XCTAssertEqual(host.view.chart, savedChart)
    }

    func testSelectiveLiveConsumptionPreservesUnresolvedInkAndRejectsRepeatedOldCallback() async throws {
        let host = try makeHost(chart())
        defer { host.window.isHidden = true }
        installDrawing(on: host)
        var state = state(host.view.chart, drawing: host.canvas.drawing)
        makeCollecting(&state.draftChords[1])
        let expectedRemaining = PKDrawing(strokes: [host.canvas.drawing.strokes[1]])
        host.coordinator.lastInputAt = inputAt
        installCensus(state, on: host)

        let outcome = try XCTUnwrap(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: inputAt.addingTimeInterval(2), lastInputAt: inputAt))

        XCTAssertEqual(outcome.result.renderedChordCount, 1)
        XCTAssertEqual(host.view.chart.measures.flatMap(\.chordEvents).count, 1)
        XCTAssertEqual(host.view.chordPreviewState.draftChords.map(\.id), [state.draftChords[1].id])
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedRemaining, current: host.canvas.drawing))
        let stored = try PKDrawing(data: XCTUnwrap(host.view.chart.pageHandwrittenChordData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedRemaining, current: stored))
        let consumedChart = host.view.chart
        let remainingBytes = host.canvas.drawing.dataRepresentation()
        XCTAssertFalse(host.view.hasCurrentAutomaticChordCensus,
            "Consumption advances the source revision and requires a new census")
        installCensus(outcome.remainingState, on: host)

        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: consumedChart,
            state: state, now: inputAt.addingTimeInterval(3), lastInputAt: inputAt))
        XCTAssertEqual(host.view.chart, consumedChart)
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), remainingBytes)
        XCTAssertEqual(host.view.chart.measures.flatMap(\.chordEvents).count, 1)
    }

    func testMissingAndStaleCensusRefuseBothSpatialAndIdleCompletion() async throws {
        let host = try makeHost(chart())
        defer { host.window.isHidden = true }
        installDrawing(on: host)
        let firstState = state(host.view.chart, drawing: host.canvas.drawing)
        host.coordinator.lastInputAt = inputAt
        XCTAssertFalse(host.view.hasCurrentAutomaticChordCensus)
        for delay in [0.05, 2.0] {
            XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
                state: firstState, now: inputAt.addingTimeInterval(delay), lastInputAt: inputAt))
        }
        installCensus(firstState, on: host)
        let previousRevision = host.view.automaticChordInputRevision
        XCTAssertTrue(host.view.hasCurrentAutomaticChordCensus)

        host.canvas.drawing = PKDrawing(strokes: host.canvas.drawing.strokes + [stroke(210)])
        host.view.canvasViewDrawingDidChange(host.canvas)
        let changedState = state(host.view.chart, drawing: host.canvas.drawing)
        host.coordinator.lastInputAt = inputAt
        XCTAssertNotEqual(host.view.automaticChordInputRevision, previousRevision)
        XCTAssertFalse(host.view.hasCurrentAutomaticChordCensus)
        let sourceBytes = host.canvas.drawing.dataRepresentation()
        for delay in [0.05, 2.0] {
            XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
                state: changedState, now: inputAt.addingTimeInterval(delay), lastInputAt: inputAt))
        }
        XCTAssertFalse(host.view.installAutomaticChordCensus(requests(for: changedState),
            forInkRevision: previousRevision))
        XCTAssertFalse(host.view.hasCurrentAutomaticChordCensus)
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), sourceBytes)
        XCTAssertTrue(host.view.chart.measures.allSatisfy(\.chordEvents.isEmpty))

        installCensus(changedState, on: host)
        let complete = try XCTUnwrap(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: changedState, now: inputAt.addingTimeInterval(2), lastInputAt: inputAt))
        XCTAssertEqual(complete.result.renderedChordCount, 3)
        XCTAssertTrue(host.canvas.drawing.strokes.isEmpty)
    }

    func testCurrentCensusLetsTrustedFRenderImmediatelyWhileGIsStillCollecting() async throws {
        let host = try makeHost(chart())
        defer { host.window.isHidden = true }
        installDrawing(on: host)
        var state = state(host.view.chart, drawing: host.canvas.drawing, texts: ["F", "G"])
        makeCollecting(&state.draftChords[1])
        let expectedG = PKDrawing(strokes: [host.canvas.drawing.strokes[1]])
        host.coordinator.lastInputAt = inputAt
        installCensus(state, on: host)

        let outcome = try XCTUnwrap(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: state, now: inputAt.addingTimeInterval(0.05), lastInputAt: inputAt))

        XCTAssertEqual(outcome.result.renderedChordCount, 1)
        XCTAssertEqual(host.view.chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["F"])
        XCTAssertEqual(outcome.remainingState.draftChords.count, 1)
        XCTAssertEqual(outcome.remainingState.draftChords[0].targetLifecycle?.stage, .collecting)
        XCTAssertFalse(outcome.remainingState.draftChords[0].requiresManualReviewOnly)
        XCTAssertNil(outcome.remainingState.draftChords[0].previewText)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedG, current: host.canvas.drawing))
        let storedG = try PKDrawing(data: XCTUnwrap(host.view.chart.pageHandwrittenChordData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expectedG, current: storedG))

        // An old F callback stays inert even after the remaining G census has
        // been installed; exact coverage cannot claim already consumed F.
        installCensus(outcome.remainingState, on: host)
        let currentChart = host.view.chart
        XCTAssertNil(host.view.renderChordDraftAutomatically(chart: currentChart,
            state: state, now: inputAt.addingTimeInterval(2), lastInputAt: inputAt))
        XCTAssertEqual(host.view.chart, currentChart)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedG, current: host.canvas.drawing))
    }

    func testOldFCompletionCannotConsumeWhileNewGSourceAwaitsCurrentCensus() async throws {
        let host = try makeHost(chart())
        defer { host.window.isHidden = true }
        installDrawing(on: host)
        var before = state(host.view.chart, drawing: host.canvas.drawing, texts: ["F", "G"])
        makeCollecting(&before.draftChords[1])
        installCensus(before, on: host)

        host.canvas.drawing = PKDrawing(strokes: host.canvas.drawing.strokes + [stroke(140)])
        host.view.canvasViewDrawingDidChange(host.canvas)
        var latest = state(host.view.chart, drawing: host.canvas.drawing, texts: ["F", "G", "G"])
        latest.draftChords[0] = before.draftChords[0]
        makeCollecting(&latest.draftChords[1])
        makeCollecting(&latest.draftChords[2])
        host.coordinator.lastInputAt = inputAt
        XCTAssertFalse(host.view.hasCurrentAutomaticChordCensus)
        let original = host.canvas.drawing.dataRepresentation()
        // Model a completed F result alongside current collecting ownership.
        // Even complete source coverage cannot authorize a pending census.
        for delay in [0.05, 2.0] {
            XCTAssertNil(host.view.renderChordDraftAutomatically(chart: host.view.chart,
                state: latest, now: inputAt.addingTimeInterval(delay), lastInputAt: inputAt))
        }
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), original)

        installCensus(latest, on: host)
        let outcome = try XCTUnwrap(host.view.renderChordDraftAutomatically(chart: host.view.chart,
            state: latest, now: inputAt.addingTimeInterval(0.05), lastInputAt: inputAt))
        XCTAssertEqual(outcome.result.renderedChordCount, 1)
        XCTAssertEqual(host.view.chart.measures.flatMap(\.chordEvents).map(\.rawInput), ["F"])
        XCTAssertEqual(host.canvas.drawing.strokes.count, 2)
        XCTAssertEqual(outcome.remainingState.draftChords.count, 2)
    }

    func testSyntheticWritingAndSelectiveRenderingStayIndependentOfOptionalDiagnosticsAndPendingTransport() async throws {
        let telemetry = try await makeAutomaticTelemetryFixture()
        defer { telemetry.cleanup() }
        let requestStarted = expectation(forNotification: .init("AutomaticLiveRenderTelemetryRequestStarted"),
            object: nil)
        // The URL protocol intentionally keeps this optional upload pending.
        // Canvas work must finish without waiting for its response.
        let upload = Task {
            await telemetry.service.record("app.error", properties: ["error_code": .string("synthetic_test")])
            await telemetry.service.flush()
        }
        defer { upload.cancel() }
        await fulfillment(of: [requestStarted], timeout: 3)

        var windows: [UIWindow] = []
        defer { windows.forEach { $0.isHidden = true } }
        for diagnosticsEnabled in [true, false] {
            if !diagnosticsEnabled {
                telemetry.consent.setConsentGranted(false)
                await telemetry.service.consentDidChange()
            }
            for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
                let automatic = try makeHost(chart(style), recognizer: AutomaticLiveRenderNoReadRecognizer())
                windows.append(automatic.window)
                automatic.view.canvasViewDidBeginUsingTool(automatic.canvas)
                installDrawing(on: automatic)
                automatic.view.canvasViewDidEndUsingTool(automatic.canvas)
                let source = automatic.canvas.drawing
                var partialState = state(automatic.view.chart, drawing: source)
                makeCollecting(&partialState.draftChords[1])
                automatic.coordinator.lastInputAt = inputAt
                installCensus(partialState, on: automatic)
                let startedAt = ProcessInfo.processInfo.systemUptime
                let partial = try XCTUnwrap(automatic.view.renderChordDraftAutomatically(
                    chart: automatic.view.chart, state: partialState,
                    now: inputAt.addingTimeInterval(0.05), lastInputAt: inputAt))
                XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, 1,
                    "Optional diagnostics must not hold up source validation and consumption")
                XCTAssertEqual(partial.result.renderedChordCount, 1)
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: PKDrawing(strokes: [source.strokes[1]]), current: automatic.canvas.drawing))
                let committed = try XCTUnwrap(automatic.view.chart.measures.flatMap(\.chordEvents).first)
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: PKDrawing(strokes: [source.strokes[0]]),
                    current: try PKDrawing(data: XCTUnwrap(committed.sourceInkData))))

                let reviewed = try makeHost(chart(style), recognizer: AutomaticLiveRenderNoReadRecognizer())
                windows.append(reviewed.window)
                installDrawing(on: reviewed)
                let reviewedSource = reviewed.canvas.drawing
                let reviewedState = state(reviewed.view.chart, drawing: reviewedSource)
                installCensus(reviewedState, on: reviewed)
                let outcome = try XCTUnwrap(reviewed.view.attemptReviewedChordDraftAutomatically(
                    chart: reviewed.view.chart, state: reviewedState).outcome)
                XCTAssertEqual(outcome.result.renderedChordCount, 2)
                XCTAssertTrue(reviewed.canvas.drawing.strokes.isEmpty)
                let archives = try reviewed.view.chart.measures.flatMap(\.chordEvents).flatMap {
                    try PKDrawing(data: XCTUnwrap($0.sourceInkData)).strokes
                }
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: reviewedSource, current: PKDrawing(strokes: archives)))

                let refused = try makeHost(chart(style), recognizer: AutomaticLiveRenderNoReadRecognizer())
                windows.append(refused.window)
                installDrawing(on: refused)
                var unfinished = state(refused.view.chart, drawing: refused.canvas.drawing)
                for index in unfinished.draftChords.indices { makeCollecting(&unfinished.draftChords[index]) }
                installCensus(unfinished, on: refused)
                let unchangedChart = refused.view.chart
                let unchangedDrawing = refused.canvas.drawing
                XCTAssertNil(refused.view.attemptChordDraftAutomatically(chart: unchangedChart,
                    state: unfinished, now: inputAt.addingTimeInterval(2), lastInputAt: inputAt).outcome)
                XCTAssertEqual(refused.view.chart, unchangedChart)
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: unchangedDrawing, current: refused.canvas.drawing))

                // A pending same-ID model update is not part of a refused canvas
                // transaction. Keep the resident model and its source untouched.
                var incomingChart = unchangedChart
                incomingChart.title = "Unapplied incoming title update"
                XCTAssertEqual(incomingChart.id, unchangedChart.id)
                XCTAssertNotEqual(incomingChart, unchangedChart)
                let sourceBytes = refused.canvas.drawing.dataRepresentation()
                XCTAssertNil(refused.view.attemptChordDraftAutomatically(chart: incomingChart,
                    state: unfinished, now: inputAt.addingTimeInterval(2), lastInputAt: inputAt).outcome)
                XCTAssertEqual(refused.view.chart, unchangedChart)
                XCTAssertEqual(refused.view.chart.pageHandwrittenChordData, unchangedChart.pageHandwrittenChordData)
                XCTAssertEqual(refused.canvas.drawing.dataRepresentation(), sourceBytes)
            }
        }
        await Task.yield()
        XCTAssertFalse(try telemetry.queue.loadEvents().contains { $0.eventName == "feature.contract_checked" })
    }

    private struct AutomaticTelemetryFixture {
        let suiteName: String
        let preferences: UserDefaults
        let directory: URL
        let consent: IChartTelemetryConsentStore
        let queue: IChartTelemetryQueueStore
        let session: URLSession
        let service: IChartTelemetryService

        @MainActor
        func cleanup() {
            IChartTelemetry.configure(nil)
            consent.setConsentGranted(false)
            session.invalidateAndCancel()
            preferences.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeAutomaticTelemetryFixture() async throws -> AutomaticTelemetryFixture {
        let suiteName = "iChart-automatic-completion-telemetry-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        // Model an already-consented installation. This test exercises an
        // actual pending upload, not first-grant preference projection or
        // first-event identity creation, which may legitimately drop an event.
        preferences.set(IChartTelemetryConsentStore.currentVersion,
            forKey: IChartTelemetryConsentStore.preferenceKey)
        preferences.set(UUID().uuidString,
            forKey: IChartTelemetryConsentStore.installationIDPreferenceKey)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automatic-completion-telemetry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let consent = IChartTelemetryConsentStore(defaults: preferences)
        await consent.waitForPendingPersistence()
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("queue.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutomaticLiveRenderTelemetryPendingProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = IChartTelemetryService(endpointURL: URL(string: "https://telemetry.invalid/automatic-completion-test")!,
            publishableKey: "synthetic-client-key", sessionStore: nil, queueStore: queue,
            consentStore: consent, urlSession: session)
        await service.initialize()
        await consent.waitForPendingPersistence()
        XCTAssertTrue(consent.snapshot.isGranted)
        IChartTelemetry.configure(service)
        return AutomaticTelemetryFixture(suiteName: suiteName, preferences: preferences, directory: directory,
            consent: consent, queue: queue, session: session, service: service)
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let window: UIWindow
        let coordinator: ChordInkDraftRenderCoordinator
    }

    private func makeHost(_ chart: Chart, recognizer: (any ChordInkRecognizing)? = nil) throws -> Host {
        let view: LeadSheetCanvasUIKitView
        if let recognizer {
            view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize),
                chordInkRecognizer: recognizer, automaticFallbackRecognizers: [])
        } else {
            view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        }
        view.recognizesChordInk = true
        view.chart = chart
        view.interactionMode = .chordEntry
        view.manualRenderWithPreview = false
        let coordinator = ChordInkDraftRenderCoordinator()
        view.chordDraftRenderCoordinator = coordinator
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: CGRect(origin: .zero, size: pageSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let canvas = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        XCTAssertFalse(canvas.isHidden)
        XCTAssertTrue(canvas.isUserInteractionEnabled)
        XCTAssertGreaterThan(canvas.bounds.width, 0)
        return Host(view: view, canvas: canvas, window: window, coordinator: coordinator)
    }

    private func installDrawing(on host: Host) {
        host.canvas.drawing = drawing()
        host.view.canvasViewDrawingDidChange(host.canvas)
    }

    private func installCensus(_ state: ChordPreviewState, on host: Host) {
        XCTAssertTrue(host.view.installAutomaticChordCensus(requests(for: state),
            forInkRevision: host.view.automaticChordInputRevision))
        XCTAssertTrue(host.view.hasCurrentAutomaticChordCensus)
    }

    private func requests(for state: ChordPreviewState) -> [ChordInkRecognitionSessionRequest] {
        let requestID = UUID()
        return state.draftChords.map { draft in
            ChordInkRecognitionSessionRequest(requestID: requestID, scheduledAt: inputAt,
                requestedDelay: 0, strokes: draft.targetLifecycle?.ownership.preparedStrokes ?? [],
                drawingData: draft.drawingData,
                target: (draft.measureID, draft.targetFraction ?? 0),
                visualOrder: draft.visualOrder, laneLocation: draft.laneLocation,
                layoutPageSize: draft.layoutPageSize, options: .live,
                requiresManualReviewOnly: draft.requiresManualReviewOnly)
        }
    }

    private func makeCollecting(_ draft: inout ChordInkDraft) {
        draft.bestCandidateText = nil
        draft.selectedText = nil
        draft.candidateTexts = []
        draft.confidence = 0
        draft.recognitionResult = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [],
            match: nil, confidence: 0)
        draft.recognitionDecision = ChordInkRecognitionDecision(action: .confirm, acceptedText: nil,
            reason: "Collecting test target", isCloseRace: false,
            competingCandidateText: nil, confidenceGap: nil)
        draft.primaryDecision = draft.recognitionDecision
        draft.targetLifecycle?.stage = .collecting
        draft.requiresManualReviewOnly = false
    }

    private func chart(_ style: ChartLayoutStyle = .simpleChordSheet) -> Chart {
        var chart = Chart.draft(title: "Automatic live render", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func state(_ chart: Chart, drawing: PKDrawing, texts: [String]? = nil) -> ChordPreviewState {
        let normalized = LeadSheetPersistentInkColorPolicy.normalizedDrawing(drawing)
        let drafts = normalized.strokes.enumerated().map { index, stroke in
            let text = texts?[index] ?? "C"
            var input = ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: Double(index + 1) / Double(normalized.strokes.count + 1), layoutPageSize: pageSize,
                drawingData: PKDrawing(strokes: [stroke]).dataRepresentation(), candidateTexts: [text],
                bestCandidateText: text, confidence: 4.5, strokeCount: 1,
                recognitionDecision: ChordInkRecognitionDecision(action: .trusted, acceptedText: text,
                    reason: "Trusted integration-test read", isCloseRace: false,
                    competingCandidateText: nil, confidenceGap: nil))
            input.targetLifecycle = ChordInkRecognitionTargetLifecycle(generationID: UUID(), anchor: input.anchor,
                ownership: ChordInkRecognitionTargetOwnership(
                    preparedStrokes: PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: [stroke]))), stage: .frozen)
            return ChordInkDraft(input: input)
        }
        return ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
    }

    private func drawing() -> PKDrawing {
        LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: [stroke(10), stroke(110)]))
    }

    private func stroke(_ x: CGFloat) -> PKStroke {
        let points = [CGPoint(x: x, y: 10), CGPoint(x: x + 14, y: 30)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: inputAt),
            transform: .identity, mask: nil, randomSeed: 17)
    }
}

private struct AutomaticLiveRenderNoReadRecognizer: ChordInkRecognizing {
    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        .init(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
    }
}

private final class AutomaticLiveRenderTelemetryPendingProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        NotificationCenter.default.post(name: .init("AutomaticLiveRenderTelemetryRequestStarted"), object: nil)
    }
    override func stopLoading() {}
}
#endif
