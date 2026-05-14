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

struct ChordInkRecognitionResult: Hashable {
    var rawCandidates: [String]
    var glyphCandidates: [[GlyphCandidate]]
    var match: ChordRecognitionMatch?
    var confidence: Double
    var candidateScores: [ChordInkCandidateScore] = []
}

enum ChordInkRecognitionAction: String, Codable, Hashable {
    case autoRender
    case confirm
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
    static let autoRenderMinimumConfidence = 4.15
    static let closeRaceConfidenceGap = 0.35

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

        if let runnerUp = rankedScores.first(where: { $0.displayText != acceptedText }),
           let competingText = runnerUp.displayText {
            let gap = bestConfidence - runnerUp.confidence
            if gap <= closeRaceConfidenceGap {
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

    private static func rankedSupportedScores(for result: ChordInkRecognitionResult) -> [ChordInkCandidateScore] {
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
