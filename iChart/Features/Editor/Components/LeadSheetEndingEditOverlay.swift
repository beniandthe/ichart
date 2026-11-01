#if canImport(UIKit)
import CoreGraphics
import Foundation
import UIKit

/// Editor-only affordances. Idle controls share their frames with routing;
/// an active gesture keeps its frozen source hit geometry while displaying its
/// destination controls and notation at the candidate measure range.
enum LeadSheetEndingEditOverlay {
    struct SegmentControls: Hashable {
        let systemIndex: Int
        let segmentFrame: CGRect
        let moveHandle: CGRect
        let lengthenHandle: CGRect?
        let paperFrame: CGRect
        let moveAttachment: CGPoint
        let lengthAttachment: CGPoint?
    }

    struct MeasureCoverage: Hashable {
        let measureIndex: Int
        let systemIndex: Int
        let frame: CGRect
    }

    struct FeedbackCallout: Hashable {
        let frame: CGRect
        let title: String
        let rangeText: String
        let instruction: String
        let systemIndex: Int
    }

    struct Presentation {
        let controls: [SegmentControls]
        let candidateSegments: [LeadSheetEndingLayout]
        let coverage: [MeasureCoverage]
        let callout: FeedbackCallout?
        let activeMoveSystemIndex: Int?
        let action: RenderedEditAction?
        let rangeCaption: String?
        let isDragging: Bool
    }

    static let minimumScreenTouchSize: CGFloat = 44

    static func controlFrames(
        for endingID: UUID, in pageLayout: LeadSheetPageLayout,
        screenPointsPerDisplayedPoint: CGFloat = 1
    ) -> [SegmentControls] {
        let scale = validScale(screenPointsPerDisplayedPoint)
        let segments = orderedSegments(for: endingID, in: pageLayout)
        let obstacles = LeadSheetEndingOverlayPlacement.notationObstacles(in: pageLayout, scale: scale)
        var reserved: [CGRect] = []
        var result: [SegmentControls] = []
        for (index, item) in segments.enumerated() {
            let (system, ending) = item
            let paper = pageLayout.paperFrame(for: system)
            guard isFinite(ending.frame), isFinite(paper) else { continue }
            let height = minimumScreenTouchSize / scale
            let usableWidth = paper.width - 12 / scale
            guard usableWidth >= height, paper.height - 12 / scale >= height else { continue }
            let isLast = index == segments.count - 1
            let moveWidth = min(98 / scale, usableWidth)
            let lengthWidth = min(118 / scale, usableWidth)
            let gap = 8 / scale
            var moveX = ending.frame.minX - moveWidth / 2
            var lengthX = ending.frame.maxX - lengthWidth / 2
            if isLast, lengthX - (moveX + moveWidth) < gap,
               moveWidth + lengthWidth + gap <= usableWidth {
                moveX = ending.frame.midX - (moveWidth + lengthWidth + gap) / 2
                lengthX = moveX + moveWidth + gap
            }
            let y = ending.frame.minY - gap - height
            guard let move = LeadSheetEndingOverlayPlacement.frame(
                size: CGSize(width: moveWidth, height: height), preferredOrigin: CGPoint(x: moveX, y: y),
                inside: paper, obstacles: obstacles, reserved: reserved, scale: scale) else { continue }
            var length: CGRect?
            if isLast {
                length = LeadSheetEndingOverlayPlacement.frame(
                    size: CGSize(width: lengthWidth, height: height),
                    preferredOrigin: CGPoint(x: lengthX, y: move.minY),
                    inside: paper, obstacles: obstacles, reserved: reserved + [move], scale: scale)
                guard length != nil else { continue }
            }
            reserved.append(move)
            if let length { reserved.append(length) }
            result.append(SegmentControls(systemIndex: system.index, segmentFrame: ending.frame,
                moveHandle: move, lengthenHandle: length, paperFrame: paper,
                moveAttachment: CGPoint(x: ending.frame.minX, y: ending.frame.minY + 3),
                lengthAttachment: isLast ? CGPoint(x: ending.frame.maxX, y: ending.frame.minY + 3) : nil))
        }
        return result
    }

    static func presentation(
        for endingID: UUID, chart: Chart, pageLayout: LeadSheetPageLayout,
        previewChart: Chart? = nil, screenPointsPerDisplayedPoint: CGFloat = 1,
        dragFeedback: LeadSheetEndingDragFeedback? = nil
    ) -> Presentation {
        let scale = validScale(screenPointsPerDisplayedPoint)
        let isDragging = dragFeedback != nil || (previewChart != nil && previewChart != chart)
        guard isDragging else {
            return Presentation(controls: controlFrames(for: endingID, in: pageLayout,
                screenPointsPerDisplayedPoint: scale), candidateSegments: [], coverage: [], callout: nil,
                activeMoveSystemIndex: nil, action: nil, rangeCaption: nil, isDragging: false)
        }
        let destination = previewChart ?? chart
        let ghosts = previewSegments(for: endingID, previewChart: destination, sourceLayout: pageLayout)
        var candidateLayout = pageLayout
        for index in candidateLayout.systems.indices {
            candidateLayout.systems[index].endingLayouts.removeAll { $0.roadmapObjectID == endingID }
            let systemIndex = candidateLayout.systems[index].index
            candidateLayout.systems[index].endingLayouts += ghosts.filter { $0.systemIndex == systemIndex }
        }
        let controls = controlFrames(for: endingID, in: candidateLayout, screenPointsPerDisplayedPoint: scale)
        let sourceRows = orderedSegments(for: endingID, in: pageLayout).map { $0.0.index }
        let grabbedOffset = dragFeedback.flatMap { sourceRows.firstIndex(of: $0.sourceSystemIndex) } ?? 0
        let activeMoveSystem: Int? = controls.isEmpty ? nil : controls[min(grabbedOffset, controls.count - 1)].systemIndex
        let resolvedRange = validatedRange(dragFeedback?.range ?? range(for: endingID, in: destination), in: destination)
        let coverage = resolvedRange.map { measureCoverage(range: $0, chart: destination, pageLayout: pageLayout) } ?? []
        let activeControl: SegmentControls?
        if dragFeedback?.action == .resizeTrailing { activeControl = controls.last }
        else { activeControl = controls.first { $0.systemIndex == activeMoveSystem } ?? controls.first }
        var callout: FeedbackCallout?
        if let range = resolvedRange, let activeControl,
           let system = pageLayout.systems.first(where: { $0.index == activeControl.systemIndex }) {
            let anchor = dragFeedback?.action == .resizeTrailing
                ? (activeControl.lengthenHandle ?? activeControl.moveHandle) : activeControl.moveHandle
            let paper = pageLayout.paperFrame(for: system)
            let allObstacles = LeadSheetEndingOverlayPlacement.notationObstacles(in: pageLayout, scale: scale)
                + ghosts.map { $0.occupiedFrame.insetBy(dx: -3 / scale, dy: -3 / scale) }
            let handles = controls.flatMap { [$0.moveHandle] + ($0.lengthenHandle.map { [$0] } ?? []) }
            let size = CGSize(width: min(246 / scale, paper.width - 12 / scale), height: 52 / scale)
            let preferred = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 8 / scale)
            if let frame = LeadSheetEndingOverlayPlacement.frame(size: size, preferredOrigin: preferred,
                inside: paper, obstacles: allObstacles, reserved: handles, scale: scale,
                requiresClearSpace: true, maximumScreenOriginTravel: 240, clearanceScreenPoints: 3) {
                let count = range.upperBound - range.lowerBound + 1
                let measures = count == 1 ? "Measure \(range.lowerBound + 1)" : "Measures \(range.lowerBound + 1)–\(range.upperBound + 1)"
                let countText = count == 1 ? "1 measure" : "\(count) measures"
                let isLength = dragFeedback?.action == .resizeTrailing
                callout = FeedbackCallout(frame: frame,
                    title: dragFeedback == nil ? "Ending range" : (isLength ? "Adjust length" : "Move ending"),
                    rangeText: "\(measures) · \(countText)",
                    instruction: isLength ? "Release to set length" : "Release to place",
                    systemIndex: activeControl.systemIndex)
            }
        }
        let rangeCaption = resolvedRange.map {
            $0.lowerBound == $0.upperBound ? "Bar \($0.lowerBound + 1)" : "Bars \($0.lowerBound + 1)–\($0.upperBound + 1)"
        }
        return Presentation(controls: controls, candidateSegments: ghosts, coverage: coverage, callout: callout,
            activeMoveSystemIndex: activeMoveSystem, action: dragFeedback?.action,
            rangeCaption: rangeCaption, isDragging: true)
    }

    static func draw(
        endingID: UUID, chart: Chart, pageLayout: LeadSheetPageLayout,
        previewChart: Chart? = nil, screenPointsPerDisplayedPoint: CGFloat = 1,
        dragFeedback: LeadSheetEndingDragFeedback? = nil
    ) {
        let scale = validScale(screenPointsPerDisplayedPoint)
        let display = presentation(for: endingID, chart: chart, pageLayout: pageLayout,
            previewChart: previewChart, screenPointsPerDisplayedPoint: scale, dragFeedback: dragFeedback)
        if display.isDragging {
            for (_, source) in orderedSegments(for: endingID, in: pageLayout) {
                let baseline = UIBezierPath(roundedRect: source.frame.insetBy(dx: -3 / scale, dy: -2 / scale), cornerRadius: 4 / scale)
                UIColor.systemGray.withAlphaComponent(0.25).setStroke()
                baseline.lineWidth = 1 / scale
                baseline.setLineDash([4 / scale, 3 / scale], count: 2, phase: 0)
                baseline.stroke()
            }
            drawCoverage(display.coverage, ghosts: display.candidateSegments, scale: scale)
            drawCandidate(display.candidateSegments, chart: previewChart ?? chart, scale: scale)
        } else {
            for segment in display.controls {
                let outline = UIBezierPath(roundedRect: segment.segmentFrame.insetBy(dx: -4 / scale, dy: -3 / scale), cornerRadius: 4 / scale)
                UIColor.systemBlue.withAlphaComponent(0.045).setFill()
                outline.fill()
                UIColor.systemBlue.withAlphaComponent(0.6).setStroke()
                outline.lineWidth = 1.2 / scale
                outline.stroke()
            }
        }
        for segment in display.controls {
            drawLeader(from: segment.moveHandle, to: segment.moveAttachment, scale: scale,
                muted: display.isDragging && display.action != .move)
            if let frame = segment.lengthenHandle, let attachment = segment.lengthAttachment {
                drawLeader(from: frame, to: attachment, scale: scale,
                    muted: display.isDragging && display.action != .resizeTrailing)
            }
            let moveActive = display.isDragging && display.action == .move && segment.systemIndex == display.activeMoveSystemIndex
            drawControl(segment.moveHandle, title: "Move", isMove: true, scale: scale,
                active: moveActive, secondary: display.isDragging && !moveActive,
                rangeCaption: moveActive && display.callout == nil ? display.rangeCaption : nil)
            if let frame = segment.lengthenHandle {
                let lengthActive = display.isDragging && display.action == .resizeTrailing
                drawControl(frame, title: "Lengthen", isMove: false, scale: scale,
                    active: lengthActive, secondary: display.isDragging && !lengthActive,
                    rangeCaption: lengthActive && display.callout == nil ? display.rangeCaption : nil)
            }
        }
        if let callout = display.callout { drawCallout(callout, scale: scale) }
    }

    /// Glyphs use production layout, translated back onto source staff rows so
    /// changing an ending does not move the chart underneath a live gesture.
    static func previewSegments(
        for endingID: UUID, previewChart: Chart, sourceLayout: LeadSheetPageLayout
    ) -> [LeadSheetEndingLayout] {
        let includesContinuation = sourceLayout.systems.contains { $0.measures.contains { $0.sourceMeasureID == nil } }
        let preview = LeadSheetPageLayoutEngine.pageLayout(for: previewChart,
            pageSize: sourceLayout.pageBounds.size, includesChordInkContinuationLanes: includesContinuation)
        return preview.systems.flatMap { system -> [LeadSheetEndingLayout] in
            guard let source = sourceLayout.systems.first(where: { $0.id == system.id })
                    ?? sourceLayout.systems.first(where: { $0.index == system.index }) else { return [] }
            let sourceAnchor = source.measures.first?.staffFrame.origin ?? source.frame.origin
            let previewAnchor = system.measures.first?.staffFrame.origin ?? system.frame.origin
            let dx = sourceAnchor.x - previewAnchor.x, dy = sourceAnchor.y - previewAnchor.y
            return system.endingLayouts.filter { $0.roadmapObjectID == endingID }.map {
                var ending = $0
                ending.frame = ending.frame.offsetBy(dx: dx, dy: dy)
                if !ending.labelFrame.isEmpty { ending.labelFrame = ending.labelFrame.offsetBy(dx: dx, dy: dy) }
                return ending
            }
        }.sorted { $0.systemIndex < $1.systemIndex }
    }

    private static func orderedSegments(for endingID: UUID, in layout: LeadSheetPageLayout) -> [(LeadSheetSystemLayout, LeadSheetEndingLayout)] {
        layout.systems.flatMap { system in
            system.endingLayouts.filter { $0.roadmapObjectID == endingID }.map { (system, $0) }
        }.sorted {
            if $0.0.index != $1.0.index { return $0.0.index < $1.0.index }
            return $0.1.frame.minX < $1.1.frame.minX
        }
    }

    private static func range(for endingID: UUID, in chart: Chart) -> ClosedRange<Int>? {
        guard let object = chart.roadmapObject(id: endingID),
              let start = chart.measures.firstIndex(where: { $0.id == object.startMeasureID }),
              let end = chart.measures.firstIndex(where: { $0.id == (object.endMeasureID ?? object.startMeasureID) }), start <= end else { return nil }
        return start...end
    }

    private static func validatedRange(_ range: ClosedRange<Int>?, in chart: Chart) -> ClosedRange<Int>? {
        guard let range, range.lowerBound >= 0, range.upperBound < chart.measures.count else { return nil }
        return range
    }

    private static func measureCoverage(range: ClosedRange<Int>, chart: Chart, pageLayout: LeadSheetPageLayout) -> [MeasureCoverage] {
        let positions = Dictionary(uniqueKeysWithValues: chart.measures.enumerated().map { ($0.element.id, $0.offset) })
        return pageLayout.systems.flatMap { system in
            system.measures.compactMap { measure -> MeasureCoverage? in
                guard let id = measure.sourceMeasureID, let index = positions[id], range.contains(index) else { return nil }
                let display = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(measure,
                    in: system, paperFrame: pageLayout.paperFrame(for: system), layoutStyle: chart.layoutStyle)
                return MeasureCoverage(measureIndex: index, systemIndex: system.index, frame: display.frame)
            }
        }.sorted { $0.measureIndex < $1.measureIndex }
    }

    private static func drawCoverage(_ coverage: [MeasureCoverage], ghosts: [LeadSheetEndingLayout], scale: CGFloat) {
        for target in coverage {
            let path = UIBezierPath(roundedRect: target.frame.insetBy(dx: 1 / scale, dy: 1 / scale), cornerRadius: 4 / scale)
            UIColor.systemBlue.withAlphaComponent(0.045).setFill()
            path.fill()
        }
        let endpoints: [(MeasureCoverage?, Bool)] = [(coverage.first, true), (coverage.last, false)]
        for (optionalTarget, isStart) in endpoints {
            guard let target = optionalTarget else { continue }
            let x = isStart ? target.frame.minX : target.frame.maxX
            let top = ghosts.first { $0.systemIndex == target.systemIndex }?.frame.minY ?? target.frame.minY
            let line = UIBezierPath()
            line.move(to: CGPoint(x: x, y: top - 3 / scale))
            line.addLine(to: CGPoint(x: x, y: target.frame.maxY + 4 / scale))
            line.lineWidth = 1.7 / scale
            UIColor.systemBlue.withAlphaComponent(0.7).setStroke()
            line.stroke()
        }
    }

    private static func drawCandidate(_ ghosts: [LeadSheetEndingLayout], chart: Chart, scale: CGFloat) {
        let renderer = LeadSheetNotationRenderer(chart: chart)
        for ghost in ghosts {
            let bounds = ghost.occupiedFrame.insetBy(dx: -3 / scale, dy: -3 / scale)
            guard isFinite(bounds) else { continue }
            let format = UIGraphicsImageRendererFormat()
            format.scale = min(2, max(1, scale))
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
                context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
                renderer.drawEnding(ghost)
            }.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            image.draw(in: bounds, blendMode: .normal, alpha: 0.98)
        }
    }

    private static func drawLeader(from frame: CGRect, to attachment: CGPoint, scale: CGFloat, muted: Bool) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: clamped(attachment.x, lower: frame.minX, upper: frame.maxX),
            y: clamped(attachment.y, lower: frame.minY, upper: frame.maxY)))
        path.addLine(to: attachment)
        path.lineWidth = 1.1 / scale
        UIColor.systemBlue.withAlphaComponent(muted ? 0.2 : 0.5).setStroke()
        path.stroke()
    }

    private static func drawControl(
        _ frame: CGRect, title: String, isMove: Bool, scale: CGFloat,
        active: Bool, secondary: Bool, rangeCaption: String?
    ) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setShadow(offset: CGSize(width: 0, height: (active ? 3 : 1) / scale),
            blur: (active ? 8 : 3) / scale, color: UIColor.black.withAlphaComponent(active ? 0.16 : 0.07).cgColor)
        let path = UIBezierPath(roundedRect: frame, cornerRadius: 14 / scale)
        (active ? UIColor.systemBlue : UIColor(red: 0.98, green: 0.99, blue: 1, alpha: 0.98)).setFill()
        path.fill()
        context?.restoreGState()
        UIColor.systemBlue.withAlphaComponent(secondary ? 0.25 : 0.65).setStroke()
        path.lineWidth = 1 / scale
        path.stroke()
        let color = active ? UIColor.white : UIColor.systemBlue.withAlphaComponent(secondary ? 0.5 : 1)
        color.setStroke()
        let center = CGPoint(x: frame.minX + 18 / scale, y: frame.midY)
        let arrows = UIBezierPath()
        let radius = 7 / scale
        arrows.move(to: CGPoint(x: center.x - radius, y: center.y))
        arrows.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        for direction: CGFloat in [-1, 1] {
            let x = center.x + radius * direction
            arrows.move(to: CGPoint(x: x - 3 / scale * direction, y: center.y - 3 / scale))
            arrows.addLine(to: CGPoint(x: x, y: center.y))
            arrows.addLine(to: CGPoint(x: x - 3 / scale * direction, y: center.y + 3 / scale))
        }
        if isMove {
            arrows.move(to: CGPoint(x: center.x, y: center.y - radius))
            arrows.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            for direction: CGFloat in [-1, 1] {
                let y = center.y + radius * direction
                arrows.move(to: CGPoint(x: center.x - 3 / scale, y: y - 3 / scale * direction))
                arrows.addLine(to: CGPoint(x: center.x, y: y))
                arrows.addLine(to: CGPoint(x: center.x + 3 / scale, y: y - 3 / scale * direction))
            }
        }
        arrows.lineWidth = 1.6 / scale
        arrows.lineCapStyle = .round
        arrows.lineJoinStyle = .round
        arrows.stroke()
        let font = UIFont.systemFont(ofSize: 13 / scale, weight: .semibold)
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        let titleY = rangeCaption == nil ? frame.midY - textSize.height / 2 : frame.minY + 6 / scale
        (title as NSString).draw(at: CGPoint(x: frame.minX + 34 / scale, y: titleY),
            withAttributes: [.font: font, .foregroundColor: color])
        if let rangeCaption {
            let available = max(1, frame.width - 40 / scale)
            let baseFont = UIFont.systemFont(ofSize: 10.5 / scale, weight: .medium)
            let width = (rangeCaption as NSString).size(withAttributes: [.font: baseFont]).width
            let size = max(8.5, min(10.5, 10.5 * available / max(1, width))) / scale
            (rangeCaption as NSString).draw(at: CGPoint(x: frame.minX + 34 / scale, y: frame.minY + 25 / scale),
                withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium),
                    .foregroundColor: color.withAlphaComponent(0.95)])
        }
    }

    private static func drawCallout(_ callout: FeedbackCallout, scale: CGFloat) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setShadow(offset: CGSize(width: 0, height: 3 / scale), blur: 9 / scale,
            color: UIColor.black.withAlphaComponent(0.13).cgColor)
        let path = UIBezierPath(roundedRect: callout.frame, cornerRadius: 12 / scale)
        UIColor.systemBlue.withAlphaComponent(0.97).setFill()
        path.fill()
        context?.restoreGState()
        let x = callout.frame.minX + 12 / scale
        let lines: [(String, CGFloat, UIFont.Weight, CGFloat, CGFloat)] = [
            (callout.title, 13, .semibold, 4, 1),
            (callout.rangeText, 11.5, .medium, 21, 0.95),
            (callout.instruction, 10.5, .regular, 37, 0.8)
        ]
        for (text, size, weight, y, alpha) in lines {
            (text as NSString).draw(at: CGPoint(x: x, y: callout.frame.minY + y / scale),
                withAttributes: [.font: UIFont.systemFont(ofSize: size / scale, weight: weight),
                    .foregroundColor: UIColor.white.withAlphaComponent(alpha)])
        }
    }

    private static func validScale(_ scale: CGFloat) -> CGFloat { scale.isFinite && scale > 0 ? scale : 1 }
    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat { min(max(value, lower), max(lower, upper)) }
    private static func isFinite(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && !frame.isInfinite
            && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }
}
#endif
