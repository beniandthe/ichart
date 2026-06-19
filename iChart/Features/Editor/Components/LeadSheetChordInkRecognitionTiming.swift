import Foundation

struct ChordInkRecognitionTiming {
    var scheduledAt: Date
    var requestedDelay: TimeInterval
    var recognitionStartedAt: Date
    var recognitionFinishedAt: Date
    var strokeCount: Int
    var ocrCandidateCount: Int

    var requestedDelayMilliseconds: Double {
        requestedDelay * 1_000
    }

    var idleMilliseconds: Double {
        recognitionStartedAt.timeIntervalSince(scheduledAt) * 1_000
    }

    var recognitionMilliseconds: Double {
        recognitionFinishedAt.timeIntervalSince(recognitionStartedAt) * 1_000
    }

    var recognitionTotalMilliseconds: Double {
        recognitionFinishedAt.timeIntervalSince(scheduledAt) * 1_000
    }

    func diagnosticEvidence(
        proposalDecisionMilliseconds: Double?,
        commitMutationMilliseconds: Double?,
        renderHandoffMilliseconds: Double? = nil
    ) -> ChordEntryTimingEvidence {
        ChordEntryTimingEvidence(
            requestedDelayMilliseconds: requestedDelayMilliseconds,
            idleMilliseconds: idleMilliseconds,
            recognitionMilliseconds: recognitionMilliseconds,
            recognitionTotalMilliseconds: recognitionTotalMilliseconds,
            proposalDecisionMilliseconds: proposalDecisionMilliseconds,
            commitMutationMilliseconds: commitMutationMilliseconds,
            renderHandoffMilliseconds: renderHandoffMilliseconds
        )
    }
}

enum LeadSheetChordInkRecognitionTimingLogger {
    static func log(
        _ timing: ChordInkRecognitionTiming,
        result: ChordInkRecognitionResult
    ) {
        #if DEBUG || targetEnvironment(simulator)
        let bestRead = result.match?.displayText ?? "none"
        let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
        let trustDecision = ChordRecognitionTrustArbiter.decision(for: result)
        let confidenceGap = trustDecision.confidenceGap ?? -1
        let metrics = result.metrics
        let composition = metrics.compositionMetrics
        print(
            String(
                format: "iChart chord timing: delay=%.0fms idle=%.0fms recognition=%.0fms total=%.0fms cluster=%.0fms glyph=%.0fms context=%.0fms compose=%.0fms semantic=%.0fms match=%.0fms ocrMs=%.0fms strokes=%d clusters=%d candidates=%d sequences=%d/%d limit=%@ ocr=%d best=%@ confidence=%.2f primaryAction=%@ finalAction=%@ trust=%@ agreement=%@ closeRace=%@ gap=%.2f reason=%@",
                timing.requestedDelayMilliseconds,
                timing.idleMilliseconds,
                timing.recognitionMilliseconds,
                timing.recognitionTotalMilliseconds,
                metrics.clusterMilliseconds,
                metrics.glyphMilliseconds,
                metrics.contextualGlyphMilliseconds,
                metrics.composeMilliseconds,
                metrics.semanticMilliseconds,
                metrics.matchMilliseconds,
                metrics.ocrMilliseconds ?? 0,
                timing.strokeCount,
                metrics.clusterCount,
                result.rawCandidates.count,
                composition.generatedSequenceCount,
                composition.maxGeneratedSequences,
                composition.hitGeneratedSequenceLimit ? "yes" : "no",
                timing.ocrCandidateCount,
                bestRead,
                result.confidence,
                primaryDecision.action.rawValue,
                trustDecision.action.rawValue,
                trustDecision.trustSource.rawValue,
                trustDecision.agreementLevel.rawValue,
                trustDecision.isCloseRace ? "yes" : "no",
                confidenceGap,
                trustDecision.reason
            )
        )
        #endif
    }
}
