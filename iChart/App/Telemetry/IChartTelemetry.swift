import Foundation
import CoreFoundation

enum IChartTelemetryValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

typealias IChartTelemetryProperties = [String: IChartTelemetryValue]

struct IChartTelemetryContext: Codable, Equatable {
    let installationID: UUID
    let sessionID: UUID
    let appVersion: String
    let buildNumber: String
    let platform: String
    let osVersion: String
    let deviceModel: String
    let localeLanguage: String
    let timeZoneOffsetMinutes: Int

    enum CodingKeys: String, CodingKey {
        case installationID = "installation_id"
        case sessionID = "session_id"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case localeLanguage = "locale_language"
        case timeZoneOffsetMinutes = "time_zone_offset_minutes"
    }
}

struct IChartTelemetryEvent: Codable, Equatable, Identifiable {
    let clientEventID: UUID
    let eventName: String
    let occurredAt: Date
    let installationID: UUID
    let sessionID: UUID
    let appVersion: String
    let buildNumber: String
    let platform: String
    let osVersion: String
    let deviceModel: String
    let localeLanguage: String
    let timeZoneOffsetMinutes: Int
    let properties: IChartTelemetryProperties

    var id: UUID { clientEventID }

    enum CodingKeys: String, CodingKey {
        case clientEventID = "client_event_id"
        case eventName = "event_name"
        case occurredAt = "occurred_at"
        case installationID = "installation_id"
        case sessionID = "session_id"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case localeLanguage = "locale_language"
        case timeZoneOffsetMinutes = "time_zone_offset_minutes"
        case properties
    }
}

private struct IChartTelemetryBatch: Encodable {
    let context: IChartTelemetryContext
    let events: [IChartTelemetryEvent]
}

/// Optional in-memory fixture diagnostics. These stages are never telemetry
/// properties and contain no account, installation, chart or content values.
struct IChartTelemetryRecordingTrace: Sendable {
    enum Stage: String, Sendable {
        case deferredScheduled, deferredStarted, deferredCompleted
        case observationEntered, observationRejected, propertiesUnavailable
        case recordEntered, consentPreparationRejected, expectedConsentRejected, eventNameRejected
        case identityRequested, identityUnavailable, identityResolved
        case contextAdmissionRejected, contextReady, contractPropertiesRejected
        case queueAdmissionRejected, queueAppendFailed, queueAppended
        case queueResetStarted, queueResetRejected, queueResetFailed, queueResetCompleted
        case queueResetRetryScheduled, queueResetRetryExhausted, queueResetRetryEnded
    }

    let callID: UUID
    let eventName: String
    let stage: Stage
    let errorDomain: String?
    let errorCode: Int?
    let admissionDenial: IChartTelemetryConsentAdmissionDenial?
}

enum IChartTelemetryBuildSource {
    static var value: String {
        #if DEBUG
        "debug_build"
        #else
        "release_build"
        #endif
    }
}

/// Best-effort admission for basic scalar diagnostics. A busy or full buffer
/// drops an observation. Callers never wait for storage, consent cleanup or HTTP.
enum IChartTelemetry {
    private static let admission = IChartTelemetryAdmission()

    static func configure(_ service: IChartTelemetryService?) {
        admission.configure(service)
    }

    static func setConsentGranted(_ isGranted: Bool) {
        admission.setConsentGranted(isGranted)
    }

    /// Legacy live-capture callers stay disabled, including when basic error
    /// reporting is consented. Basic recording checks consent at admission.
    static var isRecordingEnabled: Bool { false }

    struct BasicRecordingAuthorization {
        fileprivate let service: IChartTelemetryService
        fileprivate let consent: IChartTelemetryConsentSnapshot

        var isCurrent: Bool {
            admission.configuredService === service && service.consentStore.trySnapshotForScheduling() == consent
        }
    }

    static func basicRecordingAuthorization() -> BasicRecordingAuthorization? {
        guard let service = admission.configuredService,
              let consent = service.consentStore.trySnapshotForScheduling(), consent.isGranted else { return nil }
        return BasicRecordingAuthorization(service: service, consent: consent)
    }

    static var isBasicRecordingEnabled: Bool { basicRecordingAuthorization() != nil }

    static func record(_ eventName: String, properties: IChartTelemetryProperties = [:], chartID: UUID? = nil) {
        admission.record(eventName, properties: properties)
    }

    struct DiagnosticAuthorization {
        var isCurrent: Bool { false }
        func matches(_ other: Self) -> Bool { false }
    }

    static func diagnosticAuthorization() -> DiagnosticAuthorization? { nil }

    static func recordDeferredDiagnostic(
        _ eventName: String, chartID: UUID?, authorization: DiagnosticAuthorization,
        onCompletion: @escaping @Sendable () -> Void = {},
        properties: @escaping @Sendable () -> IChartTelemetryProperties?
    ) {
        // Complete an obsolete caller's bookkeeping without evaluating its
        // capture closure or retaining charts/drawings in background work.
        onCompletion()
    }

    static func flush() { admission.requestFlush() }

    static func flushPendingEventsIfNeeded() async { admission.requestFlush() }
}

/// One utility drain owns the bounded buffer. No closure supplied by a canvas
/// or persistence caller crosses this boundary, only sanitized scalar values.
final class IChartTelemetryAdmission: @unchecked Sendable {
    private enum Command {
        case event(IChartTelemetryService, IChartTelemetryConsentSnapshot, String, IChartTelemetryProperties)
        case flush(IChartTelemetryService, IChartTelemetryConsentSnapshot)
    }

    private let lock = NSLock()
    private let capacity: Int
    private var service: IChartTelemetryService?
    private var commands: [Command] = []
    private var isDraining = false
    private var flushQueued = false
    private var consentRefreshQueued = false
    private var isRefreshingConsent = false
    private var dropped = 0

    init(capacity: Int = 64) { self.capacity = max(1, min(capacity, 64)) }

    var configuredService: IChartTelemetryService? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return service
    }

    var pendingCount: Int {
        guard lock.try() else { return 0 }
        defer { lock.unlock() }
        return commands.count
    }

    var droppedCount: Int {
        guard lock.try() else { return 0 }
        defer { lock.unlock() }
        return dropped
    }

    func configure(_ service: IChartTelemetryService?) {
        // Configuration happens outside product work. Admission never holds
        // this lock while accessing an actor, preferences, storage or network.
        lock.lock()
        self.service = service
        commands.removeAll(keepingCapacity: true)
        flushQueued = false
        consentRefreshQueued = false
        lock.unlock()
    }

    func record(_ name: String, properties: IChartTelemetryProperties) {
        guard IChartTelemetryPrivacy.allowedEventNames.contains(name) else { return }
        let values = IChartTelemetryPrivacy.sanitizedProperties(properties, forEventName: name)
        guard lock.try() else { return }
        guard let service, let consent = service.consentStore.trySnapshotForScheduling(), consent.isGranted else {
            lock.unlock()
            return
        }
        appendLocked(.event(service, consent, name, values))
    }

    func setConsentGranted(_ isGranted: Bool) {
        lock.lock()
        let configured = service
        lock.unlock()
        (configured?.consentStore ?? .shared).setConsentGranted(isGranted)
        requestConsentRefresh()
    }

    func requestFlush() {
        guard lock.try() else { return }
        guard !flushQueued, let service,
              let consent = service.consentStore.trySnapshotForScheduling(), consent.isGranted else {
            lock.unlock()
            return
        }
        guard commands.count < capacity else { dropLocked(); return }
        flushQueued = true
        appendLocked(.flush(service, consent))
    }

    func requestConsentRefresh() {
        // This coalesced control lane can cancel a request while the data drain
        // awaits HTTP. The admission lock itself never encloses optional I/O.
        lock.lock()
        guard service != nil else { lock.unlock(); return }
        consentRefreshQueued = true
        let startsRefresh = !isRefreshingConsent
        isRefreshingConsent = true
        lock.unlock()
        if startsRefresh {
            Task.detached(priority: .utility) {
                while let service = self.nextConsentRefresh() { await service.consentDidChange() }
            }
        }
    }

    private func nextConsentRefresh() -> IChartTelemetryService? {
        lock.lock()
        defer { lock.unlock() }
        guard consentRefreshQueued else { isRefreshingConsent = false; return nil }
        consentRefreshQueued = false
        guard let service else { isRefreshingConsent = false; return nil }
        return service
    }

    private func dropLocked() {
        dropped = min(1_000_000_000, dropped + 1)
        lock.unlock()
    }

    private func appendLocked(_ command: Command) {
        guard commands.count < capacity else { dropLocked(); return }
        commands.append(command)
        let startsDrain = !isDraining
        isDraining = true
        lock.unlock()
        if startsDrain {
            Task.detached(priority: .utility) { await self.drain() }
        }
    }

    private func nextCommand() -> Command? {
        lock.lock()
        defer { lock.unlock() }
        guard !commands.isEmpty else { isDraining = false; return nil }
        let command = commands.removeFirst()
        if case .flush = command { flushQueued = false }
        return command
    }

    private func drain() async {
        while let command = nextCommand() {
            switch command {
            case let .event(service, consent, name, values):
                await service.record(name, properties: values, expectedConsent: consent)
            case let .flush(service, consent):
                await service.flushIfNeeded(expectedConsent: consent)
            }
        }
    }
}

actor IChartTelemetryService {
    private enum ConsentResetRetryOutcome: Sendable { case pending, finished, deadlineExceeded }
    nonisolated let consentStore: IChartTelemetryConsentStore
    private nonisolated let recordingObserver: (@Sendable (IChartTelemetryRecordingTrace) -> Void)?
    private let sleepForConsentResetRetry: @Sendable (UInt64) async throws -> Void
    private let consentResetRetryUptime: @Sendable () -> TimeInterval
    private let endpointURL: URL
    private let publishableKey: String
    private let queueStore: IChartTelemetryQueueStore
    private let suppliedInstallationID: UUID?
    private let suppliedSessionID: UUID?
    private var installationID: UUID?
    private var sessionID: UUID?
    private let urlSession: URLSession
    private let now: () -> Date
    private var isFlushing = false
    private var lastFlushAttemptAt: Date?
    private var observedConsent: IChartTelemetryConsentSnapshot?
    private var didInitialize = false
    private var inFlightRequest: IChartTelemetryRequest?
    private var consentResetRetryTask: Task<Void, Never>?
    private var consentResetRetryEpoch: IChartTelemetryConsentSnapshot?
    private var consentResetRetryID: UUID?

    private static let consentResetRetryDelays: [UInt64] = [10_000_000, 25_000_000, 50_000_000,
        100_000_000, 200_000_000, 400_000_000, 800_000_000]
    private static let consentResetRetryBudget: TimeInterval = 2

    private static let opportunisticFlushInterval: TimeInterval = 20
    private static let opportunisticFlushQueueThreshold = 8
    private static let maxBatchSize = 40
    private static let maximumBatchBodyBytes = 120_000
    private static let maximumBatchesPerFlush = 4

    init(
        endpointURL: URL,
        publishableKey: String,
        sessionStore: IChartSupabaseSessionStore?,
        queueStore: IChartTelemetryQueueStore,
        installationID: UUID? = nil,
        sessionID: UUID? = nil,
        consentStore: IChartTelemetryConsentStore = .shared,
        urlSession: URLSession = .shared,
        now: @escaping () -> Date = Date.init,
        recordingObserver: (@Sendable (IChartTelemetryRecordingTrace) -> Void)? = nil,
        sleepForConsentResetRetry: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        },
        consentResetRetryUptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.endpointURL = endpointURL
        self.publishableKey = publishableKey
        self.queueStore = queueStore
        self.consentStore = consentStore
        suppliedInstallationID = installationID
        suppliedSessionID = sessionID
        self.installationID = installationID
        self.sessionID = sessionID
        self.urlSession = urlSession
        self.now = now
        self.recordingObserver = recordingObserver
        self.sleepForConsentResetRetry = sleepForConsentResetRetry
        self.consentResetRetryUptime = consentResetRetryUptime

    }

    static func live(
        clients: IChartSupabaseClients?,
        configuration: IChartSupabaseConfiguration? = IChartSupabaseConfiguration.current(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> IChartTelemetryService? {
        guard Self.allowsLiveTelemetry(environment: environment),
              let configuration else {
            return nil
        }

        return IChartTelemetryService(
            endpointURL: configuration.url
                .appendingPathComponent("functions")
                .appendingPathComponent("v1")
                .appendingPathComponent("app-telemetry-ingest"),
            publishableKey: configuration.publishableKey,
            sessionStore: clients?.sessionStore,
            queueStore: .live()
        )
    }

    static func allowsLiveTelemetry(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        ![
            "XCTestBundlePath",
            "XCTestConfigurationFilePath",
            "XCInjectBundleInto"
        ].contains { key in
            guard let value = environment[key] else {
                return false
            }

            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Runs serially on the telemetry actor, outside canvas callbacks. Both
    /// sides of a potentially expensive comparison retain the original grant.
    func recordDiagnosticObservation(
        _ eventName: String, chartID: UUID?, expectedConsent: IChartTelemetryConsentSnapshot,
        traceID: UUID? = nil,
        properties: @Sendable () -> IChartTelemetryProperties?
    ) async {
        // Live/content diagnostics are retired. In particular, do not invoke
        // the supplied closure even if the current consent is granted.
        return
    }

    func consentDidChange() {
        let consent = consentStore.cachedSnapshotForScheduling
        invalidateConsentResetRetry(unlessMatching: consent)
        if !consent.isGranted { inFlightRequest?.cancel() }
        _ = preparedConsent()
        scheduleConsentResetRetry(for: consent)
    }

    func record(
        _ eventName: String,
        properties: IChartTelemetryProperties = [:],
        chartID: UUID? = nil,
        expectedConsent: IChartTelemetryConsentSnapshot? = nil,
        traceID: UUID? = nil
    ) async {
        let traceID = traceID ?? recordingTraceID()
        traceRecording(.recordEntered, callID: traceID, eventName: eventName)
        guard let consent = preparedConsent(traceID: traceID, eventName: eventName) else {
            traceRecording(.consentPreparationRejected, callID: traceID, eventName: eventName)
            return
        }
        guard expectedConsent == nil || expectedConsent == consent else {
            traceRecording(.expectedConsentRejected, callID: traceID, eventName: eventName)
            return
        }
        guard IChartTelemetryPrivacy.allowedEventNames.contains(eventName) else {
            traceRecording(.eventNameRejected, callID: traceID, eventName: eventName)
            return
        }
        guard let context = currentContext(for: consent, traceID: traceID, eventName: eventName) else {
            return
        }

        var enrichedProperties = properties
        enrichedProperties["build_source"] = .string(IChartTelemetryBuildSource.value)
        if eventName == "app.launched", let health = try? queueStore.healthSnapshot() {
            // Report cumulative prior-run collection gaps once on launch. These
            // are health totals, not a fresh incident for each positive value.
            let maximumCount = 1_000_000_000_000
            enrichedProperties["queue_overflow_count"] = .int(min(maximumCount, health.overflowDroppedEventCount))
            enrichedProperties["queue_rejected_count"] = .int(min(
                maximumCount,
                min(maximumCount, health.serverRejectedEventCount) + min(maximumCount, health.locallyRejectedEventCount)
            ))
            enrichedProperties["queue_quarantine_overflow_count"] = .int(min(maximumCount, health.quarantineOverflowDroppedEventCount))
            enrichedProperties["queue_unacknowledged_batch_count"] = .int(min(maximumCount, health.unacknowledgedBatchCount))
        }
        let sanitizedProperties = IChartTelemetryPrivacy.sanitizedProperties(
            enrichedProperties,
            forEventName: eventName
        )

        let event = IChartTelemetryEvent(
            clientEventID: UUID(),
            eventName: eventName,
            occurredAt: now(),
            installationID: context.installationID,
            sessionID: context.sessionID,
            appVersion: context.appVersion,
            buildNumber: context.buildNumber,
            platform: context.platform,
            osVersion: context.osVersion,
            deviceModel: context.deviceModel,
            localeLanguage: context.localeLanguage,
            timeZoneOffsetMinutes: context.timeZoneOffsetMinutes,
            properties: sanitizedProperties
        )

        do {
            guard try consentStore.performIfGranted(matching: consent, onDenied: { denial in
                self.traceRecording(.queueAdmissionRejected, callID: traceID, eventName: eventName,
                                    admissionDenial: denial)
            }, {
                try queueStore.append(event)
                return true
            }) == true else {
                return
            }
        } catch {
            traceRecording(.queueAppendFailed, callID: traceID, eventName: eventName, error: error)
            return
        }
        traceRecording(.queueAppended, callID: traceID, eventName: eventName)

        if shouldFlushOpportunistically() {
            await flush(expectedConsent: consent)
        }
    }

    func flushIfNeeded(expectedConsent: IChartTelemetryConsentSnapshot? = nil) async {
        guard let consent = preparedConsent(),
              expectedConsent == nil || expectedConsent == consent,
              shouldFlushOpportunistically() else {
            return
        }
        await flush(expectedConsent: consent)
    }

    func flush(expectedConsent: IChartTelemetryConsentSnapshot? = nil) async {
        guard let consent = preparedConsent(),
              expectedConsent == nil || expectedConsent == consent,
              !Task.isCancelled, !isFlushing else {
            return
        }

        isFlushing = true
        lastFlushAttemptAt = now()
        defer { isFlushing = false }

        // Catch up after an offline period without leaving all but the first
        // batch waiting for another editor event. Bound each attempt so a slow
        // connection or continuous writing cannot make one flush run forever.
        for _ in 0..<Self.maximumBatchesPerFlush {
            guard !Task.isCancelled, consentStore.snapshot == consent else {
                _ = preparedConsent()
                return
            }
            do {
                guard let batch = try nextBatch(for: consent) else {
                    return
                }
                let responseData = try await send(body: batch.body, consent: consent)
                let acknowledgment = IChartTelemetryAcknowledgment.parse(
                    responseData,
                    sentIDs: Set(batch.events.map(\.clientEventID))
                )
                // Reload before removal: recording can append while send awaits.
                guard try consentStore.performIfGranted(matching: consent, {
                    if let acknowledgment {
                        try queueStore.acknowledge(
                            acceptedIDs: acknowledgment.acceptedIDs,
                            rejectedIDs: acknowledgment.rejectedIDs
                        )
                    } else {
                        try queueStore.recordUnacknowledgedBatch()
                    }
                    return true
                }) == true else {
                    _ = preparedConsent()
                    return
                }
                guard let acknowledgment,
                      !acknowledgment.acceptedIDs.isEmpty || !acknowledgment.rejectedIDs.isEmpty else {
                    return
                }
            } catch {
                // Keep the original event IDs for an idempotent later retry.
                _ = preparedConsent()
                return
            }
        }
    }

    private func nextBatch(for consent: IChartTelemetryConsentSnapshot) throws -> (events: [IChartTelemetryEvent], body: Data)? {
        guard let loadedEvents = try consentStore.performIfGranted(matching: consent, {
            try queueStore.retainBasicEvents()
            return try queueStore.loadEvents()
        }) else { return nil }
        let queuedEvents = loadedEvents.prefix(Self.maxBatchSize)
        guard !queuedEvents.isEmpty else {
            return nil
        }

        guard let context = currentContext(for: consent) else { return nil }
        var byteCount = try Self.encoder.encode(
            IChartTelemetryBatch(context: context, events: [])
        ).count
        var events: [IChartTelemetryEvent] = []
        for event in queuedEvents {
            let addedBytes = try Self.encoder.encode(event).count + (events.isEmpty ? 0 : 1)
            guard byteCount + addedBytes <= Self.maximumBatchBodyBytes else {
                break
            }
            events.append(event)
            byteCount += addedBytes
        }
        guard !events.isEmpty else {
            return nil
        }

        let body = try Self.encoder.encode(IChartTelemetryBatch(context: context, events: events))
        guard body.count <= Self.maximumBatchBodyBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        return (events, body)
    }

    private func send(body: Data, consent: IChartTelemetryConsentSnapshot) async throws -> Data {
        guard consentStore.snapshot == consent, !Task.isCancelled else { throw CancellationError() }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = body

        let pendingRequest = IChartTelemetryRequest()
        inFlightRequest = pendingRequest
        defer {
            if inFlightRequest === pendingRequest { inFlightRequest = nil }
        }
        let delivery: (Data, URLResponse) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let started = consentStore.performIfGranted(matching: consent) {
                    let task = urlSession.dataTask(with: request) { data, response, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let response {
                            continuation.resume(returning: (data ?? Data(), response))
                        } else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                        }
                    }
                    pendingRequest.start(task)
                    return true
                }
                if started != true { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            pendingRequest.cancel()
        }
        guard let httpResponse = delivery.1 as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return delivery.0
    }

    private func shouldFlushOpportunistically() -> Bool {
        let eventCount = (try? queueStore.loadEvents().count) ?? 0
        if eventCount >= Self.opportunisticFlushQueueThreshold {
            return true
        }

        guard let lastFlushAttemptAt else {
            return true
        }

        return now().timeIntervalSince(lastFlushAttemptAt) >= Self.opportunisticFlushInterval
    }

    private func currentContext(for consent: IChartTelemetryConsentSnapshot, traceID: UUID? = nil,
                                eventName: String = "") -> IChartTelemetryContext? {
        traceRecording(.identityRequested, callID: traceID, eventName: eventName)
        guard let resolvedID = installationID ?? consentStore.installationID(for: consent) else {
            traceRecording(.identityUnavailable, callID: traceID, eventName: eventName)
            return nil
        }
        traceRecording(.identityResolved, callID: traceID, eventName: eventName)
        let context = consentStore.performIfGranted(matching: consent, onDenied: { denial in
            self.traceRecording(.contextAdmissionRejected, callID: traceID, eventName: eventName,
                                admissionDenial: denial)
        }) {
            installationID = resolvedID
            let resolvedSessionID = sessionID ?? UUID()
            sessionID = resolvedSessionID
            return IChartTelemetryContext(
                installationID: resolvedID,
                sessionID: resolvedSessionID,
                appVersion: Self.bundleValue(for: "CFBundleShortVersionString", fallback: "unknown"),
                buildNumber: Self.bundleValue(for: "CFBundleVersion", fallback: "unknown"),
                platform: Self.platformName,
                osVersion: Self.osVersion,
                deviceModel: Self.deviceModel,
                localeLanguage: "unknown",
                timeZoneOffsetMinutes: 0
            )
        }
        if context != nil { traceRecording(.contextReady, callID: traceID, eventName: eventName) }
        return context
    }

    /// Called only on this worker actor. Startup never awaits queue migration.
    func initialize() { _ = preparedConsent() }

    private func initializeIfNeeded() -> Bool {
        guard !didInitialize else { return true }
        let consent = consentStore.snapshot
        do {
            if consent.isGranted && !consentStore.requiresQueueReset {
                do { try queueStore.retainBasicEvents() }
                catch { try queueStore.clear() }
                observedConsent = consent
            }
            didInitialize = true
            return true
        } catch {
            return false
        }
    }

    private func preparedConsent(traceID: UUID? = nil, eventName: String = "") -> IChartTelemetryConsentSnapshot? {
        guard initializeIfNeeded() else { return nil }
        let consent = consentStore.snapshot
        invalidateConsentResetRetry(unlessMatching: consentStore.cachedSnapshotForScheduling)
        if consent != observedConsent || !consent.isGranted || consentStore.requiresQueueReset {
            guard applyConsentReset(for: consent, traceID: traceID, eventName: eventName) else {
                scheduleConsentResetRetry(for: consent)
                return nil
            }
        }
        return consent.isGranted ? consent : nil
    }

    func applyConsentReset(for consent: IChartTelemetryConsentSnapshot,
                           traceID: UUID? = nil, eventName: String = "") -> Bool {
        guard consentStore.cachedSnapshotForScheduling == consent else { return false }
        let resetTraceID = traceID ?? recordingTraceID()
        traceRecording(.queueResetStarted, callID: resetTraceID, eventName: eventName)
        inFlightRequest?.cancel()
        do {
            guard try consentStore.clearQueuedEvents(matching: consent, {
                try queueStore.clear()
            }) else {
                traceRecording(.queueResetRejected, callID: resetTraceID, eventName: eventName)
                return false
            }
        } catch {
            traceRecording(.queueResetFailed, callID: resetTraceID, eventName: eventName, error: error)
            return false
        }
        installationID = suppliedInstallationID
        sessionID = suppliedSessionID
        lastFlushAttemptAt = nil
        observedConsent = consent
        cancelConsentResetRetry(matching: consent)
        traceRecording(.queueResetCompleted, callID: resetTraceID, eventName: eventName)
        return true
    }

    private func needsConsentReset(matching consent: IChartTelemetryConsentSnapshot) -> Bool {
        guard consentStore.cachedSnapshotForScheduling == consent else { return false }
        // The published mirror can precede the durable reset marker. A changed
        // epoch remains pending even before that marker has reached storage.
        return observedConsent != consent || consentStore.requiresQueueReset
    }

    private func invalidateConsentResetRetry(unlessMatching consent: IChartTelemetryConsentSnapshot) {
        guard let epoch = consentResetRetryEpoch, epoch != consent else { return }
        cancelConsentResetRetry(matching: epoch)
    }

    private func cancelConsentResetRetry(matching consent: IChartTelemetryConsentSnapshot) {
        guard consentResetRetryEpoch == consent else { return }
        consentResetRetryTask?.cancel()
        consentResetRetryTask = nil
        consentResetRetryEpoch = nil
        consentResetRetryID = nil
    }

    private func scheduleConsentResetRetry(for consent: IChartTelemetryConsentSnapshot) {
        // An initializer migration failure is not evidence of a consent reset;
        // valid unsent events must survive until ordinary initialization works.
        guard didInitialize, needsConsentReset(matching: consent) else { return }
        if consentResetRetryEpoch == consent, consentResetRetryTask != nil { return }
        invalidateConsentResetRetry(unlessMatching: consent)
        let id = UUID()
        let sleep = sleepForConsentResetRetry
        let uptime = consentResetRetryUptime
        let deadline = uptime() + Self.consentResetRetryBudget
        let observer = recordingObserver
        consentResetRetryEpoch = consent
        consentResetRetryID = id
        consentResetRetryTask = Task.detached(priority: .utility) { [weak self] in
            defer {
                // This reports the real worker exit, including a cancelled
                // noncooperative fixture sleeper, rather than handle removal.
                observer?(IChartTelemetryRecordingTrace(callID: id, eventName: "", stage: .queueResetRetryEnded,
                    errorDomain: nil, errorCode: nil, admissionDenial: nil))
            }
            var exhausted = true
            retryLoop: for delay in Self.consentResetRetryDelays {
                guard !Task.isCancelled else { exhausted = false; break }
                guard uptime() < deadline else { break }
                do { try await sleep(delay) }
                catch { exhausted = false; break }
                guard !Task.isCancelled else { exhausted = false; break }
                guard let outcome = await self?.performConsentResetRetry(matching: consent, id: id, deadline: deadline) else {
                    exhausted = false
                    break
                }
                switch outcome {
                case .pending: continue
                case .finished: exhausted = false; break retryLoop
                case .deadlineExceeded: break retryLoop
                }
            }
            await self?.finishConsentResetRetry(matching: consent, id: id, exhausted: exhausted)
        }
        traceRecording(.queueResetRetryScheduled, callID: id, eventName: "")
    }

    private func performConsentResetRetry(matching consent: IChartTelemetryConsentSnapshot,
                                         id: UUID, deadline: TimeInterval) -> ConsentResetRetryOutcome {
        guard consentResetRetryID == id, consentResetRetryEpoch == consent, !Task.isCancelled,
              consentStore.cachedSnapshotForScheduling == consent else { return .finished }
        guard consentResetRetryUptime() < deadline else { return .deadlineExceeded }
        guard needsConsentReset(matching: consent) else { return .finished }
        // Never initialize, migrate, adopt a newer epoch or retry a send here.
        // The captured epoch also reaches the authoritative clear guard.
        return applyConsentReset(for: consent, traceID: id) ? .finished : .pending
    }

    private func finishConsentResetRetry(matching consent: IChartTelemetryConsentSnapshot,
                                        id: UUID, exhausted: Bool) {
        guard consentResetRetryID == id, consentResetRetryEpoch == consent else { return }
        consentResetRetryTask = nil
        consentResetRetryEpoch = nil
        consentResetRetryID = nil
        if exhausted, needsConsentReset(matching: consent) {
            // Budget limits new attempts, not preemption of existing lock/I/O.
            // A durable reset marker survives failure for later startup/work.
            traceRecording(.queueResetRetryExhausted, callID: id, eventName: "")
        }
    }

    nonisolated func recordingTraceID() -> UUID? {
        recordingObserver == nil ? nil : UUID()
    }

    nonisolated func traceRecording(_ stage: IChartTelemetryRecordingTrace.Stage,
                                   callID: UUID?, eventName: String, error: Error? = nil,
                                   admissionDenial: IChartTelemetryConsentAdmissionDenial? = nil) {
        guard let callID, let recordingObserver else { return }
        let failure = error.map { $0 as NSError }
        recordingObserver(.init(callID: callID, eventName: String(eventName.prefix(80)), stage: stage,
                                errorDomain: failure.map { String($0.domain.prefix(80)) },
                                errorCode: failure?.code, admissionDenial: admissionDenial))
    }

    private static func bundleValue(for key: String, fallback: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static var platformName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "unknown"
        #endif
    }

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var deviceModel: String {
        #if os(iOS)
        return "iOS device"
        #elseif os(macOS)
        return "Mac"
        #else
        return "unknown"
        #endif
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private final class IChartTelemetryRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func start(_ task: URLSessionDataTask) {
        lock.lock()
        defer { lock.unlock() }
        self.task = task
        if isCancelled { task.cancel() } else { task.resume() }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        task?.cancel()
    }
}

/// The HTTP status alone does not acknowledge individual telemetry records.
/// Older ingest versions are compatible only when their full-success counts
/// account for the entire batch; partial counts cannot identify safe removals.
struct IChartTelemetryAcknowledgment {
    let acceptedIDs: Set<UUID>
    let rejectedIDs: Set<UUID>

    static func parse(_ data: Data, sentIDs: Set<UUID>) -> Self? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acceptedFlag = body["accepted"] as? NSNumber,
              CFGetTypeID(acceptedFlag) == CFBooleanGetTypeID(),
              acceptedFlag.boolValue else { return nil }
        if body["accepted_event_ids"] != nil {
            guard let accepted = parsedIDs(body["accepted_event_ids"]),
                  let rejected = parsedIDs(body["rejected_event_ids"] ?? [String]()),
                  accepted.isSubset(of: sentIDs), rejected.isSubset(of: sentIDs),
                  accepted.isDisjoint(with: rejected) else { return nil }
            if let storedCount = body["stored_count"], exactCount(storedCount) != accepted.count { return nil }
            if let rejectedCount = body["rejected_count"], exactCount(rejectedCount) != rejected.count { return nil }
            return Self(acceptedIDs: accepted, rejectedIDs: rejected)
        }
        guard exactCount(body["stored_count"]) == sentIDs.count,
              exactCount(body["rejected_count"]) == 0 else { return nil }
        return Self(acceptedIDs: sentIDs, rejectedIDs: [])
    }

    private static func parsedIDs(_ value: Any?) -> Set<UUID>? {
        guard let values = value as? [String] else { return nil }
        var ids = Set<UUID>()
        for value in values {
            guard let id = UUID(uuidString: value), ids.insert(id).inserted else { return nil }
        }
        return ids
    }

    private static func exactCount(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue >= 0,
              number.doubleValue.rounded(.down) == number.doubleValue,
              number.doubleValue <= Double(Int.max) else { return nil }
        return number.intValue
    }
}

struct IChartTelemetryQueueHealth: Equatable {
    let pendingEventCount: Int
    let quarantinedEventCount: Int
    let overflowDroppedEventCount: Int
    let quarantineOverflowDroppedEventCount: Int
    let serverRejectedEventCount: Int
    let locallyRejectedEventCount: Int
    let unacknowledgedBatchCount: Int
}

private struct IChartTelemetryQueueState: Codable {
    var schemaVersion = 1
    var events: [IChartTelemetryEvent] = []
    var quarantinedEvents: [IChartTelemetryEvent] = []
    var overflowDroppedEventCount = 0
    var quarantineOverflowDroppedEventCount = 0
    var serverRejectedEventCount = 0
    var locallyRejectedEventCount = 0
    var unacknowledgedBatchCount = 0
}

final class IChartTelemetryQueueStore {
    private let url: URL
    private let fileManager: FileManager
    private let maxEventCount: Int
    private static let maximumFileBytes = 512_000

    init(url: URL, fileManager: FileManager = .default, maxEventCount: Int = 1_000) {
        self.url = url
        self.fileManager = fileManager
        self.maxEventCount = max(1, min(maxEventCount, 1_000))
    }

    static func live(fileManager: FileManager = .default) -> IChartTelemetryQueueStore {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL.appendingPathComponent("iChart", isDirectory: true)
        return IChartTelemetryQueueStore(
            url: baseDirectory.appendingPathComponent("telemetry-queue.json"),
            fileManager: fileManager
        )
    }

    func append(_ event: IChartTelemetryEvent) throws {
        var state = try loadState()
        state.events.append(event)
        if state.events.count > maxEventCount {
            state.overflowDroppedEventCount += state.events.count - maxEventCount
            state.events = Array(state.events.suffix(maxEventCount))
        }
        try save(state)
    }

    func loadEvents() throws -> [IChartTelemetryEvent] {
        try loadState().events
    }

    func loadQuarantinedEvents() throws -> [IChartTelemetryEvent] {
        try loadState().quarantinedEvents
    }

    func healthSnapshot() throws -> IChartTelemetryQueueHealth {
        let state = try loadState()
        return IChartTelemetryQueueHealth(
            pendingEventCount: state.events.count,
            quarantinedEventCount: state.quarantinedEvents.count,
            overflowDroppedEventCount: state.overflowDroppedEventCount,
            quarantineOverflowDroppedEventCount: state.quarantineOverflowDroppedEventCount,
            serverRejectedEventCount: state.serverRejectedEventCount,
            locallyRejectedEventCount: state.locallyRejectedEventCount,
            unacknowledgedBatchCount: state.unacknowledgedBatchCount
        )
    }

    func acknowledge(acceptedIDs: Set<UUID>, rejectedIDs: Set<UUID>) throws {
        var state = try loadState()
        let rejectedEvents = state.events.filter { rejectedIDs.contains($0.clientEventID) }
        state.serverRejectedEventCount += rejectedEvents.count
        state.quarantinedEvents.append(contentsOf: rejectedEvents)
        let quarantineLimit = min(maxEventCount, 100)
        if state.quarantinedEvents.count > quarantineLimit {
            state.quarantineOverflowDroppedEventCount += state.quarantinedEvents.count - quarantineLimit
            state.quarantinedEvents = Array(state.quarantinedEvents.suffix(quarantineLimit))
        }
        state.events.removeAll { acceptedIDs.contains($0.clientEventID) || rejectedIDs.contains($0.clientEventID) }
        try save(state)
    }

    /// Legacy optional diagnostics are filtered on the worker before upload.
    /// Keeping the original IDs preserves idempotent retries and acknowledgments.
    func retainBasicEvents() throws {
        var state = try loadState()
        let retained = state.events.compactMap { event -> IChartTelemetryEvent? in
            guard IChartTelemetryPrivacy.allowedEventNames.contains(event.eventName) else { return nil }
            let platform: String
            let device: String
            switch event.platform {
            case "iOS", "iPadOS":
                platform = "iOS"
                device = "iOS device"
            case "macOS":
                platform = "macOS"
                device = "Mac"
            default:
                platform = "unknown"
                device = "unknown"
            }
            return IChartTelemetryEvent(clientEventID: event.clientEventID, eventName: event.eventName,
                occurredAt: event.occurredAt, installationID: event.installationID, sessionID: event.sessionID,
                appVersion: event.appVersion, buildNumber: event.buildNumber, platform: platform,
                osVersion: event.osVersion, deviceModel: device,
                localeLanguage: "unknown", timeZoneOffsetMinutes: 0,
                properties: IChartTelemetryPrivacy.sanitizedProperties(event.properties, forEventName: event.eventName))
        }
        guard retained != state.events || !state.quarantinedEvents.isEmpty else { return }
        state.events = retained
        state.quarantinedEvents = []
        try save(state)
    }

    func recordLocalRejection() throws {
        var state = try loadState()
        state.locallyRejectedEventCount += 1
        try save(state)
    }

    func recordUnacknowledgedBatch() throws {
        var state = try loadState()
        state.unacknowledgedBatchCount += 1
        try save(state)
    }

    private func loadState() throws -> IChartTelemetryQueueState {
        guard fileManager.fileExists(atPath: url.path) else {
            return IChartTelemetryQueueState()
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
        guard data.count <= Self.maximumFileBytes else { throw CocoaError(.fileReadCorruptFile) }
        guard !data.isEmpty else {
            return IChartTelemetryQueueState()
        }
        // Existing installs persist a plain array. It is migrated atomically
        // on the next mutation, retaining every original event identifier.
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
            return IChartTelemetryQueueState(events: try Self.decoder.decode([IChartTelemetryEvent].self, from: data))
        }
        let state = try Self.decoder.decode(IChartTelemetryQueueState.self, from: data)
        guard state.schemaVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return state
    }

    func removeEvents(withIDs ids: Set<UUID>) throws {
        var state = try loadState()
        state.events.removeAll { ids.contains($0.clientEventID) }
        try save(state)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func save(_ state: IChartTelemetryQueueState) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if state.events.isEmpty && state.quarantinedEvents.isEmpty
            && state.overflowDroppedEventCount == 0 && state.quarantineOverflowDroppedEventCount == 0
            && state.serverRejectedEventCount == 0 && state.locallyRejectedEventCount == 0
            && state.unacknowledgedBatchCount == 0 {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }

        let data = try Self.encoder.encode(state)
        guard data.count <= Self.maximumFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum IChartTelemetryPrivacy {
    static let allowedEventNames: Set<String> = [
        "app.launched", "app.bootstrap_completed", "app.error",
        "chord.recognition_failed", "chord.preview_rendered", "chord.rendered_correction_applied",
        "pdf.export_succeeded", "pdf.export_failed",
        "cloud.push_succeeded", "cloud.push_failed", "cloud.restore_succeeded", "cloud.restore_failed",
        "auth.signup_failed", "auth.signin_failed", "auth.verification_email_failed",
        "auth.callback_failed", "auth.password_reset_failed",
        "subscription.purchase_failed", "subscription.restore_failed",
        "forum.post_failed", "forum.pdf_download_failed"
    ]

    private static let errorCodes: Set<String> = [
        "unknown", "library_load_failed", "library_save_failed", "load_error", "save_error", "render_error", "export_error", "reader_error", "recognition_error",
        "unsupported_candidate", "missing_measure", "invalid_drawing_data", "weak_batch_targets", "weak_single_target", "no_recognition_target",
        "authentication", "timeout", "server", "sync_error", "offline", "network", "permission",
        "invalid_credentials", "email_not_confirmed", "password_error", "auth_error",
        "purchase_error", "restore_error", "forum_error", "download_error", "storage_error"
    ]
    private static let operations: Set<String> = [
        "launch", "library_load", "library_save", "load", "save", "write", "recognize", "render", "export", "backup", "restore",
        "signup", "signin", "verification", "password_reset", "purchase", "forum", "download", "unknown"
    ]
    private static let countKeys = [
        "rendered_count", "candidate_count", "queue_overflow_count", "queue_rejected_count",
        "queue_quarantine_overflow_count", "queue_unacknowledged_batch_count"
    ]

    static func hasRequiredContractFields(_ properties: IChartTelemetryProperties) -> Bool { false }

    /// Iterate a fixed, small set of keys. Unknown keys, identities, free text,
    /// chart context and ink measurements are neither copied nor serialized.
    static func sanitizedProperties(_ properties: IChartTelemetryProperties,
                                    forEventName eventName: String? = nil) -> IChartTelemetryProperties {
        if let eventName, !allowedEventNames.contains(eventName) { return [:] }
        var values: IChartTelemetryProperties = [:]
        if case .string(let code) = properties["error_code"] {
            values["error_code"] = .string(errorCodes.contains(code) ? code : "unknown")
        }
        // The existing anonymous ingest reserves `operation` for legacy
        // feature contracts. Send the fixed basic category through its
        // generic `source` field, including when a queued event is filtered
        // again before upload.
        if case .string(let operation) = properties["operation"] ?? properties["source"], operations.contains(operation) {
            values["source"] = .string(operation)
        }
        if case .string(let result) = properties["result"], ["succeeded", "failed", "rendered"].contains(result) {
            values["result"] = .string(result)
        }
        if case .string(let source) = properties["build_source"], ["debug_build", "release_build"].contains(source) {
            values["build_source"] = .string(source)
        }
        if case .string(let decision) = properties["decision"] {
            let allowed = eventName == "chord.rendered_correction_applied"
                ? ["outside_candidates", "candidate_replacement", "equivalent_spelling", "display_space_mismatch"]
                : ["automatic", "confirmed", "manual", "reviewed_automatic", "rendered"]
            if allowed.contains(decision) { values["decision"] = .string(decision) }
        }
        for key in ["duration_ms", "recognition_ms"] {
            let milliseconds: Double
            switch properties[key] {
            case .int(let count): milliseconds = Double(count)
            case .double(let count): milliseconds = count
            default: continue
            }
            if milliseconds.isFinite, (0...86_400_000).contains(milliseconds) {
                values[key] = .double((milliseconds * 1_000).rounded() / 1_000)
            }
        }
        for key in countKeys {
            if case .int(let count) = properties[key], (0...1_000_000_000).contains(count) {
                values[key] = .int(count)
            }
        }
        return values
    }
}
