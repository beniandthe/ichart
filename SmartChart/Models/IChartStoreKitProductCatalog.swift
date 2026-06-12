import Foundation

struct IChartStoreKitProductOption: Equatable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
    let valueBadge: String?
}

enum IChartStoreKitProductCatalog {
    static let proMonthlyProductID = "com.smartchart.app.pro.monthly"
    static let proAnnualProductID = "com.smartchart.app.pro.annual"
    static let localStoreKitConfigurationFileName = "iChartProSubscriptions.storekit"
    static let targetMonthlyPriceCents = 799
    static let targetAnnualPriceCents = 6_499

    static var annualSavingsPercent: Int {
        let monthlyYearPrice = Double(targetMonthlyPriceCents * 12)
        let annualPrice = Double(targetAnnualPriceCents)
        return Int(((monthlyYearPrice - annualPrice) / monthlyYearPrice * 100).rounded())
    }

    static var annualSavingsBadge: String {
        "Save \(annualSavingsPercent)%"
    }

    static let proProductIDs: [String] = [
        proMonthlyProductID,
        proAnnualProductID
    ]

    static func isProProductID(_ productID: String) -> Bool {
        proProductIDs.contains(productID)
    }

    static func valueBadge(for productID: String) -> String? {
        productID == proAnnualProductID ? annualSavingsBadge : nil
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
