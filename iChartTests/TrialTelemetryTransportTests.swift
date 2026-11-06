#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TrialTelemetryTransportTests: XCTestCase {
    override func tearDown() { TrialTelemetryHTTPStub.configure([]); super.tearDown() }

    func testAnonymousDeliveryUsesOnlyFixedBasicPropertiesAndOriginalIDs() async throws {
        let queue = makeQueue()
        let input = basicFixtureEvent(properties: ["error_code": .string("save_error"), "duration_ms": .double(4.5),
            "operation": .string("library_save"), "source": .string("PRIVATE_ARBITRARY_SOURCE"),
            "chart_reference": .string(String(repeating: "a", count: 64)), "stroke_count": .int(12)])
        try queue.append(input)
        TrialTelemetryHTTPStub.configure([.status(202)])
        await service(queue).flush()
        let request = try XCTUnwrap(TrialTelemetryHTTPStub.requests.first)
        XCTAssertEqual(request.apiKey, "publishable-test-key")
        XCTAssertNil(request.authorization)
        let events = try XCTUnwrap(try batch(request.body)["events"] as? [[String: Any]])
        let properties = try XCTUnwrap(events.first?["properties"] as? [String: Any])
        XCTAssertEqual(properties["error_code"] as? String, "save_error")
        XCTAssertEqual(properties["duration_ms"] as? Double, 4.5)
        XCTAssertEqual(properties["source"] as? String, "library_save")
        XCTAssertNil(properties["operation"])
        XCTAssertFalse(String(decoding: request.body, as: UTF8.self).contains("PRIVATE_ARBITRARY_SOURCE"))
        XCTAssertNil(properties["chart_reference"])
        XCTAssertNil(properties["stroke_count"])
        XCTAssertEqual(events.first?["client_event_id"] as? String, input.clientEventID.uuidString)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testOfflineRetryRetainsIDsAndOneFlushHasBoundedBatches() async throws {
        let queue = makeQueue()
        let inputs = (0..<85).map { _ in basicFixtureEvent() }
        for input in inputs { try queue.append(input) }
        TrialTelemetryHTTPStub.configure([.offline, .status(202), .status(202), .status(202)])
        await service(queue).flush()
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), inputs.map(\.clientEventID))
        await service(queue).flush()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        XCTAssertEqual(TrialTelemetryHTTPStub.requests.count, 4)
        XCTAssertTrue(TrialTelemetryHTTPStub.requests.allSatisfy { $0.body.count <= 120_000 })
    }

    func testRetiredEventsAlreadyOnDiskNeverReachTheEndpoint() async throws {
        let queue = makeQueue()
        try queue.append(basicFixtureEvent(name: "feature.contract_checked"))
        try queue.append(basicFixtureEvent(name: "ink.persisted"))
        TrialTelemetryHTTPStub.configure([])
        await service(queue).flush()
        XCTAssertTrue(TrialTelemetryHTTPStub.requests.isEmpty)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testPartialAcknowledgmentQuarantinesRejectedIDAndKeepsUnknownIDs() async throws {
        let queue = makeQueue()
        let inputs = (0..<3).map { _ in basicFixtureEvent() }
        for input in inputs { try queue.append(input) }
        let partial = try JSONSerialization.data(withJSONObject: ["accepted": true, "stored_count": 1, "rejected_count": 1,
            "accepted_event_ids": [inputs[0].clientEventID.uuidString], "rejected_event_ids": [inputs[1].clientEventID.uuidString]])
        TrialTelemetryHTTPStub.configure([.reply(202, partial), .offline])
        await service(queue).flush()
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), [inputs[2].clientEventID])
        XCTAssertEqual(try queue.healthSnapshot().serverRejectedEventCount, 1)
    }

    func testForeignAcknowledgmentCannotRemovePendingEvents() async throws {
        let queue = makeQueue()
        let input = basicFixtureEvent()
        try queue.append(input)
        let response = try JSONSerialization.data(withJSONObject: ["accepted": true, "stored_count": 1, "rejected_count": 0,
            "accepted_event_ids": [UUID().uuidString], "rejected_event_ids": []])
        TrialTelemetryHTTPStub.configure([.reply(202, response)])
        await service(queue).flush()
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), [input.clientEventID])
        XCTAssertEqual(try queue.healthSnapshot().unacknowledgedBatchCount, 1)
    }

    func testWithdrawalCancelsHeldRequestAndRegrantCannotReviveItsQueue() async throws {
        let queue = makeQueue()
        let consent = try consentStore(granted: true)
        let input = basicFixtureEvent()
        try queue.append(input)
        let telemetry = service(queue, consent: consent)
        IChartTelemetry.configure(telemetry)
        defer { IChartTelemetry.configure(nil) }
        let started = expectation(description: "request started")
        TrialTelemetryHTTPStub.configure([.held], onRequest: { started.fulfill() })
        let flushing = Task { await telemetry.flush() }
        await fulfillment(of: [started], timeout: 2)
        IChartTelemetry.setConsentGranted(false)
        XCTAssertFalse(consent.trySnapshotForScheduling()?.isGranted ?? true)
        for _ in 0..<100 {
            if TrialTelemetryHTTPStub.cancellationCount > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(TrialTelemetryHTTPStub.cancellationCount, 1,
            "The facade must cancel held HTTP without waiting for the data drain or request timeout")
        await flushing.value
        await consent.waitForPendingPersistence()
        await telemetry.consentDidChange()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        consent.setConsentGranted(true)
        await consent.waitForPendingPersistence()
        await telemetry.consentDidChange()
        await consent.waitForPendingPersistence()
        TrialTelemetryHTTPStub.configure([.offline])
        await telemetry.record("app.error", properties: ["error_code": .string("save_error")])
        let replacement = try XCTUnwrap(try queue.loadEvents().first)
        XCTAssertNotEqual(replacement.clientEventID, input.clientEventID)
    }

    func testConstructionDoesNotReadOrClearAQueueAndDisabledInitializationClearsIt() async throws {
        let queue = makeQueue()
        let input = basicFixtureEvent()
        try queue.append(input)
        let disabled = try consentStore(granted: false)
        let telemetry = service(queue, consent: disabled)
        XCTAssertEqual(try queue.loadEvents().count, 1)
        await telemetry.initialize()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    @MainActor
    func testPersistedResetMarkerPreventsOldQueueRevivalAfterRecreation() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-regrant-recreation-\(UUID())"))
        defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        let queue = makeQueue()
        let original = basicFixtureEvent()
        try queue.append(original)
        consent.setConsentGranted(false)
        consent.setConsentGranted(true)
        await consent.waitForPendingPersistence()
        let recreated = IChartTelemetryConsentStore(defaults: defaults)
        XCTAssertTrue(recreated.requiresQueueReset)
        let telemetry = service(queue, consent: recreated)
        await telemetry.initialize()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        TrialTelemetryHTTPStub.configure([.offline])
        await telemetry.record("app.error", properties: ["error_code": .string("save_error")])
        XCTAssertFalse(try queue.loadEvents().contains { $0.clientEventID == original.clientEventID })
    }

    private func makeQueue() -> IChartTelemetryQueueStore {
        IChartTelemetryQueueStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("basic-transport-\(UUID())/queue.json"))
    }

    private func consentStore(granted: Bool) throws -> IChartTelemetryConsentStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-transport-consent-\(UUID())"))
        if granted { defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey) }
        return IChartTelemetryConsentStore(defaults: defaults)
    }

    private func service(_ queue: IChartTelemetryQueueStore, consent: IChartTelemetryConsentStore? = nil) -> IChartTelemetryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TrialTelemetryHTTPStub.self]
        return IChartTelemetryService(endpointURL: URL(string: "https://telemetry.invalid/ingest")!, publishableKey: "publishable-test-key",
            sessionStore: nil, queueStore: queue, installationID: UUID(),
            consentStore: consent ?? (try! consentStore(granted: true)), urlSession: URLSession(configuration: configuration))
    }

    private func batch(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class TrialTelemetryHTTPStub: URLProtocol {
    enum Response { case status(Int), reply(Int, Data), offline, held }
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
            let count = ((try? JSONSerialization.jsonObject(with: capture.body)) as? [String: Any])?["events"] as? [Any]
            respond(status: status, data: Data("{\"accepted\":true,\"stored_count\":\(count?.count ?? 0),\"rejected_count\":0}".utf8))
        case .reply(let status, let data):
            respond(status: status, data: data)
        }
    }

    private func respond(status: Int, data: Data) {
        guard let url = request.url,
              let result = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: result, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
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
