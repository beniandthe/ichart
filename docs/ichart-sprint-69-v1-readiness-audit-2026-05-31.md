# iChart Sprint 69 V1 Readiness Audit

Status: complete locally
Date: 2026-05-31
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/ichart-sprint-source-of-truth.md`
Milestone checkpoint: `4dff695 Finalize Simple chart core authoring loop`
Readiness matrix: `docs/ichart-v1-readiness-matrix-2026-05-31.md`

## Purpose

Sprint 69 is a short recursive closeout and V1 readiness audit after the Simple Chord Sheet core authoring loop became product-credible in live simulator use.

The goal is not to reopen old sprints by default. The goal is to classify all remaining known work into clear buckets, prove the current V1 loop from the app surface, and choose the next polish lane from evidence.

## Classification Buckets

- `Done`: implemented, covered by tests or live pass evidence, and not currently blocking V1.
- `V1 blocker`: must be fixed before a credible V1 release.
- `V1 polish`: improves the release feel but should be ranked against other polish work.
- `Post-V1`: intentionally after the first release.
- `Intentionally deferred`: valid idea, but not active until the user reopens it or new evidence makes it necessary.

## Initial Read

Done or currently product-proven:

- New Chart layout-style setup for the active V1 creation styles, Simple Chord Sheet and Rhythm Section Sheet, while preserving Lead Sheet compatibility in the model/post-V1 archive.
- One-measure minimum across chart creation and editing paths.
- Simple Chord Sheet core loop: create, write chords, auto-render, place on beat grid, move/delete/select, fit chords like a handwritten/iReal-style grid, and preserve writable space.
- Simple manual row flow: menu-owned row breaks, equal default row measures, proportional manual width weighting, row cap, and selected row-group guide.
- Simple chart-area freehand ink as movable measure-attached handwriting.
- Role-based typography with matched sets and per-role overrides.
- MuseJazz bundled from official MuseScore sources with license and SMuFL metadata.
- V1 structured roadmap/cue systems already implemented for active styles: repeat spans, first/second endings, point navigation markers, optional model-only links, cue text, and export/readability coverage.
- Rhythm Section core authoring and V4 rhythm-recognition gate: rhythm lane, chord lane, below-staff freehand articulations, exact-fit commit authority, and fail-closed local ink behavior.
- Lead Sheet planning and current baseline archived under `docs/post-v1/lead-sheet/`.

Likely Sprint 69 audit checks:

- Fresh app install flow: Projects -> New Chart -> Simple Chord Sheet and Rhythm Section Sheet.
- Save/reopen persistence for Simple chord layouts, typography choices, freehand, measure row breaks, roadmap objects, cue text, and exported layout.
- Export proof from real app state, not only layout fixtures.
- Toolstrip consistency after current Page/Measures/Roadmap/Text/Time/Chord/Free-Hand cleanup.
- Rhythm Section visual cohesion and whether it now lags Simple in professional polish.
- Any stale docs that still imply the old Simple above/below freehand lane, Lead Sheet as a V1 target, or generic shared layout behavior.

## Audit Findings So Far

- No hidden V1 code/doc blocker is confirmed by the first audit pass.
- Simple Chord Sheet persistence needed a richer proof than the generic snapshot round trip. Sprint 69 added a repository test that saves and reloads a V1-shaped Simple chart with role typography, a manual row break, manual width, roadmap objects, cue text, chart-area freehand ink, and rendered chords.
- The readiness matrix classifies the current implementation surface and keeps the next decision tied to live app evidence.
- The release gates were narrowed to fresh app-surface save/reopen/export checks plus a clean simulator build/run, then closed enough for the audit through regression proof, clean simulator build/run, and the final green Rhythm Section app-surface pass.
- If those passes do not expose a blocker, the highest-value next polish lane is Rhythm Section visual cohesion.
- Rhythm Section visual cohesion first pass is now implemented without changing rhythm recognition authority: section labels reserve a rehearsal-mark area above the chord lane, the renderer draws Rhythm Section section marks as compact boxed rehearsal labels, staff lines read slightly darker, cue text/roadmap text/point markers/ending brackets are stronger, and the chord/staff/below-staff articulation lanes stay separate.
- The first fresh Rhythm Section live pass exposed two issues: the old small header meter still appeared under the title, and rhythm ink did not appear to reach the recognizer/render loop reliably. The header-meter issue was fixed as a scoped layout regression. The rhythm non-render issue is now classified as a live-pipeline audit item rather than a slash/rest ordering bug.
- The upcoming Rhythm Section live pass should run in the largest native iPad app surface available. The app now declares full-screen iPad presentation and all iPad orientations, the editor canvas sizes from the actual viewport, Simple/Rhythm paper widths expand to native bounds, and Rhythm Section staff rows stretch packed measures across the usable row. Lead Sheet keeps the legacy capped page policy until post-V1.
- Follow-up Rhythm Section recognition audit found and fixed the clear whole-note non-render without opening a new live pass. The issue was an older whole-measure manual-review guard surfacing as unread feedback after confirmation UI removal; V4 now auto-applies strong single-crop whole-note reads while preserving the conservative guard for whole rests and tiny whole-like marks.
- The whole-note follow-up was tightened to the direct v1 rule after live use showed the classifier was still too precious: in the rhythm lane, a no-stem closed oval/circle above the tiny-mark threshold is a whole note. Literal closed-circle, compact oval, and regular whole-note cases now commit as `.whole`; tiny low-information marks and whole rests remain conservative.
- App-surface cohesion audit tightened the V1 creation and library contracts: the New Chart picker now exposes only Simple Chord Sheet and Rhythm Section Sheet through `ChartLayoutStyle.v1NewChartOptions`; Lead Sheet remains decodable/openable as a compatibility/post-V1 style. Library summaries now hide key names for styles whose setup hides key, while Lead Sheet summaries still include key.
- Rhythm Section persistence now has a V1-shaped repository round-trip proof covering rhythm maps with source drawing data, uncommitted raw rhythm ink, chords, cue text, roadmap objects, below-measure freehand articulations, typography, and selected-chart state.
- The editor save path has a direct store-level proof: mutating an element inside `ChartLibraryStore.charts`, the same value path used by `AppRootView`'s editor binding, triggers snapshot persistence with the edited chart.
- The final fresh Rhythm Section app-surface pass was green. The pass covered the professional staff layout, suppressed header meter, native full-screen surface, rhythm recognition for the v1 live set including slashes, quarter notes, whole-note circles, two half notes, and beamed eighths, chord snapping with and without rhythm maps, below-staff freehand articulation, structured cue/roadmap/repeat objects, and save/reopen behavior.
- Sprint 69 closes with no confirmed V1 blocker. The next lane should be Sprint 70 App Functionality and UX/UI, starting with project/library UX, export/share confidence, and app-level tool/menu polish.

## Verification Checkpoint

- `git diff --check` passed.
- Focused SwiftPM audit group passed with `165` tests and `0` failures: `FileChartRepositoryTests`, `PDFChartExporterTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, `ChartTypographyResolverTests`, `LeadSheetInteractionModeStatePolicyTests`, and `RhythmicNotationQuantizerTests`.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `438` tests, `36` skipped, and `0` failures.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only.
- Screenshot capture succeeded and showed the app launched to Projects.
- Rhythm Section visual cohesion focused SwiftPM slice passed: `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests/testRhythmSection` with `10` tests and `0` failures.
- After the Rhythm Section visual cohesion first pass, full SwiftPM verification passed with `443` tests, `36` skipped, and `0` failures.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture showed the app launched to Projects.
- After the Rhythm Section header-meter fix, XcodeBuildMCP focused simulator `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures while the live-pipeline audit remained open.
- After the same checkpoint, full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `443` tests, `36` skipped, and `0` failures.
- `git diff --check` passed after the same header/doc checkpoint.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after a fresh simulator app uninstall/reinstall with the existing headermap warning only. A new Rhythm Section chart launched from the New Chart picker and screenshot inspection confirmed the old small header `4/4` is gone while the first-system time signature remains before the staff.
- Native viewport/orientation checkpoint: focused `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter 'LeadSheetPageLayoutTests|ProjectConfigurationTests'` passed with `70` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `447` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only. The current desktop Simulator session had manual orientation menu items disabled, so the next fresh live pass should still verify visual portrait/landscape flipping.
- Whole-note checkpoint: XcodeBuildMCP focused simulator `test_sim` for `RhythmicNotationQuantizerTests` passed with `80` tests, `1` optional replay skip, and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `200` tests, `1` optional replay skip, and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `450` tests, `36` skipped, and `0` failures; `git diff --check` passed.
- Direct circle whole-note checkpoint: XcodeBuildMCP focused simulator `test_sim` for direct circle, compact oval, regular whole note, and tiny-mark guard passed with `4` tests and `0` failures; XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `83` tests, `1` optional replay skip, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only.
- V1 creation/library checkpoint: focused SwiftPM `ChartLibraryStoreTests` and `FileChartRepositoryTests` passed with `18` tests and `0` failures, then focused SwiftPM `ChartLibraryStoreTests` passed with `14` tests and `0` failures after the editor-binding persistence proof; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `455` tests, `36` skipped, and `0` failures. XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only. XcodeBuildMCP focused simulator `test_sim` for `ChartLibraryStoreTests` passed with `13` tests and `0` failures, and the previous combined focused simulator run for `ChartLibraryStoreTests` plus `FileChartRepositoryTests` passed with `17` tests and `0` failures.
- Final app-surface checkpoint: the user-reported fresh Rhythm Section live pass was green for layout, core rhythm recognition, chord snapping, below-staff freehand articulation, structured chart objects, and save/reopen behavior.

## Scope

This sprint may update docs, add audit checklists, run tests, run fresh simulator passes, and make tiny fixes only when they are clearly audit-found regressions.

Closeout: complete locally. Further app functionality and UX/UI work should start in the next sprint lane.

Larger implementation should wait until the audit says which lane is next.

## Non-Goals

- No chord-recognition score retuning.
- No OCR expansion.
- No personal handwriting fixture expansion.
- No default diagnostics stream.
- No Rhythm Section manual row/system breaks unless the audit upgrades them to V1 blockers.
- No rhythm-object editing.
- No vamp count.
- No handwritten recognition for section labels, cue text, or articulations.
- No Lead Sheet feature expansion before V1.

## Step-by-Step Plan

1. Preserve the Simple core-loop milestone remotely. Status: pushed at `4dff695`.
2. Audit current sprint docs and active code surfaces against the V1 classification buckets.
3. Run baseline verification:
   - `git status --short --branch`
   - `git diff --check`
   - focused tests for chart editing, layout, typography, interaction policy, rhythm quantizer, and PDF export
   - full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile`
4. Run a fresh simulator pass for Simple Chord Sheet:
   - create a new Simple chart
   - write one-chord, two-chord, and three-or-more-chord measures
   - move chords beat-to-beat
   - change chord font role
   - add row break, cue text, repeat/ending/point marker, and freehand object
   - save/reopen and export
   - Status: product-proven through the Sprint 68 Simple core-loop milestone and Sprint 69 persistence/export regression gates.
5. Run a fresh simulator pass for Rhythm Section Sheet:
   - create a new Rhythm Section chart
   - verify native full-screen sizing in portrait and landscape if Simulator orientation controls are available
   - write slashes, quarter-note rhythm phrases, and beamed eighths
   - add chords with no-rhythm beat fallback and rhythm-slot snapping
   - add below-staff freehand articulation, cue text, and roadmap objects
   - save/reopen and export
   - Status: final fresh app-surface pass reported green.
6. Produce a V1 readiness matrix with recommendations for the next implementation sprint.
   - Status: matrix created at `docs/ichart-v1-readiness-matrix-2026-05-31.md`.

## Acceptance Criteria

- The milestone commit is pushed.
- Source-of-truth docs name Sprint 69 as closed and Sprint 70 App Functionality and UX/UI as the next candidate lane.
- Old Sprint 68 work is marked as complete enough for the current milestone, with remaining items intentionally classified.
- The next work lane is chosen from evidence, not from stale backlog momentum.
- Closeout status: met locally; next work lane is Sprint 70 App Functionality and UX/UI.
