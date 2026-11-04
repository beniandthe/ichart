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

    var telemetryValue: String {
        switch self {
        case .browse:
            return "browse"
        case .measureEdit:
            return "measure_edit"
        case .repeatEdit:
            return "repeat_edit"
        case .timeSignatureEdit:
            return "time_signature_edit"
        case .rhythmicNotationEdit:
            return "rhythmic_notation_edit"
        case .headerEntry:
            return "header_entry"
        case .chordEntry:
            return "chord_entry"
        case .noteEdit:
            return "note_edit"
        case .freeHand:
            return "free_hand"
        case .textEdit:
            return "text_edit"
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
            return "Time Signature"
        case .rhythmicNotationEdit:
            return "Rhythm"
        case .headerEntry:
            return "Header"
        case .chordEntry:
            return "Write & Render"
        case .noteEdit:
            return "Rhythm Edit"
        case .freeHand:
            return "Free Ink"
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
        self == .browse || self == .measureEdit
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
    }

    func activeToolInstruction(
        layoutStyle: ChartLayoutStyle,
        manualRenderWithPreview: Bool,
        hasFreeInkArticulations: Bool = false
    ) -> String {
        switch self {
        case .browse:
            let dividerGuidance = layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet
                ? " Tap an eligible divider, then its red X to merge the measures."
                : ""
            if (layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet) && hasFreeInkArticulations {
                return "Tap an item for actions. Double-tap a chord to correct it. Tap a converted mark, then drag to move it. Release to attach when the line is visible. Tap its red X to delete." + dividerGuidance
            }
            return "Tap a measure, chord, or cue to see its actions. Double-tap a chord to correct it." + dividerGuidance
        case .measureEdit:
            return "Tap a measure, then use Add, Layout, or Delete to change the chart. Layout includes Merge with Next Measure when the boundary can be removed safely."
        case .repeatEdit:
            return "Select a measure, then choose a repeat or ending. Use One Bar for a single measure or Manage for existing marks."
        case .timeSignatureEdit:
            return "Tap the measure where the new time signature starts, then choose the meter and how far it applies."
        case .rhythmicNotationEdit:
            return "Tap a measure, then write rhythms inside it and check the preview."
        case .headerEntry:
            return "Write or erase in the page header. Tap Typed to enter header text."
        case .chordEntry:
            let writing = switch layoutStyle {
            case .simpleChordSheet:
                "Write chords, repeat signs, and ending brackets in the blue lanes. Draw tall barlines between chords. A lone rendered chord moves to beat 1 when barlines form its measure."
            case .rhythmSectionSheet:
                "Write chords, repeats, and endings in the blue lanes. The first chord in each measure renders on beat 1. Draw a tall barline to split at a rhythmic boundary. A lone rendered chord moves to beat 1 when barlines form its measure. If a note crosses the cut, the line stays as ink. Draw barlines on their own at the empty row end to add measures. Use Measures for other form edits."
            case .leadSheet:
                "Write chords, repeat signs, and ending brackets in the blue lanes."
            }
            let rendering = manualRenderWithPreview
                ? "Keep suffixes close to their roots. Tap Render Chords for ready ink. Use Review & Render to check chord guesses or enter missing chords. Unplaced ink stays on the page."
                : "Leave space between chords and pause to render. Unplaced ink stays on the page. Use Fix Writing for unclear ink."
            return writing + " " + rendering
        case .noteEdit:
            return "Tap a rendered rhythm note to see its editing actions."
        case .freeHand:
            if layoutStyle == .simpleChordSheet {
                return "Draw a fermata or accent anywhere. Lift the Pencil and pause to convert. Marks near a rendered chord attach; others float. Use Select to move or delete them."
            }
            if layoutStyle == .rhythmSectionSheet {
                return "Draw a fermata or accent anywhere, or a marcato (^) near a chord, note, or staff ink. Lift the Pencil and pause to convert."
            }
            return "Write or erase notes and marks that stay as handwriting."
        case .textEdit:
            return "Tap a measure, then choose Above or Below to add a text cue."
        }
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
