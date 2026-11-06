#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TelemetryConsentResetRetryTests: XCTestCase {
    override func tearDown() {
        IChartTelemetry.configure(nil)
        super.tearDown()
    }

    func testGrantedInitializationFailureDoesNotScheduleDestructiveConsentReset() async throws {
        let f = try fixture(clearFailures: nil)
        let originalBytes = try Data(contentsOf: f.url)
        f.files.failNextDirectoryCreation()
        let trace = ConsentResetRetryTrace { _ in }
        let service = makeService(f, trace: trace)
        IChartTelemetry.configure(service)
        XCTAssertTrue(f.consent.cachedSnapshotForScheduling.isGranted)
        XCTAssertFalse(f.consent.requiresQueueReset)
        await service.consentDidChange()
        XCTAssertEqual(f.files.removeAttempts, 1, "The initializer's failed migration fallback was exercised")
        XCTAssertEqual(trace.count(.queueResetRetryScheduled), 0)
        XCTAssertFalse(f.consent.requiresQueueReset)
        XCTAssertEqual(try Data(contentsOf: f.url), originalBytes)
        XCTAssertEqual(try f.queue.loadEvents().map(\.clientEventID), [f.original.clientEventID])
        f.files.allowRemovals()
        await service.initialize()
        XCTAssertEqual(try f.queue.loadEvents().map(\.clientEventID), [f.original.clientEventID])
        XCTAssertEqual(trace.count(.queueResetRetryScheduled), 0)
    }

    func testFacadeWithdrawalRecoversAfterTwoClearFailuresWithoutManualRefresh() async throws {
        let f = try fixture(clearFailures: 2)
        let entered = expectation(description: "retry sleeping")
        let reset = expectation(description: "automatic reset completed")
        let ended = expectation(description: "retry worker ended")
        let gate = ConsentResetRetryGate { entered.fulfill() }
        defer { gate.release() }
        let trace = ConsentResetRetryTrace { event in
            if event.stage == .queueResetCompleted { reset.fulfill() }
            if event.stage == .queueResetRetryEnded { ended.fulfill() }
        }
        let service = makeService(f, trace: trace, sleep: { try await gate.sleep($0) }, uptime: { 0 })
        await service.initialize()
        IChartTelemetry.configure(service)
        await MainActor.run { IChartTelemetry.setConsentGranted(false) }
        XCTAssertFalse(f.consent.cachedSnapshotForScheduling.isGranted)
        XCTAssertNil(IChartTelemetry.basicRecordingAuthorization())
        await fulfillment(of: [entered], timeout: 5)
        await f.consent.waitForPendingPersistence()
        XCTAssertTrue(f.consent.requiresQueueReset)
        gate.release()
        await fulfillment(of: [reset, ended], timeout: 5)
        XCTAssertEqual(f.files.removeAttempts, 3)
        XCTAssertEqual(trace.count(.queueResetFailed), 2)
        XCTAssertEqual(trace.count(.queueResetRetryScheduled), 1)
        XCTAssertTrue(try f.queue.loadEvents().isEmpty)
        XCTAssertFalse(f.consent.requiresQueueReset)
    }

    func testPermanentClearFailureExhaustsFiniteAttemptsAndKeepsDurableResetMarker() async throws {
        let f = try fixture(clearFailures: nil)
        let entered = expectation(description: "retry sleeping")
        let exhausted = expectation(description: "attempt cap exhausted")
        let ended = expectation(description: "retry worker ended")
        let gate = ConsentResetRetryGate { entered.fulfill() }
        defer { gate.release() }
        let trace = ConsentResetRetryTrace { event in
            if event.stage == .queueResetRetryExhausted { exhausted.fulfill() }
            if event.stage == .queueResetRetryEnded { ended.fulfill() }
        }
        let service = makeService(f, trace: trace, sleep: { try await gate.sleep($0) }, uptime: { 0 })
        await service.initialize()
        IChartTelemetry.configure(service)
        await MainActor.run { IChartTelemetry.setConsentGranted(false) }
        await fulfillment(of: [entered], timeout: 5)
        await f.consent.waitForPendingPersistence()
        gate.release()
        await fulfillment(of: [exhausted, ended], timeout: 5)
        let attemptsAtEnd = f.files.removeAttempts
        XCTAssertGreaterThan(attemptsAtEnd, 0)
        XCTAssertLessThanOrEqual(attemptsAtEnd, 8, "One initial attempt plus at most seven retries")
        XCTAssertEqual(trace.count(.queueResetRetryScheduled), 1)
        XCTAssertEqual(trace.count(.queueResetRetryExhausted), 1)
        XCTAssertTrue(f.consent.requiresQueueReset)
        XCTAssertEqual(try f.queue.loadEvents().map(\.clientEventID), [f.original.clientEventID])
        await f.consent.waitForPendingPersistence()
        XCTAssertEqual(f.files.removeAttempts, attemptsAtEnd, "An ended worker must not reschedule itself")
        XCTAssertEqual(trace.count(.queueResetRetryScheduled), 1)
        XCTAssertFalse(f.consent.cachedSnapshotForScheduling.isGranted)
    }

    func testElapsedBudgetStopsBeforeAnotherClearAndKeepsResetMarker() async throws {
        let f = try fixture(clearFailures: nil)
        let entered = expectation(description: "retry sleeping")
        let exhausted = expectation(description: "elapsed budget exhausted")
        let ended = expectation(description: "retry worker ended")
        let gate = ConsentResetRetryGate { entered.fulfill() }
        let clock = ConsentResetRetryClock()
        defer { gate.release() }
        let trace = ConsentResetRetryTrace { event in
            if event.stage == .queueResetRetryExhausted { exhausted.fulfill() }
            if event.stage == .queueResetRetryEnded { ended.fulfill() }
        }
        let service = makeService(f, trace: trace, sleep: {
            try await gate.sleep($0)
            clock.advance(by: 3)
        }, uptime: { clock.now })
        await service.initialize()
        IChartTelemetry.configure(service)
        await MainActor.run { IChartTelemetry.setConsentGranted(false) }
        await fulfillment(of: [entered], timeout: 5)
        await f.consent.waitForPendingPersistence()
        let attemptsBeforeDeadline = f.files.removeAttempts
        gate.release()
        await fulfillment(of: [exhausted, ended], timeout: 5)
        XCTAssertEqual(f.files.removeAttempts, attemptsBeforeDeadline)
        XCTAssertEqual(trace.count(.queueResetRetryScheduled), 1)
        XCTAssertTrue(f.consent.requiresQueueReset)
        XCTAssertEqual(try f.queue.loadEvents().map(\.clientEventID), [f.original.clientEventID])
        await f.consent.waitForPendingPersistence()
        XCTAssertEqual(f.files.removeAttempts, attemptsBeforeDeadline)
    }

    func testRegrantPreservesAcceptedQueueWhenCancelledOldWorkerActuallyExits() async throws {
        let f = try fixture(clearFailures: nil)
        let entered = expectation(description: "old retry sleeping")
        let reset = expectation(description: "regrant reset completed")
        let appended = expectation(description: "new epoch event accepted")
        let oldEnded = expectation(description: "old worker body exited")
        let gate = ConsentResetRetryGate { entered.fulfill() }
        defer { gate.release() }
        let trace = ConsentResetRetryTrace { event in
            if event.stage == .queueResetCompleted { reset.fulfill() }
            if event.stage == .queueAppended { appended.fulfill() }
        }
        let service = makeService(f, trace: trace, sleep: { try await gate.sleep($0) }, uptime: { 0 })
        await service.initialize()
        IChartTelemetry.configure(service)
        await MainActor.run { IChartTelemetry.setConsentGranted(false) }
        await fulfillment(of: [entered], timeout: 5)
        let oldID = try XCTUnwrap(trace.firstID(.queueResetRetryScheduled))
        trace.observeEnd(of: oldID, expectation: oldEnded)
        await f.consent.waitForPendingPersistence()
        f.files.allowRemovals()
        await MainActor.run { IChartTelemetry.setConsentGranted(true) }
        await fulfillment(of: [reset], timeout: 5)
        await f.consent.waitForPendingPersistence()
        await service.record("app.error", properties: ["error_code": .string("save_error")])
        await fulfillment(of: [appended], timeout: 5)
        let acceptedIDs = try f.queue.loadEvents().map(\.clientEventID)
        XCTAssertEqual(acceptedIDs.count, 1)
        XCTAssertNotEqual(acceptedIDs.first, f.original.clientEventID)
        let removalsBeforeOldExit = f.files.removeAttempts
        gate.release() // Deliberately ignores cancellation until this explicit release.
        await fulfillment(of: [oldEnded], timeout: 5)
        XCTAssertEqual(try f.queue.loadEvents().map(\.clientEventID), acceptedIDs)
        XCTAssertEqual(f.files.removeAttempts, removalsBeforeOldExit)
        XCTAssertFalse(f.consent.requiresQueueReset)
    }

    func testCapturedOldEpochResetCannotClearNewAcceptedEvents() async throws {
        let f = try fixture(clearFailures: 0)
        let reset = expectation(description: "new grant reset completed")
        let appended = expectation(description: "new epoch event accepted")
        let trace = ConsentResetRetryTrace { event in
            if event.stage == .queueResetCompleted { reset.fulfill() }
            if event.stage == .queueAppended { appended.fulfill() }
        }
        let service = makeService(f, trace: trace)
        await service.initialize()
        let oldGrantedEpoch = f.consent.cachedSnapshotForScheduling
        await MainActor.run {
            f.consent.setConsentGranted(false)
            f.consent.setConsentGranted(true)
        }
        await f.consent.waitForPendingPersistence()
        IChartTelemetry.configure(service)
        await service.consentDidChange()
        await fulfillment(of: [reset], timeout: 5)
        await f.consent.waitForPendingPersistence()
        await service.record("app.error", properties: ["error_code": .string("save_error")])
        await fulfillment(of: [appended], timeout: 5)
        let acceptedIDs = try f.queue.loadEvents().map(\.clientEventID)
        XCTAssertEqual(acceptedIDs.count, 1)
        XCTAssertNotEqual(acceptedIDs.first, f.original.clientEventID)
        let removalsBeforeStaleCall = f.files.removeAttempts
        let resetOldEpoch = await service.applyConsentReset(for: oldGrantedEpoch)
        XCTAssertFalse(resetOldEpoch)
        XCTAssertEqual(try f.queue.loadEvents().map(\.clientEventID), acceptedIDs)
        XCTAssertEqual(f.files.removeAttempts, removalsBeforeStaleCall)
        XCTAssertTrue(f.consent.cachedSnapshotForScheduling.isGranted)
        XCTAssertFalse(f.consent.requiresQueueReset)
    }

    private struct Fixture {
        let url: URL
        let consent: IChartTelemetryConsentStore
        let queue: IChartTelemetryQueueStore
        let files: ConsentResetRetryFileManager
        let original: IChartTelemetryEvent
    }

    private func fixture(clearFailures: Int?) throws -> Fixture {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "consent-reset-retry-\(UUID())"))
        defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("consent-reset-retry-\(UUID())/queue.json")
        let files = ConsentResetRetryFileManager(queueURL: url, failures: clearFailures)
        let queue = IChartTelemetryQueueStore(url: url, fileManager: files)
        let original = basicFixtureEvent()
        try queue.append(original)
        return Fixture(url: url, consent: consent, queue: queue, files: files, original: original)
    }

    private func makeService(_ fixture: Fixture, trace: ConsentResetRetryTrace,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> IChartTelemetryService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConsentResetRetryOfflineProtocol.self]
        return IChartTelemetryService(endpointURL: URL(string: "https://telemetry.invalid/ingest")!, publishableKey: "fixture-key",
            sessionStore: nil, queueStore: fixture.queue, installationID: UUID(), consentStore: fixture.consent,
            urlSession: URLSession(configuration: configuration), recordingObserver: { trace.record($0) },
            sleepForConsentResetRetry: sleep, consentResetRetryUptime: uptime)
    }
}

private final class ConsentResetRetryFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private let queueURL: URL
    private var failures: Int?
    private var directoryFailures = 0
    private var attempts = 0
    init(queueURL: URL, failures: Int?) { self.queueURL = queueURL; self.failures = failures; super.init() }
    var removeAttempts: Int { lock.lock(); defer { lock.unlock() }; return attempts }
    func allowRemovals() { lock.lock(); failures = 0; lock.unlock() }
    func failNextDirectoryCreation() { lock.lock(); directoryFailures += 1; lock.unlock() }
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        lock.lock()
        let shouldFail = directoryFailures > 0
        if shouldFail { directoryFailures -= 1 }
        lock.unlock()
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    override func removeItem(at url: URL) throws {
        if url == queueURL {
            lock.lock()
            attempts += 1
            let shouldFail = failures.map { $0 > 0 } ?? true
            if let remaining = failures, remaining > 0 { failures = remaining - 1 }
            lock.unlock()
            if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        }
        try super.removeItem(at: url)
    }
}

private final class ConsentResetRetryGate: @unchecked Sendable {
    private let lock = NSLock()
    private let onEntered: @Sendable () -> Void
    private var first = true
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(onEntered: @escaping @Sendable () -> Void) { self.onEntered = onEntered }
    func sleep(_ nanoseconds: UInt64) async throws {
        let holds = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            lock.lock(); let holds = first; first = false; lock.unlock(); continuation.resume(returning: holds)
        }
        guard holds else { try await Task.sleep(nanoseconds: nanoseconds); return }
        await withCheckedContinuation { continuation in
            lock.lock()
            if released { lock.unlock(); continuation.resume(); return }
            self.continuation = continuation
            lock.unlock()
            onEntered()
        }
    }
    func release() {
        lock.lock(); released = true; let pending = continuation; continuation = nil; lock.unlock(); pending?.resume()
    }
}

private final class ConsentResetRetryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    func advance(by amount: TimeInterval) { lock.lock(); value += amount; lock.unlock() }
}

private final class ConsentResetRetryTrace: @unchecked Sendable {
    private let lock = NSLock()
    private let onFirstStage: @Sendable (IChartTelemetryRecordingTrace) -> Void
    private var events: [IChartTelemetryRecordingTrace] = []
    private var endWaiters: [UUID: XCTestExpectation] = [:]
    init(onFirstStage: @escaping @Sendable (IChartTelemetryRecordingTrace) -> Void) { self.onFirstStage = onFirstStage }
    func record(_ event: IChartTelemetryRecordingTrace) {
        lock.lock()
        let first = !events.contains { $0.stage == event.stage }
        events.append(event)
        let waiter = event.stage == .queueResetRetryEnded ? endWaiters.removeValue(forKey: event.callID) : nil
        lock.unlock()
        if first { onFirstStage(event) }
        waiter?.fulfill()
    }
    func count(_ stage: IChartTelemetryRecordingTrace.Stage) -> Int {
        lock.lock(); defer { lock.unlock() }; return events.filter { $0.stage == stage }.count
    }
    func firstID(_ stage: IChartTelemetryRecordingTrace.Stage) -> UUID? {
        lock.lock(); defer { lock.unlock() }; return events.first { $0.stage == stage }?.callID
    }
    func observeEnd(of id: UUID, expectation: XCTestExpectation) {
        lock.lock()
        let finished = events.contains { $0.stage == .queueResetRetryEnded && $0.callID == id }
        if !finished { endWaiters[id] = expectation }
        lock.unlock()
        if finished { expectation.fulfill() }
    }
}

private final class ConsentResetRetryOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif
