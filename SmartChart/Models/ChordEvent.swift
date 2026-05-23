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
