import Foundation
import XCTest
@testable import iChart

/// Runtime consent/transport and legacy-report tests are the behavioral gates.
/// These source checks additionally catch accidentally disconnected UI wiring.
final class PrivacyControlsIntegrationTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    func testLegalLinksUseThePublicPoliciesAndSubscriptionNoticeIsExplicit() {
        XCTAssertEqual(IChartLegalLinks.privacyURL.absoluteString, "https://useichart.com/privacy.html")
        XCTAssertEqual(IChartLegalLinks.termsURL.absoluteString, "https://useichart.com/terms.html")
        XCTAssertTrue(IChartLegalLinks.subscriptionNotice.contains("renew automatically"))
        XCTAssertTrue(IChartLegalLinks.diagnosticsNotice.contains("account identifier"))
        XCTAssertTrue(IChartLegalLinks.diagnosticsWithdrawalNotice.contains("already sent may finish"))
        XCTAssertTrue(IChartLegalLinks.diagnosticsWithdrawalNotice.contains("does not delete reports already received"))
    }

    func testConsentIsAccessibleAndBothPurchaseSurfacesHaveLegalLinks() throws {
        let library = try String(contentsOf: root.appendingPathComponent("iChart/Features/Library/LibraryView.swift"))
        let upgrade = try String(contentsOf: root.appendingPathComponent("iChart/Features/Editor/Components/UpgradeSheetView.swift"))
        XCTAssertTrue(library.contains("title: \"Privacy\""))
        XCTAssertTrue(library.contains("Toggle(\"Share app diagnostics\""))
        XCTAssertTrue(library.contains("IChartTelemetry.setConsentGranted($0)"))
        XCTAssertTrue(library.contains("IChartTelemetryConsentStore.currentVersion"))
        XCTAssertTrue(library.contains("IChartLegalLinks.diagnosticsWithdrawalNotice"))
        let purchase = library.components(separatedBy: "private var storeKitControls: some View").last ?? ""
        XCTAssertTrue(purchase.contains("IChartLegalLinksView()"))
        XCTAssertTrue(purchase.contains("IChartLegalLinks.subscriptionNotice"))
        XCTAssertTrue(upgrade.contains("IChartLegalLinksView()"))
        XCTAssertTrue(upgrade.contains("IChartLegalLinks.subscriptionNotice"))
    }

    func testAppReportExportNeverFallsBackToSharingTheOriginalTrace() throws {
        let source = try String(contentsOf: root.appendingPathComponent("iChart/Services/IChartPerformanceTrace.swift"))
        XCTAssertTrue(source.contains("return try recorder.exportReport()"))
        XCTAssertFalse(source.contains("return recorder.url"))
        XCTAssertFalse(source.contains("ProcessInfo.processInfo.systemUptime"))
    }

    func testExplicitSupportReportDisclosureAndManifestDoNotClaimTimingOnly() throws {
        let library = try String(contentsOf: root.appendingPathComponent("iChart/Features/Library/LibraryView.swift"))
        XCTAssertTrue(library.contains("Timing and diagnostic context. Stays on this iPad until you share it."))
        XCTAssertFalse(library.contains("Timing only. Stays on this iPad until shared."))

        let data = try Data(contentsOf: root.appendingPathComponent("iChart/Resources/PrivacyInfo.xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        let types = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let supportEntries = types.filter { $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeCustomerSupport" }
        XCTAssertEqual(supportEntries.count, 1)
        let support = try XCTUnwrap(supportEntries.first)
        XCTAssertEqual(support["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
        XCTAssertEqual(support["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(support["NSPrivacyCollectedDataTypePurposes"] as? [String], ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
    }

}
