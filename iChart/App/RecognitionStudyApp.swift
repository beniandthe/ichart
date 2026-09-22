import SwiftUI

@main
struct RecognitionStudyApp: App {
    var body: some Scene {
        WindowGroup {
            RecognitionStudyCaptureView(
                resultProvider: RecognitionStudyVisionResultProvider()
            )
        }
    }
}
