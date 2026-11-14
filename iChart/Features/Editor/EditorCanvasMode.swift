import Foundation

struct EditorToolGuidance: Equatable {
    let title: String
    let steps: [String]
    let context: String?
    let detailsTitle: String
    let details: [EditorToolGuidanceSection]

    init(
        title: String,
        steps: [String],
        context: String? = nil,
        detailsTitle: String,
        details: [EditorToolGuidanceSection] = []
    ) {
        self.title = title
        self.steps = steps
        self.context = context
        self.detailsTitle = detailsTitle
        self.details = details
    }

    /// The purpose and immediate action are sufficient for a tool's hint.
    /// Longer gesture and recovery rules remain in the local guide.
    var accessibilitySummary: String {
        ([title] + steps + [context].compactMap { $0 }).map { text in
            guard let last = text.last, !".!?".contains(last) else { return text }
            return text + "."
        }.joined(separator: " ")
    }

    /// Compatibility/reference text for callers that need the complete guide.
    var referenceText: String {
        ([accessibilitySummary] + details.map { $0.text }).joined(separator: " ")
    }

    func replacingNextAction(_ action: String) -> Self {
        .init(title: title, steps: [action], context: context,
            detailsTitle: detailsTitle, details: details)
    }

    func withContext(_ context: String?) -> Self {
        .init(title: title, steps: steps, context: context,
            detailsTitle: detailsTitle, details: details)
    }
}

struct EditorToolGuidanceSection: Equatable {
    let title: String
    let text: String
    let example: String?

    init(title: String, text: String, example: String? = nil) {
        self.title = title
        self.text = text
        self.example = example
    }
}

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
        toolGuidance(
            layoutStyle: layoutStyle,
            manualRenderWithPreview: manualRenderWithPreview,
            hasFreeInkArticulations: hasFreeInkArticulations
        ).referenceText
    }

    func toolGuidance(
        layoutStyle: ChartLayoutStyle,
        manualRenderWithPreview: Bool,
        hasFreeInkArticulations: Bool = false
    ) -> EditorToolGuidance {
        switch self {
        case .browse:
            var details = [EditorToolGuidanceSection(
                title: "Chords and cues",
                text: "Drag a chord with Apple Pencil, then lift to place it. Beat guides show its destination. Tap a chord to show its controls: tap the red X to delete or drag the width handle to change width. Double-tap a chord to correct it. Tap a measure or cue to see its actions."
            )]
            if layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet {
                details.append(.init(
                    title: "Merge measures",
                    text: "Tap an eligible divider, then its red X to merge the measures."
                ))
                if layoutStyle == .rhythmSectionSheet {
                    details.append(Self.rhythmMeasureResizeGuide)
                }
                if hasFreeInkArticulations {
                    details.append(.init(
                        title: "Converted marks",
                        text: "Tap a converted mark, then drag to move it. Release to attach when the line is visible. Tap its red X to delete."
                    ))
                }
            }
            return .init(
                title: "Edit items on the chart",
                steps: ["Use Apple Pencil to select, move, or delete items on the chart. Scroll with a finger."],
                detailsTitle: "Select guide",
                details: details
            )
        case .measureEdit:
            var steps = ["Tap a measure, then choose Add, Layout, or Delete."]
            var details: [EditorToolGuidanceSection] = [
                .init(title: "Add measures", text: "Use Add to extend the chart beside the selected measure or onto another row."),
                .init(title: "Change the layout", text: "Open Layout to compare each action and read why an option is unavailable. Tap an available action to apply it. Merge with Next Measure is available when the boundary can be removed safely. Select the first or last measure in a row for row-boundary actions."),
                .init(title: "Delete a range", text: "Choose the first measure and start the range. Tap the last measure, then choose Delete To. Review the range before deleting.")
            ]
            if layoutStyle == .rhythmSectionSheet {
                steps = ["Tap a measure for Add, Layout, or Delete. Use Apple Pencil to drag the last measure’s right arrow left to make room."]
                details.insert(Self.rhythmMeasureResizeGuide, at: 1)
            }
            return .init(
                title: "Change measures and rows",
                steps: steps,
                detailsTitle: "Measures guide",
                details: details
            )
        case .repeatEdit:
            return .init(
                title: "Repeat measures or add an ending",
                steps: ["Select a measure, then choose Repeat Measures or Add Ending."],
                detailsTitle: "Repeats and endings",
                details: [
                    .init(title: "Repeat a range", text: "Select the first measure and choose Repeat Measures > Start Repeat. Tap the last measure, then choose End Repeat. Cancel leaves the chart unchanged."),
                    .init(title: "Repeat one measure", text: "Choose Repeat Measures > Repeat This Measure to place repeat boundaries around the selected measure. This differs from a % chord-repeat symbol."),
                    .init(title: "Endings", text: "Use Add Ending to choose a 1st, 2nd, or custom ending. Choose the label and first and last measures, then check the right edge and preview before applying. For a range selected on the page, choose Start 1st Ending Here or Start 2nd Ending Here, then tap the last measure and finish the ending."),
                    .init(title: "Existing marks", text: "Use Manage to remove repeats or edit and remove endings.")
                ]
            )
        case .timeSignatureEdit:
            return .init(
                title: "Change the meter from a measure",
                steps: ["Tap the starting measure, then choose the meter and how far it applies."],
                detailsTitle: "Time signature guide",
                details: [.init(title: "Choose the scope", text: "The time-signature change starts at the selected measure. Check its scope before applying it.")]
            )
        case .rhythmicNotationEdit:
            return .init(
                title: "Write rhythms in a measure",
                steps: ["Tap a measure, then write with Apple Pencil and check the preview."],
                detailsTitle: "Rhythm guide",
                details: [.init(title: "Availability", text: "The dedicated Rhythm tool is available only when enabled for this chart. Use Free Ink for staff handwriting.")]
            )
        case .headerEntry:
            return .init(
                title: "Write the chart heading",
                steps: ["Use Apple Pencil to write or erase in the page header. Choose Typed to enter text."],
                detailsTitle: "Header guide",
                details: [.init(title: "Typed or handwritten", text: "Typed lets you edit the title, credit, and style note. Handwritten lets you write directly in the page header.")]
            )
        case .chordEntry:
            return chordEntryGuidance(layoutStyle: layoutStyle, manualRenderWithPreview: manualRenderWithPreview)
        case .noteEdit:
            return .init(
                title: "Edit a rendered rhythm note",
                steps: ["Tap a rendered rhythm note to see its editing actions."],
                detailsTitle: "Rhythm editing guide",
                details: [.init(title: "Select the note", text: "Available editing actions follow the selected note and the chart's rhythm-tool availability.")]
            )
        case .freeHand:
            let supportsSymbolRendering = layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet
            var details = [EditorToolGuidanceSection(
                title: "Handwriting",
                text: "Use Apple Pencil to write notes and reminders directly on the page. Staff notes stay handwritten; Free Ink does not transcribe them into rhythm notation. Choose Erase to remove handwriting."
            )]
            switch layoutStyle {
            case .simpleChordSheet:
                details.append(.init(
                    title: "Marks that can convert",
                    text: "Draw a fermata or accent anywhere. Lift the Pencil and pause to convert. Marks near a rendered chord attach; others float. Use Select to move or delete them."
                ))
            case .rhythmSectionSheet:
                details.append(.init(
                    title: "Marks that can convert",
                    text: "Draw a fermata or accent anywhere, or a marcato (^) near a chord, note, or staff ink. Lift the Pencil and pause to convert. Use Select to move or delete converted marks."
                ))
            case .leadSheet:
                break
            }
            if supportsSymbolRendering {
                details.append(.init(
                    title: "Rendering symbols",
                    text: "Leave clear space around each symbol. Rendering replaces only that symbol's strokes; other handwriting stays on the page. iChart keeps the original strokes with the converted mark."
                ))
            }
            if hasFreeInkArticulations && supportsSymbolRendering {
                details.append(.init(title: "Restore handwriting", text: "Use Restore Ink to replace a converted mark with its original handwriting."))
            }
            details.append(.init(title: "Move around the page", text: "One finger scrolls. Two fingers pan and zoom."))
            return .init(
                title: "Write notes and reminders on the page",
                steps: [
                    "Use Apple Pencil to write, or choose Erase. Staff notes stay handwritten.",
                    supportsSymbolRendering
                        ? "Draw a fermata (arch over a dot) or accent (>). Lift the Pencil and pause to render."
                        : "One finger scrolls. Two fingers pan and zoom."
                ],
                detailsTitle: "Free Ink guide",
                details: details
            )
        case .textEdit:
            return .init(
                title: "Add a typed cue beside a measure",
                steps: ["Tap a measure, then choose Above or Below.",
                        "Tap the field to type. For Scribble, tap its Pencil icon, then write. Tap Add or Apply."],
                detailsTitle: "Text guide",
                details: [.init(title: "Existing cues", text: "Tap an existing cue with Apple Pencil to edit it, change its size, or delete it.")]
            )
        }
    }

    private static let rhythmMeasureResizeGuide = EditorToolGuidanceSection(
        title: "Resize a Rhythm row",
        text: "Select a measure to show its arrow handles. With Apple Pencil, drag an inside handle to adjust the two neighboring widths. Drag the last measure’s right arrow left to shorten the row. When you release, a lone measure on the next row moves up if its full width fits. Manual row or page breaks and key changes keep their boundaries."
    )

    private func chordEntryGuidance(
        layoutStyle: ChartLayoutStyle,
        manualRenderWithPreview: Bool
    ) -> EditorToolGuidance {
        var details = [EditorToolGuidanceSection(
            title: "Chords and chord repeats",
            text: "Write chords and chord-repeat symbols (%) in the blue lanes. Keep suffixes close to their roots. Leave a clear gap before the next chord.",
            example: "C∆7    D−7    G7    %"
        )]
        if !manualRenderWithPreview {
            details.append(.init(
                title: "Automatic rendering",
                text: "Complete chords render between strokes as you move on with clear gaps. A brief pause finishes the last chord. Barlines and ending brackets wait briefly for their own writing to settle; keep writing elsewhere while ready chords render."
            ))
        }
        switch layoutStyle {
        case .simpleChordSheet:
            details.append(.init(
                title: "Barlines",
                text: "Draw tall barlines between chords. A lone rendered chord moves to beat 1 when barlines form its measure."
            ))
        case .rhythmSectionSheet:
            details.append(.init(
                title: "Barlines and measures",
                text: "The first chord in each measure renders on beat 1. Draw a tall barline to split at a rhythmic boundary. A lone rendered chord moves to beat 1 when barlines form its measure. If a note crosses the cut, the line stays as ink. Draw barlines on their own at the empty row end to add measures. Use Measures for other form edits."
            ))
        case .leadSheet:
            break
        }
        details.append(.init(
            title: "Measure repeats",
            text: "Use Tools > Repeats for measure repeats or ranges. Drawn bar-and-dot repeat signs are not recognized."
        ))
        details.append(.init(
            title: "Ending brackets",
            text: manualRenderWithPreview
                ? "Draw an ending bracket in the blue lane. Use Review & Render for chord corrections or ending review. Enter the label, check the range and right edge, then confirm the ending."
                : "Draw an ending bracket in the blue lane. Use Review Ending when offered. Enter the label, check the range and right edge, then confirm the ending."
        ))
        details.append(.init(
            title: "Review prompts",
            text: manualRenderWithPreview
                ? "Use Review & Render to check chord guesses, enter missing chords, or review an ending's label and measures."
                : "Use Review Chord to check a chord guess, Fix Writing for unclear or unplaced writing, and Review Ending to check an ending's label and measures."
        ))
        details.append(.init(
            title: "Your source writing",
            text: "Unplaced ink stays on the page. Rendering replaces only the writing used by the rendered notation. Clear Draft Ink removes all unrendered writing in Write & Render; rendered notation and Free Ink stay unchanged."
        ))
        return .init(
            title: "Turn handwriting into chart notation",
            steps: [
                "Write with Apple Pencil in a highlighted lane. Keep each chord together and leave space between chords.",
                manualRenderWithPreview
                    ? "Check the previews. Tap Render Chords for ready ink, or Review & Render when entries need attention."
                    : "Complete chords render between strokes as you move on. Pause to finish the last chord. Follow review prompts when offered."
            ],
            context: manualRenderWithPreview ? "Rendering: Manual" : "Rendering: Automatic",
            detailsTitle: "Write & Render guide",
            details: details
        )
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
