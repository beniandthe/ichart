import Foundation

/// Only fixed outcomes and error categories belong in a basic timing report.
enum IChartPerformanceTraceResult: String, Codable, Sendable {
    case succeeded
    case failed
}

enum IChartPerformanceTraceErrorCategory: String, Codable, Sendable {
    case storageRead = "storage_read"
    case storageWrite = "storage_write"
    case serialization
    case recognition
    case export
    case unknown
}

/// A captured consent grant, rather than a boolean that can revive queued
/// observations after diagnostics is withdrawn and then granted again.
struct IChartPerformanceTraceAuthorization: Sendable {
    private let check: @Sendable () -> Bool

    init(isCurrent: @escaping @Sendable () -> Bool) {
        check = isCurrent
    }

    func isCurrent() -> Bool { check() }
}

struct IChartPerformanceTraceSpan {
    fileprivate let completedName: String?
    fileprivate let authorization: IChartPerformanceTraceAuthorization?
    fileprivate let startedAtNanoseconds: UInt64
}

enum IChartPerformanceTrace {
    static func start(
        _ name: String,
        metadata: @autoclosure () -> [String: String] = [:]
    ) -> IChartPerformanceTraceSpan {
        // Legacy metadata is intentionally never evaluated. In particular, a
        // canvas metadata builder must not inspect drawings for a basic timing.
        let completedName = name + ".end"
        let authorization = IChartPerformanceTracePolicy.names.contains(completedName)
            ? recordingAuthorization() : nil
        return IChartPerformanceTraceSpan(
            completedName: authorization == nil ? nil : completedName,
            authorization: authorization,
            startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    static func end(
        _ span: IChartPerformanceTraceSpan,
        metadata: @autoclosure () -> [String: String] = [:],
        result: IChartPerformanceTraceResult? = nil,
        errorCategory: IChartPerformanceTraceErrorCategory? = nil
    ) {
        guard let name = span.completedName, let authorization = span.authorization,
              authorization.isCurrent() else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= span.startedAtNanoseconds else { return }
        recordBasicEvent(
            name,
            durationMilliseconds: Double(now - span.startedAtNanoseconds) / 1_000_000,
            result: result,
            errorCategory: errorCategory,
            authorization: authorization
        )
    }

    static func record(
        _ name: String,
        durationMilliseconds: Double? = nil,
        metadata: @autoclosure () -> [String: String] = [:],
        result: IChartPerformanceTraceResult? = nil,
        errorCategory: IChartPerformanceTraceErrorCategory? = nil
    ) {
        guard IChartPerformanceTracePolicy.names.contains(name),
              IChartPerformanceTracePolicy.isValidDuration(durationMilliseconds),
              let authorization = recordingAuthorization() else { return }
        recordBasicEvent(name, durationMilliseconds: durationMilliseconds, result: result,
                         errorCategory: errorCategory, authorization: authorization)
    }

    private static func recordBasicEvent(
        _ name: String,
        durationMilliseconds: Double?,
        result: IChartPerformanceTraceResult?,
        errorCategory: IChartPerformanceTraceErrorCategory?,
        authorization: IChartPerformanceTraceAuthorization
    ) {
        guard authorization.isCurrent(),
              IChartPerformanceTracePolicy.isValidDuration(durationMilliseconds) else { return }
        var basicMetadata: [String: String] = [:]
        if let result { basicMetadata["result"] = result.rawValue }
        if let errorCategory, result == .failed {
            basicMetadata["error_category"] = errorCategory.rawValue
        }
        recorder.append(IChartPerformanceTraceEvent(
            timestamp: Date(),
            name: name,
            durationMilliseconds: durationMilliseconds,
            metadata: basicMetadata,
            appVersion: bundleValue(for: "CFBundleShortVersionString"),
            buildNumber: bundleValue(for: "CFBundleVersion")
        ), authorization: authorization)
    }

    /// Explicit user-requested export may wait for pending writes and read disk.
    static var reportURL: URL? {
        try? recorder.exportReport()
    }

    /// Settings availability is a best-effort memory read, never a disk probe.
    static var hasReport: Bool {
        recorder.hasLogFile
    }

    static func resetReport() {
        try? recorder.reset()
    }

    private static let recorder = IChartPerformanceTraceRecorder.live(
        authorizationProvider: { recordingAuthorization() }
    )

    private static func recordingAuthorization() -> IChartPerformanceTraceAuthorization? {
        #if canImport(UIKit)
        guard let authorization = IChartTelemetry.basicRecordingAuthorization(),
              Bundle.main.bundleIdentifier == "com.ichart.app" else { return nil }
        return IChartPerformanceTraceAuthorization(isCurrent: { authorization.isCurrent })
        #else
        // The portable model target has no configured app consent service.
        return nil
        #endif
    }

    private static func bundleValue(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }
}

struct IChartPerformanceTraceEvent: Codable, Equatable, Sendable {
    var timestamp: Date
    var name: String
    var durationMilliseconds: Double?
    var metadata: [String: String]
    var appVersion: String
    var buildNumber: String
}

private enum IChartPerformanceTracePolicy {
    static let names: Set<String> = [
        "app.init.end", "app.bootstrap.end", "library.load", "library.save",
        "ink.persistence.writeback", "chord.recognition.capture", "chord.recognition.prepare",
        "chord.preview.replace", "rhythm.recognition.capture", "rhythm.recognition.analyze",
        "pdf.export.end"
    ]
    static let maximumDurationMilliseconds = 86_400_000.0

    static func isValidDuration(_ duration: Double?) -> Bool {
        guard let duration else { return false }
        return duration.isFinite && (0...maximumDurationMilliseconds).contains(duration)
    }

    static func sanitized(_ event: IChartPerformanceTraceEvent) -> IChartPerformanceTraceEvent? {
        guard names.contains(event.name), isValidDuration(event.durationMilliseconds),
              event.timestamp.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var event = event
        var metadata: [String: String] = [:]
        if let value = event.metadata["result"], IChartPerformanceTraceResult(rawValue: value) != nil {
            metadata["result"] = value
        }
        if metadata["result"] == IChartPerformanceTraceResult.failed.rawValue,
           let value = event.metadata["error_category"],
           IChartPerformanceTraceErrorCategory(rawValue: value) != nil {
            metadata["error_category"] = value
        }
        event.metadata = metadata
        event.appVersion = sanitizedVersion(event.appVersion, allowsDot: true, maximumLength: 32)
        event.buildNumber = sanitizedVersion(event.buildNumber, allowsDot: true, maximumLength: 12)
        return event
    }

    private static func sanitizedVersion(_ value: String, allowsDot: Bool, maximumLength: Int) -> String {
        guard !value.isEmpty, value.utf8.count <= maximumLength,
              value.utf8.allSatisfy({ (48...57).contains($0) || (allowsDot && $0 == 46) }),
              value.first != ".", value.last != ".", !value.contains("..") else { return "unknown" }
        return value
    }
}

/// Admission never waits for storage or the worker. A burst retains at most 64
/// pending events, plus the single batch currently owned by the utility worker.
final class IChartPerformanceTraceRecorder: @unchecked Sendable {
    let url: URL
    let maxTraceSizeBytes: UInt64

    // FileManager is accessed only by the serial utility queue (including
    // explicit export/clear). The wrapper makes that confinement explicit at
    // the sendable closure boundary without changing Foundation's conformance.
    private struct FileManagerReference: @unchecked Sendable {
        let value: FileManager
    }
    private let fileManager: FileManager
    private let authorizationProvider: @Sendable () -> IChartPerformanceTraceAuthorization?
    private let writeBatch: @Sendable (Data, URL, UInt64) throws -> Bool
    private let queue = DispatchQueue(label: "com.ichart.performance-trace", qos: .utility)
    private let lock = NSLock()
    private struct PendingEvent {
        let event: IChartPerformanceTraceEvent
        let authorization: IChartPerformanceTraceAuthorization
    }
    private var pending: [PendingEvent] = []
    private var drainScheduled = false
    private var inFlightCount = 0
    private var hasPersistedEvents = false
    private var numberOfScheduledDrains = 0
    private static let capacity = 64

    init(
        url: URL,
        maxTraceSizeBytes: UInt64 = 768 * 1024,
        fileManager: FileManager = .default,
        isRecordingEnabled: @escaping @Sendable () -> Bool = { true },
        authorizationProvider: (@Sendable () -> IChartPerformanceTraceAuthorization?)? = nil,
        writeBatch: (@Sendable (Data, URL, UInt64) throws -> Bool)? = nil
    ) {
        self.url = url
        self.maxTraceSizeBytes = maxTraceSizeBytes
        self.fileManager = fileManager
        self.authorizationProvider = authorizationProvider ?? {
            guard isRecordingEnabled() else { return nil }
            return IChartPerformanceTraceAuthorization(isCurrent: isRecordingEnabled)
        }
        let storage = FileManagerReference(value: fileManager)
        self.writeBatch = writeBatch ?? { data, url, limit in
            try Self.appendBatch(data, to: url, limit: limit, fileManager: storage.value)
        }
        pending.reserveCapacity(Self.capacity)
        // Discovery is read-only and asynchronous even when diagnostics is off.
        // The availability getter itself never touches the file system.
        queue.async {
            let exists = self.fileManager.fileExists(atPath: self.url.fileSystemPath)
            self.lock.lock()
            self.hasPersistedEvents = self.hasPersistedEvents || exists
            self.lock.unlock()
        }
    }

    func append(
        _ event: IChartPerformanceTraceEvent,
        authorization: IChartPerformanceTraceAuthorization? = nil
    ) {
        guard let event = IChartPerformanceTracePolicy.sanitized(event),
              let authorization = authorization ?? authorizationProvider(),
              authorization.isCurrent(), lock.try() else { return }
        guard pending.count < Self.capacity else {
            lock.unlock()
            return
        }
        pending.append(PendingEvent(event: event, authorization: authorization))
        let shouldSchedule = !drainScheduled
        if shouldSchedule {
            drainScheduled = true
            numberOfScheduledDrains = min(numberOfScheduledDrains, Int.max - 1) + 1
        }
        lock.unlock()
        if shouldSchedule {
            queue.async { self.drain() }
        }
    }

    /// Explicit synchronization is for report export, clear, and tests only.
    func flush() {
        queue.sync { drain() }
    }

    func reset() throws {
        try queue.sync {
            lock.lock()
            pending.removeAll(keepingCapacity: true)
            hasPersistedEvents = false
            lock.unlock()
            // Clear only the two paths owned by this diagnostic feature.
            // Never enumerate or remove their parent directory or neighbors.
            let exportedReportURL = url.deletingLastPathComponent()
                .appendingPathComponent("performance-report.jsonl")
            for diagnosticURL in [url, exportedReportURL] {
                if fileManager.fileExists(atPath: diagnosticURL.fileSystemPath) {
                    try fileManager.removeItem(at: diagnosticURL)
                }
            }
        }
    }

    func exportReport() throws -> URL {
        try queue.sync {
            drain()
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let source = try handle.read(upToCount: IChartPerformanceTraceReportSanitizer.maximumSourceSizeBytes) ?? Data()
            let sanitized = try IChartPerformanceTraceReportSanitizer.sanitize(source)
            guard !sanitized.isEmpty else { throw ReportError.noEligibleEvents }
            let exportURL = url.deletingLastPathComponent()
                .appendingPathComponent("performance-report.jsonl")
            try sanitized.write(to: exportURL, options: .atomic)
            lock.lock()
            hasPersistedEvents = true
            lock.unlock()
            return exportURL
        }
    }

    var hasLogFile: Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        return hasPersistedEvents || !pending.isEmpty || inFlightCount > 0
    }

    // These memory-only counters also make bounded admission testable without
    // inspecting file-system state or waiting on a blocked storage operation.
    var pendingEventCount: Int? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return pending.count
    }

    var scheduledDrainCount: Int? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return numberOfScheduledDrains
    }

    private func drain() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                inFlightCount = 0
                drainScheduled = false
                lock.unlock()
                return
            }
            let batch = pending
            pending.removeAll(keepingCapacity: true)
            inFlightCount = batch.count
            lock.unlock()

            // Check the original grant on the worker. A later regrant cannot
            // revive observations made under the withdrawn consent epoch.
            var wrote = false
            var data = Data()
            var authorized: [IChartPerformanceTraceAuthorization] = []
            for observation in batch {
                guard observation.authorization.isCurrent(),
                      let line = try? encoder.encode(observation.event) else { continue }
                data.append(line)
                data.append(0x0A)
                authorized.append(observation.authorization)
            }
            if !data.isEmpty, authorized.allSatisfy({ $0.isCurrent() }) {
                wrote = (try? writeBatch(data, url, maxTraceSizeBytes)) ?? false
            }
            lock.lock()
            hasPersistedEvents = hasPersistedEvents || wrote
            inFlightCount = 0
            lock.unlock()
            // Failed writes are dropped. No retry, rotation, or cleanup runs on
            // the producer, and no lock is held during encoding or disk I/O.
        }
    }

    private static func appendBatch(_ data: Data, to url: URL, limit: UInt64, fileManager: FileManager) throws -> Bool {
        guard UInt64(data.count) <= limit else { return false }
        let exists = fileManager.fileExists(atPath: url.fileSystemPath)
        if exists {
            let attributes = try fileManager.attributesOfItem(atPath: url.fileSystemPath)
            let size = attributes[.size] as? UInt64 ?? 0
            // A full legacy trace stays intact until the user's explicit clear.
            guard size <= limit - UInt64(data.count) else { return false }
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if exists {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
        return true
    }

    private enum ReportError: Error {
        case noEligibleEvents
    }
}

enum IChartPerformanceTraceReportSanitizer {
    static let maximumSourceSizeBytes = 1024 * 1024
    static let maximumOutputSizeBytes = 768 * 1024

    static func sanitize(
        _ source: Data,
        maxSourceSizeBytes: Int = maximumSourceSizeBytes,
        maxOutputSizeBytes: Int = maximumOutputSizeBytes
    ) throws -> Data {
        guard maxSourceSizeBytes > 0, maxOutputSizeBytes > 0 else { return Data() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var result = Data()
        let bounded = source.prefix(min(maxSourceSizeBytes, maximumSourceSizeBytes))
        let outputLimit = min(maxOutputSizeBytes, maximumOutputSizeBytes)
        for line in bounded.split(separator: 0x0A) {
            // Unknown names, raw metadata, malformed lines, and fields outside
            // the typed basic schema never leave the device in a report.
            guard line.count <= 16 * 1024,
                  let decoded = try? decoder.decode(IChartPerformanceTraceEvent.self, from: Data(line)),
                  let event = IChartPerformanceTracePolicy.sanitized(decoded) else { continue }
            let encoded = try encoder.encode(event)
            guard encoded.count + 1 <= outputLimit - result.count else { break }
            result.append(encoded)
            result.append(0x0A)
        }
        return result
    }
}

private extension IChartPerformanceTraceRecorder {
    static func live(authorizationProvider: @escaping @Sendable () -> IChartPerformanceTraceAuthorization?) -> IChartPerformanceTraceRecorder {
        // Constructing the global recorder resolves a path only. Directory
        // creation and all file access belong to the utility worker or an
        // explicit user-requested export/clear operation.
        let baseDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/iChart", isDirectory: true)
        return IChartPerformanceTraceRecorder(
            url: baseDirectory.appendingPathComponent("performance-trace.jsonl"),
            authorizationProvider: authorizationProvider
        )
    }
}

private extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
    }
}
