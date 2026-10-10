import XCTest
@testable import iChart

final class IChartSubscriptionAccessRecoveryTests: XCTestCase {
    private let ownerA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let ownerB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAcceptedOrdinaryClaimDoesNotRequireRemoteOrCampaignConfirmation() async {
        let active = IChartSubscriptionEntitlement.activePro(accessEndsAt: now.addingTimeInterval(60))
        let service = AccessService(owner: ownerA, claimed: active)
        let result = await resolve(service)
        XCTAssertEqual(result, .verified(active, .ordinaryClaim))
        let calls = await service.calls
        XCTAssertEqual(calls, ["owner", "claim", "owner"])
        let expectedOwners = await service.expectedOwners
        XCTAssertEqual(expectedOwners, [ownerA])
    }

    func testThrownClaimAttemptsFreshSameOwnerRemoteBeforeUnavailable() async {
        let active = IChartSubscriptionEntitlement.activePro(accessEndsAt: now.addingTimeInterval(60))
        let service = AccessService(owner: ownerA, claimThrows: true, remote: active)
        let result = await resolve(service)
        XCTAssertEqual(result, .verified(active, .freshRemote))
        let calls = await service.calls
        XCTAssertEqual(calls, ["owner", "claim", "owner", "remote", "owner"])
        let owners = await service.expectedOwners
        XCTAssertEqual(owners, [ownerA, ownerA])
        let requestedNow = await service.requestedNow
        XCTAssertEqual(requestedNow, now)
    }

    func testRejectedOrMissingClaimAlsoReadsFreshRemote() async {
        let active = IChartSubscriptionEntitlement.activePro()
        let service = AccessService(owner: ownerA, claimed: nil, remote: active)
        let result = await resolve(service)
        XCTAssertEqual(result, .verified(active, .freshRemote))
    }

    func testClaimAndRemoteFailureCannotPreserveCachedOrLocalPro() async {
        let service = AccessService(owner: ownerA, claimThrows: true, remoteThrows: true)
        let result = await resolve(service)
        XCTAssertEqual(result, .unavailable(claimFailed: true))
    }

    func testRemoteFailureWithoutClaimHasNoServerVerifiedEntitlement() async {
        let service = AccessService(owner: ownerA, remoteThrows: true)
        let result = await resolve(service, signed: nil)
        XCTAssertEqual(result, .unavailable(claimFailed: false))
    }

    func testFreshMissingRowDoesNotGrantAccessAfterClaimFailure() async {
        let service = AccessService(owner: ownerA, claimThrows: true, remote: nil)
        let result = await resolve(service)
        XCTAssertEqual(result, .noRemoteSubscription)
    }

    func testMissingInitialOwnerDoesNotClaimOrRead() async {
        let service = AccessService(owner: ownerA, claimed: .activePro(), remote: .activePro())
        let result = await IChartSubscriptionAccessRecovery.resolve(
            expectedOwnerID: nil, signedTransactionInfo: "synthetic-jws", service: service, now: now
        )
        XCTAssertEqual(result, .unavailable(claimFailed: false))
        let calls = await service.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testChangedOwnerBeforeClaimPreventsClaimAndRemoteRead() async {
        let service = AccessService(owner: ownerB, claimed: .activePro(), remote: .activePro())
        let result = await resolve(service)
        XCTAssertEqual(result, .unavailable(claimFailed: false))
        let calls = await service.calls
        XCTAssertEqual(calls, ["owner"])
    }

    func testChangedOwnerAfterClaimPreventsApplyingClaimAndRemoteRead() async {
        let service = AccessService(owner: ownerA, ownerAnswers: [ownerA, ownerB], claimed: .activePro())
        let result = await resolve(service)
        XCTAssertEqual(result, .unavailable(claimFailed: true))
        let calls = await service.calls
        XCTAssertEqual(calls, ["owner", "claim", "owner"])
    }

    func testChangedOwnerAfterThrownClaimPreventsRecoveryRead() async {
        let service = AccessService(owner: ownerA, ownerAnswers: [ownerA, ownerB], claimThrows: true, remote: .activePro())
        let result = await resolve(service)
        XCTAssertEqual(result, .unavailable(claimFailed: true))
        let calls = await service.calls
        XCTAssertEqual(calls, ["owner", "claim", "owner"])
    }

    func testChangedOwnerAfterRemoteReadDoesNotApplyReturnedAccess() async {
        let service = AccessService(owner: ownerA, ownerAnswers: [ownerA, ownerA, ownerB], remote: .activePro())
        let result = await resolve(service, signed: nil)
        XCTAssertEqual(result, .unavailable(claimFailed: false))
    }

    func testActualRequestOwnerMismatchRejectsAToBToA() throws {
        let rowA = record(owner: ownerA)
        XCTAssertThrowsError(try validated(rowA, requestOwner: ownerB, currentOwner: ownerA))
        XCTAssertThrowsError(try validated(record(owner: ownerB), requestOwner: ownerA, currentOwner: ownerA))
    }

    func testMissingOrChangedFinalOwnerRejectsRemoteRow() throws {
        XCTAssertThrowsError(try validated(record(owner: ownerA), currentOwner: nil))
        XCTAssertThrowsError(try validated(record(owner: ownerA), currentOwner: ownerB))
    }

    func testRejectedClaimCannotGrantItsIncludedActiveRow() throws {
        XCTAssertNil(try validated(record(owner: ownerA), accepted: false))
        XCTAssertNil(try validated(nil))
    }

    func testValidatedRowUsesExistingExpiryGraceAndRevocationPolicy() throws {
        XCTAssertEqual(try validated(record(owner: ownerA))?.status, .proActive)
        XCTAssertEqual(try validated(record(owner: ownerA, expires: now.addingTimeInterval(-1)))?.status, .proExpired)
        XCTAssertEqual(try validated(record(owner: ownerA, appStoreStatus: .grace, grace: now.addingTimeInterval(60)))?.status, .proGrace)
        XCTAssertEqual(try validated(record(owner: ownerA, revoked: now.addingTimeInterval(-1)))?.status, .proExpired)
        XCTAssertEqual(try validated(record(owner: ownerA, productID: "unknown.product"))?.status, .basic)
    }

    private func resolve(_ service: AccessService, signed: String? = "synthetic-jws") async -> IChartSubscriptionAccessRecovery.Resolution {
        await IChartSubscriptionAccessRecovery.resolve(
            expectedOwnerID: ownerA, signedTransactionInfo: signed, service: service, now: now
        )
    }

    private func validated(
        _ record: IChartRemoteSubscriptionRecord?,
        requestOwner: UUID? = nil,
        currentOwner: UUID? = UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
        accepted: Bool = true
    ) throws -> IChartSubscriptionEntitlement? {
        try IChartSubscriptionAccessRecovery.validatedEntitlement(
            record: record, expectedOwnerID: ownerA,
            authenticatedRequestOwnerID: requestOwner ?? ownerA,
            currentOwnerID: currentOwner, accepted: accepted, now: now
        )
    }

    private func record(
        owner: UUID,
        productID: String = IChartStoreKitProductCatalog.proMonthlyProductID,
        appStoreStatus: IChartRemoteSubscriptionRecord.AppStoreStatus = .active,
        expires: Date? = nil,
        grace: Date? = nil,
        revoked: Date? = nil
    ) -> IChartRemoteSubscriptionRecord {
        let formatter = ISO8601DateFormatter()
        return IChartRemoteSubscriptionRecord(
            ownerID: owner, plan: .studioSubscription, status: "active", provider: .storekit,
            storeKitProductID: productID, storeKitOriginalTransactionID: nil,
            storeKitEnvironment: "sandbox", appStoreStatus: appStoreStatus,
            appStoreAutoRenewStatus: true,
            entitlementExpiresAt: formatter.string(from: expires ?? now.addingTimeInterval(60)),
            gracePeriodExpiresAt: grace.map(formatter.string(from:)),
            cloudRetentionDeadline: nil, cloudRetentionDeletedAt: nil,
            revokedAt: revoked.map(formatter.string(from:)), lastVerifiedAt: formatter.string(from: now)
        )
    }
}

private actor AccessService: IChartSubscriptionAccessClaiming {
    enum SyntheticFailure: Error { case requestFailed }
    private let owner: UUID
    private var ownerAnswers: [UUID?]
    private let claimed: IChartSubscriptionEntitlement?
    private let claimThrows: Bool
    private let remote: IChartSubscriptionEntitlement?
    private let remoteThrows: Bool
    private(set) var calls: [String] = []
    private(set) var expectedOwners: [UUID] = []
    private(set) var requestedNow: Date?

    init(owner: UUID, ownerAnswers: [UUID?] = [], claimed: IChartSubscriptionEntitlement? = nil,
         claimThrows: Bool = false, remote: IChartSubscriptionEntitlement? = nil, remoteThrows: Bool = false) {
        self.owner = owner
        self.ownerAnswers = ownerAnswers
        self.claimed = claimed
        self.claimThrows = claimThrows
        self.remote = remote
        self.remoteThrows = remoteThrows
    }

    func appAccountToken() async throws -> UUID? {
        calls.append("owner")
        return ownerAnswers.isEmpty ? owner : ownerAnswers.removeFirst()
    }

    func claim(signedTransactionInfo: String, expectedOwnerID: UUID) async throws -> IChartSubscriptionEntitlement? {
        calls.append("claim")
        expectedOwners.append(expectedOwnerID)
        if claimThrows { throw SyntheticFailure.requestFailed }
        return claimed
    }

    func loadRemoteSubscriptionEntitlement(now: Date, expectedOwnerID: UUID) async throws -> IChartSubscriptionEntitlement? {
        calls.append("remote")
        expectedOwners.append(expectedOwnerID)
        requestedNow = now
        if remoteThrows { throw SyntheticFailure.requestFailed }
        return remote
    }
}

final class IChartSubscriptionAccessRecoveryIntegrationTests: XCTestCase {
    func testGiftAppliesAcceptedClaimAfterOwnerCheckButStillFinishesOnlyAfterConfirmation() throws {
        let store = try source()
        let purchase = try section(store, from: "func purchaseComplimentaryOffer(", to: "func restorePurchases()")
        let claim = try XCTUnwrap(purchase.range(of: "guard let claimedEntitlement = try await subscriptionClaimService.claim("))
        let ownerCheck = try XCTUnwrap(purchase.range(of: "guard try await subscriptionClaimService.appAccountToken() == accountID", range: claim.upperBound..<purchase.endIndex))
        let apply = try XCTUnwrap(purchase.range(of: "entitlement = claimedEntitlement", range: ownerCheck.upperBound..<purchase.endIndex))
        let confirm = try XCTUnwrap(purchase.range(of: "action: .confirm", range: apply.upperBound..<purchase.endIndex))
        let confirmed = try XCTUnwrap(purchase.range(of: "matchesConfirmedCampaign", range: confirm.upperBound..<purchase.endIndex))
        let finish = try XCTUnwrap(purchase.range(of: "await transaction.finish()", range: confirmed.upperBound..<purchase.endIndex))
        XCTAssertLessThan(claim.lowerBound, ownerCheck.lowerBound)
        XCTAssertLessThan(ownerCheck.lowerBound, apply.lowerBound)
        XCTAssertLessThan(apply.lowerBound, confirm.lowerBound)
        XCTAssertLessThan(confirmed.lowerBound, finish.lowerBound)
        XCTAssertTrue(purchase.contains("expectedOwnerID: accountID"))
    }

    func testRefreshAndConcreteServiceUseFreshOwnerBoundAccessPath() throws {
        let store = try source()
        let refresh = try section(store, from: "private func refreshEntitlements(", to: "private func evaluateLocalStoreKitEntitlements(")
        XCTAssertTrue(refresh.contains("IChartSubscriptionAccessRecovery.resolve("))
        XCTAssertTrue(refresh.contains("expectedOwnerID: expectedOwnerID"))
        let service = try section(store, from: "private struct IChartSupabaseStoreKitSubscriptionClaimService", to: "private struct StoreKitSubscriptionClaimRequest")
        XCTAssertTrue(service.contains("accepted: response.accepted"))
        XCTAssertTrue(service.contains("authenticatedRequestOwnerID: session.user.id"))
        XCTAssertTrue(service.contains(".eq(\"owner_id\", value: expectedOwnerID.uuidString)"))
        XCTAssertTrue(service.contains("accessToken: { pinnedAccessToken }"))
        XCTAssertTrue(service.contains("storage: IChartSubscriptionRequestLocalStorage()"))
        XCTAssertFalse(service.contains("print("))
    }

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift"))
    }

    private func section(_ source: String, from startText: String, to endText: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startText))
        let end = try XCTUnwrap(source.range(of: endText, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
