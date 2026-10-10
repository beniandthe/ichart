#if canImport(UIKit)
import XCTest
@testable import iChart

final class IChartComplimentaryPurchaseFeedbackTests: XCTestCase {
    private let monthlyID = IChartStoreKitProductCatalog.proMonthlyProductID
    private let annualID = IChartStoreKitProductCatalog.proAnnualProductID

    func testFailedGiftTapCapturesTheExistingUnavailableMessage() throws {
        let message = "The complimentary offer could not be verified. No paid purchase was made."
        let feedback = try XCTUnwrap(IChartComplimentaryPurchaseFeedback(
            productID: monthlyID,
            completed: false,
            state: .unavailable(message)
        ))

        XCTAssertEqual(feedback.productID, monthlyID)
        XCTAssertEqual(feedback.message, message)
        XCTAssertEqual(feedback.accessibilityLabel, "Complimentary offer not completed")
        XCTAssertEqual(feedback.retryInstruction, "To try again, use the free-month button above.")
    }

    func testSuccessfulGiftTapDoesNotPresentAnError() {
        XCTAssertNil(IChartComplimentaryPurchaseFeedback(
            productID: monthlyID,
            completed: true,
            state: .unavailable("An unrelated state change must not become this purchase's error.")
        ))
    }

    func testCancellationReturningReadyDoesNotPresentAnError() {
        XCTAssertNil(IChartComplimentaryPurchaseFeedback(
            productID: monthlyID,
            completed: false,
            state: .ready
        ))
    }

    func testOtherNonfailureStatesDoNotPresentAnError() {
        let states: [IChartStoreKitSubscriptionState] = [
            .idle, .loading, .claiming, .purchasing, .restoring, .managing, .localPreviewActive
        ]
        for state in states {
            XCTAssertNil(IChartComplimentaryPurchaseFeedback(
                productID: monthlyID,
                completed: false,
                state: state
            ))
        }
    }

    func testBlankUnavailableMessagesDoNotCreateEmptyFeedback() {
        for message in ["", " ", "\n\t"] {
            XCTAssertNil(IChartComplimentaryPurchaseFeedback(
                productID: monthlyID,
                completed: false,
                state: .unavailable(message)
            ))
        }
    }

    func testRetainedOfferDoesNotRequestFallbackFeedback() throws {
        let feedback = try XCTUnwrap(IChartComplimentaryPurchaseFeedback(
            productID: monthlyID,
            completed: false,
            state: .unavailable("The complimentary offer changed. Refresh and review the current Apple terms.")
        ))

        XCTAssertFalse(feedback.shouldShowOutsideOffers(productIDs: [monthlyID]))
        XCTAssertFalse(feedback.shouldShowOutsideOffers(productIDs: [annualID, monthlyID]))
    }

    func testRemovedOfferRequestsFeedbackOutsideRemainingCards() throws {
        let feedback = try XCTUnwrap(IChartComplimentaryPurchaseFeedback(
            productID: monthlyID,
            completed: false,
            state: .unavailable("Apple accepted the offer, but iChart confirmation is pending. It will retry without buying again.")
        ))

        XCTAssertTrue(feedback.shouldShowOutsideOffers(productIDs: []))
        XCTAssertTrue(feedback.shouldShowOutsideOffers(productIDs: [annualID]))
    }

    func testFeedbackRemainsBoundToTheTappedAnnualOffer() throws {
        let feedback = try XCTUnwrap(IChartComplimentaryPurchaseFeedback(
            productID: annualID,
            completed: false,
            state: .unavailable("The complimentary offer could not be authorized. No paid purchase was made.")
        ))

        XCTAssertEqual(feedback.productID, annualID)
        XCTAssertTrue(feedback.shouldShowOutsideOffers(productIDs: [monthlyID]))
        XCTAssertFalse(feedback.shouldShowOutsideOffers(productIDs: [annualID]))
    }
}
#endif
