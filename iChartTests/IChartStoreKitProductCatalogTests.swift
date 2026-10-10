import Foundation
import XCTest
@testable import iChart

final class IChartStoreKitProductCatalogTests: XCTestCase {
    private typealias Price = IChartStoreKitRecurringPrice
    private let monthlyID = IChartStoreKitProductCatalog.proMonthlyProductID
    private let annualID = IChartStoreKitProductCatalog.proAnnualProductID

    func testAnnualBadgeUsesFetchedPricesInsteadOfTargets() {
        XCTAssertEqual(badge(monthly: "10", annual: "90"), "Save 25%")
        XCTAssertEqual(badge(monthly: "20", annual: "120"), "Save 50%")
    }

    func testAnnualBadgeUsesExactFractionalCurrencyPrices() {
        XCTAssertEqual(badge(monthly: "0.10", annual: "0.90"), "Save 25%")
        XCTAssertEqual(badge(monthly: "9.99", annual: "89.91"), "Save 25%")
    }

    func testAnnualBadgePreservesLocalPreviewTargetSaving() {
        let monthly = Decimal(IChartStoreKitProductCatalog.targetMonthlyPriceCents) / 100
        let annual = Decimal(IChartStoreKitProductCatalog.targetAnnualPriceCents) / 100
        XCTAssertEqual(valueBadge([price(monthlyID, monthly, .months(1)), price(annualID, annual, .years(1))]),
                       "Save 32%")
        #if DEBUG && targetEnvironment(simulator)
        XCTAssertEqual(IChartStoreKitProductCatalog.localPreviewProductOptions.first { $0.id == annualID }?.valueBadge,
                       "Save 32%")
        XCTAssertNil(IChartStoreKitProductCatalog.localPreviewProductOptions.first { $0.id == monthlyID }?.valueBadge)
        #endif
    }

    func testAnnualBadgeRoundsDownWithoutOverstatingSaving() {
        XCTAssertEqual(badge(monthly: "10", annual: "99"), "Save 17%")
        XCTAssertEqual(badge(monthly: "1", annual: "8"), "Save 33%")
        XCTAssertEqual(badge(monthly: "10", annual: "0.01"), "Save 99%")
    }

    func testAnnualBadgeOmitsSubOnePercentSaving() {
        XCTAssertNil(badge(monthly: "10", annual: "119.99"))
        XCTAssertNil(badge(monthly: "10", annual: "118.81"))
        XCTAssertEqual(badge(monthly: "10", annual: "118.80"), "Save 1%")
    }

    func testAnnualBadgeOmitsEqualOrMoreExpensiveAnnualPrices() {
        XCTAssertNil(badge(monthly: "10", annual: "120"))
        XCTAssertNil(badge(monthly: "10", annual: "121"))
    }

    func testAnnualBadgeRequiresBothFetchedProducts() {
        XCTAssertNil(valueBadge([]))
        XCTAssertNil(valueBadge([price(monthlyID, 10, .months(1))]))
        XCTAssertNil(valueBadge([price(annualID, 90, .years(1))]))
    }

    func testAnnualBadgeRequiresMatchingNonemptyCurrencies() {
        XCTAssertNil(valueBadge([price(monthlyID, 10, .months(1), currency: "USD"),
                                 price(annualID, 90, .years(1), currency: "EUR")]))
        XCTAssertNil(valueBadge([price(monthlyID, 10, .months(1), currency: ""),
                                 price(annualID, 90, .years(1), currency: "")]))
        XCTAssertEqual(valueBadge([price(monthlyID, 10, .months(1), currency: "EUR"),
                                   price(annualID, 90, .years(1), currency: "EUR")]), "Save 25%")
    }

    func testAnnualBadgeRequiresOneMonthAndOneYearPeriods() {
        for period in [Price.Period.months(2), .years(1), .other] {
            XCTAssertNil(valueBadge([price(monthlyID, 10, period), price(annualID, 90, .years(1))]))
        }
        for period in [Price.Period.years(2), .months(12), .other] {
            XCTAssertNil(valueBadge([price(monthlyID, 10, .months(1)), price(annualID, 90, period)]))
        }
    }

    func testAnnualBadgeRejectsInvalidPricesAndArithmeticOverflow() {
        for invalid in [Decimal(0), Decimal(-1), .nan] {
            XCTAssertNil(valueBadge([price(monthlyID, invalid, .months(1)), price(annualID, 90, .years(1))]))
            XCTAssertNil(valueBadge([price(monthlyID, 10, .months(1)), price(annualID, invalid, .years(1))]))
        }
        let veryLarge = NSDecimalNumber.maximum.decimalValue
        XCTAssertNil(valueBadge([price(monthlyID, veryLarge, .months(1)), price(annualID, 90, .years(1))]))
    }

    func testAnnualBadgeRejectsAmbiguousDuplicateProducts() {
        let monthly = price(monthlyID, 10, .months(1)), annual = price(annualID, 90, .years(1))
        XCTAssertNil(valueBadge([monthly, monthly, annual]))
        XCTAssertNil(valueBadge([monthly, annual, annual]))
    }

    func testSavingsBadgeAppearsOnlyOnAnnualProduct() {
        let prices = [price(monthlyID, 10, .months(1)), price(annualID, 90, .years(1))]
        XCTAssertNil(IChartStoreKitProductCatalog.valueBadge(for: monthlyID, recurringPrices: prices))
        XCTAssertNil(IChartStoreKitProductCatalog.valueBadge(for: "unknown", recurringPrices: prices))
    }

    private func badge(monthly: String, annual: String) -> String? {
        let locale = Locale(identifier: "en_US_POSIX")
        return valueBadge([price(monthlyID, Decimal(string: monthly, locale: locale)!, .months(1)),
                           price(annualID, Decimal(string: annual, locale: locale)!, .years(1))])
    }

    private func valueBadge(_ prices: [Price]) -> String? {
        IChartStoreKitProductCatalog.valueBadge(for: annualID, recurringPrices: prices)
    }

    private func price(_ productID: String, _ price: Decimal, _ period: Price.Period,
                       currency: String = "USD") -> Price {
        Price(productID: productID, price: price, currencyCode: currency, period: period)
    }
}
