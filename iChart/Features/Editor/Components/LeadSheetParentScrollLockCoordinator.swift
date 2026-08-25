#if canImport(UIKit)
import UIKit

final class LeadSheetParentScrollLockCoordinator {
    private weak var lockedScrollView: UIScrollView?
    private var lockedScrollWasEnabled: Bool?

    var isLocked: Bool {
        lockedScrollView != nil
    }

    func lock(_ scrollView: UIScrollView?) {
        guard lockedScrollView == nil,
              let scrollView else {
            return
        }

        lockedScrollView = scrollView
        lockedScrollWasEnabled = scrollView.isScrollEnabled
        scrollView.isScrollEnabled = false
    }

    func unlock() {
        defer {
            lockedScrollView = nil
            lockedScrollWasEnabled = nil
        }

        guard let scrollView = lockedScrollView,
              let wasEnabled = lockedScrollWasEnabled else {
            return
        }

        scrollView.isScrollEnabled = wasEnabled
    }
}
#endif
