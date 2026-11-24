import Foundation
#if DEBUG && targetEnvironment(simulator)
import UIKit
#endif

enum IChartSimulatorPreviewLaunch {
    static var showsEditorUIFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-iChartEditorUIPreview")
        #else
        false
        #endif
    }

    @MainActor
    static func applyEditorFixtureOrientation() {
        #if DEBUG && targetEnvironment(simulator)
        guard showsEditorUIFixture, ProcessInfo.processInfo.arguments.contains("-iChartEditorUILandscape") else {
            return
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.activationState == .foregroundActive {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft)) { error in
                NSLog("Editor fixture landscape request failed: %@", error.localizedDescription)
            }
        }
        #endif
    }
}
