import Foundation

struct ChordInkRenderResolution: Equatable {
    var primaryDecision: ChordInkRecognitionDecision
    var decision: ChordInkRecognitionDecision
    var candidateTexts: [String]

    /// A review suggestion is display-only; it does not become accepted
    /// recognition evidence or change the original trust decision.
    var bestCandidateText: String? {
        ChordInkRenderResolutionPolicy.bestCandidateText(
            preferredTexts: [decision.acceptedText],
            candidateTexts: candidateTexts
        )
    }
}

enum ChordInkRenderResolutionPolicy {
    private struct ReviewChoice {
        var displayText: String
        var confidence: Double
        var isReviewOnly: Bool
        var sourceOrder: Int
    }

    static func resolution(
        for result: ChordInkRecognitionResult,
        drawingData: Data,
        correctionMemory: ChordInkUserCorrectionMemory
    ) -> ChordInkRenderResolution {
        let primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
        var decision = primaryDecision
        let candidateTexts = candidateTexts(for: result)

        if decision.action == .trusted,
           let acceptedText = decision.acceptedText,
           correctionMemory.shouldBlockTrustedCandidate(
               acceptedText: acceptedText,
               drawingData: drawingData,
               candidateTexts: candidateTexts
           ) {
            decision.action = .confirm
            decision.reason = "This ink was previously corrected from \(acceptedText). Choose the intended chord, or type it in."
            decision.isCloseRace = false
            decision.competingCandidateText = nil
            decision.confidenceGap = nil
        }

        let personalSelection = personalSelection(for: result)
        if personalSelection.prefersPersonal, let text = personalSelection.text {
            decision = ChordInkRecognitionDecision(
                action: .confirm,
                acceptedText: text,
                reason: personalSelection.disposition == .correctedReview
                    ? "Your corrected examples suggest \(text). Check it before rendering."
                    : "Your handwriting profile suggests \(text). Check it before rendering.",
                isCloseRace: false,
                competingCandidateText: primaryDecision.acceptedText == text ? nil : primaryDecision.acceptedText,
                confidenceGap: nil
            )
        }

        return ChordInkRenderResolution(
            primaryDecision: primaryDecision,
            decision: decision,
            candidateTexts: candidateTexts
        )
    }

    static func personalSelection(for result: ChordInkRecognitionResult) -> PersonalInkArbitrationPolicy.Selection {
        var baseline = result
        baseline.personalSuggestion = nil
        return PersonalInkArbitrationPolicy.select(
            baselineText: baseline.match?.displayText ?? candidateTexts(for: baseline).first,
            // Requiring a review after erasure does not weaken native evidence
            // or authorize a personal override. resolution(for:) still applies
            // the original request-local edit gate to the returned action.
            baselineTrusted: ChordInkRecognitionPolicy.recognitionEvidenceDecision(for: baseline).action == .trusted,
            suggestion: result.personalSuggestion)
    }

    static func candidateTexts(for result: ChordInkRecognitionResult) -> [String] {
        if let personal = result.personalSuggestion {
            var baseline = result
            baseline.personalSuggestion = nil
            let baselineChoices = candidateTexts(for: baseline)
            let selection = personalSelection(for: result)
            guard selection.disposition != .baselineOnly else { return baselineChoices }
            // Reserve an alternative slot without erasing the native default.
            let ordered = [selection.text, baseline.match?.displayText, personal.text].compactMap { $0 } + baselineChoices
            return ChordRecognitionCompendium.userFacingCandidateTexts(from: ordered)
        }
        let primaryScores = ChordInkRecognitionPolicy.rankedSupportedScores(for: result)
        let primaryChoices = primaryScores.enumerated().compactMap { index, score -> ReviewChoice? in
            guard let displayText = supportedDisplayText(for: score) else {
                return nil
            }
            return ReviewChoice(
                displayText: displayText,
                confidence: score.confidence,
                isReviewOnly: false,
                sourceOrder: index
            )
        }
        let primaryDisplayText = result.match?.displayText ?? primaryChoices.first?.displayText
        let reviewChoices = result.reviewCandidateScores.enumerated().compactMap { index, score -> ReviewChoice? in
            guard let displayText = supportedDisplayText(for: score) else {
                return nil
            }
            return ReviewChoice(
                displayText: displayText,
                confidence: score.confidence,
                isReviewOnly: true,
                sourceOrder: primaryChoices.count + index
            )
        }
        let allChoices = deduplicatedChoices(primaryChoices + reviewChoices)
        guard !allChoices.isEmpty else {
            return []
        }

        // Confirmation offers only three one-tap choices. Keep the native
        // primary read first, then use the remaining slots for the strongest
        // alternative and a structurally simpler same-root recovery. This
        // prevents a correct recovery from sitting invisibly behind several
        // near-duplicate, over-specified candidates. Review-only scores still
        // never enter ChordInkRecognitionPolicy and cannot create trust.
        var preferredTexts = [String]()
        if let primaryDisplayText {
            append(primaryDisplayText, to: &preferredTexts)
        }

        if let rootAlternative = result.reviewRootAlternatives.first(where: { text in
            allChoices.contains { $0.displayText == text && $0.isReviewOnly }
                && !preferredTexts.contains(text)
        }) {
            append(rootAlternative, to: &preferredTexts)
        }

        if let strongestAlternative = allChoices
            .filter({ !preferredTexts.contains($0.displayText) })
            .sorted(by: strongerChoice)
            .first {
            append(strongestAlternative.displayText, to: &preferredTexts)
        }

        if preferredTexts.count < 3,
           let primaryDisplayText,
           let primaryRoot = rootDescriptor(for: primaryDisplayText) {
            let remaining = allChoices.filter {
                !preferredTexts.contains($0.displayText)
                    && rootDescriptor(for: $0.displayText) == primaryRoot
            }
            let recoveryChoice = recoveryChoice(
                from: remaining,
                relativeTo: primaryDisplayText
            )
            if let recoveryChoice {
                append(recoveryChoice.displayText, to: &preferredTexts)
            }
        }

        for choice in allChoices.sorted(by: strongerChoice) {
            append(choice.displayText, to: &preferredTexts)
        }

        return preferredTexts
    }

    /// Only complete, valid chord text may fill a preview or review entry.
    /// Raw transcripts and rejected glyphs are never repaired into a chord.
    static func bestCandidateText(
        preferredTexts: [String?],
        candidateTexts: [String]
    ) -> String? {
        for text in preferredTexts + candidateTexts.map({ Optional($0) }) {
            guard let text else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ChordRecognitionCompendium.match(trimmed) != nil else { continue }
            return trimmed
        }
        return nil
    }

    private static func supportedDisplayText(for score: ChordInkCandidateScore) -> String? {
        guard let displayText = score.displayText,
              let candidateMatch = ChordRecognitionCompendium.match(score.text),
              let displayMatch = ChordRecognitionCompendium.match(displayText),
              candidateMatch.displayText == displayMatch.displayText else {
            return nil
        }
        return candidateMatch.displayText
    }

    private static func deduplicatedChoices(_ choices: [ReviewChoice]) -> [ReviewChoice] {
        var bestByDisplayText = [String: ReviewChoice]()
        for choice in choices {
            guard let current = bestByDisplayText[choice.displayText] else {
                bestByDisplayText[choice.displayText] = choice
                continue
            }

            if strongerChoice(choice, current) {
                bestByDisplayText[choice.displayText] = choice
            }
        }
        return Array(bestByDisplayText.values)
    }

    private static func strongerChoice(_ lhs: ReviewChoice, _ rhs: ReviewChoice) -> Bool {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        if lhs.isReviewOnly != rhs.isReviewOnly {
            return !lhs.isReviewOnly
        }
        if lhs.sourceOrder != rhs.sourceOrder {
            return lhs.sourceOrder < rhs.sourceOrder
        }
        return lhs.displayText < rhs.displayText
    }

    private static func recoveryChoice(
        from choices: [ReviewChoice],
        relativeTo primaryDisplayText: String
    ) -> ReviewChoice? {
        choices.sorted { lhs, rhs in
            let lhsDistance = semanticDistance(
                from: lhs.displayText,
                to: primaryDisplayText
            )
            let rhsDistance = semanticDistance(
                from: rhs.displayText,
                to: primaryDisplayText
            )
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            let lhsComplexity = semanticComplexity(of: lhs.displayText)
            let rhsComplexity = semanticComplexity(of: rhs.displayText)
            if lhsComplexity != rhsComplexity {
                return lhsComplexity < rhsComplexity
            }
            if lhs.isReviewOnly != rhs.isReviewOnly {
                return lhs.isReviewOnly
            }
            return strongerChoice(lhs, rhs)
        }.first
    }

    private static func semanticDistance(from text: String, to referenceText: String) -> Int {
        guard let symbol = ChordRecognitionCompendium.match(text)?.symbol,
              let reference = ChordRecognitionCompendium.match(referenceText)?.symbol,
              symbol.kind == .rooted,
              reference.kind == .rooted,
              symbol.root == reference.root,
              symbol.accidental == reference.accidental else {
            return Int.max
        }

        return (symbol.quality == reference.quality ? 0 : 2)
            + Set(symbol.extensions).symmetricDifference(Set(reference.extensions)).count
            + Set(symbol.alterations).symmetricDifference(Set(reference.alterations)).count
            + (symbol.slashBass == reference.slashBass ? 0 : 1)
    }

    private static func semanticComplexity(of text: String) -> Int {
        guard let symbol = ChordRecognitionCompendium.match(text)?.symbol,
              symbol.kind == .rooted else {
            return Int.max
        }

        return (symbol.quality.isEmpty ? 0 : 1)
            + symbol.extensions.count
            + symbol.alterations.count
            + (symbol.slashBass == nil ? 0 : 1)
    }

    private static func rootDescriptor(for text: String) -> String? {
        guard let symbol = ChordRecognitionCompendium.match(text)?.symbol,
              symbol.kind == .rooted else {
            return nil
        }
        return "\(symbol.root.rawValue)\(symbol.accidental.rawValue)"
    }

    private static func append(_ text: String, to texts: inout [String]) {
        guard !texts.contains(text),
              ChordRecognitionCompendium.match(text) != nil else {
            return
        }
        texts.append(text)
    }
}
