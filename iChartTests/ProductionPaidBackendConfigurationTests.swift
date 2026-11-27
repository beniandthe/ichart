#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class ProductionPaidBackendConfigurationTests: XCTestCase {
    private let productionURL = "https://pausvvwoazbvmzyrebwl.supabase.co"
    private let stagingURL = "https://gfqpbikqvdgtjjgxrkgo.supabase.co"
    private let bundleKey = "sb_publishable_synthetic_bundle_client_0123456789"
    private let overrideKey = "sb_publishable_synthetic_override_client_9876543210"

    #if ICHART_PAID_SUBSCRIPTION && !ICHART_STAGING_STOREKIT_PRODUCTS
    func testPaidConfigurationUsesOnlyBundledProductionInputsDespiteLaunchOverrides() throws {
        try withBundleInfo(productionInfo) { bundle in
            for overrideURL in [productionURL, stagingURL, "https://unexpected.invalid", "http://localhost:54321"] {
                let configuration = IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                    "SUPABASE_URL": overrideURL,
                    "SUPABASE_PUBLISHABLE_KEY": overrideKey,
                    "SUPABASE_ANON_KEY": "sb_secret_synthetic_not_a_client_key"
                ])
                XCTAssertEqual(configuration?.url.absoluteString, productionURL)
                XCTAssertEqual(configuration?.publishableKey, bundleKey)
            }
        }
    }

    func testPaidConfigurationCannotRepairMissingOrWrongBundledOriginWithEnvironment() throws {
        let invalidOrigins: [String?] = [
            nil, "", "$(SUPABASE_URL)", "not a URL", stagingURL,
            "http://pausvvwoazbvmzyrebwl.supabase.co", productionURL + "/",
            productionURL + "/functions/v1", productionURL + "?project=other",
            productionURL + "#fragment", "https://pausvvwoazbvmzyrebwl.supabase.co.evil.invalid",
            "https://user@pausvvwoazbvmzyrebwl.supabase.co", productionURL + ":443"
        ]
        for origin in invalidOrigins {
            var info = productionInfo
            info["SupabaseURL"] = origin
            try withBundleInfo(info) { bundle in
                XCTAssertNil(IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                    "SUPABASE_URL": productionURL,
                    "SUPABASE_PUBLISHABLE_KEY": overrideKey
                ]), "Invalid bundled origin must fail closed: \(origin ?? "missing")")
            }
        }
    }

    func testPaidConfigurationRejectsMissingOrNonPublishableBundleKeyWithoutFallback() throws {
        let invalidKeys: [String?] = [
            nil, "", "$(SUPABASE_PUBLISHABLE_KEY)", "your-publishable-key",
            "replace-with-key", "sb_secret_synthetic_not_a_client_key",
            "invented.jwt.string", "sb_publishable_short", "sb_publishable_invalid key with spaces",
            "sb_publishable_valid_prefix_but_bad_suffix!"
        ]
        for key in invalidKeys {
            var info = productionInfo
            info["SupabasePublishableKey"] = key
            info["SupabaseAnonKey"] = bundleKey
            try withBundleInfo(info) { bundle in
                XCTAssertNil(IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                    "SUPABASE_URL": productionURL,
                    "SUPABASE_PUBLISHABLE_KEY": overrideKey,
                    "SUPABASE_ANON_KEY": overrideKey
                ]), "The reviewed publishable Info field is required; legacy and environment values cannot replace it")
            }
        }
    }

    func testPaidConfigurationWorksWithoutEnvironmentAndIgnoresUnrelatedLegacyBundleKey() throws {
        var info = productionInfo
        info["SupabaseAnonKey"] = "sb_secret_synthetic_not_a_client_key"
        try withBundleInfo(info) { bundle in
            let configuration = IChartSupabaseConfiguration.current(bundle: bundle, environment: [:])
            XCTAssertEqual(configuration?.url.absoluteString, productionURL)
            XCTAssertEqual(configuration?.publishableKey, bundleKey)
        }
    }

    func testPaidApplicationBundleStaysProductionWhenEnvironmentSelectsStaging() throws {
        XCTAssertEqual(IChartProductAccessPolicy.current, .paidSubscription)
        let configuration = try XCTUnwrap(IChartSupabaseConfiguration.current(environment: [
            "SUPABASE_URL": stagingURL,
            "SUPABASE_PUBLISHABLE_KEY": overrideKey
        ]))
        XCTAssertEqual(configuration.url.absoluteString, productionURL)
        XCTAssertEqual(configuration.publishableKey,
                       Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String)
    }
    #elseif ICHART_STAGING_STOREKIT_PRODUCTS
    func testHistoricStagingScopeStillUsesOnlyValidStagingOverrides() throws {
        try withBundleInfo(productionInfo) { bundle in
            let staging = IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                "SUPABASE_URL": stagingURL,
                "SUPABASE_PUBLISHABLE_KEY": overrideKey
            ])
            XCTAssertEqual(staging?.url.absoluteString, stagingURL)
            XCTAssertEqual(staging?.publishableKey, overrideKey)
            XCTAssertNil(IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                "SUPABASE_URL": productionURL,
                "SUPABASE_PUBLISHABLE_KEY": overrideKey
            ]))
        }
    }
    #else
    func testNormalFreeBuildRetainsExplicitEnvironmentOverrides() throws {
        try withBundleInfo(productionInfo) { bundle in
            let configuration = IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                "SUPABASE_URL": stagingURL,
                "SUPABASE_PUBLISHABLE_KEY": overrideKey
            ])
            XCTAssertEqual(configuration?.url.absoluteString, stagingURL)
            XCTAssertEqual(configuration?.publishableKey, overrideKey)
        }
    }

    func testNormalFreeBuildRetainsLegacyEnvironmentAndBundleFallbacks() throws {
        var info = productionInfo
        info.removeValue(forKey: "SupabasePublishableKey")
        info["SupabaseAnonKey"] = "legacy.bundle.client.key"
        try withBundleInfo(info) { bundle in
            let legacyOverride = IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                "SUPABASE_URL": "http://localhost:54321",
                "SUPABASE_ANON_KEY": "legacy.environment.client.key"
            ])
            XCTAssertEqual(legacyOverride?.url.absoluteString, "http://localhost:54321")
            XCTAssertEqual(legacyOverride?.publishableKey, "legacy.environment.client.key")
            let bundled = IChartSupabaseConfiguration.current(bundle: bundle, environment: [:])
            XCTAssertEqual(bundled?.url.absoluteString, productionURL)
            XCTAssertEqual(bundled?.publishableKey, "legacy.bundle.client.key")
        }
    }
    #endif

    private var productionInfo: [String: String] {
        ["SupabaseURL": productionURL, "SupabasePublishableKey": bundleKey]
    }

    private func withBundleInfo(
        _ values: [String: String],
        operation: (Bundle) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProductionPaidBackendConfigurationTests-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var info = values
        info["CFBundleIdentifier"] = "com.ichart.tests.backend.\(UUID().uuidString)"
        info["CFBundleName"] = "Backend Configuration Fixture"
        info["CFBundlePackageType"] = "BNDL"
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("Info.plist"))
        try operation(XCTUnwrap(Bundle(url: directory)))
    }
}
#endif
