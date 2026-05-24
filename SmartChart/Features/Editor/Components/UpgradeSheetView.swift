import SwiftUI

struct UpgradeSheetView: View {
    let feature: EntitledFeature

    @EnvironmentObject private var store: ChartLibraryStore
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
                    benefitRow("PDF export and sharing")
                    benefitRow("Concert, Bb, and Eb views")
                    benefitRow("Font presets, notation tools, and advanced editing")
                }

                #if DEBUG || targetEnvironment(simulator)
                Text("Debug build: this switches local entitlement state until StoreKit is wired.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif

                Spacer()

                VStack(spacing: 12) {
                    #if DEBUG || targetEnvironment(simulator)
                    Button {
                        store.setPlan(.proLifetime)
                        dismiss()
                    } label: {
                        Label("Use Pro Preview", systemImage: "star.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    #endif

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

    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(text)
                .font(.body)
        }
    }
}
