import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var store: ChartLibraryStore
    @State private var projectPath: [ProjectRoute] = []
    @State private var selectedTab: AppTab = .projects

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $projectPath) {
                LibraryView { chartID, initialCanvasMode in
                    store.selectedChartID = chartID
                    projectPath = [.chart(chartID, initialCanvasMode)]
                }
                .navigationTitle("Projects")
                .navigationDestination(for: ProjectRoute.self) { route in
                    switch route {
                    case .chart(let chartID, let initialCanvasMode):
                        if let chart = chartBinding(for: chartID) {
                            EditorView(chart: chart, initialCanvasMode: initialCanvasMode)
                        } else {
                            ContentUnavailableView(
                                "Chart Not Found",
                                systemImage: "music.quarternote.3",
                                description: Text("This chart is no longer available in the library.")
                            )
                        }
                    }
                }
            }
            .tabItem {
                Label("Projects", systemImage: "music.note.list")
            }
            .tag(AppTab.projects)

            NavigationStack {
                ContentUnavailableView(
                    "Workspace",
                    systemImage: "square.grid.2x2",
                    description: Text("This tab will hold the broader Smart Chart workspace as the app grows.")
                )
                .navigationTitle("Workspace")
            }
            .tabItem {
                Label("Workspace", systemImage: "square.grid.2x2")
            }
            .tag(AppTab.workspace)

            NavigationStack {
                ContentUnavailableView(
                    "Settings",
                    systemImage: "gearshape",
                    description: Text("Settings and account controls will live here.")
                )
                .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
    }

    private func chartBinding(for chartID: Chart.ID) -> Binding<Chart>? {
        guard let index = store.charts.firstIndex(where: { $0.id == chartID }) else {
            return nil
        }

        return $store.charts[index]
    }
}

private enum AppTab: Hashable {
    case projects
    case workspace
    case settings
}

private enum ProjectRoute: Hashable {
    case chart(UUID, EditorCanvasMode)
}
