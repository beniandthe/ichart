import Foundation

struct IChartStoreKitProductOption: Equatable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
}

enum IChartStoreKitProductCatalog {
    static let proMonthlyProductID = "com.smartchart.app.pro.monthly"
    static let proAnnualProductID = "com.smartchart.app.pro.annual"
    static let localStoreKitConfigurationFileName = "iChartProSubscriptions.storekit"

    static let proProductIDs: [String] = [
        proMonthlyProductID,
        proAnnualProductID
    ]

    static func isProProductID(_ productID: String) -> Bool {
        proProductIDs.contains(productID)
    }
}

enum IChartStoreKitEntitlementResolver {
    static func entitlement(
        hasActiveProSubscription: Bool,
        sawExpiredProTransaction: Bool,
        verifiedAt: Date
    ) -> IChartSubscriptionEntitlement {
        if hasActiveProSubscription {
            return .activePro(verifiedAt: verifiedAt)
        }

        if sawExpiredProTransaction {
            return .proExpired(verifiedAt: verifiedAt)
        }

        return .basic
    }
}
