import PDFKit
import SwiftUI
import UIKit

/// The Home appearance choice is independent of the device appearance. Apply
/// it at each presentation boundary so sheets and native controls agree with
/// the setlist workspace, including when a view is presented on its own.
private struct IChartSetlistAppearance: ViewModifier {
    @AppStorage("iChartHomeAppearanceMode") private var appearanceMode = "light"

    private var colorScheme: ColorScheme { appearanceMode == "dark" ? .dark : .light }

    func body(content: Content) -> some View {
        content
            .background(Color(uiColor: .systemBackground))
            .environment(\.colorScheme, colorScheme)
            .preferredColorScheme(colorScheme)
    }
}

struct SetlistsView: View {
    @EnvironmentObject private var setlistStore: IChartPDFSetlistStore
    @State private var selectedSetlistID: UUID?
    @State private var showingCreate = false
    @State private var pendingDeletion: IChartPDFSetlist?
    @State private var errorMessage: String?

    init(initialPath: [UUID] = []) {
        _selectedSetlistID = State(initialValue: initialPath.last)
    }

    var body: some View {
        Group {
            if let selectedSetlistID {
                IChartSetlistDetailView(setlistID: selectedSetlistID) { self.selectedSetlistID = nil }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        IChartSetlistWorkspaceTitle(text: "Setlists", identifier: "setlists.title")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        IChartSetlistNativeActionButton(title: "New Setlist", systemImage: "plus", identifier: "setlists.create",
                            isEnabled: setlistStore.loadError == nil) { showingCreate = true }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color(uiColor: .systemBackground))
                    Divider()
                    List {
                        if let loadError = setlistStore.loadError {
                            Section {
                                Label("Setlists couldn’t be loaded", systemImage: "exclamationmark.triangle")
                                Text(loadError).font(.footnote).foregroundStyle(.secondary)
                                Button("Try Again") { perform { try setlistStore.reload() } }
                            }
                        } else if setlistStore.setlists.isEmpty {
                            ContentUnavailableView {
                                Label("No Setlists Yet", systemImage: "music.note.list")
                            } description: {
                                Text("Put your PDFs in playing order for a gig or rehearsal.")
                            } actions: {
                                Button("Create Setlist") { showingCreate = true }
                                    .buttonStyle(.borderedProminent)
                            }
                            .listRowBackground(Color.clear)
                        }
                        ForEach(setlistStore.setlists) { setlist in
                            Button { selectedSetlistID = setlist.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(setlist.name).font(.headline)
                                        Text(songCount(setlist.entries.count))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("setlists.row.\(setlist.id.uuidString)")
                            .swipeActions {
                                Button("Delete Setlist", role: .destructive) { pendingDeletion = setlist }
                            }
                            .contextMenu {
                                Button("Delete Setlist", role: .destructive) { pendingDeletion = setlist }
                            }
                        }
                    }
                    .accessibilityIdentifier("setlists.list")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingCreate) {
            IChartSetlistNameSheet(title: "New Setlist", initialName: "", saveTitle: "Create") { name in
                let setlist = try setlistStore.create(name: name)
                selectedSetlistID = setlist.id
            }
        }
        .confirmationDialog("Delete Setlist?", isPresented: deletionPresented, titleVisibility: .visible) {
            Button("Delete Setlist", role: .destructive) {
                guard let setlist = pendingDeletion else { return }
                perform { try setlistStore.delete(setlistID: setlist.id) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Delete \(pendingDeletion?.name ?? "this setlist")? Your PDFs will remain in the PDF Library.")
        }
        .alert("Couldn’t Update Setlist", isPresented: errorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .modifier(IChartSetlistAppearance())
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func songCount(_ count: Int) -> String { count == 1 ? "1 song" : "\(count) songs" }
}

struct IChartSetlistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var setlistStore: IChartPDFSetlistStore
    @EnvironmentObject private var pdfStore: IChartPDFLibraryStore
    @EnvironmentObject private var chartStore: ChartLibraryStore
    let setlistID: UUID
    let onBack: (() -> Void)?
    @State private var showingAddPDFs = false
    @State private var showingRename = false
    @State private var showingDelete = false
    @State private var readerSelection: IChartSetlistReaderSelection?
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    init(setlistID: UUID, onBack: (() -> Void)? = nil) {
        self.setlistID = setlistID
        self.onBack = onBack
    }

    private var setlist: IChartPDFSetlist? { setlistStore.setlist(id: setlistID) }
    private var entries: [IChartPDFSetlistResolvedEntry] {
        setlist?.resolvedEntries(in: pdfStore.visibleItems(for: chartStore.subscriptionState)) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                IChartSetlistNativeActionButton(title: "Back", systemImage: "chevron.left", identifier: "setlists.back", action: leaveDetail)
                IChartSetlistWorkspaceTitle(text: setlist?.name ?? "Setlist", identifier: "setlists.detail.title")
                    .frame(maxWidth: .infinity, alignment: .leading)
                IChartSetlistNativeActionButton(title: "Add PDFs", systemImage: "plus", identifier: "setlists.songs.add",
                    isEnabled: setlist != nil) { showingAddPDFs = true }
                IChartSetlistNativeActionButton(title: editMode.isEditing ? "Done" : "Edit", identifier: "setlists.reorder",
                    isEnabled: !entries.isEmpty) { editMode = editMode.isEditing ? .inactive : .active }
                Menu {
                    Button("Rename", systemImage: "pencil") { showingRename = true }
                    Button("Delete Setlist", role: .destructive) { showingDelete = true }
                } label: {
                    Label("Setlist Options", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(setlist == nil)
                .accessibilityIdentifier("setlists.options")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
            Divider()
            if setlist != nil {
                List {
                    if entries.isEmpty {
                        ContentUnavailableView {
                            Label("Add Your First Song", systemImage: "doc.badge.plus")
                        } description: {
                            Text("Use Add PDFs above to choose songs from your library, then drag them into playing order.")
                        }
                        .listRowBackground(Color.clear)
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, song in
                        Button {
                            readerSelection = IChartSetlistReaderSelection(entryID: song.id)
                        } label: {
                            songRow(song, index: index)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("setlists.song.\(song.id.uuidString)")
                        .accessibilityAction(named: Text("Move Up")) { moveSong(at: index, by: -1) }
                        .accessibilityAction(named: Text("Move Down")) { moveSong(at: index, by: 1) }
                        .contextMenu {
                            Button("Move Up", systemImage: "arrow.up") { moveSong(at: index, by: -1) }
                                .disabled(index == 0)
                            Button("Move Down", systemImage: "arrow.down") { moveSong(at: index, by: 1) }
                                .disabled(index == entries.count - 1)
                            Button("Remove from Setlist", role: .destructive) {
                                perform { try setlistStore.remove(entryID: song.id, from: setlistID) }
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        perform { try setlistStore.moveEntries(in: setlistID, fromOffsets: offsets, toOffset: destination) }
                    }
                    .onDelete { offsets in
                        perform { try setlistStore.removeEntries(at: offsets, from: setlistID) }
                    }
                }
                .accessibilityIdentifier("setlists.detail.list")
                .environment(\.editMode, $editMode)
            } else {
                ContentUnavailableView("Setlist Unavailable", systemImage: "music.note.list", description: Text("This setlist has been removed."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingAddPDFs) { IChartSetlistPDFPicker(setlistID: setlistID) }
        .sheet(isPresented: $showingRename) {
            IChartSetlistNameSheet(title: "Rename Setlist", initialName: setlist?.name ?? "", saveTitle: "Save") { name in
                try setlistStore.rename(setlistID: setlistID, to: name)
            }
        }
        .fullScreenCover(item: $readerSelection) { selection in
            IChartSetlistPerformanceReader(setlistID: setlistID, startingEntryID: selection.entryID)
        }
        .confirmationDialog("Delete Setlist?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete Setlist", role: .destructive) {
                do {
                    try setlistStore.delete(setlistID: setlistID)
                    leaveDetail()
                } catch { errorMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(setlist?.name ?? "this setlist")? Your PDFs will remain in the PDF Library.")
        }
        .alert("Couldn’t Update Setlist", isPresented: errorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
        .modifier(IChartSetlistAppearance())
    }

    private func songRow(_ song: IChartPDFSetlistResolvedEntry, index: Int) -> some View {
        HStack(spacing: 14) {
            Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.displayTitle).font(.headline)
                if let item = song.pdfItem, pdfStore.exportedPDF(for: item) != nil {
                    Text("\(item.pageCountText) · \(item.transpositionText)").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Label("Unavailable PDF", systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func leaveDetail() {
        if let onBack { onBack() } else { dismiss() }
    }

    private func moveSong(at index: Int, by delta: Int) {
        let destination = index + delta
        guard entries.indices.contains(destination) else { return }
        perform {
            try setlistStore.moveEntries(in: setlistID, fromOffsets: IndexSet(integer: index), toOffset: delta > 0 ? destination + 1 : destination)
        }
    }
}

struct IChartSetlistNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let saveTitle: String
    let onSave: (String) throws -> Void
    @State private var name: String
    @State private var isFocused = false
    @State private var errorMessage: String?

    init(title: String, initialName: String, saveTitle: String, onSave: @escaping (String) throws -> Void) {
        self.title = title
        self.saveTitle = saveTitle
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Setlist Name") {
                    IChartTypedTextField(placeholder: "Setlist Name", text: $name, isFocused: $isFocused,
                        autocapitalizationType: .words, autocorrectionType: .yes, borderStyle: .roundedRect)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("setlists.name")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                        .accessibilityIdentifier("setlists.name.error")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("setlists.name.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        do {
                            try onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                            isFocused = false
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("setlists.name.save")
                }
            }
        }
        .presentationDetents([.medium])
        .modifier(IChartSetlistAppearance())
    }
}

private struct IChartSetlistPDFPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var setlistStore: IChartPDFSetlistStore
    @EnvironmentObject private var pdfStore: IChartPDFLibraryStore
    @EnvironmentObject private var chartStore: ChartLibraryStore
    let setlistID: UUID
    @State private var selectedIDs: Set<UUID> = []
    @State private var errorMessage: String?

    private var items: [IChartPDFLibraryItem] { pdfStore.visibleItems(for: chartStore.subscriptionState) }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView("No PDFs Available", systemImage: "doc.richtext", description: Text("Export a chart or download a PDF to your library, then add it to a setlist."))
                }
                ForEach(items) { item in
                    Button {
                        if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayTitle).font(.headline)
                                Text("\(item.source.itemTitle) · \(item.transpositionText) · \(item.pageCountText)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(pdfStore.exportedPDF(for: item) == nil)
                    .accessibilityIdentifier("setlists.pick.\(item.id.uuidString)")
                    .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle("Add PDFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedIDs.isEmpty ? "Add" : "Add \(selectedIDs.count)") {
                        let selected = items.filter { selectedIDs.contains($0.id) && pdfStore.exportedPDF(for: $0) != nil }
                        guard !selected.isEmpty, selected.count == selectedIDs.count else {
                            errorMessage = "A selected PDF is no longer available. Choose the PDFs again."
                            return
                        }
                        do {
                            _ = try setlistStore.add(pdfItems: selected, to: setlistID)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityIdentifier("setlists.pick.add")
                }
            }
        }
        .onChange(of: items.map(\.id)) { _, currentIDs in selectedIDs.formIntersection(currentIDs) }
        .modifier(IChartSetlistAppearance())
    }
}

private struct IChartSetlistReaderSelection: Identifiable {
    let entryID: UUID
    var id: UUID { entryID }
}

enum IChartSetlistReaderNavigation {
    static func index(in entryIDs: [UUID], selectedID: UUID?) -> Int? {
        guard !entryIDs.isEmpty else { return nil }
        return selectedID.flatMap { entryIDs.firstIndex(of: $0) } ?? 0
    }

    static func adjacentID(in entryIDs: [UUID], selectedID: UUID?, by delta: Int) -> UUID? {
        guard let index = index(in: entryIDs, selectedID: selectedID), entryIDs.indices.contains(index + delta) else { return nil }
        return entryIDs[index + delta]
    }

    static func selectionAfterChange(from previousIDs: [UUID], to currentIDs: [UUID], selectedID: UUID?) -> UUID? {
        guard !currentIDs.isEmpty else { return nil }
        if let selectedID, currentIDs.contains(selectedID) { return selectedID }
        let priorIndex = selectedID.flatMap { previousIDs.firstIndex(of: $0) } ?? 0
        return currentIDs[min(priorIndex, currentIDs.count - 1)]
    }
}

struct IChartSetlistPerformanceReader: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(IChartAppAppearance.preferenceKey) private var appearanceValue = IChartAppAppearance.light.rawValue
    @EnvironmentObject private var setlistStore: IChartPDFSetlistStore
    @EnvironmentObject private var pdfStore: IChartPDFLibraryStore
    @EnvironmentObject private var chartStore: ChartLibraryStore
    let setlistID: UUID
    @State private var selectedID: UUID?
    @State private var unreadableID: UUID?

    init(setlistID: UUID, startingEntryID: UUID) {
        self.setlistID = setlistID
        _selectedID = State(initialValue: startingEntryID)
    }

    private var setlist: IChartPDFSetlist? { setlistStore.setlist(id: setlistID) }
    private var entries: [IChartPDFSetlistResolvedEntry] {
        setlist?.resolvedEntries(in: pdfStore.visibleItems(for: chartStore.subscriptionState)) ?? []
    }
    private var entryIDs: [UUID] { entries.map(\.id) }
    private var currentIndex: Int? { IChartSetlistReaderNavigation.index(in: entryIDs, selectedID: selectedID) }
    private var currentEntry: IChartPDFSetlistResolvedEntry? { currentIndex.map { entries[$0] } }
    private var appearance: IChartAppAppearance { IChartAppAppearance(persistedValue: appearanceValue) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let song = currentEntry {
                    if let item = song.pdfItem, let pdf = pdfStore.exportedPDF(for: item), unreadableID != song.id {
                        IChartSetlistPDFDocumentView(url: pdf.url, songID: song.id) { unreadableID = song.id }
                            .ichartDocumentDisplayAppearance()
                            .accessibilityIdentifier("setlists.reader.pdf")
                    } else {
                        ContentUnavailableView {
                            Label {
                                IChartSetlistUnavailableTitle()
                            } icon: {
                                Image(systemName: "doc.questionmark")
                            }
                        } description: {
                            Text("This PDF can’t be opened with your current library access. Skip it, or return to the setlist to replace this entry.")
                        }
                    }
                    Divider()
                    IChartSetlistReaderControls(position: "\((currentIndex ?? 0) + 1) of \(entries.count)",
                        hasPrevious: adjacentID(by: -1) != nil, hasNext: adjacentID(by: 1) != nil,
                        previous: { advance(by: -1) }, next: { advance(by: 1) })
                        .frame(minHeight: 50)
                        .padding(14)
                } else {
                    ContentUnavailableView("No Songs in This Setlist", systemImage: "music.note.list", description: Text("Add PDFs to the setlist to begin playing."))
                }
            }
            .navigationTitle(currentEntry?.displayTitle ?? setlist?.name ?? "Setlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarColorScheme(appearance.colorScheme, for: .navigationBar)
            .toolbarBackground(appearance.isDark ? Color.black : Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("setlists.reader.done")
                }
                ToolbarItem(placement: .topBarTrailing) { Text(setlist?.name ?? "").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .background(IChartSetlistReaderPresentationAppearance(style: appearance.isDark ? .dark : .light)
            .frame(width: 0, height: 0).accessibilityHidden(true))
        .onChange(of: entryIDs) { previous, current in
            selectedID = IChartSetlistReaderNavigation.selectionAfterChange(from: previous, to: current, selectedID: selectedID)
            unreadableID = nil
        }
        .onChange(of: selectedID) { _, _ in unreadableID = nil }
        .modifier(IChartSetlistAppearance())
    }

    private func adjacentID(by delta: Int) -> UUID? { IChartSetlistReaderNavigation.adjacentID(in: entryIDs, selectedID: selectedID, by: delta) }
    private func advance(by delta: Int) { if let next = adjacentID(by: delta) { selectedID = next } }
}

/// A live preferredColorScheme change can leave a full-screen presentation's
/// native toolbar-item backgrounds with their old traits. Update only the
/// controller that owns this reader's modal presentation.
private struct IChartSetlistReaderPresentationAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> IChartSetlistReaderAppearanceBridge { IChartSetlistReaderAppearanceBridge() }
    func updateUIView(_ view: IChartSetlistReaderAppearanceBridge, context: Context) {
        view.selectedStyle = style
        view.applyAppearance()
        DispatchQueue.main.async { [weak view] in view?.applyAppearance() }
    }
    static func dismantleUIView(_ view: IChartSetlistReaderAppearanceBridge, coordinator: Void) { view.restoreAppearance() }
}

private final class IChartSetlistReaderAppearanceBridge: UIView {
    var selectedStyle: UIUserInterfaceStyle = .unspecified
    private weak var owner: UIViewController?
    private var originalStyle: UIUserInterfaceStyle = .unspecified
    private var appliedStyle: UIUserInterfaceStyle?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { restoreAppearance() } else { applyAppearance() }
    }

    func applyAppearance() {
        guard let window else { return }
        var responder: UIResponder? = next
        while let current = responder, !(current is UIViewController) { responder = current.next }
        guard var controller = responder as? UIViewController else { return }
        while let parent = controller.parent { controller = parent }
        guard controller.presentingViewController != nil, controller !== window.rootViewController else { return }
        if owner !== controller {
            restoreAppearance()
            owner = controller
            originalStyle = controller.overrideUserInterfaceStyle
        }
        if controller.overrideUserInterfaceStyle != selectedStyle { controller.overrideUserInterfaceStyle = selectedStyle }
        appliedStyle = selectedStyle
    }

    func restoreAppearance() {
        if let owner, owner.overrideUserInterfaceStyle == appliedStyle { owner.overrideUserInterfaceStyle = originalStyle }
        owner = nil
        appliedStyle = nil
    }
}

private struct IChartSetlistWorkspaceTitle: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let identifier: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 22, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 2
        label.isAccessibilityElement = true
        label.accessibilityTraits.insert(.header)
        return label
    }

    func updateUIView(_ view: UILabel, context: Context) {
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        view.text = text
        view.accessibilityIdentifier = identifier
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
    }
}

private struct IChartSetlistNativeActionButton: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var systemImage: String? = nil
    let identifier: String
    var isEnabled = true
    let action: () -> Void

    func makeUIView(context: Context) -> IChartSetlistActionButton { IChartSetlistActionButton() }

    func updateUIView(_ view: IChartSetlistActionButton, context: Context) {
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        view.configure(title: title, systemImage: systemImage, identifier: identifier, isEnabled: isEnabled, tinted: false)
        view.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: IChartSetlistActionButton, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        return CGSize(width: max(44, size.width), height: max(44, size.height))
    }
}

private final class IChartSetlistActionButton: UIButton {
    var action: () -> Void = {}

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: max(44, size.width), height: max(44, size.height))
    }

    init() {
        super.init(frame: .zero)
        addTarget(self, action: #selector(performAction), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, systemImage: String?, identifier: String, isEnabled: Bool, tinted: Bool) {
        var configuration = tinted ? UIButton.Configuration.tinted() : .plain()
        configuration.title = title
        configuration.image = systemImage.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        self.configuration = configuration
        self.isEnabled = isEnabled
        isAccessibilityElement = true
        accessibilityIdentifier = identifier
        accessibilityLabel = title
    }

    @objc private func performAction() { action() }
}

private struct IChartSetlistUnavailableTitle: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.text = "Unavailable PDF"
        label.accessibilityIdentifier = "setlists.reader.unavailable"
        label.isAccessibilityElement = true
        label.accessibilityTraits.insert(.header)
        label.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    func updateUIView(_ view: UILabel, context: Context) {
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
    }
}

private struct IChartSetlistReaderControls: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let position: String
    let hasPrevious: Bool
    let hasNext: Bool
    let previous: () -> Void
    let next: () -> Void

    func makeUIView(context: Context) -> IChartSetlistReaderControlBar { IChartSetlistReaderControlBar() }

    func updateUIView(_ view: IChartSetlistReaderControlBar, context: Context) {
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        view.positionLabel.text = position
        view.previousButton.configure(title: "Previous Song", systemImage: "chevron.left", identifier: "setlists.reader.previous",
            isEnabled: hasPrevious, tinted: true)
        view.nextButton.configure(title: "Next Song", systemImage: "chevron.right", identifier: "setlists.reader.next",
            isEnabled: hasNext, tinted: true)
        view.previousButton.action = previous
        view.nextButton.action = next
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: IChartSetlistReaderControlBar, context: Context) -> CGSize? {
        let height = max(50, uiView.previousButton.intrinsicContentSize.height, uiView.nextButton.intrinsicContentSize.height,
            uiView.positionLabel.intrinsicContentSize.height)
        let width = proposal.width ?? uiView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        return CGSize(width: width, height: height)
    }
}

private final class IChartSetlistReaderControlBar: UIStackView {
    let previousButton = IChartSetlistActionButton()
    let nextButton = IChartSetlistActionButton()
    let positionLabel = UILabel()

    init() {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .center
        spacing = 16
        let beforePosition = UIView()
        let afterPosition = UIView()
        positionLabel.font = .preferredFont(forTextStyle: .subheadline)
        positionLabel.adjustsFontForContentSizeCategory = true
        positionLabel.textColor = .secondaryLabel
        positionLabel.textAlignment = .center
        positionLabel.accessibilityIdentifier = "setlists.reader.position"
        positionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        [previousButton, beforePosition, positionLabel, afterPosition, nextButton].forEach(addArrangedSubview)
        beforePosition.widthAnchor.constraint(equalTo: afterPosition.widthAnchor).isActive = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct IChartSetlistPDFDocumentView: UIViewRepresentable {
    let url: URL
    let songID: UUID
    var onUnavailable: () -> Void = {}

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        // The display modifier inverts this document surface in dark mode.
        // A fixed light surround avoids inverting an already dark UIKit color.
        view.backgroundColor = UIColor(white: 0.96, alpha: 1)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.backgroundColor = UIColor(white: 0.96, alpha: 1)
        let coordinator = context.coordinator
        guard coordinator.songID != songID || coordinator.url != url else { return }
        coordinator.songID = songID
        coordinator.url = url
        let document = PDFDocument(url: url)
        view.document = document
        if let firstPage = document?.page(at: 0), document?.isLocked == false {
            view.go(to: firstPage)
            view.autoScales = true
        } else {
            view.document = nil
            DispatchQueue.main.async {
                guard coordinator.songID == songID, coordinator.url == url else { return }
                onUnavailable()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        // SwiftUI/UIKit may retain a removed view during a transition. It must
        // not retain readable song content after access changes or dismissal.
        coordinator.songID = nil
        coordinator.url = nil
        view.document = nil
    }

    final class Coordinator {
        var songID: UUID?
        var url: URL?
    }
}
