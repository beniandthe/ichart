import Foundation
import XCTest
@testable import iChart

final class IChartKnownExpiryExportContextTests: XCTestCase {
    func testPersonalExportReevaluatesKnownActiveAndGraceBoundsWithoutChangingSavedBilling() {
        let deadline = Date(timeIntervalSinceReferenceDate: 1_000)
        for billing in [IChartSubscriptionEntitlement.activePro(accessEndsAt: deadline, willAutoRenew: false),
                        .proGrace(graceEndsAt: deadline)] {
            let entitlements = AppEntitlements(subscription: billing, accessPolicy: .paidSubscription)
            XCTAssertFalse(ChartPDFExportContext.personalChart(entitlements: entitlements,
                now: deadline.addingTimeInterval(-1)).showsIChartCredit)
            XCTAssertTrue(ChartPDFExportContext.personalChart(entitlements: entitlements,
                now: deadline).showsIChartCredit)
            XCTAssertTrue(ChartPDFExportContext.personalChart(entitlements: entitlements,
                now: deadline.addingTimeInterval(1)).showsIChartCredit)
            XCTAssertEqual(entitlements.subscription, billing)
        }
    }
}
