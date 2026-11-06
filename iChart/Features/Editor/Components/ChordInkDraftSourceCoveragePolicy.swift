#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// A clearing-safety check, not recognition or trust. Every currently visible
/// source fragment must be claimed exactly once by a represented draft or a
/// freshly verified barline. Only fully mask-erased portions are excluded;
/// recognition's minimum visible size must never authorize clearing tiny ink.
enum ChordInkDraftSourceCoveragePolicy {
    /// Reusable source-freshness check for a live canvas. This does not consume
    /// ink or depend on recognition, target labels, or their order.
    static func hasIdenticalVisibleInk(expected: PKDrawing, current: PKDrawing) -> Bool {
        guard let expectedInk = visibleStrokeMultiset(expected),
              let currentInk = visibleStrokeMultiset(current) else { return false }
        return expectedInk == currentInk
    }

    /// Returns only the added fragments if the expanded drawing contains every
    /// fragment of the prior draft. Match by exact identity and multiplicity.
    static func addedVisibleStrokes(in expanded: PKDrawing, after prior: PKDrawing) -> [PKStroke]? {
        guard let fragments = maskVisibleFragments(expanded),
              var priorInk = visibleStrokeMultiset(prior), !priorInk.isEmpty else { return nil }
        let added = fragments.filter { !claim($0, from: &priorInk) }
        return priorInk.isEmpty && !added.isEmpty ? added : nil
    }

    static func hasCompleteCoverage(chart: Chart, state: ChordPreviewState) -> Bool {
        hasCoverage(chart: chart, state: state, requiresCompleteCoverage: true)
    }

    /// Validates every represented claim while allowing other live fragments
    /// to remain unclaimed. A partial transaction must retain those fragments
    /// and validate its selected source separately before consuming any ink.
    static func hasValidRepresentedCoverage(chart: Chart, state: ChordPreviewState) -> Bool {
        guard chart.pageHandwrittenChordData != nil else { return state.isEmpty }
        return hasCoverage(chart: chart, state: state, requiresCompleteCoverage: false)
    }

    private static func hasCoverage(
        chart: Chart, state: ChordPreviewState, requiresCompleteCoverage: Bool
    ) -> Bool {
        guard let data = chart.pageHandwrittenChordData else { return true }
        guard let source = try? PKDrawing(data: data) else { return false }
        guard var unclaimed = visibleStrokeMultiset(source) else { return false }
        func claimSource(_ stroke: PKStroke) -> Bool { claim(stroke, from: &unclaimed) }

        // Include unresolved represented drafts too. Commit decides whether
        // they can render; this policy only measures their source ownership.
        for draft in state.draftChords {
            guard let drawing = try? PKDrawing(data: draft.drawingData) else { return false }
            guard let fragments = maskVisibleFragments(drawing),
                  !fragments.isEmpty, fragments.allSatisfy(claimSource) else { return false }
        }

        if !state.draftBarlines.isEmpty || !state.draftEndings.isEmpty {
            // Use the detector's normal visibility/remapping contract only to
            // verify barlines. Its claims still debit the full source multiset.
            guard let pageSize = state.layoutPageSize,
                  pageSize.width.isFinite, pageSize.height.isFinite,
                  pageSize.width > 0, pageSize.height > 0,
                  (!requiresCompleteCoverage || state.draftBarlines.allSatisfy(\.isRenderable)) else { return false }
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
                includesChordInkContinuationLanes: true)
            let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
            let context = ChordInkDraftVisibleStrokePolicy.structuralVisibleDrawingContext(
                from: source, chordFrame: chordFrame, pageLayout: layout)
            let strokes = PencilKitInkAdapter.inkStrokes(from: context.drawing)
            let freshEndings = ChordDraftEndingRecognizer.recognize(
                strokes: strokes, chordFrame: chordFrame, pageLayout: layout)
            let safeEndings = context.endingRecognitionWithUnambiguousSourceStrokes(freshEndings)
            let remappedEndings = context.remappedEndingRecognition(safeEndings)
            let endingsByIdentity = Dictionary(grouping: remappedEndings.endings, by: \.identitySignature)
            let fresh = ChordDraftEndingRecognizer.recognizeBarlinesExcludingEndings(
                strokes: strokes,
                chordFrame: chordFrame, pageLayout: layout)
            let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(fresh)
            let remapped = context.remappedBarlineRecognition(safe)
            let freshByIdentity = Dictionary(grouping: remapped.barlines, by: \.identitySignature)
            let visibleBySource = Dictionary(grouping: context.originalStrokeIndices.indices,
                by: { context.originalStrokeIndices[$0] })
            for ending in state.draftEndings {
                guard let matches = endingsByIdentity[ending.identitySignature], matches.count == 1,
                      let current = matches.first,
                      current.start == ending.start, current.end == ending.end,
                      current.layoutPageSize == ending.layoutPageSize else { return false }
                var currentFragments: [PKStroke] = []
                for index in ending.sourceStrokeIndices.sorted() {
                    guard source.strokes.indices.contains(index),
                          let visible = visibleBySource[index], visible.count == 1 else { return false }
                    currentFragments.append(context.drawing.strokes[visible[0]])
                }
                if ending.isReviewed {
                    guard let receipt = ending.reviewedSourceInkData,
                          let reviewed = try? PKDrawing(data: receipt),
                          hasIdenticalVisibleInk(expected: reviewed,
                            current: PKDrawing(strokes: currentFragments)) else { return false }
                }
                for index in ending.sourceStrokeIndices {
                    guard source.strokes.indices.contains(index),
                          let visible = visibleBySource[index], visible.count == 1,
                          claimSource(context.drawing.strokes[visible[0]]) else { return false }
                }
            }
            for barline in state.draftBarlines {
                guard let sourceIndex = barline.sourceStrokeIndex,
                      source.strokes.indices.contains(sourceIndex),
                      let matches = freshByIdentity[barline.identitySignature], matches.count == 1,
                      let current = matches.first,
                      (!requiresCompleteCoverage || current.isRenderable),
                      current.ambiguity == barline.ambiguity,
                      current.metrics == barline.metrics,
                      current.measureIndex == barline.measureIndex,
                      current.laneLocation == barline.laneLocation,
                      current.fraction == barline.fraction,
                      current.layoutPageSize == barline.layoutPageSize else { return false }
                for ownedIndex in barline.ownedSourceStrokeIndices {
                    guard source.strokes.indices.contains(ownedIndex),
                          let visible = visibleBySource[ownedIndex], visible.count == 1,
                          claimSource(context.drawing.strokes[visible[0]]) else { return false }
                }
            }
        }
        return !requiresCompleteCoverage || unclaimed.isEmpty
    }

    private static func claim(_ stroke: PKStroke, from unclaimed: inout [StrokeIdentity: Int]) -> Bool {
        guard let identity = StrokeIdentity(stroke), let count = unclaimed[identity] else { return false }
        if count == 1 { unclaimed.removeValue(forKey: identity) }
        else { unclaimed[identity] = count - 1 }
        return true
    }

    private static func visibleStrokeMultiset(_ drawing: PKDrawing) -> [StrokeIdentity: Int]? {
        guard let fragments = maskVisibleFragments(drawing) else { return nil }
        var counts: [StrokeIdentity: Int] = [:]
        for stroke in fragments {
            guard let identity = StrokeIdentity(stroke) else { return nil }
            counts[identity, default: 0] += 1
        }
        return counts
    }

    private static func maskVisibleFragments(_ drawing: PKDrawing) -> [PKStroke]? {
        var fragments: [PKStroke] = []
        for stroke in drawing.strokes {
            // Validate even erased source paths before asking PencilKit for
            // mask ranges; malformed geometry is never an invisible success.
            guard StrokeIdentity(stroke) != nil else { return nil }
            let visible = PencilKitInkAdapter.visibleStrokeFragments(from: stroke)
            guard visible.allSatisfy({ StrokeIdentity($0) != nil }) else { return nil }
            fragments.append(contentsOf: visible)
        }
        return fragments
    }

    /// Ink color/type are intentionally excluded: persisted target ink is
    /// normalized to the app pen. Path, chronology, transform and random seed
    /// are not normalized, rounded, or replaced by bounds/fuzzy fingerprints.
    private struct StrokeIdentity: Hashable {
        let points: [[Double]]
        let creationTime: Double
        let transform: [Double]
        let randomSeed: UInt32

        init?(_ stroke: PKStroke) {
            guard !stroke.path.isEmpty else { return nil }
            points = stroke.path.map { point in
                let threshold: Double
                if #available(iOS 26.0, *) { threshold = Double(point.threshold) }
                else { threshold = 0 }
                return [Double(point.location.x), Double(point.location.y),
                    Double(point.size.width), Double(point.size.height), Double(point.force),
                    Double(point.opacity), Double(point.azimuth), Double(point.altitude),
                    point.timeOffset, Double(point.secondaryScale), threshold]
            }
            creationTime = stroke.path.creationDate.timeIntervalSinceReferenceDate
            let value = stroke.transform
            transform = [Double(value.a), Double(value.b), Double(value.c), Double(value.d),
                Double(value.tx), Double(value.ty)]
            randomSeed = stroke.randomSeed
            guard creationTime.isFinite, points.allSatisfy({ $0.allSatisfy(\.isFinite) }),
                  transform.allSatisfy(\.isFinite) else { return nil }
        }
    }
}
#endif
