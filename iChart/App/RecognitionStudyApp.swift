import SwiftUI

@main
struct RecognitionStudyApp: App {
    var body: some Scene {
        WindowGroup {
            RecognitionStudyEngineeringDryRunView()
        }
    }
}

private struct RecognitionStudyEngineeringDryRunView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Recognition Study")
                .font(.largeTitle.bold())

            Text("Engineering dry run")
                .font(.headline)

            Text("No study canvas or data collection is implemented in this build.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
