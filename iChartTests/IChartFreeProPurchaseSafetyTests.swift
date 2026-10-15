import Foundation
import XCTest
@testable import iChart

final class IChartFreeProProductCopyTests: XCTestCase {
    func testFreeAccessHasNoAutomaticPaidConversionPromise() {
        XCTAssertTrue(IChartProductAccessPolicy.current.includesAllFeatures)
        XCTAssertFalse(IChartProductAccessPolicy.current.offersPaidPurchases)
        XCTAssertTrue(IChartLegalLinks.freeProNotice.contains("No subscription or trial"))
        XCTAssertTrue(IChartLegalLinks.futurePricingNotice.contains("advance notice"))
        XCTAssertTrue(IChartLegalLinks.futurePricingNotice.contains("choose and confirm"))
        XCTAssertTrue(IChartLegalLinks.futurePricingNotice.contains("will not automatically"))
    }

    func testExistingBillingCopyDoesNotClaimCancellationOrRefund() {
        XCTAssertTrue(IChartLegalLinks.existingBillingNotice.contains("does not cancel"))
        XCTAssertTrue(IChartLegalLinks.existingBillingNotice.contains("or issue a refund"))
        XCTAssertEqual(IChartLegalLinks.refundHelpURL.host, "reportaproblem.apple.com")
    }

    func testProductionSettingsAndFallbackSheetHaveSeparateFreeContent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent("iChart/Features/Library/LibraryView.swift"), encoding: .utf8)
        let sheet = try String(contentsOf: root.appendingPathComponent("iChart/Features/Editor/Components/UpgradeSheetView.swift"), encoding: .utf8)
        XCTAssertTrue(settings.contains("if isFreeAccess {\n                freeAccessControls"))
        let start = try XCTUnwrap(settings.range(of: "private var freeAccessControls: some View {"))
        let end = try XCTUnwrap(settings.range(of: "private var storeKitControls: some View {", range: start.upperBound..<settings.endIndex))
        let freeControls = String(settings[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(freeControls.contains(".purchase("))
        XCTAssertFalse(freeControls.contains("purchaseComplimentaryOffer("))
        XCTAssertTrue(freeControls.contains("Manage Existing Subscription"))
        XCTAssertTrue(freeControls.contains("IChartLegalLinks.existingBillingNotice"))
        XCTAssertTrue(sheet.contains("if IChartProductAccessPolicy.current.includesAllFeatures {"))
        XCTAssertTrue(sheet.contains("IChartLegalLinks.freeProNotice"))
    }
}

#if canImport(UIKit)
@MainActor
final class IChartFreeProPurchaseSafetyTests: XCTestCase {
    func testFreeAccessRejectsStaleOrdinaryPurchaseWithoutChangingBilling() async {
        let store = IChartStoreKitSubscriptionStore.live()
        let billingBefore = store.entitlement
        let staleOption = IChartStoreKitProductOption(
            id: IChartStoreKitProductCatalog.proMonthlyProductID,
            displayName: "Old monthly purchase",
            description: "Stale product selection",
            displayPrice: "$7.99",
            valueBadge: nil
        )

        await store.purchase(staleOption)

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.entitlement, billingBefore)
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertTrue(store.productOptions.isEmpty)
        XCTAssertTrue(store.complimentaryOffers.isEmpty)
    }

    func testFreeAccessRejectsStaleFreeMonthCheckoutWithoutChangingBilling() async {
        let store = IChartStoreKitSubscriptionStore.live()
        let billingBefore = store.entitlement
        let staleOffer = IChartComplimentaryOffer(
            campaignID: "parked-free-month-fixture",
            productID: IChartStoreKitProductCatalog.proMonthlyProductID,
            offerID: nil,
            decision: .introductory,
            activation: .immediate,
            productDisplayName: "Old free month",
            offerDisplayPrice: "$0",
            renewalDisplayPrice: "$7.99",
            renewalPeriodDescription: "month"
        )

        let completed = await store.purchaseComplimentaryOffer(staleOffer)

        XCTAssertFalse(completed)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.entitlement, billingBefore)
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertTrue(store.productOptions.isEmpty)
    }
}
#endif
