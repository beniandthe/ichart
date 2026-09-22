import Foundation

enum ChordInkLearnedLegacyBridgeError: Error, Equatable, Sendable {
    case nonFiniteNoReadLogScore
    case positiveNoReadLogScore
    case nonFiniteCandidateLogScore(String)
    case positiveCandidateLogScore(String)
    case duplicateCanonicalCandidate(String)
}

struct ChordInkLearnedLegacyReviewCandidate: Equatable {
    let notation: ChordNotation
    let canonicalText: String
    let symbol: ChordSymbol
    let rawJointLogScore: Double
}

enum ChordInkLearnedLegacyDisposition: Equatable, Sendable {
    case noRead
    case reviewRequired
}

/// Review-only projection of learned decoder output into the app's existing
/// recognition result domain.
///
/// Raw joint log scores are retained in typed candidates, but never relabeled
/// as legacy confidence. Until independent calibration and the sealed gate
/// grant learned authority, this type cannot produce a prefilling or
/// persistable symbol and never populates `ChordInkRecognitionResult.match`.
struct ChordInkLearnedLegacyBridgeOutput: Equatable {
    let disposition: ChordInkLearnedLegacyDisposition
    let candidates: [ChordInkLearnedLegacyReviewCandidate]
    let noReadLogScore: Double
    let recognitionResult: ChordInkRecognitionResult

    var symbolForPrefill: ChordSymbol? { nil }
    var symbolForPersistence: ChordSymbol? { nil }
}

enum ChordInkLearnedLegacyBridge {
    static func reviewOnlyOutput(
        from decodeResult: ChordInkLearnedDecodeResult
    ) throws -> ChordInkLearnedLegacyBridgeOutput {
        guard decodeResult.noReadLogScore.isFinite else {
            throw ChordInkLearnedLegacyBridgeError.nonFiniteNoReadLogScore
        }
        guard decodeResult.noReadLogScore <= 0 else {
            throw ChordInkLearnedLegacyBridgeError.positiveNoReadLogScore
        }

        var seenCanonicalTexts = Set<String>()
        let candidates = try decodeResult.candidates.map { candidate in
            let canonicalText = candidate.notation.canonicalDisplay
            guard candidate.rawJointLogScore.isFinite else {
                throw ChordInkLearnedLegacyBridgeError.nonFiniteCandidateLogScore(canonicalText)
            }
            guard candidate.rawJointLogScore <= 0 else {
                throw ChordInkLearnedLegacyBridgeError.positiveCandidateLogScore(canonicalText)
            }
            guard seenCanonicalTexts.insert(canonicalText).inserted else {
                throw ChordInkLearnedLegacyBridgeError.duplicateCanonicalCandidate(canonicalText)
            }

            return ChordInkLearnedLegacyReviewCandidate(
                notation: candidate.notation,
                canonicalText: canonicalText,
                symbol: try ChordNotationLegacyBridge.symbol(for: candidate.notation),
                rawJointLogScore: candidate.rawJointLogScore
            )
        }

        let recognitionResult = ChordInkRecognitionResult(
            rawCandidates: candidates.map(\.canonicalText),
            glyphCandidates: [],
            match: nil,
            confidence: 0,
            candidateScores: [],
            reviewCandidateScores: candidates.map { candidate in
                ChordInkCandidateScore(
                    text: candidate.canonicalText,
                    displayText: candidate.symbol.displayText,
                    confidence: 0
                )
            },
            metrics: ChordInkRecognitionMetrics(
                rawCandidateCount: candidates.count
            )
        )

        return ChordInkLearnedLegacyBridgeOutput(
            disposition: candidates.isEmpty ? .noRead : .reviewRequired,
            candidates: candidates,
            noReadLogScore: decodeResult.noReadLogScore,
            recognitionResult: recognitionResult
        )
    }
}
