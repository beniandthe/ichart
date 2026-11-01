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

    func testAutomaticAndReviewedCanvasTransactionsQueuePreservationEvidenceOnlyWithCurrentConsent() async throws {
        let suiteName = "iChart-automatic-live-telemetry-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automatic-live-telemetry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let consent = IChartTelemetryConsentStore(defaults: preferences)
        consent.setConsentGranted(true)
        let originalGrant = consent.cachedSnapshotForScheduling
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("queue.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AutomaticLiveRenderTelemetryOfflineProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = IChartTelemetryService(
            endpointURL: URL(string: "https://telemetry.invalid/automatic-render-test")!,
            publishableKey: "synthetic-client-key", sessionStore: nil, queueStore: queue,
            consentStore: consent, urlSession: session
        )
        var windows: [UIWindow] = []
        defer {
            IChartTelemetry.configure(nil)
            consent.setConsentGranted(false)
            session.invalidateAndCancel()
            windows.forEach { $0.isHidden = true }
            preferences.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        IChartTelemetry.configure(service)

        let automatic = try makeHost(chart())
        windows.append(automatic.window)
        installDrawing(on: automatic)
        let originalSource = automatic.canvas.drawing.dataRepresentation()
        var partialState = state(automatic.view.chart, drawing: automatic.canvas.drawing)
        makeCollecting(&partialState.draftChords[1])
        automatic.coordinator.lastInputAt = inputAt
        installCensus(partialState, on: automatic)
        let partial = try XCTUnwrap(automatic.view.renderChordDraftAutomatically(
            chart: automatic.view.chart, state: partialState,
            now: inputAt.addingTimeInterval(0.05), lastInputAt: inputAt
        ))
        XCTAssertEqual(partial.result.renderedChordCount, 1)
        XCTAssertEqual(automatic.canvas.drawing.strokes.count, 1,
            "A legitimate partial automatic transaction must retain the unfinished target")

        let reviewed = try makeHost(chart())
        windows.append(reviewed.window)
        installDrawing(on: reviewed)
        let reviewedState = state(reviewed.view.chart, drawing: reviewed.canvas.drawing)
        installCensus(reviewedState, on: reviewed)
        let reviewedAttempt = reviewed.view.attemptReviewedChordDraftAutomatically(
            chart: reviewed.view.chart, state: reviewedState
        )
        XCTAssertEqual(try XCTUnwrap(reviewedAttempt.outcome).result.renderedChordCount, 2)
        XCTAssertTrue(reviewed.canvas.drawing.strokes.isEmpty)

        let events = try await automaticPreservationEvents(in: queue)
        var geometryEvents: [IChartTelemetryEvent] = []
        for _ in 0..<100 {
            geometryEvents = try queue.loadEvents().filter { $0.properties["contract_id"] == .string("ink.render_geometry") }
            if geometryEvents.count >= 2 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(geometryEvents.isEmpty, "Actual applied canvas geometry must reach the production queue")
        XCTAssertTrue(geometryEvents.allSatisfy { $0.properties["outcome"] == .string("passed") })
        let automaticEvent = try XCTUnwrap(events.first {
            $0.properties["render_mode"] == .string("automatic")
        })
        let reviewedEvent = try XCTUnwrap(events.first {
            $0.properties["render_mode"] == .string("reviewed_automatic")
        })
        for event in [automaticEvent, reviewedEvent] {
            XCTAssertEqual(event.properties["contract_id"], .string("ink.render_preservation"))
            XCTAssertEqual(event.properties["outcome"], .string("passed"))
            XCTAssertEqual(event.properties["reason"], .string("render_complete"))
            XCTAssertEqual(event.properties["expected_count"], .int(2))
            XCTAssertEqual(event.properties["actual_count"], .int(2))
            XCTAssertEqual(event.properties["source_stroke_count"], .int(2))
            XCTAssertEqual(event.properties["content_matches"], .bool(true))
            XCTAssertNotNil(event.properties["chart_reference"])
        }
        XCTAssertEqual(automaticEvent.properties["consumed_stroke_count"], .int(1))
        XCTAssertEqual(automaticEvent.properties["retained_stroke_count"], .int(1))
        XCTAssertEqual(reviewedEvent.properties["consumed_stroke_count"], .int(2))
        XCTAssertEqual(reviewedEvent.properties["retained_stroke_count"], .int(0))
        let automaticOperation = try XCTUnwrap(automaticEvent.properties["operation_id"])
        let reviewedOperation = try XCTUnwrap(reviewedEvent.properties["operation_id"])
        XCTAssertNotEqual(automaticOperation, reviewedOperation)
        XCTAssertEqual(automaticEvent.installationID, reviewedEvent.installationID)
        XCTAssertEqual(automaticEvent.sessionID, reviewedEvent.sessionID)

        let serialized = String(decoding: try JSONEncoder().encode([automaticEvent, reviewedEvent]), as: UTF8.self)
        for privateValue in [automatic.view.chart.title, reviewed.view.chart.title,
                             automatic.view.chart.id.uuidString.lowercased(),
                             reviewed.view.chart.id.uuidString.lowercased(), originalSource.base64EncodedString()] {
            XCTAssertFalse(serialized.lowercased().contains(privateValue.lowercased()))
        }
        for forbiddenKey in ["drawing", "drawingData", "sourceInkData", "rawInput", "raw_chord_text",
                             "chart_title", "points", "strokes", "candidate_texts"] {
            XCTAssertFalse(serialized.contains("\"\(forbiddenKey)\""), forbiddenKey)
        }
        XCTAssertFalse(serialized.contains("\"C\""), "Synthetic recognized text must remain local")

        // The caller can carry a same-ID model update which the resident host
        // has not applied yet. A refused attempt must compare the actual host
        // before/after, rather than reporting that earlier difference as loss.
        let refused = try makeHost(chart())
        windows.append(refused.window)
        installDrawing(on: refused)
        var collecting = state(refused.view.chart, drawing: refused.canvas.drawing)
        for index in collecting.draftChords.indices { makeCollecting(&collecting.draftChords[index]) }
        refused.coordinator.lastInputAt = inputAt
        installCensus(collecting, on: refused)
        let actualChartBeforeAttempt = refused.view.chart
        let actualSourceBeforeAttempt = refused.canvas.drawing.dataRepresentation()
        var incomingChart = actualChartBeforeAttempt
        incomingChart.title = "Unapplied incoming title update"
        XCTAssertEqual(incomingChart.id, actualChartBeforeAttempt.id)
        XCTAssertNotEqual(incomingChart, actualChartBeforeAttempt)
        XCTAssertNil(refused.view.attemptChordDraftAutomatically(
            chart: incomingChart, state: collecting,
            now: inputAt.addingTimeInterval(2), lastInputAt: inputAt
        ).outcome)
        XCTAssertEqual(refused.view.chart, actualChartBeforeAttempt)
        XCTAssertEqual(refused.canvas.drawing.dataRepresentation(), actualSourceBeforeAttempt)
        var refusalEvents: [IChartTelemetryEvent] = []
        for _ in 0..<60 {
            refusalEvents = try queue.loadEvents().filter {
                $0.properties["contract_id"] == .string("ink.render_preservation")
                    && $0.properties["render_mode"] == .string("automatic")
                    && $0.properties["outcome"] == .string("protected_rejection")
            }
            if !refusalEvents.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let refusalEvent = try XCTUnwrap(refusalEvents.first)
        XCTAssertEqual(refusalEvent.properties["reason"], .string("render_unresolved"))
        XCTAssertEqual(refusalEvent.properties["content_matches"], .bool(true))
        XCTAssertEqual(refusalEvent.properties["consumed_stroke_count"], .int(0))
        XCTAssertEqual(refusalEvent.properties["retained_stroke_count"], .int(2))
        XCTAssertFalse(try queue.loadEvents().contains {
            $0.properties["contract_id"] == .string("ink.render_preservation")
                && $0.properties["outcome"] == .string("violated")
        }, "A pre-existing incoming model difference is not a mutation made by a rejected transaction")

        let authoring = try makeHost(chart())
        windows.append(authoring.window)
        installDrawing(on: authoring)
        let stableSource = authoring.canvas.drawing
        authoring.view.canvasViewDidBeginUsingTool(authoring.canvas)
        // Controlled application-level replacement while pen input is active:
        // the earlier completed stroke vanishes, with no erase/render action.
        authoring.canvas.drawing = PKDrawing(strokes: [try XCTUnwrap(stableSource.strokes.last)])
        authoring.view.canvasViewDrawingDidChange(authoring.canvas)
        authoring.view.canvasViewDidEndUsingTool(authoring.canvas)
        var authoringEvidence: IChartTelemetryEvent?
        for _ in 0..<100 {
            authoringEvidence = try queue.loadEvents().first {
                $0.properties["contract_id"] == .string("ink.authoring_integrity")
                    && $0.properties["outcome"] == .string("violated")
            }
            if authoringEvidence != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(try XCTUnwrap(authoringEvidence).properties["reason"],
            .string("authoring_completed_source_missing"))

        let undoControl = try makeHost(chart())
        windows.append(undoControl.window)
        installDrawing(on: undoControl)
        let undoSource = undoControl.canvas.drawing
        let undo = try XCTUnwrap(undoControl.canvas.undoManager)
        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: undoControl.canvas) { canvas in
            canvas.drawing = PKDrawing(strokes: [undoSource.strokes[1]])
        }
        undo.endUndoGrouping()
        undoControl.view.canvasViewDidBeginUsingTool(undoControl.canvas)
        undo.undo()
        XCTAssertFalse(undo.isUndoing, "The authorized undo has finished before pen end")
        undoControl.view.canvasViewDrawingDidChange(undoControl.canvas)
        undoControl.view.canvasViewDidEndUsingTool(undoControl.canvas)
        try await Task.sleep(nanoseconds: 200_000_000)
        let sourceViolations = try queue.loadEvents().filter {
            $0.properties["contract_id"] == .string("ink.authoring_integrity")
                && $0.properties["outcome"] == .string("violated")
        }
        XCTAssertEqual(sourceViolations.count, 1, "Completed undo must not become a source-loss task")

        let visibility = try makeHost(chart())
        windows.append(visibility.window)
        visibility.view.manualRenderWithPreview = true
        installDrawing(on: visibility)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let priorKeyWindow = scene.windows.first { $0.isKeyWindow }
        defer { priorKeyWindow?.makeKeyAndVisible() }
        visibility.window.isHidden = true
        visibility.window.windowScene = scene
        visibility.window.frame = scene.coordinateSpace.bounds
        visibility.window.makeKeyAndVisible()
        visibility.view.setNeedsLayout()
        visibility.view.layoutIfNeeded()
        visibility.canvas.isHidden = true
        visibility.view.setNeedsLayout()
        visibility.view.layoutIfNeeded()
        var hiddenCanvasEvidence: IChartTelemetryEvent?
        for _ in 0..<120 {
            hiddenCanvasEvidence = try queue.loadEvents().first {
                $0.properties["contract_id"] == .string("ink.live_canvas_visibility")
                    && $0.properties["outcome"] == .string("violated")
            }
            if hiddenCanvasEvidence != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(try XCTUnwrap(hiddenCanvasEvidence).properties["reason"],
            .string("authoring_canvas_invisible"))
        // An intentionally hidden window/editor route is unknown, not a second
        // canvas defect, even while this application's other window is active.
        visibility.window.isHidden = true
        visibility.view.layoutSubviews()
        try await Task.sleep(nanoseconds: 700_000_000)
        visibility.window.makeKeyAndVisible()
        visibility.view.isHidden = true
        visibility.view.layoutSubviews()
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(try queue.loadEvents().filter {
            $0.properties["contract_id"] == .string("ink.live_canvas_visibility")
                && $0.properties["outcome"] == .string("violated")
        }.count, 1)

        consent.setConsentGranted(false)
        await service.consentDidChange()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        let optedOut = try makeHost(chart())
        windows.append(optedOut.window)
        installDrawing(on: optedOut)
        let optedOutState = state(optedOut.view.chart, drawing: optedOut.canvas.drawing)
        optedOut.coordinator.lastInputAt = inputAt
        installCensus(optedOutState, on: optedOut)
        let optedOutOutcome = try XCTUnwrap(optedOut.view.renderChordDraftAutomatically(
            chart: optedOut.view.chart, state: optedOutState,
            now: inputAt.addingTimeInterval(2), lastInputAt: inputAt
        ))
        XCTAssertEqual(optedOutOutcome.result.renderedChordCount, 2)
        XCTAssertTrue(optedOut.canvas.drawing.strokes.isEmpty,
            "Withdrawing diagnostics must not change the automatic rendering operation")
        await service.consentDidChange()
        XCTAssertTrue(try queue.loadEvents().isEmpty)

        // A delayed event from the earlier grant cannot revive when this
        // synthetic installation opts back in; the actor revalidates generation.
        consent.setConsentGranted(true)
        XCTAssertNotEqual(consent.cachedSnapshotForScheduling, originalGrant)
        await service.record("feature.contract_checked", properties: automaticEvent.properties,
            chartID: automatic.view.chart.id, expectedConsent: originalGrant)
        await service.flush(expectedConsent: originalGrant)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    private func automaticPreservationEvents(in queue: IChartTelemetryQueueStore) async throws -> [IChartTelemetryEvent] {
        var events: [IChartTelemetryEvent] = []
        for _ in 0..<60 {
            events = try queue.loadEvents().filter {
                $0.properties["contract_id"] == .string("ink.render_preservation")
            }
            if events.contains(where: { $0.properties["render_mode"] == .string("automatic") })
                && events.contains(where: { $0.properties["render_mode"] == .string("reviewed_automatic") }) {
                return events
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Actual automatic and reviewed canvas transactions did not reach the production telemetry queue")
        return events
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let window: UIWindow
        let coordinator: ChordInkDraftRenderCoordinator
    }

    private func makeHost(_ chart: Chart) throws -> Host {
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
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

    private func chart() -> Chart {
        var chart = Chart.draft(title: "Automatic live render", layoutStyle: .simpleChordSheet)
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

private final class AutomaticLiveRenderTelemetryOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
#endif
