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

    static func hasCompleteCoverage(chart: Chart, state: ChordPreviewState) -> Bool {
        guard let data = chart.pageHandwrittenChordData else { return true }
        guard let source = try? PKDrawing(data: data) else { return false }
        guard var unclaimed = visibleStrokeMultiset(source) else { return false }
        func claim(_ stroke: PKStroke) -> Bool {
            guard let identity = StrokeIdentity(stroke), let count = unclaimed[identity], count > 0 else {
                return false
            }
            if count == 1 { unclaimed.removeValue(forKey: identity) }
            else { unclaimed[identity] = count - 1 }
            return true
        }

        // Include unresolved represented drafts too. Commit decides whether
        // they can render; this policy only measures their source ownership.
        for draft in state.draftChords {
            guard let drawing = try? PKDrawing(data: draft.drawingData) else { return false }
            guard let fragments = maskVisibleFragments(drawing),
                  !fragments.isEmpty, fragments.allSatisfy(claim) else { return false }
        }

        if !state.draftBarlines.isEmpty {
            // Use the detector's normal visibility/remapping contract only to
            // verify barlines. Its claims still debit the full source multiset.
            let context = ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(from: source)
            guard let pageSize = state.layoutPageSize,
                  pageSize.width.isFinite, pageSize.height.isFinite,
                  pageSize.width > 0, pageSize.height > 0,
                  state.draftBarlines.allSatisfy(\.isRenderable) else { return false }
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
                includesChordInkContinuationLanes: true)
            let fresh = ChordDraftBarlineRecognizer.recognize(
                strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing),
                chordFrame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), pageLayout: layout)
            let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(fresh)
            let remapped = context.remappedBarlineRecognition(safe)
            let freshByIdentity = Dictionary(grouping: remapped.barlines, by: \.identitySignature)
            let visibleBySource = Dictionary(grouping: context.originalStrokeIndices.indices,
                by: { context.originalStrokeIndices[$0] })
            for barline in state.draftBarlines {
                guard let sourceIndex = barline.sourceStrokeIndex,
                      source.strokes.indices.contains(sourceIndex),
                      let visible = visibleBySource[sourceIndex], visible.count == 1,
                      let matches = freshByIdentity[barline.identitySignature], matches.count == 1,
                      let current = matches.first, current.isRenderable,
                      current.metrics == barline.metrics,
                      current.measureIndex == barline.measureIndex,
                      current.laneLocation == barline.laneLocation,
                      current.fraction == barline.fraction,
                      current.layoutPageSize == barline.layoutPageSize,
                      claim(context.drawing.strokes[visible[0]]) else { return false }
            }
        }
        return unclaimed.isEmpty
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
