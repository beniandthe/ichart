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
    static let recognitionWords: [String] = chordRepeatAliases + entries.flatMap(\.aliases)
    static var supportedMatches: [ChordRecognitionMatch] {
        [ChordRecognitionMatch(
            rawInput: ChordSymbol.chordRepeatDisplayText,
            symbol: .chordRepeat
        )] + entries.map { entry in
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

        if ChordSymbolParser.isChordRepeatText(text) {
            return ChordRecognitionMatch(rawInput: text, symbol: .chordRepeat)
        }

        let normalizedInput = normalized(text)
        if let entry = entryByNormalizedAlias[normalizedInput] {
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
            .replacingOccurrences(of: "·", with: "•")
            .replacingOccurrences(of: "∙", with: "•")
            .replacingOccurrences(of: "FLAT", with: "b")
            .replacingOccurrences(of: "SHARP", with: "#")
            .filter { character in
                character.isLetter
                    || character.isNumber
                    || character == "#"
                    || character == "+"
                    || character == "-"
                    || character == "/"
                    || character == "%"
                    || character == "."
                    || character == "•"
                    || character == "△"
                    || character == "°"
                    || character == "ø"
            }
            .uppercased()
    }

    private static func usesUnsupportedMajorSuffix(_ text: String) -> Bool {
        let normalizedInput = normalized(text)
        guard let rootSpelling = normalizedRootSpellings.first(where: { normalizedInput.hasPrefix($0) }) else {
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

    private static let chordRepeatAliases = [
        ChordSymbol.chordRepeatDisplayText,
        "• / •",
        "%",
        "./."
    ]

    private static let entries: [ChordRecognitionEntry] = baseEntries.flatMap { entry in
        [
            entry,
            entry.minorEntry,
            entry.minorSixthEntry,
            entry.minorMajorSeventhEntry,
            entry.suspendedEntry,
            entry.suspendedFourthEntry,
            entry.dominantSuspendedEntry,
            entry.augmentedEntry,
            entry.alteredEntry,
            entry.diminishedEntry,
            entry.diminishedSeventhEntry,
            entry.halfDiminishedSeventhEntry
        ]
    }

    private static let entryByNormalizedAlias: [String: ChordRecognitionEntry] = {
        var index: [String: ChordRecognitionEntry] = [:]
        for entry in entries {
            for alias in entry.aliases {
                let normalizedAlias = normalized(alias)
                if index[normalizedAlias] == nil {
                    index[normalizedAlias] = entry
                }
            }
        }

        return index
    }()

    private static let normalizedRootSpellings: [String] = baseEntries
        .map { normalized($0.displayText) }
        .sorted { $0.count > $1.count }

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

    var suspendedEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "sus",
            aliases: suspendedAliases
        )
    }

    var minorSixthEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "-",
            extensions: ["6"],
            aliases: minorSixthAliases
        )
    }

    var minorMajorSeventhEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "-△",
            extensions: ["7"],
            aliases: minorMajorSeventhAliases
        )
    }

    var suspendedFourthEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "sus",
            extensions: ["4"],
            aliases: suspendedFourthAliases
        )
    }

    var dominantSuspendedEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "sus",
            extensions: ["7"],
            aliases: dominantSuspendedAliases
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

    var alteredEntry: ChordRecognitionEntry {
        ChordRecognitionEntry(
            root: root,
            accidental: accidental,
            quality: "alt",
            extensions: ["7"],
            aliases: alteredAliases
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

    private var minorSixthAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)-6",
                "\(alias)m6",
                "\(alias)m 6",
                "\(alias)min6",
                "\(alias)min 6",
                "\(alias)minor6",
                "\(alias) minor6",
                "\(alias) minor 6"
            ]
        } + [
            "\(base)-6",
            "\(base)m6",
            "\(base)m 6",
            "\(base)min6",
            "\(base)min 6",
            "\(base)minor6",
            "\(base) minor6",
            "\(base) minor 6"
        ]
    }

    private var minorMajorSeventhAliases: [String] {
        let base = displayText
        let triangleSpellings = ["△", "Δ", "∆"]
        return aliases.flatMap { alias in
            triangleSpellings.flatMap { triangle in
                [
                    "\(alias)-\(triangle)7",
                    "\(alias)m\(triangle)7",
                    "\(alias)m \(triangle)7",
                    "\(alias)min\(triangle)7",
                    "\(alias)min \(triangle)7",
                    "\(alias)minor\(triangle)7",
                    "\(alias) minor\(triangle)7",
                    "\(alias) minor \(triangle)7"
                ]
            }
        } + triangleSpellings.flatMap { triangle in
            [
                "\(base)-\(triangle)7",
                "\(base)m\(triangle)7",
                "\(base)m \(triangle)7",
                "\(base)min\(triangle)7",
                "\(base)min \(triangle)7",
                "\(base)minor\(triangle)7",
                "\(base) minor\(triangle)7",
                "\(base) minor \(triangle)7"
            ]
        }
    }

    private var suspendedAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)sus",
                "\(alias) sus",
                "\(alias)suspended",
                "\(alias) suspended"
            ]
        } + [
            "\(base)sus",
            "\(base) sus",
            "\(base)suspended",
            "\(base) suspended"
        ]
    }

    private var suspendedFourthAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)sus4",
                "\(alias) sus4",
                "\(alias)sus 4",
                "\(alias) sus 4",
                "\(alias)suspended4",
                "\(alias) suspended4",
                "\(alias)suspended 4",
                "\(alias) suspended 4"
            ]
        } + [
            "\(base)sus4",
            "\(base) sus4",
            "\(base)sus 4",
            "\(base) sus 4",
            "\(base)suspended4",
            "\(base) suspended4",
            "\(base)suspended 4",
            "\(base) suspended 4"
        ]
    }

    private var dominantSuspendedAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)7sus",
                "\(alias) 7sus",
                "\(alias)7 sus",
                "\(alias) 7 sus",
                "\(alias)7suspended",
                "\(alias) 7suspended",
                "\(alias)7 suspended",
                "\(alias) 7 suspended"
            ]
        } + [
            "\(base)7sus",
            "\(base) 7sus",
            "\(base)7 sus",
            "\(base) 7 sus",
            "\(base)7suspended",
            "\(base) 7suspended",
            "\(base)7 suspended",
            "\(base) 7 suspended"
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

    private var alteredAliases: [String] {
        let base = displayText
        return aliases.flatMap { alias in
            [
                "\(alias)alt",
                "\(alias) alt",
                "\(alias)7alt",
                "\(alias) 7alt",
                "\(alias)7 alt",
                "\(alias) 7 alt",
                "\(alias)altered",
                "\(alias) altered",
                "\(alias)7altered",
                "\(alias) 7altered",
                "\(alias)7 altered",
                "\(alias) 7 altered"
            ]
        } + [
            "\(base)alt",
            "\(base) alt",
            "\(base)7alt",
            "\(base) 7alt",
            "\(base)7 alt",
            "\(base) 7 alt",
            "\(base)altered",
            "\(base) altered",
            "\(base)7altered",
            "\(base) 7altered",
            "\(base)7 altered",
            "\(base) 7 altered"
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
