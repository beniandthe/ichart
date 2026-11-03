import CoreGraphics
import Foundation

/// Resolves the same measure and beat into paper coordinates for preview,
/// the committed editor canvas, and PDF export.
enum FreeInkArticulationPlacement {
    struct Target: Equatable {
        let measureID: UUID
        let beatIndex: Int
        let center: CGPoint
        let staffSpace: CGFloat
        let isBelowStaff: Bool

        var markFrame: CGRect {
            CGRect(x: center.x - staffSpace * 0.95, y: center.y - staffSpace * 0.39,
                   width: staffSpace * 1.9, height: staffSpace * 0.78)
        }
    }

    static func target(near point: CGPoint, chart: Chart, pageLayout: LeadSheetPageLayout) -> Target? {
        guard chart.layoutStyle == .rhythmSectionSheet,
              point.x.isFinite, point.y.isFinite else { return nil }

        let systems = pageLayout.systems.filter { system in
            guard system.staffLineYPositions.count >= 2 else { return false }
            let staffSpace = system.staffLineYPositions[1] - system.staffLineYPositions[0]
            guard staffSpace.isFinite, staffSpace > 0 else { return false }
            // A mark just above the chord lane can still belong to this system.
            return point.x >= system.frame.minX && point.x < system.frame.maxX
                && point.y >= system.frame.minY - staffSpace && point.y < system.frame.maxY
        }
        guard systems.count == 1, let system = systems.first else { return nil }

        let measures = system.measures.filter {
            $0.sourceMeasureID != nil && point.x >= $0.staffFrame.minX && point.x < $0.staffFrame.maxX
        }
        guard measures.count == 1, let measureLayout = measures.first,
              let measureID = measureLayout.sourceMeasureID,
              let measure = chart.measure(id: measureID) else { return nil }

        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        guard meter.numerator > 0 else { return nil }
        let staff = measureLayout.staffFrame
        let fraction = min(max(0, (point.x - staff.minX - 8) / max(1, staff.width - 16)), 1)
        let beatIndex = fraction < 1 ? Int(fraction * CGFloat(meter.numerator)) : meter.numerator - 1
        return target(measure: measure, beatIndex: beatIndex, chart: chart, layout: measureLayout, system: system)
    }

    static func target(
        measureID: UUID,
        beatIndex: Int,
        chart: Chart,
        pageLayout: LeadSheetPageLayout
    ) -> Target? {
        guard chart.layoutStyle == .rhythmSectionSheet,
              let measure = chart.measure(id: measureID) else { return nil }
        for system in pageLayout.systems {
            if let layout = system.measures.first(where: { $0.sourceMeasureID == measureID }) {
                return target(measure: measure, beatIndex: beatIndex, chart: chart, layout: layout, system: system)
            }
        }
        return nil
    }

    static func target(
        measure: Measure,
        beatIndex: Int,
        chart: Chart,
        layout: LeadSheetMeasureLayout,
        system: LeadSheetSystemLayout
    ) -> Target? {
        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        guard beatIndex >= 0, beatIndex < meter.numerator,
              let topLine = system.staffLineYPositions.first,
              let bottomLine = system.staffLineYPositions.last,
              system.staffLineYPositions.count >= 2 else { return nil }
        let staffSpace = system.staffLineYPositions[1] - topLine
        guard staffSpace > 0 else { return nil }

        // Beat centers match the engraved rhythm lane even before it has notes.
        let fallbackX = layout.staffFrame.minX + 8
            + max(1, layout.staffFrame.width - 16) * (CGFloat(beatIndex) + 0.5) / CGFloat(meter.numerator)
        let slots = measure.resolvedRhythmSlots(defaultMeter: chart.defaultMeter) ?? []
        let beatNote = zip(slots, layout.noteLayouts).first { slot, note in
            slot.startPosition.beat == beatIndex + 1 && slot.startPosition.subdivision == 0
                && note.symbolStyle != .measureRepeat
        }?.1
        let x = beatNote?.noteheadFrame.midX ?? fallbackX
        let above = Target(measureID: measure.id, beatIndex: beatIndex, center: CGPoint(x: x, y: topLine - staffSpace * 0.6),
                           staffSpace: staffSpace, isBelowStaff: false)
        let below = Target(measureID: measure.id, beatIndex: beatIndex, center: CGPoint(x: x, y: bottomLine + staffSpace * 0.6),
                           staffSpace: staffSpace, isBelowStaff: true)
        let obstacles = layout.chordLayouts.map(\.frame) + layout.cueTextLayouts.map(\.frame)
            + layout.noteLayouts.map { $0.paintedBounds(for: chart) }
        if obstacles.contains(where: { $0.intersects(above.markFrame) }),
           layout.frame.contains(below.markFrame),
           !obstacles.contains(where: { $0.intersects(below.markFrame) }) {
            return below
        }
        return above
    }
}
