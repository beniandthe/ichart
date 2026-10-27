#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation

/// Checks only sign pairing. Geometry, live-source ownership, and mapped
/// measure boundaries remain independent commit gates.
enum ChordInkRepeatSignPairingPolicy {
    struct Review: Equatable {
        var unmatchedStartIDs: [UUID] = []
        var nestedStartIDs: [UUID] = []
        var unconfirmedEndIDs: [UUID] = []

        var unresolvedDraftIDs: [UUID] {
            var seen = Set<UUID>()
            return (unmatchedStartIDs + nestedStartIDs + unconfirmedEndIDs).filter { seen.insert($0).inserted }
        }

        var canRender: Bool { unresolvedDraftIDs.isEmpty }
    }

    struct Pairing {
        var start: DraftBarline?
        var end: DraftBarline
    }

    struct Analysis {
        var review: Review
        var pairings: [Pairing]
    }

    static func review(state: ChordPreviewState) -> Review {
        analyze(signs: orderedSigns(state.draftBarlines)).review
    }

    static func orderedSigns(_ signs: [DraftBarline]) -> [DraftBarline] {
        signs.filter { $0.kind.isRepeat }.sorted {
            if $0.visualOrder != $1.visualOrder { return $0.visualOrder < $1.visualOrder }
            if $0.measureIndex != $1.measureIndex { return $0.measureIndex < $1.measureIndex }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func analyze(signs: [DraftBarline]) -> Analysis {
        var review = Review()
        var pairings: [Pairing] = []
        var pendingStart: DraftBarline?
        for sign in signs where sign.kind.isRepeat {
            if sign.kind.endsRepeat {
                if let start = pendingStart {
                    pairings.append(Pairing(start: start, end: sign))
                    pendingStart = nil
                } else if sign.repeatFromBeginningConfirmed {
                    pairings.append(Pairing(start: nil, end: sign))
                } else {
                    review.unconfirmedEndIDs.append(sign.id)
                }
            }
            if sign.kind.startsRepeat {
                if let start = pendingStart {
                    review.nestedStartIDs.append(contentsOf: [start.id, sign.id])
                } else {
                    pendingStart = sign
                }
            }
        }
        if let start = pendingStart { review.unmatchedStartIDs.append(start.id) }
        review.unmatchedStartIDs = unique(review.unmatchedStartIDs)
        review.nestedStartIDs = unique(review.nestedStartIDs)
        review.unconfirmedEndIDs = unique(review.unconfirmedEndIDs)
        return Analysis(review: review, pairings: pairings)
    }

    private static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

/// Repeat semantics are resolved against the final measure IDs after all
/// admitted barline splits. A boundary has distinct left and right sides.
enum ChordInkRepeatSignCommitPolicy {
    enum BoundaryPlacement: Equatable {
        case leading
        case interior
        case trailing
    }

    struct Boundary {
        var draft: DraftBarline
        var leftMeasureID: UUID?
        var rightMeasureID: UUID?
    }

    struct Span {
        var startMeasureID: UUID
        var endMeasureID: UUID
        var sourceDraftIDs: [UUID]
        var sourceStrokeIndices: Set<Int>
    }

    struct Plan {
        var spans: [Span]
        var unresolvedDraftIDs: [UUID]
    }

    /// Endpoint marks use the existing boundary instead of creating a sliver
    /// measure. The tolerance is in source-page points, not a global lane ratio.
    static func boundaryPlacement(fraction: Double, sourceWidth: CGFloat) -> BoundaryPlacement {
        let tolerance = min(0.15, 6 / max(1, Double(sourceWidth)))
        if fraction <= tolerance { return .leading }
        if fraction >= 1 - tolerance { return .trailing }
        return .interior
    }

    static func plan(boundaries: [Boundary], orderedMeasureIDs: [UUID]) -> Plan {
        let positions = Dictionary(uniqueKeysWithValues: orderedMeasureIDs.enumerated().map { ($0.element, $0.offset) })
        var invalidIDs = Set<UUID>()
        func boundaryPosition(_ boundary: Boundary) -> Int? {
            let left = boundary.leftMeasureID.flatMap { positions[$0] }
            let right = boundary.rightMeasureID.flatMap { positions[$0] }
            if let left, let right, right == left + 1 { return right }
            if boundary.leftMeasureID == nil, let right, right == 0 { return 0 }
            if boundary.rightMeasureID == nil, let left, left == orderedMeasureIDs.count - 1 { return orderedMeasureIDs.count }
            return nil
        }
        let ordered = boundaries.filter { boundary in
            guard boundary.draft.kind.isRepeat, boundaryPosition(boundary) != nil else {
                invalidIDs.insert(boundary.draft.id)
                return false
            }
            return true
        }.sorted {
            let lhs = boundaryPosition($0) ?? -1
            let rhs = boundaryPosition($1) ?? -1
            if lhs != rhs { return lhs < rhs }
            return $0.draft.id.uuidString < $1.draft.id.uuidString
        }
        let byID = Dictionary(grouping: ordered, by: { $0.draft.id })
        for (id, matches) in byID where matches.count != 1 { invalidIDs.insert(id) }
        let analysis = ChordInkRepeatSignPairingPolicy.analyze(signs: ordered.map(\.draft))
        invalidIDs.formUnion(analysis.review.unresolvedDraftIDs)
        var spans: [Span] = []
        for pairing in analysis.pairings {
            let ids = [pairing.start?.id, pairing.end.id].compactMap { $0 }
            guard let end = byID[pairing.end.id]?.first,
                  let endMeasureID = end.leftMeasureID,
                  let endIndex = positions[endMeasureID] else {
                invalidIDs.formUnion(ids)
                continue
            }
            let startMeasureID: UUID?
            if let start = pairing.start {
                startMeasureID = byID[start.id]?.first?.rightMeasureID
            } else {
                startMeasureID = pairing.end.repeatFromBeginningConfirmed ? orderedMeasureIDs.first : nil
            }
            guard let startMeasureID, let startIndex = positions[startMeasureID], startIndex <= endIndex else {
                invalidIDs.formUnion(ids)
                continue
            }
            spans.append(Span(startMeasureID: startMeasureID, endMeasureID: endMeasureID,
                sourceDraftIDs: ids,
                sourceStrokeIndices: (pairing.start?.ownedSourceStrokeIndices ?? []).union(pairing.end.ownedSourceStrokeIndices)))
        }
        let unresolved = boundaries.map { $0.draft.id }.filter { invalidIDs.contains($0) }
        return Plan(spans: unresolved.isEmpty ? spans : [], unresolvedDraftIDs: unresolved)
    }
}
#endif
