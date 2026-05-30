#if canImport(UIKit)
import Foundation
import UIKit

struct LeadSheetChordEditControlFrames {
    let delete: CGRect
    let move: CGRect
}

struct ChordEditHitTarget {
    enum Action {
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

                if controlFrames.move.insetBy(dx: -controlHitOutset, dy: -controlHitOutset).contains(location) {
                    return ChordEditHitTarget(
                        measureID: measureID,
                        chordID: chordLayout.id,
                        action: .move
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
