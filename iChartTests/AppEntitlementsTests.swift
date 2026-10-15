import XCTest
@testable import iChart

final class AppEntitlementsTests: XCTestCase {
    func testBasicAccountCapsLocalChartsAndKeepsExportReachableBeforeStoreKit() {
        let entitlements = AppEntitlements(activePlan: .free, accessPolicy: .paidSubscription)

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
        let entitlements = AppEntitlements(activePlan: .proLifetime, accessPolicy: .paidSubscription)

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
        let entitlements = AppEntitlements(activePlan: .studioSubscription, accessPolicy: .paidSubscription)

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
        let entitlements = AppEntitlements(subscription: .activePro(), accessPolicy: .paidSubscription)

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
            let entitlements = AppEntitlements(subscription: subscription, accessPolicy: .paidSubscription)

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
        let entitlements = AppEntitlements(subscription: .proGrace(graceEndsAt: graceEndsAt), accessPolicy: .paidSubscription)

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

        XCTAssertTrue(IChartSubscriptionEntitlement.activePro().allowsForumDownloadAccess(accessPolicy: .paidSubscription))
        XCTAssertFalse(IChartSubscriptionEntitlement.activePro().shouldRemoveForumDownloads(accessPolicy: .paidSubscription))
        inaccessibleStates.forEach { subscription in
            XCTAssertFalse(subscription.allowsForumDownloadAccess(accessPolicy: .paidSubscription), "Expected forum downloads to be hidden for \(subscription.status)")
        }
        XCTAssertTrue(IChartSubscriptionEntitlement.basic.shouldRemoveForumDownloads(accessPolicy: .paidSubscription))
        XCTAssertTrue(IChartSubscriptionEntitlement.proExpired().shouldRemoveForumDownloads(accessPolicy: .paidSubscription))
        XCTAssertTrue(IChartSubscriptionEntitlement.legacyLocalPro.shouldRemoveForumDownloads(accessPolicy: .paidSubscription))
        XCTAssertFalse(IChartSubscriptionEntitlement.proGrace(graceEndsAt: graceEndsAt).shouldRemoveForumDownloads(accessPolicy: .paidSubscription))
        XCTAssertFalse(IChartSubscriptionEntitlement.unavailable.shouldRemoveForumDownloads(accessPolicy: .paidSubscription))
    }

    func testLegacyEntitlementDecodingDefaultsSubscriptionFromActivePlan() throws {
        struct LegacyEntitlements: Encodable {
            let activePlan: IChartPlan
        }

        let data = try JSONEncoder().encode(LegacyEntitlements(activePlan: .proLifetime))

        let decoded = try JSONDecoder().decode(AppEntitlements.self, from: data)

        XCTAssertEqual(decoded.activePlan, .proLifetime)
        XCTAssertEqual(decoded.subscription.status, .legacyLocalPro)
        XCTAssertTrue(decoded.includes(.cloudBackup), "Saved legacy billing does not override the shipping free-access policy")
        XCTAssertTrue(decoded.includes(.unlimitedLocalCharts))
    }

    func testShippingFreeAccessUnlocksEveryShippedFeatureWithoutChangingBillingEvidence() {
        XCTAssertEqual(IChartProductAccessPolicy.current, .freeAllFeatures)
        XCTAssertFalse(IChartProductAccessPolicy.current.offersPaidPurchases)
        XCTAssertTrue(IChartProductAccessPolicy.paidSubscription.offersPaidPurchases)

        for status in IChartSubscriptionStatus.allCases {
            let billing = IChartSubscriptionEntitlement(
                status: status,
                graceEndsAt: Date(timeIntervalSinceReferenceDate: 100),
                accessEndsAt: Date(timeIntervalSinceReferenceDate: 200),
                willAutoRenew: false,
                lastVerifiedAt: Date(timeIntervalSinceReferenceDate: 50)
            )
            let entitlements = AppEntitlements(subscription: billing)
            XCTAssertEqual(entitlements.subscription, billing)
            XCTAssertEqual(entitlements.activePlan, billing.effectivePlan)
            XCTAssertNil(entitlements.localChartLimit)
            XCTAssertTrue(entitlements.canCreateChart(currentChartCount: 10_000))
            XCTAssertNil(entitlements.remainingLocalChartSlots(currentChartCount: 10_000))
            for feature in EntitledFeature.allCases {
                XCTAssertTrue(entitlements.includes(feature), "Expected free access for \(status), \(feature)")
            }
            XCTAssertTrue(billing.allowsForumDownloadAccess)
            XCTAssertFalse(billing.shouldRemoveForumDownloads)
        }
        XCTAssertNil(AppEntitlements.free.localChartLimit)
    }

    func testFreeAccessSurvivesBillingRefreshRefundExpiryAndUnavailableWithoutMintingPaidStatus() {
        var entitlements = AppEntitlements(subscription: .activePro(willAutoRenew: true))
        for billing in [IChartSubscriptionEntitlement.basic, .proExpired(), .unavailable, .legacyLocalPro] {
            entitlements.applySubscription(billing)
            XCTAssertEqual(entitlements.subscription, billing)
            XCTAssertEqual(entitlements.activePlan, billing.effectivePlan)
            XCTAssertEqual(entitlements.accessPolicy, .freeAllFeatures)
            XCTAssertTrue(entitlements.includes(.cloudBackup))
            XCTAssertTrue(entitlements.includes(.forums))
            XCTAssertNil(entitlements.localChartLimit)
        }
    }

    func testAccessPolicyIsNotPersistedAndLibraryCannotOverrideShippingChoice() throws {
        let billing = IChartSubscriptionEntitlement.proExpired(verifiedAt: Date(timeIntervalSinceReferenceDate: 42))
        let legacyPolicy = AppEntitlements(subscription: billing, accessPolicy: .paidSubscription)
        let encoded = try JSONEncoder().encode(legacyPolicy)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), Set(["activePlan", "subscription"]))
        payload["accessPolicy"] = "paidSubscription"
        let decoded = try JSONDecoder().decode(AppEntitlements.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.subscription, billing)
        XCTAssertEqual(decoded.activePlan, billing.effectivePlan)
        XCTAssertEqual(decoded.accessPolicy, .current)
        XCTAssertNil(decoded.localChartLimit)
        XCTAssertTrue(decoded.includes(.projects))
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

    func testServerBackedSubscriptionAuthorityDoesNotTrustStaleLocalStoreKitHistory() {
        let verifiedAt = Date(timeIntervalSinceReferenceDate: 200)
        let remoteExpired = IChartSubscriptionEntitlement.proExpired(verifiedAt: verifiedAt)

        XCTAssertEqual(
            IChartStoreKitEntitlementResolver.serverBackedEntitlement(
                remoteEntitlement: nil,
                localEntitlement: .proExpired(verifiedAt: verifiedAt)
            ).status,
            .basic
        )
        XCTAssertEqual(
            IChartStoreKitEntitlementResolver.serverBackedEntitlement(
                remoteEntitlement: nil,
                localEntitlement: .activePro(verifiedAt: verifiedAt)
            ).status,
            .basic
        )
        XCTAssertEqual(
            IChartStoreKitEntitlementResolver.serverBackedEntitlement(
                remoteEntitlement: remoteExpired,
                localEntitlement: .basic
            ),
            remoteExpired
        )
    }

    func testServerBackedRemoteFailureOnlyBlocksLocalActivePro() {
        let verifiedAt = Date(timeIntervalSinceReferenceDate: 200)

        XCTAssertEqual(
            IChartStoreKitEntitlementResolver.serverBackedFallbackForRemoteFailure(
                localEntitlement: .proExpired(verifiedAt: verifiedAt)
            )?.status,
            .basic
        )
        XCTAssertEqual(
            IChartStoreKitEntitlementResolver.serverBackedFallbackForRemoteFailure(
                localEntitlement: .basic
            )?.status,
            .basic
        )
        XCTAssertNil(
            IChartStoreKitEntitlementResolver.serverBackedFallbackForRemoteFailure(
                localEntitlement: .activePro(verifiedAt: verifiedAt)
            )
        )
    }

}
