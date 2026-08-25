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

        let localClusters = clusterer.indexedClusters(orderedStrokes.map(\.stroke))
        let glyphs = localClusters.compactMap { localCluster -> SequentialGlyph? in
            let sourceIndexes = localCluster.originalIndexes.compactMap { localIndex -> Int? in
                guard orderedStrokes.indices.contains(localIndex) else {
                    return nil
                }

                return orderedStrokes[localIndex].index
            }
            guard !sourceIndexes.isEmpty else {
                return nil
            }

            let candidates = glyphRecognizer.rankedCandidates(
                for: localCluster.cluster,
                templates: templates,
                limit: 8
            )
            return SequentialGlyph(
                strokeIndices: sourceIndexes,
                cluster: localCluster.cluster,
                candidates: candidates
            )
        }
        let roleContext = ChordInkTheoryRoleContext(
            glyphCandidateGroups: glyphs.map(\.candidates),
            clusters: glyphs.map(\.cluster)
        )

        var groups = [WorkingGroup]()
        var currentGroup: WorkingGroup?

        for (glyphIndex, glyph) in glyphs.enumerated() {
            let roleEvidence = roleContext[glyphIndex]
            if roleEvidence?.opensChordGroup == true,
               currentGroup != nil {
                groups.append(currentGroup!)
                currentGroup = WorkingGroup(
                    glyph: glyph,
                    anchorReason: .rootStart,
                    rootText: roleEvidence?.text,
                    rootConfidence: roleEvidence?.confidence
                )
            } else if roleEvidence?.opensChordGroup == true {
                currentGroup = WorkingGroup(
                    glyph: glyph,
                    anchorReason: .rootStart,
                    rootText: roleEvidence?.text,
                    rootConfidence: roleEvidence?.confidence
                )
            } else if currentGroup != nil {
                currentGroup?.append(glyph)
            }
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

}

private struct SequentialGlyph: Hashable {
    var strokeIndices: [Int]
    var cluster: InkCluster
    var candidates: [GlyphCandidate]
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
