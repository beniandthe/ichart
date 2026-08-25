#if canImport(UIKit)
import XCTest
import UIKit
@testable import iChart

final class LeadSheetParentScrollLockCoordinatorTests: XCTestCase {
    func testLockDisablesAndUnlockRestoresParentScroll() {
        let scrollView = UIScrollView()
        scrollView.isScrollEnabled = true
        let coordinator = LeadSheetParentScrollLockCoordinator()

        coordinator.lock(scrollView)

        XCTAssertTrue(coordinator.isLocked)
        XCTAssertFalse(scrollView.isScrollEnabled)

        coordinator.unlock()

        XCTAssertFalse(coordinator.isLocked)
        XCTAssertTrue(scrollView.isScrollEnabled)
    }

    func testRepeatedLockDoesNotOverwriteOriginalState() {
        let firstScrollView = UIScrollView()
        firstScrollView.isScrollEnabled = true
        let secondScrollView = UIScrollView()
        secondScrollView.isScrollEnabled = true
        let coordinator = LeadSheetParentScrollLockCoordinator()

        coordinator.lock(firstScrollView)
        firstScrollView.isScrollEnabled = false
        coordinator.lock(secondScrollView)

        XCTAssertFalse(firstScrollView.isScrollEnabled)
        XCTAssertTrue(secondScrollView.isScrollEnabled)

        coordinator.unlock()

        XCTAssertTrue(firstScrollView.isScrollEnabled)
        XCTAssertTrue(secondScrollView.isScrollEnabled)
    }

    func testUnlockWithoutLockIsNoOp() {
        let coordinator = LeadSheetParentScrollLockCoordinator()

        coordinator.unlock()

        XCTAssertFalse(coordinator.isLocked)
    }
}
#endif
