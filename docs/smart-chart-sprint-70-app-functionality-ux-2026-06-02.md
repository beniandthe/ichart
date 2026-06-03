# Smart Chart Sprint 70 App Functionality And UX/UI

Status: opened locally
Date: 2026-06-02
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

Sprint 70 starts after the Sprint 69 V1 readiness audit closed with no confirmed V1 blocker.

The goal is to turn the proven Simple Chord Sheet and Rhythm Section Sheet authoring core into a clearer app experience. The broad lane remains project/library UX, export/share confidence, save/reopen confidence, and tool/menu affordance polish. The first functionality slice was chart-wide chord transposition, the second slice added typed-or-handwritten header entry, and the third slice hardens live ink responsiveness.

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

## Verification

- Focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests'`
- Result: `165` tests, `0` failures.
- Focused header SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests|LeadSheetInteractionModeStatePolicyTests|FileChartRepositoryTests'`
- Result: `174` tests, `0` failures.
- Focused passive ink SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter 'LeadSheetInteractionModeStatePolicyTests|ChartEditingTests|LeadSheetPageLayoutTests|FileChartRepositoryTests'`
- Result: `174` tests, `0` failures.
- Full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `467` tests, `36` skipped, `0` failures.
- `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture completed after launch.

## Guardrails

- No chord-recognition score retuning.
- No OCR expansion.
- No personal handwriting fixture expansion.
- No default diagnostics stream.
- No key-dependent transposition requirements for Simple Chord Sheet or Rhythm Section Sheet.
- Header handwriting is raw page ink, not OCR or recognized text.
- Passive ink responsiveness does not change chord/rhythm recognition authority.
- Lead Sheet remains post-V1 beyond compatibility behavior already present in the model.

## Next Candidate Slices

1. Project/library UX: rename, duplicate, delete, clearer metadata, less developer-facing library behavior.
2. Export/share UX: obvious export flow, PDF preview confidence, file naming, app-created export proof.
3. Save/reopen confidence: visible but quiet saved-state behavior.
4. Toolstrip/menu affordances: naming, hit-targets, active-menu state polish.
