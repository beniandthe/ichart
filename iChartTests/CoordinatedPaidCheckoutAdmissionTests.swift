import Foundation
import XCTest
@testable import iChart

@MainActor
final class CoordinatedPaidCheckoutAdmissionTests: XCTestCase {
    func testFreshPaidStatusAdmitsSpyOnlyAfterAnIndependentRead() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        let requestsBefore = fixture.service.productRequests.count
        var appleCalls = 0
        if await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) { appleCalls += 1 }

        XCTAssertEqual(fixture.service.productRequests.count, requestsBefore + 1)
        XCTAssertEqual(appleCalls, 1)
    }

    func testFreeRollbackReadDeniesCheckoutDespiteCachedPaidStatus() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 4)
        }
        var appleCalls = 0
        if await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) { appleCalls += 1 }

        XCTAssertEqual(appleCalls, 0)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
        XCTAssertEqual(fixture.store.productAccessStatus?.policyRevision, 4)
    }

    func testOfflineOrWrongCapturedOwnerCannotStartCheckoutRead() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        var appleCalls = 0
        if await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) { appleCalls += 1 }
        fixture.store.authStateChanged(ownerID: fixture.ownerB)
        if await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) { appleCalls += 1 }

        XCTAssertEqual(appleCalls, 0)
        XCTAssertTrue(fixture.service.productRequests.isEmpty)
    }

    func testWrongOwnerUnsupportedSchemaUnknownPhaseAndIneligibleResponsesDenyCheckout() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        let responses = [
            CoordinatedAccessTestFixture.status(owner: fixture.ownerB, phase: .paid, revision: 2),
            CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 3, schemaVersion: 2),
            CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .unsupported("future-phase"), revision: 4),
            CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 5, eligible: false),
            CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 6,
                                                policyID: "unexpected-policy-v1")
        ]
        var appleCalls = 0
        for response in responses {
            fixture.service.onProductFetch = { _ in response }
            if await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) { appleCalls += 1 }
        }

        XCTAssertEqual(appleCalls, 0)
        XCTAssertEqual(fixture.service.productRequests.count, responses.count)
    }

    func testFailedFreshReadCannotUseCachedPaidStatusToAdmitCheckout() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        fixture.service.onProductFetch = { _ in throw SyntheticFailure.unavailable }
        var appleCalls = 0
        if await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) { appleCalls += 1 }

        XCTAssertEqual(appleCalls, 0)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .paidSubscription, "A request failure does not erase confirmed local rights")
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
        XCTAssertNotNil(fixture.store.accessStatusMessage)
    }

    func testAccountCycleWhileAdmissionReadIsHeldCannotReachAppleSpy() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        let started = expectation(description: "Checkout admission read started")
        var held: CheckedContinuation<IChartProductAccessStatus, Never>?
        fixture.service.onProductFetch = { _ in
            started.fulfill()
            return await withCheckedContinuation { held = $0 }
        }
        var appleCalls = 0
        let admission = Task {
            if await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) { appleCalls += 1 }
        }
        await fulfillment(of: [started], timeout: 2)
        fixture.store.authStateChanged(ownerID: fixture.ownerB)
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        held?.resume(returning: CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 9))
        await admission.value

        XCTAssertEqual(appleCalls, 0)
        XCTAssertNil(fixture.store.productAccessStatus)
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
    }

    func testPreviouslySeenHigherRollbackRevisionRejectsStalePaidCheckoutRead() async {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 9)
        }
        await fixture.store.refresh()
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 8)
        }
        var appleCalls = 0
        if await fixture.store.authorizePaidCheckout(expectedOwnerID: fixture.ownerA) { appleCalls += 1 }

        XCTAssertEqual(appleCalls, 0)
        XCTAssertEqual(fixture.store.productAccessStatus?.policyRevision, 9)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
    }

    #if canImport(UIKit)
    func testActualSubscriptionStoreLibraryProjectionRejectsUnboundProAndPreservesLegacyLocalRight() {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        let billing = IChartSubscriptionEntitlement.activePro(accessEndsAt: Date().addingTimeInterval(3_600), verifiedAt: Date())
        let subscriptionStore = IChartStoreKitSubscriptionStore(entitlement: billing, productAccessStore: fixture.store)
        XCTAssertNil(subscriptionStore.verifiedSubscriptionOwnerID)
        XCTAssertEqual(subscriptionStore.entitlementForLibrary(ownerID: fixture.ownerB,
            currentLibraryEntitlement: .basic), .unavailable)
        XCTAssertEqual(subscriptionStore.entitlementForLibrary(ownerID: nil,
            currentLibraryEntitlement: .basic), .basic)
        XCTAssertEqual(subscriptionStore.entitlementForLibrary(ownerID: fixture.ownerB,
            currentLibraryEntitlement: .legacyLocalPro), .legacyLocalPro)
        XCTAssertEqual(subscriptionStore.entitlement, billing, "The library projection cannot rewrite StoreKit billing evidence")
    }

    func testActualSubscriptionStoreBoundaryInvokesSpyOnlyAfterFreshPaidRead() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        let subscriptionStore = IChartStoreKitSubscriptionStore(productAccessStore: fixture.store)
        let billingBefore = subscriptionStore.entitlement
        let requestsBefore = fixture.service.productRequests.count
        var appleCalls = 0
        let result = try await subscriptionStore.performAdmittedPaidCheckout(expectedOwnerID: fixture.ownerA) {
            appleCalls += 1
            return "synthetic-operation-result"
        }

        XCTAssertEqual(result, "synthetic-operation-result")
        XCTAssertEqual(appleCalls, 1)
        XCTAssertEqual(fixture.service.productRequests.count, requestsBefore + 1)
        XCTAssertEqual(subscriptionStore.entitlement, billingBefore, "Admission alone cannot create a paid entitlement")
    }

    func testActualSubscriptionStoreBoundaryRejectsFreshRollbackDespitePriorPaidAvailability() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        let subscriptionStore = IChartStoreKitSubscriptionStore(entitlement: .activePro(), productAccessStore: fixture.store)
        let billingBefore = subscriptionStore.entitlement
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 4)
        }
        var appleCalls = 0
        let result: String? = try await subscriptionStore.performAdmittedPaidCheckout(expectedOwnerID: fixture.ownerA) {
            appleCalls += 1
            return "must-not-run"
        }

        XCTAssertNil(result)
        XCTAssertEqual(appleCalls, 0)
        XCTAssertEqual(subscriptionStore.state, .ready)
        XCTAssertEqual(subscriptionStore.entitlement, billingBefore, "Rollback changes product policy, not paid billing evidence")
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .freeAllFeatures)
    }

    func testActualSubscriptionStoreBoundaryRejectsFailedFreshReadWithoutFallingBackToCache() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        let subscriptionStore = IChartStoreKitSubscriptionStore(productAccessStore: fixture.store)
        fixture.service.onProductFetch = { _ in throw SyntheticFailure.unavailable }
        var appleCalls = 0
        let result: String? = try await subscriptionStore.performAdmittedPaidCheckout(expectedOwnerID: fixture.ownerA) {
            appleCalls += 1
            return "must-not-run"
        }

        XCTAssertNil(result)
        XCTAssertEqual(appleCalls, 0)
        XCTAssertEqual(fixture.store.resolvedAccessPolicy, .paidSubscription)
        XCTAssertFalse(fixture.store.hasFreshProductAccess)
    }

    func testActualSubscriptionStoreBoundaryRejectsUnsupportedOrIneligibleFreshResponses() async throws {
        for variant in 0...3 {
            let fixture = CoordinatedAccessTestFixture()
            defer { fixture.clean() }
            fixture.store.authStateChanged(ownerID: fixture.ownerA)
            fixture.service.onProductFetch = { owner in
                CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
            }
            await fixture.store.refresh()
            let subscriptionStore = IChartStoreKitSubscriptionStore(productAccessStore: fixture.store)
            fixture.service.onProductFetch = { owner in
                switch variant {
                case 0: return CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 4, schemaVersion: 2)
                case 1: return CoordinatedAccessTestFixture.status(owner: owner, phase: .unsupported("future-phase"), revision: 4)
                case 2: return CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 4, eligible: false)
                default: return CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 4,
                                                                   policyID: "unexpected-policy-v1")
                }
            }
            var appleCalls = 0
            let result: String? = try await subscriptionStore.performAdmittedPaidCheckout(expectedOwnerID: fixture.ownerA) {
                appleCalls += 1
                return "must-not-run"
            }
            XCTAssertNil(result)
            XCTAssertEqual(appleCalls, 0)
        }
    }

    func testActualSubscriptionStoreBoundaryRejectsWrongCapturedOwnerWithoutCallingService() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        let subscriptionStore = IChartStoreKitSubscriptionStore(productAccessStore: fixture.store)
        let requestsBefore = fixture.service.productRequests.count
        var appleCalls = 0
        let result: String? = try await subscriptionStore.performAdmittedPaidCheckout(expectedOwnerID: fixture.ownerB) {
            appleCalls += 1
            return "must-not-run"
        }

        XCTAssertNil(result)
        XCTAssertEqual(appleCalls, 0)
        XCTAssertEqual(fixture.service.productRequests.count, requestsBefore)
    }

    func testActualSubscriptionStoreBoundaryRejectsOwnerCycleDuringFreshAdmission() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .paid, revision: 3)
        }
        await fixture.store.refresh()
        let subscriptionStore = IChartStoreKitSubscriptionStore(productAccessStore: fixture.store)
        let started = expectation(description: "Actual checkout boundary admission started")
        var held: CheckedContinuation<IChartProductAccessStatus, Never>?
        fixture.service.onProductFetch = { _ in
            started.fulfill()
            return await withCheckedContinuation { held = $0 }
        }
        var appleCalls = 0
        let request = Task { try await subscriptionStore.performAdmittedPaidCheckout(expectedOwnerID: fixture.ownerA) {
            appleCalls += 1
            return "must-not-run"
        } }
        await fulfillment(of: [started], timeout: 2)
        fixture.store.authStateChanged(ownerID: fixture.ownerB)
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        held?.resume(returning: CoordinatedAccessTestFixture.status(owner: fixture.ownerA, phase: .paid, revision: 4))
        let result = try await request.value

        XCTAssertNil(result)
        XCTAssertEqual(appleCalls, 0)
    }
    #endif

    private enum SyntheticFailure: Error { case unavailable }
}
