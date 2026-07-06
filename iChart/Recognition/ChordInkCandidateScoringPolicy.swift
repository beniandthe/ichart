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
    var dominantSharpNineTrailingWrapperBonus = 0.36
    var dominantFlatFiveBonus = 0.08
    var dominantFlatThirteenBonus = 0.08
    var explicitMinorSixthBonus = 0.12
    var dashMinorNinthLookalikePenalty = 0.18
    var suspendedMinorSixthPenalty = 0.65
    var explicitMajorSixthBonus = 0.42
    var likelyRootFlatCollisionPenalty = 0.35
    var triangleQualityMinConfidence = 0.60
    var triangleQualityBonus = 0.62
    var ninthSharpFiveBonus = 0.20
    var ninthSharpFiveWeakRootStructureBonus = 0.24
    var strongDominantSharpConfidence = 0.65
    var explicitSharpElevenBonus = 0.78
    var unreliableSharpElevenPenalty = 0.55
    var dominantSharpFiveBonus = 0.06
    var dominantSharpFiveTailEvidenceBonus = 0.24
    var dominantSharpFiveStrongNinthExtensionPenalty = 0.38
    var weakDominantSharpAlterationPenalty = 0.70
    var slashBassMinConfidence = 0.65
    var slashBassBonus = 0.85
    var plainFlatRootSlashBassBonus = 0.06
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

struct ChordInkCandidateScoringPolicy {
    var scoring: ChordInkCandidateComposerScoring

    func score(
        text: String,
        glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]],
        totalClusterCount: Int
    ) -> Double {
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
            if hasAlteredExtensionTrailingWrapperEvidence(
                in: glyphCandidates,
                accidental: "#"
            ) {
                score += scoring.dominantSharpNineTrailingWrapperBonus
            }
            if hasStrongNinthExtensionEvidence(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) {
                score -= scoring.dominantSharpFiveStrongNinthExtensionPenalty
            }
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

        if (text.contains("9#5") || text.contains("9(#5)")),
           !hasDominantSevenLookalikeForNinthSharpFive(
               in: glyphCandidates,
               candidateColumns: candidateColumns
           ) {
            score += scoring.ninthSharpFiveBonus
            if isNinthSharpFiveSymbol(parsedSymbol),
               let rootConfidence = leadingRootConfidence(in: glyphCandidates),
               rootConfidence >= 0.50,
               rootConfidence < scoring.veryWeakRootConfidenceThreshold {
                score += scoring.ninthSharpFiveWeakRootStructureBonus
            }
        }

        if text.contains("7#11") || text.contains("7(#11)") {
            let hasStrongSharp = (dominantAlterationAccidentalConfidence("#", in: glyphCandidates) ?? 0) >= scoring.strongDominantSharpConfidence
            if hasDominantSharpFiveTailCollision(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) || hasDominantSharpNineTailCollision(
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
            if hasStrongNinthExtensionEvidence(
                in: glyphCandidates,
                candidateColumns: candidateColumns
            ) {
                score -= scoring.dominantSharpFiveStrongNinthExtensionPenalty
            }
        }

        if hasDominantSharpAlteration(text),
           (dominantAlterationAccidentalConfidence("#", in: glyphCandidates) ?? 1.0) < scoring.strongDominantSharpConfidence {
            score -= scoring.weakDominantSharpAlterationPenalty
        }

        if hasValidSlashBass(text),
           slashGlyphConfidence(in: glyphCandidates) >= scoring.slashBassMinConfidence {
            score += scoring.slashBassBonus
            if isPlainFlatRootSlashBassSymbol(parsedSymbol),
               hasRootAccidentalEvidence("b", in: glyphCandidates) {
                score += scoring.plainFlatRootSlashBassBonus
            }
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
        guard let symbol,
              symbol.kind == .rooted else {
            return false
        }

        return symbol.quality == "-"
            && symbol.extensions == ["6"]
            && symbol.alterations.isEmpty
    }

    private func isPlainFlatRootSlashBassSymbol(_ symbol: ChordSymbol?) -> Bool {
        guard let symbol,
              symbol.kind == .rooted else {
            return false
        }

        return symbol.accidental == .flat
            && symbol.quality.isEmpty
            && symbol.extensions.isEmpty
            && symbol.alterations.isEmpty
            && symbol.slashBass != nil
    }

    private func hasRootAccidentalEvidence(_ text: String, in glyphCandidates: [GlyphCandidate]) -> Bool {
        guard glyphCandidates.indices.contains(1) else {
            return false
        }

        let candidate = glyphCandidates[1]
        return candidate.text == text && candidate.confidence >= 0.45
    }

    private func isMajorSixthSymbol(_ symbol: ChordSymbol?) -> Bool {
        guard let symbol,
              symbol.kind == .rooted else {
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
        guard let symbol,
              symbol.kind == .rooted else {
            return false
        }

        return symbol.quality.contains("△")
            && symbol.alterations.contains("#11")
    }

    private func isNinthSharpFiveSymbol(_ symbol: ChordSymbol?) -> Bool {
        guard let symbol,
              symbol.kind == .rooted else {
            return false
        }

        return symbol.quality.isEmpty
            && symbol.extensions == ["9"]
            && symbol.alterations == ["#5"]
            && symbol.slashBass == nil
    }

    private func hasDominantSevenLookalikeForNinthSharpFive(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard let ninthIndex = firstExtensionIndex(in: glyphCandidates),
              glyphCandidates.indices.contains(ninthIndex),
              glyphCandidates[ninthIndex].text == "9",
              candidateColumns.indices.contains(ninthIndex) else {
            return false
        }

        let writtenNineConfidence = glyphCandidates[ninthIndex].confidence
        let competingSevenConfidence = candidateColumns[ninthIndex]
            .filter { $0.text == "7" }
            .map(\.confidence)
            .max() ?? 0

        if writtenNineConfidence >= 0.95,
           writtenNineConfidence > competingSevenConfidence {
            return false
        }

        return competingSevenConfidence >= 0.65
            && competingSevenConfidence + 0.12 >= writtenNineConfidence
    }

    private func hasStrongNinthExtensionEvidence(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard let extensionIndex = firstExtensionIndex(in: glyphCandidates),
              glyphCandidates.indices.contains(extensionIndex),
              glyphCandidates[extensionIndex].text == "7",
              candidateColumns.indices.contains(extensionIndex) else {
            return false
        }

        let writtenSevenConfidence = glyphCandidates[extensionIndex].confidence
        let competingNineConfidence = candidateColumns[extensionIndex]
            .filter { $0.text == "9" }
            .map(\.confidence)
            .max() ?? 0

        return competingNineConfidence >= 0.95
            && competingNineConfidence > writtenSevenConfidence
    }

    private func firstExtensionIndex(in glyphCandidates: [GlyphCandidate]) -> Int? {
        guard !glyphCandidates.isEmpty else {
            return nil
        }

        var index = 1
        if glyphCandidates.indices.contains(index),
           glyphCandidates[index].text == "b" || glyphCandidates[index].text == "#" {
            index += 1
        }

        return glyphCandidates.indices.contains(index) ? index : nil
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
        return hasSuspendedContextCandidate("s", in: suffixColumns[0])
            && hasSuspendedContextCandidate("u", in: suffixColumns[1])
            && hasSuspendedContextCandidate("s", in: suffixColumns[2])
    }

    private func hasSuspendedContextCandidate(
        _ text: String,
        in column: [GlyphCandidate]
    ) -> Bool {
        column.contains { candidate in
            candidate.text == text
                && (candidate.confidence >= 0.70 || candidate.source == .composer)
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

    private func hasDominantSharpNineTailCollision(
        in glyphCandidates: [GlyphCandidate],
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        guard hasExplicitSharpElevenNumberTail(in: glyphCandidates),
              let firstAlteredNumberIndex = firstAlteredNumberIndex(
                  in: glyphCandidates,
                  accidental: "#"
              ),
              candidateColumns.indices.contains(firstAlteredNumberIndex) else {
            return false
        }

        let firstNumberGlyph = glyphCandidates[firstAlteredNumberIndex]
        let nineConfidence = candidateColumns[firstAlteredNumberIndex]
            .filter { $0.text == "9" }
            .map(\.confidence)
            .max() ?? 0

        return firstNumberGlyph.text == "1"
            && nineConfidence >= 0.55
            && nineConfidence + 0.30 >= firstNumberGlyph.confidence
    }

    private func firstAlteredNumberIndex(
        in glyphCandidates: [GlyphCandidate],
        accidental: String
    ) -> Int? {
        var hasPassedDominantSeven = false
        var hasPassedAlterationAccidental = false

        for (index, candidate) in glyphCandidates.enumerated() {
            if candidate.text == "7" {
                hasPassedDominantSeven = true
                hasPassedAlterationAccidental = false
                continue
            }

            guard hasPassedDominantSeven else {
                continue
            }

            if !hasPassedAlterationAccidental {
                if candidate.text == accidental {
                    hasPassedAlterationAccidental = true
                }
                continue
            }

            if candidate.text != "(" && candidate.text != ")" {
                return index
            }
        }

        return nil
    }

    private func hasAlteredExtensionTrailingWrapperEvidence(
        in glyphCandidates: [GlyphCandidate],
        accidental: String
    ) -> Bool {
        guard let firstAlteredNumberIndex = firstAlteredNumberIndex(
            in: glyphCandidates,
            accidental: accidental
        ) else {
            return false
        }

        return glyphCandidates.indices.contains(firstAlteredNumberIndex + 1)
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
            candidate.text == "s" && candidate.confidence >= 0.50
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
