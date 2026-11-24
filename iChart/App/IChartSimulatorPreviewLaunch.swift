import Foundation

enum IChartSimulatorPreviewLaunch {
    static var showsEditorUIFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-iChartEditorUIPreview")
        #else
        false
        #endif
    }
}
