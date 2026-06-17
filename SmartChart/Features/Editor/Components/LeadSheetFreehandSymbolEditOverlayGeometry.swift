#if canImport(UIKit)
import Foundation
import UIKit

struct LeadSheetFreehandSymbolEditControlFrames {
    let delete: CGRect
    let move: CGRect
}

struct FreehandSymbolEditHitTarget {
    enum Action {
        case delete
        case move
        case select
    }

    var symbolID: UUID
    var action: Action
}

struct ActiveFreehandSymbolEditDrag {
    var symbolID: UUID
    var initialFrame: CGRect
    var laneFrame: CGRect
}

enum LeadSheetFreehandSymbolEditOverlayGeometry {
    static let controlSize: CGFloat = 18
    static let controlHitOutset: CGFloat = 12
    static let editFrameHitOutset: CGFloat = 8
    static let selectedDragHitOutset: CGFloat = 22

    static func editFrame(for symbolLayout: LeadSheetFreehandSymbolLayout) -> CGRect {
        let paddedFrame = symbolLayout.frame.insetBy(dx: -8, dy: -8)
        let width = max(34, paddedFrame.width)
        let height = max(26, paddedFrame.height)
        return CGRect(
            x: paddedFrame.midX - width / 2,
            y: paddedFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func editHitFrame(for symbolLayout: LeadSheetFreehandSymbolLayout) -> CGRect {
        editFrame(for: symbolLayout).insetBy(dx: -editFrameHitOutset, dy: -editFrameHitOutset)
    }

    static func selectedDragFrame(for symbolLayout: LeadSheetFreehandSymbolLayout) -> CGRect {
        editFrame(for: symbolLayout).insetBy(dx: -selectedDragHitOutset, dy: -selectedDragHitOutset)
    }

    static func controlFrames(
        for symbolLayout: LeadSheetFreehandSymbolLayout
    ) -> LeadSheetFreehandSymbolEditControlFrames {
        let editFrame = editFrame(for: symbolLayout)
        let originY = editFrame.minY - controlSize / 2

        return LeadSheetFreehandSymbolEditControlFrames(
            delete: CGRect(
                x: editFrame.minX - controlSize / 2,
                y: originY,
                width: controlSize,
                height: controlSize
            ),
            move: CGRect(
                x: editFrame.maxX - controlSize / 2,
                y: originY,
                width: controlSize,
                height: controlSize
            )
        )
    }

    static func hitTarget(
        at location: CGPoint,
        in symbolLayouts: [LeadSheetFreehandSymbolLayout]
    ) -> FreehandSymbolEditHitTarget? {
        for symbolLayout in symbolLayouts.reversed() {
            let controlFrames = controlFrames(for: symbolLayout)
            if controlFrames.delete.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                return FreehandSymbolEditHitTarget(symbolID: symbolLayout.id, action: .delete)
            }

            if controlFrames.move.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                return FreehandSymbolEditHitTarget(symbolID: symbolLayout.id, action: .move)
            }

            if editHitFrame(for: symbolLayout).contains(location) {
                return FreehandSymbolEditHitTarget(symbolID: symbolLayout.id, action: .select)
            }
        }

        return nil
    }

    static func clampedFrame(
        _ frame: CGRect,
        in laneFrame: CGRect,
        minimumSize: CGFloat = 1
    ) -> CGRect {
        let width = min(max(minimumSize, frame.width), max(minimumSize, laneFrame.width))
        let height = min(max(minimumSize, frame.height), max(minimumSize, laneFrame.height))
        let minX = laneFrame.minX
        let maxX = laneFrame.maxX - width
        let minY = laneFrame.minY
        let maxY = laneFrame.maxY - height

        return CGRect(
            x: min(max(frame.minX, minX), max(minX, maxX)),
            y: min(max(frame.minY, minY), max(minY, maxY)),
            width: width,
            height: height
        )
    }
}
#endif
