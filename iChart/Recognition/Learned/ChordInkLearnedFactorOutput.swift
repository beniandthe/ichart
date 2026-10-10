import Foundation

/// Frozen semantic output contract for learned chord models.
///
/// These heads describe evidence only. They intentionally contain neither an
/// acceptance threshold nor a confidence value. Grammar filtering and any
/// independently fitted calibration happen after inference.
enum ChordInkLearnedOutputContract {
    static let version = "chord-ink-factor-output-v1"
    static let rasterShape = [1, ChordInkFeatureSchema.rasterHeight, ChordInkFeatureSchema.rasterWidth, 1]

    static let validityHeadName = "validity"
    static let kindHeadName = "kind"
    static let rootLetterHeadName = "root_letter"
    static let rootAccidentalHeadName = "root_accidental"
    static let qualityHeadName = "quality"
    static let extensionHeadName = "extension"
    static let alterationHeadName = "alteration_logits"
    static let slashPresenceHeadName = "slash_presence"
    static let slashBassLetterHeadName = "slash_bass_letter"
    static let slashBassAccidentalHeadName = "slash_bass_accidental"

}

enum ChordInkValidityFactorLabel: String, CaseIterable, Codable, Hashable, Sendable {
    case noRead = "no_read"
    case notation
}

enum ChordInkKindFactorLabel: String, CaseIterable, Codable, Hashable, Sendable {
    case rooted
    case chordRepeat = "chord_repeat"
}

enum ChordInkAccidentalFactorLabel: String, CaseIterable, Codable, Hashable, Sendable {
    case natural
    case sharp
    case flat

    var notation: ChordNotation.Accidental {
        switch self {
        case .natural: return .natural
        case .sharp: return .sharp
        case .flat: return .flat
        }
    }
}

enum ChordInkExtensionFactorLabel: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    case two = "2"
    case four = "4"
    case six = "6"
    case seven = "7"
    case nine = "9"
    case eleven = "11"
    case thirteen = "13"
    case sixNine = "6/9"

    var notation: ChordNotation.Extension? {
        switch self {
        case .none: return nil
        case .two: return .two
        case .four: return .four
        case .six: return .six
        case .seven: return .seven
        case .nine: return .nine
        case .eleven: return .eleven
        case .thirteen: return .thirteen
        case .sixNine: return .sixNine
        }
    }
}

enum ChordInkSlashPresenceFactorLabel: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    case present
}

/// A complete categorical logit head. Missing labels are invalid model output;
/// they are never silently assigned a default score.
struct ChordInkFactorLogits<Label>: Equatable, Sendable
where Label: Hashable & Sendable {
    let values: [Label: Double]

    init(_ values: [Label: Double]) {
        self.values = values
    }
}

struct ChordInkLearnedFactorOutput: Equatable, Sendable {
    let contractVersion: String
    let validity: ChordInkFactorLogits<ChordInkValidityFactorLabel>
    let kind: ChordInkFactorLogits<ChordInkKindFactorLabel>
    let rootLetter: ChordInkFactorLogits<ChordNotation.Letter>
    let rootAccidental: ChordInkFactorLogits<ChordInkAccidentalFactorLabel>
    let quality: ChordInkFactorLogits<ChordNotation.Form>
    let extensionTone: ChordInkFactorLogits<ChordInkExtensionFactorLabel>
    /// Seven independent Bernoulli logits, one for every typed alteration.
    /// These are not a categorical softmax and therefore have no `none` label.
    let alterations: ChordInkFactorLogits<ChordNotation.Alteration>
    let slashPresence: ChordInkFactorLogits<ChordInkSlashPresenceFactorLabel>
    let slashBassLetter: ChordInkFactorLogits<ChordNotation.Letter>
    let slashBassAccidental: ChordInkFactorLogits<ChordInkAccidentalFactorLabel>

    init(
        contractVersion: String = ChordInkLearnedOutputContract.version,
        validity: ChordInkFactorLogits<ChordInkValidityFactorLabel>,
        kind: ChordInkFactorLogits<ChordInkKindFactorLabel>,
        rootLetter: ChordInkFactorLogits<ChordNotation.Letter>,
        rootAccidental: ChordInkFactorLogits<ChordInkAccidentalFactorLabel>,
        quality: ChordInkFactorLogits<ChordNotation.Form>,
        extensionTone: ChordInkFactorLogits<ChordInkExtensionFactorLabel>,
        alterations: ChordInkFactorLogits<ChordNotation.Alteration>,
        slashPresence: ChordInkFactorLogits<ChordInkSlashPresenceFactorLabel>,
        slashBassLetter: ChordInkFactorLogits<ChordNotation.Letter>,
        slashBassAccidental: ChordInkFactorLogits<ChordInkAccidentalFactorLabel>
    ) {
        self.contractVersion = contractVersion
        self.validity = validity
        self.kind = kind
        self.rootLetter = rootLetter
        self.rootAccidental = rootAccidental
        self.quality = quality
        self.extensionTone = extensionTone
        self.alterations = alterations
        self.slashPresence = slashPresence
        self.slashBassLetter = slashBassLetter
        self.slashBassAccidental = slashBassAccidental
    }
}
