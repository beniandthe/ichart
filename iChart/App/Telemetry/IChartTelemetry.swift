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

enum IChartTelemetry {
    private static let lock = NSLock()
    private static var configuredService: IChartTelemetryService?

    static func configure(_ service: IChartTelemetryService?) {
        lock.lock()
        configuredService = service
        lock.unlock()
    }

    static func record(_ eventName: String, properties: IChartTelemetryProperties = [:]) {
        guard let service = service else {
            return
        }

        Task.detached(priority: .utility) {
            await service.record(eventName, properties: properties)
        }
    }

    static func flush() {
        guard let service = service else {
            return
        }

        Task.detached(priority: .utility) {
            await service.flush()
        }
    }

    private static var service: IChartTelemetryService? {
        lock.lock()
        defer { lock.unlock() }
        return configuredService
    }
}

actor IChartTelemetryService {
    private let endpointURL: URL
    private let publishableKey: String
    private let sessionStore: IChartSupabaseSessionStore?
    private let queueStore: IChartTelemetryQueueStore
    private let installationID: UUID
    private let sessionID: UUID
    private let urlSession: URLSession
    private let now: () -> Date
    private var isFlushing = false
    private var lastFlushAttemptAt: Date?

    private static let installationIDKey = "iChart.telemetry.installation-id.v1"
    private static let opportunisticFlushInterval: TimeInterval = 20
    private static let opportunisticFlushQueueThreshold = 8
    private static let maxBatchSize = 40

    init(
        endpointURL: URL,
        publishableKey: String,
        sessionStore: IChartSupabaseSessionStore?,
        queueStore: IChartTelemetryQueueStore,
        installationID: UUID,
        sessionID: UUID = UUID(),
        urlSession: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.endpointURL = endpointURL
        self.publishableKey = publishableKey
        self.sessionStore = sessionStore
        self.queueStore = queueStore
        self.installationID = installationID
        self.sessionID = sessionID
        self.urlSession = urlSession
        self.now = now
    }

    static func live(clients: IChartSupabaseClients?) -> IChartTelemetryService? {
        guard let configuration = IChartSupabaseConfiguration.current() else {
            return nil
        }

        return IChartTelemetryService(
            endpointURL: configuration.url
                .appendingPathComponent("functions")
                .appendingPathComponent("v1")
                .appendingPathComponent("app-telemetry-ingest"),
            publishableKey: configuration.publishableKey,
            sessionStore: clients?.sessionStore,
            queueStore: .live(),
            installationID: resolvedInstallationID()
        )
    }

    func record(_ eventName: String, properties: IChartTelemetryProperties = [:]) async {
        guard IChartTelemetryPrivacy.allowedEventNames.contains(eventName) else {
            return
        }

        let context = currentContext()
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
            try queueStore.append(event)
        } catch {
            return
        }

        if shouldFlushOpportunistically() {
            await flush()
        }
    }

    func flush() async {
        guard !isFlushing else {
            return
        }

        isFlushing = true
        lastFlushAttemptAt = now()
        defer { isFlushing = false }

        let events: [IChartTelemetryEvent]
        do {
            events = try Array(queueStore.loadEvents().prefix(Self.maxBatchSize))
        } catch {
            return
        }

        guard !events.isEmpty else {
            return
        }

        do {
            try await send(events)
            try queueStore.removeEvents(withIDs: Set(events.map(\.clientEventID)))
        } catch {
            return
        }
    }

    private func send(_ events: [IChartTelemetryEvent]) async throws {
        let batch = IChartTelemetryBatch(context: currentContext(), events: events)
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let accessToken = try? await sessionStore?.accessToken(),
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try Self.encoder.encode(batch)

        let (_, response) = try await urlSession.data(for: request)
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

    private func currentContext() -> IChartTelemetryContext {
        IChartTelemetryContext(
            installationID: installationID,
            sessionID: sessionID,
            appVersion: Self.bundleValue(for: "CFBundleShortVersionString", fallback: "unknown"),
            buildNumber: Self.bundleValue(for: "CFBundleVersion", fallback: "unknown"),
            platform: Self.platformName,
            osVersion: Self.osVersion,
            deviceModel: Self.deviceModel,
            localeLanguage: Locale.current.identifier,
            timeZoneOffsetMinutes: TimeZone.current.secondsFromGMT() / 60
        )
    }

    private static func resolvedInstallationID(defaults: UserDefaults = .standard) -> UUID {
        if let storedValue = defaults.string(forKey: installationIDKey),
           let uuid = UUID(uuidString: storedValue) {
            return uuid
        }

        let uuid = UUID()
        defaults.set(uuid.uuidString, forKey: installationIDKey)
        return uuid
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
        "chord.batch_committed",
        "chord.preview_updated",
        "chord.preview_edited",
        "chord.preview_rendered",
        "chord.preview_discarded",
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
        "barline_count",
        "chart_count",
        "chart_count_after",
        "chart_count_before",
        "cloud_backed_up_count",
        "confidence_bucket",
        "decision",
        "duration_ms",
        "draft_count",
        "error_code",
        "feature_area",
        "flow",
        "from_mode",
        "has_mask",
        "ink_tool_mode",
        "layout_style",
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
        "mode",
        "normalized_before_save",
        "normalization_needed",
        "page_count",
        "pdf_size_bucket",
        "plan",
        "point_count",
        "project_count",
        "reason",
        "recognition_ms",
        "render_action",
        "rendered_count",
        "rendered_ink_light_pixel_ratio",
        "rendered_ink_median_luminance",
        "rendered_ink_sample_count",
        "result",
        "scope",
        "source",
        "source_coordinate_height",
        "source_coordinate_width",
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
        "unresolved_count",
        "user_signed_in",
    ]

    static func sanitizedProperties(_ properties: IChartTelemetryProperties) -> IChartTelemetryProperties {
        Dictionary(
            uniqueKeysWithValues: properties
                .filter { allowedPropertyKeys.contains($0.key) }
                .sorted { $0.key < $1.key }
                .prefix(40)
                .map { key, value in
                    (String(key.prefix(64)), sanitizedValue(value))
                }
        )
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
