import Foundation

struct ChordInkCandidate: Hashable {
    var text: String
    var confidence: Double
    var glyphCandidates: [GlyphCandidate]
}

struct ChordInkCandidateComposerConfiguration: Hashable {
    var maxAlternativesPerCluster: Int
    var maxCandidateCount: Int
    var maxGeneratedSequences: Int

    static let chordSymbols = ChordInkCandidateComposerConfiguration(
        maxAlternativesPerCluster: 3,
        maxCandidateCount: 32,
        maxGeneratedSequences: 4096
    )
}

struct ChordInkCandidateComposer {
    var configuration: ChordInkCandidateComposerConfiguration

    init(configuration: ChordInkCandidateComposerConfiguration = .chordSymbols) {
        self.configuration = configuration
    }

    func compose(glyphCandidates columns: [[GlyphCandidate]]) -> [ChordInkCandidate] {
        let sortedColumns = columns.map(\.sortedByConfidence)
        let candidateColumns = sortedColumns
            .enumerated()
            .map { index, column in
                selectedGlyphCandidates(forColumnAt: index, in: sortedColumns)
            }
            .filter { !$0.isEmpty }

        guard !candidateColumns.isEmpty else {
            return []
        }

        var bestCandidatesByText: [String: ChordInkCandidate] = [:]
        var generatedSequenceCount = 0

        for prefixLength in 1...candidateColumns.count {
            let prefixColumns = Array(candidateColumns.prefix(prefixLength))
            for sequence in candidateSequences(from: prefixColumns) {
                guard generatedSequenceCount < configuration.maxGeneratedSequences else {
                    break
                }

                generatedSequenceCount += 1

                for variant in textVariants(for: sequence) {
                    let confidence = score(
                        text: variant,
                        glyphCandidates: sequence,
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

        return Array(bestCandidatesByText.values)
            .sortedByConfidence
            .prefix(configuration.maxCandidateCount)
            .map { $0 }
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
            column.contains { candidate in
                candidate.confidence >= 0.50 && candidate.text == "7"
            }
        }

        return columnContainsExtension
            && hasRootBeforeExtension
            && !hasDominantSevenBeforeExtension
            && !(text == "6"
                 && competingPlusConfidence >= 0.45
                 && competingPlusConfidence >= extensionConfidence)
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

        return Array(Set(variants + expandedVariants)).sorted()
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
        totalClusterCount: Int
    ) -> Double {
        let averageGlyphConfidence = glyphCandidates
            .map(\.confidence)
            .reduce(0, +) / Double(max(glyphCandidates.count, 1))
        var score = averageGlyphConfidence

        if startsWithRoot(text) {
            score += 1.0
        } else {
            score -= 1.0
        }

        if parsesAsChord(text) {
            score += 2.0
        } else {
            score -= 0.25
        }

        if hasAccidentalImmediatelyAfterRoot(text),
           hasDominantAlteration(text) {
            score += 0.35
        }

        if text.contains("7#9") || text.contains("7(#9)") {
            score += 0.08
        }

        if text.contains("7b5") || text.contains("7(b5)") {
            score += 0.08
        }

        if text.contains("7b13") || text.contains("7(b13)") {
            score += 0.08
        }

        if text.contains("7#11") || text.contains("7(#11)") {
            let hasStrongSharp = (dominantAlterationAccidentalConfidence("#", in: glyphCandidates) ?? 0) >= 0.65
            if hasExplicitSharpElevenNumberTail(in: glyphCandidates)
                || (hasStrongSharp && hasReliableCompactSharpElevenTail(in: glyphCandidates)) {
                score += 0.78
            } else {
                score -= 0.55
            }
        }

        if (text.contains("7#5") || text.contains("7(#5)")),
           (dominantAlterationAccidentalConfidence("#", in: glyphCandidates) ?? 0) >= 0.65 {
            score += 0.06
        }

        if hasDominantSharpAlteration(text),
           (dominantAlterationAccidentalConfidence("#", in: glyphCandidates) ?? 1.0) < 0.65 {
            score -= 0.06
        }

        if hasValidSlashBass(text),
           slashGlyphConfidence(in: glyphCandidates) >= 0.65 {
            score += 0.85
        } else if text.contains("/") {
            score -= 0.75
        }

        // Prefer candidates that explain more of the written glyphs, so C-7 wins
        // over the C- prefix when the written extension is still present.
        score += Double(max(0, glyphCandidates.count - 1)) * 0.12
        score -= Double(max(0, totalClusterCount - glyphCandidates.count)) * 2.00

        return score
    }

    private func startsWithRoot(_ text: String) -> Bool {
        guard let first = text.first else {
            return false
        }

        return "ABCDEFG".contains(first)
    }

    private func parsesAsChord(_ text: String) -> Bool {
        (try? ChordSymbolParser.parse(text)) != nil
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

    private func hasValidSlashBass(_ text: String) -> Bool {
        let pieces = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else {
            return false
        }

        return ChordPitch.parse(pieces[1]) != nil
    }

    private func slashGlyphConfidence(in glyphCandidates: [GlyphCandidate]) -> Double {
        glyphCandidates
            .filter { $0.text == "/" }
            .map(\.confidence)
            .max() ?? 0
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
