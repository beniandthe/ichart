import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var store: ChartLibraryStore
    @State private var projectPath: [ProjectRoute] = []

    var body: some View {
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
    }

    private func chartBinding(for chartID: Chart.ID) -> Binding<Chart>? {
        guard let index = store.charts.firstIndex(where: { $0.id == chartID }) else {
            return nil
        }

        return $store.charts[index]
    }
}

private enum ProjectRoute: Hashable {
    case chart(UUID, EditorCanvasMode)
}
