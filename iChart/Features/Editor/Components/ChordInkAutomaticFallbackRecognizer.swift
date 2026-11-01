#if canImport(UIKit) && canImport(Vision)
import Foundation

/// A fallback receives the exact prepared source of one current target. The
/// caller owns scheduling, cancellation identity, caching and publication;
/// providers never replace that source with transformed/rasterized ink.
protocol ChordInkAutomaticFallbackRecognizing {
    var identifier: String { get }
    var version: String { get }
    /// May run on a worker queue. isCurrent must be safe to call from a Vision
    /// progress callback as well as from this provider's worker.
    func recognize(
        strokes: [InkStroke], options: ChordInkRecognitionOptions,
        isCurrent: @escaping () -> Bool
    ) -> ChordInkRecognitionResult?
}

enum ChordInkAutomaticFallbackProviders {
    static let pipelineVersion = "automatic-source-fallback-v1-native-32-39.5-48-vision-7-10"

    /// The session tries this bounded chain in order and stops at its first
    /// actual parseable output. It runs independently of the primary queue.
    static var live: [any ChordInkAutomaticFallbackRecognizing] {
        [
            ChordInkNativeScaleFallbackRecognizer(targetHeight: 32),
            ChordInkNativeScaleFallbackRecognizer(targetHeight: 39.5),
            ChordInkNativeScaleFallbackRecognizer(targetHeight: 48),
            ChordInkVisionAutomaticFallbackRecognizer()
        ]
    }
}

/// One lexical/parser boundary for actual outputs of fallback engines. No
/// default chord, nearest-string repair, or confidence-to-trust conversion.
enum ChordInkAutomaticFallbackCandidatePolicy {
    static func candidateTexts(for result: ChordInkRecognitionResult) -> [String] {
        candidateScores(for: result).compactMap(\.displayText)
    }

    static func hasCandidate(_ result: ChordInkRecognitionResult) -> Bool {
        !candidateTexts(for: result).isEmpty
    }

    static func candidateScores(for result: ChordInkRecognitionResult) -> [ChordInkCandidateScore] {
        var ordered: [ChordInkCandidateScore] = []
        if let match = result.match {
            ordered.append(.init(text: match.rawInput, displayText: match.displayText,
                confidence: result.confidence))
        }
        ordered.append(contentsOf: (result.candidateScores + result.reviewCandidateScores).sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.text < $1.text
        })
        // Existing profile/review choices are legitimate candidates too. Their
        // presence prevents a needless fallback without inventing confidence.
        ordered.append(contentsOf: ChordInkRenderResolutionPolicy.candidateTexts(for: result).map {
            .init(text: $0, displayText: $0, confidence: 0)
        })
        // The primary reader already bounds this list, which may exceed one
        // provider's reporting cap after its existing scale recoveries. Check
        // every primary output before declaring the target a zero-candidate.
        ordered.append(contentsOf: result.rawCandidates.map {
            .init(text: $0, displayText: nil, confidence: 0)
        })
        var seen = Set<String>()
        return ordered.compactMap { score in
            guard score.confidence.isFinite, score.confidence >= 0,
                  let match = ChordRecognitionCompendium.match(score.text),
                  score.displayText.map({ ChordRecognitionCompendium.match($0)?.displayText == match.displayText }) ?? true,
                  seen.insert(match.displayText).inserted else { return nil }
            return .init(text: score.text, displayText: match.displayText, confidence: score.confidence)
        }
    }

    static func sourceIsUsable(_ strokes: [InkStroke], maximumStrokeCount: Int) -> Bool {
        guard !strokes.isEmpty, strokes.count <= maximumStrokeCount else { return false }
        var pointCount = 0
        for stroke in strokes {
            guard stroke.points.count <= 16_384 - pointCount,
                  stroke.bounds.minX.isFinite, stroke.bounds.minY.isFinite,
                  stroke.bounds.maxX.isFinite, stroke.bounds.maxY.isFinite,
                  stroke.creationTimeOffset.map(\.isFinite) ?? true,
                  stroke.points.allSatisfy({ point in
                      point.x.isFinite && point.y.isFinite && (point.timeOffset.map(\.isFinite) ?? true)
                  }) else { return false }
            pointCount += stroke.points.count
        }
        return pointCount > 0
    }

    static func reviewOnlyResult(
        from result: ChordInkRecognitionResult, sourceStrokeCount: Int
    ) -> ChordInkRecognitionResult? {
        let scores = candidateScores(for: result)
        guard !scores.isEmpty else { return nil }
        var metrics = result.metrics
        metrics.strokeCount = sourceStrokeCount
        return ChordInkRecognitionResult(rawCandidates: Array(result.rawCandidates.prefix(64)),
            glyphCandidates: result.glyphCandidates, match: nil, confidence: 0,
            reviewCandidateScores: Array(scores.prefix(64)), metrics: metrics)
    }
}

struct ChordInkNativeScaleFallbackRecognizer: ChordInkAutomaticFallbackRecognizing {
    let targetHeight: Double
    private let recognizer: any ChordInkRecognizing

    var identifier: String { "native-scale-\(targetHeight)" }
    var version: String { "native-scale-source-v1-\(ChordInkRecognitionPipelineIdentity.version)" }

    init(targetHeight: Double, recognizer: any ChordInkRecognizing = ChordInkRecognizer()) {
        self.targetHeight = targetHeight
        self.recognizer = recognizer
    }

    func recognize(
        strokes: [InkStroke], options: ChordInkRecognitionOptions,
        isCurrent: @escaping () -> Bool
    ) -> ChordInkRecognitionResult? {
        guard isCurrent(), [32.0, 39.5, 48.0].contains(targetHeight),
              ChordInkAutomaticFallbackCandidatePolicy.sourceIsUsable(strokes, maximumStrokeCount: 16) else { return nil }
        let transformed = ChordInkRecognitionScaleNormalizer.strokes(from: strokes, targetHeight: targetHeight)
        guard isCurrent(),
              ChordInkAutomaticFallbackCandidatePolicy.sourceIsUsable(transformed, maximumStrokeCount: 16) else { return nil }
        let result = recognizer.recognize(strokes: transformed, options: options)
        guard isCurrent() else { return nil }
        return ChordInkAutomaticFallbackCandidatePolicy.reviewOnlyResult(from: result, sourceStrokeCount: strokes.count)
    }
}

/// Uses the production app's existing lexical and parser boundary, without
/// altering the study recognizer's strict canonical default normalizer.
struct ChordInkAutomaticVisionCandidateNormalizer: RecognitionStudyChordCandidateNormalizing {
    func normalizedChord(from rawText: String) -> String? {
        ChordRecognitionCompendium.match(rawText)?.displayText
    }
}

struct ChordInkVisionAutomaticFallbackRecognizer: ChordInkAutomaticFallbackRecognizing {
    let identifier = "apple-vision-automatic-source"
    let version = "apple-vision-automatic-source-v1-production-domain-7-10"
    private let recognizer: RecognitionStudyVisionChordRecognizer

    init(recognizer: RecognitionStudyVisionChordRecognizer = .init(
        normalizer: ChordInkAutomaticVisionCandidateNormalizer()
    )) {
        self.recognizer = recognizer
    }

    func recognize(
        strokes: [InkStroke], options: ChordInkRecognitionOptions,
        isCurrent: @escaping () -> Bool
    ) -> ChordInkRecognitionResult? {
        guard isCurrent(),
              ChordInkAutomaticFallbackCandidatePolicy.sourceIsUsable(strokes, maximumStrokeCount: 128) else { return nil }
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard let output = try? recognizer.recognize(strokes: strokes, isCurrent: isCurrent),
              isCurrent() else { return nil }
        return Self.recognitionResult(from: output, sourceStrokeCount: strokes.count,
            elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
    }

    static func recognitionResult(
        from output: RecognitionStudyVisionChordRecognizer.Result,
        sourceStrokeCount: Int, elapsedMilliseconds: Double = 0
    ) -> ChordInkRecognitionResult? {
        // Raw confidence is preserved on review scores. The study's consensus
        // decision is not a production trust authority, even when accepted.
        let candidates = output.candidates.filter {
            $0.rawConfidenceFloor.isFinite && (0...1).contains($0.rawConfidenceFloor)
                && !$0.rawComponentConfidences.isEmpty
                && $0.rawComponentConfidences.allSatisfy({ $0.isFinite && (0...1).contains($0) })
        }
        let scores = candidates.compactMap { candidate -> ChordInkCandidateScore? in
            guard let match = ChordRecognitionCompendium.match(candidate.rawText) else { return nil }
            return .init(text: candidate.rawText, displayText: match.displayText,
                confidence: Double(candidate.rawConfidenceFloor))
        }.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.text < $1.text
        }
        let result = ChordInkRecognitionResult(rawCandidates: Array(candidates.map(\.rawText).prefix(64)),
            glyphCandidates: [], match: nil, confidence: 0, reviewCandidateScores: scores,
            metrics: ChordInkRecognitionMetrics(totalMilliseconds: max(0, elapsedMilliseconds),
                strokeCount: sourceStrokeCount, rawCandidateCount: candidates.count))
        return ChordInkAutomaticFallbackCandidatePolicy.reviewOnlyResult(from: result,
            sourceStrokeCount: sourceStrokeCount)
    }
}
#endif
