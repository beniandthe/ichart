import Foundation
import XCTest
@testable import iChart

@MainActor
final class CoordinatedQAConfigurationTests: XCTestCase {
    func testActualCompiledLaneSelectsItsOwnCoordinatorNamespaceAndProducts() {
        #if ICHART_COORDINATED_STAGING_QA
        XCTAssertTrue(IChartProductAccessPolicy.usesCoordinatedActivation)
        XCTAssertEqual(IChartStorageNamespace.mode, .coordinatedStagingQA)
        XCTAssertEqual(IChartStorageNamespace.productAccessCacheProjectRef, "yiuxduqhhbucsmooevxz")
        XCTAssertEqual(IChartStorageNamespace.activeDefaultsSuiteName, IChartStorageNamespace.coordinatedQADefaultsSuiteName)
        #elseif ICHART_STAGING_STOREKIT_PRODUCTS
        XCTAssertFalse(IChartProductAccessPolicy.usesCoordinatedActivation)
        XCTAssertEqual(IChartStorageNamespace.mode, .internalStaging)
        XCTAssertEqual(IChartStorageNamespace.productAccessCacheProjectRef, "gfqpbikqvdgtjjgxrkgo")
        XCTAssertEqual(IChartStorageNamespace.activeDefaultsSuiteName, IChartStorageNamespace.stagingDefaultsSuiteName)
        #else
        XCTAssertEqual(IChartStorageNamespace.mode, .publicApp)
        XCTAssertEqual(IChartStorageNamespace.productAccessCacheProjectRef, "pausvvwoazbvmzyrebwl")
        XCTAssertNil(IChartStorageNamespace.activeDefaultsSuiteName)
        #if ICHART_PAID_SUBSCRIPTION && !ICHART_LOCAL_PLAN_QA && !ICHART_LOCAL_QA_PLAN_PREVIEW
        XCTAssertTrue(IChartProductAccessPolicy.usesCoordinatedActivation)
        #else
        XCTAssertFalse(IChartProductAccessPolicy.usesCoordinatedActivation)
        #endif
        #endif
        #if ICHART_STAGING_STOREKIT_PRODUCTS
        XCTAssertEqual(IChartStoreKitProductCatalog.proProductIDs,
                       ["com.ichart.app.staging.fix036.monthly", "com.ichart.app.staging.fix036.annual"])
        XCTAssertFalse(IChartStoreKitProductCatalog.isProProductID("com.ichart.app.pro.monthly"))
        #else
        XCTAssertEqual(IChartStoreKitProductCatalog.proProductIDs,
                       ["com.ichart.app.pro.monthly", "com.ichart.app.pro.annual"])
        #endif
    }

    func testAllThreeLocalAndAuthNamespacesStayDistinctWithoutFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CoordinatedQANamespaces-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let modes: [IChartStorageNamespace.Mode] = [.publicApp, .internalStaging, .coordinatedStagingQA]
        let paths = modes.map { IChartStorageNamespace.scopedDirectory(root, mode: $0) }
        XCTAssertEqual(Set(paths).count, 3)
        for originalRoot in ["/synthetic/Library/Application Support", "/synthetic/Library/Caches", "/synthetic/tmp"] {
            let original = URL(fileURLWithPath: originalRoot, isDirectory: true)
            let qa = IChartStorageNamespace.scopedDirectory(original, mode: .coordinatedStagingQA)
            XCTAssertEqual(qa.deletingLastPathComponent(), original)
            XCTAssertEqual(qa.lastPathComponent, IChartStorageNamespace.coordinatedQADirectoryName)
            XCTAssertNotEqual(qa, IChartStorageNamespace.scopedDirectory(original, mode: .internalStaging))
        }
        for key in ["iChart.supabase.session.v1", "supabase.session", "iChart.pending-auth-flow.v1",
                    "sb-pausvvwoazbvmzyrebwl-auth-token", "sb-gfqpbikqvdgtjjgxrkgo-auth-token",
                    "sb-yiuxduqhhbucsmooevxz-auth-token-code-verifier"] {
            let scoped = modes.map { IChartStorageNamespace.authStorageKey(key, mode: $0) }
            XCTAssertEqual(Set(scoped).count, 3)
            XCTAssertEqual(scoped[0], key)
            XCTAssertEqual(scoped[1], IChartStorageNamespace.stagingAuthKeyPrefix + key)
            XCTAssertEqual(scoped[2], IChartStorageNamespace.coordinatedQAAuthKeyPrefix + key)
        }
        let relative = "iChart/library-state.json"
        var chart = Chart.blank(title: "Synthetic protected chart")
        chart.pageHandwrittenChordData = Data([1, 4, 9, 16])
        chart.pageHandwrittenNotationData = Data([2, 6, 12])
        let original = ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id, entitlements: .free,
            projects: [.init(title: "Synthetic protected project", chartIDs: [chart.id])])
        for path in paths.prefix(2) {
            try FileChartRepository(url: path.appendingPathComponent(relative)).saveSnapshot(original)
        }
        let protected = try paths.prefix(2).map { try Data(contentsOf: $0.appendingPathComponent(relative)) }
        let qaRepository = FileChartRepository(url: paths[2].appendingPathComponent(relative))
        XCTAssertNil(try qaRepository.loadSnapshot(), "A new QA library must not import either older namespace")
        try qaRepository.saveSnapshot(.empty)
        for (index, path) in paths.prefix(2).enumerated() {
            XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent(relative)), protected[index])
        }
        let otherContent = ["iChart/PDF Library/fixture.pdf", "iChart/PDF Library/pdf-library.json",
                            "iChart/Setlists/pdf-setlists.json", "iChart/chord-ink-correction-memory.json"]
        for relativePath in otherContent {
            for path in paths {
                let url = path.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data((path == paths[2] ? "new synthetic QA" : "protected synthetic content").utf8).write(to: url)
            }
        }
        try FileManager.default.removeItem(at: paths[2])
        for (index, path) in paths.prefix(2).enumerated() {
            XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent(relative)), protected[index])
            for relativePath in otherContent {
                XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent(relativePath)), Data("protected synthetic content".utf8))
            }
        }
    }

    func testPhaseCacheUsesOnlySelectedProjectAndOwnerWithoutCrossLaneHydration() async throws {
        let fixture = CoordinatedAccessTestFixture()
        defer { fixture.clean() }
        fixture.store.authStateChanged(ownerID: fixture.ownerA)
        fixture.service.onProductFetch = { owner in
            CoordinatedAccessTestFixture.status(owner: owner, phase: .freeBeta, revision: 2)
        }
        await fixture.store.refresh()
        let keys = fixture.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("iChart.productAccess.v1.") }
        let expected = "iChart.productAccess.v1.\(IChartStorageNamespace.productAccessCacheProjectRef).\(fixture.ownerA.uuidString.lowercased())"
        XCTAssertEqual(keys, [expected])
        let data = try XCTUnwrap(fixture.defaults.data(forKey: expected))
        fixture.defaults.removeObject(forKey: expected)
        let foreignProject = IChartStorageNamespace.productAccessCacheProjectRef == "yiuxduqhhbucsmooevxz"
            ? "pausvvwoazbvmzyrebwl" : "yiuxduqhhbucsmooevxz"
        fixture.defaults.set(data, forKey: "iChart.productAccess.v1.\(foreignProject).\(fixture.ownerA.uuidString.lowercased())")
        let reopened = fixture.reopenedStore()
        reopened.authStateChanged(ownerID: fixture.ownerA, isOffline: true)
        XCTAssertNil(reopened.productAccessStatus)
        XCTAssertEqual(reopened.resolvedAccessPolicy, .betaBasic)
        XCTAssertFalse(reopened.hasFreshProductAccess)
        XCTAssertFalse(reopened.canOfferPaidPurchases)
        fixture.defaults.set(data, forKey: expected)
        reopened.authStateChanged(ownerID: fixture.ownerB, isOffline: true)
        XCTAssertNil(reopened.productAccessStatus)
        XCTAssertFalse(reopened.canOfferPaidPurchases)
    }
}

#if canImport(UIKit)
import CryptoKit

final class CoordinatedQABackendRoutingTests: XCTestCase {
    private let qaURL = "https://yiuxduqhhbucsmooevxz.supabase.co"
    private let productionURL = "https://pausvvwoazbvmzyrebwl.supabase.co"
    private let historicalURL = "https://gfqpbikqvdgtjjgxrkgo.supabase.co"
    private let key = "sb_publishable_synthetic_isolated_qa_client_0123456789"
    private let overrideKey = "sb_publishable_synthetic_override_qa_client_9876543210"

    func testActualQAApplicationBundlePinsOriginKeyAndEmptyLegacyValueDespiteLaunchOverrides() throws {
        #if ICHART_COORDINATED_STAGING_QA
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.ichart.app", "The actual application must host this validation")
        XCTAssertEqual(IChartStorageNamespace.mode, .coordinatedStagingQA)
        XCTAssertTrue(IChartProductAccessPolicy.usesCoordinatedActivation)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String, qaURL)
        let bundledKey = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String)
        let keyHash = SHA256.hash(data: Data(bundledKey.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(keyHash, "bfdf9049a7237013fea1b1f18d137e4d58daa34078fec4290b78a9676e9038e2")
        let legacy = (Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(legacy, "", "The QA application must not contain a legacy-key fallback")
        for foreign in [productionURL, historicalURL, "https://unexpected.invalid"] {
            let selected = try XCTUnwrap(IChartSupabaseConfiguration.current(bundle: .main, environment: [
                "SUPABASE_URL": foreign, "SUPABASE_PUBLISHABLE_KEY": overrideKey,
                "SUPABASE_ANON_KEY": "legacy.environment.client.key"
            ]))
            XCTAssertEqual(selected.url.absoluteString, qaURL)
            XCTAssertEqual(selected.publishableKey, bundledKey)
        }
        #else
        XCTAssertFalse(IChartStorageNamespace.mode == .coordinatedStagingQA)
        #endif
    }

    func testEachActualLaneUsesItsOwnRoutingRulesWithoutChangingAnotherLane() throws {
        #if ICHART_COORDINATED_STAGING_QA
        let bundledURL = qaURL
        #elseif ICHART_STAGING_STOREKIT_PRODUCTS
        let bundledURL = historicalURL
        #else
        let bundledURL = productionURL
        #endif
        try withBundleInfo(["SupabaseURL": bundledURL, "SupabasePublishableKey": key]) { bundle in
            let configured = IChartSupabaseConfiguration.current(bundle: bundle, environment: [:])
            XCTAssertEqual(configured?.url.absoluteString, bundledURL)
            XCTAssertEqual(configured?.publishableKey, key)
            let overridden = IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                "SUPABASE_URL": "https://unexpected.invalid", "SUPABASE_PUBLISHABLE_KEY": overrideKey
            ])
            #if ICHART_COORDINATED_STAGING_QA || (ICHART_PAID_SUBSCRIPTION && !ICHART_STAGING_STOREKIT_PRODUCTS)
            XCTAssertEqual(overridden?.url.absoluteString, bundledURL)
            XCTAssertEqual(overridden?.publishableKey, key)
            #elseif ICHART_STAGING_STOREKIT_PRODUCTS
            XCTAssertNil(overridden)
            #else
            XCTAssertEqual(overridden?.url.absoluteString, "https://unexpected.invalid")
            XCTAssertEqual(overridden?.publishableKey, overrideKey)
            #endif
        }
    }

    func testCoordinatedQARejectsEveryMissingOrForeignBundleOriginWithoutLaunchRepair() throws {
        #if ICHART_COORDINATED_STAGING_QA
        let origins: [String?] = [nil, "", "$(SUPABASE_URL)", productionURL, historicalURL,
            "http://yiuxduqhhbucsmooevxz.supabase.co", qaURL + "/", qaURL + "/functions/v1",
            qaURL + "?project=public", qaURL + "#fragment", qaURL + ":443",
            "https://user@yiuxduqhhbucsmooevxz.supabase.co", qaURL + ".unexpected.invalid"]
        for origin in origins {
            var info = ["SupabasePublishableKey": key]
            info["SupabaseURL"] = origin
            try withBundleInfo(info) { bundle in
                XCTAssertNil(IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                    "SUPABASE_URL": qaURL, "SUPABASE_PUBLISHABLE_KEY": overrideKey
                ]))
            }
        }
        #else
        XCTAssertFalse(IChartStorageNamespace.mode == .coordinatedStagingQA,
                       "This lane deliberately does not acquire coordinated QA semantics")
        #endif
    }

    func testCoordinatedQACannotUseLegacyOrEnvironmentKeyFallback() throws {
        #if ICHART_COORDINATED_STAGING_QA
        let invalidKeys: [String?] = [nil, "", "$(SUPABASE_PUBLISHABLE_KEY)", "your-client-key",
            ["sb", "secret", "synthetic_not_a_client_key"].joined(separator: "_"),
            "invented.jwt.string", "sb_publishable_short", "sb_publishable_invalid key with spaces"]
        for invalid in invalidKeys {
            var info = ["SupabaseURL": qaURL, "SupabaseAnonKey": key]
            info["SupabasePublishableKey"] = invalid
            try withBundleInfo(info) { bundle in
                XCTAssertNil(IChartSupabaseConfiguration.current(bundle: bundle, environment: [
                    "SUPABASE_URL": qaURL, "SUPABASE_PUBLISHABLE_KEY": overrideKey, "SUPABASE_ANON_KEY": overrideKey
                ]))
            }
        }
        #else
        XCTAssertFalse(IChartStorageNamespace.mode == .coordinatedStagingQA)
        #endif
    }

    private func withBundleInfo(_ values: [String: String], operation: (Bundle) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoordinatedQABackendRouting-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var info = values
        info["CFBundleIdentifier"] = "com.ichart.tests.coordinated-qa.\(UUID().uuidString)"
        info["CFBundlePackageType"] = "BNDL"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Info.plist"))
        try operation(XCTUnwrap(Bundle(url: directory)))
    }
}
#endif
