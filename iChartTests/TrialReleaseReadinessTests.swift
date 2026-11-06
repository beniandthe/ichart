#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TrialReleaseReadinessTests: XCTestCase {
    func testAppBundleContainsItsOwnRequiredReasonPrivacyManifest() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        let declarations = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let expected = [
            "NSPrivacyAccessedAPICategoryUserDefaults": "CA92.1",
            "NSPrivacyAccessedAPICategorySystemBootTime": "35F9.1",
            "NSPrivacyAccessedAPICategoryFileTimestamp": "C617.1"
        ]
        for (category, reason) in expected {
            let declaration = try XCTUnwrap(declarations.first {
                $0["NSPrivacyAccessedAPIType"] as? String == category
            })
            XCTAssertEqual(declaration["NSPrivacyAccessedAPITypeReasons"] as? [String], [reason])
        }
    }

    func testManifestDeclaresLinkedFirstPartyTelemetryWithoutTracking() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        let declarations = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let expected: Set<String> = [
            "NSPrivacyCollectedDataTypeDeviceID", "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeProductInteraction", "NSPrivacyCollectedDataTypePerformanceData",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData"
        ]
        let actual = Set(declarations.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        XCTAssertTrue(actual.isSuperset(of: expected))
        for declaration in declarations {
            XCTAssertEqual(declaration["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(declaration["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            let purposes = try XCTUnwrap(declaration["NSPrivacyCollectedDataTypePurposes"] as? [String])
            XCTAssertFalse(purposes.isEmpty)
            XCTAssertTrue(Set(purposes).isSubset(of: [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality",
                "NSPrivacyCollectedDataTypePurposeAnalytics"
            ]))
        }
    }

    func testNormalTelemetryConfigurationAndBuildSourceAreExplicit() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let endpoint = try XCTUnwrap(info["SupabaseURL"] as? String)
        XCTAssertEqual(URL(string: endpoint)?.host, "pausvvwoazbvmzyrebwl.supabase.co")
        XCTAssertTrue((info["SupabasePublishableKey"] as? String)?.hasPrefix("sb_publishable_") == true)
        #if DEBUG
        XCTAssertEqual(IChartTelemetryBuildSource.value, "debug_build")
        #else
        XCTAssertEqual(IChartTelemetryBuildSource.value, "release_build")
        #endif
    }

    func testCustomerNoticeDistinguishesBasicDiagnosticsFromHistoricalExpandedRecords() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("public-site/useichart/privacy.html"))
        let basicStart = try XCTUnwrap(text.range(of: "<p>In versions with basic diagnostics,"))
        let historicalStart = try XCTUnwrap(text.range(of: "<p>Older versions with expanded diagnostics"))
        XCTAssertLessThan(basicStart.lowerBound, historicalStart.lowerBound)
        let basic = String(text[basicStart.lowerBound..<historicalStart.lowerBound])
        XCTAssertTrue(basic.contains("error counts, elapsed timings, and fixed correction categories"))
        XCTAssertTrue(basic.contains("random installation and diagnostic-session identifiers"))
        XCTAssertTrue(basic.contains("not advertising or tracking across other companies' apps or websites"))
        XCTAssertTrue(basic.contains("do not inspect ink appearance, create chart references or source-content fingerprints"))
        XCTAssertFalse(basic.contains("recognition pipeline version"))
        XCTAssertFalse(basic.contains("opaque chart reference"))
        XCTAssertTrue(text.contains("Older versions with expanded diagnostics could also send recognition pipeline versions"))
        XCTAssertTrue(text.contains("those older diagnostic records could be linked to an iChart account identifier"))
        XCTAssertTrue(text.contains("telemetry does not collect chart titles"))
        for excludedContent in ["raw chord text", "handwritten drawing data", "source-content hashes",
                                "PDF files", "screenshots", "editable chart documents"] {
            XCTAssertTrue(text.contains(excludedContent), excludedContent)
        }
    }
}
#endif
