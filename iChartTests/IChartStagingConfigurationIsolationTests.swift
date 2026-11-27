#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class IChartStagingConfigurationIsolationTests: XCTestCase {
    private let stagingURL = "https://gfqpbikqvdgtjjgxrkgo.supabase.co"
    private let publicURL = "https://pausvvwoazbvmzyrebwl.supabase.co"
    private let publicKey = "sb_publishable_synthetic_staging_client_0123456789"

    func testSelectedConfigurationKeepsOrdinaryBehaviorAndRejectsWrongStagingOverrides() throws {
        let configured = IChartSupabaseConfiguration.current(environment: [
            "SUPABASE_URL": stagingURL,
            "SUPABASE_PUBLISHABLE_KEY": publicKey
        ])
        #if ICHART_COORDINATED_STAGING_QA
        XCTAssertEqual(configured?.url.absoluteString, "https://yiuxduqhhbucsmooevxz.supabase.co")
        XCTAssertEqual(configured?.publishableKey, Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String)
        #elseif ICHART_PAID_SUBSCRIPTION && !ICHART_STAGING_STOREKIT_PRODUCTS
        XCTAssertEqual(configured?.url.absoluteString, publicURL)
        XCTAssertEqual(configured?.publishableKey, Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String)
        #else
        XCTAssertEqual(configured?.url.absoluteString, stagingURL)
        XCTAssertEqual(configured?.publishableKey, publicKey)
        #endif
        let ordinary = IChartSupabaseConfiguration.current(environment: [
            "SUPABASE_URL": publicURL,
            "SUPABASE_PUBLISHABLE_KEY": publicKey
        ])
        #if ICHART_COORDINATED_STAGING_QA
        XCTAssertEqual(ordinary?.url.absoluteString, "https://yiuxduqhhbucsmooevxz.supabase.co")
        #elseif ICHART_STAGING_STOREKIT_PRODUCTS
        XCTAssertNil(ordinary, "Staging must fail closed when a launch override selects production")
        #else
        XCTAssertEqual(ordinary?.url.absoluteString, publicURL)
        #endif
    }

    func testStagingRejectsInsecureAlternateOriginsAndNonClientKeys() {
        #if ICHART_STAGING_STOREKIT_PRODUCTS && !ICHART_COORDINATED_STAGING_QA
        for url in ["http://gfqpbikqvdgtjjgxrkgo.supabase.co", "https://wrong.invalid", stagingURL + "/path", publicURL] {
            XCTAssertNil(IChartSupabaseConfiguration.current(environment: ["SUPABASE_URL": url, "SUPABASE_PUBLISHABLE_KEY": publicKey]))
        }
        for key in ["sb_secret_synthetic_not_a_client_key", "invented.jwt.string", "sb_publishable_short"] {
            XCTAssertNil(IChartSupabaseConfiguration.current(environment: ["SUPABASE_URL": stagingURL, "SUPABASE_PUBLISHABLE_KEY": key]))
        }
        #endif
    }
}
#endif
