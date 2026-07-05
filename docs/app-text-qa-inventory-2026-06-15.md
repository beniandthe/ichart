# App Text QA Inventory - 2026-06-15

Purpose: final copy sweep for iChart, focused on obtuse, placeholder, debug, or developer-facing language.

Scope scanned:
- `iChart/**/*.swift` shipping app target files
- UI constructors such as `Text`, `Label`, `Button`, `TextField`, `ContentUnavailableView`, alerts, sheets, menus, and accessibility labels
- Model-driven display strings such as `displayText`, `detailText`, sync/account/plan status text, forum validation errors, generated PDF metadata, and sample/QA forum text

Not included as review copy:
- SF Symbol names, font filenames, database table/column names, environment variable keys, JSON keys, parser aliases, and internal diagnostic `print` formats
- Chord-symbol parser spellings and music glyph catalog keys unless they can show as UI labels

Raw scan notes:
- 2,407 string literals with alphabetic text were found in `iChart/`.
- 1,247 UI/status-ish matches were found across SwiftUI views, models, stores, and services.
- This document groups repeated labels once per subsystem. Dynamic text is shown with placeholders.

## Review Flags

Use this section first. These are the highest-risk phrases for dev-style or obtuse user experience.

- [x] Help placeholders still sound like internal roadmap copy. Fixed in triage 1 and expanded into full FAQ, User Policy, Legal Policy, and tutorial reference pages.
  - Source: `iChart/Features/Library/LibraryView.swift`
  - New FAQ coverage: Forums and why iChart uses accounts.
  - New User Policy coverage: account identity, user charts, community sharing, conduct, and Basic/Pro downgrade behavior.
  - New Legal Policy coverage: terms, privacy, subscriptions, chart content, and support/change notes.
  - New tutorial coverage: Charts, Projects, PDFs, editor navigation, Page/Header, Chord, Simple, Rhythm Section, Coda, account, Pro, Forums, and Settings.

- [x] Account unconfigured state exposes implementation details. Fixed while removing unsupported setup language.
  - Source: `iChart/Features/Library/LibraryView.swift:4315`, `:4577`; `iChart/Models/ChartSyncState.swift:34`, `:111`
  - New: "Account services are unavailable right now. Local charts remain available."
  - New: "Account sign-in and cloud backup are unavailable right now."
  - New cloud backup fallback: "Cloud backup is unavailable right now."

- [x] Plan/StoreKit QA copy is developer-facing. Fixed in triage 2 with user-facing subscription and local preview copy.
  - Source: `iChart/Features/Library/LibraryView.swift:4848`, `:4941`, `:4954`, `:4957`; `iChart/Features/Editor/Components/UpgradeSheetView.swift:38`, `:102`; `iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift:45`, `:86`, `:378`
  - New: "Pro subscriptions are temporarily unavailable. Try again later or restore an existing purchase."
  - New: "Use local preview controls on this device. Purchases and account backup still use their normal flows."
  - New: "Sample Forum Charts"
  - New: "Pro Preview unlocks Pro locally on this device. Purchases and restore still use the normal subscription flow."
  - New: "Pro preview is active on this device."

- [x] Chord fixture tools expose regression terminology. Fixed in triage 2 by relabeling debug capture as ink samples.
  - Source: `iChart/Features/Editor/Components/ChordInkSheetViews.swift:98`, `:347`, `:354`; `iChart/Features/Editor/EditorView.swift:2710`, `:2729`
  - New: "Copied {chord} ink sample as {sample name}."
  - New: "Ink sample capture"
  - New: "Copy Ink Sample"
  - New: "Could not copy this ink sample. Keep the ink and try again."

- [x] Forum seed/QA text can leak if QA samples are enabled. Fixed in triage 2 by renaming QA sample strings to local forum samples.
  - Source: `iChart/App/Forum/IChartForumStore.swift:90`, `:456`, `:520`, `:603`, `:757`
  - New: "Sample forum charts loaded."
  - New: "{title} - Forum Sample.pdf"
  - New: "iChart Samples"
  - New: "Community review example with reports already attached."
  - New PDF preview text: "iChart Forum Sample - {creator}"

- [x] Chart list empty state says projects, not charts. Fixed in triage 2.
  - Source: `iChart/Features/Library/LibraryView.swift:1264`
  - New: "No Charts Yet"
  - New: "Create a new chart to start writing."

- [x] Several cramped editor controls use abbreviations that may be unclear. Fixed in triage 2.
  - Source: `iChart/Features/Editor/EditorView.swift:1072`, `:1092`, `:1149`, `:1157`
  - New: "New Row", "Delete To", "Remove Repeat", "Remove Ending"

- [x] Rhythm/chord validation copy sometimes exposes internal model terms. Fixed in triage 2.
  - Source: `iChart/Services/MeasureTimingValidator.swift:44`, `:61`, `:72`; `iChart/Features/Editor/EditorView.swift:2810`, `:2831`
  - New: "rhythm position", "chord position", "editable rhythm sketch", "off the measure grid"

- [x] Forum has a visible "Downvote" button despite prior concern about griefing tone. Fixed in triage 2.
  - Source: `iChart/Features/Library/LibraryView.swift:3549`; `iChart/Models/ForumCommunity.swift:348`
  - New: "Not For Me"
  - New vote summary: "{up} upvote(s)"

- [x] "SMuFL" may be too technical for a musician-facing font picker. Fixed in triage 2.
  - Source: `iChart/Features/Editor/Components/ChartAppearanceSheetView.swift:26`, `:83`
  - New: "Choose the notation symbol style used in the chart."
  - New section label: "Notation Font"

- [x] New-chart Lead Sheet description references current internal workflow. Fixed in triage 2.
  - Source: `iChart/Models/Chart.swift:234`
  - New: "Staff-based page for melody, chords, and standard notation."

- [x] Status surfaces repeated persistence wording even though local persistence is the default. Fixed in triage 2 follow-up by removing the user-facing status surface entirely.
  - Source: `iChart/Features/Library/ChartLibraryStore.swift`; `iChart/Models/ChartSyncState.swift`
  - Removed: Settings storage status row.
  - Removed: editor persistence status badge.
  - Removed: export preview storage confirmation label and date.
  - New: "Upgrade to Pro to back up and restore from cloud."
  - New: "Reconnect to back up."

- [x] Forum-downloaded PDFs persist after confirmed Basic/expired entitlement. Fixed in triage 2 follow-up.
  - Source: `iChart/Services/PDFLibraryStore.swift`; `iChart/App/IChartApp.swift`; `iChart/Features/Library/LibraryView.swift`
  - Active Pro and Pro grace keep forum downloads visible.
  - Confirmed Basic, expired Pro, and legacy local Pro remove forum downloads.
  - Unavailable plan checks hide forum downloads without deleting them.

- [x] Final read-through found old entitlement and future-feature wording. Fixed by using current feature names and current Pro benefits.
  - Source: `iChart/Models/AppEntitlements.swift`; `iChart/Features/Editor/Components/UpgradeSheetView.swift`; `iChart/Features/Library/LibraryView.swift`
  - New: "Instrument Transposition", "Repeats And Coda", "Rhythm Editing", "Projects for song variants"
  - Removed stale view terminology, future-feature promises, and unsupported project organization terms.

## App Shell

Source: `iChart/App/AppRootView.swift`, `iChart/Features/Library/LibraryView.swift`

- [ ] App navigation title: "iChart"
- [ ] Sidebar tabs: "Charts", "PDFs", "Forums", "Help", "Settings"
- [ ] Sidebar accessibility: "Open sidebar", "Collapse sidebar"
- [ ] Appearance accessibility: "Light mode", "Dark mode"
- [ ] Route error title: "Resolve Basic Limit"
- [ ] Route error message: "Remove local charts until the library has 3 Basic charts, or restore Pro to keep editing."
- [ ] Missing chart title: "Chart Not Found"
- [ ] Missing chart message: "This chart is no longer available in the library."

## First-Run Account

Source: `iChart/Features/Library/LibraryView.swift`, `iChart/App/Auth/IChartAuthStore.swift`

- [ ] Welcome title: "Welcome to iChart"
- [ ] Welcome message: "Create your account to keep profile, recovery, and subscription access tied to you from the start."
- [ ] Panel title: "Account"
- [ ] Primary continue action: "Continue"
- [ ] Account status labels: "Account unavailable", "Signed out", "Temporarily offline", "Verify email", "Set new password", "Verified", "Signed in"
- [ ] Signed-out helper: "Create an account or sign in for recovery, subscriptions, cloud backup, and Forums."
- [ ] Offline helper with email: "Using local charts for {email}. Reconnect to back up."
- [ ] Offline helper without email: "Using local charts. Reconnect to back up."
- [ ] Pending verification helper: "Open the verification link sent to {email}, then sign in."
- [ ] Recovery helper with email: "Enter a new password for {email}."
- [ ] Recovery helper without email: "Enter a new password to finish account recovery."
- [ ] Signed-in fallback: "Signed in to iChart."
- [ ] Form fields: "First Name", "Last Name", "Email", "Password", "New Password"
- [ ] Placeholders: "First name", "Last name", "name@example.com", "8 characters minimum"
- [ ] Actions: "Create Account", "Sign In", "Reset Password", "Resend Email", "Save Password", "Cancel", "Reconnect", "Refresh", "Sign Out"
- [ ] Store messages: "Account created. Check your email to finish verification.", "Signed in.", "Signed out.", "Verification email sent.", "Password reset email sent.", "Account session refreshed.", "Password updated. You're signed in.", "Profile updated."
- [ ] Error: "This sign-in link is not an iChart account callback."
- [ ] Error: "Sign in before saving profile info."
- [ ] Offline status: "Account is offline. Local charts remain available."
- [ ] Recovery status: "Enter a new password to finish reset."
- [ ] Account unavailable helper: "Account services are unavailable right now. Local charts remain available."
- [ ] Account unavailable detail: "Account sign-in and cloud backup are unavailable right now."

## Guided Tour And Help

Source: `iChart/Features/Library/LibraryView.swift`, `iChart/Features/Editor/EditorView.swift`

- [ ] Help topics: "Tutorial", "FAQ", "User Policy", "Legal Policy", "Contact Us"
- [ ] Help summaries: "App walkthrough", "Common questions", "Use and conduct", "Terms and privacy", "Support and feedback"
- [ ] Help detail titles: "iChart Tutorial", "Common Questions", "User Policy", "Legal Policy", "Contact Us"
- [ ] Help intro: "Read through the main iChart systems here, or start the hands-on tour when you want guided practice in the live app."
- [ ] Help action: "Start Hands-On Tour"
- [ ] Help section controls: expandable/collapsible sections with "Expand section" and "Collapse section" accessibility hints.
- [ ] FAQ intro: "Answers about Forums and why iChart uses accounts."
- [ ] FAQ page sections: "What are Forums?", "Why does iChart need an account?"
- [ ] User Policy page sections: "Account Identity", "Your Charts", "Community Sharing", "Conduct", "Basic, Pro, And Downgrades"
- [ ] Legal Policy page sections: "Terms Of Use", "Privacy", "Subscriptions", "Chart Content", "Support And Changes"
- [ ] First-run tour titles: "Welcome To iChart", "Start With Charts", "Create Your First Chart", "Choose Simple Chord Sheet"
- [ ] First-run tour messages:
  - "Write the chart. Share with the band. Take a quick tour, or jump straight into the app."
  - "Tap Charts in the sidebar. This is where your charts and new chart creation live."
  - "Tap New Chart to choose what kind of chart you want to make."
  - "Choose Simple Chord Sheet for a chord-first page. Rhythm Section Sheet gives you more room for slashes, hits, and groove cues."
- [ ] First-run tour targets/actions: "Start Tour", "Tap Charts", "Tap New Chart", "Tap Simple Chord Sheet", "Skip Tour"
- [ ] Help sections: "Getting Started", "Charts, Projects, And PDFs", "Editor Navigation", "Page", "Measures", "Repeats", "Coda", "Text", "Time", "Rhythm", "Chord", "Free-Hand", "Account, Pro, And Forums", "Settings"
- [ ] Editor tour titles: "Create The Page", "Write A Chord", "Confirm The Chord", "Leave Chord Mode", "Page", "Measures", "Measures Row", "Repeats Row", "Coda", "Free-Hand", "Select And Finish"
- [ ] Editor tour targets: "Tap Create Blank Page", "Write a chord, then tap outside the lane", "Tap a chord choice", "Tap Done", "Tap Page", "Tap Measures", "Tap Repeats", "Tap Coda", "Tap Free-Hand"
- [ ] Editor tour actions: "Finish Tour", "Skip Tour"

## Charts Home

Source: `iChart/Features/Library/LibraryView.swift`, `iChart/Features/Library/ChartLibraryStore.swift`

- [ ] Workspace switcher: "Charts", "Projects"
- [ ] Chart preview modes: "Collapsed", "Quick", "Large"
- [ ] New chart action: "New Chart"
- [ ] Usage text: "{used} of {limit} Basic charts used"
- [ ] Chart count: "1 chart", "{count} charts"
- [ ] Empty state title: "No Charts Yet"
- [ ] Empty state message: "Create a new chart to start writing."
- [ ] Chart row actions: "Rename", "Duplicate", "Share To Forum", "Delete", "Delete Local"
- [ ] Chart action accessibility: "Chart actions", "Delete local chart"
- [ ] Rename sheet: "Rename Chart", "Chart title", "Open keyboard for chart title", "Cancel", "Save"
- [ ] Delete alert: "Delete Chart?", "Delete", "Cancel"
- [ ] Delete message: "This removes {chart title} from the local library."
- [ ] Basic lock singular: "Delete 1 local chart to edit in Basic."
- [ ] Basic lock plural: "Delete {count} local charts to edit in Basic."
- [ ] Consolidation title: "Consolidate Charts"
- [ ] Consolidation message: "Delete {count} local chart(s) from the list below to continue in Basic. Editing unlocks when 3 charts remain. Cloud backups stay available through the Pro grace period."
- [ ] Persistence status: not user-facing.
- [ ] Default chart titles: "Untitled Chart", "Untitled Chart Copy", "{title} Copy", "{title} Copy {number}"
- [x] REVIEW: empty state says "No Projects Yet" in Charts list. Fixed in triage 2.

## Projects

Source: `iChart/Features/Library/LibraryView.swift`, `iChart/Models/ChartProject.swift`

- [ ] Locked title: "Projects require Pro"
- [ ] Locked message: "Upgrade to Pro to group every chart for the same song, duplicate section variants, and keep alternate parts together."
- [ ] Empty title: "No Projects Yet"
- [ ] Empty message: "Create a project to keep every chart for the same song together."
- [ ] Project count: "1 project", "{count} projects"
- [ ] Project helper: "Group every chart for the same song."
- [ ] Actions: "New Project", "Rename Project", "Delete Project", "Add Existing", "New Chart"
- [ ] Project menu accessibility: "Project actions"
- [ ] Project chart menu accessibility: "Project chart actions"
- [ ] Empty project message: "Add an existing chart or create the first chart for this song."
- [ ] Create sheet: "New Project", "Song or project title", "Open keyboard for project title", "Cancel", "Create"
- [ ] Rename sheet: "Rename Project", "Song or project title", "Open keyboard for project title", "Cancel", "Save"
- [ ] Add sheet: "Add To {project title}", "No Charts To Add", "Every local chart is already in this project.", "Done"
- [ ] Duplicate sheet: "Duplicate Variant", "Variant Title", "Horn section chart", "Instrument Transposition", "Open keyboard for variant title", "Cancel", "Create"
- [ ] Project row actions: "Duplicate Variant", "Remove From Project"

## New Chart Setup

Source: `iChart/Features/Editor/Components/ChartSetupSheetView.swift`, `iChart/Models/Chart.swift`, `iChart/Models/ChartLayoutProfile.swift`

- [ ] Sheet titles: "New Chart", "Chart"
- [ ] Actions: "Cancel", "Create Blank Page", "Apply"
- [ ] Sections/labels: "Layout Style", "Time Signature", "Denominator", "Starting Measures", "Measures"
- [ ] Layout options: "Simple Chord Sheet", "Rhythm Section Sheet", "Lead Sheet"
- [ ] Layout descriptions:
  - "Dense chord-first grid for fast harmonic roadmaps."
  - "Chord chart with extra room for hits, slashes, and groove cues."
  - "Staff-based page for melody, chords, and standard notation."
- [ ] Header modes: "Typed", "Handwritten"
- [ ] Summary: "{layout style} · setup pending", "blank page", "{count} measures"
- [x] REVIEW: Lead Sheet description says "current iChart workflow." Fixed in triage 2.

## Editor Main Toolbar

Source: `iChart/Features/Editor/EditorView.swift`, `iChart/Features/Editor/EditorCanvasMode.swift`, `iChart/Features/Editor/EditorInkToolMode.swift`, `iChart/Models/ChartAnnotations.swift`

- [ ] Exit accessibility: "Exit Chart"
- [ ] Page menu: "Setup", "Export", "Typed", "Handwritten", "Clear Handwritten Header", "Header ({mode})", "Instrument ({instrument})", "Transpose ({interval})", "Up Half Step", "Down Half Step", "Reset to Written", "Style", "Fonts", "Pen Responsiveness", "Engraving"
- [ ] Main tool tabs: "Page", "Select", "Measures", "Repeats", "Coda", "Text", "Time", "Rhythm", "Chord", "Free-Hand"
- [ ] Ink tool labels: "Write", "Erase"
- [ ] Chord row modes: "Read", "Ink Only", "Ink Only: handwritten chords stay as ink; transposition and chord systems will not apply."
- [ ] Measures row: "Add", "Stack", "First", "Double", "Join", "New Row", "Delete", "Range", "Delete To", "Clear"
- [ ] Repeats row: "One Bar", "Start", "End Rep", "1st", "2nd", "End 1st", "End 2nd", "Remove Repeat", "Remove Ending", "Clear"
- [ ] Coda tool menu labels: "Coda", "To Coda", "Segno", "D.S.", "D.S. al Coda", "D.C.", "D.C. al Fine", "Fine", "N.C."
- [ ] Coda marker overlay: "x"
- [ ] Rendered chart roadmap symbols: Coda symbol, To Coda, Segno symbol, "D.S.", D.S. al Coda, "D.C.", "D.C. al Fine", "Fine", "N.C."
- [ ] Text actions: "Add Text Below Selected Measure", "Add Text Above Selected Measure", "Remove Text at Selected Measure"
- [ ] Done: "Done"
- [x] REVIEW: abbreviated controls listed in Review Flags. Fixed in triage 2.

## Editor Sheets And Alerts

Source: `iChart/Features/Editor/EditorView.swift`, `iChart/Features/Editor/Components/ChartHeaderSheetView.swift`, `ChartAppearanceSheetView.swift`, `ChartTypographySheetView.swift`

- [ ] Change time signature dialog: "Change Time Signature", "Apply the new time signature after the selected measure.", "Cancel"
- [ ] Export alert: "Export PDF", "OK", "Couldn’t generate the PDF right now. {error}"
- [ ] Rhythm alert: "Rhythm Edit", "OK"
- [ ] Chord alert: "Chord Recognition", "OK"
- [ ] Header sheet: "Header", "Header Mode", "Mode", "Chart", "Title", "Composer / Credit", "Style Note", "Untitled Chart", "Cancel", "Apply", "Open keyboard for {title}"
- [ ] Appearance panels: "Document Style", "Notation Fonts", "Engraving"
- [ ] Appearance subtitles: "Set the overall visual personality of the chart.", "Choose the notation symbol style used in the chart.", "Control spacing and stroke weight for the page."
- [ ] Appearance sections/actions: "Style", "Notation Font", "Preset", "Done"
- [ ] Typography sections: "Matched Set", "Chord Font", "Header Font", "Text / Cue Font", "Notation Symbols", "Use Matched Set", "Selected", "Fonts", "Done"
- [ ] Typography previews: "Almost Like Being In Love", "(Medium Swing)  To Coda", "Bb△7  C°7  Fø7"
- [ ] Pen sheet: "Pen Responsiveness", "Direct", "Smooth", "Balanced", "Pen", "Decrease pen responsiveness", "Increase pen responsiveness", "Done"
- [ ] Text sheet: "Text", "Open keyboard for text entry", "Cancel", "Add"
- [ ] Measure stack sheet: "Measures", "Measure Count", "Measure Stack", "Cancel", "Add"
- [ ] Apply meter sheet: "Add measures in this time signature?", "The new {meter} starts on the next measure.", "Additional measures", "Apply Measure Count", "Or choose a span", "To next time signature", "To end of piece", "Apply {meter}", "Cancel"
- [x] REVIEW: "SMuFL" and "Add measures of time?" may need more user-facing language. Fixed in triage 2.

## Chord Recognition And Correction

Source: `iChart/Features/Editor/Components/ChordInkSheetViews.swift`, `iChart/Features/Editor/EditorView.swift`, `iChart/Services/ChordInkRenderResolutionPolicy.swift`

- [ ] Sheet titles: "Choose Chord", "Enter Chord", "Correct Chord"
- [ ] Prompts: "Type the chord you meant.", "Pick the chord you meant, or type it.", "Close match. Pick the chord you meant.", "Choose one or type the chord."
- [ ] Measure label: "Measure {number}"
- [ ] Candidate placeholder: "Type chord"
- [ ] Empty suggestions: "No confident suggestions"
- [ ] Sections/actions: "Top 3", "Manual entry", "Manual chord entry", "Learn Chord", "Rewrite Ink", "Clear Ink"
- [ ] Accessibility: "Open keyboard for manual chord entry", "Accept suggestion {number}, {candidate}"
- [ ] Correction title/body: "Update the chord", "Make this rendered chord match the chart.", "Current", "New"
- [ ] Correction placeholder: "C, Bb, Db7(b9), G/B"
- [ ] Correction actions: "Quick choices", "Chord", "Update Chord", "Update to {chord}", "Cancel"
- [ ] Memory message: "This ink previously rendered as {acceptedText} and was deleted. Choose the intended chord, or type it in."
- [ ] Errors: "That chord candidate is not supported yet. Try another candidate or edit the text.", "That measure is no longer available. Keep the ink and try again.", "That chord is no longer available. Try writing it again."
- [ ] Ink sample copy: "Ink sample capture", "Copy Ink Sample", "Copied {chord} ink sample as {sample name}.", "Unsupported chord. Use a supported target like C, Bb, F#, C-, C-△7, C△7, C7alt, Db7(b9), or G/B.", "Could not copy this ink sample. Keep the ink and try again."
- [x] REVIEW: fixture/debug copy should not appear in production. Fixed in triage 2 by relabeling the disabled debug capture surface.

## Rhythm Recognition And Editing

Source: `iChart/Features/Editor/EditorView.swift`, `iChart/Features/Editor/Components/RhythmicNotationRecognitionTypes.swift`, `iChart/Models/RhythmicNotationAcceptance.swift`, `iChart/Services/MeasureTimingValidator.swift`

- [ ] Rhythm values: "Slash", "Eighth Note", "Eighth Rest", "Quarter Note", "Quarter Rest", "Dotted Quarter", "Dotted Quarter Note", "Half Note", "Half Rest", "Dotted Half", "Dotted Half Note", "Whole Note", "Whole Rest", "Tie"
- [ ] Short values: "W", "H", "H.", "Q", "/", "Q.", "8", "Tie", "WR", "HR", "QR", "8R"
- [ ] Edit note sheet: "Edit Note", "Rhythm"
- [ ] Error: "Select a rhythm note first, then choose the replacement value."
- [ ] Error: "That rhythm is already selected."
- [ ] Error: "That measure is no longer available."
- [ ] Error: "That note is not part of an editable rhythm sketch yet."
- [ ] Error: "That rhythm note is no longer available."
- [ ] Error: "Choose a single rhythm or rest value."
- [ ] Error: "That replacement would make the measure {status}. Choose a value with the same duration for now, or adjust the surrounding rhythms first."
- [ ] Status fragments: "empty", "fit", "short by {beats} beats", "over by {beats} beats", "off the measure grid"
- [ ] Recognition feedback: "Measure {number} contains a rhythm symbol that couldn’t be matched yet. The measure is still selected so you can adjust or rewrite it."
- [ ] Recognition feedback: "This rhythm only adds up to {actual} beats, but the measure needs {expected}. The measure is still selected so you can adjust or rewrite it."
- [ ] Recognition feedback: "This rhythm adds up to {actual} beats, which is more than the {expected} beats allowed in this measure. The measure is still selected so you can adjust or rewrite it."
- [ ] Timing validation: "Chord {chord} is tied to a rhythm position that changed.", "More than one chord is tied to rhythm position {position}.", "This rhythm has {count} chord position(s), so extra chords will not snap cleanly.", "The rhythm sketch does not add up to {meter}, so it stays inactive until it fits the full measure."
- [x] REVIEW: internal rhythm terms listed in Review Flags. Fixed in triage 2.

## PDF Library And Export

Source: `iChart/Features/Library/LibraryView.swift`, `iChart/Services/PDFLibraryStore.swift`, `iChart/Features/Editor/Components/PDFExportPreviewView.swift`, `iChart/Services/ChartExporting.swift`

- [ ] Tab/panel title: "PDF Library"
- [ ] Library intro: "Exports and forum downloads appear here so you can preview, share, or remove them later."
- [ ] Sources: "Exports", "Forum Downloads"
- [ ] Source item titles: "Chart Export", "Forum Download"
- [ ] Empty titles: "No Exports Yet", "No Forum Downloads Yet"
- [ ] Empty messages: "Export a chart as a PDF and it will land here.", "Download a forum chart PDF and it will land here."
- [ ] Missing PDF: "PDF Not Found", "This PDF is no longer available on this device.", "Done"
- [ ] Row accessibility: "Open {PDF title}", "Delete {PDF title}"
- [ ] Export preview actions: "Done", "Share"
- [ ] Page count: "1 page", "{count} pages"
- [ ] Default file/title: "iChart PDF", "iChart"
- [ ] Forum PDF metadata: "Shared from iChart Forums - Creator: {creator} - Post: {postID} - Exported: {date}"

## Community Forums

Source: `iChart/Features/Library/LibraryView.swift`, `iChart/Models/ForumCommunity.swift`, `iChart/App/Forum/IChartForumStore.swift`

- [ ] Locked title: "Forums require Pro"
- [ ] Locked message: "Upgrade to Pro to join iChart Forums."
- [ ] State title: "Community Library Unavailable"
- [ ] State message: "We can’t reach community charts right now. Your local charts are safe, and this page will work again when service returns."
- [ ] State title: "Sign In Required"
- [ ] State message: "Forums use verified account identity so charts and comments are never anonymous."
- [ ] State title: "Forums Require Pro"
- [ ] State message: "Upgrade to Pro to browse, publish, vote, comment, and download forum chart PDFs."
- [ ] Loading: "Loading community charts..."
- [ ] Retry action: "Retry"
- [ ] Search prompt/action: "Search songs, artists, arrangers, or tags", "Search"
- [ ] Hero title: "Community Bandstand"
- [ ] Hero copy: "Find working chord and rhythm PDFs, shout out clean charts, and help other musicians get through rehearsal faster."
- [ ] Hero badge: "iChart Pro"
- [ ] Hero stats: "Contributions", "Downloads", "Upvotes", "Badges", "Top Rated"
- [ ] Top board title: "Top Charts"
- [ ] Top board subtitles: "The charts players are backing right now.", "Ranked charts matching this search."
- [ ] Top board tabs: "Today", "This Week", "This Month", "All Time"
- [ ] Ranking labels: "Top 10", "Lead Chart", "#{rank}", "Show {count} more", "Collapse"
- [ ] Empty ranking: "No charts yet", "Waiting on the first approved chart."
- [ ] Search empty: "No Chart On This Tune Yet", "A matching local chart can become the first reviewed PDF for this search."
- [ ] Search results: "Search Results", "Matched forum charts grouped by song."
- [ ] Publish prompt title: "Local Chart Needed", "Submit From Your Library"
- [ ] Publish prompt copy: "Forum posts start from charts created inside iChart.", "Pick a local chart and send a reviewed PDF snapshot to the community library."
- [ ] Publish row empty: "No local charts"
- [ ] Publish action: "Submit To Forum"
- [ ] Song card count: "{count} chart(s)"
- [ ] Song card byline: "By {creator}"
- [ ] Open accessibility: "Open {chart title}", "Open lead chart {chart title}"
- [ ] Quality labels: "Pending Review", "New", "Top Rated", "Community Rated", "Needs Review", "Hidden", "Removed"
- [ ] Report reasons: "Wrong Chords", "Wrong Form", "Bad Formatting", "Spam", "Abuse", "Copyright Concern", "Other"
- [ ] Badges: "Verified Contributor", "Trusted Arranger", "Community Expert"
- [ ] Validation errors: "Choose a local iChart chart.", "Add the song title.", "Add the artist.", "Add arranger credit.", "Finish account first and last name before posting."
- [ ] Store messages: "Forum chart submitted for review.", "Report sent.", "Choose a local iChart chart before publishing.", "This forum chart is no longer available."
- [x] REVIEW: downvote language and QA seed copy listed in Review Flags. Fixed in triage 2.

## Submit To Forum

Source: `iChart/Features/Library/LibraryView.swift`

- [ ] Sheet title: "Submit To Forum"
- [ ] Section title: "Metadata"
- [ ] Fields: "Song Title", "Artist", "Arranger Credit", "Posted By", "Tags (Optional)", "Notes (Optional)"
- [ ] Tags prompt: "live, acoustic, rhythm section"
- [ ] Missing section: "Missing"
- [ ] Actions: "Cancel", "Submit"
- [ ] Posted-by fallback: "Account name required"
- [ ] Keyboard accessibility: "Open keyboard for {field title}"

## Forum Detail And Discussion

Source: `iChart/Features/Library/LibraryView.swift`

- [ ] Creator byline: "Created by {creator}", "Created by Unknown"
- [ ] Actions: "Upvote", "Not For Me", "Preview PDF", "Report"
- [ ] Discussion title: "Discussion"
- [ ] Comment field: "Add a comment"
- [ ] Comment action accessibility: "Post comment"
- [ ] Comment keyboard accessibility: "Open keyboard for forum comment"
- [ ] Closed discussion: "Discussion is closed for this chart."
- [ ] Empty comments: "No comments yet."
- [ ] Report comment accessibility: "Report comment"
- [ ] Moderation notice: "This chart is pending an authenticity review before it appears in Forums."
- [ ] Moderation notice: "This chart has been flagged for community review."
- [ ] Moderation notice: "This chart is under community review."
- [ ] Moderation notice: "This chart is hidden while it is reviewed."
- [ ] Moderation notice: "This chart is no longer available in Forums."

## Settings, Plan, And Subscription

Source: `iChart/Features/Library/LibraryView.swift`, `iChart/Models/IChartSubscriptionEntitlement.swift`, `iChart/Models/AppEntitlements.swift`, `iChart/Features/Editor/Components/UpgradeSheetView.swift`, `iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift`

- [ ] Settings panels: "Settings", "Library", "Plan", "Cloud Backup", "Diagnostics"
- [ ] Account identity editing is not exposed in Settings; name and email are set at account creation and changed only through support.
- [ ] Phone setup/verification is not active V1 UI; any existing phone data is legacy/support-controlled.
- [ ] Plan rows: "Local Charts", "Cloud Backup", "Forums", "Grace Ends"
- [ ] Plan values: "Unlimited", "{used} of {limit} used"
- [ ] Plan preview segments: "Basic", "Pro", "Grace", "Expired", "Offline"
- [ ] Plan display titles: "Basic", "Pro Active", "Pro Grace", "Pro Expired", "Plan Check Unavailable", "Legacy Local Pro"
- [ ] Plan badges: "Basic", "Pro", "Grace", "Expired", "Offline", "Legacy"
- [ ] Plan details:
  - "Local authoring, export, account recovery, and up to 3 local charts."
  - "Unlimited local charts, cloud backup and restore, and Forums access."
  - "Cloud backup is paused. Remote backups remain through {date}."
  - "Cloud backup is paused during the grace period. Remote backups remain temporarily recoverable."
  - "Pro is inactive. Cloud backup and Forums are locked until Pro is restored."
  - "Subscription status could not be verified, so the app is using Basic limits locally."
  - "Legacy local Pro keeps unlimited local chart creation, but cloud services still require active Pro."
- [ ] Cloud/forums access values: "Available", "Paused during grace", "Requires Pro", "Restore Pro", "Unavailable", "Requires active Pro"
- [ ] Entitled feature names: "Unlimited Local Charts", "PDF Export", "Instrument Transposition", "Font Presets", "Repeats And Coda", "Rhythm Editing", "Cloud Backup And Restore", "Cloud Backup", "Forums", "Community Chart Library", "Project Organization", "Handwriting Recognition", "Projects"
- [ ] Upgrade sheet title/action: "Unlock Pro", "Upgrade", "Not Now"
- [ ] Upgrade benefits: "Unlimited local charts", "Projects for song variants", "Cloud backup and restore", "Forums access"
- [ ] Purchase actions: "Restore Purchases", "Manage Subscription", "Use Pro Preview"
- [ ] Subscription status: "Checking subscription...", "Verifying subscription with iChart...", "Opening purchase...", "Restoring purchases...", "Opening subscription management...", "Pro preview is active on this device."
- [ ] Subscription error/status: "Purchase could not be verified.", "Purchase is pending approval.", "Purchase status is unavailable.", "Purchase failed. Try again from Settings.", "Pro subscriptions could not be loaded.", "Restore failed. Try again when you are online.", "Subscription management is unavailable from this window.", "Could not open subscription management.", "Subscription management is unavailable on this platform.", "Subscription could not be verified with iChart. Try again when you are online.", "Subscription transaction could not be verified."
- [ ] Value badge: "Save {percent}%"
- [x] REVIEW: StoreKit/debug copy listed in Review Flags. Fixed in triage 2.

## Cloud Sync

Source: `iChart/Models/ChartSyncState.swift`, `iChart/App/Sync/ChartCloudSyncStore.swift`, `iChart/Features/Library/LibraryView.swift`

- [ ] Status labels: "Cloud backup unavailable", "Sign in to back up", "Cloud backup requires Pro", "Offline", "Backing up", "Cloud backup active", "Cloud backup needs attention"
- [ ] Detail text: "Charts stay local until you sign in."
- [ ] Detail text: "Cloud backup is unavailable right now."
- [ ] Detail text: "Upgrade to Pro to back up and restore from cloud."
- [ ] Detail text: "Reconnect to back up."
- [ ] Detail text: "Checking cloud backup and uploading local changes."
- [ ] Detail text: "Cloud backup is up to date."
- [ ] Manual backup actions: "Unavailable", "Sign In First", "Requires Pro", "Try Again", "Backing Up", "Back Up Now"
- [ ] Disabled reasons: "Sign in to enable cloud backup.", "Cloud backup and restore require Pro."
- [ ] Backup/check timestamps are not user-facing.
- [ ] Failure text: "Sign in again to resume cloud backup.", "Cloud permissions blocked backup. Sign in again, then retry.", "We could not finish cloud backup. Retry when you are online."
- [x] REVIEW: Cloud-service fallback strings listed in Review Flags. Fixed in triage 3 by replacing setup terms with service-availability language.

## Appearance, Fonts, And Engraving Options

Source: `iChart/Models/ChartAppearance.swift`

- [ ] Notation font presets: "Bravura", "Petaluma", "Leland", "MuseJazz", "Finale Maestro", "Finale Jazz", "Finale Broadway", "Finale Engraver", "Finale Ash", "Finale Legacy"
- [ ] Notation font descriptions:
  - "Clean engraved notation, close to Dorico defaults."
  - "Handwritten jazz engraving with an organic real-book feel."
  - "MuseScore-style engraving with broad, readable glyphs."
  - "Open handwritten MuseScore jazz notation family."
  - "Classic Finale notation for polished studio charts."
  - "Finale's handwritten jazz notation family."
  - "Bold theater-copyist notation character."
  - "Formal engraved Finale notation."
  - "Looser handwritten Finale notation."
  - "Older Finale compatibility look."
- [ ] Matched font families: "Bravura", "Petaluma", "Leland", "MuseJazz", "Finale Maestro", "Finale Jazz", "Finale Broadway", "Finale Ash"
- [ ] Matched family descriptions:
  - "Clean engraved text with broad music-symbol support."
  - "Handwritten real-book family with matching text and symbols."
  - "Broad MuseScore-style notation with readable text support."
  - "Open handwritten jazz family from MuseScore."
  - "Classic Finale studio-copyist look."
  - "Finale handwritten jazz family with lowercase-safe chords."
  - "Bold theater-copyist family."
  - "Loose handwritten Finale family."
- [ ] Engraving presets: "Compact", "Balanced", "Wide", "Bold"
- [ ] Engraving descriptions: "Tighter spacing for dense lead sheets.", "Default real-book spacing and staff weight.", "More horizontal room for handwriting and rhythms.", "Heavier staff, barlines, stems, and glyphs."
- [ ] Document styles: "Classic Real Book", "Gig Sheet", "Rehearsal Draft"
- [ ] Document style descriptions: "Centered title, clean paper, and polished chart hierarchy.", "Looser handwritten title treatment for jazz chart sketches.", "Plain working-copy style for fast revisions."

## Generated, Seed, And PDF Text

Source: `iChart/Shared/SampleData/ChartSamples.swift`, `iChart/App/Forum/IChartForumStore.swift`, `iChart/Services/LeadSheetPageLayout.swift`, `iChart/Features/Editor/Components/LeadSheetNotationRenderer.swift`

- [ ] Sample chart titles: "Late Night Pocket", "Turnaround Study"
- [ ] Sample composer/style: "Irving Berlin", "MED. SWING"
- [ ] Sample section/cue text: "Intro", "hits tight with drums", "hits tight", "D.S. al Coda", "A"
- [ ] Default rendered header: "Untitled Chart", "UNTITLED CHART"
- [ ] Default style notes: "MED. SWING", "STRAIGHT 8THS", "TRIPLET FEEL"
- [ ] Forum sample songs/artists: "Blue Bossa" / "Kenny Dorham", "Cantaloupe Island" / "Herbie Hancock", "Just Friends" / "John Klenner", "There Will Never Be Another You" / "Harry Warren", "Actual Proof" / "Herbie Hancock"
- [ ] Forum sample chart titles: "Blue Bossa - Rhythm Section Roadmap", "Blue Bossa - Horn Friendly Changes", "Cantaloupe Island - Pocket Hits", "Just Friends - Jam Session Form", "Another You - Gig Roadmap", "Actual Proof - Alt Form Check"
- [ ] Forum sample notes:
  - "Clean rehearsal map with hits, repeats, and a short tag."
  - "Compact chart for horn players reading with rhythm section."
  - "Big form markers and simple hit language for a fast rehearsal."
  - "Short and clean for a singer rehearsal packet."
  - "Community review example with reports already attached."
- [ ] Forum sample comments:
  - "This one reads clean on a loud stage. The ending is easy to catch."
  - "Good roadmap for rhythm section. I would keep the tag exactly like this."
  - "The hit layout is quick to scan. Nice for rehearsal."
  - "Form might need review around the bridge."
- [x] REVIEW: sample/QA strings listed in Review Flags. Fixed in triage 2.

## Quick Triage Recommendation

Highest-value cleanup pass before release:

1. Replace Help placeholder/roadmap text with finished user copy.
2. Hide or reword service setup, subscription preview, simulator, and QA language behind surfaces that cannot appear to regular users. Done in triage 2 for Pro preview and forum samples; cloud-backup fallback copy fixed in triage 3.
3. Remove or relabel chord regression fixture UI. Done in triage 2.
4. Fix the Charts empty state title. Done in triage 2.
5. Decide whether forum downvotes are release-facing, hidden, or reframed. Done in triage 2 by reframing the button and hiding downvote counts from summaries.
6. Reword the most technical editor terms listed in the editor and rhythm sections. Done in triage 2.
7. Remove redundant local-save status wording and enforce forum-download cleanup after confirmed downgrade/expiration. Done in triage 2 follow-up.
