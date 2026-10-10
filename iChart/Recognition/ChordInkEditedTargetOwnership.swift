import Foundation

/// Label-blind edit continuity. Kept separate from recognition: this policy
/// partitions existing strokes; it cannot guess a chord or create/delete ink.
/// The editor adapter must reset the state on chart/layout/coordinate changes.
struct ChordInkEditedTargetOwnership {
    struct Target: Equatable {
        let lane: Int
        let strokes: [InkStroke]
    }

    struct SourceStroke: Equatable, Hashable {
        let targetIndex: Int
        let strokeIndex: Int
    }

    struct Resolution {
        /// An exhaustive partition of input strokes, never synthesized ink.
        /// A mixed target can split only by the exact prior-owner evidence below.
        let sourceStrokes: [[SourceStroke]]
        var sourceTargetIndices: [[Int]] {
            sourceStrokes.map { Array(Set($0.map(\.targetIndex))).sorted() }
        }
        let requiresReview: Set<Int>
        let next: ChordInkEditedTargetOwnership
    }

    private struct UnionResolution {
        let sourceTargetIndices: [[Int]]
        let requiresReview: Set<Int>
        let next: ChordInkEditedTargetOwnership
    }

    private var references: [Target] = []
    private var unassignedKeys: Set<Key> = []

    /// Recognition-prepared creation offsets rebase when the earliest stroke
    /// is erased. Per-path points/relative times stay stable. Duplicate keys
    /// are ambiguous and never authorize an ownership change.
    private struct Key: Hashable {
        let points: [InkPoint]
        init(_ stroke: InkStroke) { points = stroke.points }
    }

    func resolving(_ proposed: [Target], visibleStrokes: [InkStroke]) -> Resolution {
        guard proposed.allSatisfy({ !$0.strokes.isEmpty }) else {
            return Resolution(sourceStrokes: proposed.indices.map { index in
                proposed[index].strokes.indices.map { SourceStroke(targetIndex: index, strokeIndex: $0) }
            }, requiresReview: Set(proposed.indices), next: .init())
        }
        let sources = separatingUnchangedNeighbors(proposed, visibleStrokes: visibleStrokes)
        let isolated = sources.map { group in
            Target(lane: proposed[group[0].targetIndex].lane,
                   strokes: group.map { proposed[$0.targetIndex].strokes[$0.strokeIndex] })
        }
        let result = resolvingWholeTargets(isolated, visibleStrokes: visibleStrokes)
        return Resolution(sourceStrokes: result.sourceTargetIndices.map { $0.flatMap { sources[$0] } },
                          requiresReview: result.requiresReview, next: result.next)
    }

    /// A root-sequence regroup after erasure can absorb an untouched neighbor.
    /// Restore its exact old strokes only when every input has a unique owner:
    /// one partially erased chord, complete neighbors, disjoint horizontal
    /// footprints, and new ink confined horizontally to the edited footprint
    /// with vertical overlap. Rewritten suffixes may be taller than before.
    /// Any unknown/overlapping owner, append-only input, or ambiguous new ink
    /// leaves the proposed group intact for review. No labels or scores enter.
    private func separatingUnchangedNeighbors(_ proposed: [Target], visibleStrokes: [InkStroke]) -> [[SourceStroke]] {
        let identity = proposed.indices.map { index in
            proposed[index].strokes.indices.map { SourceStroke(targetIndex: index, strokeIndex: $0) }
        }
        let visibleKeys = visibleStrokes.map(Key.init)
        let inputKeys = proposed.flatMap { $0.strokes.map(Key.init) }
        let referenceKeys = references.flatMap { $0.strokes.map(Key.init) }
        guard proposed.count <= 64, references.count <= 64,
              Set(visibleKeys).count == visibleKeys.count,
              Set(inputKeys).count == inputKeys.count,
              Set(referenceKeys).count == referenceKeys.count,
              Set(inputKeys).isSubset(of: Set(visibleKeys)) else { return identity }
        let present = Set(visibleKeys)
        let oldKeys = Set(referenceKeys).union(unassignedKeys)
        let retained = references.map { Set($0.strokes.map(Key.init)).intersection(present) }
        let bounds = references.map { InkBounds.enclosing($0.strokes.flatMap(\.points)) }
        var output: [[SourceStroke]] = []
        for (index, target) in proposed.enumerated() {
            let keys = Set(target.strokes.map(Key.init))
            let owners = references.indices.filter { !retained[$0].isDisjoint(with: keys) }
                .sorted { bounds[$0].minX < bounds[$1].minX }
            let edited = owners.filter { retained[$0].count < references[$0].strokes.count }
            guard owners.count > 1, edited.count == 1,
                  owners.allSatisfy({ references[$0].lane == target.lane && retained[$0].isSubset(of: keys) }),
                  zip(owners, owners.dropFirst()).allSatisfy({ bounds[$0].maxX < bounds[$1].minX }) else {
                output.append(identity[index]); continue
            }
            let edit = edited[0]
            let missing = references[edit].strokes.filter { !present.contains(Key($0)) }
            guard !missing.allSatisfy({ old in
                visibleStrokes.contains { $0.points.count > old.points.count && $0.points.starts(with: old.points) }
            }) else { output.append(identity[index]); continue }
            var partitions = Array(repeating: [SourceStroke](), count: owners.count)
            var ambiguous = false
            for (strokeIndex, stroke) in target.strokes.enumerated() {
                let key = Key(stroke)
                let knownOwner = owners.firstIndex { retained[$0].contains(key) }
                let owner: Int
                if let knownOwner { owner = knownOwner }
                else {
                    let strokeBounds = InkBounds.enclosing(stroke.points)
                    guard !oldKeys.contains(key), !stroke.points.isEmpty,
                          stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                          strokeBounds.minX >= bounds[edit].minX, strokeBounds.maxX <= bounds[edit].maxX,
                          strokeBounds.maxY >= bounds[edit].minY, strokeBounds.minY <= bounds[edit].maxY else {
                        ambiguous = true; break
                    }
                    owner = owners.firstIndex(of: edit)!
                }
                partitions[owner].append(SourceStroke(targetIndex: index, strokeIndex: strokeIndex))
            }
            output.append(contentsOf: ambiguous ? [identity[index]] : partitions)
        }
        return output.count <= 64 ? output : identity
    }

    private func resolvingWholeTargets(_ proposed: [Target], visibleStrokes: [InkStroke]) -> UnionResolution {
        let identity = proposed.indices.map { [$0] }
        guard proposed.count <= 64, references.count <= 64 else {
            return UnionResolution(sourceTargetIndices: identity, requiresReview: Set(proposed.indices), next: .init())
        }
        let keys = proposed.map { $0.strokes.map(Key.init) }
        let allKeys = keys.flatMap { $0 }
        let visibleKeys = visibleStrokes.map(Key.init)
        let validInk = proposed.allSatisfy { !$0.strokes.isEmpty }
            && visibleStrokes.allSatisfy { stroke in
                !stroke.points.isEmpty && stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            }
        guard validInk, Set(allKeys).count == allKeys.count,
              Set(visibleKeys).count == visibleKeys.count,
              Set(allKeys).isSubset(of: Set(visibleKeys)) else {
            // No guessed identity when two visible strokes look identical.
            return UnionResolution(sourceTargetIndices: identity, requiresReview: Set(proposed.indices), next: .init())
        }
        // A targeting omission is not an erasure. Compare to the authoritative
        // visible page input, including ink not assigned to a proposed target.
        let present = Set(visibleKeys)
        let oldKeys = Set(references.flatMap { $0.strokes.map(Key.init) }).union(unassignedKeys)
        var plans: [(reference: Target, retainedTargets: Set<Int>, candidates: Set<Int>, mayMerge: Bool)] = []
        for reference in references {
            let previous = Set(reference.strokes.map(Key.init))
            let retained = previous.intersection(present)
            guard !retained.isEmpty, retained.count < previous.count else { continue }
            // A pen-down path may grow after a preview snapshot. Appending
            // points to that same path is not evidence of an eraser edit.
            let missing = reference.strokes.filter { !present.contains(Key($0)) }
            if missing.allSatisfy({ old in
                visibleStrokes.contains { current in
                    current.points.count > old.points.count && current.points.starts(with: old.points)
                }
            }) { continue }
            let owners = Set(proposed.indices.filter { !Set(keys[$0]).isDisjoint(with: retained) })
            guard !owners.isEmpty else { continue }
            let footprint = InkBounds.enclosing(reference.strokes.flatMap(\.points))
            func isWithinFootprint(_ stroke: InkStroke) -> Bool {
                stroke.points.allSatisfy {
                    footprint.minX <= $0.x && $0.x <= footprint.maxX &&
                    footprint.minY <= $0.y && $0.y <= footprint.maxY
                }
            }
            let eligible = Set(proposed.indices.filter { index in
                proposed[index].lane == reference.lane &&
                proposed[index].strokes.enumerated().allSatisfy { offset, stroke in
                    let key = keys[index][offset]
                    return retained.contains(key) || (!oldKeys.contains(key) && isWithinFootprint(stroke))
                }
            })
            // Never pull a neighboring owner's ink out of a proposed target.
            let mayMerge = owners.isSubset(of: eligible)
            plans.append((reference, owners, mayMerge ? eligible : owners, mayMerge))
        }

        var claimed = Set<Int>()
        var output: [[Int]] = []
        var review = Set<Int>()
        var carried: [Target] = []
        for plan in plans {
            // Overlapping prior footprints/owners cannot decide intent. Leave
            // their targets separate and explicitly review all affected ink.
            let hasConflict = plans.contains { other in
                other.reference != plan.reference && !other.candidates.isDisjoint(with: plan.candidates)
            }
            let members = plan.candidates
            if hasConflict || !plan.mayMerge || !claimed.isDisjoint(with: members) {
                for member in members.sorted() where !claimed.contains(member) {
                    review.insert(output.count); output.append([member]); claimed.insert(member)
                }
            } else {
                review.insert(output.count); output.append(members.sorted()); claimed.formUnion(members)
            }
            carried.append(plan.reference)
        }
        for index in proposed.indices where !claimed.contains(index) { output.append([index]) }
        let ordered = output.enumerated().sorted { $0.element[0] < $1.element[0] }
        let groups = ordered.map(\.element)
        let sortedReview = Set(ordered.enumerated().compactMap { index, pair in review.contains(pair.offset) ? index : nil })
        var next = Self()
        next.unassignedKeys = unassignedKeys.intersection(present).union(present.subtracting(allKeys))
        // Retain a partially erased footprint across erase-only snapshots and
        // arbitrary pauses. A full erase releases it; undo restores normal
        // grouping. New targets outside that footprint remain independent.
        next.references = carried
        for (index, group) in groups.enumerated() where !sortedReview.contains(index) {
            guard let first = group.first else { continue }
            next.references.append(Target(lane: proposed[first].lane, strokes: group.flatMap { proposed[$0].strokes }))
        }
        return UnionResolution(sourceTargetIndices: groups, requiresReview: sortedReview, next: next)
    }
}
