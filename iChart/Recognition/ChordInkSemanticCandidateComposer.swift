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
        let roleContext = ChordInkTheoryRoleContext(
            glyphCandidateGroups: glyphCandidateGroups,
            clusters: clusters
        )

        let semanticStart = Date()
        let semanticCandidates = semanticCandidateComposer.candidates(
            from: glyphCandidateGroups,
            clusters: clusters,
            roleContext: roleContext
        )
        for semanticCandidate in semanticCandidates {
            if let currentBest = bestCandidatesByText[semanticCandidate.text],
               currentBest.confidence >= semanticCandidate.confidence {
                continue
            }

            bestCandidatesByText[semanticCandidate.text] = semanticCandidate
        }
        let semanticMilliseconds = Self.elapsedMilliseconds(since: semanticStart)

        let grammarPolicy = ChordInkCandidateGrammarPolicy()
        let evidencePolicy = ChordInkCandidateEvidencePolicy()
        let candidates = Array(bestCandidatesByText.values).filter { candidate in
            grammarPolicy.allows(
                candidate,
                candidateColumns: glyphCandidateGroups,
                clusters: clusters
            )
            && evidencePolicy.allows(
                candidate,
                candidateColumns: glyphCandidateGroups,
                clusters: clusters,
                roleContext: roleContext
            )
        }.sorted { lhs, rhs in
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
        clusters: [InkCluster],
        roleContext: ChordInkTheoryRoleContext? = nil
    ) -> [ChordInkCandidate] {
        let roleContext = roleContext ?? ChordInkTheoryRoleContext(
            glyphCandidateGroups: glyphCandidateGroups,
            clusters: clusters
        )
        let bareAlteredColorToneCandidates = bareAlteredColorToneCandidates(
            from: glyphCandidateGroups,
            clusters: clusters
        )
        let singleCandidates = [
            chordRepeatCandidate(roleContext: roleContext),
            diminishedQualityCandidate(from: glyphCandidateGroups, clusters: clusters),
            plainNinthAlteredExtensionCandidate(from: glyphCandidateGroups, clusters: clusters),
            majorAlteredExtensionCandidate(from: glyphCandidateGroups, clusters: clusters),
            dominantAlteredCandidate(from: glyphCandidateGroups, clusters: clusters),
            dominantSharpElevenCandidate(from: glyphCandidateGroups, clusters: clusters),
            majorSharpElevenCandidate(from: glyphCandidateGroups, clusters: clusters),
            minorEleventhCandidate(from: glyphCandidateGroups, clusters: clusters),
            majorSixthCandidate(from: glyphCandidateGroups, clusters: clusters)
        ].compactMap { $0 }

        return bareAlteredColorToneCandidates + singleCandidates + suspendedSuffixCandidates(
            from: glyphCandidateGroups,
            clusters: clusters
        )
    }

    private func chordRepeatCandidate(
        roleContext: ChordInkTheoryRoleContext
    ) -> ChordInkCandidate? {
        guard let glyphCandidates = roleContext.chordRepeatGlyphCandidates else {
            return nil
        }

        return ChordInkCandidate(
            text: ChordSymbol.chordRepeatDisplayText,
            confidence: 4.8,
            glyphCandidates: glyphCandidates
        )
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
        case compactSuspended
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

    private struct BareAlterationNumberCandidate {
        var number: String
        var glyphs: [GlyphCandidate]
        var evidenceConfidence: Double
    }

    /// Composes explicitly parenthesized color tones written without a leading
    /// extension, such as Ab(#5), B#(b9), Db(b3), and Gb(b13). Parenthesis ink
    /// is removed by the clusterer, so this path requires a complete accidental
    /// plus number tail and never infers a missing alteration glyph.
    private func bareAlteredColorToneCandidates(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> [ChordInkCandidate] {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 3,
              let rootCandidate = bareAlterationRootCandidate(in: glyphCandidateGroups[0]) else {
            return []
        }

        var glyphs = [rootCandidate]
        var symbolText = rootCandidate.text
        var index = 1

        // A high accidental immediately after the root is only claimed as the
        // root accidental when another written accidental remains for the
        // alteration. This keeps C(#5) distinct from C#(b9).
        let hasLaterAlterationAccidental = glyphCandidateGroups.indices
            .dropFirst(2)
            .contains { groupIndex in
                accidentalCandidate(
                    in: glyphCandidateGroups[groupIndex],
                    minimumConfidence: 0.42
                ) != nil
            }
        if hasLaterAlterationAccidental,
           glyphCandidateGroups.indices.contains(index),
           let rootAccidental = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.65
           ),
           isHighAccidentalCluster(clusters[index], rootBounds: clusters[0].bounds) {
            glyphs.append(rootAccidental)
            symbolText.append(rootAccidental.text)
            index += 1
        }

        guard glyphCandidateGroups.indices.contains(index),
              let alterationAccidental = accidentalCandidate(
                  in: glyphCandidateGroups[index],
                  minimumConfidence: 0.42
              ),
              index + 1 < glyphCandidateGroups.count,
              clusters[index].hasRecognitionHint(.parenthesizedAlteration),
              clusters[(index + 1)...].contains(where: {
                  $0.hasRecognitionHint(.parenthesizedAlteration)
              }) else {
            return []
        }

        glyphs.append(alterationAccidental)
        let numberCandidates = bareAlterationNumberCandidates(
            in: glyphCandidateGroups,
            clusters: clusters,
            startingAt: index + 1
        )

        return numberCandidates.compactMap { numberCandidate in
            let candidateText = symbolText
                + "(\(alterationAccidental.text)\(numberCandidate.number))"
            guard ChordRecognitionCompendium.match(candidateText) != nil else {
                return nil
            }

            return ChordInkCandidate(
                text: candidateText,
                confidence: 4.78 + numberCandidate.evidenceConfidence * 0.62,
                glyphCandidates: glyphs + numberCandidate.glyphs
            )
        }
    }

    private func bareAlterationRootCandidate(
        in group: [GlyphCandidate]
    ) -> GlyphCandidate? {
        let strongestConfidence = group.map(\.confidence).max() ?? 0
        return group
            .filter { candidate in
                candidate.confidence >= 0.60
                    && candidate.confidence + 0.08 >= strongestConfidence
                    && "ABCDEFG".contains(candidate.text)
            }
            .max { lhs, rhs in
                lhs.confidence < rhs.confidence
            }
    }

    private func bareAlterationNumberCandidates(
        in groups: [[GlyphCandidate]],
        clusters: [InkCluster],
        startingAt index: Int
    ) -> [BareAlterationNumberCandidate] {
        let remainingCount = groups.count - index
        guard remainingCount == 1 || remainingCount == 2 else {
            return []
        }

        if remainingCount == 2 {
            guard let oneCandidate = bestCandidate(
                in: groups[index],
                text: "1",
                minimumConfidence: 0.48
            ) else {
                return []
            }

            var candidates: [BareAlterationNumberCandidate] = []
            if let threeCandidate = bestCandidate(
                in: groups[index + 1],
                text: "3",
                minimumConfidence: 0.40
            ),
               isExplicitBareAlterationThree(
                   groups[index + 1],
                   cluster: clusters[index + 1]
               ) {
                candidates.append(
                    BareAlterationNumberCandidate(
                        number: "13",
                        glyphs: [oneCandidate, threeCandidate],
                        evidenceConfidence: min(oneCandidate.confidence, max(threeCandidate.confidence, 0.94))
                    )
                )
            }

            if let secondOneCandidate = bestCandidate(
                in: groups[index + 1],
                text: "1",
                minimumConfidence: 0.48
            ) {
                candidates.append(
                    BareAlterationNumberCandidate(
                        number: "11",
                        glyphs: [oneCandidate, secondOneCandidate],
                        evidenceConfidence: min(oneCandidate.confidence, secondOneCandidate.confidence)
                    )
                )
            }

            return candidates.sorted { lhs, rhs in
                lhs.evidenceConfidence > rhs.evidenceConfidence
            }
        }

        let group = groups[index]
        let cluster = clusters[index]
        let strongLoopAndTailNine = isStrongLoopAndTailNine(cluster)
        let explicitThree = isExplicitBareAlterationThree(group, cluster: cluster)
        var candidates: [BareAlterationNumberCandidate] = []

        if let nineCandidate = bestCandidate(
            in: group,
            text: "9",
            minimumConfidence: 0.38
        ),
           strongLoopAndTailNine || nineCandidate.confidence >= 0.75 {
            candidates.append(
                BareAlterationNumberCandidate(
                    number: "9",
                    glyphs: [nineCandidate],
                    evidenceConfidence: strongLoopAndTailNine
                        ? max(nineCandidate.confidence, 0.97)
                        : nineCandidate.confidence
                )
            )
        }

        if let threeCandidate = bestCandidate(
            in: group,
            text: "3",
            minimumConfidence: 0.40
        ),
           explicitThree {
            candidates.append(
                BareAlterationNumberCandidate(
                    number: "3",
                    glyphs: [threeCandidate],
                    evidenceConfidence: max(threeCandidate.confidence, 0.94)
                )
            )
        }

        if let fiveCandidate = bestCandidate(
            in: group,
            text: "5",
            minimumConfidence: 0.48
        ),
           !explicitThree || fiveCandidate.confidence >= 0.80 {
            candidates.append(
                BareAlterationNumberCandidate(
                    number: "5",
                    glyphs: [fiveCandidate],
                    evidenceConfidence: fiveCandidate.confidence
                )
            )
        }

        return candidates.sorted { lhs, rhs in
            if lhs.evidenceConfidence != rhs.evidenceConfidence {
                return lhs.evidenceConfidence > rhs.evidenceConfidence
            }
            return lhs.number < rhs.number
        }
    }

    private func isExplicitBareAlterationThree(
        _ group: [GlyphCandidate],
        cluster: InkCluster
    ) -> Bool {
        let threeConfidence = candidateConfidence("3", in: group)
        let fiveConfidence = candidateConfidence("5", in: group)
        guard threeConfidence >= 0.40,
              cluster.strokes.count == 1,
              let stroke = cluster.strokes.first else {
            return false
        }

        if stroke.isThreeGlyphCandidate {
            return true
        }

        // Device-written 3s can finish with a slightly wider return than the
        // generic glyph gate permits. In the explicit alteration-number slot,
        // require the two-lobe geometry plus a real recognition advantage over
        // 5 before accepting that wider form.
        let width = max(stroke.bounds.width, 1)
        let height = max(stroke.bounds.height, 1)
        let aspectRatio = width / height
        let isWideTwoLobeThree = stroke.points.count >= 10
            && stroke.bounds.width >= 8
            && stroke.bounds.height >= 12
            && stroke.bounds.height <= 30
            && aspectRatio >= 0.42
            && aspectRatio <= 1.45
            && stroke.straightness >= 0.18
            && stroke.straightness <= 0.70
            && stroke.angleDegrees >= 35
            && stroke.angleDegrees <= 135
            && (stroke.horizontalDirectionChangeCount >= 1 || stroke.hasEarlyTopHorizontalRun)

        return isWideTwoLobeThree
            && threeConfidence >= fiveConfidence + 0.04
    }

    private func isStrongLoopAndTailNine(_ cluster: InkCluster) -> Bool {
        guard cluster.strokes.count == 1,
              let stroke = cluster.strokes.first,
              stroke.isNineGlyphCandidate,
              !stroke.hasEarlyTopHorizontalRun,
              let firstPoint = stroke.points.first,
              let lastPoint = stroke.points.last else {
            return false
        }

        let width = max(stroke.bounds.width, 1)
        let height = max(stroke.bounds.height, 1)
        let startX = (firstPoint.x - stroke.bounds.minX) / width
        let startY = (firstPoint.y - stroke.bounds.minY) / height
        let endX = (lastPoint.x - stroke.bounds.minX) / width
        let endY = (lastPoint.y - stroke.bounds.minY) / height
        let loopPoints = stroke.points.prefix(max(4, stroke.points.count * 2 / 3))
        let loopWidth = (loopPoints.map(\.x).max() ?? stroke.bounds.minX)
            - (loopPoints.map(\.x).min() ?? stroke.bounds.minX)
        let loopHeight = (loopPoints.map(\.y).max() ?? stroke.bounds.minY)
            - (loopPoints.map(\.y).min() ?? stroke.bounds.minY)

        return startX >= 0.58
            && startY <= 0.25
            && endX >= 0.58
            && endY >= 0.78
            && loopWidth >= width * 0.72
            && loopHeight >= height * 0.42
    }

    private func suspendedSuffixCandidates(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> [ChordInkCandidate] {
        guard glyphCandidateGroups.count == clusters.count,
              clusters.count >= 3,
              !plausibleSuspendedRootCandidates(in: glyphCandidateGroups[0]).isEmpty else {
            return []
        }

        var index = 1
        var accidentalGlyph: GlyphCandidate?

        if glyphCandidateGroups.indices.contains(index),
           let candidate = accidentalCandidate(
               in: glyphCandidateGroups[index],
               minimumConfidence: 0.65
           ),
           isHighAccidentalCluster(clusters[index], rootBounds: clusters[0].bounds) {
            accidentalGlyph = candidate
            index += 1
        }

        var hasDominantSeven = false
        var dominantSevenCandidate: GlyphCandidate?
        if glyphCandidateGroups.indices.contains(index),
           let sevenCandidate = sevenCandidate(in: glyphCandidateGroups[index]) {
            hasDominantSeven = true
            dominantSevenCandidate = sevenCandidate
            index += 1
        }

        guard index < glyphCandidateGroups.count else {
            return []
        }

        let suffixGroups = Array(glyphCandidateGroups[index...])
        let suffixClusters = Array(clusters[index...])
        guard let suffixKind = suspendedSuffixKind(
            in: suffixGroups,
            clusters: suffixClusters,
            rootBounds: clusters[0].bounds
        ) else {
            return []
        }

        return plausibleSuspendedRootCandidates(in: glyphCandidateGroups[0]).map { rootCandidate in
            var glyphs = [rootCandidate]
            var symbolText = rootCandidate.text

            if let accidentalGlyph {
                glyphs.append(accidentalGlyph)
                symbolText.append(accidentalGlyph.text)
            }

            if let dominantSevenCandidate {
                glyphs.append(dominantSevenCandidate)
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
            case .compactSuspended:
                symbolText.append("sus")
                glyphs.append(contentsOf: [
                    GlyphCandidate(text: "s", confidence: 0.72, source: .composer),
                    GlyphCandidate(text: "u", confidence: 0.72, source: .composer),
                    GlyphCandidate(text: "s", confidence: 0.72, source: .composer)
                ])
                return ChordInkCandidate(
                    text: symbolText,
                    confidence: 3.90,
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
    }

    private func plausibleSuspendedRootCandidates(in group: [GlyphCandidate]) -> [GlyphCandidate] {
        let rootCandidates = group.filter { candidate in
            candidate.confidence >= 0.50 && "ABCDEFG".contains(candidate.text)
        }
        guard let strongestConfidence = rootCandidates.map(\.confidence).max() else {
            return []
        }

        let floor = max(0.50, strongestConfidence - 0.08)
        return rootCandidates
            .filter { $0.confidence >= floor }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }

                return lhs.text < rhs.text
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

    private func isHighAccidentalCluster(
        _ cluster: InkCluster,
        rootBounds: InkBounds
    ) -> Bool {
        let highModifierBottom = rootBounds.maxY - rootBounds.height * 0.32
        return cluster.bounds.maxY <= highModifierBottom
    }

    private func hasSuspendedSuffixSequenceEvidence(
        in suffixGroups: [[GlyphCandidate]],
        clusters: [InkCluster],
        rootBounds: InkBounds
    ) -> Bool {
        guard suffixGroups.count == 3,
              clusters.count == 3 else {
            return false
        }

        return isSuspendedSContext(group: suffixGroups[0], cluster: clusters[0])
            && isSuspendedUContext(group: suffixGroups[1], cluster: clusters[1], rootBounds: rootBounds)
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
           isCompactSuspendedMiddleContext(group: suffixGroups[1], cluster: clusters[1], rootBounds: rootBounds),
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
               clusters: Array(clusters.prefix(3)),
               rootBounds: rootBounds
           ),
           isSuspendedFourthContext(group: suffixGroups[3], cluster: clusters[3]) {
            return .suspendedFourth
        }

        if suffixGroups.count >= 3,
           hasSuspendedSuffixSequenceEvidence(
               in: Array(suffixGroups.prefix(3)),
               clusters: Array(clusters.prefix(3)),
               rootBounds: rootBounds
           ) {
            return .suspended
        }

        if suffixGroups.count >= 3,
           isSuspendedSContext(group: suffixGroups[0], cluster: clusters[0]),
           isCompactSuspendedMiddleContext(group: suffixGroups[1], cluster: clusters[1], rootBounds: rootBounds),
           isCompactSuspendedTailContext(group: suffixGroups[2], cluster: clusters[2]),
           !hasHardNonSuspendedDescriptorEvidence(in: Array(suffixGroups.prefix(3))) {
            return .compactSuspended
        }

        if suffixGroups.count == 2,
           isSuspendedSContext(group: suffixGroups[0], cluster: clusters[0]),
           isCompactSuspendedMiddleContext(group: suffixGroups[1], cluster: clusters[1], rootBounds: rootBounds) {
            return .suspended
        }

        if suffixGroups.count == 2,
           isSuspendedSContext(group: suffixGroups[0], cluster: clusters[0]),
           isCompactSuspendedTailContext(group: suffixGroups[1], cluster: clusters[1]),
           !hasHardNonSuspendedDescriptorEvidence(in: suffixGroups) {
            return .compactSuspended
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
        cluster: InkCluster,
        rootBounds: InkBounds
    ) -> Bool {
        if group.containsSuspendedCandidate("u", minimumConfidence: 0.45) {
            return true
        }

        // This fallback is used only within suspended-suffix context and after
        // the lowercase-lane/minor-quality guards. Measure against the owned
        // root, so enlarging the same `sus` does not lose its middle cup. Do not
        // rescale the ink or its clock, or change standalone glyph confidence.
        let scale = ChordInkRecognitionScaleNormalizer.normalizedHeight / max(rootBounds.height, 1)
        let width = cluster.bounds.width * scale
        let height = cluster.bounds.height * scale
        return cluster.strokes.count == 1
            && width >= 7
            && width <= 24
            && height >= 7
            && height <= 24
            && width * height >= 60
    }

    private func isCompactSuspendedMiddleContext(
        group: [GlyphCandidate],
        cluster: InkCluster,
        rootBounds: InkBounds
    ) -> Bool {
        if isSuspendedUContext(group: group, cluster: cluster, rootBounds: rootBounds) {
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

    private func isCompactSuspendedTailContext(
        group: [GlyphCandidate],
        cluster: InkCluster
    ) -> Bool {
        if group.containsSuspendedCandidate("s", minimumConfidence: 0.45)
            || group.containsSuspendedCandidate("u", minimumConfidence: 0.45) {
            return true
        }

        let hasHardDescriptor = group.contains { candidate in
            candidate.confidence >= 0.78
                && ["#", "°", "ø", "△", "+"].contains(candidate.text)
        }

        return !hasHardDescriptor
            && cluster.strokes.count == 1
            && cluster.bounds.width >= 4
            && cluster.bounds.width <= 14
            && cluster.bounds.height >= 10
            && cluster.bounds.height <= 32
            && cluster.bounds.width * cluster.bounds.height >= 45
    }

    private func hasHardNonSuspendedDescriptorEvidence(
        in suffixGroups: [[GlyphCandidate]]
    ) -> Bool {
        suffixGroups.contains { group in
            if let topCandidate = group.max(by: { lhs, rhs in
                lhs.confidence < rhs.confidence
            }),
               ["s", "u"].contains(topCandidate.text) {
                return false
            }

            return group.contains { candidate in
                candidate.confidence >= 0.70
                    && ["#", "°", "ø", "△", "+"].contains(candidate.text)
            }
        }
    }

    private func isSuspendedFourthContext(
        group: [GlyphCandidate],
        cluster: InkCluster
    ) -> Bool {
        if group.contains(where: { candidate in
            candidate.text == "2"
                && candidate.source != .composer
                && candidate.confidence >= 0.55
        }) {
            return false
        }

        return group.contains { candidate in
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

}
