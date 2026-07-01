import Foundation

enum ChordInkRecognitionFlow: Equatable {
    case tapToConfirm

    var canRenderChord: Bool {
        true
    }
}
