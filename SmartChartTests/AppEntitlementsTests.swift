import XCTest
@testable import SmartChart

final class AppEntitlementsTests: XCTestCase {
    func testBasicAccountCapsLocalChartsAndKeepsExportReachableBeforeStoreKit() {
        let entitlements = AppEntitlements.free

        XCTAssertEqual(entitlements.localChartLimit, 3)
        XCTAssertEqual(SmartChartPlan.free.displayText, "Basic")
        XCTAssertTrue(entitlements.canCreateChart(currentChartCount: 2))
        XCTAssertFalse(entitlements.canCreateChart(currentChartCount: 3))
        XCTAssertTrue(entitlements.includes(.pdfExport))
        XCTAssertTrue(entitlements.includes(.documentTransposition))
        XCTAssertTrue(entitlements.includes(.fontPresets))
        XCTAssertTrue(entitlements.includes(.roadmapNotationTools))
        XCTAssertTrue(entitlements.includes(.advancedRhythmEditing))
        XCTAssertFalse(entitlements.includes(.cloudBackup))
        XCTAssertFalse(entitlements.includes(.forums))
        XCTAssertFalse(entitlements.includes(.projects))
    }

    func testLegacyLocalProUnlocksLocalAuthoringFeatures() {
        let entitlements = AppEntitlements(activePlan: .proLifetime)

        XCTAssertNil(entitlements.localChartLimit)
        XCTAssertTrue(entitlements.includes(.unlimitedLocalCharts))
        XCTAssertTrue(entitlements.includes(.pdfExport))
        XCTAssertTrue(entitlements.includes(.fontPresets))
        XCTAssertTrue(entitlements.includes(.advancedRhythmEditing))
        XCTAssertFalse(entitlements.includes(.cloudBackup))
        XCTAssertFalse(entitlements.includes(.forums))
        XCTAssertFalse(entitlements.includes(.projects))
    }

    func testLegacyCloudEntitlementAddsServiceBackedFeaturesOnTopOfLocalPro() {
        let entitlements = AppEntitlements(activePlan: .studioSubscription)

        XCTAssertEqual(entitlements.subscription.status, .proActive)
        XCTAssertTrue(entitlements.includes(.syncedChartOrganization))
        XCTAssertTrue(entitlements.includes(.cloudBackup))
        XCTAssertTrue(entitlements.includes(.forums))
        XCTAssertTrue(entitlements.includes(.projects))
        XCTAssertTrue(entitlements.includes(.sharedBandLibraries))
        XCTAssertTrue(entitlements.includes(.setlistsAndVersionHistory))
        XCTAssertTrue(entitlements.includes(.aiRecognitionCleanup))
    }

    func testActiveProSubscriptionIsTheAuthorityForCloudAndForums() {
        let entitlements = AppEntitlements(subscription: .activePro())

        XCTAssertEqual(entitlements.activePlan, .studioSubscription)
        XCTAssertNil(entitlements.localChartLimit)
        XCTAssertTrue(entitlements.includes(.cloudBackup))
        XCTAssertTrue(entitlements.includes(.forums))
        XCTAssertTrue(entitlements.includes(.unlimitedLocalCharts))
        XCTAssertTrue(entitlements.includes(.projects))
    }

    func testInactiveSubscriptionStatesUseBasicLocalLimits() {
        let graceEndsAt = Date(timeIntervalSinceReferenceDate: 100)
        let inactiveStates: [IChartSubscriptionEntitlement] = [
            .basic,
            .proGrace(graceEndsAt: graceEndsAt),
            .proExpired(),
            .unavailable
        ]

        for subscription in inactiveStates {
            let entitlements = AppEntitlements(subscription: subscription)

            XCTAssertEqual(entitlements.activePlan, .free, "Expected Basic fallback for \(subscription.status)")
            XCTAssertEqual(entitlements.localChartLimit, 3)
            XCTAssertTrue(entitlements.includes(.pdfExport))
            XCTAssertFalse(entitlements.includes(.cloudBackup))
            XCTAssertFalse(entitlements.includes(.forums))
            XCTAssertFalse(entitlements.includes(.unlimitedLocalCharts))
            XCTAssertFalse(entitlements.includes(.projects))
        }
    }

    func testLegacyEntitlementDecodingDefaultsSubscriptionFromActivePlan() throws {
        struct LegacyEntitlements: Encodable {
            let activePlan: SmartChartPlan
        }

        let data = try JSONEncoder().encode(LegacyEntitlements(activePlan: .proLifetime))

        let decoded = try JSONDecoder().decode(AppEntitlements.self, from: data)

        XCTAssertEqual(decoded.activePlan, .proLifetime)
        XCTAssertEqual(decoded.subscription.status, .legacyLocalPro)
        XCTAssertFalse(decoded.includes(.cloudBackup))
        XCTAssertTrue(decoded.includes(.unlimitedLocalCharts))
    }

    func testStoreKitProductCatalogDefinesMonthlyAndAnnualProProducts() {
        XCTAssertEqual(
            IChartStoreKitProductCatalog.proProductIDs,
            [
                "com.smartchart.app.pro.monthly",
                "com.smartchart.app.pro.annual"
            ]
        )
        XCTAssertTrue(IChartStoreKitProductCatalog.isProProductID("com.smartchart.app.pro.monthly"))
        XCTAssertTrue(IChartStoreKitProductCatalog.isProProductID("com.smartchart.app.pro.annual"))
        XCTAssertFalse(IChartStoreKitProductCatalog.isProProductID("com.smartchart.app.basic"))
    }

    func testStoreKitEntitlementResolverOnlyActivatesProForActiveSubscription() {
        let verifiedAt = Date(timeIntervalSinceReferenceDate: 200)

        let active = IChartStoreKitEntitlementResolver.entitlement(
            hasActiveProSubscription: true,
            sawExpiredProTransaction: false,
            verifiedAt: verifiedAt
        )
        let expired = IChartStoreKitEntitlementResolver.entitlement(
            hasActiveProSubscription: false,
            sawExpiredProTransaction: true,
            verifiedAt: verifiedAt
        )
        let basic = IChartStoreKitEntitlementResolver.entitlement(
            hasActiveProSubscription: false,
            sawExpiredProTransaction: false,
            verifiedAt: verifiedAt
        )

        XCTAssertEqual(active.status, .proActive)
        XCTAssertEqual(active.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(expired.status, .proExpired)
        XCTAssertEqual(expired.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(basic.status, .basic)
        XCTAssertNil(basic.lastVerifiedAt)
    }

}
