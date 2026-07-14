import Foundation
import StoreKit
import SwiftUI

private enum IChartHomeBrand {
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.92)
    static let paperSecondary = Color(red: 0.93, green: 0.90, blue: 0.85)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let night = Color(red: 0.06, green: 0.09, blue: 0.11)
    static let stage = Color(red: 0.06, green: 0.08, blue: 0.11)
    static let blue = Color(red: 0.13, green: 0.42, blue: 0.54)
    static let logoBlue = Color(red: 0.56, green: 0.83, blue: 0.90)
    static let blueSoft = Color(red: 0.86, green: 0.93, blue: 0.95)
    static let staffOnDark = Color.white.opacity(0.23)
}

private enum IChartSupportLinks {
    static let supportURL = URL(string: "https://useichart.com/support")!
    static let supportEmail = "support@useichart.com"
}

private enum IChartHomeAppearanceMode: String, CaseIterable, Identifiable {
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

private struct IChartHomeTheme {
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
        isDark ? IChartHomeBrand.paper.opacity(0.10) : Color.white.opacity(0.68)
    }

    var panelBackground: Color {
        isDark ? IChartHomeBrand.stage.opacity(0.82) : IChartHomeBrand.paper.opacity(0.84)
    }

    var panelTitle: Color {
        isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink
    }

    var panelSecondary: Color {
        isDark ? IChartHomeBrand.paper.opacity(0.68) : Color.secondary
    }

    var panelBorder: Color {
        isDark ? Color.white.opacity(0.10) : IChartHomeBrand.ink.opacity(0.07)
    }

    var panelShadow: Color {
        isDark ? Color.black.opacity(0.28) : IChartHomeBrand.ink.opacity(0.08)
    }
}

private enum IChartLogoVariant: String {
    case b47b
    case b48a

    static var homeScreenTrialDefault: IChartLogoVariant {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-iChartLogoVariant"),
              arguments.indices.contains(arguments.index(after: flagIndex)) else {
            return .b48a
        }

        let requestedValue = arguments[arguments.index(after: flagIndex)].lowercased()
        return IChartLogoVariant(rawValue: requestedValue) ?? .b48a
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
    case faq
    case userPolicy
    case legal
    case contactUs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tutorial:
            "Tutorial"
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
            "App walkthrough"
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
            "iChart Tutorial"
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
            "A written guide to the main iChart systems, plus a hands-on tour when you want to try the flow."
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

private struct IChartTutorialSection: Identifiable {
    let id: String
    let title: String
    let summary: String
    let systemImageName: String
    let steps: [IChartTutorialStep]

    static let all: [IChartTutorialSection] = [
        IChartTutorialSection(
            id: "write-chart-flow",
            title: "Write A Real Chart",
            summary: "Start with the chart goal, choose the right page, write the music, then export the finished PDF.",
            systemImageName: "person.crop.circle.badge.checkmark",
            steps: [
                IChartTutorialStep(
                    id: "start-with-purpose",
                    title: "Start With The Job",
                    detail: "Decide what the band needs before you touch tools: a quick chord chart, a rhythm-section part, a rehearsal PDF, or a polished shareable chart. That choice should guide the page style and how much detail you add."
                ),
                IChartTutorialStep(
                    id: "chart-type",
                    title: "Choose The Page",
                    detail: "Tap New Chart. Use Simple Chord Sheet for chord-first pages and Rhythm Section Sheet when you need staff lines, slash rhythm, bass clef, rhythmic figures, or clearer rhythm-section notation."
                ),
                IChartTutorialStep(
                    id: "setup",
                    title: "Set The Starting Shape",
                    detail: "Choose the time signature and starting measure count up front. You can adjust later, but starting close saves cleanup when repeats, text, rhythm, and chords are already attached to measures."
                ),
                IChartTutorialStep(
                    id: "build-finish-save",
                    title: "Build, Check, Export",
                    detail: "Lay out measures first, add roadmap markings, enter chords and rhythms, add text last, then export a PDF. iChart keeps the editable chart in Charts and stores finished PDFs in the PDF Library."
                )
            ]
        ),
        IChartTutorialSection(
            id: "library",
            title: "Charts, Projects, And PDFs",
            summary: "Keep editable work, song folders, and finished PDFs in the right places.",
            systemImageName: "folder.badge.plus",
            steps: [
                IChartTutorialStep(
                    id: "charts",
                    title: "Charts",
                    detail: "Charts is where editable chart files live. Open a chart to keep working, or use chart actions to rename, duplicate, export, upload to Forums, or delete."
                ),
                IChartTutorialStep(
                    id: "projects",
                    title: "Projects",
                    detail: "Projects are for Pro song folders. Put related versions together, such as Concert, Bb Horn, Eb Horn, rhythm, rehearsal, or short-form copies, without mixing them into unrelated library files."
                ),
                IChartTutorialStep(
                    id: "variants",
                    title: "Variants",
                    detail: "Create a variant when the same song needs another reading view or layout. A variant lets you keep the original chart intact while preparing another part."
                ),
                IChartTutorialStep(
                    id: "pdfs",
                    title: "PDFs",
                    detail: "PDFs stores exported charts and forum downloads. This is the handoff shelf: preview, share, or remove finished files without changing the editable chart."
                ),
                IChartTutorialStep(
                    id: "cloud",
                    title: "Cloud Restore",
                    detail: "Pro cloud backup helps restore your library to the same account. Keep working locally, and use Settings when you need to confirm backup or restore state."
                )
            ]
        ),
        IChartTutorialSection(
            id: "editor-navigation",
            title: "Editor Navigation",
            summary: "Use Select to move around, then enter one tool at a time for the actual edit.",
            systemImageName: "hand.tap",
            steps: [
                IChartTutorialStep(
                    id: "select",
                    title: "Select",
                    detail: "Select is the clean browsing mode. Use it to scroll, tap existing objects, move rendered chords/text/roadmap markers, and get out of writing tools before making layout decisions."
                ),
                IChartTutorialStep(
                    id: "top-row",
                    title: "Top Row",
                    detail: "The top row chooses the system: Page, Measures, Repeats, Coda, Text, Time, Rhythm when available, Chord, and Free-Write. Treat each one as its own mode so accidental marks do not land in the wrong layer."
                ),
                IChartTutorialStep(
                    id: "active-row",
                    title: "Active Row",
                    detail: "The active row appears under the main toolbar after you choose a tool. It holds the actions for that tool only, such as Write, Erase, Read, Clear, Stack, End Rep, or Done."
                ),
                IChartTutorialStep(
                    id: "done-before-switching",
                    title: "Tap Done Before Switching",
                    detail: "When a tool shows Done, tap it before jumping to another tool. That returns the editor to Select and helps keep Pencil input, scrolling, and object selection predictable."
                ),
                IChartTutorialStep(
                    id: "write-vs-free-write",
                    title: "Read Tools Vs Free-Write",
                    detail: "Chord and Rhythm are read tools: iChart tries to interpret your writing and render notation. Free-Write is raw persistent ink for anything you want to stay exactly handwritten."
                )
            ]
        ),
        IChartTutorialSection(
            id: "page-tool",
            title: "Page",
            summary: "Use Page for whole-chart setup, appearance, transposition, and PDF export.",
            systemImageName: "doc.text",
            steps: [
                IChartTutorialStep(
                    id: "setup-export",
                    title: "Setup",
                    detail: "Use Setup when the whole page needs a structural change, such as page style, default time signature, or starting measure count. Make these changes early when possible."
                ),
                IChartTutorialStep(
                    id: "header",
                    title: "Header",
                    detail: "Use Header for the chart title. Typed is clean and fast; Handwritten lets the title match the chart's handwritten feel. Clear removes a handwritten header when you want to rewrite it."
                ),
                IChartTutorialStep(
                    id: "transpose",
                    title: "Transposition",
                    detail: "Instrument Transposition changes the reading view, such as Concert or Bb Horn. Transpose is a one-time written-chord action, so use it when you intentionally want the chart's existing chords moved."
                ),
                IChartTutorialStep(
                    id: "appearance",
                    title: "Appearance",
                    detail: "Style, Fonts, Pen Responsiveness, and Engraving change the look and feel of the chart. Use them after the music is readable, then do one final scan for spacing and collisions."
                ),
                IChartTutorialStep(
                    id: "export",
                    title: "Export PDF",
                    detail: "Export PDF creates the handoff file and saves it to PDFs. Export after checking title, page style, measure flow, repeats, text, chord placement, and rhythm rendering."
                )
            ]
        ),
        IChartTutorialSection(
            id: "measures-tool",
            title: "Measures",
            summary: "Use Measures to shape the chart before you fill it with notation.",
            systemImageName: "rectangle.split.3x1",
            steps: [
                IChartTutorialStep(
                    id: "select-measure",
                    title: "Select A Measure",
                    detail: "Tap a measure first. Measures actions use that measure as the target for insertion, row breaks, joins, and deletion."
                ),
                IChartTutorialStep(
                    id: "add-stack",
                    title: "Add And Stack",
                    detail: "Add inserts one measure after the selected measure. Stack is faster for adding a phrase, section, or full form because you can choose a measure count at once."
                ),
                IChartTutorialStep(
                    id: "first-double",
                    title: "First And Double",
                    detail: "First inserts a measure at the beginning. Double adds a measure with a double barline, which is useful for section breaks and endings."
                ),
                IChartTutorialStep(
                    id: "system-flow",
                    title: "New Row And Join",
                    detail: "New Row starts the selected measure on a new system. Join removes that manual break when the row should flow naturally again."
                ),
                IChartTutorialStep(
                    id: "delete",
                    title: "Delete And Range",
                    detail: "Delete removes the selected measure. On the first measure, Delete clears only the right barline when needed and keeps the opening barline. Range and Delete To remove a span; Clear cancels the pending range."
                )
            ]
        ),
        IChartTutorialSection(
            id: "repeats-tool",
            title: "Repeats",
            summary: "Use Repeats for repeat barlines, one-bar repeats, and endings.",
            systemImageName: "repeat",
            steps: [
                IChartTutorialStep(
                    id: "repeat-targets",
                    title: "Select The Boundary",
                    detail: "Tap the measure where the repeat or ending starts or ends. Repeats are boundary markings, so the selected measure matters."
                ),
                IChartTutorialStep(
                    id: "one-bar",
                    title: "One Bar",
                    detail: "One Bar places a one-measure repeat symbol at the selected measure. Use it when the previous measure should be repeated exactly."
                ),
                IChartTutorialStep(
                    id: "repeat-span",
                    title: "Start And End Rep",
                    detail: "Start marks the opening repeat. Move to the last measure of the repeated section and tap End Rep to close the span."
                ),
                IChartTutorialStep(
                    id: "endings",
                    title: "1st And 2nd",
                    detail: "Use 1st and 2nd for alternate endings. Start the ending at its first measure, then close it with End 1st or End 2nd at the last measure in that ending."
                ),
                IChartTutorialStep(
                    id: "remove",
                    title: "Remove Repeat, Remove Ending, And Clear",
                    detail: "Remove Repeat removes repeat markings at the selected measure. Remove Ending removes endings. Clear cancels a repeat or ending span you started but do not want to finish."
                )
            ]
        ),
        IChartTutorialSection(
            id: "coda-tool",
            title: "Coda",
            summary: "Use Coda for roadmap marks like Coda, Segno, Fine, D.S., and D.C.",
            systemImageName: "scope",
            steps: [
                IChartTutorialStep(
                    id: "markers",
                    title: "Markers",
                    detail: "Select the measure, then add Coda, To Coda, Segno, D.S., D.S. al Coda, D.C., D.C. al Fine, Fine, or N.C. as a point marker."
                ),
                IChartTutorialStep(
                    id: "edit-markers",
                    title: "Move, Size, And Delete",
                    detail: "Use Select to adjust a roadmap marker after placing it. Move it away from chords or text, resize when it needs more weight, and delete it when the road map changes."
                )
            ]
        ),
        IChartTutorialSection(
            id: "text-tool",
            title: "Text",
            summary: "Use Text for cues, feel notes, section labels, and rehearsal reminders.",
            systemImageName: "text.bubble",
            steps: [
                IChartTutorialStep(
                    id: "above",
                    title: "Add Text Above Selected Measure",
                    detail: "Select a measure, then add text above it for section names, hits, cue notes, or anything the player should see before reading the measure."
                ),
                IChartTutorialStep(
                    id: "below",
                    title: "Add Text Below Selected Measure",
                    detail: "Use below-measure text when the note belongs under the staff or chord grid, such as feel reminders, performance notes, or short warnings."
                ),
                IChartTutorialStep(
                    id: "write-text",
                    title: "Pencil Or Keyboard",
                    detail: "Use Pencil handwriting or the system keyboard tools for entry. Text mode should focus on the text box, not measure selection."
                ),
                IChartTutorialStep(
                    id: "edit-text",
                    title: "Move, Resize, And Remove",
                    detail: "Use Select to tap existing text, then move it up, down, left, or right to avoid clashes. Resize or delete it when the page needs cleanup."
                )
            ]
        ),
        IChartTutorialSection(
            id: "time-tool",
            title: "Time",
            summary: "Use Time for meter changes inside the chart.",
            systemImageName: "metronome",
            steps: [
                IChartTutorialStep(
                    id: "target-measure",
                    title: "Choose A Measure",
                    detail: "Tap Time, then tap the measure where the next time signature should start."
                ),
                IChartTutorialStep(
                    id: "meter-choice",
                    title: "Choose A Meter",
                    detail: "The Time tool offers common /4 and /8 meters, including 4/4, 3/4, 5/4, 6/4, 3/8, 5/8, 6/8, 7/8, 9/8, and 12/8."
                ),
                IChartTutorialStep(
                    id: "scope",
                    title: "Choose The Span",
                    detail: "Apply the change for a measure count, to the next time signature, or to the end of the piece. Use the shortest span that matches the music so later measures stay predictable."
                )
            ]
        ),
        IChartTutorialSection(
            id: "rhythm-tool",
            title: "Rhythm",
            summary: "Use Rhythm when iChart should read and render supported rhythm notation.",
            systemImageName: "music.note",
            steps: [
                IChartTutorialStep(
                    id: "availability",
                    title: "Availability",
                    detail: "Rhythm appears on chart styles that support rhythm notation, especially Rhythm Section Sheet. Simple chord charts can still use Free-Write for handwritten rhythm notes."
                ),
                IChartTutorialStep(
                    id: "write-rhythm",
                    title: "Write",
                    detail: "Tap Rhythm, choose Write, and write inside the target measure. Let the preview tell you what iChart is reading before you commit."
                ),
                IChartTutorialStep(
                    id: "supported-values",
                    title: "Use Supported Values",
                    detail: "The reader is built for clear slash rhythm, rests, common note values, dotted figures, ties, beams, and full-measure repeat symbols. If you need a custom mark, use Free-Write instead."
                ),
                IChartTutorialStep(
                    id: "clear-rhythm",
                    title: "Clear And Rewrite",
                    detail: "Use Clear Rendered Rhythm when a measure should be rebuilt. Erase removes rhythm ink while you are still writing; Clear removes the rendered result at the selected measure."
                )
            ]
        ),
        IChartTutorialSection(
            id: "chord-tool",
            title: "Chord",
            summary: "Use Chord when iChart should read handwritten chord symbols and render them cleanly.",
            systemImageName: "pencil",
            steps: [
                IChartTutorialStep(
                    id: "write",
                    title: "Write",
                    detail: "Tap Chord, choose Write, and write only inside the chord writing box. When you are finished, tap outside the box to read it. The chord ink lane should not render until you tap outside it."
                ),
                IChartTutorialStep(
                    id: "confirm",
                    title: "Confirm",
                    detail: "Pick the chord you meant, type it manually, or use Chord Repeat for •/•. Confirm renders the chord; Rewrite clears the attempt and lets you try again."
                ),
                IChartTutorialStep(
                    id: "move",
                    title: "Move",
                    detail: "Use Select to drag a rendered chord within its measure. Movement snaps to the measure's placement grid so chords stay musically attached instead of floating randomly."
                ),
                IChartTutorialStep(
                    id: "edit",
                    title: "Edit",
                    detail: "Double tap a rendered chord box when the text needs correction. Use Free-Write instead when the notation should stay handwritten and never be interpreted."
                )
            ]
        ),
        IChartTutorialSection(
            id: "free-hand-tool",
            title: "Free-Write",
            summary: "Use Free-Write for persistent raw ink that iChart never reads or interprets.",
            systemImageName: "pencil.and.scribble",
            steps: [
                IChartTutorialStep(
                    id: "write-freehand",
                    title: "Write",
                    detail: "Choose Write and draw handwritten chords, rhythms, articulations, rehearsal notes, layout marks, kicks, or reminders directly on the page."
                ),
                IChartTutorialStep(
                    id: "erase-freehand",
                    title: "Erase",
                    detail: "Choose Erase to remove Free-Write ink. Free-Write does not create movable boxes or saved symbols, so moving a mark means erasing and rewriting it."
                ),
                IChartTutorialStep(
                    id: "trust-freehand",
                    title: "When To Use It",
                    detail: "Use Free-Write when speed matters, when a symbol is too personal or unusual for a reader, or when you want the chart to look exactly like your handwriting."
                )
            ]
        ),
        IChartTutorialSection(
            id: "account-pro-forums",
            title: "Account, Pro, And Forums",
            summary: "Know what stays local, what needs Pro, and how community sharing works.",
            systemImageName: "person.2",
            steps: [
                IChartTutorialStep(
                    id: "basic",
                    title: "Basic",
                    detail: "Basic includes the chart-writing tools, PDF export, and three local charts. If you are over the Basic cap after Pro ends, choose which three charts stay active."
                ),
                IChartTutorialStep(
                    id: "pro",
                    title: "Pro",
                    detail: "Pro adds unlimited local charts, Projects, cloud backup and restore, and Forums."
                ),
                IChartTutorialStep(
                    id: "cloud",
                    title: "Cloud Backup",
                    detail: "Cloud backup is for account restore support. Local editing and PDF export keep working without cloud service, but cloud backup pauses when Pro is not active."
                ),
                IChartTutorialStep(
                    id: "forums",
                    title: "Forums",
                    detail: "Forums are a Pro community PDF library. Upload starts from a chart made in iChart, runs metadata and provenance checks, then publishes a fixed PDF snapshot when it passes."
                ),
                IChartTutorialStep(
                    id: "forum-remove",
                    title: "Withdraw Or Remove",
                    detail: "You can withdraw a pending submission or remove your published forum chart. Removing it hides the public post and download, but the chart stays in your own library."
                )
            ]
        ),
        IChartTutorialSection(
            id: "settings-help",
            title: "Settings And Support",
            summary: "Check account identity, Pro state, backup, appearance, and support paths.",
            systemImageName: "gearshape",
            steps: [
                IChartTutorialStep(
                    id: "account-identity",
                    title: "Account Identity",
                    detail: "Name and email come from account creation and are used for support, Pro, cloud backup, and forum attribution. Contact support if an identifier needs to change."
                ),
                IChartTutorialStep(
                    id: "subscription",
                    title: "Subscription",
                    detail: "Use Settings to check Pro status, restore purchases, and see when cloud backup or Forums require Pro."
                ),
                IChartTutorialStep(
                    id: "theme",
                    title: "Theme",
                    detail: "Use light or dark mode based on the rehearsal environment. The chart itself should stay readable before it looks stylish."
                ),
                IChartTutorialStep(
                    id: "support",
                    title: "Support",
                    detail: "Use Contact Us for bugs, account questions, or Pro help. Include the account email and the chart type or tool involved, but never send passwords or recovery links."
                )
            ]
        )
    ]
}

private struct IChartTutorialStep: Identifiable {
    let id: String
    let title: String
    let detail: String
}

private struct IChartHelpArticleSection: Identifiable {
    let id: String
    let title: String
    let systemImageName: String
    let body: String
    let bullets: [String]

    static func sections(for topic: IChartHelpTopic) -> [IChartHelpArticleSection] {
        switch topic {
        case .tutorial:
            []
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

    private static let faq: [IChartHelpArticleSection] = [
        IChartHelpArticleSection(
            id: "faq-forums",
            title: "What are Forums?",
            systemImageName: "bubble.left.and.bubble.right",
            body: "Forums are a Pro space for sharing useful chart PDFs with other musicians.",
            bullets: [
                "A forum upload starts from a chart you made in iChart.",
                "iChart checks that the PDF and chart details belong to that upload before it appears publicly.",
                "Members can browse, download, vote, comment, and report charts that need attention."
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
            title: "What changes with Pro?",
            systemImageName: "star.circle",
            body: "Basic is the local chart writer. Pro adds the service-backed parts of iChart.",
            bullets: [
                "Basic includes local chart writing, three local charts, and PDF export.",
                "Pro adds unlimited local charts, Projects, cloud backup and restore, and Forums.",
                "If Pro ends, local charts remain yours, but over-cap access and cloud features follow the downgrade rules in Settings."
            ]
        ),
        IChartHelpArticleSection(
            id: "faq-support",
            title: "What should I send support?",
            systemImageName: "envelope",
            body: "Send enough detail for the issue to be reproduced without sharing private credentials.",
            bullets: [
                "For chart-writing bugs, include the chart type, active tool, and what you expected to happen.",
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
                "Basic includes local chart-writing tools and PDF export.",
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
                "Editable chart data, source ink, and private local authoring state are not shared in V1."
            ]
        ),
        IChartHelpArticleSection(
            id: "policy-conduct",
            title: "Conduct",
            systemImageName: "checkmark.seal",
            body: "Treat the community library like a shared music stand.",
            bullets: [
                "Use comments for helpful corrections, version notes, and respectful discussion.",
                "Report charts or comments that look inaccurate, miscredited, abusive, or unsafe.",
                "Voting is for chart quality, not personal pile-ons. Repeated bad-faith behavior may limit forum access."
            ]
        ),
        IChartHelpArticleSection(
            id: "policy-plan",
            title: "Basic, Pro, And Downgrades",
            systemImageName: "star.circle",
            body: "Basic keeps the local writer available. Pro adds the larger library and online features.",
            bullets: [
                "Basic keeps three local charts, all local authoring tools, and PDF export.",
                "Pro adds unlimited charts, Projects, cloud backup and restore, and Forums.",
                "If Pro ends while your library is above the Basic cap, chart access locks until you choose three active Basic charts; cloud backup is removed after the paid period or Apple billing grace ends."
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
                "Forum posts, comments, votes, reports, downloads, and moderation events are handled by the community service."
            ]
        ),
        IChartHelpArticleSection(
            id: "legal-subscriptions",
            title: "Subscriptions",
            systemImageName: "creditcard",
            body: "Pro is an auto-renewing subscription managed through Apple purchase and restore flows.",
            bullets: [
                "Apple handles purchase and restore in the app.",
                "Pro unlocks unlimited local charts, Projects, cloud backup and restore, and Forums.",
                "If Pro cannot be verified, cloud backup and Forums pause while Basic local authoring and PDF export remain available within the Basic chart cap."
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
                "For chart-writing bugs, mention the chart type, active tool, and what you expected to happen.",
                "For account or Pro questions, include your account email and whether you are on Basic or Pro.",
                "Do not send passwords, recovery links, verification links, or payment credentials."
            ]
        )
    ]
}

private enum IChartGuidedTourStep: String, Identifiable {
    case welcome
    case charts
    case newChart
    case simpleChart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:
            "Welcome To iChart"
        case .charts:
            "Start With Charts"
        case .newChart:
            "Create Your First Chart"
        case .simpleChart:
            "Choose Simple Chord Sheet"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            "Write the chart. Share with the band. Take a quick tour, or jump straight into the app."
        case .charts:
            "Tap Charts in the sidebar. This is where your charts and new chart creation live."
        case .newChart:
            "Tap New Chart to choose what kind of chart you want to make."
        case .simpleChart:
            "Choose Simple Chord Sheet for a chord-first page. Rhythm Section Sheet gives you more room for slashes, hits, and groove cues."
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .welcome:
            "Start Tour"
        case .charts, .newChart, .simpleChart:
            nil
        }
    }

    var targetText: String? {
        switch self {
        case .welcome:
            nil
        case .charts:
            "Tap Charts"
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
    @EnvironmentObject private var store: ChartLibraryStore
    @EnvironmentObject private var authStore: IChartAuthStore
    @EnvironmentObject private var cloudSyncStore: ChartCloudSyncStore
    @EnvironmentObject private var subscriptionStore: IChartStoreKitSubscriptionStore
    @EnvironmentObject private var forumStore: IChartForumStore
    @EnvironmentObject private var pdfLibraryStore: IChartPDFLibraryStore
    let onOpenChart: (Chart.ID, EditorCanvasMode) -> Void
    @AppStorage("iChartHomeAppearanceMode") private var homeAppearanceModeRawValue = IChartHomeAppearanceMode.light.rawValue
    @AppStorage("iChartHomeSidebarCollapsed") private var isSidebarCollapsed = false
    @AppStorage("iChartChartPreviewMode") private var chartPreviewModeRawValue = IChartChartPreviewMode.collapsed.rawValue
    @AppStorage("iChartChartsWorkspaceMode") private var chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
    @AppStorage("iChartHasSeenAccountLanding") private var hasSeenAccountLanding = false
    @AppStorage("iChartHasSeenGuidedTourOffer") private var hasSeenGuidedTourOffer = false
    @AppStorage("iChartPendingSimpleChartTour") private var pendingSimpleChartTour = false
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
    @State private var showingAccountLanding = false
    @State private var showingCreateProject = false
    @State private var renameRequest: ChartRenameRequest?
    @State private var deleteRequest: ChartDeleteRequest?
    @State private var renameProjectRequest: ChartProjectRenameRequest?
    @State private var addChartsRequest: ChartProjectAddChartsRequest?
    @State private var duplicateVariantRequest: ChartProjectDuplicateVariantRequest?
    @State private var forumSearchText = ""
    @State private var forumPublishRequest: IChartForumPublishRequest?
    @State private var selectedPDFLibraryItem: IChartPDFLibraryItem?
    @State private var activeLibraryOperation: IChartLibraryOperation?
    @State private var activeLibraryOperationID = UUID()

    init(onOpenChart: @escaping (Chart.ID, EditorCanvasMode) -> Void) {
        self.onOpenChart = onOpenChart
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

            selectedHomeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IChartLibraryBackground(mode: homeAppearanceMode).ignoresSafeArea())
        .tint(IChartHomeBrand.blue)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            if let guidedTourStep, guidedTourStep != .simpleChart {
                IChartGuidedTourPrompt(
                    step: guidedTourStep,
                    theme: homeTheme,
                    onPrimaryAction: beginGuidedTour,
                    onSkip: finishGuidedTour
                )
                .padding(.top, 28)
                .padding(.trailing, 28)
            }
        }
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
            cloudSyncStore.authStateChanged(authStore.state)
            forumStore.resumePendingUploads(charts: store.charts)
            refreshForumHomeIfVisible()
            updateAccountLandingPresentation()
        }
        .onChange(of: authStore.state) { _, state in
            cloudSyncStore.authStateChanged(state)
            refreshForumHomeIfVisible(authState: state)
            updateAccountLandingPresentation()
        }
        .onChange(of: store.entitlements) { _, _ in
            cloudSyncStore.authStateChanged(authStore.state)
            applyForumDownloadAccess(store.subscriptionState)
            refreshForumHomeIfVisible()
        }
        .sheet(isPresented: $showingLayoutPicker) {
            NewChartLayoutPickerView(
                tourStep: guidedTourStep == .simpleChart ? .simpleChart : nil
            ) { layoutStyle in
                showingLayoutPicker = false
                createNewChart(layoutStyle: layoutStyle)
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
                store.createProject(title: title)
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
                store.duplicateChart(
                    id: chartID,
                    title: title,
                    transpositionView: transpositionView,
                    projectID: projectID
                )
            }
        }
        .sheet(item: $forumPublishRequest) { request in
            IChartForumPublishSheet(
                request: request,
                theme: homeTheme
            ) { chart, draft in
                forumStore.enqueuePublish(chart: chart, draft: draft)
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
                    isWorking: forumStore.isWorking,
                    theme: homeTheme,
                    onVote: { vote in
                        Task {
                            await forumStore.vote(vote, on: detail)
                        }
                    },
                    onComment: { body in
                        Task {
                            await forumStore.addComment(body, to: detail)
                        }
                    },
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
                    onDownloadPDF: {
                        Task {
                            guard let downloadedPDF = await forumStore.downloadPDF(for: detail) else {
                                return
                            }

                            do {
                                let libraryPDF = try pdfLibraryStore.save(downloadedPDF, source: .forumDownload)
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
        .sheet(item: $selectedPDFLibraryItem) { item in
            if let exportedPDF = pdfLibraryStore.exportedPDF(for: item) {
                PDFExportPreviewView(exportedPDF: exportedPDF)
            } else {
                NavigationStack {
                    ContentUnavailableView(
                        "PDF Not Found",
                        systemImage: "doc.badge.exclamationmark",
                        description: Text("This PDF is no longer available on this device.")
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
        .alert(
            "Delete Chart?",
            isPresented: deleteConfirmationPresented,
            presenting: deleteRequest
        ) { request in
            Button("Delete", role: .destructive) {
                runLibraryOperation(.deletingChart(request.title)) {
                    store.deleteChart(id: request.chartID)
                }
                deleteRequest = nil
            }
            Button("Cancel", role: .cancel) {
                deleteRequest = nil
            }
        } message: { request in
            Text("This removes \(request.title) from the local library.")
        }
    }

    @ViewBuilder
    private var selectedHomeContent: some View {
        switch selectedHomeTab {
        case .charts:
            chartsHomeContent
        case .pdfs:
            pdfLibraryHomeContent
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
                        ForEach(store.projects) { project in
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
                                    store.deleteProject(id: projectID)
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
                        message: "Upgrade to Pro to group every chart for the same song, duplicate section variants, and keep alternate parts together.",
                        systemImageName: "lock.folder",
                        theme: homeTheme
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
                IChartPDFLibraryHomeView(
                    items: pdfLibraryStore.visibleItems(for: store.subscriptionState),
                    theme: homeTheme,
                    onOpen: { item in
                        selectedPDFLibraryItem = item
                    },
                    onDelete: { item in
                        pdfLibraryStore.delete(item)
                    }
                )
            }
        }
        .task {
            pdfLibraryStore.reload()
        }
    }

    private var forumsHomeContent: some View {
        homeScroll {
            IChartHomePanel(
                title: "Forums",
                systemImageName: "bubble.left.and.bubble.right",
                theme: homeTheme
            ) {
                if store.canUse(.forums) {
                    IChartForumHomeView(
                        state: forumStore.state,
                        searchText: $forumSearchText,
                        charts: store.charts,
                        currentUserID: authStore.state.signedInSession?.id,
                        uploadQueue: forumStore.uploadQueue,
                        statusMessage: forumStore.statusMessage,
                        errorMessage: forumStore.errorMessage,
                        theme: homeTheme,
                        onSearch: { query in
                            Task {
                                await forumStore.refresh(
                                    authState: authStore.state,
                                    entitlements: store.entitlements,
                                    query: query
                                )
                            }
                        },
                        onRefresh: {
                            Task {
                                await forumStore.refresh(
                                    authState: authStore.state,
                                    entitlements: store.entitlements,
                                    query: forumSearchText
                                )
                            }
                        },
                        onPublishChart: { chart in
                            forumPublishRequest = IChartForumPublishRequest(chart: chart)
                        },
                        onRetryUpload: { item in
                            forumStore.retryUpload(item, charts: store.charts)
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
                        }
                    )
                } else {
                    IChartLockedFeatureView(
                        title: "Forums require Pro",
                        message: "Upgrade to Pro to join iChart Forums.",
                        systemImageName: "lock.icloud",
                        theme: homeTheme
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
                    systemImageName: store.subscriptionState.systemImageName,
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
        homeScroll {
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
                        onStartGuidedTour: startGuidedTourFromHelp
                    )
                        .padding(.top, 16)
                }
            }
        }
    }

    private func homeScroll<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
        }
    }

    private var chartListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.canOpenChartsForEditing {
                HStack(alignment: .center, spacing: 16) {
                    Spacer()

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
                    ForEach(store.charts) { chart in
                        ProjectRowView(
                            chart: chart,
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
                                    store.duplicateChart(id: chart.id)
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
                                deleteRequest = ChartDeleteRequest(chart: chart)
                            }
                        )
                    }
                }
            }
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { deleteRequest != nil },
            set: { isPresented in
                if !isPresented {
                    deleteRequest = nil
                }
            }
        )
    }

    private func handleHomeTabSelection(_ tab: IChartHomeTab) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedHomeTab = tab
        }

        if tab == .forums {
            forumStore.resumePendingUploads(charts: store.charts)
            refreshForumHomeIfVisible()
        }

        guard guidedTourStep == .charts, tab == .charts else {
            return
        }

        chartsWorkspaceModeRawValue = IChartChartsWorkspaceMode.charts.rawValue
        withAnimation(.easeInOut(duration: 0.18)) {
            guidedTourStep = .newChart
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

        Task {
            await forumStore.refresh(
                authState: authState ?? authStore.state,
                entitlements: entitlements ?? store.entitlements,
                query: forumSearchText
            )
        }
    }

    private func createNewChart(layoutStyle: ChartLayoutStyle) {
        let targetProjectID = pendingProjectForNewChart
        let startsGuidedSimpleChartTour = guidedTourStep == .simpleChart && layoutStyle == .simpleChordSheet
        pendingProjectForNewChart = nil

        let traceSpan = IChartPerformanceTrace.start(
            "library.createNewChart",
            metadata: [
                "layoutStyle": layoutStyle.rawValue,
                "targetProject": targetProjectID == nil ? "none" : "present"
            ]
        )
        runLibraryOperation(.creatingChart(layoutStyle.displayText)) {
            guard store.createBlankChart(layoutStyle: layoutStyle, projectID: targetProjectID),
                  let chartID = store.selectedChartID else {
                IChartPerformanceTrace.end(traceSpan, metadata: ["result": "blocked"])
                return
            }

            if guidedTourStep == .simpleChart {
                guidedTourStep = nil
            }

            if startsGuidedSimpleChartTour {
                pendingSimpleChartTour = true
            }

            onOpenChart(chartID, startsGuidedSimpleChartTour ? .chordEntry : .browse)
            IChartPerformanceTrace.end(traceSpan, metadata: ["result": "opened"])
        }
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

    private func updateAccountLandingPresentation() {
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

    private func apply(subscriptionPreview: IChartSubscriptionEntitlement) {
        withAnimation(.easeInOut(duration: 0.18)) {
            store.applySubscriptionState(subscriptionPreview)
        }
        applyForumDownloadAccess(subscriptionPreview)
        cloudSyncStore.authStateChanged(authStore.state)
    }

    private func applyForumDownloadAccess(_ subscription: IChartSubscriptionEntitlement) {
        pdfLibraryStore.removeForumDownloadsIfInactive(for: subscription)
        if selectedPDFLibraryItem?.source == .forumDownload,
           !subscription.allowsForumDownloadAccess {
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

private struct ChartDeleteRequest: Identifiable, Hashable {
    let chartID: Chart.ID
    let title: String

    var id: Chart.ID { chartID }

    init(chart: Chart) {
        chartID = chart.id
        title = chart.title
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
    @FocusState private var isTitleFocused: Bool

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
                    HStack(spacing: 10) {
                        TextField("Chart title", text: $title)
                            .focused($isTitleFocused)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(save)

                        IChartKeyboardFocusButton(
                            accessibilityLabel: "Open keyboard for chart title"
                        ) {
                            isTitleFocused = true
                        }
                    }
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
        .task {
            isTitleFocused = true
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
                            .background(IChartHomeBrand.paper.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(step.message)
                        .font(.subheadline)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let targetText = step.targetText {
                Label(targetText, systemImage: "hand.tap")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.16 : 0.76))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 10) {
                if let primaryActionTitle = step.primaryActionTitle {
                    Button(primaryActionTitle, action: onPrimaryAction)
                        .buttonStyle(.borderedProminent)
                        .tint(IChartHomeBrand.blue)
                }

                Button("Skip Tour", action: onSkip)
                    .buttonStyle(.bordered)
                    .tint(IChartHomeBrand.blue)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
        .shadow(color: theme.panelShadow, radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }
}

private struct IChartGuidedTourSheetCallout: View {
    let step: IChartGuidedTourStep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(step.title, systemImage: "hand.tap")
                .font(.headline.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.ink)

            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IChartHomeBrand.blueSoft.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(IChartHomeBrand.blue.opacity(0.16), lineWidth: 1)
        }
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
    @FocusState private var isProjectTitleFocused: Bool

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
                    HStack(spacing: 10) {
                        TextField("Song or project title", text: $projectTitle)
                            .focused($isProjectTitleFocused)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(save)

                        IChartKeyboardFocusButton(
                            accessibilityLabel: "Open keyboard for project title"
                        ) {
                            isProjectTitleFocused = true
                        }
                    }
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
        .task {
            isProjectTitleFocused = true
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
                                    .foregroundStyle(IChartHomeBrand.blue)
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
                                    .foregroundStyle(IChartHomeBrand.blue)
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
    @FocusState private var isTitleFocused: Bool

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

                        HStack(spacing: 10) {
                            TextField("Horn section chart", text: $title)
                                .focused($isTitleFocused)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            IChartKeyboardFocusButton(
                                accessibilityLabel: "Open keyboard for variant title"
                            ) {
                                isTitleFocused = true
                            }
                        }
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
        .task {
            isTitleFocused = true
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

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImageName,
            description: Text(message)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .foregroundStyle(theme.panelSecondary)
    }
}

private struct IChartForumPublishRequest: Identifiable {
    let chart: Chart

    var id: Chart.ID { chart.id }
}

private struct IChartPDFLibraryHomeView: View {
    let items: [IChartPDFLibraryItem]
    let theme: IChartHomeTheme
    let onOpen: (IChartPDFLibraryItem) -> Void
    let onDelete: (IChartPDFLibraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exports and forum downloads appear here so you can preview, share, or remove them later.")
                .font(.subheadline)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(IChartPDFLibrarySource.allCases) { source in
                IChartPDFLibrarySection(
                    source: source,
                    items: items.filter { $0.source == source },
                    theme: theme,
                    onOpen: onOpen,
                    onDelete: onDelete
                )
            }
        }
    }
}

private struct IChartPDFLibrarySection: View {
    let source: IChartPDFLibrarySource
    let items: [IChartPDFLibraryItem]
    let theme: IChartHomeTheme
    let onOpen: (IChartPDFLibraryItem) -> Void
    let onDelete: (IChartPDFLibraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: source.systemImageName)
                    .foregroundStyle(IChartHomeBrand.blue)
                    .frame(width: 22)

                Text(source.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)

                Spacer()

                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(theme.emptyStateBackground)
                    .clipShape(Capsule())
            }

            if items.isEmpty {
                ContentUnavailableView(
                    source.emptyTitle,
                    systemImage: source.systemImageName,
                    description: Text(source.emptyMessage)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .foregroundStyle(theme.panelSecondary)
                .background(theme.emptyStateBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        IChartPDFLibraryRow(
                            item: item,
                            theme: theme,
                            onOpen: {
                                onOpen(item)
                            },
                            onDelete: {
                                onDelete(item)
                            }
                        )
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title3.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 36, height: 36)
                .background(theme.emptyStateBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
                    .lineLimit(1)

                Text(item.fileName)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 7) {
                    metadataPill(item.source.itemTitle)
                    metadataPill(item.layoutStyle.displayText)
                    metadataPill(item.transpositionText)
                    metadataPill(item.pageCountText)
                    metadataPill(item.fileSizeText)
                }
                .font(.caption2.weight(.semibold))
            }

            Spacer(minLength: 12)

            Button(action: onOpen) {
                Image(systemName: "eye")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Open \(item.displayTitle)")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Delete \(item.displayTitle)")
        }
        .padding(12)
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(theme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct IChartForumHomeView: View {
    let state: IChartForumState
    @Binding var searchText: String
    let charts: [Chart]
    let currentUserID: UUID?
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

    @State private var submittedSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let summaries = loadedSummaries {
                IChartForumCommunityHero(
                    featuredPosts: featuredPosts(from: summaries),
                    currentUserID: currentUserID,
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
    }

    private var loadedSummaries: [IChartForumSongSummary]? {
        guard case .loaded(let summaries) = state else {
            return nil
        }

        return summaries
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingSearchResults: Bool {
        !submittedSearchText.isEmpty
    }

    private var searchAndPublishRow: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.panelSecondary)
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Search songs, artists, arrangers, or tags")
                        .foregroundStyle(theme.panelSecondary.opacity(theme.isDark ? 0.95 : 1.0))
                )
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .foregroundStyle(theme.panelTitle)
                    .tint(IChartHomeBrand.logoBlue)
                    .onSubmit {
                        submitSearch()
                    }
                    .onChange(of: searchText) { _, newValue in
                        handleSearchTextChange(newValue)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.panelBackground.opacity(theme.isDark ? 0.94 : 0.84))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.isDark ? Color.white.opacity(0.18) : theme.panelBorder, lineWidth: 1)
            }

            Button {
                submitSearch()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(IChartHomeBrand.blue)
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
            ContentUnavailableView(
                "Sign In Required",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Forums use verified account identity so charts and comments are never anonymous.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        case .requiresPro:
            ContentUnavailableView(
                "Forums Require Pro",
                systemImage: "lock.icloud",
                description: Text("Upgrade to Pro to browse, publish, vote, comment, and download forum chart PDFs.")
            )
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

                searchAndPublishRow

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
                                subtitle: "Matched forum charts grouped by song.",
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
        let normalizedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue != submittedSearchText else {
            return
        }

        let shouldRestoreDefaultCharts = !submittedSearchText.isEmpty
        submittedSearchText = ""
        if shouldRestoreDefaultCharts {
            onSearch("")
        }
    }

    private func featuredPosts(from summaries: [IChartForumSongSummary]) -> [IChartForumFeaturedPost] {
        summaries
            .flatMap { summary in
                summary.topPosts.map { post in
                    IChartForumFeaturedPost(song: summary.song, post: post)
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
    let featuredPosts: [IChartForumFeaturedPost]
    let currentUserID: UUID?
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
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Community Bandstand")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.panelTitle)

                    Text("Find working chord and rhythm PDFs, shout out clean charts, and help other musicians get through rehearsal faster.")
                        .font(.subheadline)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

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
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                statPill(value: "\(userPosts.count)", label: "Contributions", systemImageName: "square.and.arrow.up")
                statPill(value: "0", label: "Downloads", systemImageName: "tray.and.arrow.down")
                statPill(value: "\(userUpvoteCount)", label: "Upvotes", systemImageName: "hand.thumbsup")
                statPill(value: "0", label: "Badges", systemImageName: "checkmark.seal")
                statPill(value: "\(userTopRatedCount)", label: "Top Rated", systemImageName: "star.fill")
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.14 : 0.70),
                    IChartHomeBrand.paper.opacity(theme.isDark ? 0.08 : 0.52),
                    theme.emptyStateBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous)
                .stroke(theme.panelBorder.opacity(0.72), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            IChartForumPalette.accentGradient
                .frame(height: 3)
        }
    }

    private func statPill(value: String, label: String, systemImageName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImageName)
                .font(.caption.weight(.bold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 24, height: 24)
                .background(IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.18 : 0.82))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(theme.panelTitle)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [
                    theme.panelBackground.opacity(theme.isDark ? 0.68 : 0.88),
                    IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.10 : 0.36)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(IChartHomeBrand.blue.opacity(theme.isDark ? 0.48 : 0.30))
                .frame(width: 2)
        }
    }
}

private struct IChartForumTopChartsBoard: View {
    let featuredPosts: [IChartForumFeaturedPost]
    let isSearching: Bool
    let theme: IChartHomeTheme
    let onOpenPost: (ForumSong, ForumChartPost) -> Void

    @State private var expandedPeriod: IChartForumTopChartPeriod?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 132), spacing: 10, alignment: .top), count: 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Top Charts")
                        .font(.title2.weight(.black))
                        .foregroundStyle(theme.panelTitle)

                    Text(isSearching ? "Ranked charts matching this search." : "The charts players are backing right now.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.panelSecondary)
                }

                Spacer(minLength: 12)

                Text("Top 10")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(IChartHomeBrand.blue)
                    .clipShape(Capsule())
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
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    theme.panelBackground.opacity(theme.isDark ? 0.78 : 0.96),
                    IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.08 : 0.46),
                    IChartHomeBrand.paper.opacity(theme.isDark ? 0.06 : 0.40)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(IChartHomeBrand.blue.opacity(theme.isDark ? 0.64 : 0.46))
                .frame(width: 3)
        }
        .overlay(alignment: .top) {
            IChartForumPalette.accentGradient
                .frame(height: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous)
                .stroke(theme.panelBorder.opacity(0.72), lineWidth: 1)
        }
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
                        .foregroundStyle(IChartHomeBrand.blue)
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
        .background(
            LinearGradient(
                colors: [
                    theme.emptyStateBackground,
                    IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.08 : 0.36)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous)
                .stroke(theme.panelBorder.opacity(0.68), lineWidth: 1)
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
                        .foregroundStyle(accent)

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
                    .foregroundStyle(rank <= 3 ? accent : theme.panelSecondary)
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
                }

                Spacer(minLength: 4)

                Text("\(max(0, featuredPost.post.voteUpCount))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.panelSecondary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panelBackground.opacity(theme.isDark ? 0.58 : 0.74))
            .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(featuredPost.post.chartTitle)")
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
        .background(
            LinearGradient(
                colors: [
                    IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.08 : 0.38),
                    theme.panelBackground.opacity(theme.isDark ? 0.58 : 0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: IChartForumPalette.cornerRadius, style: .continuous))
    }
}

private struct IChartForumSectionHeader: View {
    let title: String
    let subtitle: String
    let theme: IChartHomeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(theme.panelSecondary)
        }
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
                    .foregroundStyle(IChartHomeBrand.blue)
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
                .foregroundStyle(IChartHomeBrand.blue)
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
                    .foregroundStyle(IChartHomeBrand.blue)
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
                    IChartForumPostRow(post: post, theme: theme) {
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

                    if !post.tags.isEmpty {
                        Text(post.tags.joined(separator: " · "))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(IChartHomeBrand.blue)
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
                    .foregroundStyle(IChartHomeBrand.blue)
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
            } else {
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
            return IChartHomeBrand.blue
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
            return IChartHomeBrand.blue
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(theme.isDark ? 0.18 : 0.12)
    }
}

private struct IChartForumPublishSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: IChartForumPublishRequest
    let theme: IChartHomeTheme
    let onPublish: (Chart, ForumPublishDraft) -> Void

    @State private var draft = ForumPublishDraft()
    @State private var validationErrors: [ForumPublishValidationError] = []
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case song
        case artist
        case arranger
        case tags
        case note
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metadata") {
                    forumTextField("Song Title", text: $draft.songTitle, field: .song)
                    forumTextField("Artist", text: $draft.artistName, field: .artist)
                    forumTextField("Arranger Credit", text: $draft.arrangerCredit, field: .arranger)
                    forumTextField("Tags (Optional)", text: $draft.tagsText, field: .tags, prompt: "live, acoustic, rhythm section")
                    forumMultilineTextField("Notes (Optional)", text: $draft.versionNote, field: .note)
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
        field: Field,
        prompt: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            if let prompt {
                TextField(title, text: text, prompt: Text(prompt))
                    .focused($focusedField, equals: field)
            } else {
                TextField(title, text: text)
                    .focused($focusedField, equals: field)
            }

            IChartKeyboardFocusButton(accessibilityLabel: "Open keyboard for \(title)") {
                focusedField = field
            }
        }
    }

    private func forumMultilineTextField(
        _ title: String,
        text: Binding<String>,
        field: Field,
        prompt: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let prompt {
                TextField(title, text: text, prompt: Text(prompt), axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: field)
            } else {
                TextField(title, text: text, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: field)
            }

            IChartKeyboardFocusButton(accessibilityLabel: "Open keyboard for \(title)") {
                focusedField = field
            }
        }
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
    let detail: IChartForumPostDetail
    let currentUserID: UUID?
    let downloadedPDF: ExportedPDF?
    let isWorking: Bool
    let theme: IChartHomeTheme
    let onVote: (ForumVoteValue) -> Void
    let onComment: (String) -> Void
    let onReportPost: (ForumReportReason) -> Void
    let onReportComment: (ForumComment, ForumReportReason) -> Void
    let onDownloadPDF: () -> Void
    let onClearDownloadedPDF: () -> Void
    let onWithdrawPost: () -> Void
    let onRemovePost: () -> Void

    @State private var commentText = ""
    @FocusState private var isCommentFocused: Bool

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
                PDFExportPreviewView(exportedPDF: downloadedPDF)
            }
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

            if !detail.authorBadges.isEmpty {
                HStack(spacing: 8) {
                    ForEach(detail.authorBadges) { badge in
                        Label(badge.badgeType.displayText, systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IChartHomeBrand.blue)
                    }
                }
            }

            if !detail.post.tags.isEmpty {
                Text(detail.post.tags.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
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
        HStack(spacing: 10) {
            Button {
                onVote(.up)
            } label: {
                Label("Upvote", systemImage: detail.currentUserVote == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)

            Button {
                onVote(.down)
            } label: {
                Label("Downvote", systemImage: detail.currentUserVote == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .buttonStyle(.bordered)

            Button(action: onDownloadPDF) {
                Label("Preview PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach(ForumReportReason.allCases) { reason in
                    Button(reason.displayText) {
                        onReportPost(reason)
                    }
                }
            } label: {
                Label("Report", systemImage: "flag")
            }
            .buttonStyle(.bordered)
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

            if detail.post.acceptsCommunityActions {
                HStack(alignment: .top, spacing: 8) {
                    TextField("Add a comment", text: $commentText, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .focused($isCommentFocused)

                    IChartKeyboardFocusButton(accessibilityLabel: "Open keyboard for forum comment") {
                        isCommentFocused = true
                    }

                    Button {
                        let body = ForumPublishDraft.normalizedDisplayText(commentText)
                        guard !body.isEmpty else {
                            return
                        }
                        commentText = ""
                        onComment(body)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(isWorking)
                    .accessibilityLabel("Post comment")
                }
            } else {
                Text("Discussion is closed for this chart.")
                    .font(.subheadline)
                    .foregroundStyle(theme.panelSecondary)
                    .padding(.vertical, 8)
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
                        theme: theme,
                        onReport: { reason in
                            onReportComment(comment, reason)
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
}

private struct IChartForumCommentRow: View {
    let comment: ForumComment
    let theme: IChartHomeTheme
    let onReport: (ForumReportReason) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble")
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                if let creatorDisplayName = comment.creatorDisplayName, !creatorDisplayName.isEmpty {
                    Text(creatorDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IChartHomeBrand.blue)
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
            } label: {
                Image(systemName: "flag")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Report comment")
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

            IChartHomeAppearanceModeSwitch(selectedMode: $appearanceMode)
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
                    .foregroundStyle(IChartHomeBrand.blue)
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
                    .foregroundStyle(isSelected ? IChartHomeBrand.blue : theme.panelSecondary.opacity(0.7))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(isSelected ? IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.18 : 0.72) : Color.clear)
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
    let onStartGuidedTour: () -> Void

    @ViewBuilder
    var body: some View {
        switch topic {
        case .tutorial:
            IChartTutorialGuide(theme: theme, onStartGuidedTour: onStartGuidedTour)
        case .faq, .userPolicy, .legal, .contactUs:
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
            VStack(alignment: .leading, spacing: 8) {
                Label(topic.detailTitle, systemImage: topic.systemImageName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)

                Text(topic.detailText)
                    .font(.subheadline)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if topic == .contactUs {
                    Link(destination: IChartSupportLinks.supportURL) {
                        Label("Open Support Site", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(IChartHomeBrand.blue)
                    .accessibilityHint("Opens useichart.com/support")

                    IChartPerformanceReportShareRow(theme: theme)
                }
            }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reportURL {
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
                .tint(IChartHomeBrand.blue)
            } else {
                Label("No performance report yet", systemImage: "doc.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.panelSecondary)
            }

            Text("Timing only. Stays on this iPad until shared.")
                .font(.caption2)
                .foregroundStyle(theme.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: refreshReportURL)
    }

    private func refreshReportURL() {
        reportURL = IChartPerformanceTrace.hasReport ? IChartPerformanceTrace.reportURL : nil
    }
}

private struct IChartHelpArticleSectionView: View {
    let section: IChartHelpArticleSection
    let theme: IChartHomeTheme
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: section.systemImageName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(IChartHomeBrand.blue)
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
                    ForEach(section.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(IChartHomeBrand.blue)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)

                            Text(bullet)
                                .font(.caption)
                                .foregroundStyle(theme.panelSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IChartTutorialGuide: View {
    let theme: IChartHomeTheme
    let onStartGuidedTour: () -> Void

    @State private var expandedSectionIDs = Set(IChartTutorialSection.all.prefix(1).map(\.id))

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("iChart Tutorial", systemImage: "graduationcap")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            Button(action: onStartGuidedTour) {
                Label("Start Hands-On Tour", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(IChartHomeBrand.blue)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(IChartTutorialSection.all) { section in
                    IChartTutorialSectionCard(
                        section: section,
                        theme: theme,
                        isExpanded: expandedSectionIDs.contains(section.id)
                    ) {
                        toggleSection(section.id)
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

private struct IChartTutorialSectionCard: View {
    let section: IChartTutorialSection
    let theme: IChartHomeTheme
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: section.systemImageName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(IChartHomeBrand.blue)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.panelTitle)

                        Text(section.summary)
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(section.steps.enumerated()), id: \.element.id) { index, step in
                        IChartTutorialStepRow(number: index + 1, step: step, theme: theme)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }
}

private struct IChartTutorialStepRow: View {
    let number: Int
    let step: IChartTutorialStep
    let theme: IChartHomeTheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 22, height: 22)
                .background(IChartHomeBrand.blueSoft.opacity(theme.isDark ? 0.18 : 0.82))
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
                    .foregroundStyle(IChartHomeBrand.blue)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)
            }

            content
                .foregroundStyle(theme.panelTitle)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
        .shadow(color: theme.panelShadow, radius: 16, y: 8)
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
                .foregroundStyle(IChartHomeBrand.blue)
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
                                    showsSignedInActions: false
                                )
                            }

                            if authStore.state.isVerifiedSignedIn && authStore.hasCompleteAccountIdentity {
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        isLaunchAnimationVisible = true
                                    }
                                } label: {
                                    Label("Continue", systemImage: "arrow.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(IChartHomeBrand.blue)
                                .disabled(isLaunchAnimationVisible)
                            }
                        }
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 44)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
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

private struct IChartAccountSettings: View {
    @ObservedObject var authStore: IChartAuthStore
    let theme: IChartHomeTheme
    var requiresNameForSignup = true
    var showsSignedInActions = true
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @FocusState private var focusedField: IChartAccountInputField?

    private var canSubmitCredentials: Bool {
        !trimmed(email).isEmpty
            && password.count >= 8
            && !authStore.isWorking
    }

    private var canCreateAccount: Bool {
        canSubmitCredentials
            && (!requiresNameForSignup || (!trimmed(firstName).isEmpty && !trimmed(lastName).isEmpty))
    }

    private var canSignIn: Bool {
        canSubmitCredentials
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
                    .foregroundStyle(IChartHomeBrand.blue)
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
                credentialsForm
                actionRow
                passwordResetRow
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
        .task(id: authStore.state.statusText) {
            focusDefaultInputIfNeeded()
        }
    }

    private var credentialsForm: some View {
        VStack(spacing: 10) {
            if requiresNameForSignup {
                IChartAccountTextField(
                    title: "First Name",
                    placeholder: "First name",
                    text: $firstName,
                    systemImageName: "person",
                    keyboardType: .default,
                    theme: theme,
                    focusedField: $focusedField,
                    field: .firstName,
                    textInputAutocapitalization: .words,
                    autocorrectionDisabled: false
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
                    textInputAutocapitalization: .words,
                    autocorrectionDisabled: false
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
                focusedField: $focusedField,
                field: .password
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
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
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(!canCreateAccount)

            Button {
                Task {
                    await authStore.signIn(email: email, password: password)
                }
            } label: {
                Label("Sign In", systemImage: "person.crop.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!canSignIn)
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
        HStack(spacing: 10) {
            Button {
                Task {
                    await authStore.resendVerificationEmail()
                }
            } label: {
                Label("Resend Email", systemImage: "envelope.badge")
            }
            .buttonStyle(.bordered)
            .disabled(authStore.isWorking)

            Button {
                authStore.returnToSignIn()
            } label: {
                Label("Sign In", systemImage: "person.crop.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
            .disabled(authStore.isWorking)
        }
    }

    private var passwordRecoveryRow: some View {
        VStack(spacing: 10) {
            IChartAccountSecureField(
                title: "New Password",
                placeholder: "8 characters minimum",
                text: $newPassword,
                systemImageName: "lock",
                theme: theme,
                focusedField: $focusedField,
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
                textInputAutocapitalization: .words,
                autocorrectionDisabled: false
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
                textInputAutocapitalization: .words,
                autocorrectionDisabled: false
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
            return "Open the verification link sent to \(email), then sign in."
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

    private func focusDefaultInputIfNeeded() {
        guard !authStore.isWorking else {
            return
        }

        switch authStore.state {
        case .signedOut:
            if requiresNameForSignup {
                focusedField = .firstName
            } else {
                focusedField = .email
            }
        case .passwordRecovery:
            focusedField = .newPassword
        case .unconfigured, .temporarilyOffline, .pendingEmailVerification, .signedIn:
            break
        }
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
    let theme: IChartHomeTheme
    let onSelectSubscriptionState: (IChartSubscriptionEntitlement) -> Void
    let onForumQASampleDataChanged: (Bool) -> Void

    #if DEBUG && targetEnvironment(simulator)
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
                    value: store.subscriptionState.cloudAccessText,
                    systemImageName: "icloud.and.arrow.up",
                    theme: theme
                )

                planDivider

                IChartSettingsRow(
                    title: "Forums",
                    value: store.subscriptionState.forumsAccessText,
                    systemImageName: "bubble.left.and.bubble.right",
                    theme: theme
                )

                if let graceEndsAt = store.subscriptionState.graceEndsAt {
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

            storeKitControls

            #if DEBUG && targetEnvironment(simulator)
            debugControls
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if DEBUG && targetEnvironment(simulator)
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
            Image(systemName: store.subscriptionState.systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(statusTint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.subscriptionState.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.panelTitle)

                Text(store.subscriptionState.detailText)
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(store.subscriptionState.badgeText)
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
            return IChartHomeBrand.blue
        }
    }

    private var storeKitControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(theme.panelBorder)

            Text("Pro Subscription")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.panelTitle)

            if subscriptionStore.productOptions.isEmpty {
                Text("Pro subscriptions are temporarily unavailable. Try again later or restore an existing purchase.")
                    .font(.caption)
                    .foregroundStyle(theme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(subscriptionStore.productOptions) { product in
                    Button {
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
                Task {
                    await subscriptionStore.manageSubscriptions()
                }
            } label: {
                Label("Manage Subscription", systemImage: "person.crop.circle")
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
        }
    }

    #if DEBUG && targetEnvironment(simulator)
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
            .onChange(of: debugPreview) { _, preview in
                let subscriptionState = preview.subscriptionState()
                subscriptionStore.applyLocalPreview(subscriptionState)
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
                        .foregroundStyle(IChartHomeBrand.blue)
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
                Image(systemName: syncStore.state.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(syncStore.state.displayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.panelTitle)

                    Text(syncStore.state.detailText)
                        .font(.caption)
                        .foregroundStyle(theme.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            Button {
                syncStore.syncNow()
            } label: {
                Label(syncStore.state.manualSyncTitle, systemImage: syncStore.state.manualSyncSystemImageName)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canRunManualSync: Bool {
        syncStore.state.allowsManualSync && !syncStore.isWorking
    }

    private var disabledReason: String? {
        guard !syncStore.isWorking else {
            return nil
        }

        return syncStore.state.manualSyncDisabledReason
    }

    private var statusTint: Color {
        switch syncStore.state {
        case .synced:
            return Color(red: 0.16, green: 0.48, blue: 0.24)
        case .offline:
            return Color(red: 0.76, green: 0.48, blue: 0.12)
        case .failed:
            return Color(red: 0.72, green: 0.18, blue: 0.12)
        case .requiresPro:
            return Color(red: 0.62, green: 0.40, blue: 0.10)
        case .syncing, .signedOut, .unconfigured:
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
                        Text("Show the Rhythm tool's last read and save local recognition notes for TestFlight QA.")
                            .font(.caption)
                            .foregroundStyle(theme.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(IChartHomeBrand.blue)
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
    let focusedField: FocusState<IChartAccountInputField?>.Binding
    let field: IChartAccountInputField
    var textInputAutocapitalization: TextInputAutocapitalization = .never
    var autocorrectionDisabled = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 104, alignment: .leading)

            TextField(placeholder, text: $text)
                .focused(focusedField, equals: field)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(textInputAutocapitalization)
                .autocorrectionDisabled(autocorrectionDisabled)
                .font(.subheadline)
                .foregroundStyle(theme.panelTitle)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
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

private struct IChartAccountSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImageName: String
    let theme: IChartHomeTheme
    let focusedField: FocusState<IChartAccountInputField?>.Binding
    let field: IChartAccountInputField

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartHomeBrand.blue)
                .frame(width: 30, height: 30)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.panelTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 104, alignment: .leading)

            SecureField(placeholder, text: $text)
                .focused(focusedField, equals: field)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .foregroundStyle(theme.panelTitle)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
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

private struct IChartNewChartControl: View {
    let chartUsageText: String?
    let canCreateChart: Bool
    let theme: IChartHomeTheme
    let onCreateChart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onCreateChart) {
                Label("New Chart", systemImage: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                    .frame(minWidth: 180, minHeight: 44)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(IChartHomeBrand.blue)
            .disabled(!canCreateChart)

            if let chartUsageText {
                Text(chartUsageText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.workspaceTitle.opacity(0.68))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
        .padding(.bottom, 2)
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
                                    .fill(IChartHomeBrand.paper.opacity(0.95))
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
            return IChartHomeBrand.ink
        }

        return theme.isDark ? IChartHomeBrand.paper : IChartHomeBrand.ink.opacity(0.72)
    }
}

private struct IChartProjectCreateControl: View {
    let projectCount: Int
    let theme: IChartHomeTheme
    let onCreateProject: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(projectCount == 1 ? "1 project" : "\(projectCount) projects")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.workspaceTitle)

                Text("Group every chart for the same song.")
                    .font(.caption)
                    .foregroundStyle(theme.workspaceSecondary)
            }

            Spacer(minLength: 16)

            Button(action: onCreateProject) {
                Label("New Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(IChartHomeBrand.blue)
        }
        .padding(16)
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                            .foregroundStyle(IChartHomeBrand.blue)
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
        .background(theme.emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                                    .fill(IChartHomeBrand.paper.opacity(0.95))
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
            return IChartHomeBrand.ink
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
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(IChartHomeBrand.ink)
                .lineLimit(1)

            Text(rowSubtitle)
                .font(.subheadline)
                .foregroundStyle(IChartHomeBrand.ink.opacity(0.58))
                .lineLimit(1)

            if !canOpenForEditing {
                Label(lockMessage, systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IChartHomeBrand.blue)
                    .lineLimit(1)
            }
        }
    }

    private var rowSubtitle: String {
        chart.librarySummaryText
    }

    private var cardBackground: Color {
        isSelected ? IChartHomeBrand.blueSoft.opacity(0.82) : IChartHomeBrand.paper.opacity(0.92)
    }

    private var cardBorderColor: Color {
        isSelected ? IChartHomeBrand.blue.opacity(0.35) : IChartHomeBrand.ink.opacity(0.07)
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
