import Foundation

enum IChartRuntimeDiagnostics {
    static let rhythmRecognitionDiagnosticsKey = "iChartRhythmRecognitionDiagnosticsEnabled"

    static var isRhythmRecognitionDiagnosticsEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        UserDefaults.standard.bool(forKey: rhythmRecognitionDiagnosticsKey)
            || ProcessInfo.processInfo.arguments.contains("-iChartRhythmDiagnostics")
            || ProcessInfo.processInfo.environment["ICHART_RHYTHM_DIAGNOSTICS"] == "1"
        #else
        false
        #endif
    }
}

enum RhythmRecognitionDiagnosticStage: String, Codable, Equatable {
    case autoApplyCandidate
    case autoApplied
    case tapToRenderCandidate
    case tapRendered
    case selectionFinalized
    case inkPreserved
}

struct RhythmRecognitionDiagnosticEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var timestamp: Date
    var chartID: UUID
    var chartTitle: String
    var measureID: UUID
    var measureIndex: Int
    var layoutStyle: ChartLayoutStyle
    var meterText: String
    var stage: RhythmRecognitionDiagnosticStage
    var decision: String
    var route: String
    var reason: String?
    var proposalValues: [RhythmValue]
    var proposalSafety: String?
    var proposalIsNaturalExactFit: Bool?
    var phraseSource: String?
    var naturalValues: [RhythmValue]
    var naturalUnits: Int?
    var targetUnits: Int?
    var passesCompendium: Bool?
    var primitiveCount: Int?
    var symbolCount: Int?
    var unreadSymbolCount: Int?
    var uncoveredStrokeCount: Int?
    var inkStrokeCount: Int
    var pipelinePreview: RhythmRecognitionPipelinePreview?

    var valuesText: String {
        let values = proposalValues.isEmpty ? naturalValues : proposalValues
        guard !values.isEmpty else {
            return "no read"
        }

        return values.map(\.displayText).joined(separator: ", ")
    }

    var statusTitle: String {
        switch stage {
        case .autoApplyCandidate:
            return "Rhythm Ready"
        case .autoApplied:
            return "Rhythm Rendered"
        case .tapToRenderCandidate:
            return "Tap To Render"
        case .tapRendered:
            return "Rhythm Rendered"
        case .selectionFinalized:
            return "Rhythm Saved"
        case .inkPreserved:
            return "Rhythm Needs Check"
        }
    }

    var statusDetail: String {
        switch stage {
        case .autoApplyCandidate, .autoApplied, .tapToRenderCandidate, .tapRendered, .selectionFinalized:
            return pipelinePreview.map { "\(valuesText) • \($0.statusText)" } ?? valuesText
        case .inkPreserved:
            let pipelineText = pipelinePreview.map { " • \($0.statusText)" } ?? ""
            if let reason {
                return "\(reason): \(valuesText)\(pipelineText)"
            }
            return "\(valuesText)\(pipelineText)"
        }
    }
}

struct RhythmRecognitionDiagnosticsRecorder {
    let url: URL
    var maxLogSizeBytes: UInt64 = 2 * 1024 * 1024
    private let fileManager: FileManager

    init(
        url: URL,
        maxLogSizeBytes: UInt64 = 2 * 1024 * 1024,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.maxLogSizeBytes = maxLogSizeBytes
        self.fileManager = fileManager
    }

    func append(_ event: RhythmRecognitionDiagnosticEvent) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try Self.encoder.encode(event)
        let line = data + Data([0x0A])

        if fileManager.fileExists(atPath: url.fileSystemPath) {
            if try currentLogSizeBytes() >= maxLogSizeBytes {
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

    func reset() throws {
        guard fileManager.fileExists(atPath: url.fileSystemPath) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    var hasLogFile: Bool {
        fileManager.fileExists(atPath: url.fileSystemPath)
    }

    func loadEvents() throws -> [RhythmRecognitionDiagnosticEvent] {
        guard fileManager.fileExists(atPath: url.fileSystemPath) else {
            return []
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return try text
            .split(whereSeparator: \.isNewline)
            .map { line in
                try Self.decoder.decode(
                    RhythmRecognitionDiagnosticEvent.self,
                    from: Data(line.utf8)
                )
            }
    }

    private func currentLogSizeBytes() throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.fileSystemPath)
        return attributes[.size] as? UInt64 ?? 0
    }
}

extension RhythmRecognitionDiagnosticsRecorder {
    static func live(fileManager: FileManager = .default) -> RhythmRecognitionDiagnosticsRecorder {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL.appendingPathComponent("iChart", isDirectory: true)
        return RhythmRecognitionDiagnosticsRecorder(
            url: baseDirectory.appendingPathComponent("rhythm-recognition-diagnostics.jsonl"),
            fileManager: fileManager
        )
    }
}

private extension RhythmRecognitionDiagnosticsRecorder {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
    }
}
