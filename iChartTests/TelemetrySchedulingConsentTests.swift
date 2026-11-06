#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TelemetrySchedulingConsentTests: XCTestCase {
    override func tearDown() { IChartTelemetry.configure(nil); super.tearDown() }

    func testMainAdmissionAndWithdrawalReturnWhileActualQueueIOIsBlocked() async throws {
        let consent = try makeConsent()
        let gate = TelemetrySchedulingIOGate()
        let queue = IChartTelemetryQueueStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("basic-blocked-\(UUID())/queue.json"),
            fileManager: TelemetrySchedulingBlockingFileManager(gate: gate))
        let service = makeService(consent: consent, queue: queue)
        IChartTelemetry.configure(service)
        let recording = Task.detached { await service.record("app.error", properties: ["error_code": .string("save_error")]) }
        defer { gate.release() }
        XCTAssertTrue(gate.waitUntilEntered())
        let returned = expectation(description: "main returns before queue I/O release")
        DispatchQueue.main.async {
            XCTAssertTrue(IChartTelemetry.isBasicRecordingEnabled)
            XCTAssertFalse(IChartTelemetry.isRecordingEnabled)
            IChartTelemetry.record("app.error", properties: ["error_code": .string("save_error")])
            IChartTelemetry.flush()
            IChartTelemetry.setConsentGranted(false)
            XCTAssertFalse(IChartTelemetry.isBasicRecordingEnabled)
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 1)
        gate.release()
        await recording.value
        await consent.waitForPendingPersistence()
        await service.consentDidChange()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testSingleDrainKeepsOnly64PendingScalarsWhileNetworkIsHeld() async throws {
        let consent = try makeConsent()
        let queue = IChartTelemetryQueueStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("basic-held-network-\(UUID())/queue.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BasicHeldTelemetryProtocol.self]
        let started = expectation(description: "network held")
        BasicHeldTelemetryProtocol.onStart = { started.fulfill() }
        defer { BasicHeldTelemetryProtocol.onStart = nil }
        let service = IChartTelemetryService(endpointURL: URL(string: "https://telemetry.invalid/held")!,
            publishableKey: "test", sessionStore: nil, queueStore: queue, installationID: UUID(),
            consentStore: consent, urlSession: URLSession(configuration: configuration))
        let admission = IChartTelemetryAdmission()
        admission.configure(service)
        admission.record("app.error", properties: ["error_code": .string("save_error")])
        await fulfillment(of: [started], timeout: 2)
        let returned = expectation(description: "bounded admission on main")
        DispatchQueue.main.async {
            for _ in 0..<1_000 { admission.record("app.error", properties: ["error_code": .string("save_error")]) }
            XCTAssertEqual(admission.pendingCount, 64)
            XCTAssertEqual(admission.droppedCount, 936)
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 1)
        consent.setConsentGranted(false)
        await consent.waitForPendingPersistence()
        await service.consentDidChange()
        for _ in 0..<100 {
            if admission.pendingCount == 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(admission.pendingCount, 0)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testDisabledDiagnosticAPINeverEvaluatesItsCaptureClosure() async {
        let completed = expectation(description: "obsolete diagnostic bookkeeping completes once")
        completed.assertForOverFulfill = true
        IChartTelemetry.recordDeferredDiagnostic("feature.contract_checked", chartID: UUID(),
            authorization: .init(), onCompletion: { completed.fulfill() }) {
                XCTFail("Retired diagnostics cannot inspect chart or source data")
                return ["reason": .string("private content")]
            }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertNil(IChartTelemetry.diagnosticAuthorization())
    }

    func testCapturedOldGenerationCannotRecordAfterWithdrawalAndRegrant() async throws {
        let consent = try makeConsent()
        let original = consent.snapshot
        let queue = IChartTelemetryQueueStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("basic-old-epoch-\(UUID())/queue.json"))
        let service = makeService(consent: consent, queue: queue)
        consent.setConsentGranted(false)
        consent.setConsentGranted(true)
        await consent.waitForPendingPersistence()
        await service.record("app.error", properties: ["error_code": .string("save_error")], expectedConsent: original)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testBasicAuthorizationCannotSurviveWithdrawalRegrantOrServiceReplacement() throws {
        let consent = try makeConsent()
        let queue = IChartTelemetryQueueStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("basic-token-\(UUID())/queue.json"))
        IChartTelemetry.configure(makeService(consent: consent, queue: queue))
        let original = try XCTUnwrap(IChartTelemetry.basicRecordingAuthorization())
        XCTAssertTrue(original.isCurrent)
        consent.setConsentGranted(false)
        XCTAssertFalse(original.isCurrent)
        consent.setConsentGranted(true)
        XCTAssertFalse(original.isCurrent)
        let replacement = try XCTUnwrap(IChartTelemetry.basicRecordingAuthorization())
        IChartTelemetry.configure(nil)
        XCTAssertFalse(replacement.isCurrent)
    }

    private func makeConsent() throws -> IChartTelemetryConsentStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-scheduling-\(UUID())"))
        defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
        return IChartTelemetryConsentStore(defaults: defaults)
    }

    private func makeService(consent: IChartTelemetryConsentStore, queue: IChartTelemetryQueueStore) -> IChartTelemetryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetrySchedulingOfflineProtocol.self]
        return IChartTelemetryService(endpointURL: URL(string: "https://telemetry.invalid/ingest")!,
            publishableKey: "test", sessionStore: nil, queueStore: queue, installationID: UUID(),
            consentStore: consent, urlSession: URLSession(configuration: configuration))
    }
}

private final class BasicHeldTelemetryProtocol: URLProtocol {
    static var onStart: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?() }
    override func stopLoading() {}
}

private final class TelemetrySchedulingIOGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didBlock = false

    func block() throws {
        lock.lock()
        let shouldBlock = !didBlock
        didBlock = true
        lock.unlock()
        guard shouldBlock else { return }
        entered.signal()
        guard released.wait(timeout: .now() + 5) == .success else {
            throw NSError(domain: "TelemetrySchedulingIOTimeout", code: 1)
        }
    }

    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    func release() { released.signal() }
}

private final class TelemetrySchedulingBlockingFileManager: FileManager, @unchecked Sendable {
    private let gate: TelemetrySchedulingIOGate

    init(gate: TelemetrySchedulingIOGate) {
        self.gate = gate
        super.init()
    }

    override func createDirectory(
        at url: URL, withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try gate.block()
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

private final class TelemetrySchedulingOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
#endif
