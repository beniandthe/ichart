import XCTest
@testable import iChart

final class IChartSubscriptionEntitlementExpiryTests: XCTestCase {
    private let deadline = Date(timeIntervalSinceReferenceDate: 1_000)
    private let verifiedAt = Date(timeIntervalSinceReferenceDate: 500)

    func testActivePaidThroughChangesOnlyAtKnownDeadlineAndPreservesEvidence() {
        let active = IChartSubscriptionEntitlement.activePro(
            accessEndsAt: deadline, willAutoRenew: false, verifiedAt: verifiedAt)

        XCTAssertEqual(active.accessDeadline, deadline)
        XCTAssertEqual(active.evaluated(at: deadline.addingTimeInterval(-0.001)), active)
        for now in [deadline, deadline.addingTimeInterval(0.001), deadline.addingTimeInterval(60)] {
            let expired = active.evaluated(at: now)
            XCTAssertEqual(expired.status, .proExpired)
            XCTAssertEqual(expired.accessEndsAt, deadline)
            XCTAssertEqual(expired.willAutoRenew, false)
            XCTAssertEqual(expired.lastVerifiedAt, verifiedAt)
            XCTAssertNil(expired.accessDeadline)
        }
        XCTAssertEqual(active.status, .proActive, "Reading a deadline does not rewrite its cached evidence")
    }

    func testGraceUsesItsOwnKnownDeadlineWithoutCreatingAnotherPeriod() {
        let grace = IChartSubscriptionEntitlement(
            status: .proGrace, graceEndsAt: deadline, accessEndsAt: deadline.addingTimeInterval(-100),
            willAutoRenew: true, lastVerifiedAt: verifiedAt)

        XCTAssertEqual(grace.accessDeadline, deadline)
        XCTAssertEqual(grace.evaluated(at: deadline.addingTimeInterval(-1)), grace)
        let expired = grace.evaluated(at: deadline)
        XCTAssertEqual(expired.status, .proExpired)
        XCTAssertEqual(expired.graceEndsAt, deadline)
        XCTAssertEqual(expired.accessEndsAt, grace.accessEndsAt)
        XCTAssertEqual(expired.lastVerifiedAt, verifiedAt)
    }

    func testMissingBoundsAndLegacyStatusRetainExistingCompatibility() {
        for status in IChartSubscriptionStatus.allCases {
            let unbounded = IChartSubscriptionEntitlement(status: status, willAutoRenew: false)
            XCTAssertNil(unbounded.accessDeadline)
            XCTAssertEqual(unbounded.evaluated(at: deadline), unbounded)
        }
        let legacy = IChartSubscriptionEntitlement(
            status: .legacyLocalPro, graceEndsAt: .distantPast, accessEndsAt: .distantPast,
            lastVerifiedAt: verifiedAt)
        XCTAssertNil(legacy.accessDeadline)
        XCTAssertEqual(legacy.evaluated(at: deadline), legacy)
    }

    func testKnownExpiredActiveSnapshotCannotReplaceLegacyLocalRights() {
        let ended = IChartSubscriptionEntitlement.activePro(
            accessEndsAt: deadline, verifiedAt: verifiedAt)
        XCTAssertEqual(ended.resolvedForLibraryApplication(
            currentLibraryEntitlement: .legacyLocalPro, at: deadline), .legacyLocalPro)
        XCTAssertEqual(ended.resolvedForLibraryApplication(
            currentLibraryEntitlement: .basic, at: deadline).status, .proExpired)
        XCTAssertEqual(ended.resolvedForLibraryApplication(
            currentLibraryEntitlement: .legacyLocalPro, at: deadline.addingTimeInterval(-1)), ended)
    }

    func testResidentPaidSnapshotLosesAdmissionsAtBoundaryWithoutBeingReapplied() {
        let cached = AppEntitlements(subscription: .activePro(
            accessEndsAt: deadline, willAutoRenew: false, verifiedAt: verifiedAt), accessPolicy: .paidSubscription)
        let before = deadline.addingTimeInterval(-0.001)
        XCTAssertNil(cached.localChartLimit(at: before))
        XCTAssertTrue(cached.canCreateChart(currentChartCount: 30, at: before))
        XCTAssertTrue(cached.canConvertPDFToEditableChart(at: before))
        XCTAssertTrue(cached.canUsePremiumFonts(at: before))
        XCTAssertTrue(cached.canSyncPDFSetlists(at: before))
        XCTAssertTrue(cached.includes(.cloudBackup, at: before))
        XCTAssertTrue(cached.includes(.forums, at: before))
        XCTAssertTrue(cached.includes(.projects, at: before))

        for now in [deadline, deadline.addingTimeInterval(60)] {
            XCTAssertEqual(cached.localChartLimit(at: now), 3)
            XCTAssertFalse(cached.canCreateChart(currentChartCount: 30, at: now))
            XCTAssertFalse(cached.canCreateChart(currentChartCount: 3, at: now))
            XCTAssertTrue(cached.canCreateChart(currentChartCount: 2, at: now))
            XCTAssertEqual(cached.remainingLocalChartSlots(currentChartCount: 30, at: now), 0)
            XCTAssertFalse(cached.canConvertPDFToEditableChart(at: now))
            XCTAssertFalse(cached.canUsePremiumFonts(at: now))
            XCTAssertFalse(cached.canSyncPDFSetlists(at: now))
            XCTAssertFalse(cached.includes(.cloudBackup, at: now))
            XCTAssertFalse(cached.includes(.forums, at: now))
            XCTAssertFalse(cached.includes(.projects, at: now))
            XCTAssertTrue(cached.includes(.pdfExport, at: now))
            XCTAssertTrue(cached.includes(.fontPresets, at: now), "Existing readability choices remain usable")
            XCTAssertTrue(cached.includes(.documentTransposition, at: now))
            XCTAssertTrue(cached.includes(.advancedRhythmEditing, at: now))
            XCTAssertTrue(cached.chartCapacityText(currentChartCount: 30, at: now).contains("Keep editing your saved charts"))
        }
        XCTAssertEqual(cached.subscription.status, .proActive)
        XCTAssertEqual(cached.activePlan, .studioSubscription, "Persisted projection is evidence, not admission authority")
    }

    func testRuntimeAdmissionPropertiesRejectEndedResidentSnapshot() {
        let cached = AppEntitlements(subscription: .activePro(
            accessEndsAt: .distantPast, verifiedAt: verifiedAt), accessPolicy: .paidSubscription)

        XCTAssertEqual(cached.localChartLimit, 3)
        XCTAssertFalse(cached.canCreateChart(currentChartCount: 3))
        XCTAssertEqual(cached.remainingLocalChartSlots(currentChartCount: 3), 0)
        XCTAssertFalse(cached.canConvertPDFToEditableChart)
        XCTAssertFalse(cached.canUsePremiumFonts)
        XCTAssertFalse(cached.canSyncPDFSetlists)
        XCTAssertFalse(cached.includes(.unlimitedLocalCharts))
        XCTAssertFalse(cached.includes(.cloudBackup))
        XCTAssertFalse(cached.includes(.projects))
        XCTAssertTrue(cached.includes(.pdfExport))
    }

    func testGraceLocalAdmissionsEndAtKnownGraceBoundary() {
        let cached = AppEntitlements(subscription: .proGrace(
            graceEndsAt: deadline, verifiedAt: verifiedAt), accessPolicy: .paidSubscription)
        let before = deadline.addingTimeInterval(-1)

        XCTAssertNil(cached.localChartLimit(at: before))
        XCTAssertTrue(cached.canUsePremiumFonts(at: before))
        XCTAssertTrue(cached.includes(.projects, at: before))
        XCTAssertFalse(cached.canSyncPDFSetlists(at: before))
        XCTAssertFalse(cached.includes(.cloudBackup, at: before))
        XCTAssertEqual(cached.localChartLimit(at: deadline), 3)
        XCTAssertFalse(cached.canUsePremiumFonts(at: deadline))
        XCTAssertFalse(cached.includes(.projects, at: deadline))
        XCTAssertTrue(cached.includes(.pdfExport, at: deadline))
    }

    func testBetaFreeProAndBasicChoicesStayIndependentOfExpiredBilling() {
        let billing = IChartSubscriptionEntitlement.activePro(
            accessEndsAt: deadline, willAutoRenew: false, verifiedAt: verifiedAt)
        let betaPro = AppEntitlements(subscription: billing, accessPolicy: .freeAllFeatures)
        let betaBasic = AppEntitlements(subscription: billing, accessPolicy: .betaBasic)

        for now in [deadline.addingTimeInterval(-1), deadline, deadline.addingTimeInterval(1)] {
            XCTAssertNil(betaPro.localChartLimit(at: now))
            XCTAssertTrue(betaPro.canCreateChart(currentChartCount: 30, at: now))
            XCTAssertTrue(betaPro.canConvertPDFToEditableChart(at: now))
            XCTAssertTrue(betaPro.canUsePremiumFonts(at: now))
            XCTAssertFalse(betaPro.canSyncPDFSetlists(at: now), "Free beta does not enable the hosted paid-only rollout")
            XCTAssertTrue(betaPro.includes(.cloudBackup, at: now))
            XCTAssertTrue(betaPro.includes(.projects, at: now))
            XCTAssertEqual(betaBasic.localChartLimit(at: now), 3)
            XCTAssertFalse(betaBasic.canCreateChart(currentChartCount: 30, at: now))
            XCTAssertFalse(betaBasic.canUsePremiumFonts(at: now))
            XCTAssertFalse(betaBasic.canSyncPDFSetlists(at: now))
            XCTAssertFalse(betaBasic.includes(.projects, at: now))
            XCTAssertTrue(betaBasic.includes(.pdfExport, at: now))
        }
        XCTAssertEqual(betaPro.subscription, billing)
        XCTAssertEqual(betaBasic.subscription, billing)
    }

    func testEvaluationAndSerializationKeepBillingEvidenceAndPolicyBoundaries() throws {
        let billing = IChartSubscriptionEntitlement.activePro(
            accessEndsAt: deadline, willAutoRenew: false, verifiedAt: verifiedAt)
        let cached = AppEntitlements(subscription: billing, accessPolicy: .paidSubscription)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(cached)
        let projected = cached.evaluated(at: deadline)

        XCTAssertEqual(projected.activePlan, .free)
        XCTAssertEqual(projected.subscription.status, .proExpired)
        XCTAssertEqual(projected.subscription.accessEndsAt, deadline)
        XCTAssertEqual(projected.subscription.lastVerifiedAt, verifiedAt)
        XCTAssertEqual(projected.accessPolicy, .paidSubscription)
        XCTAssertEqual(try encoder.encode(cached), before)
        let decoded = try JSONDecoder().decode(AppEntitlements.self, from: before)
        XCTAssertEqual(decoded.subscription, billing)
        XCTAssertEqual(decoded.activePlan, .studioSubscription)
        XCTAssertEqual(decoded.accessPolicy, .current, "Runtime rollout policy is not read from saved billing")
        XCTAssertEqual(AppEntitlements(subscription: decoded.subscription, accessPolicy: .paidSubscription)
            .localChartLimit(at: deadline), 3)
    }
}
