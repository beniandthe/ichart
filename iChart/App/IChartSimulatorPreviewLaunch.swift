import Foundation

enum IChartSimulatorPreviewLaunch {
    static var showsEditorUIFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-iChartEditorUIPreview")
        #else
        false
        #endif
    }

    static var editorWidthLimit: CGFloat? {
        #if DEBUG && targetEnvironment(simulator)
        if showsEditorUIFixture, ProcessInfo.processInfo.arguments.contains("-iChartEditorUINarrow") {
            return 360
        }
        #endif
        return nil
    }
}
