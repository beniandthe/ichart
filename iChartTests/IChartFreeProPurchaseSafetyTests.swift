import Foundation
import XCTest
@testable import iChart

final class IChartFreeProProductCopyTests: XCTestCase {
    func testFreeAccessHasNoAutomaticPaidConversionPromise() {
        XCTAssertTrue(IChartProductAccessPolicy.current.includesAllFeatures)
        XCTAssertFalse(IChartProductAccessPolicy.current.offersPaidPurchases)
        XCTAssertEqual(IChartLegalLinks.freeProTitle, "Pro — Free")
        XCTAssertEqual(
            IChartLegalLinks.freeProNotice + " " + IChartLegalLinks.futurePricingNotice,
            "Pro is currently free with your iChart account. Leave or rejoin at any time in Settings. We’ll notify you before pricing changes; a new paid subscription will require your confirmation with Apple."
        )
        XCTAssertTrue(IChartLegalLinks.betaBasicNotice.contains("rejoin at any time in Settings"))
        XCTAssertTrue(IChartLegalLinks.betaBasicNotice.contains("existing charts and downloads are kept"))
    }

    func testExistingBillingCopyDoesNotClaimCancellationOrRefund() {
        XCTAssertTrue(IChartLegalLinks.existingBillingNotice.contains("does not cancel"))
        XCTAssertTrue(IChartLegalLinks.existingBillingNotice.contains("or issue a refund"))
        XCTAssertTrue(IChartLegalLinks.existingBillingNotice.contains("Manage My Subscription"))
    }

    func testProductionSettingsAndFallbackSheetHaveSeparateFreeContent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent("iChart/Features/Library/LibraryView.swift"), encoding: .utf8)
        let sheet = try String(contentsOf: root.appendingPathComponent("iChart/Features/Editor/Components/UpgradeSheetView.swift"), encoding: .utf8)
        XCTAssertTrue(settings.contains("if isFreeBeta {\n                freeAccessControls"))
        let start = try XCTUnwrap(settings.range(of: "private var freeAccessControls: some View {"))
        let end = try XCTUnwrap(settings.range(of: "private var storeKitControls: some View {", range: start.upperBound..<settings.endIndex))
        let freeControls = String(settings[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(freeControls.contains(".purchase("))
        XCTAssertFalse(freeControls.contains("purchaseComplimentaryOffer("))
        XCTAssertTrue(freeControls.contains("Manage My Subscription"))
        XCTAssertFalse(settings.contains("Request an Apple Refund"))
        XCTAssertFalse(freeControls.contains("refundHelpURL"))
        XCTAssertTrue(freeControls.contains("IChartBetaProControls(store: betaProStore)"))
        XCTAssertTrue(freeControls.contains("IChartLegalLinks.existingBillingNotice"))
        XCTAssertTrue(sheet.contains("if IChartProductAccessPolicy.current.isFreeBeta {"))
        XCTAssertTrue(sheet.contains("IChartLegalLinks.freeProNotice"))
    }

    func testCurrentFreeAccessSurfacesDoNotDescribeTheAppAsBeta() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let paths = [
            "iChart/Services/IChartLegalLinks.swift",
            "iChart/Features/Editor/Components/IChartBetaProControls.swift",
            "iChart/Features/Editor/Components/UpgradeSheetView.swift",
            "iChart/Features/Library/LibraryView.swift"
        ]
        let retiredCopy = ["During Beta", "during beta", "free beta Pro", "Free Pro beta", "Pro Beta Update", "before beta ends", "while iChart is in beta"]
        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for phrase in retiredCopy {
                XCTAssertFalse(source.contains(phrase), "Retired customer-facing copy in \(path): \(phrase)")
            }
        }
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
