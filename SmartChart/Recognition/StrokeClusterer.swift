import Foundation

struct StrokeClustererConfiguration: Hashable {
    var maxTimeGap: TimeInterval
    var maxHorizontalGapRatio: Double
    var maxVerticalOverlapMissRatio: Double
    var smallModifierSizeRatio: Double

    static let chordSymbols = StrokeClustererConfiguration(
        maxTimeGap: 0.35,
        maxHorizontalGapRatio: 0.18,
        maxVerticalOverlapMissRatio: 0.18,
        smallModifierSizeRatio: 0.20
    )
}
struct StrokeClusterer {
    var configuration: StrokeClustererConfiguration

    init(configuration: StrokeClustererConfiguration = .chordSymbols) {
        self.configuration = configuration
    }

    func cluster(_ strokes: [InkStroke]) -> [InkCluster] {
        var workingClusters = strokes.enumerated().map { index, stroke in
            MutableInkCluster(strokes: [stroke], originalIndexes: [index])
        }

        var didMerge = true
        while didMerge {
            didMerge = false
            mergeLoop: for lhsIndex in workingClusters.indices {
                for rhsIndex in workingClusters.indices where rhsIndex > lhsIndex {
                    guard shouldMerge(workingClusters[lhsIndex], workingClusters[rhsIndex]) else {
                        continue
                    }

                    let mergedCluster = workingClusters[lhsIndex].merged(with: workingClusters[rhsIndex])
                    workingClusters[lhsIndex] = mergedCluster
                    workingClusters.remove(at: rhsIndex)
                    didMerge = true
                    break mergeLoop
                }
            }
        }

        let splitClusters = splitEmbeddedSharpAccidentals(in: workingClusters)
            .flatMap { cluster in
                splitAttachedRightSideSharpStem(in: cluster) ?? [cluster]
            }
        let normalizedClusters = mergeRootConstructionFragments(
            in: mergeSharpConstructionFragments(in: splitClusters)
        )
            .flatMap { cluster in
                splitAdjacentOneGlyphs(in: cluster) ?? [cluster]
            }
            .flatMap { cluster in
                splitAdjacentOneThreeGlyphs(in: cluster) ?? [cluster]
            }
            .flatMap { cluster in
                splitMinorSeventhSuffix(in: cluster) ?? [cluster]
            }
        let suffixNormalizedClusters = mergeDominantFlatNineSuffixFragments(in: normalizedClusters)
        let wrapperNormalizedClusters = removeDominantAlterationParenthesisWrappers(in: suffixNormalizedClusters)
        let alteredFlatNormalizedClusters = mergeDominantAlterationFlatFragments(in: wrapperNormalizedClusters)
        let semanticClusters = mergeDominantAlteredFiveSuffixFragments(in: alteredFlatNormalizedClusters)
        let finalClusters = semanticClusters.flatMap { cluster in
            splitMinorSeventhSuffix(in: cluster) ?? [cluster]
        }
        let suspendedSuffixClusters = splitSuspendedSuffixFragments(in: finalClusters)
        let slashSeparatedClusters = splitSlashBassSeparatorFragments(in: suspendedSuffixClusters)

        return slashSeparatedClusters
            .sorted { lhs, rhs in
                if lhs.bounds.minX != rhs.bounds.minX {
                    return lhs.bounds.minX < rhs.bounds.minX
                }

                if lhs.bounds.minY != rhs.bounds.minY {
                    return lhs.bounds.minY < rhs.bounds.minY
                }

                return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
            }
            .map { cluster in
                InkCluster(strokes: cluster.strokes)
            }
    }

    private func splitSlashBassSeparatorFragments(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        let orderedClusters = clusters.sorted { lhs, rhs in
            if lhs.bounds.minX != rhs.bounds.minX {
                return lhs.bounds.minX < rhs.bounds.minX
            }

            return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
        }

        return orderedClusters.enumerated().flatMap { index, cluster in
            let previousCluster = index > orderedClusters.startIndex ? orderedClusters[index - 1] : nil
            let nextCluster = orderedClusters.indices.contains(index + 1) ? orderedClusters[index + 1] : nil
            return splitSlashBassSeparatorFragment(
                in: cluster,
                previousCluster: previousCluster,
                nextCluster: nextCluster
            ) ?? [cluster]
        }
    }

    private func splitSlashBassSeparatorFragment(
        in cluster: MutableInkCluster,
        previousCluster: MutableInkCluster?,
        nextCluster: MutableInkCluster?
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count >= 2 else {
            return nil
        }

        let orderedPairs = zip(cluster.originalIndexes, cluster.strokes)
            .sorted { lhs, rhs in
                if lhs.1.bounds.minX != rhs.1.bounds.minX {
                    return lhs.1.bounds.minX < rhs.1.bounds.minX
                }

                return lhs.0 < rhs.0
            }

        for slashIndex in orderedPairs.indices.dropFirst() {
            let slashStroke = orderedPairs[slashIndex].1
            guard slashStroke.isLooseSlashBassSeparatorCandidate else {
                continue
            }

            let leftPairs = Array(orderedPairs[..<slashIndex])
            let rightPairs = Array(orderedPairs.dropFirst(slashIndex + 1))
            let leftCluster = MutableInkCluster(
                strokes: leftPairs.map(\.1),
                originalIndexes: leftPairs.map(\.0)
            )
            let rightCluster = rightPairs.isEmpty
                ? nil
                : MutableInkCluster(
                    strokes: rightPairs.map(\.1),
                    originalIndexes: rightPairs.map(\.0)
                )
            let hasBassTarget = rightCluster?.isSlashBassFollowingGlyphCandidate == true
                || nextCluster?.isSlashBassFollowingGlyphCandidate == true
            let hasPrefixWithPreviousRoot = previousCluster
                .map { previousCluster in
                    previousCluster.isSlashBassLeadingRootContextCandidate
                        && (leftCluster.isAccidentalModifierCandidate
                            || leftCluster.isSharpGlyphCandidate
                            || leftCluster.isSharpConstructionPart)
                } ?? false

            guard hasBassTarget,
                  leftCluster.isSlashBassPrefixCandidate || hasPrefixWithPreviousRoot else {
                continue
            }

            var splitClusters = [
                leftCluster,
                MutableInkCluster(strokes: [slashStroke], originalIndexes: [orderedPairs[slashIndex].0])
            ]

            if let rightCluster {
                splitClusters.append(rightCluster)
            }

            return splitClusters
        }

        return nil
    }

    private func splitSuspendedSuffixFragments(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        let orderedClusters = clusters.sorted { lhs, rhs in
            if lhs.bounds.minX != rhs.bounds.minX {
                return lhs.bounds.minX < rhs.bounds.minX
            }

            return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
        }

        return orderedClusters.enumerated().flatMap { index, cluster in
            let previousCluster = index > orderedClusters.startIndex ? orderedClusters[index - 1] : nil
            let previousPreviousCluster = index >= 2 ? orderedClusters[index - 2] : nil
            let nextCluster = orderedClusters.indices.contains(index + 1) ? orderedClusters[index + 1] : nil

            if let splitClusters = splitSuspendedPair(
                in: cluster,
                previousCluster: previousCluster,
                nextCluster: nextCluster
            ) {
                return splitClusters
            }

            if let splitClusters = splitSuspendedFourthTail(
                in: cluster,
                previousCluster: previousCluster,
                previousPreviousCluster: previousPreviousCluster,
                hasDominantSevenInkBefore: hasDominantSevenInk(before: index, in: orderedClusters)
            ) {
                return splitClusters
            }

            if let splitClusters = splitSuspendedSFromSharp(
                in: cluster,
                hasDominantSevenBefore: hasDominantSevenCandidate(before: index, in: orderedClusters),
                nextCluster: nextCluster
            ) {
                return splitClusters
            }

            if let splitClusters = splitMinorMFromSharp(
                in: cluster,
                previousCluster: previousCluster,
                nextCluster: nextCluster
            ) {
                return splitClusters
            }

            return [cluster]
        }
    }

    private func splitSuspendedPair(
        in cluster: MutableInkCluster,
        previousCluster: MutableInkCluster?,
        nextCluster: MutableInkCluster?
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count == 2 else {
            return nil
        }

        let singleStrokeClusters = zip(cluster.originalIndexes, cluster.strokes)
            .map { index, stroke in
                MutableInkCluster(strokes: [stroke], originalIndexes: [index])
            }
            .sorted { lhs, rhs in
                if lhs.bounds.minX != rhs.bounds.minX {
                    return lhs.bounds.minX < rhs.bounds.minX
                }

                return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
            }

        guard singleStrokeClusters.count == 2,
              shouldKeepSeparateAsSuspendedSuffixLetters(singleStrokeClusters[0], singleStrokeClusters[1]) else {
            return nil
        }

        let hasRootOrAccidentalBefore = previousCluster?.isPlainSuspendedPrefixCandidate == true
        let hasSuspendedSAfter = nextCluster?.isSuspendedSLikeCandidate == true
        let hasSuspendedSBefore = previousCluster?.isSuspendedSLikeCandidate == true

        if singleStrokeClusters[0].isSuspendedSLikeCandidate,
           singleStrokeClusters[1].isSuspendedULikeCandidate,
           hasRootOrAccidentalBefore || hasSuspendedSAfter {
            return singleStrokeClusters
        }

        if singleStrokeClusters[0].isSuspendedULikeCandidate,
           singleStrokeClusters[1].isSuspendedSLikeCandidate,
           hasSuspendedSBefore {
            return singleStrokeClusters
        }

        return nil
    }

    private func splitSuspendedFourthTail(
        in cluster: MutableInkCluster,
        previousCluster: MutableInkCluster?,
        previousPreviousCluster: MutableInkCluster?,
        hasDominantSevenInkBefore: Bool
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count == 2,
              !hasDominantSevenInkBefore,
              previousCluster?.isSuspendedULikeContextCandidate == true,
              previousPreviousCluster?.isSuspendedSLikeContextCandidate == true else {
            return nil
        }

        let singleStrokeClusters = zip(cluster.originalIndexes, cluster.strokes)
            .map { index, stroke in
                MutableInkCluster(strokes: [stroke], originalIndexes: [index])
            }
            .sorted { lhs, rhs in
                if lhs.bounds.minX != rhs.bounds.minX {
                    return lhs.bounds.minX < rhs.bounds.minX
                }

                return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
            }

        guard singleStrokeClusters.count == 2 else {
            return nil
        }

        let leadingS = singleStrokeClusters[0]
        let trailingFour = singleStrokeClusters[1]
        let horizontalGap = leadingS.bounds.horizontalGap(to: trailingFour.bounds)
        let verticalMiss = leadingS.bounds.verticalMiss(to: trailingFour.bounds)

        guard leadingS.isSuspendedSLikeContextCandidate,
              trailingFour.isSuspendedFourthLikeCandidate,
              horizontalGap <= 18,
              verticalMiss <= 18 else {
            return nil
        }

        return singleStrokeClusters
    }

    private func splitSuspendedSFromSharp(
        in cluster: MutableInkCluster,
        hasDominantSevenBefore: Bool,
        nextCluster: MutableInkCluster?
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count >= 5,
              nextCluster?.isSuspendedULikeCandidate == true,
              !hasDominantSevenBefore else {
            return nil
        }

        let orderedPairs = zip(cluster.originalIndexes, cluster.strokes)
            .sorted { lhs, rhs in lhs.0 < rhs.0 }
        let orderedIndexes = orderedPairs.map(\.0)
        let orderedStrokes = orderedPairs.map(\.1)

        let splitIndex = orderedStrokes.count - 1
        let left = MutableInkCluster(
            strokes: Array(orderedStrokes[..<splitIndex]),
            originalIndexes: Array(orderedIndexes[..<splitIndex])
        )
        let right = MutableInkCluster(
            strokes: [orderedStrokes[splitIndex]],
            originalIndexes: [orderedIndexes[splitIndex]]
        )

        guard left.isSharpGlyphCandidate,
              right.isSuspendedSLikeCandidate,
              left.bounds.horizontalGap(to: right.bounds) <= 16,
              left.bounds.verticalMiss(to: right.bounds) <= 16 else {
            return nil
        }

        return [left, right]
    }

    private func splitMinorMFromSharp(
        in cluster: MutableInkCluster,
        previousCluster: MutableInkCluster?,
        nextCluster: MutableInkCluster?
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count >= 5,
              previousCluster?.isRootBodyCandidate == true,
              previousCluster?.isDominantSevenInkAnchor != true,
              nextCluster?.isMinorSixExtensionContextCandidate == true else {
            return nil
        }

        let orderedPairs = zip(cluster.originalIndexes, cluster.strokes)
            .sorted { lhs, rhs in lhs.0 < rhs.0 }
        let orderedIndexes = orderedPairs.map(\.0)
        let orderedStrokes = orderedPairs.map(\.1)
        let splitIndex = orderedStrokes.count - 1
        let left = MutableInkCluster(
            strokes: Array(orderedStrokes[..<splitIndex]),
            originalIndexes: Array(orderedIndexes[..<splitIndex])
        )
        let right = MutableInkCluster(
            strokes: [orderedStrokes[splitIndex]],
            originalIndexes: [orderedIndexes[splitIndex]]
        )

        guard left.isSharpGlyphCandidate,
              right.isMinorSuffixCandidate,
              left.bounds.horizontalGap(to: right.bounds) <= 10,
              left.bounds.verticalMiss(to: right.bounds) <= 14 else {
            return nil
        }

        return [left, right]
    }

    private func mergeSharpConstructionFragments(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        var workingClusters = clusters
        var didMerge = true

        while didMerge {
            didMerge = false
            mergeLoop: for lhsIndex in workingClusters.indices {
                for rhsIndex in workingClusters.indices where rhsIndex > lhsIndex {
                    let lhs = workingClusters[lhsIndex]
                    let rhs = workingClusters[rhsIndex]
                    guard lhs.canMergeAsSharpFragment,
                          rhs.canMergeAsSharpFragment,
                          !lhs.isSlashLikeSeparator,
                          !rhs.isSlashLikeSeparator,
                          !shouldKeepSeparateAsMinorSuffixAndExtension(lhs, rhs),
                          shouldMergeAsSharpConstruction(lhs, rhs) else {
                        continue
                    }

                    workingClusters[lhsIndex] = lhs.merged(with: rhs)
                    workingClusters.remove(at: rhsIndex)
                    didMerge = true
                    break mergeLoop
                }
            }
        }

        return workingClusters
    }

    private func mergeRootConstructionFragments(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        var workingClusters = clusters
        var didMerge = true

        while didMerge {
            didMerge = false
            mergeLoop: for lhsIndex in workingClusters.indices {
                for rhsIndex in workingClusters.indices where rhsIndex > lhsIndex {
                    let lhs = workingClusters[lhsIndex]
                    let rhs = workingClusters[rhsIndex]
                    guard !lhs.isSlashLikeSeparator,
                          !rhs.isSlashLikeSeparator else {
                        continue
                    }

                    let hasVerticalRootConstruction = lhs.hasRootConstructionVerticalStem
                        || rhs.hasRootConstructionVerticalStem
                    let hasBarRootConstruction = (lhs.hasRootConstructionBar || rhs.hasRootConstructionBar)
                        && (lhs.hasRootConstructionBody || rhs.hasRootConstructionBody)
                    guard (hasVerticalRootConstruction
                            || hasBarRootConstruction
                            || (!lhs.isQualityOrExtensionGlyphCandidate
                                && !rhs.isQualityOrExtensionGlyphCandidate)),
                          shouldMergeAsRootConstruction(lhs, rhs) else {
                        continue
                    }

                    workingClusters[lhsIndex] = lhs.merged(with: rhs)
                    workingClusters.remove(at: rhsIndex)
                    didMerge = true
                    break mergeLoop
                }
            }
        }

        return workingClusters
    }

    private func mergeDominantFlatNineSuffixFragments(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        var workingClusters = clusters.sorted { lhs, rhs in
            if lhs.bounds.minX != rhs.bounds.minX {
                return lhs.bounds.minX < rhs.bounds.minX
            }

            return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
        }

        var index = 1
        while index + 2 < workingClusters.count {
            let seven = workingClusters[index - 1]
            if index + 3 < workingClusters.count {
                let flatStem = workingClusters[index]
                let flatBody = workingClusters[index + 1]
                let nineLoop = workingClusters[index + 2]
                let nineTail = workingClusters[index + 3]

                if shouldMergeAsDominantFlatNineSuffix(
                    seven: seven,
                    flatStem: flatStem,
                    flatBody: flatBody,
                    nineLoop: nineLoop,
                    nineTail: nineTail
                ) {
                    workingClusters.replaceSubrange(
                        index...(index + 3),
                        with: [
                            flatStem.merged(with: flatBody),
                            nineLoop.merged(with: nineTail)
                        ]
                    )
                    index += 2
                    continue
                }
            }

            let flat = workingClusters[index]
            let nineLoop = workingClusters[index + 1]
            let nineTail = workingClusters[index + 2]

            if shouldMergeAsDominantFlatNineTailAfterMergedFlat(
                seven: seven,
                flat: flat,
                nineLoop: nineLoop,
                nineTail: nineTail
            ) {
                workingClusters.replaceSubrange(
                    (index + 1)...(index + 2),
                    with: [nineLoop.merged(with: nineTail)]
                )
                index += 2
                continue
            }

            index += 1
        }

        return workingClusters
    }

    private func shouldMergeAsDominantFlatNineSuffix(
        seven: MutableInkCluster,
        flatStem: MutableInkCluster,
        flatBody: MutableInkCluster,
        nineLoop: MutableInkCluster,
        nineTail: MutableInkCluster
    ) -> Bool {
        if flatStem.isSuspendedSLikeContextCandidate,
           flatBody.isSuspendedULikeContextCandidate,
           nineLoop.isSuspendedSLikeContextCandidate,
           hasLowerDominantSuspendedSuffix(after: seven, suffixClusters: [flatStem, flatBody, nineLoop]) {
            return false
        }

        guard seven.isDominantSevenSuffixAnchor,
              flatStem.isDominantFlatNineStemFragment,
              flatBody.isDominantFlatNineCurvedFragment,
              nineLoop.isDominantFlatNineCurvedFragment,
              nineTail.isDominantFlatNineTailFragment else {
            return false
        }

        let flatBounds = InkBounds.enclosing([flatStem.bounds, flatBody.bounds])
        let nineBounds = InkBounds.enclosing([nineLoop.bounds, nineTail.bounds])
        let suffixBounds = InkBounds.enclosing([flatBounds, nineBounds])
        let sevenToFlatGap = seven.bounds.horizontalGap(to: flatStem.bounds)
        let flatStemToBodyGap = flatStem.bounds.horizontalGap(to: flatBody.bounds)
        let flatToNineGap = flatBody.bounds.horizontalGap(to: nineLoop.bounds)
        let nineLoopToTailGap = nineLoop.bounds.horizontalGap(to: nineTail.bounds)
        let flatVerticalOverlap = flatStem.bounds.verticalOverlap(with: flatBody.bounds)
        let nineVerticalOverlap = nineLoop.bounds.verticalOverlap(with: nineTail.bounds)
        let flatReferenceHeight = max(min(flatStem.bounds.height, flatBody.bounds.height), 1)
        let nineReferenceHeight = max(min(nineLoop.bounds.height, nineTail.bounds.height), 1)

        return sevenToFlatGap <= 36
            && flatStemToBodyGap <= 18
            && flatToNineGap <= 20
            && nineLoopToTailGap <= 22
            && flatBounds.width <= 32
            && flatBounds.height <= 42
            && nineBounds.width <= 38
            && nineBounds.height <= 44
            && suffixBounds.height <= 48
            && flatVerticalOverlap >= flatReferenceHeight * 0.18
            && nineVerticalOverlap >= nineReferenceHeight * 0.18
            && flatBody.bounds.recognitionMidX > flatStem.bounds.recognitionMidX
            && nineTail.bounds.recognitionMidX > nineLoop.bounds.recognitionMidX
    }

    private func shouldMergeAsDominantFlatNineTailAfterMergedFlat(
        seven: MutableInkCluster,
        flat: MutableInkCluster,
        nineLoop: MutableInkCluster,
        nineTail: MutableInkCluster
    ) -> Bool {
        if flat.isSuspendedSLikeContextCandidate,
           nineLoop.isSuspendedULikeContextCandidate,
           nineTail.isSuspendedSLikeContextCandidate,
           hasLowerDominantSuspendedSuffix(after: seven, suffixClusters: [flat, nineLoop, nineTail]) {
            return false
        }

        guard seven.isDominantSevenSuffixAnchor,
              flat.isDominantFlatNineMergedFlatFragment,
              nineLoop.isDominantFlatNineCurvedFragment,
              nineTail.isDominantFlatNineTailFragment else {
            return false
        }

        let nineBounds = InkBounds.enclosing([nineLoop.bounds, nineTail.bounds])
        let sevenToFlatGap = seven.bounds.horizontalGap(to: flat.bounds)
        let flatToNineGap = flat.bounds.horizontalGap(to: nineLoop.bounds)
        let nineLoopToTailGap = nineLoop.bounds.horizontalGap(to: nineTail.bounds)
        let nineVerticalOverlap = nineLoop.bounds.verticalOverlap(with: nineTail.bounds)
        let nineReferenceHeight = max(min(nineLoop.bounds.height, nineTail.bounds.height), 1)

        return sevenToFlatGap <= 36
            && flatToNineGap <= 24
            && nineLoopToTailGap <= 22
            && nineBounds.width <= 38
            && nineBounds.height <= 44
            && nineVerticalOverlap >= nineReferenceHeight * 0.18
            && nineTail.bounds.recognitionMidX > nineLoop.bounds.recognitionMidX
    }

    private func mergeDominantAlterationFlatFragments(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        var workingClusters = clusters.sorted { lhs, rhs in
            if lhs.bounds.minX != rhs.bounds.minX {
                return lhs.bounds.minX < rhs.bounds.minX
            }

            return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
        }

        var index = 1
        while index + 2 < workingClusters.count {
            let seven = workingClusters[index - 1]
            let flatStem = workingClusters[index]
            let flatBody = workingClusters[index + 1]
            let nextSuffixFragment = workingClusters[index + 2]

            if shouldMergeAsDominantAlterationFlat(
                seven: seven,
                flatStem: flatStem,
                flatBody: flatBody,
                nextSuffixFragment: nextSuffixFragment
            ) {
                workingClusters.replaceSubrange(
                    index...(index + 1),
                    with: [flatStem.merged(with: flatBody)]
                )
                index += 1
                continue
            }

            index += 1
        }

        return workingClusters
    }

    private func shouldMergeAsDominantAlterationFlat(
        seven: MutableInkCluster,
        flatStem: MutableInkCluster,
        flatBody: MutableInkCluster,
        nextSuffixFragment: MutableInkCluster
    ) -> Bool {
        if flatStem.isSuspendedSLikeContextCandidate,
           flatBody.isSuspendedULikeContextCandidate,
           nextSuffixFragment.isSuspendedSLikeContextCandidate,
           hasLowerDominantSuspendedSuffix(after: seven, suffixClusters: [flatStem, flatBody, nextSuffixFragment]) {
            return false
        }

        guard seven.isDominantSevenSuffixAnchor,
              flatStem.isDominantFlatNineStemFragment,
              flatBody.isDominantFlatNineCurvedFragment,
              nextSuffixFragment.isLooseAlteredFiveFragmentCandidate else {
            return false
        }

        let flatBounds = InkBounds.enclosing([flatStem.bounds, flatBody.bounds])
        let sevenToFlatGap = seven.bounds.horizontalGap(to: flatStem.bounds)
        let flatStemToBodyGap = flatStem.bounds.horizontalGap(to: flatBody.bounds)
        let flatToSuffixGap = flatBody.bounds.horizontalGap(to: nextSuffixFragment.bounds)
        let flatVerticalOverlap = flatStem.bounds.verticalOverlap(with: flatBody.bounds)
        let flatReferenceHeight = max(min(flatStem.bounds.height, flatBody.bounds.height), 1)

        return sevenToFlatGap <= 42
            && flatStemToBodyGap <= 18
            && flatToSuffixGap <= 28
            && flatBounds.width <= 34
            && flatBounds.height <= 44
            && flatVerticalOverlap >= flatReferenceHeight * 0.18
            && flatBody.bounds.recognitionMidX > flatStem.bounds.recognitionMidX
    }

    private func mergeDominantAlteredFiveSuffixFragments(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        var workingClusters = clusters.sorted { lhs, rhs in
            if lhs.bounds.minX != rhs.bounds.minX {
                return lhs.bounds.minX < rhs.bounds.minX
            }

            return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
        }

        var index = 1
        while index + 2 < workingClusters.count {
            let seven = workingClusters[index - 1]
            let alteration = workingClusters[index]

            if index + 3 < workingClusters.count {
                let fragments = Array(workingClusters[(index + 1)...(index + 3)])
                if shouldMergeAsDominantAlteredFiveSuffix(
                    seven: seven,
                    alteration: alteration,
                    fragments: fragments
                ) {
                    workingClusters.replaceSubrange(
                        (index + 1)...(index + 3),
                        with: [fragments.dropFirst().reduce(fragments[0]) { $0.merged(with: $1) }]
                    )
                    index += 2
                    continue
                }
            }

            let fragments = Array(workingClusters[(index + 1)...(index + 2)])
            if shouldMergeAsDominantAlteredFiveSuffix(
                seven: seven,
                alteration: alteration,
                fragments: fragments
            ) {
                workingClusters.replaceSubrange(
                    (index + 1)...(index + 2),
                    with: [fragments[0].merged(with: fragments[1])]
                )
                index += 2
                continue
            }

            index += 1
        }

        return workingClusters
    }

    private func shouldMergeAsDominantAlteredFiveSuffix(
        seven: MutableInkCluster,
        alteration: MutableInkCluster,
        fragments: [MutableInkCluster]
    ) -> Bool {
        if fragments.count >= 2,
           alteration.isSuspendedSLikeContextCandidate,
           fragments[0].isSuspendedULikeContextCandidate,
           fragments[1].isSuspendedSLikeContextCandidate,
           hasLowerDominantSuspendedSuffix(after: seven, suffixClusters: [alteration, fragments[0], fragments[1]]) {
            return false
        }

        guard seven.isDominantSevenSuffixAnchor,
              alteration.isWrittenAlterationAccidentalCandidate,
              fragments.count >= 2,
              fragments.count <= 3,
              fragments.allSatisfy(\.isLooseAlteredFiveFragmentCandidate) else {
            return false
        }

        if fragments.count >= 2,
           fragments[0].isStandaloneOneGlyphCandidate,
           fragments[1].isStandaloneThreeGlyphCandidate {
            return false
        }

        if fragments.count >= 2,
           fragments[0].isStandaloneOneGlyphCandidate,
           fragments[1].isStandaloneOneGlyphCandidate {
            return false
        }

        let fiveBounds = InkBounds.enclosing(fragments.map(\.bounds))
        let alterationGap = alteration.bounds.horizontalGap(to: fragments[0].bounds)
        let suffixBounds = InkBounds.enclosing([alteration.bounds, fiveBounds])
        let fragmentGaps = zip(fragments, fragments.dropFirst()).map { lhs, rhs in
            lhs.bounds.horizontalGap(to: rhs.bounds)
        }

        return alterationGap <= 28
            && fragmentGaps.allSatisfy { $0 <= 18 }
            && fiveBounds.width <= 42
            && fiveBounds.height <= 38
            && suffixBounds.height <= 46
            && fragments.last?.bounds.recognitionMidX ?? 0 > fragments[0].bounds.recognitionMidX
    }

    private func splitAdjacentOneGlyphs(
        in cluster: MutableInkCluster
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count == 2,
              cluster.strokes.allSatisfy(\.isOneGlyphCandidate) else {
            return nil
        }

        let orderedPairs = zip(cluster.originalIndexes, cluster.strokes)
            .sorted { lhs, rhs in
                if lhs.1.bounds.minX != rhs.1.bounds.minX {
                    return lhs.1.bounds.minX < rhs.1.bounds.minX
                }

                return lhs.0 < rhs.0
            }

        return orderedPairs.map { index, stroke in
            MutableInkCluster(strokes: [stroke], originalIndexes: [index])
        }
    }

    private func splitAdjacentOneThreeGlyphs(
        in cluster: MutableInkCluster
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count == 2 else {
            return nil
        }

        let singleStrokeClusters = zip(cluster.originalIndexes, cluster.strokes)
            .map { index, stroke in
                MutableInkCluster(strokes: [stroke], originalIndexes: [index])
            }
            .sorted { lhs, rhs in
                if lhs.bounds.minX != rhs.bounds.minX {
                    return lhs.bounds.minX < rhs.bounds.minX
                }

                return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
            }

        guard singleStrokeClusters.count == 2,
              singleStrokeClusters[0].isStandaloneOneGlyphCandidate,
              singleStrokeClusters[1].isStandaloneThreeGlyphCandidate,
              shouldKeepSeparateAsAdjacentOneThreeGlyphs(singleStrokeClusters[0], singleStrokeClusters[1]) else {
            return nil
        }

        return singleStrokeClusters
    }

    private func splitMinorSeventhSuffix(
        in cluster: MutableInkCluster
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count == 2 else {
            return nil
        }

        let singleStrokeClusters = zip(cluster.originalIndexes, cluster.strokes)
            .map { index, stroke in
                MutableInkCluster(strokes: [stroke], originalIndexes: [index])
            }
            .sorted { lhs, rhs in
                if lhs.bounds.minX != rhs.bounds.minX {
                    return lhs.bounds.minX < rhs.bounds.minX
                }

                return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
            }

        guard singleStrokeClusters.count == 2,
              shouldKeepSeparateAsMinorSuffixAndExtension(singleStrokeClusters[0], singleStrokeClusters[1]) else {
            return nil
        }

        if shouldKeepMergedAsRootBarBodyConstruction(singleStrokeClusters[0], singleStrokeClusters[1]) {
            return nil
        }

        return singleStrokeClusters
    }

    private func shouldKeepMergedAsRootBarBodyConstruction(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let ordered = lhs.hasRootConstructionBar
            ? (bar: lhs, body: rhs)
            : (bar: rhs, body: lhs)

        guard ordered.bar.hasRootConstructionBar,
              !ordered.bar.hasRootConstructionBody,
              ordered.body.hasRootConstructionBody else {
            return false
        }

        let horizontalOverlap = ordered.bar.bounds.horizontalOverlap(with: ordered.body.bounds)
        let narrowerWidth = max(min(ordered.bar.bounds.width, ordered.body.bounds.width), 1)
        let centerDistance = abs(ordered.bar.bounds.recognitionMidX - ordered.body.bounds.recognitionMidX)
        let bodyWidth = max(ordered.body.bounds.width, 1)

        return horizontalOverlap >= narrowerWidth * 0.70
            && centerDistance <= bodyWidth * 0.35
            && ordered.bar.bounds.verticalOverlap(with: ordered.body.bounds) > 0
    }

    private func splitAttachedRightSideSharpStem(
        in cluster: MutableInkCluster
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count == 2 else {
            return nil
        }

        let singleStrokeClusters = zip(cluster.originalIndexes, cluster.strokes)
            .map { index, stroke in
                MutableInkCluster(strokes: [stroke], originalIndexes: [index])
            }
        guard let root = singleStrokeClusters.first(where: \.isRootBodyCandidate),
              let modifier = singleStrokeClusters.first(where: { $0 != root && $0.isSharpConstructionPart }),
              root.bounds.recognitionArea >= modifier.bounds.recognitionArea * 12 else {
            return nil
        }

        let rootWidth = max(root.bounds.width, 1)
        let rootHeight = max(root.bounds.height, 1)
        let startsAtRightEdge = modifier.bounds.minX >= root.bounds.maxX - max(2, rootWidth * 0.10)
        let closeEnoughToBelongToRoot = root.bounds.horizontalGap(to: modifier.bounds) <= max(8, rootHeight * 0.45)
            && root.bounds.verticalMiss(to: modifier.bounds) <= max(8, rootHeight * 0.55)

        guard startsAtRightEdge, closeEnoughToBelongToRoot else {
            return nil
        }

        return [root, modifier]
    }

    private func splitEmbeddedSharpAccidentals(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        clusters.flatMap { cluster in
            splitEmbeddedSharpAccidental(in: cluster) ?? [cluster]
        }
    }

    private func splitEmbeddedSharpAccidental(
        in cluster: MutableInkCluster
    ) -> [MutableInkCluster]? {
        guard cluster.strokes.count >= 5 else {
            return nil
        }

        let orderedPairs = zip(cluster.originalIndexes, cluster.strokes)
            .sorted { lhs, rhs in lhs.0 < rhs.0 }
        let orderedIndexes = orderedPairs.map(\.0)
        let orderedStrokes = orderedPairs.map(\.1)

        for splitIndex in stride(from: orderedStrokes.count - 4, through: 1, by: -1) {
            let left = MutableInkCluster(
                strokes: Array(orderedStrokes[..<splitIndex]),
                originalIndexes: Array(orderedIndexes[..<splitIndex])
            )
            let right = MutableInkCluster(
                strokes: Array(orderedStrokes[splitIndex...]),
                originalIndexes: Array(orderedIndexes[splitIndex...])
            )

            guard right.isSharpGlyphCandidate,
                  left.isRootBodyCandidate,
                  !left.isSharpGlyphCandidate,
                  right.bounds.recognitionMidX > left.bounds.recognitionMidX,
                  left.bounds.horizontalGap(to: right.bounds) <= max(12, left.bounds.width * 0.60) else {
                continue
            }

            return [left, right]
        }

        return nil
    }

    private func shouldMerge(_ lhs: MutableInkCluster, _ rhs: MutableInkCluster) -> Bool {
        guard timingAllowsMerge(lhs, rhs) else {
            return false
        }

        if shouldMergeAsHalfDiminishedConstruction(lhs, rhs) {
            return true
        }

        guard !shouldKeepSeparateAsMinorSuffixAndExtension(lhs, rhs) else {
            return false
        }

        if shouldMergeAsPlusConstruction(lhs, rhs) {
            return true
        }

        guard !lhs.isSlashLikeSeparator,
              !rhs.isSlashLikeSeparator else {
            return false
        }

        guard !shouldKeepSeparateAsRightSideModifier(lhs, rhs) else {
            return false
        }

        guard !shouldKeepSeparateAsAdjacentOneGlyphs(lhs, rhs) else {
            return false
        }

        guard !shouldKeepSeparateAsAdjacentOneThreeGlyphs(lhs, rhs) else {
            return false
        }

        guard !shouldKeepSeparateAsOverlappingFlatModifier(lhs, rhs) else {
            return false
        }

        guard !shouldKeepSeparateAsParenthesizedAlterationWrapper(lhs, rhs) else {
            return false
        }

        if shouldMergeAsSharpConstruction(lhs, rhs) {
            return true
        }

        guard !shouldKeepSeparateAsSequentialGlyphs(lhs, rhs) else {
            return false
        }

        if shouldMergeAsRootConstruction(lhs, rhs) {
            return true
        }

        let horizontalGap = lhs.bounds.horizontalGap(to: rhs.bounds)
        let verticalMiss = lhs.bounds.verticalMiss(to: rhs.bounds)
        let referenceHeight = max(lhs.bounds.height, rhs.bounds.height, 1)
        let referenceWidth = max(lhs.bounds.width, rhs.bounds.width, 1)
        let smallModifierTightening = hasSmallModifier(lhs, rhs) ? 0.75 : 1.0

        let maxHorizontalGap = max(
            2,
            referenceHeight * configuration.maxHorizontalGapRatio * smallModifierTightening
        )
        let maxVerticalMiss = max(
            2,
            referenceWidth * configuration.maxVerticalOverlapMissRatio
        )
        let overlappingGlyphStrokeVerticalMiss = horizontalGap == 0 ? 4.0 : maxVerticalMiss

        return horizontalGap <= maxHorizontalGap
            && verticalMiss <= overlappingGlyphStrokeVerticalMiss
    }

    private func shouldMergeAsRootConstruction(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let combinedStrokeCount = lhs.strokes.count + rhs.strokes.count
        guard combinedStrokeCount <= 4,
              lhs.bounds.horizontalGap(to: rhs.bounds) <= 4 else {
            return false
        }

        let ordered = lhs.bounds.minX <= rhs.bounds.minX ? (left: lhs, right: rhs) : (left: rhs, right: lhs)
        if ordered.left.hasRootConstructionBody,
           ordered.right.isFlatGlyphCandidate,
           ordered.right.bounds.recognitionMidX > ordered.left.bounds.recognitionMidX {
            return false
        }

        let combinedBounds = InkBounds.enclosing([lhs.bounds, rhs.bounds])
        let horizontalOverlap = lhs.bounds.horizontalOverlap(with: rhs.bounds)
        let narrowerWidth = max(min(lhs.bounds.width, rhs.bounds.width), 1)
        let verticalMiss = lhs.bounds.verticalMiss(to: rhs.bounds)
        let hasRootBar = lhs.hasRootConstructionBar || rhs.hasRootConstructionBar
        let hasRootBody = lhs.hasRootConstructionBody || rhs.hasRootConstructionBody
        let hasRootVerticalStem = lhs.hasRootConstructionVerticalStem || rhs.hasRootConstructionVerticalStem
        let horizontalGap = lhs.bounds.horizontalGap(to: rhs.bounds)
        let edgeTouchingDetachedStem = horizontalGap <= 1.5
            && lhs.hasRootConstructionBody != rhs.hasRootConstructionBody

        if hasRootVerticalStem,
           hasRootBody,
           combinedBounds.width >= 14,
           (horizontalOverlap >= narrowerWidth * 0.40 || edgeTouchingDetachedStem),
           verticalMiss <= max(6, combinedBounds.height * 0.32) {
            return true
        }

        return hasRootBar
            && hasRootBody
            && horizontalOverlap >= narrowerWidth * 0.35
            && verticalMiss <= max(6, combinedBounds.height * 0.28)
    }

    private func shouldMergeAsHalfDiminishedConstruction(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let ordered = lhs.isDiminishedCircleConstructionPart
            ? (circle: lhs, slash: rhs)
            : (circle: rhs, slash: lhs)

        guard ordered.circle.isDiminishedCircleConstructionPart,
              ordered.slash.isHalfDiminishedSlashConstructionPart else {
            return false
        }

        let combinedBounds = InkBounds.enclosing([ordered.circle.bounds, ordered.slash.bounds])
        let horizontalGap = ordered.circle.bounds.horizontalGap(to: ordered.slash.bounds)
        let verticalMiss = ordered.circle.bounds.verticalMiss(to: ordered.slash.bounds)
        let horizontalOverlap = ordered.circle.bounds.horizontalOverlap(with: ordered.slash.bounds)
        let verticalOverlap = ordered.circle.bounds.verticalOverlap(with: ordered.slash.bounds)

        return combinedBounds.width <= 34
            && combinedBounds.height <= 34
            && horizontalGap <= max(5, ordered.circle.bounds.width * 0.55)
            && verticalMiss <= max(5, ordered.circle.bounds.height * 0.55)
            && (horizontalOverlap > 0 || verticalOverlap > 0)
    }

    private func shouldMergeAsPlusConstruction(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let ordered = lhs.isPlusVerticalConstructionPart
            ? (vertical: lhs, horizontal: rhs)
            : (vertical: rhs, horizontal: lhs)

        guard ordered.vertical.isPlusVerticalConstructionPart,
              ordered.horizontal.isPlusHorizontalConstructionPart else {
            return false
        }

        let combinedBounds = InkBounds.enclosing([ordered.vertical.bounds, ordered.horizontal.bounds])
        let verticalCenterX = ordered.vertical.bounds.recognitionMidX
        let horizontalCenterY = ordered.horizontal.bounds.recognitionMidY
        let crossesHorizontalStroke = ordered.horizontal.bounds.minX - 2 <= verticalCenterX
            && verticalCenterX <= ordered.horizontal.bounds.maxX + 2
        let crossesVerticalStroke = ordered.vertical.bounds.minY - 2 <= horizontalCenterY
            && horizontalCenterY <= ordered.vertical.bounds.maxY + 2

        return combinedBounds.width >= 7
            && combinedBounds.width <= 28
            && combinedBounds.height >= 7
            && combinedBounds.height <= 30
            && crossesHorizontalStroke
            && crossesVerticalStroke
    }

    private func shouldMergeAsSharpConstruction(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let combinedStrokeCount = lhs.strokes.count + rhs.strokes.count
        guard combinedStrokeCount <= 6,
              lhs.isSharpConstructionPart,
              rhs.isSharpConstructionPart,
              !lhs.isParenthesizedAlterationWrapperCandidate,
              !rhs.isParenthesizedAlterationWrapperCandidate,
              !lhs.isTallRootLikeSharpConstruction,
              !rhs.isTallRootLikeSharpConstruction else {
            return false
        }

        let combinedBounds = InkBounds.enclosing([lhs.bounds, rhs.bounds])
        let combinedAspectRatio = max(combinedBounds.width, 1) / max(combinedBounds.height, 1)
        let horizontalGap = lhs.bounds.horizontalGap(to: rhs.bounds)
        let verticalGap = lhs.bounds.verticalMiss(to: rhs.bounds)
        let combinedVerticalCount = lhs.looseSharpVerticalStrokeCount + rhs.looseSharpVerticalStrokeCount
        let combinedHorizontalCount = lhs.looseSharpHorizontalStrokeCount + rhs.looseSharpHorizontalStrokeCount

        guard combinedHorizontalCount <= 2,
              combinedVerticalCount <= 3 else {
            return false
        }

        if lhs.hasSharpVerticalStroke && rhs.hasSharpVerticalStroke {
            guard combinedHorizontalCount > 0 else {
                return false
            }

            let minimumHeight = max(min(lhs.bounds.height, rhs.bounds.height), 1)
            return horizontalGap <= 11
                && lhs.bounds.verticalOverlap(with: rhs.bounds) >= minimumHeight * 0.35
                && combinedAspectRatio <= 1.15
        }

        if lhs.hasSharpHorizontalStroke && rhs.hasSharpHorizontalStroke {
            let minimumWidth = max(min(lhs.bounds.width, rhs.bounds.width), 1)
            return verticalGap <= 7
                && lhs.bounds.horizontalOverlap(with: rhs.bounds) >= minimumWidth * 0.25
                && combinedAspectRatio >= 0.75
        }

        return combinedVerticalCount >= 1
            && combinedHorizontalCount >= 1
            && combinedAspectRatio >= 0.22
            && combinedAspectRatio <= 1.45
            && horizontalGap <= 6
            && verticalGap <= 9
            && (lhs.bounds.horizontalOverlap(with: rhs.bounds) > 0
                || lhs.bounds.verticalOverlap(with: rhs.bounds) > 0)
    }

    private func timingAllowsMerge(_ lhs: MutableInkCluster, _ rhs: MutableInkCluster) -> Bool {
        guard let lhsEnd = lhs.endTimeOffset,
              let rhsStart = rhs.startTimeOffset else {
            return true
        }

        let forwardGap = rhsStart - lhsEnd
        if forwardGap >= 0 {
            return forwardGap <= configuration.maxTimeGap
        }

        guard let rhsEnd = rhs.endTimeOffset,
              let lhsStart = lhs.startTimeOffset else {
            return true
        }

        let reverseGap = lhsStart - rhsEnd
        return reverseGap <= configuration.maxTimeGap
    }

    private func hasSmallModifier(_ lhs: MutableInkCluster, _ rhs: MutableInkCluster) -> Bool {
        let smallerArea = min(lhs.bounds.recognitionArea, rhs.bounds.recognitionArea)
        let largerArea = max(lhs.bounds.recognitionArea, rhs.bounds.recognitionArea)
        guard largerArea > 0 else {
            return false
        }

        return smallerArea / largerArea <= configuration.smallModifierSizeRatio
    }

    private func shouldKeepSeparateAsRightSideModifier(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        isRightSideModifier(lhs, attachedTo: rhs)
            || isRightSideModifier(rhs, attachedTo: lhs)
    }

    private func shouldKeepSeparateAsAdjacentOneGlyphs(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        guard lhs.isStandaloneOneGlyphCandidate,
              rhs.isStandaloneOneGlyphCandidate else {
            return false
        }

        let horizontalGap = lhs.bounds.horizontalGap(to: rhs.bounds)
        let minimumHeight = max(min(lhs.bounds.height, rhs.bounds.height), 1)

        return horizontalGap <= 12
            && lhs.bounds.verticalOverlap(with: rhs.bounds) >= minimumHeight * 0.45
    }

    private func shouldKeepSeparateAsAdjacentOneThreeGlyphs(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let ordered = lhs.bounds.minX <= rhs.bounds.minX ? (left: lhs, right: rhs) : (left: rhs, right: lhs)
        guard ordered.left.isStandaloneOneGlyphCandidate,
              ordered.right.isStandaloneThreeGlyphCandidate else {
            return false
        }

        let horizontalGap = ordered.left.bounds.horizontalGap(to: ordered.right.bounds)
        let minimumHeight = max(min(ordered.left.bounds.height, ordered.right.bounds.height), 1)
        let combinedBounds = InkBounds.enclosing([ordered.left.bounds, ordered.right.bounds])

        return horizontalGap <= 8
            && combinedBounds.height <= 24
            && ordered.left.bounds.verticalOverlap(with: ordered.right.bounds) >= minimumHeight * 0.35
    }

    private func isRightSideModifier(
        _ modifier: MutableInkCluster,
        attachedTo root: MutableInkCluster
    ) -> Bool {
        let rootArea = root.bounds.recognitionArea
        let modifierArea = modifier.bounds.recognitionArea
        guard root.isRootBodyCandidate,
              modifier.isAccidentalModifierCandidate else {
            return false
        }

        if root.isPartialSharpConstruction,
           modifier.isSharpConstructionPart,
           !root.isTallRootLikeSharpConstruction,
           !modifier.isTallRootLikeSharpConstruction {
            return false
        }

        let rootWidth = max(root.bounds.width, 1)
        let rootHeight = max(root.bounds.height, 1)
        let horizontalGap = root.bounds.horizontalGap(to: modifier.bounds)
        let verticalMiss = root.bounds.verticalMiss(to: modifier.bounds)
        let clearlyDetachedToRight = modifier.bounds.minX >= root.bounds.maxX + max(1, rootWidth * 0.04)
        guard rootArea >= modifierArea * 1.2
                || (clearlyDetachedToRight && rootArea >= modifierArea * 0.60) else {
            return false
        }

        let startsAfterRootBody = modifier.bounds.minX >= root.bounds.maxX - max(2, rootWidth * 0.08)
        let sharpCrossesRootEdge = modifier.isSharpConstructionPart
            && modifier.bounds.maxX >= root.bounds.maxX + max(2, rootWidth * 0.12)
            && modifier.bounds.minX >= root.bounds.maxX - max(5, rootWidth * 0.24)
        let closeEnoughToBelongToThisChord = horizontalGap <= rootHeight * 0.45
            && verticalMiss <= rootHeight * 0.55
        let modifierSized = modifierArea / rootArea <= 0.72
            || modifier.bounds.width <= rootWidth * 0.85
            || clearlyDetachedToRight

        return (startsAfterRootBody || sharpCrossesRootEdge)
            && closeEnoughToBelongToThisChord
            && modifierSized
    }

    private func shouldKeepSeparateAsOverlappingFlatModifier(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        isOverlappingFlatModifier(lhs, attachedTo: rhs)
            || isOverlappingFlatModifier(rhs, attachedTo: lhs)
    }

    private func isOverlappingFlatModifier(
        _ modifier: MutableInkCluster,
        attachedTo root: MutableInkCluster
    ) -> Bool {
        guard root.isRootBodyCandidate,
              modifier.isFlatGlyphCandidate else {
            return false
        }

        let rootWidth = max(root.bounds.width, 1)
        let rootHeight = max(root.bounds.height, 1)
        let rootArea = root.bounds.recognitionArea
        let modifierArea = modifier.bounds.recognitionArea
        let startsAtRootEdge = modifier.bounds.minX >= root.bounds.maxX - max(4, rootWidth * 0.22)
        let closeEnoughToBelongToThisChord = root.bounds.horizontalGap(to: modifier.bounds) <= rootHeight * 0.45
            && root.bounds.verticalMiss(to: modifier.bounds) <= rootHeight * 0.55
        let modifierSized = modifierArea / max(rootArea, 1) <= 0.72
            || modifier.bounds.width <= rootWidth * 0.85

        return startsAtRootEdge && closeEnoughToBelongToThisChord && modifierSized
    }

    private func removeDominantAlterationParenthesisWrappers(
        in clusters: [MutableInkCluster]
    ) -> [MutableInkCluster] {
        let orderedClusters = clusters.sorted { lhs, rhs in
            if lhs.bounds.minX != rhs.bounds.minX {
                return lhs.bounds.minX < rhs.bounds.minX
            }

            return (lhs.originalIndexes.min() ?? 0) < (rhs.originalIndexes.min() ?? 0)
        }
        let removalIndices = orderedClusters.indices.filter { index in
            guard !isDominantSuspendedClosingSuffixCandidate(at: index, in: orderedClusters) else {
                return false
            }

            guard !isPotentialDominantSuspendedSuffixPart(at: index, in: orderedClusters) else {
                return false
            }

            guard !isSuspendedFourthTail(at: index, in: orderedClusters) else {
                return false
            }

            return isOpeningDominantAlterationWrapper(at: index, in: orderedClusters)
                || isClosingDominantAlterationWrapper(at: index, in: orderedClusters)
        }
        let removalIndexSet = Set(removalIndices)

        return orderedClusters.enumerated().compactMap { index, cluster in
            removalIndexSet.contains(index) ? nil : cluster
        }
    }

    private func isDominantSuspendedClosingSuffixCandidate(
        at index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        guard index >= 3,
              clusters[index].isSuspendedSLikeContextCandidate else {
            return false
        }

        let sevenIndex = index - 3
        let leadingSuspended = clusters[index - 2]
        let middleSuspended = clusters[index - 1]

        guard middleSuspended.isLooseDominantSuspendedMiddleCandidate,
              leadingSuspended.isSuspendedSLikeContextCandidate,
              clusters[sevenIndex].isDominantSevenInkAnchor,
              hasLowerDominantSuspendedSuffix(after: sevenIndex, in: clusters) else {
            return false
        }

        return clusters[sevenIndex].bounds.horizontalGap(to: clusters[index - 2].bounds) <= 44
            && clusters[index - 2].bounds.horizontalGap(to: clusters[index - 1].bounds) <= 44
            && clusters[index - 1].bounds.horizontalGap(to: clusters[index].bounds) <= 44
    }

    private func hasLowerDominantSuspendedSuffix(
        after sevenIndex: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        guard sevenIndex + 3 < clusters.count else {
            return false
        }

        let sevenBounds = clusters[sevenIndex].bounds
        let suffixFloor = sevenBounds.minY + max(8, sevenBounds.height * 0.60)
        return clusters[(sevenIndex + 1)...(sevenIndex + 3)].allSatisfy { suffixCluster in
            suffixCluster.bounds.minY >= suffixFloor
        }
    }

    private func hasLowerDominantSuspendedSuffix(
        after seven: MutableInkCluster,
        suffixClusters: [MutableInkCluster]
    ) -> Bool {
        guard suffixClusters.count >= 3 else {
            return false
        }

        let suffixFloor = seven.bounds.minY + max(8, seven.bounds.height * 0.60)
        return suffixClusters.prefix(3).allSatisfy { suffixCluster in
            suffixCluster.bounds.minY >= suffixFloor
        }
    }

    private func isDominantSuspendedSuffixPart(
        at index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        let sevenIndex: Int?
        if index >= 1,
           clusters[index - 1].isDominantSevenInkAnchor {
            sevenIndex = index - 1
        } else if index >= 2,
                  clusters[index - 2].isDominantSevenInkAnchor {
            sevenIndex = index - 2
        } else if index >= 3,
                  clusters[index - 3].isDominantSevenInkAnchor {
            sevenIndex = index - 3
        } else {
            sevenIndex = nil
        }

        guard let sevenIndex,
              sevenIndex > 0,
              sevenIndex + 3 < clusters.count else {
            return false
        }

        let suspendedStart = sevenIndex + 1
        guard index >= suspendedStart,
              index <= sevenIndex + 3 else {
            return false
        }

        return clusters[suspendedStart].isSuspendedSLikeContextCandidate
            && clusters[suspendedStart + 1].isSuspendedULikeContextCandidate
            && clusters[suspendedStart + 2].isSuspendedSLikeContextCandidate
            && hasLowerDominantSuspendedSuffix(after: sevenIndex, in: clusters)
            && clusters[sevenIndex].bounds.horizontalGap(to: clusters[suspendedStart].bounds) <= 40
            && clusters[suspendedStart].bounds.horizontalGap(to: clusters[suspendedStart + 1].bounds) <= 40
            && clusters[suspendedStart + 1].bounds.horizontalGap(to: clusters[suspendedStart + 2].bounds) <= 40
    }

    private func isPotentialDominantSuspendedSuffixPart(
        at index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        if isDominantSuspendedSuffixPart(at: index, in: clusters) {
            return true
        }

        guard index > 0 else {
            return false
        }

        let nearbySevenIndex = clusters[..<index].indices.reversed().first { candidateIndex in
            candidateIndex > 0
                && index - candidateIndex <= 3
                && clusters[candidateIndex].isDominantSevenInkAnchor
        }

        guard let sevenIndex = nearbySevenIndex else {
            return false
        }

        guard hasLowerDominantSuspendedSuffix(after: sevenIndex, in: clusters) else {
            return false
        }

        let offset = index - sevenIndex
        let current = clusters[index]
        let staysNearSeven = clusters[sevenIndex].bounds.horizontalGap(to: current.bounds) <= 78

        guard staysNearSeven else {
            return false
        }

        switch offset {
        case 1:
            return current.isSuspendedSLikeContextCandidate
                && index + 1 < clusters.count
                && clusters[index + 1].isSuspendedULikeContextCandidate
        case 2:
            return current.isSuspendedULikeContextCandidate
                && clusters[index - 1].isSuspendedSLikeContextCandidate
        case 3:
            return current.isSuspendedSLikeContextCandidate
                && clusters[index - 1].isSuspendedULikeContextCandidate
                && clusters[index - 2].isSuspendedSLikeContextCandidate
        default:
            return false
        }
    }

    private func isSuspendedFourthTail(
        at index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        guard index >= 3,
              clusters[index].isSuspendedFourthLikeCandidate,
              !hasDominantSevenInk(before: index, in: clusters) else {
            return false
        }

        return clusters[index - 1].isSuspendedSLikeContextCandidate
            && clusters[index - 2].isSuspendedULikeContextCandidate
            && clusters[index - 3].isSuspendedSLikeContextCandidate
    }

    private func isOpeningDominantAlterationWrapper(
        at index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        guard !clusters[index].isSuspendedSLikeCandidate
                || hasDominantSevenCandidate(before: index, in: clusters) else {
            return false
        }

        if index >= 1,
           index + 1 < clusters.count,
           clusters[index].isLooseOpeningParenthesizedAlterationWrapperCandidate,
           !clusters[index + 1].isParenthesizedAlterationWrapperCandidate,
           clusters[index + 1].isWrittenAlterationAccidentalCandidate,
           clusters[index - 1].isLooseAlterationNumberCandidate,
           clusters[index - 1].bounds.horizontalGap(to: clusters[index].bounds) <= 36,
           clusters[index].bounds.horizontalGap(to: clusters[index + 1].bounds) <= 24 {
            return true
        }

        guard index + 1 < clusters.count,
              let sevenIndex = nearestDominantSevenIndex(before: index, in: clusters),
              clusters[index].isOpeningParenthesizedAlterationWrapperCandidate
                || clusters[index].isLooseOpeningParenthesizedAlterationWrapperCandidate,
              !clusters[index + 1].isParenthesizedAlterationWrapperCandidate,
              clusters[index + 1].isWrittenAlterationAccidentalCandidate else {
            return false
        }

        return clusters[sevenIndex].bounds.horizontalGap(to: clusters[index].bounds) <= 96
            && clusters[index].bounds.horizontalGap(to: clusters[index + 1].bounds) <= 24
    }

    private func isClosingDominantAlterationWrapper(
        at index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        guard !clusters[index].isSuspendedSLikeCandidate
                || hasDominantSevenCandidate(before: index, in: clusters) else {
            return false
        }

        if index > 0,
           clusters[index].isStandaloneThreeGlyphCandidate,
           clusters[index - 1].isLooseAlterationNumberCandidate {
            return false
        }

        if index + 1 < clusters.count,
           clusters[index].isStandaloneOneGlyphCandidate,
           clusters[index + 1].isStandaloneThreeGlyphCandidate {
            return false
        }

        if index >= 4,
           clusters[index].isTrailingParenthesizedAlterationWrapperCandidate
            || clusters[index].isLooseTrailingAlterationWrapperCandidate,
           clusters[index - 1].isStandaloneThreeGlyphCandidate,
           clusters[index - 2].isLooseAlterationNumberCandidate,
           clusters[index - 3].isWrittenAlterationAccidentalCandidate,
           (clusters[index - 4].isDominantSevenSuffixAnchor || clusters[index - 4].isLooseAlterationNumberCandidate),
           clusters[index - 2].bounds.horizontalGap(to: clusters[index - 1].bounds) <= 24,
           clusters[index - 1].bounds.horizontalGap(to: clusters[index].bounds) <= 24 {
            return true
        }

        if index >= 3,
           clusters[index].isTrailingParenthesizedAlterationWrapperCandidate
            || clusters[index].isLooseTrailingAlterationWrapperCandidate,
           clusters[index - 1].isLooseAlterationNumberCandidate
            || clusters[index - 1].isLooseAlteredFiveFragmentCandidate,
           clusters[index - 2].isWrittenAlterationAccidentalCandidate,
           (clusters[index - 3].isDominantSevenSuffixAnchor || clusters[index - 3].isLooseAlterationNumberCandidate),
           clusters[index - 2].bounds.horizontalGap(to: clusters[index - 1].bounds) <= 36,
           clusters[index - 1].bounds.horizontalGap(to: clusters[index].bounds) <= 24 {
            return true
        }

        guard index > 0,
              let sevenIndex = nearestDominantSevenIndex(before: index, in: clusters) else {
            return false
        }

        let hasAlterationAccidental = clusters[(sevenIndex + 1)..<index].contains { cluster in
            cluster.isWrittenAlterationAccidentalCandidate
        }
        let isFinalWrapper = index == clusters.indices.last
            || clusters[index].bounds.horizontalGap(to: clusters[index + 1].bounds) > 18
        let followsAlterationNumber = clusters[index - 1].isAlterationNumberCandidate
            || clusters[index - 1].isLooseAlterationNumberCandidate
        let looksLikeClosingWrapper = clusters[index].isLooseClosingParenthesizedAlterationWrapperCandidate
            || (followsAlterationNumber && clusters[index].isTrailingParenthesizedAlterationWrapperCandidate)

        return hasAlterationAccidental
            && isFinalWrapper
            && looksLikeClosingWrapper
            && clusters[sevenIndex].bounds.horizontalGap(to: clusters[index].bounds) <= 118
            && clusters[index - 1].bounds.horizontalGap(to: clusters[index].bounds) <= 24
    }

    private func nearestDominantSevenIndex(
        before index: Int,
        in clusters: [MutableInkCluster]
    ) -> Int? {
        clusters[..<index].indices.reversed().first { candidateIndex in
            candidateIndex > 0
                && (clusters[candidateIndex].isDominantSevenAlterationAnchor
                    || candidateIndex == index - 1 && clusters[candidateIndex].isDominantSevenSuffixAnchor)
        }
    }

    private func hasDominantSevenContext(
        before index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        clusters[..<index].indices.contains { candidateIndex in
            candidateIndex > 0 && clusters[candidateIndex].isDominantSevenAlterationAnchor
        }
    }

    private func hasDominantSevenCandidate(
        before index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        clusters[..<index].indices.contains { candidateIndex in
            let participatesInSuspendedSuffix = clusters[candidateIndex].isSuspendedSLikeCandidate
                && candidateIndex + 1 < index
                && clusters[candidateIndex + 1].isSuspendedULikeCandidate
                || clusters[candidateIndex].isSuspendedULikeCandidate
                && candidateIndex > 0
                && clusters[candidateIndex - 1].isSuspendedSLikeCandidate

            return candidateIndex > 0
                && clusters[candidateIndex].isDominantSevenSuffixAnchor
                && !participatesInSuspendedSuffix
        }
    }

    private func hasDominantSevenInk(
        before index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
        clusters[..<index].indices.contains { candidateIndex in
            guard candidateIndex > 0,
                  clusters[candidateIndex].isDominantSevenAlterationAnchor else {
                return false
            }

            let participatesInSuspendedSuffix = clusters[candidateIndex].isSuspendedSLikeCandidate
                && candidateIndex + 1 < index
                && clusters[candidateIndex + 1].isSuspendedULikeContextCandidate
                || clusters[candidateIndex].isSuspendedSLikeCandidate
                && candidateIndex > 0
                && clusters[candidateIndex - 1].isSuspendedULikeContextCandidate
                || clusters[candidateIndex].isSuspendedSLikeContextCandidate
                && candidateIndex > 1
                && clusters[candidateIndex - 1].isSuspendedULikeContextCandidate
                && clusters[candidateIndex - 2].isSuspendedSLikeContextCandidate

            return !participatesInSuspendedSuffix
        }
    }

    private func shouldKeepSeparateAsParenthesizedAlterationWrapper(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let ordered = lhs.bounds.minX <= rhs.bounds.minX ? (left: lhs, right: rhs) : (left: rhs, right: lhs)

        return ordered.left.isOpeningParenthesizedAlterationWrapperCandidate
            && ordered.right.isAlterationAccidentalCandidate
            && ordered.left.bounds.horizontalGap(to: ordered.right.bounds) <= 18
    }

    private func shouldKeepSeparateAsMinorSuffixAndExtension(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let ordered = lhs.bounds.minX <= rhs.bounds.minX ? (left: lhs, right: rhs) : (left: rhs, right: lhs)

        return ordered.left.isMinorSuffixCandidate
            && ordered.right.isDominantSevenSuffixAnchor
            && ordered.left.bounds.horizontalGap(to: ordered.right.bounds) <= 14
            && ordered.left.bounds.verticalMiss(to: ordered.right.bounds) <= 14
    }

    private func shouldKeepSeparateAsSuspendedSuffixLetters(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let ordered = lhs.bounds.minX <= rhs.bounds.minX ? (left: lhs, right: rhs) : (left: rhs, right: lhs)
        let horizontalGap = ordered.left.bounds.horizontalGap(to: ordered.right.bounds)
        let verticalMiss = ordered.left.bounds.verticalMiss(to: ordered.right.bounds)

        guard horizontalGap <= 16,
              verticalMiss <= 16 else {
            return false
        }

        if ordered.left.isSharpGlyphCandidate,
           ordered.right.isSuspendedSLikeCandidate {
            return true
        }

        if ordered.left.isSuspendedSLikeCandidate,
           ordered.right.isSuspendedULikeCandidate {
            return true
        }

        if ordered.left.isSuspendedULikeCandidate,
           ordered.right.isSuspendedSLikeCandidate {
            return true
        }

        return false
    }

    private func shouldKeepSeparateAsSequentialGlyphs(
        _ lhs: MutableInkCluster,
        _ rhs: MutableInkCluster
    ) -> Bool {
        let ordered = lhs.bounds.minX <= rhs.bounds.minX ? (left: lhs, right: rhs) : (left: rhs, right: lhs)
        let leftWidth = max(ordered.left.bounds.width, 1)
        let rightStartsAfterLeftBody = ordered.right.bounds.minX >= ordered.left.bounds.maxX - max(1, leftWidth * 0.08)
        let closeEnoughToBeSameChord = ordered.left.bounds.horizontalGap(to: ordered.right.bounds) <= 8
            && ordered.left.bounds.verticalMiss(to: ordered.right.bounds) <= 10

        guard rightStartsAfterLeftBody,
              closeEnoughToBeSameChord else {
            return ordered.left.isQualityOrExtensionGlyphCandidate
                && ordered.right.isQualityOrExtensionGlyphCandidate
                && ordered.right.bounds.recognitionMidX > ordered.left.bounds.recognitionMidX + leftWidth * 0.35
        }

        return ((ordered.left.isFlatGlyphCandidate || ordered.left.isSharpGlyphCandidate)
            && ordered.right.isQualityOrExtensionGlyphCandidate)
            || (ordered.left.isQualityOrExtensionGlyphCandidate && ordered.right.isQualityOrExtensionGlyphCandidate)
    }
}
