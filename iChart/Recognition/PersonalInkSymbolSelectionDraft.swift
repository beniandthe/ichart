import Foundation

/// Local, label-blind editing state for optional teaching. It does not change
/// an example, a model, or a chart. Regrouping invalidates the affected labels
/// so a stale choice cannot silently become supervision for different ink.
struct PersonalInkSymbolSelectionDraft {
    let review: PersonalInkSymbolTeachingReview
    private(set) var groups: [[Int]]
    private(set) var labels: [String?]

    init(review: PersonalInkSymbolTeachingReview) {
        self.review = review
        groups = review.pieces.map(\.originalStrokeIndexes)
        labels = Array(repeating: nil, count: groups.count)
    }

    var selectedSymbolCount: Int { labels.compactMap { $0 }.count }

    var unassignedStrokeIndexes: [Int] {
        let assigned = Set(groups.flatMap { $0 })
        return review.source.recognitionInput.indices.filter { !assigned.contains($0) }
    }

    mutating func setLabel(_ label: String?, forPiece index: Int) throws {
        guard groups.indices.contains(index),
              label.map(PersonalInkProfile.glyphLabels.contains) ?? true else {
            throw PersonalInkSymbolTeachingReview.Failure.invalidSelection
        }
        labels[index] = label
    }

    /// Merge/split by assigning complete original strokes to one piece. Stroke
    /// transfers are explicit in the selection UI. Leftovers from the edited
    /// piece become unassigned; remainders of other pieces stay visible and
    /// lose their old labels. No heuristic decides whether this is one glyph.
    mutating func replacePiece(at index: Int?, withStrokeIndexes indexes: [Int]) throws {
        guard index.map(groups.indices.contains) ?? true, !indexes.isEmpty,
              indexes.allSatisfy({ review.source.recognitionInput.indices.contains($0) }),
              Set(indexes).count == indexes.count else {
            throw PersonalInkSymbolTeachingReview.Failure.invalidSelection
        }
        let ordered = indexes.sorted()
        if let index, groups[index] == ordered { return }
        let selected = Set(ordered)
        var newGroups: [[Int]] = []
        var newLabels: [String?] = []
        for oldIndex in groups.indices {
            if oldIndex == index {
                newGroups.append(ordered); newLabels.append(nil)
            } else {
                let remainder = groups[oldIndex].filter { !selected.contains($0) }
                if !remainder.isEmpty {
                    newGroups.append(remainder)
                    newLabels.append(remainder == groups[oldIndex] ? labels[oldIndex] : nil)
                }
            }
        }
        if index == nil { newGroups.append(ordered); newLabels.append(nil) }
        // Validate before publishing any of the local edit; capacity or a bad
        // selection cannot leave partially changed groups/labels behind.
        _ = try review.selectingOriginalGroups(newGroups)
        groups = newGroups
        labels = newLabels
    }

    mutating func removePiece(at index: Int) throws {
        guard groups.indices.contains(index) else {
            throw PersonalInkSymbolTeachingReview.Failure.invalidSelection
        }
        groups.remove(at: index)
        labels.remove(at: index)
    }

    func makeReview() throws -> PersonalInkSymbolTeachingReview {
        try review.selectingOriginalGroups(groups)
    }
}
