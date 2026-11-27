#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// A completed preparation pass may still describe an unchanged leading part
/// of live writing. This proof grants partial processing only: it never makes
/// an older pass a complete census of newer ink or authorizes clearing it.
@MainActor
enum ChordInkAutomaticSourcePrefixPolicy {
    static func hasIdenticalOrderedSource(snapshot: PKDrawing, current: PKDrawing) -> Bool {
        snapshot.strokes.count == current.strokes.count
            && (snapshot.strokes.isEmpty
                || unchangedLeadingStrokeCount(snapshot: snapshot, current: current) == snapshot.strokes.count)
    }

    static func unchangedLeadingStrokeCount(snapshot: PKDrawing, current: PKDrawing) -> Int? {
        let earlier = snapshot.strokes
        let live = current.strokes
        guard !earlier.isEmpty, live.count >= earlier.count else { return nil }
        for index in earlier.indices {
            guard hasIdenticalSource(earlier[index], live[index]) else {
                // PencilKit may extend the last captured stroke while its
                // earlier neighbors are already complete. An erase/reorder
                // or edit earlier in the snapshot invalidates this proof.
                return index == earlier.count - 1 && index > 0 ? index : nil
            }
        }
        return earlier.count
    }

    private static func hasIdenticalSource(_ expected: PKStroke, _ current: PKStroke) -> Bool {
        guard expected.randomSeed == current.randomSeed, expected.transform == current.transform,
              expected.path.creationDate == current.path.creationDate,
              expected.path.count == current.path.count else { return false }
        switch (expected.mask, current.mask) {
        case (nil, nil): break
        case (let prior?, let live?):
            guard CFEqual(prior.cgPath, live.cgPath) else { return false }
        default: return false
        }
        return zip(expected.path, current.path).allSatisfy { prior, live in
            guard prior.location == live.location, prior.timeOffset == live.timeOffset,
                  prior.size == live.size, prior.force == live.force, prior.opacity == live.opacity,
                  prior.azimuth == live.azimuth, prior.altitude == live.altitude,
                  prior.secondaryScale == live.secondaryScale else { return false }
            if #available(iOS 26.0, *) { return prior.threshold == live.threshold }
            return true
        }
    }

    static func containsTargetDrawing(_ data: Data, in prefix: PKDrawing) -> Bool {
        guard let target = try? PKDrawing(data: data), !target.strokes.isEmpty else { return false }
        return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: target, current: prefix)
            || ChordInkDraftSourceCoveragePolicy.addedVisibleStrokes(in: prefix, after: target) != nil
    }

    static func retainingUnchangedTargets(
        in state: ChordPreviewState, current: PKDrawing, prefixCount: Int
    ) -> ChordPreviewState {
        var retained = state
        retained.draftChords = state.draftChords.filter { draft in
            guard let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, source: current) else { return false }
            return plan.originalStrokeIndices.allSatisfy { $0 < prefixCount }
        }
        retained.draftBarlines = state.draftBarlines.filter {
            !$0.ownedSourceStrokeIndices.isEmpty && $0.ownedSourceStrokeIndices.allSatisfy { $0 < prefixCount }
        }
        retained.draftEndings = state.draftEndings.filter {
            !$0.sourceStrokeIndices.isEmpty && $0.sourceStrokeIndices.allSatisfy { $0 < prefixCount }
        }
        return retained
    }

    /// Unknown newer ink may stay in the same open measure only when it is
    /// strictly after the selected source, with the ordinary word gap or a
    /// verified later writing row. A late accidental, suffix, left boundary,
    /// or ambiguous row owner cannot use this route.
    static func trailingInkIsIndependent(
        unknownIndices: Set<Int>, selectedIndices: Set<Int>, drawing: PKDrawing,
        layout: LeadSheetPageLayout, sourceFrame: CGRect
    ) -> Bool {
        guard !selectedIndices.isEmpty, !unknownIndices.isEmpty,
              selectedIndices.isDisjoint(with: unknownIndices),
              selectedIndices.union(unknownIndices).allSatisfy(drawing.strokes.indices.contains) else { return false }
        let rows = LeadSheetActiveInkScope.chordWritingRegion(for: layout).inputFrames
        func locatedFragments(_ indices: Set<Int>) -> [(row: Int, bounds: CGRect)]? {
            var fragments: [(row: Int, bounds: CGRect)] = []
            for index in indices.sorted() {
                for fragment in PencilKitInkAdapter.visibleStrokeFragments(from: drawing.strokes[index]) {
                    let bounds = fragment.renderBounds.standardized
                        .offsetBy(dx: sourceFrame.minX, dy: sourceFrame.minY)
                    guard !bounds.isNull, !bounds.isInfinite,
                          bounds.minX.isFinite, bounds.minY.isFinite,
                          bounds.maxX.isFinite, bounds.maxY.isFinite else { return nil }
                    let owners = rows.indices.filter { rows[$0].contains(bounds) }
                    guard owners.count == 1, let row = owners.first else { return nil }
                    fragments.append((row, bounds))
                }
            }
            return fragments
        }
        guard let selected = locatedFragments(selectedIndices), !selected.isEmpty,
              let unknown = locatedFragments(unknownIndices), !unknown.isEmpty else { return false }
        let gap = ChordInkAutomaticRenderPolicy.minimumChordGap * layout.pageBounds.width / 900
        return unknown.allSatisfy { later in
            selected.allSatisfy { earlier in
                later.row > earlier.row || (later.row == earlier.row
                    && later.bounds.minX - earlier.bounds.maxX >= gap)
            }
        }
    }
}
#endif
