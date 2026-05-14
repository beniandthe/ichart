import Foundation

enum ChordEntryDiagnosticResolution: String, Codable, Equatable {
    case autoRendered
    case confirmedSuggestion
    case manualCorrection
    case renderedChordCorrection
}

struct ChordEntryDiagnosticEvent: Codable, Equatable {
    var timestamp: Date
    var chartID: UUID
    var chartTitle: String
    var measureID: UUID
    var measureIndex: Int
    var chordEventID: UUID?
    var resolution: ChordEntryDiagnosticResolution
    var acceptedText: String
    var previousRenderedDisplayText: String?
    var renderedDisplayText: String
    var bestCandidateText: String?
    var suggestedCandidateTexts: [String]
    var rawCandidates: [String]
    var candidateScores: [ChordInkCandidateScore]
    var confidence: Double
    var recognitionReason: String
    var wasCloseRace: Bool
    var confidenceGap: Double?
    var targetFraction: Double?
}

struct ChordEntryDiagnosticsRecorder {
    let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func append(_ event: ChordEntryDiagnosticEvent) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try Self.encoder.encode(event)
        let line = data + Data([0x0A])

        if fileManager.fileExists(atPath: url.path()) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    func reset() throws {
        guard fileManager.fileExists(atPath: url.path()) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    func loadEvents() throws -> [ChordEntryDiagnosticEvent] {
        guard fileManager.fileExists(atPath: url.path()) else {
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
                    ChordEntryDiagnosticEvent.self,
                    from: Data(line.utf8)
                )
            }
    }
}

extension ChordEntryDiagnosticsRecorder {
    static func live(fileManager: FileManager = .default) -> ChordEntryDiagnosticsRecorder {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL.appendingPathComponent("SmartChart", isDirectory: true)
        return ChordEntryDiagnosticsRecorder(
            url: baseDirectory.appendingPathComponent("chord-entry-diagnostics.jsonl"),
            fileManager: fileManager
        )
    }
}

private extension ChordEntryDiagnosticsRecorder {
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
