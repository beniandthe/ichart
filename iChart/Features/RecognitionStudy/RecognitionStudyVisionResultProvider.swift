import Foundation

/// Runs Apple's general text-recognition model as an engineering baseline.
/// Even when its internal consensus gate passes, the result remains review-
/// only because no writer-independent calibration artifact exists yet.
struct RecognitionStudyVisionResultProvider:
    RecognitionStudyLocalResultProviding
{
    let recognizerID = "apple-vision-text-baseline"
    let recognizerVersion = "apple-vision-text-baseline-v1"

    private let recognizer: RecognitionStudyVisionChordRecognizer

    init(
        recognizer: RecognitionStudyVisionChordRecognizer =
            RecognitionStudyVisionChordRecognizer(
                normalizer: RecognitionStudyCanonicalChordNormalizer()
            )
    ) {
        self.recognizer = recognizer
    }

    func result(
        for packet: ChordInkCanonicalTrajectoryPacket
    ) async -> RecognitionStudyLocalResult {
        do {
            let clock = ContinuousClock()
            let started = clock.now
            let output = try recognizer.recognize(packet: packet)
            let elapsed = started.duration(to: clock.now).components
            let elapsedMilliseconds =
                (Double(elapsed.seconds) * 1_000)
                + (Double(elapsed.attoseconds) / 1_000_000_000_000_000)
            return Self.presentation(
                for: output,
                elapsedMilliseconds: elapsedMilliseconds
            )
        } catch {
            return .noRead(
                detail: "The local Vision baseline could not process this ink. Nothing was accepted."
            )
        }
    }

    static func presentation(
        for output: RecognitionStudyVisionChordRecognizer.Result,
        elapsedMilliseconds: Double
    ) -> RecognitionStudyLocalResult {
        let elapsedText = String(format: "%.0f ms", elapsedMilliseconds)

        switch output.decision {
        case let .accepted(chord, confidenceFloor):
            return .review(
                candidate: chord,
                detail: "Uncalibrated baseline candidate (raw Vision floor \(Self.percent(confidenceFloor)), \(elapsedText)). Review only; this build never auto-accepts it."
            )

        case let .review(reason):
            return .review(
                candidate: Self.bestDisplayCandidate(in: output.candidates),
                detail: "Baseline needs review: \(Self.reviewDescription(reason)) (\(elapsedText))."
            )

        case .noRead(.noGrammarCandidate):
            return .review(
                candidate: output.candidates.first?.rawText,
                detail: "Vision returned text outside the strict chord grammar (\(elapsedText)). It was not accepted."
            )

        case .noRead(.noInk):
            return .noRead(detail: "No ink reached the baseline.")

        case .noRead(.noVisionText):
            return .noRead(
                detail: "Vision found no text candidate (\(elapsedText))."
            )
        }
    }

    private static func bestDisplayCandidate(
        in candidates: [RecognitionStudyVisionChordRecognizer.Candidate]
    ) -> String? {
        guard let first = candidates.first else { return nil }
        return first.normalizedChord ?? first.rawText
    }

    private static func percent(_ confidence: Float) -> String {
        String(format: "%.0f%%", confidence * 100)
    }

    private static func reviewDescription(
        _ reason: RecognitionStudyVisionChordRecognizer.ReviewReason
    ) -> String {
        switch reason {
        case .insufficientConsensus:
            return "not enough independent raster passes produced a candidate"
        case .rasterPassDisagreement:
            return "the raster passes disagreed"
        case .confidenceBelowThreshold:
            return "raw Vision confidence was below the engineering threshold"
        case .candidateMarginBelowThreshold:
            return "the leading candidate was not separated from alternatives"
        case .topCandidateOutsideGrammar:
            return "the leading Vision text was outside the strict chord grammar"
        }
    }
}
