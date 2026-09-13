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

    func testCustomerNoticeDisclosesIdentifiersAndRecognitionDiagnostics() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("public-site/useichart/privacy.html"))
        XCTAssertTrue(text.contains("random installation identifier"))
        XCTAssertTrue(text.contains("session identifier"))
        XCTAssertTrue(text.contains("linked to your iChart account identifier"))
        XCTAssertTrue(text.contains("recognition pipeline version"))
        XCTAssertTrue(text.contains("telemetry does not collect chart titles"))
        XCTAssertTrue(text.contains("handwritten drawing data"))
    }
}
#endif
