import Foundation

enum ChordEntryDiagnosticResolution: String, Codable, Equatable {
    case autoRendered
    case userRuleApplied
    case confirmedSuggestion
    case manualCorrection
    case renderedChordCorrection
    case reconciledRenderedChord
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
    var ocrCandidates: [ChordOCRCandidate]? = nil
    var ocrBestCandidateText: String? = nil
    var ocrRawTexts: [String]? = nil
    var recognitionTrustSource: ChordRecognitionTrustSource? = nil
    var recognitionAgreementLevel: ChordRecognitionAgreementLevel? = nil
    var primaryRecognitionAction: ChordInkRecognitionAction? = nil
    var primaryAcceptedText: String? = nil
    var primaryRecognitionReason: String? = nil
    var primaryWasCloseRace: Bool? = nil
    var primaryConfidenceGap: Double? = nil
    var recognitionMetrics: ChordInkRecognitionMetrics? = nil
    var symbolLedger: ChordInkSymbolLedgerSnapshot? = nil
    var symbolLedgerAssessment: ChordInkSymbolLedgerAssessment? = nil
    var primarySymbolLedgerAssessment: ChordInkSymbolLedgerAssessment? = nil
    var placementEvidence: ChordEntryPlacementEvidence? = nil
    var timingEvidence: ChordEntryTimingEvidence? = nil
}

struct ChordEntryPlacementEvidence: Codable, Equatable {
    var startPositionText: String
    var durationText: String
    var rhythmPlacement: RhythmPlacement
    var mappedRhythmSlotIndex: Int?
}

struct ChordEntryTimingEvidence: Codable, Equatable {
    var requestedDelayMilliseconds: Double?
    var idleMilliseconds: Double?
    var recognitionMilliseconds: Double?
    var recognitionTotalMilliseconds: Double?
    var proposalDecisionMilliseconds: Double?
    var commitMutationMilliseconds: Double?
    var renderHandoffMilliseconds: Double?
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

        if fileManager.fileExists(atPath: url.fileSystemPath) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    func replaceLatestMatchingEvent(with event: ChordEntryDiagnosticEvent) throws {
        guard event.chordEventID != nil else {
            try append(event)
            return
        }

        var events = try loadEvents()
        guard let matchingIndex = events.indices.reversed().first(where: { index in
            Self.hasSameDiagnosticIdentity(events[index], event)
        }) else {
            try append(event)
            return
        }

        events[matchingIndex] = event
        try write(events)
    }

    func reset() throws {
        guard fileManager.fileExists(atPath: url.fileSystemPath) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    func loadEvents() throws -> [ChordEntryDiagnosticEvent] {
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
                    ChordEntryDiagnosticEvent.self,
                    from: Data(line.utf8)
                )
            }
    }

    private func write(_ events: [ChordEntryDiagnosticEvent]) throws {
        guard !events.isEmpty else {
            try reset()
            return
        }

        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try events.reduce(into: Data()) { output, event in
            output.append(try Self.encoder.encode(event))
            output.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func hasSameDiagnosticIdentity(
        _ lhs: ChordEntryDiagnosticEvent,
        _ rhs: ChordEntryDiagnosticEvent
    ) -> Bool {
        lhs.chartID == rhs.chartID
            && lhs.chordEventID == rhs.chordEventID
            && lhs.resolution == rhs.resolution
            && lhs.acceptedText == rhs.acceptedText
            && lhs.renderedDisplayText == rhs.renderedDisplayText
    }

    @discardableResult
    func reconcileRenderedChordEvents(for chart: Chart, timestamp: Date = .now) throws -> [ChordEntryDiagnosticEvent] {
        let events = try loadEvents()
        let report = ChordEntryDiagnosticCoverage.report(for: chart, events: events)
        guard !report.missingChordEventIDs.isEmpty else {
            return []
        }

        let missingEventIDSet = Set(report.missingChordEventIDs)
        let fallbackEvents = chart.systems.flatMap(\.measures).flatMap { measure in
            measure.chordEvents.compactMap { chordEvent -> ChordEntryDiagnosticEvent? in
                guard missingEventIDSet.contains(chordEvent.id) else {
                    return nil
                }

                let displayText = chordEvent.symbol.displayText
                let acceptedText = chordEvent.rawInput ?? displayText
                return ChordEntryDiagnosticEvent(
                    timestamp: timestamp,
                    chartID: chart.id,
                    chartTitle: chart.title,
                    measureID: measure.id,
                    measureIndex: measure.index,
                    chordEventID: chordEvent.id,
                    resolution: .reconciledRenderedChord,
                    acceptedText: acceptedText,
                    previousRenderedDisplayText: nil,
                    renderedDisplayText: displayText,
                    bestCandidateText: acceptedText,
                    suggestedCandidateTexts: [acceptedText],
                    rawCandidates: [acceptedText],
                    candidateScores: [],
                    confidence: 0,
                    recognitionReason: "Reconciled rendered chord event missing live diagnostic.",
                    wasCloseRace: false,
                    confidenceGap: nil,
                    targetFraction: nil,
                    ocrCandidates: nil,
                    ocrBestCandidateText: nil,
                    ocrRawTexts: nil,
                    recognitionTrustSource: nil,
                    recognitionAgreementLevel: nil,
                    primaryRecognitionAction: nil,
                    primaryAcceptedText: nil,
                    primaryRecognitionReason: nil,
                    primaryWasCloseRace: nil,
                    primaryConfidenceGap: nil,
                    recognitionMetrics: nil,
                    placementEvidence: ChordEntryPlacementEvidence(chordEvent: chordEvent),
                    timingEvidence: nil
                )
            }
        }

        for event in fallbackEvents {
            try append(event)
        }

        return fallbackEvents
    }
}

private extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
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

        let baseDirectory = applicationSupportURL.appendingPathComponent("iChart", isDirectory: true)
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

extension ChordEntryPlacementEvidence {
    init(chordEvent: ChordEvent) {
        self.init(
            startPositionText: chordEvent.startPosition.displayText,
            durationText: chordEvent.duration.displayText,
            rhythmPlacement: chordEvent.rhythmPlacement,
            mappedRhythmSlotIndex: chordEvent.mappedRhythmSlotIndex
        )
    }
}
