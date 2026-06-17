import Foundation

enum EditorInkToolMode: String, CaseIterable, Hashable {
    case write
    case erase

    var systemImageName: String {
        switch self {
        case .write:
            return "pencil.tip"
        case .erase:
            return "eraser.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .write:
            return "Write"
        case .erase:
            return "Erase"
        }
    }
}
