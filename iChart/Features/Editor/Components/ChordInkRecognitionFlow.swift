import Foundation

enum ChordInkRecognitionFlow: Equatable {
    case draftPreview
    case tapToConfirm

    var canRenderChord: Bool {
        switch self {
        case .draftPreview, .tapToConfirm:
            return false
        }
    }

    var telemetryValue: String {
        switch self {
        case .draftPreview:
            return "draft_preview"
        case .tapToConfirm:
            return "tap_to_confirm"
        }
    }
}
