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
    case formMarkerEdit

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
        case .formMarkerEdit:
            return "form_marker_edit"
        }
    }

    var freeHandTabSymbol: String {
        switch self {
        case .browse, .measureEdit, .repeatEdit, .timeSignatureEdit, .rhythmicNotationEdit,
                .headerEntry, .chordEntry, .noteEdit, .freeHand, .textEdit, .formMarkerEdit:
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
        case .formMarkerEdit:
            return "Form Markers"
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
        case .formMarkerEdit:
            return "signpost.right"
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
        hasFreeInkArticulations: Bool = false,
        usesPaperMeasureLayout: Bool = false
    ) -> String {
        toolGuidance(
            layoutStyle: layoutStyle,
            manualRenderWithPreview: manualRenderWithPreview,
            hasFreeInkArticulations: hasFreeInkArticulations,
            usesPaperMeasureLayout: usesPaperMeasureLayout
        ).referenceText
    }

    func toolGuidance(
        layoutStyle: ChartLayoutStyle,
        manualRenderWithPreview: Bool,
        hasFreeInkArticulations: Bool = false,
        isClosingRepeatSelected: Bool = false,
        isLayoutMeasureSelected: Bool = false,
        usesPaperMeasureLayout: Bool = false
    ) -> EditorToolGuidance {
        if self == .chordEntry, usesPaperMeasureLayout {
            return paperWritingGuidance(manualRenderWithPreview: manualRenderWithPreview)
        }
        switch self {
        case .browse:
            var details = [EditorToolGuidanceSection(
                title: "Chords and cues",
                text: "Drag a chord with Apple Pencil, then lift to place it. Snap to beat 1 at the first guide, or keep dragging toward the left barline for tighter spacing. Cross the barline to move into the previous measure in the row. Tap a chord to show its side handles. Drag a side handle to resize that chord or tap the red X to delete it. Double-tap a chord to correct it. Tap a cue to see its actions."
            ), .init(
                title: "Moving text cues",
                text: Self.cueMoveGuidance
            ), .init(
                title: "Space endings and form marks",
                text: "Tap the item, then drag Move Up or Down to adjust its height. Reset Position restores automatic height. For endings, Move and Lengthen adjust the measures."
            ), Self.layoutPlacementGuide]
            if layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet {
                details.append(Self.measureRowActionsGuide(layoutStyle: layoutStyle))
                details.append(.init(
                    title: "Merge measures",
                    text: "Tap an eligible divider, then its red X to merge the measures."
                ))
                details.append(.init(
                    title: "Move a measure",
                    text: "Tap a measure, then drag its grab handle or an empty part of the selected measure with Apple Pencil. Lift to place it within the system. Chords and attached ink follow. Drag an edge handle to resize. Moving across other measures changes their order. When measures reorder, the dashed outline shows where yours will land."
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
                steps: ["Use Apple Pencil to select, move, or delete items on the chart. Scroll with a finger.",
                        isLayoutMeasureSelected
                            ? "Drag the selected measure's grab handle to move it, or use its Layout actions."
                            : "Tap a chord for width handles. Drag its body to move it."],
                detailsTitle: "Select guide",
                details: details
            )
        case .measureEdit:
            var details: [EditorToolGuidanceSection] = [
                .init(title: "Add measures", text: "Select a measure and tap Add One After to insert one measure or Add Multiple After… to choose how many. Add at Beginning inserts before the first measure. Add Double Barline adds a double boundary."),
                Self.layoutPlacementGuide,
                .init(title: "Delete one measure", text: "Select the measure, tap Delete Measure…, and confirm the measure shown. When the first measure shows Reset Barline…, you can restore its right barline to a single line."),
                .init(title: "Delete a range", text: "Select the first measure and tap Delete Range… to start. Tap the last measure and check the highlighted range, then tap Delete To or Cancel.")
            ]
            if layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet {
                details.insert(Self.measureRowActionsGuide(layoutStyle: layoutStyle), at: 2)
            }
            if layoutStyle == .rhythmSectionSheet {
                details[0] = .init(
                    title: "Add measures",
                    text: "Adding one measure fits it in the row and evens the measure widths, including when the row is full. Add Multiple After… can extend the chart across rows. Add at Beginning inserts before the first measure. Add Double Barline adds a double boundary."
                )
                details.insert(Self.rhythmMeasureResizeGuide, at: 1)
            }
            details.insert(.init(
                title: "Add at the end of a repeat",
                text: "Select the last measure of a repeat. Add Inside Repeat includes the new measure in the loop and moves the closing repeat sign. Add After Repeat puts the new measure after the closing sign. If several repeats end there, adding inside extends the outermost repeat. For several measures at the end of a repeat, tap Add Multiple… and choose the count and placement. After Repeat is selected when the sheet opens."
            ), at: 1)
            return .init(
                title: "Change measures and rows",
                steps: [isClosingRepeatSelected
                    ? "Choose Add Inside Repeat or Add After Repeat."
                    : "Tap a measure, then choose an action."],
                detailsTitle: "Measures guide",
                details: details
            )
        case .repeatEdit:
            return .init(
                title: "Repeat measures or add an ending",
                steps: ["Tap a measure, then choose a repeat or ending action."],
                detailsTitle: "Repeats and endings",
                details: [
                    .init(title: "Repeat a range", text: "Select the first measure and tap Start Repeat in Quick Actions or Repeats. Tap the last measure and check the highlight. Tap End Repeat where you started. If Quick Actions is hidden, finish with End Repeat in Repeats. Tap Cancel in Repeats to discard the range."),
                    .init(title: "Repeat one measure", text: "Select a measure and choose Repeat This Measure to place repeat boundaries around it. This differs from a % chord-repeat symbol."),
                    .init(title: "Endings", text: "Use Add Ending to choose a 1st, 2nd, or custom ending. Choose the label and first and last measures, then check the right edge and preview before applying. For a range selected on the page, choose Start 1st Ending Here or Start 2nd Ending Here, then tap the last measure and finish the ending."),
                    .init(title: "Remove a repeat", text: "Select the first or last measure of a repeat, then tap Remove Repeat. If repeats share the measure, choose the range to remove."),
                    .init(title: "Edit or remove an ending", text: "Select a measure covered by an ending. Tap Edit Ending… to change it, or tap Remove Ending and confirm. If endings overlap, choose the ending by label and range.")
                ]
            )
        case .timeSignatureEdit:
            return .init(
                title: "Change the meter from a measure",
                steps: ["Tap the starting measure, then choose a time signature above the chart."],
                detailsTitle: "Time signature guide",
                details: [
                    .init(title: "Choose a time signature", text: "Choose a preset or tap Custom… to set the numerator and denominator."),
                    .init(title: "Choose the scope", text: "The time-signature change starts at the selected measure. Check its scope before applying it.")
                ]
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
                text: "Use Apple Pencil to write notes and reminders directly on the page. Staff notes stay handwritten. Ink in or just below a measure follows it when the layout changes. Ink directly below a chord can follow that chord. Choose Erase to remove handwriting."
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
                    text: "Draw an accent (>) in one or two strokes. Leave clear space around each symbol. Other handwriting stays on the page, and iChart keeps the symbol's original strokes."
                ))
            }
            if hasFreeInkArticulations && supportsSymbolRendering {
                details.append(.init(title: "Restore handwriting", text: "Use Restore Ink to replace a converted mark with its original handwriting."))
            }
            details.append(.init(title: "Move around the page", text: "One finger scrolls. Two fingers pan and zoom."))
            return .init(
                title: "Write notes and reminders on the page",
                steps: [
                    "Use Apple Pencil to write, or choose Erase. Staff notes stay handwritten and follow their measure.",
                    supportsSymbolRendering
                        ? "Draw a fermata (arch over a dot) or accent (>). Lift the Pencil and pause to render."
                        : "One finger scrolls. Two fingers pan and zoom."
                ],
                detailsTitle: "Free Ink guide",
                details: details
            )
        case .textEdit:
            return .init(
                title: "Place or edit a text cue",
                steps: ["Tap where the cue should start, then choose Above or Below.",
                        "Choose Keyboard or Scribble. For Scribble, tap the field with Apple Pencil before writing. Tap Add or Apply."],
                detailsTitle: "Text guide",
                details: [
                    .init(title: "Cue placement", text: "The blue marker shows the cue’s beat. Check the measure and placement in the Text panel before tapping Add."),
                    .init(title: "Text entry", text: "In Keyboard, press Return for a new line. All lines stay in the same cue."),
                    .init(title: "Existing cues", text: "Tap a cue with Apple Pencil, then use Edit, Larger, Smaller or Delete."),
                    .init(title: "Moving cues", text: Self.cueMoveGuidance)
                ]
            )
        case .formMarkerEdit:
            return .init(
                title: "Place a form marker",
                steps: ["Tap a measure, then choose a form marker."],
                detailsTitle: "Form Markers guide",
                details: [
                    .init(title: "Place and adjust", text: "Tap a marker button to add it to the selected measure and return to Select. In Select, drag the marker to move it, or use its controls to resize or delete it.")
                ]
            )
        }
    }

    private static let cueMoveGuidance = "Press and hold the cue, then drag it in any direction. The blue line stays at the center of its measure until you cross a barline and disappears in the row margin. Lift to place the cue. Staff spacing stays fixed."

    private static let layoutPlacementGuide = EditorToolGuidanceSection(
        title: "Layout actions",
        text: "Quick Actions holds the Layout controls to the left of the chart, or below the tool controls in narrow windows. Tap the left-pointing chevron beside Quick Actions to give the chart more room. Tap the right-pointing chevron to show the controls again. Tap a measure in Select or Measures to see which actions are available."
    )

    private static func measureRowActionsGuide(layoutStyle: ChartLayoutStyle) -> EditorToolGuidanceSection {
        let move = "Start New Row begins a row at the selection. Join Row Above moves from the start of the row through your selection. Move to Row Below moves from your selection through the end of the row. The rows adjust to fit."
        let align = "Even System Measures gives the measures in the selected row matching widths. Merge with Next Measure removes an eligible divider."
        let fill = layoutStyle == .simpleChordSheet ? " Fill Row expands a lone measure to fill its row." : ""
        return .init(title: "Move and resize rows", text: move + " " + align + fill)
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
                text: "Draw single or double barlines between chords with a gap on both sides. They can be shorter than the lane and drawn in either direction. A lone rendered chord moves to beat 1 when barlines form its measure."
            ))
        case .rhythmSectionSheet:
            details.append(.init(
                title: "Barlines and measures",
                text: "The first chord in each measure renders on beat 1. Draw a barline to split at a rhythmic boundary. Leave a gap on both sides. It can be shorter than the lane and drawn in either direction. A lone rendered chord moves to beat 1 when barlines form its measure. If a note crosses the cut, the line stays as ink. Draw barlines on their own at the empty row end to add measures. Use Measures for other form edits."
            ))
        case .leadSheet:
            break
        }
        details.append(.init(
            title: "Measure repeats",
            text: "Use Repeats for measure repeats or ranges. Drawn bar-and-dot repeat signs are not recognized."
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

    private func paperWritingGuidance(manualRenderWithPreview: Bool) -> EditorToolGuidance {
        .init(
            title: "Write your chart",
            steps: [
                "Write chords and single or double barlines in a blue lane. Barlines can be shorter than the lane.",
                manualRenderWithPreview
                    ? "Check the previews, then tap Render Chords or Review & Render. Tap Done to finish the row."
                    : "Complete chords render as you continue writing. Pause to finish the last mark, then tap Done to finish the row."
            ],
            context: manualRenderWithPreview ? "Rendering: Manual" : "Rendering: Automatic",
            detailsTitle: "Write & Render guide",
            details: [
                .init(title: "Start anywhere",
                    text: "New charts have empty writing rows. A starting barline sets the left edge. Draw the next barline to close that measure. Two double barlines enclose one measure. Space enclosed between drawn boundaries is a measure you can select. Draw nearly vertical strokes upward or downward; they need not touch the lane edges. Leave a gap between chords and barlines."),
                .init(title: "Finish the row",
                    text: "Tap Done to size the measures across the system. A single measure written away from the left edge keeps its position. In Select, tap a measure and drag its grab handle to move it, or drag an edge handle to resize."),
                .init(title: "Keep writing",
                    text: manualRenderWithPreview
                        ? "Write in any empty row, including its right end. Keep chord suffixes close to their roots. Check the previews before rendering. A lone chord in a newly formed measure sits on beat 1."
                        : "Write chords and barlines in the same pass, including at the right end of a row. Keep suffixes close to their roots. Completed marks render while unfinished writing stays on the page. A lone chord in a newly formed measure sits on beat 1."),
                .init(title: "Review writing",
                    text: manualRenderWithPreview
                        ? "Use Review & Render to check chord guesses, correct a chord, or choose an ending's label and measures."
                        : "Use Review Chord or Review Ending when offered. Your unfinished handwriting stays on the page."),
                .init(title: "Repeats",
                    text: "Use Repeats for measure and range repeats. Chord-repeat symbols (%) can be handwritten in the lane.")
            ])
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
