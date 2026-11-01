#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import CoreGraphics

/// Immutable, already-computed paper geometry. This helper neither lays out a
/// chart nor inspects PencilKit points. Frames and local IDs never enter an
/// event; only bounded comparison results leave the device.
enum ChordInkRenderGeometryTelemetry {
    struct MeasureGeometry: Equatable, Sendable {
        var id: UUID
        var paperFrame: CGRect
        var chordBandFrame: CGRect
    }

    struct GlyphGeometry: Equatable, Sendable {
        var id: UUID
        var naturalFrame: CGRect
        var frame: CGRect

        var combinedFrame: CGRect { naturalFrame.union(frame) }
    }

    struct Snapshot: Equatable, Sendable {
        var pageSize: CGSize
        var coordinateEpoch: UInt64
        var configurationEpoch: UInt64
        var measures: [MeasureGeometry]
        var glyphs: [GlyphGeometry]
        var retainedInkFrames: [CGRect]
    }

    /// Capture only values which the production layout has already computed.
    /// The caller supplies the retained-source frames in the same paper space.
    static func snapshot(
        layout: LeadSheetPageLayout,
        coordinateEpoch: UInt64,
        configurationEpoch: UInt64,
        retainedInkFrames: [CGRect]
    ) -> Snapshot {
        let measures = layout.systems.flatMap(\.measures)
        return Snapshot(pageSize: layout.pageBounds.size, coordinateEpoch: coordinateEpoch,
            configurationEpoch: configurationEpoch,
            measures: measures.compactMap { measure in
                guard let id = measure.sourceMeasureID else { return nil }
                return MeasureGeometry(id: id, paperFrame: measure.frame, chordBandFrame: measure.chordBandFrame)
            },
            glyphs: measures.flatMap(\.chordLayouts).map {
                GlyphGeometry(id: $0.id, naturalFrame: $0.naturalFrame, frame: $0.frame)
            }, retainedInkFrames: retainedInkFrames)
    }

    /// Nil means the transition cannot establish a comparison. A staged
    /// rejection is deliberately not an observed committed geometry defect.
    static func assessment(
        before: Snapshot,
        after: Snapshot,
        preservedMeasureIDs: Set<UUID>,
        renderedChordIDs: Set<UUID>,
        isCommitted: Bool,
        hasIntentionalStructuralChange: Bool = false
    ) -> LeadSheetInkFeatureContract.Assessment? {
        assessments(before: before, after: after, preservedMeasureIDs: preservedMeasureIDs,
            renderedChordIDs: renderedChordIDs, isCommitted: isCommitted,
            hasIntentionalStructuralChange: hasIntentionalStructuralChange)?.first
    }

    /// A single operation may expose both row discontinuity and a new overlap.
    /// Keep the observations separate while retaining one operation ID when
    /// building their envelopes. Passing transitions produce one coverage event.
    static func assessments(
        before: Snapshot,
        after: Snapshot,
        preservedMeasureIDs: Set<UUID>,
        renderedChordIDs: Set<UUID>,
        isCommitted: Bool,
        hasIntentionalStructuralChange: Bool = false
    ) -> [LeadSheetInkFeatureContract.Assessment]? {
        guard isCommitted, !hasIntentionalStructuralChange,
              before.coordinateEpoch == after.coordinateEpoch,
              before.configurationEpoch == after.configurationEpoch,
              validPageSize(before.pageSize), validPageSize(after.pageSize),
              before.pageSize == after.pageSize,
              before.retainedInkFrames.allSatisfy(validFrame),
              after.retainedInkFrames.allSatisfy(validFrame),
              before.glyphs.allSatisfy(validGlyph), after.glyphs.allSatisfy(validGlyph) else { return nil }

        let beforeMeasures = Dictionary(grouping: before.measures, by: \.id)
        let afterMeasures = Dictionary(grouping: after.measures, by: \.id)
        let beforeGlyphs = Dictionary(grouping: before.glyphs, by: \.id)
        let afterGlyphs = Dictionary(grouping: after.glyphs, by: \.id)
        // Duplicate IDs, missing materialized IDs, or a deleted measure are
        // ambiguous geometry evidence. They are not silently converted to zero.
        guard beforeGlyphs.values.allSatisfy({ $0.count == 1 }),
              afterGlyphs.values.allSatisfy({ $0.count == 1 }),
              renderedChordIDs.allSatisfy({ afterGlyphs[$0]?.count == 1 }),
              preservedMeasureIDs.allSatisfy({ id in
                  beforeMeasures[id]?.count == 1 && afterMeasures[id]?.count == 1
                      && beforeMeasures[id]?.allSatisfy(validMeasure) == true
                      && afterMeasures[id]?.allSatisfy(validMeasure) == true
              }), !preservedMeasureIDs.isEmpty || !renderedChordIDs.isEmpty else { return nil }

        let unchangedMeasures = preservedMeasureIDs.filter { id in
            guard let original = beforeMeasures[id]?.first, let observed = afterMeasures[id]?.first else { return false }
            return sameFrame(original.paperFrame, observed.paperFrame)
                && sameFrame(original.chordBandFrame, observed.chordBandFrame)
        }.count
        var results: [LeadSheetInkFeatureContract.Assessment] = []
        if unchangedMeasures != preservedMeasureIDs.count {
            results.append(.init(outcome: "violated", reason: "render_prior_geometry_changed",
                expectedCount: preservedMeasureIDs.count, actualCount: unchangedMeasures, contentMatches: false))
        }

        var inkCollisions = 0
        var glyphCollisions = Set<GlyphPair>()
        for glyph in after.glyphs {
            let isNew = renderedChordIDs.contains(glyph.id)
            let hadSameGeometry = beforeGlyphs[glyph.id]?.first.map {
                sameFrame($0.combinedFrame, glyph.combinedFrame)
            } ?? false
            // Leave pre-existing, unchanged overlaps out of this operation.
            guard isNew || !hadSameGeometry else { continue }
            inkCollisions += after.retainedInkFrames.filter { overlaps(glyph.combinedFrame, $0) }.count
            for other in after.glyphs where other.id != glyph.id {
                guard overlaps(glyph.combinedFrame, other.combinedFrame) else { continue }
                glyphCollisions.insert(GlyphPair(glyph.id, other.id))
            }
        }
        let collisionCount = inkCollisions + glyphCollisions.count
        if collisionCount > 0 {
            results.append(.init(outcome: "violated", reason: "render_new_overlap",
                expectedCount: 0, actualCount: collisionCount, contentMatches: false))
        }
        if results.isEmpty {
            results.append(.init(outcome: "passed", reason: "render_geometry_preserved",
                expectedCount: preservedMeasureIDs.count, actualCount: unchangedMeasures, contentMatches: true))
        }
        return results
    }

    static func properties(
        for assessment: LeadSheetInkFeatureContract.Assessment,
        chart: Chart,
        mode: ChordInkAutomaticRenderTelemetry.Mode,
        operationID: UUID = UUID()
    ) -> IChartTelemetryProperties {
        var values = LeadSheetInkFeatureContract.properties(for: assessment,
            contractID: "ink.render_geometry", chart: chart, scope: "chords", operationID: operationID)
        values["render_mode"] = .string(mode.rawValue)
        return values
    }

    /// These match the production automatic-placement guard, in paper points.
    static func sameFrame(_ first: CGRect, _ second: CGRect) -> Bool {
        validFrame(first) && validFrame(second)
            && abs(first.minX - second.minX) < 0.01 && abs(first.minY - second.minY) < 0.01
            && abs(first.width - second.width) < 0.01 && abs(first.height - second.height) < 0.01
    }

    static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        guard validFrame(first), validFrame(second) else { return false }
        let intersection = first.insetBy(dx: -1, dy: -1).intersection(second)
        return !intersection.isNull && intersection.width > 0.5 && intersection.height > 0.5
    }

    private static func validFrame(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !frame.isEmpty
            && frame.minX.isFinite && frame.minY.isFinite && frame.maxX.isFinite && frame.maxY.isFinite
            && frame.width > 0 && frame.height > 0
    }

    private static func validPageSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func validGlyph(_ glyph: GlyphGeometry) -> Bool {
        validFrame(glyph.frame) && validFrame(glyph.naturalFrame) && validFrame(glyph.combinedFrame)
    }

    private static func validMeasure(_ measure: MeasureGeometry) -> Bool {
        validFrame(measure.paperFrame) && validFrame(measure.chordBandFrame)
    }

    private struct GlyphPair: Hashable {
        var first: UUID
        var second: UUID

        init(_ first: UUID, _ second: UUID) {
            if first.uuidString < second.uuidString { self.first = first; self.second = second }
            else { self.first = second; self.second = first }
        }
    }
}
#endif
