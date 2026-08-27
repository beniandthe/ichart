import Foundation

struct ChordInkSequentialGroup: Hashable {
    var strokeIndices: [Int]
    var bounds: InkBounds
    var anchorReason: ChordInkSequentialGroupAnchorReason
    var rootText: String?
    var rootConfidence: Double?
}

enum ChordInkSequentialGroupAnchorReason: Hashable {
    case rootStart
    case fallbackGap
}

struct ChordInkSequentialGrouper {
    var clusterer: StrokeClusterer
    var glyphRecognizer: GestureTemplateRecognizer
    var templates: [GestureTemplate]

    init(
        clusterer: StrokeClusterer = StrokeClusterer(),
        glyphRecognizer: GestureTemplateRecognizer = GestureTemplateRecognizer(),
        templates: [GestureTemplate] = ChordGlyphTemplateLibrary.initialTemplates
    ) {
        self.clusterer = clusterer
        self.glyphRecognizer = glyphRecognizer
        self.templates = templates
    }

    func groups(for indexedStrokes: [(index: Int, stroke: InkStroke)]) -> [ChordInkSequentialGroup] {
        let orderedStrokes = indexedStrokes
            .filter { _, stroke in
                stroke.bounds.width >= 1 || stroke.bounds.height >= 1
            }
            .sorted { lhs, rhs in
                if lhs.stroke.bounds.minX == rhs.stroke.bounds.minX {
                    return lhs.index < rhs.index
                }

                return lhs.stroke.bounds.minX < rhs.stroke.bounds.minX
            }
        guard !orderedStrokes.isEmpty else {
            return []
        }

        let clusteredStrokes = clusterer.indexedClusters(orderedStrokes.map(\.stroke))
        let localClusters = splitFusedSequentialRootClusters(
            clusteredStrokes,
            orderedStrokes: orderedStrokes
        )
        let glyphs = localClusters.compactMap { localCluster -> SequentialGlyph? in
            sequentialGlyph(for: localCluster, orderedStrokes: orderedStrokes)
        }
        var groups = [WorkingGroup]()
        var currentGroup: WorkingGroup?
        var previousGlyphWasSlashSeparator = false

        var glyphIndex = glyphs.startIndex
        while glyphIndex < glyphs.endIndex {
            let glyph = glyphs[glyphIndex]
            let rootStartEvidence = ChordInkSequentialRootStartDetector.evidence(
                in: glyph.candidates,
                cluster: glyph.cluster,
                currentGroupBounds: currentGroup?.bounds,
                previousGlyphWasSlashSeparator: previousGlyphWasSlashSeparator
            )

            if let rootStartEvidence,
               currentGroup != nil {
                groups.append(currentGroup!)
                currentGroup = WorkingGroup(
                    glyph: glyph,
                    anchorReason: .rootStart,
                    rootText: rootStartEvidence.text,
                    rootConfidence: rootStartEvidence.confidence
                )
            } else if currentGroup != nil {
                if let group = currentGroup,
                   let constructionStart = rootConstructionStart(
                    at: glyphIndex,
                    in: glyphs,
                    currentGroupBounds: group.bounds,
                    previousGlyphWasSlashSeparator: previousGlyphWasSlashSeparator
                   ) {
                    groups.append(group)
                    currentGroup = WorkingGroup(
                        glyph: constructionStart.glyph,
                        anchorReason: .rootStart,
                        rootText: constructionStart.evidence.text,
                        rootConfidence: constructionStart.evidence.confidence
                    )
                    previousGlyphWasSlashSeparator = constructionStart.glyph.isSlashSeparator
                    glyphIndex = constructionStart.nextIndex
                    continue
                } else {
                    currentGroup?.append(glyph)
                }
            } else if let rootStartEvidence {
                currentGroup = WorkingGroup(
                    glyph: glyph,
                    anchorReason: .rootStart,
                    rootText: rootStartEvidence.text,
                    rootConfidence: rootStartEvidence.confidence
                )
            }

            previousGlyphWasSlashSeparator = glyph.isSlashSeparator
            glyphIndex = glyphs.index(after: glyphIndex)
        }

        if let currentGroup {
            groups.append(currentGroup)
        }

        return groups
            .map { group in
                ChordInkSequentialGroup(
                    strokeIndices: group.strokeIndices,
                    bounds: group.bounds,
                    anchorReason: group.anchorReason,
                    rootText: group.rootText,
                    rootConfidence: group.rootConfidence
                )
            }
            .filter { group in
                !group.strokeIndices.isEmpty
                    && (group.bounds.width >= 4 || group.bounds.height >= 4)
            }
    }

    private func sequentialGlyph(
        for localCluster: IndexedInkCluster,
        orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> SequentialGlyph? {
        let sourceIndexedStrokes = localCluster.originalIndexes.compactMap { localIndex -> SequentialIndexedStroke? in
            guard orderedStrokes.indices.contains(localIndex) else {
                return nil
            }

            let orderedStroke = orderedStrokes[localIndex]
            return SequentialIndexedStroke(
                index: orderedStroke.index,
                stroke: orderedStroke.stroke
            )
        }
        let sourceIndexes = sourceIndexedStrokes.map(\.index).sorted()
        guard !sourceIndexes.isEmpty else {
            return nil
        }

        let sourceOrderCluster = InkCluster(
            strokes: sourceIndexedStrokes
                .sorted { lhs, rhs in lhs.index < rhs.index }
                .map(\.stroke),
            bounds: localCluster.cluster.bounds
        )
        let candidates = glyphRecognizer.rankedCandidates(
            for: sourceOrderCluster,
            templates: templates,
            limit: 8
        )
        return SequentialGlyph(
            strokeIndices: sourceIndexes,
            indexedStrokes: sourceIndexedStrokes,
            cluster: sourceOrderCluster,
            candidates: candidates
        )
    }

    private func splitFusedSequentialRootClusters(
        _ localClusters: [IndexedInkCluster],
        orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [IndexedInkCluster] {
        localClusters.flatMap { localCluster in
            recursivelySplitFusedSequentialRootCluster(
                localCluster,
                orderedStrokes: orderedStrokes
            )
        }
    }

    private func recursivelySplitFusedSequentialRootCluster(
        _ localCluster: IndexedInkCluster,
        orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [IndexedInkCluster] {
        guard let splitClusters = splitFusedSequentialRootCluster(
            localCluster,
            orderedStrokes: orderedStrokes
        ) else {
            return [localCluster]
        }

        return splitClusters.flatMap { splitCluster in
            recursivelySplitFusedSequentialRootCluster(
                splitCluster,
                orderedStrokes: orderedStrokes
            )
        }
    }

    private func splitFusedSequentialRootCluster(
        _ localCluster: IndexedInkCluster,
        orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [IndexedInkCluster]? {
        let orderedPairs = localCluster.originalIndexes.compactMap { localIndex -> (localIndex: Int, stroke: InkStroke)? in
            guard orderedStrokes.indices.contains(localIndex) else {
                return nil
            }

            return (localIndex: localIndex, stroke: orderedStrokes[localIndex].stroke)
        }
            .sorted { lhs, rhs in
                if lhs.stroke.bounds.minX == rhs.stroke.bounds.minX {
                    return lhs.localIndex < rhs.localIndex
                }

                return lhs.stroke.bounds.minX < rhs.stroke.bounds.minX
            }

        guard orderedPairs.count >= 3 else {
            return nil
        }

        for splitIndex in orderedPairs.indices.dropFirst() {
            let leftCluster = indexedCluster(from: Array(orderedPairs[..<splitIndex]))
            let rightCluster = indexedCluster(from: Array(orderedPairs[splitIndex...]))

            guard let leftGlyph = sequentialGlyph(for: leftCluster, orderedStrokes: orderedStrokes),
                  let rightGlyph = sequentialGlyph(for: rightCluster, orderedStrokes: orderedStrokes),
                  hasFusedSequentialRootBoundary(left: leftGlyph, right: rightGlyph) else {
                continue
            }

            return [leftCluster, rightCluster]
        }

        return nil
    }

    private func indexedCluster(
        from pairs: [(localIndex: Int, stroke: InkStroke)]
    ) -> IndexedInkCluster {
        IndexedInkCluster(
            cluster: InkCluster(strokes: pairs.map(\.stroke)),
            originalIndexes: pairs.map(\.localIndex)
        )
    }

    private func hasFusedSequentialRootBoundary(
        left: SequentialGlyph,
        right: SequentialGlyph
    ) -> Bool {
        guard ChordInkSequentialRootStartDetector.evidence(
            in: left.candidates,
            cluster: left.cluster,
            currentGroupBounds: nil,
            previousGlyphWasSlashSeparator: false
        ) != nil else {
            return false
        }

        guard right.canBeginDetachedRootConstruction(from: left.cluster.bounds),
              ChordInkSequentialRootStartDetector.evidence(
                in: right.candidates,
                cluster: right.cluster,
                currentGroupBounds: left.cluster.bounds,
                previousGlyphWasSlashSeparator: false
              ) != nil else {
            return false
        }

        return true
    }

    private func rootConstructionStart(
        at index: Int,
        in glyphs: [SequentialGlyph],
        currentGroupBounds: InkBounds,
        previousGlyphWasSlashSeparator: Bool
    ) -> (glyph: SequentialGlyph, evidence: ChordInkSequentialRootStartEvidence, nextIndex: Int)? {
        guard !previousGlyphWasSlashSeparator,
              glyphs.indices.contains(index),
              glyphs[index].canBeginDetachedRootConstruction(from: currentGroupBounds) else {
            return nil
        }

        let upperBound = min(glyphs.endIndex, index + 3)
        var constructionGlyphs = [SequentialGlyph]()
        var scanIndex = index

        while scanIndex < upperBound {
            let glyph = glyphs[scanIndex]
            if scanIndex > index,
               !glyph.canContinueDetachedRootConstruction(after: constructionGlyphs.last) {
                break
            }

            constructionGlyphs.append(glyph)

            if constructionGlyphs.count >= 2 {
                let combinedGlyph = combinedGlyph(from: constructionGlyphs)
                if let evidence = ChordInkSequentialRootStartDetector.evidence(
                    in: combinedGlyph.candidates,
                    cluster: combinedGlyph.cluster,
                    currentGroupBounds: currentGroupBounds,
                    previousGlyphWasSlashSeparator: false
                ) {
                    return (
                        glyph: combinedGlyph,
                        evidence: evidence,
                        nextIndex: glyphs.index(after: scanIndex)
                    )
                }
            }

            scanIndex = glyphs.index(after: scanIndex)
        }

        return nil
    }

    private func combinedGlyph(from glyphs: [SequentialGlyph]) -> SequentialGlyph {
        let indexedStrokes = glyphs
            .flatMap(\.indexedStrokes)
            .sorted { lhs, rhs in lhs.index < rhs.index }
        let cluster = InkCluster(
            strokes: indexedStrokes.map(\.stroke),
            bounds: InkBounds.enclosing(glyphs.map(\.cluster.bounds))
        )
        let candidates = glyphRecognizer.rankedCandidates(
            for: cluster,
            templates: templates,
            limit: 8
        )

        return SequentialGlyph(
            strokeIndices: indexedStrokes.map(\.index).sorted(),
            indexedStrokes: indexedStrokes,
            cluster: cluster,
            candidates: candidates
        )
    }

}

struct ChordInkSequentialRootStartEvidence: Hashable {
    var text: String
    var confidence: Double
}

enum ChordInkSequentialRootStartDetector {
    private static let rootTexts: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
    private static let initialRootStartMinimumConfidence = 0.70
    private static let detachedRootStartMinimumConfidence = 0.50
    private static let rootSizedModifierLookalikeMinimumConfidence = 0.90
    private static let rootSizedModifierLookalikeMaximumLag = 0.08
    private static let suffixAndModifierTexts: Set<String> = [
        "#", "b", "△", "°", "ø", "•", "+", "m", "a", "l", "t",
        "-", "s", "u", "6", "7", "9", "(", ")", "1", "3", "5", "/"
    ]
    private static let rootSizedModifierLookalikeOverrideTexts: Set<String> = ["b", "m", "-", "6"]
    private static let closeBoundarySymbolicSuffixTexts: Set<String> = ["△", "°", "ø", "•", "+"]

    static func evidence(
        in candidates: [GlyphCandidate],
        cluster: InkCluster,
        currentGroupBounds: InkBounds?,
        previousGlyphWasSlashSeparator: Bool
    ) -> ChordInkSequentialRootStartEvidence? {
        let minimumRootConfidence = currentGroupBounds == nil
            ? initialRootStartMinimumConfidence
            : detachedRootStartMinimumConfidence

        guard !previousGlyphWasSlashSeparator,
              cluster.bounds.width >= 8,
              cluster.bounds.height >= 16,
              cluster.bounds.recognitionArea >= 180,
              let rootCandidate = candidates.first(where: { candidate in
                rootTexts.contains(candidate.text) && candidate.confidence >= minimumRootConfidence
              }) else {
            return nil
        }

        let bestCandidate = candidates.first
        let bestConfidence = bestCandidate?.confidence ?? 0
        let suffixLeads = bestCandidate
            .map { suffixAndModifierTexts.contains($0.text) && $0.text != rootCandidate.text } ?? false
        let suffixLeadGap = bestConfidence - rootCandidate.confidence
        let hasRootSizedModifierLookalikeOverride = Self.hasRootSizedModifierLookalikeOverride(
            rootCandidate: rootCandidate,
            bestCandidate: bestCandidate,
            cluster: cluster,
            currentGroupBounds: currentGroupBounds
        )

        if let currentGroupBounds {
            let usesStrictBoundary = isDetachedRootSizedGlyph(cluster.bounds, from: currentGroupBounds)
            let usesCloseBoundary = !usesStrictBoundary
                && isRootSequenceBoundarySizedGlyph(cluster.bounds, from: currentGroupBounds)
            guard usesStrictBoundary || usesCloseBoundary else {
                return nil
            }

            if usesCloseBoundary,
               hasCloseBoundarySymbolicSuffixPressure(
                in: candidates,
                rootCandidate: rootCandidate
               ) {
                return nil
            }

            if suffixLeads,
               !hasRootSizedModifierLookalikeOverride,
               (rootCandidate.source != .heuristic || suffixLeadGap >= 0.04) {
                return nil
            }
        } else if suffixLeads {
            guard hasRootSizedModifierLookalikeOverride else {
                return nil
            }
        }

        let maximumLag = hasRootSizedModifierLookalikeOverride
            ? rootSizedModifierLookalikeMaximumLag
            : 0.06
        guard rootCandidate.confidence + maximumLag >= bestConfidence else {
            return nil
        }

        if let suffixCandidate = candidates.first(where: { candidate in
            suffixAndModifierTexts.contains(candidate.text)
        }),
           suffixCandidate.confidence >= rootCandidate.confidence + 0.10,
           !hasRootSizedModifierLookalikeOverride {
            return nil
        }

        return ChordInkSequentialRootStartEvidence(
            text: rootCandidate.text,
            confidence: rootCandidate.confidence
        )
    }

    private static func hasCloseBoundarySymbolicSuffixPressure(
        in candidates: [GlyphCandidate],
        rootCandidate: GlyphCandidate
    ) -> Bool {
        candidates.contains { candidate in
            closeBoundarySymbolicSuffixTexts.contains(candidate.text)
                && candidate.confidence >= 0.45
                && candidate.confidence + 0.25 >= rootCandidate.confidence
        }
    }

    static func isDetachedRootSizedGlyph(
        _ bounds: InkBounds,
        from currentGroupBounds: InkBounds
    ) -> Bool {
        isRootSequenceBoundarySizedGlyph(
            bounds,
            from: currentGroupBounds,
            minimumHorizontalGap: 16,
            minimumCenterAdvance: 18,
            heightRatioFloor: 0.55,
            widthRatioFloor: 0.18,
            heightGapScale: 0.30,
            widthAdvanceScale: 0.45
        )
    }

    static func isRootSequenceBoundarySizedGlyph(
        _ bounds: InkBounds,
        from currentGroupBounds: InkBounds
    ) -> Bool {
        isRootSequenceBoundarySizedGlyph(
            bounds,
            from: currentGroupBounds,
            minimumHorizontalGap: 10,
            minimumCenterAdvance: 14,
            heightRatioFloor: 0.55,
            widthRatioFloor: 0.18,
            heightGapScale: 0.22,
            widthAdvanceScale: 0.35
        )
    }

    private static func isRootSequenceBoundarySizedGlyph(
        _ bounds: InkBounds,
        from currentGroupBounds: InkBounds,
        minimumHorizontalGap: Double,
        minimumCenterAdvance: Double,
        heightRatioFloor: Double,
        widthRatioFloor: Double,
        heightGapScale: Double,
        widthAdvanceScale: Double
    ) -> Bool {
        let horizontalGap = currentGroupBounds.horizontalGap(to: bounds)
        let referenceHeight = max(currentGroupBounds.height, bounds.height, 1)
        let referenceWidth = max(currentGroupBounds.width, bounds.width, 1)
        let centerAdvance = bounds.recognitionMidX - currentGroupBounds.recognitionMidX
        let heightRatio = bounds.height / referenceHeight
        let widthRatio = bounds.width / referenceWidth
        let rootSized = heightRatio >= heightRatioFloor && widthRatio >= widthRatioFloor

        return rootSized
            && horizontalGap >= max(minimumHorizontalGap, referenceHeight * heightGapScale)
            && centerAdvance >= max(minimumCenterAdvance, referenceWidth * widthAdvanceScale)
    }

    private static func isInitialRootSizedModifierLookalike(_ bounds: InkBounds) -> Bool {
        bounds.width >= 18
            && bounds.height >= 18
            && bounds.recognitionArea >= 360
    }

    private static func hasRootSizedModifierLookalikeOverride(
        rootCandidate: GlyphCandidate,
        bestCandidate: GlyphCandidate?,
        cluster: InkCluster,
        currentGroupBounds: InkBounds?
    ) -> Bool {
        guard let bestCandidate,
              bestCandidate.text != rootCandidate.text,
              bestCandidate.confidence > rootCandidate.confidence,
              rootSizedModifierLookalikeOverrideTexts.contains(bestCandidate.text),
              rootCandidate.source == .heuristic,
              rootCandidate.confidence >= rootSizedModifierLookalikeMinimumConfidence,
              rootCandidate.confidence + rootSizedModifierLookalikeMaximumLag >= bestCandidate.confidence else {
            return false
        }

        if let currentGroupBounds {
            return isRootSequenceBoundarySizedGlyph(cluster.bounds, from: currentGroupBounds)
        }

        return isInitialRootSizedModifierLookalike(cluster.bounds)
    }
}

private struct SequentialIndexedStroke: Hashable {
    var index: Int
    var stroke: InkStroke
}

private struct SequentialGlyph: Hashable {
    var strokeIndices: [Int]
    var indexedStrokes: [SequentialIndexedStroke]
    var cluster: InkCluster
    var candidates: [GlyphCandidate]
    var isSlashSeparator: Bool {
        if candidates.contains(where: { $0.text == "/" && $0.confidence >= 0.60 }) {
            return true
        }

        return cluster.strokes.count == 1
            && cluster.strokes.first?.isLooseSlashBassSeparatorCandidate == true
    }

    func canBeginDetachedRootConstruction(from currentGroupBounds: InkBounds) -> Bool {
        guard !isSlashSeparator else {
            return false
        }

        let bounds = cluster.bounds
        let referenceHeight = max(currentGroupBounds.height, bounds.height, 1)
        let referenceWidth = max(currentGroupBounds.width, bounds.width, 1)
        let horizontalGap = currentGroupBounds.horizontalGap(to: bounds)
        let centerAdvance = bounds.recognitionMidX - currentGroupBounds.recognitionMidX

        guard horizontalGap >= max(10, referenceHeight * 0.22),
              centerAdvance >= max(14, referenceWidth * 0.35),
              bounds.height >= 12,
              bounds.recognitionArea >= 18 else {
            return false
        }

        return hasRootConstructionFragment || hasAmbiguousRootPressure
    }

    func canContinueDetachedRootConstruction(after previousGlyph: SequentialGlyph?) -> Bool {
        guard let previousGlyph,
              !isSlashSeparator else {
            return false
        }

        let previousBounds = previousGlyph.cluster.bounds
        let bounds = cluster.bounds
        let combinedBounds = InkBounds.enclosing([previousBounds, bounds])
        let horizontalGap = previousBounds.horizontalGap(to: bounds)
        let verticalMiss = previousBounds.verticalMiss(to: bounds)
        let horizontalOverlap = previousBounds.horizontalOverlap(with: bounds)
        let narrowerWidth = max(min(previousBounds.width, bounds.width), 1)

        return combinedBounds.width <= 58
            && combinedBounds.height <= 64
            && verticalMiss <= max(8, combinedBounds.height * 0.28)
            && (horizontalGap <= max(8, combinedBounds.height * 0.16)
                || horizontalOverlap >= narrowerWidth * 0.25)
            && (hasRootConstructionFragment || hasAmbiguousRootPressure)
    }

    private var hasRootConstructionFragment: Bool {
        hasRootConstructionVerticalStem
            || hasRootConstructionBody
            || hasRootConstructionBar
    }

    private var hasRootConstructionBar: Bool {
        cluster.strokes.contains { stroke in
            stroke.bounds.width >= 5
                && stroke.aspectRatio >= 1.6
                && stroke.straightness >= 0.50
                && stroke.horizontalAngleMagnitude <= 45
        }
    }

    private var hasRootConstructionVerticalStem: Bool {
        cluster.strokes.contains { stroke in
            stroke.bounds.height >= 14
                && stroke.bounds.height / max(stroke.bounds.width, 1) >= 1.90
                && stroke.straightness >= 0.50
                && abs(abs(stroke.angleDegrees) - 90) <= 32
        }
    }

    private var hasRootConstructionBody: Bool {
        cluster.bounds.height >= 14
            && cluster.bounds.width >= 8
            && cluster.bounds.recognitionArea >= 140
    }

    private var hasAmbiguousRootPressure: Bool {
        let rootCandidates = candidates.filter { candidate in
            ["A", "B", "C", "D", "E", "F", "G"].contains(candidate.text)
        }
        guard let bestRootConfidence = rootCandidates.map(\.confidence).max(),
              bestRootConfidence >= 0.46 else {
            return false
        }

        let bestCandidateConfidence = candidates.first?.confidence ?? 0
        return bestRootConfidence + 0.10 >= bestCandidateConfidence
    }
}

private struct WorkingGroup: Hashable {
    var strokeIndices: [Int]
    var bounds: InkBounds
    var anchorReason: ChordInkSequentialGroupAnchorReason
    var rootText: String?
    var rootConfidence: Double?

    init(
        glyph: SequentialGlyph,
        anchorReason: ChordInkSequentialGroupAnchorReason,
        rootText: String?,
        rootConfidence: Double?
    ) {
        strokeIndices = glyph.strokeIndices
        bounds = glyph.cluster.bounds
        self.anchorReason = anchorReason
        self.rootText = rootText
        self.rootConfidence = rootConfidence
    }

    mutating func append(_ glyph: SequentialGlyph) {
        strokeIndices.append(contentsOf: glyph.strokeIndices)
        bounds = bounds.union(glyph.cluster.bounds)
    }
}
