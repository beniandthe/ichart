#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class CoordinatedPlanPresentationTests: XCTestCase {
    private let owner = UUID(uuidString: "88888888-1111-4111-8111-888888888888")!

    func testComputedHelpAndRecoveryCopyFollowPaidActivationAndBetaRollback() throws {
        let free = presentation(.freeAllFeatures)
        let paid = presentation(.paidSubscription)
        let basic = presentation(.betaBasic)
        func plan(_ value: IChartPlanAccessPresentation) throws -> IChartHelpArticleSection {
            try XCTUnwrap(IChartHelpArticleSection.sections(for: .faq, presentation: value)
                .first { $0.id == "faq-basic-pro" })
        }
        XCTAssertEqual(try plan(free).title, "Is Pro free?")
        XCTAssertEqual(try plan(paid).title, "What does Pro include?")
        XCTAssertEqual(try plan(basic).title, "Is Pro free?")
        XCTAssertTrue(try plan(paid).bullets.contains { $0.contains("every chart already saved") })
        XCTAssertTrue(free.projectCreationMessage.contains("Rejoin free Pro"))
        XCTAssertFalse(paid.projectCreationMessage.contains("Rejoin free Pro"))
        XCTAssertTrue(basic.forumRecoveryMessage.contains("Rejoin Pro — Free"))
        XCTAssertFalse(paid.forumRecoveryMessage.contains("Rejoin Pro — Free"))
        let freeTools = IChartHelpArticleSection.sections(for: .howTo, presentation: free)
        let paidTools = IChartHelpArticleSection.sections(for: .howTo, presentation: paid)
        XCTAssertEqual(freeTools.map(\.id), paidTools.map(\.id))
        for id in ["editor-free-write", "editor-corridor-lane", "editor-writing-ending-brackets"] {
            XCTAssertEqual(freeTools.first { $0.id == id }?.body, paidTools.first { $0.id == id }?.body)
            XCTAssertEqual(freeTools.first { $0.id == id }?.bullets, paidTools.first { $0.id == id }?.bullets)
        }
    }

    func testUnknownPhaseUsesCheckingCopyAndNeverLabelsNetworkFailureBasic() {
        let checking = IChartPlanAccessPresentation(accessPolicy: .freeAllFeatures,
            isAccessChecking: true, canOfferPaidPurchases: false, accessStatusMessage: nil,
            canUseHostedAccountFeatures: false)
        XCTAssertFalse(checking.showsBetaControls)
        XCTAssertFalse(checking.showsPaidPlans)
        XCTAssertFalse(checking.projectReadOnlyMessage.contains("Basic"))
        XCTAssertFalse(checking.projectCreationMessage.contains("Rejoin"))
        for topic in [IChartHelpTopic.faq, .userPolicy, .legal] {
            let sections = IChartHelpArticleSection.sections(for: topic, presentation: checking)
            let section = sections.first { $0.title == "Checking Plan Access" }
            XCTAssertNotNil(section)
            XCTAssertTrue(section?.bullets.contains { $0.contains("Restore Purchases and Manage Subscription") } == true)
        }
    }

    func testHostedForumFloorDoesNotRewriteRetainedLocalAccessOrBilling() {
        let billing = IChartSubscriptionEntitlement.activePro(willAutoRenew: false)
        let local = AppEntitlements(subscription: billing, accessPolicy: .freeAllFeatures)
        var phase = presentation(.freeAllFeatures)
        phase.canUseHostedAccountFeatures = false
        let hosted = phase.forumEntitlements(from: local)
        XCTAssertEqual(local.accessPolicy, .freeAllFeatures)
        XCTAssertTrue(local.includes(.forums))
        XCTAssertEqual(hosted.subscription, billing)
        XCTAssertEqual(hosted.accessPolicy, .betaBasic)
        XCTAssertFalse(hosted.includes(.forums))
        phase.canUseHostedAccountFeatures = true
        XCTAssertEqual(phase.forumEntitlements(from: local), local)
    }

    func testFixedFreeAndHistoricalStagingPresentationKeepCompileTimeSemantics() {
        let fixed = IChartPlanAccessPresentation.fixed(.betaBasic)
        XCTAssertEqual(fixed.isFreeBeta, IChartProductAccessPolicy.current.isFreeBeta)
        XCTAssertEqual(fixed.canOfferPaidPurchases, IChartProductAccessPolicy.current.offersPaidPurchases)
        XCTAssertFalse(fixed.isAccessChecking)
        XCTAssertTrue(fixed.canUseHostedAccountFeatures)
    }

    func testForumAuthTransitionCannotBorrowPreviousOwnersFreshGrant() async {
        let fixture = Fixture(status: status(.freeBeta, revision: 1, participating: true))
        defer { fixture.clean() }
        fixture.beta.authStateChanged(ownerID: owner)
        await fixture.beta.refresh()
        let local = AppEntitlements(subscription: .activePro(), accessPolicy: .freeAllFeatures)
        let nextOwner = UUID(uuidString: "99999999-2222-4222-8222-999999999999")!
        let valid = IChartPlanAccessPresentation.forumEntitlements(from: local,
            store: fixture.beta, signedInOwnerID: owner)
        XCTAssertTrue(valid.includes(.forums))
        for currentOwner in [Optional(nextOwner), nil] {
            let guarded = IChartPlanAccessPresentation.forumEntitlements(from: local,
                store: fixture.beta, signedInOwnerID: currentOwner)
            XCTAssertFalse(guarded.includes(.forums))
            XCTAssertEqual(guarded.accessPolicy, .betaBasic)
            XCTAssertEqual(guarded.subscription, local.subscription)
        }
        XCTAssertEqual(local.accessPolicy, .freeAllFeatures, "Only hosted request permissions are narrowed")
        XCTAssertEqual(fixture.beta.ownerID, owner, "The guard never becomes a second account-policy writer")
    }

    func testMountedUpgradeRemovesSeededPricesOnRollbackWithoutReplacingExistingView() async throws {
        let fixture = Fixture(status: status(.paid, revision: 1, participating: true))
        defer { fixture.clean() }
        fixture.beta.authStateChanged(ownerID: owner)
        await fixture.beta.refresh()
        let subscriptions = IChartStoreKitSubscriptionStore(productAccessStore: fixture.beta,
            initialProductOptions: [
                .init(id: IChartStoreKitProductCatalog.proMonthlyProductID, displayName: "Monthly fixture",
                    description: "Injected Apple-formatted metadata", displayPrice: "$6.99", valueBadge: nil),
                .init(id: IChartStoreKitProductCatalog.proAnnualProductID, displayName: "Annual fixture",
                    description: "Injected Apple-formatted metadata", displayPrice: "$60.00", valueBadge: "Save 28%")
            ])
        let library = ChartLibraryStore(charts: [],
            entitlements: AppEntitlements(subscription: .basic, accessPolicy: .paidSubscription))
        let lifetime = Lifetime()
        let host = UIHostingController(rootView: UpgradeSheetView(feature: .projects)
            .environmentObject(library).environmentObject(subscriptions)
            .environment(\.betaProStore, fixture.beta).environment(\.accessibilityEnabled, true)
            .onAppear { lifetime.appearances += 1 }.onDisappear { lifetime.disappearances += 1 })
        let window = try mount(host)
        defer { close(window) }
        // Finish the real entry refresh before changing the synthetic server
        // phase; a coalesced older read is not a rollback UI regression.
        await Task.yield()
        await fixture.beta.refresh()
        try await eventually(in: window) {
            $0.contains("$6.99") && $0.contains("$60.00") && !$0.contains("Advance beta notice")
        }
        let originalController = window.rootViewController

        fixture.service.current = status(.freeBeta, revision: 2, participating: false)
        await fixture.beta.refresh()
        library.applyAccessPolicy(fixture.beta.resolvedAccessPolicy) // App is the production writer.
        // Deliberately keep stale display metadata: the mounted UI must hide
        // it from the shared phase itself, independently of App's cleanup.
        try await eventually(in: window) {
            $0.contains("Rejoin Pro — Free") && $0.contains("Restore Purchases")
                && $0.contains("Manage Subscription") && $0.contains("Advance beta notice")
                && !$0.contains("$6.99") && !$0.contains("$60.00")
        }
        XCTAssertTrue(window.rootViewController === originalController)
        XCTAssertEqual(lifetime.appearances, 1)
        XCTAssertEqual(lifetime.disappearances, 0)
        XCTAssertEqual(subscriptions.productOptions.count, 2)
        XCTAssertEqual(library.entitlements.accessPolicy, .betaBasic)
    }

    func testMountedSettingsTracksPhaseWhenFreeAccessBooleanStaysFalseAndPreservesOptOut() async throws {
        let fixture = Fixture(status: status(.freeBeta, revision: 1, participating: false))
        defer { fixture.clean() }
        fixture.beta.authStateChanged(ownerID: owner)
        await fixture.beta.refresh()
        let billing = IChartSubscriptionEntitlement.activePro(willAutoRenew: false)
        let library = ChartLibraryStore(charts: (1...4).map { Chart.blank(title: "Retained \($0)") },
            entitlements: AppEntitlements(subscription: billing, accessPolicy: .betaBasic))
        let originalCharts = library.charts
        let subscriptions = IChartStoreKitSubscriptionStore(entitlement: billing, productAccessStore: fixture.beta)
        let forum = IChartForumStore.live(clients: nil)
        let host = UIHostingController(rootView:
            ScrollView {
                IChartPlanAccessReader(fallbackPolicy: library.entitlements.accessPolicy) { _ in
                    IChartPlanSettings(store: library, subscriptionStore: subscriptions, forumStore: forum,
                        theme: IChartHomeTheme(mode: .light), onSelectSubscriptionState: { _ in },
                        onForumQASampleDataChanged: { _ in })
                }
            }
            .environment(\.betaProStore, fixture.beta).environment(\.accessibilityEnabled, true))
        let window = try mount(host)
        defer { close(window) }
        // Finish the real entry refresh before changing the synthetic server
        // phase; a coalesced older read is not a rollback UI regression.
        await Task.yield()
        await fixture.beta.refresh()
        try await eventually(in: window) { $0.contains("Rejoin Pro — Free") }
        XCTAssertFalse(fixture.beta.freeProAccess)

        fixture.service.current = status(.paid, revision: 2, participating: false)
        await fixture.beta.refresh()
        library.applyAccessPolicy(fixture.beta.resolvedAccessPolicy)
        try await eventually(in: window) { $0.contains("Pro Active") && !$0.contains("Rejoin Pro — Free") }
        XCTAssertFalse(fixture.beta.freeProAccess)

        fixture.service.current = status(.freeBeta, revision: 3, participating: false)
        await fixture.beta.refresh()
        library.applyAccessPolicy(fixture.beta.resolvedAccessPolicy)
        try await eventually(in: window) { $0.contains("Rejoin Pro — Free") && $0.contains("Manage My Subscription") }
        XCTAssertFalse(fixture.beta.freeProAccess)
        XCTAssertEqual(library.entitlements.accessPolicy, .betaBasic)
        XCTAssertEqual(library.entitlements.subscription, billing)
        XCTAssertEqual(library.charts, originalCharts)
    }

    func testMountedUnknownUpgradeKeepsRecoveryAndDoesNotShowBetaNoticeOrCheckout() async throws {
        let fixture = Fixture(status: status(.freeBeta, revision: 1, participating: true))
        defer { fixture.clean() }
        fixture.beta.authStateChanged(ownerID: owner)
        fixture.service.failReads = true
        await fixture.beta.refresh()
        let library = ChartLibraryStore(charts: [], entitlements: AppEntitlements(subscription: .unavailable,
            accessPolicy: fixture.beta.resolvedAccessPolicy))
        let subscriptions = IChartStoreKitSubscriptionStore(entitlement: .unavailable, productAccessStore: fixture.beta)
        let host = UIHostingController(rootView: UpgradeSheetView(feature: .projects)
            .environmentObject(library).environmentObject(subscriptions)
            .environment(\.betaProStore, fixture.beta).environment(\.accessibilityEnabled, true))
        let window = try mount(host)
        defer { close(window) }
        try await eventually(in: window) {
            $0.contains("Checking Plan Access") && $0.contains("Retry Access Check")
                && $0.contains("Restore Purchases") && $0.contains("Manage Subscription")
                && !$0.contains("Unlock Pro") && !$0.contains("Rejoin Pro — Free")
                && !$0.contains("Advance beta notice")
        }
    }

    func testCoordinatedNoticeDoesNotPresentAModalOrMoveTheWritingSurface() async throws {
        let fixture = Fixture(status: status(.freeBeta, revision: 1, participating: true))
        defer { fixture.clean() }
        fixture.beta.authStateChanged(ownerID: owner)
        await fixture.beta.refresh()
        let host = UIHostingController(rootView: Text("Saved writing remains available")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(IChartBetaProNoticePresenter(store: fixture.beta))
            .environment(\.accessibilityEnabled, true))
        let window = try mount(host)
        defer { close(window) }
        try await eventually(in: window) { $0.contains("Saved writing remains available") }
        let originalFrame = host.view.frame
        XCTAssertNil(host.presentedViewController)
        fixture.service.current = status(.paid, revision: 2, participating: true)
        await fixture.beta.refresh()
        try await eventually(in: window) { $0.contains("Saved writing remains available") }
        XCTAssertNil(host.presentedViewController)
        XCTAssertEqual(host.view.frame, originalFrame)
        XCTAssertNotNil(fixture.beta.pendingNotice, "Notices are retained for the relevant Plan surface, never auto-shown over writing")
    }

    private func presentation(_ policy: IChartProductAccessPolicy) -> IChartPlanAccessPresentation {
        .init(accessPolicy: policy, isAccessChecking: false,
              canOfferPaidPurchases: policy == .paidSubscription, accessStatusMessage: nil)
    }

    private func status(_ phase: IChartProductAccessPhase, revision: Int64,
                        participating: Bool) -> IChartProductAccessStatus {
        let now = Date(timeIntervalSince1970: 1_800_000_000 + Double(revision))
        return .init(ownerID: owner, policyID: IChartProductAccessStatus.expectedPolicyID,
            phase: phase, policyRevision: revision, serverNow: now, policyUpdatedAt: now,
            betaAvailable: phase == .freeBeta, eligible: true, participating: participating,
            freeProAccess: phase == .freeBeta && participating,
            noticeID: "advance-notice", noticeTitle: "Advance beta notice",
            noticeBody: "The planned beta date is approaching.")
    }

    private func mount<Content: View>(_ host: UIHostingController<Content>) throws -> PresentationWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = PresentationWindow(windowScene: scene)
        window.previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func close(_ window: PresentationWindow) {
        window.rootViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        window.previousKeyWindow?.makeKeyAndVisible()
    }

    private func eventually(in window: UIWindow, _ condition: (String) -> Bool,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<80 {
            window.layoutIfNeeded()
            let labels = try NativeAccessibilityLookup.nodes(in: window)
                .compactMap { $0.element.accessibilityLabel }.joined(separator: "\n")
            if condition(labels) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Mounted plan content did not converge to the expected runtime phase", file: file, line: line)
    }

    private final class Lifetime { var appearances = 0; var disappearances = 0 }
    private final class PresentationWindow: UIWindow { weak var previousKeyWindow: UIWindow? }

    @MainActor
    private final class Fixture {
        let suite: String
        let defaults: UserDefaults
        let service: PhaseService
        let beta: IChartBetaProStore
        init(status: IChartProductAccessStatus) {
            let name = "CoordinatedPlanPresentationTests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: name)!
            preferences.removePersistentDomain(forName: name)
            let provider = PhaseService(status: status)
            suite = name
            defaults = preferences
            service = provider
            beta = IChartBetaProStore(service: provider, defaults: preferences, isCoordinatedActivation: true)
        }
        func clean() { defaults.removePersistentDomain(forName: suite) }
    }

    @MainActor
    private final class PhaseService: IChartBetaProService {
        var current: IChartProductAccessStatus
        var failReads = false
        init(status: IChartProductAccessStatus) { current = status }
        func fetchStatus(for ownerID: UUID) async throws -> IChartBetaProStatus {
            try await fetchProductAccessStatus(for: ownerID).betaStatus
        }
        func fetchProductAccessStatus(for ownerID: UUID) async throws -> IChartProductAccessStatus {
            guard !failReads, current.ownerID == ownerID else { throw IChartBetaProServiceError.accountChanged }
            return current
        }
        func setParticipation(_ participating: Bool, for ownerID: UUID) async throws -> IChartBetaProStatus {
            throw IChartBetaProServiceError.participationNotConfirmed
        }
    }
}
#endif
