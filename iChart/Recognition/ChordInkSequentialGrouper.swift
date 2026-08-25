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
    private static let rootTexts: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
    private static let suffixAndModifierTexts: Set<String> = [
        "#", "b", "△", "°", "ø", "•", "+", "m", "a", "l", "t",
        "-", "s", "u", "6", "7", "9", "(", ")", "1", "3", "5", "/"
    ]

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
                candidates: candidates,
                rootEvidence: rootEvidence(in: candidates, bounds: localCluster.bounds),
                isSlashSeparator: isSlashSeparator(candidates: candidates, cluster: localCluster.cluster)
            )
        }

        var groups = [WorkingGroup]()
        var currentGroup: WorkingGroup?
        var previousGlyphWasSlashSeparator = false

        for glyph in glyphs {
            if let rootEvidence = glyph.rootEvidence,
               currentGroup != nil,
               !previousGlyphWasSlashSeparator {
                groups.append(currentGroup!)
                currentGroup = WorkingGroup(
                    glyph: glyph,
                    anchorReason: .rootStart,
                    rootText: rootEvidence.text,
                    rootConfidence: rootEvidence.confidence
                )
            } else if currentGroup != nil {
                currentGroup?.append(glyph)
            } else if let rootEvidence = glyph.rootEvidence {
                currentGroup = WorkingGroup(
                    glyph: glyph,
                    anchorReason: .rootStart,
                    rootText: rootEvidence.text,
                    rootConfidence: rootEvidence.confidence
                )
            }

            previousGlyphWasSlashSeparator = glyph.isSlashSeparator
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

    private func rootEvidence(
        in candidates: [GlyphCandidate],
        bounds: InkBounds
    ) -> RootEvidence? {
        guard bounds.width >= 8,
              bounds.height >= 16,
              bounds.recognitionArea >= 180,
              let rootCandidate = candidates.first(where: { candidate in
                Self.rootTexts.contains(candidate.text) && candidate.confidence >= 0.70
              }) else {
            return nil
        }

        if let bestCandidate = candidates.first,
           Self.suffixAndModifierTexts.contains(bestCandidate.text) {
            return nil
        }

        let bestConfidence = candidates.first?.confidence ?? 0
        guard rootCandidate.confidence + 0.06 >= bestConfidence else {
            return nil
        }

        if let suffixCandidate = candidates.first(where: { candidate in
            Self.suffixAndModifierTexts.contains(candidate.text)
        }),
           suffixCandidate.confidence >= rootCandidate.confidence + 0.10 {
            return nil
        }

        return RootEvidence(
            text: rootCandidate.text,
            confidence: rootCandidate.confidence
        )
    }

    private func isSlashSeparator(candidates: [GlyphCandidate], cluster: InkCluster) -> Bool {
        if candidates.contains(where: { $0.text == "/" && $0.confidence >= 0.60 }) {
            return true
        }

        return cluster.strokes.count == 1
            && cluster.strokes.first?.isLooseSlashBassSeparatorCandidate == true
    }
}

private struct SequentialGlyph: Hashable {
    var strokeIndices: [Int]
    var cluster: InkCluster
    var candidates: [GlyphCandidate]
    var rootEvidence: RootEvidence?
    var isSlashSeparator: Bool
}

private struct RootEvidence: Hashable {
    var text: String
    var confidence: Double
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
