# Smart Chart Sprint 66 Profile-Driven Structure Defaults

Status: complete locally; setup/profile, Simple layout/free-hand capture/editing, first Lead Sheet key-signature baseline, and mixed pitched-note/rest proof verified
Date: 2026-05-27
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

Supersession note: the Simple Chord Sheet above/below free-hand lane model captured here is historical. Sprint 68 replaces it with measure-attached chart-area freehand objects; keep this file as Sprint 66 evidence, but use the source-of-truth file for current behavior.

## Purpose

Sprint 66 lets the Sprint 65 layout-profile contracts begin shaping newly created chart structure and setup policy, then takes the first tightly scoped Simple Chord Sheet renderer and above/below free-hand steps.

The first target was chart structure/setup defaults: key visibility, clef options, initial measure count, preferred measures per system, system spacing mode, and beat-grid defaults. After the user definitions landed, the sprint added the smallest Simple Chord Sheet visual branch: blank bar-to-bar measure space without the staff-led lead-sheet symbols. After the user clarified that free-hand symbols must live above or below the chord lane only, the sprint added the first Simple free-hand object capture/render/edit checkpoint.

Implementation should remain limited to safe setup/profile defaults, the verified Simple blank-measure skeleton, and Simple above/below free-hand object capture/render/select/move/delete. Do not start pitched-note engraving, free-hand symbol resizing, semantic ink classification, rhythm snapping, or broad per-style renderer rewrites until those product slices are explicitly scoped.

## User Definition Gate

The actual starting structure for each `ChartLayoutStyle` is now defined:

- `Simple Chord Sheet`: defined below.
- `Rhythm Section Sheet`: defined below.
- `Lead Sheet`: defined below.

Also define what should stay common across all layouts: title/header setup, meter setup, transposition, export route for now, and any shared authoring controls.

Shared invariant: every chart layout starts with at least one measure. The starting-measures control must not offer `0`, and model defaults must clamp any accidental zero value back to `1`.

## Simple Chord Sheet Definition

Confirmed Sprint 66 direction:

- New chart setup for this style should not ask for a key.
- Setup should ask for starting time and starting measures.
- If the user does not choose extra measures, the chart defaults to one measure. Zero-measure charts are not allowed.
- Measures render as empty white space from barline to barline.
- Measures can be added, shifted, compressed, and enlarged.
- The chord writing zone is the open blank space inside each measure between barlines.
- Free-hand drawing zones live above and below the blank measure space.
- Free-hand symbols are not created in the chord lane; the chord lane stays separate for chord authoring.
- Free-hand marks are not rhythm-snapped, but each free-hand symbol must become editable and moveable like chord objects.
- The layout is not necessarily rhythm-aware, but it is base-meter-aware for chord placement.
- Chords written in the white measure space render and snap to the denominator rhythm base.
- Users can free-hand rhythms, ties, and articulations above and below the chords.

Sprint 66 implementation boundary:

- Implemented the model profile contract for `Simple Chord Sheet` starting measure count `1`.
- Implemented setup policy so this layout omits key and clef setup, but includes time-signature and starting-measure setup.
- Implemented the first renderer skeleton: no key header text, no clef, no leading time-signature glyph, no staff lines, no slash/rhythm note rendering, chord band inside the blank measure body, and normal barline boundaries.
- Implemented the first free-hand symbol object checkpoint: above/below lanes only, measure-anchored raw ink objects, normalized lane-relative frames, editor/PDF rendering, and stroke-start capture that ignores the chord lane.
- Implemented the first free-hand symbol editing checkpoint: tap selection, lane-constrained drag/move inside the original above/below lane, and delete controls for selected symbols.
- Do not implement free-hand symbol resizing, semantic classification, or rhythm snapping until the next Simple Chord Sheet interaction/design slice is explicitly scoped.

## Rhythm Section Sheet Definition

Confirmed Sprint 66 direction:

- This layout is the current basic chart workflow Smart Chart has been building so far.
- No new behavior is required right now beyond designating the current workflow as `Rhythm Section Sheet`.
- Key should be taken out officially for this layout for now. Treat key as legacy and leave the door open to revisit it later.
- Setup should ask for starting time and starting measures.
- Measures are real measures with staff lines.
- Rhythms are written between barlines and snap to the measure.
- Chords are written above the staff in the chord writing lane.
- Chords snap to a rhythm in the measure and can be moved to other rhythms.
- If a measure has no written rhythm yet, a chord automatically snaps at beat `1`.

Sprint 66 implementation boundary:

- Implemented setup policy so this layout omits key and clef setup, but includes time-signature and starting-measure setup.
- Implemented profile beat-grid and spacing defaults for new structure.
- Do not add renderer changes or rhythm-section-specific structure rewrites until that workflow refinement is explicitly scoped.

## Lead Sheet Definition

Confirmed Sprint 66 direction:

- This will be the most difficult layout style, so start small and iterate after the other sheet styles are more solid.
- Setup should ask for key, time signature, starting measures, and clef.
- Clef choices are treble and bass only.
- The chart should populate actual measures with staff lines.
- Before the first measure, the layout should show key-signature flat/sharp objects on the correct staff lines plus the time signature.
- Ledger lines are out of scope for now.
- Eventually, the user should be able to write actual note/rhythm content into a measure and have it snap to both rhythm and staff-line pitch.
- Chords can still be written above the measure in the usual chord writing lane.

Sprint 66 implementation boundary:

- Safe to keep the current lead-sheet-like staff/page profile as the Lead Sheet baseline.
- Implemented setup policy so Lead Sheet requires key and clef setup while Simple Chord Sheet and Rhythm Section Sheet do not.
- Implemented Lead Sheet clef options as `Treble` and `Bass` only.
- Implemented the first Lead Sheet key-signature/clef rendering baseline after the Rhythm Section detour: treble/bass clef setup chooses the rendered clef glyph, and transposed key-signature accidentals appear before the first measure's time signature.
- The first dedicated Lead Sheet note-entry slice is now implemented as a narrow proof: accepted note/rest rhythm commits can snap note-capable slots to clamped in-staff pitched-note events, including beamed-eighth groups with separate pitch anchors, with no ledger lines and the chord lane unchanged. Every note-capable slot must have exactly one pitch anchor before the phrase can commit.
- Do not implement clef-specific named pitch mapping, ledger-line policy beyond "none", individual note editing, or full lead-sheet engraving until those slices are explicitly scoped.

## Implemented Slice

- `ChartLayoutProfile` defines setup policy for key visibility, time-signature visibility, starting-measure visibility, and clef options.
- `ChartSetupSheetView` follows the selected layout style's setup policy.
- `Chart.defaultClef` is persisted and decodes legacy charts as treble.
- Initial setup stores the selected clef and creates `max(1, startingMeasureCount)` measures.
- Initial setup uses the selected layout style's spacing mode and beat-grid default.
- Appended/open measures and `Chart.blank` use the selected layout style's beat-grid default.
- `Chart.blank` still clamps requested measure count to at least `1`.
- Preferred measures per system remains a profile contract only; executable regrouping is deferred to avoid changing current rhythm-section layout behavior before that slice is designed.
- `LeadSheetPageLayoutEngine` now has a scoped Simple Chord Sheet branch that removes staff-led visuals and uses the measure body as the chord-writing band.
- Editor and PDF rendering skip Simple open-measure hint marks so Simple measures remain blank barline-to-barline spaces.
- `FreehandSymbol` persists Simple-only measure-anchored raw ink objects in above/below lanes.
- Simple free-hand mode shows above/below lane affordances, groups strokes by the lane where each stroke starts, stores accepted strokes as `FreehandSymbol` objects, and clears the temporary drawing canvas after capture.
- Editor and PDF rendering draw saved Simple free-hand symbols from their lane-relative frames.
- Simple free-hand mode supports selecting saved `FreehandSymbol` objects, moving selected objects within their original lane, and deleting selected objects.
- `ChartLayoutProfile` owns whether user-facing rhythm-note editing is available; Rhythm Section and Simple keep it off for now, while Lead Sheet can use the existing note/rhythm edit surface.
- `ChartLayoutProfile` also owns freehand symbol ink availability: Simple and Rhythm Section have active freehand symbol scopes through their lane policies, while Lead Sheet has no freehand page-ink scope for now.
- `ChartLayoutProfile` owns rhythmic-notation ink availability: Simple Chord Sheet has no rhythmic-notation active ink scope, while Rhythm Section and Lead Sheet keep rhythm-notation entry available.
- Lead Sheet renders the selected treble/bass clef, reserves key-signature width before the first measure, and places sharp/flat glyphs for the transposed document key before the time signature.
- Lead Sheet now has the first mixed pitched-note/rest proof: accepted rhythm ink can create clamped in-staff `LeadSheetPitchedNoteEvent` objects for note-capable slots through V4 visual note anchors, including separate anchors for beamed eighths, and the layout renders those events as pitched noteheads while preserving rest glyphs on rest slots. Partial or duplicate pitch coverage rejects the commit instead of falling back to placeholder slash notation.

## Step-By-Step Plan

0. Complete the user definition gate. Status: complete.
   - Broad per-style renderer/system-layout work remains paused beyond safe setup defaults and the scoped Simple blank-measure skeleton.
   - Record the selected system/layout behavior in this file and the source-of-truth doc.

1. Apply profile defaults at initial chart setup. Status: complete for setup policy and initial measure creation.
   - Use the selected layout style's setup policy for key visibility, time-signature visibility, starting-measure visibility, and clef options.
   - Use the selected layout style's initial measure count when a draft chart becomes a blank page.
   - Preserve existing lead-sheet behavior unless the profile explicitly says otherwise.

2. Keep preferred system grouping as a profile contract for now. Status: deferred by design.
   - Do not change rebuild chunking until the per-style renderer/layout slice is scoped.
   - Keep existing lead-sheet grouping behavior on the current renderer path.

3. Apply safe measure-level defaults. Status: complete.
   - Use the profile's default beat-grid preset for newly created measures.
   - Use the profile's default system spacing mode for newly created systems.

4. Verify proportionally. Status: complete for this slice.
   - Focused model/editing tests for each layout style's initial structure.
   - Full SwiftPM suite after focused tests pass.
   - iOS simulator compile if app-target coverage is touched.

5. Implement the smallest Simple Chord Sheet layout branch. Status: complete for blank-measure skeleton.
   - Hide key/staff/clef/leading time-signature visuals for Simple Chord Sheet.
   - Put the chord-writing band inside the blank measure body.
   - Keep rhythm-section refinement and richer lead-sheet melody/editing systems deferred.

6. Implement the first Simple free-hand symbol object checkpoint. Status: complete for capture/render/edit.
   - Store Simple free-hand symbols as measure-anchored raw ink objects in above/below lanes only.
   - Render saved free-hand symbols in the editor and PDF export.
   - Do not allow free-hand symbol capture in the chord lane.
   - Select saved symbols, move them within their original above/below lane, and delete selected symbols.
   - Keep resizing, semantic classification, and rhythm snapping deferred.

## Guardrails

- No recognition, parser, compendium, OCR, symbol-ledger, or fixture changes.
- No broad layout-specific renderer/export rewrite beyond the scoped Simple Chord Sheet blank-measure skeleton and above/below free-hand symbol rendering/editing.
- No full notation, melody entry, playback, or broad editor rewrite.
- No layout-changing UI after chart creation until conversion rules exist.
- Keep existing saved chart decode compatibility intact.

## Acceptance Criteria

- Layout profiles define key, time-signature, starting-measure, and clef setup policy.
- New draft setup uses layout-profile initial measure count.
- No layout can offer or create a zero-measure chart.
- New systems use layout-profile spacing mode.
- Preferred measures per system is pinned in profile tests but remains deferred as executable regrouping.
- New measures use layout-profile beat-grid defaults.
- `Lead Sheet` remains compatible with the current renderer path and four-measure system grouping while rendering the selected clef and first-system key signature.
- `Lead Sheet` can store and render pitched-note events snapped to in-staff positions without ledger lines, including mixed note/rest rhythm phrases.
- `Simple Chord Sheet` renders a blank barline-to-barline measure body without staff/key/clef/leading-time-signature visuals.
- `Simple Chord Sheet` has no rhythmic-notation ink scope until a Simple-specific rhythm/freehand semantics slice is designed.
- Simple free-hand symbols persist only in the above/below measure lanes and stay separate from the chord lane.
- Simple free-hand symbols can be selected, moved within their original lane, and deleted without enabling chord-lane free-hand capture.
- Tests pin all three layout families.

## Verification Log

- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `35` tests, `0` failures after updating the Simple Chord Sheet profile to default to one starting measure.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `336` tests, `36` skipped, `0` failures after adding setup-policy contracts for key/time/starting-measure/clef behavior.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `36` tests, `0` failures after pinning the one-measure minimum invariant for layout defaults and blank charts.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `38` tests, `0` failures after wiring initial setup to starting-measure count, clef persistence, profile spacing, and profile beat-grid defaults.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `339` tests, `36` skipped, `0` failures after the setup/profile implementation.
- `xcodegen generate` completed; XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO` passed for the `SmartChart` scheme on the configured iPad simulator with one existing headermap warning and no errors.
- XcodeBuildMCP live simulator smoke launched `SmartChart`, opened the New Chart picker, verified Simple Chord Sheet setup hides Key/Clef and defaults Starting Measures to `1`, verified Rhythm Section Sheet setup hides Key/Clef and defaults Starting Measures to `8`, verified Lead Sheet setup shows Key and Clef with Starting Measures defaulting to `4`, and confirmed the library summaries after creation showed Simple `1` measure, Rhythm `8` measures, and Lead Sheet `4` measures.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `30` tests, `0` failures after adding the Simple blank-measure renderer layout checks plus Rhythm/Lead header/staff guard checks.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `342` tests, `36` skipped, `0` failures after the Simple layout branch.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed for the `SmartChart` scheme on the configured iPad simulator with one existing headermap warning and no errors.
- XcodeBuildMCP live simulator smoke opened a saved Simple Chord Sheet and confirmed the editor renders `4/4` only in the header area, no key text, no clef, no leading time-signature glyph, no staff lines, and one blank barline-to-barline measure space.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `40` tests, `0` failures after adding Simple-only `FreehandSymbol` persistence and guard tests.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `31` tests, `0` failures after adding above/below lane geometry and free-hand symbol layout resolution checks.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `345` tests, `36` skipped, `0` failures after the Simple free-hand symbol capture/render checkpoint.
- XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO` passed for the `SmartChart` scheme on the configured iPad simulator with one existing headermap warning and no errors.
- XcodeBuildMCP live simulator smoke opened a saved Simple Chord Sheet, entered `Free-Hand`, showed above/below lane affordances around the blank measure, drew one upper-lane stroke, tapped `Done`, and confirmed the stroke persisted as rendered ink above the chord lane.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `42` tests, `0` failures after adding Simple free-hand symbol move/delete mutations and open-measure retention coverage.
- XcodeBuildMCP `test_sim -only-testing:SmartChartTests/LeadSheetFreehandSymbolEditOverlayGeometryTests CODE_SIGNING_ALLOWED=NO` passed with `4` tests, `0` failures after adding Simple free-hand selection/control/clamping geometry checks.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `347` tests, `36` skipped, `0` failures after the Simple free-hand selection/move/delete checkpoint.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed for the `SmartChart` scheme on the configured iPad simulator with one existing headermap warning and no errors.
- XcodeBuildMCP live simulator smoke opened a saved Simple Chord Sheet, entered `Free-Hand`, selected a saved upper-lane mark, deleted it, re-created/selected a new upper-lane mark, and moved it right inside the above-measure lane.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `35` tests, `0` failures after adding Lead Sheet key-signature layout, bass-clef position, and Rhythm Section no-key-signature guards.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `176` tests and `0` failures after the Lead Sheet key-signature baseline and V4 render-comparison acceptance coverage.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `356` tests, `36` skipped, and `0` failures after the Lead Sheet key-signature baseline.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only after the Lead Sheet key-signature baseline.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `84` tests and `0` failures after the Lead Sheet pitched-note model/layout baseline.
- XcodeBuildMCP focused `test_sim` for Lead Sheet pitched-note finalization passed with `2` tests and `0` failures, and XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `76` tests and `0` failures after V4 visual note anchors and stem-down quarter protection.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `182` tests and `0` failures after the Lead Sheet pitched-note baseline.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `360` tests, `36` skipped, and `0` failures after the Lead Sheet pitched-note baseline.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only after the Lead Sheet pitched-note baseline.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `86` tests and `0` failures after adding mixed Lead Sheet note/rest commit and layout coverage.
- XcodeBuildMCP focused `test_sim` for mixed Lead Sheet note/rest finalization passed with `1` test and `0` failures; XcodeBuildMCP focused `test_sim` for beamed-eighth pitch-anchor finalization passed with `1` test and `0` failures; XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `186` tests and `0` failures after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice and again after the pitch-coverage guard.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures after tightening Lead Sheet pitch coverage to require every note-capable rhythm slot.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures after moving user-facing rhythm-note editing availability into `ChartLayoutProfile`; grouped simulator `test_sim` passed with `186` tests and `0` failures.
- XcodeBuildMCP focused `test_sim` for `LeadSheetInteractionModeStatePolicyTests` and `ChartEditingTests` passed with `66` tests and `0` failures after moving freehand symbol ink availability into `ChartLayoutProfile`; the grouped simulator gate passed with `187` tests and `0` failures.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures after moving rhythmic-notation ink availability into `ChartLayoutProfile`.
- XcodeBuildMCP focused `test_sim` for `LeadSheetInteractionModeStatePolicyTests` and `ChartEditingTests` passed with `67` tests and `0` failures after guarding Simple Chord Sheet from rhythmic-notation ink scope; the grouped simulator gate passed with `188` tests and `0` failures.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the rhythmic-notation availability guard.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only after the rhythmic-notation availability guard.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice and after the pitch-coverage guard doc audit.
