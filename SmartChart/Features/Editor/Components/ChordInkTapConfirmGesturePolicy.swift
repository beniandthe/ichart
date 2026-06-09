#if canImport(UIKit)
import Foundation
import UIKit

enum ChordInkTapConfirmGesturePolicy {
    static let maximumSmallDragDistance: CGFloat = 30

    static func shouldConfirmOutsideLaneTap(
        location: CGPoint,
        pageLayout: LeadSheetPageLayout?,
        hasChordInk: Bool
    ) -> Bool {
        guard hasChordInk,
              let pageLayout else {
            return false
        }

        return !LeadSheetCanvasInteractionTargeting.chordWritingBandContains(location, in: pageLayout)
    }

    static func shouldConfirmOutsideLaneGesture(
        startLocation: CGPoint,
        currentLocation: CGPoint,
        pageLayout: LeadSheetPageLayout?,
        hasChordInk: Bool
    ) -> Bool {
        guard shouldConfirmOutsideLaneTap(
            location: startLocation,
            pageLayout: pageLayout,
            hasChordInk: hasChordInk
        ) else {
            return false
        }

        let distance = hypot(
            currentLocation.x - startLocation.x,
            currentLocation.y - startLocation.y
        )
        return distance <= maximumSmallDragDistance
    }
}

@available(*, deprecated, renamed: "ChordInkTapConfirmGesturePolicy")
typealias LeadSheetChordInkCommitGesturePolicy = ChordInkTapConfirmGesturePolicy
#endif
