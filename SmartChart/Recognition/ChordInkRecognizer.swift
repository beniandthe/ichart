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
        maxGlyphCandidatesPerCluster: Int = 5,
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
        let chordCandidates = candidateComposer.compose(glyphCandidates: glyphCandidateGroups)
        let rawCandidates = chordCandidates.map(\.text)
        let proposedMatch = ChordRecognitionCompendium.match(candidates: rawCandidates)
        let confidence = proposedMatch.flatMap { match in
            chordCandidates.first(where: { $0.text == match.rawInput })?.confidence
        } ?? 0
        let match = confidence >= minimumAcceptedCandidateConfidence ? proposedMatch : nil
        let acceptedConfidence = match == nil ? 0 : confidence

        return ChordInkRecognitionResult(
            rawCandidates: rawCandidates,
            glyphCandidates: glyphCandidateGroups,
            match: match,
            confidence: acceptedConfidence
        )
    }
}
