#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TrialTelemetryTransportTests: XCTestCase {
    override func tearDown() {
        TrialTelemetryHTTPStub.configure([])
        super.tearDown()
    }

    func testSignedOutDeliveryUsesOnlyPublishableKeyAndContentFreeProperties() async throws {
        let queue = makeQueue()
        let input = event(properties: IChartTelemetryPrivacy.sanitizedProperties([
            "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
            "trust_probe_count": .int(4),
            "no_read_count": .int(1),
            "raw_chord_text": .string("Do not upload"),
            "drawing_data": .string("Do not upload")
        ]))
        try queue.append(input)
        TrialTelemetryHTTPStub.configure([.status(202)])
        await service(queue).flush()

        let request = try XCTUnwrap(TrialTelemetryHTTPStub.requests.first)
        XCTAssertEqual(request.apiKey, "publishable-test-key")
        XCTAssertNil(request.authorization)
        XCTAssertEqual(request.timeout, 15)
        let payload = try batch(request.body)
        let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
        let properties = try XCTUnwrap(events.first?["properties"] as? [String: Any])
        XCTAssertEqual(properties["recognition_pipeline_version"] as? String, ChordInkRecognitionPipelineIdentity.version)
        XCTAssertEqual(properties["trust_probe_count"] as? Int, 4)
        XCTAssertEqual(properties["no_read_count"] as? Int, 1)
        XCTAssertNil(properties["raw_chord_text"])
        XCTAssertNil(properties["drawing_data"])
        XCTAssertEqual(events.first?["client_event_id"] as? String, input.clientEventID.uuidString)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testOfflineEventsSurviveServiceRecreationAndRetryWithOriginalIDs() async throws {
        let queue = makeQueue()
        let input = event()
        try queue.append(input)
        TrialTelemetryHTTPStub.configure([.offline, .status(202)])
        await service(queue).flush()
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), [input.clientEventID])

        await service(queue).flush()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        XCTAssertEqual(try sentIDs(), [input.clientEventID, input.clientEventID])
    }

    func testOneFlushDrainsMultipleQueuedBatches() async throws {
        let queue = makeQueue()
        let inputs = (0..<85).map { _ in event() }
        for input in inputs { try queue.append(input) }
        TrialTelemetryHTTPStub.configure([.status(202), .status(202), .status(202)])
        await service(queue).flush()

        XCTAssertEqual(try batchCounts(), [40, 40, 5])
        XCTAssertEqual(try sentIDs(), inputs.map(\.clientEventID))
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testPartialFailureRetainsOnlyUnacknowledgedEventsForLaterRetry() async throws {
        let queue = makeQueue()
        let inputs = (0..<85).map { _ in event() }
        for input in inputs { try queue.append(input) }
        TrialTelemetryHTTPStub.configure([.status(202), .status(500), .status(202), .status(202)])
        let telemetry = service(queue)
        await telemetry.flush()
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), Array(inputs.dropFirst(40)).map(\.clientEventID))

        await telemetry.flush()
        XCTAssertEqual(try batchCounts(), [40, 40, 40, 5])
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testUnicodeBatchStaysBelowServerBodyLimitWithoutLosingTheRemainder() async throws {
        let queue = makeQueue()
        let keys = [
            "app_phase", "auth_state", "decision", "error_code", "feature_area",
            "flow", "from_mode", "layout_style", "mode", "plan", "reason",
            "recognition_pipeline_version", "render_action", "result", "scope",
            "source", "target", "to_mode", "trust_outcome", "subscription_status"
        ]
        let large = Dictionary(uniqueKeysWithValues: keys.map {
            ($0, IChartTelemetryValue.string(String(repeating: "🎵", count: 160)))
        })
        let inputs = (0..<40).map { _ in event(properties: large) }
        for input in inputs { try queue.append(input) }
        TrialTelemetryHTTPStub.configure(Array(repeating: .status(202), count: 4))
        await service(queue).flush()

        let requests = TrialTelemetryHTTPStub.requests
        XCTAssertGreaterThan(requests.count, 1)
        XCTAssertLessThanOrEqual(requests.count, 4)
        XCTAssertTrue(requests.allSatisfy { $0.body.count <= 120_000 })
        let sent = try sentIDs()
        let pending = try queue.loadEvents().map(\.clientEventID)
        XCTAssertEqual(Set(sent + pending), Set(inputs.map(\.clientEventID)))
        XCTAssertEqual(sent.count + pending.count, inputs.count)
    }

    func testForegroundRetryDoesNotRequireAnotherEditorEvent() async throws {
        let queue = makeQueue()
        try queue.append(event())
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        TrialTelemetryHTTPStub.configure([.offline, .status(202)])
        let telemetry = service(queue, now: { clock })
        await telemetry.flush()
        clock.addTimeInterval(19)
        await telemetry.flushIfNeeded()
        XCTAssertEqual(TrialTelemetryHTTPStub.requests.count, 1)
        clock.addTimeInterval(2)
        await telemetry.flushIfNeeded()
        XCTAssertEqual(TrialTelemetryHTTPStub.requests.count, 2)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testCancelledFlushKeepsQueuedEventsWithoutSending() async throws {
        let queue = makeQueue()
        let input = event()
        try queue.append(input)
        TrialTelemetryHTTPStub.configure([.status(202)])
        let telemetry = service(queue)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await telemetry.flush()
        }
        await task.value
        XCTAssertTrue(TrialTelemetryHTTPStub.requests.isEmpty)
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), [input.clientEventID])
    }

    func testRecordingDuringAFlushNeverLosesTheNewEvent() async throws {
        for _ in 0..<12 {
            let queue = makeQueue()
            let original = event()
            try queue.append(original)
            TrialTelemetryHTTPStub.configure(Array(repeating: .status(202), count: 4))
            let telemetry = service(queue)
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await telemetry.flush() }
                group.addTask { await telemetry.record("chord.preview_discarded") }
            }
            let sent = try sentIDs()
            let pending = try queue.loadEvents().map(\.clientEventID)
            XCTAssertEqual(Set(sent + pending).count, 2)
            XCTAssertTrue(Set(sent + pending).contains(original.clientEventID))
        }
    }

    func testUnconsentedServiceClearsLegacyQueueAndNeverCreatesIdentityOrSends() async throws {
        let queue = makeQueue()
        try queue.append(event())
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "iChart-telemetry-off-\(UUID().uuidString)"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        TrialTelemetryHTTPStub.configure([.status(202)])
        let telemetry = service(queue, consentStore: consent, installationID: nil)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        await telemetry.record("app.launched")
        await telemetry.flush()
        await telemetry.flushIfNeeded()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        XCTAssertTrue(TrialTelemetryHTTPStub.requests.isEmpty)
        XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
    }

    func testExplicitConsentEnablesRecordingAndWithdrawalDropsOfflineBacklog() async throws {
        let queue = makeQueue()
        let consent = makeConsentStore(granted: false)
        let telemetry = service(queue, consentStore: consent)
        TrialTelemetryHTTPStub.configure([.offline, .status(202)])
        consent.setConsentGranted(true)
        await telemetry.record("app.launched")
        let oldEvent = try XCTUnwrap(try queue.loadEvents().first)
        consent.setConsentGranted(false)
        await telemetry.consentDidChange()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        await telemetry.record("chord.preview_discarded")
        await telemetry.flush()
        XCTAssertEqual(TrialTelemetryHTTPStub.requests.count, 1)
        consent.setConsentGranted(true)
        await telemetry.record("chord.preview_discarded")
        let delivered = try sentIDs()
        XCTAssertEqual(delivered.count, 2)
        XCTAssertEqual(delivered.first, oldEvent.clientEventID)
        XCTAssertNotEqual(delivered.last, oldEvent.clientEventID)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testRecordCapturedBeforeOptInOrWithdrawalCannotRunAfterLaterOptIn() async throws {
        let queue = makeQueue()
        let consent = makeConsentStore(granted: false)
        let telemetry = service(queue, consentStore: consent)
        let disabledConsent = consent.snapshot
        consent.setConsentGranted(true)
        await telemetry.record("app.launched", expectedConsent: disabledConsent)
        let earlierConsent = consent.snapshot
        consent.setConsentGranted(false)
        consent.setConsentGranted(true)
        await telemetry.record("app.launched", expectedConsent: earlierConsent)
        await telemetry.flush(expectedConsent: earlierConsent)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        XCTAssertTrue(TrialTelemetryHTTPStub.requests.isEmpty)
    }

    func testWithdrawalThenOptInBeforeCleanupCannotReviveQueueAfterRecreation() async throws {
        let queue = makeQueue()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "iChart-telemetry-relaunch-\(UUID().uuidString)"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        consent.setConsentGranted(true)
        let originalService = service(queue, consentStore: consent, installationID: nil)
        TrialTelemetryHTTPStub.configure([.offline])
        await originalService.record("app.launched")
        let withdrawnEvent = try XCTUnwrap(try queue.loadEvents().first)

        // Do not notify the first actor: model termination before its queued
        // withdrawal cleanup, followed by a fresh store and service on launch.
        consent.setConsentGranted(false)
        consent.setConsentGranted(true)
        XCTAssertTrue(consent.requiresQueueReset)
        let recreatedConsent = IChartTelemetryConsentStore(defaults: defaults)
        XCTAssertTrue(recreatedConsent.snapshot.isGranted)
        XCTAssertTrue(recreatedConsent.requiresQueueReset)
        let recreatedService = service(queue, consentStore: recreatedConsent, installationID: nil)
        XCTAssertFalse(recreatedConsent.requiresQueueReset)
        XCTAssertTrue(try queue.loadEvents().isEmpty)

        TrialTelemetryHTTPStub.configure([.status(202)])
        await recreatedService.flush()
        XCTAssertTrue(TrialTelemetryHTTPStub.requests.isEmpty)
        await recreatedService.record("chord.preview_discarded")
        let freshEvent = try XCTUnwrap(try queue.loadEvents().first)
        XCTAssertNotEqual(freshEvent.clientEventID, withdrawnEvent.clientEventID)
        // The empty flush intentionally started the existing retry cooldown.
        // Explicitly flush the newly consented event rather than assuming an
        // immediate opportunistic retry during that interval.
        await recreatedService.flush()
        let delivered = try sentIDs()
        XCTAssertEqual(delivered.count, 1)
        XCTAssertNotEqual(delivered.first, withdrawnEvent.clientEventID)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testWithdrawalCancelsInFlightRequestAndClearsQueue() async throws {
        let queue = makeQueue()
        try queue.append(event())
        let consent = makeConsentStore(granted: true)
        let telemetry = service(queue, consentStore: consent)
        let started = expectation(description: "Telemetry request started")
        let completed = expectation(description: "Withdrawn telemetry flush completed")
        TrialTelemetryHTTPStub.configure([.held], onRequest: { started.fulfill() })
        let flush = Task {
            await telemetry.flush()
            completed.fulfill()
        }
        defer { flush.cancel() }
        await fulfillment(of: [started], timeout: 2)
        consent.setConsentGranted(false)
        await telemetry.consentDidChange()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        XCTAssertEqual(TrialTelemetryHTTPStub.requests.count, 1)
        XCTAssertEqual(TrialTelemetryHTTPStub.cancellationCount, 1)
    }

    func testOldInFlightCompletionCannotDequeueEventsFromAnotherConsentGeneration() async throws {
        let queue = makeQueue()
        let original = event()
        try queue.append(original)
        let consent = makeConsentStore(granted: true)
        let telemetry = service(queue, consentStore: consent)
        let started = expectation(description: "Original telemetry request started")
        let completed = expectation(description: "Previous consent generation flush completed")
        TrialTelemetryHTTPStub.configure([.held, .status(202)], onRequest: { started.fulfill() })
        let flush = Task {
            await telemetry.flush()
            completed.fulfill()
        }
        defer { flush.cancel() }
        await fulfillment(of: [started], timeout: 2)
        TrialTelemetryHTTPStub.setOnRequest(nil)
        consent.setConsentGranted(false)
        consent.setConsentGranted(true)
        await telemetry.record("chord.preview_discarded")
        let replacement = try XCTUnwrap(try queue.loadEvents().first)
        XCTAssertNotEqual(replacement.clientEventID, original.clientEventID)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), [replacement.clientEventID])
        XCTAssertEqual(TrialTelemetryHTTPStub.requests.count, 1)
        await telemetry.flush()
        XCTAssertEqual(try sentIDs(), [original.clientEventID, replacement.clientEventID])
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    private func makeQueue() -> IChartTelemetryQueueStore {
        IChartTelemetryQueueStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("iChart-trial-telemetry-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("queue.json"))
    }

    private func makeConsentStore(granted: Bool) -> IChartTelemetryConsentStore {
        let defaults = UserDefaults(suiteName: "iChart-trial-telemetry-consent-\(UUID().uuidString)")!
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        consent.setConsentGranted(granted)
        return consent
    }

    private func service(
        _ queue: IChartTelemetryQueueStore,
        consentStore: IChartTelemetryConsentStore? = nil,
        installationID: UUID? = UUID(),
        now: @escaping () -> Date = Date.init
    ) -> IChartTelemetryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TrialTelemetryHTTPStub.self]
        return IChartTelemetryService(
            endpointURL: URL(string: "https://telemetry.invalid/functions/v1/app-telemetry-ingest")!,
            publishableKey: "publishable-test-key",
            sessionStore: nil,
            queueStore: queue,
            installationID: installationID,
            consentStore: consentStore ?? makeConsentStore(granted: true),
            urlSession: URLSession(configuration: configuration),
            now: now
        )
    }

    private func event(properties: IChartTelemetryProperties = [:]) -> IChartTelemetryEvent {
        IChartTelemetryEvent(
            clientEventID: UUID(), eventName: "chord.preview_updated",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
            installationID: UUID(), sessionID: UUID(), appVersion: "trial",
            buildNumber: "test", platform: "iPadOS", osVersion: "test",
            deviceModel: "test", localeLanguage: "en", timeZoneOffsetMinutes: 0,
            properties: properties
        )
    }

    private func batch(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func batchCounts() throws -> [Int] {
        try TrialTelemetryHTTPStub.requests.map {
            try XCTUnwrap(try batch($0.body)["events"] as? [[String: Any]]).count
        }
    }

    private func sentIDs() throws -> [UUID] {
        try TrialTelemetryHTTPStub.requests.flatMap {
            try XCTUnwrap(try batch($0.body)["events"] as? [[String: Any]]).map {
                try XCTUnwrap(UUID(uuidString: try XCTUnwrap($0["client_event_id"] as? String)))
            }
        }
    }
}

private final class TrialTelemetryHTTPStub: URLProtocol {
    enum Response { case status(Int), offline, held }
    struct CapturedRequest {
        let body: Data
        let apiKey: String?
        let authorization: String?
        let timeout: TimeInterval
    }
    private static let lock = NSLock()
    private static var responses: [Response] = []
    private static var captured: [CapturedRequest] = []
    private static var onRequest: (() -> Void)?
    private static var cancelledRequests = 0

    static var cancellationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelledRequests
    }

    static var requests: [CapturedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static func configure(_ values: [Response], onRequest: (() -> Void)? = nil) {
        lock.lock()
        defer { lock.unlock() }
        responses = values
        captured = []
        cancelledRequests = 0
        self.onRequest = onRequest
    }

    static func setOnRequest(_ callback: (() -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        onRequest = callback
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let capture = CapturedRequest(
            body: Self.body(of: request),
            apiKey: request.value(forHTTPHeaderField: "apikey"),
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            timeout: request.timeoutInterval
        )
        Self.lock.lock()
        Self.captured.append(capture)
        let response = Self.responses.isEmpty ? Response.status(202) : Self.responses.removeFirst()
        let onRequest = Self.onRequest
        Self.lock.unlock()
        onRequest?()

        switch response {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .held:
            break
        case .status(let status):
            guard let url = request.url,
                  let result = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: result, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"accepted\":true}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.lock.lock()
        Self.cancelledRequests += 1
        Self.lock.unlock()
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }
}
#endif
