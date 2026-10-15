#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// The production Beta controls are mounted and activated through public UIKit
/// accessibility/control actions. This is not a StoreKit purchase test.
@MainActor
final class IChartBetaProMountedControlsTests: XCTestCase {
    func testConfirmedProShowsLeaveWithoutRejoinOrCheckout() async throws {
        let fixture = makeFixture(participating: true)
        defer { fixture.clean() }
        await fixture.store.refresh()
        let mounted = try mount(IChartBetaProControls(store: fixture.store))
        defer { mounted.close() }

        let leave = try await button("Leave Pro — Use Basic", in: mounted.window)
        XCTAssertTrue(leave.isEnabled)
        XCTAssertGreaterThan(leave.frame(in: mounted.window).width, 0)
        XCTAssertGreaterThan(leave.frame(in: mounted.window).height, 0)
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Rejoin Pro — Free During Beta", in: mounted.window).isEmpty)
        try assertNoCheckout(in: mounted.window)
        XCTAssertTrue(fixture.service.setRequests.isEmpty)
    }

    func testMountedRejoinCallsServiceAndCallbackOnlyAfterConfirmedAccess() async throws {
        let fixture = makeFixture(participating: false)
        defer { fixture.clean() }
        await fixture.store.refresh()
        var joinedCount = 0
        let mounted = try mount(IChartBetaProControls(store: fixture.store, didJoin: { joinedCount += 1 }))
        defer { mounted.close() }

        let rejoin = try await button("Rejoin Pro — Free During Beta", in: mounted.window)
        XCTAssertTrue(rejoin.isEnabled)
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Leave Pro — Use Basic", in: mounted.window).isEmpty)
        try assertNoCheckout(in: mounted.window)
        try activate(rejoin)
        try await waitUntil(in: mounted.window) { fixture.store.freeProAccess && joinedCount == 1 }

        XCTAssertEqual(fixture.service.setRequests.map(\.owner), [fixture.owner])
        XCTAssertEqual(fixture.service.setRequests.map(\.participating), [true])
        XCTAssertTrue(fixture.store.isEnrolled)
        XCTAssertFalse(fixture.store.isWorking)
        XCTAssertNil(fixture.store.errorMessage)
        XCTAssertEqual(joinedCount, 1)
        _ = try await button("Leave Pro — Use Basic", in: mounted.window)
        try assertNoCheckout(in: mounted.window)
    }

    func testChangingAccountDismissesOldLeaveConfirmationWithoutMutatingNewAccount() async throws {
        let fixture = makeFixture(participating: true)
        defer { fixture.clean() }
        await fixture.store.refresh()
        let mounted = try mount(IChartBetaProControls(store: fixture.store))
        defer { mounted.close() }

        try activate(try await button("Leave Pro — Use Basic", in: mounted.window))
        _ = try await button("Use Basic", in: mounted.window)
        XCTAssertTrue(fixture.service.setRequests.isEmpty, "Opening the confirmation must not leave Pro yet")
        let nextOwner = UUID()
        fixture.store.authStateChanged(ownerID: nextOwner)
        try await waitUntil(in: mounted.window) {
            try NativeAccessibilityLookup.matching("Use Basic", in: mounted.window, buttonsOnly: true).isEmpty
        }

        XCTAssertEqual(fixture.store.ownerID, nextOwner)
        XCTAssertTrue(fixture.store.freeProAccess)
        XCTAssertTrue(fixture.service.setRequests.isEmpty, "The old owner's dialog must not mutate the next owner")
        _ = try await button("Leave Pro — Use Basic", in: mounted.window)
    }

    func testMountedFailedRejoinKeepsBasicAndShowsRecoverableErrorWithoutCallback() async throws {
        let fixture = makeFixture(participating: false)
        defer { fixture.clean() }
        await fixture.store.refresh()
        fixture.service.failMutation = true
        var joinedCount = 0
        let mounted = try mount(IChartBetaProControls(store: fixture.store, didJoin: { joinedCount += 1 }))
        defer { mounted.close() }

        try activate(try await button("Rejoin Pro — Free During Beta", in: mounted.window))
        try await waitUntil(in: mounted.window) { fixture.store.errorMessage != nil && !fixture.store.isWorking }
        let error = try XCTUnwrap(fixture.store.errorMessage)
        try await waitUntil(in: mounted.window) {
            try !NativeAccessibilityLookup.matching(error, in: mounted.window).isEmpty
        }

        XCTAssertEqual(fixture.service.setRequests.map(\.owner), [fixture.owner])
        XCTAssertEqual(fixture.service.setRequests.map(\.participating), [true])
        XCTAssertFalse(fixture.store.isEnrolled)
        XCTAssertFalse(fixture.store.freeProAccess)
        XCTAssertEqual(joinedCount, 0)
        let retryRejoin = try await button("Rejoin Pro — Free During Beta", in: mounted.window)
        let retryRefresh = try await button("Try Again", in: mounted.window)
        XCTAssertTrue(retryRejoin.isEnabled)
        XCTAssertTrue(retryRefresh.isEnabled)
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Leave Pro — Use Basic", in: mounted.window).isEmpty)
        try assertNoCheckout(in: mounted.window)
    }

    func testUpgradeSheetUsesInjectedBasicMembershipAndOffersFreeRejoinNotCheckout() async throws {
        let fixture = makeFixture(participating: false)
        defer { fixture.clean() }
        await fixture.store.refresh()
        let library = ChartLibraryStore(charts: [], entitlements: AppEntitlements(subscription: .basic, accessPolicy: .betaBasic))
        let subscriptions = IChartStoreKitSubscriptionStore.live()
        let originalBilling = subscriptions.entitlement
        let root = UpgradeSheetView(feature: .projects)
            .environmentObject(library)
            .environmentObject(subscriptions)
            .environment(\.betaProStore, fixture.store)
        let mounted = try mount(root)
        defer { mounted.close() }

        let rejoin = try await button("Rejoin Pro — Free During Beta", in: mounted.window)
        let done = try await button("Done", in: mounted.window)
        XCTAssertTrue(rejoin.isEnabled)
        XCTAssertTrue(done.isEnabled)
        XCTAssertTrue(try NativeAccessibilityLookup.matching("Leave Pro — Use Basic", in: mounted.window).isEmpty)
        try assertNoCheckout(in: mounted.window)
        XCTAssertEqual(library.entitlements.accessPolicy, .betaBasic)
        XCTAssertEqual(library.entitlements.subscription, .basic)
        XCTAssertEqual(subscriptions.entitlement, originalBilling)
        XCTAssertTrue(fixture.service.setRequests.isEmpty)
    }

    private func makeFixture(participating: Bool) -> Fixture {
        let suite = "IChartBetaProMountedControlsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let owner = UUID()
        let service = MountedBetaProService(participating: participating)
        let store = IChartBetaProStore(service: service, defaults: defaults)
        store.authStateChanged(ownerID: owner)
        return Fixture(store: store, service: service, defaults: defaults, suite: suite, owner: owner)
    }

    private func mount<Content: View>(_ content: Content) throws -> Mounted {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "A foreground native test scene is required.")
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: content
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.accessibilityEnabled, true))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1_180)
        window.rootViewController = host
        window.makeKeyAndVisible()
        return Mounted(window: window, previousKeyWindow: previousKeyWindow)
    }

    private func button(_ label: String, in window: UIWindow) async throws -> NativeAccessibilityLookup.Node {
        try await waitUntil(in: window) {
            try !NativeAccessibilityLookup.matching(label, in: window, buttonsOnly: true).isEmpty
        }
        let node = try XCTUnwrap(NativeAccessibilityLookup.matching(label, in: window, buttonsOnly: true).first)
        XCTAssertTrue(node.isEnabled, "Expected enabled \(label)")
        return node
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
        if let button = node.element as? UIButton {
            button.sendActions(for: .touchUpInside)
        } else if !node.element.accessibilityActivate() {
            XCTFail("The mounted control did not accept its public accessibility activation action.")
            throw MountedFailure.activationRejected
        }
    }

    private func assertNoCheckout(in window: UIWindow) throws {
        let paidActions = ["monthly", "annual", "trial", "subscribe", "purchase", "claim", "unlock", "restore"]
        for node in try NativeAccessibilityLookup.nodes(in: window).filter(\.isButton) {
            let label = node.element.accessibilityLabel?.lowercased() ?? ""
            XCTAssertFalse(paidActions.contains(where: label.contains), "Unexpected checkout control: \(label)")
        }
    }

    private func waitUntil(in window: UIWindow, _ condition: () throws -> Bool) async throws {
        for _ in 0..<60 {
            window.layoutIfNeeded()
            window.rootViewController?.view.layoutIfNeeded()
            if try condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let nodes = try NativeAccessibilityLookup.nodes(in: window)
        let details = nodes.map { "\(type(of: $0.element)): \($0.element.accessibilityLabel ?? "nil"), \($0.frame(in: window))" }
            .joined(separator: "\n")
        let attachment = XCTAttachment(string: details)
        attachment.name = "Mounted Beta controls at timeout"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("Production Beta controls did not reach the expected visible state before timeout.")
        throw MountedFailure.timeout
    }

    private struct Fixture {
        let store: IChartBetaProStore
        let service: MountedBetaProService
        let defaults: UserDefaults
        let suite: String
        let owner: UUID
        func clean() { defaults.removePersistentDomain(forName: suite) }
    }

    private struct Mounted {
        let window: UIWindow
        let previousKeyWindow: UIWindow?
        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
    }

    private enum MountedFailure: Error { case activationRejected, timeout }
}

@MainActor
private final class MountedBetaProService: IChartBetaProService {
    var participating: Bool
    var failMutation = false
    private(set) var setRequests: [(owner: UUID, participating: Bool)] = []

    init(participating: Bool) { self.participating = participating }

    func fetchStatus(for ownerID: UUID) async throws -> IChartBetaProStatus { response(for: ownerID) }

    func setParticipation(_ participating: Bool, for ownerID: UUID) async throws -> IChartBetaProStatus {
        setRequests.append((ownerID, participating))
        if failMutation { throw Failure.unavailable }
        self.participating = participating
        return response(for: ownerID)
    }

    private func response(for ownerID: UUID) -> IChartBetaProStatus {
        IChartBetaProStatus(ownerID: ownerID, policyID: "mounted-fixture", betaAvailable: true,
            eligible: true, participating: participating, freeProAccess: participating)
    }

    private enum Failure: Error { case unavailable }
}
#endif
