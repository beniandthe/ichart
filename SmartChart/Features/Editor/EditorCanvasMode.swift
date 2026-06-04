import Foundation

enum EditorCanvasMode: Hashable {
    case browse
    case measureEdit
    case timeSignatureEdit
    case rhythmicNotationEdit
    case headerEntry
    case chordEntry
    case noteEdit
    case freeHand

    var freeHandTabTitle: String {
        switch self {
        case .browse, .measureEdit, .timeSignatureEdit, .rhythmicNotationEdit, .headerEntry, .chordEntry, .noteEdit:
            return "Free-Hand"
        case .freeHand:
            return "Done"
        }
    }

    var freeHandTabSymbol: String {
        switch self {
        case .browse, .measureEdit, .timeSignatureEdit, .rhythmicNotationEdit, .headerEntry, .chordEntry, .noteEdit:
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
        self == .freeHand || self == .headerEntry || self == .chordEntry || self == .noteEdit
    }

    var allowsTopBarExport: Bool {
        self != .freeHand && self != .headerEntry
    }

    var allowsMeasureSelection: Bool {
        self != .freeHand && self != .headerEntry && self != .chordEntry && self != .noteEdit
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

    var allowsHeaderInkEditing: Bool {
        self == .headerEntry
    }

    var allowsChordInkEditing: Bool {
        self == .chordEntry
    }

    var allowsChordObjectEditing: Bool {
        self == .browse || self == .chordEntry
    }

    var requiresChordSelectionBeforeObjectActions: Bool {
        false
    }

    var drawsAllChordObjectEditBoxes: Bool {
        self == .browse || self == .chordEntry
    }

    var drawsAllChordObjectEditControls: Bool {
        self == .browse || self == .chordEntry
    }

    var allowsNoteSelectionInk: Bool {
        self == .noteEdit
    }

    var allowsAnyInkEditing: Bool {
        allowsPageInkEditing
            || allowsHeaderInkEditing
            || allowsChordInkEditing
            || allowsDirectRhythmicNotationInk
            || allowsNoteSelectionInk
    }

    var allowsPassiveInkPersistence: Bool {
        allowsPageInkEditing || allowsHeaderInkEditing
    }

    var restrictsPageScrollToOutsideMargins: Bool {
        self != .browse
    }
}
