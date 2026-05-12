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

        return finalClusters
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
            return isOpeningDominantAlterationWrapper(at: index, in: orderedClusters)
                || isClosingDominantAlterationWrapper(at: index, in: orderedClusters)
        }
        let removalIndexSet = Set(removalIndices)

        return orderedClusters.enumerated().compactMap { index, cluster in
            removalIndexSet.contains(index) ? nil : cluster
        }
    }

    private func isOpeningDominantAlterationWrapper(
        at index: Int,
        in clusters: [MutableInkCluster]
    ) -> Bool {
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

private struct MutableInkCluster: Hashable {
    var strokes: [InkStroke]
    var originalIndexes: [Int]

    var bounds: InkBounds {
        InkBounds.enclosing(strokes.map(\.bounds))
    }

    var startTimeOffset: TimeInterval? {
        strokes
            .flatMap(\.points)
            .compactMap(\.timeOffset)
            .min()
    }

    var endTimeOffset: TimeInterval? {
        strokes
            .flatMap(\.points)
            .compactMap(\.timeOffset)
            .max()
    }

    var isRootBodyCandidate: Bool {
        bounds.width >= 8
            && bounds.height >= 16
            && bounds.recognitionArea >= 220
    }

    var isAccidentalModifierCandidate: Bool {
        bounds.width >= 1
            && (bounds.height >= 4 || bounds.width >= 8)
            && bounds.recognitionArea >= 4
            && strokes.count <= 6
    }

    var isDominantSevenSuffixAnchor: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isSevenCandidate
    }

    var isMinorSuffixCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isMinorMCandidate || stroke.isLooseMinorMSuffixCandidate || stroke.isDashMinorCandidate
    }

    var isDominantSevenAlterationAnchor: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isSevenCandidate && stroke.hasEarlyTopHorizontalRun
    }

    var isDominantFlatNineStemFragment: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDominantFlatNineStemFragment
    }

    var isDominantFlatNineCurvedFragment: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDominantFlatNineCurvedFragment
    }

    var isDominantFlatNineMergedFlatFragment: Bool {
        guard strokes.count == 2 else {
            return false
        }

        let orderedStrokes = strokes.sorted { lhs, rhs in
            lhs.bounds.minX < rhs.bounds.minX
        }

        return orderedStrokes[0].isDominantFlatNineStemFragment
            && orderedStrokes[1].isDominantFlatNineCurvedFragment
            && bounds.width <= 32
            && bounds.height <= 42
    }

    var isDominantFlatNineTailFragment: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDominantFlatNineTailFragment
    }

    var isParenthesizedAlterationWrapperCandidate: Bool {
        isOpeningParenthesizedAlterationWrapperCandidate
            || isClosingParenthesizedAlterationWrapperCandidate
    }

    var isOpeningParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isOpeningParenthesizedAlterationWrapperCandidate
            || stroke.isLooseOpeningParenthesizedAlterationWrapperCandidate
    }

    var isLooseOpeningParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isLooseOpeningParenthesizedAlterationWrapperCandidate
    }

    var isClosingParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isClosingParenthesizedAlterationWrapperCandidate
    }

    var isLooseClosingParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isLooseClosingParenthesizedAlterationWrapperCandidate
    }

    var isTrailingParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isTrailingParenthesizedAlterationWrapperCandidate
    }

    var isLooseTrailingAlterationWrapperCandidate: Bool {
        strokes.count == 1
            && bounds.width <= 18
            && bounds.height >= 14
            && bounds.height <= 42
    }

    var isAlterationAccidentalCandidate: Bool {
        isSharpGlyphCandidate
            || isPartialSharpConstruction
            || isFlatGlyphCandidate
            || isDominantFlatNineMergedFlatFragment
            || isDominantFlatNineStemFragment
    }

    var isWrittenAlterationAccidentalCandidate: Bool {
        isSharpGlyphCandidate
            || isFlatGlyphCandidate
            || isDominantFlatNineMergedFlatFragment
    }

    var isAlterationNumberCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isOneGlyphCandidate
            || stroke.isThreeGlyphCandidate
            || stroke.isFiveGlyphCandidate
            || stroke.isNineGlyphCandidate
    }

    var isLooseAlterationNumberCandidate: Bool {
        strokes.count == 1
            && bounds.width <= 18
            && bounds.height >= 8
            && bounds.height <= 34
    }

    var isLooseAlteredFiveFragmentCandidate: Bool {
        strokes.count <= 2
            && bounds.width <= 18
            && bounds.height >= 3
            && bounds.height <= 32
            && bounds.recognitionArea >= 8
    }

    var isStandaloneOneGlyphCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isOneGlyphCandidate
    }

    var isStandaloneThreeGlyphCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isThreeGlyphCandidate
    }

    var isSlashLikeSeparator: Bool {
        guard strokes.count == 1,
              let firstPoint = strokes[0].points.first,
              let lastPoint = strokes[0].points.last else {
            return false
        }

        let bounds = strokes[0].bounds
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let slopeMagnitude = height / width
        let dx = lastPoint.x - firstPoint.x
        let dy = lastPoint.y - firstPoint.y
        let angleDegrees = abs(atan2(dy, dx) * 180 / .pi)

        return slopeMagnitude >= 0.65
            && slopeMagnitude <= 4.0
            && strokes[0].straightness >= 0.72
            && dx * dy < 0
            && angleDegrees >= 42
            && angleDegrees <= 78
            && width >= 4
            && height >= 8
    }

    var isFlatGlyphCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first,
              let firstPoint = stroke.points.first,
              let lastPoint = stroke.points.last else {
            return false
        }

        let bounds = stroke.bounds
        let aspectRatio = max(bounds.width, 1) / max(bounds.height, 1)
        let angleDegrees = atan2(lastPoint.y - firstPoint.y, lastPoint.x - firstPoint.x) * 180 / .pi

        return stroke.points.count >= 10
            && bounds.height >= 10
            && aspectRatio >= 0.42
            && aspectRatio <= 1.20
            && angleDegrees >= 42
            && angleDegrees <= 105
            && !stroke.hasEarlyTopHorizontalRun
            || stroke.points.count >= 7
            && bounds.width <= 12
            && bounds.height >= 8
            && aspectRatio >= 0.35
            && aspectRatio <= 1.20
            && angleDegrees >= 35
            && angleDegrees <= 115
            && !stroke.hasEarlyTopHorizontalRun
    }

    var isQualityOrExtensionGlyphCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDashMinorCandidate
            || stroke.isMinorMCandidate
            || stroke.isDiminishedCircleConstructionCandidate
            || stroke.isSevenCandidate
    }

    var isSharpGlyphCandidate: Bool {
        strokes.count >= 4
            && strokes.count <= 6
            && looseSharpVerticalStrokeCount >= 2
            && looseSharpHorizontalStrokeCount >= 1
            && bounds.width >= 8
            && bounds.height >= 12
    }

    var isPlusVerticalConstructionPart: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isPlusVerticalConstructionCandidate
    }

    var isPlusHorizontalConstructionPart: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isPlusHorizontalConstructionCandidate
    }

    var isDiminishedCircleConstructionPart: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDiminishedCircleConstructionCandidate
    }

    var isHalfDiminishedSlashConstructionPart: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isHalfDiminishedSlashConstructionCandidate
    }

    var canMergeAsSharpFragment: Bool {
        !isRootBodyCandidate
            || isSharpGlyphCandidate
            || (strokes.count >= 2 && isSharpConstructionPart)
    }

    var looseSharpVerticalStrokeCount: Int {
        strokes.filter(\.isLooseSharpVerticalCandidate).count
    }

    var looseSharpHorizontalStrokeCount: Int {
        strokes.filter(\.isLooseSharpHorizontalCandidate).count
    }

    var hasSharpVerticalStroke: Bool {
        looseSharpVerticalStrokeCount > 0
    }

    var hasSharpHorizontalStroke: Bool {
        looseSharpHorizontalStrokeCount > 0
    }

    var isSharpConstructionPart: Bool {
        guard !strokes.isEmpty,
              strokes.allSatisfy({ $0.isSharpConstructionStrokeCandidate }) else {
            return false
        }

        let aspectRatio = max(bounds.width, 1) / max(bounds.height, 1)

        return bounds.width <= max(26, bounds.height * 1.45)
            && bounds.height <= max(28, bounds.width * 3.2)
            && aspectRatio >= 0.04
            && aspectRatio <= 8.0
    }

    var isTallRootLikeSharpConstruction: Bool {
        strokes.count >= 2
            && hasSharpVerticalStroke
            && hasSharpHorizontalStroke
            && looseSharpVerticalStrokeCount <= 1
            && bounds.height > 23
            && bounds.width >= 10
    }

    var isPartialSharpConstruction: Bool {
        looseSharpVerticalStrokeCount >= 2
            || (hasSharpVerticalStroke && hasSharpHorizontalStroke)
    }

    var hasRootConstructionBar: Bool {
        strokes.contains { stroke in
            stroke.bounds.width >= 5
                && stroke.aspectRatio >= 1.6
                && stroke.straightness >= 0.50
                && stroke.horizontalAngleMagnitude <= 45
        }
    }

    var hasRootConstructionVerticalStem: Bool {
        strokes.contains { stroke in
            stroke.bounds.height >= 14
                && stroke.bounds.height / max(stroke.bounds.width, 1) >= 1.90
                && stroke.straightness >= 0.50
                && abs(abs(stroke.angleDegrees) - 90) <= 32
        }
    }

    var hasRootConstructionBody: Bool {
        bounds.height >= 14
            && bounds.width >= 8
            && bounds.recognitionArea >= 140
    }

    func merged(with other: MutableInkCluster) -> MutableInkCluster {
        MutableInkCluster(
            strokes: strokes + other.strokes,
            originalIndexes: originalIndexes + other.originalIndexes
        )
    }
}

private extension InkBounds {
    var recognitionArea: Double {
        max(width, 1) * max(height, 1)
    }

    func horizontalGap(to other: InkBounds) -> Double {
        if maxX < other.minX {
            return other.minX - maxX
        }

        if other.maxX < minX {
            return minX - other.maxX
        }

        return 0
    }

    func verticalMiss(to other: InkBounds) -> Double {
        if maxY < other.minY {
            return other.minY - maxY
        }

        if other.maxY < minY {
            return minY - other.maxY
        }

        return 0
    }

    func horizontalOverlap(with other: InkBounds) -> Double {
        max(0, min(maxX, other.maxX) - max(minX, other.minX))
    }

    func verticalOverlap(with other: InkBounds) -> Double {
        max(0, min(maxY, other.maxY) - max(minY, other.minY))
    }

    var recognitionMidX: Double {
        minX + width / 2
    }

    var recognitionMidY: Double {
        minY + height / 2
    }
}

private extension InkStroke {
    var straightness: Double {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return 0
        }

        let pathLength = zip(points, points.dropFirst())
            .map { start, end in
                start.clusterDistance(to: end)
            }
            .reduce(0, +)
        guard pathLength > 0 else {
            return 0
        }

        return firstPoint.clusterDistance(to: lastPoint) / pathLength
    }

    var aspectRatio: Double {
        max(bounds.width, 1) / max(bounds.height, 1)
    }

    var isDashMinorCandidate: Bool {
        let standardDash = bounds.width >= 5
            && aspectRatio >= 1.80
            && straightness >= 0.50
            && abs(angleDegrees) <= 40
        let compactDash = points.count >= 3
            && points.count <= 7
            && bounds.width >= 4
            && bounds.height <= max(2.5, bounds.width * 0.30)
            && aspectRatio >= 2.20
            && straightness >= 0.30
            && abs(angleDegrees) <= 32
        let slantedCompactDash = points.count >= 3
            && points.count <= 9
            && bounds.width >= 6
            && bounds.height <= max(7, bounds.width * 0.70)
            && aspectRatio >= 1.35
            && straightness >= 0.40
            && abs(angleDegrees) <= 42

        return standardDash || compactDash || slantedCompactDash
    }

    var isMinorMCandidate: Bool {
        points.count >= 16
            && bounds.width >= 12
            && bounds.height >= 8
            && aspectRatio >= 0.70
            && aspectRatio <= 2.35
            && straightness <= 0.60
            && !hasEarlyTopHorizontalRun
    }

    var isLooseMinorMSuffixCandidate: Bool {
        points.count >= 12
            && bounds.width >= 10
            && bounds.height >= 8
            && aspectRatio >= 0.55
            && aspectRatio <= 2.60
            && straightness <= 0.72
            && !hasEarlyTopHorizontalRun
    }

    var isSevenCandidate: Bool {
        let standardSeven = points.count >= 7
            && bounds.width >= 5
            && bounds.height >= 8
            && aspectRatio >= 0.25
            && aspectRatio <= 1.65
            && angleDegrees >= 35
            && angleDegrees <= 105
            && hasEarlyTopHorizontalRun
        let trailingSeven = points.count >= 7
            && bounds.width >= 5
            && bounds.height >= 8
            && aspectRatio >= 0.25
            && aspectRatio <= 1.65
            && angleDegrees >= 35
            && angleDegrees <= 105
            && points.last.map { $0.y >= bounds.minY + bounds.height * 0.70 } == true

        return standardSeven || trailingSeven
    }

    var isOneGlyphCandidate: Bool {
        points.count >= 4
            && bounds.height >= 8
            && bounds.width <= max(6, bounds.height * 0.35)
            && straightness >= 0.60
            && abs(abs(angleDegrees) - 90) <= 28
    }

    var isThreeGlyphCandidate: Bool {
        points.count >= 10
            && bounds.width >= 8
            && bounds.height >= 12
            && bounds.height <= 28
            && aspectRatio >= 0.42
            && aspectRatio <= 1.45
            && straightness >= 0.18
            && straightness <= 0.70
            && angleDegrees >= 35
            && angleDegrees <= 115
            && (horizontalDirectionChangeCount >= 2 || hasEarlyTopHorizontalRun)
    }

    var isDominantFlatNineStemFragment: Bool {
        points.count >= 5
            && bounds.height >= 14
            && bounds.height <= 38
            && bounds.width <= max(10, bounds.height * 0.42)
            && straightness >= 0.48
            && abs(abs(angleDegrees) - 90) <= 38
    }

    var isDominantFlatNineCurvedFragment: Bool {
        points.count >= 8
            && bounds.width >= 4.5
            && bounds.width <= 16
            && bounds.height >= 10
            && bounds.height <= 30
            && aspectRatio >= 0.18
            && aspectRatio <= 1.25
            && straightness <= 0.58
            && (!hasEarlyTopHorizontalRun || straightness <= 0.40 || aspectRatio <= 0.70)
    }

    var isDominantFlatNineTailFragment: Bool {
        points.count >= 6
            && bounds.height >= 17
            && bounds.height <= 38
            && bounds.width <= 16
            && aspectRatio <= 0.92
            && straightness >= 0.48
            && angleDegrees >= 50
            && angleDegrees <= 125
    }

    var isNineGlyphCandidate: Bool {
        points.count >= 8
            && bounds.width >= 4
            && bounds.width <= 18
            && bounds.height >= 10
            && bounds.height <= 34
            && aspectRatio >= 0.16
            && aspectRatio <= 1.20
            && (straightness <= 0.72 || angleDegrees >= 35 && angleDegrees <= 125)
            && !hasEarlyTopHorizontalRun
    }

    var isFiveGlyphCandidate: Bool {
        points.count >= 5
            && bounds.width >= 4
            && bounds.width <= 20
            && bounds.height >= 8
            && bounds.height <= 34
            && aspectRatio >= 0.18
            && aspectRatio <= 1.55
            && points.last.map { $0.y >= bounds.minY + bounds.height * 0.55 } == true
            && (hasEarlyTopHorizontalRun || horizontalDirectionChangeCount >= 1 || straightness <= 0.72)
    }

    var isOpeningParenthesizedAlterationWrapperCandidate: Bool {
        isParenthesizedAlterationWrapperCandidate(curvingToward: .left)
    }

    var isLooseOpeningParenthesizedAlterationWrapperCandidate: Bool {
        points.count >= 4
            && bounds.height >= 14
            && bounds.height <= 38
            && bounds.width <= max(8, bounds.height * 0.40)
            && straightness >= 0.35
            && angleDegrees >= 48
            && angleDegrees <= 126
    }

    var isClosingParenthesizedAlterationWrapperCandidate: Bool {
        isParenthesizedAlterationWrapperCandidate(curvingToward: .right)
    }

    var isLooseClosingParenthesizedAlterationWrapperCandidate: Bool {
        isClosingParenthesizedAlterationWrapperCandidate
            || points.count >= 8
            && bounds.height >= 16
            && bounds.height <= 42
            && bounds.width >= 4.5
            && bounds.width <= 18
            && aspectRatio >= 0.08
            && aspectRatio <= 0.85
            && straightness >= 0.15
            && straightness <= 0.98
            && normalizedXRatio(of: points[0]) <= 0.65
            && normalizedXRatio(of: points[points.count - 1]) <= 0.75
            && points[points.count - 1].y >= bounds.minY + bounds.height * 0.55
    }

    var isTrailingParenthesizedAlterationWrapperCandidate: Bool {
        points.count >= 5
            && bounds.height >= 16
            && bounds.height <= 42
            && bounds.width >= 2
            && bounds.width <= 18
            && aspectRatio >= 0.08
            && aspectRatio <= 0.90
            && straightness >= 0.12
    }

    private enum ParenthesisCurveDirection {
        case left
        case right
    }

    private func isParenthesizedAlterationWrapperCandidate(
        curvingToward direction: ParenthesisCurveDirection
    ) -> Bool {
        guard points.count >= 8 else {
            return false
        }

        let middlePoints = points.filter { point in
            let yRatio = normalizedYRatio(of: point)
            return yRatio >= 0.22 && yRatio <= 0.78
        }
        let startX = normalizedXRatio(of: points[0])
        let endX = normalizedXRatio(of: points[points.count - 1])
        let middleMinX = middlePoints
            .map(normalizedXRatio(of:))
            .min() ?? startX
        let middleMaxX = middlePoints
            .map(normalizedXRatio(of:))
            .max() ?? startX
        let curvesLeft = startX >= 0.50
            && endX >= 0.38
            && middleMinX <= 0.55
        let curvesRight = startX <= 0.55
            && endX <= 0.70
            && middleMaxX >= 0.45

        return bounds.height >= 16
            && bounds.height <= 42
            && bounds.width >= 4.5
            && bounds.width <= 18
            && aspectRatio >= 0.08
            && aspectRatio <= 0.78
            && straightness >= 0.15
            && straightness <= 0.98
            && (direction == .left ? curvesLeft : curvesRight)
    }

    var isLooseSharpVerticalCandidate: Bool {
        bounds.height >= 8
            && bounds.width <= max(6, bounds.height * 0.45)
            && straightness >= 0.45
            && abs(abs(angleDegrees) - 90) <= 38
    }

    var isLooseSharpHorizontalCandidate: Bool {
        bounds.width >= 5
            && bounds.height <= max(7, bounds.width * 0.68)
            && straightness >= 0.45
            && abs(angleDegrees) <= 38
    }

    var isSharpConstructionStrokeCandidate: Bool {
        isLooseSharpVerticalCandidate || isLooseSharpHorizontalCandidate
    }

    var isPlusVerticalConstructionCandidate: Bool {
        bounds.height >= 7
            && bounds.height <= 30
            && bounds.width <= max(7, bounds.height * 0.50)
            && straightness >= 0.52
            && abs(abs(angleDegrees) - 90) <= 36
    }

    var isPlusHorizontalConstructionCandidate: Bool {
        bounds.width >= 7
            && bounds.width <= 30
            && bounds.height <= max(7, bounds.width * 0.55)
            && straightness >= 0.52
            && abs(angleDegrees) <= 38
    }

    var isDiminishedCircleConstructionCandidate: Bool {
        bounds.width >= 4
            && bounds.width <= 17
            && bounds.height >= 4
            && bounds.height <= 20
            && aspectRatio >= 0.42
            && aspectRatio <= 1.55
            && points.count >= 8
            && straightness <= 0.28
            && endpointClosureRatio <= 0.82
            && (startsLikeWrittenCircle || isTinyLooseCircle)
            && !looksLikeTriangleReturn
            && !hasEarlyTopHorizontalRun
    }

    var isHalfDiminishedSlashConstructionCandidate: Bool {
        bounds.width >= 4
            && bounds.height >= 4
            && straightness >= 0.54
            && aspectRatio >= 0.35
            && aspectRatio <= 2.80
            && diagonalAngleMagnitude >= 20
            && diagonalAngleMagnitude <= 80
            && (!hasEarlyTopHorizontalRun || abs(angleDegrees) >= 100)
    }

    var hasEarlyTopHorizontalRun: Bool {
        guard points.count >= 4 else {
            return false
        }

        let earlyCount = max(3, Int((Double(points.count) * 0.45).rounded(.up)))
        let earlyPoints = Array(points.prefix(min(points.count, earlyCount)))
        let earlyBounds = InkBounds.enclosing(earlyPoints)
        let averageY = earlyPoints.map(\.y).reduce(0, +) / Double(earlyPoints.count)

        return earlyBounds.width >= bounds.width * 0.45
            && earlyBounds.height <= max(4.5, bounds.height * 0.45)
            && averageY <= bounds.minY + bounds.height * 0.38
    }

    var horizontalDirectionChangeCount: Int {
        var previousDirection = 0
        var changeCount = 0

        for (currentPoint, nextPoint) in zip(points, points.dropFirst()) {
            let deltaX = nextPoint.x - currentPoint.x
            guard abs(deltaX) >= 2 else {
                continue
            }

            let direction = deltaX > 0 ? 1 : -1
            if previousDirection != 0, direction != previousDirection {
                changeCount += 1
            }
            previousDirection = direction
        }

        return changeCount
    }

    var angleDegrees: Double {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return 0
        }

        return atan2(lastPoint.y - firstPoint.y, lastPoint.x - firstPoint.x) * 180 / .pi
    }

    var horizontalAngleMagnitude: Double {
        let absoluteAngle = abs(angleDegrees)
        return min(absoluteAngle, abs(180 - absoluteAngle))
    }

    var endpointClosureRatio: Double {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return 0
        }

        return firstPoint.clusterDistance(to: lastPoint) / max(bounds.width, bounds.height, 1)
    }

    var startsLikeWrittenCircle: Bool {
        guard let firstPoint = points.first else {
            return false
        }

        let startYRatio = (firstPoint.y - bounds.minY) / max(bounds.height, 1)
        return startYRatio <= 0.42 || endpointClosureRatio <= 0.45
    }

    var isTinyLooseCircle: Bool {
        bounds.width <= 10
            && bounds.height <= 8
            && endpointClosureRatio <= 0.62
    }

    var looksLikeTriangleReturn: Bool {
        guard let lastPoint = points.last else {
            return false
        }

        let endXRatio = (lastPoint.x - bounds.minX) / max(bounds.width, 1)
        let endYRatio = (lastPoint.y - bounds.minY) / max(bounds.height, 1)

        return hasLowerBodyThenUpperPeakReturn
            && angleDegrees >= 55
            && angleDegrees <= 130
            && endXRatio <= 0.62
            && endYRatio >= 0.55
    }

    var diagonalAngleMagnitude: Double {
        let absoluteAngle = abs(angleDegrees)
        return min(absoluteAngle, abs(180 - absoluteAngle))
    }

    func normalizedXRatio(of point: InkPoint) -> Double {
        (point.x - bounds.minX) / max(bounds.width, 1)
    }

    func normalizedYRatio(of point: InkPoint) -> Double {
        (point.y - bounds.minY) / max(bounds.height, 1)
    }

    var hasLowerBodyThenUpperPeakReturn: Bool {
        guard points.count >= 8 else {
            return false
        }

        let lowerBodyLimit = bounds.minY + bounds.height * 0.62
        let upperPeakLimit = bounds.minY + bounds.height * 0.32
        var sawLowerBody = false

        for (index, point) in points.enumerated() where index >= max(1, points.count / 8) {
            if point.y >= lowerBodyLimit {
                sawLowerBody = true
            } else if sawLowerBody, point.y <= upperPeakLimit {
                return true
            }
        }

        return false
    }
}

private extension InkPoint {
    func clusterDistance(to other: InkPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
