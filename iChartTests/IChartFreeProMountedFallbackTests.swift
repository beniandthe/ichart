#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Mounted coverage of the actual Upgrade fallback, not a test-created copy.
/// The private Plan settings view is covered separately by its source contract;
/// this suite does not claim that its existing-billing controls were mounted.
@MainActor
final class IChartFreeProMountedFallbackTests: XCTestCase {
    func testBasicBillingShowsFreeFallbackWithoutPurchaseOrTrialControls() async throws {
        try await assertFreeFallback(billing: .basic)
    }

    func testExpiredBillingShowsFreeFallbackWithoutPurchaseOrTrialControls() async throws {
        try await assertFreeFallback(billing: .proExpired(verifiedAt: Date(timeIntervalSinceReferenceDate: 42)))
    }

    func testUnavailableBillingShowsFreeFallbackWithoutPurchaseOrTrialControls() async throws {
        try await assertFreeFallback(billing: .unavailable)
    }

    private func assertFreeFallback(
        billing: IChartSubscriptionEntitlement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let library = ChartLibraryStore(charts: [], entitlements: AppEntitlements(subscription: billing))
        let subscriptionStore = IChartStoreKitSubscriptionStore.live()
        let originalStoreBilling = subscriptionStore.entitlement
        let root = UpgradeSheetView(feature: .projects)
            .environmentObject(library)
            .environmentObject(subscriptionStore)
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive },
            "A foreground scene is required to exercise the mounted fallback", file: file, line: line)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1_180)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        try await waitForFreeFallback(in: window, file: file, line: line)
        XCTAssertTrue(window.isKeyWindow, file: file, line: line)
        XCTAssertFalse(try NativeAccessibilityLookup.matching(IChartLegalLinks.freeProTitle, in: window).isEmpty,
            "The rendered fallback must explicitly identify free Pro access", file: file, line: line)
        XCTAssertFalse(try NativeAccessibilityLookup.matching(IChartLegalLinks.freeProNotice, in: window).isEmpty,
            "Free access must be visible, not inferred from an empty product response", file: file, line: line)
        XCTAssertFalse(try NativeAccessibilityLookup.matching(IChartLegalLinks.futurePricingNotice, in: window).isEmpty,
            "The actual fallback must show the no-automatic-paid-conversion notice", file: file, line: line)
        let done = try XCTUnwrap(NativeAccessibilityLookup.matching("Done", in: window, buttonsOnly: true).first,
            "Free users need an enabled way to leave the fallback", file: file, line: line)
        XCTAssertTrue(done.isEnabled, file: file, line: line)
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Unlock Pro", in: window).isEmpty, file: file, line: line)

        let checkoutWords = ["monthly", "annual", "trial", "subscribe", "purchase", "one month", "claim", "unlock", "restore"]
        let buttons = try NativeAccessibilityLookup.nodes(in: window).filter(\.isButton)
        for button in buttons {
            let label = button.element.accessibilityLabel?.lowercased() ?? ""
            XCTAssertFalse(checkoutWords.contains(where: label.contains),
                "A free fallback must not expose a paid/offer control: \(label)", file: file, line: line)
        }
        XCTAssertEqual(library.entitlements.subscription, billing,
            "Rendering free access must not change the customer's billing state", file: file, line: line)
        XCTAssertEqual(subscriptionStore.entitlement, originalStoreBilling,
            "Mounting free UI must not mint a paid StoreKit entitlement", file: file, line: line)
        XCTAssertFalse(IChartProductAccessPolicy.current.offersPaidPurchases, file: file, line: line)
        XCTAssertTrue(library.canUse(.projects), file: file, line: line)
        XCTAssertNil(library.localChartLimit, file: file, line: line)
    }

    private func waitForFreeFallback(
        in window: UIWindow,
        file: StaticString,
        line: UInt
    ) async throws {
        for _ in 0..<60 {
            window.layoutIfNeeded()
            window.rootViewController?.view.layoutIfNeeded()
            if try !NativeAccessibilityLookup.matching(IChartLegalLinks.freeProNotice, in: window).isEmpty,
               try !NativeAccessibilityLookup.matching("Done", in: window, buttonsOnly: true).isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let snapshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        snapshot.name = "Free Pro fallback did not mount"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        XCTFail("The actual free fallback did not display its notice and Done control before timeout", file: file, line: line)
        throw NSError(domain: "IChartFreeProMountedFallbackTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Free fallback did not finish mounting"])
    }
}
#endif
