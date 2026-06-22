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
    case autoApply
    case extendedStability
    case manualReview
}

struct RhythmicNotationMeasureProposal: Hashable {
    let values: [RhythmValue]
    let safety: RhythmicNotationMeasureProposalSafety
    let isNaturalExactFit: Bool

    var canAutoApply: Bool {
        safety != .manualReview && isNaturalExactFit
    }

    var requiresExtendedStability: Bool {
        safety == .extendedStability
    }
}

enum RhythmInkPrimitiveKind: String, Hashable {
    case notehead
    case stem
    case beam
    case dot
    case slash
    case restShape
    case cleanup
    case unknown
}

struct RhythmInkPrimitive: Hashable {
    let strokeIndex: Int
    let kind: RhythmInkPrimitiveKind
    let bounds: CGRect
}

enum RhythmPhraseSource: String, Hashable {
    case gridFirst
    case rasterTemplate
    case visual
    case legacyFallback
}

enum RhythmRecognitionReasoningPathKind: String, Hashable {
    case rasterTemplate
    case visualShape
    case legacyFallback
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
}

struct RhythmPhraseHypothesis: Hashable {
    let source: RhythmPhraseSource
    let primitives: [RhythmInkPrimitive]
    let symbols: [RhythmSymbolHypothesis]
    let uncoveredStrokeIndices: [Int]
    let naturalValues: [RhythmValue]
    let naturalUnits: Int
    let targetUnits: Int
    let passesCompendium: Bool
    var reasoningPaths: [RhythmRecognitionReasoningPath] = []

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
    case nonVisualFallback
    case uncoveredStrokes
    case competingExactPhrases
}

struct RhythmCandidate: Hashable {
    let value: RhythmValue
    let score: Double
    var canDriveExactFit: Bool = true
    var canExtendAutoApplyStability: Bool = false

    var isConfidentEnoughForMeasureFit: Bool {
        canDriveExactFit && score <= 1.15
    }
}

struct CandidatePath: Hashable {
    let values: [RhythmValue]
    let score: Double
    let units: Int
}
#endif
