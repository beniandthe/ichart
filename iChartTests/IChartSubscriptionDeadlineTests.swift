#if canImport(UIKit)
import Combine
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class IChartSubscriptionDeadlineTests: XCTestCase {
    func testKnownDeadlinePublishesBeforeRefreshWithoutNavigation() async throws {
        let fixture = await Fixture.make()
        defer { fixture.clean() }
        let deadline = fixture.clock.now.addingTimeInterval(60)
        let store = fixture.store(.activePro(accessEndsAt: deadline, willAutoRenew: false))
        let request = try await fixture.sleep.nextRequest()
        XCTAssertEqual(request.nanoseconds, 60_000_000_000)
        XCTAssertEqual(store.entitlement.status, .proActive)
        XCTAssertEqual(fixture.refreshCount, 0)

        fixture.clock.now = deadline
        await fixture.sleep.release(request.id)
        try await eventually { fixture.refreshCount == 1 }
        XCTAssertEqual(store.entitlement.status, .proExpired)
        XCTAssertEqual(fixture.stateWhenRefreshStarted, .proExpired)
        XCTAssertEqual(store.entitlement.accessEndsAt, deadline)
        XCTAssertEqual(store.entitlement.willAutoRenew, false)
        XCTAssertEqual(store.billingObservationOwnerID, fixture.owner)
    }

    func testRenewalCancelsThePriorDeadlineAndUsesTheNewBound() async throws {
        let fixture = await Fixture.make()
        defer { fixture.clean() }
        let firstDeadline = fixture.clock.now.addingTimeInterval(60)
        let store = fixture.store(.activePro(accessEndsAt: firstDeadline))
        let first = try await fixture.sleep.nextRequest()
        let renewedDeadline = fixture.clock.now.addingTimeInterval(600)
        store.applyBillingObservation(.activePro(accessEndsAt: renewedDeadline),
            verifiedOwnerID: fixture.owner, observationOwnerID: fixture.owner)
        let second = try await fixture.sleep.nextRequest(after: first.id)

        fixture.clock.now = firstDeadline
        await fixture.sleep.release(first.id)
        await Task.yield()
        XCTAssertEqual(store.entitlement.status, .proActive)
        XCTAssertEqual(store.entitlement.accessEndsAt, renewedDeadline)
        XCTAssertEqual(fixture.refreshCount, 0)

        fixture.clock.now = renewedDeadline
        await fixture.sleep.release(second.id)
        try await eventually { fixture.refreshCount == 1 }
        XCTAssertEqual(store.entitlement.status, .proExpired)
    }

    func testPreviousOwnersDeadlineCannotPublishIntoTheNewAccount() async throws {
        let fixture = await Fixture.make()
        defer { fixture.clean() }
        let deadline = fixture.clock.now.addingTimeInterval(60)
        let store = fixture.store(.activePro(accessEndsAt: deadline))
        let request = try await fixture.sleep.nextRequest()
        let nextOwner = UUID(uuidString: "99999999-2222-4222-8222-999999999999")!
        fixture.beta.authStateChanged(ownerID: nextOwner)
        fixture.clock.now = deadline
        await fixture.sleep.release(request.id)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(fixture.refreshCount, 0)
        XCTAssertEqual(store.billingObservationOwnerID, fixture.owner)
        let guarded = store.entitlementForLibrary(ownerID: nextOwner, currentLibraryEntitlement: .basic)
        XCTAssertEqual(guarded.status, .unavailable)

        let nextDeadline = fixture.clock.now.addingTimeInterval(600)
        store.applyBillingObservation(.activePro(accessEndsAt: nextDeadline),
            verifiedOwnerID: nextOwner, observationOwnerID: nextOwner)
        XCTAssertEqual(store.entitlement.status, .proActive)
        XCTAssertEqual(store.entitlement.accessEndsAt, nextDeadline)
        XCTAssertEqual(store.billingObservationOwnerID, nextOwner)
    }

    func testDelayedObservationCannotRegrantAnEndedPeriod() async {
        let fixture = await Fixture.make()
        defer { fixture.clean() }
        let deadline = fixture.clock.now.addingTimeInterval(60)
        let observedBeforeAwait = IChartSubscriptionEntitlement.activePro(
            accessEndsAt: deadline, willAutoRenew: false, verifiedAt: fixture.clock.now)
        let store = fixture.store(.basic)
        fixture.clock.now = deadline.addingTimeInterval(1)
        store.applyBillingObservation(observedBeforeAwait,
            verifiedOwnerID: fixture.owner, observationOwnerID: fixture.owner)
        XCTAssertEqual(store.entitlement.status, .proExpired)
        XCTAssertEqual(store.entitlement.accessEndsAt, deadline)
        XCTAssertEqual(store.entitlement.lastVerifiedAt, observedBeforeAwait.lastVerifiedAt)
        XCTAssertEqual(fixture.refreshCount, 0)
    }

    func testDeadlineWaitDoesNotRetainTheSubscriptionStore() async throws {
        let fixture = await Fixture.make()
        defer { fixture.clean() }
        var store: IChartStoreKitSubscriptionStore? = fixture.store(
            .activePro(accessEndsAt: fixture.clock.now.addingTimeInterval(60)))
        let request = try await fixture.sleep.nextRequest()
        let weakStore = WeakSubscriptionStore(store)
        store = nil
        XCTAssertNil(weakStore.value)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
        await fixture.sleep.release(request.id)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(fixture.refreshCount, 0)
    }

    func testMountedPlanExpiresAndSavedLibraryRemainsEditableWithoutReplacingTheView() async throws {
        let fixture = await Fixture.make()
        defer { fixture.clean() }
        let deadline = fixture.clock.now.addingTimeInterval(60)
        let billing = IChartSubscriptionEntitlement.activePro(accessEndsAt: deadline, willAutoRenew: false)
        let subscriptions = fixture.store(billing)
        var chart = Chart.blank(title: "Saved chart with opaque ink")
        chart.pageHandwrittenNotationData = Data([1, 4, 9, 16])
        let charts = [chart] + (2...4).map { Chart.blank(title: "Saved \($0)") }
        let library = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(subscription: billing, accessPolicy: .paidSubscription))
        let projectID = try XCTUnwrap(library.createProject(title: "Saved project", chartIDs: [chart.id]))
        let project = try XCTUnwrap(library.projects.first { $0.id == projectID })
        let originalProjects = library.projects
        let originalCharts = library.charts
        library.selectedChartID = chart.id
        let lifetime = Lifetime()
        let forum = IChartForumStore.live(clients: nil)
        let host = UIHostingController(rootView:
            ScrollView {
                IChartPlanSettings(store: library, subscriptionStore: subscriptions, forumStore: forum,
                    theme: IChartHomeTheme(mode: .light), onSelectSubscriptionState: { _ in },
                    onForumQASampleDataChanged: { _ in })
            }
            .environment(\.betaProStore, fixture.beta).environment(\.accessibilityEnabled, true)
            .onReceive(subscriptions.$entitlement) { observed in
                library.applySubscriptionState(IChartProductAccessResolver.billingForLibrary(
                    subscription: observed, verifiedOwnerID: subscriptions.billingObservationOwnerID,
                    currentOwnerID: fixture.beta.ownerID, currentLibraryEntitlement: library.entitlements.subscription))
            }
            .onAppear { lifetime.appearances += 1 }.onDisappear { lifetime.disappearances += 1 })
        let window = try mount(host)
        defer { close(window) }
        try await eventually(in: window) { $0.contains("Pro Active") }
        let originalController = window.rootViewController
        let request = try await fixture.sleep.nextRequest()
        fixture.clock.now = deadline
        await fixture.sleep.release(request.id)
        try await eventually(in: window) { $0.contains("Pro Expired") && $0.contains("Restore Pro") }

        XCTAssertTrue(window.rootViewController === originalController)
        XCTAssertEqual(lifetime.appearances, 1)
        XCTAssertEqual(lifetime.disappearances, 0)
        XCTAssertEqual(library.localChartLimit, 3)
        XCTAssertFalse(library.canCreateChart)
        XCTAssertFalse(library.canUse(.cloudBackup))
        XCTAssertFalse(library.canUse(.projects))
        XCTAssertEqual(library.projects, originalProjects)
        XCTAssertEqual(library.projects.first { $0.id == projectID }, project)
        XCTAssertEqual(library.charts, originalCharts)
        XCTAssertEqual(library.selectedChartID, chart.id)
        let binding = try XCTUnwrap(library.editorBinding(for: chart.id))
        var edited = binding.wrappedValue
        edited.title = "Editing still works after expiry"
        binding.wrappedValue = edited
        XCTAssertEqual(library.charts.first?.pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
        XCTAssertEqual(library.charts.first?.title, edited.title)
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Deadline publication did not finish after the controlled wake")
    }

    private func eventually(in window: UIWindow, _ condition: (String) -> Bool) async throws {
        for _ in 0..<80 {
            window.layoutIfNeeded()
            let labels = try NativeAccessibilityLookup.nodes(in: window)
                .compactMap { $0.element.accessibilityLabel }.joined(separator: "\n")
            if condition(labels) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Mounted plan did not converge after the controlled deadline")
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
    private final class Lifetime { var appearances = 0; var disappearances = 0 }
    private final class WeakSubscriptionStore {
        weak var value: IChartStoreKitSubscriptionStore?
        init(_ value: IChartStoreKitSubscriptionStore?) { self.value = value }
    }
    private final class PresentationWindow: UIWindow { weak var previousKeyWindow: UIWindow? }

    @MainActor
    private final class Clock { var now = Date().addingTimeInterval(3_600) }

    @MainActor
    private final class Fixture {
        let owner = UUID(uuidString: "88888888-1111-4111-8111-888888888888")!
        let suite = "IChartSubscriptionDeadlineTests.\(UUID().uuidString)"
        let clock = Clock()
        let sleep = ControlledSleep()
        let beta: IChartBetaProStore
        let defaults: UserDefaults
        var refreshCount = 0
        var stateWhenRefreshStarted: IChartSubscriptionStatus?
        weak var observedStore: IChartStoreKitSubscriptionStore?
        private init() {
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            beta = IChartBetaProStore(service: PhaseService(owner: owner), defaults: defaults,
                isCoordinatedActivation: true)
        }
        static func make() async -> Fixture {
            let value = Fixture()
            value.beta.authStateChanged(ownerID: value.owner)
            await value.beta.refresh()
            return value
        }
        func store(_ entitlement: IChartSubscriptionEntitlement) -> IChartStoreKitSubscriptionStore {
            let sleep = sleep
            let store = IChartStoreKitSubscriptionStore(entitlement: entitlement, productAccessStore: beta,
                verifiedOwnerID: owner, observationOwnerID: owner,
                entitlementNow: { [clock] in clock.now },
                entitlementSleep: { try await sleep.wait(nanoseconds: $0) },
                expiredEntitlementRefresh: { [weak self] in
                    self?.refreshCount += 1
                    self?.stateWhenRefreshStarted = self?.observedStore?.entitlement.status
                })
            observedStore = store
            return store
        }
        func clean() { defaults.removePersistentDomain(forName: suite) }
    }

    @MainActor
    private final class PhaseService: IChartBetaProService {
        let owner: UUID
        init(owner: UUID) { self.owner = owner }
        func fetchStatus(for ownerID: UUID) async throws -> IChartBetaProStatus {
            try await fetchProductAccessStatus(for: ownerID).betaStatus
        }
        func fetchProductAccessStatus(for ownerID: UUID) async throws -> IChartProductAccessStatus {
            guard ownerID == owner else { throw IChartBetaProServiceError.accountChanged }
            let now = Date()
            return .init(ownerID: owner, policyID: IChartProductAccessStatus.expectedPolicyID,
                phase: .paid, policyRevision: 2, serverNow: now, policyUpdatedAt: now,
                betaAvailable: false, eligible: true, participating: true, freeProAccess: false)
        }
        func setParticipation(_ participating: Bool, for ownerID: UUID) async throws -> IChartBetaProStatus {
            throw IChartBetaProServiceError.participationNotConfirmed
        }
    }

    private actor ControlledSleep {
        struct Request: Sendable { let id: UUID; let nanoseconds: UInt64 }
        private var requests: [Request] = []
        private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]
        func wait(nanoseconds: UInt64) async throws {
            let id = UUID()
            requests.append(.init(id: id, nanoseconds: nanoseconds))
            try await withTaskCancellationHandler(operation: { () async throws -> Void in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                    else { continuations[id] = continuation }
                }
            }, onCancel: {
                Task { await self.cancel(id) }
            })
        }
        func release(_ id: UUID) { continuations.removeValue(forKey: id)?.resume() }
        private func cancel(_ id: UUID) { continuations.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        func nextRequest(after previous: UUID? = nil) async throws -> Request {
            for _ in 0..<200 {
                if let request = requests.first(where: { value in
                    guard let previous, let index = requests.firstIndex(where: { $0.id == previous }),
                          let candidate = requests.firstIndex(where: { $0.id == value.id }) else { return previous == nil }
                    return candidate > index
                }) { return request }
                await Task.yield()
            }
            throw NSError(domain: "IChartSubscriptionDeadlineTests", code: 1)
        }
    }
}
#endif
