#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PencilKit

/// A user-selected measure ordinal belongs to one source and split plan. The
/// chart is retained as a value rather than encoded JSON: sorted object keys
/// alone do not make encoded Set element ordering canonical.
struct ChordDraftEndingRangeReviewContext: Hashable {
    private struct BarlineSnapshot: Hashable {
        let identity: ChordDraftBarlineIdentitySignature
        let measureIndex: Int
        let fraction: Double
        let laneLocation: ChordInkDraftLaneLocation?
        let layoutPageSize: CGSize?
        let metrics: DraftBarlineGestureMetrics
        let ambiguity: DraftBarlineAmbiguity

        init(_ barline: DraftBarline) {
            identity = barline.identitySignature
            measureIndex = barline.measureIndex
            fraction = barline.fraction
            laneLocation = barline.laneLocation
            layoutPageSize = barline.layoutPageSize
            metrics = barline.metrics
            ambiguity = barline.ambiguity
        }
    }

    private let canonicalChart: Chart
    private let approvedSourceDrawingData: Data
    private let sourceCoordinateSpace: PersistentInkCoordinateSpace?
    private let layoutPageSize: CGSize
    private let orderedBarlines: [BarlineSnapshot]
    private let requiredSystemIndex: Int

    static func capture(chart: Chart, state: ChordPreviewState) -> Self? {
        guard let pageSize = state.layoutPageSize,
              pageSize.width.isFinite, pageSize.height.isFinite,
              pageSize.width > 0, pageSize.height > 0,
              let sourceData = chart.pageHandwrittenChordData,
              let drawing = try? PKDrawing(data: sourceData),
              !drawing.strokes.isEmpty,
              ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: drawing, current: drawing) else { return nil }
        let systemIndices = state.draftChords.compactMap { $0.laneLocation?.systemIndex }
            + state.draftBarlines.compactMap { $0.laneLocation?.systemIndex }
            + state.draftEndings.flatMap { [$0.start.laneLocation.systemIndex, $0.end.laneLocation.systemIndex] }
        guard systemIndices.allSatisfy({ $0 >= 0 }) else { return nil }
        var canonical = chart
        canonical.pageHandwrittenChordData = nil
        canonical.pageHandwrittenChordCoordinateSpace = nil
        canonical.updatedAt = Date(timeIntervalSince1970: 0)
        // A backup acknowledgement can arrive while the ending sheet is open.
        // It has no effect on the chart geometry or the source ink.
        canonical.cloudBackupStatus = .included
        return Self(
            canonicalChart: canonical,
            approvedSourceDrawingData: sourceData,
            sourceCoordinateSpace: chart.pageHandwrittenChordCoordinateSpace,
            layoutPageSize: pageSize,
            orderedBarlines: state.draftBarlines
                .sorted(by: ChordInkRepeatSignPairingPolicy.precedesInSourceOrder)
                .map(BarlineSnapshot.init),
            requiredSystemIndex: systemIndices.max() ?? 0
        )
    }

    /// Native pen normalization may change encoded bytes or ink color/type.
    /// Visible paths, chronology, masks, transforms and random seeds must still
    /// match exactly before an approved ordinal can resolve to final measures.
    func matches(chart: Chart, state: ChordPreviewState) -> Bool {
        guard let current = Self.capture(chart: chart, state: state),
              canonicalChart == current.canonicalChart,
              sourceCoordinateSpace == current.sourceCoordinateSpace,
              layoutPageSize == current.layoutPageSize,
              orderedBarlines == current.orderedBarlines,
              requiredSystemIndex == current.requiredSystemIndex,
              let expectedDrawing = try? PKDrawing(data: approvedSourceDrawingData),
              let currentDrawing = try? PKDrawing(data: current.approvedSourceDrawingData) else { return false }
        return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: expectedDrawing, current: currentDrawing)
    }
}
#endif
