#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation

/// An endpoint in the source writing lane. The final measure IDs are resolved
/// only after the reviewed barlines have been split.
struct DraftEndingEndpoint: Hashable {
    var measureID: UUID
    var measureIndex: Int
    var fraction: Double
    var laneLocation: ChordInkDraftLaneLocation
}

struct DraftEndingIdentitySignature: Hashable {
    var start: DraftEndingEndpoint
    var end: DraftEndingEndpoint
    var layoutPageSize: CGSize?
    var sourceStrokeIndices: Set<Int>
    var sourceStrokeGeometry: [InkStroke]
    var detectedEndStyle: EndingEndStyle
}

/// Geometry detects the bracket and owns its source. Labels remain an explicit
/// user choice so arbitrary words and pass lists never depend on chord OCR.
struct DraftEnding: Identifiable, Hashable {
    var id: UUID
    var start: DraftEndingEndpoint
    var end: DraftEndingEndpoint
    var layoutPageSize: CGSize?
    var sourceStrokeIndices: Set<Int>
    var sourceStrokeGeometry: [InkStroke]
    /// Source-local roof review target, kept above the writable label band.
    /// Fitted/slanted roofs cannot use the full stroke bounds when a leg is tall.
    var roofReviewFrame: CGRect? = nil
    var label: String
    var endStyle: EndingEndStyle
    var isReviewed: Bool
    /// Exact PencilKit source approved by the user, including chronology and
    /// masks. A geometry-equivalent replacement must be reviewed again.
    var reviewedSourceInkData: Data?
    var reviewedMeasureRange: ClosedRange<Int>?
    var reviewedRangeContext: ChordDraftEndingRangeReviewContext?
    var detectedEndStyle: EndingEndStyle

    init(
        id: UUID = UUID(), start: DraftEndingEndpoint, end: DraftEndingEndpoint,
        layoutPageSize: CGSize? = nil, sourceStrokeIndices: Set<Int>,
        sourceStrokeGeometry: [InkStroke], label: String = "",
        endStyle: EndingEndStyle, isReviewed: Bool = false, reviewedSourceInkData: Data? = nil,
        reviewedMeasureRange: ClosedRange<Int>? = nil,
        reviewedRangeContext: ChordDraftEndingRangeReviewContext? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.layoutPageSize = layoutPageSize
        self.sourceStrokeIndices = sourceStrokeIndices
        self.sourceStrokeGeometry = sourceStrokeGeometry
        self.label = label
        self.endStyle = endStyle
        self.isReviewed = isReviewed
        self.reviewedSourceInkData = reviewedSourceInkData
        self.reviewedMeasureRange = reviewedMeasureRange
        self.reviewedRangeContext = reviewedRangeContext
        detectedEndStyle = endStyle
    }

    var normalizedLabel: String { RoadmapObject.normalizedEndingDisplayText(label) ?? "" }
    var isRenderable: Bool { isReviewed && !normalizedLabel.isEmpty && reviewedSourceInkData != nil }
    var visualOrder: Double { start.laneLocation.visualOrder }
    var identitySignature: DraftEndingIdentitySignature {
        DraftEndingIdentitySignature(start: start, end: end, layoutPageSize: layoutPageSize,
            sourceStrokeIndices: sourceStrokeIndices, sourceStrokeGeometry: sourceStrokeGeometry,
            detectedEndStyle: detectedEndStyle)
    }
}

struct ChordDraftEndingRecognition {
    var endings: [DraftEnding]
    var strokeIndices: Set<Int>
}

enum ChordInkEndingCommitPolicy {
    struct PageBoundary {
        var leftMeasureID: UUID?
        var rightMeasureID: UUID?
        /// Visible source-page positions belonging to this musical boundary.
        /// Repeat bars and dots may lie away from the measure's logical edge.
        var sourceRanges: [ClosedRange<CGFloat>]
    }

    private struct BoundaryIdentity: Hashable {
        var leftMeasureID: UUID?
        var rightMeasureID: UUID?
    }

    /// Work in source-page points and compare distinct musical boundaries,
    /// rather than selecting a measure first. Multiple aliases of one repeat
    /// boundary must not make its own two bars look ambiguous.
    static func measureID(atSourceX x: CGFloat, boundaries: [PageBoundary], isStart: Bool) -> UUID? {
        guard x.isFinite else { return nil }
        var grouped: [BoundaryIdentity: [ClosedRange<CGFloat>]] = [:]
        for boundary in boundaries {
            let key = BoundaryIdentity(leftMeasureID: boundary.leftMeasureID,
                rightMeasureID: boundary.rightMeasureID)
            grouped[key, default: []].append(contentsOf: boundary.sourceRanges.filter {
                $0.lowerBound.isFinite && $0.upperBound.isFinite
            })
        }
        let ranked = grouped.compactMap { key, ranges -> (BoundaryIdentity, CGFloat)? in
            guard let distance = ranges.map({ max($0.lowerBound - x, x - $0.upperBound, 0) }).min() else { return nil }
            return (key, distance)
        }.sorted { $0.1 < $1.1 }
        guard let nearest = ranked.first, nearest.1 <= 18 else { return nil }
        // A four-point margin leaves a small no-snap zone around the midpoint
        // of neighboring boundaries. Widening handwriting tolerance cannot
        // turn a midpoint into an arbitrary choice of the following measure.
        if ranked.count > 1, ranked[1].1 - nearest.1 < 4 { return nil }
        return isStart ? nearest.0.rightMeasureID : nearest.0.leftMeasureID
    }

}
#endif
