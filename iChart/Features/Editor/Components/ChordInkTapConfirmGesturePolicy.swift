#if canImport(UIKit)
import Foundation
import UIKit

enum ChordInkTapConfirmGesturePolicy {
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
}

#endif
