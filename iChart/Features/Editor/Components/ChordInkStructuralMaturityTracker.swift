#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// A live-session clock for unchanged structural ink. Maturity only permits
/// the normal guarded transaction to try; it never validates or consumes ink.
/// Archived stroke dates and unrelated later writing cannot age a new mark.
@MainActor
final class ChordInkStructuralMaturityTracker {
    private struct Endpoint: Equatable {
        let measureID: UUID
        let fraction: Double
        let lane: ChordInkDraftLaneLocation

        init(_ endpoint: DraftEndingEndpoint) {
            measureID = endpoint.measureID
            fraction = endpoint.fraction
            lane = endpoint.laneLocation
        }
    }

    private enum Semantic: Equatable {
        case barline(measureID: UUID, fraction: Double, lane: ChordInkDraftLaneLocation,
            pageSize: CGSize?, kind: DraftBarlineKind, metrics: DraftBarlineGestureMetrics)
        case ending(start: Endpoint, end: Endpoint, pageSize: CGSize?,
            roof: CGRect?, detectedEndStyle: EndingEndStyle)
    }

    private struct Candidate {
        let id: UUID
        let semantic: Semantic
        let source: PKDrawing
        let indices: Set<Int>
    }

    private struct Entry {
        let semantic: Semantic
        let source: PKDrawing
        let observedAt: Date
        let indices: Set<Int>
    }

    private var lastObservationAt: Date?
    private var chartID: UUID?
    private var entries: [Entry] = []
    private(set) var nextDeadline: Date?

    func reset() {
        chartID = nil
        entries = []
        lastObservationAt = nil
        nextDeadline = nil
    }

    /// Erasing a mark invalidates its age immediately, before a replacement
    /// recognition census arrives. Index rebasing or unrelated added ink can
    /// keep the exact source receipt present without restarting its clock.
    func retainPresentSource(in drawing: PKDrawing) {
        entries.removeAll { entry in
            if let indexed = source(indices: entry.indices, in: drawing),
               ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: entry.source, current: indexed) {
                return false
            }
            return !ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: entry.source, current: drawing)
                && ChordInkDraftSourceCoveragePolicy.addedVisibleStrokes(in: drawing, after: entry.source) == nil
        }
        if let lastObservationAt {
            nextDeadline = entries.map { $0.observedAt.addingTimeInterval(ChordInkAutomaticRenderPolicy.structuralIdleDelay) }
                .filter { $0 > lastObservationAt }.min()
        } else {
            nextDeadline = nil
        }
    }

    /// Returns current draft IDs whose exact structural source and semantic
    /// target have stayed unchanged for the full existing structural grace.
    /// Draft IDs, source indices and measure ordinals may be regenerated.
    func observe(chartID: UUID, state: ChordPreviewState, drawing: PKDrawing, now: Date) -> Set<UUID> {
        if self.chartID != chartID { reset(); self.chartID = chartID }
        guard now.timeIntervalSinceReferenceDate.isFinite else { reset(); return [] }
        lastObservationAt = now
        let candidates = candidates(state: state, drawing: drawing)
        let claims = state.draftBarlines.map { ($0.id, $0.ownedSourceStrokeIndices) }
            + state.draftEndings.map { ($0.id, $0.sourceStrokeIndices) }
        var nextEntries: [Entry] = []
        var mature = Set<UUID>()
        nextDeadline = nil
        for candidate in candidates {
            // Two claims for one source or identity are ambiguous. Never let
            // either inherit an age until the current census disambiguates it.
            guard claims.filter({ $0.0 == candidate.id }).count == 1,
                  claims.filter({ !$0.1.isDisjoint(with: candidate.indices) }).count == 1,
                  candidates.filter({ matches($0.semantic, source: $0.source,
                    candidate.semantic, source: candidate.source) }).count == 1 else { continue }
            let previous = entries.filter {
                matches($0.semantic, source: $0.source, candidate.semantic, source: candidate.source)
            }
            let observedAt: Date
            if previous.count == 1, let prior = previous.first, now >= prior.observedAt {
                observedAt = prior.observedAt
            } else {
                observedAt = now
            }
            nextEntries.append(Entry(semantic: candidate.semantic, source: candidate.source,
                observedAt: observedAt, indices: candidate.indices))
            let deadline = observedAt.addingTimeInterval(ChordInkAutomaticRenderPolicy.structuralIdleDelay)
            if now >= deadline {
                mature.insert(candidate.id)
            } else {
                nextDeadline = min(nextDeadline ?? deadline, deadline)
            }
        }
        // Absence, invalid claims and ambiguity prune immediately. A later
        // reappearance starts a new live observation instead of resuming age.
        entries = nextEntries
        return mature
    }

    private func matches(_ lhs: Semantic, source lhsSource: PKDrawing,
        _ rhs: Semantic, source rhsSource: PKDrawing) -> Bool {
        lhs == rhs && ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: lhsSource, current: rhsSource)
    }

    private func candidates(state: ChordPreviewState, drawing: PKDrawing) -> [Candidate] {
        var result: [Candidate] = []
        for barline in state.draftBarlines {
            guard barline.isRenderable, valid(barline.fraction),
                  let lane = barline.laneLocation, valid(lane), valid(barline.layoutPageSize),
                  [barline.metrics.height, barline.metrics.width, barline.metrics.angleDegreesFromVertical,
                    barline.metrics.straightness, barline.metrics.laneCoverage].allSatisfy(\.isFinite),
                  let source = source(indices: barline.ownedSourceStrokeIndices, in: drawing) else { continue }
            result.append(Candidate(id: barline.id,
                semantic: .barline(measureID: barline.measureID, fraction: barline.fraction,
                    lane: lane, pageSize: barline.layoutPageSize, kind: barline.kind, metrics: barline.metrics),
                source: source, indices: barline.ownedSourceStrokeIndices))
        }
        for ending in state.draftEndings {
            guard valid(ending.start.fraction), valid(ending.end.fraction),
                  valid(ending.start.laneLocation), valid(ending.end.laneLocation),
                  valid(ending.layoutPageSize),
                  ending.roofReviewFrame.map(valid) ?? true,
                  let source = source(indices: ending.sourceStrokeIndices, in: drawing) else { continue }
            result.append(Candidate(id: ending.id,
                semantic: .ending(start: Endpoint(ending.start), end: Endpoint(ending.end),
                    pageSize: ending.layoutPageSize, roof: ending.roofReviewFrame,
                    detectedEndStyle: ending.detectedEndStyle),
                source: source, indices: ending.sourceStrokeIndices))
        }
        return result
    }

    private func source(indices: Set<Int>, in drawing: PKDrawing) -> PKDrawing? {
        guard !indices.isEmpty, indices.allSatisfy(drawing.strokes.indices.contains) else { return nil }
        let source = PKDrawing(strokes: indices.sorted().map { drawing.strokes[$0] })
        guard source.strokes.allSatisfy({ PencilKitInkAdapter.visibleStrokeFragments(from: $0).count == 1 }),
              ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: source) else { return nil }
        return source
    }

    private func valid(_ fraction: Double) -> Bool { fraction.isFinite && fraction >= 0 && fraction < 1 }
    private func valid(_ lane: ChordInkDraftLaneLocation) -> Bool { lane.systemIndex >= 0 && valid(lane.fraction) }
    private func valid(_ pageSize: CGSize?) -> Bool {
        guard let pageSize else { return true }
        return pageSize.width.isFinite && pageSize.height.isFinite && pageSize.width > 0 && pageSize.height > 0
    }
    private func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.minX.isFinite && frame.minY.isFinite
            && frame.maxX.isFinite && frame.maxY.isFinite
    }
}
#endif
