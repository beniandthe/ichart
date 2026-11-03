import CoreGraphics
import Foundation

/// Resolves an articulation into document coordinates for the canvas and PDF.
enum FreeInkArticulationPlacement {
    struct Target: Equatable {
        let measureID: UUID?
        let beatIndex: Int?
        let center: CGPoint
        let staffSpace: CGFloat
        let isBelowStaff: Bool

        var markFrame: CGRect {
            CGRect(x: center.x - staffSpace * 0.95, y: center.y - staffSpace * 0.39,
                   width: staffSpace * 1.9, height: staffSpace * 0.78)
        }
    }

    static func pagePoint(at point: CGPoint, pageLayout: LeadSheetPageLayout) -> FreeInkArticulationPagePoint? {
        guard point.x.isFinite, point.y.isFinite,
              let page = pageLayout.pages.first(where: { $0.frame.contains(point) }) else { return nil }
        return FreeInkArticulationPagePoint(pageIndex: page.index,
            x: point.x - page.frame.minX, y: point.y - page.frame.minY)
    }

    static func center(for pagePoint: FreeInkArticulationPagePoint, pageLayout: LeadSheetPageLayout) -> CGPoint? {
        guard pagePoint.x.isFinite, pagePoint.y.isFinite,
              let page = page(containing: pagePoint, in: pageLayout) else { return nil }
        let point = CGPoint(x: page.frame.minX + pagePoint.x, y: page.frame.minY + pagePoint.y)
        if page.frame.contains(point) { return point }
        // A smaller page can clip the original paper point. Keep the glyph
        // visible at the nearest edge with room for its outline.
        let inset = min(10, page.frame.width / 2, page.frame.height / 2)
        let drawable = page.frame.insetBy(dx: inset, dy: inset)
        return CGPoint(x: min(max(point.x, drawable.minX), drawable.maxX),
                       y: min(max(point.y, drawable.minY), drawable.maxY))
    }

    static func attachment(
        near point: CGPoint,
        chart: Chart,
        pageLayout: LeadSheetPageLayout,
        staffInkBounds: [CGRect] = []
    ) -> (measureID: UUID, attachment: FreeInkArticulationAttachment)? {
        guard chart.layoutStyle == .rhythmSectionSheet,
              let pagePoint = pagePoint(at: point, pageLayout: pageLayout),
              let page = pageLayout.pages.first(where: { $0.index == pagePoint.pageIndex }) else { return nil }

        // Test actual engraving geometry before considering the bare staff.
        // A broad measure or chord band alone does not claim a mark.
        var nearest: (measureID: UUID, attachment: FreeInkArticulationAttachment, distance: CGFloat)?
        var staffMatches: [(measureID: UUID, attachment: FreeInkArticulationAttachment)] = []
        for system in pageLayout.systems where page.systemIDs.contains(system.id) {
            guard let spacing = staffSpace(in: system),
                  system.frame.insetBy(dx: -spacing, dy: -1.5 * spacing).contains(point) else { continue }
            for layout in system.measures {
                guard let measureID = layout.sourceMeasureID, let measure = chart.measure(id: measureID) else { continue }
                func consider(_ attachment: FreeInkArticulationAttachment, in frame: CGRect) {
                    guard frame.insetBy(dx: -spacing, dy: -1.5 * spacing).contains(point) else { return }
                    let distance = hypot(point.x - frame.midX, point.y - frame.midY)
                    if nearest.map({ distance < $0.distance }) ?? true {
                        nearest = (measureID, attachment, distance)
                    }
                }
                for chord in layout.chordLayouts {
                    consider(.chord(id: chord.id), in: chord.frame)
                }
                for (position, note) in attachableNotes(measure: measure, layout: layout, chart: chart) {
                    consider(.note(beat: position.beat, subdivision: position.subdivision),
                             in: note.noteheadFrame)
                }

                let staff = layout.staffFrame
                guard staff.width > 0, staff.height > 0,
                      point.x >= staff.minX, point.x < staff.maxX else { continue }
                let nearbyStroke = staffInkBounds.filter { bounds in
                    staff.insetBy(dx: 0, dy: -spacing).intersects(bounds)
                        && bounds.insetBy(dx: -spacing, dy: -spacing).contains(point)
                }.min { lhs, rhs in
                    hypot(lhs.midX - point.x, lhs.midY - point.y) < hypot(rhs.midX - point.x, rhs.midY - point.y)
                }
                guard nearbyStroke != nil || staff.contains(point) else { continue }
                let x = nearbyStroke.map { min(max($0.midX, staff.minX), staff.maxX) } ?? point.x
                let y = nearbyStroke.map { $0.minY - 0.6 * spacing } ?? point.y
                staffMatches.append((measureID, .staff(xFraction: (x - staff.minX) / staff.width,
                                                       yFraction: (y - staff.minY) / staff.height)))
            }
        }
        if let nearest { return (nearest.measureID, nearest.attachment) }
        return staffMatches.count == 1 ? staffMatches.first : nil
    }

    static func target(for mark: FreeInkArticulation, chart: Chart, pageLayout: LeadSheetPageLayout) -> Target? {
        if let attachment = mark.attachment, let measure = attachmentMeasure(for: mark, chart: chart) {
            let measureID = measure.id
            for system in pageLayout.systems {
                guard let layout = system.measures.first(where: { $0.sourceMeasureID == measureID }),
                      let spacing = staffSpace(in: system) else { continue }
                switch attachment {
                case .chord(let id):
                    if let chord = layout.chordLayouts.first(where: { $0.id == id }) {
                        let offset = attachmentStackOffset(for: mark, chart: chart, spacing: spacing)
                        return Target(measureID: measureID, beatIndex: nil,
                            center: CGPoint(x: chord.frame.midX, y: chord.frame.minY - 0.6 * spacing - offset),
                            staffSpace: spacing, isBelowStaff: false)
                    }
                case .note(let beat, let subdivision):
                    if let note = attachableNotes(measure: measure, layout: layout, chart: chart).first(where: {
                        $0.position.beat == beat && $0.position.subdivision == subdivision
                    })?.note {
                        let offset = attachmentStackOffset(for: mark, chart: chart, spacing: spacing)
                        let y = min(layout.staffFrame.minY, note.paintedBounds(for: chart).minY) - 0.6 * spacing - offset
                        return Target(measureID: measureID, beatIndex: beat - 1,
                            center: CGPoint(x: note.noteheadFrame.midX, y: y),
                            staffSpace: spacing, isBelowStaff: false)
                    }
                case .staff(let xFraction, let yFraction):
                    guard xFraction.isFinite, yFraction.isFinite, (0...1).contains(xFraction) else { break }
                    let staff = layout.staffFrame
                    let point = CGPoint(x: staff.minX + staff.width * xFraction, y: staff.minY + staff.height * yFraction)
                    return Target(measureID: measureID, beatIndex: nil, center: point,
                        staffSpace: spacing, isBelowStaff: point.y > staff.maxY)
                }
            }
        }

        if let pagePoint = mark.pagePoint, let point = center(for: pagePoint, pageLayout: pageLayout) {
            let page = page(containing: pagePoint, in: pageLayout)
            let system = pageLayout.systems.first { page?.systemIDs.contains($0.id) == true }
            let spacing = system.flatMap(staffSpace(in:)) ?? 10.5
            return Target(measureID: nil, beatIndex: nil, center: point, staffSpace: spacing, isBelowStaff: false)
        }
        guard let measureID = mark.measureID, let beatIndex = mark.legacyBeatIndex else { return nil }
        return target(measureID: measureID, beatIndex: beatIndex, chart: chart, pageLayout: pageLayout)
    }

    private static func page(
        containing point: FreeInkArticulationPagePoint, in layout: LeadSheetPageLayout
    ) -> LeadSheetPaperPageLayout? {
        layout.pages.min {
            abs(Double($0.index) - Double(point.pageIndex)) < abs(Double($1.index) - Double(point.pageIndex))
        }
    }

    private static func attachmentStackOffset(for mark: FreeInkArticulation, chart: Chart, spacing: CGFloat) -> CGFloat {
        let preceding = chart.freeInkArticulations.prefix { $0.id != mark.id }
        let count = preceding.filter { other in
            guard other.attachment == mark.attachment else { return false }
            if case .chord = mark.attachment { return true }
            return other.measureID == mark.measureID
        }.count
        return CGFloat(count) * spacing
    }

    private static func attachmentMeasure(for mark: FreeInkArticulation, chart: Chart) -> Measure? {
        if case .chord(let id) = mark.attachment {
            return chart.measureContainingChordEvent(id: id)
        }
        return mark.measureID.flatMap(chart.measure(id:))
    }

    private static func staffSpace(in system: LeadSheetSystemLayout) -> CGFloat? {
        guard system.staffLineYPositions.count >= 2 else { return nil }
        let spacing = system.staffLineYPositions[1] - system.staffLineYPositions[0]
        return spacing.isFinite && spacing > 0 ? spacing : nil
    }

    private static func attachableNotes(
        measure: Measure, layout: LeadSheetMeasureLayout, chart: Chart
    ) -> [(position: BeatPosition, note: LeadSheetNoteLayout)] {
        guard let slots = measure.resolvedRhythmSlots(defaultMeter: chart.defaultMeter) else { return [] }
        return zip(slots, layout.noteLayouts).compactMap { slot, note in
            switch note.symbolStyle {
            case .pitchedNote, .slash: return (slot.startPosition, note)
            default: return nil
            }
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
