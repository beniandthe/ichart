#if canImport(UIKit)
import Foundation
import UIKit

struct LeadSheetChordEditControlFrames {
    let delete: CGRect
}

struct ChordEditHitTarget {
    enum Action: Equatable {
        case select
        case delete
        case move
        case review
    }

    var measureID: UUID
    var chordID: UUID
    var action: Action
}

enum LeadSheetChordEditOverlayGeometry {
    static let controlSize: CGFloat = 18
    static let controlHitOutset: CGFloat = 12

    static func editFrame(for chordLayout: LeadSheetChordLayout) -> CGRect {
        CGRect(
            x: chordLayout.frame.minX - 6,
            y: chordLayout.frame.minY - 2,
            width: chordLayout.frame.width + 12,
            height: max(28, chordLayout.frame.height + 4)
        )
    }

    static func controlFrames(for chordLayout: LeadSheetChordLayout) -> LeadSheetChordEditControlFrames {
        let editFrame = editFrame(for: chordLayout)
        let originY = editFrame.minY - controlSize / 2

        return LeadSheetChordEditControlFrames(
            delete: CGRect(
                x: editFrame.minX - controlSize / 2,
                y: originY,
                width: controlSize,
                height: controlSize
            )
        )
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
                let controls = controlFrames(for: chordLayout)
                if controls.delete.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
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
                let controlFrames = controlFrames(for: chordLayout)
                if controlFrames.delete.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                    return ChordEditHitTarget(
                        measureID: measureID,
                        chordID: chordLayout.id,
                        action: .delete
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
    var movementFrame: CGRect
}

struct ActiveCueTextMoveDrag {
    var cueTextID: UUID
    var startLocation: CGPoint
    var startingVerticalOffset: Double
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

    static func hitTarget(
        at location: CGPoint,
        in cueTextLayouts: [LeadSheetCueTextLayout],
        selectedCueTextID: UUID?
    ) -> CueTextEditHitTarget? {
        for cueTextLayout in cueTextLayouts.reversed() {
            let isSelected = selectedCueTextID == cueTextLayout.id
            let controlFrames = controlFrames(for: cueTextLayout)

            if isSelected {
                if controlFrames.delete.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                    return CueTextEditHitTarget(cueTextID: cueTextLayout.id, action: .delete)
                }
                if controlFrames.edit.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                    return CueTextEditHitTarget(cueTextID: cueTextLayout.id, action: .edit)
                }
                if controlFrames.shrink.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                    return CueTextEditHitTarget(cueTextID: cueTextLayout.id, action: .shrink)
                }
                if controlFrames.grow.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                    return CueTextEditHitTarget(cueTextID: cueTextLayout.id, action: .grow)
                }
            }

            if editHitFrame(for: cueTextLayout).contains(location) {
                return CueTextEditHitTarget(cueTextID: cueTextLayout.id, action: .select)
            }
        }

        return nil
    }

    static func moveHitTarget(
        at location: CGPoint,
        in cueTextLayouts: [LeadSheetCueTextLayout]
    ) -> LeadSheetCueTextLayout? {
        for cueTextLayout in cueTextLayouts.reversed() {
            if editFrame(for: cueTextLayout).insetBy(dx: -editFrameHitOutset, dy: -editFrameHitOutset).contains(location) {
                return cueTextLayout
            }
        }

        return nil
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
        let minimumHeight: CGFloat = markerLayout.type.containsNotationMarkerGlyph ? 40 : 24
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

final class ChordEditHitOverlayView: UIView {
    var containsEditableControl: ((CGPoint) -> Bool)?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, isUserInteractionEnabled else {
            return false
        }

        return containsEditableControl?(point) ?? false
    }
}
#endif
