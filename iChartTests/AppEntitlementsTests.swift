import XCTest
@testable import iChart

final class AppEntitlementsTests: XCTestCase {
    func testBasicAccountCapsLocalChartsAndKeepsExportReachableBeforeStoreKit() {
        let entitlements = AppEntitlements.free

        XCTAssertEqual(entitlements.localChartLimit, 3)
        XCTAssertEqual(IChartPlan.free.displayText, "Basic")
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

    func testLibrarySubscriptionApplicationPreservesLegacyLocalProForInactiveStoreKitResults() {
        let currentLegacyEntitlement = IChartSubscriptionEntitlement.legacyLocalPro
        let inactiveStoreKitResults: [IChartSubscriptionEntitlement] = [
            .basic,
            .proGrace(graceEndsAt: Date(timeIntervalSinceReferenceDate: 100)),
            .proExpired(verifiedAt: Date(timeIntervalSinceReferenceDate: 200)),
            .unavailable
        ]

        for entitlement in inactiveStoreKitResults {
            let resolved = entitlement.resolvedForLibraryApplication(
                currentLibraryEntitlement: currentLegacyEntitlement
            )

            XCTAssertEqual(resolved.status, .legacyLocalPro, "Expected legacy local Pro to survive \(entitlement.status)")
        }
    }

    func testLibrarySubscriptionApplicationLetsActiveStoreKitProReplaceLegacyLocalPro() {
        let activePro = IChartSubscriptionEntitlement.activePro(verifiedAt: Date(timeIntervalSinceReferenceDate: 300))

        let resolved = activePro.resolvedForLibraryApplication(
            currentLibraryEntitlement: .legacyLocalPro
        )

        XCTAssertEqual(resolved, activePro)
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
        let inactiveStates: [IChartSubscriptionEntitlement] = [
            .basic,
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

    func testBillingGraceKeepsLocalChartAccessButPausesCloudServices() {
        let graceEndsAt = Date(timeIntervalSinceReferenceDate: 100)
        let entitlements = AppEntitlements(subscription: .proGrace(graceEndsAt: graceEndsAt))

        XCTAssertNil(entitlements.localChartLimit)
        XCTAssertTrue(entitlements.includes(.unlimitedLocalCharts))
        XCTAssertTrue(entitlements.includes(.projects))
        XCTAssertTrue(entitlements.includes(.pdfExport))
        XCTAssertFalse(entitlements.includes(.cloudBackup))
        XCTAssertFalse(entitlements.includes(.forums))
    }

    func testForumDownloadRetentionAllowsActiveProOnlyAndPreservesGraceFiles() {
        let graceEndsAt = Date(timeIntervalSinceReferenceDate: 100)
        let inaccessibleStates: [IChartSubscriptionEntitlement] = [
            .basic,
            .proGrace(graceEndsAt: graceEndsAt),
            .proExpired(),
            .unavailable,
            .legacyLocalPro
        ]

        XCTAssertTrue(IChartSubscriptionEntitlement.activePro().allowsForumDownloadAccess)
        XCTAssertFalse(IChartSubscriptionEntitlement.activePro().shouldRemoveForumDownloads)
        inaccessibleStates.forEach { subscription in
            XCTAssertFalse(subscription.allowsForumDownloadAccess, "Expected forum downloads to be hidden for \(subscription.status)")
        }
        XCTAssertTrue(IChartSubscriptionEntitlement.basic.shouldRemoveForumDownloads)
        XCTAssertTrue(IChartSubscriptionEntitlement.proExpired().shouldRemoveForumDownloads)
        XCTAssertTrue(IChartSubscriptionEntitlement.legacyLocalPro.shouldRemoveForumDownloads)
        XCTAssertFalse(IChartSubscriptionEntitlement.proGrace(graceEndsAt: graceEndsAt).shouldRemoveForumDownloads)
        XCTAssertFalse(IChartSubscriptionEntitlement.unavailable.shouldRemoveForumDownloads)
    }

    func testLegacyEntitlementDecodingDefaultsSubscriptionFromActivePlan() throws {
        struct LegacyEntitlements: Encodable {
            let activePlan: IChartPlan
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
                "com.ichart.app.pro.monthly",
                "com.ichart.app.pro.annual"
            ]
        )
        XCTAssertTrue(IChartStoreKitProductCatalog.isProProductID("com.ichart.app.pro.monthly"))
        XCTAssertTrue(IChartStoreKitProductCatalog.isProProductID("com.ichart.app.pro.annual"))
        XCTAssertFalse(IChartStoreKitProductCatalog.isProProductID("com.ichart.app.basic"))
        XCTAssertEqual(IChartStoreKitProductCatalog.targetMonthlyPriceCents, 799)
        XCTAssertEqual(IChartStoreKitProductCatalog.targetAnnualPriceCents, 6_499)
        XCTAssertEqual(IChartStoreKitProductCatalog.annualSavingsPercent, 32)
        XCTAssertEqual(
            IChartStoreKitProductCatalog.valueBadge(for: "com.ichart.app.pro.annual"),
            "Save 32%"
        )
        XCTAssertNil(IChartStoreKitProductCatalog.valueBadge(for: "com.ichart.app.pro.monthly"))
    }

    func testStoreKitEntitlementResolverOnlyActivatesProForActiveSubscription() {
        let verifiedAt = Date(timeIntervalSinceReferenceDate: 200)

        let active = IChartStoreKitEntitlementResolver.entitlement(
            hasActiveProSubscription: true,
            sawExpiredProTransaction: false,
            accessEndsAt: Date(timeIntervalSinceReferenceDate: 300),
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
        XCTAssertEqual(active.accessEndsAt, Date(timeIntervalSinceReferenceDate: 300))
        XCTAssertEqual(active.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(expired.status, .proExpired)
        XCTAssertEqual(expired.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(basic.status, .basic)
        XCTAssertNil(basic.lastVerifiedAt)
    }

}
