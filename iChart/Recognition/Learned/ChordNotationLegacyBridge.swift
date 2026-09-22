import Foundation

enum ChordNotationLegacyBridgeError: Error, Equatable, Sendable {
    case unsupportedLegacyQuality(String)
    case unsupportedLegacyExtension([String])
    case unsupportedLegacyAlteration(String)
    case unsupportedLegacySlashBass(String)
    case semanticRoundTripMismatch(expected: String, actual: String)
}

/// Lossless semantic bridge between the strict recognition grammar and the
/// chart model already persisted by the app.
///
/// This bridge does not use `ChordSymbolParser`: that parser intentionally
/// accepts musician-friendly aliases, while learned output must remain inside
/// the exact typed grammar. An exhaustive mapping plus a structural round trip
/// makes future grammar/model drift fail closed.
enum ChordNotationLegacyBridge {
    static func symbol(for notation: ChordNotation) throws -> ChordSymbol {
        let symbol: ChordSymbol
        switch notation {
        case .chordRepeat:
            symbol = .chordRepeat

        case .rooted(let rooted):
            symbol = ChordSymbol(
                root: legacyRoot(rooted.root.letter),
                accidental: legacyAccidental(rooted.root.accidental),
                quality: legacyQuality(rooted.form),
                extensions: legacyExtensions(rooted.extensionTone),
                alterations: rooted.alterations.map(\.rawValue),
                slashBass: rooted.slashBass?.canonicalDisplay
            )
        }

        let roundTripped = try Self.notation(for: symbol)
        guard roundTripped == notation else {
            throw ChordNotationLegacyBridgeError.semanticRoundTripMismatch(
                expected: notation.canonicalDisplay,
                actual: roundTripped.canonicalDisplay
            )
        }
        return symbol
    }

    /// Strict inverse used to verify that a legacy symbol has an exact typed
    /// meaning. Friendly legacy aliases are deliberately rejected here.
    static func notation(for symbol: ChordSymbol) throws -> ChordNotation {
        guard symbol.kind == .rooted else {
            return .chordRepeat
        }

        let slashBass: ChordNotation.Pitch?
        if let rawSlashBass = symbol.slashBass {
            guard let parsed = ChordNotation.Pitch.parseCanonical(rawSlashBass) else {
                throw ChordNotationLegacyBridgeError.unsupportedLegacySlashBass(rawSlashBass)
            }
            slashBass = parsed
        } else {
            slashBass = nil
        }

        let alterations = try symbol.alterations.map { value in
            guard let alteration = ChordNotation.Alteration(rawValue: value) else {
                throw ChordNotationLegacyBridgeError.unsupportedLegacyAlteration(value)
            }
            return alteration
        }

        let rooted = try ChordNotation.Rooted(
            root: ChordNotation.Pitch(
                letter: notationLetter(symbol.root),
                accidental: notationAccidental(symbol.accidental)
            ),
            form: try notationForm(symbol.quality),
            extensionTone: try notationExtension(symbol.extensions),
            alterations: alterations,
            slashBass: slashBass
        )
        return .rooted(rooted)
    }

    private static func legacyRoot(_ letter: ChordNotation.Letter) -> ChordRoot {
        switch letter {
        case .a: return .a
        case .b: return .b
        case .c: return .c
        case .d: return .d
        case .e: return .e
        case .f: return .f
        case .g: return .g
        }
    }

    private static func notationLetter(_ root: ChordRoot) -> ChordNotation.Letter {
        switch root {
        case .a: return .a
        case .b: return .b
        case .c: return .c
        case .d: return .d
        case .e: return .e
        case .f: return .f
        case .g: return .g
        }
    }

    private static func legacyAccidental(_ accidental: ChordNotation.Accidental) -> Accidental {
        switch accidental {
        case .natural: return .natural
        case .sharp: return .sharp
        case .flat: return .flat
        }
    }

    private static func notationAccidental(_ accidental: Accidental) -> ChordNotation.Accidental {
        switch accidental {
        case .natural: return .natural
        case .sharp: return .sharp
        case .flat: return .flat
        }
    }

    private static func legacyQuality(_ form: ChordNotation.Form) -> String {
        switch form {
        case .plain: return ""
        case .minor: return "-"
        case .explicitMajor: return "△"
        case .minorMajor: return "-△"
        case .augmented: return "+"
        case .diminished: return "°"
        case .halfDiminished: return "ø"
        case .suspended: return "sus"
        case .addedTone: return "add"
        case .altered: return "alt"
        }
    }

    private static func notationForm(_ quality: String) throws -> ChordNotation.Form {
        switch quality {
        case "": return .plain
        case "-": return .minor
        case "△": return .explicitMajor
        case "-△": return .minorMajor
        case "+": return .augmented
        case "°": return .diminished
        case "ø": return .halfDiminished
        case "sus": return .suspended
        case "add": return .addedTone
        case "alt": return .altered
        default:
            throw ChordNotationLegacyBridgeError.unsupportedLegacyQuality(quality)
        }
    }

    private static func legacyExtensions(_ extensionTone: ChordNotation.Extension?) -> [String] {
        switch extensionTone {
        case nil:
            return []
        case .sixNine:
            return ["6", "9"]
        case .some(let extensionTone):
            return [extensionTone.rawValue]
        }
    }

    private static func notationExtension(
        _ extensions: [String]
    ) throws -> ChordNotation.Extension? {
        if extensions.isEmpty {
            return nil
        }
        if extensions == ["6", "9"] {
            return .sixNine
        }
        if extensions.count == 1,
           let extensionTone = ChordNotation.Extension(rawValue: extensions[0]) {
            return extensionTone
        }
        throw ChordNotationLegacyBridgeError.unsupportedLegacyExtension(extensions)
    }
}
