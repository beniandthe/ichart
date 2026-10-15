import Foundation
import XCTest
@testable import iChart

@MainActor
final class IChartBetaProStoreTests: XCTestCase {
    private let ownerA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let ownerB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    func testNewAccountDefaultsToFreeProBeforeRemoteRead() {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: ownerA)
        XCTAssertEqual(fixture.store.ownerID, ownerA)
        XCTAssertTrue(fixture.store.isEnrolled)
        XCTAssertTrue(fixture.store.freeProAccess)
        XCTAssertFalse(fixture.store.isWorking)
        XCTAssertNil(fixture.store.status)
        XCTAssertNil(fixture.store.errorMessage)
    }

    func testConfirmedLeaveAndRejoinPersistPerAccountAcrossRelaunch() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: ownerA)
        let left = await fixture.store.setParticipating(false)
        XCTAssertTrue(left)
        XCTAssertFalse(fixture.store.isEnrolled)
        XCTAssertFalse(fixture.store.freeProAccess)
        let reopened = IChartBetaProStore(service: fixture.service, defaults: fixture.defaults)
        reopened.authStateChanged(ownerID: ownerA)
        XCTAssertFalse(reopened.isEnrolled)
        XCTAssertFalse(reopened.freeProAccess)
        reopened.authStateChanged(ownerID: ownerB)
        XCTAssertTrue(reopened.isEnrolled, "A's opt-out cannot become B's choice")
        reopened.authStateChanged(ownerID: ownerA)
        let rejoined = await reopened.setParticipating(true)
        XCTAssertTrue(rejoined)
        XCTAssertTrue(reopened.isEnrolled)
        XCTAssertTrue(reopened.freeProAccess)
        XCTAssertEqual(fixture.service.setRequests.map(\.owner), [ownerA, ownerA])
        XCTAssertEqual(fixture.service.setRequests.map(\.participating), [false, true])
    }

    func testFailedMutationKeepsLastConfirmedChoiceAndFriendlyError() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: ownerA)
        let left = await fixture.store.setParticipating(false)
        XCTAssertTrue(left)
        fixture.service.setError = TestFailure.privateServiceDetail
        let saved = await fixture.store.setParticipating(true)
        XCTAssertFalse(saved)
        XCTAssertFalse(fixture.store.isEnrolled)
        XCTAssertFalse(fixture.store.freeProAccess)
        XCTAssertFalse(fixture.store.isWorking)
        XCTAssertNotNil(fixture.store.errorMessage)
        XCTAssertFalse(fixture.store.errorMessage?.contains("privateServiceDetail") == true)
        let reopened = IChartBetaProStore(service: fixture.service, defaults: fixture.defaults)
        reopened.authStateChanged(ownerID: ownerA)
        XCTAssertFalse(reopened.isEnrolled)
    }

    func testOfflinePreservesSavedChoiceWithoutRPCOrFalseMutationSuccess() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: ownerA)
        let left = await fixture.store.setParticipating(false)
        XCTAssertTrue(left)
        fixture.store.authStateChanged(ownerID: ownerA, isOffline: true)
        await fixture.store.refresh()
        let saved = await fixture.store.setParticipating(true)
        XCTAssertFalse(saved)
        XCTAssertFalse(fixture.store.isEnrolled)
        XCTAssertFalse(fixture.store.freeProAccess)
        XCTAssertTrue(fixture.service.fetchRequests.isEmpty)
        XCTAssertEqual(fixture.service.setRequests.count, 1)
        XCTAssertNotNil(fixture.store.errorMessage)
    }

    func testSignedOutMutationDoesNotCallServiceOrClaimSuccess() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let saved = await fixture.store.setParticipating(true)
        XCTAssertFalse(saved)
        XCTAssertTrue(fixture.service.setRequests.isEmpty)
        XCTAssertFalse(fixture.store.isEnrolled)
        XCTAssertFalse(fixture.store.freeProAccess)
        XCTAssertNotNil(fixture.store.errorMessage)
    }

    func testStaleButtonOwnerCannotStartMutationForNewAccount() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: ownerA)
        let capturedOwner = fixture.store.ownerID!
        fixture.store.authStateChanged(ownerID: ownerB)
        let saved = await fixture.store.setParticipating(false, for: capturedOwner)
        XCTAssertFalse(saved)
        XCTAssertTrue(fixture.service.setRequests.isEmpty)
        XCTAssertEqual(fixture.store.ownerID, ownerB)
        XCTAssertTrue(fixture.store.isEnrolled)
        XCTAssertTrue(fixture.store.freeProAccess)
        XCTAssertNil(fixture.store.errorMessage)

        let currentSaved = await fixture.store.setParticipating(false, for: ownerB)
        XCTAssertTrue(currentSaved)
        XCTAssertEqual(fixture.service.setRequests.count, 1)
        XCTAssertEqual(fixture.service.setRequests.first?.owner, ownerB)
        XCTAssertFalse(fixture.store.freeProAccess)
    }

    func testUnconfirmedParticipationResponseDoesNotChangeChoiceOrCache() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: ownerA)
        fixture.service.onSet = { _, owner in self.status(owner: owner, participating: true) }
        let saved = await fixture.store.setParticipating(false)
        XCTAssertFalse(saved)
        XCTAssertTrue(fixture.store.isEnrolled)
        XCTAssertTrue(fixture.store.freeProAccess)
        XCTAssertNil(fixture.store.status)
        XCTAssertNotNil(fixture.store.errorMessage)
    }

    func testStaleFetchCannotApplyAfterAToBToAAccountChanges() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let started = expectation(description: "A fetch started")
        var held: CheckedContinuation<IChartBetaProStatus, Never>?
        fixture.service.onFetch = { _ in
            started.fulfill()
            return await withCheckedContinuation { held = $0 }
        }
        fixture.store.authStateChanged(ownerID: ownerA)
        let request = Task { await fixture.store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        fixture.store.authStateChanged(ownerID: ownerB)
        fixture.store.authStateChanged(ownerID: ownerA)
        held?.resume(returning: status(owner: ownerA, participating: false))
        await request.value
        XCTAssertTrue(fixture.store.isEnrolled)
        XCTAssertTrue(fixture.store.freeProAccess)
        XCTAssertNil(fixture.store.status)
        XCTAssertNil(fixture.store.errorMessage)
        XCTAssertFalse(fixture.store.isWorking)
    }

    func testStaleMutationCannotChangeNewOwnerOrItsCache() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        let started = expectation(description: "A mutation started")
        var held: CheckedContinuation<IChartBetaProStatus, Never>?
        fixture.service.onSet = { _, _ in
            started.fulfill()
            return await withCheckedContinuation { held = $0 }
        }
        fixture.store.authStateChanged(ownerID: ownerA)
        let request = Task { await fixture.store.setParticipating(false) }
        await fulfillment(of: [started], timeout: 2)
        fixture.store.authStateChanged(ownerID: ownerB)
        held?.resume(returning: status(owner: ownerA, participating: false))
        let saved = await request.value
        XCTAssertFalse(saved)
        XCTAssertEqual(fixture.store.ownerID, ownerB)
        XCTAssertTrue(fixture.store.isEnrolled)
        XCTAssertTrue(fixture.store.freeProAccess)
        XCTAssertNil(fixture.store.errorMessage)
        XCTAssertEqual(fixture.service.setRequests.first?.owner, ownerA)
        let reopened = IChartBetaProStore(service: fixture.service, defaults: fixture.defaults)
        reopened.authStateChanged(ownerID: ownerA)
        XCTAssertTrue(reopened.isEnrolled, "An unconfirmed stale response cannot write A's cache either")
    }

    func testWrongOwnerAndInconsistentGrantCannotBeApplied() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: ownerA)
        fixture.service.onFetch = { [ownerB] _ in self.status(owner: ownerB, participating: false) }
        await fixture.store.refresh()
        XCTAssertTrue(fixture.store.freeProAccess)
        XCTAssertNil(fixture.store.status)
        fixture.service.onFetch = { [ownerA] _ in
            IChartBetaProStatus(ownerID: ownerA, policyID: "fixture", betaAvailable: false,
                eligible: true, participating: true, freeProAccess: true)
        }
        await fixture.store.refresh()
        XCTAssertTrue(fixture.store.freeProAccess)
        XCTAssertNil(fixture.store.status)
        XCTAssertNotNil(fixture.store.errorMessage)
    }

    func testServerEndingRevokesBetaGrantWithoutFalsifyingParticipationAndSurvivesOfflineRestart() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: ownerA)
        fixture.service.onFetch = { [ownerA] _ in
            IChartBetaProStatus(ownerID: ownerA, policyID: "fixture", betaAvailable: false,
                eligible: true, participating: true, freeProAccess: false)
        }
        await fixture.store.refresh()
        XCTAssertTrue(fixture.store.isEnrolled)
        XCTAssertFalse(fixture.store.freeProAccess)
        let reopened = IChartBetaProStore(service: fixture.service, defaults: fixture.defaults)
        reopened.authStateChanged(ownerID: ownerA, isOffline: true)
        XCTAssertTrue(reopened.isEnrolled)
        XCTAssertFalse(reopened.freeProAccess)
    }

    func testNoticeAcknowledgementRequiresExactCurrentNoticeAndOwner() async {
        let fixture = makeFixture()
        defer { fixture.clean() }
        fixture.service.onFetch = { owner in
            var value = self.status(owner: owner, participating: true)
            value.noticeID = "notice-1"
            value.noticeTitle = "Beta update"
            value.noticeBody = "An advance notice, not a purchase."
            value.betaEndingAt = "2026-12-01T00:00:00Z"
            return value
        }
        fixture.store.authStateChanged(ownerID: ownerA)
        await fixture.store.refresh()
        XCTAssertEqual(fixture.store.pendingNotice?.id, "notice-1")
        fixture.store.acknowledgeNotice("wrong-notice")
        XCTAssertNotNil(fixture.store.pendingNotice)
        fixture.store.acknowledgeNotice("notice-1")
        XCTAssertNil(fixture.store.pendingNotice)
        await fixture.store.refresh()
        XCTAssertNil(fixture.store.pendingNotice)
        fixture.store.authStateChanged(ownerID: ownerB)
        await fixture.store.refresh()
        XCTAssertEqual(fixture.store.pendingNotice?.id, "notice-1", "A cannot acknowledge B's notice")
        XCTAssertEqual(fixture.store.pendingNotice?.ownerID, ownerB)
        fixture.store.acknowledgeNotice("notice-1", for: ownerA)
        XCTAssertNotNil(fixture.store.pendingNotice, "An old A alert cannot dismiss B's same-ID notice")
        fixture.store.authStateChanged(ownerID: nil)
        fixture.store.acknowledgeNotice("notice-1")
        XCTAssertNil(fixture.store.pendingNotice)
        XCTAssertFalse(fixture.store.freeProAccess)
    }

    func testRPCStatusDecodesSnakeCaseAndIncompleteNoticeIsNotPresented() throws {
        let data = Data("""
        {"owner_id":"11111111-1111-4111-8111-111111111111","policy_id":"fixture",
        "beta_available":true,"eligible":true,"participating":false,"free_pro_access":false,
        "notice_id":"notice-2","notice_title":null,"notice_body":"Incomplete","beta_ending_at":null}
        """.utf8)
        let decoded = try JSONDecoder().decode(IChartBetaProStatus.self, from: data)
        XCTAssertEqual(decoded.ownerID, ownerA)
        XCTAssertFalse(decoded.participating)
        XCTAssertTrue(decoded.hasConsistentAccess)
        XCTAssertNil(decoded.notice)
        XCTAssertEqual(try JSONDecoder().decode(IChartBetaProStatus.self, from: JSONEncoder().encode(decoded)), decoded)
    }

    func testLiveRPCMutationIncludesPinnedExpectedOwnerAndNoChartOrBillingPayload() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("iChart/App/Supabase/IChartSupabaseBetaProService.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("expectedOwnerID: ownerID"))
        XCTAssertTrue(source.contains("case expectedOwnerID = \"p_expected_owner_id\""))
        XCTAssertTrue(source.contains("case participating = \"p_participating\""))
        XCTAssertTrue(source.contains("session.user.id == expectedOwner"))
        XCTAssertFalse(source.contains("ChartLibrarySnapshot"))
        XCTAssertFalse(source.contains("activePro("))
        XCTAssertFalse(source.contains("Transaction.currentEntitlements"))
    }

    private func status(owner: UUID, participating: Bool) -> IChartBetaProStatus {
        IChartBetaProStatus(ownerID: owner, policyID: "fixture", betaAvailable: true,
            eligible: true, participating: participating, freeProAccess: participating)
    }

    private func makeFixture() -> Fixture {
        let suite = "iChartBetaProStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let service = StubBetaProService()
        return Fixture(store: IChartBetaProStore(service: service, defaults: defaults),
            service: service, defaults: defaults, suite: suite)
    }

    private struct Fixture {
        let store: IChartBetaProStore
        let service: StubBetaProService
        let defaults: UserDefaults
        let suite: String
        func clean() { defaults.removePersistentDomain(forName: suite) }
    }

    private enum TestFailure: Error { case privateServiceDetail }
}

@MainActor
private final class StubBetaProService: IChartBetaProService {
    var fetchRequests: [UUID] = []
    var setRequests: [(owner: UUID, participating: Bool)] = []
    var onFetch: ((UUID) async throws -> IChartBetaProStatus)?
    var onSet: ((Bool, UUID) async throws -> IChartBetaProStatus)?
    var setError: Error?

    func fetchStatus(for ownerID: UUID) async throws -> IChartBetaProStatus {
        fetchRequests.append(ownerID)
        if let onFetch { return try await onFetch(ownerID) }
        return response(ownerID, true)
    }

    func setParticipation(_ participating: Bool, for ownerID: UUID) async throws -> IChartBetaProStatus {
        setRequests.append((ownerID, participating))
        if let setError { throw setError }
        if let onSet { return try await onSet(participating, ownerID) }
        return response(ownerID, participating)
    }

    private func response(_ owner: UUID, _ participating: Bool) -> IChartBetaProStatus {
        IChartBetaProStatus(ownerID: owner, policyID: "fixture", betaAvailable: true,
            eligible: true, participating: participating, freeProAccess: participating)
    }
}
