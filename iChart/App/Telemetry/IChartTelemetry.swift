import Foundation
import CryptoKit
import CoreFoundation

#if canImport(UIKit)
import UIKit
#endif

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

enum IChartTelemetryBuildSource {
    static var value: String {
        #if DEBUG
        "debug_build"
        #else
        "release_build"
        #endif
    }
}

enum IChartTelemetry {
    private static let lock = NSLock()
    private static var configuredService: IChartTelemetryService?

    static func configure(_ service: IChartTelemetryService?) {
        lock.lock()
        configuredService = service
        lock.unlock()
    }

    static func setConsentGranted(_ isGranted: Bool) {
        let configured = service
        (configured?.consentStore ?? .shared).setConsentGranted(isGranted)
        Task.detached(priority: .utility) {
            await configured?.consentDidChange()
        }
    }

    /// Lets diagnostic callers skip expensive read-only capture while opted out.
    static var isRecordingEnabled: Bool {
        guard let configured = service else { return false }
        return configured.consentStore.snapshot.isGranted
    }

    static func record(
        _ eventName: String,
        properties: IChartTelemetryProperties = [:],
        chartID: UUID? = nil
    ) {
        guard let service = service else {
            return
        }

        let consent = service.consentStore.snapshot
        guard consent.isGranted else {
            Task.detached(priority: .utility) { await service.consentDidChange() }
            return
        }
        Task.detached(priority: .utility) {
            await service.record(eventName, properties: properties, chartID: chartID, expectedConsent: consent)
        }
    }

    static func flush() {
        guard let service = service else {
            return
        }

        let consent = service.consentStore.snapshot
        Task.detached(priority: .utility) {
            await service.flush(expectedConsent: consent)
        }
    }

    static func flushPendingEventsIfNeeded() async {
        guard let service = service else { return }
        let consent = service.consentStore.snapshot
        await service.flushIfNeeded(expectedConsent: consent)
    }

    private static var service: IChartTelemetryService? {
        lock.lock()
        defer { lock.unlock() }
        return configuredService
    }
}

actor IChartTelemetryService {
    nonisolated let consentStore: IChartTelemetryConsentStore
    private let endpointURL: URL
    private let publishableKey: String
    private let sessionStore: IChartSupabaseSessionStore?
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
    private var inFlightRequest: IChartTelemetryRequest?

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
        now: @escaping () -> Date = Date.init
    ) {
        self.endpointURL = endpointURL
        self.publishableKey = publishableKey
        self.sessionStore = sessionStore
        self.queueStore = queueStore
        self.consentStore = consentStore
        suppliedInstallationID = installationID
        suppliedSessionID = sessionID
        self.installationID = installationID
        self.sessionID = sessionID
        self.urlSession = urlSession
        self.now = now
        let consent = consentStore.snapshot
        if consent.isGranted && !consentStore.requiresQueueReset {
            observedConsent = consent
        } else {
            // A queue from builds that collected without this explicit consent
            // must never become eligible merely because the user later opts in.
            do {
                if try consentStore.clearQueuedEvents(matching: consent, {
                    try queueStore.clear()
                }) {
                    observedConsent = consent
                } else {
                    observedConsent = nil
                }
            } catch {
                observedConsent = nil
            }
        }
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

    func consentDidChange() {
        _ = preparedConsent()
    }

    func record(
        _ eventName: String,
        properties: IChartTelemetryProperties = [:],
        chartID: UUID? = nil,
        expectedConsent: IChartTelemetryConsentSnapshot? = nil
    ) async {
        guard let consent = preparedConsent(),
              expectedConsent == nil || expectedConsent == consent,
              IChartTelemetryPrivacy.allowedEventNames.contains(eventName),
              let context = currentContext(for: consent) else {
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
        // References identify one chart only inside this consented installation.
        // Neither raw chart IDs nor content fingerprints leave the device.
        enrichedProperties.removeValue(forKey: "chart_reference")
        if let chartID {
            let key = SymmetricKey(data: Data(context.installationID.uuidString.lowercased().utf8))
            let authentication = HMAC<SHA256>.authenticationCode(
                for: Data(("ichart-chart-reference-v1:" + chartID.uuidString.lowercased()).utf8),
                using: key
            )
            enrichedProperties["chart_reference"] = .string(authentication.map { String(format: "%02x", $0) }.joined())
        }
        let sanitizedProperties = IChartTelemetryPrivacy.sanitizedProperties(
            enrichedProperties,
            forEventName: eventName
        )
        if eventName == "feature.contract_checked",
           !IChartTelemetryPrivacy.hasRequiredContractFields(sanitizedProperties) {
            try? consentStore.performIfGranted(matching: consent) {
                try queueStore.recordLocalRejection()
            }
            return
        }

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
            guard try consentStore.performIfGranted(matching: consent, {
                try queueStore.append(event)
                return true
            }) == true else { return }
        } catch {
            return
        }

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
            try queueStore.loadEvents()
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

        if let accessToken = try? await sessionStore?.accessToken(),
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

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

    private func currentContext(for consent: IChartTelemetryConsentSnapshot) -> IChartTelemetryContext? {
        guard let resolvedID = installationID ?? consentStore.installationID(for: consent) else { return nil }
        return consentStore.performIfGranted(matching: consent) {
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
                localeLanguage: Locale.current.identifier,
                timeZoneOffsetMinutes: TimeZone.current.secondsFromGMT() / 60
            )
        }
    }

    private func preparedConsent() -> IChartTelemetryConsentSnapshot? {
        let consent = consentStore.snapshot
        if consent != observedConsent || !consent.isGranted || consentStore.requiresQueueReset {
            inFlightRequest?.cancel()
            do {
                guard try consentStore.clearQueuedEvents(matching: consent, {
                    try queueStore.clear()
                }) else { return nil }
            } catch {
                return nil
            }
            installationID = suppliedInstallationID
            sessionID = suppliedSessionID
            lastFlushAttemptAt = nil
            observedConsent = consent
        }
        return consent.isGranted ? consent : nil
    }

    private static func bundleValue(for key: String, fallback: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static var platformName: String {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #else
        "macOS"
        #endif
    }

    private static var osVersion: String {
        #if canImport(UIKit)
        UIDevice.current.systemVersion
        #else
        ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private static var deviceModel: String {
        #if canImport(UIKit)
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? UIDevice.current.model
            }
        }
        #else
        Host.current().localizedName ?? "mac"
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

    init(url: URL, fileManager: FileManager = .default, maxEventCount: Int = 1_000) {
        self.url = url
        self.fileManager = fileManager
        self.maxEventCount = max(1, maxEventCount)
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

        let data = try Data(contentsOf: url)
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
    private static let maximumPropertyCount = 64

    static let allowedEventNames: Set<String> = [
        "feature.contract_checked",
        "app.launched",
        "app.bootstrap_completed",
        "app.open_chart",
        "app.error",
        "auth.bootstrap",
        "auth.state_changed",
        "auth.signup_started",
        "auth.signup_completed",
        "auth.signup_failed",
        "auth.signin_started",
        "auth.signin_completed",
        "auth.signin_failed",
        "auth.verification_email_requested",
        "auth.verification_email_failed",
        "auth.callback_received",
        "auth.callback_completed",
        "auth.callback_failed",
        "auth.password_reset_requested",
        "auth.password_reset_failed",
        "auth.signout_completed",
        "auth.account_deleted",
        "library.chart_created",
        "library.chart_deleted",
        "library.chart_duplicated",
        "library.project_created",
        "library.project_deleted",
        "library.pdf_library_opened",
        "editor.opened",
        "editor.closed",
        "editor.mode_changed",
        "editor.chart_setup_completed",
        "ink.persisted",
        "ink.normalization_applied",
        "ink.visibility_probe",
        "ink.coordinate_space_reprojected",
        "chord.recognition_proposed",
        "chord.recognition_committed",
        "chord.recognition_failed",
        "chord.confirmation_presented",
        "chord.correction_applied",
        "chord.rendered_correction_applied",
        "chord.batch_committed",
        "chord.preview_updated",
        "chord.preview_rendered",
        "chord.preview_discarded",
        "chord.preview_rewritten",
        "chord.draft_barline_added",
        "rhythm.preview_changed",
        "rhythm.confirmed",
        "pdf.export_started",
        "pdf.export_succeeded",
        "pdf.export_failed",
        "cloud.push_started",
        "cloud.push_succeeded",
        "cloud.push_failed",
        "cloud.restore_started",
        "cloud.restore_succeeded",
        "cloud.restore_failed",
        "subscription.entitlement_changed",
        "subscription.purchase_started",
        "subscription.purchase_succeeded",
        "subscription.purchase_failed",
        "subscription.restore_started",
        "subscription.restore_succeeded",
        "subscription.restore_failed",
        "forum.opened",
        "forum.post_started",
        "forum.post_succeeded",
        "forum.post_failed",
        "forum.pdf_download_started",
        "forum.pdf_download_succeeded",
        "forum.pdf_download_failed",
    ]

    private static let allowedPropertyKeys: Set<String> = [
        "actual_bytes",
        "actual_count",
        "actual_point_count",
        "build_source",
        "chart_reference",
        "content_matches",
        "contract_id",
        "contract_version",
        "expected_bytes",
        "expected_count",
        "expected_point_count",
        "operation",
        "operation_id",
        "outcome",
        "queue_overflow_count",
        "queue_rejected_count",
        "queue_quarantine_overflow_count",
        "queue_unacknowledged_batch_count",
        "app_phase",
        "auth_state",
        "alteration_issue_count",
        "batch_size",
        "build_seen",
        "canvas_alpha",
        "canvas_background_alpha",
        "canvas_bounds_height",
        "canvas_bounds_width",
        "canvas_content_scale",
        "canvas_drawing_policy",
        "canvas_is_first_responder",
        "canvas_is_hidden",
        "canvas_is_opaque",
        "canvas_override_user_interface_style",
        "canvas_superview_user_interface_style",
        "canvas_user_interaction_enabled",
        "canvas_user_interface_style",
        "canvas_window_user_interface_style",
        "candidate_count",
        "candidate_limit_issue_count",
        "barline_count",
        "barline_sequence_issue_count",
        "chart_count",
        "chart_count_after",
        "chart_count_before",
        "changed_chord_count",
        "close_race_count",
        "cloud_backed_up_count",
        "cluster_count",
        "confidence_bucket",
        "confirm_count",
        "decision",
        "dim_quality_issue_count",
        "duration_ms",
        "draft_count",
        "error_code",
        "extension_issue_count",
        "feature_area",
        "flow",
        "from_mode",
        "generated_sequence_limit_count",
        "has_mask",
        "ink_tool_mode",
        "issue_count",
        "layout_style",
        "last_stroke_to_preview_ms",
        "light_stroke_count",
        "local_chart_limit",
        "live_canvas_light_trait_guard_enabled",
        "measure_count",
        "median_opacity",
        "median_width",
        "min_opacity",
        "min_width",
        "max_opacity",
        "max_width",
        "matched_count",
        "mode",
        "no_read_count",
        "normalized_before_save",
        "normalization_needed",
        "page_count",
        "pdf_size_bucket",
        "plan",
        "point_count",
        "project_count",
        "quality_issue_count",
        "reason",
        "recognition_ms",
        "recognition_pipeline_version",
        "recognition_target_count",
        "review_candidate_count",
        "raw_candidate_count",
        "render_action",
        "rendered_count",
        "rendered_ink_light_pixel_ratio",
        "rendered_ink_median_luminance",
        "rendered_ink_sample_count",
        "repaired_no_read_count",
        "result",
        "review_duration_ms",
        "reviewed_count",
        "rewrite_outcome",
        "scope",
        "source",
        "source_coordinate_height",
        "source_coordinate_width",
        "root_accidental_issue_count",
        "root_issue_count",
        "slash_bass_issue_count",
        "stroke_color_max_luminance",
        "stroke_color_median_luminance",
        "stroke_color_min_luminance",
        "stroke_count",
        "subscription_status",
        "target",
        "tool_color_luminance",
        "tool_ink_type",
        "tool_is_inking",
        "tool_matches_persistent_ink",
        "tool_width",
        "target_coordinate_height",
        "target_coordinate_width",
        "to_mode",
        "triangle_quality_issue_count",
        "trust_corroborated_count",
        "trust_outcome",
        "trust_probe_count",
        "trust_rejected_count",
        "trust_symbol_support_count",
        "trust_validation_ms",
        "trusted_count",
        "unknown_issue_count",
        "unresolved_count",
        "user_signed_in",
        "writing_batch_id",
    ]

    private static let contractPropertyKeys: Set<String> = [
        "contract_id", "contract_version", "operation_id", "operation", "outcome", "reason",
        "build_source", "chart_reference", "expected_count", "actual_count", "expected_bytes",
        "actual_bytes", "expected_point_count", "actual_point_count", "content_matches", "duration_ms",
        "scope", "layout_style"
    ]

    private static let contractReasons: Set<String> = [
        "save_completed", "save_failed", "load_completed", "load_failed", "first_launch",
        "readback_matches", "readback_mismatch", "readback_failed", "baseline_missing", "baseline_changed",
        "reopen_matches", "reopen_mismatch", "render_complete", "render_source_missing",
        "render_incomplete_coverage", "render_unresolved", "render_empty", "render_canvas_unavailable",
        "render_repeat_review_required", "render_rejected_mutated", "render_canvas_not_cleared",
        "rotation_complete", "rotation_stroke_count_changed", "rotation_point_count_changed",
        "rotation_nonfinite_geometry", "export_completed", "export_failed"
    ]

    static func hasRequiredContractFields(_ properties: IChartTelemetryProperties) -> Bool {
        ["contract_id", "contract_version", "operation_id", "operation", "outcome", "reason", "build_source"].allSatisfy {
            properties[$0] != nil
        }
    }

    static func sanitizedProperties(
        _ properties: IChartTelemetryProperties,
        forEventName eventName: String? = nil
    ) -> IChartTelemetryProperties {
        let isContract = eventName == "feature.contract_checked"
        return Dictionary(
            uniqueKeysWithValues: properties
                .filter { allowedPropertyKeys.contains($0.key) }
                .filter { !isContract || contractPropertyKeys.contains($0.key) }
                .sorted { $0.key < $1.key }
                .prefix(maximumPropertyCount)
                .compactMap { key, value -> (String, IChartTelemetryValue)? in
                    guard let sanitized = sanitizedWorkflowValue(value, forKey: key, isContract: isContract) else {
                        return nil
                    }
                    return (String(key.prefix(64)), sanitized)
                }
        )
    }

    // These new workflow fields have narrow scalar types, so arbitrary chord
    // text cannot be smuggled through a count, duration or correlation field.
    private static func sanitizedWorkflowValue(
        _ value: IChartTelemetryValue,
        forKey key: String,
        isContract: Bool
    ) -> IChartTelemetryValue? {
        if isContract {
            switch key {
            case "reason":
                guard case .string(let string) = value, contractReasons.contains(string) else { return nil }
                return value
            case "scope":
                guard case .string(let string) = value,
                      ["library", "chart", "page", "header", "chords", "rhythm", "chord_sources", "note_sources", "roadmap_sources"].contains(string) else { return nil }
                return value
            case "layout_style":
                guard case .string(let string) = value,
                      ["leadSheet", "simpleChordSheet", "rhythmSectionSheet"].contains(string) else { return nil }
                return value
            case "duration_ms":
                let milliseconds: Double
                switch value {
                case .double(let number): milliseconds = number
                case .int(let number): milliseconds = Double(number)
                default: return nil
                }
                guard milliseconds.isFinite, (0...86_400_000).contains(milliseconds) else { return nil }
                return sanitizedValue(value)
            default: break
            }
        }
        switch key {
        case "contract_id":
            guard case .string(let string) = value,
                  ["chart.save", "chart.load", "chart.save_readback", "ink.reopen_preservation",
                   "ink.render_preservation", "ink.rotation_preservation", "chart.export"].contains(string) else { return nil }
            return value
        case "contract_version":
            guard value == .int(1) else { return nil }
            return value
        case "build_source":
            guard case .string(let string) = value,
                  ["debug_build", "release_build"].contains(string) else { return nil }
            return value
        case "outcome":
            guard case .string(let string) = value,
                  ["passed", "violated", "unknown", "protected_rejection"].contains(string) else { return nil }
            return value
        case "operation":
            if isContract {
                guard case .string(let string) = value,
                      ["save", "load", "save_readback", "reopen", "render", "rotate", "export"].contains(string) else { return nil }
            }
            return sanitizedValue(value)
        case "chart_reference":
            guard case .string(let string) = value,
                  string.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil else { return nil }
            return value
        case "expected_count", "actual_count", "expected_bytes", "actual_bytes", "expected_point_count", "actual_point_count",
             "queue_overflow_count", "queue_rejected_count", "queue_quarantine_overflow_count", "queue_unacknowledged_batch_count":
            guard case .int(let count) = value, (0...1_000_000_000_000).contains(count) else { return nil }
            return value
        case "content_matches":
            guard case .bool = value else { return nil }
            return value
        case "writing_batch_id", "operation_id":
            guard case .string(let string) = value,
                  string.range(
                    of: #"\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\z"#,
                    options: .regularExpression
                  ) != nil else {
                return nil
            }
            return .string(string.lowercased())
        case "rewrite_outcome":
            guard case .string(let string) = value,
                  ["local", "page", "discard"].contains(string) else {
                return nil
            }
            return .string(string)
        case "changed_chord_count", "repaired_no_read_count", "reviewed_count":
            guard case .int(let count) = value, (0...10_000).contains(count) else {
                return nil
            }
            return .int(count)
        case "last_stroke_to_preview_ms", "review_duration_ms":
            let milliseconds: Double
            switch value {
            case .double(let number): milliseconds = number
            case .int(let number): milliseconds = Double(number)
            default: return nil
            }
            guard milliseconds.isFinite, (0...86_400_000).contains(milliseconds) else {
                return nil
            }
            return sanitizedValue(value)
        default:
            return sanitizedValue(value)
        }
    }

    private static func sanitizedValue(_ value: IChartTelemetryValue) -> IChartTelemetryValue {
        switch value {
        case .string(let string):
            return .string(String(string.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)))
        case .double(let double):
            guard double.isFinite else {
                return .double(0)
            }
            return .double((double * 1_000).rounded() / 1_000)
        case .int, .bool:
            return value
        }
    }
}
