import Foundation

struct ChordInkRecognitionCandidateResult: Hashable {
    var candidates: [ChordInkCandidate]
    var compositionMetrics: ChordInkCandidateCompositionMetrics
    var composeMilliseconds: Double
    var semanticMilliseconds: Double
    var semanticCandidateCount: Int
}

struct ChordInkRecognitionCandidateComposer {
    var baseComposer: ChordInkCandidateComposer
    var semanticCandidateComposer: ChordInkSemanticCandidateComposer

    init(
        baseComposer: ChordInkCandidateComposer = ChordInkCandidateComposer(),
        semanticCandidateComposer: ChordInkSemanticCandidateComposer = ChordInkSemanticCandidateComposer()
    ) {
        self.baseComposer = baseComposer
        self.semanticCandidateComposer = semanticCandidateComposer
    }

    func composeRecognitionCandidates(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkRecognitionCandidateResult {
        let composeStart = Date()
        let compositionResult = baseComposer.composeDetailed(glyphCandidates: glyphCandidateGroups)
        let composeMilliseconds = Self.elapsedMilliseconds(since: composeStart)
        let composedCandidates = compositionResult.candidates
        var bestCandidatesByText = Dictionary(
            uniqueKeysWithValues: composedCandidates.map { ($0.text, $0) }
        )

        let semanticStart = Date()
        let semanticCandidates = semanticCandidateComposer.candidates(
            from: glyphCandidateGroups,
            clusters: clusters
        )
        for semanticCandidate in semanticCandidates {
            if let currentBest = bestCandidatesByText[semanticCandidate.text],
               currentBest.confidence >= semanticCandidate.confidence {
                continue
            }

            bestCandidatesByText[semanticCandidate.text] = semanticCandidate
        }
        let semanticMilliseconds = Self.elapsedMilliseconds(since: semanticStart)

        let candidates = Array(bestCandidatesByText.values).sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.text < rhs.text
        }
        return ChordInkRecognitionCandidateResult(
            candidates: candidates,
            compositionMetrics: compositionResult.metrics,
            composeMilliseconds: composeMilliseconds,
            semanticMilliseconds: semanticMilliseconds,
            semanticCandidateCount: semanticCandidates.count
        )
    }

    private static func elapsedMilliseconds(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1_000
    }
}

struct ChordInkSemanticCandidateComposer {
    func candidates(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> [ChordInkCandidate] {
        [
            diminishedQualityCandidate(from: glyphCandidateGroups, clusters: clusters),
            plainNinthAlteredExtensionCandidate(from: glyphCandidateGroups, clusters: clusters),
            majorAlteredExtensionCandidate(from: glyphCandidateGroups, clusters: clusters),
            dominantAlteredCandidate(from: glyphCandidateGroups, clusters: clusters),
            dominantSharpElevenCandidate(from: glyphCandidateGroups, clusters: clusters),
            majorSharpElevenCandidate(from: glyphCandidateGroups, clusters: clusters),
            minorEleventhCandidate(from: glyphCandidateGroups, clusters: clusters),
            majorSixthCandidate(from: glyphCandidateGroups, clusters: clusters),
            suspendedSuffixCandidate(from: glyphCandidateGroups, clusters: clusters)
        ].compactMap { $0 }
    }

    private func minorEleventhCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 3,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.65
           ),
           isHighAccidentalCluster(clusters[index], rootBounds: clusters[0].bounds) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
        }

        guard glyphCandidateGroups.indices.contains(index),
              let minorCandidate = minorQualityCandidate(in: glyphCandidateGroups[index]) else {
            return nil
        }
        glyphs.append(minorCandidate)
        symbolText.append("-")
        index += 1

        guard index == glyphCandidateGroups.count - 1,
              let tailCandidate = compressedEleventhTailCandidate(
                  in: glyphCandidateGroups[index],
                  cluster: clusters[index]
              ) else {
            return nil
        }

        glyphs.append(tailCandidate)
        symbolText.append("11")

        return ChordInkCandidate(
            text: symbolText,
            confidence: 4.42,
            glyphCandidates: glyphs
        )
    }

    private func majorSixthCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 2,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.65
           ),
           isHighAccidentalCluster(clusters[index], rootBounds: clusters[0].bounds) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
        }

        guard index == glyphCandidateGroups.count - 1,
              let sixthCandidate = sixthCandidate(
                  in: glyphCandidateGroups[index],
                  cluster: clusters[index],
                  rootBounds: clusters[0].bounds
              ) else {
            return nil
        }

        glyphs.append(sixthCandidate)
        symbolText.append("6")

        return ChordInkCandidate(
            text: symbolText,
            confidence: 4.36,
            glyphCandidates: glyphs
        )
    }

    private enum SuspendedSuffixKind {
        case suspended
        case suspendedFourth
    }

    private struct MajorExtensionCandidate {
        var text: String
        var glyphs: [GlyphCandidate]
        var nextIndex: Int
    }

    private struct AlteredExtensionCandidate {
        var accidental: String
        var number: String
        var glyphs: [GlyphCandidate]
    }

    private func suspendedSuffixCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 3,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.65
           ),
           isHighAccidentalCluster(clusters[index], rootBounds: clusters[0].bounds) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
        }

        var hasDominantSeven = false
        if glyphCandidateGroups.indices.contains(index),
           let sevenCandidate = sevenCandidate(in: glyphCandidateGroups[index]) {
            hasDominantSeven = true
            glyphs.append(sevenCandidate)
            index += 1
        }

        guard index < glyphCandidateGroups.count else {
            return nil
        }

        let suffixGroups = Array(glyphCandidateGroups[index...])
        let suffixClusters = Array(clusters[index...])
        guard let suffixKind = suspendedSuffixKind(
            in: suffixGroups,
            clusters: suffixClusters,
            rootBounds: clusters[0].bounds
        ) else {
            return nil
        }

        if hasDominantSeven {
            symbolText.append("7sus")
            glyphs.append(contentsOf: [
                GlyphCandidate(text: "s", confidence: 0.86, source: .composer),
                GlyphCandidate(text: "u", confidence: 0.86, source: .composer),
                GlyphCandidate(text: "s", confidence: 0.86, source: .composer)
            ])
            return ChordInkCandidate(
                text: symbolText,
                confidence: 5.05,
                glyphCandidates: glyphs
            )
        }

        switch suffixKind {
        case .suspended:
            symbolText.append("sus")
            glyphs.append(contentsOf: [
                GlyphCandidate(text: "s", confidence: 0.84, source: .composer),
                GlyphCandidate(text: "u", confidence: 0.84, source: .composer),
                GlyphCandidate(text: "s", confidence: 0.84, source: .composer)
            ])
            return ChordInkCandidate(
                text: symbolText,
                confidence: 4.95,
                glyphCandidates: glyphs
            )
        case .suspendedFourth:
            symbolText.append("sus4")
            glyphs.append(contentsOf: [
                GlyphCandidate(text: "s", confidence: 0.86, source: .composer),
                GlyphCandidate(text: "u", confidence: 0.86, source: .composer),
                GlyphCandidate(text: "s", confidence: 0.86, source: .composer),
                GlyphCandidate(text: "4", confidence: 0.82, source: .composer)
            ])
            return ChordInkCandidate(
                text: symbolText,
                confidence: 5.15,
                glyphCandidates: glyphs
            )
        }
    }

    private func diminishedQualityCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 2,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.50
           ),
           isDiminishedAccidentalCluster(
               glyphCandidateGroups[index],
               cluster: clusters[index],
               rootBounds: clusters[0].bounds,
               nextGroup: glyphCandidateGroups.indices.contains(index + 1)
                   ? glyphCandidateGroups[index + 1]
                   : nil
           ) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
        }

        guard glyphCandidateGroups.indices.contains(index),
              let diminishedCandidate = diminishedQualityCandidate(
                  in: glyphCandidateGroups[index]
              ) ?? contextualDiminishedQualityCandidate(
                  in: glyphCandidateGroups[index],
                  cluster: clusters[index],
                  rootBounds: clusters[0].bounds,
                  nextGroup: glyphCandidateGroups.indices.contains(index + 1)
                      ? glyphCandidateGroups[index + 1]
                      : nil
              ) else {
            return nil
        }

        glyphs.append(diminishedCandidate)
        symbolText.append("°")
        index += 1

        if glyphCandidateGroups.indices.contains(index),
           let sevenCandidate = sevenCandidate(in: glyphCandidateGroups[index]) {
            glyphs.append(sevenCandidate)
            symbolText.append("7")
            index += 1
        }

        guard index == glyphCandidateGroups.count else {
            return nil
        }

        return ChordInkCandidate(
            text: symbolText,
            confidence: symbolText.hasSuffix("7") ? 4.90 : 5.18,
            glyphCandidates: glyphs
        )
    }

    private func majorAlteredExtensionCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 5,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.50
           ),
           isMajorQualityAccidentalCluster(
               glyphCandidateGroups[index],
               cluster: clusters[index],
               rootBounds: clusters[0].bounds,
               nextGroup: glyphCandidateGroups.indices.contains(index + 1)
                   ? glyphCandidateGroups[index + 1]
                   : nil
           ) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
        }

        guard glyphCandidateGroups.indices.contains(index),
              let triangleCandidate = triangleMajorCandidate(
                  in: glyphCandidateGroups[index],
                  cluster: clusters[index]
              ) else {
            return nil
        }
        glyphs.append(triangleCandidate)
        symbolText.append("△")
        index += 1

        guard glyphCandidateGroups.indices.contains(index),
              let extensionCandidate = majorExtensionCandidate(
                  in: glyphCandidateGroups,
                  startingAt: index
              ) else {
            return nil
        }
        glyphs.append(contentsOf: extensionCandidate.glyphs)
        symbolText.append(extensionCandidate.text)
        index = extensionCandidate.nextIndex

        guard let alterationCandidate = alteredExtensionCandidate(
            in: glyphCandidateGroups,
            startingAt: index
        ) else {
            return nil
        }
        glyphs.append(contentsOf: alterationCandidate.glyphs)
        symbolText.append("(\(alterationCandidate.accidental)\(alterationCandidate.number))")

        return ChordInkCandidate(
            text: symbolText,
            confidence: 5.30,
            glyphCandidates: glyphs
        )
    }

    private func plainNinthAlteredExtensionCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 4,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text
        var consumedRootAccidental = false

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.50
           ),
           isHighAccidentalCluster(clusters[index], rootBounds: clusters[0].bounds) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
            consumedRootAccidental = true
        }

        guard consumedRootAccidental else {
            return nil
        }

        guard glyphCandidateGroups.indices.contains(index),
              shouldAttemptPlainNinthAlteredExtension(
                  at: index,
                  in: glyphCandidateGroups,
                  clusters: clusters
              ),
              let extensionCandidate = majorExtensionCandidate(
                  in: glyphCandidateGroups,
                  startingAt: index
              ),
              extensionCandidate.text == "9" else {
            return nil
        }

        glyphs.append(contentsOf: extensionCandidate.glyphs)
        symbolText.append(extensionCandidate.text)
        index = extensionCandidate.nextIndex

        guard let alterationCandidate = ninthAlterationCandidate(
            in: glyphCandidateGroups,
            clusters: clusters,
            startingAt: index
        ) else {
            return nil
        }

        glyphs.append(contentsOf: alterationCandidate.glyphs)
        symbolText.append("(\(alterationCandidate.accidental)\(alterationCandidate.number))")

        guard ChordRecognitionCompendium.match(symbolText) != nil else {
            return nil
        }

        return ChordInkCandidate(
            text: symbolText,
            confidence: 4.88,
            glyphCandidates: glyphs
        )
    }

    private func shouldAttemptPlainNinthAlteredExtension(
        at index: Int,
        in glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        guard glyphCandidateGroups.indices.contains(index),
              clusters.indices.contains(index) else {
            return false
        }

        if triangleMajorCandidate(
            in: glyphCandidateGroups[index],
            cluster: clusters[index]
        ) != nil {
            return false
        }

        if let seven = sevenCandidate(in: glyphCandidateGroups[index]),
           seven.confidence >= 0.65 {
            return false
        }

        let nineConfidence = candidateConfidence("9", in: glyphCandidateGroups[index])
        guard nineConfidence >= 0.85 else {
            return false
        }

        let accidentalConfidence = max(
            candidateConfidence("b", in: glyphCandidateGroups[index]),
            candidateConfidence("#", in: glyphCandidateGroups[index])
        )
        return accidentalConfidence < 0.85
            || (nineConfidence >= 0.95 && nineConfidence >= accidentalConfidence)
    }

    private func dominantAlteredCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 3,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.65
           ) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
        }

        let sevenIndex: Int?
        if glyphCandidateGroups.indices.contains(index),
           let sevenCandidate = sevenCandidate(in: glyphCandidateGroups[index]) {
            sevenIndex = index
            glyphs.append(sevenCandidate)
            index += 1
        } else {
            sevenIndex = nil
            glyphs.append(GlyphCandidate(text: "7", confidence: 0.78, source: .composer))
        }

        guard index < glyphCandidateGroups.count,
              isDominantAlteredSuffixContext(
                  suffixStartIndex: index,
                  sevenIndex: sevenIndex,
                  glyphCandidateGroups: glyphCandidateGroups,
                  clusters: clusters
              ) else {
            return nil
        }

        symbolText.append("7alt")
        glyphs.append(GlyphCandidate(text: "alt", confidence: 0.92, source: .composer))

        return ChordInkCandidate(
            text: symbolText,
            confidence: sevenIndex == nil ? 4.85 : 5.25,
            glyphCandidates: glyphs
        )
    }

    private func majorSharpElevenCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 4,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(in: glyphCandidateGroups[index]) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
        }

        guard glyphCandidateGroups.indices.contains(index),
              let triangleCandidate = triangleMajorCandidate(
                  in: glyphCandidateGroups[index],
                  cluster: clusters[index]
              ) else {
            return nil
        }

        glyphs.append(triangleCandidate)
        symbolText.append("△")
        index += 1

        if glyphCandidateGroups.indices.contains(index),
           let sevenCandidate = sevenCandidate(in: glyphCandidateGroups[index]) {
            glyphs.append(sevenCandidate)
            symbolText.append("7")
            index += 1
        } else {
            glyphs.append(GlyphCandidate(text: "7", confidence: 0.78, source: .composer))
            symbolText.append("7")
        }

        guard let sharpIndex = glyphCandidateGroups[index...].firstIndex(where: { group in
            group.contains { candidate in
                candidate.text == "#" && candidate.confidence >= 0.55
            }
        }) else {
            return nil
        }

        let sharpGroup = glyphCandidateGroups[sharpIndex]
        let sharpConfidence = sharpGroup
            .filter { $0.text == "#" }
            .map(\.confidence)
            .max() ?? 0
        glyphs.append(GlyphCandidate(text: "#", confidence: sharpConfidence, source: .heuristic))

        let tailGroups = Array(glyphCandidateGroups.dropFirst(sharpIndex + 1))
        let tailClusters = Array(clusters.dropFirst(sharpIndex + 1))
        guard hasExplicitSharpElevenTailEvidence(groups: tailGroups, clusters: tailClusters) else {
            return nil
        }

        glyphs.append(GlyphCandidate(text: "1", confidence: 0.82, source: .composer))
        glyphs.append(GlyphCandidate(text: "1", confidence: 0.82, source: .composer))
        symbolText.append("#11")

        return ChordInkCandidate(
            text: symbolText,
            confidence: 5.05,
            glyphCandidates: glyphs
        )
    }

    private func dominantSharpElevenCandidate(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> ChordInkCandidate? {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 5,
              let rootCandidate = rootCandidate(in: glyphCandidateGroups[0]) else {
            return nil
        }

        var glyphs = [rootCandidate]
        var index = 1
        var symbolText = rootCandidate.text

        if glyphCandidateGroups.indices.contains(index),
           let accidentalCandidate = accidentalCandidate(in: glyphCandidateGroups[index]) {
            glyphs.append(accidentalCandidate)
            symbolText.append(accidentalCandidate.text)
            index += 1
        }

        guard glyphCandidateGroups.indices.contains(index),
              let sevenCandidate = sevenCandidate(in: glyphCandidateGroups[index]) else {
            return nil
        }
        glyphs.append(sevenCandidate)
        symbolText.append("7")
        index += 1

        guard let sharpIndex = glyphCandidateGroups[index...].firstIndex(where: { group in
            group.contains { candidate in
                candidate.text == "#" && candidate.confidence >= 0.50
            }
        }) else {
            return nil
        }

        let sharpGroup = glyphCandidateGroups[sharpIndex]
        let sharpConfidence = sharpGroup
            .filter { $0.text == "#" }
            .map(\.confidence)
            .max() ?? 0
        let tailGroups = Array(glyphCandidateGroups.dropFirst(sharpIndex + 1))
        let tailClusters = Array(clusters.dropFirst(sharpIndex + 1))
        guard hasExplicitSharpElevenTailEvidence(groups: tailGroups, clusters: tailClusters) else {
            return nil
        }

        glyphs.append(GlyphCandidate(text: "#", confidence: sharpConfidence, source: .heuristic))
        glyphs.append(GlyphCandidate(text: "1", confidence: 0.82, source: .composer))
        glyphs.append(GlyphCandidate(text: "1", confidence: 0.82, source: .composer))
        symbolText.append("#11")

        return ChordInkCandidate(
            text: symbolText,
            confidence: 4.95,
            glyphCandidates: glyphs
        )
    }

    private func rootCandidate(in group: [GlyphCandidate]) -> GlyphCandidate? {
        group
            .filter { candidate in
                candidate.confidence >= 0.75 && "ABCDEFG".contains(candidate.text)
            }
            .max { lhs, rhs in
                lhs.confidence < rhs.confidence
            }
    }

    private func accidentalCandidate(
        in group: [GlyphCandidate],
        minimumConfidence: Double = 0.72
    ) -> GlyphCandidate? {
        group
            .filter { candidate in
                candidate.confidence >= minimumConfidence && (candidate.text == "#" || candidate.text == "b")
            }
            .max { lhs, rhs in
                lhs.confidence < rhs.confidence
            }
    }

    private func sevenCandidate(in group: [GlyphCandidate]) -> GlyphCandidate? {
        if group.contains(where: { candidate in
            candidate.text == "/" && candidate.confidence >= 0.65
        }) {
            return nil
        }

        guard let candidate = group
            .filter({ candidate in
                candidate.confidence >= 0.50 && candidate.text == "7"
            })
            .max(by: { lhs, rhs in lhs.confidence < rhs.confidence }) else {
            return nil
        }

        let strongRootOrAccidental = group.contains { candidate in
            candidate.confidence >= 0.85
                && ["A", "B", "C", "D", "E", "F", "G", "#", "b"].contains(candidate.text)
        }

        return strongRootOrAccidental && candidate.confidence < 0.85 ? nil : candidate
    }

    private func diminishedQualityCandidate(in group: [GlyphCandidate]) -> GlyphCandidate? {
        guard let candidate = group
            .filter({ candidate in
                candidate.text == "°" && candidate.confidence >= 0.50
            })
            .max(by: { lhs, rhs in lhs.confidence < rhs.confidence }) else {
            return nil
        }

        let strongestConfidence = group.map(\.confidence).max() ?? 0
        guard candidate.confidence >= 0.82
                || candidate.confidence + 0.08 >= strongestConfidence else {
            return nil
        }

        let halfDiminishedConfidence = candidateConfidence("ø", in: group)
        let triangleConfidence = candidateConfidence("△", in: group)
        let dominantSevenConfidence = candidateConfidence("7", in: group)
        let extensionThreeConfidence = candidateConfidence("3", in: group)
        let extensionOneConfidence = candidateConfidence("1", in: group)
        guard halfDiminishedConfidence < max(0.74, candidate.confidence + 0.04),
              triangleConfidence < max(0.72, candidate.confidence + 0.08),
              dominantSevenConfidence <= candidate.confidence + 0.06,
              extensionThreeConfidence <= candidate.confidence + 0.06,
              extensionOneConfidence <= candidate.confidence + 0.06 else {
            return nil
        }

        return GlyphCandidate(
            text: "°",
            confidence: max(candidate.confidence, 0.84),
            source: candidate.source
        )
    }

    private func contextualDiminishedQualityCandidate(
        in group: [GlyphCandidate],
        cluster: InkCluster,
        rootBounds: InkBounds,
        nextGroup: [GlyphCandidate]?
    ) -> GlyphCandidate? {
        guard nextGroup.map({ sevenCandidate(in: $0) != nil }) == true else {
            return nil
        }

        let bounds = cluster.bounds
        let isCompactUpperQualityMark = bounds.width <= max(12, rootBounds.width * 0.70)
            && bounds.height <= max(14, rootBounds.height * 0.45)
            && bounds.maxY <= rootBounds.minY + rootBounds.height * 0.50
        guard isCompactUpperQualityMark else {
            return nil
        }

        let hardConflict = group.contains { candidate in
            candidate.confidence >= 0.82
                && ["#", "-", "m", "ø", "△", "+", "/", "1", "7"].contains(candidate.text)
        }
        guard !hardConflict else {
            return nil
        }

        let roundLookalikeConfidence = ["b", "G", "C", "6", "9"]
            .map { candidateConfidence($0, in: group) }
            .max() ?? 0
        guard roundLookalikeConfidence >= 0.50 else {
            return nil
        }

        return GlyphCandidate(text: "°", confidence: 0.86, source: .composer)
    }

    private func isDiminishedAccidentalCluster(
        _ group: [GlyphCandidate],
        cluster: InkCluster,
        rootBounds: InkBounds,
        nextGroup: [GlyphCandidate]?
    ) -> Bool {
        let flatConfidence = candidateConfidence("b", in: group)
        let sharpConfidence = candidateConfidence("#", in: group)
        guard max(flatConfidence, sharpConfidence) >= 0.50 else {
            return false
        }

        if isHighAccidentalCluster(cluster, rootBounds: rootBounds) {
            return true
        }

        let nextHasDiminished = nextGroup
            .map { diminishedQualityCandidate(in: $0) != nil } == true
        let sitsAboveRootBody = cluster.bounds.maxY <= rootBounds.maxY + rootBounds.height * 0.08
        return nextHasDiminished
            && flatConfidence >= 0.45
            && sitsAboveRootBody
    }

    private func isMajorQualityAccidentalCluster(
        _ group: [GlyphCandidate],
        cluster: InkCluster,
        rootBounds: InkBounds,
        nextGroup: [GlyphCandidate]?
    ) -> Bool {
        let accidentalConfidence = max(
            candidateConfidence("b", in: group),
            candidateConfidence("#", in: group)
        )
        guard accidentalConfidence >= 0.50 else {
            return false
        }

        if isHighAccidentalCluster(cluster, rootBounds: rootBounds) {
            return true
        }

        let nextHasTriangle = nextGroup?.contains { candidate in
            candidate.text == "△" && candidate.confidence >= 0.55
        } == true
        if nextHasTriangle && accidentalConfidence >= 0.65 {
            return true
        }

        let sitsAboveRootBody = cluster.bounds.maxY <= rootBounds.maxY + rootBounds.height * 0.10
        return nextHasTriangle && sitsAboveRootBody
    }

    private func majorExtensionCandidate(
        in groups: [[GlyphCandidate]],
        startingAt index: Int
    ) -> MajorExtensionCandidate? {
        guard groups.indices.contains(index) else {
            return nil
        }

        let seven = sevenCandidate(in: groups[index])
        let nine = bestCandidate(in: groups[index], text: "9", minimumConfidence: 0.42)

        if let seven,
           seven.confidence >= 0.80,
           seven.confidence + 0.05 >= (nine?.confidence ?? 0) {
            return MajorExtensionCandidate(
                text: "7",
                glyphs: [seven],
                nextIndex: index + 1
            )
        }

        if let candidate = nine,
           candidate.confidence >= 0.85
               || candidate.confidence >= (seven?.confidence ?? 0) + 0.10 {
            return MajorExtensionCandidate(
                text: "9",
                glyphs: [candidate],
                nextIndex: index + 1
            )
        }

        if let candidate = seven {
            return MajorExtensionCandidate(
                text: "7",
                glyphs: [candidate],
                nextIndex: index + 1
            )
        }

        if groups.indices.contains(index + 1),
           let oneCandidate = bestCandidate(in: groups[index], text: "1", minimumConfidence: 0.58),
           let threeCandidate = bestCandidate(in: groups[index + 1], text: "3", minimumConfidence: 0.45) {
            return MajorExtensionCandidate(
                text: "13",
                glyphs: [oneCandidate, threeCandidate],
                nextIndex: index + 2
            )
        }

        return nil
    }

    private func alteredExtensionCandidate(
        in groups: [[GlyphCandidate]],
        startingAt index: Int
    ) -> AlteredExtensionCandidate? {
        guard index < groups.count else {
            return nil
        }

        let alterationRange = groups.indices.suffix(from: index)
        guard let accidentalIndex = alterationRange.first(where: { groupIndex in
            candidateConfidence("b", in: groups[groupIndex]) >= 0.42
                || candidateConfidence("#", in: groups[groupIndex]) >= 0.42
        }) else {
            return nil
        }

        let accidentalGlyph: GlyphCandidate
        if let sharp = bestCandidate(in: groups[accidentalIndex], text: "#", minimumConfidence: 0.42),
           sharp.confidence >= candidateConfidence("b", in: groups[accidentalIndex]) {
            accidentalGlyph = sharp
        } else if let flat = bestCandidate(in: groups[accidentalIndex], text: "b", minimumConfidence: 0.42) {
            accidentalGlyph = flat
        } else {
            return nil
        }

        let numberGroups = groups.suffix(from: accidentalIndex + 1)
        if let elevenCandidate = compactElevenCandidate(in: numberGroups) {
            return AlteredExtensionCandidate(
                accidental: accidentalGlyph.text,
                number: "11",
                glyphs: [accidentalGlyph] + elevenCandidate
            )
        }

        if let fiveCandidate = strongestCandidate(in: numberGroups, text: "5", minimumConfidence: 0.38) {
            return AlteredExtensionCandidate(
                accidental: accidentalGlyph.text,
                number: "5",
                glyphs: [accidentalGlyph, fiveCandidate]
            )
        }

        if let nineCandidate = strongestCandidate(in: numberGroups, text: "9", minimumConfidence: 0.38) {
            return AlteredExtensionCandidate(
                accidental: accidentalGlyph.text,
                number: "9",
                glyphs: [accidentalGlyph, nineCandidate]
            )
        }

        if let thirteenCandidate = compactThirteenCandidate(in: numberGroups) {
            return AlteredExtensionCandidate(
                accidental: accidentalGlyph.text,
                number: "13",
                glyphs: [accidentalGlyph] + thirteenCandidate
            )
        }

        return nil
    }

    private func ninthAlterationCandidate(
        in groups: [[GlyphCandidate]],
        clusters: [InkCluster],
        startingAt index: Int
    ) -> AlteredExtensionCandidate? {
        guard index < groups.count else {
            return nil
        }

        let possibleAccidentals = groups.indices.suffix(from: index).dropLast().compactMap { groupIndex -> (Int, GlyphCandidate)? in
            let sharp = bestCandidate(in: groups[groupIndex], text: "#", minimumConfidence: 0.42)
            let flat = bestCandidate(in: groups[groupIndex], text: "b", minimumConfidence: 0.42)
            guard let accidental = [sharp, flat].compactMap({ $0 }).max(by: { lhs, rhs in
                lhs.confidence < rhs.confidence
            }) else {
                return nil
            }

            return (groupIndex, accidental)
        }

        guard let (accidentalIndex, accidentalGlyph) = possibleAccidentals.max(by: { lhs, rhs in
            lhs.1.confidence < rhs.1.confidence
        }) else {
            return nil
        }
        guard accidentalGlyph.text == "b" else {
            return nil
        }

        let numberRange = groups.indices.suffix(from: accidentalIndex + 1)
        if let fiveCandidate = numberRange
            .compactMap({ bestCandidate(in: groups[$0], text: "5", minimumConfidence: 0.38) })
            .max(by: { lhs, rhs in lhs.confidence < rhs.confidence }) {
            return AlteredExtensionCandidate(
                accidental: accidentalGlyph.text,
                number: "5",
                glyphs: [accidentalGlyph, fiveCandidate]
            )
        }

        for groupIndex in numberRange where clusters.indices.contains(groupIndex) {
            if let noisyFive = noisyAlteredFiveCandidate(
                in: groups[groupIndex],
                cluster: clusters[groupIndex]
            ) {
                return AlteredExtensionCandidate(
                    accidental: accidentalGlyph.text,
                    number: "5",
                    glyphs: [accidentalGlyph, noisyFive]
                )
            }
        }

        if let nineCandidate = numberRange
            .compactMap({ bestCandidate(in: groups[$0], text: "9", minimumConfidence: 0.38) })
            .max(by: { lhs, rhs in lhs.confidence < rhs.confidence }) {
            return AlteredExtensionCandidate(
                accidental: accidentalGlyph.text,
                number: "9",
                glyphs: [accidentalGlyph, nineCandidate]
            )
        }

        return nil
    }

    private func noisyAlteredFiveCandidate(
        in group: [GlyphCandidate],
        cluster: InkCluster
    ) -> GlyphCandidate? {
        let nineConfidence = candidateConfidence("9", in: group)
        let roundedTopConfidence = ["B", "D", "F", "+"]
            .map { candidateConfidence($0, in: group) }
            .max() ?? 0
        guard nineConfidence >= 0.80,
              roundedTopConfidence >= 0.50,
              cluster.bounds.width >= 16,
              cluster.bounds.height >= 18 else {
            return nil
        }

        return GlyphCandidate(text: "5", confidence: 0.72, source: .composer)
    }

    private func bestCandidate(
        in group: [GlyphCandidate],
        text: String,
        minimumConfidence: Double
    ) -> GlyphCandidate? {
        group
            .filter { candidate in
                candidate.text == text && candidate.confidence >= minimumConfidence
            }
            .max { lhs, rhs in
                lhs.confidence < rhs.confidence
            }
    }

    private func strongestCandidate(
        in groups: ArraySlice<[GlyphCandidate]>,
        text: String,
        minimumConfidence: Double
    ) -> GlyphCandidate? {
        groups
            .flatMap { $0 }
            .filter { candidate in
                candidate.text == text && candidate.confidence >= minimumConfidence
            }
            .max { lhs, rhs in
                lhs.confidence < rhs.confidence
            }
    }

    private func compactElevenCandidate(
        in groups: ArraySlice<[GlyphCandidate]>
    ) -> [GlyphCandidate]? {
        let ones = groups.compactMap { group in
            bestCandidate(in: group, text: "1", minimumConfidence: 0.48)
        }
        guard ones.count >= 2 else {
            return nil
        }

        return Array(ones.prefix(2))
    }

    private func compactThirteenCandidate(
        in groups: ArraySlice<[GlyphCandidate]>
    ) -> [GlyphCandidate]? {
        guard let oneCandidate = strongestCandidate(in: groups, text: "1", minimumConfidence: 0.48),
              let threeCandidate = strongestCandidate(in: groups, text: "3", minimumConfidence: 0.40) else {
            return nil
        }

        return [oneCandidate, threeCandidate]
    }

    private func candidateConfidence(_ text: String, in group: [GlyphCandidate]) -> Double {
        group
            .filter { $0.text == text }
            .map(\.confidence)
            .max() ?? 0
    }

    private func minorQualityCandidate(in group: [GlyphCandidate]) -> GlyphCandidate? {
        group
            .filter { candidate in
                candidate.confidence >= 0.70 && (candidate.text == "-" || candidate.text == "m")
            }
            .max { lhs, rhs in
                lhs.confidence < rhs.confidence
            }
            .map { candidate in
                GlyphCandidate(text: "-", confidence: candidate.confidence, source: candidate.source)
            }
    }

    private func compressedEleventhTailCandidate(
        in group: [GlyphCandidate],
        cluster: InkCluster
    ) -> GlyphCandidate? {
        guard cluster.strokes.count >= 2,
              cluster.bounds.height >= 12,
              cluster.bounds.width <= max(8, cluster.bounds.height * 0.45),
              group.contains(where: { candidate in
                  candidate.text == "1" && candidate.confidence >= 0.42
              }),
              !group.contains(where: { candidate in
                  candidate.confidence >= 0.75
                      && ["7", "9", "°", "ø", "△", "+", "/", "#", "-"].contains(candidate.text)
              }) else {
            return nil
        }

        return GlyphCandidate(text: "11", confidence: 0.84, source: .heuristic)
    }

    private func sixthCandidate(
        in group: [GlyphCandidate],
        cluster: InkCluster,
        rootBounds: InkBounds
    ) -> GlyphCandidate? {
        guard let bestSix = group
            .filter({ candidate in
                candidate.text == "6" && candidate.confidence >= 0.42
            })
            .max(by: { lhs, rhs in lhs.confidence < rhs.confidence }),
            isBodySizedSixthCluster(cluster, rootBounds: rootBounds),
            !hasDominantFlatEvidence(over: bestSix, in: group),
            !group.contains(where: { candidate in
                candidate.confidence >= 0.75
                    && ["-", "m", "7", "9", "°", "ø", "△", "+", "/", "#"].contains(candidate.text)
            }) else {
            return nil
        }

        return GlyphCandidate(
            text: "6",
            confidence: max(bestSix.confidence, 0.82),
            source: bestSix.source
        )
    }

    private func hasDominantFlatEvidence(
        over sixthCandidate: GlyphCandidate,
        in group: [GlyphCandidate]
    ) -> Bool {
        let flatConfidence = group
            .filter { candidate in
                candidate.text == "b"
            }
            .map(\.confidence)
            .max() ?? 0

        return flatConfidence >= 0.82
            && flatConfidence >= sixthCandidate.confidence + 0.16
    }

    private func isBodySizedSixthCluster(
        _ cluster: InkCluster,
        rootBounds: InkBounds
    ) -> Bool {
        guard !isHighAccidentalCluster(cluster, rootBounds: rootBounds) else {
            return false
        }

        let rootWidth = max(rootBounds.width, 1)
        let rootHeight = max(rootBounds.height, 1)
        let heightRatio = cluster.bounds.height / rootHeight
        let widthRatio = cluster.bounds.width / rootWidth
        let overlapsRootBody = cluster.bounds.maxY >= rootBounds.minY + rootHeight * 0.70

        return overlapsRootBody
            && heightRatio >= 0.72
            && widthRatio >= 0.40
    }

    private func isDominantAlteredSuffixContext(
        suffixStartIndex: Int,
        sevenIndex: Int?,
        glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        let suffixGroups = glyphCandidateGroups[suffixStartIndex...]
        let suffixClusters = clusters[suffixStartIndex...]
        guard suffixGroups.count <= 3,
              let firstSuffixCluster = suffixClusters.first,
              !suffixGroups.contains(where: { group in
                  group.contains { candidate in
                      candidate.text == "/" && candidate.confidence >= 0.65
                  }
              }) else {
            return false
        }

        let referenceCluster = sevenIndex.map { clusters[$0] } ?? clusters[max(0, suffixStartIndex - 1)]
        let firstSuffixSitsInLowercaseLane = firstSuffixCluster.bounds.minY >= referenceCluster.bounds.minY + 2
        let hasExplicitSeven = sevenIndex != nil
        let firstSuffixIsLooseAltLoop = suffixGroups.first?.contains { candidate in
            ["b", "9", "°", "G"].contains(candidate.text) && candidate.confidence >= 0.50
                || ["a", "A"].contains(candidate.text) && candidate.confidence >= 0.45
        } == true
        let suffixHasMiddleOrTailLetterEvidence = suffixGroups.dropFirst().contains { group in
            group.contains { candidate in
                (candidate.text == "l" || candidate.text == "t") && candidate.confidence >= 0.45
            }
        }
        let suffixHasTallTail = suffixClusters.contains { cluster in
            cluster.bounds.height >= 13
                && cluster.bounds.width <= 24
        }
        let suffixHasTerminalTShape = suffixGroups.last?.contains { candidate in
            candidate.text == "t" && candidate.confidence >= 0.45
        } == true
            || suffixGroups.last?.contains { candidate in
                candidate.text == "l" && candidate.confidence >= 0.60
            } == true
            || (hasExplicitSeven
                && suffixGroups.count == 2
                && suffixClusters.last.map { cluster in
                    cluster.strokes.count >= 2
                        && cluster.bounds.height >= 14
                        && cluster.bounds.width >= 20
                        && cluster.bounds.width <= 42
                } == true)
            || suffixClusters.last.map { cluster in
                cluster.strokes.count >= 2
                    && cluster.bounds.height >= 14
                    && cluster.bounds.width >= 6
                    && cluster.bounds.width <= 28
            } == true
            || (hasExplicitSeven
                && suffixGroups.count == 1
                && firstSuffixCluster.bounds.height >= 12
                && firstSuffixCluster.bounds.width <= 16)
        let suffixLooksLikeLiteralAlteration = sevenIndex != nil
            && !firstSuffixSitsInLowercaseLane
            && suffixGroups.first?.contains(where: { candidate in
                candidate.text == "b" || candidate.text == "#"
            }) == true
        let firstSuffixIsExplicitSharpAlteration = suffixGroups.first?.contains { candidate in
            candidate.text == "#" && candidate.confidence >= 0.70
        } == true
        let implicitSevenHasEnoughLiteralAltEvidence = hasExplicitSeven
            || (suffixGroups.count >= 3 && suffixHasMiddleOrTailLetterEvidence)

        return firstSuffixSitsInLowercaseLane
            && firstSuffixIsLooseAltLoop
            && suffixHasTallTail
            && suffixHasTerminalTShape
            && implicitSevenHasEnoughLiteralAltEvidence
            && !suffixLooksLikeLiteralAlteration
            && !firstSuffixIsExplicitSharpAlteration
    }

    private func triangleMajorCandidate(
        in group: [GlyphCandidate],
        cluster: InkCluster
    ) -> GlyphCandidate? {
        let hardDominantSevenEvidence = group.contains { candidate in
            candidate.text == "7" && candidate.confidence >= 0.70
        }
        guard !hardDominantSevenEvidence else {
            return nil
        }

        if let triangleCandidate = group
            .filter({ $0.text == "△" && $0.confidence >= 0.60 })
            .max(by: { lhs, rhs in lhs.confidence < rhs.confidence }) {
            return triangleCandidate
        }

        let hardMinorEvidence = group.contains { candidate in
            ["-", "m"].contains(candidate.text) && candidate.confidence >= 0.75
        }
        guard !hardMinorEvidence,
              cluster.strokes.count >= 2,
              cluster.bounds.width >= 22,
              cluster.bounds.height >= 12,
              cluster.bounds.width / max(cluster.bounds.height, 1) >= 1.20 else {
            return nil
        }

        return GlyphCandidate(text: "△", confidence: 0.82, source: .heuristic)
    }

    private func hasSharpElevenTailEvidence(
        groups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        guard groups.count == clusters.count,
              !groups.isEmpty else {
            return false
        }

        let explicitOneCount = groups.reduce(0) { count, group in
            count + (group.contains { candidate in
                candidate.text == "1" && candidate.confidence >= 0.45
            } ? 1 : 0)
        }
        if explicitOneCount >= 2 {
            return true
        }

        guard groups.count == 1,
              let group = groups.first,
              let cluster = clusters.first else {
            return false
        }

        let topCandidateTexts = Set(group.prefix(4).map(\.text))
        return cluster.strokes.count >= 2
            && cluster.bounds.height >= 14
            && cluster.bounds.width >= 10
            && cluster.bounds.width <= 24
            && !topCandidateTexts.contains("9")
            && (topCandidateTexts.contains("1")
                || topCandidateTexts.contains("5")
                || topCandidateTexts.contains("#"))
    }

    private func hasExplicitSharpElevenTailEvidence(
        groups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        guard groups.count == clusters.count,
              groups.count >= 2 else {
            return false
        }

        let hasHardFiveEvidence = groups.contains { group in
            group.contains { candidate in
                candidate.text == "5" && candidate.confidence >= 0.70
            }
        }
        guard !hasHardFiveEvidence else {
            return false
        }

        let explicitOneCount = groups.reduce(0) { count, group in
            count + (group.contains { candidate in
                candidate.text == "1" && candidate.confidence >= 0.90
            } ? 1 : 0)
        }
        return explicitOneCount >= 2
    }

    func contextualizedGlyphCandidateGroups(
        _ glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> [[GlyphCandidate]] {
        guard clusters.count == glyphCandidateGroups.count,
              clusters.count >= 4,
              clusters.count <= 6,
              glyphCandidateGroups.first?.contains(where: { candidate in
                  candidate.confidence >= 0.50 && "ABCDEFG".contains(candidate.text)
              }) == true else {
            return glyphCandidateGroups
        }

        let prefixLength = hasHighAccidentalPrefix(in: glyphCandidateGroups, clusters: clusters) ? 2 : 1
        let suffixLength = clusters.count - prefixLength
        guard suffixLength == 3 || suffixLength == 4 else {
            return glyphCandidateGroups
        }

        var contextualGroups = glyphCandidateGroups
        var didPromoteDominantAlteredContext = false
        if let sevenIndex = dominantAlteredSevenLookalikeIndex(
            in: glyphCandidateGroups,
            clusters: clusters,
            startingAt: prefixLength
        ) {
            contextualGroups[sevenIndex] = contextualGroups[sevenIndex].promotingContextualCandidate(
                "7",
                confidence: 0.82
            )
            didPromoteDominantAlteredContext = true
        }

        let suffixGroups = Array(contextualGroups[prefixLength...])
        let suffixClusters = Array(clusters[prefixLength...])

        if suffixLength == 4,
           canApplyDominantSuspendedContext(
               to: suffixGroups,
               suffixClusters: suffixClusters
           ) {
            contextualGroups[prefixLength + 1] = contextualGroups[prefixLength + 1].promotingContextualCandidate(
                "s",
                confidence: 0.78
            )
            contextualGroups[prefixLength + 2] = contextualGroups[prefixLength + 2].promotingContextualCandidate(
                "u",
                confidence: 0.78
            )
            contextualGroups[prefixLength + 3] = contextualGroups[prefixLength + 3].promotingContextualCandidate(
                "s",
                confidence: 0.78
            )

            return contextualGroups
        }

        guard canApplySuspendedContext(
            to: suffixGroups,
            suffixClusters: suffixClusters,
            rootBounds: clusters[0].bounds
        ) else {
            return didPromoteDominantAlteredContext ? contextualGroups : glyphCandidateGroups
        }

        contextualGroups[prefixLength] = contextualGroups[prefixLength].promotingContextualCandidate(
            "s",
            confidence: 0.78
        )
        contextualGroups[prefixLength + 1] = contextualGroups[prefixLength + 1].promotingContextualCandidate(
            "u",
            confidence: 0.78
        )
        contextualGroups[prefixLength + 2] = contextualGroups[prefixLength + 2].promotingContextualCandidate(
            "s",
            confidence: 0.78
        )
        if suffixLength == 4 {
            contextualGroups[prefixLength + 3] = contextualGroups[prefixLength + 3].promotingContextualCandidate(
                "4",
                confidence: 0.76
            )
        }

        return contextualGroups
    }

    private func dominantAlteredSevenLookalikeIndex(
        in glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster],
        startingAt index: Int
    ) -> Int? {
        guard glyphCandidateGroups.indices.contains(index),
              clusters.indices.contains(index),
              glyphCandidateGroups.indices.contains(index + 2),
              sevenCandidate(in: glyphCandidateGroups[index]) == nil,
              hasAlteredExtensionContext(after: index, in: glyphCandidateGroups) else {
            return nil
        }

        let group = glyphCandidateGroups[index]
        guard candidateConfidence("9", in: group) < 0.85 else {
            return nil
        }

        let lookalikeConfidence = ["B", "D", "E", "F", "+", "5", "6"]
            .map { candidateConfidence($0, in: group) }
            .max() ?? 0
        let hardConflict = group.contains { candidate in
            candidate.confidence >= 0.75
                && ["#", "b", "-", "m", "△", "°", "ø", "/", "s", "u"].contains(candidate.text)
        }
        let bounds = clusters[index].bounds

        guard lookalikeConfidence >= 0.48,
              bounds.width >= 8,
              bounds.height >= 12,
              !hardConflict else {
            return nil
        }

        return index
    }

    private func hasAlteredExtensionContext(
        after index: Int,
        in glyphCandidateGroups: [[GlyphCandidate]]
    ) -> Bool {
        guard index + 2 < glyphCandidateGroups.count else {
            return false
        }

        let suffixRange = glyphCandidateGroups.indices.suffix(from: index + 1)
        guard let accidentalIndex = suffixRange.first(where: { groupIndex in
            candidateConfidence("#", in: glyphCandidateGroups[groupIndex]) >= 0.50
                || candidateConfidence("b", in: glyphCandidateGroups[groupIndex]) >= 0.50
        }) else {
            return false
        }

        let tailGroups = glyphCandidateGroups.suffix(from: accidentalIndex + 1)
        return tailGroups.contains { group in
            candidateConfidence("5", in: group) >= 0.38
                || candidateConfidence("9", in: group) >= 0.38
                || candidateConfidence("1", in: group) >= 0.48
                || candidateConfidence("3", in: group) >= 0.40
        }
    }

    private func canApplyDominantSuspendedContext(
        to suffixGroups: [[GlyphCandidate]],
        suffixClusters: [InkCluster]
    ) -> Bool {
        guard suffixGroups.count == 4,
              suffixClusters.count == 4,
              suffixGroups[0].contains(where: { candidate in
                  candidate.text == "7" && candidate.confidence >= 0.85
              }),
              dominantSuspendedSuffixSitsBelowSeven(suffixClusters) else {
            return false
        }

        let suspendedGroups = Array(suffixGroups.dropFirst())
        let suspendedClusters = Array(suffixClusters.dropFirst())

        return hasSuspendedSuffixSequenceEvidence(
            in: suspendedGroups,
            clusters: suspendedClusters
        )
            && !hasHardNonSuspendedDescriptorEvidence(in: suspendedGroups)
    }

    private func dominantSuspendedSuffixSitsBelowSeven(_ suffixClusters: [InkCluster]) -> Bool {
        guard suffixClusters.count == 4 else {
            return false
        }

        let sevenBounds = suffixClusters[0].bounds
        let suffixFloor = sevenBounds.minY + max(8, sevenBounds.height * 0.60)
        return suffixClusters.dropFirst().allSatisfy { suffixCluster in
            suffixCluster.bounds.minY >= suffixFloor
        }
    }

    private func hasHighAccidentalPrefix(
        in glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        guard glyphCandidateGroups.indices.contains(1),
              clusters.indices.contains(1) else {
            return false
        }

        let hasStrongFlat = glyphCandidateGroups[1].contains { candidate in
            candidate.confidence >= 0.60 && candidate.text == "b"
        }
        let hasStrongSharp = glyphCandidateGroups[1].contains { candidate in
            candidate.confidence >= 0.70 && candidate.text == "#"
        }
        let rootBounds = clusters[0].bounds
        let highModifierBottom = rootBounds.maxY - rootBounds.height * 0.32

        return hasStrongSharp || hasStrongFlat && clusters[1].bounds.maxY <= highModifierBottom
    }

    private func isHighAccidentalCluster(
        _ cluster: InkCluster,
        rootBounds: InkBounds
    ) -> Bool {
        let highModifierBottom = rootBounds.maxY - rootBounds.height * 0.32
        return cluster.bounds.maxY <= highModifierBottom
    }

    private func canApplySuspendedContext(
        to suffixGroups: [[GlyphCandidate]],
        suffixClusters: [InkCluster],
        rootBounds: InkBounds
    ) -> Bool {
        guard (suffixGroups.count == 3 || suffixGroups.count == 4),
              suffixGroups.count == suffixClusters.count else {
            return false
        }

        let firstSuffixTopCandidate = suffixGroups[0].max { lhs, rhs in
            lhs.confidence < rhs.confidence
        }
        let firstSuffixLooksSuspended = firstSuffixTopCandidate
            .map { ["s", "u"].contains($0.text) } == true
        let firstSuffixHasStrongExplicitQuality = !firstSuffixLooksSuspended
            && suffixGroups[0].contains { candidate in
                candidate.confidence >= 0.85
                    && ["-", "m", "7", "°", "ø", "△", "+"].contains(candidate.text)
            }
        let firstSuffixIsExplicitSlash = firstSuffixTopCandidate?.text == "/"
            && (firstSuffixTopCandidate?.confidence ?? 0) >= 0.65
        let firstSuffixHasTallSlashSeparator = suffixGroups[0].contains { candidate in
            candidate.text == "/" && candidate.confidence >= 0.65
        } && suffixClusters[0].bounds.height >= rootBounds.height * 0.95

        let firstThreeSuffixGroups = Array(suffixGroups.prefix(3))
        let fourSuffixHasStrongNonSuspendedDescriptor = suffixGroups.count == 4
            && hasHardNonSuspendedDescriptorEvidence(in: firstThreeSuffixGroups)
        let firstThreeSuffixClusters = Array(suffixClusters.prefix(3))
        let hasSuspendedSequenceEvidence = hasSuspendedSuffixSequenceEvidence(
            in: firstThreeSuffixGroups,
            clusters: firstThreeSuffixClusters
        )
        let finalFourthHasHardConflict = suffixGroups.count == 4
            && suffixGroups[3].contains { candidate in
                candidate.confidence >= 0.78
                    && ["-", "m", "°", "ø", "△", "+"].contains(candidate.text)
            }

        return !firstSuffixHasStrongExplicitQuality
            && hasSuspendedSequenceEvidence
            && (!firstSuffixIsExplicitSlash || firstSuffixLooksSuspended)
            && (!firstSuffixHasTallSlashSeparator || firstSuffixLooksSuspended)
            && !fourSuffixHasStrongNonSuspendedDescriptor
            && !finalFourthHasHardConflict
    }

    private func hasHardNonSuspendedDescriptorEvidence(in suffixGroups: [[GlyphCandidate]]) -> Bool {
        suffixGroups.contains { group in
            if group.max(by: { lhs, rhs in lhs.confidence < rhs.confidence })
                .map({ ["s", "u"].contains($0.text) }) == true {
                return false
            }

            return group.contains { candidate in
                candidate.confidence >= 0.70
                    && ["#", "°", "ø", "△", "+"].contains(candidate.text)
            }
        }
    }

    private func hasSuspendedSuffixSequenceEvidence(
        in suffixGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        guard suffixGroups.count == 3,
              clusters.count == 3 else {
            return false
        }

        return isSuspendedSContext(group: suffixGroups[0], cluster: clusters[0])
            && isSuspendedUContext(group: suffixGroups[1], cluster: clusters[1])
            && isSuspendedSContext(group: suffixGroups[2], cluster: clusters[2])
    }

    private func suspendedSuffixKind(
        in suffixGroups: [[GlyphCandidate]],
        clusters: [InkCluster],
        rootBounds: InkBounds
    ) -> SuspendedSuffixKind? {
        guard suffixGroups.count == clusters.count,
              suffixSitsInLowercaseLane(clusters: clusters, rootBounds: rootBounds) else {
            return nil
        }

        if firstSuffixHasHardMinorQuality(in: suffixGroups) {
            return nil
        }

        if suffixGroups.count == 3,
           isSuspendedSContext(group: suffixGroups[0], cluster: clusters[0]),
           isCompactSuspendedMiddleContext(group: suffixGroups[1], cluster: clusters[1]),
           isCompactSuspendedFourthTailContext(
               group: suffixGroups[2],
               cluster: clusters[2],
               previousClusters: Array(clusters.prefix(2))
           ) {
            return .suspendedFourth
        }

        if suffixGroups.count >= 4,
           hasSuspendedSuffixSequenceEvidence(
               in: Array(suffixGroups.prefix(3)),
               clusters: Array(clusters.prefix(3))
           ),
           isSuspendedFourthContext(group: suffixGroups[3], cluster: clusters[3]) {
            return .suspendedFourth
        }

        if suffixGroups.count >= 3,
           hasSuspendedSuffixSequenceEvidence(
               in: Array(suffixGroups.prefix(3)),
               clusters: Array(clusters.prefix(3))
           ) {
            return .suspended
        }

        if suffixGroups.count == 2,
           isSuspendedSContext(group: suffixGroups[0], cluster: clusters[0]),
           isCompactSuspendedMiddleContext(group: suffixGroups[1], cluster: clusters[1]) {
            return .suspended
        }

        return nil
    }

    private func firstSuffixHasHardMinorQuality(in suffixGroups: [[GlyphCandidate]]) -> Bool {
        suffixGroups.first?.contains { candidate in
            ["-", "m"].contains(candidate.text) && candidate.confidence >= 0.72
        } == true
    }

    private func suffixSitsInLowercaseLane(
        clusters: [InkCluster],
        rootBounds: InkBounds
    ) -> Bool {
        guard let firstSuffixCluster = clusters.first else {
            return false
        }

        let minimumLowerOffset = max(3, rootBounds.height * 0.10)
        return firstSuffixCluster.bounds.minY >= rootBounds.minY + minimumLowerOffset
    }

    private func isSuspendedSContext(
        group: [GlyphCandidate],
        cluster: InkCluster
    ) -> Bool {
        if group.containsSuspendedCandidate("s", minimumConfidence: 0.45) {
            return true
        }

        return cluster.strokes.count == 1
            && cluster.bounds.width >= 4
            && cluster.bounds.width <= 18
            && cluster.bounds.height >= 12
            && cluster.bounds.height <= 32
            && cluster.bounds.width * cluster.bounds.height >= 55
    }

    private func isSuspendedUContext(
        group: [GlyphCandidate],
        cluster: InkCluster
    ) -> Bool {
        if group.containsSuspendedCandidate("u", minimumConfidence: 0.45) {
            return true
        }

        return cluster.strokes.count == 1
            && cluster.bounds.width >= 7
            && cluster.bounds.width <= 24
            && cluster.bounds.height >= 7
            && cluster.bounds.height <= 24
            && cluster.bounds.width * cluster.bounds.height >= 60
    }

    private func isCompactSuspendedMiddleContext(
        group: [GlyphCandidate],
        cluster: InkCluster
    ) -> Bool {
        if isSuspendedUContext(group: group, cluster: cluster) {
            return true
        }

        let hasHardDescriptor = group.contains { candidate in
            candidate.confidence >= 0.78
                && ["#", "°", "ø", "△", "+"].contains(candidate.text)
        }

        return !hasHardDescriptor
            && cluster.strokes.count >= 2
            && cluster.bounds.width >= 18
            && cluster.bounds.width <= 42
            && cluster.bounds.height >= 10
            && cluster.bounds.height <= 30
            && cluster.bounds.width * cluster.bounds.height >= 220
    }

    private func isSuspendedFourthContext(
        group: [GlyphCandidate],
        cluster: InkCluster
    ) -> Bool {
        group.contains { candidate in
            candidate.text == "4" && candidate.confidence >= 0.35
        }
            || cluster.bounds.width <= 18
            && cluster.bounds.height >= 14
            && cluster.bounds.height / max(cluster.bounds.width, 1) >= 1.25
    }

    private func isCompactSuspendedFourthTailContext(
        group: [GlyphCandidate],
        cluster: InkCluster,
        previousClusters: [InkCluster]
    ) -> Bool {
        guard isSuspendedFourthContext(group: group, cluster: cluster),
              !previousClusters.isEmpty else {
            return false
        }

        let previousMinY = previousClusters
            .map(\.bounds.minY)
            .min() ?? cluster.bounds.minY

        return cluster.bounds.minY <= previousMinY - 3
    }
}

private extension Array where Element == GlyphCandidate {
    func containsSuspendedCandidate(
        _ text: String,
        minimumConfidence: Double
    ) -> Bool {
        contains { candidate in
            candidate.text == text && candidate.confidence >= minimumConfidence
        }
    }

    func promotingContextualCandidate(_ text: String, confidence: Double) -> [GlyphCandidate] {
        var candidates = self
        if let index = candidates.firstIndex(where: { $0.text == text }) {
            candidates[index].confidence = Swift.max(candidates[index].confidence, confidence)
            return candidates
        }

        candidates.append(GlyphCandidate(text: text, confidence: confidence, source: .composer))
        return candidates
    }
}
