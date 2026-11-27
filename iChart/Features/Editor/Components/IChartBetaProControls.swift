import SwiftUI

// Optional so standalone previews and existing editor hosts do not require an
// unrelated account object. Production injects the live account-scoped store.
private struct IChartBetaProStoreKey: EnvironmentKey {
    static let defaultValue: IChartBetaProStore? = nil
}

private struct IChartBetaProRetryActionKey: EnvironmentKey {
    static let defaultValue: (@MainActor () async -> Void)? = nil
}

extension EnvironmentValues {
    var betaProStore: IChartBetaProStore? {
        get { self[IChartBetaProStoreKey.self] }
        set { self[IChartBetaProStoreKey.self] = newValue }
    }

    var betaProRetryAction: (@MainActor () async -> Void)? {
        get { self[IChartBetaProRetryActionKey.self] }
        set { self[IChartBetaProRetryActionKey.self] = newValue }
    }
}

/// Presentation uses the same resolved account policy as the library. Billing
/// history remains independent; an unavailable phase is not an expired plan.
struct IChartPlanAccessPresentation: Equatable {
    let accessPolicy: IChartProductAccessPolicy
    let isAccessChecking: Bool
    let canOfferPaidPurchases: Bool
    let accessStatusMessage: String?
    var betaPresentationOverride: Bool? = nil
    var canUseHostedAccountFeatures = true

    static func fixed(_ policy: IChartProductAccessPolicy) -> Self {
        Self(accessPolicy: policy, isAccessChecking: false,
             canOfferPaidPurchases: IChartProductAccessPolicy.current.offersPaidPurchases,
             accessStatusMessage: nil, betaPresentationOverride: IChartProductAccessPolicy.current.isFreeBeta)
    }

    @MainActor
    static func resolved(store: IChartBetaProStore, fallbackPolicy: IChartProductAccessPolicy) -> Self {
        guard store.isCoordinatedActivation else { return .fixed(fallbackPolicy) }
        return Self(accessPolicy: store.resolvedAccessPolicy,
                    isAccessChecking: store.isAccessChecking,
                    canOfferPaidPurchases: store.canOfferPaidPurchases,
                    accessStatusMessage: store.accessStatusMessage,
                    canUseHostedAccountFeatures: store.hasFreshProductAccess
                        && store.productAccessStatus?.eligible == true)
    }

    var isFreeBeta: Bool { betaPresentationOverride ?? accessPolicy.isFreeBeta }
    var showsBetaControls: Bool { isFreeBeta && !isAccessChecking }
    var showsPaidPlans: Bool { !isFreeBeta && !isAccessChecking && canOfferPaidPurchases }
    var checkingMessage: String {
        accessStatusMessage ?? "Plan access is being checked. Your saved charts, PDFs and setlists remain available. Reconnect and try again."
    }
    func forumEntitlements(from local: AppEntitlements) -> AppEntitlements {
        guard !canUseHostedAccountFeatures else { return local }
        return AppEntitlements(subscription: local.subscription, accessPolicy: .betaBasic)
    }

    @MainActor
    static func forumEntitlements(from local: AppEntitlements, store: IChartBetaProStore,
                                  signedInOwnerID: UUID?) -> AppEntitlements {
        guard store.isCoordinatedActivation else { return local }
        guard let signedInOwnerID, store.ownerID == signedInOwnerID,
              store.productAccessStatus?.ownerID == signedInOwnerID else {
            return AppEntitlements(subscription: local.subscription, accessPolicy: .betaBasic)
        }
        return resolved(store: store, fallbackPolicy: local.accessPolicy).forumEntitlements(from: local)
    }
    var projectReadOnlyMessage: String {
        if isAccessChecking {
            return "Plan access is being checked. Open any saved chart to edit or export it. Use Retry Access Check in Settings to refresh Project organization."
        }
        return isFreeBeta
            ? "Your Projects are read-only on Basic. Open any chart to edit or export it. Rejoin free Pro in Settings to manage Projects and variants."
            : "Your Projects are read-only on Basic. Open any chart to edit or export it. Pro lets you manage Projects and variants."
    }
    var projectCreationMessage: String {
        if isAccessChecking { return projectReadOnlyMessage }
        return isFreeBeta
            ? "Rejoin free Pro in Settings to use Projects. Your existing projects and charts are kept."
            : "Pro lets you group charts for the same song and manage variants. Every saved chart stays editable on Basic."
    }
    var forumRecoveryMessage: String {
        if isAccessChecking {
            return "Plan access is being checked. Open Plan Settings and use Retry Access Check. Your saved PDFs and queued charts are kept."
        }
        return isFreeBeta
            ? "Choose Open Plan Settings, then Rejoin Pro — Free to browse and share community charts. Your saved PDFs and queued charts are kept."
            : "Open Plan Settings to check your Pro access. A verified account can still browse and read; your saved PDFs and queued charts are kept."
    }
}

private struct IChartPlanAccessPresentationKey: EnvironmentKey {
    static let defaultValue: IChartPlanAccessPresentation? = nil
}

extension EnvironmentValues {
    var planAccessPresentation: IChartPlanAccessPresentation? {
        get { self[IChartPlanAccessPresentationKey.self] }
        set { self[IChartPlanAccessPresentationKey.self] = newValue }
    }
}

/// Reading an optional Environment store alone does not observe its changes.
/// This child observes the actual injected instance, preserving the content's
/// identity and local state while phase, revision or membership changes.
struct IChartPlanAccessReader<Content: View>: View {
    @Environment(\.betaProStore) private var betaProStore
    let fallbackPolicy: IChartProductAccessPolicy
    let content: (IChartPlanAccessPresentation) -> Content

    init(fallbackPolicy: IChartProductAccessPolicy,
         @ViewBuilder content: @escaping (IChartPlanAccessPresentation) -> Content) {
        self.fallbackPolicy = fallbackPolicy
        self.content = content
    }

    var body: some View {
        if let betaProStore {
            IChartObservedPlanAccess(store: betaProStore, fallbackPolicy: fallbackPolicy, content: content)
        } else {
            let presentation = IChartPlanAccessPresentation.fixed(fallbackPolicy)
            content(presentation).environment(\.planAccessPresentation, presentation)
        }
    }
}

private struct IChartObservedPlanAccess<Content: View>: View {
    @ObservedObject var store: IChartBetaProStore
    let fallbackPolicy: IChartProductAccessPolicy
    let content: (IChartPlanAccessPresentation) -> Content

    var body: some View {
        let presentation = IChartPlanAccessPresentation.resolved(store: store, fallbackPolicy: fallbackPolicy)
        content(presentation).environment(\.planAccessPresentation, presentation)
    }
}

struct IChartPlanAccessCheckView: View {
    @Environment(\.betaProStore) private var betaProStore
    @Environment(\.betaProRetryAction) private var retryAction
    let presentation: IChartPlanAccessPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checking Plan Access").font(.headline)
            Text(presentation.checkingMessage)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry Access Check") {
                Task {
                    if let retryAction { await retryAction() }
                    else { await betaProStore?.refresh() }
                }
            }
            .buttonStyle(.bordered)
            .disabled(betaProStore?.isWorking == true)
            .accessibilityIdentifier("plan_access_retry")
        }
        .accessibilityIdentifier("plan_access_checking")
    }
}

struct IChartBetaProControls: View {
    @Environment(\.betaProRetryAction) private var retryAction
    @ObservedObject var store: IChartBetaProStore
    var allowsLeaving = true
    var didJoin: () -> Void = {}
    @State private var confirmingLeave = false
    @State private var leaveOwnerID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isCoordinatedActivation && store.isAccessChecking {
                IChartPlanAccessCheckView(presentation: .resolved(store: store, fallbackPolicy: store.resolvedAccessPolicy))
            } else if store.isCoordinatedActivation && !store.resolvedAccessPolicy.isFreeBeta {
                Text("Paid plans are active. Use Restore Purchases or Manage Subscription for existing Apple billing. Your saved work is kept.")
                    .font(.footnote)
            } else if store.ownerID == nil {
                Text("Sign in to your verified iChart account to use free Pro.")
                    .font(.footnote)
            } else if store.status?.betaAvailable == false {
                Text("Free Pro access is currently unavailable. Your saved work is kept.")
                    .font(.footnote)
            } else if store.freeProAccess {
                if allowsLeaving {
                    Button("Leave Pro — Use Basic") {
                        leaveOwnerID = store.ownerID
                        confirmingLeave = true
                    }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("beta_pro_leave")
                        .disabled(store.isWorking)
                }
            } else {
                Button("Rejoin Pro — Free") {
                    guard let owner = store.ownerID else { return }
                    Task {
                        if await store.setParticipating(true, for: owner), store.freeProAccess { didJoin() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("beta_pro_rejoin")
                .disabled(store.isWorking)
            }

            if store.isWorking {
                ProgressView("Updating free Pro settings…")
                    .font(.footnote)
            }
            if let error = store.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("beta_pro_error")
                Button("Try Again") {
                    Task {
                        if let retryAction { await retryAction() }
                        else { await store.refresh() }
                    }
                }
                    .buttonStyle(.bordered)
                    .disabled(store.isWorking)
            }
        }
        .onChange(of: store.ownerID) { _, _ in
            confirmingLeave = false
            leaveOwnerID = nil
        }
        .onChange(of: store.resolvedAccessPolicy) { _, _ in
            if store.isCoordinatedActivation && (!store.resolvedAccessPolicy.isFreeBeta || store.isAccessChecking) {
                confirmingLeave = false
                leaveOwnerID = nil
            }
        }
        .onChange(of: store.isAccessChecking) { _, checking in
            if store.isCoordinatedActivation && checking {
                confirmingLeave = false
                leaveOwnerID = nil
            }
        }
        .confirmationDialog("Use Basic instead of free Pro?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Use Basic") {
                guard let owner = leaveOwnerID else { return }
                Task { await store.setParticipating(false, for: owner) }
            }
            Button("Keep Free Pro", role: .cancel) {}
        } message: {
            Text("Basic can create up to 3 local charts and does not include Projects, cloud backup or Forums. Your existing work stays on this iPad and remains editable. Rejoin free Pro at any time in Settings. This does not cancel Apple billing.")
        }
    }
}

/// Coordinated notices live in Plan surfaces. They never interrupt writing or
/// move its canvas. Fixed-free clients retain their existing notice behavior.
struct IChartBetaProNoticePresenter: ViewModifier {
    @ObservedObject var store: IChartBetaProStore

    @ViewBuilder
    func body(content: Content) -> some View {
        if store.isCoordinatedActivation {
            content
        } else {
            content.alert(store.pendingNotice?.title ?? "Pro Access Update", isPresented: Binding(
                get: { store.pendingNotice != nil }, set: { _ in }
            ), presenting: store.pendingNotice) { notice in
                Button("Got It") { store.acknowledgeNotice(notice.id, for: notice.ownerID) }
            } message: { notice in
                Text(notice.body + "\n\nYou can choose Basic in Settings. " + IChartLegalLinks.futurePricingNotice)
            }
        }
    }
}

struct IChartCoordinatedAccessNoticeView: View {
    @ObservedObject var store: IChartBetaProStore

    var body: some View {
        if store.isCoordinatedActivation, !store.isAccessChecking,
           store.productAccessStatus?.phase == .freeBeta, let notice = store.pendingNotice {
            VStack(alignment: .leading, spacing: 8) {
                Text(notice.title).font(.headline)
                Text(notice.body).font(.footnote).fixedSize(horizontal: false, vertical: true)
                Button("Got It") { store.acknowledgeNotice(notice.id, for: notice.ownerID) }
                    .buttonStyle(.bordered)
            }
            .accessibilityIdentifier("product_access_notice")
        }
    }
}
