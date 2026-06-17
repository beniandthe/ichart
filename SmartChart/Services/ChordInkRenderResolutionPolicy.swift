import Foundation

struct ChordInkRenderResolution: Equatable {
    var primaryDecision: ChordInkRecognitionDecision
    var decision: ChordInkRecognitionDecision
    var candidateTexts: [String]
}

enum ChordInkRenderResolutionPolicy {
    static func resolution(
        for result: ChordInkRecognitionResult,
        drawingData: Data,
        correctionMemory: ChordInkUserCorrectionMemory
    ) -> ChordInkRenderResolution {
        let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
        var decision = ChordRecognitionTrustArbiter.decision(for: result)
        let candidateTexts = candidateTexts(for: result)

        if decision.action == .autoRender,
           let acceptedText = decision.acceptedText,
           correctionMemory.shouldBlockAutoRender(
               acceptedText: acceptedText,
               drawingData: drawingData,
               candidateTexts: candidateTexts
           ) {
            decision.action = .confirm
            decision.reason = "This ink previously rendered as \(acceptedText) and was deleted. Choose the intended chord, or type it in."
            decision.isCloseRace = false
            decision.competingCandidateText = nil
            decision.confidenceGap = nil
        }

        return ChordInkRenderResolution(
            primaryDecision: primaryDecision,
            decision: decision,
            candidateTexts: candidateTexts
        )
    }

    static func candidateTexts(for result: ChordInkRecognitionResult) -> [String] {
        let rankedCandidateTexts = ChordInkRecognitionPolicy.rankedSupportedScores(for: result)
            .compactMap(\.displayText)
        let primaryCandidateTexts = [result.match?.displayText].compactMap { $0 }
        let ocrCandidateTexts = result.ocrCandidates?.compactMap(\.displayText) ?? []

        return ChordRecognitionCompendium.userFacingCandidateTexts(
            from: rankedCandidateTexts + primaryCandidateTexts + ocrCandidateTexts
        )
    }
}
