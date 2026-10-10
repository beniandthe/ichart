import Foundation

struct IChartStoreKitProductOption: Equatable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
    let valueBadge: String?
}

struct IChartStoreKitRecurringPrice: Equatable {
    enum Period: Equatable {
        case months(Int)
        case years(Int)
        case other
    }

    let productID: String
    let price: Decimal
    let currencyCode: String
    let period: Period
}

enum IChartStoreKitProductCatalog {
    static let proMonthlyProductID = "com.ichart.app.pro.monthly"
    static let proAnnualProductID = "com.ichart.app.pro.annual"
    static let targetMonthlyPriceCents = 799
    static let targetAnnualPriceCents = 6_499

    static let proProductIDs: [String] = [
        proMonthlyProductID,
        proAnnualProductID
    ]

    static func isProProductID(_ productID: String) -> Bool {
        proProductIDs.contains(productID)
    }

    static func valueBadge(for productID: String, recurringPrices: [IChartStoreKitRecurringPrice]) -> String? {
        guard productID == proAnnualProductID else { return nil }
        let monthlyPrices = recurringPrices.filter { $0.productID == proMonthlyProductID }
        let annualPrices = recurringPrices.filter { $0.productID == proAnnualProductID }
        guard monthlyPrices.count == 1, annualPrices.count == 1,
              let monthly = monthlyPrices.first, let annual = annualPrices.first,
              monthly.period == .months(1), annual.period == .years(1),
              !monthly.currencyCode.isEmpty, monthly.currencyCode == annual.currencyCode,
              let percent = annualSavingsPercent(monthlyPrice: monthly.price, annualPrice: annual.price)
        else { return nil }
        return "Save \(percent)%"
    }

    private static func annualSavingsPercent(monthlyPrice: Decimal, annualPrice: Decimal) -> Int? {
        guard !monthlyPrice.isNaN, !annualPrice.isNaN, monthlyPrice > 0, annualPrice > 0 else { return nil }
        var monthly = monthlyPrice, annual = annualPrice, months = Decimal(12)
        var annualizedMonthly = Decimal(), savings = Decimal(), hundred = Decimal(100)
        var savingsTimesHundred = Decimal(), percent = Decimal(), wholePercent = Decimal()
        guard NSDecimalMultiply(&annualizedMonthly, &monthly, &months, .down) == .noError,
              annual < annualizedMonthly,
              NSDecimalSubtract(&savings, &annualizedMonthly, &annual, .down) == .noError,
              NSDecimalMultiply(&savingsTimesHundred, &savings, &hundred, .down) == .noError
        else { return nil }
        let division = NSDecimalDivide(&percent, &savingsTimesHundred, &annualizedMonthly, .down)
        guard division == .noError || division == .lossOfPrecision else { return nil }
        // Never round the claimed saving up, or advertise a zero-percent saving.
        NSDecimalRound(&wholePercent, &percent, 0, .down)
        guard !wholePercent.isNaN, wholePercent >= 1, wholePercent < 100 else { return nil }
        return NSDecimalNumber(decimal: wholePercent).intValue
    }

    #if DEBUG && targetEnvironment(simulator)
    private static let localPreviewRecurringPrices: [IChartStoreKitRecurringPrice] = [
        IChartStoreKitRecurringPrice(productID: proMonthlyProductID,
                                    price: Decimal(targetMonthlyPriceCents) / 100,
                                    currencyCode: "USD", period: .months(1)),
        IChartStoreKitRecurringPrice(productID: proAnnualProductID,
                                    price: Decimal(targetAnnualPriceCents) / 100,
                                    currencyCode: "USD", period: .years(1))
    ]
    static let localPreviewProductOptions: [IChartStoreKitProductOption] = [
        IChartStoreKitProductOption(
            id: proMonthlyProductID,
            displayName: "iChart Pro Monthly",
            description: "Monthly Pro access for iChart.",
            displayPrice: "$7.99",
            valueBadge: valueBadge(for: proMonthlyProductID, recurringPrices: localPreviewRecurringPrices)
        ),
        IChartStoreKitProductOption(
            id: proAnnualProductID,
            displayName: "iChart Pro Annual",
            description: "Annual Pro access for iChart.",
            displayPrice: "$64.99",
            valueBadge: valueBadge(for: proAnnualProductID, recurringPrices: localPreviewRecurringPrices)
        )
    ]
    #endif
}

enum IChartStoreKitEntitlementResolver {
    static func entitlement(
        hasActiveProSubscription: Bool,
        sawExpiredProTransaction: Bool,
        accessEndsAt: Date? = nil,
        verifiedAt: Date
    ) -> IChartSubscriptionEntitlement {
        if hasActiveProSubscription {
            return .activePro(accessEndsAt: accessEndsAt, verifiedAt: verifiedAt)
        }

        if sawExpiredProTransaction {
            return .proExpired(verifiedAt: verifiedAt)
        }

        return .basic
    }

    static func serverBackedEntitlement(
        remoteEntitlement: IChartSubscriptionEntitlement?,
        localEntitlement: IChartSubscriptionEntitlement
    ) -> IChartSubscriptionEntitlement {
        if let remoteEntitlement {
            return remoteEntitlement
        }

        return .basic
    }

    static func serverBackedFallbackForRemoteFailure(
        localEntitlement: IChartSubscriptionEntitlement
    ) -> IChartSubscriptionEntitlement? {
        localEntitlement.status == .proActive ? nil : .basic
    }
}
