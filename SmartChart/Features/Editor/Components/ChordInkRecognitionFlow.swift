import Foundation

enum ChordInkRecognitionFlow: Equatable {
    case automaticPreview
    case tapToConfirm

    var allowsContinuationGrace: Bool {
        self == .automaticPreview
    }

    var recordsPreviewSnapshot: Bool {
        self == .automaticPreview
    }

    var canRenderChord: Bool {
        self == .tapToConfirm
    }
}
