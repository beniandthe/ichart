import Combine
import Foundation
import StoreKit
import SwiftUI
import UIKit

private enum IChartHomeBrand {
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.92)
    static let paperSecondary = Color(red: 0.93, green: 0.90, blue: 0.85)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let night = Color(red: 0.06, green: 0.09, blue: 0.11)
    static let stage = Color(red: 0.06, green: 0.08, blue: 0.11)
    static let blue = IChartInterfaceStyle.actionBlue
    static let logoBlue = Color(red: 0.56, green: 0.83, blue: 0.90)
    static let blueSoft = Color(red: 0.86, green: 0.93, blue: 0.95)
    static let staffOnDark = Color.white.opacity(0.23)
}

private enum IChartSupportLinks {
    static let supportURL = URL(string: "https://useichart.com/support.html")!
    static let supportEmail = "support@useichart.com"
}

enum IChartHomeAppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .light:
            "Light mode"
        case .dark:
            "Dark mode"
        }
    }
}

struct IChartHomeTheme {
    let mode: IChartHomeAppearanceMode

    var isDark: Bool {
        mode == .dark
    }

    var workspaceTitle: Color {
        isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink
    }

    var workspaceSecondary: Color {
        isDark ? IChartHomeBrand.paper.opacity(0.66) : Color.secondary
    }

    var emptyStateBackground: Color {
        isDark ? Color(red: 0.10, green: 0.12, blue: 0.15) : Color.white
    }

    var panelBackground: Color {
        emptyStateBackground
    }

    var panelTitle: Color {
        isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink
    }

    var panelSecondary: Color {
        isDark ? IChartHomeBrand.paper.opacity(0.68) : Color.secondary
    }

    var panelBorder: Color {
        isDark ? Color.white.opacity(0.48) : IChartHomeBrand.ink.opacity(0.42)
    }

    var panelShadow: Color {
        isDark ? Color.black.opacity(0.28) : IChartHomeBrand.ink.opacity(0.08)
    }

    var actionText: Color {
        isDark ? Color(red: 0.43, green: 0.67, blue: 1) : IChartInterfaceStyle.actionBlue
    }

    var selectionBackground: Color {
        isDark ? Color(red: 0.10, green: 0.22, blue: 0.39) : Color(red: 0.90, green: 0.95, blue: 1.00)
    }
}

private enum IChartLogoVariant: String {
    case b47b
    case b48a

    static var homeScreenTrialDefault: IChartLogoVariant {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-iChartLogoVariant"),
              arguments.indices.contains(arguments.index(after: flagIndex)) else {
            return .b48a
        }

        let requestedValue = arguments[arguments.index(after: flagIndex)].lowercased()
        return IChartLogoVariant(rawValue: requestedValue) ?? .b48a
        #else
        return .b48a
        #endif
    }

    var iFontName: String {
        switch self {
        case .b47b:
            return "FinaleMaestroText"
        case .b48a:
            return "FinaleMaestroText-Italic"
        }
    }

    var iTrailingAdjustment: CGFloat {
        switch self {
        case .b47b:
            return -0.07
        case .b48a:
            return -0.025
        }
    }

    var iOffset: CGSize {
        switch self {
        case .b47b:
            return .zero
        case .b48a:
            return CGSize(width: -0.055, height: 0)
        }
    }
}

private enum IChartHomeTab: String, CaseIterable, Identifiable {
    case charts
    case pdfs
    case setlists
    case forums
    case help
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charts:
            "Charts"
        case .pdfs:
            "PDFs"
        case .setlists:
            "Setlists"
        case .forums:
            "Forums"
        case .help:
            "Help"
        case .settings:
            "Settings"
        }
    }

    var systemImageName: String {
        switch self {
        case .charts:
            "music.note.list"
        case .pdfs:
            "doc.richtext"
        case .setlists:
            "list.number"
        case .forums:
            "bubble.left.and.bubble.right"
        case .help:
            "questionmark.circle"
        case .settings:
            "gearshape"
        }
    }
}

private enum IChartHelpTopic: String, CaseIterable, Identifiable {
    case tutorial
    case howTo
    case faq
    case userPolicy
    case legal
    case contactUs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tutorial:
            "Quick Start"
        case .howTo:
            "How To"
        case .faq:
            "FAQ"
        case .userPolicy:
            "User Policy"
        case .legal:
            "Legal Policy"
        case .contactUs:
            "Contact Us"
        }
    }

    var summary: String {
        switch self {
        case .tutorial:
            "Make your first chart"
        case .howTo:
            "Use the chart tools"
        case .faq:
            "Common questions"
        case .userPolicy:
            "Use and conduct"
        case .legal:
            "Terms and privacy"
        case .contactUs:
            "Support and feedback"
        }
    }

    var systemImageName: String {
        switch self {
        case .tutorial:
            "graduationcap"
        case .howTo:
            "wrench.and.screwdriver"
        case .faq:
            "questionmark.circle"
        case .userPolicy:
            "person.text.rectangle"
        case .legal:
            "doc.text"
        case .contactUs:
            "envelope"
        }
    }

    var detailTitle: String {
        switch self {
        case .tutorial:
            "Quick Start"
        case .howTo:
            "How To Use The Tools"
        case .faq:
            "Common Questions"
        case .userPolicy:
            "User Policy"
        case .legal:
            "Legal Policy"
        case .contactUs:
            "Contact Us"
        }
    }

    var detailText: String {
        switch self {
        case .tutorial:
            "One short path to a first Simple Chord Sheet, plus an optional guide on the chart."
        case .howTo:
            "Simple help for Select, Write & Render, Free Ink, Measures, Tools, and Export PDF."
        case .faq:
            "Answers about Forums and why iChart uses accounts."
        case .userPolicy:
            "How to use iChart, keep account identity clear, and share community chart PDFs responsibly."
        case .legal:
            "Plain-language terms, privacy, subscription, and community notes for iChart."
        case .contactUs:
            "For feedback, bug reports, account questions, or Pro support, use the hosted support page and include the email tied to your iChart account."
        }
    }
}

private struct IChartQuickStartStep: Identifiable {
    let id: String
    let title: String
    let detail: String

    static let all: [IChartQuickStartStep] = [
        IChartQuickStartStep(
            id: "create",
            title: "Create A Simple Sheet",
            detail: "Tap New Chart and choose Simple Chord Sheet. Quick Start prepares four measures; change the setup if you want, then create the page."
        ),
        IChartQuickStartStep(
            id: "chords",
            title: "Write And Render Chords",
            detail: "Tap Write & Render and use Apple Pencil to write C, F, G, C with space between chords. Complete chords render as you move on; pause to finish the last chord. For previews, choose Manual in Rendering in Write & Render or Settings, then use Render Chords or Review & Render."
        ),
        IChartQuickStartStep(
            id: "form",
            title: "Shape The Form",
            detail: "Tap Measures, select a measure, then use Add, Layout, or Delete. Layout also moves measures between rows and evens their widths."
        ),
        IChartQuickStartStep(
            id: "cue",
            title: "Add A Cue And Review",
            detail: "Open Tools > Text, select a measure, then choose Above or Below. Tap the field to type or use its Pencil icon for Scribble. Tap Add, then tap Done for Select. Use Pencil to select items on the chart."
        ),
        IChartQuickStartStep(
            id: "export",
            title: "Export When Ready",
            detail: "Tap Export PDF. Your editable chart stays in Charts. Use How To for Free Ink, repeats, time changes, form markers, and document settings."
        )
    ]
}

private struct IChartHelpArticleSection: Identifiable {
    let id: String
    let title: String
    let systemImageName: String
    let body: String
    let bullets: [String]

    struct BulletGroup: Identifiable {
        let title: String
        let bullets: [String]
        var id: String { title }
    }

    var readingGroups: [BulletGroup] {
        guard id.hasPrefix("editor-") || id.hasPrefix("pdf-") else {
            return [BulletGroup(title: "Details", bullets: bullets)]
        }
        let recoveryIndices: Set<Int>
        let startIndices: Set<Int>
        switch id {
        case "editor-edit-checkpoint": startIndices = [0, 1, 2]; recoveryIndices = [7]
        case "editor-corridor-lane": startIndices = [0, 1, 4, 6]; recoveryIndices = [5, 12, 14, 16]
        case "editor-writing-ending-brackets": startIndices = [0, 2, 3, 4]; recoveryIndices = [6, 7]
        case "editor-render-chords": startIndices = [0, 1, 2]; recoveryIndices = [3, 5, 8]
        case "editor-free-write": startIndices = [0, 1]; recoveryIndices = [5]
        case "pdf-import": startIndices = [0, 1]; recoveryIndices = [3]
        case "pdf-offline": startIndices = [0, 1]; recoveryIndices = [2]
        case "pdf-recovery": startIndices = [0, 1]; recoveryIndices = [2]
        default: startIndices = [0, 1]; recoveryIndices = []
        }
        func group(_ title: String, including predicate: (Int) -> Bool) -> BulletGroup {
            BulletGroup(title: title, bullets: bullets.enumerated().filter { predicate($0.offset) }.map(\.element))
        }
        return [
            group("Start here", including: { startIndices.contains($0) }),
            group("Common actions", including: { !startIndices.contains($0) && !recoveryIndices.contains($0) }),
            group("Fix a problem", including: { recoveryIndices.contains($0) })
        ].filter { !$0.bullets.isEmpty }
    }

    static func sections(for topic: IChartHelpTopic) -> [IChartHelpArticleSection] {
        switch topic {
        case .tutorial:
            []
        case .howTo:
            howTo
        case .faq:
            faq
        case .userPolicy:
            userPolicy
        case .legal:
            legalPolicy
        case .contactUs:
            contact
        }
    }

    private static let howTo: [IChartHelpArticleSection] = [
        IChartHelpArticleSection(
            id: "editor-edit-checkpoint",
            title: "Select",
            systemImageName: "cursorarrow",
            body: "Use Select when you want to check the page or change something already on it.",
            bullets: [
                "Tap Done to leave the current tool and return to Select.",
                "You can switch directly between Write & Render, Free Ink, Measures, and Tools without returning to Select first.",
                "Tap a chord, barline, text label, marker, or measure with Apple Pencil to show its buttons. Use a finger to scroll.",
                "In Select, drag a chord with Apple Pencil, then lift to place it. You can start on the chord without selecting it first.",
                "Tap a chord to show its controls. Tap the red X to delete it, or drag the width handle to change its width.",
                "In either chart style, tap an eligible divider, then its red X or Delete to merge the two measures. Rhythm divider deletion is limited to chord-only measures; notes, attached marks or a merge that could move staff handwriting keep the boundary protected.",
                "On a Simple Chord Sheet or Rhythm Section Sheet, tap a converted mark to select it. Drag to move it or tap the red X to delete it.",
                "While you drag, a line points to a nearby chord. On a Rhythm Section Sheet, it can also point to a rhythm note or staff ink. Release to attach when the line is visible.",
                "Drag out of range and the line disappears. Release in open space to leave the mark floating.",
                "Tap Undo Delete to bring back the last deleted converted mark.",
                "Use the buttons to correct, move, resize, delete, or clean up what you selected."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-corridor-lane",
            title: "Write & Render",
            systemImageName: "pencil",
            body: "Use Write & Render to turn handwritten chords, chord-repeat symbols (%), barlines, and ending brackets into chart notation.",
            bullets: [
                "Use Apple Pencil to write in the highlighted lane above the staff. Keep suffixes close to their roots and leave space between chords.",
                "Write chord-repeat symbols (%) in the lane alongside chords. Keep separate symbols apart and follow review prompts when offered.",
                "Add measure repeats and repeat ranges with Tools > Repeats by selecting measures.",
                "On a Rhythm Section Sheet, the first chord in each measure renders on beat 1 wherever you write it in that measure.",
                "In Automatic, keep each chord together and leave clear gaps before the next. Complete chords render between strokes as you move on; pause to finish the last chord. Barlines and ending brackets wait briefly for their own writing to settle while ready chords can render elsewhere.",
                "If a triangle is unclear, the ink stays on the chart. Tap Review Chord in Automatic, or Review & Render in Manual, to enter the intended chord.",
                "Choose Manual under Rendering in Write & Render or app Settings to check the previews before tapping Render Chords or Review & Render.",
                "On a Simple Chord Sheet or Rhythm Section Sheet, draw a tall, nearly vertical barline in the highlighted lane with space on either side.",
                "When barlines form measures around rendered chords in either style, each resulting measure with just one chord moves that chord to beat 1. Measures with multiple chords keep their relative placement.",
                "On a Rhythm Section Sheet, a handwritten barline can split a measure at a rhythmic boundary in Automatic or Manual. If a note crosses that boundary, the line stays as draft ink and the tool shows feedback above the controls. Use Measures for other form edits.",
                "Draw the line near an existing note onset when splitting a measure that already has rhythms. Both new measures use the current meter. Written notes keep their lengths, and rests fill the unused beats.",
                "To add measures at the end of a short row, draw tall barlines on their own in the empty lane and leave space between them.",
                "If a barline cannot be placed, it stays on the page while chords that can be placed independently render. Keep writing, or use Erase to remove the line and redraw it.",
                "Splits in Simple measures and supported splits in committed Rhythm measures keep converted marks and their original handwriting. An open Rhythm measure may require Restore Ink in Free Ink before splitting when it holds a converted mark or its original writing.",
                "When Review Chords opens, check each Recognition guess. Type a correction or choose a suggestion to mark the row Your edit. You can also rewrite just that chord.",
                "In Edit Chord, choose a saved alternative or use Change quality for a supported chord quality on the same root. Quality choices are editing options, not new recognition guesses. Save applies the chord shown in Change to.",
                "If you see Chart not saved, keep the chart open and tap Retry Save above the tools."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-repeat-tools",
            title: "Chord and Measure Repeats",
            systemImageName: "repeat",
            body: "Write chord-repeat symbols (%) in Write & Render. Use Tools > Repeats for measure repeats and repeat ranges.",
            bullets: [
                "Select the first measure, then choose Repeat Measures > Start Repeat. Select the last measure and tap End Repeat.",
                "Open Repeat Measures and choose Repeat This Measure for one measure, or Start Repeat for a range. Use Manage to remove repeats or edit and remove endings.",
                "Write & Render does not convert drawn bar-and-dot repeat barlines. Use Free Ink to keep those signs as handwriting."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-writing-ending-brackets",
            title: "Writing Ending Brackets",
            systemImageName: "rectangle.topthird.inset.filled",
            body: "Draw the bracket in the blue lane, then review its label and measures.",
            bullets: [
                "Draw a long roof near the top of the lane across the intended measures, with a short downward hook at the left. Add a right hook for a closed ending, or leave that edge open.",
                "The roof and hooks can be one stroke or separate strokes. Put the label just below the roof, between the hooks, with chords lower in the lane.",
                "Tap the ending preview to open Review Ending. In Automatic, use Review Ending when offered. In Manual, use Review & Render when the ending needs review.",
                "The handwritten label is shown for reference. Enter the intended label in Review Ending, such as 1., 2., 1–3, Last time, or On cue.",
                "Check Start measure and End measure, choose Open or Closed under Right edge, then tap Use Ending. You can correct the measure range without redrawing the bracket.",
                "Use Ending confirms the draft. Rendering replaces the bracket and label ink with the reviewed notation. Back to Writing keeps the ink; changed writing may need another review.",
                "If a mark blocks Review Ending, tap its name or Back to Writing to highlight it. Correct the highlighted mark, then review the same ending bracket again.",
                "Clear Draft Ink removes all unrendered writing in Write & Render after confirmation. Use Erase to change only the mark you are fixing."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-render-chords",
            title: "Manual Rendering",
            systemImageName: "checkmark.circle",
            body: "Choose Manual under Rendering in Write & Render or app Settings to review your writing before it becomes notation.",
            bullets: [
                "Tap Render Chords to render ready ink. Use Review & Render to check chord guesses or enter missing chords. You can keep writing while unplaced ink stays on the page.",
                "Tap an ending preview to review its label and measures. When only an unreviewed ending remains, use Review & Render.",
                "When adding △7 or −7 after a preview appears, write it close to its root and check the updated preview before rendering. Leave space between separate chords.",
                "If a preview says Add chord, tap Review & Render and type the intended chord.",
                "After Back to Writing, your corrections stay with the same handwriting. Check the updated rows if you return to review.",
                "If new strokes make a chord unreadable, Add chord marks the combined writing. If you see Separate chords, go back to writing and rewrite those chords with more space between them.",
                "In Review Chords, Recognition guess marks a prefilled read and Your edit marks text you typed or chose. Fill in any missing chords and check the guesses. Render All uses the text shown in every row. Ink that cannot be placed stays on the page.",
                "Choose Automatic to return to rendering complete chords as you move on.",
                "Clear Draft Ink removes all unrendered writing in Write & Render after confirmation."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-rendered-objects",
            title: "Changing Chords, Text, And Markers",
            systemImageName: "square.and.pencil",
            body: "In Select, use Apple Pencil to edit items on the chart. Use a finger to scroll.",
            bullets: [
                "Double-tap a chord in Select to correct it. Tap once to show its controls.",
                "Drag a chord body to move it, then lift to place it. The width handle changes width; the red X deletes.",
                "If a selected chord has a custom width, Reset Width returns it to 100% width without changing its placement.",
                "Tap text or roadmap markers in Select to move, resize, edit, or delete them.",
                "To remove an eligible chord-only divider, choose Select, tap the divider, then its red X or Delete. Protected Rhythm boundaries keep their content and remain in place."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-structure-tools",
            title: "Measures And Tools",
            systemImageName: "rectangle.split.3x1",
            body: "Measures stays one tap away; less-frequent structure and annotation commands live under Tools.",
            bullets: [
                "Measures groups Add, Layout, and Delete actions for the selected measure.",
                "On a Rhythm Section Sheet, select a measure to show its arrow handles. Use Apple Pencil to drag an inside handle to adjust the two neighboring widths, or drag the last measure’s right arrow left to shorten the row.",
                "When you release, a lone measure on the next row moves up if its full width fits. Manual row or page breaks and key changes keep their boundaries.",
                "Open Layout to compare Start New Row, Join Row Above, Move to Row Below, Even Row Widths, and Merge with Next Measure. The sheet explains each action and why an option is unavailable. Tap an available action to apply it.",
                "Tools > Repeats groups Repeat Measures, Add Ending, and Manage. Add Ending offers 1st Ending…, 2nd Ending…, or Custom Ending… with a shared label and range editor.",
                "Tools > Text uses the selected measure. Choose Above or Below. Tap the field to type, or tap its Pencil icon and write in the field. Tap Add or Apply.",
                "Tools > Time Signature uses the selected measure. Tools > Form Markers opens a sheet: check the measure, choose a marker, then tap Add."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-sheet-types",
            title: "Simple And Rhythm Section Sheets",
            systemImageName: "music.note.list",
            body: "Pick the sheet that matches the chart you want to write.",
            bullets: [
                "Simple Chord Sheet is a compact chart of chords and song form.",
                "Rhythm Section Sheet adds space for handwritten rhythms, hits, slashes, groove cues, and bass clef parts.",
                "New Chart shows examples before setup. Use Back to change the layout, or Cancel before creating it. Quick Start uses Simple Chord Sheet only."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-free-write",
            title: "Free Ink",
            systemImageName: "pencil.and.scribble",
            body: "Use Free Ink to write or erase notes and marks, or draw a fermata (arch over a dot) or accent (>).",
            bullets: [
                "Use it for handwritten rhythm notes and reminders.",
                "On a Simple Chord Sheet or Rhythm Section Sheet, draw a fermata or accent anywhere on the page. Lift the Pencil and pause. iChart converts clear marks into notation and leaves unclear marks as handwriting.",
                "Leave clear space around each symbol. Rendering replaces only that symbol’s strokes; iChart keeps those strokes with the converted mark and leaves other handwriting on the page.",
                "On a Simple Chord Sheet, a converted mark attaches above a nearby rendered chord. Other marks float where you drew them. Drag near a chord to attach; drag away to float. Deleting a chord keeps its mark floating.",
                "On a Rhythm Section Sheet, draw a marcato (^) near a chord, rhythm note, or staff ink, then lift the Pencil and pause. In open space, the caret stays handwritten.",
                "On a Rhythm Section Sheet, a converted mark attaches above a nearby chord, rhythm note, or staff ink. Fermatas and accents drawn in open space stay where you drew them. Use Select to move or delete a converted mark.",
                "Use Restore Ink to replace a converted mark with its original handwriting. In Simple, measure splits, merges and deletions keep converted marks and their original handwriting. In Rhythm, a converted mark can require restoration before merging or deleting measures; supported splits of committed measures keep the marks.",
                "Switch directly to another tool, or tap Done to return to Select."
            ]
        ),
        IChartHelpArticleSection(
            id: "editor-page-export",
            title: "Document Settings And Export",
            systemImageName: "square.and.arrow.up",
            body: "Tap the chart title for document settings; Export PDF stays visible in the navigation bar.",
            bullets: [
                "The chart-title menu groups Chart Details, Key & Transposition, and Appearance & Layout. Open the group for header, key, instrument view, transposition, fonts, engraving or spacing controls.",
                "Chart Key changes the key and chord pitches. Transpose changes chord pitches immediately; repeated choices add further shifts. Instrument changes the display view. Reset Display Offset clears a display offset rather than undoing earlier pitch changes.",
                "Engraving previews use the chart's Simple Chord Sheet or Rhythm Section Sheet layout. Preset changes apply to the chart and its exported PDF.",
                "Export PDF creates the finished file. Your editable chart stays in Charts.",
                "Personal PDF exports include rendered notation and saved Free Ink. Unresolved Write & Render ink stays in the editable chart.",
                "If Export PDF is unavailable, tap Done and finish setup first."
            ]
        ),
        IChartHelpArticleSection(
            id: "pdf-import", title: "Import a PDF", systemImageName: "square.and.arrow.down",
            body: "Keep your own PDFs in the library for offline reading.",
            bullets: [
                "Open PDFs, choose Import PDF, then choose a PDF in Files. iChart saves a local copy; the original file stays where it is.",
                "Check the preview after import. Choose Share to send a copy, or Add to Setlist to arrange it with other songs.",
                "Use Search PDFs to find a title or file name. Choose Sort: Recent or Name to change the displayed order.",
                "Cancel an import while it is preparing if you chose the wrong file. If a PDF cannot be opened, check that the original is a readable PDF and import it again."
            ]
        ),
        IChartHelpArticleSection(
            id: "pdf-setlist", title: "Build a Setlist", systemImageName: "list.number",
            body: "Put saved PDFs in performance order.",
            bullets: [
                "In PDFs, open a file's Actions menu and choose Add to Setlist. Tap an existing setlist, or open New Setlist and choose Create & Add PDFs.",
                "You can also open Setlists, choose a setlist, then Add PDFs. Search for titles and select the songs to add.",
                "Use Edit in the setlist to reorder songs or remove an entry. Removing an entry keeps the original PDF in your library."
            ]
        ),
        IChartHelpArticleSection(
            id: "pdf-offline", title: "Read Offline", systemImageName: "wifi.slash",
            body: "Saved PDFs and setlists stay on this device for reading without a connection.",
            bullets: [
                "Save or import each PDF before going offline. In Forums, Save PDF & Open saves the download into PDFs.",
                "Open Setlists and tap a song to read it. Use Previous Song and Next Song to move through the running order.",
                "Open the setlist before a performance and check any unavailable songs. Online account actions and new forum downloads still need a connection."
            ]
        ),
        IChartHelpArticleSection(
            id: "pdf-recovery", title: "Replace an Unavailable Song", systemImageName: "doc.badge.exclamationmark",
            body: "A setlist keeps an unavailable song in its place so you can repair it.",
            bullets: [
                "Read the reason shown for the PDF. A missing or unreadable file is different from a library-access restriction.",
                "Choose Replace PDF on the song and select a readable PDF from the library. Its position in the setlist stays the same.",
                "Use Next Song in the reader to continue. Import a replacement PDF first if it is not already in the library."
            ]
        )
    ]

    private static let faq: [IChartHelpArticleSection] = [
        IChartHelpArticleSection(
            id: "faq-forums",
            title: "What are Forums?",
            systemImageName: "bubble.left.and.bubble.right",
            body: "Forums are an account-based space for sharing useful chart PDFs with other musicians, included in free Pro access.",
            bullets: [
                "A forum upload starts from a chart you made in iChart.",
                "Use the search field at the top of Forums, then tap Search to find songs, artists, arrangers, or tags. Use Load More for additional matches. Your search text stays available while results load or if you need to retry.",
                "Forum PDFs keep the publisher's instrument view and transposition at submission. Change the view in the chart before Submit To Forum if needed.",
                "Older downloads without reliable view metadata show Instrument view unknown. Downloading never changes the notes printed in the PDF.",
                "iChart checks that the PDF and chart details belong to that upload before it appears publicly.",
                "Members can browse, download, vote, comment, report concerns, and block contributors they no longer want to see.",
                "Author badges appear beside chart contributors. Open a chart to read what its author’s badges mean."
            ]
        ),
        IChartHelpArticleSection(
            id: "faq-account",
            title: "Why does iChart need an account?",
            systemImageName: "person.crop.circle.badge.checkmark",
            body: "Your account keeps Pro, cloud backup, Forums, recovery, and support tied to the right person.",
            bullets: [
                "First name, last name, and email are set during signup so support and public forum credit stay consistent.",
                "Email verification protects password recovery and Pro access.",
                "If your name or email needs to change later, contact support so the account stays clean."
            ]
        ),
        IChartHelpArticleSection(
            id: "faq-basic-pro",
            title: "Is Pro free?",
            systemImageName: "star.circle",
            body: IChartLegalLinks.freeProNotice,
            bullets: [
                "Your account includes unlimited local charts, Projects, cloud backup and restore, Forums, and PDF export without a purchase.",
                "Online features still require a verified account and a connection; your local charts remain available offline.",
                IChartLegalLinks.futurePricingNotice
            ]
        ),
        IChartHelpArticleSection(
            id: "faq-subscription",
            title: "What if I already subscribed?",
            systemImageName: "creditcard",
            body: IChartLegalLinks.existingBillingNotice,
            bullets: [
                "Settings includes Manage My Subscription for existing Apple billing.",
                "Apple controls cancellations, charges, and refund decisions. Free app access is separate from your existing Apple billing history.",
                "Cancelling an old subscription does not remove free Pro access. You can separately choose Basic or rejoin Pro in Settings."
            ]
        ),
        IChartHelpArticleSection(
            id: "faq-support",
            title: "What should I send support?",
            systemImageName: "envelope",
            body: "Send enough detail for the issue to be reproduced without sharing private credentials.",
            bullets: [
                "For chart-writing bugs, include the chart type, what you were doing, and what you expected to happen.",
                "For account or Pro questions, include the email tied to your iChart account.",
                "Do not send passwords, recovery links, verification links, or payment details."
            ]
        )
    ]

    private static let userPolicy: [IChartHelpArticleSection] = [
        IChartHelpArticleSection(
            id: "policy-account",
            title: "Account Identity",
            systemImageName: "person.text.rectangle",
            body: "Use your own account and keep the email reachable so support, recovery, Pro, and forum credit stay reliable.",
            bullets: [
                "Name and email are tied to the account after signup.",
                "Forum posts and comments use your verified account identity, shown publicly as a shortened name.",
                "Never share passwords, verification links, recovery links, or purchase credentials."
            ]
        ),
        IChartHelpArticleSection(
            id: "policy-local-charts",
            title: "Your Charts",
            systemImageName: "music.note.list",
            body: "Use iChart to create, edit, save, and export charts you are allowed to use and share.",
            bullets: [
                "Free Pro access includes unlimited local charts, all shipped local authoring tools, and PDF export.",
                "Keep titles, notes, credits, and chart details clear for the musicians reading the chart.",
                "Deleting a local chart removes it from your local library."
            ]
        ),
        IChartHelpArticleSection(
            id: "policy-community",
            title: "Community Sharing",
            systemImageName: "bubble.left.and.bubble.right",
            body: "Forums work best when shared charts are useful, readable, and credited honestly.",
            bullets: [
                "Publish only charts you have the right to share.",
                "Forum publishing sends a fixed PDF snapshot with creator credit and chart details.",
                "Your editable chart, original handwriting, and private drafts are not shared when you publish."
            ]
        ),
        IChartHelpArticleSection(
            id: "policy-conduct",
            title: "Conduct",
            systemImageName: "checkmark.seal",
            body: "Treat the community library like a shared music stand.",
            bullets: [
                "Use comments for helpful corrections, version notes, and respectful discussion.",
                "If posting a comment fails, your draft stays in the discussion. Check the message and tap Post comment to try again.",
                "Discussion opens with recent comments. Tap Load Earlier Comments to read more while keeping the comments already shown.",
                "Use Safety to report charts or comments that look inaccurate, miscredited, abusive, or unsafe. You can also block a contributor to hide their forum posts and comments from your account.",
                "Voting is for chart quality, not personal pile-ons. Repeated bad-faith behavior may limit forum access."
            ]
        ),
        IChartHelpArticleSection(
            id: "policy-plan",
            title: "Free Pro Access",
            systemImageName: "star.circle",
            body: IChartLegalLinks.freeProNotice,
            bullets: [
                "Pro currently has no chart cap or purchase requirement. If you choose Basic, you can create up to 3 local charts; your existing work stays editable.",
                "A subscription expiry or refund does not remove free Pro access or trigger subscription-based backup removal during this free-access period.",
                IChartLegalLinks.futurePricingNotice
            ]
        )
    ]

    private static let legalPolicy: [IChartHelpArticleSection] = [
        IChartHelpArticleSection(
            id: "legal-terms",
            title: "Terms Of Use",
            systemImageName: "doc.text",
            body: "Use iChart to write, manage, export, and share charts in ways you are allowed to perform or distribute.",
            bullets: [
                "You are responsible for the content, credits, and chart details you create or publish.",
                "Do not use iChart to impersonate another person, bypass moderation, or interfere with the service.",
                "Features may change as the app, App Store requirements, and community systems evolve."
            ]
        ),
        IChartHelpArticleSection(
            id: "legal-privacy",
            title: "Privacy",
            systemImageName: "lock.shield",
            body: "iChart uses account data and chart data only to run the app features you choose.",
            bullets: [
                "Local charts stay on the device unless you use cloud backup or publish a forum PDF.",
                "Account information supports sign-in, email verification, password recovery, subscription identity, and support.",
                "Optional diagnostics include basic error counts, elapsed timings, correction categories, and app/build/device context, but not chart titles, emails, raw chord text, drawings, PDFs, screenshots, or chart documents. Manage sharing in Settings → Privacy.",
                "Forum posts, comments, votes, reports, downloads, and moderation events are handled by the community service."
            ]
        ),
        IChartHelpArticleSection(
            id: "legal-subscriptions",
            title: "Subscriptions",
            systemImageName: "creditcard",
            body: IChartLegalLinks.existingBillingNotice,
            bullets: [
                "No new subscription purchase is required or offered for free Pro access in this version.",
                "Manage My Subscription in Settings opens Apple's controls for an existing subscription. Changing app access does not cancel Apple billing.",
                IChartLegalLinks.futurePricingNotice
            ]
        ),
        IChartHelpArticleSection(
            id: "legal-content",
            title: "Chart Content",
            systemImageName: "music.note",
            body: "You keep responsibility for the charts you create, export, send, or publish.",
            bullets: [
                "Only publish forum charts you have the right to share.",
                "Forum posts are reviewed before public visibility.",
                "Downloaded forum PDFs are for use inside your local PDF Library and are not editable chart source files."
            ]
        ),
        IChartHelpArticleSection(
            id: "legal-support",
            title: "Support And Changes",
            systemImageName: "envelope",
            body: "Support requests should include enough account and chart context to reproduce the issue.",
            bullets: [
                "Include the email tied to your iChart account when asking for account or Pro support.",
                "Do not send passwords, recovery links, private credentials, or payment details.",
                "Legal, privacy, and subscription wording may be updated as the production release is finalized."
            ]
        )
    ]

    private static let contact: [IChartHelpArticleSection] = [
        IChartHelpArticleSection(
            id: "contact-feedback",
            title: "Feedback And Bugs",
            systemImageName: "exclamationmark.triangle",
            body: "For feedback, bug reports, account questions, or Pro support, contact iChart through the hosted support page.",
            bullets: [
                "For chart-writing bugs, mention the chart type, what you were doing, and what you expected to happen.",
                "For account or Pro questions, include your account email and whether you are on Basic or Pro.",
                "Do not send passwords, recovery links, verification links, or payment credentials."
            ]
        )
    ]
}

private enum IChartGuidedTourStep: String, Identifiable {
    case welcome
    case newChart
    case simpleChart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:
            "Quick Start"
        case .newChart:
            "Create A Chart"
        case .simpleChart:
            "Choose Simple Chord Sheet"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            "Make your first usable chart with one short, optional guide."
        case .newChart:
            "Tap New Chart."
        case .simpleChart:
            "Choose Simple Chord Sheet."
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .welcome:
            "Start Quick Start"
        case .newChart, .simpleChart:
            nil
        }
    }

    var targetText: String? {
        switch self {
        case .welcome:
            nil
        case .newChart:
            "Tap New Chart"
        case .simpleChart:
            "Tap Simple Chord Sheet"
        }
    }
}

private enum IChartChartPreviewMode: String, CaseIterable, Identifiable {
    case collapsed
    case quick
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collapsed:
            "Collapsed"
        case .quick:
            "Quick"
        case .large:
            "Large"
        }
    }
}

private enum IChartChartsWorkspaceMode: String, CaseIterable, Identifiable {
    case charts
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charts:
            return "Charts"
        case .projects:
            return "Projects"
        }
    }
}

struct LibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var store: ChartLibraryStore
    @EnvironmentObject private var authStore: IChartAuthStore
    @EnvironmentObject private var cloudSyncStore: ChartCloudSyncStore
    @EnvironmentObject private var subscriptionStore: IChartStoreKitSubscriptionStore
    @EnvironmentObject private var forumStore: IChartForumStore
    @EnvironmentObject private var pdfLibraryStore: IChartPDFLibraryStore
    @Environment(\.betaProStore) private var betaProStore
    let onOpenChart: (Chart.ID, EditorCanvasMode) -> Void
    @AppStorage("iChartHomeAppearanceMode") private var homeAppearanceModeRawValue = IChartHomeAppearanceMode.light.rawValue
    @AppStorage("iChartHomeSidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("iChartChartPreviewMode") private var chartPreviewModeRawValue = IChartChartPreviewMode.collapsed.rawValue
    @AppStorage("iChartChartsWorkspaceMode") private var chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
    @AppStorage("iChartHasSeenAccountLanding") private var hasSeenAccountLanding = false
    @AppStorage("iChartHasSeenGuidedTourOffer") private var hasSeenGuidedTourOffer = false
    @AppStorage(IChartTelemetryConsentStore.preferenceKey) private var telemetryConsentVersion = ""
    @AppStorage("iChartPendingSimpleChartTour") private var pendingSimpleChartTour = false
    @AppStorage(ChordInkWorkflowSettings.manualRenderWithPreviewKey)
    private var manualRenderWithPreview = ChordInkWorkflowSettings.defaultManualRenderWithPreview
    #if DEBUG && targetEnvironment(simulator)
    @AppStorage(IChartRuntimeDiagnostics.rhythmRecognitionDiagnosticsKey)
    private var rhythmDiagnosticsEnabled = false
    #endif
    @State private var logoVariant = IChartLogoVariant.homeScreenTrialDefault
    @State private var selectedHomeTab: IChartHomeTab = .charts
    @State private var selectedHelpTopic: IChartHelpTopic?
    @State private var guidedTourStep: IChartGuidedTourStep?
    @State private var showingLayoutPicker = false
    @State private var pendingProjectForNewChart: ChartProject.ID?
    @State private var createdChartToOpen: Chart.ID?
    @State private var showingAccountLanding = false
    @State private var showingCreateProject = false
    @State private var renameRequest: ChartRenameRequest?
    @State private var libraryAlert = IChartLibraryAlertPresentation()
    @State private var isSelectingCharts = false
    @State private var selectedChartIDs: Set<Chart.ID> = []
    @State private var isSelectingPDFs = false
    @State private var selectedPDFIDs: Set<UUID> = []
    @State private var awaitingChartDeleteSave = false
    @State private var renameProjectRequest: ChartProjectRenameRequest?
    @State private var addChartsRequest: ChartProjectAddChartsRequest?
    @State private var duplicateVariantRequest: ChartProjectDuplicateVariantRequest?
    @State private var forumSearchText = ""
    @State private var forumSubmittedSearchText = ""
    @State private var forumPublishRequest: IChartForumPublishRequest?
    @State private var selectedPDFLibraryItem: IChartPDFLibraryItem?
    @State private var selectedAddToSetlistPDF: IChartPDFLibraryItem?
    @State private var chartSearchText = ""
    @State private var projectSearchText = ""
    @State private var pdfSearchText = ""
    @State private var chartSortOrder: LibrarySortOrder = .recent
    @State private var projectSortOrder: LibrarySortOrder = .recent
    @State private var pdfSortOrder: LibrarySortOrder = .recent
    @State private var savedForumPDFs: [UUID: ExportedPDF] = [:]
    @State private var activeLibraryOperation: IChartLibraryOperation?
    @State private var activeLibraryOperationID = UUID()

    init(onOpenChart: @escaping (Chart.ID, EditorCanvasMode) -> Void) {
        self.onOpenChart = onOpenChart
    }

    private var filteredCharts: [Chart] {
        LibraryRetrievalPolicy.items(store.charts, query: chartSearchText, order: chartSortOrder,
            title: { $0.title }, date: { $0.updatedAt })
    }

    private var filteredProjects: [ChartProject] {
        LibraryRetrievalPolicy.items(store.projects, query: projectSearchText, order: projectSortOrder,
            title: { $0.title }, date: { $0.updatedAt })
    }

    private var filteredPDFs: [IChartPDFLibraryItem] {
        LibraryRetrievalPolicy.items(
            pdfLibraryStore.visibleItems(for: store.subscriptionState, accessPolicy: store.entitlements.accessPolicy),
            query: pdfSearchText, order: pdfSortOrder,
            title: { $0.displayTitle + " " + $0.fileName }, date: { $0.createdAt })
    }

    private var chartCountText: String {
        let count = store.charts.count
        return count == 1 ? "1 chart" : "\(count) charts"
    }

    private var homeAppearanceMode: IChartHomeAppearanceMode {
        IChartHomeAppearanceMode(rawValue: homeAppearanceModeRawValue) ?? .light
    }

    private var homeAppearanceModeBinding: Binding<IChartHomeAppearanceMode> {
        Binding(
            get: { homeAppearanceMode },
            set: { homeAppearanceModeRawValue = $0.rawValue }
        )
    }

    private var homeTheme: IChartHomeTheme {
        IChartHomeTheme(mode: homeAppearanceMode)
    }

    private var chartPreviewMode: IChartChartPreviewMode {
        IChartChartPreviewMode(rawValue: chartPreviewModeRawValue) ?? .collapsed
    }

    private var activeChartPreviewMode: IChartChartPreviewMode {
        store.isChartEditingLockedByCurrentPlan ? .collapsed : chartPreviewMode
    }

    private var chartPreviewModeBinding: Binding<IChartChartPreviewMode> {
        Binding(
            get: { chartPreviewMode },
            set: { chartPreviewModeRawValue = $0.rawValue }
        )
    }

    private var chartsWorkspaceMode: IChartChartsWorkspaceMode {
        IChartChartsWorkspaceMode(rawValue: chartsWorkspaceModeRawValue) ?? .charts
    }

    private var chartsWorkspaceModeBinding: Binding<IChartChartsWorkspaceMode> {
        Binding(
            get: { chartsWorkspaceMode },
            set: { chartsWorkspaceModeRawValue = $0.rawValue }
        )
    }

    private var chartUsageText: String? {
        guard let limit = store.entitlements.localChartLimit else {
            return nil
        }

        guard store.canCreateChart else {
            return store.chartCapacityText
        }

        return "\(min(store.charts.count, limit)) of \(limit) Basic charts used"
    }

    private var chartEditingLockMessage: String {
        if store.localChartOverflowCount == 1 {
            return "Delete 1 local chart to edit in Basic."
        }

        return "Delete \(store.localChartOverflowCount) local charts to edit in Basic."
    }

    var body: some View {
        HStack(spacing: 0) {
            IChartHomeSidebar(
                logoVariant: logoVariant,
                selectedTab: $selectedHomeTab,
                appearanceMode: homeAppearanceModeBinding,
                isCollapsed: $isSidebarCollapsed,
                onSelectTab: handleHomeTabSelection
            )

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            libraryContentWithTour
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IChartLibraryBackground(mode: homeAppearanceMode).ignoresSafeArea())
        .tint(homeTheme.actionText)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let activeLibraryOperation {
                IChartLibraryOperationOverlay(message: activeLibraryOperation.message)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: activeLibraryOperation)
        .task {
            cloudSyncStore.attach(libraryStore: store)
            await authStore.bootstrap()
            synchronizeBetaAccess(authStore.state)
            cloudSyncStore.authStateChanged(authStore.state)
            forumStore.applyAccess(
                entitlements: store.entitlements,
                charts: store.charts,
                currentUserID: authStore.state.signedInSession?.id
            )
            refreshForumHomeIfVisible()
            updateAccountLandingPresentation()
        }
        .onChange(of: authStore.state) { _, state in
            synchronizeBetaAccess(state)
            cloudSyncStore.authStateChanged(state)
            forumStore.applyAccess(
                entitlements: store.entitlements,
                charts: store.charts,
                currentUserID: state.signedInSession?.id
            )
            refreshForumHomeIfVisible(authState: state)
            updateAccountLandingPresentation()
        }
        .onChange(of: store.entitlements) { _, _ in
            cloudSyncStore.authStateChanged(authStore.state)
            forumStore.applyAccess(entitlements: store.entitlements, charts: store.charts,
                currentUserID: authStore.state.signedInSession?.id)
            applyForumDownloadAccess(store.subscriptionState)
            selectedPDFIDs.formIntersection(Set(pdfLibraryStore.visibleItems(for: store.subscriptionState, accessPolicy: store.entitlements.accessPolicy).map(\.id)))
            refreshForumHomeIfVisible()
        }
        .onChange(of: store.charts.map(\.id)) { _, ids in
            selectedChartIDs.formIntersection(Set(ids))
            forumStore.applyAccess(entitlements: store.entitlements, charts: store.charts,
                currentUserID: authStore.state.signedInSession?.id)
        }
        .onChange(of: pdfLibraryStore.items.map(\.id)) { _, _ in
            selectedPDFIDs.formIntersection(Set(pdfLibraryStore.visibleItems(for: store.subscriptionState, accessPolicy: store.entitlements.accessPolicy).map(\.id)))
        }
        .onChange(of: chartsWorkspaceModeRawValue) { _, _ in
            isSelectingCharts = false
            selectedChartIDs.removeAll()
        }
        // Observe save events, not only unequal states: a second attempt can
        // fail with the exact same error and must still tell the user.
        .onReceive(store.$persistenceStatus.dropFirst()) { status in
            guard awaitingChartDeleteSave else { return }
            switch status {
            case .failed(let message):
                awaitingChartDeleteSave = false
                presentLibraryError("Chart deletion could not be saved. Your library changes are still pending on this device. \(message)")
            case .saved:
                awaitingChartDeleteSave = false
            case .ready, .notTracking:
                break
            }
        }
        .sheet(isPresented: $showingLayoutPicker, onDismiss: {
            pendingProjectForNewChart = nil
            if let chartID = createdChartToOpen {
                createdChartToOpen = nil
                onOpenChart(chartID, .browse)
            }
        }) {
            NewChartCreationView(
                highlightsSimpleLayout: guidedTourStep == .simpleChart,
                onSkipTour: finishGuidedTour
            ) { preparedChart in
                createNewChart(preparedChart: preparedChart)
            }
        }
        .fullScreenCover(isPresented: $showingAccountLanding) {
            IChartFirstRunAccountLandingView(
                authStore: authStore,
                theme: homeTheme,
                onContinue: completeFirstRunAccountLanding
            )
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showingCreateProject) {
            IChartProjectFormSheet(
                title: "New Project",
                initialTitle: "",
                saveTitle: "Create",
                theme: homeTheme
            ) { title in
                let projectCountBefore = store.projects.count
                if store.createProject(title: title) != nil {
                    IChartTelemetry.record(
                        "library.project_created",
                        properties: [
                            "project_count": .int(projectCountBefore + 1),
                            "chart_count": .int(store.charts.count),
                            "result": .string("created")
                        ]
                    )
                }
            }
        }
        .sheet(item: $renameRequest) { request in
            RenameChartSheetView(request: request) { chartID, title in
                store.renameChart(id: chartID, to: title)
            }
        }
        .sheet(item: $renameProjectRequest) { request in
            IChartProjectFormSheet(
                title: "Rename Project",
                initialTitle: request.currentTitle,
                saveTitle: "Save",
                theme: homeTheme
            ) { title in
                store.renameProject(id: request.projectID, to: title)
            }
        }
        .sheet(item: $addChartsRequest) { request in
            IChartProjectAddChartsSheet(
                request: request,
                charts: store.charts,
                theme: homeTheme
            ) { chartID, projectID in
                store.addChartToProject(chartID: chartID, projectID: projectID)
            }
        }
        .sheet(item: $duplicateVariantRequest) { request in
            IChartProjectDuplicateVariantSheet(
                request: request,
                theme: homeTheme
            ) { chartID, projectID, title, transpositionView in
                let chartCountBefore = store.charts.count
                let duplicateID = store.duplicateChart(
                    id: chartID,
                    title: title,
                    transpositionView: transpositionView,
                    projectID: projectID
                )
                IChartTelemetry.record(
                    "library.chart_duplicated",
                    properties: [
                        "chart_count_before": .int(chartCountBefore),
                        "chart_count_after": .int(store.charts.count),
                        "result": .string(duplicateID == nil ? "blocked" : "duplicated"),
                        "source": .string("project_variant")
                    ]
                )
                return duplicateID
            }
        }
        .sheet(item: $forumPublishRequest) { request in
            IChartForumPublishSheet(
                request: request,
                theme: homeTheme
            ) { chart, draft in
                forumStore.enqueuePublish(
                    chart: chart,
                    draft: draft,
                    ownerID: authStore.state.signedInSession?.id
                )
                forumPublishRequest = nil
                selectedHomeTab = .forums
            }
        }
        .sheet(
            isPresented: Binding(
                get: { forumStore.selectedDetail != nil },
                set: { isPresented in
                    if !isPresented {
                        forumStore.clearSelectedDetail()
                    }
                }
            )
        ) {
            if let detail = forumStore.selectedDetail {
                IChartForumPostDetailView(
                    detail: detail,
                    currentUserID: authStore.state.signedInSession?.id,
                    downloadedPDF: forumStore.downloadedPDF,
                    isPDFSaved: savedForumPDFs[detail.post.id].flatMap { pdfLibraryStore.itemID(forExportedURL: $0.url) } != nil,
                    savedPDFItemID: savedForumPDFs[detail.post.id].flatMap { saved in
                        pdfLibraryStore.itemID(forExportedURL: saved.url)
                    },
                    isWorking: forumStore.isWorking || forumStore.isLoadingEarlierComments,
                    isLoadingEarlierComments: forumStore.isLoadingEarlierComments,
                    errorMessage: forumStore.errorMessage,
                    theme: homeTheme,
                    onVote: { vote in
                        Task {
                            await forumStore.vote(vote, on: detail)
                        }
                    },
                    onComment: { body in
                        await forumStore.addComment(body, to: detail)
                    },
                    onLoadEarlierComments: { await forumStore.loadEarlierComments() },
                    onReportPost: { reason in
                        Task {
                            await forumStore.reportPost(reason, detailText: nil, detail: detail)
                        }
                    },
                    onReportComment: { comment, reason in
                        Task {
                            await forumStore.reportComment(comment, reason: reason, detailText: nil, detail: detail)
                        }
                    },
                    onBlockUser: { ownerID, displayName in
                        Task {
                            await forumStore.blockUser(ownerID: ownerID, displayName: displayName)
                        }
                    },
                    onDownloadPDF: {
                        Task {
                            if let saved = savedForumPDFs[detail.post.id],
                               pdfLibraryStore.itemID(forExportedURL: saved.url) != nil {
                                forumStore.presentDownloadedPDF(saved)
                                return
                            }
                            guard let downloadedPDF = await forumStore.downloadPDF(for: detail) else {
                                return
                            }

                            do {
                                let libraryPDF = try pdfLibraryStore.save(downloadedPDF, source: .forumDownload)
                                savedForumPDFs[detail.post.id] = libraryPDF
                                forumStore.presentDownloadedPDF(libraryPDF)
                            } catch {
                                forumStore.showDownloadStorageError(
                                    "Couldn’t save this forum PDF to your library. \(error.localizedDescription)"
                                )
                            }
                        }
                    },
                    onClearDownloadedPDF: {
                        forumStore.clearDownloadedPDF()
                    },
                    onWithdrawPost: {
                        Task {
                            await forumStore.withdrawPost(detail)
                        }
                    },
                    onRemovePost: {
                        Task {
                            await forumStore.removePost(detail)
                        }
                    }
                )
            }
        }
        .sheet(item: $selectedAddToSetlistPDF) { item in
            AddPDFToSetlistSheet(pdfItemIDs: [item.id])
        }
        .sheet(item: $selectedPDFLibraryItem) { item in
            if let exportedPDF = pdfLibraryStore.exportedPDF(for: item) {
                PDFExportPreviewView(exportedPDF: exportedPDF, source: item.source, pdfItemID: item.id)
            } else {
                NavigationStack {
                    ContentUnavailableView(
                        "PDF Not Found",
                        systemImage: "doc.badge.exclamationmark",
                        description: Text("This PDF is no longer available on this device. Import a replacement in PDFs, then use Replace PDF in any affected setlist.")
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedPDFLibraryItem = nil
                            }
                        }
                    }
                }
            }
        }
        .alert(item: libraryAlertBinding) { item in
            switch item {
            case .deletion(let request):
                Alert(
                    title: Text(request.confirmationTitle),
                    message: Text(request.confirmationMessage),
                    primaryButton: .destructive(Text(request.deleteButtonTitle)) {
                        // Retire this presentation before removing its source
                        // row. The action retains the immutable confirmed IDs.
                        libraryAlert.dismiss(id: request.id)
                        performDeletion(request)
                    },
                    secondaryButton: .cancel {
                        libraryAlert.dismiss(id: request.id)
                    }
                )
            case .failure(let id, let message):
                Alert(
                    title: Text("Library Needs Attention"),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) {
                        libraryAlert.dismiss(id: id)
                    }
                )
            }
        }
    }

    private var libraryContentWithTour: some View {
        VStack(spacing: 0) {
            if let guidedTourStep, guidedTourStep != .simpleChart {
                IChartGuidedTourPrompt(
                    step: guidedTourStep,
                    theme: homeTheme,
                    onPrimaryAction: beginGuidedTour,
                    onSkip: finishGuidedTour
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .overlay(alignment: .bottom) {
                    Divider()
                        .overlay(homeTheme.panelBorder)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            selectedHomeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.16), value: guidedTourStep)
    }

    @ViewBuilder
    private var selectedHomeContent: some View {
        switch selectedHomeTab {
        case .charts:
            chartsHomeContent
        case .pdfs:
            pdfLibraryHomeContent
        case .setlists:
            SetlistsView()
        case .forums:
            forumsHomeContent
        case .help:
            helpHomeContent
        case .settings:
            settingsHomeContent
        }
    }

    private var chartsHomeContent: some View {
        homeScroll {
            VStack(alignment: .leading, spacing: 20) {
                IChartChartsWorkspaceModePicker(selection: chartsWorkspaceModeBinding, theme: homeTheme)

                switch chartsWorkspaceMode {
                case .charts:
                    chartsListHomeContent
                case .projects:
                    chartProjectsHomeContent
                }
            }
        }
    }

    private var chartsListHomeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            IChartNewChartControl(
                chartUsageText: chartUsageText,
                canCreateChart: store.canCreateChart,
                theme: homeTheme,
                isTourHighlighted: guidedTourStep == .newChart,
                onCreateChart: {
                    requestNewChart(projectID: nil)
                }
            )

            if store.requiresLocalChartPruningForCurrentPlan {
                IChartChartConsolidationNotice(
                    overflowCount: store.localChartOverflowCount,
                    theme: homeTheme
                )
            }

            chartListSection
        }
    }

    private var chartProjectsHomeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.canUse(.projects) {
                IChartProjectCreateControl(
                    projectCount: store.projects.count,
                    theme: homeTheme,
                    onCreateProject: {
                        showingCreateProject = true
                    }
                )

                libraryRetrievalControls(query: $projectSearchText, order: $projectSortOrder, noun: "Projects")

                if !store.projects.isEmpty && filteredProjects.isEmpty {
                    libraryNoMatches(noun: "projects", query: projectSearchText)
                }
                if store.projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects Yet",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a project to keep every chart for the same song together.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .foregroundStyle(homeTheme.workspaceTitle)
                    .background(homeTheme.emptyStateBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProjects) { project in
                            IChartProjectCard(
                                project: project,
                                charts: store.charts(in: project),
                                canCreateChart: store.canCreateChart,
                                canOpenCharts: store.canOpenChartsForEditing,
                                availableCharts: store.charts,
                                chartEditingLockMessage: chartEditingLockMessage,
                                theme: homeTheme,
                                onOpenChart: { chartID in
                                    openChartIfAllowed(chartID, initialCanvasMode: .browse)
                                },
                                onNewChart: { projectID in
                                    requestNewChart(projectID: projectID)
                                },
                                onAddExisting: { project in
                                    addChartsRequest = ChartProjectAddChartsRequest(project: project)
                                },
                                onDuplicateVariant: { chart, project in
                                    duplicateVariantRequest = ChartProjectDuplicateVariantRequest(
                                        project: project,
                                        chart: chart
                                    )
                                },
                                onRemoveChart: { chartID, projectID in
                                    store.removeChartFromProject(chartID: chartID, projectID: projectID)
                                },
                                onRenameProject: { project in
                                    renameProjectRequest = ChartProjectRenameRequest(project: project)
                                },
                                onDeleteProject: { projectID in
                                    let projectCountBefore = store.projects.count
                                    let didDelete = store.deleteProject(id: projectID)
                                    IChartTelemetry.record(
                                        "library.project_deleted",
                                        properties: [
                                            "project_count": .int(store.projects.count),
                                            "result": .string(didDelete ? "deleted" : "blocked"),
                                            "chart_count": .int(store.charts.count),
                                            "chart_count_before": .int(projectCountBefore)
                                        ]
                                    )
                                }
                            )
                        }
                    }
                }
            } else {
                IChartHomePanel(
                    title: "Projects",
                    systemImageName: "folder.badge.plus",
                    theme: homeTheme
                ) {
                    IChartLockedFeatureView(
                        title: "Projects require Pro",
                        message: IChartProductAccessPolicy.current.isFreeBeta
                            ? "Rejoin free Pro in Settings to use Projects. Your existing projects and charts are kept."
                            : "Upgrade to Pro to group every chart for the same song, duplicate section variants, and keep alternate parts together.",
                        systemImageName: "lock.folder",
                        theme: homeTheme,
                        onOpenSettings: { selectedHomeTab = .settings }
                    )
                }
            }
        }
    }

    private var pdfLibraryHomeContent: some View {
        homeScroll {
            IChartHomePanel(
                title: "PDF Library",
                systemImageName: "doc.richtext",
                theme: homeTheme
            ) {
                if let message = pdfLibraryStore.recoveryErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                IChartPDFImportButton(identifier: "pdf.library.import") { item in
                    selectedPDFLibraryItem = item
                }
                .buttonStyle(.borderedProminent)
                .tint(IChartHomeBrand.blue)
                .frame(maxWidth: .infinity, alignment: .center)
                libraryRetrievalControls(query: $pdfSearchText, order: $pdfSortOrder, noun: "PDFs")
                if !pdfSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredPDFs.isEmpty {
                    libraryNoMatches(noun: "PDFs", query: pdfSearchText)
                }
                librarySelectionBar(
                    isSelecting: $isSelectingPDFs,
                    selectedIDs: $selectedPDFIDs,
                    availableIDs: Set(filteredPDFs.map(\.id)),
                    noun: "PDFs"
                ) { shownSelectedIDs in
                    let items = filteredPDFs.filter { shownSelectedIDs.contains($0.id) }
                    libraryAlert.requestDeletion(IChartLibraryDeleteRequest(pdfs: items))
                }
                IChartPDFLibraryHomeView(
                    items: filteredPDFs,
                    theme: homeTheme,
                    isSelecting: isSelectingPDFs,
                    selectedIDs: selectedPDFIDs,
                    onOpen: { item in
                        if isSelectingPDFs {
                            toggleSelection(item.id, in: &selectedPDFIDs)
                            return
                        }
                        IChartTelemetry.record(
                            "library.pdf_library_opened",
                            properties: [
                                "source": .string(item.source.rawValue),
                                "page_count": .int(item.pageCount),
                                "pdf_size_bucket": .string(Self.pdfSizeBucket(item.fileSizeBytes))
                            ]
                        )
                        selectedPDFLibraryItem = item
                    },
                    onDelete: { item in
                        libraryAlert.requestDeletion(IChartLibraryDeleteRequest(pdfs: [item]))
                    },
                    onAddToSetlist: { item in selectedAddToSetlistPDF = item },
                    isFiltering: !pdfSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .task {
            pdfLibraryStore.reload()
        }
    }

    private var forumsHomeContent: some View {
        homeScroll(supportsTextEntry: false) {
            IChartHomePanel(
                title: "Forums",
                systemImageName: "bubble.left.and.bubble.right",
                theme: homeTheme
            ) {
                if store.canUse(.forums) {
                    IChartForumHomeView(
                        state: forumStore.state,
                        searchText: $forumSearchText,
                        submittedSearchText: $forumSubmittedSearchText,
                        charts: store.charts,
                        currentUserID: authStore.state.signedInSession?.id,
                        currentUserBadges: forumStore.currentUserBadges,
                        uploadQueue: forumStore.uploadQueue.filter { item in
                            guard let currentUserID = authStore.state.signedInSession?.id,
                                  let ownerID = item.ownerID else {
                                return false
                            }

                            return ownerID == currentUserID
                        },
                        statusMessage: forumStore.statusMessage,
                        errorMessage: forumStore.errorMessage,
                        theme: homeTheme,
                        onSearch: { query in
                            refreshForumHome(query: query)
                        },
                        onRefresh: {
                            refreshForumHome(query: forumSubmittedSearchText)
                        },
                        onPublishChart: { chart in
                            forumPublishRequest = IChartForumPublishRequest(chart: chart)
                        },
                        onRetryUpload: { item in
                            forumStore.retryUpload(
                                item,
                                charts: store.charts,
                                currentUserID: authStore.state.signedInSession?.id
                            )
                        },
                        onWithdrawUpload: { item in
                            Task {
                                await forumStore.withdrawUpload(item)
                            }
                        },
                        onDismissUpload: { item in
                            forumStore.clearUploadQueueItem(item)
                        },
                        onOpenPost: { song, post in
                            Task {
                                await forumStore.openPost(post, song: song)
                            }
                        },
                        onOpenAccount: { selectedHomeTab = .settings },
                        hasMoreSearchResults: forumStore.homeNextCursor != nil,
                        isLoadingMoreSearchResults: forumStore.isLoadingMoreHome,
                        onLoadMoreSearchResults: { Task { await forumStore.loadMoreHome() } }
                    )
                } else {
                    IChartLockedFeatureView(
                        title: "Forums require Pro",
                        message: IChartProductAccessPolicy.current.isFreeBeta
                            ? "Rejoin free Pro in Settings to use Forums. Your downloaded PDFs and queued charts are kept."
                            : "Upgrade to Pro to join iChart Forums.",
                        systemImageName: "lock.icloud",
                        theme: homeTheme,
                        onOpenSettings: { selectedHomeTab = .settings }
                    )
                }
            }
        }
    }

    private var settingsHomeContent: some View {
        homeScroll {
            VStack(spacing: 18) {
                IChartHomePanel(
                    title: "Settings",
                    systemImageName: "gearshape",
                    theme: homeTheme
                ) {
                    VStack(spacing: 0) {
                        IChartSettingsRow(
                            title: "Library",
                            value: chartCountText,
                            systemImageName: "doc.text",
                            theme: homeTheme
                        )
                    }
                }

                IChartHomePanel(
                    title: "Chord Recognition",
                    systemImageName: "pencil.and.scribble",
                    theme: homeTheme
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Rendering", selection: $manualRenderWithPreview) {
                            Text("Automatic").tag(false)
                            Text("Manual").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .foregroundStyle(homeTheme.panelTitle)
                        .accessibilityIdentifier("rendering-mode-picker")
                        .accessibilityHint("Automatic renders complete chords between strokes as you move on; pause to finish the last chord. Manual shows previews before you choose Render Chords or Review & Render.")

                        Text(manualRenderWithPreview
                            ? ChordInkWorkflowSettings.manualRenderingDescription
                            : ChordInkWorkflowSettings.automaticRenderingDescription)
                            .font(.caption)
                            .foregroundStyle(homeTheme.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                IChartHomePanel(
                    title: "Account",
                    systemImageName: "person.crop.circle.badge.checkmark",
                    theme: homeTheme
                ) {
                    IChartAccountSettings(
                        authStore: authStore,
                        theme: homeTheme,
                        requiresNameForSignup: true,
                        showsSignedInActions: true
                    )
                }

                IChartHomePanel(
                    title: "Plan",
                    systemImageName: store.entitlements.accessPolicy.includesAllFeatures ? "star.fill" : store.subscriptionState.systemImageName,
                    theme: homeTheme
                ) {
                    IChartPlanSettings(
                        store: store,
                        subscriptionStore: subscriptionStore,
                        forumStore: forumStore,
                        theme: homeTheme,
                        onSelectSubscriptionState: apply(subscriptionPreview:),
                        onForumQASampleDataChanged: { isEnabled in
                            forumStore.setQASampleDataEnabled(isEnabled)
                            Task {
                                await forumStore.refresh(authState: authStore.state, entitlements: store.entitlements)
                            }
                        }
                    )
                }

                IChartHomePanel(
                    title: "Cloud Backup",
                    systemImageName: "icloud.and.arrow.up",
                    theme: homeTheme
                ) {
                    IChartCloudSyncSettings(syncStore: cloudSyncStore, theme: homeTheme)
                }

                IChartHomePanel(
                    title: "Privacy",
                    systemImageName: "hand.raised",
                    theme: homeTheme
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Share app diagnostics", isOn: Binding(
                            get: { telemetryConsentVersion == IChartTelemetryConsentStore.currentVersion },
                            set: { IChartTelemetry.setConsentGranted($0) }
                        ))
                        .tint(IChartHomeBrand.blue)
                        .foregroundStyle(homeTheme.panelTitle)
                        .accessibilityIdentifier("telemetry-consent-toggle")
                        .accessibilityHint("Optional. Off by default. Does not change your app features or subscription.")

                        Text(IChartLegalLinks.diagnosticsNotice)
                            .font(.caption)
                            .foregroundStyle(homeTheme.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(IChartLegalLinks.diagnosticsWithdrawalNotice)
                            .font(.caption)
                            .foregroundStyle(homeTheme.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        IChartLegalLinksView()
                            .tint(homeTheme.actionText)
                    }
                }

                #if DEBUG && targetEnvironment(simulator)
                IChartHomePanel(
                    title: "Diagnostics",
                    systemImageName: "waveform.path.ecg",
                    theme: homeTheme
                ) {
                    IChartDiagnosticsSettings(
                        rhythmDiagnosticsEnabled: $rhythmDiagnosticsEnabled,
                        theme: homeTheme
                    )
                }
                #endif
            }
        }
    }

    private var helpHomeContent: some View {
        homeScroll(supportsTextEntry: false) {
            IChartHomePanel(
                title: "Help",
                systemImageName: "questionmark.circle",
                theme: homeTheme
            ) {
                VStack(spacing: 0) {
                    let activeTopic = selectedHelpTopic ?? .tutorial

                    ForEach(IChartHelpTopic.allCases) { topic in
                        IChartHelpTopicRow(
                            topic: topic,
                            isSelected: activeTopic == topic,
                            theme: homeTheme,
                            action: {
                                selectedHelpTopic = topic
                            }
                        )

                        if topic.id != IChartHelpTopic.allCases.last?.id {
                            Divider()
                                .overlay(homeTheme.panelBorder)
                                .padding(.leading, 44)
                        }
                    }

                    Divider()
                        .overlay(homeTheme.panelBorder)
                        .padding(.top, 8)

                    IChartHelpTopicDetail(
                        topic: activeTopic,
                        theme: homeTheme,
                        canStartGuidedTour: store.canCreateChart,
                        onStartGuidedTour: startGuidedTourFromHelp
                    )
                        .padding(.top, 16)
                }
            }
        }
    }

    private func homeScroll<Content: View>(
        supportsTextEntry: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .background {
                    if supportsTextEntry { IChartTypedSheetScrollSupport() }
                }
        }
    }

    private func libraryRetrievalControls(
        query: Binding<String>, order: Binding<LibrarySortOrder>, noun: String
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            librarySearchField(query: query, noun: noun)
            librarySortMenu(order: order)
        }
    }

    private func librarySearchField(query: Binding<String>, noun: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(homeTheme.panelSecondary)
            IChartTypedTextField(placeholder: "Search \(noun.lowercased())", text: query,
                borderStyle: .none, returnKeyType: .search,
                textColor: UIColor(homeTheme.panelTitle), placeholderColor: UIColor(homeTheme.panelSecondary),
                tintColor: UIColor(homeTheme.actionText),
                accessibilityIdentifier: "library.search.\(noun.lowercased())",
                accessibilityLabel: "Search \(noun)")
                .frame(minHeight: 44)
            if !query.wrappedValue.isEmpty {
                Button { query.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Clear \(noun.lowercased()) search")
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(homeTheme.emptyStateBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private func librarySortMenu(order: Binding<LibrarySortOrder>) -> some View {
        Menu {
            Picker("Sort", selection: order) {
                ForEach(LibrarySortOrder.allCases) { value in Text(value.title).tag(value) }
            }
        } label: {
            Label("Sort: \(order.wrappedValue.title)", systemImage: "arrow.up.arrow.down")
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Sort library")
    }

    private func libraryNoMatches(noun: String, query: String) -> some View {
        ContentUnavailableView("No Matching \(noun.capitalized)", systemImage: "magnifyingglass",
            description: Text("No \(noun) match “\(query)”. Clear the search to see the full library."))
            .frame(maxWidth: .infinity)
            .foregroundStyle(homeTheme.panelSecondary)
    }

    private var chartListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            libraryRetrievalControls(query: $chartSearchText, order: $chartSortOrder, noun: "Charts")
            if !store.charts.isEmpty && filteredCharts.isEmpty {
                libraryNoMatches(noun: "charts", query: chartSearchText)
            }
            HStack(spacing: 16) {
                librarySelectionBar(
                    isSelecting: $isSelectingCharts,
                    selectedIDs: $selectedChartIDs,
                    availableIDs: Set(filteredCharts.map(\.id)),
                    noun: "Charts"
                ) { shownSelectedIDs in
                    libraryAlert.requestDeletion(IChartLibraryDeleteRequest(charts: filteredCharts.filter { shownSelectedIDs.contains($0.id) }))
                }
                if store.canOpenChartsForEditing && !isSelectingCharts {
                    IChartPreviewModePicker(selection: chartPreviewModeBinding, theme: homeTheme)
                }
            }

            if store.charts.isEmpty {
                ContentUnavailableView(
                    "No Charts Yet",
                    systemImage: "music.note",
                    description: Text("Create a new chart to start writing.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .foregroundStyle(homeTheme.workspaceTitle)
                .background(homeTheme.emptyStateBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredCharts) { chart in
                        if isSelectingCharts {
                            IChartLibrarySelectionRow(
                                title: chart.title,
                                subtitle: chart.layoutStyle.displayText,
                                theme: homeTheme,
                                isSelected: selectedChartIDs.contains(chart.id)
                            ) {
                                toggleSelection(chart.id, in: &selectedChartIDs)
                            }
                        } else {
                        ProjectRowView(
                            chart: chart,
                            theme: homeTheme,
                            previewMode: activeChartPreviewMode,
                            isSelected: store.selectedChartID == chart.id,
                            canDuplicate: store.canCreateChart,
                            canShareToForum: store.canUse(.forums),
                            canOpenForEditing: store.canOpenChartsForEditing,
                            lockMessage: chartEditingLockMessage,
                            onOpen: {
                                openChartIfAllowed(chart.id, initialCanvasMode: .browse)
                            },
                            onRename: {
                                renameRequest = ChartRenameRequest(chart: chart)
                            },
                            onDuplicate: {
                                runLibraryOperation(.duplicatingChart(chart.title)) {
                                    let chartCountBefore = store.charts.count
                                    let duplicateID = store.duplicateChart(id: chart.id)
                                    IChartTelemetry.record(
                                        "library.chart_duplicated",
                                        properties: [
                                            "chart_count_before": .int(chartCountBefore),
                                            "chart_count_after": .int(store.charts.count),
                                            "result": .string(duplicateID == nil ? "blocked" : "duplicated"),
                                            "source": .string("chart_row")
                                        ]
                                    )
                                }
                            },
                            onShareToForum: {
                                forumPublishRequest = IChartForumPublishRequest(chart: chart)
                            },
                            onRemoveLocal: {
                                runLibraryOperation(.removingLocalChart(chart.title)) {
                                    store.pruneLocalChartForCurrentPlan(id: chart.id)
                                }
                            },
                            onDelete: {
                                libraryAlert.requestDeletion(IChartLibraryDeleteRequest(charts: [chart]))
                            }
                        )
                        }
                    }
                }
            }
        }
    }

    private var libraryAlertBinding: Binding<IChartLibraryAlertPresentation.Item?> {
        let presentedID = libraryAlert.item?.id
        return Binding(
            get: { libraryAlert.item },
            set: { item in
                if item == nil {
                    // SwiftUI may finish dismissing the previous alert after
                    // the next menu action. Never clear that newer request.
                    libraryAlert.dismiss(id: presentedID)
                }
            }
        )
    }

    private func handleHomeTabSelection(_ tab: IChartHomeTab) {
        isSelectingCharts = false
        isSelectingPDFs = false
        selectedChartIDs.removeAll()
        selectedPDFIDs.removeAll()
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedHomeTab = tab
        }

        if tab == .forums {
            IChartTelemetry.record(
                "forum.opened",
                properties: [
                    "auth_state": .string(authStore.state.telemetryValue),
                    "user_signed_in": .bool(authStore.state.signedInSession != nil),
                    "plan": .string(store.subscriptionState.effectivePlan.rawValue),
                    "subscription_status": .string(store.subscriptionState.status.rawValue)
                ]
            )
            forumStore.resumePendingUploads(
                charts: store.charts,
                currentUserID: authStore.state.signedInSession?.id
            )
            refreshForumHomeIfVisible()
        }

    }

    private func toggleSelection(_ id: UUID, in selection: inout Set<UUID>) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func librarySelectionBar(
        isSelecting: Binding<Bool>, selectedIDs: Binding<Set<UUID>>,
        availableIDs: Set<UUID>, noun: String, onDelete: @escaping (Set<UUID>) -> Void
    ) -> some View {
        let scope = LibraryRetrievalPolicy.selectionScope(selectedIDs: selectedIDs.wrappedValue, availableIDs: availableIDs)
        return HStack(spacing: 14) {
            if isSelecting.wrappedValue {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(scope.visibleIDs.count) selected in results")
                        .font(.subheadline.weight(.semibold))
                    if !scope.hiddenIDs.isEmpty {
                        Text("\(scope.hiddenIDs.count) selected outside this search")
                            .font(.caption)
                    }
                }
                Spacer()
                Button(selectedIDs.wrappedValue.isSuperset(of: availableIDs) ? "Deselect All" : "Select All") {
                    selectedIDs.wrappedValue = LibraryRetrievalPolicy.togglingVisibleSelection(
                        selectedIDs: selectedIDs.wrappedValue, availableIDs: availableIDs)
                }
                Button("Delete", role: .destructive) { onDelete(scope.visibleIDs) }
                    .disabled(scope.visibleIDs.isEmpty)
                    .accessibilityLabel("Delete \(scope.visibleIDs.count) selected \(noun.lowercased()) shown in results")
                Button("Done") {
                    isSelecting.wrappedValue = false
                    selectedIDs.wrappedValue.removeAll()
                }
            } else {
                Spacer()
                Button("Select") { isSelecting.wrappedValue = true }
                    .disabled(availableIDs.isEmpty)
                    .accessibilityLabel("Select \(noun.lowercased())")
            }
        }
        .frame(minHeight: 44)
        .foregroundStyle(homeTheme.workspaceTitle)
    }

    private func performDeletion(_ request: IChartLibraryDeleteRequest) {
        switch request.kind {
        case .charts:
            guard !request.ids.isDisjoint(with: store.charts.map(\.id)) else {
                selectedChartIDs.subtract(request.ids)
                isSelectingCharts = !selectedChartIDs.isEmpty
                return
            }
            let before = store.charts.count
            awaitingChartDeleteSave = true
            let count = store.deleteCharts(ids: request.ids)
            if count == 0, case .failed(let message) = store.persistenceStatus {
                awaitingChartDeleteSave = false
                presentLibraryError(message)
            } else {
                if count == 0 || store.persistenceStatus == .notTracking {
                    awaitingChartDeleteSave = false
                }
                selectedChartIDs.subtract(request.ids)
                isSelectingCharts = !selectedChartIDs.isEmpty
            }
            IChartTelemetry.record("library.chart_deleted", properties: [
                "chart_count_before": .int(before), "chart_count_after": .int(store.charts.count),
                "result": .string(count > 0 ? "deleted" : "blocked"),
                "source": .string("delete_confirmation")
            ])
        case .pdfs:
            do {
                try pdfLibraryStore.deleteItems(ids: request.ids)
                selectedPDFIDs.subtract(request.ids)
                isSelectingPDFs = !selectedPDFIDs.isEmpty
            } catch {
                selectedPDFIDs.formIntersection(Set(pdfLibraryStore.visibleItems(for: store.subscriptionState, accessPolicy: store.entitlements.accessPolicy).map(\.id)))
                isSelectingPDFs = !selectedPDFIDs.isEmpty
                presentLibraryError(error.localizedDescription)
            }
        }
    }

    private func presentLibraryError(_ message: String) {
        // Let the destructive confirmation finish dismissing before presenting
        // a save failure; competing alerts can otherwise hide the error.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            libraryAlert.presentFailure(message)
        }
    }

    private func requestNewChart(projectID: ChartProject.ID?) {
        pendingProjectForNewChart = projectID

        if guidedTourStep == .newChart {
            guidedTourStep = .simpleChart
        }

        showingLayoutPicker = true
    }

    private func openChartIfAllowed(_ chartID: Chart.ID, initialCanvasMode: EditorCanvasMode) {
        guard store.canOpenChartsForEditing else {
            store.selectedChartID = nil
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedHomeTab = .charts
                chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
            }
            return
        }

        onOpenChart(chartID, initialCanvasMode)
    }

    private func refreshForumHomeIfVisible(
        authState: IChartAuthState? = nil,
        entitlements: AppEntitlements? = nil
    ) {
        guard selectedHomeTab == .forums else {
            return
        }

        refreshForumHome(query: forumSubmittedSearchText, authState: authState, entitlements: entitlements)
    }

    private func refreshForumHome(
        query: String,
        authState: IChartAuthState? = nil,
        entitlements: AppEntitlements? = nil
    ) {
        // This belongs to the library, which survives tab changes. Track the
        // actual requested query rather than reseeding from an unsubmitted
        // field draft when the forum view appears or a refresh completes.
        forumSubmittedSearchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await forumStore.refresh(
                authState: authState ?? authStore.state,
                entitlements: entitlements ?? store.entitlements,
                query: query
            )
        }
    }

    private func createNewChart(preparedChart: Chart) -> Bool {
        let targetProjectID = pendingProjectForNewChart
        let startsGuidedSimpleChartTour = guidedTourStep == .simpleChart && preparedChart.layoutStyle == .simpleChordSheet
        let traceSpan = IChartPerformanceTrace.start("library.createNewChart", metadata: [
            "layoutStyle": preparedChart.layoutStyle.rawValue,
            "targetProject": targetProjectID == nil ? "none" : "present"
        ])
        guard store.createPreparedChart(preparedChart, projectID: targetProjectID) else {
            IChartPerformanceTrace.end(traceSpan, metadata: ["result": "blocked"])
            return false
        }
        pendingProjectForNewChart = nil
        createdChartToOpen = preparedChart.id
        showingLayoutPicker = false
        if guidedTourStep == .simpleChart { guidedTourStep = nil }
        if startsGuidedSimpleChartTour { pendingSimpleChartTour = true }
        IChartPerformanceTrace.end(traceSpan, metadata: ["result": "opened"])
        IChartTelemetry.record("library.chart_created", properties: [
            "layout_style": .string(preparedChart.layoutStyle.rawValue),
            "chart_count": .int(store.charts.count),
            "measure_count": .int(preparedChart.measures.count),
            "result": .string("created"),
            "source": .string(targetProjectID == nil ? "library" : "project")
        ])
        return true
    }

    private func runLibraryOperation(_ operation: IChartLibraryOperation, perform work: @escaping () -> Void) {
        let operationID = UUID()
        activeLibraryOperationID = operationID
        activeLibraryOperation = operation

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            work()
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard activeLibraryOperationID == operationID else {
                return
            }

            activeLibraryOperation = nil
        }
    }

    private static func pdfSizeBucket(_ byteCount: Int) -> String {
        switch byteCount {
        case ..<100_000:
            return "lt_100kb"
        case ..<500_000:
            return "100kb_500kb"
        case ..<1_000_000:
            return "500kb_1mb"
        case ..<5_000_000:
            return "1mb_5mb"
        default:
            return "gt_5mb"
        }
    }

    private func updateAccountLandingPresentation() {
        if IChartSimulatorPreviewLaunch.showsEditorUIFixture {
            showingAccountLanding = false
            return
        }

        let shouldPresent = authStore.state.shouldPresentFirstRunAccountLanding
            && (!hasSeenAccountLanding || !authStore.state.isVerifiedSignedIn)

        guard shouldPresent else {
            if showingAccountLanding {
                showingAccountLanding = false
            }
            return
        }

        guard !showingAccountLanding else {
            return
        }

        showingAccountLanding = true
    }

    private func completeFirstRunAccountLanding() {
        guard authStore.state.isVerifiedSignedIn else {
            return
        }

        hasSeenAccountLanding = true
        showingAccountLanding = false

        guard !hasSeenGuidedTourOffer else {
            return
        }

        selectedHomeTab = .charts
        chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
        guidedTourStep = .welcome
    }

    private func synchronizeBetaAccess(_ state: IChartAuthState) {
        guard IChartProductAccessPolicy.current.isFreeBeta, let betaProStore else { return }
        betaProStore.authStateChanged(state)
        store.applyAccessPolicy(betaProStore.freeProAccess ? .freeAllFeatures : .betaBasic)
    }

    private func apply(subscriptionPreview: IChartSubscriptionEntitlement) {
        withAnimation(.easeInOut(duration: 0.18)) {
            store.applySubscriptionState(subscriptionPreview)
        }
        applyForumDownloadAccess(subscriptionPreview)
        cloudSyncStore.authStateChanged(authStore.state)
    }

    private func applyForumDownloadAccess(_ subscription: IChartSubscriptionEntitlement) {
        pdfLibraryStore.removeForumDownloadsIfInactive(
            for: subscription,
            accessPolicy: store.entitlements.accessPolicy
        )
        if selectedPDFLibraryItem?.source == .forumDownload,
           !subscription.allowsForumDownloadAccess(accessPolicy: store.entitlements.accessPolicy) {
            selectedPDFLibraryItem = nil
        }
    }

    private func beginGuidedTour() {
        hasSeenGuidedTourOffer = true
        selectedHomeTab = .charts
        chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
        withAnimation(.easeInOut(duration: 0.18)) {
            guidedTourStep = .newChart
        }
    }

    private func startGuidedTourFromHelp() {
        guard store.canCreateChart else {
            return
        }

        hasSeenGuidedTourOffer = true
        selectedHelpTopic = .tutorial
        selectedHomeTab = .charts
        chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
        withAnimation(.easeInOut(duration: 0.18)) {
            guidedTourStep = .newChart
        }
    }

    private func finishGuidedTour() {
        hasSeenGuidedTourOffer = true
        pendingSimpleChartTour = false
        withAnimation(.easeInOut(duration: 0.18)) {
            guidedTourStep = nil
        }
    }
}

private struct ChartRenameRequest: Identifiable, Hashable {
    let chartID: Chart.ID
    let currentTitle: String

    var id: Chart.ID { chartID }

    init(chart: Chart) {
        chartID = chart.id
        currentTitle = chart.title
    }
}

private struct ChartProjectRenameRequest: Identifiable, Hashable {
    let projectID: ChartProject.ID
    let currentTitle: String

    var id: ChartProject.ID { projectID }

    init(project: ChartProject) {
        projectID = project.id
        currentTitle = project.title
    }
}

private struct ChartProjectAddChartsRequest: Identifiable, Hashable {
    let project: ChartProject

    var id: ChartProject.ID { project.id }
}

private struct ChartProjectDuplicateVariantRequest: Identifiable, Hashable {
    let project: ChartProject
    let chart: Chart

    var id: String {
        "\(project.id.uuidString)-\(chart.id.uuidString)"
    }
}

private struct IChartLibraryOperation: Equatable {
    let message: String

    static func creatingChart(_ layoutName: String) -> IChartLibraryOperation {
        IChartLibraryOperation(message: "Creating \(layoutName)...")
    }

    static func duplicatingChart(_ title: String) -> IChartLibraryOperation {
        IChartLibraryOperation(message: "Duplicating \(title)...")
    }

    static func deletingChart(_ title: String) -> IChartLibraryOperation {
        IChartLibraryOperation(message: "Deleting \(title)...")
    }

    static func removingLocalChart(_ title: String) -> IChartLibraryOperation {
        IChartLibraryOperation(message: "Removing \(title)...")
    }
}

private struct IChartLibraryOperationOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

private struct RenameChartSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChartRenameRequest
    let onSave: (Chart.ID, String) -> Void
    @State private var title: String
    @State private var isTitleFocused = false

    init(
        request: ChartRenameRequest,
        onSave: @escaping (Chart.ID, String) -> Void
    ) {
        self.request = request
        self.onSave = onSave
        _title = State(initialValue: request.currentTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IChartTypedTextField(placeholder: "Chart title", text: $title, isFocused: $isTitleFocused,
                        autocapitalizationType: .words, autocorrectionType: .yes)
                        .frame(minHeight: 44)
                        .background(IChartTypedSheetScrollSupport())
                }
            }
            .navigationTitle("Rename Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(sanitizedTitle.isEmpty)
                }
            }
        }
    }

    private var sanitizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !sanitizedTitle.isEmpty else {
            return
        }

        onSave(request.chartID, sanitizedTitle)
        dismiss()
    }
}

private struct NewChartLayoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let tourStep: IChartGuidedTourStep?
    let onSelect: (ChartLayoutStyle) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let tourStep {
                        IChartGuidedTourSheetCallout(step: tourStep)
                    }

                    ForEach(ChartLayoutStyle.v1NewChartOptions) { layoutStyle in
                        let isTourTarget = tourStep == .simpleChart && layoutStyle == .simpleChordSheet

                        Button {
                            onSelect(layoutStyle)
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: layoutStyle.systemImageName)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(IChartHomeBrand.blue)
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(layoutStyle.displayText)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(layoutStyle.detailText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 12)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                isTourTarget
                                    ? IChartHomeBrand.blueSoft.opacity(0.72)
                                    : IChartHomeBrand.paper.opacity(0.82)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .tourActionHighlight(
                            isActive: isTourTarget,
                            cornerRadius: 10,
                            tint: IChartHomeBrand.blue
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("New Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

}

private struct IChartGuidedTourPrompt: View {
    let step: IChartGuidedTourStep
    let theme: IChartHomeTheme
    let onPrimaryAction: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartTourStyle.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tourTitleColor)

                Text(step.message)
                    .font(.subheadline)
                    .foregroundStyle(tourMessageColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let targetText = step.targetText {
                Label(targetText, systemImage: "hand.tap")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IChartTourStyle.navy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(IChartTourStyle.orangeSoft.opacity(theme.isDark ? 0.86 : 1))
                    .clipShape(Capsule())
            }

            if let primaryActionTitle = step.primaryActionTitle {
                Button(primaryActionTitle, action: onPrimaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(IChartInterfaceStyle.actionBlue)
                    .foregroundStyle(Color.white)
                    .fixedSize()
            }

            Button(action: onSkip) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(tourTitleColor.opacity(0.72))
            .accessibilityLabel("End Quick Start")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tourPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var tourTitleColor: Color {
        IChartInterfaceStyle.guidanceTitle
    }

    private var tourMessageColor: Color {
        IChartInterfaceStyle.guidanceText
    }

    private var tourPanelBackground: Color {
        IChartInterfaceStyle.guidanceBackground
    }
}

private struct IChartGuidedTourSheetCallout: View {
    let step: IChartGuidedTourStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartTourStyle.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(IChartInterfaceStyle.guidanceTitle)

                Text(step.message)
                    .font(.subheadline)
                    .foregroundStyle(IChartInterfaceStyle.guidanceText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IChartInterfaceStyle.guidanceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct IChartProjectFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initialTitle: String
    let saveTitle: String
    let theme: IChartHomeTheme
    let onSave: (String) -> Void
    @State private var projectTitle: String
    @State private var isProjectTitleFocused = false

    init(
        title: String,
        initialTitle: String,
        saveTitle: String,
        theme: IChartHomeTheme,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.saveTitle = saveTitle
        self.theme = theme
        self.onSave = onSave
        _projectTitle = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IChartTypedTextField(placeholder: "Song or project title", text: $projectTitle,
                        isFocused: $isProjectTitleFocused, autocapitalizationType: .words, autocorrectionType: .yes)
                        .frame(minHeight: 44)
                        .background(IChartTypedSheetScrollSupport())
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        save()
                    }
                    .disabled(sanitizedTitle.isEmpty)
                }
            }
        }
    }

    private var sanitizedTitle: String {
        projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !sanitizedTitle.isEmpty else {
            return
        }

        onSave(sanitizedTitle)
        dismiss()
    }
}

private struct IChartProjectAddChartsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChartProjectAddChartsRequest
    let charts: [Chart]
    let theme: IChartHomeTheme
    let onAddChart: (Chart.ID, ChartProject.ID) -> Void

    private var availableCharts: [Chart] {
        charts.filter { !request.project.chartIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableCharts.isEmpty {
                    ContentUnavailableView(
                        "No Charts To Add",
                        systemImage: "doc.badge.plus",
                        description: Text("Every local chart is already in this project.")
                    )
                    .padding(.vertical, 32)
                } else {
                    ForEach(availableCharts) { chart in
                        Button {
                            onAddChart(chart.id, request.project.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: chart.layoutStyle.systemImageName)
                                    .foregroundStyle(theme.actionText)
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chart.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(chart.librarySummaryText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)

                                Image(systemName: "plus.circle")
                                    .foregroundStyle(theme.actionText)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add To \(request.project.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct IChartProjectDuplicateVariantSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChartProjectDuplicateVariantRequest
    let theme: IChartHomeTheme
    let onSave: (Chart.ID, ChartProject.ID, String, TranspositionView) -> Chart.ID?
    @State private var title: String
    @State private var selectedTranspositionView: TranspositionView
    @State private var isTitleFocused = false

    init(
        request: ChartProjectDuplicateVariantRequest,
        theme: IChartHomeTheme,
        onSave: @escaping (Chart.ID, ChartProject.ID, String, TranspositionView) -> Chart.ID?
    ) {
        self.request = request
        self.theme = theme
        self.onSave = onSave
        _title = State(initialValue: "\(request.chart.title) Copy")
        _selectedTranspositionView = State(initialValue: request.chart.defaultTranspositionView)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.chart.title)
                            .font(.headline.weight(.semibold))

                        Text(request.chart.librarySummaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Variant Title")
                            .font(.headline)

                        IChartTypedTextField(placeholder: "Horn section chart", text: $title,
                            isFocused: $isTitleFocused, autocapitalizationType: .words, autocorrectionType: .yes)
                            .frame(minHeight: 44)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instrument Transposition")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                            ForEach(TranspositionView.instrumentOptions) { view in
                                Button {
                                    selectedTranspositionView = view
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(view.displayText)
                                            .font(.subheadline.weight(.semibold))

                                        Text(view.intervalDisplayText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(selectedTranspositionView == view ? IChartHomeBrand.blue : .secondary.opacity(0.3))
                            }
                        }
                    }
                }
                .padding(24)
                .background(IChartTypedSheetScrollSupport())
            }
            .navigationTitle("Duplicate Variant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard onSave(
                            request.chart.id,
                            request.project.id,
                            title,
                            selectedTranspositionView
                        ) != nil else {
                            return
                        }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct IChartChartConsolidationNotice: View {
    let overflowCount: Int
    let theme: IChartHomeTheme

    var body: some View {
        IChartHomePanel(
            title: "Consolidate Charts",
            systemImageName: "trash",
            theme: theme
        ) {
            Text("Choose \(overflowCount) local chart\(overflowCount == 1 ? "" : "s") to remove from this device to continue in Basic. Editing unlocks when 3 charts remain. Cloud backup is removed after Pro access ends.")
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IChartLockedFeatureView: View {
    let title: String
    let message: String
    let systemImageName: String
    let theme: IChartHomeTheme
    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(title, systemImage: systemImageName, description: Text(message))
            if let onOpenSettings {
                Button("Open Plan Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(IChartHomeBrand.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .foregroundStyle(theme.panelSecondary)
    }
}

struct IChartForumPublishRequest: Identifiable {
    let chart: Chart

    var id: Chart.ID { chart.id }
}

private struct IChartLibrarySelectionRow: View {
    let title: String
    let subtitle: String
    let theme: IChartHomeTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? theme.actionText : theme.panelSecondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(theme.panelSecondary).lineLimit(1)
                }
                Spacer()
            }
            .foregroundStyle(theme.panelTitle)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(isSelected ? theme.selectionBackground : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                Divider().overlay(theme.panelBorder.opacity(0.28))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct IChartPDFLibraryHomeView: View {
    let items: [IChartPDFLibraryItem]
    let theme: IChartHomeTheme
    let isSelecting: Bool
    let selectedIDs: Set<UUID>
    let onOpen: (IChartPDFLibraryItem) -> Void
    let onDelete: (IChartPDFLibraryItem) -> Void
    let onAddToSetlist: (IChartPDFLibraryItem) -> Void
    var isFiltering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import a PDF from Files, or find your exports and forum downloads here. Add saved PDFs to a setlist for offline reading.")
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            ForEach(IChartPDFLibrarySource.allCases.filter { source in
                !isFiltering || items.contains { $0.source == source }
            }) { source in
                IChartPDFLibrarySection(
                    source: source,
                    items: items.filter { $0.source == source },
                    theme: theme,
                    isSelecting: isSelecting,
                    selectedIDs: selectedIDs,
                    onOpen: onOpen,
                    onDelete: onDelete,
                    onAddToSetlist: onAddToSetlist
                )
            }
        }
    }
}

private struct IChartPDFLibrarySection: View {
    let source: IChartPDFLibrarySource
    let items: [IChartPDFLibraryItem]
    let theme: IChartHomeTheme
    let isSelecting: Bool
    let selectedIDs: Set<UUID>
    let onOpen: (IChartPDFLibraryItem) -> Void
    let onDelete: (IChartPDFLibraryItem) -> Void
    let onAddToSetlist: (IChartPDFLibraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: source.systemImageName)
                    .foregroundStyle(IChartTourStyle.orange)
                    .frame(width: 22)

                Text(source.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
                    .multilineTextAlignment(.center)

                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)

            if items.isEmpty {
                ContentUnavailableView(
                    source.emptyTitle,
                    systemImage: source.systemImageName,
                    description: Text(source.emptyMessage)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .foregroundStyle(theme.panelSecondary)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        if isSelecting {
                            IChartLibrarySelectionRow(
                                title: item.displayTitle,
                                subtitle: item.fileName,
                                theme: theme,
                                isSelected: selectedIDs.contains(item.id)
                            ) { onOpen(item) }
                        } else {
                        IChartPDFLibraryRow(
                            item: item,
                            theme: theme,
                            onOpen: {
                                onOpen(item)
                            },
                            onDelete: {
                                onDelete(item)
                            },
                            onAddToSetlist: { onAddToSetlist(item) }
                        )
                        }
                    }
                }
            }
        }
    }
}

private struct IChartPDFLibraryRow: View {
    let item: IChartPDFLibraryItem
    let theme: IChartHomeTheme
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onAddToSetlist: () -> Void

    private var metadata: [String] {
        [item.source.itemTitle, item.layoutStyle?.displayText, item.transpositionText,
         item.pageCountText].compactMap { $0 }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.actionText)
                        .frame(width: 36, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.panelTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.fileName)
                            .font(.caption)
                            .foregroundStyle(theme.panelSecondary)
                            .lineLimit(2)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 6) {
                            ForEach(Array(metadata.enumerated()), id: \.offset) { _, text in
                                Text(text)
                                    .font(.caption)
                                    .foregroundStyle(theme.panelSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.displayTitle)")
            .accessibilityIdentifier("pdf.library.open.\(item.id.uuidString)")

            Menu {
                Button(action: onOpen) { Label("Open PDF", systemImage: "doc.richtext") }
                Button(action: onAddToSetlist) { Label("Add to Setlist", systemImage: "text.badge.plus") }
                Button(role: .destructive, action: onDelete) { Label("Delete PDF", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Actions for \(item.displayTitle)")
        }
        .padding(12)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.panelBorder.opacity(0.32))
        }
    }
}

struct IChartForumHomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let state: IChartForumState
    @Binding var searchText: String
    @Binding var submittedSearchText: String
    let charts: [Chart]
    let currentUserID: UUID?
    let currentUserBadges: [ForumAuthorBadgeType]?
    let uploadQueue: [ForumUploadQueueItem]
    let statusMessage: String?
    let errorMessage: String?
    let theme: IChartHomeTheme
    let onSearch: (String) -> Void
    let onRefresh: () -> Void
    let onPublishChart: (Chart) -> Void
    let onRetryUpload: (ForumUploadQueueItem) -> Void
    let onWithdrawUpload: (ForumUploadQueueItem) -> Void
    let onDismissUpload: (ForumUploadQueueItem) -> Void
    let onOpenPost: (ForumSong, ForumChartPost) -> Void
    var onOpenAccount: (() -> Void)? = nil
    var hasMoreSearchResults = false
    var isLoadingMoreSearchResults = false
    var onLoadMoreSearchResults: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsSearchControls {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search songs, artists, arrangers, or tags, then tap Search. Use Load More for more matches. Open a chart to save its PDF or discuss it.")
                        .font(.subheadline)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("forum.search.instructions")
                    searchAndPublishRow
                }
            }

            if let summaries = loadedSummaries {
                IChartForumCommunityHero(
                    featuredPosts: featuredPosts(from: summaries),
                    currentUserID: currentUserID,
                    currentUserBadges: currentUserBadges,
                    theme: theme
                )
            }

            if let errorMessage {
                IChartForumStatusBanner(text: errorMessage, systemImageName: "exclamationmark.triangle.fill", color: .orange, theme: theme)
            }

            if let statusMessage {
                IChartForumStatusBanner(text: statusMessage, systemImageName: "checkmark.circle.fill", color: .green, theme: theme)
            }

            if !uploadQueue.isEmpty {
                IChartForumUploadQueueView(
                    items: uploadQueue,
                    theme: theme,
                    onRetry: onRetryUpload,
                    onWithdraw: onWithdrawUpload,
                    onDismiss: onDismissUpload
                )
            }

            forumStateContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IChartTypedSheetScrollSupport())
    }

    private var loadedSummaries: [IChartForumSongSummary]? {
        guard case .loaded(let summaries) = state else {
            return nil
        }

        return summaries
    }

    private var showsSearchControls: Bool {
        switch state {
        case .loading, .loaded, .failed:
            true
        case .unconfigured, .signedOut, .requiresPro:
            false
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingSearchResults: Bool {
        !submittedSearchText.isEmpty
    }

    private var searchAndPublishRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.panelSecondary)
                IChartTypedTextField(
                    placeholder: "Search songs, artists, arrangers, or tags",
                    text: $searchText,
                    autocapitalizationType: .words,
                    autocorrectionType: .default,
                    borderStyle: .none,
                    returnKeyType: .search,
                    textColor: UIColor(theme.panelTitle),
                    placeholderColor: UIColor(theme.panelSecondary.opacity(theme.isDark ? 0.95 : 1.0)),
                    tintColor: UIColor(IChartHomeBrand.logoBlue),
                    accessibilityIdentifier: "forum.search",
                    accessibilityLabel: "Forum search",
                    accessibilityHint: "Search song titles, artists, arrangers, or tags, then tap Search.",
                    onSubmit: submitSearch
                )
                    .frame(minHeight: 44)
                    .onChange(of: searchText) { _, newValue in
                        handleSearchTextChange(newValue)
                    }
            }
            .padding(.horizontal, 12)
            .background(theme.panelBackground.opacity(theme.isDark ? 0.94 : 0.84))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.isDark ? Color.white.opacity(0.18) : theme.panelBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }

            Button {
                submitSearch()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(IChartHomeBrand.blue)
            .accessibilityIdentifier("forum.search.submit")
            .accessibilityHint("Show charts matching the search text.")
        }
    }

    @ViewBuilder
    private var forumStateContent: some View {
        switch state {
        case .unconfigured:
            ContentUnavailableView(
                "Community Library Unavailable",
                systemImage: "wifi.slash",
                description: Text("We can’t reach community charts right now. Your local charts are safe, and this page will work again when service returns.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        case .signedOut:
            VStack(spacing: 12) {
                ContentUnavailableView("Sign In Required", systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Forums use verified account identity so charts and comments are never anonymous."))
                if let onOpenAccount {
                    Button("Sign In", action: onOpenAccount)
                        .buttonStyle(.borderedProminent)
                        .tint(IChartHomeBrand.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        case .requiresPro:
            VStack(spacing: 12) {
                ContentUnavailableView("Forums Require Pro", systemImage: "lock.icloud",
                    description: Text("Open Settings to rejoin free Pro or check your current plan."))
                if let onOpenAccount {
                    Button("Open Plan Settings", action: onOpenAccount)
                        .buttonStyle(.borderedProminent)
                        .tint(IChartHomeBrand.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        case .loading:
            ProgressView("Loading community charts...")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
        case .failed(let message):
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "Community Library Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message.isEmpty ? "We can’t reach community charts right now. Your local charts are safe, and this page will work again when service returns." : message)
                )
                Button(action: onRefresh) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(IChartHomeBrand.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        case .loaded(let summaries):
            let featuredPosts = featuredPosts(from: summaries)
            LazyVStack(alignment: .leading, spacing: 18) {
                IChartForumTopChartsBoard(
                    featuredPosts: featuredPosts,
                    isSearching: isShowingSearchResults,
                    theme: theme,
                    onOpenPost: onOpenPost
                )

                IChartForumEmptyPublishBar(
                    localCharts: charts,
                    isSearching: isShowingSearchResults,
                    theme: theme,
                    onPublishChart: onPublishChart
                )

                if isShowingSearchResults {
                    if summaries.isEmpty {
                        IChartForumInlineEmptyRow(
                            title: "No Chart On This Tune Yet",
                            message: "A matching local chart can become the first reviewed PDF for this search.",
                            systemImageName: "magnifyingglass",
                            theme: theme
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            IChartForumSectionHeader(
                                title: "Search Results",
                                subtitle: "Results for “\(submittedSearchText)” · grouped by song.",
                                theme: theme,
                            )

                            ForEach(summaries) { summary in
                                IChartForumSongCard(
                                    summary: summary,
                                    theme: theme,
                                    onOpenPost: { post in
                                        onOpenPost(summary.song, post)
                                    }
                                )
                            }
                            if hasMoreSearchResults {
                                Button(action: onLoadMoreSearchResults) {
                                    HStack(spacing: 8) {
                                        if isLoadingMoreSearchResults { ProgressView() }
                                        Text(isLoadingMoreSearchResults ? "Loading More…" : "Load More")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isLoadingMoreSearchResults)
                                .accessibilityIdentifier("forum.search.load-more")
                                .accessibilityHint("Load the next page of charts matching this submitted search.")
                            }
                        }
                    }
                }
            }
        }
    }

    private func submitSearch() {
        submittedSearchText = trimmedSearchText
        onSearch(searchText)
    }

    private func handleSearchTextChange(_ newValue: String) {
        guard LibraryRetrievalPolicy.shouldRestoreForumBrowsing(
            editedQuery: newValue, submittedQuery: submittedSearchText
        ) else { return }
        submittedSearchText = ""
        onSearch("")
    }

    private func featuredPosts(from summaries: [IChartForumSongSummary]) -> [IChartForumFeaturedPost] {
        summaries
            .flatMap { summary in
                summary.topPosts.map { post in
                    IChartForumFeaturedPost(song: summary.song, post: post, authorBadges: summary.badges(for: post))
                }
            }
            .sorted { lhs, rhs in
                if lhs.post.rankingScore == rhs.post.rankingScore {
                    return lhs.post.publishedAt > rhs.post.publishedAt
                }

                return lhs.post.rankingScore > rhs.post.rankingScore
            }
    }
}

private struct IChartForumFeaturedPost: Identifiable {
    let song: ForumSong
    let post: ForumChartPost
    let authorBadges: [ForumAuthorBadgeType]

    var id: UUID { post.id }
}

private enum IChartForumPalette {
    static let cornerRadius: CGFloat = 8
    static let primary = IChartHomeBrand.blue
    static let secondary = IChartHomeBrand.logoBlue
    static let soft = IChartHomeBrand.blueSoft

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                IChartHomeBrand.blue.opacity(0.92),
                IChartHomeBrand.logoBlue.opacity(0.54)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct IChartForumCommunityHero: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let featuredPosts: [IChartForumFeaturedPost]
    let currentUserID: UUID?
    let currentUserBadges: [ForumAuthorBadgeType]?
    let theme: IChartHomeTheme

    private var userPosts: [IChartForumFeaturedPost] {
        guard let currentUserID else {
            return []
        }

        return featuredPosts.filter { $0.post.ownerID == currentUserID }
    }

    private var userUpvoteCount: Int {
        userPosts.reduce(0) { total, featuredPost in
            total + max(0, featuredPost.post.voteUpCount)
        }
    }

    private var userTopRatedCount: Int {
        userPosts.filter { $0.post.qualityStatus == .topRated }.count
    }

    var body: some View {
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        VStack(alignment: .leading, spacing: 15) {
            headerLayout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Community Bandstand")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.panelTitle)

                    Text("Find working chord and rhythm PDFs, shout out clean charts, and help other musicians get through rehearsal faster.")
                        .font(.subheadline)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 12)
                }

                Label("iChart Pro", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [
                                IChartHomeBrand.blue,
                                IChartHomeBrand.blue.opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
                    .fixedSize(horizontal: true, vertical: false)
            }

            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible(minimum: 0))]
                : [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                statPill(value: "\(userPosts.count)", label: "Your Charts in View", systemImageName: "square.and.arrow.up")
                statPill(value: "\(userUpvoteCount)", label: "Upvotes in View", systemImageName: "hand.thumbsup")
                if let currentUserBadges {
                    statPill(value: "\(Set(currentUserBadges).count)", label: "Your Badges", systemImageName: "checkmark.seal")
                }
                statPill(value: "\(userTopRatedCount)", label: "Top Rated in View", systemImageName: "star.fill")
            }
            Text("Chart counts reflect your charts shown below. Badges reflect your account.")
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.panelBorder.opacity(0.32))
        }
    }

    private func statPill(value: String, label: String, systemImageName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImageName)
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.actionText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(theme.panelTitle)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

private struct IChartForumTopChartsBoard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let featuredPosts: [IChartForumFeaturedPost]
    let isSearching: Bool
    let theme: IChartHomeTheme
    let onOpenPost: (ForumSong, ForumChartPost) -> Void

    @State private var expandedPeriod: IChartForumTopChartPeriod?
    @State private var gridWidth: CGFloat = 0

    private var columns: [GridItem] {
        // A forum card needs room for its title, contributor and badge names.
        // Measure the grid itself so sidebar and panel padding count toward
        // the available width. Flexible columns can still shrink on a narrow
        // window; their minimum must not force the board past its bounds.
        let count = dynamicTypeSize.isAccessibilitySize
            ? 1 : min(4, max(1, Int((gridWidth + 10) / 230)))
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .top), count: count)
    }

    var body: some View {
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 12))
        VStack(alignment: .leading, spacing: 14) {
            headerLayout {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Top Charts")
                        .font(.title2.weight(.black))
                        .foregroundStyle(theme.panelTitle)

                    Text(isSearching ? "Ranked charts matching this search." : "The charts players are backing right now.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.panelSecondary)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 12)
                }

                Text("Top 10")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(IChartHomeBrand.blue)
                    .clipShape(Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(IChartForumTopChartPeriod.allCases) { period in
                    IChartForumTopChartColumn(
                        period: period,
                        featuredPosts: period.posts(from: featuredPosts),
                        isExpanded: expandedPeriod == period,
                        theme: theme,
                        onToggleExpansion: {
                            withAnimation(.snappy(duration: 0.22)) {
                                expandedPeriod = expandedPeriod == period ? nil : period
                            }
                        },
                        onOpenPost: onOpenPost
                    )
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { updateGridWidth(geometry.size.width) }
                        .onChange(of: geometry.size.width) { _, width in updateGridWidth(width) }
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.panelBorder.opacity(0.32))
        }
    }

    private func updateGridWidth(_ width: CGFloat) {
        guard width.isFinite, width >= 0, abs(gridWidth - width) > 0.5 else { return }
        gridWidth = width
    }
}

private enum IChartForumTopChartPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .week:
            return "This Week"
        case .month:
            return "This Month"
        case .allTime:
            return "All Time"
        }
    }

    var accent: Color {
        IChartHomeBrand.blue
    }

    func posts(from featuredPosts: [IChartForumFeaturedPost]) -> [IChartForumFeaturedPost] {
        let now = Date()
        let calendar = Calendar.current
        let filteredPosts: [IChartForumFeaturedPost]

        switch self {
        case .today:
            filteredPosts = featuredPosts.filter { calendar.isDateInToday($0.post.publishedAt) }
        case .week:
            let threshold = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            filteredPosts = featuredPosts.filter { $0.post.publishedAt >= threshold }
        case .month:
            let threshold = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            filteredPosts = featuredPosts.filter { $0.post.publishedAt >= threshold }
        case .allTime:
            filteredPosts = featuredPosts
        }

        return filteredPosts
            .sorted { lhs, rhs in
                if lhs.post.rankingScore == rhs.post.rankingScore {
                    return lhs.post.publishedAt > rhs.post.publishedAt
                }

                return lhs.post.rankingScore > rhs.post.rankingScore
            }
            .prefix(10)
            .map { $0 }
    }
}

private struct IChartForumTopChartColumn: View {
    let period: IChartForumTopChartPeriod
    let featuredPosts: [IChartForumFeaturedPost]
    let isExpanded: Bool
    let theme: IChartHomeTheme
    let onToggleExpansion: () -> Void
    let onOpenPost: (ForumSong, ForumChartPost) -> Void

    private let collapsedPostLimit = 4
    private let collapsedHeight: CGFloat = 372

    private var visiblePosts: [IChartForumFeaturedPost] {
        isExpanded ? featuredPosts : Array(featuredPosts.prefix(collapsedPostLimit))
    }

    private var hiddenPostCount: Int {
        max(0, featuredPosts.count - visiblePosts.count)
    }

    private var canExpand: Bool {
        featuredPosts.count > collapsedPostLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if canExpand {
                    onToggleExpansion()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(period.title)
                        .font(.subheadline.weight(.black))
                    Spacer(minLength: 4)
                    if canExpand {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.black))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IChartHomeBrand.blue.opacity(theme.isDark ? 0.78 : 0.88))
                .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
            .accessibilityLabel(canExpand ? "\(period.title) top charts \(isExpanded ? "collapse" : "expand")" : "\(period.title) top charts")

            if featuredPosts.isEmpty {
                IChartForumTopChartEmptyRow(accent: period.accent, theme: theme)
            } else {
                if let firstPost = visiblePosts.first {
                    IChartForumTopHeadlineRow(
                        rank: 1,
                        featuredPost: firstPost,
                        accent: period.accent,
                        theme: theme,
                        onOpen: {
                            onOpenPost(firstPost.song, firstPost.post)
                        }
                    )
                }

                let remainingPosts = Array(visiblePosts.dropFirst())
                if !remainingPosts.isEmpty {
                    VStack(spacing: 7) {
                        ForEach(Array(remainingPosts.enumerated()), id: \.element.id) { index, featuredPost in
                            IChartForumTopChartRow(
                                rank: index + 2,
                                featuredPost: featuredPost,
                                accent: period.accent,
                                theme: theme,
                                onOpen: {
                                    onOpenPost(featuredPost.song, featuredPost.post)
                                }
                            )
                        }
                    }
                }

                if canExpand {
                    Button(action: onToggleExpansion) {
                        HStack(spacing: 5) {
                            Text(isExpanded ? "Collapse" : "Show \(hiddenPostCount) more")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption2.weight(.black))
                        .foregroundStyle(theme.actionText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.14 : 0.52))
                        .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: collapsedHeight, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.panelBorder.opacity(0.25))
                .frame(width: 1)
        }
    }
}

private struct IChartForumTopHeadlineRow: View {
    let rank: Int
    let featuredPost: IChartForumFeaturedPost
    let accent: Color
    let theme: IChartHomeTheme
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text("#\(rank)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(accent)
                        .clipShape(Capsule())

                    Text("Lead Chart")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(theme.actionText)

                    Spacer(minLength: 0)
                }

                Text(featuredPost.post.chartTitle)
                    .font(.headline.weight(.black))
                    .foregroundStyle(theme.panelTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(featuredPost.post.creatorDisplayName.isEmpty ? "Unknown" : featuredPost.post.creatorDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
                    .lineLimit(1)

                IChartForumBadgeLabels(badges: featuredPost.authorBadges, foregroundColor: theme.actionText)

                HStack(spacing: 8) {
                    Label("\(max(0, featuredPost.post.voteUpCount))", systemImage: "hand.thumbsup")
                    Text(featuredPost.post.qualityStatus.displayText)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(theme.panelSecondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.10 : 0.50),
                        theme.panelBackground.opacity(theme.isDark ? 0.60 : 0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(IChartHomeBrand.blue.opacity(theme.isDark ? 0.62 : 0.44))
                    .frame(width: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open lead chart \(featuredPost.post.chartTitle)")
        .accessibilityValue(featuredPost.authorBadges.map(\.displayText).joined(separator: ", "))
    }
}

private struct IChartForumTopChartRow: View {
    let rank: Int
    let featuredPost: IChartForumFeaturedPost
    let accent: Color
    let theme: IChartHomeTheme
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(rank)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(rank <= 3 ? theme.actionText : theme.panelSecondary)
                    .frame(width: 20, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(featuredPost.post.chartTitle)
                        .font(.caption.weight(.black))
                        .foregroundStyle(theme.panelTitle)
                        .lineLimit(1)

                    Text(featuredPost.post.creatorDisplayName.isEmpty ? "Unknown" : featuredPost.post.creatorDisplayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.panelSecondary)
                        .lineLimit(1)

                    IChartForumBadgeLabels(badges: featuredPost.authorBadges, foregroundColor: theme.actionText)
                }

                Spacer(minLength: 4)

                Text("\(max(0, featuredPost.post.voteUpCount))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.panelSecondary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Divider().overlay(theme.panelBorder.opacity(0.25))
            }
            .contentShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(featuredPost.post.chartTitle)")
        .accessibilityValue(featuredPost.authorBadges.map(\.displayText).joined(separator: ", "))
    }
}

private struct IChartForumTopChartEmptyRow: View {
    let accent: Color
    let theme: IChartHomeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No charts yet")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.panelTitle)
            Text("Waiting on the first approved chart.")
                .font(.caption2)
                .foregroundStyle(theme.panelSecondary)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IChartForumSectionHeader: View {
    let title: String
    let subtitle: String
    let theme: IChartHomeTheme

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct IChartForumEmptyCommunityHub: View {
    let isSearching: Bool
    let localCharts: [Chart]
    let theme: IChartHomeTheme
    let onPublishChart: (Chart) -> Void
    let onOpenPost: (ForumSong, ForumChartPost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IChartForumTopChartsBoard(
                featuredPosts: [],
                isSearching: isSearching,
                theme: theme,
                onOpenPost: onOpenPost
            )

            if isSearching {
                IChartForumInlineEmptyRow(
                    title: "No Chart On This Tune Yet",
                    message: "A matching local chart can become the first reviewed PDF for this search.",
                    systemImageName: "magnifyingglass",
                    theme: theme
                )
            }

            IChartForumEmptyPublishBar(
                localCharts: localCharts,
                isSearching: isSearching,
                theme: theme,
                onPublishChart: onPublishChart
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IChartForumEmptyPublishBar: View {
    let localCharts: [Chart]
    let isSearching: Bool
    let theme: IChartHomeTheme
    let onPublishChart: (Chart) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localCharts.isEmpty ? "Local Chart Needed" : "Submit From Your Library")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.panelTitle)
                    Text(localCharts.isEmpty ? "Forum posts start from charts created inside iChart." : isSearching ? "A matching local chart can become the first reviewed PDF for this search." : "Pick a local chart and send a reviewed PDF snapshot to the community library.")
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: localCharts.isEmpty ? "doc.badge.plus" : "square.and.arrow.up")
                    .foregroundStyle(theme.actionText)
            }

            Spacer(minLength: 12)

            if localCharts.isEmpty {
                Text("No local charts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.panelSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(theme.panelBackground.opacity(theme.isDark ? 0.56 : 0.72))
                    .clipShape(Capsule())
            } else {
                Menu {
                    ForEach(localCharts) { chart in
                        Button {
                            onPublishChart(chart)
                        } label: {
                            Label(chart.title, systemImage: "doc.badge.plus")
                        }
                    }
                } label: {
                    Label("Submit To Forum", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IChartHomeBrand.blue)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelBackground.opacity(theme.isDark ? 0.62 : 0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }
}

private struct IChartForumInlineEmptyRow: View {
    let title: String
    let message: String
    let systemImageName: String
    let theme: IChartHomeTheme

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
            }
        } icon: {
            Image(systemName: systemImageName)
                .foregroundStyle(theme.actionText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct IChartForumStatusBanner: View {
    let text: String
    let systemImageName: String
    let color: Color
    let theme: IChartHomeTheme

    var body: some View {
        Label(text, systemImage: systemImageName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.emptyStateBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct IChartForumSongCard: View {
    let summary: IChartForumSongSummary
    let theme: IChartHomeTheme
    let onOpenPost: (ForumChartPost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.actionText)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.song.songTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(summary.song.artistName)
                        .font(.subheadline)
                        .foregroundStyle(theme.panelSecondary)
                }

                Spacer()

                Text("\(summary.topPosts.count) chart\(summary.topPosts.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(theme.emptyStateBackground)
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                ForEach(summary.topPosts) { post in
                    IChartForumPostRow(post: post, authorBadges: summary.badges(for: post), theme: theme) {
                        onOpenPost(post)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }
}

private struct IChartForumPostRow: View {
    let post: ForumChartPost
    let authorBadges: [ForumAuthorBadgeType]
    let theme: IChartHomeTheme
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(post.chartTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.panelTitle)
                            .lineLimit(1)

                        IChartForumQualityPill(status: post.qualityStatus, theme: theme)
                    }

                    Text("By \(post.creatorDisplayName.isEmpty ? "Unknown" : post.creatorDisplayName)")
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .lineLimit(1)

                    IChartForumBadgeLabels(badges: authorBadges, foregroundColor: theme.actionText)

                    if !post.tags.isEmpty {
                        Text(post.tags.joined(separator: " · "))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.actionText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Label(post.voteSummaryText, systemImage: "hand.thumbsup")
                        .font(.caption2.weight(.semibold))
                    Text(post.layoutStyle.displayText)
                        .font(.caption2)
                }
                .foregroundStyle(theme.panelSecondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panelBackground.opacity(theme.isDark ? 0.62 : 0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(post.chartTitle)")
        .accessibilityValue(authorBadges.map(\.displayText).joined(separator: ", "))
    }
}

struct IChartForumBadgeLabels: View {
    let badges: [ForumAuthorBadgeType]
    var showsExplanations = false
    var foregroundColor = IChartInterfaceStyle.actionBlue

    var body: some View {
        if !badges.isEmpty {
            VStack(alignment: .leading, spacing: showsExplanations ? 8 : 3) {
                ForEach(badges) { badge in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(badge.displayText, systemImage: "checkmark.seal.fill")
                            .font((showsExplanations ? Font.caption : .caption2).weight(.semibold))
                            .foregroundStyle(foregroundColor)
                        if showsExplanations {
                            Text(badge.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct IChartForumUploadQueueView: View {
    let items: [ForumUploadQueueItem]
    let theme: IChartHomeTheme
    let onRetry: (ForumUploadQueueItem) -> Void
    let onWithdraw: (ForumUploadQueueItem) -> Void
    let onDismiss: (ForumUploadQueueItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Forum Uploads", systemImage: "icloud.and.arrow.up")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.actionText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(IChartHomeBrand.blue.opacity(theme.isDark ? 0.18 : 0.12))
                    .clipShape(Capsule())
            }

            ForEach(items) { item in
                IChartForumUploadQueueRow(
                    item: item,
                    theme: theme,
                    onRetry: { onRetry(item) },
                    onWithdraw: { onWithdraw(item) },
                    onDismiss: { onDismiss(item) }
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelBackground.opacity(theme.isDark ? 0.92 : 0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }
}

private struct IChartForumUploadQueueRow: View {
    let item: ForumUploadQueueItem
    let theme: IChartHomeTheme
    let onRetry: () -> Void
    let onWithdraw: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if item.stage.isActive {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusSystemImage)
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.songTitle.isEmpty ? item.chartTitle : item.songTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
                    .lineLimit(1)

                Text(item.statusText)
                    .font(.caption)
                    .foregroundStyle(item.stage == .failed ? .orange : theme.panelSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if item.canRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if item.canWithdraw {
                Button(role: .destructive, action: onWithdraw) {
                    Label("Withdraw", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if item.canDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Dismiss forum upload")
            }
        }
        .padding(10)
        .background(theme.panelBackground.opacity(theme.isDark ? 0.7 : 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusSystemImage: String {
        switch item.stage {
        case .published:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .withdrawn, .removed:
            return "xmark.circle.fill"
        case .queued, .preparingPDF, .uploadingPDF, .submittingMetadata, .validating:
            return "icloud.and.arrow.up"
        }
    }

    private var statusColor: Color {
        switch item.stage {
        case .published:
            return .green
        case .failed:
            return .orange
        case .withdrawn, .removed:
            return .red
        case .queued, .preparingPDF, .uploadingPDF, .submittingMetadata, .validating:
            return theme.actionText
        }
    }
}

private struct IChartForumQualityPill: View {
    let status: ForumPostQualityStatus
    let theme: IChartHomeTheme

    var body: some View {
        Text(status.displayText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch status {
        case .topRated:
            return .green
        case .pendingReview, .needsReview:
            return .orange
        case .hidden, .removed:
            return .red
        case .new, .active:
            return theme.actionText
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(theme.isDark ? 0.18 : 0.12)
    }
}

struct IChartForumPublishSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var notesHeight: CGFloat = 72
    let request: IChartForumPublishRequest
    let theme: IChartHomeTheme
    let onPublish: (Chart, ForumPublishDraft) -> Void

    @State private var draft = ForumPublishDraft()
    @State private var validationErrors: [ForumPublishValidationError] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The PDF keeps this chart's current instrument view and transposition. To change them, return to the chart before submitting.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("Forum instrument view guidance")
                }
                Section {
                    forumTextField("Song Title", text: $draft.songTitle)
                        .background(IChartTypedSheetScrollSupport())
                    forumTextField("Artist", text: $draft.artistName)
                    forumTextField("Arranger Credit", text: $draft.arrangerCredit)
                    forumTextField("Tags (Optional)", text: $draft.tagsText, prompt: "live, acoustic, rhythm section")
                    IChartTypedTextView(
                        text: $draft.versionNote,
                        placeholder: "Notes (Optional)",
                        accessibilityLabel: "Notes (Optional)"
                    )
                    .frame(height: notesHeight)
                } header: {
                    Text("Metadata")
                } footer: {
                    Text("Tap a field to type. For Scribble, tap its Pencil icon, then write in the field.")
                }

                if !validationErrors.isEmpty {
                    Section("Missing") {
                        ForEach(validationErrors) { error in
                            Label(error.message, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Submit To Forum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        publish()
                    } label: {
                        Label("Submit", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                configureDraftIfNeeded()
            }
        }
        .presentationDetents([.large])
    }

    private func configureDraftIfNeeded() {
        guard draft.selectedChartID == nil else {
            return
        }

        draft.selectedChartID = request.chart.id
        draft.chartTitle = ""
    }

    private func forumTextField(
        _ title: String,
        text: Binding<String>,
        prompt: String? = nil
    ) -> some View {
        IChartTypedTextField(
            placeholder: prompt ?? title,
            text: text,
            autocapitalizationType: .sentences,
            autocorrectionType: .default,
            borderStyle: .none,
            accessibilityLabel: title
        )
        .frame(minHeight: 44)
    }

    private func publish() {
        let errors = draft.validationErrors(availableChartIDs: [request.chart.id])
        guard errors.isEmpty else {
            validationErrors = errors
            return
        }

        validationErrors = []
        onPublish(request.chart, draft)
    }
}

private struct IChartForumPostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var commentHeight: CGFloat = 72
    let detail: IChartForumPostDetail
    let currentUserID: UUID?
    let downloadedPDF: ExportedPDF?
    let isPDFSaved: Bool
    let savedPDFItemID: UUID?
    let isWorking: Bool
    let isLoadingEarlierComments: Bool
    let errorMessage: String?
    let theme: IChartHomeTheme
    let onVote: (ForumVoteValue) -> Void
    let onComment: (String) async -> Bool
    let onLoadEarlierComments: () async -> Void
    let onReportPost: (ForumReportReason) -> Void
    let onReportComment: (ForumComment, ForumReportReason) -> Void
    let onBlockUser: (UUID, String) -> Void
    let onDownloadPDF: () -> Void
    let onClearDownloadedPDF: () -> Void
    let onWithdrawPost: () -> Void
    let onRemovePost: () -> Void

    @State private var commentText = ""
    @State private var isSubmittingComment = false
    @State private var blockConfirmationRequest: ForumBlockConfirmationRequest?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    moderationNotice
                    actionRow
                    ownerManagementRow
                    comments
                }
                .padding(22)
                .background(IChartTypedSheetScrollSupport())
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let errorMessage {
                    IChartForumStatusBanner(
                        text: errorMessage,
                        systemImageName: "exclamationmark.triangle.fill",
                        color: .orange,
                        theme: theme
                    )
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .background(theme.panelBackground)
                }
            }
            .background(IChartLibraryBackground(mode: theme.mode).ignoresSafeArea())
            .navigationTitle(detail.post.chartTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(
            isPresented: Binding(
                get: { downloadedPDF != nil },
                set: { isPresented in
                    if !isPresented {
                        onClearDownloadedPDF()
                    }
                }
            )
        ) {
            if let downloadedPDF {
                PDFExportPreviewView(exportedPDF: downloadedPDF, source: .forumDownload, pdfItemID: savedPDFItemID)
            }
        }
        .alert(
            "Block Contributor?",
            isPresented: blockConfirmationPresented,
            presenting: blockConfirmationRequest
        ) { request in
            Button("Block", role: .destructive) {
                onBlockUser(request.ownerID, request.displayName)
                blockConfirmationRequest = nil
            }
            Button("Cancel", role: .cancel) {
                blockConfirmationRequest = nil
            }
        } message: { request in
            Text(request.confirmationMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.song.songTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(theme.panelTitle)

            Text(detail.song.artistName)
                .font(.headline)
                .foregroundStyle(theme.panelSecondary)

            HStack(spacing: 8) {
                IChartForumQualityPill(status: detail.post.qualityStatus, theme: theme)
                Text(detail.post.voteSummaryText)
                Text(detail.post.layoutStyle.displayText)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.panelSecondary)

            Text("Created by \(detail.post.creatorDisplayName.isEmpty ? "Unknown" : detail.post.creatorDisplayName)")
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)

            IChartForumBadgeLabels(badges: detail.authorBadges.map(\.badgeType), showsExplanations: true, foregroundColor: theme.actionText)

            if !detail.post.tags.isEmpty {
                Text(detail.post.tags.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.actionText)
            }

            if let note = detail.post.versionNote, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(theme.panelSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var moderationNotice: some View {
        if let message = moderationNoticeText {
            IChartForumStatusBanner(
                text: message,
                systemImageName: detail.post.acceptsCommunityActions ? "exclamationmark.triangle.fill" : "lock.fill",
                color: detail.post.acceptsCommunityActions ? .orange : .red,
                theme: theme
            )
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onDownloadPDF) {
                Label(isPDFSaved ? "Open Saved PDF" : "Save PDF & Open", systemImage: isPDFSaved ? "checkmark.circle" : "arrow.down.doc")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .accessibilityHint(isPDFSaved ? "Opens the saved offline PDF." : "Downloads this PDF to your local PDF library, then opens it.")
            Text(isPDFSaved ? "Saved for offline reading in PDFs." : "Saves a local copy in PDFs for offline reading.")
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 10, rowSpacing: 10) {
            Button {
                onVote(.up)
            } label: {
                Label("Upvote", systemImage: detail.currentUserVote == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .buttonStyle(.bordered)
            .tint(theme.actionText)

            Button {
                onVote(.down)
            } label: {
                Label("Downvote", systemImage: detail.currentUserVote == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach(ForumReportReason.allCases) { reason in
                    Button(reason.displayText) {
                        onReportPost(reason)
                    }
                }

                if currentUserID != detail.post.ownerID {
                    Divider()
                    Button(role: .destructive) {
                        requestBlockUser(ownerID: detail.post.ownerID, displayName: detail.post.creatorDisplayName)
                    } label: {
                        Label("Block Contributor", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            } label: {
                Label("Safety", systemImage: "flag")
            }
            .buttonStyle(.bordered)
            }
        }
        .disabled(isWorking || !detail.post.acceptsCommunityActions)
    }

    @ViewBuilder
    private var ownerManagementRow: some View {
        if currentUserID == detail.post.ownerID {
            HStack(spacing: 10) {
                switch detail.post.status {
                case .pending:
                    Button(role: .destructive, action: onWithdrawPost) {
                        Label("Withdraw Submission", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                case .published, .flagged:
                    Button(role: .destructive, action: onRemovePost) {
                        Label("Remove From Forums", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                case .hidden, .removed:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discussion")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            if detail.earlierCommentCursor != nil {
                Text("Showing \(detail.comments.count) recent comments. Load earlier comments to read more.")
                    .font(.subheadline)
                    .foregroundStyle(theme.panelSecondary)
            }

            if detail.post.acceptsCommunityActions {
                HStack(alignment: .top, spacing: 8) {
                    IChartTypedTextView(
                        text: $commentText,
                        placeholder: "Add a comment",
                        textColor: UIColor(theme.panelTitle),
                        placeholderColor: UIColor(theme.panelSecondary),
                        tintColor: UIColor(theme.actionText),
                        accessibilityLabel: "Add a comment",
                        accessibilityHint: "Tap to type. Use Start Scribble to write with Apple Pencil."
                    )
                    .frame(height: commentHeight)
                    .background(theme.emptyStateBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.panelBorder, lineWidth: 1)
                            .allowsHitTesting(false)
                    }

                    Button {
                        let submittedDraft = commentText
                        let body = ForumPublishDraft.normalizedDisplayText(submittedDraft)
                        guard !body.isEmpty, !isSubmittingComment else { return }
                        isSubmittingComment = true
                        Task {
                            let posted = await onComment(body)
                            if posted, commentText == submittedDraft {
                                commentText = ""
                            }
                            isSubmittingComment = false
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(isWorking || isSubmittingComment)
                    .accessibilityLabel("Post comment")
                }
            } else {
                Text("Discussion is closed for this chart.")
                    .font(.subheadline)
                    .foregroundStyle(theme.panelSecondary)
                    .padding(.vertical, 8)
            }

            if detail.earlierCommentCursor != nil {
                Button {
                    Task { await onLoadEarlierComments() }
                } label: {
                    if isLoadingEarlierComments {
                        ProgressView("Loading earlier comments…")
                    } else {
                        Label("Load Earlier Comments", systemImage: "arrow.up.bubble")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isWorking || isLoadingEarlierComments)
                .accessibilityHint("Adds earlier discussion above the comments already shown.")
            }

            if detail.comments.isEmpty {
                Text("No comments yet.")
                    .font(.subheadline)
                    .foregroundStyle(theme.panelSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(detail.comments) { comment in
                    IChartForumCommentRow(
                        comment: comment,
                        currentUserID: currentUserID,
                        theme: theme,
                        onReport: { reason in
                            onReportComment(comment, reason)
                        },
                        onBlockUser: {
                            requestBlockUser(ownerID: comment.ownerID, displayName: comment.creatorDisplayName ?? "")
                        }
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }

    private var moderationNoticeText: String? {
        switch detail.post.status {
        case .pending:
            return "This chart is pending an authenticity review before it appears in Forums."
        case .published:
            return detail.post.qualityStatus == .needsReview
                ? "This chart has been flagged for community review."
                : nil
        case .flagged:
            return "This chart is under community review."
        case .hidden:
            return "This chart is hidden while it is reviewed."
        case .removed:
            return "This chart is no longer available in Forums."
        }
    }

    private var blockConfirmationPresented: Binding<Bool> {
        Binding(
            get: { blockConfirmationRequest != nil },
            set: { isPresented in
                if !isPresented {
                    blockConfirmationRequest = nil
                }
            }
        )
    }

    private func requestBlockUser(ownerID: UUID, displayName: String) {
        blockConfirmationRequest = ForumBlockConfirmationRequest(ownerID: ownerID, displayName: displayName)
    }
}

private struct ForumBlockConfirmationRequest: Identifiable {
    let ownerID: UUID
    let displayName: String

    var id: UUID { ownerID }

    var confirmationMessage: String {
        let contributorName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if contributorName.isEmpty {
            return "Hide this contributor's forum posts and comments from this account."
        }

        return "Hide \(contributorName)'s forum posts and comments from this account."
    }
}

private struct IChartForumCommentRow: View {
    let comment: ForumComment
    let currentUserID: UUID?
    let theme: IChartHomeTheme
    let onReport: (ForumReportReason) -> Void
    let onBlockUser: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble")
                .foregroundStyle(theme.actionText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                if let creatorDisplayName = comment.creatorDisplayName, !creatorDisplayName.isEmpty {
                    Text(creatorDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.actionText)
                }

                Text(comment.body)
                    .font(.subheadline)
                    .foregroundStyle(theme.panelTitle)

                Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(theme.panelSecondary)
            }

            Spacer()

            Menu {
                ForEach(ForumReportReason.allCases) { reason in
                    Button(reason.displayText) {
                        onReport(reason)
                    }
                }

                if currentUserID != comment.ownerID {
                    Divider()
                    Button(role: .destructive, action: onBlockUser) {
                        Label("Block Commenter", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            } label: {
                Image(systemName: "flag")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Comment safety options")
        }
        .padding(11)
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct IChartHomeSidebar: View {
    private let expandedWidth: CGFloat = 208
    private let collapsedWidth: CGFloat = 82

    let logoVariant: IChartLogoVariant
    @Binding var selectedTab: IChartHomeTab
    @Binding var appearanceMode: IChartHomeAppearanceMode
    @Binding var isCollapsed: Bool
    let onSelectTab: (IChartHomeTab) -> Void

    var body: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: isCollapsed ? 16 : 22) {
            sidebarHeader

            VStack(spacing: 8) {
                ForEach(IChartHomeTab.allCases) { tab in
                    IChartHomeSidebarButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        isCollapsed: isCollapsed,
                        action: {
                            onSelectTab(tab)
                        }
                    )
                }
            }
            .padding(.horizontal, isCollapsed ? 10 : 12)

            Spacer()

            VStack(alignment: isCollapsed ? .center : .leading, spacing: 10) {
                IChartHomeAppearanceModeSwitch(selectedMode: $appearanceMode)

                IChartHomeUpdateStamp(isCollapsed: isCollapsed)
            }
                .padding(.horizontal, isCollapsed ? 10 : 12)
                .padding(.bottom, 20)
        }
        .frame(width: isCollapsed ? collapsedWidth : expandedWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    IChartHomeBrand.stage,
                    IChartHomeBrand.night
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .animation(.easeInOut(duration: 0.20), value: isCollapsed)
    }

    private var sidebarHeader: some View {
        VStack(spacing: isCollapsed ? 6 : 4) {
            HStack {
                Spacer()
                collapseButton
            }

            IChartWordmarkView(variant: logoVariant, size: isCollapsed ? 34 : 72)
                .frame(maxWidth: .infinity, minHeight: isCollapsed ? 42 : 70, alignment: .center)
        }
        .padding(.horizontal, isCollapsed ? 8 : 12)
        .padding(.top, isCollapsed ? 12 : 16)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.20)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                .font(.caption.weight(.bold))
                .foregroundStyle(IChartHomeBrand.paper.opacity(0.70))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Open sidebar" : "Collapse sidebar")
    }
}

private struct IChartHomeUpdateStamp: View {
    let isCollapsed: Bool

    var body: some View {
        Text(isCollapsed ? IChartBuildIdentity.collapsedStamp : IChartBuildIdentity.expandedStamp)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(IChartHomeBrand.paper.opacity(0.62))
            .lineLimit(1)
            .minimumScaleFactor(0.80)
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .accessibilityLabel(IChartBuildIdentity.accessibilityLabel)
    }
}

private enum IChartBuildIdentity {
    static var collapsedStamp: String {
        "v\(version) (\(buildNumber))"
    }

    static var expandedStamp: String {
        collapsedStamp
    }

    static var accessibilityLabel: String {
        "Version \(version), build \(buildNumber)"
    }

    private static var version: String {
        bundleValue(for: "CFBundleShortVersionString", fallback: "unknown")
    }

    private static var buildNumber: String {
        bundleValue(for: "CFBundleVersion", fallback: "unknown")
    }

    private static func bundleValue(for key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return fallback
        }

        return value
    }
}

private struct IChartHomeAppearanceModeSwitch: View {
    @Binding var selectedMode: IChartHomeAppearanceMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IChartHomeAppearanceMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMode = mode
                    }
                } label: {
                    Image(systemName: mode.systemImageName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(foregroundColor(for: mode))
                        .background(backgroundColor(for: mode))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.accessibilityLabel)
                .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func foregroundColor(for mode: IChartHomeAppearanceMode) -> Color {
        selectedMode == mode ? IChartHomeBrand.paper : IChartHomeBrand.paper.opacity(0.62)
    }

    private func backgroundColor(for mode: IChartHomeAppearanceMode) -> Color {
        selectedMode == mode ? IChartHomeBrand.logoBlue.opacity(0.22) : Color.clear
    }
}

private struct IChartHomeSidebarButton: View {
    let tab: IChartHomeTab
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImageName)
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)

                if !isCollapsed {
                    Text(tab.title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, isCollapsed ? 10 : 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var foregroundColor: Color {
        isSelected ? IChartHomeBrand.paper : IChartHomeBrand.paper.opacity(0.70)
    }

    private var backgroundColor: Color {
        isSelected ? IChartHomeBrand.logoBlue.opacity(0.18) : Color.clear
    }

    private var borderColor: Color {
        isSelected ? IChartHomeBrand.logoBlue.opacity(0.28) : Color.clear
    }
}

private struct IChartHelpTopicRow: View {
    let topic: IChartHelpTopic
    let isSelected: Bool
    let theme: IChartHomeTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: topic.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.actionText)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(topic.summary)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                }

                Spacer(minLength: 16)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? theme.actionText : theme.panelSecondary.opacity(0.7))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(isSelected ? theme.selectionBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(topic.title)
    }
}

private struct IChartHelpTopicDetail: View {
    let topic: IChartHelpTopic
    let theme: IChartHomeTheme
    let canStartGuidedTour: Bool
    let onStartGuidedTour: () -> Void

    @ViewBuilder
    var body: some View {
        switch topic {
        case .tutorial:
            IChartTutorialGuide(
                theme: theme,
                canStartGuidedTour: canStartGuidedTour,
                onStartGuidedTour: onStartGuidedTour
            )
        case .howTo, .faq, .userPolicy, .legal, .contactUs:
            IChartHelpArticlePage(
                topic: topic,
                theme: theme,
                sections: IChartHelpArticleSection.sections(for: topic)
            )
        }
    }
}

private struct IChartHelpArticlePage: View {
    let topic: IChartHelpTopic
    let theme: IChartHomeTheme
    let sections: [IChartHelpArticleSection]

    @State private var expandedSectionIDs: Set<String>

    init(topic: IChartHelpTopic, theme: IChartHomeTheme, sections: [IChartHelpArticleSection]) {
        self.topic = topic
        self.theme = theme
        self.sections = sections
        _expandedSectionIDs = State(initialValue: Set(sections.prefix(1).map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .center, spacing: 8) {
                Label(topic.detailTitle, systemImage: topic.systemImageName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)

                Text(topic.detailText)
                    .font(.subheadline)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)

                if topic == .contactUs {
                    Link(destination: IChartSupportLinks.supportURL) {
                        Label("Open Support Site", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(IChartHomeBrand.blue)
                    .accessibilityHint("Opens useichart.com/support.html")

                    IChartPerformanceReportShareRow(theme: theme)
                }

                if topic == .legal {
                    IChartLegalLinksView()
                        .tint(theme.actionText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    IChartHelpArticleSectionView(
                        section: section,
                        theme: theme,
                        isExpanded: expandedSectionIDs.contains(section.id)
                    ) {
                        toggleSection(section.id)
                    }

                    if section.id != sections.last?.id {
                        Divider()
                            .overlay(theme.panelBorder)
                            .padding(.vertical, 14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func toggleSection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedSectionIDs.contains(id) {
                expandedSectionIDs.remove(id)
            } else {
                expandedSectionIDs.insert(id)
            }
        }
    }
}

private struct IChartPerformanceReportShareRow: View {
    let theme: IChartHomeTheme
    @State private var reportURL: URL?
    @State private var isPreparingReport = true
    @State private var isClearingReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isPreparingReport || isClearingReport {
                ProgressView(isClearingReport ? "Clearing performance report..." : "Preparing performance report...")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
            } else if let reportURL {
                ShareLink(
                    item: reportURL,
                    preview: SharePreview("iChart Performance Report")
                ) {
                    Label("Share Performance Report", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(theme.actionText)

            } else {
                Label("No basic performance entries to share", systemImage: "doc.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
            }

            Button("Clear Report", role: .destructive) {
                Task { await clearReport() }
            }
            .font(.caption)
            .disabled(isPreparingReport || isClearingReport)
            .accessibilityHint("Removes local diagnostic history and prepared performance reports from this iPad.")

            Text("Basic operation timings and error categories. Stays on this iPad until you share it.")
                .font(.caption2)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await refreshReportURL() }
    }

    @MainActor
    private func refreshReportURL() async {
        isPreparingReport = true
        // This row exists only after the user opens Contact Us. Exporting here
        // also finds retained reports before the memory-only availability probe
        // finishes; disk work never runs in the view or on the main actor.
        let preparedURL = await Task.detached(priority: .utility) {
            IChartPerformanceTrace.reportURL
        }.value
        guard !Task.isCancelled else { return }
        reportURL = preparedURL
        isPreparingReport = false
    }

    @MainActor
    private func clearReport() async {
        guard !isPreparingReport, !isClearingReport else { return }
        reportURL = nil
        isClearingReport = true
        await Task.detached(priority: .utility) {
            IChartPerformanceTrace.resetReport()
        }.value
        guard !Task.isCancelled else { return }
        isClearingReport = false
    }
}

private struct IChartHelpArticleSectionView: View {
    let section: IChartHelpArticleSection
    let theme: IChartHomeTheme
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var expandedGroups: Set<String> = ["Start here", "Details"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: section.systemImageName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(IChartTourStyle.orange)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.panelTitle)

                        Text(section.body)
                            .font(.caption)
                            .foregroundStyle(theme.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.panelSecondary.opacity(0.75))
                        .frame(width: 20, height: 20)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")

            if isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(section.readingGroups) { group in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedGroups.contains(group.id) },
                            set: { isOpen in
                                if isOpen { expandedGroups.insert(group.id) }
                                else { expandedGroups.remove(group.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(group.bullets, id: \.self) { bullet in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 5))
                                            .padding(.top, 7)
                                            .accessibilityHidden(true)
                                        Text(bullet)
                                            .font(.subheadline)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .foregroundStyle(theme.panelTitle)
                                }
                            }
                            .padding(.vertical, 8)
                        } label: {
                            Text(group.title).font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.panelTitle)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.panelBorder.opacity(0.32))
                        .frame(width: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct IChartTutorialGuide: View {
    let theme: IChartHomeTheme
    let canStartGuidedTour: Bool
    let onStartGuidedTour: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Quick Start", systemImage: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Make a first Simple Chord Sheet with one short guide that stays on the chart while you try it.")
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            Button(action: onStartGuidedTour) {
                Label("Start Quick Start", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(IChartHomeBrand.blue)
            .disabled(!canStartGuidedTour)
            .accessibilityHint(
                canStartGuidedTour
                    ? "Opens Charts and guides you through a new Simple Chord Sheet."
                    : "Quick Start needs one free chart slot."
            )

            if !canStartGuidedTour {
                Label(
                    "Quick Start creates one practice chart. Free a chart slot to begin.",
                    systemImage: "info.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.panelSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(IChartQuickStartStep.all.enumerated()), id: \.element.id) { index, step in
                    IChartQuickStartStepRow(
                        number: index + 1,
                        step: step,
                        theme: theme
                    )
                }
            }

            Label(
                "Need a specific command? How To keeps the complete tool reference.",
                systemImage: "book.closed"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.panelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct IChartQuickStartStepRow: View {
    let number: Int
    let step: IChartQuickStartStep
    let theme: IChartHomeTheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(IChartTourStyle.navy)
                .frame(width: 22, height: 22)
                .background(IChartTourStyle.orangeSoft)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)

                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.panelBorder.opacity(0.25))
        }
    }
}

private struct IChartHomePanel<Content: View>: View {
    let title: String
    let systemImageName: String
    let theme: IChartHomeTheme
    let content: Content

    init(
        title: String,
        systemImageName: String,
        theme: IChartHomeTheme,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImageName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IChartTourStyle.orange)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            content
                .foregroundStyle(theme.panelTitle)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.panelBorder.opacity(0.32))
        }
    }
}

private struct IChartSettingsRow: View {
    let title: String
    let value: String
    let systemImageName: String
    let theme: IChartHomeTheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.actionText)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            Spacer(minLength: 16)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }
}

private struct IChartFirstRunAccountLandingView: View {
    @ObservedObject var authStore: IChartAuthStore
    let theme: IChartHomeTheme
    let onContinue: () -> Void
    @State private var isLaunchAnimationVisible = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        VStack(alignment: .center, spacing: 20) {
                            VStack(alignment: .center, spacing: 10) {
                                Label("Welcome to iChart", systemImage: "music.note.list")
                                    .font(.largeTitle.weight(.semibold))
                                    .foregroundStyle(theme.panelTitle)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text("Create your account to keep identity, recovery, and subscription access tied to you from the start.")
                                    .font(.body)
                                    .foregroundStyle(theme.panelSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 520)
                            }

                            IChartHomePanel(
                                title: "Account",
                                systemImageName: "person.crop.circle.badge.plus",
                                theme: theme
                            ) {
                                IChartAccountSettings(
                                    authStore: authStore,
                                    theme: theme,
                                    requiresNameForSignup: true,
                                    showsSignedInActions: false,
                                    initialEntryMode: .createAccount
                                )
                            }

                            if authStore.state.isVerifiedSignedIn && authStore.hasCompleteAccountIdentity {
                                Label("Verification complete. Opening iChart...", systemImage: "checkmark.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.panelSecondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 44)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                    .background(IChartTypedSheetScrollSupport())
                }
                .scrollIndicators(.hidden)
            }
            .background(IChartLibraryBackground(mode: theme.mode).ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(true)
        }
        .overlay {
            if isLaunchAnimationVisible {
                IChartLaunchScreenView(
                    capturedHandwritingSample: IChartLaunchHandwritingSample.bundledCanonicalLaunchSample(),
                    onFinished: onContinue
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .task {
            startLaunchAnimationIfReady()
        }
        .onChange(of: authStore.state) { _, _ in
            startLaunchAnimationIfReady()
        }
        .onChange(of: authStore.hasCompleteAccountIdentity) { _, _ in
            startLaunchAnimationIfReady()
        }
    }

    private func startLaunchAnimationIfReady() {
        guard authStore.state.isVerifiedSignedIn,
              authStore.hasCompleteAccountIdentity,
              !isLaunchAnimationVisible else {
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            isLaunchAnimationVisible = true
        }
    }
}

private struct IChartKeyboardFocusButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "keyboard")
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
    }
}

private enum IChartAccountInputField: Hashable {
    case firstName
    case lastName
    case email
    case password
    case newPassword
}

private enum IChartAccountEntryMode: String, CaseIterable {
    case signIn
    case createAccount
}

private struct IChartAccountSettings: View {
    @ObservedObject var authStore: IChartAuthStore
    let theme: IChartHomeTheme
    var requiresNameForSignup: Bool
    var showsSignedInActions: Bool
    @State private var entryMode: IChartAccountEntryMode
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var accountEntryPrompt: String?
    @State private var isShowingVerificationRecovery = false
    @State private var didSendVerificationRecoveryEmail = false
    @State private var isSendingVerificationRecoveryEmail = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var focusedField: IChartAccountInputField?
    @FocusState private var focusedSecureField: IChartAccountInputField?

    init(
        authStore: IChartAuthStore,
        theme: IChartHomeTheme,
        requiresNameForSignup: Bool = true,
        showsSignedInActions: Bool = true,
        initialEntryMode: IChartAccountEntryMode = .signIn
    ) {
        self.authStore = authStore
        self.theme = theme
        self.requiresNameForSignup = requiresNameForSignup
        self.showsSignedInActions = showsSignedInActions
        _entryMode = State(initialValue: initialEntryMode)
    }

    private var hasSignInCredentials: Bool {
        !trimmed(email).isEmpty
            && password.count >= 8
    }

    private var canSubmitCredentials: Bool {
        hasSignInCredentials
            && !authStore.isWorking
    }

    private var canRequestPasswordReset: Bool {
        !trimmed(email).isEmpty
            && !authStore.isWorking
    }

    private var canUpdateRecoveryPassword: Bool {
        newPassword.count >= 8 && !authStore.isWorking
    }

    private var canCompleteAccountIdentity: Bool {
        !trimmed(firstName).isEmpty
            && !trimmed(lastName).isEmpty
            && !authStore.isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.actionText)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(authStore.state.statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            switch authStore.state {
            case .unconfigured:
                Text("Account services are unavailable right now. Local charts remain available.")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .signedOut:
                signedOutContent
            case .temporarilyOffline:
                offlineRow
            case .pendingEmailVerification:
                verificationRow
            case .passwordRecovery:
                passwordRecoveryRow
            case .signedIn:
                signedInContent
            }

            statusFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Delete Account?", isPresented: $isShowingDeleteAccountConfirmation) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await authStore.deleteAccount()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your iChart account, profile, cloud backup, subscription authority, and forum activity from iChart servers. App Store subscriptions and billing are managed by Apple; cancel or manage them from your Apple account before continuing. This cannot be undone.")
        }
    }

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Account action", selection: $entryMode) {
                Text("Sign In").tag(IChartAccountEntryMode.signIn)
                Text("Create Account").tag(IChartAccountEntryMode.createAccount)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Account action")
            .disabled(authStore.isWorking)

            credentialsForm
            accountEntryPromptText
            actionRow

            if entryMode == .signIn {
                passwordResetRow
            }
        }
    }

    private var credentialsForm: some View {
        VStack(spacing: 10) {
            if requiresNameForSignup && entryMode == .createAccount {
                IChartAccountTextField(
                    title: "First Name",
                    placeholder: "First name",
                    text: $firstName,
                    systemImageName: "person",
                    keyboardType: .default,
                    theme: theme,
                    focusedField: $focusedField,
                    field: .firstName,
                    autocapitalizationType: .words,
                    autocorrectionType: .yes
                )

                IChartAccountTextField(
                    title: "Last Name",
                    placeholder: "Last name",
                    text: $lastName,
                    systemImageName: "person.text.rectangle",
                    keyboardType: .default,
                    theme: theme,
                    focusedField: $focusedField,
                    field: .lastName,
                    autocapitalizationType: .words,
                    autocorrectionType: .yes
                )
            }

            IChartAccountTextField(
                title: "Email",
                placeholder: "name@example.com",
                text: $email,
                systemImageName: "envelope",
                keyboardType: .emailAddress,
                theme: theme,
                focusedField: $focusedField,
                field: .email
            )

            IChartAccountSecureField(
                title: "Password",
                placeholder: "8 characters minimum",
                text: $password,
                systemImageName: "lock",
                theme: theme,
                focusedField: $focusedSecureField,
                field: .password
            )
        }
    }

    private var actionRow: some View {
        Group {
            switch entryMode {
            case .signIn:
                signInButton
            case .createAccount:
                createAccountButton
            }
        }
    }

    private var signInButton: some View {
        Button {
            guard hasSignInCredentials else {
                accountEntryPrompt = "Enter your email and password, then tap Sign In."
                focusInput(trimmed(email).isEmpty ? .email : .password)
                return
            }

            accountEntryPrompt = nil
            Task {
                await authStore.signIn(email: email, password: password)
            }
        } label: {
            Label("Sign In", systemImage: "person.crop.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(IChartHomeBrand.blue)
        .disabled(authStore.isWorking)
    }

    private var createAccountButton: some View {
        Button {
            guard validateCreateAccountInputs() else {
                return
            }

            accountEntryPrompt = nil
            resetVerificationRecoveryState()
            Task {
                await authStore.createAccount(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName
                )
            }
        } label: {
            Label("Create Account", systemImage: "person.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(IChartHomeBrand.blue)
        .disabled(authStore.isWorking)
    }

    @ViewBuilder
    private var accountEntryPromptText: some View {
        if let accountEntryPrompt {
            Text(accountEntryPrompt)
                .font(.caption)
                .foregroundStyle(Color(red: 0.62, green: 0.18, blue: 0.12))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account-entry-prompt")
        }
    }

    private var passwordResetRow: some View {
        Button {
            Task {
                await authStore.requestPasswordReset(email: email)
            }
        } label: {
            Label("Reset Password", systemImage: "lock")
        }
        .buttonStyle(.bordered)
        .disabled(!canRequestPasswordReset)
    }

    private var verificationRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This page will stay here until iChart confirms your email link.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label("1. Open Mail on this iPad.", systemImage: "1.circle")
                Label("2. Find the iChart verification email.", systemImage: "2.circle")
                Label("3. Tap Verify iChart Account.", systemImage: "3.circle")
                Label("4. Tap Return to iChart on the browser page.", systemImage: "4.circle")
            }
            .font(.caption)
            .foregroundStyle(theme.panelSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Do not tap anything else here after opening the email. iChart will move forward when the link is confirmed.")
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Waiting for email verification...")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.panelSecondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.panelBorder, lineWidth: 1)
                }

                verificationRecoveryRow

                HStack(spacing: 10) {
                    Button {
                        authStore.returnToSignIn()
                        resetVerificationRecoveryState()
                        entryMode = .signIn
                        password = ""
                        accountEntryPrompt = "If your email is verified, sign in with that email and password."
                        focusInput(.email)
                    } label: {
                        Label("Already Verified? Sign In", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(authStore.isWorking)

                    Button {
                        authStore.returnToSignIn()
                        resetVerificationRecoveryState()
                        entryMode = .createAccount
                        email = ""
                        password = ""
                        accountEntryPrompt = "Enter the email address you want to use, then tap Create Account."
                        focusInput(.email)
                    } label: {
                        Label("Use a Different Email", systemImage: "arrow.uturn.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(authStore.isWorking)
                }
            }
        }
    }

    private var verificationRecoveryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingVerificationRecovery.toggle()
                }
            } label: {
                Label("Email Didn't Arrive?", systemImage: "questionmark.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.actionText)
            .disabled(authStore.isWorking)

            if isShowingVerificationRecovery {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use this only if no iChart email arrived after a few minutes. It sends one replacement email to the same address.")
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        guard !isSendingVerificationRecoveryEmail else {
                            return
                        }

                        isSendingVerificationRecoveryEmail = true
                        Task { @MainActor in
                            didSendVerificationRecoveryEmail = await authStore.resendVerificationEmail()
                            isSendingVerificationRecoveryEmail = false
                        }
                    } label: {
                        Label(
                            verificationRecoveryButtonTitle,
                            systemImage: verificationRecoveryButtonSystemImage
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(authStore.isWorking || isSendingVerificationRecoveryEmail || didSendVerificationRecoveryEmail)

                    if didSendVerificationRecoveryEmail {
                        Text("Open Mail and tap Verify iChart Account. If the replacement email still does not arrive, contact support.")
                            .font(.caption)
                            .foregroundStyle(theme.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Link(destination: IChartSupportLinks.supportURL) {
                        Label("Contact Support", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Get help with verification without leaving this account flow.")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.panelBorder, lineWidth: 1)
                }
            }
        }
    }

    private func resetVerificationRecoveryState() {
        isShowingVerificationRecovery = false
        didSendVerificationRecoveryEmail = false
        isSendingVerificationRecoveryEmail = false
    }

    private var verificationRecoveryButtonTitle: String {
        if isSendingVerificationRecoveryEmail {
            return "Sending Replacement Email..."
        }

        return didSendVerificationRecoveryEmail ? "Replacement Email Sent" : "Send Replacement Email"
    }

    private var verificationRecoveryButtonSystemImage: String {
        if isSendingVerificationRecoveryEmail {
            return "hourglass"
        }

        return didSendVerificationRecoveryEmail ? "checkmark.circle" : "envelope.badge"
    }

    private var passwordRecoveryRow: some View {
        VStack(spacing: 10) {
            IChartAccountSecureField(
                title: "New Password",
                placeholder: "8 characters minimum",
                text: $newPassword,
                systemImageName: "lock",
                theme: theme,
                focusedField: $focusedSecureField,
                field: .newPassword
            )

            HStack(spacing: 10) {
                Button {
                    Task {
                        await authStore.updatePassword(newPassword)
                        newPassword = ""
                    }
                } label: {
                    Label("Save Password", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .tint(IChartHomeBrand.blue)
                .disabled(!canUpdateRecoveryPassword)

                Button {
                    Task {
                        await authStore.dismissPasswordRecovery()
                        newPassword = ""
                    }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(authStore.isWorking)
            }
        }
    }

    private var offlineRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await authStore.refreshSession()
                }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(authStore.isWorking)
        }
    }

    private var signedInRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await authStore.refreshSession()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(authStore.isWorking)

            Button(role: .destructive) {
                Task {
                    await authStore.signOut()
                }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
            .disabled(authStore.isWorking)
        }
    }

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountIdentitySummary

            if authStore.needsAccountIdentityCompletion {
                accountIdentityCompletionForm
            } else {
                Text("Name and email are tied to account recovery, support, subscriptions, and forum credit. Contact support if they need to change.")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsSignedInActions {
                signedInRow
                deleteAccountSection
            }
        }
        .onAppear {
            prefillAccountIdentityFieldsIfNeeded()
        }
        .onChange(of: authStore.profile) { _, _ in
            prefillAccountIdentityFieldsIfNeeded()
        }
    }

    private var accountIdentitySummary: some View {
        VStack(spacing: 0) {
            IChartSettingsRow(
                title: "Email",
                value: accountEmailText,
                systemImageName: "envelope",
                theme: theme
            )

            Divider()

            IChartSettingsRow(
                title: "Name",
                value: accountNameText,
                systemImageName: authStore.needsAccountIdentityCompletion ? "person.crop.circle.badge.exclamationmark" : "person.text.rectangle",
                theme: theme
            )
        }
    }

    private var accountIdentityCompletionForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Complete Account Identity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            Text("This legacy account needs first and last name once so support and forum posts can use stable account credit.")
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            IChartAccountTextField(
                title: "First Name",
                placeholder: "First name",
                text: $firstName,
                systemImageName: "person",
                keyboardType: .default,
                theme: theme,
                focusedField: $focusedField,
                field: .firstName,
                autocapitalizationType: .words,
                autocorrectionType: .yes
            )

            IChartAccountTextField(
                title: "Last Name",
                placeholder: "Last name",
                text: $lastName,
                systemImageName: "person.text.rectangle",
                keyboardType: .default,
                theme: theme,
                focusedField: $focusedField,
                field: .lastName,
                autocapitalizationType: .words,
                autocorrectionType: .yes
            )

            Button {
                Task {
                    await authStore.completeProfileIdentity(firstName: firstName, lastName: lastName)
                }
            } label: {
                Label("Save Account Name", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(!canCompleteAccountIdentity)
        }
    }

    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Delete Account")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            Text("Permanently removes your iChart account and server data. App Store subscriptions and billing are managed by Apple. Local chart files on this iPad remain on the device until you delete them or remove the app.")
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive) {
                isShowingDeleteAccountConfirmation = true
            } label: {
                Label("Delete Account", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(authStore.isWorking)
            .accessibilityIdentifier("delete-account-button")
        }
    }

    private var accountEmailText: String {
        if let email = authStore.state.signedInSession?.email?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }

        if let email = authStore.profile?.email?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return email
        }

        return "Unavailable"
    }

    private var accountNameText: String {
        if let name = authStore.profile?.accountName {
            return name
        }

        if authStore.needsAccountIdentityCompletion {
            return "Needs first and last name"
        }

        return "Unavailable"
    }

    @ViewBuilder
    private var statusFooter: some View {
        if authStore.isWorking {
            ProgressView()
                .controlSize(.small)
        } else if let errorMessage = authStore.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(Color(red: 0.62, green: 0.18, blue: 0.12))
                .fixedSize(horizontal: false, vertical: true)
        } else if let statusMessage = authStore.statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var iconName: String {
        switch authStore.state {
        case .unconfigured:
            return "wifi.slash"
        case .signedOut:
            return "person.crop.circle.badge.plus"
        case .temporarilyOffline:
            return "wifi.exclamationmark"
        case .pendingEmailVerification:
            return "envelope.badge"
        case .passwordRecovery:
            return "lock"
        case .signedIn:
            return "checkmark.seal"
        }
    }

    private var detailText: String {
        switch authStore.state {
        case .unconfigured:
            return "Account sign-in and cloud backup are unavailable right now."
        case .signedOut:
            return "Create an account or sign in for recovery, subscriptions, cloud backup, and Forums."
        case .temporarilyOffline(let session):
            if let email = session.email {
                return "Using local charts for \(email). Reconnect to back up."
            }

            return "Using local charts. Reconnect to back up."
        case .pendingEmailVerification(let email):
            return "Waiting for \(email). Open the iChart verification email and tap Verify iChart Account."
        case .passwordRecovery(let session):
            if let email = session.email {
                return "Enter a new password for \(email)."
            }

            return "Enter a new password to finish account recovery."
        case .signedIn(let session):
            return session.email ?? "Signed in to iChart."
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func focusInput(_ field: IChartAccountInputField) {
        switch field {
        case .firstName, .lastName, .email:
            focusedSecureField = nil
            focusedField = field
        case .password, .newPassword:
            focusedField = nil
            focusedSecureField = field
        }
    }

    private func validateCreateAccountInputs() -> Bool {
        if requiresNameForSignup && trimmed(firstName).isEmpty {
            accountEntryPrompt = "Enter first name, last name, email, and a password with at least 8 characters. Then tap Create Account."
            focusInput(.firstName)
            return false
        }

        if requiresNameForSignup && trimmed(lastName).isEmpty {
            accountEntryPrompt = "Enter first name, last name, email, and a password with at least 8 characters. Then tap Create Account."
            focusInput(.lastName)
            return false
        }

        if trimmed(email).isEmpty {
            accountEntryPrompt = "Enter first name, last name, email, and a password with at least 8 characters. Then tap Create Account."
            focusInput(.email)
            return false
        }

        if password.count < 8 {
            accountEntryPrompt = "Enter first name, last name, email, and a password with at least 8 characters. Then tap Create Account."
            focusInput(.password)
            return false
        }

        return true
    }

    private func prefillAccountIdentityFieldsIfNeeded() {
        guard authStore.needsAccountIdentityCompletion else {
            return
        }

        if firstName.isEmpty,
           let profileFirstName = authStore.profile?.firstName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !profileFirstName.isEmpty {
            firstName = profileFirstName
        }

        if lastName.isEmpty,
           let profileLastName = authStore.profile?.lastName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !profileLastName.isEmpty {
            lastName = profileLastName
        }
    }
}

private extension IChartAuthState {
    var isVerifiedSignedIn: Bool {
        guard case .signedIn(let session) = self else {
            return false
        }

        return session.isEmailVerified
    }

    var shouldPresentFirstRunAccountLanding: Bool {
        switch self {
        case .signedOut, .pendingEmailVerification, .signedIn:
            return true
        case .unconfigured, .temporarilyOffline, .passwordRecovery:
            return false
        }
    }
}

private enum IChartDebugPlanPreview: String, CaseIterable, Identifiable {
    case basic
    case pro
    case grace
    case expired
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic:
            return "Basic"
        case .pro:
            return "Pro"
        case .grace:
            return "Grace"
        case .expired:
            return "Expired"
        case .unavailable:
            return "Offline"
        }
    }

    static func preview(for subscription: IChartSubscriptionEntitlement) -> IChartDebugPlanPreview {
        switch subscription.status {
        case .basic:
            return .basic
        case .proActive, .legacyLocalPro:
            return .pro
        case .proGrace:
            return .grace
        case .proExpired:
            return .expired
        case .unavailable:
            return .unavailable
        }
    }

    func subscriptionState(now: Date = Date()) -> IChartSubscriptionEntitlement {
        switch self {
        case .basic:
            return .basic
        case .pro:
            return .activePro(verifiedAt: now)
        case .grace:
            let graceEndsAt = Calendar.current.date(
                byAdding: .day,
                value: 30,
                to: now
            ) ?? now.addingTimeInterval(30 * 24 * 60 * 60)
            return .proGrace(graceEndsAt: graceEndsAt, verifiedAt: now)
        case .expired:
            return .proExpired(verifiedAt: now)
        case .unavailable:
            return .unavailable
        }
    }
}

private struct IChartPlanSettings: View {
    @ObservedObject var store: ChartLibraryStore
    @ObservedObject var subscriptionStore: IChartStoreKitSubscriptionStore
    @ObservedObject var forumStore: IChartForumStore
    @Environment(\.betaProStore) private var betaProStore
    let theme: IChartHomeTheme
    let onSelectSubscriptionState: (IChartSubscriptionEntitlement) -> Void
    let onForumQASampleDataChanged: (Bool) -> Void
    @State private var complimentaryPurchaseFeedback: IChartComplimentaryPurchaseFeedback?

    private var isFreeAccess: Bool { store.entitlements.accessPolicy.includesAllFeatures }
    private var isFreeBeta: Bool { IChartProductAccessPolicy.current.isFreeBeta }
    private var planTitle: String {
        isFreeBeta ? (isFreeAccess ? IChartLegalLinks.freeProTitle : IChartLegalLinks.betaBasicTitle) : store.subscriptionState.displayTitle
    }
    private var planDetail: String {
        isFreeBeta ? (isFreeAccess ? IChartLegalLinks.freeProNotice : IChartLegalLinks.betaBasicNotice) : store.subscriptionState.detailText
    }

    #if DEBUG
    @State private var debugPreview: IChartDebugPlanPreview = .basic
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            planHeader

            VStack(spacing: 0) {
                IChartSettingsRow(
                    title: "Local Charts",
                    value: localChartCapacityValue,
                    systemImageName: "doc.on.doc",
                    theme: theme
                )

                planDivider

                IChartSettingsRow(
                    title: "Cloud Backup",
                    value: isFreeBeta ? (isFreeAccess ? "Included" : "Not included in Basic") : store.subscriptionState.cloudAccessText,
                    systemImageName: "icloud.and.arrow.up",
                    theme: theme
                )

                planDivider

                IChartSettingsRow(
                    title: "Forums",
                    value: isFreeBeta ? (isFreeAccess ? "Included" : "Not included in Basic") : store.subscriptionState.forumsAccessText,
                    systemImageName: "bubble.left.and.bubble.right",
                    theme: theme
                )

                if !isFreeBeta, let graceEndsAt = store.subscriptionState.graceEndsAt {
                    planDivider

                    IChartSettingsRow(
                        title: "Grace Ends",
                        value: graceEndsAt.formatted(date: .abbreviated, time: .omitted),
                        systemImageName: "calendar.badge.clock",
                        theme: theme
                    )
                }
            }

            if store.requiresLocalChartPruningForCurrentPlan {
                Text("Choose \(store.localChartOverflowCount) local chart\(store.localChartOverflowCount == 1 ? "" : "s") to remove from the Charts tab before Basic can open charts for editing or create new charts.")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isFreeBeta {
                freeAccessControls
            } else {
                storeKitControls
            }

            #if DEBUG
            debugControls
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if DEBUG
        .onAppear {
            debugPreview = IChartDebugPlanPreview.preview(for: store.subscriptionState)
        }
        .onChange(of: store.entitlements.subscription) { _, subscription in
            let nextPreview = IChartDebugPlanPreview.preview(for: subscription)
            if debugPreview != nextPreview {
                debugPreview = nextPreview
            }
        }
        #endif
    }

    private var planHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isFreeBeta ? (isFreeAccess ? "star.fill" : "person.crop.circle") : store.subscriptionState.systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(statusTint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(planTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)

                Text(planDetail)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(isFreeBeta ? (isFreeAccess ? "Free" : "Basic") : store.subscriptionState.badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusTint.opacity(theme.isDark ? 0.18 : 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var planDivider: some View {
        Divider()
            .overlay(theme.panelBorder)
            .padding(.leading, 44)
    }

    private var localChartCapacityValue: String {
        guard let limit = store.localChartLimit else {
            return "Unlimited"
        }

        return "\(min(store.charts.count, limit)) of \(limit) used"
    }

    private var statusTint: Color {
        if isFreeAccess { return Color(red: 0.16, green: 0.48, blue: 0.24) }
        if isFreeBeta { return theme.actionText }
        switch store.subscriptionState.status {
        case .proActive:
            return Color(red: 0.16, green: 0.48, blue: 0.24)
        case .proGrace:
            return Color(red: 0.76, green: 0.48, blue: 0.12)
        case .proExpired:
            return Color(red: 0.72, green: 0.18, blue: 0.12)
        case .unavailable:
            return Color(red: 0.48, green: 0.48, blue: 0.50)
        case .basic, .legacyLocalPro:
            return theme.actionText
        }
    }

    private var freeAccessControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let betaProStore {
                IChartBetaProControls(store: betaProStore)
            }
            Text(IChartLegalLinks.futurePricingNotice)
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(theme.panelBorder)
            Text("Existing Apple Purchases")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
            Text(IChartLegalLinks.existingBillingNotice)
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await subscriptionStore.manageSubscriptions() }
            } label: {
                Label("Manage My Subscription", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(subscriptionStore.state.isWorking)

            Button {
                Task { await subscriptionStore.restorePurchases() }
            } label: {
                Label("Restore Purchase History", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(subscriptionStore.state.isWorking)

            if let statusText = subscriptionStore.state.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            IChartLegalLinksView().tint(theme.actionText)
        }
    }

    private var storeKitControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(theme.panelBorder)

            Text("Pro Subscription")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            ForEach(subscriptionStore.complimentaryOfferStatuses) { status in
                Label(status.detailText, systemImage: "calendar.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(subscriptionStore.complimentaryOffers) { offer in
                VStack(alignment: .leading, spacing: 8) {
                    Text("One Month Free")
                        .font(.subheadline.weight(.semibold))
                    Text("\(offer.productDisplayName) · \(offer.detailText)")
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        complimentaryPurchaseFeedback = nil
                        Task {
                            let completed = await subscriptionStore.purchaseComplimentaryOffer(offer)
                            complimentaryPurchaseFeedback = IChartComplimentaryPurchaseFeedback(
                                productID: offer.productID,
                                completed: completed,
                                state: subscriptionStore.state
                            )
                        }
                    } label: {
                        Label(offer.actionTitle, systemImage: "gift.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.16, green: 0.48, blue: 0.24))
                    .disabled(subscriptionStore.state.isWorking)

                    if let complimentaryPurchaseFeedback,
                       complimentaryPurchaseFeedback.productID == offer.productID {
                        IChartComplimentaryPurchaseFeedbackView(
                            feedback: complimentaryPurchaseFeedback,
                            showsRetryHint: true
                        )
                    }
                }
                .padding(12)
                .background(Color(red: 0.16, green: 0.48, blue: 0.24).opacity(theme.isDark ? 0.16 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let complimentaryPurchaseFeedback,
               complimentaryPurchaseFeedback.shouldShowOutsideOffers(productIDs: subscriptionStore.complimentaryOffers.map(\.productID)) {
                IChartComplimentaryPurchaseFeedbackView(
                    feedback: complimentaryPurchaseFeedback,
                    showsRetryHint: false
                )
                .padding(12)
                .background(Color.red.opacity(theme.isDark ? 0.16 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !subscriptionStore.complimentaryOffers.isEmpty {
                Text("Standard paid plans")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
            }

            if subscriptionStore.productOptions.isEmpty {
                Text("Pro subscriptions are temporarily unavailable. Try again later or restore an existing purchase.")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(subscriptionStore.productOptions) { product in
                    Button {
                        complimentaryPurchaseFeedback = nil
                        Task {
                            await subscriptionStore.purchase(product)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(product.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(product.displayPrice)
                                    .font(.subheadline.weight(.semibold))

                                if let valueBadge = product.valueBadge {
                                    Text(valueBadge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color(red: 0.16, green: 0.48, blue: 0.24))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(IChartHomeBrand.blue)
                    .disabled(subscriptionStore.state.isWorking)
                }
            }

            Button {
                complimentaryPurchaseFeedback = nil
                Task {
                    await subscriptionStore.restorePurchases()
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(subscriptionStore.state.isWorking)

            Button {
                complimentaryPurchaseFeedback = nil
                Task {
                    await subscriptionStore.manageSubscriptions()
                }
            } label: {
                Label("Manage Subscription", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(subscriptionStore.state.isWorking)

            Text(IChartLegalLinks.subscriptionNotice)
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            IChartLegalLinksView()
                .tint(theme.actionText)

            if let statusText = subscriptionStore.state.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    #if DEBUG
    private var debugControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(theme.panelBorder)

            Text("Plan Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            Picker("Plan Preview", selection: $debugPreview) {
                ForEach(IChartDebugPlanPreview.allCases) { preview in
                    Text(preview.title).tag(preview)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: debugPreview) {
                let subscriptionState = debugPreview.subscriptionState()
                #if targetEnvironment(simulator)
                subscriptionStore.applyLocalPreview(subscriptionState)
                #endif
                onSelectSubscriptionState(subscriptionState)
            }

            Text("Use local preview controls on this device. Purchases and account backup still use their normal flows.")
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(
                isOn: Binding(
                    get: { forumStore.isQASampleDataEnabled },
                    set: onForumQASampleDataChanged
                )
            ) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sample Forum Charts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.panelTitle)
                        Text("Show local sample songs, names, rankings, comments, reports, and PDF previews.")
                            .font(.caption2)
                            .foregroundStyle(theme.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "person.3.sequence")
                        .foregroundStyle(theme.actionText)
                }
            }
            .toggleStyle(.switch)
        }
    }
    #endif
}

private struct IChartCloudSyncSettings: View {
    @ObservedObject var syncStore: ChartCloudSyncStore
    let theme: IChartHomeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Group {
                    if syncStore.progress != nil {
                        ProgressView()
                            .accessibilityLabel(statusTitle)
                    } else {
                        Image(systemName: statusImageName)
                            .font(.body.weight(.semibold))
                    }
                }
                .foregroundStyle(statusForeground)
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            Button {
                syncStore.backUpNow()
            } label: {
                Label(backupButtonTitle, systemImage: syncStore.state.manualSyncSystemImageName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(statusTint)
            .disabled(!canRunManualSync)
            .accessibilityHint(syncStore.state.manualSyncDisabledReason ?? "")

            if let disabledReason = disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                syncStore.restoreChartsFromCloud()
            } label: {
                Label(restoreButtonTitle, systemImage: "icloud.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(theme.actionText)
            .disabled(!canRunCloudRestore)
            .accessibilityHint(syncStore.state.cloudRestoreDisabledReason ?? "")

            if let restoreDisabledReason = restoreDisabledReason {
                Text(restoreDisabledReason)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let result = syncStore.lastRestoreResult {
                VStack(alignment: .leading, spacing: 4) {
                    Label(result.displayTitle, systemImage: result.systemImageName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)
                    Text(result.detailText)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(result.completedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(theme.panelSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cloud-restore-result")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canRunManualSync: Bool {
        syncStore.state.allowsManualSync && !syncStore.isWorking && syncStore.progress == nil
    }

    private var disabledReason: String? {
        guard !syncStore.isWorking, syncStore.progress == nil else {
            return nil
        }

        return syncStore.state.manualSyncDisabledReason
    }

    private var canRunCloudRestore: Bool {
        syncStore.state.allowsCloudRestore && !syncStore.isWorking && syncStore.progress == nil
    }

    private var restoreDisabledReason: String? {
        guard !syncStore.isWorking, syncStore.progress == nil else {
            return nil
        }

        guard syncStore.state.allowsManualSync else {
            return nil
        }

        return syncStore.state.cloudRestoreDisabledReason
    }

    private var statusTitle: String {
        if let progress = syncStore.progress { return progress.displayTitle }
        if let failure = syncStore.lastFailure { return failure.displayTitle }
        if let result = syncStore.lastOperationResult, result.operation == .backup { return result.displayTitle }
        return syncStore.state.displayText
    }

    private var statusDetail: String {
        if let progress = syncStore.progress { return progress.detailText }
        if let failure = syncStore.lastFailure { return failure.detailText }
        if let result = syncStore.lastOperationResult, result.operation == .backup { return result.detailText }
        return syncStore.state.detailText
    }

    private var statusImageName: String {
        if let failure = syncStore.lastFailure { return failure.systemImageName }
        if let result = syncStore.lastOperationResult, result.operation == .backup { return result.systemImageName }
        return syncStore.state.systemImageName
    }

    private var backupButtonTitle: String {
        if syncStore.progress?.operation == .restore || syncStore.lastFailure?.operation == .restore {
            return "Back Up Now"
        }
        return syncStore.state.manualSyncTitle
    }

    private var restoreButtonTitle: String {
        if syncStore.progress?.operation == .restore { return "Restoring Charts…" }
        if syncStore.lastFailure?.operation == .restore { return "Retry Restore" }
        return "Restore Charts from Cloud"
    }

    private var statusForeground: Color {
        if syncStore.progress != nil { return theme.actionText }
        switch syncStore.state {
        case .idle, .syncing, .signedOut, .unconfigured:
            return theme.actionText
        default:
            return statusTint
        }
    }

    private var statusTint: Color {
        if syncStore.progress != nil { return IChartHomeBrand.blue }
        switch syncStore.state {
        case .synced:
            return Color(red: 0.16, green: 0.48, blue: 0.24)
        case .offline:
            return Color(red: 0.76, green: 0.48, blue: 0.12)
        case .failed:
            return Color(red: 0.72, green: 0.18, blue: 0.12)
        case .requiresPro:
            return Color(red: 0.62, green: 0.40, blue: 0.10)
        case .idle, .syncing, .signedOut, .unconfigured:
            return IChartHomeBrand.blue
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct IChartDiagnosticsSettings: View {
    @Binding var rhythmDiagnosticsEnabled: Bool
    let theme: IChartHomeTheme
    @State private var rhythmDiagnosticsLogURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $rhythmDiagnosticsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rhythm Diagnostics")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.panelTitle)
                        Text("Show the Rhythm tool's last read and save local recognition notes for local review.")
                            .font(.caption)
                            .foregroundStyle(theme.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(theme.actionText)
                }
            }
            .toggleStyle(.switch)

            if rhythmDiagnosticsEnabled {
                Text("Diagnostics stay on this device in Application Support and do not upload chart ink.")
                    .font(.caption2)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Experimental pipeline preview is included so rhythm reads can be checked before the new recognizer path is committed.")
                    .font(.caption2)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let rhythmDiagnosticsLogURL {
                        ShareLink(
                            item: rhythmDiagnosticsLogURL,
                            preview: SharePreview("iChart Rhythm Diagnostics")
                        ) {
                            Label("Share Log", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Label("No rhythm log yet", systemImage: "doc.badge.clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.panelSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(role: .destructive) {
                        clearRhythmDiagnosticsLog()
                    } label: {
                        Label("Clear Log", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(rhythmDiagnosticsLogURL == nil)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .onAppear(perform: refreshRhythmDiagnosticsLog)
        .onChange(of: rhythmDiagnosticsEnabled) {
            refreshRhythmDiagnosticsLog()
        }
    }

    private func refreshRhythmDiagnosticsLog() {
        let recorder = RhythmRecognitionDiagnosticsRecorder.live()
        rhythmDiagnosticsLogURL = recorder.hasLogFile ? recorder.url : nil
    }

    private func clearRhythmDiagnosticsLog() {
        let recorder = RhythmRecognitionDiagnosticsRecorder.live()
        try? recorder.reset()
        refreshRhythmDiagnosticsLog()
    }
}
#endif

private struct IChartAccountTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImageName: String
    let keyboardType: UIKeyboardType
    let theme: IChartHomeTheme
    @Binding var focusedField: IChartAccountInputField?
    let field: IChartAccountInputField
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no

    var body: some View {
        IChartAccountFieldRow(title: title, systemImageName: systemImageName, theme: theme) {
            IChartTypedTextField(
                placeholder: placeholder,
                text: $text,
                isFocused: Binding(
                    get: { focusedField == field },
                    set: { isFocused in
                        if isFocused {
                            focusedField = field
                        } else if focusedField == field {
                            focusedField = nil
                        }
                    }
                ),
                autocapitalizationType: autocapitalizationType,
                autocorrectionType: autocorrectionType,
                font: .preferredFont(forTextStyle: .subheadline),
                borderStyle: .none,
                keyboardType: keyboardType,
                textColor: UIColor(theme.panelTitle),
                placeholderColor: UIColor(theme.panelSecondary),
                tintColor: UIColor(theme.actionText),
                accessibilityLabel: title,
                accessibilityHint: "Tap to type. Use Start Scribble to write with Apple Pencil."
            )
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.emptyStateBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.panelBorder, lineWidth: 1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct IChartAccountSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImageName: String
    let theme: IChartHomeTheme
    let focusedField: FocusState<IChartAccountInputField?>.Binding
    let field: IChartAccountInputField

    var body: some View {
        IChartAccountFieldRow(title: title, systemImageName: systemImageName, theme: theme) {
            HStack(spacing: 12) {
                SecureField(placeholder, text: $text)
                    .focused(focusedField, equals: field)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .foregroundStyle(theme.panelTitle)
                    .accessibilityLabel(title)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.emptyStateBackground)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.panelBorder, lineWidth: 1)
                    }

                IChartKeyboardFocusButton(
                    accessibilityLabel: "Open keyboard for \(title)"
                ) {
                    focusedField.wrappedValue = field
                }
            }
        }
    }
}

private struct IChartAccountFieldRow<Input: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let systemImageName: String
    let theme: IChartHomeTheme
    @ViewBuilder let input: () -> Input

    var body: some View {
        let stacksLabel = horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
        let layout = stacksLabel
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            HStack(spacing: 12) {
                Image(systemName: systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.actionText)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
                    .frame(width: stacksLabel ? nil : 104, alignment: .leading)
                    .accessibilityHidden(true)
            }

            input()
        }
    }
}

private struct IChartNewChartControl: View {
    let chartUsageText: String?
    let canCreateChart: Bool
    let theme: IChartHomeTheme
    var isTourHighlighted = false
    let onCreateChart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onCreateChart) {
                Label("New Chart", systemImage: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(canCreateChart ? Color.white : theme.workspaceTitle)
                    .frame(minWidth: 180, minHeight: 44)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(IChartHomeBrand.blue)
            .disabled(!canCreateChart)
            .tourActionHighlight(
                isActive: isTourHighlighted && canCreateChart,
                cornerRadius: 11,
                tint: IChartHomeBrand.blue
            )

            if let chartUsageText {
                Text(chartUsageText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.workspaceTitle.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 14)
    }
}

private struct IChartChartsWorkspaceModePicker: View {
    @Binding var selection: IChartChartsWorkspaceMode
    let theme: IChartHomeTheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(IChartChartsWorkspaceMode.allCases) { mode in
                let isSelected = selection == mode

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textColor(isSelected: isSelected))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(IChartHomeBrand.blue)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(3)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.isDark ? Color.white.opacity(0.16) : IChartHomeBrand.ink.opacity(0.08), lineWidth: 1)
        }
    }

    private func textColor(isSelected: Bool) -> Color {
        if isSelected {
            return .white
        }

        return theme.isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink.opacity(0.72)
    }
}

private struct IChartProjectCreateControl: View {
    let projectCount: Int
    let theme: IChartHomeTheme
    let onCreateProject: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .center, spacing: 3) {
                Text(projectCount == 1 ? "1 project" : "\(projectCount) projects")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.workspaceTitle)

                Text("Group every chart for the same song.")
                    .font(.caption)
                    .foregroundStyle(theme.workspaceSecondary)
            }
            .multilineTextAlignment(.center)

            Button(action: onCreateProject) {
                Label("New Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct IChartProjectCard: View {
    let project: ChartProject
    let charts: [Chart]
    let canCreateChart: Bool
    let canOpenCharts: Bool
    let availableCharts: [Chart]
    let chartEditingLockMessage: String
    let theme: IChartHomeTheme
    let onOpenChart: (Chart.ID) -> Void
    let onNewChart: (ChartProject.ID) -> Void
    let onAddExisting: (ChartProject) -> Void
    let onDuplicateVariant: (Chart, ChartProject) -> Void
    let onRemoveChart: (Chart.ID, ChartProject.ID) -> Void
    let onRenameProject: (ChartProject) -> Void
    let onDeleteProject: (ChartProject.ID) -> Void

    var body: some View {
        IChartHomePanel(
            title: project.title,
            systemImageName: "folder",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label(project.chartCountText, systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.panelSecondary)

                    Spacer(minLength: 12)

                    projectMenu
                }

                if charts.isEmpty {
                    Text("Add an existing chart or create the first chart for this song.")
                        .font(.subheadline)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 8) {
                        ForEach(charts) { chart in
                            IChartProjectChartRow(
                                chart: chart,
                                theme: theme,
                                canDuplicate: canCreateChart,
                                canOpenForEditing: canOpenCharts,
                                lockMessage: chartEditingLockMessage,
                                onOpen: {
                                    onOpenChart(chart.id)
                                },
                                onDuplicateVariant: {
                                    onDuplicateVariant(chart, project)
                                },
                                onRemove: {
                                    onRemoveChart(chart.id, project.id)
                                }
                            )
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        onAddExisting(project)
                    } label: {
                        Label("Add Existing", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(availableCharts.isEmpty)

                    Button {
                        onNewChart(project.id)
                    } label: {
                        Label("New Chart", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(IChartHomeBrand.blue)
                    .disabled(!canCreateChart)
                }
            }
        }
    }

    private var projectMenu: some View {
        Menu {
            Button {
                onRenameProject(project)
            } label: {
                Label("Rename Project", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDeleteProject(project.id)
            } label: {
                Label("Delete Project", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.panelSecondary)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Project actions")
    }
}

private struct IChartProjectChartRow: View {
    let chart: Chart
    let theme: IChartHomeTheme
    let canDuplicate: Bool
    let canOpenForEditing: Bool
    let lockMessage: String
    let onOpen: () -> Void
    let onDuplicateVariant: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chart.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)
                        .lineLimit(1)

                    Text(chart.librarySummaryText)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .lineLimit(1)

                    if !canOpenForEditing {
                        Label(lockMessage, systemImage: "lock.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.actionText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpenForEditing)
            .accessibilityHint(canOpenForEditing ? "" : lockMessage)

            Menu {
                Button(action: onDuplicateVariant) {
                    Label("Duplicate Variant", systemImage: "plus.square.on.square")
                }
                .disabled(!canDuplicate)

                Button(role: .destructive, action: onRemove) {
                    Label("Remove From Project", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Project chart actions")
        }
        .padding(12)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.panelBorder.opacity(0.25))
        }
    }
}

private struct IChartPreviewModePicker: View {
    @Binding var selection: IChartChartPreviewMode
    let theme: IChartHomeTheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(IChartChartPreviewMode.allCases) { mode in
                let isSelected = selection == mode

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(textColor(isSelected: isSelected))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(IChartHomeBrand.blue)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) preview")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .padding(3)
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(controlBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(controlBorder, lineWidth: 1)
        }
    }

    private var controlBackground: Color {
        theme.isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.34)
    }

    private var controlBorder: Color {
        theme.isDark ? Color.white.opacity(0.16) : IChartHomeBrand.ink.opacity(0.08)
    }

    private func textColor(isSelected: Bool) -> Color {
        if isSelected {
            return .white
        }

        return theme.isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink.opacity(0.72)
    }
}

private struct IChartWordmarkView: View {
    let variant: IChartLogoVariant
    let size: CGFloat

    init(variant: IChartLogoVariant, size: CGFloat) {
        self.variant = variant
        self.size = size
        #if canImport(UIKit)
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        #endif
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("i")
                .font(.custom(variant.iFontName, size: size * 0.58))
                .foregroundStyle(IChartHomeBrand.paper)
                .padding(.trailing, size * variant.iTrailingAdjustment)
                .offset(
                    x: size * variant.iOffset.width,
                    y: size * variant.iOffset.height
                )

            staffWord
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityLabel("iChart")
    }

    private var staffWord: some View {
        HStack(alignment: .lastTextBaseline, spacing: -size * 0.035) {
            Text("C")
                .font(.custom("FinaleMaestroText", size: size))
                .foregroundStyle(IChartHomeBrand.logoBlue)

            Text("hart")
                .font(.custom("FinaleMaestroText", size: size * 0.74))
                .foregroundStyle(IChartHomeBrand.paper)
                .baselineOffset(size * 0.01)
        }
        .padding(.trailing, size * 0.14)
        .overlay {
            IChartStaffMeasureLines()
                .frame(height: size * 0.72)
                .padding(.top, size * 0.08)
                .allowsHitTesting(false)
        }
    }
}

private struct IChartStaffMeasureLines: View {
    var body: some View {
        GeometryReader { geometry in
            let lineWidth = max(geometry.size.height * 0.018, 1)
            let barSpacing = max(geometry.size.width * 0.024, 4)

            Path { path in
                for index in 0..<5 {
                    let y = geometry.size.height * CGFloat(index) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(
                IChartHomeBrand.staffOnDark,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )

            Path { path in
                let firstBarX = geometry.size.width - barSpacing
                path.move(to: CGPoint(x: firstBarX, y: 0))
                path.addLine(to: CGPoint(x: firstBarX, y: geometry.size.height))
                path.move(to: CGPoint(x: geometry.size.width, y: 0))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
            }
            .stroke(
                IChartHomeBrand.staffOnDark,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
        }
    }
}

private struct ProjectRowView: View {
    let chart: Chart
    let theme: IChartHomeTheme
    let previewMode: IChartChartPreviewMode
    let isSelected: Bool
    let canDuplicate: Bool
    let canShareToForum: Bool
    let canOpenForEditing: Bool
    let lockMessage: String
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onShareToForum: () -> Void
    let onRemoveLocal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: previewMode == .collapsed ? 3 : 10) {
                    rowText

                    if previewMode != .collapsed {
                        IChartLibraryChartPreview(chart: chart, mode: previewMode)
                    }
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(!canOpenForEditing)
            .accessibilityHint(canOpenForEditing ? "" : lockMessage)

            rowActionControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, previewMode == .collapsed ? 13 : 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) {
            if previewMode == .collapsed {
                Divider().overlay(theme.panelBorder.opacity(0.32))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            }
        }
        .contextMenu {
            if canOpenForEditing {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .disabled(!canDuplicate)

                Button(action: onShareToForum) {
                    Label("Share To Forum", systemImage: "bubble.left.and.bubble.right")
                }
                .disabled(!canShareToForum)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button(role: .destructive, action: onRemoveLocal) {
                    Label("Delete Local", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var rowActionControl: some View {
        if canOpenForEditing {
            Menu {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .disabled(!canDuplicate)

                Button(action: onShareToForum) {
                    Label("Share To Forum", systemImage: "bubble.left.and.bubble.right")
                }
                .disabled(!canShareToForum)

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.actionText)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Chart actions")
        } else {
            Button(role: .destructive, action: onRemoveLocal) {
                Label("Delete Local", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Delete local chart")
            .accessibilityHint(lockMessage)
        }
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chart.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .lineLimit(1)

            Text(rowSubtitle)
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .lineLimit(1)

            if !canOpenForEditing {
                Label(lockMessage, systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.actionText)
                    .lineLimit(1)
            }
        }
    }

    private var rowSubtitle: String {
        chart.librarySummaryText
    }

    private var cardBackground: Color {
        if isSelected { return theme.selectionBackground }
        return previewMode == .collapsed ? .clear : theme.panelBackground
    }

    private var cardBorderColor: Color {
        isSelected ? theme.actionText : theme.panelBorder
    }
}

private struct IChartLibraryChartPreview: View {
    let chart: Chart
    let mode: IChartChartPreviewMode

    private var previewHeight: CGFloat {
        switch mode {
        case .collapsed:
            0
        case .quick:
            78
        case .large:
            174
        }
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 6),
                with: .color(IChartHomeBrand.paper)
            )

            drawSystems(in: rect.insetBy(dx: 14, dy: mode == .large ? 16 : 12), context: &context)

            context.stroke(
                Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6),
                with: .color(IChartHomeBrand.ink.opacity(0.08)),
                lineWidth: 1
            )
        }
        .frame(height: previewHeight)
        .background(IChartHomeBrand.paper.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private func drawSystems(in rect: CGRect, context: inout GraphicsContext) {
        let systemsToDraw = mode == .large ? 3 : 1
        let systemGap = rect.height / CGFloat(max(systemsToDraw, 1))

        for systemIndex in 0..<systemsToDraw {
            let y = rect.minY + CGFloat(systemIndex) * systemGap + systemGap * 0.42
            drawSystemLine(
                in: CGRect(x: rect.minX, y: y, width: rect.width, height: systemGap * 0.45),
                systemIndex: systemIndex,
                context: &context
            )
        }
    }

    private func drawSystemLine(
        in rect: CGRect,
        systemIndex: Int,
        context: inout GraphicsContext
    ) {
        let measuresPerSystem = min(max(chart.measures.count, 1), mode == .large ? 4 : 4)
        let measureWidth = rect.width / CGFloat(measuresPerSystem)
        let isSimple = chart.layoutStyle == .simpleChordSheet

        if !isSimple {
            var staffPath = Path()
            for index in 0..<5 {
                let y = rect.minY + CGFloat(index) * rect.height / 4
                staffPath.move(to: CGPoint(x: rect.minX, y: y))
                staffPath.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(staffPath, with: .color(IChartHomeBrand.ink.opacity(0.22)), lineWidth: 0.9)
        }

        var barPath = Path()
        for measureIndex in 0...measuresPerSystem {
            let x = rect.minX + CGFloat(measureIndex) * measureWidth
            barPath.move(to: CGPoint(x: x, y: rect.minY - (isSimple ? 8 : 0)))
            barPath.addLine(to: CGPoint(x: x, y: rect.maxY + (isSimple ? 8 : 0)))
        }
        context.stroke(barPath, with: .color(IChartHomeBrand.ink.opacity(0.72)), lineWidth: isSimple ? 1.4 : 1.0)

        if isSimple {
            drawSimpleChordMarks(in: rect, systemIndex: systemIndex, measureWidth: measureWidth, context: &context)
        } else {
            drawRhythmMarks(in: rect, systemIndex: systemIndex, measureWidth: measureWidth, context: &context)
        }
    }

    private func drawSimpleChordMarks(
        in rect: CGRect,
        systemIndex: Int,
        measureWidth: CGFloat,
        context: inout GraphicsContext
    ) {
        let startIndex = systemIndex * 4
        let measures = Array(chart.measures.dropFirst(startIndex).prefix(4))

        for (index, measure) in measures.enumerated() {
            guard let chord = measure.chordEvents.first else {
                continue
            }

            let x = rect.minX + CGFloat(index) * measureWidth + 10
            let y = rect.midY
            context.draw(
                Text(chord.symbol.displayText)
                    .font(.system(size: mode == .large ? 17 : 14, weight: .regular))
                    .foregroundStyle(IChartHomeBrand.ink),
                at: CGPoint(x: x, y: y),
                anchor: .leading
            )
        }
    }

    private func drawRhythmMarks(
        in rect: CGRect,
        systemIndex: Int,
        measureWidth: CGFloat,
        context: inout GraphicsContext
    ) {
        let startIndex = systemIndex * 4
        let measures = Array(chart.measures.dropFirst(startIndex).prefix(4))

        for (index, measure) in measures.enumerated() {
            let x = rect.minX + CGFloat(index) * measureWidth + measureWidth * 0.42
            let y = rect.midY
            let markHeight = rect.height * 0.42

            var stem = Path()
            stem.move(to: CGPoint(x: x, y: y - markHeight * 0.5))
            stem.addLine(to: CGPoint(x: x, y: y + markHeight * 0.5))
            context.stroke(stem, with: .color(IChartHomeBrand.ink.opacity(0.62)), lineWidth: 1)

            if !measure.chordEvents.isEmpty {
                context.draw(
                    Text(measure.chordEvents.first?.symbol.displayText ?? "")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(IChartHomeBrand.ink.opacity(0.70)),
                    at: CGPoint(x: rect.minX + CGFloat(index) * measureWidth + 8, y: rect.minY - 10),
                    anchor: .leading
                )
            }
        }
    }
}

private struct IChartLibraryBackground: View {
    let mode: IChartHomeAppearanceMode

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: baseColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: overlayColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
        }
    }

    private var baseColors: [Color] {
        switch mode {
        case .light:
            [
                IChartHomeBrand.paper,
                IChartHomeBrand.blueSoft,
                IChartHomeBrand.paperSecondary
            ]
        case .dark:
            [
                IChartHomeBrand.night,
                IChartHomeBrand.stage,
                Color(red: 0.08, green: 0.11, blue: 0.13)
            ]
        }
    }

    private var overlayColors: [Color] {
        switch mode {
        case .light:
            [
                IChartHomeBrand.night.opacity(0.94),
                IChartHomeBrand.night.opacity(0.58),
                IChartHomeBrand.night.opacity(0)
            ]
        case .dark:
            [
                Color.black.opacity(0.48),
                IChartHomeBrand.logoBlue.opacity(0.08),
                Color.black.opacity(0)
            ]
        }
    }
}
