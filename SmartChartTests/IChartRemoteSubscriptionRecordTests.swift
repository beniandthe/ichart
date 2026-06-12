import XCTest
@testable import SmartChart

final class IChartRemoteSubscriptionRecordTests: XCTestCase {
    func testActiveStoreKitRowResolvesToActiveProForKnownProduct() throws {
        let record = try decodeRecord(
            appStoreStatus: "active",
            entitlementExpiresAt: "2026-07-12T21:00:00.000Z",
            lastVerifiedAt: "2026-06-12T21:00:00.000Z"
        )

        let entitlement = record.entitlement(now: isoDate("2026-06-12T21:00:00.000Z"))

        XCTAssertEqual(entitlement.status, .proActive)
        XCTAssertEqual(entitlement.lastVerifiedAt, isoDate("2026-06-12T21:00:00.000Z"))
    }

    func testExpiredStoreKitRowResolvesToExpiredPro() throws {
        let record = try decodeRecord(
            appStoreStatus: "active",
            entitlementExpiresAt: "2026-06-01T21:00:00.000Z",
            lastVerifiedAt: "2026-06-12T21:00:00.000Z"
        )

        let entitlement = record.entitlement(now: isoDate("2026-06-12T21:00:00.000Z"))

        XCTAssertEqual(entitlement.status, .proExpired)
        XCTAssertEqual(entitlement.lastVerifiedAt, isoDate("2026-06-12T21:00:00.000Z"))
    }

    func testGraceStoreKitRowResolvesToGraceWithoutUnlockingProPlan() throws {
        let record = try decodeRecord(
            appStoreStatus: "billing_retry",
            gracePeriodExpiresAt: "2026-06-20T21:00:00.000Z",
            lastVerifiedAt: "2026-06-12T21:00:00.000Z"
        )

        let entitlement = record.entitlement(now: isoDate("2026-06-12T21:00:00.000Z"))

        XCTAssertEqual(entitlement.status, .proGrace)
        XCTAssertEqual(entitlement.graceEndsAt, isoDate("2026-06-20T21:00:00.000Z"))
        XCTAssertEqual(entitlement.effectivePlan, .free)
    }

    func testUnknownStoreKitProductDoesNotUnlockPro() throws {
        let record = try decodeRecord(
            productID: "com.smartchart.app.basic",
            appStoreStatus: "active",
            entitlementExpiresAt: "2026-07-12T21:00:00.000Z"
        )

        XCTAssertEqual(record.entitlement().status, .basic)
    }

    func testLegacyServerOwnedActivePlanCanStillResolveDuringMigrationWindow() throws {
        let record = try decodeRecord(
            plan: "studioSubscription",
            status: "active",
            provider: "none",
            productID: nil,
            appStoreStatus: nil,
            entitlementExpiresAt: nil
        )

        XCTAssertEqual(record.entitlement().status, .proActive)
    }

    private func decodeRecord(
        plan: String = "free",
        status: String = "inactive",
        provider: String = "storekit",
        productID: String? = "com.smartchart.app.pro.annual",
        appStoreStatus: String?,
        entitlementExpiresAt: String? = nil,
        gracePeriodExpiresAt: String? = nil,
        lastVerifiedAt: String? = nil
    ) throws -> IChartRemoteSubscriptionRecord {
        let payload: [String: Any?] = [
            "owner_id": "00000000-0000-0000-0000-000000000001",
            "plan": plan,
            "status": status,
            "provider": provider,
            "storekit_product_id": productID,
            "storekit_original_transaction_id": "1000000000000001",
            "storekit_environment": "sandbox",
            "app_store_status": appStoreStatus,
            "entitlement_expires_at": entitlementExpiresAt,
            "grace_period_expires_at": gracePeriodExpiresAt,
            "revoked_at": nil,
            "last_verified_at": lastVerifiedAt
        ]

        let data = try JSONSerialization.data(
            withJSONObject: payload.compactMapValues { $0 },
            options: [.sortedKeys]
        )
        return try JSONDecoder().decode(IChartRemoteSubscriptionRecord.self, from: data)
    }

    private func isoDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }
}
