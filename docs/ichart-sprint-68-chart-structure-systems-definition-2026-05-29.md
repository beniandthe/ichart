# iChart Sprint 68 Chart Structure Systems Definition

Status: active definition sprint
Date: 2026-05-29
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Purpose

Sprint 68 resumes the main chart-layout plan after the Rhythm Section core-authoring side sprint. The goal is to define the shared chart-structure systems for the V1 sheet styles before implementation changes layout behavior.

This sprint began definition-first. Do not implement section/system layout, roadmap symbols, cue text, or richer per-style rendering until the target behavior is written down and confirmed for that slice.

Lead Sheet feature work is deferred until after V1. Preserve existing compatibility and baseline behavior, but do not use Lead Sheet as an active Sprint 68 design target.

## Current Foundation

- `ChartLayoutStyle` and `ChartLayoutProfile` are implemented for Simple Chord Sheet, Rhythm Section Sheet, and Lead Sheet.
- New Chart setup follows each layout style's key, time, starting-measure, and clef policy.
- Every chart style preserves a hard one-measure minimum.
- Simple Chord Sheet has blank barline-to-barline measures and measure-attached floating freehand ink anywhere on the chart paper.
- Rhythm Section Sheet owns the current staff-line rhythm/chord workflow and V4 rhythm recognition gate.
- Lead Sheet has the first clef/key-signature baseline and a narrow in-staff pitched-note proof, now archived for post-V1 continuation in `post-v1/lead-sheet/`.

## Systems To Define

### 1. System Layout And Measure Flow

Definition needed:

- How measures wrap into systems for the V1 sheet styles.
- Whether each style uses fixed measures per row, flexible fit-to-page wrapping, manual row breaks, or a hybrid.
- How manual measure stretch/compress interacts with wrapping.
- How adding measures at the beginning, after selected, or later between measures should reflow existing content.
- Whether users can force a new system before automatic layout is implemented.

Implementation boundary:

- Start with model/layout tests before changing renderer behavior.
- Preserve existing Rhythm Section authoring feel unless this sprint explicitly defines a change.
- Keep the one-measure minimum invariant.

Simple Chord Sheet direction:

- The target feel is an iReal Pro / handwritten chord-chart grid, not a notation staff.
- The page should feel like free grid space arranged by the musician.
- A system is a horizontal row of chord-chart measures, not a staff system with notation semantics.
- System rows should be controlled by manual row breaks, not per-measure row IDs or fully automatic equal-width grouping.
- Measures must stay complete inside one system row; a single measure should not split across rows.
- Users should be able to compress, stretch, and reposition measures in a system row.
- Direct row dragging can be revisited later, but the V1 control path is the Measure menu: `New System Before This Measure` and `Remove System Break`.
- Moving measures to a new system should live under the Measure menu/edit-measure workflow.
- The first Measure menu row-break controls should be `New System Before This Measure` and `Remove System Break`.
- Adding a measure should place the new measure on the same system row as the current last measure by default.
- iChart should preserve user-directed system grouping instead of immediately forcing every measure back into an automatic equal-width layout.
- The default can still start from a compact chord-chart grid, but user discretion controls how many measures belong on a row.
- The amount of measures per row is entirely at the user's discretion up to an app/performance cap.
- Simple Chord Sheet must allow at least `16` measures in one row.
- The first implementation should expose the row cap through a profile/test constant, defaulting to `20` measures per row, so simulator performance evidence can tune it later without scattering magic numbers.

Manual row-break behavior:

- `New System Before This Measure` inserts a row break before the selected measure, unless it is already the first measure on its row.
- `Remove System Break` removes the row break before the selected measure when one exists, merging the selected measure's row into the previous row.
- Adding a measure at the end appends it to the final row.
- Adding a measure after selected inserts it after the selected measure and keeps it in that selected measure's current row unless the user later adds a row break.
- Adding a measure at the beginning keeps the new first measure on the first row and shifts existing row breaks by measure identity/order without creating a zero-measure row.
- Rows auto-fit proportionally inside the available page width.
- Compress/stretch changes the selected measure's relative width weight inside its row; it should not silently add or remove row breaks.
- Adding a measure to a row proportionally rebalances that row while preserving user width emphasis.
- iChart should not automatically move measures to a new row for readability.
- The row cap is the exception: when adding a measure would exceed the cap, iChart automatically starts a new system and places the new measure there.
- Dragging a measure vertically between rows should become a row-break edit operation, not a second layout authority.
- Row-break actions move the selected measure plus every following measure until the next manual row break; they do not move only one isolated measure.
- In Measure edit mode, a subtle row-break/group guide should appear for the selected measure group so the user can see which measures the menu action affects.

Reference notes:

- iReal Pro's documented chart representation is cell/grid-like: it describes 16 cells per line, usually 4 cells per measure, producing a common 4-measure system.
- iReal Pro also exposes adding/deleting spaces to adjust bar size and warns that a measure should not split between systems.
- iChart should use those ideas as product inspiration, not a compatibility requirement or clone target.

Rhythm Section Sheet direction:

- Rhythm Section Sheet should keep automatic system wrapping for now.
- The visual target is a close-to-professional rhythm/hit chart feel: clear staff systems, chord lane, rhythmic hits/slashes, cue text, and roadmap space.
- The inspiration includes real big-band-style hit/rhythm charts, but the product should not become intentionally jazz-only or genre-locked.
- The visible renderer currently flattens measures and packs them left-to-right by preferred measure width until the next measure would exceed the available page width, then starts a new system.
- Rhythm Section should not adopt Simple Chord Sheet's manual row-break grid in this slice.
- Manual row/system breaks for Rhythm Section are deferred until section labels, roadmap objects, or rhythm-section-specific spacing prove they are needed.
- The mismatch between model-level four-measure chunks and renderer-level width packing should be cleaned up later as architecture debt, but this definition pass should not change the user-facing Rhythm Section flow yet.

### 2. Section Labels

Definition needed:

- The v1 section-label vocabulary and whether labels are typed, handwritten, or selected from a menu first.
- Whether labels anchor to a measure, system, or page position.
- How labels affect vertical spacing and measure/system wrapping.
- How labels appear differently in Simple Chord Sheet and Rhythm Section Sheet.

Implementation boundary:

- Section labels should become structured chart objects, not raw free text.
- Recognition for handwritten section labels is deferred unless explicitly scoped.

V1 direction:

- Section labels are measure-attached structured objects.
- A section label means "section starts before this measure."
- A section label should not automatically force a new system row.
- A later option may combine a section label with a manual row/system break, but those should remain separate layout concepts.
- Creation should start through a menu/manual entry flow, not handwriting recognition.
- Each measure should support at most one primary section label for V1.
- Section labels should survive measure insertion and reindexing by anchoring to measure ID, not only measure number.
- If the anchored measure is deleted later, all section labels and symbols attached to that measure should be deleted with it.
- V1 preset vocabulary: `Intro`, `A`, `B`, `C`, `Verse`, `Chorus`, `Bridge`, `Solo`, `Tag`, `Coda`.
- V1 must also support custom section text.
- Simple Chord Sheet visual treatment: compact boxed/pill-style form marker above the attached measure or row, optimized for dense chord-grid readability.
- Rhythm Section Sheet visual treatment: stronger rehearsal-mark style above the staff/chord lane, clear enough for a professional rhythm/hit chart without colliding with chord symbols.

### 3. Roadmap Objects

Definition needed:

- V1 roadmap vocabulary: repeats, first/second endings, coda, To Coda, Segno, D.S., D.C., Fine, N.C., vamp count, and any exclusions.
- Object anchoring rules: barline-anchored, measure-spanning, system-level, or text-like.
- How repeat spans and endings behave when measures are inserted or moved.
- How roadmap objects differ visually between Simple Chord Sheet and Rhythm Section Sheet.

Implementation boundary:

- Prefer structured objects with deterministic layout and export.
- Recognition is deferred; start with menu/manual object creation unless a smaller recognition slice is defined later.

V1 direction:

- Roadmap objects are structured chart objects, not freehand ink and not plain floating text.
- Creation should start through a menu/manual entry flow, not handwriting recognition.
- Roadmap objects should reuse the existing `RoadmapObject` model direction: `type`, `startMeasureID`, optional `endMeasureID`, optional `anchorSystemID`, placement, display text, optional count, optional linked target, and raw input.
- Roadmap objects anchor by measure ID so insertion and reindexing preserve intent.
- If a measure is deleted later, any roadmap object attached to that measure should be deleted with it.
- V1 should support single-measure markers and measure-spanning objects.

V1 vocabulary:

- `Repeat Span`
- `1st Ending`
- `2nd Ending`
- `Coda`
- `To Coda`
- `Segno`
- `D.S.`
- `D.S. al Coda`
- `D.C.`
- `D.C. al Fine`
- `Fine`
- `N.C.`
- `Vamp Count`

Object anchoring:

- Point markers use `startMeasureID` only.
- Span objects use `startMeasureID` and `endMeasureID`.
- Endings and repeat spans are spanning objects.
- Coda, To Coda, Segno, D.S., D.C., Fine, and N.C. are point markers unless a later slice defines a span behavior.
- Vamp count can start as a point marker with `count`, then become a span if the user selects an end measure.
- Linked targets, such as To Coda to Coda, should remain optional for V1; visual rendering should not depend on solving playback/navigation.

Visual treatment:

- Simple Chord Sheet: compact roadmap symbols and brackets integrated into the chord grid; prioritize density and quick form readability.
- Rhythm Section Sheet: professional chart treatment above the staff/chord lane, with repeat and ending brackets clear enough for rhythm/hit charts.
- Roadmap objects should reserve just enough local vertical space to avoid collisions, but should not force global page redesign in the first slice.

Implementation sequence:

1. Add/edit/delete repeat spans and repeat markers first.
2. Add/edit/delete first and second endings.
3. Add/edit/delete point roadmap markers such as Coda, Segno, Fine, D.S., D.C., and N.C.
4. Skip vamp count for now; keep it deferred until there is a clearer V1 need.
5. Add optional linked target behavior after point marker rendering is stable.

First roadmap implementation:

- Start with repeats and repeat markers.
- V1 repeat work should cover start repeat, end repeat, and repeat span rendering/anchoring.
- Repeat marker creation should be available from the selected measure's Measure/Roadmap menu path.
- Repeat spans should use measure IDs for start and end anchors.
- Repeat markers should survive measure insertion and reindexing, but should be deleted if their attached measure is deleted.
- First and second endings are important but should be the second roadmap slice after repeat markers are stable.

Repeat span contract:

- A V1 repeat should persist as one structured `Repeat Span` roadmap object, not as two unrelated start/end marker objects.
- `startMeasureID` means the first measure inside the repeat.
- `endMeasureID` means the final measure inside the repeat.
- The renderer should draw a start-repeat marker at the leading edge of the start measure and an end-repeat marker at the trailing edge of the end measure.
- A one-measure repeat is valid when `startMeasureID` and `endMeasureID` are the same measure.
- Independent start-only or end-only repeat markers are deferred until there is a clear product need; the first slice should avoid orphan repeat markers.
- The menu flow may expose `Start Repeat Here`, `End Repeat Here`, and `Repeat Selected Range`, but the committed model result should still be a single repeat-span object.
- Repeat count text such as `x3` is deferred from this first slice unless it naturally falls out of the same edit surface; the default repeat marker implies the standard repeat.
- If the start or end measure is deleted, delete the whole repeat span.
- If measures are inserted between the start and end anchors, the inserted measures become part of the repeat span because the span resolves by current measure order between its measure IDs.
- If measures are inserted before the start or after the end, the repeat anchors stay attached to their original measures.
- If a future move operation inverts the start/end order, the span should fail closed for rendering/editing until the user repairs the range.

Repeat visual contract:

- Simple Chord Sheet should render compact repeat barlines and dots integrated into the chord-grid cell edges without stealing much horizontal space.
- Rhythm Section Sheet should render notation-style repeat barlines and dots through the staff at the repeated range edges.
- Both styles should leave room for later ending brackets above the repeated measures without requiring a global page-layout rewrite in the first slice.

Repeat implementation test targets:

- Model add/edit/delete for a repeat span by selected start/end measures.
- One-measure minimum remains intact when repeat spans are added or removed.
- Inserting measures before, inside, and after the span preserves the intended anchor behavior.
- Deleting either attached measure deletes the repeat span and clears measure back-references.
- Layout/export can resolve start/end marker geometry for Simple Chord Sheet and Rhythm Section Sheet.

Repeat implementation progress:

- Model repeat-span creation, update, lookup, and deletion are implemented locally through `ChartEditing`.
- Repeat spans attach their roadmap object ID to the start and end boundary measures, using one back-reference for one-measure repeats.
- Duplicate requests for the same repeat boundary return the existing repeat span instead of stacking duplicate repeat markers.
- Repeat spans can be removed from a selected boundary measure; selecting an interior measure does not remove the span because no repeat marker is attached there.
- Public measure deletion now preserves the one-measure minimum and removes annotations attached to the deleted measure: section labels, cue text, freehand symbols, and roadmap objects.
- Deleting a repeat boundary measure deletes the whole repeat span; deleting a non-boundary measure does not implicitly delete the span.
- Layout now resolves repeat marker geometry for both Simple Chord Sheet and Rhythm Section Sheet through the shared page layout.
- The editor canvas and PDF export path draw repeat markers from the same `LeadSheetRepeatMarkerLayout` geometry.
- Repeat spans are excluded from the legacy roadmap-text banner so they render as barline markers only.
- Repeat marker art was tuned after the first live pass so each marker reads as two clear barlines instead of one overly thick artifact.
- The Measures menu exposes first repeat creation/removal commands: `Repeat Selected Measure`, `Start Repeat Here`, `End Repeat Here`, `Remove Repeat at Selected Measure`, and `Clear Repeat Start`.
- Focused verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `102` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `378` tests, `36` skipped, and `0` failures.
- Simulator verification: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.

Ending span contract:

- V1 first and second endings persist as structured roadmap span objects of type `1st Ending` or `2nd Ending`, not as loose text or freehand ink.
- `startMeasureID` means the first measure under the ending bracket.
- `endMeasureID` means the final measure under the ending bracket.
- One-measure endings are valid when `startMeasureID` and `endMeasureID` are the same measure.
- First and second endings can share the same measure range because they represent different musical passes.
- Duplicate requests for the same ending type and same boundary range return the existing ending span.
- Deleting either attached boundary measure deletes the whole ending span and clears measure back-references.
- Inserting measures between the anchors includes the inserted measures in the visual span by current measure order; inserting before or after the anchors preserves the existing boundary measures.
- If a future move operation inverts the start/end order, the span should fail closed for rendering/editing until the user repairs the range.

Ending visual contract:

- Simple Chord Sheet renders compact ending brackets above the blank measure space, integrated with the chord-grid feel and excluded from the legacy roadmap-text banner.
- Rhythm Section Sheet renders notation-style ending brackets above the chord lane and reserves local bracket space so chord symbols remain readable below the bracket.
- Wrapped ending spans render as system-local bracket segments from the first visible measure in range to the last visible measure in range.
- The first visible segment shows the ending label (`1.` or `2.` by default); continuation segments preserve the bracket without creating a second roadmap-text banner.

Ending implementation progress:

- `RoadmapType` now marks repeat spans and endings as structured-layout roadmap objects.
- `ChartEditing` can add, update, look up through `roadmapObject(id:)`, and delete first/second ending spans by selected boundary measures.
- Ending spans attach their roadmap object ID to the start and end boundary measures, support one-measure endings, reject missing/inverted/non-ending requests, allow first and second endings over the same range, and avoid duplicate spans for the same type/range.
- Shared layout resolves `LeadSheetEndingLayout` per system segment for Simple Chord Sheet and Rhythm Section Sheet.
- The editor canvas and PDF export path draw ending brackets through the shared notation renderer.
- The Measures menu exposes ending creation/removal commands: `1st Ending Selected Measure`, `2nd Ending Selected Measure`, `Start 1st Ending Here`, `Start 2nd Ending Here`, `End Ending Here`, `Remove Ending at Selected Measure`, and `Clear Ending Start`.
- Focused verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `116` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `392` tests, `36` skipped, and `0` failures.
- Focused simulator PDF verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/PDFChartExporterTests CODE_SIGNING_ALLOWED=NO` passed with `5` tests and `0` failures.
- Simulator verification: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.

Point marker contract:

- V1 point roadmap markers persist as structured roadmap objects with `startMeasureID` only and no `endMeasureID`.
- Supported V1 point marker types are `Coda`, `To Coda`, `Segno`, `D.S.`, `D.S. al Coda`, `D.C.`, `D.C. al Fine`, `Fine`, and `N.C.`.
- Duplicate requests for the same marker type and same measure return the existing point marker instead of stacking duplicates.
- Deleting the attached measure deletes the marker and clears the measure back-reference.
- Linked target behavior, such as connecting `To Coda` to a `Coda`, remains optional and model-only for V1; visual rendering does not depend on playback/navigation semantics.
- Vamp count is skipped for now because it needs a count entry surface and may later become either a point marker or span.

Point marker visual contract:

- Simple Chord Sheet renders compact marker text above the blank measure space, integrated with the chord-grid feel and excluded from the legacy roadmap-text banner.
- Rhythm Section Sheet renders point markers in a reserved local roadmap lane above the chord lane so chord symbols remain readable.
- If a point marker and an ending bracket share a system, the ending bracket shifts down inside the roadmap reserve instead of colliding with the marker.
- The editor canvas and PDF export path use the same `LeadSheetRoadmapMarkerLayout` geometry and shared notation renderer.

Point marker implementation progress:

- `RoadmapType` now identifies point marker types separately from repeat spans, endings, and deferred vamp count.
- `ChartEditing` can add, look up by attached measure, deduplicate, and delete point roadmap markers while preserving measure-ID anchoring.
- Shared layout resolves `LeadSheetRoadmapMarkerLayout` for Simple Chord Sheet and Rhythm Section Sheet and keeps point markers out of the legacy roadmap-text banner.
- The editor canvas and PDF export path draw point markers through the shared notation renderer.
- The editor now exposes a `Roadmap` menu with point marker creation commands plus `Remove Roadmap Marker at Selected Measure`.
- Focused verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `122` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `398` tests, `36` skipped, and `0` failures.
- Focused simulator PDF verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/PDFChartExporterTests CODE_SIGNING_ALLOWED=NO` passed with `5` tests and `0` failures.
- Simulator verification: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.

Linked target contract:

- Optional V1 linked targets use the existing `RoadmapObject.linkedTargetID` field.
- Supported source-to-target rules are intentionally small: `To Coda` can link to `Coda`, `D.S.` and `D.S. al Coda` can link to `Segno`, and `D.C. al Fine` can link to `Fine`.
- `D.C.`, standalone `Coda`, standalone `Segno`, standalone `Fine`, `N.C.`, repeat spans, endings, and deferred vamp count are not link sources in this slice.
- Suggested links prefer musical direction: `To Coda` looks forward first, while `D.S.`, `D.S. al Coda`, and `D.C. al Fine` look backward first.
- Missing targets fail quietly. The marker still renders and exports normally without a link.
- Deleting a linked target clears any source `linkedTargetID` that pointed to it, whether the target marker is removed directly or through measure deletion.
- Linked targets do not create playback/navigation behavior, extra visible explanation text, or export dependencies in this slice.

Linked target implementation progress:

- `RoadmapType` now owns the small source/target vocabulary and preferred target-search direction.
- `ChartEditing` can suggest, set, clear, and auto-link valid point roadmap targets while rejecting invalid source/target pairs.
- Point marker creation auto-links when a valid target already exists, and the editor `Roadmap` menu can link or clear links for markers attached to the selected measure.
- Roadmap deletion paths clear stale incoming links so the model does not retain dangling target IDs.
- Focused verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `78` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `403` tests, `36` skipped, and `0` failures.
- Simulator verification: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.

### 4. Cue Text

Defined V1 behavior:

- Cue text is structured musician-facing instruction text attached to a measure: groove notes, player instructions, arrangement reminders, tacets, stops, pushes, builds, or short local notes.
- Cue text is not a section label and not a roadmap/navigation symbol. Section labels describe form starts; roadmap objects describe repeat/navigation structure; cue text describes local performance instructions.
- Cue text is not freehand articulation ink. V1 cue text is typed/manual-first and renders as editable structured text; handwritten cue recognition is deferred.
- Cue text is measure-attached. If the measure is deleted, all cue text attached to that measure is deleted with it.
- V1 supports above-measure and below-measure cue positions. The default user path is below the selected measure; above is available for cases where below-staff space is already carrying local articulations.
- Simple Chord Sheet renders cue text as small secondary text inside the measure's blank space, keeping the handwritten/iReal-style chart feel.
- Rhythm Section Sheet renders cue text as small secondary text below or above the staff lane so the primary chord and rhythm notation remain visually dominant.

Implementation progress:

- `ChartEditing` can now add cue text to a selected measure, trim/reject empty text, preserve position/emphasis, look up cue text, and remove cue text attached to a measure while clearing measure back-references.
- Shared layout resolves `LeadSheetCueTextLayout` per measure for Simple Chord Sheet and Rhythm Section Sheet.
- The editor canvas and PDF export path draw cue text through the shared notation renderer.
- The editor now exposes this workflow through the user-facing `Text` menu with add-below, add-above, and remove-at-selected-measure commands.
- Focused verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `107` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `383` tests, `36` skipped, and `0` failures.
- Simulator verification: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.

### 5. Per-Style Export And Readability

Defined V1 behavior:

- Simple Chord Sheet export is worthy when it reads like a dense handwritten chord-chart grid: no key header, blank barline-to-barline measure space, structured chords inside the blank measure area, compact section/repeat/cue objects, and measure-attached chart-area freehand ink that stays separate from chord entry.
- Simple Chord Sheet should prefer dense one-page readability when possible, but never by overlapping structured objects or collapsing the user's measure-width emphasis.
- Rhythm Section Sheet export is worthy when it reads like a professional rhythm/hit chart: no key header, visible meter/staff systems, chord lane above the staff, rhythmic slashes/rests inside the staff lane, cue text and below-staff freehand articulations below the measure, and clear repeat markers at repeated range edges.
- Rhythm Section Sheet prioritizes readable rhythm-lane space over maximum density. Automatic wrapping remains acceptable for this slice.
- Both active V1 styles must export from structured chart objects and shared page-layout geometry, not screenshots, editor placeholders, or raw live ink.
- Lead Sheet export polish remains deferred to the post-V1 archive.

Implementation boundary:

- Export should render from structured chart objects, not screenshots or raw editor ink.
- Keep PDF proof proportional to each implemented slice.

Implementation progress:

- `PDFChartExporterTests` now includes Simple Chord Sheet and Rhythm Section Sheet export-proof charts populated with section labels, repeat spans, ending spans, point roadmap markers, cue text, chords, and rhythm maps where appropriate.
- The PDF proof asserts exported document text includes the structured title/chord/cue/section/point-marker content and excludes key text plus editor placeholder instructions. Repeat markers and ending brackets remain geometry-proofed through layout tests because their barline/bracket art is not reliably searchable PDF text.
- `LeadSheetPageLayoutTests` now includes SwiftPM-visible per-style readiness tests proving Simple keeps staff lines absent and structured objects readable inside the chord-grid layout, while Rhythm Section keeps staff lines, chord lane, rhythm notation, below-staff cue/freehand space, repeat edge markers, ending bracket space, and point marker space readable across automatic wrapping.

Verification:

- Focused layout verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `45` tests and `0` failures.
- Focused simulator PDF verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/PDFChartExporterTests CODE_SIGNING_ALLOWED=NO` passed with `5` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `385` tests, `36` skipped, and `0` failures.
- Simulator smoke verification: `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.

## Simple Chord Sheet Manual Rows Implementation

Implemented slice:

- `ChartLayoutProfile` now exposes a Simple Chord Sheet row-cap contract through `maximumMeasuresPerSystem`, defaulting Simple Chord Sheet to `20` while leaving Rhythm Section Sheet and Lead Sheet automatic.
- `ChartEditing` now supports `New System Before This Measure` and `Remove System Break` for Simple Chord Sheet only.
- Manual row breaks are stored as forced `ChartSystem` boundaries and are preserved by measure identity when measures are inserted or reindexed.
- Adding a measure at the beginning keeps the new measure on the first row and shifts existing forced row breaks by measure identity.
- Adding a measure beyond the Simple row cap starts an automatic next row; this is the only automatic Simple row push in this slice.
- The Simple Chord Sheet page layout now renders each model system as a proportional fit-to-row chord-grid system. Default measures share equal width, and manual width emphasis acts as the only proportional weight source.
- Simple Chord Sheet layout allows `16` measures on one row and caps at `20`; Rhythm Section layout remains on the existing automatic width-packing path.
- The editor Measures menu exposes `New System Before This Measure` and `Remove System Break`, disabled outside valid Simple Chord Sheet row-break positions.

Verification:

- Focused model/layout verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `134` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `410` tests, `36` skipped, and `0` failures.
- Simulator smoke verification: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture showed the app launched to Projects.

## Simple Chord Sheet Row Group Indicator

Implemented slice:

- Measure edit mode draws a Simple Chord Sheet-only row group guide for the selected measure.
- The guide is a dashed marker spanning the selected measure through the end of the current manual row.
- The grouping follows the row-break rule: selected measure plus following measures until the next manual row break.
- Rhythm Section Sheet and Lead Sheet do not show this Simple row-group guide.
- Direct vertical drag has been removed from the active V1 path after live-pass friction; the Measure menu remains the row-break authority and does not introduce per-measure row IDs or freeform placement state.

Verification:

- Focused layout verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `54` tests and `0` failures after adding equal-default-width and manual-weight regression coverage.
- Focused simulator editor verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `21` tests and `0` failures after removing the active vertical drag path.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `412` tests, `36` skipped, and `0` failures.
- Simulator smoke verification: `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.

## Simple Floating Freehand Ink Pivot

Implemented slice:

- Simple Chord Sheet freehand ink no longer uses above/below lanes or a resize handle.
- Simple `Free-Hand` mode uses the chart-paper writing scope and persists strokes as `FreehandSymbolLane.chartArea` objects.
- Chart-area symbols store a measure-relative frame, so they move with the attached measure when the row/layout changes.
- Selected freehand symbols keep delete and move controls only; moving a chart-area symbol reanchors it to the nearest measure when its center crosses measure territory.
- Selected freehand symbol drag targets are intentionally more forgiving than the visible edit box, and the active-tool scroll gate protects editable freehand boxes/controls from parent page panning so grabbing an ink object does not pull the page sideways.
- Rhythm Section Sheet keeps the below-measure freehand articulation lane; Lead Sheet still has no active freehand symbol lane for V1.
- The previous freehand resize checkpoint is superseded by this floating ink model because resizing the selection box did not resize the underlying PencilKit ink.

Verification:

- Focused model verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `82` tests and `0` failures after adding chart-area storage, lane-policy, move, and delete coverage.
- Focused layout verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `54` tests and `0` failures after updating Simple export/readability and chart-area layout coverage.
- Focused simulator editor verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetFreehandSymbolEditOverlayGeometryTests -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `25` tests and `0` failures.
- Focused simulator editor hardening: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetFreehandSymbolEditOverlayGeometryTests -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `28` tests and `0` failures after the selected freehand drag-target hardening.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `412` tests, `36` skipped, and `0` failures.
- Simulator smoke verification: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.

## Tool Scroll Margin Gate

Implemented slice:

- Browse mode keeps normal page scrolling.
- Any active tool mode gates the parent page scroll gestures to the outside paper margins, so gestures that begin on the rendered sheet do not pan the document while the user is writing, erasing, resizing measures, selecting, or moving objects.
- The gate is installed by the canvas host as custom no-op blocker recognizers on the enclosing `UIScrollView`; it makes the built-in pan/pinch gestures wait/fail for sheet-started tool gestures without replacing UIKit's required scroll gesture delegates.
- The margin decision uses the rendered paper frame with a small hit slop, keeping near-edge paper gestures stable while still allowing scroll starts from the surrounding workspace.

Verification:

- XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `23` tests and `0` failures after adding scroll-margin policy coverage.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `412` tests, `36` skipped, and `0` failures.
- Simulator smoke verification: `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.
- Crash hardening verification: after a clean simulator erase on 2026-05-30, XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` launched successfully and screenshot capture succeeded without the `UIScrollView` pan delegate exception.

## Toolstrip Cleanup

Implemented slice:

- `Select` is now the highlighted default browse tool, and highlighted tools can be tapped again to return to `Select`.
- `Page` is now a dropdown that owns Export, Header, Style, Fonts, and Engraving controls.
- Style, Fonts, Engraving, and Header no longer occupy separate toolstrip tabs.
- The roadmap tool is surfaced as the coda-symbol menu while keeping the existing roadmap object model and commands.
- `Cue` is now user-facing `Text`; the underlying typed cue-text model remains the structured musician-instruction object.
- `Chord` uses a pencil icon instead of the text-format glyph.
- `Free-Hand` remains the ink-entry label; Rhythm Section keeps its below-measure freehand lane without renaming the tool to Articulation.
- Legacy/redundant `Edit`, `Jazz`, and `View` tabs are hidden from the active V1 toolstrip.
- `Add Measure After Selected` now inserts a real measure after the selected measure instead of only reusing the trailing open measure.

Verification:

- Focused SwiftPM `ChartEditingTests/testInsertMeasureAfterSelectedAddsMeasureWithoutMovingTrailingOpenMeasure` passed with `1` test and `0` failures.
- XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `24` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `413` tests, `36` skipped, and `0` failures.
- `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only, and screenshot capture succeeded.

## Simple Header And Grid Polish

Implemented slice:

- `Rhythmic Notation` is hidden from the Simple Chord Sheet toolstrip because Simple has no rhythmic-notation ink scope; Rhythm Section and Lead Sheet keep the tool available.
- Simple Chord Sheet measure bodies now use a taller blank chord-grid cell so regular barlines read as measure boundaries instead of short staff remnants.
- Simple Chord Sheet regular barlines are drawn heavier while keeping the repeat-marker double-bar treatment separate.
- The chart header now follows a cleaner chart-header hierarchy: centered title, one compact metadata row beneath it, style/tempo text on the left, key/meter centered when present, composer/credit on the right.
- The old title underline is removed from the rendered editor/PDF header.

Reference notes:

- iReal Pro's documented chord chart format is a cell/grid representation with explicit barline symbols and a common 4-measure system feel, which supports making Simple measure boundaries more visually assertive.
- Lead-sheet/chord-chart header references consistently treat title, style/tempo, key/meter, and composer/credit as compact header metadata rather than large stacked form fields.

Verification:

- Focused SwiftPM `LeadSheetPageLayoutTests` passed with `55` tests and `0` failures after adding header metadata-row and Simple tall-grid layout coverage.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `414` tests, `36` skipped, and `0` failures.
- XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `24` tests and `0` failures.
- XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests CODE_SIGNING_ALLOWED=NO` passed with `55` tests and `0` failures.
- `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only, and screenshot capture succeeded.

## Cohesion Polish

Implemented slice:

- Simple Chord Sheet now reserves a left meter gutter across every rendered row, so the initial time signature appears before the first measure without shifting only the first row.
- Simple Chord Sheet non-initial meter changes now render visibly in the grid instead of being suppressed.
- The Measures tool keeps opening as a menu during pending multi-step measure workflows such as `Start Repeat Here` -> `End Repeat Here` and ending-span creation, instead of deselecting on the second tap.
- Header, metadata, section, roadmap, and cue text now use stable app-standard text fonts instead of the selected notation font, so font changes do not clip the bottom of chart headers or make annotation styles drift.
- Follow-up correction: non-initial time-signature changes now render inline inside the measure whose meter they change, not before the barline of the previous measure.
- First architecture seam: `LeadSheetPageLayoutEngine.VisualPolicy` now owns shared header/meter placement constants so visual decisions can keep moving out of one-off feature code.

Design note:

- This is the first small pass toward a unified chart visual grammar. The larger follow-up is to consolidate tool/symbol/header/annotation styling into one explicit per-style visual policy instead of letting each feature define its own typography, spacing, and symbol treatment independently.

## Simple iReal-Style Visual Cohesion

Implemented slice:

- The provided iReal Pro screenshot is treated as a feel reference, not a 1:1 compatibility target.
- Simple Chord Sheet now uses a tighter chart-header hierarchy: compact title-case title, style/tempo text on the left, composer/credit on the right, and no duplicated key/meter header block.
- The first time signature still appears before the first measure inside the shared left gutter; later meter changes stay inline inside the measure they change.
- Simple rendering now uses white paper, larger bold size-fitting chord text, and stronger chord-grid identity while keeping the measured grid and structured object model unchanged.
- Simple section labels render as black badges sized to their label text. One-letter sections keep the square iReal-style look; longer labels such as `Intro` remain readable and searchable in PDF export.
- The pass keeps Rhythm Section and Lead Sheet visual behavior separate from Simple Chord Sheet.

Follow-up chord-fit slice:

- Simple Chord Sheet chords now use the available snapped measure segment as their invisible placement/fit authority instead of sizing only from a text-width box.
- A single downbeat chord keeps the full-measure snap segment, but its visible rendered object is capped to the left-side primary-beat slot so beat `3` remains blank enough for writing the next chord.
- One- and two-chord measures keep a fixed uncompressed chord scale regardless of selected beat positions, so moving the second chord around the bar cannot squeeze or expand either chord.
- Measures with three or more Simple chords lay out the whole chord row from natural chord widths first, then distribute the remaining barline-to-barline measure space as equal gaps around and between chords.
- Three-or-more-chord measures only compress if the full natural-width chord row cannot fit; when they do, they share one measure-level horizontal compression scale across every chord.
- Three-or-more-chord compression is count/content based, not beat-position based: a chord snapped to beat `4` or moved later/earlier in the bar cannot receive a different compression scale from the other chords in that measure.
- Page > Fonts now uses role-based typography profiles instead of one notation-font choice driving every text surface. The typography contract is a matched set plus optional overrides for Chord Font, Header Font, Text / Cue Font, and Notation Symbols.
- `ChartTypographySettings` stores matched set and role overrides while preserving legacy `notationFont` as the notation-symbol role for this sprint. Changing the matched set updates role defaults and the compatible notation-symbol preset; changing a role override affects only that role.
- Simple chord rendering now uses structured `ChordSymbol` tokens instead of one raw display string: root/accidental text, suffix text, music-symbol quality marks, alterations, and slash bass draw as separate runs. Root flats/sharps stay text-style `b/#`; Finale Jazz uses `FinaleJazzTextLowercase`; triangle, diminished, and half-diminished symbols use the resolved symbol face with vector fallback so they do not disappear when a selected chord text face lacks the glyph. The renderer still keeps primary chord size consistent across long and short symbols, keeps all suffixes on one fixed shared suffix scale, horizontally compresses the full drawn chord only when the measure segment is too tight, and vertically centers the chord inside the barline-to-barline measure cell.
- Simple chord typography now has one shared size contract across all chord font roles: 46-point primary text, 54% suffix/symbol text, and a 2-point token gap. The live/export renderer applies one final glyph-fit clamp so a selected font with wider real glyph metrics cannot spill out of the resolved measure segment.
- MuseJazz is bundled from the official MuseScore source with OFL license and SMuFL metadata, alongside the existing Bravura, Petaluma, Leland, and Finale assets.
- The visible rendered chord frame and edit overlay are intentionally separate from the fit segment: the chord can scale like an iReal-style grid cell while the selection/review/move/delete box wraps the displayed chord instead of presenting a segment-sized resize-looking box.
- Simple chord editing no longer exposes a separate move/resize-looking control. In `Select` mode, dragging the selected chord body moves it beat-to-beat; delete remains the only visible chord edit control.
- Simple chord append placement now follows the iReal-style grid rule instead of the handwriting location: the first chord in an empty measure lands on beat `1`, and the second chord lands on beat `3` in common time.
- Simple chord append placement also preserves left-to-right write intent once a measure already has later-beat content: if an existing chord sits on beat `3`, a new chord written to its right lands on the next open beat instead of backfilling beat `1`.
- Moving an existing Simple chord still uses the drag location to snap to the requested beat, while chord size remains fully automatic from the measure, beat segment, and rendered text fit.
- Chord mode is now write-only for rendered chord objects. The failed live pass committed the chord at beat `1`, then the rendered-chord pan path moved it to beat `4`; rendered chord move/delete/review controls are now reserved for `Select` mode so a writing gesture cannot silently become a chord move after auto-render.

Verification:

- Focused SwiftPM `LeadSheetPageLayoutTests` passed with `58` tests and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `417` tests, `36` skipped, and `0` failures.
- Focused simulator layout/PDF verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests -only-testing:iChartTests/PDFChartExporterTests CODE_SIGNING_ALLOWED=NO` passed with `63` tests and `0` failures.
- Simulator smoke verification: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only, and screenshot capture succeeded.
- Follow-up chord-fit focused SwiftPM `LeadSheetPageLayoutTests` passed with `60` tests and `0` failures.
- Follow-up chord-fit full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `419` tests, `36` skipped, and `0` failures.
- Follow-up chord-fit simulator layout/PDF verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests -only-testing:iChartTests/PDFChartExporterTests CODE_SIGNING_ALLOWED=NO` passed with `65` tests and `0` failures.
- Follow-up chord edit-box correction: focused SwiftPM `LeadSheetPageLayoutTests` passed with `60` tests and `0` failures; full SwiftPM verification passed with `419` tests, `36` skipped, and `0` failures; XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests -only-testing:iChartTests/LeadSheetChordEditOverlayGeometryTests -only-testing:iChartTests/PDFChartExporterTests CODE_SIGNING_ALLOWED=NO` passed with `69` tests and `0` failures; `git diff --check` passed; clean simulator reinstall/rebuild and screenshot capture succeeded.
- Follow-up automatic placement/no-resize correction: focused SwiftPM `ChartEditingTests` plus `LeadSheetPageLayoutTests` passed with `146` tests and `0` failures; focused simulator `ChartEditingTests`, `LeadSheetInteractionModeStatePolicyTests`, and Simple chord layout cases passed with `31` tests and `0` failures; full SwiftPM verification passed with `422` tests, `36` skipped, and `0` failures.
- Follow-up beat-3 writing-space and Simple chord typography correction: focused SwiftPM `LeadSheetPageLayoutTests` passed with `61` tests and `0` failures; focused simulator `LeadSheetPageLayoutTests` plus `LeadSheetInteractionModeStatePolicyTests` passed with `87` tests and `0` failures; full SwiftPM verification passed with `423` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded and screenshot inspection showed same-size primary chord text, fixed shared suffix scale, and visible chord boxes wrapping the rendered text instead of occupying the full measure.
- Follow-up later-beat append-order and count-only compression correction: focused SwiftPM `LeadSheetPageLayoutTests` passed with `64` tests and `0` failures after adding the two-chord no-compression-on-move regression and the three-or-more-chords even-slot regression; focused SwiftPM `ChartEditingTests/testSimpleChordSheetAppendAfterExistingLaterBeatKeepsWrittenOrder` passed with `1` test and `0` failures; full SwiftPM verification passed with `427` tests, `36` skipped, and `0` failures; `git diff --check` passed; focused simulator `ChartEditingTests/testSimpleChordSheetAppendAfterExistingLaterBeatKeepsWrittenOrder`, `LeadSheetPageLayoutTests`, and `LeadSheetInteractionModeStatePolicyTests` passed with `89` tests and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only.
- Follow-up current page-font chord rendering: Simple chords use a chord-safe font mapping for the selected Page > Fonts preset, including `FinaleJazzTextLowercase` for Finale Jazz chord symbols. Full SwiftPM verification passed with `427` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only; screenshot capture confirmed the simulator launched.
- Follow-up role-based typography profiles: focused SwiftPM `ChartTypographyResolverTests` passed with `6` tests and `0` failures; focused SwiftPM `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `ChartTypographyResolverTests` passed with `158` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `434` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only and screenshot capture succeeded.
- Follow-up universal Simple chord text size: focused SwiftPM `ChartTypographyResolverTests` passed with `8` tests and `0` failures; focused SwiftPM `LeadSheetPageLayoutTests/testSimpleChordSheetChordFramesUseUniversalTypographyAcrossChordFonts` passed with `1` test and `0` failures; grouped SwiftPM `LeadSheetPageLayoutTests` plus `ChartTypographyResolverTests` passed with `73` tests and `0` failures; full SwiftPM verification passed with `437` tests, `36` skipped, and `0` failures; `git diff --check` passed; clean simulator wipe plus XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only and screenshot capture succeeded.

Verification:

- Focused SwiftPM `LeadSheetPageLayoutTests` passed with `57` tests and `0` failures after adding Simple meter-gutter and Simple meter-change layout coverage.
- Focused SwiftPM `ChartEditingTests/testDraftStoresSelectedLayoutStyleAndDefaults` passed with `1` test and `0` failures.
- Full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `416` tests, `36` skipped, and `0` failures.
- Focused simulator editor verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `24` tests and `0` failures.
- Focused simulator layout verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests CODE_SIGNING_ALLOWED=NO` passed with `57` tests and `0` failures.
- Simulator smoke verification: `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture succeeded.
- Follow-up focused SwiftPM `LeadSheetPageLayoutTests` passed with `57` tests and `0` failures after the inline meter-change correction.
- Follow-up focused SwiftPM `ChartEditingTests/testApplyMeterChangeToNextTimeSignaturePersistsIntoFutureMeasures` passed with `1` test and `0` failures.
- Follow-up full SwiftPM verification: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `416` tests, `36` skipped, and `0` failures.
- Follow-up focused simulator layout verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests CODE_SIGNING_ALLOWED=NO` passed with `57` tests and `0` failures.
- Follow-up focused simulator editor verification: XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `24` tests and `0` failures.
- Follow-up simulator smoke verification: `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only, and screenshot capture succeeded.

## Recommended Sequence

1. Define system layout and measure flow.
2. Implement the smallest model/layout contract for V1 sheet-style system wrapping.
3. Define and implement section labels.
4. Define and implement the first manual roadmap object slice.
5. Define and implement cue text.
6. Run per-style export/readability proof.
7. Return to style-specific refinements:
   - Simple Chord Sheet: dense systems, roadmap/section polish, floating freehand ink polish.
   - Rhythm Section Sheet: below-staff articulation workflow, cue text, eventual rhythm object editing.
   - Lead Sheet: defer to `post-v1/lead-sheet/` after V1.

## Guardrails

- No chord-recognition retuning.
- No OCR expansion.
- No personal handwriting fixture expansion.
- No default symbol-ledger or rhythm diagnostic stream.
- No global recognizer retraining from live passes.
- Keep correction/user-loop behavior local and contextual.
- Keep recognition separate from layout authority.
- Preserve the hard one-measure minimum.

## Current Checkpoint

Simple Chord Sheet row-break/menu controls are implemented locally, default Simple measures now equalize inside each row until manually resized, Measure edit mode shows a Simple-only row-group guide without active vertical drag, Simple freehand ink now floats anywhere on chart paper as measure-attached, movable/deleteable objects, selected freehand drag targets no longer pull the page sideways, and active tool modes only allow parent page scrolling from outside the rendered paper margins. Rhythm Section owns below-measure freehand articulations only. The active toolstrip now defaults to highlighted `Select`, groups Export/appearance/header controls under `Page`, keeps `Free-Hand`, uses a coda-symbol roadmap menu, renames cue entry to `Text`, gives `Chord` a pencil icon, hides legacy/redundant `Edit`, `Jazz`, and `View` tabs, and lets active tools toggle back to `Select`.

Next implementation checkpoint:

- Superseded by Sprint 69 V1 readiness audit and matrix.
- Keep vamp count deferred until there is a clearer V1 need.
