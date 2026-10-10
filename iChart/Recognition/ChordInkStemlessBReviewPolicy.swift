import Foundation

/// Some writers omit the left stem of a B. Its two-bowl outline also reads
/// as a 3, and the broad one-stroke G heuristic can win at particular sizes.
/// That geometry is useful for explicit recovery, never for automatic B trust.
enum ChordInkStemlessBReviewPolicy {
    static func hasAmbiguousRoot(
        in result: ChordInkRecognitionResult,
        strokes: [InkStroke]
    ) -> Bool {
        guard let symbol = result.match?.symbol,
              symbol.kind == .rooted,
              symbol.root == .g || symbol.root == .d,
              let root = strokes.min(by: { $0.bounds.minX < $1.bounds.minX }),
              root.points.count >= 12,
              root.bounds.height >= 12,
              let first = root.points.first,
              let last = root.points.last else {
            return false
        }
        let width = max(root.bounds.width, 1)
        let height = max(root.bounds.height, 1)
        let aspect = width / height
        guard aspect >= 0.40, aspect <= 1.10,
              root.straightness <= 0.40,
              max(first.x, last.x) <= root.bounds.minX + width * 0.35,
              abs(first.y - last.y) >= height * 0.50 else {
            return false
        }
        // A separate overlapping stem is actual B/D construction evidence,
        // not the stemless ambiguity addressed here. Do not relabel it.
        let rootNeighbors = strokes.filter {
            $0 != root
                && $0.bounds.horizontalOverlap(with: root.bounds) > 0
                && $0.bounds.verticalOverlap(with: root.bounds)
                    >= min($0.bounds.height, height) * 0.50
        }
        guard rootNeighbors.isEmpty else { return false }

        let upperReach = root.points.filter { $0.y <= root.bounds.minY + height * 0.35 }
            .map(\.x).max() ?? root.bounds.minX
        let lowerReach = root.points.filter { $0.y >= root.bounds.minY + height * 0.58 }
            .map(\.x).max() ?? root.bounds.minX
        guard min(upperReach, lowerReach) >= root.bounds.minX + width * 0.75 else {
            return false
        }
        // Both outward lobes must surround a real inward waist. Prefix and
        // suffix maxima make this independent of drawing direction and O(n).
        var laterMaxima = [Double](repeating: -.infinity, count: root.points.count)
        var maximum = -Double.infinity
        for index in root.points.indices.reversed() {
            laterMaxima[index] = maximum
            maximum = max(maximum, root.points[index].x)
        }
        maximum = -Double.infinity
        for index in root.points.indices {
            let point = root.points[index]
            let y = (point.y - root.bounds.minY) / height
            if y >= 0.25, y <= 0.60,
               point.x >= root.bounds.minX + width * 0.30,
               min(maximum, laterMaxima[index]) - point.x >= width * 0.20 {
                return true
            }
            maximum = max(maximum, point.x)
        }
        return false
    }

    static func addingReviewSuggestions(
        to result: ChordInkRecognitionResult,
        strokes: [InkStroke]
    ) -> ChordInkRecognitionResult {
        guard hasAmbiguousRoot(in: result, strokes: strokes),
              ChordInkRecognitionPolicy.decision(for: result).action == .confirm else {
            return result
        }
        var augmented = result
        let excluded = Set(result.candidateScores.compactMap(\.displayText))
        var scores = Dictionary(
            result.reviewCandidateScores.compactMap { score in
                score.displayText.map { ($0, score) }
            },
            uniquingKeysWith: { $0.confidence >= $1.confidence ? $0 : $1 }
        )
        var rootAlternatives = Set<String>()
        for score in ChordInkRecognitionPolicy.rankedSupportedScores(for: result)
            + result.reviewCandidateScores {
            guard let text = score.displayText,
                  let match = ChordRecognitionCompendium.match(text),
                  match.symbol.root == .g || match.symbol.root == .d else {
                continue
            }
            // Retain the already-supported suffix and accidental exactly;
            // only the ambiguous root gets an explicit, review-only alternative.
            var symbol = match.symbol
            symbol.root = .b
            guard let alternate = ChordRecognitionCompendium.match(symbol.displayText),
                  !excluded.contains(alternate.displayText) else {
                continue
            }
            let alternateScore = ChordInkCandidateScore(
                text: alternate.displayText,
                displayText: alternate.displayText,
                confidence: score.confidence - 0.25
            )
            rootAlternatives.insert(alternate.displayText)
            if scores[alternate.displayText].map({ $0.confidence >= alternateScore.confidence }) != true {
                scores[alternate.displayText] = alternateScore
            }
        }
        let orderedScores = scores.values.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return ($0.displayText ?? $0.text) < ($1.displayText ?? $1.text)
        }
        let strongestRootAlternative = orderedScores.first {
            $0.displayText.map { rootAlternatives.contains($0) } == true
        }
        var retainedScores = Array(orderedScores.prefix(4))
        if let strongestRootAlternative,
           !retainedScores.contains(strongestRootAlternative) {
            retainedScores = Array(orderedScores.prefix(3)) + [strongestRootAlternative]
        }
        augmented.reviewCandidateScores = retainedScores
        // Reserve one of the three visible review choices for this actual
        // root ambiguity instead of hiding it behind same-root near-duplicates.
        augmented.reviewRootAlternatives = strongestRootAlternative?.displayText.map { [$0] } ?? []
        return augmented
    }
}
