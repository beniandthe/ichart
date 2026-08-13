import Foundation

enum ChordInkRecognitionFlow: Equatable {
    case tapToConfirm

    var canRenderChord: Bool {
        true
    }

    var telemetryValue: String {
        switch self {
        case .tapToConfirm:
            return "tap_to_confirm"
        }
    }
}
