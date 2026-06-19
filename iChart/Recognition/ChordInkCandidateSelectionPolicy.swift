struct ChordInkCandidateSelectionPolicy {
    var maxAlternativesPerCluster: Int

    func selectedGlyphCandidates(
        forColumnAt index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> [GlyphCandidate] {
        let column = sortedColumns[index]
        var selected = Array(column.prefix(maxAlternativesPerCluster))

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
            promoteCandidate("3", minimumConfidence: 0.84)
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

        let currentColumnCanCarryOne = sortedColumns[index].hasExplicitAlteredThirteenDigit("1")
            || !sortedColumns[index].hasStrongWrapperEvidence
        let nextColumnHasExplicitThree = sortedColumns[index + 1].hasExplicitAlteredThirteenDigit("3")
        let previousColumnLooksLikeAlteration = sortedColumns[index - 1].contains { candidate in
            candidate.confidence >= 0.45 && (candidate.text == "#" || candidate.text == "b")
        }
        let hasDominantSevenBeforeAlteration = sortedColumns[..<(index - 1)].contains { column in
            column.contains { candidate in
                candidate.confidence >= 0.50 && candidate.text == "7"
            }
        }

        return currentColumnCanCarryOne
            && nextColumnHasExplicitThree
            && previousColumnLooksLikeAlteration
            && hasDominantSevenBeforeAlteration
    }

    private func shouldExposeAlteredDominantThirteenContinuationCandidate(
        at index: Int,
        in sortedColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard index >= 3 else {
            return false
        }

        let currentColumnHasExplicitThree = sortedColumns[index].hasExplicitAlteredThirteenDigit("3")
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

        return currentColumnHasExplicitThree
            && previousColumnLooksLikeOne
            && hasAlterationAccidentalBeforePreviousColumn
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
}

private extension Array where Element == GlyphCandidate {
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

    func hasExplicitAlteredThirteenDigit(_ text: String) -> Bool {
        let hasDigit = contains { candidate in
            candidate.text == text
                && candidate.source != .composer
                && candidate.confidence >= 0.45
        }

        return hasDigit && !hasStrongWrapperEvidence
    }

    var hasStrongWrapperEvidence: Bool {
        contains { candidate in
            ["(", ")"].contains(candidate.text)
                && candidate.confidence >= 0.70
        }
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
