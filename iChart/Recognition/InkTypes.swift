import Foundation

enum InkClusterRecognitionHint: String, Codable, Hashable {
    case parenthesizedAlteration
}

struct InkCluster: Codable, Hashable {
    var strokes: [InkStroke]
    var bounds: InkBounds
    var startTimeOffset: TimeInterval?
    var endTimeOffset: TimeInterval?
    var recognitionHints: Set<InkClusterRecognitionHint>?

    init(
        strokes: [InkStroke],
        bounds: InkBounds? = nil,
        startTimeOffset: TimeInterval? = nil,
        endTimeOffset: TimeInterval? = nil,
        recognitionHints: Set<InkClusterRecognitionHint>? = nil
    ) {
        self.strokes = strokes
        self.bounds = bounds ?? InkBounds.enclosing(strokes.map(\.bounds))
        self.startTimeOffset = startTimeOffset ?? strokes
            .flatMap(\.points)
            .compactMap(\.timeOffset)
            .min()
        self.endTimeOffset = endTimeOffset ?? strokes
            .flatMap(\.points)
            .compactMap(\.timeOffset)
            .max()
        self.recognitionHints = recognitionHints
    }

    func hasRecognitionHint(_ hint: InkClusterRecognitionHint) -> Bool {
        recognitionHints?.contains(hint) == true
    }
}

struct IndexedInkCluster: Hashable {
    var cluster: InkCluster
    var originalIndexes: [Int]

    var strokes: [InkStroke] {
        cluster.strokes
    }

    var bounds: InkBounds {
        cluster.bounds
    }
}

struct ChordInkBatchCluster: Hashable {
    var strokeIndices: [Int]
    var bounds: InkBounds

    var isUsable: Bool {
        bounds.width >= 4 || bounds.height >= 4
    }
}

enum ChordInkBatchClusterer {
    static let maximumClusterCount = 12

    static func clusters(for strokes: [InkStroke]) -> [ChordInkBatchCluster] {
        let indexedStrokes = strokes.enumerated()
            .filter { _, stroke in
                stroke.bounds.width >= 1 || stroke.bounds.height >= 1
            }
            .sorted { lhs, rhs in
                if lhs.element.bounds.minX == rhs.element.bounds.minX {
                    return lhs.offset < rhs.offset
                }

                return lhs.element.bounds.minX < rhs.element.bounds.minX
            }

        guard indexedStrokes.count > 1 else {
            return indexedStrokes.map { indexedStroke in
                ChordInkBatchCluster(
                    strokeIndices: [indexedStroke.offset],
                    bounds: indexedStroke.element.bounds
                )
            }
        }

        let splitGap = horizontalSplitGap(for: indexedStrokes.map(\.element))
        var clusters = [ChordInkBatchCluster]()
        var currentIndices = [Int]()
        var currentBounds: InkBounds?

        for indexedStroke in indexedStrokes {
            let stroke = indexedStroke.element
            if let bounds = currentBounds {
                let gap = stroke.bounds.minX - bounds.maxX
                if gap > splitGap {
                    clusters.append(
                        ChordInkBatchCluster(
                            strokeIndices: currentIndices,
                            bounds: bounds
                        )
                    )
                    currentIndices = [indexedStroke.offset]
                    currentBounds = stroke.bounds
                } else {
                    currentIndices.append(indexedStroke.offset)
                    currentBounds = bounds.union(stroke.bounds)
                }
            } else {
                currentIndices = [indexedStroke.offset]
                currentBounds = stroke.bounds
            }
        }

        if let currentBounds {
            clusters.append(
                ChordInkBatchCluster(
                    strokeIndices: currentIndices,
                    bounds: currentBounds
                )
            )
        }

        let usableClusters = clusters.filter(\.isUsable)
        guard usableClusters.count <= maximumClusterCount else {
            return [ChordInkBatchCluster(strokeIndices: indexedStrokes.map(\.offset), bounds: InkBounds.enclosing(indexedStrokes.map(\.element.bounds)))]
        }

        return usableClusters
    }

    private static func horizontalSplitGap(for strokes: [InkStroke]) -> Double {
        let heights = strokes
            .map(\.bounds.height)
            .filter { $0 > 0 }
            .sorted()
        let medianHeight = heights.isEmpty ? 0 : heights[heights.count / 2]
        return max(36, min(70, medianHeight * 0.9))
    }
}

enum RecognitionSource: String, Codable, Hashable {
    case template
    case heuristic
    case composer
}

struct GlyphCandidate: Hashable {
    var text: String
    var confidence: Double
    var source: RecognitionSource
}

struct ChordInkCandidateScore: Codable, Hashable {
    var text: String
    var displayText: String?
    var confidence: Double

    var isSupported: Bool {
        displayText != nil
    }
}

struct ChordInkCandidateCompositionMetrics: Codable, Hashable {
    var selectedColumnCount: Int = 0
    var generatedSequenceCount: Int = 0
    var returnedCandidateCount: Int = 0
    var maxGeneratedSequences: Int = 0
    var hitGeneratedSequenceLimit: Bool = false
}

struct ChordInkRecognitionMetrics: Codable, Hashable {
    var clusterMilliseconds: Double = 0
    var glyphMilliseconds: Double = 0
    var contextualGlyphMilliseconds: Double = 0
    var composeMilliseconds: Double = 0
    var semanticMilliseconds: Double = 0
    var matchMilliseconds: Double = 0
    var totalMilliseconds: Double = 0
    var strokeCount: Int = 0
    var clusterCount: Int = 0
    var glyphCandidateColumnCount: Int = 0
    var semanticCandidateCount: Int = 0
    var rawCandidateCount: Int = 0
    var compositionMetrics: ChordInkCandidateCompositionMetrics = ChordInkCandidateCompositionMetrics()
}

struct ChordInkRecognitionOptions: Hashable {
    var includesSymbolLedgerDiagnostics: Bool = false

    static let live = ChordInkRecognitionOptions()
    static let includingSymbolLedgerDiagnostics = ChordInkRecognitionOptions(
        includesSymbolLedgerDiagnostics: true
    )
}

struct ChordInkRecognitionResult: Hashable {
    var rawCandidates: [String]
    var glyphCandidates: [[GlyphCandidate]]
    var match: ChordRecognitionMatch?
    var confidence: Double
    var acceptedGlyphCandidates: [GlyphCandidate] = []
    var candidateScores: [ChordInkCandidateScore] = []
    /// Rejection-only evidence, not a candidate or alternative chord. Preserves
    /// caution when invalid complete strings are removed from scored candidates.
    var rejectedCandidateConfidence: Double? = nil
    /// Grammar-supported alternatives offered only in the explicit review UI.
    /// Automatic recognition policy deliberately ignores these scores.
    var reviewCandidateScores: [ChordInkCandidateScore] = []
    /// Explicit root-conflict recoveries that need a visible review slot.
    /// Like reviewCandidateScores, these never enter the automatic decision.
    var reviewRootAlternatives: [String] = []
    /// Personal evidence is review-only and must never enter base trust scoring.
    var personalSuggestion: ChordInkPersonalSuggestion? = nil
    var personalizationRevision: UUID? = nil
    var symbolLedger: ChordInkSymbolLedgerSnapshot? = nil
    var symbolLedgerAssessment: ChordInkSymbolLedgerAssessment? = nil
    var trustEvidence: ChordInkTrustEvidence? = nil
    /// Request-local ownership context, never part of the recognizer cache.
    /// A partial erase cannot establish that the remaining root is complete.
    var requiresEditReview: Bool = false
    var metrics: ChordInkRecognitionMetrics = ChordInkRecognitionMetrics()
}

enum ChordInkTrustEvidenceOutcome: String, Codable, Hashable, CaseIterable {
    case corroborated
    case insufficientSymbolEvidence
    case insufficientCapturedFamilyEvidence
    case insufficientPointDensity
    case conflictingExtensionEvidence
    case conflictingAccidentalEvidence
    case conflictingAlterationEvidence
    case conflictingQualityEvidence
    case implausibleRootGeometry
    case unstableUnderPointDensity
    case unstableUnderScale
    case unstableUnderCounterclockwiseRotation
    case unstableUnderClockwiseRotation
}

/// Corroborating evidence required before a high-confidence chord is allowed
/// to render without confirmation. The evidence intentionally contains no chord
/// text or stroke data so it is also safe to summarize in diagnostics.
struct ChordInkTrustEvidence: Codable, Hashable {
    var outcome: ChordInkTrustEvidenceOutcome
    var symbolSupportCount: Int
    var completedProbeCount: Int
    var requiredProbeCount: Int
    var validationMilliseconds: Double

    var isCorroborated: Bool {
        outcome == .corroborated
            && completedProbeCount == requiredProbeCount
    }
}

enum ChordInkRecognitionAction: Codable, Hashable {
    case trusted
    case confirm

    var rawValue: String {
        switch self {
        case .trusted:
            return "trusted"
        case .confirm:
            return "confirm"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "trusted", "autoRender":
            self = .trusted
        case "confirm":
            self = .confirm
        default:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let action = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown chord ink recognition action: \(rawValue)"
            )
        }

        self = action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ChordInkContinuationGracePolicy {
    static func shouldWaitForPossibleContinuation(
        result: ChordInkRecognitionResult,
        strokeCount: Int
    ) -> Bool {
        guard strokeCount <= 8,
              let symbol = result.match?.symbol,
              symbol.kind == .rooted,
              symbol.alterations.isEmpty,
              symbol.slashBass == nil,
              symbol.extensions.count <= 1 else {
            return false
        }

        return true
    }
}

struct ChordInkRecognitionDecision: Hashable {
    var action: ChordInkRecognitionAction
    var acceptedText: String?
    var reason: String
    var isCloseRace: Bool
    var competingCandidateText: String?
    var confidenceGap: Double?
}

enum ChordInkRecognitionPolicy {
    static let trustedMinimumConfidence = 3.95
    static let closeRaceConfidenceGap = 0.04
    private static let uncommonRootSpellingConfirmationGap = 0.08
    private static let weakSingleCandidateRootConfidence = 0.76
    private static let ambiguousSingleCandidateRootGap = 0.08
    private static let ambiguousAcceptedRootGlyphRaceGap = 0.08
    private static let unsupportedCandidatePressureGap = 0.02

    /// Compare native evidence with a personal suggestion independently of the
    /// request's edit-review requirement. This is not permission to render:
    /// callers must still use decision(for:) for the actual user-facing action.
    static func recognitionEvidenceDecision(for result: ChordInkRecognitionResult) -> ChordInkRecognitionDecision {
        var evidence = result
        evidence.requiresEditReview = false
        return decision(for: evidence)
    }

    static func decision(for result: ChordInkRecognitionResult) -> ChordInkRecognitionDecision {
        if result.requiresEditReview {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: result.match?.displayText,
                reason: "This chord was edited. Check the complete chord before rendering.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
        }
        guard let match = result.match else {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: nil,
                reason: "No reliable read yet. Type the chord you meant, then use it on the chart.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
        }

        let rankedScores = rankedSupportedScores(for: result)
        let acceptedText = match.displayText
        let bestScore = rankedScores.first { $0.displayText == acceptedText }
        let bestConfidence = max(result.confidence, bestScore?.confidence ?? 0)

        guard bestConfidence >= trustedMinimumConfidence else {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: acceptedText,
                reason: "Low-confidence read. Choose a suggestion or type the chord you meant.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
        }

        // Prefer the specific musician-facing trust explanation over a generic
        // candidate-budget message. Maximum-trust validation may deliberately
        // mark an otherwise strong long chord as handwriting-unproven even when
        // its bounded candidate beam also reached the safety limit.
        if let trustEvidence = result.trustEvidence,
           !trustEvidence.isCorroborated {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: acceptedText,
                reason: confirmationReason(for: trustEvidence.outcome),
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
        }

        if result.metrics.compositionMetrics.hitGeneratedSequenceLimit {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: acceptedText,
                reason: "Recognition candidate limit hit. Choose a suggestion or type the chord you meant.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
        }

        if hasUnsupportedCandidatePressure(
            result: result,
            bestConfidence: bestConfidence
        ) {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: acceptedText,
                reason: "Unsupported high-confidence read. Choose a suggestion or type the chord you meant.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
        }

        if shouldConfirmMissingRootEvidence(
            acceptedText: acceptedText,
            glyphCandidates: result.glyphCandidates
        ) {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: acceptedText,
                reason: "No clear root evidence. Choose a suggestion or type the chord you meant.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
        }

        if shouldConfirmSingleCandidateWithWeakRoot(
            acceptedText: acceptedText,
            rankedScores: rankedScores,
            glyphCandidates: result.glyphCandidates
        ) {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: acceptedText,
                reason: "Ambiguous root read. Choose a suggestion or type the chord you meant.",
                isCloseRace: false,
                competingCandidateText: nil,
                confidenceGap: nil
            )
        }

        if let rootRace = acceptedRootGlyphRace(
            acceptedText: acceptedText,
            glyphCandidates: result.glyphCandidates
        ) {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: acceptedText,
                reason: "Ambiguous root read. Choose a suggestion or type the chord you meant.",
                isCloseRace: true,
                competingCandidateText: rootRace.runnerUpRoot,
                confidenceGap: rootRace.absoluteGapToRunnerUp
            )
        }

        if let runnerUp = rankedScores.first(where: { $0.displayText != acceptedText }),
           let competingText = runnerUp.displayText {
            let gap = bestConfidence - runnerUp.confidence
            if shouldConfirmUncommonSpellingWinner(
                acceptedText: acceptedText,
                competingText: competingText,
                gap: gap
            ) {
                return ChordInkRecognitionDecision(
                    action: .confirm,
                    acceptedText: acceptedText,
                    reason: "Close uncommon spelling. Choose the chord you meant, or type it in.",
                    isCloseRace: true,
                    competingCandidateText: competingText,
                    confidenceGap: gap
                )
            }

            if gap <= closeRaceConfidenceGap {
                if shouldTrustCloseSpellingRace(
                    acceptedText: acceptedText,
                    competingText: competingText,
                    gap: gap
                ) {
                    return ChordInkRecognitionDecision(
                        action: .trusted,
                        acceptedText: acceptedText,
                        reason: "Trusted read.",
                        isCloseRace: false,
                        competingCandidateText: nil,
                        confidenceGap: nil
                    )
                }

                return ChordInkRecognitionDecision(
                    action: .confirm,
                    acceptedText: acceptedText,
                    reason: "Close race. Choose the chord you meant, or type it in.",
                    isCloseRace: true,
                    competingCandidateText: competingText,
                    confidenceGap: gap
                )
            }
        }

        return ChordInkRecognitionDecision(
            action: .trusted,
            acceptedText: acceptedText,
            reason: "Trusted read.",
            isCloseRace: false,
            competingCandidateText: nil,
            confidenceGap: nil
        )
    }

    private static func confirmationReason(
        for outcome: ChordInkTrustEvidenceOutcome
    ) -> String {
        switch outcome {
        case .corroborated:
            return "Choose a suggestion or type the chord you meant."
        case .insufficientSymbolEvidence:
            return "I couldn't verify every part of this chord. Choose a suggestion or type it in."
        case .insufficientCapturedFamilyEvidence:
            return "This chord form still needs handwriting confirmation. Choose the suggestion or type it in."
        case .insufficientPointDensity:
            return "This chord is too sparse to place confidently. Choose a suggestion or type it in."
        case .conflictingExtensionEvidence:
            return "The extension could be read more than one way. Choose a suggestion or type it in."
        case .conflictingAccidentalEvidence:
            return "The accidental could be read more than one way. Choose a suggestion or type it in."
        case .conflictingAlterationEvidence:
            return "The alteration could be read more than one way. Choose a suggestion or type it in."
        case .conflictingQualityEvidence:
            return "The chord quality could be read more than one way. Choose a suggestion or type it in."
        case .implausibleRootGeometry:
            return "This mark doesn't have a reliable chord-root shape. Choose a suggestion or type the chord you meant."
        case .unstableUnderPointDensity,
             .unstableUnderScale,
             .unstableUnderCounterclockwiseRotation,
             .unstableUnderClockwiseRotation:
            return "Small variations change this read. Choose a suggestion or type the chord you meant."
        }
    }

    static func rankedSupportedScores(for result: ChordInkRecognitionResult) -> [ChordInkCandidateScore] {
        var bestByDisplayText: [String: ChordInkCandidateScore] = [:]

        for score in result.candidateScores {
            guard let displayText = score.displayText else {
                continue
            }

            if let current = bestByDisplayText[displayText],
               current.confidence >= score.confidence {
                continue
            }

            bestByDisplayText[displayText] = score
        }

        if let match = result.match,
           bestByDisplayText[match.displayText] == nil {
            bestByDisplayText[match.displayText] = ChordInkCandidateScore(
                text: match.displayText,
                displayText: match.displayText,
                confidence: result.confidence
            )
        }

        return bestByDisplayText.values.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return (lhs.displayText ?? lhs.text) < (rhs.displayText ?? rhs.text)
        }
    }

    private static func shouldTrustCloseSpellingRace(
        acceptedText: String,
        competingText: String,
        gap: Double
    ) -> Bool {
        gap >= 0.04
            && !hasUncommonRootSpelling(acceptedText)
            && hasUncommonRootSpelling(competingText)
    }

    private static func shouldConfirmUncommonSpellingWinner(
        acceptedText: String,
        competingText: String,
        gap: Double
    ) -> Bool {
        gap <= uncommonRootSpellingConfirmationGap
            && hasUncommonRootSpelling(acceptedText)
            && !hasUncommonRootSpelling(competingText)
    }

    private static func hasUncommonRootSpelling(_ text: String) -> Bool {
        guard let symbol = try? ChordSymbolParser.parse(text),
              symbol.kind == .rooted else {
            return false
        }

        return ["B#", "E#", "Cb", "Fb"].contains("\(symbol.root.rawValue)\(symbol.accidental.rawValue)")
    }

    private static func hasUnsupportedCandidatePressure(
        result: ChordInkRecognitionResult,
        bestConfidence: Double
    ) -> Bool {
        // Defensive compatibility for manually constructed/older result sources;
        // the native reader now emits only supported candidateScores.
        let legacyRejectedConfidence = result.candidateScores
            .filter({ $0.displayText == nil })
            .map(\.confidence).max()
        guard let strongestRejected = [result.rejectedCandidateConfidence, legacyRejectedConfidence]
            .compactMap({ $0 }).max() else {
            return false
        }

        return strongestRejected + unsupportedCandidatePressureGap >= bestConfidence
    }

    private static func shouldConfirmMissingRootEvidence(
        acceptedText: String,
        glyphCandidates: [[GlyphCandidate]]
    ) -> Bool {
        guard !glyphCandidates.isEmpty,
              let acceptedSymbol = try? ChordSymbolParser.parse(acceptedText),
              acceptedSymbol.kind == .rooted else {
            return false
        }

        return rootGlyphEvidence(
            for: acceptedSymbol.root.rawValue,
            glyphCandidates: glyphCandidates
        ) == nil
    }

    private static func shouldConfirmSingleCandidateWithWeakRoot(
        acceptedText: String,
        rankedScores: [ChordInkCandidateScore],
        glyphCandidates: [[GlyphCandidate]]
    ) -> Bool {
        guard rankedScores.count == 1,
              let acceptedSymbol = try? ChordSymbolParser.parse(acceptedText),
              acceptedSymbol.kind == .rooted,
              let rootEvidence = rootGlyphEvidence(
                for: acceptedSymbol.root.rawValue,
                glyphCandidates: glyphCandidates
              ) else {
            return false
        }

        return rootEvidence.acceptedConfidence < weakSingleCandidateRootConfidence
            || rootEvidence.gapToRunnerUp <= ambiguousSingleCandidateRootGap
    }

    private static func acceptedRootGlyphRace(
        acceptedText: String,
        glyphCandidates: [[GlyphCandidate]]
    ) -> ChordInkRootGlyphEvidence? {
        guard let acceptedSymbol = try? ChordSymbolParser.parse(acceptedText),
              acceptedSymbol.kind == .rooted,
              let rootEvidence = rootGlyphEvidence(
                for: acceptedSymbol.root.rawValue,
                glyphCandidates: glyphCandidates
              ),
              rootEvidence.gapToRunnerUp <= ambiguousAcceptedRootGlyphRaceGap else {
            return nil
        }

        return rootEvidence
    }

    private static func rootGlyphEvidence(
        for acceptedRoot: String,
        glyphCandidates: [[GlyphCandidate]]
    ) -> ChordInkRootGlyphEvidence? {
        guard let rootGlyphColumn = glyphCandidates.first else {
            return nil
        }

        let rootLetters: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
        let rootCandidates = rootGlyphColumn
            .filter { candidate in
                candidate.text.count == 1 && rootLetters.contains(candidate.text)
            }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }

                return lhs.text < rhs.text
            }
        guard let acceptedCandidate = rootCandidates.first(where: { $0.text == acceptedRoot }) else {
            return nil
        }

        let runnerUpCandidate = rootCandidates
            .first { $0.text != acceptedRoot }
        let runnerUpConfidence = runnerUpCandidate?.confidence ?? 0

        return ChordInkRootGlyphEvidence(
            acceptedRoot: acceptedRoot,
            acceptedConfidence: acceptedCandidate.confidence,
            runnerUpRoot: runnerUpCandidate?.text,
            runnerUpConfidence: runnerUpConfidence
        )
    }
}

private struct ChordInkRootGlyphEvidence {
    var acceptedRoot: String
    var acceptedConfidence: Double
    var runnerUpRoot: String?
    var runnerUpConfidence: Double

    var gapToRunnerUp: Double {
        acceptedConfidence - runnerUpConfidence
    }

    var absoluteGapToRunnerUp: Double {
        abs(gapToRunnerUp)
    }
}

struct InkFixtureDocument: Codable, Hashable {
    var name: String
    var expectedDisplayText: String
    var expectedClusterCount: Int?
    var expectedTopGlyphs: [String]
    var strokes: [InkStroke]

    init(
        name: String,
        expectedDisplayText: String,
        expectedClusterCount: Int? = nil,
        expectedTopGlyphs: [String] = [],
        strokes: [InkStroke]
    ) {
        self.name = name
        self.expectedDisplayText = expectedDisplayText
        self.expectedClusterCount = expectedClusterCount
        self.expectedTopGlyphs = expectedTopGlyphs
        self.strokes = strokes
    }
}
