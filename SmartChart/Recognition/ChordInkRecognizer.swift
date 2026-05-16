import Foundation

protocol ChordInkRecognizing {
    func recognize(strokes: [InkStroke]) -> ChordInkRecognitionResult
}

struct ChordInkRecognizer: ChordInkRecognizing {
    var clusterer: StrokeClusterer
    var glyphRecognizer: GestureTemplateRecognizer
    var candidateComposer: ChordInkCandidateComposer
    var templates: [GestureTemplate]
    var maxGlyphCandidatesPerCluster: Int
    var minimumAcceptedCandidateConfidence: Double

    init(
        clusterer: StrokeClusterer = StrokeClusterer(),
        glyphRecognizer: GestureTemplateRecognizer = GestureTemplateRecognizer(),
        candidateComposer: ChordInkCandidateComposer = ChordInkCandidateComposer(),
        templates: [GestureTemplate] = ChordGlyphTemplateLibrary.initialTemplates,
        maxGlyphCandidatesPerCluster: Int = 8,
        minimumAcceptedCandidateConfidence: Double = 3.70
    ) {
        self.clusterer = clusterer
        self.glyphRecognizer = glyphRecognizer
        self.candidateComposer = candidateComposer
        self.templates = templates
        self.maxGlyphCandidatesPerCluster = maxGlyphCandidatesPerCluster
        self.minimumAcceptedCandidateConfidence = minimumAcceptedCandidateConfidence
    }

    func recognize(strokes: [InkStroke]) -> ChordInkRecognitionResult {
        let clusters = clusterer.cluster(strokes)
        let glyphCandidateGroups = clusters.map { cluster in
            glyphRecognizer.rankedCandidates(
                for: cluster,
                templates: templates,
                limit: maxGlyphCandidatesPerCluster
            )
        }
        let contextualGlyphCandidateGroups = glyphCandidateGroupsWithSuspendedContext(
            glyphCandidateGroups,
            clusters: clusters
        )
        let chordCandidates = recognitionCandidates(
            from: contextualGlyphCandidateGroups,
            clusters: clusters
        )
        let rawCandidates = chordCandidates.map(\.text)
        let minimumScoredCandidateConfidence = minimumAcceptedCandidateConfidence
            - ChordInkRecognitionPolicy.closeRaceConfidenceGap
        let candidateScores = chordCandidates.prefix(8)
            .filter { $0.confidence >= minimumScoredCandidateConfidence }
            .map { candidate in
                let match = ChordRecognitionCompendium.match(candidate.text)
                return ChordInkCandidateScore(
                    text: candidate.text,
                    displayText: match?.displayText,
                    confidence: candidate.confidence
                )
            }
        let acceptedCandidate = chordCandidates.lazy.compactMap { candidate -> (ChordRecognitionMatch, Double)? in
            guard let match = ChordRecognitionCompendium.match(candidate.text),
                  candidate.confidence >= minimumAcceptedCandidateConfidence else {
                return nil
            }

            return (match, candidate.confidence)
        }.first
        let match = acceptedCandidate?.0
        let acceptedConfidence = acceptedCandidate?.1 ?? 0

        return ChordInkRecognitionResult(
            rawCandidates: rawCandidates,
            glyphCandidates: contextualGlyphCandidateGroups,
            match: match,
            confidence: acceptedConfidence,
            candidateScores: candidateScores
        )
    }

    private func recognitionCandidates(
        from glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> [ChordInkCandidate] {
        let composedCandidates = candidateComposer.compose(glyphCandidates: glyphCandidateGroups)
        var bestCandidatesByText = Dictionary(
            uniqueKeysWithValues: composedCandidates.map { ($0.text, $0) }
        )

        for semanticCandidate in [
            dominantAlteredCandidate(from: glyphCandidateGroups, clusters: clusters),
            majorSharpElevenCandidate(from: glyphCandidateGroups, clusters: clusters),
            minorEleventhCandidate(from: glyphCandidateGroups, clusters: clusters),
            majorSixthCandidate(from: glyphCandidateGroups, clusters: clusters),
            suspendedSuffixCandidate(from: glyphCandidateGroups, clusters: clusters)
        ].compactMap({ $0 }) {
            if let currentBest = bestCandidatesByText[semanticCandidate.text],
               currentBest.confidence >= semanticCandidate.confidence {
                continue
            }

            bestCandidatesByText[semanticCandidate.text] = semanticCandidate
        }

        return Array(bestCandidatesByText.values).sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.text < rhs.text
        }
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
        guard hasSharpElevenTailEvidence(groups: tailGroups, clusters: tailClusters) else {
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

    private func glyphCandidateGroupsWithSuspendedContext(
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
        let suffixGroups = Array(glyphCandidateGroups[prefixLength...])
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
            return glyphCandidateGroups
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
