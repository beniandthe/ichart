struct ChordInkCandidateGrammarPolicy {
    private static let rootTexts: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
    private static let suffixAndModifierTexts: Set<String> = [
        "#", "b", "△", "°", "ø", "•", "+", "m", "a", "l", "t",
        "-", "s", "u", "6", "7", "9", "(", ")", "1", "3", "5"
    ]
    private static let detachedRootPressureVetoTexts: Set<String> = ["m", "-", "6"]
    private static let detachedRootPressureMinimumConfidence = 0.90
    private static let detachedRootPressureMaximumLag = 0.08

    func allows(_ candidate: ChordInkCandidate) -> Bool {
        allows(text: candidate.text, glyphCandidates: candidate.glyphCandidates)
    }

    func allows(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        allows(text: candidate.text, glyphCandidates: candidate.glyphCandidates)
            && !usesDetachedRootPressureAsSuffix(
                candidate,
                candidateColumns: candidateColumns,
                clusters: clusters
            )
    }

    func allows(text: String, glyphCandidates: [GlyphCandidate]) -> Bool {
        guard glyphCandidates.count >= 2,
              let rootGlyph = glyphCandidates.first,
              Self.rootTexts.contains(rootGlyph.text) else {
            return true
        }

        let accidentalGlyph = glyphCandidates[1]
        guard accidentalGlyph.text == "B",
              let symbol = try? ChordSymbolParser.parse(text),
              symbol.kind == .rooted,
              symbol.root.rawValue == rootGlyph.text,
              symbol.accidental == .flat else {
            return true
        }

        return false
    }

    private func usesDetachedRootPressureAsSuffix(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        guard candidate.glyphCandidates.count >= 2,
              candidateColumns.count >= candidate.glyphCandidates.count,
              clusters.count >= candidate.glyphCandidates.count,
              let symbol = try? ChordSymbolParser.parse(candidate.text),
              symbol.kind == .rooted else {
            return false
        }

        for index in candidate.glyphCandidates.indices.dropFirst() {
            let glyph = candidate.glyphCandidates[index]
            guard Self.detachedRootPressureVetoTexts.contains(glyph.text),
                  !isSlashBassRole(at: index, in: candidate.glyphCandidates),
                  !isProtectedChordSuffixRole(at: index, in: candidate.glyphCandidates),
                  hasDetachedRootPressure(
                    in: candidateColumns[index],
                    selectedGlyph: glyph
                  ) else {
                continue
            }

            let prefixBounds = InkBounds.enclosing(
                Array(clusters.prefix(index)).map(\.bounds)
            )
            if ChordInkSequentialRootStartDetector.isDetachedRootSizedGlyph(
                clusters[index].bounds,
                from: prefixBounds
            ) {
                return true
            }
        }

        return false
    }

    private func isProtectedChordSuffixRole(
        at index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        if hasRootAccidentalBefore(index, in: glyphCandidates) {
            return true
        }

        if glyphCandidates[index].text == "6",
           hasQualityBefore(index, in: glyphCandidates) {
            return true
        }

        return false
    }

    private func hasRootAccidentalBefore(
        _ index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        guard index > 1 else {
            return false
        }

        return glyphCandidates[1..<index].contains { glyph in
            glyph.text == "b" || glyph.text == "#"
        }
    }

    private func hasQualityBefore(
        _ index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        guard index > 1 else {
            return false
        }

        return glyphCandidates[1..<index].contains { glyph in
            glyph.text == "-" || glyph.text == "m"
        }
    }

    private func isSlashBassRole(
        at index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        if index > 0,
           glyphCandidates[index - 1].text == "/" {
            return true
        }

        if index > 1,
           glyphCandidates[index - 2].text == "/",
           glyphCandidates[index - 1].text.count == 1,
           glyphCandidates[index - 1].text.first.map({ "ABCDEFG".contains($0) }) == true,
           glyphCandidates[index].text == "b" || glyphCandidates[index].text == "#" {
            return true
        }

        return false
    }

    private func hasDetachedRootPressure(
        in column: [GlyphCandidate],
        selectedGlyph: GlyphCandidate
    ) -> Bool {
        guard let rootCandidate = column.first(where: { candidate in
            Self.rootTexts.contains(candidate.text)
                && candidate.source == .heuristic
                && candidate.confidence >= Self.detachedRootPressureMinimumConfidence
        }) else {
            return false
        }

        let selectedConfidence = column.first { candidate in
            candidate.text == selectedGlyph.text
        }?.confidence ?? selectedGlyph.confidence
        let bestConfidence = column.first?.confidence ?? selectedConfidence

        return rootCandidate.confidence
            + Self.detachedRootPressureMaximumLag
            >= max(bestConfidence, selectedConfidence)
    }
}
