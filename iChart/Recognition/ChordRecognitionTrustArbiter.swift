import Foundation

enum ChordRecognitionTrustArbiter {
    private static let ocrAgreementRenderFloor = ChordInkRecognitionPolicy.autoRenderMinimumConfidence - 0.20

    static func shouldRequestOCR(
        for result: ChordInkRecognitionResult,
        primaryDecision: ChordInkRecognitionDecision? = nil
    ) -> Bool {
        guard !result.rawCandidates.isEmpty else {
            return false
        }

        let decision = primaryDecision ?? ChordInkRecognitionPolicy.decision(for: result)
        if decision.action == .confirm || decision.isCloseRace {
            return true
        }

        return false
    }

    static func decision(for result: ChordInkRecognitionResult) -> ChordInkRecognitionDecision {
        decision(for: result, ocrCandidates: result.ocrCandidates)
    }

    static func decision(
        for result: ChordInkRecognitionResult,
        ocrCandidates: [ChordOCRCandidate]?
    ) -> ChordInkRecognitionDecision {
        var decision = ChordInkRecognitionPolicy.decision(for: result)
        guard let ocrCandidates else {
            decision.agreementLevel = .ocrNotRequested
            decision.trustSource = .primaryRecognizer
            return decision
        }

        decision.ocrRawTexts = ocrCandidates.map(\.rawText)
        guard let bestOCRCandidate = bestSupportedOCRCandidate(from: ocrCandidates) else {
            decision.agreementLevel = ocrCandidates.isEmpty ? .noOCREvidence : .ocrInvalid
            decision.trustSource = .primaryRecognizer
            return decision
        }

        let ocrDisplayText = bestOCRCandidate.displayText
        decision.ocrBestCandidateText = ocrDisplayText

        guard let ocrDisplayText else {
            decision.agreementLevel = .ocrInvalid
            decision.trustSource = .primaryRecognizer
            return decision
        }

        guard let acceptedText = decision.acceptedText else {
            return ocrOnlyConfirmation(
                from: decision,
                ocrDisplayText: ocrDisplayText
            )
        }

        if acceptedText == ocrDisplayText {
            return primaryAgreementDecision(
                from: decision,
                result: result,
                ocrDisplayText: ocrDisplayText
            )
        }

        if isPartialOCRCandidate(ocrDisplayText, of: acceptedText) {
            return partialOCRDecision(
                from: decision,
                ocrDisplayText: ocrDisplayText
            )
        }

        if primaryCandidateScores(result).contains(where: { $0.displayText == ocrDisplayText }) {
            return runnerUpSupportedDecision(
                from: decision,
                ocrDisplayText: ocrDisplayText
            )
        }

        return disagreementDecision(
            from: decision,
            ocrDisplayText: ocrDisplayText
        )
    }

    private static func bestSupportedOCRCandidate(
        from candidates: [ChordOCRCandidate]
    ) -> ChordOCRCandidate? {
        candidates
            .filter(\.isSupported)
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }

                return (lhs.displayText ?? lhs.rawText) < (rhs.displayText ?? rhs.rawText)
            }
            .first
    }

    private static func primaryCandidateScores(_ result: ChordInkRecognitionResult) -> [ChordInkCandidateScore] {
        ChordInkRecognitionPolicy.rankedSupportedScores(for: result)
    }

    private static func primaryAgreementDecision(
        from decision: ChordInkRecognitionDecision,
        result: ChordInkRecognitionResult,
        ocrDisplayText: String
    ) -> ChordInkRecognitionDecision {
        var updated = decision
        updated.trustSource = .primaryWithOCRAgreement
        updated.agreementLevel = .agreesWithPrimary

        if decision.action == .confirm,
           result.confidence >= ocrAgreementRenderFloor {
            updated.action = .autoRender
            updated.reason = "Primary recognizer and OCR agree on \(ocrDisplayText). Placed automatically."
            updated.isCloseRace = false
            updated.competingCandidateText = nil
            updated.confidenceGap = nil
        }

        return updated
    }

    private static func runnerUpSupportedDecision(
        from decision: ChordInkRecognitionDecision,
        ocrDisplayText: String
    ) -> ChordInkRecognitionDecision {
        var updated = decision
        updated.action = .confirm
        updated.trustSource = .primaryWithOCRDisagreement
        updated.agreementLevel = .supportsRunnerUp
        updated.reason = "OCR supports \(ocrDisplayText), which is also a ranked recognizer candidate. Choose the chord you meant."
        updated.isCloseRace = true
        updated.competingCandidateText = ocrDisplayText
        return updated
    }

    private static func partialOCRDecision(
        from decision: ChordInkRecognitionDecision,
        ocrDisplayText: String
    ) -> ChordInkRecognitionDecision {
        var updated = decision
        updated.trustSource = .primaryRecognizer
        updated.agreementLevel = .partialOCR
        updated.reason = decision.reason
        updated.ocrBestCandidateText = ocrDisplayText
        return updated
    }

    private static func disagreementDecision(
        from decision: ChordInkRecognitionDecision,
        ocrDisplayText: String
    ) -> ChordInkRecognitionDecision {
        var updated = decision
        updated.trustSource = .primaryRecognizer
        updated.agreementLevel = .disagreesWithPrimary
        updated.reason = decision.reason
        return updated
    }

    private static func isPartialOCRCandidate(_ ocrDisplayText: String, of acceptedText: String) -> Bool {
        guard ocrDisplayText.count < acceptedText.count else {
            return false
        }

        return acceptedText.hasPrefix(ocrDisplayText)
    }

    private static func ocrOnlyConfirmation(
        from decision: ChordInkRecognitionDecision,
        ocrDisplayText: String
    ) -> ChordInkRecognitionDecision {
        ChordInkRecognitionDecision(
            action: .confirm,
            acceptedText: ocrDisplayText,
            reason: "OCR found \(ocrDisplayText), but the primary recognizer did not find a supported chord. Confirm before placing.",
            isCloseRace: false,
            competingCandidateText: nil,
            confidenceGap: nil,
            trustSource: .ocrSupportedCandidate,
            agreementLevel: .ocrOnlySupported,
            ocrBestCandidateText: ocrDisplayText,
            ocrRawTexts: decision.ocrRawTexts
        )
    }
}
