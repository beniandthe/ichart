import Foundation

enum EditorCanvasMode: Hashable {
    case browse
    case measureEdit
    case repeatEdit
    case timeSignatureEdit
    case rhythmicNotationEdit
    case headerEntry
    case chordEntry
    case noteEdit
    case freeHand
    case textEdit

    var freeHandTabTitle: String {
        switch self {
        case .browse, .measureEdit, .repeatEdit, .timeSignatureEdit, .rhythmicNotationEdit,
                .headerEntry, .chordEntry, .noteEdit, .freeHand, .textEdit:
            return "Free-Write"
        }
    }

    var freeHandTabSymbol: String {
        switch self {
        case .browse, .measureEdit, .repeatEdit, .timeSignatureEdit, .rhythmicNotationEdit,
                .headerEntry, .chordEntry, .noteEdit, .freeHand, .textEdit:
            return "pencil.and.scribble"
        }
    }

    var showsActiveToolControls: Bool {
        switch self {
        case .browse:
            return false
        case .rhythmicNotationEdit:
            return RhythmRecognitionOverhaulGate.shipsDedicatedRhythmTool
        default:
            return true
        }
    }

    var activeToolTitle: String {
        switch self {
        case .browse:
            return "Select"
        case .measureEdit:
            return "Measures"
        case .repeatEdit:
            return "Repeats"
        case .timeSignatureEdit:
            return "Time"
        case .rhythmicNotationEdit:
            return "Rhythm"
        case .headerEntry:
            return "Header"
        case .chordEntry:
            return "Chord"
        case .noteEdit:
            return "Rhythm Edit"
        case .freeHand:
            return "Free-Write"
        case .textEdit:
            return "Text"
        }
    }

    var activeToolSymbol: String {
        switch self {
        case .browse:
            return "cursorarrow"
        case .measureEdit:
            return "rectangle.split.3x1"
        case .repeatEdit:
            return "repeat"
        case .timeSignatureEdit:
            return "metronome"
        case .rhythmicNotationEdit:
            return "music.note"
        case .headerEntry:
            return "character.cursor.ibeam"
        case .chordEntry:
            return "pencil"
        case .noteEdit:
            return "selection.pin.in.out"
        case .freeHand:
            return "pencil.and.scribble"
        case .textEdit:
            return "text.bubble"
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
        self != .freeHand
            && self != .headerEntry
            && self != .chordEntry
            && self != .noteEdit
            && self != .textEdit
    }

    var allowsNoteSelection: Bool {
        self == .noteEdit
    }

    var allowsDirectRhythmicNotationInk: Bool {
        self == .rhythmicNotationEdit
            && RhythmRecognitionOverhaulGate.shipsDedicatedRhythmTool
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

    var allowsCueTextEditing: Bool {
        self == .browse || self == .textEdit
    }

    var allowsHeaderAuthoringSelection: Bool {
        self == .browse
    }

    var requiresChordSelectionBeforeObjectActions: Bool {
        self == .browse || self == .chordEntry
    }

    var drawsAllChordObjectEditBoxes: Bool {
        self == .chordEntry
    }

    var drawsAllChordObjectEditControls: Bool {
        false
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
        allowsAnyInkEditing
    }
}
