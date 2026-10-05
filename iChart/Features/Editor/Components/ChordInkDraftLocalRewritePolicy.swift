#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// Selective deletion is permitted only for complete, uniquely owned original
/// strokes. A bitmap fragment shared with another chord is never a removable
/// original stroke, even when its bounds overlap the selected preview.
enum ChordInkDraftLocalRewritePolicy {
    struct Plan {
        let draftID: UUID
        let expectedSource: PKDrawing
        let originalStrokeIndices: Set<Int>

        func rewrittenDrawing(ifCurrentSource current: PKDrawing) -> PKDrawing? {
            guard ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: expectedSource, current: current
            ), current.strokes.count == expectedSource.strokes.count,
            // Full source strokes must still occupy these indices. Visible
            // multiset equality alone allows reordering; deletion does not.
            zip(expectedSource.strokes, current.strokes).allSatisfy({ expected, actual in
                ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: PKDrawing(strokes: [expected]), current: PKDrawing(strokes: [actual])
                )
            }) else { return nil }
            return PKDrawing(strokes: current.strokes.enumerated().compactMap { index, stroke in
                originalStrokeIndices.contains(index) ? nil : stroke
            })
        }
    }

    static func plan(for draft: ChordInkDraft, in state: ChordPreviewState, source: PKDrawing) -> Plan? {
        guard state.draftChords.filter({ $0.id == draft.id }).count == 1,
              state.draftChords.first(where: { $0.id == draft.id }) == draft,
              let plan = plan(for: draft, source: source),
              !state.draftBarlines.contains(where: { barline in
                  barline.sourceStrokeIndex.map(plan.originalStrokeIndices.contains) ?? false
              }) else { return nil }
        let selectedFragments = plan.originalStrokeIndices.flatMap { index in
            PencilKitInkAdapter.visibleStrokeFragments(from: source.strokes[index])
        }
        for neighbor in state.draftChords where neighbor.id != draft.id {
            guard let drawing = try? PKDrawing(data: neighbor.drawingData),
                  ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: drawing, current: drawing) else {
                return nil
            }
            let fragments = drawing.strokes.flatMap { PencilKitInkAdapter.visibleStrokeFragments(from: $0) }
            guard !fragments.contains(where: { fragment in
                selectedFragments.contains { selected in
                    ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                        expected: PKDrawing(strokes: [selected]), current: PKDrawing(strokes: [fragment])
                    )
                }
            }) else { return nil }
        }
        return plan
    }

    static func plan(for draft: ChordInkDraft, source: PKDrawing) -> Plan? {
        guard let target = try? PKDrawing(data: draft.drawingData),
              ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: source),
              ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: target, current: target) else {
            return nil
        }
        let targetFragments = target.strokes.flatMap { PencilKitInkAdapter.visibleStrokeFragments(from: $0) }
        guard !targetFragments.isEmpty else { return nil }
        let sourceFragments = source.strokes.enumerated().flatMap { index, stroke in
            PencilKitInkAdapter.visibleStrokeFragments(from: stroke).map { (originalIndex: index, stroke: $0) }
        }
        var selectedFragments = Set<Int>()
        for targetFragment in targetFragments {
            let matches = sourceFragments.indices.filter { index in
                ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: PKDrawing(strokes: [targetFragment]),
                    current: PKDrawing(strokes: [sourceFragments[index].stroke])
                )
            }
            guard matches.count == 1, let match = matches.first,
                  selectedFragments.insert(match).inserted else { return nil }
        }
        let originalIndices = Set(selectedFragments.map { sourceFragments[$0].originalIndex })
        guard sourceFragments.indices.allSatisfy({ index in
            !originalIndices.contains(sourceFragments[index].originalIndex) || selectedFragments.contains(index)
        }) else { return nil }
        return Plan(draftID: draft.id, expectedSource: source, originalStrokeIndices: originalIndices)
    }
}
#endif
