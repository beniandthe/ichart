import Foundation
import StoreKit
import SwiftUI

struct UpgradeSheetView: View {
    let feature: EntitledFeature

    @EnvironmentObject private var store: ChartLibraryStore
    @EnvironmentObject private var subscriptionStore: IChartStoreKitSubscriptionStore
    @Environment(\.dismiss) private var dismiss

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
            if subscriptionStore.productOptions.isEmpty {
                Text("Pro subscriptions are temporarily unavailable. Try again later or restore an existing purchase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subscriptionStore.productOptions) { product in
                    Button {
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
