import Foundation

enum ChordSpellingIntent: String, Codable, Hashable {
    case automatic
    case explicit
}

enum ChordSpellingOverrideSource: String, Codable, Hashable {
    case userSelection
}

struct ChordEvent: Identifiable, Codable, Hashable {
    static let minimumManualDisplayWidth: Double = 18
    static let maximumManualDisplayWidth: Double = 360
    static let minimumManualLaneFraction: Double = 0
    static let maximumManualLaneFraction: Double = 0.9999

    var id: UUID
    var symbol: ChordSymbol
    var spellingIntent: ChordSpellingIntent
    var spellingOverrideSource: ChordSpellingOverrideSource?
    var startPosition: BeatPosition
    var duration: RhythmValue
    var rhythmPlacement: RhythmPlacement
    var mappedRhythmSlotIndex: Int? = nil
    var tieOut: Bool
    var hitStyle: HitStyle
    var rawInput: String?
    var sourceInkData: Data? = nil
    var sourceCandidateSignature: [String] = []
    var manualDisplayWidth: Double? = nil
    var manualLaneFraction: Double? = nil

    init(
        id: UUID,
        symbol: ChordSymbol,
        spellingIntent: ChordSpellingIntent = .automatic,
        spellingOverrideSource: ChordSpellingOverrideSource? = nil,
        startPosition: BeatPosition,
        duration: RhythmValue,
        rhythmPlacement: RhythmPlacement,
        mappedRhythmSlotIndex: Int? = nil,
        tieOut: Bool,
        hitStyle: HitStyle,
        rawInput: String?,
        sourceInkData: Data? = nil,
        sourceCandidateSignature: [String] = [],
        manualDisplayWidth: Double? = nil,
        manualLaneFraction: Double? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.spellingIntent = spellingIntent
        self.spellingOverrideSource = spellingIntent == .explicit
            ? (spellingOverrideSource ?? .userSelection)
            : nil
        self.startPosition = startPosition
        self.duration = duration
        self.rhythmPlacement = rhythmPlacement
        self.mappedRhythmSlotIndex = mappedRhythmSlotIndex
        self.tieOut = tieOut
        self.hitStyle = hitStyle
        self.rawInput = rawInput
        self.sourceInkData = normalizedPersistentInkDrawingData(sourceInkData)
        self.sourceCandidateSignature = sourceCandidateSignature
        self.manualDisplayWidth = manualDisplayWidth.map(Self.clampedManualDisplayWidth)
        self.manualLaneFraction = manualLaneFraction.map(Self.clampedManualLaneFraction)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case spellingIntent
        case spellingOverrideSource
        case startPosition
        case duration
        case rhythmPlacement
        case mappedRhythmSlotIndex
        case tieOut
        case hitStyle
        case rawInput
        case sourceInkData
        case sourceCandidateSignature
        case manualDisplayWidth
        case manualLaneFraction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        symbol = try container.decode(ChordSymbol.self, forKey: .symbol)
        let decodedSpellingIntent = try container.decodeIfPresent(ChordSpellingIntent.self, forKey: .spellingIntent) ?? .automatic
        let decodedSpellingOverrideSource = try container.decodeIfPresent(
            ChordSpellingOverrideSource.self,
            forKey: .spellingOverrideSource
        )
        if decodedSpellingIntent == .explicit,
           decodedSpellingOverrideSource == nil {
            spellingIntent = .automatic
            spellingOverrideSource = nil
        } else {
            spellingIntent = decodedSpellingIntent
            spellingOverrideSource = decodedSpellingOverrideSource
        }
        startPosition = try container.decode(BeatPosition.self, forKey: .startPosition)
        duration = try container.decode(RhythmValue.self, forKey: .duration)
        rhythmPlacement = try container.decode(RhythmPlacement.self, forKey: .rhythmPlacement)
        mappedRhythmSlotIndex = try container.decodeIfPresent(Int.self, forKey: .mappedRhythmSlotIndex)
        tieOut = try container.decode(Bool.self, forKey: .tieOut)
        hitStyle = try container.decode(HitStyle.self, forKey: .hitStyle)
        rawInput = try container.decodeIfPresent(String.self, forKey: .rawInput)
        sourceInkData = normalizedPersistentInkDrawingData(
            try container.decodeIfPresent(Data.self, forKey: .sourceInkData)
        )
        sourceCandidateSignature = try container.decodeIfPresent([String].self, forKey: .sourceCandidateSignature) ?? []
        manualDisplayWidth = try container.decodeIfPresent(Double.self, forKey: .manualDisplayWidth)
            .map(Self.clampedManualDisplayWidth)
        manualLaneFraction = try container.decodeIfPresent(Double.self, forKey: .manualLaneFraction)
            .map(Self.clampedManualLaneFraction)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(symbol, forKey: .symbol)
        if spellingIntent != .automatic {
            try container.encode(spellingIntent, forKey: .spellingIntent)
            try container.encodeIfPresent(spellingOverrideSource, forKey: .spellingOverrideSource)
        }
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
        try container.encodeIfPresent(manualDisplayWidth, forKey: .manualDisplayWidth)
        try container.encodeIfPresent(manualLaneFraction, forKey: .manualLaneFraction)
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

    static func clampedManualDisplayWidth(_ width: Double) -> Double {
        guard width.isFinite else {
            return minimumManualDisplayWidth
        }

        return min(max(width, minimumManualDisplayWidth), maximumManualDisplayWidth)
    }

    static func clampedManualLaneFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else {
            return minimumManualLaneFraction
        }

        return min(max(fraction, minimumManualLaneFraction), maximumManualLaneFraction)
    }
}

struct ChordSymbol: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case rooted
        case chordRepeat
    }

    static let chordRepeatDisplayText = "•/•"

    var kind: Kind
    var root: ChordRoot
    var accidental: Accidental
    var quality: String
    var extensions: [String]
    var alterations: [String]
    var slashBass: String?

    init(
        root: ChordRoot,
        accidental: Accidental,
        quality: String,
        extensions: [String],
        alterations: [String],
        slashBass: String?,
        kind: Kind = .rooted
    ) {
        self.kind = kind
        self.root = root
        self.accidental = accidental
        self.quality = quality
        self.extensions = extensions
        self.alterations = alterations
        self.slashBass = slashBass
    }

    static var chordRepeat: ChordSymbol {
        ChordSymbol(
            root: .c,
            accidental: .natural,
            quality: "",
            extensions: [],
            alterations: [],
            slashBass: nil,
            kind: .chordRepeat
        )
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case root
        case accidental
        case quality
        case extensions
        case alterations
        case slashBass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .rooted

        if kind == .chordRepeat {
            root = try container.decodeIfPresent(ChordRoot.self, forKey: .root) ?? .c
            accidental = try container.decodeIfPresent(Accidental.self, forKey: .accidental) ?? .natural
            quality = try container.decodeIfPresent(String.self, forKey: .quality) ?? ""
            extensions = try container.decodeIfPresent([String].self, forKey: .extensions) ?? []
            alterations = try container.decodeIfPresent([String].self, forKey: .alterations) ?? []
            slashBass = nil
            return
        }

        root = try container.decode(ChordRoot.self, forKey: .root)
        accidental = try container.decode(Accidental.self, forKey: .accidental)
        quality = try container.decode(String.self, forKey: .quality)
        extensions = try container.decode([String].self, forKey: .extensions)
        alterations = try container.decode([String].self, forKey: .alterations)
        slashBass = try container.decodeIfPresent(String.self, forKey: .slashBass)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if kind == .chordRepeat {
            try container.encode(kind, forKey: .kind)
            return
        }

        try container.encode(root, forKey: .root)
        try container.encode(accidental, forKey: .accidental)
        try container.encode(quality, forKey: .quality)
        try container.encode(extensions, forKey: .extensions)
        try container.encode(alterations, forKey: .alterations)
        try container.encodeIfPresent(slashBass, forKey: .slashBass)
    }

    var displayText: String {
        if kind == .chordRepeat {
            return Self.chordRepeatDisplayText
        }

        let qualityText = displayQualityText
        let extensionText = extensions == ["6", "9"] ? "6/9" : extensions.joined()
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
        guard semitones != 0, kind == .rooted else { return self }

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
        guard kind == .rooted else { return self }

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

    func spelledForChartDisplay(using preference: PitchSpellingPreference) -> ChordSymbol {
        guard kind == .rooted else { return self }

        let pitch = ChordPitch(root: root, accidental: accidental).spelled(using: preference)
        var copy = self
        copy.root = pitch.root
        copy.accidental = pitch.accidental

        if let slashBass,
           let parsedBass = ChordPitch.parse(slashBass) {
            copy.slashBass = parsedBass.spelled(using: preference).displayText
        }

        return copy
    }

    func enharmonicDisplayTexts() -> [String] {
        guard kind == .rooted else { return [] }

        let spellings = [PitchSpellingPreference.flats, .sharps]
            .map { spelledForChartDisplay(using: $0).displayText }

        var seen = Set<String>()
        return spellings.filter { spelling in
            guard !seen.contains(spelling) else {
                return false
            }

            seen.insert(spelling)
            return true
        }
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
