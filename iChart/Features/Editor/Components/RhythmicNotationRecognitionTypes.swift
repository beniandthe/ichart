#if canImport(UIKit)
import CoreGraphics
import Foundation

enum RhythmicNotationQuantizationError: LocalizedError, Hashable {
    case unsupportedSymbol(Int)
    case underfilled(expectedBeats: Double, actualBeats: Double)
    case overflow(expectedBeats: Double, actualBeats: Double)

    var errorDescription: String? {
        userFacingMessage
    }

    var userFacingMessage: String {
        switch self {
        case .unsupportedSymbol(let index):
            return "Measure \(index + 1) contains a rhythm symbol that couldn’t be matched yet. The measure is still selected so you can adjust or rewrite it."
        case .underfilled(let expectedBeats, let actualBeats):
            return "This rhythm only adds up to \(formattedBeats(actualBeats)) beats, but the measure needs \(formattedBeats(expectedBeats)). The measure is still selected so you can adjust or rewrite it."
        case .overflow(let expectedBeats, let actualBeats):
            return "This rhythm adds up to \(formattedBeats(actualBeats)) beats, which is more than the \(formattedBeats(expectedBeats)) beats allowed in this measure. The measure is still selected so you can adjust or rewrite it."
        }
    }

    private func formattedBeats(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }
}

enum RhythmicNotationMeasureProposalSafety: Hashable {
    case readyToRender
    case extendedStability
    case manualReview
}

struct RhythmicNotationMeasureProposal: Hashable {
    let values: [RhythmValue]
    let safety: RhythmicNotationMeasureProposalSafety
    let isNaturalExactFit: Bool
    let tieOutSlotIndices: Set<Int>

    init(
        values: [RhythmValue],
        safety: RhythmicNotationMeasureProposalSafety,
        isNaturalExactFit: Bool,
        tieOutSlotIndices: Set<Int> = []
    ) {
        self.values = values
        self.safety = safety
        self.isNaturalExactFit = isNaturalExactFit
        self.tieOutSlotIndices = tieOutSlotIndices
    }

    var canRenderWithoutReview: Bool {
        safety != .manualReview && isNaturalExactFit
    }

    var requiresExtendedStability: Bool {
        safety == .extendedStability
    }
}

enum RhythmGlyphEvidenceKind: String, Hashable {
    case filledNotehead
    case openNotehead
    case stem
    case singleBeam
    case doubleBeam
    case durationDot
    case tieArc
    case slash
    case quarterRestZigzag
    case eighthRestHook
    case sixteenthRestDoubleHook
    case halfRestBlock
    case wholeRestBlock
    case unknownStroke
}

struct RhythmGlyphEvidence: Hashable {
    let kind: RhythmGlyphEvidenceKind
    let strokeIndices: Set<Int>
    let bounds: CGRect
    let confidence: Double
}

enum RhythmPhraseSource: String, Hashable {
    case gridFirst
}

enum RhythmRecognitionReasoningPathKind: String, Hashable {
    case glyphOCR
    case contextRules
}

enum RhythmRecognitionReasoningPathOutcome: String, Hashable {
    case commitCandidate
    case keepWriting
    case needsReview
    case blocked
    case unavailable
}

struct RhythmRecognitionReasoningPath: Hashable {
    let kind: RhythmRecognitionReasoningPathKind
    let outcome: RhythmRecognitionReasoningPathOutcome
    let values: [RhythmValue]
    let reason: RhythmRecognitionReason?
    let summary: String
}

struct RhythmSymbolHypothesis: Hashable {
    let coveredStrokeIndices: Set<Int>
    let bounds: CGRect
    let candidateValues: [RhythmValue]
    let selectedValue: RhythmValue?
    let evidence: [RhythmGlyphEvidence]

    init(
        coveredStrokeIndices: Set<Int>,
        bounds: CGRect,
        candidateValues: [RhythmValue],
        selectedValue: RhythmValue?,
        evidence: [RhythmGlyphEvidence] = []
    ) {
        self.coveredStrokeIndices = coveredStrokeIndices
        self.bounds = bounds
        self.candidateValues = candidateValues
        self.selectedValue = selectedValue
        self.evidence = evidence
    }
}

struct RhythmVisualNoteAnchor: Hashable {
    let index: Int
    let center: CGPoint
    let bounds: CGRect
    let normalizedBounds: CGRect
}

struct RhythmPhraseHypothesis: Hashable {
    let source: RhythmPhraseSource
    let glyphEvidence: [RhythmGlyphEvidence]
    let symbols: [RhythmSymbolHypothesis]
    let uncoveredStrokeIndices: [Int]
    let naturalValues: [RhythmValue]
    let naturalUnits: Int
    let targetUnits: Int
    let passesCompendium: Bool
    var reasoningPaths: [RhythmRecognitionReasoningPath] = []

    init(
        source: RhythmPhraseSource,
        glyphEvidence: [RhythmGlyphEvidence] = [],
        symbols: [RhythmSymbolHypothesis],
        uncoveredStrokeIndices: [Int],
        naturalValues: [RhythmValue],
        naturalUnits: Int,
        targetUnits: Int,
        passesCompendium: Bool,
        reasoningPaths: [RhythmRecognitionReasoningPath] = []
    ) {
        self.source = source
        self.glyphEvidence = glyphEvidence
        self.symbols = symbols
        self.uncoveredStrokeIndices = uncoveredStrokeIndices
        self.naturalValues = naturalValues
        self.naturalUnits = naturalUnits
        self.targetUnits = targetUnits
        self.passesCompendium = passesCompendium
        self.reasoningPaths = reasoningPaths
    }

    var isNaturalExactFit: Bool {
        naturalUnits == targetUnits && passesCompendium
    }

    func withReasoningPaths(_ reasoningPaths: [RhythmRecognitionReasoningPath]) -> RhythmPhraseHypothesis {
        var copy = self
        copy.reasoningPaths = reasoningPaths
        return copy
    }
}

enum RhythmRecognitionDecision: Hashable {
    case commit(RhythmicNotationMeasureProposal, RhythmPhraseHypothesis)
    case keepWriting(RhythmRecognitionReason, RhythmPhraseHypothesis?)
    case needsReview(RhythmRecognitionReason, RhythmPhraseHypothesis?, RhythmicNotationMeasureProposal?)

    var proposal: RhythmicNotationMeasureProposal? {
        switch self {
        case .commit(let proposal, _):
            return proposal
        case .needsReview(_, _, let proposal):
            return proposal
        case .keepWriting:
            return nil
        }
    }

    var phrase: RhythmPhraseHypothesis? {
        switch self {
        case .commit(_, let phrase):
            return phrase
        case .keepWriting(_, let phrase):
            return phrase
        case .needsReview(_, let phrase, _):
            return phrase
        }
    }

    var reason: RhythmRecognitionReason? {
        switch self {
        case .commit:
            return nil
        case .keepWriting(let reason, _):
            return reason
        case .needsReview(let reason, _, _):
            return reason
        }
    }

    func addingReasoningPaths(_ reasoningPaths: [RhythmRecognitionReasoningPath]) -> RhythmRecognitionDecision {
        switch self {
        case .commit(let proposal, let phrase):
            return .commit(proposal, phrase.withReasoningPaths(reasoningPaths))
        case .keepWriting(let reason, let phrase):
            return .keepWriting(reason, phrase?.withReasoningPaths(reasoningPaths))
        case .needsReview(let reason, let phrase, let proposal):
            return .needsReview(reason, phrase?.withReasoningPaths(reasoningPaths), proposal)
        }
    }

    func reasoningPath(kind: RhythmRecognitionReasoningPathKind) -> RhythmRecognitionReasoningPath {
        let outcome: RhythmRecognitionReasoningPathOutcome
        switch self {
        case .commit:
            outcome = .commitCandidate
        case .keepWriting:
            outcome = .keepWriting
        case .needsReview:
            outcome = .needsReview
        }

        return RhythmRecognitionReasoningPath(
            kind: kind,
            outcome: outcome,
            values: proposal?.values ?? phrase?.naturalValues ?? [],
            reason: reason,
            summary: diagnosticSummary
        )
    }

    private var diagnosticSummary: String {
        let valueText = (proposal?.values ?? phrase?.naturalValues ?? [])
            .map(\.rawValue)
            .joined(separator: ",")
        let reasonText = reason?.rawValue ?? "none"
        let sourceText = phrase?.source.rawValue ?? "none"
        return "source=\(sourceText) reason=\(reasonText) values=\(valueText)"
    }
}

enum RhythmRecognitionReason: String, Hashable {
    case noInk
    case underfilled
    case overflow
    case unsupported
    case nonNaturalExactFit
    case ambiguousPhrase
    case manualReview
    case uncoveredStrokes
}
#endif
