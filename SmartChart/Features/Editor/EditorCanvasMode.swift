import Foundation

enum EditorCanvasMode: Hashable {
    case browse
    case measureEdit
    case timeSignatureEdit
    case rhythmicNotationEdit
    case noteEdit
    case freeHand

    var freeHandTabTitle: String {
        switch self {
        case .browse, .measureEdit, .timeSignatureEdit, .rhythmicNotationEdit, .noteEdit:
            return "Free-Hand"
        case .freeHand:
            return "Done"
        }
    }

    var freeHandTabSymbol: String {
        switch self {
        case .browse, .measureEdit, .timeSignatureEdit, .rhythmicNotationEdit, .noteEdit:
            return "pencil.and.scribble"
        case .freeHand:
            return "pencil.slash"
        }
    }

    var showsMeasureResizeHandles: Bool {
        self == .measureEdit
    }

    var showsTimeSignatureTargeting: Bool {
        self == .timeSignatureEdit
    }

    var showsRhythmicNotationTargeting: Bool {
        self == .rhythmicNotationEdit
    }

    var showsNoteSelectionTargeting: Bool {
        self == .noteEdit
    }

    var locksDocumentActions: Bool {
        self == .freeHand || self == .noteEdit
    }

    var allowsMeasureSelection: Bool {
        self != .freeHand && self != .noteEdit
    }

    var allowsNoteSelection: Bool {
        self == .noteEdit
    }

    var allowsDirectRhythmicNotationInk: Bool {
        self == .rhythmicNotationEdit
    }

    var allowsPageInkEditing: Bool {
        self == .freeHand
    }

    var allowsNoteSelectionInk: Bool {
        self == .noteEdit
    }

    var allowsAnyInkEditing: Bool {
        allowsPageInkEditing || allowsDirectRhythmicNotationInk || allowsNoteSelectionInk
    }

    var disablesPageScroll: Bool {
        self != .browse
    }
}
