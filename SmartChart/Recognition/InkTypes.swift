import Foundation

struct InkPoint: Codable, Hashable {
    var x: Double
    var y: Double
    var timeOffset: TimeInterval?
}

struct InkBounds: Codable, Hashable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double {
        max(0, maxX - minX)
    }

    var height: Double {
        max(0, maxY - minY)
    }

    static let zero = InkBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)

    static func enclosing(_ points: [InkPoint]) -> InkBounds {
        guard let firstPoint = points.first else {
            return .zero
        }

        return points.dropFirst().reduce(
            InkBounds(
                minX: firstPoint.x,
                minY: firstPoint.y,
                maxX: firstPoint.x,
                maxY: firstPoint.y
            )
        ) { bounds, point in
            bounds.union(
                InkBounds(
                    minX: point.x,
                    minY: point.y,
                    maxX: point.x,
                    maxY: point.y
                )
            )
        }
    }

    static func enclosing(_ bounds: [InkBounds]) -> InkBounds {
        guard let firstBounds = bounds.first else {
            return .zero
        }

        return bounds.dropFirst().reduce(firstBounds) { partialBounds, nextBounds in
            partialBounds.union(nextBounds)
        }
    }

    func union(_ other: InkBounds) -> InkBounds {
        InkBounds(
            minX: min(minX, other.minX),
            minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX),
            maxY: max(maxY, other.maxY)
        )
    }
}

struct InkStroke: Codable, Hashable {
    var points: [InkPoint]
    var bounds: InkBounds

    init(points: [InkPoint], bounds: InkBounds? = nil) {
        self.points = points
        self.bounds = bounds ?? InkBounds.enclosing(points)
    }
}

struct InkCluster: Codable, Hashable {
    var strokes: [InkStroke]
    var bounds: InkBounds
    var startTimeOffset: TimeInterval?
    var endTimeOffset: TimeInterval?

    init(
        strokes: [InkStroke],
        bounds: InkBounds? = nil,
        startTimeOffset: TimeInterval? = nil,
        endTimeOffset: TimeInterval? = nil
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
    }
}

enum RecognitionSource: String, Codable, Hashable {
    case template
    case heuristic
    case composer
    case ocr
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
    var ocrMilliseconds: Double? = nil
    var strokeCount: Int = 0
    var clusterCount: Int = 0
    var glyphCandidateColumnCount: Int = 0
    var semanticCandidateCount: Int = 0
    var rawCandidateCount: Int = 0
    var compositionMetrics: ChordInkCandidateCompositionMetrics = ChordInkCandidateCompositionMetrics()
}

enum ChordOCRCandidateSource: String, Codable, Hashable {
    case appleVision
    case testDouble
}

struct ChordOCRCandidate: Codable, Hashable {
    var rawText: String
    var displayText: String?
    var confidence: Double
    var source: ChordOCRCandidateSource

    var isSupported: Bool {
        displayText != nil
    }

    init(
        rawText: String,
        displayText: String? = nil,
        confidence: Double,
        source: ChordOCRCandidateSource
    ) {
        self.rawText = rawText
        self.displayText = displayText
        self.confidence = confidence
        self.source = source
    }

    static func normalized(
        rawText: String,
        confidence: Double,
        source: ChordOCRCandidateSource
    ) -> ChordOCRCandidate {
        let displayText = bestCompendiumMatch(for: rawText)?.displayText
        return ChordOCRCandidate(
            rawText: rawText,
            displayText: displayText,
            confidence: confidence,
            source: source
        )
    }

    private static func bestCompendiumMatch(for rawText: String) -> ChordRecognitionMatch? {
        for candidate in normalizedCandidateTexts(from: rawText) {
            if let match = ChordRecognitionCompendium.match(candidate) {
                return match
            }
        }

        return nil
    }

    private static func normalizedCandidateTexts(from rawText: String) -> [String] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let compact = trimmed.filter { !$0.isWhitespace }
        let musical = compact
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "＃", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "Δ", with: "△")
            .replacingOccurrences(of: "∆", with: "△")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        var candidates: [String] = []
        for candidate in [trimmed, compact, musical] {
            guard !candidate.isEmpty,
                  !candidates.contains(candidate) else {
                continue
            }

            candidates.append(candidate)
        }

        return candidates
    }
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
    var candidateScores: [ChordInkCandidateScore] = []
    var ocrCandidates: [ChordOCRCandidate]? = nil
    var symbolLedger: ChordInkSymbolLedgerSnapshot? = nil
    var symbolLedgerAssessment: ChordInkSymbolLedgerAssessment? = nil
    var metrics: ChordInkRecognitionMetrics = ChordInkRecognitionMetrics()
}

enum ChordInkRecognitionAction: String, Codable, Hashable {
    case autoRender
    case confirm
}

enum ChordInkContinuationGracePolicy {
    static func shouldWaitForPossibleContinuation(
        result: ChordInkRecognitionResult,
        strokeCount: Int
    ) -> Bool {
        guard strokeCount <= 8,
              let symbol = result.match?.symbol,
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
    var trustSource: ChordRecognitionTrustSource = .primaryRecognizer
    var agreementLevel: ChordRecognitionAgreementLevel = .ocrNotRequested
    var ocrBestCandidateText: String?
    var ocrRawTexts: [String] = []
}

enum ChordRecognitionTrustSource: String, Codable, Hashable {
    case primaryRecognizer
    case primaryWithOCRAgreement
    case primaryWithOCRDisagreement
    case ocrSupportedCandidate
}

enum ChordRecognitionAgreementLevel: String, Codable, Hashable {
    case ocrNotRequested
    case noOCREvidence
    case ocrInvalid
    case partialOCR
    case agreesWithPrimary
    case supportsRunnerUp
    case disagreesWithPrimary
    case ocrOnlySupported
}

enum ChordInkRecognitionPolicy {
    static let autoRenderMinimumConfidence = 3.95
    static let closeRaceConfidenceGap = 0.04
    private static let uncommonRootSpellingConfirmationGap = 0.08
    private static let weakSingleCandidateRootConfidence = 0.76
    private static let ambiguousSingleCandidateRootGap = 0.08

    static func decision(for result: ChordInkRecognitionResult) -> ChordInkRecognitionDecision {
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

        guard bestConfidence >= autoRenderMinimumConfidence else {
            return ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: acceptedText,
                reason: "Low-confidence read. Choose a suggestion or type the chord you meant.",
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
                if shouldAutoRenderCloseSpellingRace(
                    acceptedText: acceptedText,
                    competingText: competingText,
                    gap: gap
                ) {
                    return ChordInkRecognitionDecision(
                        action: .autoRender,
                        acceptedText: acceptedText,
                        reason: "Confident read. Placed automatically.",
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
            action: .autoRender,
            acceptedText: acceptedText,
            reason: "Confident read. Placed automatically.",
            isCloseRace: false,
            competingCandidateText: nil,
            confidenceGap: nil
        )
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

    private static func shouldAutoRenderCloseSpellingRace(
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
        guard let symbol = try? ChordSymbolParser.parse(text) else {
            return false
        }

        return ["B#", "E#", "Cb", "Fb"].contains("\(symbol.root.rawValue)\(symbol.accidental.rawValue)")
    }

    private static func shouldConfirmSingleCandidateWithWeakRoot(
        acceptedText: String,
        rankedScores: [ChordInkCandidateScore],
        glyphCandidates: [[GlyphCandidate]]
    ) -> Bool {
        guard rankedScores.count == 1,
              let acceptedSymbol = try? ChordSymbolParser.parse(acceptedText),
              let rootEvidence = rootGlyphEvidence(
                for: acceptedSymbol.root.rawValue,
                glyphCandidates: glyphCandidates
              ) else {
            return false
        }

        return rootEvidence.acceptedConfidence < weakSingleCandidateRootConfidence
            || rootEvidence.gapToRunnerUp <= ambiguousSingleCandidateRootGap
    }

    private static func rootGlyphEvidence(
        for acceptedRoot: String,
        glyphCandidates: [[GlyphCandidate]]
    ) -> (acceptedConfidence: Double, gapToRunnerUp: Double)? {
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

        let runnerUpConfidence = rootCandidates
            .first { $0.text != acceptedRoot }?
            .confidence ?? 0
        return (
            acceptedConfidence: acceptedCandidate.confidence,
            gapToRunnerUp: acceptedCandidate.confidence - runnerUpConfidence
        )
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
