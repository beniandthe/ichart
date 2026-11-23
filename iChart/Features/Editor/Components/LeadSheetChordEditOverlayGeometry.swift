#if canImport(UIKit)
import Foundation
import UIKit

struct LeadSheetChordEditControlFrames {
    let delete: CGRect
    let leadingResize: CGRect
    let trailingResize: CGRect
}

struct ChordEditHitTarget {
    enum Action: Equatable {
        case select
        case delete
        case move
        case review
        case resizeLeading
        case resizeTrailing
    }

    var measureID: UUID
    var chordID: UUID
    var action: Action
}

enum LeadSheetChordEditOverlayGeometry {
    static let controlSize: CGFloat = 18
    static let controlHitOutset: CGFloat = 12

    static func editFrame(for chordLayout: LeadSheetChordLayout) -> CGRect {
        chordLayout.frame.insetBy(dx: -2, dy: -2)
    }

    static func bodySelectionFrame(for chordLayout: LeadSheetChordLayout) -> CGRect {
        editFrame(for: chordLayout)
    }

    static func selectedMoveBodyFrame(for chordLayout: LeadSheetChordLayout) -> CGRect {
        editFrame(for: chordLayout).insetBy(dx: -8, dy: -8)
    }

    static func controlFrames(for chordLayout: LeadSheetChordLayout,
        in pageLayout: LeadSheetPageLayout,
        screenPointsPerDisplayedPoint: CGFloat = 1) -> LeadSheetChordEditControlFrames {
        controlFrames(for: chordLayout, within: pageLayout.pageBounds,
            avoiding: pageLayout.systems.flatMap(\.measures).flatMap(\.chordLayouts)
                .filter { $0.id != chordLayout.id }.map { bodySelectionFrame(for: $0) },
            screenPointsPerDisplayedPoint: screenPointsPerDisplayedPoint)
    }

    static func resizeHitFrame(for control: CGRect, edge: ActiveChordResizeDrag.Edge,
        screenPointsPerDisplayedPoint: CGFloat = 1) -> CGRect {
        let outset = controlHitOutset / max(0.05, screenPointsPerDisplayedPoint)
        // Keep the generous target on the outside of the glyph instead of
        // padding back across its move/select body. The visible grip stays
        // directly beside the rendered edge.
        return CGRect(x: edge == .leading ? control.minX - 2 * outset : control.minX,
            y: control.minY - outset, width: control.width + 2 * outset,
            height: control.height + 2 * outset)
    }

    static func controlFrames(for chordLayout: LeadSheetChordLayout,
        within canvasBounds: CGRect? = nil, avoiding otherBodies: [CGRect] = [],
        screenPointsPerDisplayedPoint: CGFloat = 1) -> LeadSheetChordEditControlFrames {
        let editFrame = editFrame(for: chordLayout)
        let scale = max(0.05, screenPointsPerDisplayedPoint)
        let size = controlSize / scale
        let outset = controlHitOutset / scale
        let gap = 2 / scale
        var delete = CGRect(x: editFrame.minX - size / 2,
            y: editFrame.minY - size - outset - 8 / scale, width: size, height: size)
        if let canvasBounds, canvasBounds.width >= size + 2 * outset {
            delete.origin.x = min(max(delete.minX, canvasBounds.minX + outset),
                canvasBounds.maxX - size - outset)
            delete.origin.y = min(max(delete.minY, canvasBounds.minY + outset),
                canvasBounds.maxY - size - outset)
        }
        let deleteHit = delete.insetBy(dx: -outset, dy: -outset)
        let protected = [editFrame] + otherBodies + [deleteHit]

        func placedHandle(edge: ActiveChordResizeDrag.Edge, avoiding occupied: [CGRect]) -> CGRect {
            var preferred = CGRect(x: edge == .leading ? editFrame.minX - gap - size : editFrame.maxX + gap,
                y: editFrame.midY - size / 2, width: size, height: size)
            if let canvasBounds, canvasBounds.width >= size + 2 * outset {
                // An edge grip may need to lift above the glyph, but its full
                // touch target must remain on the page even at a paper edge.
                let minimumX = canvasBounds.minX + (edge == .leading ? 2 * outset : 0)
                let maximumX = canvasBounds.maxX - size - (edge == .trailing ? 2 * outset : 0)
                preferred.origin.x = min(max(preferred.minX, minimumX), maximumX)
            }
            let hit = resizeHitFrame(for: preferred, edge: edge, screenPointsPerDisplayedPoint: scale)
            let obstacles = occupied.filter { $0.minX < hit.maxX && $0.maxX > hit.minX }
            var ys = [preferred.minY]
            for obstacle in obstacles {
                ys.append(obstacle.minY - size - outset - gap)
                ys.append(obstacle.maxY + outset + gap)
            }
            if let canvasBounds {
                ys.append(canvasBounds.minY + outset)
                ys.append(canvasBounds.maxY - size - outset)
            }
            ys.sort { lhs, rhs in
                let leftDistance = abs(lhs - preferred.minY)
                let rightDistance = abs(rhs - preferred.minY)
                return leftDistance == rightDistance ? lhs < rhs : leftDistance < rightDistance
            }
            for y in ys {
                let candidate = CGRect(x: preferred.minX, y: y, width: size, height: size)
                let target = resizeHitFrame(for: candidate, edge: edge, screenPointsPerDisplayedPoint: scale)
                if let canvasBounds, !canvasBounds.contains(target) { continue }
                if !obstacles.contains(where: { $0.intersects(target) }) { return candidate }
            }
            return preferred
        }
        let leading = placedHandle(edge: .leading, avoiding: protected)
        let leadingHit = resizeHitFrame(for: leading, edge: .leading, screenPointsPerDisplayedPoint: scale)
        let trailing = placedHandle(edge: .trailing, avoiding: protected + [leadingHit])
        return LeadSheetChordEditControlFrames(delete: delete,
            leadingResize: leading, trailingResize: trailing)
    }

    static func resizeHitTarget(
        at location: CGPoint,
        in pageLayout: LeadSheetPageLayout,
        selectedChordID: UUID?
    ) -> ChordEditHitTarget? {
        guard let selectedChordID else {
            return nil
        }

        let measures = pageLayout.systems.flatMap(\.measures)
        for measure in measures.reversed() {
            guard let measureID = measure.sourceMeasureID else {
                continue
            }

            for chordLayout in measure.chordLayouts.reversed() where chordLayout.id == selectedChordID {
                let controls = controlFrames(for: chordLayout, in: pageLayout)
                let handles: [(CGRect, ActiveChordResizeDrag.Edge, ChordEditHitTarget.Action)] = [
                    (controls.leadingResize, .leading, .resizeLeading),
                    (controls.trailingResize, .trailing, .resizeTrailing)
                ]
                for (frame, edge, action) in handles where resizeHitFrame(for: frame, edge: edge).contains(location) {
                    return ChordEditHitTarget(
                        measureID: measureID,
                        chordID: chordLayout.id,
                        action: action
                    )
                }
            }
        }

        return nil
    }

    static func moveHitTarget(
        at location: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> ChordEditHitTarget? {
        let measures = pageLayout.systems.flatMap(\.measures)
        for measure in measures.reversed() {
            guard let measureID = measure.sourceMeasureID else {
                continue
            }

            for chordLayout in measure.chordLayouts.reversed() {
                let controls = controlFrames(for: chordLayout, in: pageLayout)
                if controls.delete.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                    continue
                }
                if resizeHitFrame(for: controls.leadingResize, edge: .leading).contains(location)
                    || resizeHitFrame(for: controls.trailingResize, edge: .trailing).contains(location) {
                    continue
                }

                guard editFrame(for: chordLayout).insetBy(dx: -8, dy: -8).contains(location) else {
                    continue
                }

                return ChordEditHitTarget(
                    measureID: measureID,
                    chordID: chordLayout.id,
                    action: .move
                )
            }
        }

        return nil
    }

    static func hitTarget(
        at location: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> ChordEditHitTarget? {
        let measures = pageLayout.systems.flatMap(\.measures)
        for measure in measures.reversed() {
            guard let measureID = measure.sourceMeasureID else {
                continue
            }

            for chordLayout in measure.chordLayouts.reversed() {
                let controlFrames = controlFrames(for: chordLayout, in: pageLayout)
                if controlFrames.delete.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                    return ChordEditHitTarget(
                        measureID: measureID,
                        chordID: chordLayout.id,
                        action: .delete
                    )
                }
                if resizeHitFrame(for: controlFrames.leadingResize, edge: .leading).contains(location) {
                    return ChordEditHitTarget(measureID: measureID, chordID: chordLayout.id, action: .resizeLeading)
                }
                if resizeHitFrame(for: controlFrames.trailingResize, edge: .trailing).contains(location) {
                    return ChordEditHitTarget(
                        measureID: measureID,
                        chordID: chordLayout.id,
                        action: .resizeTrailing
                    )
                }

                if editFrame(for: chordLayout).insetBy(dx: -8, dy: -8).contains(location) {
                    return ChordEditHitTarget(
                        measureID: measureID,
                        chordID: chordLayout.id,
                        action: .review
                    )
                }
            }
        }

        return nil
    }
}

enum LeadSheetChordObjectInteractionPolicy {
    static func resolvedTapTarget(
        _ hitTarget: ChordEditHitTarget?,
        selectedChordID: UUID?,
        requiresSelectionBeforeAction: Bool
    ) -> ChordEditHitTarget? {
        guard let hitTarget else {
            return nil
        }

        guard requiresSelectionBeforeAction,
              selectedChordID != hitTarget.chordID else {
            return hitTarget
        }

        return ChordEditHitTarget(
            measureID: hitTarget.measureID,
            chordID: hitTarget.chordID,
            action: .select
        )
    }

    static func resolvedMoveTarget(
        _ hitTarget: ChordEditHitTarget?,
        selectedChordID: UUID?,
        requiresSelectionBeforeMove: Bool
    ) -> ChordEditHitTarget? {
        guard let hitTarget else {
            return nil
        }

        guard requiresSelectionBeforeMove else {
            return hitTarget
        }

        return selectedChordID == hitTarget.chordID ? hitTarget : nil
    }

    static func shouldDrawBox(
        for chordID: UUID,
        selectedChordID: UUID?,
        activeMoveChordID: UUID?,
        drawsAllBoxes: Bool
    ) -> Bool {
        drawsAllBoxes
            || selectedChordID == chordID
            || activeMoveChordID == chordID
    }

    static func shouldDrawControls(
        for chordID: UUID,
        selectedChordID: UUID?,
        activeMoveChordID: UUID?,
        drawsAllControls: Bool
    ) -> Bool {
        drawsAllControls
            || selectedChordID == chordID
            || activeMoveChordID == chordID
    }
}

struct LeadSheetRoadmapMarkerEditControlFrames {
    let delete: CGRect
}

struct RoadmapMarkerEditHitTarget {
    enum Action {
        case select
        case delete
        case move
    }

    var markerID: UUID
    var action: Action
}

struct ActiveRoadmapMarkerEditDrag {
    var markerID: UUID
    var initialFrame: CGRect
    var currentFrame: CGRect
    var movementFrame: CGRect
}

struct ActiveCueTextMoveDrag {
    var cueTextID: UUID
    var startLocation: CGPoint
    var initialFrame: CGRect
    var currentFrame: CGRect
    var startingVerticalOffset: Double
    var sourceChart: Chart
    var sourcePageLayout: LeadSheetPageLayout
    var sourcePageSize: CGSize
    var sourceCue: CueText
    var sourceMeasure: LeadSheetMeasureLayout
    var screenPointsPerDisplayedPoint: CGFloat
    var currentProjection: LeadSheetCueTextMoveProjection?
    var anchorLayouts: [LeadSheetCueTextMoveAnchor: LeadSheetCueTextMoveAnchorLayout] = [:]
    var lastProjectionKey: LeadSheetCueTextMoveProjectionKey?
    var pageLayoutProjectionCount = 0

    init?(cueTextID: UUID, chart: Chart, pageLayout: LeadSheetPageLayout, pageSize: CGSize,
        startLocation: CGPoint, screenPointsPerDisplayedPoint: CGFloat = 1) {
        guard let cue = chart.cueText(id: cueTextID),
              let measure = pageLayout.systems.flatMap(\.measures).first(where: {
                  $0.sourceMeasureID == cue.anchorMeasureID
              }), let layout = measure.cueTextLayouts.first(where: { $0.id == cueTextID }) else { return nil }
        self.cueTextID = cueTextID
        self.startLocation = startLocation
        initialFrame = layout.frame
        currentFrame = layout.frame
        // Saved requests may exceed the room available in this row. Continue
        // from the visible cue, so one drag back responds immediately.
        startingVerticalOffset = Double(layout.verticalOffsetFromDefault)
        sourceChart = chart
        sourcePageLayout = pageLayout
        sourcePageSize = pageSize
        sourceCue = cue
        sourceMeasure = measure
        self.screenPointsPerDisplayedPoint = max(0.0001, screenPointsPerDisplayedPoint)
        currentProjection = LeadSheetCueTextMoveProjection(measureID: cue.anchorMeasureID,
            fraction: cue.beatFraction, verticalOffset: cue.verticalOffset, cueLayout: layout)
        let anchor = LeadSheetCueTextMoveAnchor(measureID: cue.anchorMeasureID, fraction: cue.beatFraction)
        anchorLayouts[anchor] = LeadSheetCueTextMoveAnchorLayout(pageLayout: pageLayout,
            verticalOffset: cue.verticalOffset, cueLayout: layout)
    }
}

struct LeadSheetCueTextEditControlFrames {
    let edit: CGRect
    let shrink: CGRect
    let grow: CGRect
    let delete: CGRect
}

struct CueTextEditHitTarget {
    enum Action {
        case select
        case edit
        case shrink
        case grow
        case delete
    }

    var cueTextID: UUID
    var action: Action
}

enum LeadSheetCueTextEditOverlayGeometry {
    static let controlSize: CGFloat = 20
    static let controlGap: CGFloat = 5
    static let controlHitOutset: CGFloat = 7
    static let editFrameHitOutset: CGFloat = 8

    static func editFrame(for cueTextLayout: LeadSheetCueTextLayout) -> CGRect {
        let paddedFrame = cueTextLayout.frame.insetBy(dx: -5, dy: -4)
        return CGRect(
            x: paddedFrame.minX,
            y: paddedFrame.minY,
            width: max(32, paddedFrame.width),
            height: max(22, paddedFrame.height)
        )
    }

    static func editHitFrame(for cueTextLayout: LeadSheetCueTextLayout) -> CGRect {
        editFrame(for: cueTextLayout).insetBy(dx: -editFrameHitOutset, dy: -editFrameHitOutset)
    }

    static func controlFrames(for cueTextLayout: LeadSheetCueTextLayout) -> LeadSheetCueTextEditControlFrames {
        let editFrame = editFrame(for: cueTextLayout)
        let originY = editFrame.minY - controlSize - 4
        let startX = editFrame.minX
        let controlStep = controlSize + controlGap

        return LeadSheetCueTextEditControlFrames(
            edit: CGRect(x: startX, y: originY, width: controlSize, height: controlSize),
            shrink: CGRect(
                x: startX + controlStep,
                y: originY,
                width: controlSize,
                height: controlSize
            ),
            grow: CGRect(
                x: startX + controlStep * 2,
                y: originY,
                width: controlSize,
                height: controlSize
            ),
            delete: CGRect(
                x: startX + controlStep * 3,
                y: originY,
                width: controlSize,
                height: controlSize
            )
        )
    }

    static func controlHitFrames(for cueTextLayout: LeadSheetCueTextLayout) -> LeadSheetCueTextEditControlFrames {
        let controls = controlFrames(for: cueTextLayout)
        let frames = [controls.edit, controls.shrink, controls.grow, controls.delete]
        let hits = frames.enumerated().map { index, frame in
            let padded = frame.insetBy(dx: -controlHitOutset, dy: -controlHitOutset)
            let minX = index == 0 ? padded.minX : (frames[index - 1].maxX + frame.minX) / 2
            let maxX = index == frames.count - 1 ? padded.maxX : (frame.maxX + frames[index + 1].minX) / 2
            return CGRect(x: minX, y: padded.minY, width: maxX - minX, height: padded.height)
        }
        return LeadSheetCueTextEditControlFrames(edit: hits[0], shrink: hits[1], grow: hits[2], delete: hits[3])
    }

    static func bodyHitTarget(
        at location: CGPoint,
        in cueTextLayouts: [LeadSheetCueTextLayout]
    ) -> LeadSheetCueTextLayout? {
        func nearest(in candidates: [LeadSheetCueTextLayout], frame: (LeadSheetCueTextLayout) -> CGRect) -> LeadSheetCueTextLayout? {
            candidates.reduce(nil) { best, cue in
                guard let best else { return cue }
                let candidate = frame(cue), existing = frame(best)
                let candidateDistance = hypot(candidate.midX - location.x, candidate.midY - location.y)
                let existingDistance = hypot(existing.midX - location.x, existing.midY - location.y)
                return candidateDistance < existingDistance ? cue : best
            }
        }
        let visible = cueTextLayouts.filter { $0.frame.contains(location) }
        if !visible.isEmpty { return nearest(in: visible, frame: { $0.frame }) }
        return nearest(in: cueTextLayouts.filter { editHitFrame(for: $0).contains(location) },
            frame: { editHitFrame(for: $0) })
    }

    static func hitTarget(
        at location: CGPoint,
        in cueTextLayouts: [LeadSheetCueTextLayout],
        selectedCueTextID: UUID?
    ) -> CueTextEditHitTarget? {
        let selected = cueTextLayouts.first { $0.id == selectedCueTextID }
        func controlTarget(_ controls: LeadSheetCueTextEditControlFrames, cue: LeadSheetCueTextLayout) -> CueTextEditHitTarget? {
            for (frame, action) in [(controls.edit, CueTextEditHitTarget.Action.edit),
                (controls.shrink, .shrink), (controls.grow, .grow), (controls.delete, .delete)] {
                if frame.contains(location) { return CueTextEditHitTarget(cueTextID: cue.id, action: action) }
            }
            return nil
        }
        if let selected, let control = controlTarget(controlFrames(for: selected), cue: selected) { return control }
        if cueTextLayouts.contains(where: { $0.frame.contains(location) }),
           let cue = bodyHitTarget(at: location, in: cueTextLayouts) {
            return CueTextEditHitTarget(cueTextID: cue.id, action: .select)
        }
        if let selected, let control = controlTarget(controlHitFrames(for: selected), cue: selected) { return control }
        guard let cue = bodyHitTarget(at: location, in: cueTextLayouts) else { return nil }
        return CueTextEditHitTarget(cueTextID: cue.id, action: .select)
    }

    static func moveHitTarget(
        at location: CGPoint,
        in cueTextLayouts: [LeadSheetCueTextLayout]
    ) -> LeadSheetCueTextLayout? {
        bodyHitTarget(at: location, in: cueTextLayouts)
    }

}

enum LeadSheetRoadmapMarkerEditOverlayGeometry {
    static let controlSize: CGFloat = 18
    static let controlHitOutset: CGFloat = 6
    static let editFrameHitOutset: CGFloat = 14

    static func editFrame(for markerLayout: LeadSheetRoadmapMarkerLayout) -> CGRect {
        let horizontalPadding: CGFloat = markerLayout.type.isStandaloneNotationMarker ? 3 : 4
        let verticalPadding: CGFloat = 2
        let minimumWidth: CGFloat = markerLayout.type.isStandaloneNotationMarker ? 44 : 28
        let minimumHeight: CGFloat = markerLayout.type.containsNotationMarkerGlyph ? 44 : 24
        let paddedFrame = markerLayout.frame.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        let width = max(minimumWidth, paddedFrame.width)
        let height = max(minimumHeight, paddedFrame.height)
        return CGRect(
            x: paddedFrame.midX - width / 2,
            y: paddedFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func editHitFrame(for markerLayout: LeadSheetRoadmapMarkerLayout) -> CGRect {
        editFrame(for: markerLayout).insetBy(dx: -editFrameHitOutset, dy: -editFrameHitOutset)
    }

    static func controlFrames(
        for markerLayout: LeadSheetRoadmapMarkerLayout
    ) -> LeadSheetRoadmapMarkerEditControlFrames {
        let editFrame = editFrame(for: markerLayout)
        return LeadSheetRoadmapMarkerEditControlFrames(
            delete: CGRect(
                x: editFrame.minX - controlSize / 2,
                y: editFrame.minY - controlSize / 2,
                width: controlSize,
                height: controlSize
            )
        )
    }

    static func hitTarget(
        at location: CGPoint,
        in markerLayouts: [LeadSheetRoadmapMarkerLayout],
        selectedMarkerID: UUID?
    ) -> RoadmapMarkerEditHitTarget? {
        for markerLayout in markerLayouts.reversed() {
            let isSelected = selectedMarkerID == markerLayout.id
            let controlFrames = controlFrames(for: markerLayout)

            if isSelected,
               controlFrames.delete.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                return RoadmapMarkerEditHitTarget(markerID: markerLayout.id, action: .delete)
            }

            if editHitFrame(for: markerLayout).contains(location) {
                return RoadmapMarkerEditHitTarget(markerID: markerLayout.id, action: .select)
            }
        }

        return nil
    }

    static func moveHitTarget(
        at location: CGPoint,
        in markerLayouts: [LeadSheetRoadmapMarkerLayout]
    ) -> LeadSheetRoadmapMarkerLayout? {
        for markerLayout in markerLayouts.reversed() {
            let controlFrames = controlFrames(for: markerLayout)
            if controlFrames.delete.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                continue
            }

            if editHitFrame(for: markerLayout).contains(location) {
                return markerLayout
            }
        }

        return nil
    }

    static func clampedFrame(_ frame: CGRect, in movementFrame: CGRect) -> CGRect {
        let width = min(max(1, frame.width), max(1, movementFrame.width))
        let x = min(
            max(frame.minX, movementFrame.minX),
            max(movementFrame.minX, movementFrame.maxX - width)
        )
        return CGRect(
            x: x,
            y: movementFrame.minY + (movementFrame.height - frame.height) / 2,
            width: width,
            height: frame.height
        )
    }

    static func normalizedOffset(for frame: CGRect, in movementFrame: CGRect) -> Double {
        let availableWidth = movementFrame.width - frame.width
        guard availableWidth > 0 else {
            return 0
        }

        return Double((frame.minX - movementFrame.minX) / availableWidth)
    }
}

#endif
