import Foundation

struct ChordRecognitionMatch: Hashable {
    var rawInput: String
    var symbol: ChordSymbol

    var displayText: String {
        symbol.displayText
    }
}

typealias BasicMajorChordMatch = ChordRecognitionMatch

enum ChordRecognitionCompendium {
    static let recognitionWords: [String] = entries.flatMap(\.aliases)
    static var supportedMatches: [ChordRecognitionMatch] {
        entries.map { entry in
            ChordRecognitionMatch(
                rawInput: entry.aliases.first ?? entry.symbol.displayText,
                symbol: entry.symbol
            )
        }
    }

    static func match(_ text: String) -> ChordRecognitionMatch? {
        guard !usesUnsupportedMajorSuffix(text) else {
            return nil
        }

        let normalizedInput = normalized(text)
        if let entry = entries.first(where: { entry in
            entry.normalizedAliases.contains(normalizedInput)
        }) {
            return ChordRecognitionMatch(rawInput: text, symbol: entry.symbol)
        }

        if let parsedSymbol = try? ChordSymbolParser.parse(text) {
            return ChordRecognitionMatch(rawInput: text, symbol: parsedSymbol)
        }

        return nil
    }

    static func match(candidates: [String]) -> ChordRecognitionMatch? {
        for candidate in candidates {
            if let match = match(candidate) {
                return match
            }
        }

        return nil
    }

    static func userFacingCandidateTexts(from candidates: [String]) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard let match = match(candidate) else {
                return nil
            }

            let displayText = match.displayText
            guard !seen.contains(displayText) else {
                return nil
            }

            seen.insert(displayText)
            return displayText
        }
    }

    fileprivate static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "＃", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "Δ", with: "△")
            .replacingOccurrences(of: "∆", with: "△")
            .replacingOccurrences(of: "º", with: "°")
            .replacingOccurrences(of: "Ø", with: "ø")
            .replacingOccurrences(of: "⌀", with: "ø")
            .replacingOccurrences(of: "FLAT", with: "b")
            .replacingOccurrences(of: "SHARP", with: "#")
            .filter { character in
                character.isLetter
                    || character.isNumber
                    || character == "#"
                    || character == "+"
                    || character == "-"
                    || character == "/"
                    || character == "△"
                    || character == "°"
                    || character == "ø"
            }
            .uppercased()
    }

    private static func usesUnsupportedMajorSuffix(_ text: String) -> Bool {
        let normalizedInput = normalized(text)
        let rootSpellings = baseEntries
            .map { normalized($0.displayText) }
            .sorted { $0.count > $1.count }
        guard let rootSpelling = rootSpellings.first(where: { normalizedInput.hasPrefix($0) }) else {
            return false
        }

        let suffix = String(normalizedInput.dropFirst(rootSpelling.count))
        guard !suffix.isEmpty else {
            return false
        }

        if (suffix == "M" || suffix.dropFirst().allSatisfy(\.isNumber)),
           text.contains("M"),
           !text.contains("m") {
            return true
        }

        return suffix == "MAJ" || suffix == "MAJOR"
    }

    private static let entries: [ChordRecognitionEntry] = baseEntries.flatMap { entry in
        [
            entry,
            entry.minorEntry,
            entry.augmentedEntry,
            entry.diminishedEntry,
            entry.diminishedSeventhEntry,
            entry.halfDiminishedSeventhEntry
        ]
    }

    private static let baseEntries: [ChordRecognitionEntry] = [
        ChordRecognitionEntry(root: .c, accidental: .natural, aliases: ["C"]),
        ChordRecognitionEntry(root: .c, accidental: .sharp, aliases: ["C#", "C sharp"]),
        ChordRecognitionEntry(root: .c, accidental: .flat, aliases: ["Cb", "C flat"]),
        ChordRecognitionEntry(root: .d, accidental: .natural, aliases: ["D"]),
        ChordRecognitionEntry(root: .d, accidental: .sharp, aliases: ["D#", "D sharp"]),
        ChordRecognitionEntry(root: .d, accidental: .flat, aliases: ["Db", "D flat"]),
        ChordRecognitionEntry(root: .e, accidental: .natural, aliases: ["E"]),
        ChordRecognitionEntry(root: .e, accidental: .sharp, aliases: ["E#", "E sharp"]),
        ChordRecognitionEntry(root: .e, accidental: .flat, aliases: ["Eb", "E flat"]),
        ChordRecognitionEntry(root: .f, accidental: .natural, aliases: ["F"]),
        ChordRecognitionEntry(root: .f, accidental: .sharp, aliases: ["F#", "F sharp"]),
        ChordRecognitionEntry(root: .f, accidental: .flat, aliases: ["Fb", "F flat"]),
        ChordRecognitionEntry(root: .g, accidental: .natural, aliases: ["G"]),
        ChordRecognitionEntry(root: .g, accidental: .sharp, aliases: ["G#", "G sharp"]),
        ChordRecognitionEntry(root: .g, accidental: .flat, aliases: ["Gb", "G flat"]),
        ChordRecognitionEntry(root: .a, accidental: .natural, aliases: ["A"]),
        ChordRecognitionEntry(root: .a, accidental: .sharp, aliases: ["A#", "A sharp"]),
        ChordRecognitionEntry(root: .a, accidental: .flat, aliases: ["Ab", "A flat"]),
        ChordRecognitionEntry(root: .b, accidental: .natural, aliases: ["B"]),
        ChordRecognitionEntry(root: .b, accidental: .sharp, aliases: ["B#", "B sharp"]),
        ChordRecognitionEntry(root: .b, accidental: .flat, aliases: ["Bb", "B flat"])
    ]
}

enum BasicMajorChordCompendium {
    static let recognitionWords = ChordRecognitionCompendium.recognitionWords
    static var supportedMatches: [BasicMajorChordMatch] {
        ChordRecognitionCompendium.supportedMatches
    }

    static func match(_ text: String) -> BasicMajorChordMatch? {
        ChordRecognitionCompendium.match(text)
    }

    static func match(candidates: [String]) -> BasicMajorChordMatch? {
        ChordRecognitionCompendium.match(candidates: candidates)
    }
}

private struct ChordRecognitionEntry: Hashable {
    var root: ChordRoot
    var accidental: Accidental
    var quality: String = ""
    var extensions: [String] = []
    var alterations: [String] = []
    var aliases: [String]

    var symbol: ChordSymbol {
        ChordSymbol(
            root: root,
            accidental: accidental,
            quality: quality,
            extensions: extensions,
            alterations: alterations,
            slashBass: nil
        )
    }

    var displayText: String {
        symbol.displayText
    }

    var minorEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "-",
            aliases: minorAliases
        )
    }

    var diminishedEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "°",
            aliases: diminishedAliases
        )
    }

    var augmentedEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "+",
            aliases: augmentedAliases
        )
    }

    var diminishedSeventhEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "°",
            extensions: ["7"],
            aliases: diminishedSeventhAliases
        )
    }

    var halfDiminishedSeventhEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "ø",
            extensions: ["7"],
            aliases: halfDiminishedSeventhAliases
        )
    }

    var normalizedAliases: Set<String> {
        Set(aliases.map(ChordRecognitionCompendium.normalized))
    }

    private var minorAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)-",
                "\(alias)m",
                "\(alias)min",
                "\(alias) minor"
            ]
        } + [
            "\(base)-",
            "\(base)m",
            "\(base)min",
            "\(base) minor"
        ]
    }

    private var diminishedAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)°",
                "\(alias)º",
                "\(alias)dim",
                "\(alias)diminished",
                "\(alias) diminished"
            ]
        } + [
            "\(base)°",
            "\(base)º",
            "\(base)dim",
            "\(base)diminished",
            "\(base) diminished"
        ]
    }

    private var augmentedAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)+",
                "\(alias)aug",
                "\(alias)augmented",
                "\(alias) augmented"
            ]
        } + [
            "\(base)+",
            "\(base)aug",
            "\(base)augmented",
            "\(base) augmented"
        ]
    }

    private var diminishedSeventhAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)°7",
                "\(alias)º7",
                "\(alias)dim7",
                "\(alias)diminished7",
                "\(alias) diminished7"
            ]
        } + [
            "\(base)°7",
            "\(base)º7",
            "\(base)dim7",
            "\(base)diminished7",
            "\(base) diminished7"
        ]
    }

    private var halfDiminishedSeventhAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)ø",
                "\(alias)ø7",
                "\(alias)Ø",
                "\(alias)Ø7",
                "\(alias)half-dim7",
                "\(alias)half dim7",
                "\(alias)halfdim7",
                "\(alias)half-diminished7",
                "\(alias)half diminished7",
                "\(alias)m7b5",
                "\(alias)min7b5",
                "\(alias)-7b5"
            ]
        } + [
            "\(base)ø",
            "\(base)ø7",
            "\(base)Ø",
            "\(base)Ø7",
            "\(base)half-dim7",
            "\(base)half dim7",
            "\(base)halfdim7",
            "\(base)half-diminished7",
            "\(base)half diminished7",
            "\(base)m7b5",
            "\(base)min7b5",
            "\(base)-7b5"
        ]
    }
}
