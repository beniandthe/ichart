import Foundation

struct IChartPerformanceTraceSpan {
    fileprivate let name: String
    fileprivate let metadata: [String: String]
    fileprivate let startedAt: Date
}

enum IChartPerformanceTrace {
    static func start(
        _ name: String,
        metadata: [String: String] = [:]
    ) -> IChartPerformanceTraceSpan {
        let span = IChartPerformanceTraceSpan(
            name: name,
            metadata: sanitized(metadata),
            startedAt: Date()
        )
        record("\(name).begin", metadata: span.metadata)
        return span
    }

    static func end(
        _ span: IChartPerformanceTraceSpan,
        metadata: [String: String] = [:]
    ) {
        var mergedMetadata = span.metadata
        for (key, value) in metadata {
            mergedMetadata[key] = value
        }
        let durationMilliseconds = Date().timeIntervalSince(span.startedAt) * 1_000
        record(
            "\(span.name).end",
            durationMilliseconds: durationMilliseconds,
            metadata: mergedMetadata
        )
    }

    static func record(
        _ name: String,
        durationMilliseconds: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        guard isEnabled else {
            return
        }

        recorder.append(
            IChartPerformanceTraceEvent(
                timestamp: Date(),
                processUptimeSeconds: ProcessInfo.processInfo.systemUptime,
                name: name,
                durationMilliseconds: durationMilliseconds,
                metadata: sanitized(metadata),
                appVersion: bundleValue(for: "CFBundleShortVersionString"),
                buildNumber: bundleValue(for: "CFBundleVersion")
            )
        )
    }

    static var reportURL: URL {
        recorder.flush()
        try? recorder.ensureReportExists()
        return recorder.url
    }

    static var hasReport: Bool {
        recorder.flush()
        return recorder.hasLogFile
    }

    static func resetReport() {
        try? recorder.reset()
    }

    private static let recorder = IChartPerformanceTraceRecorder.live()

    private static var isEnabled: Bool {
        Bundle.main.bundleIdentifier == "com.ichart.app"
    }

    private static func bundleValue(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    private static func sanitized(_ metadata: [String: String]) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: metadata
                .sorted { $0.key < $1.key }
                .prefix(18)
                .map { key, value in
                    let trimmedKey = String(key.prefix(48))
                    let trimmedValue = String(value.prefix(140))
                    return (trimmedKey, trimmedValue)
                }
        )
    }
}

struct IChartPerformanceTraceEvent: Codable, Equatable {
    var timestamp: Date
    var processUptimeSeconds: TimeInterval
    var name: String
    var durationMilliseconds: Double?
    var metadata: [String: String]
    var appVersion: String
    var buildNumber: String
}

private final class IChartPerformanceTraceRecorder {
    let url: URL
    var maxTraceSizeBytes: UInt64 = 768 * 1024

    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.ichart.performance-trace", qos: .utility)

    init(
        url: URL,
        maxTraceSizeBytes: UInt64 = 768 * 1024,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.maxTraceSizeBytes = maxTraceSizeBytes
        self.fileManager = fileManager
    }

    func append(_ event: IChartPerformanceTraceEvent) {
        queue.async {
            try? self.appendSynchronously(event)
        }
    }

    func flush() {
        queue.sync {}
    }

    func ensureReportExists() throws {
        try queue.sync {
            guard !hasLogFile else {
                return
            }

            try appendSynchronously(
                IChartPerformanceTraceEvent(
                    timestamp: Date(),
                    processUptimeSeconds: ProcessInfo.processInfo.systemUptime,
                    name: "performance.report.created",
                    durationMilliseconds: nil,
                    metadata: [:],
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
                )
            )
        }
    }

    func reset() throws {
        try queue.sync {
            guard fileManager.fileExists(atPath: url.fileSystemPath) else {
                return
            }
            try fileManager.removeItem(at: url)
        }
    }

    var hasLogFile: Bool {
        fileManager.fileExists(atPath: url.fileSystemPath)
    }

    private func appendSynchronously(_ event: IChartPerformanceTraceEvent) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try Self.encoder.encode(event)
        let line = data + Data([0x0A])

        if fileManager.fileExists(atPath: url.fileSystemPath) {
            if try currentTraceSizeBytes() >= maxTraceSizeBytes {
                try fileManager.removeItem(at: url)
                try line.write(to: url, options: .atomic)
                return
            }

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    private func currentTraceSizeBytes() throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.fileSystemPath)
        return attributes[.size] as? UInt64 ?? 0
    }
}

private extension IChartPerformanceTraceRecorder {
    static func live(fileManager: FileManager = .default) -> IChartPerformanceTraceRecorder {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL.appendingPathComponent("iChart", isDirectory: true)
        return IChartPerformanceTraceRecorder(
            url: baseDirectory.appendingPathComponent("performance-trace.jsonl"),
            fileManager: fileManager
        )
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
    }
}
