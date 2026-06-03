import Foundation

struct ChordEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var symbol: ChordSymbol
    var startPosition: BeatPosition
    var duration: RhythmValue
    var rhythmPlacement: RhythmPlacement
    var mappedRhythmSlotIndex: Int? = nil
    var tieOut: Bool
    var hitStyle: HitStyle
    var rawInput: String?
    var sourceInkData: Data? = nil
    var sourceCandidateSignature: [String] = []

    init(
        id: UUID,
        symbol: ChordSymbol,
        startPosition: BeatPosition,
        duration: RhythmValue,
        rhythmPlacement: RhythmPlacement,
        mappedRhythmSlotIndex: Int? = nil,
        tieOut: Bool,
        hitStyle: HitStyle,
        rawInput: String?,
        sourceInkData: Data? = nil,
        sourceCandidateSignature: [String] = []
    ) {
        self.id = id
        self.symbol = symbol
        self.startPosition = startPosition
        self.duration = duration
        self.rhythmPlacement = rhythmPlacement
        self.mappedRhythmSlotIndex = mappedRhythmSlotIndex
        self.tieOut = tieOut
        self.hitStyle = hitStyle
        self.rawInput = rawInput
        self.sourceInkData = sourceInkData
        self.sourceCandidateSignature = sourceCandidateSignature
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case startPosition
        case duration
        case rhythmPlacement
        case mappedRhythmSlotIndex
        case tieOut
        case hitStyle
        case rawInput
        case sourceInkData
        case sourceCandidateSignature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        symbol = try container.decode(ChordSymbol.self, forKey: .symbol)
        startPosition = try container.decode(BeatPosition.self, forKey: .startPosition)
        duration = try container.decode(RhythmValue.self, forKey: .duration)
        rhythmPlacement = try container.decode(RhythmPlacement.self, forKey: .rhythmPlacement)
        mappedRhythmSlotIndex = try container.decodeIfPresent(Int.self, forKey: .mappedRhythmSlotIndex)
        tieOut = try container.decode(Bool.self, forKey: .tieOut)
        hitStyle = try container.decode(HitStyle.self, forKey: .hitStyle)
        rawInput = try container.decodeIfPresent(String.self, forKey: .rawInput)
        sourceInkData = try container.decodeIfPresent(Data.self, forKey: .sourceInkData)
        sourceCandidateSignature = try container.decodeIfPresent([String].self, forKey: .sourceCandidateSignature) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(startPosition, forKey: .startPosition)
        try container.encode(duration, forKey: .duration)
        try container.encode(rhythmPlacement, forKey: .rhythmPlacement)
        try container.encodeIfPresent(mappedRhythmSlotIndex, forKey: .mappedRhythmSlotIndex)
        try container.encode(tieOut, forKey: .tieOut)
        try container.encode(hitStyle, forKey: .hitStyle)
        try container.encodeIfPresent(rawInput, forKey: .rawInput)
        try container.encodeIfPresent(sourceInkData, forKey: .sourceInkData)
        if !sourceCandidateSignature.isEmpty {
            try container.encode(sourceCandidateSignature, forKey: .sourceCandidateSignature)
        }
    }

    var displaySummary: String {
        var components = [symbol.displayText, "@\(startPosition.displayText)", duration.displayText]

        if hitStyle != .none {
            components.append(hitStyle.rawValue)
        }

        if let mappedRhythmSlotIndex {
            components.append("slot \(mappedRhythmSlotIndex + 1)")
        }

        if tieOut {
            components.append("tie out")
        }

        return components.joined(separator: " · ")
    }

    func transposed(for view: TranspositionView) -> ChordEvent {
        var copy = self
        copy.symbol = symbol.transposed(by: view.semitoneOffsetFromConcert)
        return copy
    }

    mutating func apply(suggestion: MeasureChordInsertionSuggestion) {
        startPosition = suggestion.startPosition
        duration = suggestion.duration
        rhythmPlacement = suggestion.isRhythmMapped ? .aboveChord : .inline
        mappedRhythmSlotIndex = suggestion.mappedRhythmSlotIndex
    }
}

struct ChordSymbol: Codable, Hashable {
    var root: ChordRoot
    var accidental: Accidental
    var quality: String
    var extensions: [String]
    var alterations: [String]
    var slashBass: String?

    var displayText: String {
        let qualityText = displayQualityText
        let extensionText = extensions.joined()
        let alterationText = alterations.map { "(\($0))" }.joined()
        let slashText = slashBass.map { "/\($0)" } ?? ""

        if qualityText == "sus", extensions == ["7"] {
            return "\(root.rawValue)\(accidental.rawValue)7sus\(alterationText)\(slashText)"
        }

        if qualityText == "alt", extensions.isEmpty || extensions == ["7"] {
            return "\(root.rawValue)\(accidental.rawValue)7alt\(slashText)"
        }

        if qualityText == "-△", extensions == ["7"], alterations.isEmpty {
            return "\(root.rawValue)\(accidental.rawValue)-△7\(slashText)"
        }

        if qualityText == "-", extensions == ["6"], alterations.isEmpty {
            return "\(root.rawValue)\(accidental.rawValue)m6\(slashText)"
        }

        return "\(root.rawValue)\(accidental.rawValue)\(qualityText)\(extensionText)\(alterationText)\(slashText)"
    }

    func transposed(by semitones: Int) -> ChordSymbol {
        guard semitones != 0 else { return self }

        let originalPitch = ChordPitch(root: root, accidental: accidental)
        let preference = PitchSpellingPreference.forAccidental(accidental)
        let transposedRoot = originalPitch.transposed(by: semitones).spelled(using: preference)

        var copy = self
        copy.root = transposedRoot.root
        copy.accidental = transposedRoot.accidental

        if let slashBass,
           let parsedBass = ChordPitch.parse(slashBass) {
            let transposedBass = parsedBass.transposed(by: semitones).spelled(using: preference)
            copy.slashBass = transposedBass.displayText
        }

        return copy
    }

    func transposedForChartDisplay(by semitones: Int) -> ChordSymbol {
        let normalizedSemitones = Chart.normalizedChordTranspositionSemitones(semitones)
        guard normalizedSemitones != 0 else { return self }

        let originalPitch = ChordPitch(root: root, accidental: accidental)
        let rootPreference = Self.chartDisplaySpellingPreference(
            for: originalPitch,
            semitones: normalizedSemitones
        )
        let transposedRoot = originalPitch
            .transposed(by: normalizedSemitones)
            .spelled(using: rootPreference)

        var copy = self
        copy.root = transposedRoot.root
        copy.accidental = transposedRoot.accidental

        if let slashBass,
           let parsedBass = ChordPitch.parse(slashBass) {
            let bassPreference = Self.chartDisplaySpellingPreference(
                for: parsedBass,
                semitones: normalizedSemitones
            )
            let transposedBass = parsedBass
                .transposed(by: normalizedSemitones)
                .spelled(using: bassPreference)
            copy.slashBass = transposedBass.displayText
        }

        return copy
    }

    private static func chartDisplaySpellingPreference(
        for pitch: ChordPitch,
        semitones: Int
    ) -> PitchSpellingPreference {
        if pitch.accidental != .natural {
            return PitchSpellingPreference.forAccidental(pitch.accidental)
        }

        return semitones == 0 ? .flats : .sharps
    }

    private var displayQualityText: String {
        if quality == "△" || quality == "Δ" || quality == "∆" {
            return "△"
        }

        if quality == "maj" || quality == "major" || quality == "M" {
            return "△"
        }

        if quality == "-△" || quality == "-Δ" || quality == "-∆" {
            return "-△"
        }

        if quality.hasPrefix("maj") {
            return "△" + String(quality.dropFirst(3))
        }

        return quality
    }
}

enum ChordRoot: String, Codable, CaseIterable, Hashable {
    case c = "C"
    case d = "D"
    case e = "E"
    case f = "F"
    case g = "G"
    case a = "A"
    case b = "B"
}

enum Accidental: String, Codable, CaseIterable, Hashable {
    case natural = ""
    case sharp = "#"
    case flat = "b"
}
