#if canImport(UIKit)
import SwiftUI

/// Adds references to existing local PDFs. It never copies, edits or deletes
/// their files, and rechecks access at the moment the user chooses a setlist.
struct AddPDFToSetlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var setlistStore: IChartPDFSetlistStore
    @EnvironmentObject private var pdfStore: IChartPDFLibraryStore
    @EnvironmentObject private var chartStore: ChartLibraryStore
    @AppStorage(IChartAppAppearance.preferenceKey) private var appearanceValue = IChartAppAppearance.light.rawValue
    let pdfItemIDs: [UUID]
    @State private var query = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var nameFocused = false
    @State private var errorMessage: String?

    private var appearance: IChartAppAppearance { IChartAppAppearance(persistedValue: appearanceValue) }
    private var availableItems: [IChartPDFLibraryItem] {
        let visible = pdfStore.visibleItems(for: chartStore.subscriptionState,
            accessPolicy: chartStore.entitlements.accessPolicy)
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        return pdfItemIDs.compactMap { byID[$0] }.filter { pdfStore.exportedPDF(for: $0) != nil }
    }
    private var canAdd: Bool { !pdfItemIDs.isEmpty && availableItems.count == pdfItemIDs.count && setlistStore.loadError == nil }
    private var targets: [IChartPDFSetlist] {
        IChartSetlistSearch.setlists(setlistStore.setlists, query: query, order: .recent)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundStyle(IChartTourStyle.orange)
                            .accessibilityHidden(true)
                        Text("Choose a setlist").font(.headline)
                        Text("Tap a setlist to add \(pdfItemIDs.count == 1 ? "this PDF" : "these PDFs") at the end, or create a new one.")
                            .foregroundStyle(.secondary)
                        Text("The PDFs stay in your library for offline reading.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setlists.destination.guidance")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if let loadError = setlistStore.loadError {
                    Section {
                        Text("Setlists couldn’t be loaded").font(.headline)
                        Text(loadError).font(.footnote).foregroundStyle(.secondary)
                        Button("Try Again") { perform { try setlistStore.reload() } }
                    }
                } else if !canAdd {
                    Section {
                        Label("A PDF is no longer available", systemImage: "exclamationmark.triangle")
                        Text("Close this sheet and choose an available PDF from your library.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup("New Setlist", isExpanded: $creating) {
                            IChartTypedTextField(placeholder: "Setlist name", text: $newName, isFocused: $nameFocused,
                                autocapitalizationType: .words, autocorrectionType: .yes,
                                accessibilityIdentifier: "setlists.destination.name",
                                accessibilityHint: "Tap to type. Use Start Scribble to write with Apple Pencil.")
                                .frame(minHeight: 44)
                            Button("Create & Add PDFs") {
                                perform {
                                    let items = try checkedItems()
                                    _ = try setlistStore.create(name: newName, pdfItems: items)
                                    nameFocused = false
                                    dismiss()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(IChartInterfaceStyle.actionBlue)
                            .disabled(!canAdd || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("setlists.destination.create")
                        }
                        IChartTypedTextField(placeholder: "Search setlists", text: $query,
                            returnKeyType: .search, accessibilityIdentifier: "setlists.destination.search",
                            accessibilityHint: "Tap to type. Use Start Scribble to write with Apple Pencil.")
                            .frame(minHeight: 44)
                    }
                    .background(IChartTypedSheetScrollSupport())
                }
                Section("Existing Setlists") {
                    if targets.isEmpty {
                        Text(setlistStore.setlists.isEmpty ? "No setlists yet. Create one above." : "No setlists match this search.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(targets) { setlist in
                        Button {
                            perform {
                                _ = try setlistStore.add(pdfItems: checkedItems(), to: setlist.id)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(setlist.name).font(.headline)
                                    Text("\(setlist.entries.count) \(setlist.entries.count == 1 ? "song" : "songs")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(canAdd ? IChartInterfaceStyle.actionText : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(!canAdd)
                        .accessibilityLabel("Add to \(setlist.name)")
                        .accessibilityIdentifier("setlists.destination.\(setlist.id.uuidString)")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                        .accessibilityIdentifier("setlists.destination.error")
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add to Setlist")
            .navigationBarTitleDisplayMode(.inline)
            .tint(IChartInterfaceStyle.actionText)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.colorScheme, appearance.colorScheme)
    }

    private func checkedItems() throws -> [IChartPDFLibraryItem] {
        let items = availableItems
        guard !pdfItemIDs.isEmpty, items.count == pdfItemIDs.count else {
            throw AddToSetlistError.unavailablePDF
        }
        return items
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private enum AddToSetlistError: LocalizedError {
        case unavailablePDF
        var errorDescription: String? { "A selected PDF is no longer available. Close this sheet and choose the PDFs again." }
    }
}
#endif
