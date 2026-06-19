struct ChordInkSemanticGlyphContextualizer {
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
            contextualGroups[sevenIndex] = promotingContextualCandidate(
                "7",
                confidence: 0.82,
                in: contextualGroups[sevenIndex]
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
            contextualGroups[prefixLength + 1] = promotingContextualCandidate(
                "s",
                confidence: 0.78,
                in: contextualGroups[prefixLength + 1]
            )
            contextualGroups[prefixLength + 2] = promotingContextualCandidate(
                "u",
                confidence: 0.78,
                in: contextualGroups[prefixLength + 2]
            )
            contextualGroups[prefixLength + 3] = promotingContextualCandidate(
                "s",
                confidence: 0.78,
                in: contextualGroups[prefixLength + 3]
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

        contextualGroups[prefixLength] = promotingContextualCandidate(
            "s",
            confidence: 0.78,
            in: contextualGroups[prefixLength]
        )
        contextualGroups[prefixLength + 1] = promotingContextualCandidate(
            "u",
            confidence: 0.78,
            in: contextualGroups[prefixLength + 1]
        )
        contextualGroups[prefixLength + 2] = promotingContextualCandidate(
            "s",
            confidence: 0.78,
            in: contextualGroups[prefixLength + 2]
        )
        if suffixLength == 4 {
            contextualGroups[prefixLength + 3] = promotingContextualCandidate(
                "4",
                confidence: 0.76,
                in: contextualGroups[prefixLength + 3]
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

    private func isSuspendedSContext(
        group: [GlyphCandidate],
        cluster: InkCluster
    ) -> Bool {
        if containsSuspendedCandidate("s", minimumConfidence: 0.45, in: group) {
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
        if containsSuspendedCandidate("u", minimumConfidence: 0.45, in: group) {
            return true
        }

        return cluster.strokes.count == 1
            && cluster.bounds.width >= 7
            && cluster.bounds.width <= 24
            && cluster.bounds.height >= 7
            && cluster.bounds.height <= 24
            && cluster.bounds.width * cluster.bounds.height >= 60
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

    private func candidateConfidence(_ text: String, in group: [GlyphCandidate]) -> Double {
        group
            .filter { $0.text == text }
            .map(\.confidence)
            .max() ?? 0
    }

    private func containsSuspendedCandidate(
        _ text: String,
        minimumConfidence: Double,
        in group: [GlyphCandidate]
    ) -> Bool {
        group.contains { candidate in
            candidate.text == text && candidate.confidence >= minimumConfidence
        }
    }

    private func promotingContextualCandidate(
        _ text: String,
        confidence: Double,
        in group: [GlyphCandidate]
    ) -> [GlyphCandidate] {
        var candidates = group
        if let index = candidates.firstIndex(where: { $0.text == text }) {
            candidates[index].confidence = Swift.max(candidates[index].confidence, confidence)
            return candidates
        }

        candidates.append(GlyphCandidate(text: text, confidence: confidence, source: .composer))
        return candidates
    }
}
