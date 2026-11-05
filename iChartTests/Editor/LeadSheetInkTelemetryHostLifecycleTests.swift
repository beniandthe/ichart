#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import CryptoKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Native host callbacks and real production queue admission. Source is an
/// explicitly synthetic local fixture; the URL protocol prevents transmission.
@MainActor
final class LeadSheetInkTelemetryHostLifecycleTests: XCTestCase {
    func testToolEndBeforeFinalDrawingCallbackRecordsSameOperationResponsivenessAndIntegrity() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let baseline = fixture.canvas.drawing
        fixture.host.canvasViewDidBeginUsingTool(fixture.canvas)
        fixture.host.canvasViewDidEndUsingTool(fixture.canvas)
        fixture.canvas.drawing = PKDrawing(strokes: baseline.strokes + [stroke(150)])
        fixture.host.canvasViewDrawingDidChange(fixture.canvas)
        let events = try await waitForEvents(fixture.queue) {
            $0.contains { $0.properties["contract_id"] == .string("ink.authoring_integrity") }
                && $0.contains { $0.properties["contract_id"] == .string("ink.authoring_responsiveness") }
        }
        let integrity = try XCTUnwrap(events.first { $0.properties["contract_id"] == .string("ink.authoring_integrity") })
        let responsiveness = try XCTUnwrap(events.first { $0.properties["contract_id"] == .string("ink.authoring_responsiveness") })
        XCTAssertEqual(integrity.properties["operation_id"], responsiveness.properties["operation_id"])
        XCTAssertEqual(integrity.properties["outcome"], .string("passed"))
        XCTAssertEqual(integrity.properties["source_stroke_count"], .int(3))
        XCTAssertEqual(integrity.properties["expected_count"], .int(1))
        XCTAssertEqual(integrity.properties["actual_count"], .int(1))
        XCTAssertEqual(responsiveness.properties["scope"], .string("page"))
        if let duration = numericDurationMilliseconds(responsiveness.properties["duration_ms"]) {
            XCTAssertTrue(duration.isFinite)
            XCTAssertGreaterThanOrEqual(duration, 0)
        } else { XCTFail("A real observed callback must retain its measured duration") }
        XCTAssertEqual(fixture.canvas.drawing.strokes.count, 3)
        let serialized = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
        XCTAssertFalse(serialized.contains(fixture.host.chart.title))
        XCTAssertFalse(serialized.contains(baseline.dataRepresentation().base64EncodedString()))
    }

    func testNextPenBeginFinalizesPriorSettlingObservationWithoutDuplicateOrInventedCallback() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.host.canvasViewDidBeginUsingTool(fixture.canvas)
        fixture.host.canvasViewDrawingDidChange(fixture.canvas)
        fixture.host.canvasViewDidEndUsingTool(fixture.canvas)
        // The prior bounded finalizer has not fired yet. Begin must retain its
        // genuine callback measurement before installing the new pen ticket.
        fixture.host.canvasViewDidBeginUsingTool(fixture.canvas)
        fixture.host.canvasViewDidEndUsingTool(fixture.canvas)
        _ = try await waitForEvents(fixture.queue) {
            $0.contains { $0.properties["contract_id"] == .string("ink.authoring_responsiveness") }
        }
        try await Task.sleep(nanoseconds: 350_000_000)
        let responsive = try fixture.queue.loadEvents().filter {
            $0.properties["contract_id"] == .string("ink.authoring_responsiveness")
        }
        XCTAssertEqual(responsive.count, 1,
            "The old timer must not emit again, and a pen operation without callbacks must not invent coverage")
    }

    func testRepeatedIdenticalHostLayoutsDoNotStarveStableCanvasVisibility() async throws {
        let recordingTrace = InkLifecycleRecordingTraceProbe()
        let fixture = try makeFixture(recordingObserver: { recordingTrace.record($0) })
        defer { fixture.close() }
        let chartID = fixture.host.chart.id
        XCTAssertTrue(recordingTrace.snapshot().scheduledCallIDs.isEmpty,
            "The layout observation must begin before any deferred producer handoff")
        for _ in 0..<10 {
            fixture.host.setNeedsLayout()
            fixture.host.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // Preserve the original producer deadline. A queue wait by itself would
        // let a starved timer run only after these repeated layouts stop.
        let scheduledCallIDs = recordingTrace.snapshot().scheduledCallIDs
        XCTAssertEqual(scheduledCallIDs.count, 1,
            "Stable visibility must hand off while identical layouts continue. \(recordingTrace.failureMessage())")

        // The detached recorder and disk append are asynchronous to that handoff.
        // Await their actual completion rather than sampling an in-flight queue.
        let events = try await waitForEvents(fixture.queue) { events in
            events.contains { isFixtureVisibilityEvent($0, chartID: chartID) }
                && recordingTrace.snapshot().appendedCallIDs == scheduledCallIDs
        }
        let visible = try XCTUnwrap(events.first {
            isFixtureVisibilityEvent($0, chartID: chartID)
        }, recordingTrace.failureMessage())
        XCTAssertEqual(visible.properties["outcome"], .string("passed"))
        XCTAssertEqual(visible.properties["scope"], .string("page"))
        XCTAssertEqual(visible.properties["source_stroke_count"], .int(2))
        XCTAssertEqual(visible.properties["expected_count"], .int(1))
        XCTAssertEqual(visible.properties["actual_count"], .int(1))
        if let duration = numericDurationMilliseconds(visible.properties["duration_ms"]) {
            XCTAssertTrue(duration.isFinite)
            XCTAssertGreaterThanOrEqual(duration, 599.999)
        } else {
            XCTFail("Visibility duration must be numeric; \(recordingTrace.failureMessage())")
        }
        XCTAssertEqual(try fixture.queue.loadEvents().filter {
            $0.properties["contract_id"] == .string("ink.live_canvas_visibility")
        }.count, 1)
        let completed = recordingTrace.snapshot()
        XCTAssertFalse(completed.isTruncated, "The bounded fixture trace must retain every producer")
        XCTAssertEqual(completed.scheduledCallIDs, scheduledCallIDs,
            "An ambient or post-loop producer must not satisfy the original handoff deadline")
        XCTAssertEqual(completed.appendedCallIDs, scheduledCallIDs,
            "The delivered visibility event must complete the same sole deferred producer")
    }

    func testSameScopeModelReloadInvalidatesSettlingIntegrityButNextUnannouncedDeletionStillReports() async throws {
        let fixture = try makeFixture(installsDrawingThroughDelegate: false)
        defer { fixture.close() }
        let baseline = fixture.canvas.drawing
        XCTAssertEqual(baseline.strokes.count, 2)
        let chartID = fixture.host.chart.id
        let canvasFrame = fixture.canvas.frame

        fixture.host.canvasViewDidBeginUsingTool(fixture.canvas)
        fixture.host.canvasViewDidEndUsingTool(fixture.canvas)
        // Replace the clean resident canvas through its real model sync while
        // the pen observation is settling. The chart, scope and frame stay put.
        let replacement = PKDrawing(strokes: Array(baseline.strokes.dropFirst()) + [stroke(150), stroke(220)])
        var updatedChart = fixture.host.chart
        XCTAssertTrue(updatedChart.setPageHandwrittenNotationDrawing(replacement.dataRepresentation(),
            coordinateSpace: updatedChart.pageHandwrittenNotationCoordinateSpace))
        fixture.host.chart = updatedChart
        fixture.host.layoutIfNeeded()
        let reloaded = fixture.canvas.drawing
        XCTAssertEqual(fixture.host.chart.id, chartID)
        XCTAssertEqual(fixture.canvas.frame, canvasFrame)
        XCTAssertEqual(reloaded.strokes.count, 3, "The model reload must reach the resident canvas")

        // Starting the next stroke closes any uncancelled prior observation.
        // This time remove completed source without a model, undo or erase.
        fixture.host.canvasViewDidBeginUsingTool(fixture.canvas)
        fixture.canvas.drawing = PKDrawing(strokes: Array(reloaded.strokes.dropFirst()))
        fixture.host.canvasViewDrawingDidChange(fixture.canvas)
        fixture.host.canvasViewDidEndUsingTool(fixture.canvas)

        let events = try await waitForEvents(fixture.queue) { events in
            events.contains {
                $0.properties["contract_id"] == .string("ink.authoring_integrity")
                    && $0.properties["outcome"] == .string("violated")
                    && $0.properties["expected_count"] == .int(2)
                    && $0.properties["actual_count"] == .int(1)
            }
        }
        let violations = events.filter {
            $0.properties["contract_id"] == .string("ink.authoring_integrity")
                && $0.properties["reason"] == .string("authoring_completed_source_missing")
        }
        XCTAssertEqual(violations.count, 1, "Only the unannounced deletion should emit a violation")
        XCTAssertEqual(violations.last?.properties["scope"], .string("page"))
        XCTAssertEqual(violations.last?.properties["expected_count"], .int(2))
        XCTAssertEqual(violations.last?.properties["actual_count"], .int(1))
    }

    func testConsentWithdrawalAndRegrantCannotPublishPendingOldPenOperation() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.host.canvasViewDidBeginUsingTool(fixture.canvas)
        fixture.host.canvasViewDidEndUsingTool(fixture.canvas)
        fixture.host.canvasViewDrawingDidChange(fixture.canvas)
        fixture.consent.setConsentGranted(false)
        await fixture.service.consentDidChange()
        fixture.consent.setConsentGranted(true)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(try fixture.queue.loadEvents().contains {
            $0.properties["contract_id"] == .string("ink.authoring_integrity")
                || $0.properties["contract_id"] == .string("ink.authoring_responsiveness")
        })
        fixture.host.canvasViewDidBeginUsingTool(fixture.canvas)
        fixture.host.canvasViewDidEndUsingTool(fixture.canvas)
        fixture.host.canvasViewDrawingDidChange(fixture.canvas)
        let events = try await waitForEvents(fixture.queue) {
            $0.contains { $0.properties["contract_id"] == .string("ink.authoring_responsiveness") }
        }
        XCTAssertEqual(events.filter {
            $0.properties["contract_id"] == .string("ink.authoring_responsiveness")
        }.count, 1, "Only the new consent-bound pen operation may publish")
    }

    private func makeFixture(installsDrawingThroughDelegate: Bool = true,
        recordingObserver: (@Sendable (IChartTelemetryRecordingTrace) -> Void)? = nil
    ) throws -> Fixture {
        let suiteName = "iChart-authoring-host-lifecycle-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let consent = IChartTelemetryConsentStore(defaults: preferences)
        consent.setConsentGranted(true)
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("queue.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InkLifecycleOfflineProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = IChartTelemetryService(endpointURL: URL(string: "https://telemetry.invalid/lifecycle")!,
            publishableKey: "synthetic-client-key", sessionStore: nil, queueStore: queue,
            consentStore: consent, urlSession: session, recordingObserver: recordingObserver)
        IChartTelemetry.configure(service)

        var chart = Chart.draft(title: "Synthetic local lifecycle source", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        let source = PKDrawing(strokes: [stroke(20), stroke(80)])
        _ = chart.setPageHandwrittenNotationDrawing(source.dataRepresentation())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let host = LeadSheetCanvasUIKitView(frame: scene.coordinateSpace.bounds)
        host.recognizesChordInk = false
        host.chart = chart
        host.interactionMode = .freeHand
        let controller = UIViewController()
        controller.view = host
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        host.setNeedsLayout()
        host.layoutIfNeeded()
        let canvas = try XCTUnwrap(host.subviews.compactMap { $0 as? PKCanvasView }.last)
        if installsDrawingThroughDelegate {
            canvas.drawing = source
            host.canvasViewDrawingDidChange(canvas)
        }
        XCTAssertFalse(canvas.isHidden)
        XCTAssertTrue(canvas.tool is PKInkingTool)
        XCTAssertGreaterThan(canvas.bounds.width, 0)
        return Fixture(host: host, canvas: canvas, window: window, previousWindow: previousWindow,
            directory: directory, suiteName: suiteName, preferences: preferences,
            queue: queue, consent: consent, service: service, session: session)
    }

    private func numericDurationMilliseconds(_ value: IChartTelemetryValue?) -> Double? {
        // Queue JSON has scalar numbers, not enum tags: an integral measured
        // Double can legitimately reload as Int without changing its value.
        switch value {
        case .double(let value)?: return value
        case .int(let value)?: return Double(value)
        default: return nil
        }
    }

    private func isFixtureVisibilityEvent(_ event: IChartTelemetryEvent, chartID: UUID) -> Bool {
        guard event.properties["contract_id"] == .string("ink.live_canvas_visibility"),
              case .string(let reference)? = event.properties["chart_reference"] else { return false }
        // Match the opaque per-installation reference; never log either raw ID.
        let key = SymmetricKey(data: Data(event.installationID.uuidString.lowercased().utf8))
        let message = Data(("ichart-chart-reference-v1:" + chartID.uuidString.lowercased()).utf8)
        let expected = HMAC<SHA256>.authenticationCode(for: message, using: key)
            .map { String(format: "%02x", $0) }.joined()
        return reference == expected
    }

    private func waitForEvents(_ queue: IChartTelemetryQueueStore,
        matching predicate: ([IChartTelemetryEvent]) -> Bool) async throws -> [IChartTelemetryEvent] {
        for _ in 0..<100 {
            let events = try queue.loadEvents()
            if predicate(events) { return events }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let events = try queue.loadEvents()
        XCTFail("The actual native host lifecycle did not publish its expected local evidence")
        return events
    }

    private func stroke(_ x: CGFloat) -> PKStroke {
        let locations = [CGPoint(x: x, y: 100), CGPoint(x: x + 20, y: 120)]
        let points = locations.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: .init(.pen, color: .black),
            path: .init(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(x))),
            transform: .identity, mask: nil, randomSeed: UInt32(x))
    }

    @MainActor
    private struct Fixture {
        let host: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let window: UIWindow
        let previousWindow: UIWindow?
        let directory: URL
        let suiteName: String
        let preferences: UserDefaults
        let queue: IChartTelemetryQueueStore
        let consent: IChartTelemetryConsentStore
        let service: IChartTelemetryService
        let session: URLSession

        func close() {
            host.isInteractionSuspended = true
            IChartTelemetry.configure(nil)
            consent.setConsentGranted(false)
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
            session.invalidateAndCancel()
            preferences.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

/// Test-only bounded metadata; never captures an event payload or source values.
/// Defined outside the MainActor test class so the Sendable observer stays synchronous.
private final class InkLifecycleRecordingTraceProbe: @unchecked Sendable {
    private struct Entry {
        let elapsedMilliseconds: Double
        let callID: UUID
        let eventName: String
        let stage: IChartTelemetryRecordingTrace.Stage
        let admissionDenial: IChartTelemetryConsentAdmissionDenial?
    }

    private let lock = NSLock()
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var entries: [Entry] = []
    private var truncated = false

    func record(_ trace: IChartTelemetryRecordingTrace) {
        lock.lock()
        defer { lock.unlock() }
        guard entries.count < 64 else {
            truncated = true
            return
        }
        entries.append(Entry(
            elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000,
            callID: trace.callID, eventName: trace.eventName,
            stage: trace.stage, admissionDenial: trace.admissionDenial))
    }

    struct Snapshot {
        let scheduledCallIDs: Set<UUID>
        let appendedCallIDs: Set<UUID>
        let isTruncated: Bool
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let featureCalls = entries.filter { $0.eventName == "feature.contract_checked" }
        let scheduled = Set(featureCalls.filter { $0.stage == .deferredScheduled }.map(\.callID))
        return Snapshot(
            scheduledCallIDs: scheduled,
            appendedCallIDs: Set(featureCalls.filter {
                $0.stage == .queueAppended && scheduled.contains($0.callID)
            }.map(\.callID)),
            isTruncated: truncated)
    }

    func failureMessage() -> String {
        lock.lock()
        let snapshot = entries
        let wasTruncated = truncated
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        lock.unlock()
        let header = "Visibility queue read failed; trace snapshot at +\(String(format: "%.3f", elapsedMilliseconds))ms; recording traces=\(snapshot.count), truncated=\(wasTruncated)"
        let rows = snapshot.map { entry in
            let denial = entry.admissionDenial?.rawValue ?? "none"
            return "+\(String(format: "%.3f", entry.elapsedMilliseconds))ms call=\(entry.callID.uuidString.lowercased()) stage=\(entry.stage.rawValue) admission=\(denial)"
        }
        return ([header] + rows).joined(separator: "\n")
    }
}

private final class InkLifecycleOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
#endif
