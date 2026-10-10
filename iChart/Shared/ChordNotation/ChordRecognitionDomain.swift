import Foundation

/// The app-facing lexical boundary for handwritten chord recognition.
///
/// Learned models may retain broader output heads for artifact compatibility,
/// but only tokens in this domain may be projected into a chord-reading path.
/// This policy is deliberately lexical: `ChordNotationGrammar` remains the
/// authority for whether a sequence of otherwise legal tokens is a chord.
enum ChordRecognitionDomain {
    static let version = "chord-recognition-domain-v1"

    /// Returns true for one legal chord glyph/fragment or for an explicitly
    /// supported atomic template token. Contextual fragments such as `1` and
    /// lowercase `j` are legal because they can complete `11`/`13` and `maj`;
    /// this does not make either fragment a complete chord or a legal root.
    static func isAllowedGlyphToken(_ text: String) -> Bool {
        guard !text.isEmpty,
              text == text.precomposedStringWithCanonicalMapping,
              !text.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0)
                      || CharacterSet.controlCharacters.contains($0)
                      || CharacterSet.illegalCharacters.contains($0)
              }) else {
            return false
        }

        if canonicalAtomicTokens.contains(text) || aliasAtomicTokens.contains(text) {
            return true
        }

        return text.count == 1 && allowedSingleGlyphFragments.contains(text)
    }

    /// Rejects characters that cannot participate in any supported chord input
    /// before tolerant alias matching. It never removes or substitutes an
    /// unsupported character. Complete grammar validity is checked separately.
    static func containsOnlyChordInputCharacters(_ text: String) -> Bool {
        guard text == text.precomposedStringWithCanonicalMapping else {
            return false
        }

        let trimmed = text.trimmingCharacters(in: asciiSpaceSet)
        guard !trimmed.isEmpty else {
            return false
        }

        if isChordRepeatInput(trimmed) {
            return true
        }

        // Repeat punctuation is legal only as one of the exact complete repeat
        // spellings above; it is never decoration on a rooted chord.
        if trimmed.contains("•") || trimmed.contains("·") || trimmed.contains("∙")
            || trimmed.contains("%") || trimmed.contains(".") {
            return false
        }

        guard let first = trimmed.first,
              rootInputLetters.contains(String(first)) else {
            return false
        }

        for character in trimmed {
            if character == " " {
                continue
            }
            guard allowedChordInputCharacters.contains(String(character)) else {
                return false
            }
        }
        return true
    }

    /// Removes impossible lower ranks only when the raw top rank is itself in
    /// the chord domain. An illegal top rank yields no projection, so filtering
    /// can never promote a lower legal label into a read.
    static func projectTopRanked<T>(
        _ ranks: [T],
        label: (T) -> String
    ) -> [T] {
        guard let first = ranks.first,
              isAllowedGlyphToken(label(first)) else {
            return []
        }

        return ranks.filter { isAllowedGlyphToken(label($0)) }
    }

    private static let asciiSpaceSet = CharacterSet(charactersIn: " ")
    private static let rootInputLetters = Set(
        ChordNotation.Letter.allCases.flatMap { letter in
            [letter.rawValue, letter.rawValue.lowercased()]
        }
    )

    /// Canonical atoms come from the typed recognition grammar rather than from
    /// the much broader character-recognition training vocabulary.
    private static let canonicalAtomicTokens: Set<String> = {
        var values = Set(ChordNotation.Letter.allCases.map(\.rawValue))
        values.formUnion(ChordNotation.Accidental.allCases.map(\.rawValue).filter { !$0.isEmpty })
        values.formUnion(ChordNotation.Extension.allCases.map(\.rawValue))
        values.formUnion(ChordNotation.Alteration.allCases.map(\.rawValue))
        values.formUnion(["-", "△", "-△", "+", "°", "ø", "sus", "add", "alt"])
        values.formUnion(["/", "(", ")", ChordNotation.chordRepeat.canonicalDisplay])
        return values
    }()

    /// Friendly aliases already accepted by `ChordSymbolParser`, plus the exact
    /// setup glyph `o` whose UI meaning is the diminished mark. Multi-character
    /// values are allowed only as complete known atoms, not merely because each
    /// of their characters happens to be legal somewhere else.
    private static let aliasAtomicTokens: Set<String> = [
        "m", "M", "min", "minor", "maj", "major",
        "dim", "diminished", "hdim", "halfdim", "half-dim",
        "half dim", "halfdiminished", "half-diminished", "half diminished",
        "aug", "augmented", "sus", "suspended", "add", "alt", "altered",
        "flat", "sharp", "o",
        "♯", "＃", "♭", "−", "–", "—", "Δ", "∆", "º", "Ø", "⌀",
        "•", "·", "∙", "%", "./."
    ]

    private static let aliasWords = [
        "m", "min", "minor", "maj", "major",
        "dim", "diminished", "hdim", "halfdim", "half",
        "aug", "augmented", "sus", "suspended", "add", "alt", "altered",
        "flat", "sharp"
    ]

    private static let explicitAliasGlyphs: Set<String> = [
        "M", "o", "♯", "＃", "♭", "−", "–", "—", "Δ", "∆", "º", "Ø", "⌀",
        "•", "·", "∙", "%", "."
    ]

    private static let allowedSingleGlyphFragments: Set<String> = {
        var values = canonicalCharacters
        values.formUnion(explicitAliasGlyphs)
        for word in aliasWords {
            values.formUnion(word.map(String.init))
        }
        values.formUnion(rootInputLetters)
        return values
    }()

    private static let canonicalCharacters: Set<String> = {
        var values: Set<String> = []
        for atom in canonicalAtomicTokens {
            values.formUnion(atom.map(String.init))
        }
        return values
    }()

    private static let allowedChordInputCharacters: Set<String> = {
        var values = canonicalCharacters
        values.formUnion(explicitAliasGlyphs.subtracting(["•", "·", "∙", "%", "."]))
        values.formUnion(rootInputLetters)
        for word in aliasWords {
            for character in word {
                let lower = String(character)
                values.insert(lower)
                // Complete-word aliases are case-insensitive (`CMAJ7`). This
                // does not make standalone `J` an allowed model glyph/root;
                // the complete parser still must consume the entire word.
                values.insert(lower.uppercased())
            }
        }
        return values
    }()

    private static func isChordRepeatInput(_ text: String) -> Bool {
        let compact = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "·", with: "•")
            .replacingOccurrences(of: "∙", with: "•")
        return compact == ChordNotation.chordRepeat.canonicalDisplay
            || compact == "%"
            || compact == "./."
    }
}
