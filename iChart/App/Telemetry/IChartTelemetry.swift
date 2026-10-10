import Foundation

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

    static func record(_ eventName: String, properties: IChartTelemetryProperties = [:]) {
        guard let service = service else {
            return
        }

        let consent = service.consentStore.snapshot
        guard consent.isGranted else {
            Task.detached(priority: .utility) { await service.consentDidChange() }
            return
        }
        Task.detached(priority: .utility) {
            await service.record(eventName, properties: properties, expectedConsent: consent)
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
        expectedConsent: IChartTelemetryConsentSnapshot? = nil
    ) async {
        guard let consent = preparedConsent(),
              expectedConsent == nil || expectedConsent == consent,
              IChartTelemetryPrivacy.allowedEventNames.contains(eventName),
              let context = currentContext(for: consent) else {
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
            properties: IChartTelemetryPrivacy.sanitizedProperties(properties)
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
                try await send(body: batch.body, consent: consent)
                // Reload before removal: recording can append while send awaits.
                guard try consentStore.performIfGranted(matching: consent, {
                    try queueStore.removeEvents(withIDs: Set(batch.events.map(\.clientEventID)))
                    return true
                }) == true else {
                    _ = preparedConsent()
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

    private func send(body: Data, consent: IChartTelemetryConsentSnapshot) async throws {
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
        let response: URLResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let started = consentStore.performIfGranted(matching: consent) {
                    let task = urlSession.dataTask(with: request) { _, response, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let response {
                            continuation.resume(returning: response)
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
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
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

final class IChartTelemetryQueueStore {
    private let url: URL
    private let fileManager: FileManager
    private let maxEventCount: Int

    init(url: URL, fileManager: FileManager = .default, maxEventCount: Int = 1_000) {
        self.url = url
        self.fileManager = fileManager
        self.maxEventCount = maxEventCount
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
        var events = try loadEvents()
        events.append(event)
        if events.count > maxEventCount {
            events = Array(events.suffix(maxEventCount))
        }
        try save(events)
    }

    func loadEvents() throws -> [IChartTelemetryEvent] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return []
        }

        return try Self.decoder.decode([IChartTelemetryEvent].self, from: data)
    }

    func removeEvents(withIDs ids: Set<UUID>) throws {
        let remainingEvents = try loadEvents().filter { !ids.contains($0.clientEventID) }
        try save(remainingEvents)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func save(_ events: [IChartTelemetryEvent]) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if events.isEmpty {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }

        let data = try Self.encoder.encode(events)
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

    static func sanitizedProperties(_ properties: IChartTelemetryProperties) -> IChartTelemetryProperties {
        Dictionary(
            uniqueKeysWithValues: properties
                .filter { allowedPropertyKeys.contains($0.key) }
                .sorted { $0.key < $1.key }
                .prefix(maximumPropertyCount)
                .compactMap { key, value -> (String, IChartTelemetryValue)? in
                    guard let sanitized = sanitizedWorkflowValue(value, forKey: key) else {
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
        forKey key: String
    ) -> IChartTelemetryValue? {
        switch key {
        case "writing_batch_id":
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
