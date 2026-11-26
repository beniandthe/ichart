import Foundation

extension ChordSymbol {
    /// Respelling changes notation while retaining every sounding pitch.
    func spelledForChartDisplay(in key: DocumentKey) -> ChordSymbol {
        KeyAwareChordSpelling.spelled(self, in: key)
    }

    /// A key change supplies both the chromatic and diatonic interval.
    func transposedForChartDisplay(
        by semitones: Int, from sourceKey: DocumentKey, to targetKey: DocumentKey,
        preservingSpelling: Bool = false
    ) -> ChordSymbol {
        KeyAwareChordSpelling.transposed(self, by: semitones,
            from: sourceKey, to: targetKey, preservingSpelling: preservingSpelling)
    }
}

enum KeyAwareChordSpelling {
    private static let letters: [ChordRoot] = [.c, .d, .e, .f, .g, .a, .b]
    private static let majorScale = [0, 2, 4, 5, 7, 9, 11]
    private static let minorScale = [0, 2, 3, 5, 7, 8, 10]

    static func spelled(_ symbol: ChordSymbol, using preference: PitchSpellingPreference) -> ChordSymbol {
        guard symbol.kind == .rooted else { return symbol }
        let root = ChordPitch(root: symbol.root, accidental: symbol.accidental).spelled(using: preference)
        var copy = symbol
        copy.root = root.root
        copy.accidental = root.accidental
        if let text = symbol.slashBass, let bass = ChordPitch.parse(text) {
            if let degree = chordToneDegree(of: bass, in: symbol),
               let chordTone = pitch(matching: bass.semitone, letter: shifted(root.root, by: degree)) {
                copy.slashBass = chordTone.displayText
            } else {
                copy.slashBass = bass.spelled(using: preference).displayText
            }
        }
        return copy
    }

    static func spelled(_ symbol: ChordSymbol, in key: DocumentKey) -> ChordSymbol {
        guard symbol.kind == .rooted else { return symbol }
        let sourceRoot = ChordPitch(root: symbol.root, accidental: symbol.accidental)
        let root = scalePitch(matching: sourceRoot.semitone, in: key)
            ?? minorLeadingTone(for: symbol, in: key) ?? sourceRoot
        var copy = symbol
        copy.root = root.root
        copy.accidental = root.accidental
        if let text = symbol.slashBass, let bass = ChordPitch.parse(text) {
            copy.slashBass = bassPitch(bass, of: symbol, withRoot: root, in: key,
                semitones: 0, letterShift: 0, preservingSpelling: false,
                usesKeyForNonChordTone: true).displayText
        }
        return copy
    }

    static func transposed(
        _ symbol: ChordSymbol, by semitones: Int,
        from sourceKey: DocumentKey, to targetKey: DocumentKey,
        preservingSpelling: Bool
    ) -> ChordSymbol {
        guard symbol.kind == .rooted else { return symbol }
        let semitones = normalized(semitones)
        let source = preservingSpelling ? symbol : spelled(symbol, in: sourceKey)
        let sourceRoot = ChordPitch(root: source.root, accidental: source.accidental)
        let shift = letterIndex(targetKey.tonic) - letterIndex(sourceKey.tonic)
        let rootSemitone = normalized(sourceRoot.semitone + semitones)
        let root = pitch(matching: rootSemitone, letter: shifted(source.root, by: shift))
            ?? readablePitch(matching: rootSemitone, in: targetKey)
        var copy = source
        copy.root = root.root
        copy.accidental = root.accidental
        if let text = source.slashBass, let bass = ChordPitch.parse(text) {
            copy.slashBass = bassPitch(bass, of: source, withRoot: root, in: targetKey,
                semitones: semitones, letterShift: shift, preservingSpelling: preservingSpelling,
                usesKeyForNonChordTone: false).displayText
        }
        return copy
    }

    private static func bassPitch(
        _ sourceBass: ChordPitch, of symbol: ChordSymbol, withRoot root: ChordPitch,
        in key: DocumentKey, semitones: Int, letterShift: Int,
        preservingSpelling: Bool, usesKeyForNonChordTone: Bool
    ) -> ChordPitch {
        let targetSemitone = normalized(sourceBass.semitone + semitones)
        if !preservingSpelling,
           let degree = chordToneDegree(of: sourceBass, in: symbol),
           let chordTone = pitch(matching: targetSemitone, letter: shifted(root.root, by: degree)) {
            return chordTone
        }
        if usesKeyForNonChordTone, let diatonic = scalePitch(matching: targetSemitone, in: key) {
            return diatonic
        }
        return pitch(matching: targetSemitone, letter: shifted(sourceBass.root, by: letterShift))
            ?? readablePitch(matching: targetSemitone, in: key)
    }

    private static func scalePitch(matching semitone: Int, in key: DocumentKey) -> ChordPitch? {
        let steps: [Int]
        switch key.mode {
        case .major: steps = majorScale
        case .minor: steps = minorScale
        case .modal: return nil
        }
        let degree = steps.firstIndex { normalized(key.pitch.semitone + $0) == normalized(semitone) }
        guard let degree else { return nil }
        return pitch(matching: semitone, letter: shifted(key.tonic, by: degree))
    }

    private static func minorLeadingTone(for symbol: ChordSymbol, in key: DocumentKey) -> ChordPitch? {
        guard key.mode == .minor, isDiminished(symbol.quality),
              ChordPitch(root: symbol.root, accidental: symbol.accidental).semitone
                == normalized(key.pitch.semitone - 1) else { return nil }
        return pitch(matching: key.pitch.semitone - 1, letter: shifted(key.tonic, by: 6))
    }

    /// A pitch can have more than one harmonic role, such as #11 and b5.
    /// The source letter chooses between the roles actually written in the chord.
    private static func chordToneDegree(of bass: ChordPitch, in symbol: ChordSymbol) -> Int? {
        let root = ChordPitch(root: symbol.root, accidental: symbol.accidental)
        let interval = normalized(bass.semitone - root.semitone)
        let sourceDegree = (letterIndex(bass.root) - letterIndex(root.root) + 7) % 7
        let quality = symbol.quality.lowercased()
        let diminished = isDiminished(quality)
        let minor = symbol.quality != "M"
            && (quality.hasPrefix("-") || ["m", "min", "minor"].contains(quality))
        let augmented = ["+", "aug", "augmented"].contains(quality)
        let suspended = quality == "sus"
        let majorSeventh = quality.contains("△") || quality.contains("∆")
            || quality.contains("δ") || ["maj", "major", "M"].contains(symbol.quality)
        var tones: [(semitone: Int, degree: Int)] = [(0, 0)]
        if suspended {
            tones.append(symbol.extensions.contains("2") ? (2, 1) : (5, 3))
        } else {
            tones.append((minor || diminished ? 3 : 4, 2))
        }
        tones.append((diminished ? 6 : augmented ? 8 : 7, 4))
        if symbol.extensions.contains("6") { tones.append((9, 5)) }
        if symbol.extensions.contains("9") { tones.append((2, 1)) }
        if symbol.extensions.contains("11") { tones.append((5, 3)) }
        if symbol.extensions.contains("13") { tones.append((9, 5)) }
        let hasSeventh = symbol.extensions.contains("7")
            || quality == "alt"
            || (quality != "add" && !symbol.extensions.contains("6")
                && symbol.extensions.contains { ["9", "11", "13"].contains($0) })
        if hasSeventh {
            let seventh = majorSeventh ? 11 : ["°", "º", "dim", "diminished"].contains(quality) ? 9 : 10
            tones.append((seventh, 6))
        }
        let alteredTones: [String: (Int, Int)] = [
            "b5": (6, 4), "#5": (8, 4), "b9": (1, 1), "#9": (3, 1),
            "#11": (6, 3), "b13": (8, 5)
        ]
        for alteration in symbol.alterations {
            let normalized = alteration.replacingOccurrences(of: "♭", with: "b")
                .replacingOccurrences(of: "♯", with: "#")
            if let altered = alteredTones[normalized] { tones.append(altered) }
        }
        let matches = tones.filter { $0.semitone == interval }
        return matches.first(where: { $0.degree == sourceDegree })?.degree ?? matches.first?.degree
    }

    private static func isDiminished(_ quality: String) -> Bool {
        ["°", "º", "dim", "diminished", "ø", "halfdim", "halfdim7"].contains(quality.lowercased())
    }

    private static func readablePitch(matching semitone: Int, in key: DocumentKey) -> ChordPitch {
        scalePitch(matching: semitone, in: key)
            ?? ChordPitch.from(semitone: semitone, preference: key.spellingPreference)
    }

    private static func pitch(matching semitone: Int, letter: ChordRoot) -> ChordPitch? {
        let natural = ChordPitch(root: letter, accidental: .natural)
        switch normalized(semitone - natural.semitone) {
        case 0: return natural
        case 1: return ChordPitch(root: letter, accidental: .sharp)
        case 11: return ChordPitch(root: letter, accidental: .flat)
        default: return nil
        }
    }

    private static func letterIndex(_ root: ChordRoot) -> Int {
        letters.firstIndex(of: root)!
    }

    private static func shifted(_ root: ChordRoot, by steps: Int) -> ChordRoot {
        letters[(letterIndex(root) + steps % 7 + 7) % 7]
    }

    private static func normalized(_ semitone: Int) -> Int {
        (semitone % 12 + 12) % 12
    }
}
