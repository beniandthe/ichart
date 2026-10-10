import Foundation
import StoreKit
import SwiftUI

struct IChartComplimentaryPurchaseFeedback: Equatable {
    let productID: String
    let message: String

    init?(productID: String, completed: Bool, state: IChartStoreKitSubscriptionState) {
        guard !completed,
              case .unavailable(let message) = state,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.productID = productID
        self.message = message
    }

    var accessibilityLabel: String { "Complimentary offer not completed" }
    var retryInstruction: String { "To try again, use the free-month button above." }

    func shouldShowOutsideOffers(productIDs: [String]) -> Bool {
        !productIDs.contains(productID)
    }
}

struct IChartComplimentaryPurchaseFeedbackView: View {
    let feedback: IChartComplimentaryPurchaseFeedback
    let showsRetryHint: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(feedback.message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            if showsRetryHint {
                Text(feedback.retryInstruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedback.accessibilityLabel)
        .accessibilityValue(feedback.message)
        .accessibilityHint(showsRetryHint ? feedback.retryInstruction : "")
        .accessibilityIdentifier("complimentary_purchase_feedback")
    }
}

struct UpgradeSheetView: View {
    let feature: EntitledFeature

    @EnvironmentObject private var store: ChartLibraryStore
    @EnvironmentObject private var subscriptionStore: IChartStoreKitSubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var complimentaryPurchaseFeedback: IChartComplimentaryPurchaseFeedback?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unlock Pro")
                        .font(.largeTitle.weight(.semibold))

                    Text(feature.displayText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(feature.upgradeMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    benefitRow("Unlimited local charts")
                    benefitRow("Projects for song variants")
                    benefitRow("Cloud backup and restore")
                    benefitRow("Forums access")
                }

                storeKitPurchaseControls

                VStack(alignment: .leading, spacing: 2) {
                    Text(IChartLegalLinks.subscriptionNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    IChartLegalLinksView()
                }

                #if DEBUG && targetEnvironment(simulator)
                Text("Pro Preview unlocks Pro locally on this device. Purchases and restore still use the normal subscription flow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif

                Spacer()

                VStack(spacing: 12) {
                    #if DEBUG && targetEnvironment(simulator)
                    Button {
                        store.applySubscriptionState(.activePro(verifiedAt: Date()))
                        dismiss()
                    } label: {
                        Label("Use Pro Preview", systemImage: "star.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    #endif

                    Button {
                        complimentaryPurchaseFeedback = nil
                        Task {
                            await subscriptionStore.restorePurchases()
                            store.applySubscriptionState(subscriptionStore.entitlement)
                            if subscriptionStore.entitlement.status == .proActive {
                                dismiss()
                            }
                        }
                    } label: {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(subscriptionStore.state.isWorking)

                    Button {
                        complimentaryPurchaseFeedback = nil
                        Task {
                            await subscriptionStore.manageSubscriptions()
                            store.applySubscriptionState(subscriptionStore.entitlement)
                            if subscriptionStore.entitlement.status == .proActive {
                                dismiss()
                            }
                        }
                    } label: {
                        Label("Manage Subscription", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(subscriptionStore.state.isWorking)

                    Button("Not Now") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var storeKitPurchaseControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(subscriptionStore.complimentaryOfferStatuses) { status in
                Label(status.detailText, systemImage: "calendar.badge.checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(subscriptionStore.complimentaryOffers) { offer in
                VStack(alignment: .leading, spacing: 8) {
                    Text("One Month Free")
                        .font(.headline)
                    Text("\(offer.productDisplayName) · \(offer.detailText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        complimentaryPurchaseFeedback = nil
                        Task {
                            let completed = await subscriptionStore.purchaseComplimentaryOffer(offer)
                            complimentaryPurchaseFeedback = IChartComplimentaryPurchaseFeedback(
                                productID: offer.productID,
                                completed: completed,
                                state: subscriptionStore.state
                            )
                            store.applySubscriptionState(subscriptionStore.entitlement)
                            if completed, subscriptionStore.entitlement.status == .proActive {
                                dismiss()
                            }
                        }
                    } label: {
                        Label(offer.actionTitle, systemImage: "gift.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(subscriptionStore.state.isWorking)

                    if let complimentaryPurchaseFeedback,
                       complimentaryPurchaseFeedback.productID == offer.productID {
                        IChartComplimentaryPurchaseFeedbackView(
                            feedback: complimentaryPurchaseFeedback,
                            showsRetryHint: true
                        )
                    }
                }
                .padding(12)
                .background(.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let complimentaryPurchaseFeedback,
               complimentaryPurchaseFeedback.shouldShowOutsideOffers(productIDs: subscriptionStore.complimentaryOffers.map(\.productID)) {
                IChartComplimentaryPurchaseFeedbackView(
                    feedback: complimentaryPurchaseFeedback,
                    showsRetryHint: false
                )
                .padding(12)
                .background(.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !subscriptionStore.complimentaryOffers.isEmpty {
                Text("Standard paid plans")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if subscriptionStore.productOptions.isEmpty {
                Text("Pro subscriptions are temporarily unavailable. Try again later or restore an existing purchase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subscriptionStore.productOptions) { product in
                    Button {
                        complimentaryPurchaseFeedback = nil
                        Task {
                            await subscriptionStore.purchase(product)
                            store.applySubscriptionState(subscriptionStore.entitlement)
                            if subscriptionStore.entitlement.status == .proActive {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayName)
                                    .font(.headline)
                                Text(product.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(product.displayPrice)
                                    .font(.headline)

                                if let valueBadge = product.valueBadge {
                                    Text(valueBadge)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(subscriptionStore.state.isWorking)
                }
            }

            if let statusText = subscriptionStore.state.statusText {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(text)
                .font(.body)
        }
    }
}
