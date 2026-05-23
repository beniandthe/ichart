import Foundation

enum EditorCanvasMode: Hashable {
    case browse
    case measureEdit
    case timeSignatureEdit
    case rhythmicNotationEdit
    case chordEntry
    case noteEdit
    case freeHand

    var freeHandTabTitle: String {
        switch self {
        case .browse, .measureEdit, .timeSignatureEdit, .rhythmicNotationEdit, .chordEntry, .noteEdit:
            return "Free-Hand"
        case .freeHand:
            return "Done"
        }
    }

    var freeHandTabSymbol: String {
        switch self {
        case .browse, .measureEdit, .timeSignatureEdit, .rhythmicNotationEdit, .chordEntry, .noteEdit:
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
        self == .freeHand || self == .chordEntry || self == .noteEdit
    }

    var allowsTopBarExport: Bool {
        self != .freeHand
    }

    var allowsMeasureSelection: Bool {
        self != .freeHand && self != .chordEntry && self != .noteEdit
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

    var allowsChordInkEditing: Bool {
        self == .chordEntry
    }

    var allowsNoteSelectionInk: Bool {
        self == .noteEdit
    }

    var allowsAnyInkEditing: Bool {
        allowsPageInkEditing || allowsChordInkEditing || allowsDirectRhythmicNotationInk || allowsNoteSelectionInk
    }

    var disablesPageScroll: Bool {
        self != .browse
    }
}
