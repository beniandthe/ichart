#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TelemetrySchedulingConsentTests: XCTestCase {
    override func tearDown() {
        IChartTelemetry.configure(nil)
        super.tearDown()
    }

    func testMainEntryPointsReturnWhileQueueAppendHoldsAuthoritativeConsentLock() async throws {
        let consent = try makeConsent(granted: true)
        let gate = TelemetrySchedulingIOGate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = IChartTelemetryQueueStore(
            url: directory.appendingPathComponent("queue.json"),
            fileManager: TelemetrySchedulingBlockingFileManager(gate: gate)
        )
        let service = makeService(consent: consent, queue: queue)
        IChartTelemetry.configure(service)
        let recording = Task.detached { await service.record("pdf.export_succeeded") }
        defer { gate.release() }
        XCTAssertTrue(gate.waitUntilEntered(), "The actual queue append must reach its disk-write section")

        await assertMainEntryPointsReturnBeforeReleasingIO()

        gate.release()
        await recording.value
        consent.setConsentGranted(false)
        await service.consentDidChange()
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    func testMainEntryPointsReturnWhileCheckpointPublishHoldsAuthoritativeConsentLock() async throws {
        let gate = TelemetrySchedulingIOGate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let checkpoint = directory.appendingPathComponent("library-state.json.experience-checkpoint.json")
        let consent = IChartTelemetryConsentStore(
            defaults: try makeDefaults(granted: true), diagnosticFileURLs: [checkpoint],
            writeDiagnosticFile: { data, url in
                try gate.block()
                try data.write(to: url, options: .atomic)
            }
        )
        let authorization = try XCTUnwrap(consent.checkpointAuthorization())
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("queue.json"))
        let service = makeService(consent: consent, queue: queue)
        IChartTelemetry.configure(service)
        let publishing = Task.detached {
            try consent.publishDiagnosticCheckpoint(Data([1, 2, 3]), to: checkpoint, authorization: authorization)
        }
        defer { gate.release() }
        XCTAssertTrue(gate.waitUntilEntered(), "The actual checkpoint publisher must hold its consent lock")

        await assertMainEntryPointsReturnBeforeReleasingIO()

        gate.release()
        let published = try await publishing.value
        XCTAssertTrue(published)
        consent.setConsentGranted(false)
        await service.consentDidChange()
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.path))
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    func testSchedulingMirrorTracksSupportedConsentTransitionsAndGeneration() throws {
        let consent = try makeConsent(granted: false)
        let disabled = consent.cachedSnapshotForScheduling
        XCTAssertFalse(disabled.isGranted)
        XCTAssertEqual(disabled, consent.snapshot)
        consent.setConsentGranted(true)
        let firstGrant = consent.cachedSnapshotForScheduling
        XCTAssertTrue(firstGrant.isGranted)
        XCTAssertEqual(firstGrant, consent.snapshot)
        consent.setConsentGranted(false)
        XCTAssertFalse(consent.cachedSnapshotForScheduling.isGranted)
        XCTAssertEqual(consent.cachedSnapshotForScheduling, consent.snapshot)
        consent.setConsentGranted(true)
        XCTAssertNotEqual(consent.cachedSnapshotForScheduling, firstGrant)
        XCTAssertEqual(consent.cachedSnapshotForScheduling, consent.snapshot)
        XCTAssertNil(consent.performIfGranted(matching: firstGrant) { true })
    }

    func testWithdrawalPublishesDisabledSchedulingStateBeforeCheckpointCleanupCompletes() async throws {
        let gate = TelemetrySchedulingIOGate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let checkpoint = directory.appendingPathComponent("checkpoint.json")
        let consent = IChartTelemetryConsentStore(
            defaults: try makeDefaults(granted: true), diagnosticFileURLs: [checkpoint],
            removeDiagnosticFile: { _ in try gate.block() }
        )
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("queue.json"))
        let service = makeService(consent: consent, queue: queue)
        IChartTelemetry.configure(service)
        let withdrawing = Task.detached { consent.setConsentGranted(false) }
        defer { gate.release() }
        XCTAssertTrue(gate.waitUntilEntered())

        await assertMainEntryPointsReturnBeforeReleasingIO(expectedEnabled: false)

        gate.release()
        await withdrawing.value
        await service.consentDidChange()
        XCTAssertFalse(consent.cachedSnapshotForScheduling.isGranted)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
    }

    func testCachedOffAndEarlierGenerationTasksCannotRecordOrSendAfterOptIn() async throws {
        let consent = try makeConsent(granted: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("queue.json"))
        let service = makeService(consent: consent, queue: queue)
        let disabled = consent.cachedSnapshotForScheduling
        consent.setConsentGranted(true)
        await service.record("pdf.export_succeeded", expectedConsent: disabled)
        let firstGrant = consent.cachedSnapshotForScheduling
        consent.setConsentGranted(false)
        consent.setConsentGranted(true)

        await service.record("pdf.export_succeeded", expectedConsent: firstGrant)
        await service.flush(expectedConsent: firstGrant)

        XCTAssertTrue(try queue.loadEvents().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("queue.json").path))
    }

    func testAuthoritativeValidationRejectsDirectPreferenceWithdrawalAndRefreshesMirror() async throws {
        let preferences = try makeDefaults(granted: true)
        let consent = IChartTelemetryConsentStore(defaults: preferences)
        let staleGrant = consent.cachedSnapshotForScheduling
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("queue.json"))
        let service = makeService(consent: consent, queue: queue)
        preferences.removeObject(forKey: IChartTelemetryConsentStore.preferenceKey)
        XCTAssertEqual(consent.cachedSnapshotForScheduling, staleGrant,
                       "Scheduling does not synchronously read preferences or perform cleanup")

        await service.record("pdf.export_succeeded", expectedConsent: staleGrant)
        await service.flush(expectedConsent: staleGrant)

        XCTAssertFalse(consent.cachedSnapshotForScheduling.isGranted)
        XCTAssertEqual(consent.cachedSnapshotForScheduling, consent.snapshot)
        XCTAssertTrue(try queue.loadEvents().isEmpty)
        XCTAssertNil(preferences.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
    }

    private func assertMainEntryPointsReturnBeforeReleasingIO(expectedEnabled: Bool = true) async {
        let returned = expectation(description: "main telemetry scheduling returned while I/O is blocked")
        DispatchQueue.main.async {
            XCTAssertEqual(IChartTelemetry.isRecordingEnabled, expectedEnabled)
            IChartTelemetry.record("pdf.export_succeeded")
            IChartTelemetry.flush()
            returned.fulfill()
        }
        // The test keeps the writer blocked until this expectation completes.
        // A caller waiting on the I/O-bearing consent lock fails this deadline.
        await fulfillment(of: [returned], timeout: 1)
    }

    private func makeDefaults(granted: Bool) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "iChart-scheduling-consent-\(UUID().uuidString)"))
        if granted {
            defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
        }
        return defaults
    }

    private func makeConsent(granted: Bool) throws -> IChartTelemetryConsentStore {
        IChartTelemetryConsentStore(defaults: try makeDefaults(granted: granted))
    }

    private func makeService(
        consent: IChartTelemetryConsentStore, queue: IChartTelemetryQueueStore
    ) -> IChartTelemetryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetrySchedulingOfflineProtocol.self]
        return IChartTelemetryService(
            endpointURL: URL(string: "https://telemetry.invalid/ingest")!,
            publishableKey: "test", sessionStore: nil, queueStore: queue,
            consentStore: consent, urlSession: URLSession(configuration: configuration)
        )
    }
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
