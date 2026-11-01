#if canImport(UIKit) && canImport(PencilKit)
import Foundation
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
        if case .double(let duration) = responsiveness.properties["duration_ms"] {
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
        let fixture = try makeFixture()
        defer { fixture.close() }
        for _ in 0..<10 {
            fixture.host.setNeedsLayout()
            fixture.host.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let visible = try XCTUnwrap(try fixture.queue.loadEvents().first {
            $0.properties["contract_id"] == .string("ink.live_canvas_visibility")
        })
        XCTAssertEqual(visible.properties["outcome"], .string("passed"))
        XCTAssertEqual(visible.properties["scope"], .string("page"))
        XCTAssertEqual(visible.properties["source_stroke_count"], .int(2))
        XCTAssertEqual(visible.properties["expected_count"], .int(1))
        XCTAssertEqual(visible.properties["actual_count"], .int(1))
        if case .double(let duration) = visible.properties["duration_ms"] {
            XCTAssertGreaterThanOrEqual(duration, 599.999)
        } else { XCTFail("Visibility duration must be the actual stable observation span") }
        XCTAssertEqual(try fixture.queue.loadEvents().filter {
            $0.properties["contract_id"] == .string("ink.live_canvas_visibility")
        }.count, 1)
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

    private func makeFixture() throws -> Fixture {
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
            consentStore: consent, urlSession: session)
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
        canvas.drawing = source
        host.canvasViewDrawingDidChange(canvas)
        XCTAssertFalse(canvas.isHidden)
        XCTAssertTrue(canvas.tool is PKInkingTool)
        XCTAssertGreaterThan(canvas.bounds.width, 0)
        return Fixture(host: host, canvas: canvas, window: window, previousWindow: previousWindow,
            directory: directory, suiteName: suiteName, preferences: preferences,
            queue: queue, consent: consent, service: service, session: session)
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

private final class InkLifecycleOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
#endif
