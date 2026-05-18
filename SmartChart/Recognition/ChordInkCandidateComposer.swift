import Foundation

struct ChordInkCandidate: Hashable {
    var text: String
    var confidence: Double
    var glyphCandidates: [GlyphCandidate]
}

struct ChordInkCandidateCompositionResult: Hashable {
    var candidates: [ChordInkCandidate]
    var metrics: ChordInkCandidateCompositionMetrics
}

struct ChordInkCandidateComposerScoring: Hashable {
    var startsWithRootBonus = 1.0
    var missingRootPenalty = 1.0
    var veryWeakRootConfidenceThreshold = 0.60
    var veryWeakRootPenalty = 0.70
    var weakRootConfidenceThreshold = 0.65
    var weakRootPenalty = 0.35
    var parsesAsChordBonus = 2.0
    var invalidChordPenalty = 0.25
    var accidentalDominantAlterationBonus = 0.35
    var dominantSharpNineBonus = 0.08
    var dominantFlatFiveBonus = 0.08
    var dominantFlatThirteenBonus = 0.08
    var explicitMinorSixthBonus = 0.12
    var dashMinorNinthLookalikePenalty = 0.18
    var suspendedMinorSixthPenalty = 0.65
    var explicitMajorSixthBonus = 0.42
    var likelyRootFlatCollisionPenalty = 0.35
    var triangleQualityMinConfidence = 0.60
    var triangleQualityBonus = 0.62
    var accidentalRootNinthSharpFiveBonus = 0.20
    var strongDominantSharpConfidence = 0.65
    var explicitSharpElevenBonus = 0.78
    var unreliableSharpElevenPenalty = 0.55
    var dominantSharpFiveBonus = 0.06
    var dominantSharpFiveTailEvidenceBonus = 0.24
    var weakDominantSharpAlterationPenalty = 0.70
    var slashBassMinConfidence = 0.65
    var slashBassBonus = 0.85
    var lowercaseSlashBassPenalty = 0.30
    var suspendedSlashLookalikePenalty = 0.45
    var invalidSlashPenalty = 0.75
    var suspendedFourthBonus = 1.75
    var dominantSuspendedBonus = 1.65
    var plainSuspendedBonus = 0.25
    var missingSuspendedEvidencePenalty = 0.35
    var explainedGlyphBonus = 0.12
    var unexplainedClusterPenalty = 2.00
}

struct ChordInkCandidateComposerConfiguration: Hashable {
    var maxAlternativesPerCluster: Int
    var maxCandidateCount: Int
    var maxGeneratedSequences: Int
    var scoring: ChordInkCandidateComposerScoring

    static let chordSymbols = ChordInkCandidateComposerConfiguration(
        maxAlternativesPerCluster: 3,
        maxCandidateCount: 32,
        maxGeneratedSequences: 4096,
        scoring: ChordInkCandidateComposerScoring()
    )
}

struct ChordInkCandidateComposer {
    var configuration: ChordInkCandidateComposerConfiguration

    init(configuration: ChordInkCandidateComposerConfiguration = .chordSymbols) {
        self.configuration = configuration
    }

    func compose(glyphCandidates columns: [[GlyphCandidate]]) -> [ChordInkCandidate] {
        composeDetailed(glyphCandidates: columns).candidates
    }

    func composeDetailed(glyphCandidates columns: [[GlyphCandidate]]) -> ChordInkCandidateCompositionResult {
        let sortedColumns = columns.map(\.sortedByConfidence)
        let candidateColumns = sortedColumns
            .enumerated()
            .map { index, column in
                selectedGlyphCandidates(forColumnAt: index, in: sortedColumns)
            }
            .filter { !$0.isEmpty }

        guard !candidateColumns.isEmpty else {
            return ChordInkCandidateCompositionResult(
                candidates: [],
                metrics: ChordInkCandidateCompositionMetrics(
                    selectedColumnCount: 0,
                    generatedSequenceCount: 0,
                    returnedCandidateCount: 0,
                    maxGeneratedSequences: configuration.maxGeneratedSequences,
                    hitGeneratedSequenceLimit: false
                )
            )
        }

        var bestCandidatesByText: [String: ChordInkCandidate] = [:]
        var generatedSequenceCount = 0
        var hitGeneratedSequenceLimit = false

        for prefixLength in 1...candidateColumns.count {
            let prefixColumns = Array(candidateColumns.prefix(prefixLength))
            for sequence in candidateSequences(from: prefixColumns) {
                guard generatedSequenceCount < configuration.maxGeneratedSequences else {
                    hitGeneratedSequenceLimit = true
                    break
                }

                generatedSequenceCount += 1

                for variant in textVariants(for: sequence) {
                    let confidence = score(
                        text: variant,
                        glyphCandidates: sequence,
                        candidateColumns: candidateColumns,
                        totalClusterCount: candidateColumns.count
                    )
                    let candidate = ChordInkCandidate(
                        text: variant,
                        confidence: confidence,
                        glyphCandidates: sequence
                    )

                    if let currentBest = bestCandidatesByText[variant],
                       currentBest.confidence >= candidate.confidence {
                        continue
                    }

                    bestCandidatesByText[variant] = candidate
                }
            }
        }

        let candidates = Array(bestCandidatesByText.values)
            .sortedByConfidence
            .prefix(configuration.maxCandidateCount)
            .map { $0 }
        return ChordInkCandidateCompositionResult(
            candidates: candidates,
            metrics: ChordInkCandidateCompositionMetrics(
                selectedColumnCount: candidateColumns.count,
                generatedSequenceCount: generatedSequenceCount,
                returnedCandidateCount: candidates.count,
                maxGeneratedSequences: configuration.maxGeneratedSequences,
                hitGeneratedSequenceLimit: hitGeneratedSequenceLimit
            )
        )
    }

    private func candidateSequences(from columns: [[GlyphCandidate]]) -> [[GlyphCandidate]] {
        columns.reduce([[]]) { partialSequences, column in
            partialSequences.flatMap { sequence in
                column.map { candidate in
                    sequence + [candidate]
                }
            }
        }
    }

    private func selectedGlyphCandidates(
        forColumnAt index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> [GlyphCandidate] {
        let column = sortedColumns[index]
        var selected = Array(column.prefix(configuration.maxAlternativesPerCluster))

        if index == 0,
           let rootCandidate = column.first(where: { candidate in
               candidate.confidence >= 0.85 && "ABCDEFG".contains(candidate.text)
           }) {
            selected.removeAll { candidate in
                candidate.text == "b" || candidate.text == "#"
            }
            if !selected.contains(where: { $0.text == rootCandidate.text }) {
                selected.insert(rootCandidate, at: 0)
            }
        }

        func promoteCandidate(
            _ text: String,
            minimumConfidence: Double? = nil,
            fallbackConfidence: Double? = nil
        ) {
            var candidate: GlyphCandidate?
            if var existingCandidate = column.first(where: { $0.text == text }) {
                if let minimumConfidence {
                    existingCandidate.confidence = max(existingCandidate.confidence, minimumConfidence)
                }
                candidate = existingCandidate
            } else if let fallbackConfidence {
                candidate = GlyphCandidate(text: text, confidence: fallbackConfidence, source: .composer)
            }

            guard let candidate else {
                return
            }

            selected.removeAll { $0.text == text }
            selected.insert(candidate, at: 0)
        }

        if shouldExposePlainFinalExtensionCandidate("6", at: index, in: sortedColumns) {
            promoteCandidate("6", minimumConfidence: 0.72)
        }

        if shouldExposePlainSuspendedSCandidate(at: index, in: sortedColumns) {
            promoteCandidate("s", minimumConfidence: 0.84, fallbackConfidence: 0.72)
        }

        if shouldExposePlainSuspendedUCandidate(at: index, in: sortedColumns) {
            promoteCandidate("u", minimumConfidence: 0.96, fallbackConfidence: 0.72)
        }

        if shouldExposeSuspendedFourthCandidate(at: index, in: sortedColumns) {
            promoteCandidate("4", minimumConfidence: 0.84, fallbackConfidence: 0.72)
        }

        if shouldExposeHalfDiminishedLookalikeCandidate(at: index, in: sortedColumns) {
            promoteCandidate("ø", minimumConfidence: 0.82, fallbackConfidence: 0.76)
        }

        if shouldExposeAlteredDominantNumberCandidate(at: index, in: sortedColumns) {
            let hasStrongCompetingAlterationNumber = column.contains { candidate in
                candidate.confidence >= 0.60 && (candidate.text == "5" || candidate.text == "9")
            }
            for alteredNumber in ["5", "9", "1"] {
                if alteredNumber == "1" && hasStrongCompetingAlterationNumber {
                    continue
                }

                if let candidate = column.first(where: { $0.text == alteredNumber }),
                   !selected.contains(where: { $0.text == alteredNumber }) {
                    selected.append(candidate)
                }
            }
        }

        if shouldExposeAlteredDominantThirteenStartCandidate(at: index, in: sortedColumns) {
            promoteCandidate("1", minimumConfidence: 0.86, fallbackConfidence: 0.58)
        }

        if shouldExposeAlteredDominantThirteenContinuationCandidate(at: index, in: sortedColumns) {
            promoteCandidate("3", minimumConfidence: 0.84, fallbackConfidence: 0.58)
        }

        if shouldExposeCompactSharpElevenTailCandidate(at: index, in: sortedColumns) {
            promoteCandidate("1", minimumConfidence: 0.82, fallbackConfidence: 0.62)
        }

        if shouldExposeAlteredDominantAccidentalCandidate(at: index, in: sortedColumns) {
            let hasStrongSharpEvidence = column.contains { candidate in
                candidate.text == "#" && candidate.confidence >= 0.65
            }

            for accidental in ["b", "#"] {
                if var candidate = column.first(where: { $0.text == accidental }),
                   !selected.contains(where: { $0.text == accidental }) {
                    if accidental == "b" && !hasStrongSharpEvidence {
                        candidate.confidence = max(candidate.confidence, 0.72)
                    }
                    selected.append(candidate)
                }
            }
        }

        return selected
    }

    private func shouldExposePlainFinalExtensionCandidate(
        _ text: String,
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index == sortedColumns.count - 1 else {
            return false
        }

        let columnContainsExtension = sortedColumns[index].contains { candidate in
            candidate.text == text && candidate.confidence >= 0.45
        }
        let extensionConfidence = sortedColumns[index].first { candidate in
            candidate.text == text
        }?.confidence ?? 0
        let competingPlusConfidence = sortedColumns[index].first { candidate in
            candidate.text == "+"
        }?.confidence ?? 0
        let hasRootBeforeExtension = sortedColumns[..<index].contains { column in
            column.contains { candidate in
                candidate.confidence >= 0.50 && "ABCDEFG".contains(candidate.text)
            }
        }
        let hasDominantSevenBeforeExtension = sortedColumns[..<index].contains { column in
            column.hasStandaloneDominantSevenEvidence
        }

        return columnContainsExtension
            && hasRootBeforeExtension
            && !hasDominantSevenBeforeExtension
            && !(text == "6"
                 && competingPlusConfidence >= 0.45
                 && competingPlusConfidence >= extensionConfidence)
    }

    private func shouldExposePlainSuspendedSCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 1 else {
            return false
        }

        let currentHasS = sortedColumns[index].hasSuspendedContextCandidate("s")
        let previousHasU = sortedColumns[index - 1].hasSuspendedContextCandidate("u")
        let nextHasU = index + 1 < sortedColumns.count
            && sortedColumns[index + 1].hasSuspendedContextCandidate("u")
        let hasRootOrAccidentalBefore = sortedColumns[..<index].contains { column in
            column.contains { candidate in
                candidate.confidence >= 0.45
                    && ["A", "B", "C", "D", "E", "F", "G", "#", "b"].contains(candidate.text)
            }
        }
        let hasDominantSuspendedContext = hasDominantSuspendedContext(around: index, in: sortedColumns)
        let hasMinorOrDominantBefore = hasStandaloneMinorOrDominantColumn(before: index, in: sortedColumns)

        return currentHasS
            && (!hasMinorOrDominantBefore || hasDominantSuspendedContext)
            && (previousHasU || nextHasU && hasRootOrAccidentalBefore)
    }

    private func shouldExposePlainSuspendedUCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 1,
              index + 1 < sortedColumns.count else {
            return false
        }

        let currentHasU = sortedColumns[index].hasSuspendedContextCandidate("u")
        let previousHasS = sortedColumns[index - 1].hasSuspendedContextCandidate("s")
        let nextHasS = sortedColumns[index + 1].hasSuspendedContextCandidate("s")
        let hasDominantSuspendedContext = hasDominantSuspendedContext(around: index, in: sortedColumns)
        let hasMinorOrDominantBefore = hasStandaloneMinorOrDominantColumn(before: index, in: sortedColumns)

        return currentHasU
            && previousHasS
            && nextHasS
            && (!hasMinorOrDominantBefore || hasDominantSuspendedContext)
    }

    private func hasDominantSuspendedContext(
        around index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        if index >= 2,
           index + 2 < sortedColumns.count,
           sortedColumns[index - 1].hasConfidentStandaloneDominantSevenEvidence,
           sortedColumns[index].hasSuspendedContextCandidate("s"),
           sortedColumns[index + 1].hasSuspendedContextCandidate("u"),
           sortedColumns[index + 2].hasSuspendedContextCandidate("s") {
            return true
        }

        if index >= 3,
           index + 1 < sortedColumns.count,
           sortedColumns[index - 2].hasConfidentStandaloneDominantSevenEvidence,
           sortedColumns[index - 1].hasSuspendedContextCandidate("s"),
           sortedColumns[index].hasSuspendedContextCandidate("u"),
           sortedColumns[index + 1].hasSuspendedContextCandidate("s") {
            return true
        }

        if index >= 4,
           sortedColumns[index - 3].hasConfidentStandaloneDominantSevenEvidence,
           sortedColumns[index - 2].hasSuspendedContextCandidate("s"),
           sortedColumns[index - 1].hasSuspendedContextCandidate("u"),
           sortedColumns[index].hasSuspendedContextCandidate("s") {
            return true
        }

        return false
    }

    private func shouldExposeSuspendedFourthCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 4,
              index == sortedColumns.count - 1 else {
            return false
        }

        let suffixTexts = sortedColumns[(index - 3)..<index].map { column in
            column.firstSuspendedContextText
        }
        let currentHasFour = sortedColumns[index].contains { candidate in
            candidate.text == "4" && candidate.confidence >= 0.35
        }
        let currentHasContextualFour = sortedColumns[index].contains { candidate in
            candidate.text == "4" && candidate.source == .composer
        }
        let currentHasStrongQualityConflict = sortedColumns[index].contains { candidate in
            candidate.confidence >= 0.86
                && ["-", "m", "7", "°", "ø", "△", "+", "/", "6", "9", "1", "3", "5"].contains(candidate.text)
        }

        return suffixTexts == ["s", "u", "s"]
            && currentHasFour
            && (!currentHasStrongQualityConflict || currentHasContextualFour)
    }

    private func shouldExposeHalfDiminishedLookalikeCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 1,
              index + 1 < sortedColumns.count else {
            return false
        }

        let hasRootBefore = sortedColumns[..<index].contains { column in
            column.contains { candidate in
                candidate.confidence >= 0.72 && "ABCDEFG".contains(candidate.text)
            }
        }
        let hasSevenAfter = sortedColumns[(index + 1)...].prefix(2).contains { column in
            column.contains { candidate in
                candidate.text == "7" && candidate.confidence >= 0.45
            }
        }
        let currentColumn = sortedColumns[index]
        let currentLooksLikeRoundHalfDiminishedBody = currentColumn.contains { candidate in
            candidate.confidence >= 0.42 && ["ø", "B", "D", "G", "O", "0", "3", "8"].contains(candidate.text)
        }
        let currentIsRootAccidental = currentColumn.contains { candidate in
            candidate.confidence >= 0.70 && (candidate.text == "b" || candidate.text == "#")
        }
        let currentHasHardQualityConflict = currentColumn.contains { candidate in
            candidate.confidence >= 0.75 && ["-", "m", "7", "9", "△", "+", "/"].contains(candidate.text)
        }

        return hasRootBefore
            && hasSevenAfter
            && currentLooksLikeRoundHalfDiminishedBody
            && !currentIsRootAccidental
            && !currentHasHardQualityConflict
    }

    private func hasStandaloneMinorOrDominantColumn(
        before index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        sortedColumns[..<index].contains { column in
            let participatesInSuspendedContext = column.contains { candidate in
                ["s", "u"].contains(candidate.text)
                    && (candidate.confidence >= 0.70 || candidate.source == .composer)
            }
            if participatesInSuspendedContext {
                return false
            }

            let hasStrongRootOrAccidental = column.contains { candidate in
                candidate.confidence >= 0.85
                    && ["A", "B", "C", "D", "E", "F", "G", "#", "b"].contains(candidate.text)
            }
            let hasModifier = column.contains { candidate in
                candidate.confidence >= 0.45
                    && ["-", "m", "7"].contains(candidate.text)
            }

            return hasModifier && !hasStrongRootOrAccidental
        }
    }

    private func shouldExposeAlteredDominantNumberCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 2 else {
            return false
        }

        let previousColumn = sortedColumns[index - 1]
        let previousColumnLooksLikeAlteration = previousColumn.contains { candidate in
            candidate.confidence >= 0.45 && (candidate.text == "#" || candidate.text == "b")
        }
        let hasDominantSevenBeforeAlteration = sortedColumns[..<(index - 1)].contains { column in
            column.contains { candidate in
                candidate.confidence >= 0.50 && candidate.text == "7"
            }
        }

        return previousColumnLooksLikeAlteration && hasDominantSevenBeforeAlteration
    }

    private func shouldExposeAlteredDominantThirteenStartCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 2,
              index + 1 < sortedColumns.count else {
            return false
        }

        let previousColumnLooksLikeAlteration = sortedColumns[index - 1].contains { candidate in
            candidate.confidence >= 0.45 && (candidate.text == "#" || candidate.text == "b")
        }
        let hasDominantSevenBeforeAlteration = sortedColumns[..<(index - 1)].contains { column in
            column.contains { candidate in
                candidate.confidence >= 0.50 && candidate.text == "7"
            }
        }

        return previousColumnLooksLikeAlteration && hasDominantSevenBeforeAlteration
    }

    private func shouldExposeAlteredDominantThirteenContinuationCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 3 else {
            return false
        }

        let previousColumnLooksLikeOne = sortedColumns[index - 1].contains { candidate in
            candidate.confidence >= 0.45 && candidate.text == "1"
        } || shouldExposeAlteredDominantThirteenStartCandidate(at: index - 1, in: sortedColumns)
        let hasAlterationAccidentalBeforePreviousColumn = sortedColumns[..<(index - 1)].indices.contains { candidateIndex in
            let columnLooksLikeAlteration = sortedColumns[candidateIndex].contains { candidate in
                candidate.confidence >= 0.45 && (candidate.text == "#" || candidate.text == "b")
            }
            let hasDominantSevenBeforeAlteration = sortedColumns[..<candidateIndex].contains { column in
                column.contains { candidate in
                    candidate.confidence >= 0.50 && candidate.text == "7"
                }
            }

            return columnLooksLikeAlteration && hasDominantSevenBeforeAlteration
        }

        return previousColumnLooksLikeOne && hasAlterationAccidentalBeforePreviousColumn
    }

    private func shouldExposeCompactSharpElevenTailCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 3 else {
            return false
        }

        let previousColumnLooksLikeSharp = sortedColumns[index - 1].contains { candidate in
            candidate.confidence >= 0.45 && candidate.text == "#"
        }
        let hasDominantSevenBeforeSharp = sortedColumns[..<(index - 1)].contains { column in
            column.contains { candidate in
                candidate.confidence >= 0.50 && candidate.text == "7"
            }
        }
        let currentColumnHasStrongCompetingAlterationNumber = sortedColumns[index].contains { candidate in
            candidate.confidence >= 0.60 && (candidate.text == "5" || candidate.text == "9")
        }

        return previousColumnLooksLikeSharp
            && hasDominantSevenBeforeSharp
            && !currentColumnHasStrongCompetingAlterationNumber
    }

    private func shouldExposeAlteredDominantAccidentalCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 2, index + 1 < sortedColumns.count else {
            return false
        }

        let hasDominantSevenBeforeAlteration = sortedColumns[..<index].contains { column in
            column.contains { candidate in
                candidate.confidence >= 0.50 && candidate.text == "7"
            }
        }
        let nextColumnLooksLikeAlteredNumber = sortedColumns[index + 1].contains { candidate in
            candidate.confidence >= 0.45 && (candidate.text == "5" || candidate.text == "9" || candidate.text == "1")
        }

        return hasDominantSevenBeforeAlteration && nextColumnLooksLikeAlteredNumber
    }

    private func textVariants(for glyphCandidates: [GlyphCandidate]) -> [String] {
        let variantsByGlyph = glyphCandidates.map { glyphTextVariants(for: $0.text) }
        let variants = variantsByGlyph.reduce([""]) { partialVariants, glyphVariants in
            partialVariants.flatMap { prefix in
                glyphVariants.map { variant in
                    prefix + variant
                }
            }
        }

        let expandedVariants = variants.flatMap { variant in
            var expansions: [String] = []
            if let compactSharpElevenVariant = expandedCompactSharpElevenVariant(for: variant) {
                expansions.append(compactSharpElevenVariant)
            }
            expansions.append(contentsOf: expandedSharpElevenWrapperVariants(for: variant))
            if let trailingWrapperVariant = expandedSharpElevenTrailingWrapperVariant(for: variant) {
                expansions.append(trailingWrapperVariant)
            }
            return expansions
        }

        let canonicalVariants = (variants + expandedVariants).map(canonicalTextVariant)
        return Array(Set(canonicalVariants)).sorted()
    }

    private func canonicalTextVariant(for text: String) -> String {
        guard let symbol = try? ChordSymbolParser.parse(text),
              symbol.quality == "-",
              symbol.extensions == ["6"],
              symbol.alterations.isEmpty else {
            return text
        }

        return symbol.displayText
    }

    private func expandedCompactSharpElevenVariant(for text: String) -> String? {
        guard let range = text.range(of: "7#1") else {
            return nil
        }

        let suffix = text[range.upperBound...]
        guard suffix.isEmpty || suffix.first == "/" else {
            return nil
        }

        var expandedText = text
        expandedText.replaceSubrange(range, with: "7#11")
        return expandedText
    }

    private func expandedSharpElevenWrapperVariants(for text: String) -> [String] {
        ["71#11", "7b#11", "7C#11"].compactMap { wrapperPattern in
            guard let range = text.range(of: wrapperPattern) else {
                return nil
            }

            var expandedText = text
            expandedText.replaceSubrange(range, with: "7#11")
            return expandedText
        }
        + ["77#11", "73#11", "75#11"].compactMap { wrapperPattern in
            guard let range = text.range(of: wrapperPattern) else {
                return nil
            }

            var expandedText = text
            expandedText.replaceSubrange(range, with: "7#11")
            return expandedText
        }
        + ["71#1", "77#1", "73#1", "75#1"].compactMap { wrapperPattern in
            guard let range = text.range(of: wrapperPattern) else {
                return nil
            }

            var expandedText = text
            expandedText.replaceSubrange(range, with: "7#11")
            return expandedText
        }
    }

    private func expandedSharpElevenTrailingWrapperVariant(for text: String) -> String? {
        guard let range = text.range(of: "7#11") else {
            return nil
        }

        let suffix = text[range.upperBound...]
        guard suffix.count == 1,
              let wrapper = suffix.first,
              "3579C)".contains(wrapper) else {
            return nil
        }

        return String(text[..<range.upperBound])
    }

    private func glyphTextVariants(for text: String) -> [String] {
        switch text {
        case "Δ", "∆":
            return ["△"]
        case "º":
            return ["°"]
        case "Ø", "⌀":
            return ["ø"]
        case "°":
            return ["°"]
        case "ø":
            return ["ø"]
        case "m", "-":
            return ["-", "m"]
        default:
            return [text]
        }
    }

    private func score(
        text: String,
        glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]],
        totalClusterCount: Int
    ) -> Double {
        let scoring = configuration.scoring
        let averageGlyphConfidence = glyphCandidates
            .map(\.confidence)
            .reduce(0, +) / Double(max(glyphCandidates.count, 1))
        let parsedSymbol = try? ChordSymbolParser.parse(text)
        var score = averageGlyphConfidence

        if startsWithRoot(text) {
            score += scoring.startsWithRootBonus
        } else {
            score -= scoring.missingRootPenalty
        }

        if let rootConfidence = leadingRootConfidence(in: glyphCandidates) {
            if rootConfidence < scoring.veryWeakRootConfidenceThreshold {
                score -= scoring.veryWeakRootPenalty
            } else if rootConfidence < scoring.weakRootConfidenceThreshold {
                score -= scoring.weakRootPenalty
            }
        }

        if parsedSymbol != nil {
            score += scoring.parsesAsChordBonus
        } else {
            score -= scoring.invalidChordPenalty
        }

        if hasAccidentalImmediatelyAfterRoot(text),
           hasDominantAlteration(text) {
            score += scoring.accidentalDominantAlterationBonus
        }

        if text.contains("7#9") || text.contains("7(#9)") {
            score += scoring.dominantSharpNineBonus
        }

        if text.contains("7b5") || text.contains("7(b5)") {
            score += scoring.dominantFlatFiveBonus
        }

        if text.contains("7b13") || text.contains("7(b13)") {
            score += scoring.dominantFlatThirteenBonus
        }

        if isMinorSixthSymbol(parsedSymbol) {
            if hasExplicitMinorSixthEvidence(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) {
                score += scoring.explicitMinorSixthBonus
            }

            if hasDashMinorNinthLookalikeEvidence(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) {
                score -= scoring.dashMinorNinthLookalikePenalty
            }

            if hasSuspendedColumnSuffixEvidence(in: candidateColumns) {
                score -= scoring.suspendedMinorSixthPenalty
            }
        }

        if isMajorSixthSymbol(parsedSymbol) {
            if hasVeryStrongExplicitMajorSixthEvidence(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) {
                score += scoring.explicitMajorSixthBonus
            } else if hasLikelyRootFlatCollision(
                in: glyphCandidates,
                candidateColumns: candidateColumns,
                totalClusterCount: totalClusterCount
            ) {
                score -= scoring.likelyRootFlatCollisionPenalty
            }
        }

        if hasTriangleQuality(parsedSymbol),
           glyphCandidates.contains(where: { $0.text == "△" && $0.confidence >= scoring.triangleQualityMinConfidence }) {
            score += scoring.triangleQualityBonus
        }

        if hasAccidentalImmediatelyAfterRoot(text),
           text.contains("9#5") || text.contains("9(#5)") {
            score += scoring.accidentalRootNinthSharpFiveBonus
        }

        if text.contains("7#11") || text.contains("7(#11)") {
            let hasStrongSharp = (dominantAlterationAccidentalConfidence("#", in: glyphCandidates) ?? 0) >= scoring.strongDominantSharpConfidence
            if hasDominantSharpFiveTailCollision(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) {
                score -= scoring.unreliableSharpElevenPenalty
            } else if hasExplicitSharpElevenNumberTail(in: glyphCandidates)
                || (hasStrongSharp && hasReliableCompactSharpElevenTail(in: glyphCandidates)) {
                score += scoring.explicitSharpElevenBonus
            } else {
                score -= scoring.unreliableSharpElevenPenalty
            }
        }

        if (text.contains("7#5") || text.contains("7(#5)")),
           (dominantAlterationAccidentalConfidence("#", in: glyphCandidates) ?? 0) >= scoring.strongDominantSharpConfidence {
            score += scoring.dominantSharpFiveBonus
            if hasDominantSharpFiveNumberEvidence(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) {
                score += scoring.dominantSharpFiveTailEvidenceBonus
            }
        }

        if hasDominantSharpAlteration(text),
           (dominantAlterationAccidentalConfidence("#", in: glyphCandidates) ?? 1.0) < scoring.strongDominantSharpConfidence {
            score -= scoring.weakDominantSharpAlterationPenalty
        }

        if hasValidSlashBass(text),
           slashGlyphConfidence(in: glyphCandidates) >= scoring.slashBassMinConfidence {
            score += scoring.slashBassBonus
            if hasLowercaseSlashBassRoot(text) {
                score -= scoring.lowercaseSlashBassPenalty
            }
            if hasSuspendedLookalikeAtSlash(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) {
                score -= scoring.suspendedSlashLookalikePenalty
            }
        } else if text.contains("/") {
            score -= scoring.invalidSlashPenalty
        }

        if text.hasSuffix("sus") || text.hasSuffix("sus4") {
            if hasSuspendedSuffixEvidence(for: text, in: glyphCandidates) {
                if text.hasSuffix("sus4") {
                    score += scoring.suspendedFourthBonus
                } else if text.hasSuffix("7sus") {
                    score += scoring.dominantSuspendedBonus
                } else {
                    score += scoring.plainSuspendedBonus
                }
            } else {
                score -= scoring.missingSuspendedEvidencePenalty
            }
        }

        // Prefer candidates that explain more of the written glyphs, so C-7 wins
        // over the C- prefix when the written extension is still present.
        score += Double(max(0, glyphCandidates.count - 1)) * scoring.explainedGlyphBonus
        score -= Double(max(0, totalClusterCount - glyphCandidates.count)) * scoring.unexplainedClusterPenalty

        return score
    }

    private func startsWithRoot(_ text: String) -> Bool {
        guard let first = text.first else {
            return false
        }

        return "ABCDEFG".contains(first)
    }

    private func leadingRootConfidence(in glyphCandidates: [GlyphCandidate]) -> Double? {
        guard let firstCandidate = glyphCandidates.first,
              firstCandidate.text.count == 1,
              firstCandidate.text.first.map({ "ABCDEFG".contains($0) }) == true else {
            return nil
        }

        return firstCandidate.confidence
    }

    private func hasAccidentalImmediatelyAfterRoot(_ text: String) -> Bool {
        guard text.count > 1 else {
            return false
        }

        let secondIndex = text.index(after: text.startIndex)
        return text[secondIndex] == "#" || text[secondIndex] == "b"
    }

    private func hasDominantAlteration(_ text: String) -> Bool {
        ["b5", "#5", "b9", "#9", "#11", "b13"].contains { alteration in
            text.contains("7\(alteration)") || text.contains("7(\(alteration))")
        }
    }

    private func hasDominantSharpAlteration(_ text: String) -> Bool {
        ["#5", "#9", "#11"].contains { alteration in
            text.contains("7\(alteration)") || text.contains("7(\(alteration))")
        }
    }

    private func isMinorSixthSymbol(_ symbol: ChordSymbol?) -> Bool {
        guard let symbol else {
            return false
        }

        return symbol.quality == "-"
            && symbol.extensions == ["6"]
            && symbol.alterations.isEmpty
    }

    private func isMajorSixthSymbol(_ symbol: ChordSymbol?) -> Bool {
        guard let symbol else {
            return false
        }

        return symbol.quality.isEmpty
            && symbol.extensions == ["6"]
            && symbol.alterations.isEmpty
            && symbol.slashBass == nil
    }

    private func hasLikelyRootFlatCollision(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]],
        totalClusterCount: Int
    ) -> Bool {
        guard totalClusterCount == 2,
              glyphCandidates.count == 2,
              let rootCandidate = glyphCandidates.first,
              "ABCDEFG".contains(rootCandidate.text),
              let finalSixCandidate = glyphCandidates.last,
              finalSixCandidate.text == "6",
              let finalColumn = candidateColumns.last else {
            return false
        }

        let flatConfidence = finalColumn
            .filter { $0.text == "b" }
            .map(\.confidence)
            .max() ?? 0

        return flatConfidence >= 0.45
            && flatConfidence + 0.10 >= finalSixCandidate.confidence
    }

    private func hasVeryStrongExplicitMajorSixthEvidence(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard let finalCandidate = glyphCandidates.last,
              finalCandidate.text == "6",
              finalCandidate.confidence >= 0.98 else {
            return false
        }

        let finalColumn = candidateColumns.last ?? []
        let finalNineConfidence = finalColumn
            .filter { $0.text == "9" }
            .map(\.confidence)
            .max() ?? 0

        return finalNineConfidence < 0.60
    }

    private func hasTriangleQuality(_ symbol: ChordSymbol?) -> Bool {
        guard let symbol else {
            return false
        }

        return symbol.quality.contains("△")
            && symbol.alterations.contains("#11")
    }

    private func hasExplicitMinorSixthEvidence(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard glyphCandidates.contains(where: { candidate in
                  candidate.text == "m" && candidate.confidence >= 0.75
              }),
              let finalSix = glyphCandidates.last,
              finalSix.text == "6",
              finalSix.confidence >= 0.45 else {
            return false
        }

        let finalColumn = candidateColumns.last ?? []
        let strongSevenConfidence = finalColumn
            .filter { $0.text == "7" }
            .map(\.confidence)
            .max() ?? 0

        return strongSevenConfidence < 0.85
            || strongSevenConfidence <= finalSix.confidence + 0.15
    }

    private func hasDashMinorNinthLookalikeEvidence(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard !glyphCandidates.contains(where: { candidate in
                  candidate.text == "m" && candidate.confidence >= 0.75
              }),
              let finalSix = glyphCandidates.last,
              finalSix.text == "6" else {
            return false
        }

        let finalColumn = candidateColumns.last ?? []
        let finalNineConfidence = finalColumn
            .filter { $0.text == "9" }
            .map(\.confidence)
            .max() ?? 0

        return finalNineConfidence >= 0.90
            && finalNineConfidence + 0.04 >= finalSix.confidence
    }

    private func hasSuspendedColumnSuffixEvidence(in candidateColumns: [[GlyphCandidate]]) -> Bool {
        guard candidateColumns.count >= 4 else {
            return false
        }

        let suffixColumns = Array(candidateColumns.suffix(3))
        return suffixColumns[0].hasSuspendedContextCandidate("s")
            && suffixColumns[1].hasSuspendedContextCandidate("u")
            && suffixColumns[2].hasSuspendedContextCandidate("s")
    }

    private func dominantAlterationAccidentalConfidence(
        _ accidental: String,
        in glyphCandidates: [GlyphCandidate]
    ) -> Double? {
        var hasPassedDominantSeven = false

        for candidate in glyphCandidates {
            if candidate.text == "7" {
                hasPassedDominantSeven = true
                continue
            }

            guard hasPassedDominantSeven else {
                continue
            }

            if candidate.text == "(" || candidate.text == ")" {
                continue
            }

            if candidate.text == accidental {
                return candidate.confidence
            }

            if candidate.text == "b" || candidate.text == "#" {
                return nil
            }
        }

        return nil
    }

    private func hasExplicitSharpElevenNumberTail(in glyphCandidates: [GlyphCandidate]) -> Bool {
        var hasPassedDominantSeven = false
        var hasPassedAlterationSharp = false
        var consecutiveOneCount = 0

        for candidate in glyphCandidates {
            if candidate.text == "7" {
                hasPassedDominantSeven = true
                hasPassedAlterationSharp = false
                consecutiveOneCount = 0
                continue
            }

            guard hasPassedDominantSeven else {
                continue
            }

            if !hasPassedAlterationSharp {
                if candidate.text == "#" {
                    hasPassedAlterationSharp = true
                }
                continue
            }

            if candidate.text == "1" {
                consecutiveOneCount += 1
                if consecutiveOneCount >= 2 {
                    return true
                }
            } else if candidate.text != "(" && candidate.text != ")" {
                consecutiveOneCount = 0
            }
        }

        return false
    }

    private func hasReliableCompactSharpElevenTail(in glyphCandidates: [GlyphCandidate]) -> Bool {
        var hasPassedDominantSeven = false
        var hasPassedAlterationSharp = false

        for candidate in glyphCandidates {
            if candidate.text == "7" {
                hasPassedDominantSeven = true
                hasPassedAlterationSharp = false
                continue
            }

            guard hasPassedDominantSeven else {
                continue
            }

            if !hasPassedAlterationSharp {
                if candidate.text == "#" {
                    hasPassedAlterationSharp = true
                }
                continue
            }

            guard candidate.text == "1" else {
                continue
            }

            return candidate.confidence >= 0.75 || candidate.source == .composer
        }

        return false
    }

    private func hasDominantSharpFiveTailCollision(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard !hasExplicitSharpElevenNumberTail(in: glyphCandidates),
              let finalColumn = candidateColumns.last else {
            return false
        }

        let hardFinalFive = finalColumn.contains { candidate in
            candidate.text == "5" && candidate.confidence >= 0.85
        }
        let finalColumnHasStrongOne = finalColumn.contains { candidate in
            candidate.text == "1" && candidate.confidence >= 0.90
        }

        return hardFinalFive && !finalColumnHasStrongOne
    }

    private func hasDominantSharpFiveNumberEvidence(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard dominantAlterationAccidentalConfidence("#", in: glyphCandidates) != nil else {
            return false
        }

        var hasPassedDominantSeven = false
        var hasPassedAlterationSharp = false
        var numberIndex: Int?

        for (index, candidate) in glyphCandidates.enumerated() {
            if candidate.text == "7" {
                hasPassedDominantSeven = true
                continue
            }

            guard hasPassedDominantSeven else {
                continue
            }

            if !hasPassedAlterationSharp {
                if candidate.text == "#" {
                    hasPassedAlterationSharp = true
                }
                continue
            }

            if candidate.text == "(" || candidate.text == ")" {
                continue
            }

            if candidate.text == "5" {
                numberIndex = index
                break
            }

            if ["1", "3", "7", "9"].contains(candidate.text) {
                return false
            }
        }

        guard let numberIndex,
              candidateColumns.indices.contains(numberIndex) else {
            return false
        }

        let numberColumn = candidateColumns[numberIndex]
        let fiveConfidence = numberColumn
            .filter { $0.text == "5" }
            .map(\.confidence)
            .max() ?? 0
        let nineConfidence = numberColumn
            .filter { $0.text == "9" }
            .map(\.confidence)
            .max() ?? 0
        let threeConfidence = numberColumn
            .filter { $0.text == "3" }
            .map(\.confidence)
            .max() ?? 0

        return fiveConfidence >= 0.58
            && threeConfidence >= 0.90
            && fiveConfidence + 0.04 >= nineConfidence
    }

    private func hasValidSlashBass(_ text: String) -> Bool {
        let pieces = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else {
            return false
        }

        return ChordPitch.parse(pieces[1]) != nil
    }

    private func hasLowercaseSlashBassRoot(_ text: String) -> Bool {
        guard let slashIndex = text.firstIndex(of: "/") else {
            return false
        }

        let bassStart = text.index(after: slashIndex)
        guard bassStart < text.endIndex else {
            return false
        }

        return "abcdefg".contains(text[bassStart])
    }

    private func slashGlyphConfidence(in glyphCandidates: [GlyphCandidate]) -> Double {
        glyphCandidates
            .filter { $0.text == "/" }
            .map(\.confidence)
            .max() ?? 0
    }

    private func hasSuspendedLookalikeAtSlash(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard let slashIndex = glyphCandidates.firstIndex(where: { $0.text == "/" }),
              candidateColumns.indices.contains(slashIndex) else {
            return false
        }

        return candidateColumns[slashIndex].contains { candidate in
            candidate.text == "s" && candidate.confidence >= 0.70
        }
    }

    private func hasSuspendedSuffixEvidence(
        for text: String,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        guard glyphCandidates.count >= 4 else {
            return false
        }

        if text.hasSuffix("sus4") {
            return glyphCandidates.suffix(4).map(\.text) == ["s", "u", "s", "4"]
        }

        return glyphCandidates.suffix(3).map(\.text) == ["s", "u", "s"]
    }
}

private extension Array where Element == GlyphCandidate {
    var sortedByConfidence: [GlyphCandidate] {
        sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.text < rhs.text
        }
    }

    var hasStandaloneDominantSevenEvidence: Bool {
        let hasSeven = contains { candidate in
            candidate.text == "7" && candidate.confidence >= 0.50
        }
        let hasStrongRootOrAccidental = contains { candidate in
            candidate.confidence >= 0.85
                && ["A", "B", "C", "D", "E", "F", "G", "#", "b"].contains(candidate.text)
        }

        return hasSeven && !hasStrongRootOrAccidental
    }

    var hasConfidentStandaloneDominantSevenEvidence: Bool {
        let hasSeven = contains { candidate in
            candidate.text == "7" && candidate.confidence >= 0.85
        }
        let hasStrongRootOrAccidental = contains { candidate in
            candidate.confidence >= 0.85
                && ["A", "B", "C", "D", "E", "F", "G", "#", "b"].contains(candidate.text)
        }

        return hasSeven && !hasStrongRootOrAccidental
    }

    func hasSuspendedContextCandidate(_ text: String) -> Bool {
        contains { candidate in
            candidate.text == text
                && (candidate.confidence >= 0.70 || candidate.source == .composer)
        }
    }

    var firstSuspendedContextText: String? {
        first { candidate in
            ["s", "u"].contains(candidate.text)
                && (candidate.confidence >= 0.70 || candidate.source == .composer)
        }?.text
    }
}

private extension Array where Element == ChordInkCandidate {
    var sortedByConfidence: [ChordInkCandidate] {
        sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.text < rhs.text
        }
    }
}
