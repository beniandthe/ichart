# Smart Chart Sprint 70 App Functionality And UX/UI

Status: opened locally
Date: 2026-06-02
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

Sprint 70 starts after the Sprint 69 V1 readiness audit closed with no confirmed V1 blocker.

The goal is to turn the proven Simple Chord Sheet and Rhythm Section Sheet authoring core into a clearer app experience. The broad lane remains project/library UX, export/share confidence, save/reopen confidence, and tool/menu affordance polish. The first functionality slice was chart-wide chord transposition, the second slice added typed-or-handwritten header entry, the third and fourth slices hardened live ink responsiveness, the fifth slice adds a user-facing pen responsiveness setting, the sixth slice adds first-measure and measure-menu double barline behavior, the seventh slice adds rendered chord correction/movement inside the Chord tool, the eighth slice locks out the editor route's swipe-to-exit gesture, the ninth slice promotes Measure-menu system breaks to Rhythm Section charts, the tenth slice tightens Rhythm Section system visual alignment, the eleventh slice standardizes default Rhythm Section measure widths across rendered systems, the twelfth slice adds Measure-menu deletion for the selected measure stack, and the thirteenth slice adds Measure-menu bulk deletion from or after the selected measure.

## Slice 1: Chart-Wide Chord Transposition

User direction:

- The current V1 styles are not key dependent.
- Add chord transposition by half steps.
- All rendered chords should transpose together.
- The behavior must work in both Simple Chord Sheet and Rhythm Section Sheet.

Implementation contract:

- Store a chart-level `chordTranspositionSemitones` setting normalized to `0...11`.
- Keep transposition non-destructive: stored `ChordEvent.symbol`, raw input, source ink data, candidate signatures, beat placement, rhythm-slot mapping, and correction memory remain unchanged.
- Resolve displayed chord symbols through `Chart.displayedChordSymbol(for:)`.
- Apply the displayed symbol in shared page layout so live canvas rendering and PDF/export use the same transposed text.
- Transpose root and slash-bass pitches together.
- Preserve accidental family when the source pitch is explicitly flat or sharp; natural roots use sharp spelling for chromatic chart-display offsets.
- Add Page menu controls for reset, up/down half step, and direct `0...11` half-step offsets.

## Slice 2: Typed Or Handwritten Headers

User direction:

- Headers should be user-selectable as either handwritten on the chart page or typed like the current flow.
- The behavior should fit both active V1 styles, Simple Chord Sheet and Rhythm Section Sheet.

Implementation contract:

- Store `Chart.headerInputMode` as `.typed` or `.handwritten`, with legacy charts decoding to `.typed`.
- Keep chart metadata (`title`, `composerCredit`, and `styleNote`) intact even when the page header is handwritten, so library/navigation naming stays clean.
- Store handwritten header ink separately from page freehand, chord ink, rhythm ink, and freehand-symbol objects through `pageHandwrittenHeaderData`.
- Add a dedicated header ink scope using `LeadSheetHeaderLayout.handwrittenFrame`.
- Page > Header exposes typed and handwritten modes, a header-writing tool, and a local clear action for handwritten header ink.
- Live canvas and PDF/export share the same mode authority: typed mode draws typed header text; handwritten mode suppresses typed page-header text and draws saved header ink.

## Slice 3: Live Ink Responsiveness And Persistence

User direction:

- Fast handwriting should feel responsive across the chart, including handwritten headers.
- Ink should not feel like it is being erased, chopped, or reloaded while the user is actively writing.

Implementation contract:

- Preserve active passive ink canvases from stale model reloads the same way chord and rhythm ink already preserve dirty live canvases.
- Treat header, page/freehand, and freehand-symbol ink as passive ink: keep it live in `PKCanvasView` while the user is writing, then persist only after a stable idle window or when leaving the tool.
- Increase passive ink idle persistence to avoid serializing/redrawing during normal fast handwritten motion.
- Persist using the old tool's active ink scope when switching back to Select, so header/page/freehand ink does not depend on the idle timer firing first.
- Keep chord recognition, rhythm recognition, OCR, score thresholds, and personal handwriting fixtures unchanged.

## Slice 4: Chord/Rhythm Ink Session Unification

User direction:

- Apply the same live-ink stability thinking to chord and rhythm authoring without changing recognizer behavior.
- Improve recognition reliability by reducing stale scheduled reads and canvas/model sync drift, not by retuning scores.

Implementation contract:

- Replace separate chord, rhythm, and passive dirty-canvas flags with a shared `LeadSheetInkAuthoringSessionState`.
- Route active ink scopes through `LeadSheetInkAuthoringSessionRole` values: chord, rhythm, and passive.
- Keep dirty active canvases protected from stale model reloads through one policy.
- Rename the rhythm-only drawing snapshot to `LeadSheetInkDrawingSnapshot` and use it as the shared stable-canvas snapshot for scheduled work.
- Add stable-snapshot gating to chord recognition requests, matching the rhythm auto-apply safety model.
- Preserve the existing chord commit cleanup path and rhythm V4 commit/fail-closed authority.
- Keep chord recognition, rhythm recognition, OCR, score thresholds, compendium behavior, and personal handwriting fixtures unchanged.

## Slice 5: User Pen Responsiveness Setting

User direction:

- Commit the new ink working state before adding more behavior.
- Add a user setting that lets the writer choose pen responsiveness with a drag bar or plus/minus control.

Implementation contract:

- Store the setting as an app/user preference, not a chart document field.
- Expose the control under Page > Pen Responsiveness.
- Provide a slider plus minus/plus buttons and a balanced reset.
- Apply the setting immediately to the live canvas host.
- Treat the setting as input scheduling only: it changes how much drawing-change follow-up work is coalesced before persistence or recognition timers start.
- Do not change chord recognition, rhythm recognition, OCR, score thresholds, compendium behavior, default diagnostics, or personal handwriting fixtures.

## Slice 6: Measure Double Barlines

User direction:

- Add a double barline measure action to the Measures addition tool.
- The double barline belongs at the end of the measure, not the beginning.
- The first measure of every chart should always begin with a leading double barline.

Implementation contract:

- Keep `Measure.barlineAfter` as the model authority for trailing barlines.
- Use `LeadSheetMeasureLayout.leadingBarline` as shared live canvas and PDF/export authority for first-measure leading barlines.
- Add Page/Measures menu action `Add Double Barline Measure`.
- Reuse the existing add-measure targeting behavior: append/insert after the selected authoring target, or commit the current open measure and create the next open slot.
- When committing the current open measure from this action, set that committed measure's trailing barline to `.double`.
- Do not mutate the first measure's trailing `barlineAfter` just to show the leading double.

## Slice 7: Chord Tool Rendered Chord Correction

User direction:

- When a chord auto-renders incorrectly, the user should not have to switch between Chord and Select just to correct it.
- The Chord tool needs a path for rendered chord deletion and movement.
- Select should be a neutral auto-select/browse state that can also scroll the chart.

Implementation contract:

- Keep Chord mode as an ink-authoring mode; chord writing stays active.
- In Chord mode, rendered chord boxes are active immediately after render.
- Every rendered chord draws a lightweight edit frame in Chord mode so the object remains visible/editable after render.
- Delete, review, and move actions are available from Chord mode without switching tools or selecting first.
- Rendered chord boxes intercept interaction over the chord object so PencilKit does not treat that same spot as new chord ink.
- Empty chord-lane space remains available for writing new chord ink.
- Chord mode bypasses the old post-render object-action suppression so newly rendered chords are immediately interactive.
- Active rendered chord drags lock the parent chart scroll view until the drag ends or fails, so moving a chord does not pan or zoom the sheet underneath it.
- Select/Browse remains the neutral scroll/object-selection state and keeps the existing all-rendered-chord object editing behavior.
- Keep chord recognition, rhythm recognition, OCR, score thresholds, and personal handwriting fixtures unchanged.

## Slice 8: Editor Back-Swipe Lock

User direction:

- Rightward pen movement should not drag the sheet into a quick navigation exit.
- The chart already has an explicit top-left exit arrow, so the interactive swipe-to-exit path should be locked out while editing.

Implementation contract:

- Hide the editor route's system navigation back button so iOS does not attach the default back-swipe exit gesture to the chart canvas.
- Provide an explicit custom top-left exit arrow that dismisses the editor route.
- Keep rendered chord dragging and parent chart scrolling governed by the existing chord-drag scroll lock.
- Scope the lock to app navigation only; do not change chart scrolling, chord dragging, ink persistence, recognition, OCR, parser/compendium behavior, score thresholds, diagnostics, or personal handwriting fixtures.

## Slice 9: Rhythm Section System Breaks

User direction:

- The system break path does not work on Rhythm Section charts.
- Rhythm Section should get the missing Measure-menu system-break behavior.
- Keep Rhythm Section chart behavior otherwise intact.

Implementation contract:

- Promote manual system-break support from Simple-only to the active V1 chart styles: Simple Chord Sheet and Rhythm Section Sheet.
- Keep Lead Sheet manual system breaks deferred for post-V1/compatibility work.
- Store breaks through the existing forced `ChartSystem` boundary model; do not add a second Rhythm-only layout flag.
- Add shared `Chart.canInsertSystemBreak`, `insertSystemBreak`, `canRemoveSystemBreak`, and `removeSystemBreak` APIs, while keeping the old Simple-named APIs as strict Simple-only wrappers.
- Keep Simple's row cap and proportional manual-width behavior unchanged.
- Keep Rhythm Section automatic measure packing/stretching unchanged inside each row, but treat a forced break as a hard rendered-system boundary.
- Use the existing Measures menu commands: `New System Before This Measure` and `Remove System Break`.
- Do not change rhythm recognition, chord recognition, OCR, score thresholds, parser/compendium behavior, diagnostics, or personal handwriting fixture authority.

## Slice 10: Rhythm Section System Visual Alignment

User direction:

- Remove the extra staff-line tails at the start and end of Rhythm Section systems.
- Make systems line up exactly or closely with each other for cleaner reading.

Implementation contract:

- Keep Rhythm Section continuation rows on the same leading measure gutter as the first system.
- Reserve blank continuation gutter space without drawing extra clef/time signatures.
- Draw Rhythm Section staff lines only across the actual visible system boundary: from the leading barline or repeat marker to the trailing barline or repeat marker.
- Keep existing measure packing/stretching, chord placement, rhythm recognition, OCR, parser/compendium behavior, score thresholds, diagnostics, and handwriting fixture authority unchanged.

## Slice 11: Rhythm Section Standard Measure Widths

User direction:

- The measure-width difference between Rhythm Section systems is noticeable.
- Use the current first-system measure width as the standard starting width across the board.

Implementation contract:

- Derive the default Rhythm Section measure width from the first rendered system.
- Apply that default width to later Rhythm Section measures so short forced/manual rows no longer stretch a small measure count across the full system.
- Keep explicit manual measure-width overrides as intentional user edits.
- Prevent standard-width rows from overflowing the available paper body when the first rendered system is unusually short and later rows contain more measures.
- Keep existing system gutters, staff-line clipping, chord placement, rhythm recognition, OCR, parser/compendium behavior, score thresholds, diagnostics, and handwriting fixture authority unchanged.

## Slice 12: Measure Stack Deletion

User direction:

- Add a delete measure/measure stack system.
- Deleting a measure should delete everything attached to that measure.

Implementation contract:

- Add a Measure-menu `Delete Selected Measure` action.
- Use the existing chart model deletion authority so the one-measure minimum remains enforced.
- Treat the deleted measure as a full attached-object stack: chord events, rhythm map/ink, section labels, cue text, roadmap objects, repeat/ending spans, point markers, links, and freehand symbols attached to the measure are removed through the model cleanup path.
- After deletion, clear pending repeat/ending/text/time/note state that could reference the deleted measure.
- Keep the editor in Measure mode and move selection to the next neighboring measure when possible, otherwise the previous remaining measure.
- Do not change rhythm recognition, chord recognition, OCR, parser/compendium behavior, score thresholds, diagnostics, or handwriting fixture authority.

## Slice 13: Controlled Measure Range Deletion

User direction:

- Control exactly which measures are deleted.
- Use the same start/end boundary system approach as repeat across multiple measures.

Implementation contract:

- Add Measure-menu `Start Delete Range Here`, `Delete Through Here`, and `Clear Delete Start` actions.
- `Start Delete Range Here` stores the selected measure as the pending delete boundary, mutually exclusive with pending repeat and ending boundaries.
- `Delete Through Here` deletes the inclusive ordered range between the stored start boundary and the current selected measure.
- The selected range can be chosen forward or backward, matching the repeat/ending multi-measure boundary workflow.
- After deletion, select the previous remaining measure when possible, otherwise the next remaining measure.
- Use the same model-backed attached-stack cleanup path as single-measure deletion for every removed measure.
- Preserve the hard one-measure minimum: ranges that would remove every measure are disabled/refused.
- Clear pending repeat/delete/ending/text/time/note state after range deletion and cancel the pending delete start when leaving Measure work.
- Do not change rhythm recognition, chord recognition, OCR, parser/compendium behavior, score thresholds, diagnostics, or handwriting fixture authority.

## Slice 14: Measure Stack Insertion

User direction:

- Add `Add Measure Stack After Selected`.
- Let the user choose how many measures to add.

Implementation contract:

- Add Measure-menu `Add Measure Stack After Selected`.
- Open a compact count chooser with a `1...64` measure range and common count presets.
- Insert exactly the chosen number of committed measures after the selected anchor through the chart model, not by ad hoc UI looping.
- Preserve existing trailing open-measure behavior; if the selected anchor is open, commit it first, insert the chosen stack after it, and keep the new open measure after the inserted stack.
- Select the last inserted measure after the operation.
- Keep this as Measure-menu editing only.
- Do not change rhythm recognition, chord recognition, OCR, parser/compendium behavior, score thresholds, diagnostics, layout renderer behavior, or handwriting fixture authority.

## Verification

- Focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests'`
- Result: `165` tests, `0` failures.
- Focused header SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests|LeadSheetInteractionModeStatePolicyTests|FileChartRepositoryTests'`
- Result: `174` tests, `0` failures.
- Focused passive ink SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter 'LeadSheetInteractionModeStatePolicyTests|ChartEditingTests|LeadSheetPageLayoutTests|FileChartRepositoryTests'`
- Result: `174` tests, `0` failures.
- Full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `467` tests, `36` skipped, `0` failures.
- Chord/rhythm ink-session unification full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `467` tests, `36` skipped, `0` failures.
- `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture completed after launch.
- Chord/rhythm ink-session unification XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture completed after launch.
- User pen responsiveness focused SwiftPM filter compiled the updated UIKit-gated test file; no macOS package tests matched that filter.
- User pen responsiveness full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `467` tests, `36` skipped, `0` failures.
- User pen responsiveness focused simulator: XcodeBuildMCP `test_sim -only-testing:SmartChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO`
- Result: `39` tests, `0` failures.
- User pen responsiveness XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture completed after launch.
- Measure double barline focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests'`
- Result: `172` tests, `0` failures.
- Measure double barline full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `471` tests, `36` skipped, `0` failures.
- Measure double barline XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture completed after launch.
- Chord tool correction full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `471` tests, `36` skipped, `0` failures.
- Chord tool correction focused simulator: XcodeBuildMCP `test_sim -only-testing:SmartChartTests/LeadSheetInteractionModeStatePolicyTests -only-testing:SmartChartTests/LeadSheetChordEditOverlayGeometryTests CODE_SIGNING_ALLOWED=NO`
- Result: `49` tests, `0` failures.
- Chord tool correction XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- Chord tool rendered-box follow-up full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `471` tests, `36` skipped, `0` failures.
- Chord tool rendered-box follow-up XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- Chord tool active-rendered-object follow-up full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `471` tests, `36` skipped, `0` failures.
- Chord tool active-rendered-object follow-up XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- Editor back-swipe lock full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `471` tests, `36` skipped, `0` failures.
- Editor back-swipe lock XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- `git diff --check` passed.
- Rhythm Section system-break focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests`
- Result: `100` tests, `0` failures.
- Rhythm Section system-break focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests`
- Result: `75` tests, `0` failures.
- Rhythm Section system-break full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `474` tests, `36` skipped, `0` failures.
- Rhythm Section system-break `git diff --check` passed.
- Rhythm Section system-break XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture completed after launch.
- Rhythm Section system visual alignment focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests`
- Result: `75` tests, `0` failures.
- Rhythm Section system visual alignment full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `474` tests, `36` skipped, `0` failures.
- Rhythm Section system visual alignment XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture confirmed aligned Rhythm Section systems without staff-line tails past the barlines.
- Rhythm Section standard measure widths focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests`
- Result: `76` tests, `0` failures.
- Rhythm Section standard measure widths full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `475` tests, `36` skipped, `0` failures.
- Rhythm Section standard measure widths XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture completed after launch.
- Measure stack deletion focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests'`
- Result: `177` tests, `0` failures.
- Measure stack deletion full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `476` tests, `36` skipped, `0` failures.
- Measure stack deletion XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture completed after launch.
- Controlled measure range deletion focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests`
- Result: `103` tests, `0` failures.
- Controlled measure range deletion full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `478` tests, `36` skipped, `0` failures.
- Controlled measure range deletion `git diff --check`: passed.
- Controlled measure range deletion XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture confirmed launch to Projects.
- Measure stack insertion focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests`
- Result: `106` tests, `0` failures.
- Measure stack insertion full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `481` tests, `36` skipped, `0` failures.
- Measure stack insertion `git diff --check`: passed.
- Measure stack insertion XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture confirmed launch to Projects.

## Guardrails

- No chord-recognition score retuning.
- No OCR expansion.
- No personal handwriting fixture expansion.
- No default diagnostics stream.
- No key-dependent transposition requirements for Simple Chord Sheet or Rhythm Section Sheet.
- Header handwriting is raw page ink, not OCR or recognized text.
- Passive ink responsiveness does not change chord/rhythm recognition authority.
- Chord/rhythm ink-session unification does not change parser, compendium, scoring, OCR, or training authority.
- User pen responsiveness changes input scheduling only and does not change parser, compendium, scoring, OCR, or training authority.
- Chord tool correction changes rendered-object interaction routing only and does not retune recognition or correction authority.
- Editor back-swipe locking changes app navigation behavior only and does not change canvas, ink, recognition, parser, compendium, scoring, OCR, or training authority.
- Rhythm Section system breaks change Measure-menu layout boundaries only and do not retune recognition, parser, compendium, scoring, OCR, diagnostics, or training authority.
- Rhythm Section system visual alignment changes shared live/export rendering geometry only and does not retune recognition, parser, compendium, scoring, OCR, diagnostics, or training authority.
- Rhythm Section standard measure widths change rendered layout planning only and do not retune recognition, parser, compendium, scoring, OCR, diagnostics, or training authority.
- Measure stack deletion changes Measure-menu editing only and does not retune recognition, parser, compendium, scoring, OCR, diagnostics, or training authority.
- Controlled measure range deletion changes Measure-menu editing only and does not retune recognition, parser, compendium, scoring, OCR, diagnostics, or training authority.
- Measure stack insertion changes Measure-menu editing only and does not retune recognition, parser, compendium, scoring, OCR, diagnostics, layout renderer behavior, or training authority.
- Lead Sheet remains post-V1 beyond compatibility behavior already present in the model.

## Next Candidate Slices

1. Project/library UX: rename, duplicate, delete, clearer metadata, less developer-facing library behavior.
2. Export/share UX: obvious export flow, PDF preview confidence, file naming, app-created export proof.
3. Save/reopen confidence: visible but quiet saved-state behavior.
4. Toolstrip/menu affordances: naming, hit-targets, active-menu state polish.
