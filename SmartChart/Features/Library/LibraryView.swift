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

private enum IChartChartsWorkspaceMode: String, CaseIterable, Identifiable {
    case charts
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charts:
            return "Charts"
        case .projects:
            return "Projects"
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
    @AppStorage("iChartChartsWorkspaceMode") private var chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
    @AppStorage("iChartHasSeenAccountLanding") private var hasSeenAccountLanding = false
    @AppStorage("iChartUserEmail") private var userEmail = ""
    @AppStorage("iChartUserPhone") private var userPhone = ""
    @AppStorage("iChartUserAddress") private var userAddress = ""
    @State private var logoVariant = IChartLogoVariant.homeScreenTrialDefault
    @State private var selectedHomeTab: IChartHomeTab = .charts
    @State private var selectedHelpTopic: IChartHelpTopic?
    @State private var showingLayoutPicker = false
    @State private var pendingProjectForNewChart: ChartProject.ID?
    @State private var showingAccountLanding = false
    @State private var showingCreateProject = false
    @State private var renameRequest: ChartRenameRequest?
    @State private var deleteRequest: ChartDeleteRequest?
    @State private var renameProjectRequest: ChartProjectRenameRequest?
    @State private var addChartsRequest: ChartProjectAddChartsRequest?
    @State private var duplicateVariantRequest: ChartProjectDuplicateVariantRequest?

    init(onOpenChart: @escaping (Chart.ID, EditorCanvasMode) -> Void) {
        self.onOpenChart = onOpenChart
    }

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

    private var activeChartPreviewMode: IChartChartPreviewMode {
        store.isChartEditingLockedByCurrentPlan ? .collapsed : chartPreviewMode
    }

    private var chartPreviewModeBinding: Binding<IChartChartPreviewMode> {
        Binding(
            get: { chartPreviewMode },
            set: { chartPreviewModeRawValue = $0.rawValue }
        )
    }

    private var chartsWorkspaceMode: IChartChartsWorkspaceMode {
        IChartChartsWorkspaceMode(rawValue: chartsWorkspaceModeRawValue) ?? .charts
    }

    private var chartsWorkspaceModeBinding: Binding<IChartChartsWorkspaceMode> {
        Binding(
            get: { chartsWorkspaceMode },
            set: { chartsWorkspaceModeRawValue = $0.rawValue }
        )
    }

    private var chartUsageText: String? {
        guard let limit = store.entitlements.localChartLimit else {
            return nil
        }

        guard store.canCreateChart else {
            return store.chartCapacityText
        }

        return "\(min(store.charts.count, limit)) of \(limit) Basic charts used"
    }

    private var chartEditingLockMessage: String {
        if store.localChartOverflowCount == 1 {
            return "Delete 1 local chart to edit in Basic."
        }

        return "Delete \(store.localChartOverflowCount) local charts to edit in Basic."
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
            updateAccountLandingPresentation()
        }
        .onChange(of: authStore.state) { _, state in
            cloudSyncStore.authStateChanged(state)
            if !hasSeenAccountLanding {
                updateAccountLandingPresentation()
            }
        }
        .onChange(of: store.entitlements) { _, _ in
            cloudSyncStore.authStateChanged(authStore.state)
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
        .fullScreenCover(isPresented: $showingAccountLanding) {
            IChartFirstRunAccountLandingView(
                authStore: authStore,
                theme: homeTheme,
                onContinue: completeFirstRunAccountLanding
            )
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingCreateProject) {
            IChartProjectFormSheet(
                title: "New Project",
                initialTitle: "",
                saveTitle: "Create",
                theme: homeTheme
            ) { title in
                store.createProject(title: title)
            }
        }
        .sheet(item: $renameRequest) { request in
            RenameChartSheetView(request: request) { chartID, title in
                store.renameChart(id: chartID, to: title)
            }
        }
        .sheet(item: $renameProjectRequest) { request in
            IChartProjectFormSheet(
                title: "Rename Project",
                initialTitle: request.currentTitle,
                saveTitle: "Save",
                theme: homeTheme
            ) { title in
                store.renameProject(id: request.projectID, to: title)
            }
        }
        .sheet(item: $addChartsRequest) { request in
            IChartProjectAddChartsSheet(
                request: request,
                charts: store.charts,
                theme: homeTheme
            ) { chartID, projectID in
                store.addChartToProject(chartID: chartID, projectID: projectID)
            }
        }
        .sheet(item: $duplicateVariantRequest) { request in
            IChartProjectDuplicateVariantSheet(
                request: request,
                theme: homeTheme
            ) { chartID, projectID, title, transpositionView in
                store.duplicateChart(
                    id: chartID,
                    title: title,
                    transpositionView: transpositionView,
                    projectID: projectID
                )
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
                IChartChartsWorkspaceModePicker(selection: chartsWorkspaceModeBinding, theme: homeTheme)

                switch chartsWorkspaceMode {
                case .charts:
                    chartsListHomeContent
                case .projects:
                    chartProjectsHomeContent
                }
            }
        }
    }

    private var chartsListHomeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            IChartNewChartControl(
                chartUsageText: chartUsageText,
                canCreateChart: store.canCreateChart,
                theme: homeTheme,
                onCreateChart: {
                    pendingProjectForNewChart = nil
                    showingLayoutPicker = true
                }
            )

            if store.requiresLocalChartPruningForCurrentPlan {
                IChartChartConsolidationNotice(
                    overflowCount: store.localChartOverflowCount,
                    theme: homeTheme
                )
            }

            chartListSection
        }
    }

    private var chartProjectsHomeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.canUse(.projects) {
                IChartProjectCreateControl(
                    projectCount: store.projects.count,
                    theme: homeTheme,
                    onCreateProject: {
                        showingCreateProject = true
                    }
                )

                if store.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects Yet",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a project to keep every chart for the same song together.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .foregroundStyle(homeTheme.workspaceTitle)
                    .background(homeTheme.emptyStateBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.projects) { project in
                            IChartProjectCard(
                                project: project,
                                charts: store.charts(in: project),
                                canCreateChart: store.canCreateChart,
                                canOpenCharts: store.canOpenChartsForEditing,
                                availableCharts: store.charts,
                                chartEditingLockMessage: chartEditingLockMessage,
                                theme: homeTheme,
                                onOpenChart: { chartID in
                                    openChartIfAllowed(chartID, initialCanvasMode: .browse)
                                },
                                onNewChart: { projectID in
                                    pendingProjectForNewChart = projectID
                                    showingLayoutPicker = true
                                },
                                onAddExisting: { project in
                                    addChartsRequest = ChartProjectAddChartsRequest(project: project)
                                },
                                onDuplicateVariant: { chart, project in
                                    duplicateVariantRequest = ChartProjectDuplicateVariantRequest(
                                        project: project,
                                        chart: chart
                                    )
                                },
                                onRemoveChart: { chartID, projectID in
                                    store.removeChartFromProject(chartID: chartID, projectID: projectID)
                                },
                                onRenameProject: { project in
                                    renameProjectRequest = ChartProjectRenameRequest(project: project)
                                },
                                onDeleteProject: { projectID in
                                    store.deleteProject(id: projectID)
                                }
                            )
                        }
                    }
                }
            } else {
                IChartHomePanel(
                    title: "Projects",
                    systemImageName: "folder.badge.plus",
                    theme: homeTheme
                ) {
                    IChartLockedFeatureView(
                        title: "Projects require Pro",
                        message: "Upgrade to Pro to group every chart for the same song, duplicate section variants, and keep alternate keys together.",
                        systemImageName: "lock.folder",
                        theme: homeTheme
                    )
                }
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
                if store.canUse(.forums) {
                    ContentUnavailableView(
                        "No Forum Posts",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    IChartLockedFeatureView(
                        title: "Forums require Pro",
                        message: "Upgrade to Pro to join iChart Forums.",
                        systemImageName: "lock.icloud",
                        theme: homeTheme
                    )
                }
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
                    }
                }

                IChartHomePanel(
                    title: "Plan",
                    systemImageName: store.subscriptionState.systemImageName,
                    theme: homeTheme
                ) {
                    IChartPlanSettings(
                        store: store,
                        theme: homeTheme,
                        onSelectSubscriptionState: apply(subscriptionPreview:)
                    )
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
                        theme: homeTheme,
                        authState: authStore.state,
                        isSaving: authStore.isWorking,
                        onSaveProfile: {
                            Task {
                                await authStore.saveProfile(
                                    email: userEmail,
                                    phone: userPhone,
                                    mailingAddress: userAddress
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

    private var chartListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.canOpenChartsForEditing {
                HStack(alignment: .center, spacing: 16) {
                    Spacer()

                    IChartPreviewModePicker(selection: chartPreviewModeBinding, theme: homeTheme)
                }
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
                            previewMode: activeChartPreviewMode,
                            isSelected: store.selectedChartID == chart.id,
                            canDuplicate: store.canCreateChart,
                            canOpenForEditing: store.canOpenChartsForEditing,
                            lockMessage: chartEditingLockMessage,
                            onOpen: {
                                openChartIfAllowed(chart.id, initialCanvasMode: .browse)
                            },
                            onRename: {
                                renameRequest = ChartRenameRequest(chart: chart)
                            },
                            onDuplicate: {
                                store.duplicateChart(id: chart.id)
                            },
                            onRemoveLocal: {
                                store.pruneLocalChartForCurrentPlan(id: chart.id)
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

    private func openChartIfAllowed(_ chartID: Chart.ID, initialCanvasMode: EditorCanvasMode) {
        guard store.canOpenChartsForEditing else {
            store.selectedChartID = nil
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedHomeTab = .charts
                chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
            }
            return
        }

        onOpenChart(chartID, initialCanvasMode)
    }

    private func createNewChart(layoutStyle: ChartLayoutStyle) {
        let targetProjectID = pendingProjectForNewChart
        pendingProjectForNewChart = nil

        guard store.createBlankChart(layoutStyle: layoutStyle, projectID: targetProjectID),
              let chartID = store.selectedChartID else {
            return
        }

        onOpenChart(chartID, .browse)
    }

    private func updateAccountLandingPresentation() {
        guard !hasSeenAccountLanding,
              !showingAccountLanding,
              authStore.state.shouldPresentFirstRunAccountLanding else {
            return
        }

        showingAccountLanding = true
    }

    private func completeFirstRunAccountLanding() {
        guard authStore.state.isVerifiedSignedIn else {
            return
        }

        hasSeenAccountLanding = true
        showingAccountLanding = false
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
    }

    private func apply(subscriptionPreview: IChartSubscriptionEntitlement) {
        withAnimation(.easeInOut(duration: 0.18)) {
            store.applySubscriptionState(subscriptionPreview)
        }
        cloudSyncStore.authStateChanged(authStore.state)
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

private struct ChartProjectRenameRequest: Identifiable, Hashable {
    let projectID: ChartProject.ID
    let currentTitle: String

    var id: ChartProject.ID { projectID }

    init(project: ChartProject) {
        projectID = project.id
        currentTitle = project.title
    }
}

private struct ChartProjectAddChartsRequest: Identifiable, Hashable {
    let project: ChartProject

    var id: ChartProject.ID { project.id }
}

private struct ChartProjectDuplicateVariantRequest: Identifiable, Hashable {
    let project: ChartProject
    let chart: Chart

    var id: String {
        "\(project.id.uuidString)-\(chart.id.uuidString)"
    }
}

private struct RenameChartSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChartRenameRequest
    let onSave: (Chart.ID, String) -> Void
    @State private var title: String
    @FocusState private var isTitleFocused: Bool

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
                    HStack(spacing: 10) {
                        TextField("Chart title", text: $title)
                            .focused($isTitleFocused)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(save)

                        IChartKeyboardFocusButton(
                            accessibilityLabel: "Open keyboard for chart title"
                        ) {
                            isTitleFocused = true
                        }
                    }
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
        .task {
            isTitleFocused = true
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

private struct IChartProjectFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initialTitle: String
    let saveTitle: String
    let theme: IChartHomeTheme
    let onSave: (String) -> Void
    @State private var projectTitle: String
    @FocusState private var isProjectTitleFocused: Bool

    init(
        title: String,
        initialTitle: String,
        saveTitle: String,
        theme: IChartHomeTheme,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.saveTitle = saveTitle
        self.theme = theme
        self.onSave = onSave
        _projectTitle = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        TextField("Song or project title", text: $projectTitle)
                            .focused($isProjectTitleFocused)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(save)

                        IChartKeyboardFocusButton(
                            accessibilityLabel: "Open keyboard for project title"
                        ) {
                            isProjectTitleFocused = true
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        save()
                    }
                    .disabled(sanitizedTitle.isEmpty)
                }
            }
        }
        .task {
            isProjectTitleFocused = true
        }
    }

    private var sanitizedTitle: String {
        projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !sanitizedTitle.isEmpty else {
            return
        }

        onSave(sanitizedTitle)
        dismiss()
    }
}

private struct IChartProjectAddChartsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChartProjectAddChartsRequest
    let charts: [Chart]
    let theme: IChartHomeTheme
    let onAddChart: (Chart.ID, ChartProject.ID) -> Void

    private var availableCharts: [Chart] {
        charts.filter { !request.project.chartIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableCharts.isEmpty {
                    ContentUnavailableView(
                        "No Charts To Add",
                        systemImage: "doc.badge.plus",
                        description: Text("Every local chart is already in this project.")
                    )
                    .padding(.vertical, 32)
                } else {
                    ForEach(availableCharts) { chart in
                        Button {
                            onAddChart(chart.id, request.project.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: chart.layoutStyle.systemImageName)
                                    .foregroundStyle(IChartHomeBrand.blue)
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chart.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(chart.librarySummaryText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)

                                Image(systemName: "plus.circle")
                                    .foregroundStyle(IChartHomeBrand.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add To \(request.project.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct IChartProjectDuplicateVariantSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChartProjectDuplicateVariantRequest
    let theme: IChartHomeTheme
    let onSave: (Chart.ID, ChartProject.ID, String, TranspositionView) -> Chart.ID?
    @State private var title: String
    @State private var selectedTranspositionView: TranspositionView
    @FocusState private var isTitleFocused: Bool

    init(
        request: ChartProjectDuplicateVariantRequest,
        theme: IChartHomeTheme,
        onSave: @escaping (Chart.ID, ChartProject.ID, String, TranspositionView) -> Chart.ID?
    ) {
        self.request = request
        self.theme = theme
        self.onSave = onSave
        _title = State(initialValue: "\(request.chart.title) Copy")
        _selectedTranspositionView = State(initialValue: request.chart.defaultTranspositionView)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.chart.title)
                            .font(.headline.weight(.semibold))

                        Text(request.chart.librarySummaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Variant Title")
                            .font(.headline)

                        HStack(spacing: 10) {
                            TextField("Horn section chart", text: $title)
                                .focused($isTitleFocused)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            IChartKeyboardFocusButton(
                                accessibilityLabel: "Open keyboard for variant title"
                            ) {
                                isTitleFocused = true
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instrument View")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                            ForEach(TranspositionView.instrumentOptions) { view in
                                Button {
                                    selectedTranspositionView = view
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(view.displayText)
                                            .font(.subheadline.weight(.semibold))

                                        Text(view.intervalDisplayText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(selectedTranspositionView == view ? IChartHomeBrand.blue : .secondary.opacity(0.3))
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Duplicate Variant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard onSave(
                            request.chart.id,
                            request.project.id,
                            title,
                            selectedTranspositionView
                        ) != nil else {
                            return
                        }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task {
            isTitleFocused = true
        }
    }
}

private struct IChartChartConsolidationNotice: View {
    let overflowCount: Int
    let theme: IChartHomeTheme

    var body: some View {
        IChartHomePanel(
            title: "Consolidate Charts",
            systemImageName: "trash",
            theme: theme
        ) {
            Text("Delete \(overflowCount) local chart\(overflowCount == 1 ? "" : "s") from the list below to continue in Basic. Editing unlocks when 3 charts remain. Cloud backups stay available through the Pro grace period.")
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IChartLockedFeatureView: View {
    let title: String
    let message: String
    let systemImageName: String
    let theme: IChartHomeTheme

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImageName,
            description: Text(message)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .foregroundStyle(theme.panelSecondary)
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

private struct IChartFirstRunAccountLandingView: View {
    @ObservedObject var authStore: IChartAuthStore
    let theme: IChartHomeTheme
    let onContinue: () -> Void
    @State private var isLaunchAnimationVisible = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        VStack(alignment: .center, spacing: 20) {
                            VStack(alignment: .center, spacing: 10) {
                                Label("Welcome to iChart", systemImage: "music.note.list")
                                    .font(.largeTitle.weight(.semibold))
                                    .foregroundStyle(theme.panelTitle)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text("Create your account to keep profile, recovery, and subscription access tied to you from the start.")
                                    .font(.body)
                                    .foregroundStyle(theme.panelSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 520)
                            }

                            IChartHomePanel(
                                title: "Account",
                                systemImageName: "person.crop.circle.badge.plus",
                                theme: theme
                            ) {
                                IChartAccountSettings(
                                    authStore: authStore,
                                    theme: theme,
                                    requiresNameForSignup: true,
                                    showsSignedInActions: false
                                )
                            }

                            if authStore.state.isVerifiedSignedIn {
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        isLaunchAnimationVisible = true
                                    }
                                } label: {
                                    Label("Continue", systemImage: "arrow.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(IChartHomeBrand.blue)
                                .disabled(isLaunchAnimationVisible)
                            }
                        }
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 44)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
            .background(IChartLibraryBackground(mode: theme.mode).ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(true)
        }
        .overlay {
            if isLaunchAnimationVisible {
                IChartLaunchScreenView(
                    capturedHandwritingSample: IChartLaunchHandwritingSample.bundledCanonicalLaunchSample(),
                    onFinished: onContinue
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
    }
}

private struct IChartKeyboardFocusButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "keyboard")
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
    }
}

private enum IChartAccountInputField: Hashable {
    case firstName
    case lastName
    case email
    case password
    case newPassword
}

private struct IChartAccountSettings: View {
    @ObservedObject var authStore: IChartAuthStore
    let theme: IChartHomeTheme
    var requiresNameForSignup = false
    var showsSignedInActions = true
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @FocusState private var focusedField: IChartAccountInputField?

    private var canSubmitCredentials: Bool {
        !trimmed(email).isEmpty
            && password.count >= 8
            && !authStore.isWorking
    }

    private var canCreateAccount: Bool {
        canSubmitCredentials
            && (!requiresNameForSignup || (!trimmed(firstName).isEmpty && !trimmed(lastName).isEmpty))
    }

    private var canSignIn: Bool {
        canSubmitCredentials
    }

    private var canRequestPasswordReset: Bool {
        !trimmed(email).isEmpty
            && !authStore.isWorking
    }

    private var canUpdateRecoveryPassword: Bool {
        newPassword.count >= 8 && !authStore.isWorking
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
            case .temporarilyOffline:
                offlineRow
            case .pendingEmailVerification:
                verificationRow
            case .passwordRecovery:
                passwordRecoveryRow
            case .signedIn where showsSignedInActions:
                signedInRow
            case .signedIn:
                EmptyView()
            }

            statusFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: authStore.state.statusText) {
            focusDefaultInputIfNeeded()
        }
    }

    private var credentialsForm: some View {
        VStack(spacing: 10) {
            if requiresNameForSignup {
                IChartAccountTextField(
                    title: "First Name",
                    placeholder: "First name",
                    text: $firstName,
                    systemImageName: "person",
                    keyboardType: .default,
                    theme: theme,
                    focusedField: $focusedField,
                    field: .firstName,
                    textInputAutocapitalization: .words,
                    autocorrectionDisabled: false
                )

                IChartAccountTextField(
                    title: "Last Name",
                    placeholder: "Last name",
                    text: $lastName,
                    systemImageName: "person.text.rectangle",
                    keyboardType: .default,
                    theme: theme,
                    focusedField: $focusedField,
                    field: .lastName,
                    textInputAutocapitalization: .words,
                    autocorrectionDisabled: false
                )
            }

            IChartAccountTextField(
                title: "Email",
                placeholder: "name@example.com",
                text: $email,
                systemImageName: "envelope",
                keyboardType: .emailAddress,
                theme: theme,
                focusedField: $focusedField,
                field: .email
            )

            IChartAccountSecureField(
                title: "Password",
                placeholder: "8 characters minimum",
                text: $password,
                systemImageName: "lock",
                theme: theme,
                focusedField: $focusedField,
                field: .password
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await authStore.createAccount(
                        email: email,
                        password: password,
                        firstName: firstName,
                        lastName: lastName
                    )
                }
            } label: {
                Label("Create Account", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(!canCreateAccount)

            Button {
                Task {
                    await authStore.signIn(email: email, password: password)
                }
            } label: {
                Label("Sign In", systemImage: "person.crop.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!canSignIn)
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

    private var passwordRecoveryRow: some View {
        VStack(spacing: 10) {
            IChartAccountSecureField(
                title: "New Password",
                placeholder: "8 characters minimum",
                text: $newPassword,
                systemImageName: "key",
                theme: theme,
                focusedField: $focusedField,
                field: .newPassword
            )

            HStack(spacing: 10) {
                Button {
                    Task {
                        await authStore.updatePassword(newPassword)
                        newPassword = ""
                    }
                } label: {
                    Label("Save Password", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .tint(IChartHomeBrand.blue)
                .disabled(!canUpdateRecoveryPassword)

                Button {
                    Task {
                        await authStore.dismissPasswordRecovery()
                        newPassword = ""
                    }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(authStore.isWorking)
            }
        }
    }

    private var offlineRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await authStore.refreshSession()
                }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
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
        case .temporarilyOffline:
            return "wifi.exclamationmark"
        case .pendingEmailVerification:
            return "envelope.badge"
        case .passwordRecovery:
            return "key"
        case .signedIn:
            return "checkmark.seal"
        }
    }

    private var detailText: String {
        switch authStore.state {
        case .unconfigured:
            return "This build needs Supabase configuration."
        case .signedOut:
            return "Create an account or sign in to manage your profile and subscription."
        case .temporarilyOffline(let session):
            if let email = session.email {
                return "Using local charts for \(email). Reconnect to back up."
            }

            return "Using local charts. Reconnect to back up."
        case .pendingEmailVerification(let email):
            return "Open the verification link sent to \(email), then sign in."
        case .passwordRecovery(let session):
            if let email = session.email {
                return "Enter a new password for \(email)."
            }

            return "Enter a new password to finish account recovery."
        case .signedIn(let session):
            return session.email ?? "Signed in to iChart."
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func focusDefaultInputIfNeeded() {
        guard !authStore.isWorking else {
            return
        }

        switch authStore.state {
        case .signedOut:
            focusedField = requiresNameForSignup ? .firstName : .email
        case .passwordRecovery:
            focusedField = .newPassword
        case .unconfigured, .temporarilyOffline, .pendingEmailVerification, .signedIn:
            break
        }
    }
}

private extension IChartAuthState {
    var isVerifiedSignedIn: Bool {
        guard case .signedIn(let session) = self else {
            return false
        }

        return session.isEmailVerified
    }

    var shouldPresentFirstRunAccountLanding: Bool {
        switch self {
        case .signedOut, .pendingEmailVerification, .signedIn:
            return true
        case .unconfigured, .temporarilyOffline, .passwordRecovery:
            return false
        }
    }
}

private enum IChartDebugPlanPreview: String, CaseIterable, Identifiable {
    case basic
    case pro
    case grace
    case expired
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic:
            return "Basic"
        case .pro:
            return "Pro"
        case .grace:
            return "Grace"
        case .expired:
            return "Expired"
        case .unavailable:
            return "Offline"
        }
    }

    static func preview(for subscription: IChartSubscriptionEntitlement) -> IChartDebugPlanPreview {
        switch subscription.status {
        case .basic:
            return .basic
        case .proActive, .legacyLocalPro:
            return .pro
        case .proGrace:
            return .grace
        case .proExpired:
            return .expired
        case .unavailable:
            return .unavailable
        }
    }

    func subscriptionState(now: Date = Date()) -> IChartSubscriptionEntitlement {
        switch self {
        case .basic:
            return .basic
        case .pro:
            return .activePro(verifiedAt: now)
        case .grace:
            let graceEndsAt = Calendar.current.date(
                byAdding: .day,
                value: 30,
                to: now
            ) ?? now.addingTimeInterval(30 * 24 * 60 * 60)
            return .proGrace(graceEndsAt: graceEndsAt, verifiedAt: now)
        case .expired:
            return .proExpired(verifiedAt: now)
        case .unavailable:
            return .unavailable
        }
    }
}

private struct IChartPlanSettings: View {
    @ObservedObject var store: ChartLibraryStore
    let theme: IChartHomeTheme
    let onSelectSubscriptionState: (IChartSubscriptionEntitlement) -> Void

    #if DEBUG || targetEnvironment(simulator)
    @State private var debugPreview: IChartDebugPlanPreview = .basic
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            planHeader

            VStack(spacing: 0) {
                IChartSettingsRow(
                    title: "Local Charts",
                    value: localChartCapacityValue,
                    systemImageName: "doc.on.doc",
                    theme: theme
                )

                planDivider

                IChartSettingsRow(
                    title: "Cloud Backup",
                    value: store.subscriptionState.cloudAccessText,
                    systemImageName: "icloud.and.arrow.up",
                    theme: theme
                )

                planDivider

                IChartSettingsRow(
                    title: "Forums",
                    value: store.subscriptionState.forumsAccessText,
                    systemImageName: "bubble.left.and.bubble.right",
                    theme: theme
                )

                if let graceEndsAt = store.subscriptionState.graceEndsAt {
                    planDivider

                    IChartSettingsRow(
                        title: "Grace Ends",
                        value: graceEndsAt.formatted(date: .abbreviated, time: .omitted),
                        systemImageName: "calendar.badge.clock",
                        theme: theme
                    )
                }
            }

            if store.requiresLocalChartPruningForCurrentPlan {
                Text("Choose \(store.localChartOverflowCount) local chart\(store.localChartOverflowCount == 1 ? "" : "s") to remove from the Charts tab before Basic can open charts for editing or create new charts.")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if DEBUG || targetEnvironment(simulator)
            debugControls
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if DEBUG || targetEnvironment(simulator)
        .onAppear {
            debugPreview = IChartDebugPlanPreview.preview(for: store.subscriptionState)
        }
        .onChange(of: store.entitlements.subscription) { _, subscription in
            let nextPreview = IChartDebugPlanPreview.preview(for: subscription)
            if debugPreview != nextPreview {
                debugPreview = nextPreview
            }
        }
        #endif
    }

    private var planHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: store.subscriptionState.systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(statusTint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.subscriptionState.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)

                Text(store.subscriptionState.detailText)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(store.subscriptionState.badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusTint.opacity(theme.isDark ? 0.18 : 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var planDivider: some View {
        Divider()
            .overlay(theme.panelBorder)
            .padding(.leading, 44)
    }

    private var localChartCapacityValue: String {
        guard let limit = store.localChartLimit else {
            return "Unlimited"
        }

        return "\(min(store.charts.count, limit)) of \(limit) used"
    }

    private var statusTint: Color {
        switch store.subscriptionState.status {
        case .proActive:
            return Color(red: 0.16, green: 0.48, blue: 0.24)
        case .proGrace:
            return Color(red: 0.76, green: 0.48, blue: 0.12)
        case .proExpired:
            return Color(red: 0.72, green: 0.18, blue: 0.12)
        case .unavailable:
            return Color(red: 0.48, green: 0.48, blue: 0.50)
        case .basic, .legacyLocalPro:
            return IChartHomeBrand.blue
        }
    }

    #if DEBUG || targetEnvironment(simulator)
    private var debugControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(theme.panelBorder)

            Text("Plan Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            Picker("Plan Preview", selection: $debugPreview) {
                ForEach(IChartDebugPlanPreview.allCases) { preview in
                    Text(preview.title).tag(preview)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: debugPreview) { _, preview in
                onSelectSubscriptionState(preview.subscriptionState())
            }

            Text("Simulator control for StoreKit/Supabase entitlement QA. Production authority will come from trusted subscription state.")
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif
}

private struct IChartCloudSyncSettings: View {
    @ObservedObject var syncStore: ChartCloudSyncStore
    let theme: IChartHomeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: syncStore.state.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(statusTint)
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

            if let lastSyncAttemptAt = syncStore.lastSyncAttemptAt,
               shouldShowLastChecked {
                IChartSettingsRow(
                    title: "Last Checked",
                    value: lastSyncAttemptAt.formatted(date: .omitted, time: .shortened),
                    systemImageName: "arrow.triangle.2.circlepath",
                    theme: theme
                )
            }

            Button {
                syncStore.syncNow()
            } label: {
                Label(syncStore.state.manualSyncTitle, systemImage: syncStore.state.manualSyncSystemImageName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(statusTint)
            .disabled(!canRunManualSync)
            .accessibilityHint(syncStore.state.manualSyncDisabledReason ?? "")

            if let disabledReason = disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canRunManualSync: Bool {
        syncStore.state.allowsManualSync && !syncStore.isWorking
    }

    private var disabledReason: String? {
        guard !syncStore.isWorking else {
            return nil
        }

        return syncStore.state.manualSyncDisabledReason
    }

    private var shouldShowLastChecked: Bool {
        switch syncStore.state {
        case .offline, .failed:
            return true
        case .unconfigured, .signedOut, .requiresPro, .syncing, .synced:
            return false
        }
    }

    private var statusTint: Color {
        switch syncStore.state {
        case .synced:
            return Color(red: 0.16, green: 0.48, blue: 0.24)
        case .offline:
            return Color(red: 0.76, green: 0.48, blue: 0.12)
        case .failed:
            return Color(red: 0.72, green: 0.18, blue: 0.12)
        case .requiresPro:
            return Color(red: 0.62, green: 0.40, blue: 0.10)
        case .syncing, .signedOut, .unconfigured:
            return IChartHomeBrand.blue
        }
    }
}

private struct IChartAccountTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImageName: String
    let keyboardType: UIKeyboardType
    let theme: IChartHomeTheme
    let focusedField: FocusState<IChartAccountInputField?>.Binding
    let field: IChartAccountInputField
    var textInputAutocapitalization: TextInputAutocapitalization = .never
    var autocorrectionDisabled = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 104, alignment: .leading)

            TextField(placeholder, text: $text)
                .focused(focusedField, equals: field)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(textInputAutocapitalization)
                .autocorrectionDisabled(autocorrectionDisabled)
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

            IChartKeyboardFocusButton(
                accessibilityLabel: "Open keyboard for \(title)"
            ) {
                focusedField.wrappedValue = field
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
    let focusedField: FocusState<IChartAccountInputField?>.Binding
    let field: IChartAccountInputField

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 104, alignment: .leading)

            SecureField(placeholder, text: $text)
                .focused(focusedField, equals: field)
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

            IChartKeyboardFocusButton(
                accessibilityLabel: "Open keyboard for \(title)"
            ) {
                focusedField.wrappedValue = field
            }
        }
    }
}

private struct IChartUserInfoSettings: View {
    @Binding var email: String
    @Binding var phone: String
    @Binding var address: String
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
                keyboardType: .emailAddress,
                theme: theme
            )

            settingsDivider

            IChartSettingsTextFieldRow(
                title: "Phone",
                placeholder: "(555) 555-5555",
                text: $phone,
                systemImageName: "phone",
                keyboardType: .phonePad,
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
    var keyboardType: UIKeyboardType = .default
    var isMultiline = false
    let theme: IChartHomeTheme
    @FocusState private var isFocused: Bool

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
                .focused($isFocused)
                .keyboardType(keyboardType)
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

            IChartKeyboardFocusButton(
                accessibilityLabel: "Open keyboard for \(title)"
            ) {
                isFocused = true
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
    let chartUsageText: String?
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

            if let chartUsageText {
                Text(chartUsageText)
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

private struct IChartChartsWorkspaceModePicker: View {
    @Binding var selection: IChartChartsWorkspaceMode
    let theme: IChartHomeTheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(IChartChartsWorkspaceMode.allCases) { mode in
                let isSelected = selection == mode

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textColor(isSelected: isSelected))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(IChartHomeBrand.paper.opacity(0.95))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(3)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.isDark ? Color.white.opacity(0.16) : IChartHomeBrand.ink.opacity(0.08), lineWidth: 1)
        }
    }

    private func textColor(isSelected: Bool) -> Color {
        if isSelected {
            return IChartHomeBrand.ink
        }

        return theme.isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink.opacity(0.72)
    }
}

private struct IChartProjectCreateControl: View {
    let projectCount: Int
    let theme: IChartHomeTheme
    let onCreateProject: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(projectCount == 1 ? "1 project" : "\(projectCount) projects")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.workspaceTitle)

                Text("Group every chart for the same song.")
                    .font(.caption)
                    .foregroundStyle(theme.workspaceSecondary)
            }

            Spacer(minLength: 16)

            Button(action: onCreateProject) {
                Label("New Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
        }
        .padding(16)
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct IChartProjectCard: View {
    let project: ChartProject
    let charts: [Chart]
    let canCreateChart: Bool
    let canOpenCharts: Bool
    let availableCharts: [Chart]
    let chartEditingLockMessage: String
    let theme: IChartHomeTheme
    let onOpenChart: (Chart.ID) -> Void
    let onNewChart: (ChartProject.ID) -> Void
    let onAddExisting: (ChartProject) -> Void
    let onDuplicateVariant: (Chart, ChartProject) -> Void
    let onRemoveChart: (Chart.ID, ChartProject.ID) -> Void
    let onRenameProject: (ChartProject) -> Void
    let onDeleteProject: (ChartProject.ID) -> Void

    var body: some View {
        IChartHomePanel(
            title: project.title,
            systemImageName: "folder",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label(project.chartCountText, systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.panelSecondary)

                    Spacer(minLength: 12)

                    projectMenu
                }

                if charts.isEmpty {
                    Text("Add an existing chart or create the first chart for this song.")
                        .font(.subheadline)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 8) {
                        ForEach(charts) { chart in
                            IChartProjectChartRow(
                                chart: chart,
                                theme: theme,
                                canDuplicate: canCreateChart,
                                canOpenForEditing: canOpenCharts,
                                lockMessage: chartEditingLockMessage,
                                onOpen: {
                                    onOpenChart(chart.id)
                                },
                                onDuplicateVariant: {
                                    onDuplicateVariant(chart, project)
                                },
                                onRemove: {
                                    onRemoveChart(chart.id, project.id)
                                }
                            )
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        onAddExisting(project)
                    } label: {
                        Label("Add Existing", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(availableCharts.isEmpty)

                    Button {
                        onNewChart(project.id)
                    } label: {
                        Label("New Chart", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(IChartHomeBrand.blue)
                    .disabled(!canCreateChart)
                }
            }
        }
    }

    private var projectMenu: some View {
        Menu {
            Button {
                onRenameProject(project)
            } label: {
                Label("Rename Project", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDeleteProject(project.id)
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.panelSecondary)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Project actions")
    }
}

private struct IChartProjectChartRow: View {
    let chart: Chart
    let theme: IChartHomeTheme
    let canDuplicate: Bool
    let canOpenForEditing: Bool
    let lockMessage: String
    let onOpen: () -> Void
    let onDuplicateVariant: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chart.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)
                        .lineLimit(1)

                    Text(chart.librarySummaryText)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .lineLimit(1)

                    if !canOpenForEditing {
                        Label(lockMessage, systemImage: "lock.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(IChartHomeBrand.blue)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpenForEditing)
            .accessibilityHint(canOpenForEditing ? "" : lockMessage)

            Menu {
                Button(action: onDuplicateVariant) {
                    Label("Duplicate Variant", systemImage: "plus.square.on.square")
                }
                .disabled(!canDuplicate)

                Button(role: .destructive, action: onRemove) {
                    Label("Remove From Project", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Project chart actions")
        }
        .padding(12)
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    let canOpenForEditing: Bool
    let lockMessage: String
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onRemoveLocal: () -> Void
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
            .disabled(!canOpenForEditing)
            .accessibilityHint(canOpenForEditing ? "" : lockMessage)

            rowActionControl
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
            if canOpenForEditing {
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
            } else {
                Button(role: .destructive, action: onRemoveLocal) {
                    Label("Delete Local", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var rowActionControl: some View {
        if canOpenForEditing {
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
        } else {
            Button(role: .destructive, action: onRemoveLocal) {
                Label("Delete Local", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Delete local chart")
            .accessibilityHint(lockMessage)
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

            if !canOpenForEditing {
                Label(lockMessage, systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
                    .lineLimit(1)
            }
        }
    }

    private var rowSubtitle: String {
        chart.librarySummaryText
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
