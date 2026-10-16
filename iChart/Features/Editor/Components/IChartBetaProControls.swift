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

struct IChartBetaProControls: View {
    @Environment(\.betaProRetryAction) private var retryAction
    @ObservedObject var store: IChartBetaProStore
    var allowsLeaving = true
    var didJoin: () -> Void = {}
    @State private var confirmingLeave = false
    @State private var leaveOwnerID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.ownerID == nil {
                Text("Sign in to your verified iChart account to use free Pro during beta.")
                    .font(.footnote)
            } else if store.status?.betaAvailable == false {
                Text("Free Pro beta access is currently unavailable. Your saved work is kept.")
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
                Button("Rejoin Pro — Free During Beta") {
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
        .confirmationDialog("Use Basic instead of free Pro?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Use Basic") {
                guard let owner = leaveOwnerID else { return }
                Task { await store.setParticipating(false, for: owner) }
            }
            Button("Keep Free Pro", role: .cancel) {}
        } message: {
            Text("Basic can create up to 3 local charts and does not include Projects, cloud backup or Forums. Your existing work stays on this iPad and remains editable. Rejoin Pro free during beta whenever you want. This does not cancel Apple billing.")
        }
    }
}

/// An administrator must explicitly supply a notice. There is no scheduled end
/// date, paid conversion or push-permission request in this presentation path.
struct IChartBetaProNoticePresenter: ViewModifier {
    @ObservedObject var store: IChartBetaProStore

    func body(content: Content) -> some View {
        content.alert(store.pendingNotice?.title ?? "Pro Beta Update", isPresented: Binding(
            get: { store.pendingNotice != nil },
            set: { _ in }
        ), presenting: store.pendingNotice) { notice in
            Button("Got It") { store.acknowledgeNotice(notice.id, for: notice.ownerID) }
        } message: { notice in
            Text(notice.body + "\n\nYou can choose Basic in Settings. " + IChartLegalLinks.futurePricingNotice)
        }
    }
}
