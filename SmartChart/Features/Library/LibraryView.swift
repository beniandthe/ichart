import Foundation
import SwiftUI

private enum IChartHomeBrand {
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.92)
    static let paperSecondary = Color(red: 0.93, green: 0.90, blue: 0.85)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let night = Color(red: 0.06, green: 0.09, blue: 0.11)
    static let stage = Color(red: 0.06, green: 0.08, blue: 0.11)
    static let blue = Color(red: 0.13, green: 0.42, blue: 0.54)
    static let logoBlue = Color(red: 0.56, green: 0.83, blue: 0.90)
    static let blueSoft = Color(red: 0.86, green: 0.93, blue: 0.95)
    static let staffOnDark = Color.white.opacity(0.23)
}

private enum IChartHomeAppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .light:
            "Light mode"
        case .dark:
            "Dark mode"
        }
    }
}

private struct IChartHomeTheme {
    let mode: IChartHomeAppearanceMode

    var isDark: Bool {
        mode == .dark
    }

    var workspaceTitle: Color {
        isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink
    }

    var workspaceSecondary: Color {
        isDark ? IChartHomeBrand.paper.opacity(0.66) : Color.secondary
    }

    var emptyStateBackground: Color {
        isDark ? IChartHomeBrand.paper.opacity(0.10) : Color.white.opacity(0.68)
    }

    var panelBackground: Color {
        isDark ? IChartHomeBrand.stage.opacity(0.82) : IChartHomeBrand.paper.opacity(0.84)
    }

    var panelTitle: Color {
        isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink
    }

    var panelSecondary: Color {
        isDark ? IChartHomeBrand.paper.opacity(0.68) : Color.secondary
    }

    var panelBorder: Color {
        isDark ? Color.white.opacity(0.10) : IChartHomeBrand.ink.opacity(0.07)
    }

    var panelShadow: Color {
        isDark ? Color.black.opacity(0.28) : IChartHomeBrand.ink.opacity(0.08)
    }
}

private enum IChartLogoVariant: String {
    case b47b
    case b48a

    static var homeScreenTrialDefault: IChartLogoVariant {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-iChartLogoVariant"),
              arguments.indices.contains(arguments.index(after: flagIndex)) else {
            return .b48a
        }

        let requestedValue = arguments[arguments.index(after: flagIndex)].lowercased()
        return IChartLogoVariant(rawValue: requestedValue) ?? .b48a
    }

    var iFontName: String {
        switch self {
        case .b47b:
            return "FinaleMaestroText"
        case .b48a:
            return "FinaleMaestroText-Italic"
        }
    }

    var iTrailingAdjustment: CGFloat {
        switch self {
        case .b47b:
            return -0.07
        case .b48a:
            return -0.025
        }
    }

    var iOffset: CGSize {
        switch self {
        case .b47b:
            return .zero
        case .b48a:
            return CGSize(width: -0.055, height: 0)
        }
    }
}

private enum IChartHomeTab: String, CaseIterable, Identifiable {
    case charts
    case forums
    case help
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charts:
            "Charts"
        case .forums:
            "Forums"
        case .help:
            "Help"
        case .settings:
            "Settings"
        }
    }

    var systemImageName: String {
        switch self {
        case .charts:
            "music.note.list"
        case .forums:
            "bubble.left.and.bubble.right"
        case .help:
            "questionmark.circle"
        case .settings:
            "gearshape"
        }
    }
}

private enum IChartHelpTopic: String, CaseIterable, Identifiable {
    case faq
    case userPolicy
    case legal
    case contactUs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faq:
            "FAQ"
        case .userPolicy:
            "User Policy"
        case .legal:
            "Legal"
        case .contactUs:
            "Contact Us"
        }
    }

    var summary: String {
        switch self {
        case .faq:
            "Common questions"
        case .userPolicy:
            "Use and conduct"
        case .legal:
            "Privacy and notices"
        case .contactUs:
            "Support placeholder"
        }
    }

    var systemImageName: String {
        switch self {
        case .faq:
            "questionmark.circle"
        case .userPolicy:
            "person.text.rectangle"
        case .legal:
            "doc.text"
        case .contactUs:
            "envelope"
        }
    }

    var detailTitle: String {
        switch self {
        case .faq:
            "Common Questions"
        case .userPolicy:
            "User Policy"
        case .legal:
            "Legal Notes"
        case .contactUs:
            "Contact Us"
        }
    }

    var detailText: String {
        switch self {
        case .faq:
            "Quick help for chart setup, handwriting tools, export, and saved charts will live here as V1 hardens."
        case .userPolicy:
            "Smart Chart should keep correction behavior local and contextual. Handwritten passes are validation evidence, not global recognizer training."
        case .legal:
            "Terms, privacy language, font attributions, and third-party notices are tracked here for the release hygiene sprint."
        case .contactUs:
            "A support contact path will live here for V1 feedback, bug reports, and account questions."
        }
    }
}

private enum IChartChartPreviewMode: String, CaseIterable, Identifiable {
    case collapsed
    case quick
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collapsed:
            "Collapsed"
        case .quick:
            "Quick"
        case .large:
            "Large"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: ChartLibraryStore
    @EnvironmentObject private var authStore: IChartAuthStore
    @EnvironmentObject private var cloudSyncStore: ChartCloudSyncStore
    let onOpenChart: (Chart.ID, EditorCanvasMode) -> Void
    @AppStorage("iChartHomeAppearanceMode") private var homeAppearanceModeRawValue = IChartHomeAppearanceMode.light.rawValue
    @AppStorage("iChartHomeSidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("iChartChartPreviewMode") private var chartPreviewModeRawValue = IChartChartPreviewMode.collapsed.rawValue
    @AppStorage("iChartUserEmail") private var userEmail = ""
    @AppStorage("iChartUserPhone") private var userPhone = ""
    @AppStorage("iChartUserAddress") private var userAddress = ""
    @AppStorage("iChartUserPaymentSummary") private var userPaymentSummary = ""
    @State private var logoVariant = IChartLogoVariant.homeScreenTrialDefault
    @State private var selectedHomeTab: IChartHomeTab = .charts
    @State private var selectedHelpTopic: IChartHelpTopic?
    @State private var showingLayoutPicker = false
    @State private var renameRequest: ChartRenameRequest?
    @State private var deleteRequest: ChartDeleteRequest?

    private var chartCountText: String {
        let count = store.charts.count
        return count == 1 ? "1 chart" : "\(count) charts"
    }

    private var homeAppearanceMode: IChartHomeAppearanceMode {
        IChartHomeAppearanceMode(rawValue: homeAppearanceModeRawValue) ?? .light
    }

    private var homeAppearanceModeBinding: Binding<IChartHomeAppearanceMode> {
        Binding(
            get: { homeAppearanceMode },
            set: { homeAppearanceModeRawValue = $0.rawValue }
        )
    }

    private var homeTheme: IChartHomeTheme {
        IChartHomeTheme(mode: homeAppearanceMode)
    }

    private var chartPreviewMode: IChartChartPreviewMode {
        IChartChartPreviewMode(rawValue: chartPreviewModeRawValue) ?? .collapsed
    }

    private var chartPreviewModeBinding: Binding<IChartChartPreviewMode> {
        Binding(
            get: { chartPreviewMode },
            set: { chartPreviewModeRawValue = $0.rawValue }
        )
    }

    private var freeChartUsageText: String? {
        guard let limit = store.entitlements.localChartLimit else {
            return nil
        }

        return "\(min(store.charts.count, limit)) of \(limit) free charts used"
    }

    var body: some View {
        HStack(spacing: 0) {
            IChartHomeSidebar(
                logoVariant: logoVariant,
                selectedTab: $selectedHomeTab,
                appearanceMode: homeAppearanceModeBinding,
                isCollapsed: $isSidebarCollapsed
            )

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            selectedHomeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IChartLibraryBackground(mode: homeAppearanceMode).ignoresSafeArea())
        .tint(IChartHomeBrand.blue)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            cloudSyncStore.attach(libraryStore: store)
            await authStore.bootstrap()
            cloudSyncStore.authStateChanged(authStore.state)
        }
        .onChange(of: authStore.state) { _, state in
            cloudSyncStore.authStateChanged(state)
        }
        .onChange(of: authStore.profile) { _, profile in
            apply(profile: profile)
        }
        .sheet(isPresented: $showingLayoutPicker) {
            NewChartLayoutPickerView { layoutStyle in
                showingLayoutPicker = false
                createNewChart(layoutStyle: layoutStyle)
            }
        }
        .sheet(item: $renameRequest) { request in
            RenameChartSheetView(request: request) { chartID, title in
                store.renameChart(id: chartID, to: title)
            }
        }
        .alert(
            "Delete Chart?",
            isPresented: deleteConfirmationPresented,
            presenting: deleteRequest
        ) { request in
            Button("Delete", role: .destructive) {
                store.deleteChart(id: request.chartID)
                deleteRequest = nil
            }
            Button("Cancel", role: .cancel) {
                deleteRequest = nil
            }
        } message: { request in
            Text("This removes \(request.title) from the local library.")
        }
    }

    @ViewBuilder
    private var selectedHomeContent: some View {
        switch selectedHomeTab {
        case .charts:
            chartsHomeContent
        case .forums:
            forumsHomeContent
        case .help:
            helpHomeContent
        case .settings:
            settingsHomeContent
        }
    }

    private var chartsHomeContent: some View {
        homeScroll {
            VStack(alignment: .leading, spacing: 20) {
                IChartNewChartControl(
                    freeChartUsageText: freeChartUsageText,
                    canCreateChart: store.canCreateChart,
                    theme: homeTheme,
                    onCreateChart: {
                        showingLayoutPicker = true
                    }
                )

                projectsSection
            }
        }
    }

    private var forumsHomeContent: some View {
        homeScroll {
            IChartHomePanel(
                title: "Forums",
                systemImageName: "bubble.left.and.bubble.right",
                theme: homeTheme
            ) {
                ContentUnavailableView(
                    "No Forum Posts",
                    systemImage: "bubble.left.and.bubble.right"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            }
        }
    }

    private var settingsHomeContent: some View {
        homeScroll {
            VStack(spacing: 18) {
                IChartHomePanel(
                    title: "Settings",
                    systemImageName: "gearshape",
                    theme: homeTheme
                ) {
                    VStack(spacing: 0) {
                        IChartSettingsRow(
                            title: "Library",
                            value: chartCountText,
                            systemImageName: "doc.text",
                            theme: homeTheme
                        )

                        Divider()
                            .overlay(homeTheme.panelBorder)
                            .padding(.leading, 44)

                        IChartSettingsRow(
                            title: "Storage",
                            value: store.persistenceStatus.displayText,
                            systemImageName: store.persistenceStatus.systemImageName,
                            theme: homeTheme
                        )

                        Divider()
                            .overlay(homeTheme.panelBorder)
                            .padding(.leading, 44)

                        IChartSettingsRow(
                            title: "Plan",
                            value: store.chartCapacityText,
                            systemImageName: "person.crop.circle",
                            theme: homeTheme
                        )
                    }
                }

                IChartHomePanel(
                    title: "Account",
                    systemImageName: "person.crop.circle.badge.checkmark",
                    theme: homeTheme
                ) {
                    IChartAccountSettings(authStore: authStore, theme: homeTheme)
                }

                IChartHomePanel(
                    title: "Chart Sync",
                    systemImageName: "icloud.and.arrow.up",
                    theme: homeTheme
                ) {
                    IChartCloudSyncSettings(syncStore: cloudSyncStore, theme: homeTheme)
                }

                IChartHomePanel(
                    title: "User Info",
                    systemImageName: "person.text.rectangle",
                    theme: homeTheme
                ) {
                    IChartUserInfoSettings(
                        email: $userEmail,
                        phone: $userPhone,
                        address: $userAddress,
                        paymentSummary: $userPaymentSummary,
                        theme: homeTheme,
                        authState: authStore.state,
                        isSaving: authStore.isWorking,
                        onSaveProfile: {
                            Task {
                                await authStore.saveProfile(
                                    email: userEmail,
                                    phone: userPhone,
                                    mailingAddress: userAddress,
                                    paymentSummary: userPaymentSummary
                                )
                            }
                        }
                    )
                }
            }
        }
    }

    private var helpHomeContent: some View {
        homeScroll {
            IChartHomePanel(
                title: "Help",
                systemImageName: "questionmark.circle",
                theme: homeTheme
            ) {
                VStack(spacing: 0) {
                    let activeTopic = selectedHelpTopic ?? .faq

                    ForEach(IChartHelpTopic.allCases) { topic in
                        IChartHelpTopicRow(
                            topic: topic,
                            isSelected: activeTopic == topic,
                            theme: homeTheme,
                            action: {
                                selectedHelpTopic = topic
                            }
                        )

                        if topic.id != IChartHelpTopic.allCases.last?.id {
                            Divider()
                                .overlay(homeTheme.panelBorder)
                                .padding(.leading, 44)
                        }
                    }

                    Divider()
                        .overlay(homeTheme.panelBorder)
                        .padding(.top, 8)

                    IChartHelpTopicDetail(topic: activeTopic, theme: homeTheme)
                        .padding(.top, 16)
                }
            }
        }
    }

    private func homeScroll<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Spacer()

                IChartPreviewModePicker(selection: chartPreviewModeBinding, theme: homeTheme)
            }

            if store.charts.isEmpty {
                ContentUnavailableView(
                    "No Projects Yet",
                    systemImage: "music.note",
                    description: Text("Create a new chart to start the first project.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .foregroundStyle(homeTheme.workspaceTitle)
                .background(homeTheme.emptyStateBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.charts) { chart in
                        ProjectRowView(
                            chart: chart,
                            previewMode: chartPreviewMode,
                            isSelected: store.selectedChartID == chart.id,
                            canDuplicate: store.canCreateChart,
                            onOpen: {
                                onOpenChart(chart.id, .browse)
                            },
                            onRename: {
                                renameRequest = ChartRenameRequest(chart: chart)
                            },
                            onDuplicate: {
                                store.duplicateChart(id: chart.id)
                            },
                            onDelete: {
                                deleteRequest = ChartDeleteRequest(chart: chart)
                            }
                        )
                    }
                }
            }
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { deleteRequest != nil },
            set: { isPresented in
                if !isPresented {
                    deleteRequest = nil
                }
            }
        )
    }

    private func createNewChart(layoutStyle: ChartLayoutStyle) {
        guard store.createBlankChart(layoutStyle: layoutStyle), let chartID = store.selectedChartID else {
            return
        }

        onOpenChart(chartID, .browse)
    }

    private func apply(profile: IChartUserProfile?) {
        guard let profile else {
            return
        }

        if let email = profile.email {
            userEmail = email
        }

        if let phone = profile.phone {
            userPhone = phone
        }

        if let mailingAddress = profile.mailingAddress {
            userAddress = mailingAddress
        }

        if let paymentSummary = profile.paymentSummary {
            userPaymentSummary = paymentSummary
        }
    }
}

private struct ChartRenameRequest: Identifiable, Hashable {
    let chartID: Chart.ID
    let currentTitle: String

    var id: Chart.ID { chartID }

    init(chart: Chart) {
        chartID = chart.id
        currentTitle = chart.title
    }
}

private struct ChartDeleteRequest: Identifiable, Hashable {
    let chartID: Chart.ID
    let title: String

    var id: Chart.ID { chartID }

    init(chart: Chart) {
        chartID = chart.id
        title = chart.title
    }
}

private struct RenameChartSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChartRenameRequest
    let onSave: (Chart.ID, String) -> Void
    @State private var title: String

    init(
        request: ChartRenameRequest,
        onSave: @escaping (Chart.ID, String) -> Void
    ) {
        self.request = request
        self.onSave = onSave
        _title = State(initialValue: request.currentTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Chart title", text: $title)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            }
            .navigationTitle("Rename Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(sanitizedTitle.isEmpty)
                }
            }
        }
    }

    private var sanitizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !sanitizedTitle.isEmpty else {
            return
        }

        onSave(request.chartID, sanitizedTitle)
        dismiss()
    }
}

private struct NewChartLayoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ChartLayoutStyle) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ChartLayoutStyle.v1NewChartOptions) { layoutStyle in
                        Button {
                            onSelect(layoutStyle)
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: layoutStyle.systemImageName)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(IChartHomeBrand.blue)
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(layoutStyle.displayText)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(layoutStyle.detailText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 12)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(IChartHomeBrand.paper.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("New Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

}

private struct IChartHomeSidebar: View {
    private let expandedWidth: CGFloat = 208
    private let collapsedWidth: CGFloat = 82

    let logoVariant: IChartLogoVariant
    @Binding var selectedTab: IChartHomeTab
    @Binding var appearanceMode: IChartHomeAppearanceMode
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: isCollapsed ? 16 : 22) {
            sidebarHeader

            VStack(spacing: 8) {
                ForEach(IChartHomeTab.allCases) { tab in
                    IChartHomeSidebarButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        isCollapsed: isCollapsed,
                        action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedTab = tab
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, isCollapsed ? 10 : 12)

            Spacer()

            IChartHomeAppearanceModeSwitch(selectedMode: $appearanceMode)
                .padding(.horizontal, isCollapsed ? 10 : 12)
                .padding(.bottom, 20)
        }
        .frame(width: isCollapsed ? collapsedWidth : expandedWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    IChartHomeBrand.stage,
                    IChartHomeBrand.night
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .animation(.easeInOut(duration: 0.20), value: isCollapsed)
    }

    private var sidebarHeader: some View {
        VStack(spacing: isCollapsed ? 6 : 4) {
            HStack {
                Spacer()
                collapseButton
            }

            IChartWordmarkView(variant: logoVariant, size: isCollapsed ? 34 : 72)
                .frame(maxWidth: .infinity, minHeight: isCollapsed ? 42 : 70, alignment: .center)
        }
        .padding(.horizontal, isCollapsed ? 8 : 12)
        .padding(.top, isCollapsed ? 12 : 16)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.20)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                .font(.caption.weight(.bold))
                .foregroundStyle(IChartHomeBrand.paper.opacity(0.70))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Open sidebar" : "Collapse sidebar")
    }
}

private struct IChartHomeAppearanceModeSwitch: View {
    @Binding var selectedMode: IChartHomeAppearanceMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IChartHomeAppearanceMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMode = mode
                    }
                } label: {
                    Image(systemName: mode.systemImageName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(foregroundColor(for: mode))
                        .background(backgroundColor(for: mode))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.accessibilityLabel)
                .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func foregroundColor(for mode: IChartHomeAppearanceMode) -> Color {
        selectedMode == mode ? IChartHomeBrand.paper : IChartHomeBrand.paper.opacity(0.62)
    }

    private func backgroundColor(for mode: IChartHomeAppearanceMode) -> Color {
        selectedMode == mode ? IChartHomeBrand.logoBlue.opacity(0.22) : Color.clear
    }
}

private struct IChartHomeSidebarButton: View {
    let tab: IChartHomeTab
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImageName)
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)

                if !isCollapsed {
                    Text(tab.title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, isCollapsed ? 10 : 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var foregroundColor: Color {
        isSelected ? IChartHomeBrand.paper : IChartHomeBrand.paper.opacity(0.70)
    }

    private var backgroundColor: Color {
        isSelected ? IChartHomeBrand.logoBlue.opacity(0.18) : Color.clear
    }

    private var borderColor: Color {
        isSelected ? IChartHomeBrand.logoBlue.opacity(0.28) : Color.clear
    }
}

private struct IChartHelpTopicRow: View {
    let topic: IChartHelpTopic
    let isSelected: Bool
    let theme: IChartHomeTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: topic.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(topic.summary)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                }

                Spacer(minLength: 16)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? IChartHomeBrand.blue : theme.panelSecondary.opacity(0.7))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(isSelected ? IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.18 : 0.72) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(topic.title)
    }
}

private struct IChartHelpTopicDetail: View {
    let topic: IChartHelpTopic
    let theme: IChartHomeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(topic.detailTitle, systemImage: topic.systemImageName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            Text(topic.detailText)
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct IChartHomePanel<Content: View>: View {
    let title: String
    let systemImageName: String
    let theme: IChartHomeTheme
    let content: Content

    init(
        title: String,
        systemImageName: String,
        theme: IChartHomeTheme,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImageName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
            }

            content
                .foregroundStyle(theme.panelTitle)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
        .shadow(color: theme.panelShadow, radius: 16, y: 8)
    }
}

private struct IChartSettingsRow: View {
    let title: String
    let value: String
    let systemImageName: String
    let theme: IChartHomeTheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            Spacer(minLength: 16)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }
}

private struct IChartAccountSettings: View {
    @ObservedObject var authStore: IChartAuthStore
    let theme: IChartHomeTheme
    @State private var email = ""
    @State private var password = ""

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 8
            && !authStore.isWorking
    }

    private var canRequestPasswordReset: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !authStore.isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(authStore.state.statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            switch authStore.state {
            case .unconfigured:
                Text("Add SupabaseURL and SupabasePublishableKey to the build, or pass SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in the scheme environment.")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .signedOut:
                credentialsForm
                actionRow
                passwordResetRow
            case .pendingEmailVerification:
                verificationRow
            case .signedIn:
                signedInRow
            }

            statusFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var credentialsForm: some View {
        VStack(spacing: 10) {
            IChartAccountTextField(
                title: "Email",
                placeholder: "name@example.com",
                text: $email,
                systemImageName: "envelope",
                keyboardType: .emailAddress,
                theme: theme
            )

            IChartAccountSecureField(
                title: "Password",
                placeholder: "8 characters minimum",
                text: $password,
                systemImageName: "lock",
                theme: theme
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await authStore.createAccount(email: email, password: password)
                }
            } label: {
                Label("Create Account", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(!canSubmit)

            Button {
                Task {
                    await authStore.signIn(email: email, password: password)
                }
            } label: {
                Label("Sign In", systemImage: "person.crop.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!canSubmit)
        }
    }

    private var passwordResetRow: some View {
        Button {
            Task {
                await authStore.requestPasswordReset(email: email)
            }
        } label: {
            Label("Reset Password", systemImage: "key")
        }
        .buttonStyle(.bordered)
        .disabled(!canRequestPasswordReset)
    }

    private var verificationRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await authStore.resendVerificationEmail()
                }
            } label: {
                Label("Resend Email", systemImage: "envelope.badge")
            }
            .buttonStyle(.bordered)
            .disabled(authStore.isWorking)

            Button {
                authStore.returnToSignIn()
            } label: {
                Label("Sign In", systemImage: "person.crop.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(authStore.isWorking)
        }
    }

    private var signedInRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await authStore.refreshSession()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(authStore.isWorking)

            Button(role: .destructive) {
                Task {
                    await authStore.signOut()
                }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
            .disabled(authStore.isWorking)
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if authStore.isWorking {
            ProgressView()
                .controlSize(.small)
        } else if let errorMessage = authStore.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(Color(red: 0.62, green: 0.18, blue: 0.12))
                .fixedSize(horizontal: false, vertical: true)
        } else if let statusMessage = authStore.statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var iconName: String {
        switch authStore.state {
        case .unconfigured:
            return "wifi.slash"
        case .signedOut:
            return "person.crop.circle.badge.plus"
        case .pendingEmailVerification:
            return "envelope.badge"
        case .signedIn:
            return "checkmark.seal"
        }
    }

    private var detailText: String {
        switch authStore.state {
        case .unconfigured:
            return "This build needs Supabase configuration."
        case .signedOut:
            return "Create an account or sign in to sync profile and chart data."
        case .pendingEmailVerification(let email):
            return "Open the verification link sent to \(email), then sign in."
        case .signedIn(let session):
            return session.email ?? "Signed in to iChart."
        }
    }
}

private struct IChartCloudSyncSettings: View {
    @ObservedObject var syncStore: ChartCloudSyncStore
    let theme: IChartHomeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: syncStore.state.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(syncStore.state.displayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(syncStore.state.detailText)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            if let lastRemoteBackupAt = syncStore.lastRemoteBackupAt {
                IChartSettingsRow(
                    title: "Last Backup",
                    value: lastRemoteBackupAt.formatted(date: .abbreviated, time: .shortened),
                    systemImageName: "clock.arrow.circlepath",
                    theme: theme
                )
            }

            Button {
                syncStore.syncNow()
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(syncStore.isWorking || syncStore.state == .unconfigured || syncStore.state == .signedOut)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IChartAccountTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImageName: String
    let keyboardType: UIKeyboardType
    let theme: IChartHomeTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .frame(width: 86, alignment: .leading)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .foregroundStyle(theme.panelTitle)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.emptyStateBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.panelBorder, lineWidth: 1)
                }
        }
    }
}

private struct IChartAccountSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImageName: String
    let theme: IChartHomeTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .frame(width: 86, alignment: .leading)

            SecureField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .foregroundStyle(theme.panelTitle)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.emptyStateBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.panelBorder, lineWidth: 1)
                }
        }
    }
}

private struct IChartUserInfoSettings: View {
    @Binding var email: String
    @Binding var phone: String
    @Binding var address: String
    @Binding var paymentSummary: String
    let theme: IChartHomeTheme
    let authState: IChartAuthState
    let isSaving: Bool
    let onSaveProfile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            IChartSettingsTextFieldRow(
                title: "Email",
                placeholder: "name@example.com",
                text: $email,
                systemImageName: "envelope",
                theme: theme
            )

            settingsDivider

            IChartSettingsTextFieldRow(
                title: "Phone",
                placeholder: "(555) 555-5555",
                text: $phone,
                systemImageName: "phone",
                theme: theme
            )

            settingsDivider

            IChartSettingsTextFieldRow(
                title: "Address",
                placeholder: "Mailing address",
                text: $address,
                systemImageName: "house",
                isMultiline: true,
                theme: theme
            )

            settingsDivider

            IChartSettingsTextFieldRow(
                title: "Payment Info",
                placeholder: "Payment method",
                text: $paymentSummary,
                systemImageName: "creditcard",
                theme: theme
            )

            Text("Card details stay with the payment processor.")
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 44)
                .padding(.top, 8)

            Button {
                onSaveProfile()
            } label: {
                Label("Save Profile", systemImage: "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(authState.signedInSession == nil || isSaving)
            .padding(.top, 14)
        }
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(theme.panelBorder)
            .padding(.leading, 44)
    }
}

private struct IChartSettingsTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImageName: String
    var isMultiline = false
    let theme: IChartHomeTheme

    var body: some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: 14) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .frame(minWidth: 104, alignment: .leading)

            Spacer(minLength: 12)

            field
                .font(.subheadline)
                .foregroundStyle(theme.panelTitle)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 11)
                .padding(.vertical, isMultiline ? 9 : 7)
                .frame(maxWidth: 340, alignment: .trailing)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.emptyStateBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.panelBorder, lineWidth: 1)
                }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var field: some View {
        if isMultiline {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2...4)
        } else {
            TextField(placeholder, text: $text)
                .lineLimit(1)
        }
    }
}

private struct IChartNewChartControl: View {
    let freeChartUsageText: String?
    let canCreateChart: Bool
    let theme: IChartHomeTheme
    let onCreateChart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onCreateChart) {
                Label("New Chart", systemImage: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                    .frame(minWidth: 180, minHeight: 44)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(IChartHomeBrand.blue)
            .disabled(!canCreateChart)

            if let freeChartUsageText {
                Text(freeChartUsageText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.workspaceTitle.opacity(0.68))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}

private struct IChartPreviewModePicker: View {
    @Binding var selection: IChartChartPreviewMode
    let theme: IChartHomeTheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(IChartChartPreviewMode.allCases) { mode in
                let isSelected = selection == mode

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(textColor(isSelected: isSelected))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(IChartHomeBrand.paper.opacity(0.95))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) preview")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(3)
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(controlBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(controlBorder, lineWidth: 1)
        }
    }

    private var controlBackground: Color {
        theme.isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.34)
    }

    private var controlBorder: Color {
        theme.isDark ? Color.white.opacity(0.16) : IChartHomeBrand.ink.opacity(0.08)
    }

    private func textColor(isSelected: Bool) -> Color {
        if isSelected {
            return IChartHomeBrand.ink
        }

        return theme.isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink.opacity(0.72)
    }
}

private struct IChartWordmarkView: View {
    let variant: IChartLogoVariant
    let size: CGFloat

    init(variant: IChartLogoVariant, size: CGFloat) {
        self.variant = variant
        self.size = size
        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        #endif
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("i")
                .font(.custom(variant.iFontName, size: size * 0.58))
                .foregroundStyle(IChartHomeBrand.paper)
                .padding(.trailing, size * variant.iTrailingAdjustment)
                .offset(
                    x: size * variant.iOffset.width,
                    y: size * variant.iOffset.height
                )

            staffWord
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityLabel("iChart")
    }

    private var staffWord: some View {
        HStack(alignment: .lastTextBaseline, spacing: -size * 0.035) {
            Text("C")
                .font(.custom("FinaleMaestroText", size: size))
                .foregroundStyle(IChartHomeBrand.logoBlue)

            Text("hart")
                .font(.custom("FinaleMaestroText", size: size * 0.74))
                .foregroundStyle(IChartHomeBrand.paper)
                .baselineOffset(size * 0.01)
        }
        .padding(.trailing, size * 0.14)
        .overlay {
            IChartStaffMeasureLines()
                .frame(height: size * 0.72)
                .padding(.top, size * 0.08)
                .allowsHitTesting(false)
        }
    }
}

private struct IChartStaffMeasureLines: View {
    var body: some View {
        GeometryReader { geometry in
            let lineWidth = max(geometry.size.height * 0.018, 1)
            let barSpacing = max(geometry.size.width * 0.024, 4)

            Path { path in
                for index in 0..<5 {
                    let y = geometry.size.height * CGFloat(index) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(
                IChartHomeBrand.staffOnDark,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )

            Path { path in
                let firstBarX = geometry.size.width - barSpacing
                path.move(to: CGPoint(x: firstBarX, y: 0))
                path.addLine(to: CGPoint(x: firstBarX, y: geometry.size.height))
                path.move(to: CGPoint(x: geometry.size.width, y: 0))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
            }
            .stroke(
                IChartHomeBrand.staffOnDark,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
        }
    }
}

struct ChartLibraryPersistenceStatusBadge: View {
    let status: ChartLibraryPersistenceStatus

    var body: some View {
        Label(status.displayText, systemImage: status.systemImageName)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
            .accessibilityLabel(status.accessibilityText)
    }

    private var foregroundColor: Color {
        switch status {
        case .failed:
            Color(red: 0.62, green: 0.18, blue: 0.12)
        case .notTracking:
            IChartHomeBrand.paper.opacity(0.70)
        case .ready, .saved:
            Color(red: 0.13, green: 0.38, blue: 0.20)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .failed:
            Color(red: 1.0, green: 0.91, blue: 0.88)
        case .notTracking:
            Color.white.opacity(0.08)
        case .ready, .saved:
            Color(red: 0.90, green: 0.97, blue: 0.91)
        }
    }

    private var borderColor: Color {
        switch status {
        case .failed:
            Color(red: 0.78, green: 0.28, blue: 0.18).opacity(0.35)
        case .notTracking:
            Color.white.opacity(0.10)
        case .ready, .saved:
            Color(red: 0.21, green: 0.55, blue: 0.28).opacity(0.28)
        }
    }
}

private struct ProjectRowView: View {
    let chart: Chart
    let previewMode: IChartChartPreviewMode
    let isSelected: Bool
    let canDuplicate: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: previewMode == .collapsed ? 3 : 10) {
                    rowText

                    if previewMode != .collapsed {
                        IChartLibraryChartPreview(chart: chart, mode: previewMode)
                    }
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .disabled(!canDuplicate)

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Chart actions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, previewMode == .collapsed ? 13 : 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        }
        .contextMenu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }

            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(!canDuplicate)

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chart.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.ink)
                .lineLimit(1)

            Text(rowSubtitle)
                .font(.subheadline)
                .foregroundStyle(IChartHomeBrand.ink.opacity(0.58))
                .lineLimit(1)
        }
    }

    private var rowSubtitle: String {
        let measureCount = chart.measures.count
        let measureText = measureCount == 1 ? "1 measure" : "\(measureCount) measures"

        return "\(chart.layoutStyle.displayText) · \(measureText)"
    }

    private var cardBackground: Color {
        isSelected ? IChartHomeBrand.blueSoft.opacity(0.82) : IChartHomeBrand.paper.opacity(0.92)
    }

    private var cardBorderColor: Color {
        isSelected ? IChartHomeBrand.blue.opacity(0.35) : IChartHomeBrand.ink.opacity(0.07)
    }
}

private struct IChartLibraryChartPreview: View {
    let chart: Chart
    let mode: IChartChartPreviewMode

    private var previewHeight: CGFloat {
        switch mode {
        case .collapsed:
            0
        case .quick:
            78
        case .large:
            174
        }
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 6),
                with: .color(IChartHomeBrand.paper)
            )

            drawSystems(in: rect.insetBy(dx: 14, dy: mode == .large ? 16 : 12), context: &context)

            context.stroke(
                Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6),
                with: .color(IChartHomeBrand.ink.opacity(0.08)),
                lineWidth: 1
            )
        }
        .frame(height: previewHeight)
        .background(IChartHomeBrand.paper.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private func drawSystems(in rect: CGRect, context: inout GraphicsContext) {
        let systemsToDraw = mode == .large ? 3 : 1
        let systemGap = rect.height / CGFloat(max(systemsToDraw, 1))

        for systemIndex in 0..<systemsToDraw {
            let y = rect.minY + CGFloat(systemIndex) * systemGap + systemGap * 0.42
            drawSystemLine(
                in: CGRect(x: rect.minX, y: y, width: rect.width, height: systemGap * 0.45),
                systemIndex: systemIndex,
                context: &context
            )
        }
    }

    private func drawSystemLine(
        in rect: CGRect,
        systemIndex: Int,
        context: inout GraphicsContext
    ) {
        let measuresPerSystem = min(max(chart.measures.count, 1), mode == .large ? 4 : 4)
        let measureWidth = rect.width / CGFloat(measuresPerSystem)
        let isSimple = chart.layoutStyle == .simpleChordSheet

        if !isSimple {
            var staffPath = Path()
            for index in 0..<5 {
                let y = rect.minY + CGFloat(index) * rect.height / 4
                staffPath.move(to: CGPoint(x: rect.minX, y: y))
                staffPath.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(staffPath, with: .color(IChartHomeBrand.ink.opacity(0.22)), lineWidth: 0.9)
        }

        var barPath = Path()
        for measureIndex in 0...measuresPerSystem {
            let x = rect.minX + CGFloat(measureIndex) * measureWidth
            barPath.move(to: CGPoint(x: x, y: rect.minY - (isSimple ? 8 : 0)))
            barPath.addLine(to: CGPoint(x: x, y: rect.maxY + (isSimple ? 8 : 0)))
        }
        context.stroke(barPath, with: .color(IChartHomeBrand.ink.opacity(0.72)), lineWidth: isSimple ? 1.4 : 1.0)

        if isSimple {
            drawSimpleChordMarks(in: rect, systemIndex: systemIndex, measureWidth: measureWidth, context: &context)
        } else {
            drawRhythmMarks(in: rect, systemIndex: systemIndex, measureWidth: measureWidth, context: &context)
        }
    }

    private func drawSimpleChordMarks(
        in rect: CGRect,
        systemIndex: Int,
        measureWidth: CGFloat,
        context: inout GraphicsContext
    ) {
        let startIndex = systemIndex * 4
        let measures = Array(chart.measures.dropFirst(startIndex).prefix(4))

        for (index, measure) in measures.enumerated() {
            guard let chord = measure.chordEvents.first else {
                continue
            }

            let x = rect.minX + CGFloat(index) * measureWidth + 10
            let y = rect.midY
            context.draw(
                Text(chord.symbol.displayText)
                    .font(.system(size: mode == .large ? 17 : 14, weight: .regular))
                    .foregroundStyle(IChartHomeBrand.ink),
                at: CGPoint(x: x, y: y),
                anchor: .leading
            )
        }
    }

    private func drawRhythmMarks(
        in rect: CGRect,
        systemIndex: Int,
        measureWidth: CGFloat,
        context: inout GraphicsContext
    ) {
        let startIndex = systemIndex * 4
        let measures = Array(chart.measures.dropFirst(startIndex).prefix(4))

        for (index, measure) in measures.enumerated() {
            let x = rect.minX + CGFloat(index) * measureWidth + measureWidth * 0.42
            let y = rect.midY
            let markHeight = rect.height * 0.42

            var stem = Path()
            stem.move(to: CGPoint(x: x, y: y - markHeight * 0.5))
            stem.addLine(to: CGPoint(x: x, y: y + markHeight * 0.5))
            context.stroke(stem, with: .color(IChartHomeBrand.ink.opacity(0.62)), lineWidth: 1)

            if !measure.chordEvents.isEmpty {
                context.draw(
                    Text(measure.chordEvents.first?.symbol.displayText ?? "")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(IChartHomeBrand.ink.opacity(0.70)),
                    at: CGPoint(x: rect.minX + CGFloat(index) * measureWidth + 8, y: rect.minY - 10),
                    anchor: .leading
                )
            }
        }
    }
}

private struct IChartLibraryBackground: View {
    let mode: IChartHomeAppearanceMode

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: baseColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: overlayColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
        }
    }

    private var baseColors: [Color] {
        switch mode {
        case .light:
            [
                IChartHomeBrand.paper,
                IChartHomeBrand.blueSoft,
                IChartHomeBrand.paperSecondary
            ]
        case .dark:
            [
                IChartHomeBrand.night,
                IChartHomeBrand.stage,
                Color(red: 0.08, green: 0.11, blue: 0.13)
            ]
        }
    }

    private var overlayColors: [Color] {
        switch mode {
        case .light:
            [
                IChartHomeBrand.night.opacity(0.94),
                IChartHomeBrand.night.opacity(0.58),
                IChartHomeBrand.night.opacity(0)
            ]
        case .dark:
            [
                Color.black.opacity(0.48),
                IChartHomeBrand.logoBlue.opacity(0.08),
                Color.black.opacity(0)
            ]
        }
    }
}
