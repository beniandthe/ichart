# iChart Sprint Source Of Truth

Status: active living sprint document
Created: 2026-05-20
Repo: `beniandthe/ichart`
Active branch: `codex/rhythm-section-core-authoring`
Active baseline commit: `1b792df Merge pull request #4 from beniandthe/codex/symbol-ledger-recognition`
Trusted checkpoint reference: `c60bb46 Polish altered chord recognition trust`

## Purpose

This document is the working source of truth for iChart sprint recovery and forward planning.

Use it before starting recognition, editor, simulator, or architecture work. After each sprint completes, update this file in place: move the finished sprint into the completed log, record verification evidence, and define the next sprint only after discussing the next priority.

If this document conflicts with older recognition or architecture planning docs, this document wins for current sprint execution. `docs/core-design-document.md` still wins for product intent.

## Current Baseline

The active app runtime implementation state is the merged recovery branch from PR [#4](https://github.com/beniandthe/ichart/pull/4):

- branch: `main`
- merge checkpoint: `1b792df Merge pull request #4 from beniandthe/codex/symbol-ledger-recognition`
- runtime checkpoint: `72cd12e Close sprint eight semantic contextualizer extraction`
- product/editor checkpoint: `c76a356 Close sprint ten product editor audit`
- PR review follow-through checkpoint: `66dc5d2 Document chord ink clear decision`
- PR readiness checkpoint: `61caeb9 Open sprint nine merge readiness`
- previous runtime checkpoint: `a738ed3 Close sprint seven text variant extraction`
- implementation state: recognition recovery, product/editor polish audit, PR review follow-through, PR [#4](https://github.com/beniandthe/ichart/pull/4) merge, Sprint 12 post-merge app audit, Sprint 13 local hygiene/product smoke, Sprint 14 editor boundary cleanup, Sprint 15 recognition corpus debloat, Sprint 16 app-shell debloat, Sprint 17 working Library debloat, Sprint 18 chord sheet extraction, Sprint 19 rhythm confirmation extraction, Sprint 20 chord edit overlay geometry extraction, Sprint 21 measure resize geometry extraction, Sprint 22 active ink-scope extraction, Sprint 23 saved ink renderer extraction, Sprint 24 active ink persistence extraction, Sprint 25 chord ink image renderer extraction, Sprint 26 interaction targeting extraction, Sprint 27 note-selection lasso targeting extraction, Sprint 28 chord ink recognition targeting extraction, Sprint 29 chord recognition timing extraction, Sprint 30 chord recognition scheduling extraction, Sprint 31 rhythmic notation finalization policy extraction, Sprint 32 interaction-mode state policy extraction, Sprint 33 chord recognition request-state extraction, Sprint 34 editor/recognition execution audit, Sprint 35 recognition-session boundary design, Sprint 36 recognition generalization policy reset, Sprint 37 recognition-session boundary implementation, Sprint 38 recognition-session OCR gate test hardening, Sprint 39 bounded renderer product proof, Sprint 40 visual renderer QA, Sprint 41 writing-to-render commit contract, Sprint 42 writing-to-render readiness QA, Sprint 43 real Pencil field-test evidence, Sprint 44 renderer/iPad export availability, Sprint 45 post-export field-test validation, Sprint 46 recognition latency/trust triage, Sprint 47 confidence/performance split triage, Sprint 48 persistent timing telemetry, Sprint 49 flat-root candidate availability, Sprint 50 post-stroke responsiveness, Sprint 51 real-life polish, Sprint 52 chord confirmation/user loop UX, Sprint 53 validation speed, Sprint 54 confirmation UX polish, Sprint 55 chord-first product polish, Sprint 56 chord field validation, Sprint 57 chord placement/edit loop, Sprint 58 wrong render recovery, Sprint 59 confirmation/direct-input polish, Sprint 60 general candidate availability hardening, Sprint 61 raster/render handoff polish, Sprint 62 chord-first release-candidate pass, Sprint 63 chart layout goals, Sprint 64 New Chart layout-style chooser, Sprint 65 layout-profile contracts, Sprint 66 profile-driven structure defaults, Sprint 67 Rhythm Section current workflow lock, Rhythm Section side sprint core authoring, Sprint 68 chart-structure/product-loop work, Sprint 69 V1 readiness audit, and Sprint 70 App Functionality and UX/UI are complete and pushed on `codex/rhythm-section-core-authoring`; Sprint 71 V1 Product Readiness and Release Hardening is open locally.
- supporting audit: `docs/repo-github-recognition-audit-2026-05-20.md`
- Sprint 12 audit artifact: `docs/ichart-post-merge-app-audit-2026-05-23.md`
- Sprint 34 audit artifact: `docs/ichart-editor-recognition-execution-audit-2026-05-24.md`
- Sprint 35 design artifact: `docs/ichart-recognition-session-boundary-design-2026-05-25.md`
- Sprint 42 readiness artifact: `docs/ichart-real-life-testing-readiness-2026-05-25.md`
- Sprint 43 field-test log: `docs/ichart-real-pencil-field-test-log-2026-05-26.md`
- Sprint 45 post-export field-test log: `docs/ichart-post-export-field-test-log-2026-05-26.md`
- Sprint 46 latency triage artifact: `docs/ichart-recognition-latency-triage-2026-05-26.md`
- Sprint 46 latency repeat log: `docs/ichart-sprint-46-latency-repeat-log-2026-05-26.md`
- Sprint 47 confidence/performance triage artifact: `docs/ichart-sprint-47-confidence-performance-triage-2026-05-26.md`
- Sprint 47 timing capture log: `docs/ichart-sprint-47-timing-capture-log-2026-05-26.md`
- Sprint 48 persistent timing telemetry artifact: `docs/ichart-sprint-48-persistent-timing-telemetry-2026-05-26.md`
- Sprint 49 flat-root candidate availability artifact: `docs/ichart-sprint-49-flat-root-candidate-availability-2026-05-26.md`
- Sprint 50 post-stroke responsiveness artifact: `docs/ichart-sprint-50-post-stroke-responsiveness-2026-05-26.md`
- Sprint 51 real-life polish artifact: `docs/ichart-sprint-51-real-life-polish-2026-05-26.md`
- Sprint 52 chord confirmation/user loop artifact: `docs/ichart-sprint-52-chord-confirmation-user-loop-2026-05-26.md`
- Sprint 53 validation speed artifact: `docs/ichart-sprint-53-validation-speed-2026-05-26.md`
- Sprint 54 confirmation UX polish artifact: `docs/ichart-sprint-54-confirmation-ux-polish-2026-05-26.md`
- Sprint 55 chord-first product polish artifact: `docs/ichart-sprint-55-chord-first-product-polish-2026-05-26.md`
- Sprint 56 chord field validation artifact: `docs/ichart-sprint-56-chord-field-validation-2026-05-27.md`
- Sprint 56 repeat validation log: `docs/ichart-sprint-56-repeat-validation-log-2026-05-27.md`
- chord-first side-sprint lane: `docs/ichart-chord-first-side-sprints-2026-05-27.md`
- Sprint 57 chord placement/edit loop artifact: `docs/ichart-sprint-57-chord-placement-edit-loop-2026-05-27.md`
- Sprint 58 wrong render recovery artifact: `docs/ichart-sprint-58-wrong-render-recovery-2026-05-27.md`
- Sprint 59 confirmation/direct-input polish artifact: `docs/ichart-sprint-59-confirmation-direct-input-polish-2026-05-27.md`
- Sprint 60 general candidate availability artifact: `docs/ichart-sprint-60-general-candidate-availability-hardening-2026-05-27.md`
- Sprint 61 raster/render handoff polish artifact: `docs/ichart-sprint-61-raster-render-handoff-polish-2026-05-27.md`
- Sprint 62 chord-first release-candidate pass artifact: `docs/ichart-sprint-62-chord-first-release-candidate-pass-2026-05-27.md`
- Sprint 63 chart layout goals artifact: `docs/ichart-sprint-63-chart-layout-goals-2026-05-27.md`
- Sprint 64 New Chart layout-style chooser artifact: `docs/ichart-sprint-64-new-chart-layout-style-chooser-2026-05-27.md`
- Sprint 65 layout-profile contracts artifact: `docs/ichart-sprint-65-layout-profile-contracts-2026-05-27.md`
- Sprint 66 profile-driven structure defaults artifact: `docs/ichart-sprint-66-profile-driven-structure-defaults-2026-05-27.md`
- Sprint 67 Rhythm Section current workflow lock artifact: `docs/ichart-sprint-67-rhythm-section-current-workflow-lock-2026-05-27.md`
- Rhythm Section side sprint plan artifact: `docs/ichart-rhythm-section-side-sprint-plan-2026-05-27.md`
- Rhythm Section chart plan artifact: `docs/ichart-rhythm-section-chart-plan-2026-05-27.md`
- Rhythm recognition rebuild plan artifact: `docs/ichart-rhythm-recognition-rebuild-plan-2026-05-28.md`
- Post-V1 Lead Sheet archive: `docs/post-v1/lead-sheet/README.md`
- Lead Sheet pitched-note baseline artifact: `docs/post-v1/lead-sheet/ichart-lead-sheet-pitched-note-baseline-2026-05-29.md`
- Rhythm Section V4 closeout audit: `docs/ichart-rhythm-section-v4-closeout-audit-2026-05-29.md`
- Rhythm Section progress log: `docs/ichart-rhythm-section-progress-log-2026-05-29.md`
- Sprint 68 chart structure systems definition artifact: `docs/ichart-sprint-68-chart-structure-systems-definition-2026-05-29.md`
- Sprint 69 V1 readiness audit artifact: `docs/ichart-sprint-69-v1-readiness-audit-2026-05-31.md`
- Sprint 69 V1 readiness matrix: `docs/ichart-v1-readiness-matrix-2026-05-31.md`
- Sprint 70 App Functionality and UX/UI artifact: `docs/ichart-sprint-70-app-functionality-ux-2026-06-02.md`
- Sprint 71 V1 Product Readiness and Release Hardening artifact: `docs/ichart-sprint-71-v1-product-readiness-2026-06-04.md`
- iChart plan policy authority: `docs/ichart-plan-policy-source-of-truth.md`
- latest Sprint 69 closeout: Sprint 69 is complete locally. The final fresh Rhythm Section app-surface pass was green for professional staff layout, suppressed header meter, native full-screen surface, rhythm recognition across the current v1 live set, chord snapping with and without rhythm maps, below-staff freehand articulation, structured cue/roadmap/repeat objects, and save/reopen behavior. No V1 blocker remains confirmed by the audit. The readiness matrix now moves the next lane to Sprint 70 App Functionality and UX/UI, starting with project/library UX, export/share confidence, save/reopen confidence, and tool/menu affordance polish.
- latest Sprint 70 chord transposition checkpoint: chart-wide chord transposition is implemented locally as a non-destructive half-step display setting for rendered chords. `Chart.chordTranspositionSemitones` stores a normalized `0...11` offset; stored `ChordEvent.symbol`, raw input, source ink evidence, correction signatures, beat placement, and rhythm-slot mapping remain unchanged. `Chart.displayedChordSymbol(for:)` resolves transposed root and slash-bass symbols, and shared page layout now feeds that displayed symbol into Simple Chord Sheet and Rhythm Section chord layouts so live canvas and PDF/export paths share the same display authority. Page > Transpose Chords exposes reset, up/down half-step, and direct half-step offsets. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests'` passed with `165` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `464` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture completed after launch.
- latest Sprint 70 header entry checkpoint: typed-or-handwritten headers are implemented locally for the active V1 styles. `Chart.headerInputMode` decodes legacy charts to `.typed`, while `pageHandwrittenHeaderData` stores header ink separately from page freehand, chord ink, rhythm ink, and freehand-symbol objects. `LeadSheetHeaderLayout.handwrittenFrame` defines the header writing scope; Page > Header can keep typed mode, enter handwritten header writing, or clear only handwritten header ink. Live canvas and PDF/export now share the same mode authority: typed mode draws typed header text and handwritten mode suppresses typed page-header text while drawing saved header ink. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests|LeadSheetInteractionModeStatePolicyTests|FileChartRepositoryTests'` passed with `174` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `467` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture completed after launch.
- latest Sprint 70 ink session checkpoint: passive ink responsiveness is implemented locally for handwritten headers, page/freehand ink, and freehand-symbol writing, and chord/rhythm ink authoring now shares the same live-session contract. `LeadSheetInkAuthoringSessionState` replaces separate chord/rhythm/passive dirty flags, active scopes resolve through chord/rhythm/passive `LeadSheetInkAuthoringSessionRole` values, and `LeadSheetInkCanvasSyncPolicy` preserves dirty active canvases from stale model reloads through one authority. The former rhythm-only stable drawing snapshot is now `LeadSheetInkDrawingSnapshot`; rhythm auto-apply continues to use it, passive ink persistence uses it, and chord recognition requests now also no-op when the live canvas no longer matches the snapshot that was scheduled. This keeps fast handwriting live in `PKCanvasView` longer and reduces stale scheduled recognition reads without changing chord recognition, rhythm recognition, OCR, score thresholds, parser/compendium behavior, default diagnostics, or personal handwriting fixtures. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter 'LeadSheetInteractionModeStatePolicyTests|ChartEditingTests|LeadSheetPageLayoutTests|FileChartRepositoryTests'` passed with `174` tests and `0` failures before the chord/rhythm unification; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `467` tests, `36` skipped, and `0` failures after the unification; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture completed after launch.
- latest Sprint 70 user pen responsiveness checkpoint: `e2f309c Unify live ink authoring sessions` is the committed clean marker for the new ink working state. Page > Pen Responsiveness is now implemented locally as a user preference that coalesces live drawing-change follow-up work before persistence or recognition timers start. This setting is app/user scoped, not stored in chart documents, and it does not change chord recognition, rhythm recognition, OCR, scores, parser/compendium behavior, default diagnostics, or handwriting fixture authority. Full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `467` tests, `36` skipped, and `0` failures; XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `39` tests and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture completed after launch.
- latest Sprint 70 measure double-barline checkpoint: Page > Measures now includes `Add Double Barline Measure`, reusing the existing selected/open measure add flow while setting the committed or inserted measure's trailing `barlineAfter` to `.double`. The first chart measure now resolves a shared `LeadSheetMeasureLayout.leadingBarline` of `.double`, so live canvas and PDF/export draw a leading double barline at the beginning of the first measure without mutating that measure's trailing `barlineAfter`. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests'` passed with `172` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `471` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture completed after launch.
- latest Sprint 70 Chord-tool correction checkpoint: Chord mode now supports rendered chord correction without switching to Select. `EditorCanvasMode.chordEntry` keeps chord ink writing active in empty chord-lane space while making every rendered chord box active immediately after render. Rendered chord boxes intercept interaction over the chord object so PencilKit does not treat that same spot as new chord ink; delete, review, and move are available from Chord mode without selecting first or switching tools. The old post-render object-action suppression is bypassed in Chord mode so newly rendered chords are immediately interactive. Active rendered chord drags now lock the parent chart scroll view until the drag ends or fails, so moving a chord cannot pan or zoom the sheet underneath it. Select/Browse remains the neutral scroll/object-selection state with the existing all-chord overlay behavior. This changed object interaction routing only: no chord recognition, rhythm recognition, OCR, score, parser, compendium, diagnostics, or personal handwriting fixture authority changed. Full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `471` tests, `36` skipped, and `0` failures after the active-rendered-object follow-up; XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests -only-testing:iChartTests/LeadSheetChordEditOverlayGeometryTests CODE_SIGNING_ALLOWED=NO` passed with `49` tests and `0` failures before the rendered-box follow-up; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only after the active-rendered-object follow-up.
- latest Sprint 70 editor back-swipe checkpoint: the editor route now hides the system navigation back button and provides an explicit custom top-left exit arrow, preventing iOS from attaching the default right-swipe navigation exit gesture to the chart canvas. Active rendered chord drags remain governed by the parent-scroll lock from the Chord-tool correction slice, so chord movement and app navigation stay separate. This is an app-navigation behavior change only: no chart scrolling model, chord dragging model, ink persistence, recognition, OCR, parser, compendium, score, diagnostics, or personal handwriting fixture authority changed. Full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `471` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- latest Sprint 70 Rhythm Section system-break checkpoint: Measure-menu system breaks are now active for Rhythm Section charts as well as Simple Chord Sheet charts. The model exposes shared `canInsertSystemBreak`, `insertSystemBreak`, `canRemoveSystemBreak`, and `removeSystemBreak` APIs for active V1 styles while keeping the old Simple-named wrappers Simple-only; Lead Sheet manual system breaks remain deferred. Forced breaks continue to persist through `ChartSystem.lineBreakRule == .forced`. Rhythm Section page layout treats forced break starts as hard rendered-system boundaries, then keeps automatic measure packing/stretching inside each row. This is a layout/editing contract change only: no rhythm recognition, chord recognition, OCR, parser, compendium, score, diagnostics, or handwriting fixture authority changed. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `100` tests and `0` failures; focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `75` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `474` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture completed after launch.
- latest Sprint 70 Rhythm Section system visual-alignment checkpoint: Rhythm Section continuation systems now reserve the same leading measure gutter as the first system, giving forced/manual system rows matching measure starts and trailing barline ends while leaving continuation clef/time hidden. Rhythm Section staff lines now draw only from the visible leading barline or repeat marker through the visible trailing barline or repeat marker, removing the extra line tails before and after systems in both live canvas and export rendering. This is a rendering/layout polish change only: no rhythm recognition, chord recognition, OCR, parser, compendium, score, diagnostics, or handwriting fixture authority changed. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `75` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `474` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only, and screenshot capture confirmed aligned Rhythm Section systems without staff-line tails past the barlines.
- latest Sprint 70 Rhythm Section standard-measure-width checkpoint: Rhythm Section layout now derives the default measure width from the first rendered system and applies that standard to later default measures, so short forced/manual rows no longer stretch a small measure count across the full row. Explicit manual measure-width overrides remain user-authored exceptions, and the standard is capped when needed to prevent overflow on later rows with more measures. This is a rendered layout-planning change only: no rhythm recognition, chord recognition, OCR, parser, compendium, score, diagnostics, or handwriting fixture authority changed. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `76` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `475` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture completed after launch.
- latest Sprint 70 Measure stack deletion checkpoint: the Measures menu now exposes `Delete Selected Measure` as a destructive action backed by the existing chart model deletion authority. The model exposes `canDeleteMeasure(id:)`, preserves the one-measure minimum, and deletes the selected measure's attached stack through the existing cleanup path: chord events, rhythm map/ink, section labels, cue text, roadmap objects, repeat/ending spans, point markers, links, and freehand symbols attached to the measure are removed with the measure. The editor clears pending repeat/ending/text/time/note state after deletion and selects the next neighboring measure when possible. This is a Measure-menu editing change only: no rhythm recognition, chord recognition, OCR, parser, compendium, score, diagnostics, or handwriting fixture authority changed. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter 'ChartEditingTests|LeadSheetPageLayoutTests'` passed with `177` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `476` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture completed after launch.
- latest Sprint 70 controlled measure range deletion checkpoint: the Measures menu now exposes `Start Delete Range Here`, `Delete Through Here`, and `Clear Delete Start`. Like repeat and ending ranges, the delete range uses two user-selected boundaries, accepts either forward or reverse ordering, and deletes only the inclusive selected span. The operation uses the same model-backed attached-stack cleanup path as single-measure deletion, preserves the hard one-measure minimum by refusing all-measure ranges, and clears pending repeat/delete/ending/text/time/note editor state after deletion or tool changes. This is a Measure-menu editing change only: no rhythm recognition, chord recognition, OCR, parser, compendium, score, diagnostics, or handwriting fixture authority changed. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `103` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `478` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture confirmed launch to Projects.
- latest Sprint 70 Measure-menu stack insertion checkpoint: the Measures menu now exposes `Add Measure Stack After Selected`. The action opens a compact count chooser from `1...64` measures with common count presets, inserts exactly the chosen number of committed measures after the selected anchor through the model-backed insertion/rebuild path, selects the last inserted measure, and preserves any existing trailing open measure. If the selected anchor is open, the editor commits it first and leaves a trailing open measure after the inserted stack. This is a Measure-menu editing change only: no rhythm recognition, chord recognition, OCR, parser, compendium, score, diagnostics, layout renderer, or handwriting fixture authority changed. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `106` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `481` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only and screenshot capture confirmed launch to Projects.
- latest Sprint 70 closeout: Sprint 70 is complete and pushed at `cf6c137 Advance Sprint 70 editor workflows`. The lane closed with chart-wide transposition, typed/handwritten headers, live ink responsiveness, unified chord/rhythm ink sessions, user pen responsiveness, leading/trailing double-barlines, Chord-tool rendered chord correction, editor back-swipe locking, Rhythm Section system breaks, system visual alignment, standard Rhythm Section measure widths, selected-measure deletion, controlled range deletion, and measure stack insertion. Final verification passed `ChartEditingTests` with `106` tests and `0` failures, full SwiftPM with `481` tests, `36` skipped, and `0` failures, `git diff --check`, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- latest Sprint 71 kickoff: Sprint 71 V1 Product Readiness and Release Hardening is now the active lane. Codex-side work starts with project/library actions and release-surface cleanup while the user owns broader UI/UX appearance. Candidate order is project/library rename/duplicate/delete and metadata, export/share confidence, quiet save/reopen confidence, release hygiene, and only targeted tool/menu affordance polish. Guardrails remain unchanged: no recognition retuning, OCR expansion, personal handwriting fixture expansion, default diagnostics, global retraining, or Lead Sheet feature expansion before V1.
- latest Sprint 71 project/library actions checkpoint: Library rename, duplicate, and delete are implemented locally through `ChartLibraryStore` and surfaced from each chart row. Rename trims/rejects empty titles and preserves selection; duplicate respects capacity, creates a fresh chart identity, copies chart content, assigns a `Copy` / numbered-copy title, selects the duplicate, and persists it; delete removes the saved chart from the library snapshot, selects a neighboring chart when possible, clears selection when empty, and batches persistence so no stale selected-chart snapshot is written. The production-facing Library surface no longer shows the Developer Tools section. Focused SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartLibraryStoreTests` passed with `22` tests and `0` failures; full SwiftPM `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `489` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- latest Sprint 71 GitHub Actions audit checkpoint: branch run `26921373138` on `cf6c137` failed only in the iOS simulator PDF/export text assertions; SwiftPM passed. Local reproduction showed role-based semantic chord rendering still exported text, but PDFKit extracted split chord tokens such as `Db 7(b9)` and `G /B`, and sometimes omitted music-symbol glyphs such as triangle. The test contract now uses `XCTAssertPDFExtractedTextContains` for chord-text export assertions only, normalizing PDF extraction artifacts while preserving exact text checks for non-chord export proof. Focused XcodeBuildMCP simulator export tests passed with `7` tests and `0` failures; full XcodeBuildMCP simulator tests passed with `608` tests, `37` skipped, and `0` failures; full SwiftPM passed with `489` tests, `36` skipped, and `0` failures; `git diff --check` passed. GitHub Actions branch run [`26922352743`](https://github.com/beniandthe/ichart/actions/runs/26922352743) passed on `fc46d33`, with `SwiftPM tests` passing in `1m46s` and `iOS simulator tests` passing in `8m7s`.
- latest Sprint 71 export/share confidence checkpoint: PDF export now returns a first-class `ExportedPDF` result instead of a bare URL, preserving the same structured-object renderer while carrying file name, chart style, transposition context, page count, file size, and exported-at metadata into the preview/share flow. `PDFChartExporter` now writes readable share-friendly names such as `Almost Like Being In Love - Simple Chord Sheet - Concert.pdf`, including chord-transposition context when needed. `PDFExportPreviewView` shows a compact ready-state summary with the generated file name and metadata, keeps direct sharing, and adds an explicit `Done` action. Focused XcodeBuildMCP simulator export tests passed with `9` tests and `0` failures; full SwiftPM passed with `489` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture succeeded after launch.
- latest Sprint 71 save/reopen confidence checkpoint: `ChartLibraryStore` now publishes local persistence state as `notTracking`, `ready`, `saved`, or `failed`, so the app no longer hides repository load/save failures behind console output only. Repository-backed mutations mark the library saved with a timestamp, loaded live snapshots show as saved, and load/save failures surface as a quiet local failure state without dropping in-memory edits. Library and Editor both show a compact persistence badge driven by that same model state. Focused XcodeBuildMCP simulator `ChartLibraryStoreTests` passed with `26` tests and `0` failures; full SwiftPM passed with `494` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only; screenshot capture confirmed the Library surface launches with the quiet `Saved locally` persistence badge visible.
- latest iChart home-shell checkpoint: Release hygiene is deferred into its own future sprint so pipeline/testing work can be handled cleanly. The app home page now uses the locked iChart adaptive sidebar shell with the full B4.8A-H1 canon wordmark and left-side tabs named `Charts`, `Forums`, `Help`, and `Settings`. `Charts` remains the saved-chart library and owns the `New Chart` action, but no longer repeats the logo in its content header; `Forums`, `Help`, and `Settings` are app-level home destinations, separate from editor tools. The native home navigation title is hidden so the sidebar wordmark and content header own the page chrome. The sidebar can collapse/open while preserving the active destination, and Help is now the all-in-one support surface for `FAQ`, `User Policy`, `Legal`, and `Contact Us` placeholders instead of duplicating those links under the Light/Dark switch. Full SwiftPM passed with `494` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only; screenshot and UI snapshot/tap verification confirmed the left tabs render and switch panels. The universal-logo follow-up replaced the compact `iC` mark with the full B4.8A-H1 sidebar wordmark, aligned the SwiftUI mark to the canon export proportions, corrected the italic `i` so its bottom aligns with `hart`, and screenshot-verified the Charts tab no longer duplicates the logo.
- latest Charts tab polish checkpoint: The Charts tab now removes the redundant top header, centers `New Chart`, shows the Basic chart usage line only when a local chart cap applies, simplifies chart rows to title/style/measure count, and lets the user choose `Collapsed`, `Quick`, or `Large` row previews. Full SwiftPM passed with `494` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only; runtime UI snapshot confirmed the capped usage line and preview targets, and tapping `Quick` / `Large` switched modes with screenshot proof of readable large paper-first previews.
- latest account/cloud monetization decision: Basic remains a mandatory account tier with the complete local chart-writing tool, PDF/export, local autosave, and a 3-chart local cap. Pro is a monthly/annual subscription surface for unlimited chart capacity, cloud chart backup/sync/restore, Forums, and future service-heavy features. If Pro expires, cloud sync and Forums lock immediately and remote chart backups use a clear grace period, recommended default 30 days, before cloud retention cleanup. Downgraded Basic accounts over the 3-chart cap must choose which local charts to remove until only 3 remain. This downgrade pruning is local-only, does not create cloud deletion tombstones, and keeps the pruned charts recoverable from cloud snapshots until the grace period ends.
- latest Forums implementation contract: Forums are a Pro-only community chart library rather than a social feed. V1 submits fixed PDF snapshots with creator/source credit, not editable chart JSON or source ink; every post/comment/vote/report/badge is account-tied; song/artist/chart/arranger metadata is required; new forum chart posts start as `pending` until an authenticity review approves them for the public library, and community quality is then driven by votes, reports, ranking, and moderation-ready statuses (`published`, `flagged`, `hidden`, `removed`). Forum access follows the same active Pro entitlement boundary as cloud services.
- latest iChart launch simplification checkpoint: the launch-handwriting animation remains baked into `AppRootView` and now resolves from the bundled canonical `iChart/Resources/Launch/IChartCanonicalLaunchHandwriting.json` sample on every boot. The user-facing `Settings > Launch Handwriting` capture/selection surface has been removed because the launch sample is product-owned, not user-configurable. This is a product-surface simplification only: no chart handwriting recognition, fixture authority, parser, OCR, or score behavior changed.
- latest local verification: Rhythm Section side sprint core authoring is complete and locally verified on `codex/rhythm-section-core-authoring`. Rhythm Recognition V3 is implemented locally through the targeted-unread-stroke-feedback slice, and Rhythm Recognition V4 is now implemented locally as a deterministic raster/template phrase gate ahead of the V3 safety bridge. Live rhythm auto-apply rechecks a stable stroke-shape snapshot instead of comparing serialized PencilKit `Data`; live auto-render and selection finalization require a trusted commit decision, while underfilled, review-only, ambiguous, uncovered, competing, non-visual-fallback, non-natural exact-fit, unsupported, or unread-crop paths preserve local ink. V4 normalizes live rhythm ink into measure-relative symbol crops, matches those crops against a writer-agnostic visual compendium, validates exact values through `RhythmicNotationCompendium` and `MeasureRhythmMap`, and commits only when visual evidence plus render alignment agree. Red unread-ink feedback now waits until a rhythm decision is completed-looking and can localize the unread item; V4 unread-symbol decisions target the failing crop when possible, V3 uncovered decisions target primitive bounds, and broad review/fallback states no longer frame the whole live ink area. Rhythm mode resolves a real authoring measure when entered. The latest live simulator pass after the stable snapshot repair committed `slash, slash, slash, slash` in measure 1 and `quarter, quarter, quarter, eighth, eighth` in measure 2; follow-up underfilled/ambiguous attempts stayed local. The latest saved-state check after a clear non-rendering quarter-note pass showed raw measure ink preserved without a rhythm map, confirming fail-closed behavior. Temporary runtime auto-apply trace logging and the one-off live-trace replay helper were removed after that evidence capture, leaving the stable snapshot guard without a new default diagnostic stream. XcodeBuildMCP focused simulator `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `80` tests and `0` failures after the V4 raster/template gate and crop-level unread feedback slice; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `125` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only and screenshot proof showed the app launched to Projects.
- latest V4 slash authority verification: the follow-up live four-slash Rhythm Section failure was traced to a dead-end handoff from V4 into the visual fallback, where the second slash could be claimed as an eighth rest and leave the measure underfilled at `7/8` units. V4 now owns isolated placeholder-slash crops directly, emits one `.slash` per isolated slash stroke even when crops group tightly, and the fallback eighth-rest branch refuses isolated placeholder-slash symbols. This is writer-agnostic replay coverage only: no personal handwriting fixtures, score retuning, OCR expansion, or default diagnostic stream were added. XcodeBuildMCP focused simulator replay/regression `test_sim` passed with `2` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests` plus `LeadSheetInteractionModeStatePolicyTests` passed with `111` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `443` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest V4 whole-note verification: the clear whole-note live-pass catch was traced to the earlier whole-measure safety guard, not missing vocabulary support. V4 already recognized the clear hollow notehead as `.whole`, but the proposal remained review-only and surfaced as unread feedback after the confirmation workflow was removed. Strong single-crop V4 whole-note evidence now promotes to auto-apply, while tiny whole-like marks and whole rests remain conservative. This did not change chord layout, typography, OCR, score tuning, personal handwriting fixtures, or default diagnostics. XcodeBuildMCP focused simulator `test_sim` for `RhythmicNotationQuantizerTests` passed with `80` tests, `1` optional replay skip, and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `200` tests, `1` optional replay skip, and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `450` tests, `36` skipped, and `0` failures; `git diff --check` passed.
- latest V4 half-note ambiguity verification: the live two-half-note Rhythm Section failure was traced to phrase routing, not ink capture or missing vocabulary. The saved raw ink persisted, but the raster/template candidate groups offered both quarter and half for each hollow-stem crop; the natural shortest path selected `quarter, quarter`, returned underfilled at `4/8` units, and preserved ink before V4 checked the aligned exact-fit `half, half` path. The underfilled branch now allows only a writer-agnostic, render-aligned exact-fit promotion when it lengthens existing confident candidates without stretching unsupported evidence. This did not add personal handwriting fixtures, score retuning, OCR expansion, or default diagnostics. XcodeBuildMCP focused simulator replay/regression `test_sim` passed with `2` tests and `0` failures; XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `81` tests, `1` optional replay skip, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest V4 compact whole-note verification: the follow-up whole-note live failure was traced to the strong whole-note promotion threshold, not capture or vocabulary support. A normal compact handwritten oval could be accepted by the whole-note template but remain too small for the auto-apply promotion, causing unread feedback. Strong single-crop whole-note promotion now accepts compact hollow-head crops at the template-recognition scale; tiny low-information whole-like marks and whole rests remain conservative. XcodeBuildMCP focused simulator `test_sim` for the compact/strong/tiny whole-note cases passed with `3` tests and `0` failures; XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `82` tests, `1` optional replay skip, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest V4 direct whole-note circle verification: whole-note recognition now follows the simple v1 rule instead of depending on the stricter hollow-head classifier. In the rhythm lane, a no-stem closed oval/circle above the tiny-mark threshold is a whole note. Literal closed-circle, compact oval, and regular whole-note simulator cases commit as `.whole`; tiny low-information whole-like marks and whole rests remain conservative. XcodeBuildMCP focused simulator `test_sim` for the direct circle/compact/strong/tiny whole-note cases passed with `4` tests and `0` failures; XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `83` tests, `1` optional replay skip, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only.
- latest V1 creation/library contract verification: `ChartLayoutStyle.v1NewChartOptions` now limits New Chart creation to the active V1 styles, Simple Chord Sheet and Rhythm Section Sheet, while preserving Lead Sheet as a model-compatible post-V1 style. Library summaries now derive from layout setup policy, so Simple and Rhythm Section hide key names while Lead Sheet can still show key. Rhythm Section now has a V1-shaped persistence proof matching the Simple proof level: rhythm maps with source drawing data, preserved raw rhythm ink, chords, cue text, roadmap objects, below-measure freehand articulations, typography, and selected-chart state round-trip through `FileChartRepository`. `ChartLibraryStore` also now has a direct editor-binding persistence proof: mutating a chart element inside `store.charts`, as `AppRootView` does for `EditorView`, writes the edited chart into the saved snapshot. The persistence regression gate now also round-trips a mixed V1 library snapshot containing Simple and Rhythm charts, pending page chord ink, committed chord source ink/signatures, committed rhythm maps with drawing data, unresolved raw rhythm ink, typography, manual Simple row/width state, roadmap objects, cue text, freehand symbols, selected-chart state, and entitlements. Focused SwiftPM `ChartLibraryStoreTests` and `FileChartRepositoryTests` passed with `18` tests and `0` failures; focused SwiftPM `ChartLibraryStoreTests` passed with `14` tests and `0` failures after the binding proof; persistence regression focused SwiftPM passed with `20` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` now passes with `458` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only; XcodeBuildMCP focused simulator `test_sim` for `ChartLibraryStoreTests` passed with `13` tests and `0` failures.
- latest rhythm silent-state verification: live rhythm preserve-ink decisions that are intentionally quiet during active writing now get a stale-state check after the normal auto-render window if the ink has not changed. If the measure still cannot commit and V4 has no targeted unread crop, the existing dashed feedback frames the actual ink bounds instead of leaving the selected measure visually silent. The optional live replay harness now skips when `ICHART_RHYTHM_STATE_LIVE=1` has no pending raw rhythm ink, while explicit replay state remains strict. XcodeBuildMCP focused simulator `LeadSheetInteractionModeStatePolicyTests` passed with `31` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests` plus `LeadSheetInteractionModeStatePolicyTests` passed with `111` tests, `1` optional live replay skipped, and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `443` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest native iPad viewport/orientation verification: `project.yml` now generates iPad full-screen metadata with portrait, portrait-upside-down, landscape-left, and landscape-right support. `EditorView` measures the actual app viewport and sizes the canvas from that width instead of the old fixed `900`-point assumption. Simple Chord Sheet and Rhythm Section paper widths expand to native portrait/landscape app bounds, Rhythm Section rows stretch packed measures across the usable staff row after automatic wrapping, and Lead Sheet keeps its legacy capped-paper policy until post-V1 layout work resumes. Focused SwiftPM layout/config verification passed with `70` tests and `0` failures; full SwiftPM passed with `447` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only. The current desktop Simulator session reported manual orientation menu items disabled, so visual rotate proof remains part of the next fresh live simulator pass rather than treated as failed app metadata.
- latest V4 semantic gate verification: stemmed notehead crops can no longer drive slash values, dotted values require detached dot evidence, and unflagged quarter-like stems can extend stability or require review but cannot force exact-fit live auto-render as eighths. XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `67` tests and `0` failures; grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `128` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only.
- latest unread-feedback verification: red unread feedback now waits for completed-looking rhythm decisions and only draws localized unread symbol/primitive frames. XcodeBuildMCP `test_sim` for `LeadSheetInteractionModeStatePolicyTests` passed with `17` tests and `0` failures; grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `129` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only.
- latest V4 rest-phrase verification: V4 now owns quarter-rest, half-rest, whole-rest review, dotted/long value, and adjacent eighth-rest phrase decisions through the raster/template gate when the visual evidence is complete. Rest crops filter out note alternatives when rest evidence is strongest, strong quarter/half/whole rest matches are not overwritten by generic eighth-rest hooks, and adjacent eighth-rest dot/tail crops stay paired after symbol splitting. XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `69` tests and `0` failures; grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `131` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` and screenshot capture succeeded with the existing headermap warning only.
- latest V4 non-exact state verification: V4 now owns strong-template underfilled, overflow, and completed unsupported-crop states locally instead of handing them to older meter-fit paths. Single-unit unflagged-stem exact alternatives are manual review only, and beamed-template overcount cases still fall through to the proven visual bridge. XcodeBuildMCP focused `test_sim` passed with `5` tests and `0` failures; `RhythmicNotationQuantizerTests` passed with `72` tests and `0` failures; grouped `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `134` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` and screenshot capture succeeded with the existing headermap warning only.
- latest V4 normalization and Lead Sheet baseline verification: V4 now rejects tiny isolated noise marks before crop grouping and has explicit render-comparison accept/reject coverage. Lead Sheet now renders treble/bass clef glyphs from setup and places transposed key-signature accidental glyphs before the first measure's time signature. The first pitched-note baseline is implemented locally: note-only Lead Sheet rhythm commits can use V4 visual note anchors to create clamped in-staff pitched-note events, and stem-down staff notes are protected from single-eighth misreads caused by upper notehead mass. XcodeBuildMCP focused `test_sim` for the new Lead Sheet pitched-note finalization cases passed with `2` tests and `0` failures; XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `76` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `182` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `360` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` and screenshot capture succeeded with the existing headermap warning only.
- latest Lead Sheet mixed note/rest verification: Lead Sheet pitched-note commit now accepts mixed note/rest phrases by storing pitched events only on note-capable rhythm slots while preserving rest glyphs on rest slots. V4 visual note anchors feed those note-capable slots, so a phrase like `quarter, quarterRest, quarter, quarterRest` can commit two clamped staff-position notes without treating rests as pitched notes. Partial or duplicate pitch coverage is rejected, so note-capable slots do not fall back to slash placeholders or stale note events. Beamed-eighth V4 crops can also supply separate pitch anchors for each accepted eighth. `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `86` tests and `0` failures; XcodeBuildMCP focused `test_sim` for mixed Lead Sheet note/rest finalization passed with `1` test and `0` failures; XcodeBuildMCP focused `test_sim` for beamed-eighth pitch-anchor finalization passed with `1` test and `0` failures; XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `186` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest Lead Sheet pitch-coverage guard verification: `Chart.setLeadSheetRhythmMap` now rejects partial, duplicate, or rest-slot pitch coverage so mixed note/rest Lead Sheet commits only land when every note-capable slot has exactly one V4 visual note anchor. `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `186` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest profile-interaction audit: `ChartLayoutProfile` now owns user-facing rhythm-note editing availability, keeping Rhythm Section and Simple editing off for now while Lead Sheet can use the existing note/rhythm edit surface. This removes an editor-local style exception and preserves the Rhythm Section contract that individual rhythm editing is not enabled yet. `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `186` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest freehand availability guard: `ChartLayoutProfile` now exposes profile-owned freehand symbol ink availability. Simple and Rhythm Section still resolve freehand symbol ink scopes because they have lanes; Lead Sheet resolves no freehand page-ink scope for now, matching the no-freehand-symbol-lane contract. XcodeBuildMCP focused `test_sim` for `LeadSheetInteractionModeStatePolicyTests` and `ChartEditingTests` passed with `66` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `187` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest rhythm-notation tool availability guard: `ChartLayoutProfile` now owns rhythmic-notation ink availability. Simple Chord Sheet resolves no rhythmic-notation active ink scope and the editor tab is guarded/disabled for that style; Rhythm Section and Lead Sheet keep rhythmic-notation ink scopes. `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures; XcodeBuildMCP focused `test_sim` for `LeadSheetInteractionModeStatePolicyTests` and `ChartEditingTests` passed with `67` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest V4 architecture audit: the raster/template core has been extracted into `RhythmicNotationRasterTemplateRecognizer.swift` beside the quantizer. `RhythmicNotationQuantizer` remains the public entrypoint and V3/visual/fallback bridge, while the sibling core owns V4 raster input, symbol crops, template matches, phrase decisions, render comparison, and visual note anchors. XcodeBuildMCP focused simulator `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest rhythm recognition type audit: shared rhythm proposal, phrase, primitive, decision, reason, candidate, and candidate-path contracts now live in `RhythmicNotationRecognitionTypes.swift`, leaving `RhythmicNotationQuantizer` focused on orchestration/bridging and keeping V3/V4 decision shapes auditable from their own file. XcodeBuildMCP focused simulator `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest side-sprint closure audit: `docs/ichart-rhythm-section-v4-closeout-audit-2026-05-29.md` records implemented Rhythm Section core authoring, V3/V4 recognition, profile-owned tool policies, the resumed Lead Sheet baseline, verification evidence, and the product-definition-gated deferred systems.
- latest local breadcrumb log: `docs/ichart-rhythm-section-progress-log-2026-05-29.md` preserves the final implementation checkpoints and verification trail for regression hunting.
- latest Simple Chord Sheet manual row-flow verification: `ChartLayoutProfile` now exposes the Simple row cap as `maximumMeasuresPerSystem`, defaulting to `20`; `ChartEditing` can insert and remove Simple-only forced row breaks before selected measures; forced row breaks survive measure insertion/reindexing by measure identity; Simple layout renders model systems as proportional chord-grid rows, allows `16` measures in one row, and pushes overflow to a new automatic row at the cap; Rhythm Section automatic wrapping is unchanged. The Measures menu exposes `New System Before This Measure` and `Remove System Break` with Simple-only guards. `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `134` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `410` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only and screenshot proof showed the app launched to Projects.
- latest Simple Chord Sheet row-control adjustment: default Simple measures now equalize inside a row unless the user has applied a manual width override; manual widths remain proportional row weights. The live-pass vertical drag path has been removed from the active V1 workflow after friction, leaving the Measure menu as the row-break authority and a Simple-only dashed row-group guide as a visual selection hint. `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `54` tests and `0` failures; XcodeBuildMCP focused `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `21` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `412` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest Simple floating freehand ink pivot: the previous freehand resize checkpoint is superseded. Simple Chord Sheet `Free-Hand` now uses chart-paper ink capture and persists strokes as measure-attached `chartArea` freehand objects with measure-relative frames, so ink can be moved/deleted as its own object and follows the attached measure through layout changes. The resize handle was removed because it only resized the selection frame, not the underlying ink. Selected freehand objects now get a forgiving selected drag hit area, and active-tool scroll blocking treats editable freehand boxes/controls as protected from parent page panning. Rhythm Section keeps below-measure freehand articulations only, and Lead Sheet still exposes no V1 freehand symbol lane. Focused `ChartEditingTests` passed with `82` tests and `0` failures; focused `LeadSheetPageLayoutTests` passed with `54` tests and `0` failures; XcodeBuildMCP focused simulator `test_sim` for `LeadSheetFreehandSymbolEditOverlayGeometryTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `28` tests and `0` failures after the freehand grab hardening; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `412` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest active-tool scroll margin gate: browse mode keeps normal page scrolling, but every active tool mode now lets the parent page scroll/pinch begin only from outside the rendered paper margins. The canvas host installs custom no-op blocker recognizers on the enclosing `UIScrollView`, so parent scrolling waits/fails for gestures that begin on the sheet while writing/erasing/moving/editing without replacing UIKit's required built-in scroll gesture delegates. XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `23` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `412` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only. A follow-up clean-simulator launch on 2026-05-30 verified the blocker recognizer hardening fixes the `UIScrollView` pan delegate crash.
- latest Simple cohesion polish: Simple Chord Sheet now reserves a left meter gutter across every row, shows the initial time signature before the first measure, and renders Simple meter changes inside the grid instead of leaving them model-only. The Measures tool keeps reopening as a menu during pending repeat/ending workflows, so `Start Repeat Here` -> `End Repeat Here` no longer deselects the tool on the second tap. Header, metadata, section, roadmap, and cue text use stable app-standard text fonts instead of selected notation fonts, reducing clipping and visual drift while leaving notation glyph choices intact. Focused SwiftPM `LeadSheetPageLayoutTests` passed with `57` tests and `0` failures; focused SwiftPM `ChartEditingTests/testDraftStoresSelectedLayoutStyleAndDefaults` passed with `1` test and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `416` tests, `36` skipped, and `0` failures; XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `24` tests and `0` failures; XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests CODE_SIGNING_ALLOWED=NO` passed with `57` tests and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest cohesion continuation: non-initial time-signature changes now render inside the measure whose meter they change, not as a marker before the next barline. `LeadSheetMeasureLayout` exposes this as `meterChange` / `meterChangeFrame`, the Time tool selects the changed measure after applying a change, and `LeadSheetPageLayoutEngine.VisualPolicy` now owns the first shared visual constants for header title framing, Simple meter gutter width, initial meter placement, and inline meter-change placement. Focused SwiftPM `LeadSheetPageLayoutTests` passed with `57` tests and `0` failures after the inline meter-change correction; focused SwiftPM `ChartEditingTests/testApplyMeterChangeToNextTimeSignaturePersistsIntoFutureMeasures` passed with `1` test and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `416` tests, `36` skipped, and `0` failures; XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests CODE_SIGNING_ALLOWED=NO` passed with `57` tests and `0` failures; XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `24` tests and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest Simple chord edit-box correction: Simple Chord Sheet chord layout now separates the invisible measure/segment fit area from the visible rendered chord frame. Chord text still scales from top to bottom into the snapped measure segment for the iReal-style grid feel, but selection/review/move/delete geometry wraps the displayed chord instead of exposing a segment-sized resize-looking box. Focused SwiftPM `LeadSheetPageLayoutTests` passed with `60` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `419` tests, `36` skipped, and `0` failures; XcodeBuildMCP focused simulator `test_sim -only-testing:iChartTests/LeadSheetPageLayoutTests -only-testing:iChartTests/LeadSheetChordEditOverlayGeometryTests -only-testing:iChartTests/PDFChartExporterTests CODE_SIGNING_ALLOWED=NO` passed with `69` tests and `0` failures; `git diff --check` passed; a clean simulator reinstall/rebuild via XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only, and screenshot capture showed the app launched to Projects.
- latest Simple automatic chord placement/no-resize/writing-space correction: Simple Chord Sheet chord editing no longer shows a separate move/resize-looking control. The selected chord body is the move target in `Select` mode, delete remains the only visible chord edit control there, and Simple append placement ignores handwriting fraction so the first chord in an empty measure lands on beat `1` and the second chord lands on beat `3` in common time. Once a measure already has later-beat content, append placement now preserves left-to-right write intent: a chord written to the right of an existing beat-`3` chord lands on the next open beat instead of backfilling beat `1`. A live simulator state audit found the failed pass committed the chord at beat `1` and then a rendered-chord pan path moved it to beat `4`; the follow-up fix makes Chord mode write-only so a writing gesture cannot become a rendered-chord move after auto-render. Moving an existing chord still snaps to the dragged beat from Select mode, while rendered chord size stays automatic from the measure, beat segment, and text fit. The latest visual-authoring fix keeps a lone beat-1 chord's invisible snap/fit segment on the full measure but caps the visible chord object to the left-side primary-beat slot, renders root/accidental with a chord-safe text-face mapping for the current Page > Fonts preset, uses `FinaleJazzTextLowercase` for Finale Jazz chord symbols, keeps a shared primary size with a fixed shared suffix scale, horizontally compresses the full chord drawing when a measure segment gets too tight, and vertically centers the chord inside the barline-to-barline cell so long symbols like `Bb△7` no longer shrink below short chords like `C-7`. Focused SwiftPM Simple placement/layout slices passed with `25` tests and `0` failures after adding the later-beat append-order regression; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `425` tests, `36` skipped, and `0` failures; focused simulator `ChartEditingTests/testSimpleChordSheetAppendAfterExistingLaterBeatKeepsWrittenOrder`, `LeadSheetPageLayoutTests`, and `LeadSheetInteractionModeStatePolicyTests` passed with `89` tests and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only.
- latest Rhythm Section visual cohesion checkpoint: Sprint 69 has begun the Rhythm Section polish lane without changing V4 rhythm recognition, `MeasureRhythmMap`, or automatic wrapping. Rhythm Section section labels now reserve rehearsal-mark space above the chord lane; the renderer draws compact boxed rehearsal marks, slightly darker staff lines, stronger cue/roadmap text, crisper point markers, and stronger ending brackets while preserving the chord lane above staff, rhythm notation inside staff, and below-staff articulation/freehand lane. Focused SwiftPM `LeadSheetPageLayoutTests/testRhythmSection` passed with `10` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `443` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch simulator with the existing headermap warning only, and screenshot capture showed the app launched to Projects.
- latest Rhythm Section live-pass finding: the first fresh Rhythm Section pass found the old small header meter still showing under the title and rhythm ink failing to render/recognize reliably in live use. Rhythm Section headers now suppress key and meter text while keeping the first-system time signature before the staff. The rhythm non-render is classified as a live ink-to-recognizer pipeline audit item, not a confirmed slash/rest ordering bug. XcodeBuildMCP focused simulator `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures at the header checkpoint; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `443` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after a fresh simulator app uninstall/reinstall with the existing headermap warning only, and screenshot inspection of a newly created Rhythm Section chart confirmed the header `4/4` is gone while the first-system time signature remains before the staff.
- latest Rhythm Section live route audit: the intended rhythm workflow is now one path again. Live rhythm ink persists into the selected measure, V4 produces a `RhythmRecognitionDecision`, `LeadSheetRhythmicNotationLiveDecisionPolicy` routes that decision, and only a natural auto-apply commit writes a `MeasureRhythmMap` and clears handwritten rhythm ink. Underfilled, unsupported, ambiguous, review-only, non-natural exact-fit, overflow, or uncovered decisions preserve the ink and only show localized unread feedback when the phrase is complete enough. The old `RhythmicNotationConfirmationSheetView`, EditorView pending rhythm confirmation state, and host proposal/error callbacks were removed from the active runtime contract. Saved live Rhythm Section ink from the failing pass replayed through this route and now commits `[quarter, quarter, quarter, quarter]`; the audit found and fixed two writer-agnostic V4 mistakes: normal stem strokes no longer count as upper flag mass, and right-leaning quarter noteheads are no longer stolen backward as dotted-rhythm dots. No rhythm scores, OCR, handwriting fixtures, or training policy changed. XcodeBuildMCP focused simulator replay/regression tests passed with `2` tests and `0` failures; grouped simulator `RhythmicNotationQuantizerTests` plus `LeadSheetInteractionModeStatePolicyTests` passed with `110` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `443` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- latest GitHub verification: main commit `6e8ae16 Close sprint 62 release candidate pass` passed `SwiftPM tests`, `iOS simulator tests`, and `Analyze Swift` on 2026-05-27. Direct-main `Analyze Swift` completed quickly and reported the intentional CodeQL defer; real CodeQL remains on pull requests, weekly schedule, and manual dispatch. Supabase and Expo suites may remain queued with zero check runs and are not treated as current required app health.
- latest account/cloud product decision: iChart should require recoverable accounts for both Basic and Pro users. Account/auth/email verification/password recovery/immutable identity/subscription identity are base trust infrastructure, not paid features. Name and email are set during account creation and customer-support controlled afterward. Phone setup and verification are legacy/post-v1; existing phone data remains support-controlled but is not part of new-user onboarding. Chart authoring remains local-first. Cloud chart backup/sync/restore is the Pro subscription cloud-service surface and must be gated by active Pro entitlement before production rollout. The current signed-in chart sync behavior is an interim QA path until StoreKit/subscription entitlement wiring is implemented. Domain/custom SMTP setup is still pending before hosted Auth email templates can use the final direct app recovery path.

`c60bb46` remains the trusted checkpoint reference. It represents the last known-good altered-chord trust polish baseline before the symbol-ledger drift/recovery work. Do not treat `c60bb46` as the active implementation baseline unless a future sprint explicitly chooses a reset.

Known drift after Sprint 8:

- `ChordInkRecognizer` is back to a narrower orchestration role and now calls an explicit recognition-candidate coordinator, semantic candidate sidecar, and semantic glyph contextualizer instead of semantic merge methods on the base composer.
- `ChordInkSymbolLedger` is diagnostics-only by policy and is gated off by default on the live recognition path.
- `StrokeClusterer.swift`, `StrokeClustererSupport.swift`, `ChordInkCandidateScoringPolicy.swift`, `ChordInkCandidateSelectionPolicy.swift`, `ChordInkCandidateTextVariantPolicy.swift`, `ChordInkSemanticGlyphContextualizer.swift`, and `ChordInkSemanticCandidateComposer.swift` contain the largest remaining recognition maintenance risk.
- `ChordInkCandidateComposer.swift` now delegates scoring to `ChordInkCandidateScoringPolicy`, glyph selection to `ChordInkCandidateSelectionPolicy`, text variants to `ChordInkCandidateTextVariantPolicy`, and no longer owns recognition-level semantic candidate merging.
- `ChordInkCandidateSelectionPolicy.swift` is intentionally a behavior-preserving move of the old selection rules. Do not retune those thresholds without a new recognition sprint and fixture evidence.
- `ChordInkCandidateTextVariantPolicy.swift` is intentionally a behavior-preserving move of the old text alias/expansion rules. Do not retune those expansions without fixture evidence.
- `ChordInkSemanticGlyphContextualizer.swift` is intentionally a behavior-preserving move of the old contextual glyph promotion rules. Do not retune those promotions without fixture evidence.
- `ChordInkSemanticCandidateComposer.swift` remains large; it owns semantic candidate recipes and shared suffix-shape helpers that should be split only as behavior-preserving refactors.
- The old handwriting plan and current-architecture audit are explicitly marked historical/stale when they conflict with this file.
- The full ink fixture archive remains test-only evidence, not runtime authority or user handwriting training data. Default recognition, cluster, and glyph tests now use a compact transferable regression suite; full archive/captured coverage runs are opt-in through `ICHART_FULL_INK_FIXTURES=1`.
- Sprint 36 retired count-based captured handwriting coverage gates as active validation. Fixture capture UI now uses regression-fixture wording so debug capture cannot imply ongoing personal training.
- Fixture pruning/deletion remains deferred. Sprint 15 changes default test authority, not the archived fixture files.
- PR [#4](https://github.com/beniandthe/ichart/pull/4) merged the recovery branch into `main`; it is no longer the active review surface.
- The local duplicate `iChartTests/Recognition/* 2.swift` files found during Sprint 12 were removed after explicit approval; no duplicate files remain in that directory.
- No tracked cache/raster/direct-ink detour files remain in the current tree; remaining bloat is inside the current recognition path and broad editor surfaces.
- `EditorView.swift` no longer owns chord confirmation/correction sheet UI or the shared flow layout after Sprint 19. The old rhythm confirmation sheet path has since been removed entirely from `EditorView.swift`, `LeadSheetCanvasHostView.swift`, and the app target; Rhythm Section live auto-render now routes through V4 decisions plus `MeasureRhythmMap` commit authority instead of a confirmation modal. `LeadSheetCanvasHostView.swift` no longer owns chord edit overlay geometry, measure resize handle geometry, active ink-scope support, saved ink image rendering, active ink persistence write-back decisions, chord ink bounds/OCR image rendering, gesture/targeting support, note-selection lasso targeting, chord ink recognition target selection, chord recognition timing log formatting, chord recognition scheduling/continuation policy, rhythmic notation finalization policy/apply helpers, interaction-mode recognizer/canvas/tool policy, chord recognition request-state bookkeeping, or prepared recognition/OCR execution after Sprint 37, but it remains the largest live editor bridge.
- Sprint 34 audited the remaining editor-to-recognition execution path and found it is no longer obvious cleanup. The remaining chord path crosses async recognition, optional OCR, trust policy, proposal routing, chart mutation, diagnostics, and chord ink clearing, so further extraction should wait for an explicit recognition-session boundary design or product validation evidence.
- Sprint 37 implemented the first `ChordInkRecognitionSession` boundary defined in `docs/ichart-recognition-session-boundary-design-2026-05-25.md`. UIKit/PencilKit state, mode/scope guards, stale request validation, continuation-grace requeue, proposal routing, chart mutation, diagnostics, and chord ink clearing remain outside the session; the session owns prepared recognition execution, optional OCR evidence, timing construction, and main-thread payload delivery.
- Sprint 38 added app-target coverage proving the recognition session skips OCR sidecar work when the primary recognition decision does not need ambiguity evidence, even when an OCR provider exists. This is test-only hardening; it does not change runtime recognition behavior.
- Sprint 39 added a bounded renderer product-proof test using exactly three fixed ink fixtures (`C`, `Db7(b9)`, and `G/B`) to prove ink strokes can recognize into structured chords, clear page chord ink after commit, and appear in exported PDF text. This is product proof, not corpus expansion or training authority.
- Sprint 40 added bounded visual renderer QA for representative sample charts plus the Sprint 39 product-proof path, then fixed export-only defects found by that pass: late-measure chord/timing labels now shift left instead of clipping, and exported pages explicitly paint a white background for stable PDF thumbnails and image conversion.
- Sprint 41 centralized the successful chord-ink commit contract in `Chart.commitRecognizedChordInk`: a supported candidate appends a structured `ChordEvent`, stores the source ink evidence on that event, and clears the active chord ink pass; a failed target lookup leaves the active chord ink intact.
- Sprint 42 centralized the bounded product-proof cases in test support and made renderer product proof pass through the same live trust decision and commit contract as the editor path. `C` and `G/B` remain expected auto-render cases; `Db7(b9)` remains a supported but confirmation-gated close-race case.

## Product North Star

The product workflow remains:

```text
open -> write -> recognize -> snap -> fix -> export
```

Product rules:

- iChart is chord-first and rhythm-aware, not full notation software.
- Native Apple Pencil writing feel matters more than custom capture workarounds.
- Recognition proposes; structured chart objects decide.
- Correction speed matters more than perfect recognition.
- Raw ink should support reinterpretation, but the chart must not depend on raw ink alone.
- Recognition architecture must be writer-agnostic by default. Do not design, tune, or expand recognition systems around one person's repeated chord-writing passes.
- Any future personalization must be explicit user-specific product behavior with a separate opt-in data boundary. Until then, real Pencil validation is observation/regression evidence only, not training.
- Current chord-entry rule: accepting/rendering a chord consumes the chord-writing pass and clears the live chord ink layer, including other unrendered strokes from that pass. Do not preserve leftover chord ink after commit unless a future product sprint explicitly changes the writing workflow.

## Source-Of-Truth Pipeline

The live chord-recognition pipeline must converge to:

```text
native PKCanvasView ink
-> PencilKitInkAdapter
-> StrokeClusterer
-> GestureTemplateRecognizer
-> ChordInkCandidateComposer
-> ChordRecognitionCompendium / ChordSymbolParser
-> ChordInkRecognitionPolicy plus optional trust sidecar
-> structured ChordEvent commit
```

Current sidecars:

- OCR sidecar: optional, ambiguity-only, compendium-gated.
- Symbol ledger: diagnostics-only evidence, not a renderer or final chord authority.
- Diagnostic recorder/audit script: tooling path for simulator and archived passes, not product behavior.

Deferred sidecars:

- Raster/classifier evidence.
- Incremental symbol cache/session state.
- Fixture corpus pruning or deletion.
- CoreML/HOMUS expansion.

## Authority Rules

These rules are hard boundaries for Sprint 1 and future recognition work:

- `ChordRecognitionCompendium` and `ChordSymbolParser` are the only final validators for accepted chord tokens.
- `ChordInkCandidateComposer` is the only layer that should compose glyph columns into final chord-string candidates.
- `ChordInkRecognizer` should orchestrate the pipeline and collect metrics; it should not keep growing new semantic candidate authorities.
- `ChordRecognitionTrustArbiter` may decorate or support a primary decision, but it must not bypass compendium validation.
- Raw OCR text must never render or appear as a trusted suggestion unless it normalizes through the compendium.
- `ChordInkSymbolLedger` may explain or audit a result, but it must not auto-render a different answer on its own.
- Recognition must not own beat placement. The editor/layout layer decides where a structured `ChordEvent` lands.
- The editor owns chord ink lifecycle. Under the current product flow, a committed `ChordEvent` clears the chord ink layer instead of carrying forward unprocessed chord strokes.
- Native `PKCanvasView` stays the writing renderer unless a future sprint explicitly proves a better native-feeling path.
- Chord fixture capture is not a training loop. Add or keep fixtures only when they protect a transferable regression, represent a general chord/glyph shape, or document a product validation finding that should apply beyond one writer.
- Do not use the `Chord Writing Test Chart`, fixture watcher, or copied fixture JSON as a standing corpus-expansion habit. They are debug/regression tools.

## Active Sprint

### Sprint 70: App Functionality and UX/UI

Status: complete and pushed at `cf6c137 Advance Sprint 70 editor workflows`.

Goal: turn the proven editor core into a clearer app experience. Start with app-level functionality and UX polish that applies to the V1 active chart styles, while keeping recognition guardrails intact.

Sprint 69 closeout state:

- Sprint 69 is complete locally on `codex/rhythm-section-core-authoring`.
- The V1 readiness matrix is recorded at `docs/ichart-v1-readiness-matrix-2026-05-31.md`.
- No V1 blocker remains confirmed by the Sprint 69 audit.
- Simple Chord Sheet remains the product-proven handwritten/iReal-style chord-grid loop from Sprint 68 plus Sprint 69 persistence/export proof.
- Rhythm Section passed the final fresh app-surface gate for professional staff layout, suppressed header meter, native full-screen surface, v1 rhythm recognition, chord snapping, below-staff freehand, structured chart objects, and save/reopen behavior.
- Lead Sheet remains archived under `docs/post-v1/lead-sheet/` until after V1.

Completed Sprint 70 checkpoints:

- Chart-wide chord transposition is the first functionality slice.
- Chord transposition is not key-dependent; it stores a chart-level half-step offset and applies only to displayed/rendered chord symbols.
- Stored chord events, raw input, source ink evidence, correction signatures, beat placement, rhythm-slot mapping, and recognition behavior remain unchanged.
- Simple Chord Sheet and Rhythm Section Sheet both resolve rendered chord text through the same display authority.
- Typed-or-handwritten headers are the second functionality slice.
- Header handwriting is stored as raw header ink and does not add OCR, recognition, or global training behavior.
- Live ink responsiveness is the third functionality slice.
- Header/page/freehand ink stays local while actively writing and persists after stable idle or tool exit.
- Chord/rhythm ink-session unification is the fourth functionality slice.
- Chord, rhythm, and passive ink now share dirty-canvas protection and stable scheduled-work snapshot rules without retuning recognition.
- User pen responsiveness is the fifth functionality slice.
- The setting is an app/user preference exposed under Page > Pen Responsiveness and changes live input scheduling only, not recognition authority.
- Measure double barlines are the sixth functionality slice.
- The first measure always begins with a leading double barline, and the Measures menu can add a measure whose trailing barline is double.
- Chord-tool rendered chord correction is the seventh functionality slice.
- Chord mode now keeps writing active in empty chord-lane space while all rendered chord boxes are immediately active for deletion, review, and movement without switching to Select; active chord drags lock parent chart scrolling.
- Editor back-swipe locking is the eighth functionality slice.
- The editor route disables iOS back-swipe by hiding the system back button and replacing it with an explicit top-left exit arrow.
- Rhythm Section system breaks are the ninth functionality slice.
- Measure-menu `New System Before This Measure` and `Remove System Break` now work for Rhythm Section charts through forced `ChartSystem` boundaries while preserving automatic packing/stretching inside each rendered row.
- Rhythm Section system visual alignment is the tenth functionality slice.
- Rhythm Section continuation rows now reserve the same measure gutter as the first row and staff lines stop at visible system barlines/repeat markers.
- Rhythm Section standard measure widths are the eleventh functionality slice.
- Default Rhythm Section measures now use the first rendered system's measure width across later rows, while explicit manual widths remain user-authored exceptions.
- Measure stack deletion is the twelfth functionality slice.
- The Measures menu can delete the selected measure through the model cleanup path, preserving the one-measure minimum and removing attached measure objects with it.
- Controlled measure range deletion is the thirteenth functionality slice.
- The Measures menu can delete a user-bounded inclusive range through the same model cleanup path, preserving at least one measure.
- Measure-menu stack insertion is the fourteenth functionality slice.
- The Measures menu can insert a user-counted stack after the selected measure, preserving centralized reindexing/system rebuild behavior.

Moved to Sprint 71 continuing order:

1. Project/library UX: rename, duplicate, delete, clearer metadata, and less developer-facing library behavior.
2. Export/share UX: obvious export flow, PDF preview confidence, file naming, and app-created export proof.
3. Save/reopen confidence: visible but quiet saved-state behavior.
4. Toolstrip/menu affordances: remaining naming, hit-target, and active-menu state polish.

Guardrails remain unchanged:

- No chord-recognition retuning.
- No OCR expansion.
- No personal handwriting fixture expansion.
- No default diagnostics stream.
- No Lead Sheet feature expansion before V1.

### Sprint 71: V1 Product Readiness and Release Hardening

Status: opened locally.

Goal: harden the proven active V1 app into a production-ready product surface while the broader visual/UI overhaul can proceed independently.

Active scope:

- Simple Chord Sheet and Rhythm Section Sheet remain the only active V1 chart styles.
- Lead Sheet remains post-V1/compatibility only.
- Project/library, save/reopen, export/share, and release hygiene are the main Codex-owned lanes.
- Recognition guardrails remain unchanged.

Current Sprint 71 checkpoint:

- Project/library actions are implemented locally and pushed.
- Export/share confidence is implemented locally as the second slice.
- The exporter returns `ExportedPDF` metadata, readable file names, and PDF preview/share metadata without changing the renderer.
- Save/reopen confidence is implemented locally as the third slice with a quiet persistence-status badge in Library and Editor.
- Release hygiene is deferred into a separate future sprint so pipeline/testing work can get its own clean lane.
- The current app-appearance pass locks the home page to the iChart adaptive sidebar with `Charts`, `Forums`, `Help`, and `Settings`.
- The universal iChart logo now lives in the sidebar as the full B4.8A-H1 canon wordmark with the italic `i` bottom-aligned to `hart`; home tabs, including `Charts`, do not repeat the logo in their content headers.
- The sidebar wordmark now uses a larger centered home-header size so it fills the top-left logo space without clipping or crowding the tab stack.
- Sidebar tab icon/text groups are centered under the wordmark while retaining full-width tab hit targets.
- The bottom of the sidebar owns persistent sun/moon Light and Dark mode controls for the home shell only. Light keeps the Paper Workbench workspace; Dark switches the surrounding workspace to Stage Workbench while keeping chart rows paper-first and leaving editor/chart rendering unchanged.
- The sidebar can now collapse/open while preserving the active home destination, and `FAQ`, `User Policy`, `Legal`, and `Contact Us` live inside the `Help` surface instead of duplicating under the mode switch.
- The Charts tab now drops the redundant top header, centers `New Chart`, shows Basic chart usage only for capped users, simplifies chart rows, and lets the user switch row previews between `Collapsed`, `Quick`, and `Large` modes.
- The launch-handwriting overlay remains canon and uses the bundled canonical handwriting sample on every boot. The Settings capture surface and export helper are removed from the product path; launch handwriting is a backend/product asset, not a user preference.
- Chord ink recognition no longer treats the idle timer as user-facing commit authority. Idle recognition remains available as the `automaticPreview` path, while rendered chord commit and confirmation-sheet presentation use the separate `tapToConfirm` path from Chord mode. Tap-confirm bypasses continuation grace so the app does not add another timer after the user indicates they are done. The split is codified through `ChordInkRecognitionFlow`, `ChordInkAutomaticRecognitionPolicy`, `ChordInkTapConfirmGesturePolicy`, and `ChordInkRenderResolutionPolicy`; legacy names remain only as deprecated aliases. Verification: focused XcodeBuildMCP simulator `ChordInkAutomaticRecognitionPolicyTests`, `ChordInkRenderResolutionPolicyTests`, and `LeadSheetInteractionModeStatePolicyTests` passed with `56` tests and `0` failures; full SwiftPM passed with `501` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only, and simulator screenshot confirmed the iChart home shell.

Candidate Sprint 71 continuing order:

1. Continue app UI/UX appearance on the locked iChart shell.
2. Toolstrip/menu affordances: only targeted polish not covered by the user-side UI overhaul.
3. Verify launch animation transition polish with a timed simulator launch-frame pass.
4. Future separate release hygiene sprint: build settings, app metadata, stale-doc audit, PR/CI readiness, and pipeline/testing work.

### Rhythm Section Side Sprint: Core Authoring

Status: core implementation complete locally on `codex/rhythm-section-core-authoring`; deferred product systems are definition-gated.

Goal: implement the first dedicated Rhythm Section core authoring slice after Sprint 67 locked the current workflow designation.

Current state:

- Sprint 67 is the lock checkpoint: Rhythm Section remains keyless at setup/header, keeps staff-line measures, keeps the chord lane above staff, and keeps rhythm-map chord snapping plus beat fallback.
- This side sprint added profile-owned free-hand symbol policy. Current active policy after the Sprint 68 Simple pivot: Simple Chord Sheet uses measure-attached chart-area freehand objects, Rhythm Section supports below-measure articulations only, and Lead Sheet supports no free-hand symbol lanes for now.
- Measures can now be inserted at the beginning through a chart-editing API that reindexes existing measures and preserves existing measure IDs/anchors.
- The Measures tab is being split into explicit menu actions for edit, add at beginning, and add after selected.
- Rhythm tap-to-render is the current loop on the overhaul branch: exact-fit rhythm passes can analyze and surface a ready state, but handwritten rhythm maps commit only when the user taps outside/finalizes the active writing box. Underfilled, overflow, unsupported, ambiguous, uncovered, review-only, or context-blocked passes preserve local ink.
- `RhythmicNotationCompendium` gates committed rhythm maps to the supported v1 rhythm vocabulary and exact meter fit.
- Rhythm ink now has the same dirty live-canvas ownership guard as chord ink. The idle path persists/analyzes stable raw rhythm ink and can show "Tap outside to render", but it no longer clears ink or writes a rhythm map by timer.
- Beamed eighth recognition now includes focused sloped and folded-beam grouping rules: a simple upward/downward beam stroke can seed a beamed-eighth event only when it spans two rhythm stems, and a folded beam/right-stem stroke can seed a beamed-eighth event only when paired with notehead evidence.
- The latest simulator ink diagnosis showed a folded beamed-eighth pair plus a quarter being falsely accepted as `dottedHalf, quarter`. Visual beamed-eighth reads now block fallback reinterpretation when they are underfilled, so visible beamed ink cannot be stretched into a longer dotted value just to satisfy exact meter fit.
- The follow-up simulator pass showed beamed eighths still failing when the first eighth of a last-beat pair looked like a complete quarter. Auto-render now uses `RhythmicNotationMeasureProposal` instead of only raw values: the compendium can still find exact-fit values, but the host delays ink clearing for terminal quarter-like stems that could still become an eighth pair.
- Rhythm Recognition V2 now treats exact meter fit as readiness, not timer commit authority. A proposal carries `autoApply`, `extendedStability`, or `manualReview` safety for trust analysis, while `LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy` allows stable selected rhythm ink to be analyzed during idle, `LeadSheetRhythmicNotationLiveDecisionPolicy` returns `readyToRender`, and rhythm maps commit only when tap/finalization explicitly allows commit.
- All live ink canvas tools now expose a left-side ink tool tab with write and erase boxes. Opening an ink tool resets the tab to write mode; erase mode swaps the active `PKCanvasView` to a bitmap eraser so the stylus wipes only live ink strokes, not rendered chords, rhythm maps, or saved free-hand symbols.
- Rhythm erasing cancels stale pending auto-render work and enters a stricter post-erase gate: auto-render and explicit finalization can still commit when erasing an extra symbol makes the remaining ink naturally exact-fit, but they will not commit a stretched/reinterpreted exact-fit path just to fill missing beats.
- The latest raw-ink simulator trace found the actual beamed-eighth failure in the visual pass: a single notehead was being claimed as an eighth rest before its attached stem/dot could form a dotted-half note, and a touched-up right stem in a beamed pair could be left uncovered, forcing fallback reinterpretation. The visual layer now blocks that notehead steal and folds local beamed touch-up strokes into the beamed-eighth event, so the traced raw ink proposes `dottedHalf, eighth, eighth` as a natural exact fit.
- The follow-up simulator pass showed the larger recognizer problem: a later measure had `visual=nil`, then fallback meter-fit selected `quarter, dottedQuarter, dottedQuarter` even though the raw ink should not have been trusted as that phrase. Rhythm Recognition V3 is now opened as a bottom-up rebuild plan; the immediate safety gate blocks all non-natural exact-fit proposals from live auto-render and selection finalization.
- Rhythm Recognition V3 first slice is now implemented locally. It adds ordered ink primitives, symbol hypotheses, phrase hypotheses, and explicit `commit` / `keepWriting` / `needsReview` decisions; live auto-render and selection finalization require `commit`, while fallback-created exact fits cannot clear ink.
- Rhythm Recognition V3 visual-rest slice is now implemented locally. Quarter rests, half rests, and whole rests are first-class visual hypotheses; quarter/half rest phrases can commit when naturally exact, single whole-rest measures remain review-only, and clear quarter-rest bodies are protected from eighth-rest or beamed-eighth stealing.
- Rhythm Recognition V3 phrase-ambiguity slice is now implemented locally. Tight adjacent rest/note clusters can still be manually quantized, but live auto-render marks them `needsReview(.ambiguousPhrase)` so visually entangled ink is not cleared by an overconfident exact-fit pass.
- Rhythm entry now auto-resolves a measure target. If Rhythm mode starts or resumes with no selected measure, the editor chooses the current valid selection, the open measure, or the last measure so live rhythm ink has a measure-owned canvas before writing.
- Rhythm auto-apply stability now compares a stroke-shape snapshot instead of serialized PencilKit `Data`, preventing unchanged visible ink from going stale because of PencilKit metadata changes.
- Temporary runtime auto-apply trace logging and the one-off live-trace replay helper were removed after the stable snapshot pass was verified, so no new default rhythm diagnostic stream remains in the app path.
- Rhythm Recognition V3 now reports uncovered visual strokes explicitly. If an otherwise exact visual phrase has leftover visible ink, the decision stays in the V3 path as `keepWriting(.uncoveredStrokes)` and preserves the live ink instead of falling through to legacy meter fitting.
- Rhythm Recognition V3 now reports close full-measure alternatives as `needsReview(.competingExactPhrases)`, keeping near-tied exact phrase reads out of the confident auto-render path while preserving low-information whole-measure marks as generic manual review.
- Rhythm Recognition V3 now keeps non-visual fallback exact fits local as `keepWriting(.nonVisualFallback)` with no proposal. Manual quantize can still use the legacy fitter for tooling and diagnostics, but live auto-render and selection finalization do not get fallback-created exact-fit proposals.
- Rhythm unread-ink feedback now highlights completed-looking non-commit rhythm ink only when it can target a localized unread symbol or primitive. Underfilled/no-ink states stay quiet; V3 uncovered-stroke decisions target unread primitive bounds directly, and broad review/fallback states do not fall back to whole-measure framing. The feedback does not persist, train the recognizer, retune scores, or add a default diagnostic stream.
- Rhythm Recognition V4 is now implemented locally as a raster/template phrase gate. It builds measure-relative symbol crops from live rhythm ink, matches those crops against a deterministic visual compendium for the v1 vocabulary, validates exact phrases through `RhythmicNotationCompendium` and `MeasureRhythmMap`, and requires render alignment before auto-commit. V3 remains the fail-closed bridge for states V4 cannot naturally own.
- Rhythm unread-ink feedback now prefers V4 unread-symbol crop bounds when a crop has no accepted value and the phrase is completed-looking, then uses V3 uncovered-stroke bounds when available; broad review states stay quiet until they can localize the unread item.
- V4 semantic visual gating is now implemented locally. Slashes require slash evidence instead of notehead/stem evidence, dotted values require detached dots, and single eighth values require flag or beam evidence; unflagged quarter-like stems can delay/review but cannot auto-render as eighths by meter fit alone.
- V4 rest and long-value phrase coverage is now broadened locally. Quarter rests, half rests, whole-rest review, dotted quarter, dotted half, adjacent eighth rests, and mixed long-value phrases can be owned by the raster/template source when the crops are complete. Rest-owned crops no longer carry note alternatives into the exact-fit competition, and adjacent eighth-rest dots are reattached to their following tails after compound symbol splitting.
- V4 non-exact phrase ownership is now implemented locally. Strong template underfills and overflows stay local, completed unsupported crops can surface localized unread-symbol evidence, single-unit unflagged-stem exact alternatives are manual review only, and beamed-template overcount cases fall back to the existing visual bridge rather than blocking known-good beamed reads.
- V4 raster normalization now rejects tiny isolated noise marks before crop grouping, and V4 render-comparison tests cover both bad-spacing rejection and aligned exact-fit acceptance.
- V4 internals now live in `RhythmicNotationRasterTemplateRecognizer.swift` beside the quantizer, preserving the current public rhythm proposal entrypoint while separating raster/template authority from the older bridge.
- Rhythm recognition proposal/decision/phrase/candidate types now live in `RhythmicNotationRecognitionTypes.swift`, preserving behavior while making V3/V4 contracts explicit.
- The closeout audit for Rhythm Section V4 is recorded in `docs/ichart-rhythm-section-v4-closeout-audit-2026-05-29.md`; remaining chart-style system work is explicitly definition-gated.
- Chord layouts now expose a snap-guide target so the active chord move can show the resolved beat/rhythm attack connection.
- Main layout work has resumed after the Rhythm Section detour. Lead Sheet now renders selected treble/bass clefs, places transposed key-signature accidentals before the first measure's time signature, and has the first pitched-entry proof: accepted Lead Sheet rhythm ink can create clamped in-staff pitched-note events through V4 visual note anchors, including mixed note/rest phrases where only note-capable slots become pitched notes and every note-capable slot must have an anchor. Ledger lines, named pitches, and individual note editing remain deferred.
- User-facing rhythm-note editing, freehand symbol ink availability, and rhythmic-notation ink availability are now `ChartLayoutProfile` contracts instead of editor-local style branches. Rhythm Section and Simple keep rhythm-note editing disabled; Simple has no rhythmic-notation ink scope; Rhythm Section and Lead Sheet keep rhythm-notation ink scopes; Lead Sheet keeps access to the existing note/rhythm edit surface but has no freehand ink scope until that product slice is defined.

Step-by-step plan:

1. Branch/docs first. Status: complete.
   - Branch from the current Sprint 64-67 working tree.
   - Add the Rhythm Section side-sprint plan and dedicated chart-plan artifacts.
2. Profile-owned free-hand symbol lanes. Status: implemented locally; focused tests passing.
   - Drive add/move/delete and layout resolution from `ChartLayoutProfile.freehandSymbolLanes`.
   - Keep Rhythm Section free-hand symbols below-staff only.
3. Measure menu and beginning insertion. Status: implemented locally; focused tests passing.
   - Add explicit Measures menu actions.
   - Add beginning insertion without changing the one-measure invariant.
4. Rhythm pipeline auto-render. Status: complete locally through the V3 fail-closed bridge and V4 raster/template phrase gate.
   - Auto-commit exact-fit rhythm passes only after the first exact-fit candidate survives the grace-window recheck.
   - Require `RhythmicNotationMeasureProposal.canAutoApply` before the live host clears ink and commits a rhythm map.
   - Keep `MeasureRhythmMap`, `RhythmicNotationCompendium`, and resolved slots as the placement authority.
   - Preserve dirty rhythm ink in the active `PKCanvasView` when model data is stale during fast writing.
   - Do not persist raw rhythm ink during idle auto-render checks; only grace-confirmed exact-fit commit or explicit finalization touches the chart model.
   - Treat sloped and folded handwritten beams as beamed-eighth connectors when they carry local stem/notehead evidence; keep the compendium and exact meter fit as the final commit gate.
   - Route auto-render through `RhythmicNotationMeasureProposal` so terminal quarter-like stems with an eighth alternative get an extra stability window instead of clearing before a last-beat beam can land.
   - Add the write/erase ink tool tab to every active canvas ink mode while keeping eraser effects inside the live ink layer only.
   - After erasing rhythm ink, require the next auto-render or explicit finalization proposal to be a natural exact-fit path unless the user writes replacement ink.
   - Keep the visual rhythm pass from stealing a stemmed notehead as an eighth rest, and include local beamed touch-up strokes in the protected beamed-eighth event before falling back to per-symbol exact-fit stretching.
   - Treat exact meter fit as a validation gate only: live auto-render and selection finalization now require the proposal's natural left-to-right read to be the exact measure, so fallback meter-fit rewrites cannot clear ink.
   - Rebuild the recognizer around raw ink primitives, symbol hypotheses, phrase hypotheses, and explicit `commit` / `keepWriting` / `needsReview` decisions before further symbol tuning.
   - Route the live host through V3 decisions: only `.commit` can schedule render/clear, while `.keepWriting` and `.needsReview` preserve local ink.
   - Surface completed-looking non-commit rhythm decisions with a local red dashed unread-ink overlay only when the unread item can be localized, without highlighting underfilled/no-ink states or changing recognizer authority.
   - Use V3 uncovered-stroke evidence to target unread primitive bounds when available; do not fall back to the full live-ink frame for broader review/fallback decisions.
   - Route strong visual rhythm evidence through the V4 raster/template phrase gate before V3: crop live ink left-to-right, match against the v1 visual compendium, validate exact values through the rhythm compendium and `MeasureRhythmMap`, and require render alignment before clearing ink.
   - Keep legacy fallback from auto-rendering live exact fits; unsupported crops and ambiguous or non-authoritative phrases stay local with targeted unread feedback when available.
   - Require semantic visual evidence before V4 exact-fit commits: stemmed notehead crops cannot become slashes, dotted values need detached dot evidence, and single eighth values need flag or beam evidence unless the result is review/stability-only.
   - Keep V4 rest crops rest-owned when rest evidence is strongest, protect strong quarter/half/whole rest matches from generic eighth-rest hooks, and reattach adjacent eighth-rest dots to their following tails after compound symbol splitting.
   - Reject tiny isolated raster noise before V4 crop grouping without letting meaningful unsupported strokes disappear, and pin render comparison with both aligned and bad-spacing tests.
   - Keep the V4 raster/template core separated in `RhythmicNotationRasterTemplateRecognizer.swift` so future symbol work does not re-bloat the public quantizer entrypoint.
   - Keep shared rhythm recognition contracts and candidate/path structs separated in `RhythmicNotationRecognitionTypes.swift`.
5. Chord snap guide. Status: implemented locally; focused tests passing.
   - Attach chord layouts to resolved snap targets.
   - Draw the active moving chord guide line to the resolved target.
6. Lead Sheet baseline continuation. Status: implemented locally for key signature, clef glyph layout, and first mixed pitched-note/rest proof.
   - Render treble/bass clefs from `Chart.defaultClef`.
   - Place transposed key-signature sharp/flat glyphs between the clef and first measure time signature.
   - Commit Lead Sheet rhythm phrases as clamped in-staff pitched-note events when V4 visual note anchors match the note-capable slots in the accepted values.
   - Keep ledger lines, named pitches, and note editing deferred.
   - Preserve Rhythm Section keyless setup and Simple blank-measure rendering.
7. Verify. Status: complete locally.

Non-goals:

- No chord-recognition retuning.
- No OCR expansion.
- No handwriting fixture expansion.
- No default symbol-ledger diagnostics cost.
- No Section/System layout behavior.
- No Lead Sheet ledger-line, named-pitch, or note-editing implementation.

Current local verification:

- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `43` tests, `0` failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `33` tests, `0` failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter MeasureRhythmMappingTests` passed with `17` tests, `0` failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, `0` failures.
- XcodeBuildMCP focused `test_sim` for terminal quarter-like stem proposal gating, completed last-beat folded beams, folded beamed-eighth success, and ambiguous-stem grace policy passed with `4` tests, `0` failures.
- XcodeBuildMCP focused `test_sim` for Rhythm Recognition V2 whole-measure safety passed with `4` tests, `0` failures: single whole-note values remained quantizable, early single whole-measure proposals required manual review before auto-apply, tiny whole-like marks could not auto-apply, completed last-beat beams still auto-applied, and terminal quarter-like stems still requested extended stability. The later V4 whole-note checkpoint supersedes this for strong hollow-notehead evidence only.
- XcodeBuildMCP focused `test_sim` for ink write/erase policy passed with `3` tests, `0` failures: write mode preserves the original chord pen, erase mode uses a PencilKit eraser for ink modes, and non-ink modes ignore erase mode.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `56` tests, `0` failures, including connected, loose, direct, sloped, folded, false-exact-fit, last-beat beam, extended-stability auto-apply, V2 manual-review safety, ink write/erase policy, and post-erase natural exact-fit coverage.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `46` tests, and `0` failures after adding the touched-up trailing beamed-eighth regression and verifying the copied simulator raw-ink trace now proposes `dottedHalf, eighth, eighth` naturally for the previously misrendered measure.
- Latest raw-ink trace for the new bad pass showed measure 2 rendered from `visual=nil` through fallback exact-fit `quarter, dottedQuarter, dottedQuarter`; after the natural-exact-fit safety gate, the same proposal reports `proposal.canAutoApply=false`.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `57` tests, and `0` failures after blocking non-natural exact-fit rhythm commits.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, and `0` failures after the fail-closed rhythm safety gate; `git diff --check` passed.
- Earlier XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetChordEditOverlayGeometryTests`, and `LeadSheetFreehandSymbolEditOverlayGeometryTests` passed with `45` tests, `0` failures.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `51` tests, and `0` failures after the V3 visual-rest slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `62` tests, and `0` failures after the V3 visual-rest slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `63` tests, and `0` failures after the V3 phrase-ambiguity slice.
- XcodeBuildMCP focused `test_sim` passed with `4` tests and `0` failures after adding rhythm-entry measure resolution and V3 slash-decision regressions.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `110` tests, and `0` failures after the rhythm-entry measure selection repair.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the rhythm-entry measure selection repair.
- XcodeBuildMCP `test_sim` for `LeadSheetInteractionModeStatePolicyTests` passed with `12` tests and `0` failures after replacing serialized-data equality with stable rhythm ink snapshots.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `111` tests, and `0` failures after adding stable rhythm auto-apply snapshots.
- Latest live simulator pass after the stable snapshot repair matched the expected outcome: measure 1 committed `slash, slash, slash, slash`; measure 2 committed `quarter, quarter, quarter, eighth, eighth`; follow-up underfilled/ambiguous attempts stayed local.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the stable rhythm auto-apply snapshot repair; `git diff --check` passed.
- After removing temporary runtime auto-apply trace logging and the one-off live-trace replay helper, XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` still passed with `111` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` still passed with `354` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded and relaunched the app.
- XcodeBuildMCP focused `test_sim` for non-visual fallback exact-fit handling passed with `1` test and `0` failures after confirming fallback-created exact fits stay local with no proposal; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `115` tests and `0` failures.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the non-visual-fallback slice; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only and screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for unread rhythm ink feedback policy and frame geometry passed with `2` tests and `0` failures after the unread-ink-feedback slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `117` tests and `0` failures after the unread-ink-feedback slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the unread-ink-feedback slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the unread-ink-feedback slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP focused `test_sim` for unread rhythm ink feedback policy, full-frame fallback, and targeted uncovered-stroke frame geometry passed with `3` tests and `0` failures after the targeted-unread-stroke-feedback slice.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `80` tests and `0` failures after the V4 raster/template phrase gate and crop-level unread feedback slice.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `125` tests and `0` failures after the V4 raster/template phrase gate.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 raster/template phrase gate.
- `git diff --check` passed after the V4 raster/template phrase gate, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only; screenshot proof showed the app launched to Projects.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `67` tests and `0` failures after the V4 semantic visual gate.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `128` tests and `0` failures after the V4 semantic visual gate.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 semantic visual gate; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V4 semantic visual gate with the existing headermap warning only.
- XcodeBuildMCP `test_sim` for `LeadSheetInteractionModeStatePolicyTests` passed with `17` tests and `0` failures after tightening unread feedback to completed-looking, localized targets only.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `129` tests and `0` failures after the unread-feedback targeting rule.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the unread-feedback targeting rule; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the unread-feedback targeting rule with the existing headermap warning only.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `69` tests and `0` failures after broadening V4 rest, dotted, and long-value phrase coverage.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `131` tests and `0` failures after the V4 rest-crop ownership slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 rest-crop ownership slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V4 rest-crop ownership slice with the existing headermap warning only; screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for V4 underfill, overflow, unsupported-crop, and unflagged-eighth review gates passed with `5` tests and `0` failures after the V4 non-exact ownership slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `72` tests and `0` failures after the V4 non-exact ownership slice.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `134` tests and `0` failures after the V4 non-exact ownership slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 non-exact ownership slice.
- `git diff --check` passed after the V4 non-exact ownership slice, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for V4 noise rejection plus Lead Sheet key-signature layout, bass-clef key-signature positions, and key-header guard coverage passed with `4` tests and `0` failures after the V4 normalization and Lead Sheet baseline slice.
- XcodeBuildMCP focused `test_sim` for Lead Sheet pitched-note finalization passed with `2` tests and `0` failures, and `RhythmicNotationQuantizerTests` passed with `76` tests and `0` failures after adding V4 visual note anchors and stem-down quarter protection.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `182` tests and `0` failures after the Lead Sheet pitched-note baseline.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `360` tests, `36` skipped, and `0` failures after the Lead Sheet pitched-note baseline; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures after tightening Lead Sheet pitch coverage to require every note-capable rhythm slot.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `176` tests and `0` failures after the V4 render-comparison acceptance coverage and Lead Sheet key-signature baseline.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `356` tests, `36` skipped, and `0` failures after the V4 render-comparison acceptance coverage and Lead Sheet key-signature baseline.
- `git diff --check` passed after the V4 normalization and Lead Sheet key-signature baseline, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `118` tests and `0` failures after the targeted-unread-stroke-feedback slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the targeted-unread-stroke-feedback slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the targeted-unread-stroke-feedback slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, and `0` failures after the V3 phrase-ambiguity slice; `git diff --check` passed.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, and `0` failures after the V3 visual-rest slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded and launched on `iPad Pro 13-inch (M5)` with the existing headermap warning only; the latest Rhythm Section chart was reopened in `Rhythmic Notation` mode, the left ink tool tab appeared in write mode, and tapping the eraser switched the highlighted mode.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V3 decision slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V3 visual-rest slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V3 phrase-ambiguity slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the rhythm-entry measure selection repair with the existing headermap warning only; screenshot proof showed the simulator on a Rhythm Section chart in `Rhythmic Notation` mode with write mode active and a measure selected.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after the behavior-preserving V4 core extraction; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after the shared recognition-type and candidate/path extraction; grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.

### Sprint 67: Rhythm Section Current Workflow Lock

Status: complete locally; retained as the workflow-lock checkpoint before the completed Rhythm Section side sprint.

Goal: make `Rhythm Section Sheet` explicitly mean the current basic iChart workflow without changing renderer behavior.

Current state:

- Sprint 66 is complete locally: setup/profile defaults are wired and the first Simple Chord Sheet blank-measure branch is verified. Its original Simple above/below free-hand capture path is now historical and superseded by the Sprint 68 measure-attached chart-area freehand model.
- Rhythm Section Sheet has already been defined by the user as the existing basic chart workflow: no official key setup for now, starting time/starting measures, real staff-line measures, rhythms written between barlines, chords in the chord lane above the staff, rhythm-aware chord placement when rhythms exist, and beat-grid fallback when they do not.
- Sprint 67 should lock that designation in tests/docs before any new rhythm-section system work.
- The first Sprint 67 implementation checkpoint added a focused layout regression that pins key suppression, meter/header retention, staff lines, leading notation, no Simple Chord Sheet above-lane leakage, rhythm-map note layouts, chord lane above staff, and chord alignment to rhythm attack centers.

Sprint 67 step-by-step plan:

0. Close Sprint 66 locally. Status: complete.
   - Keep Sprint 66 pending final commit in the current local change set.
   - Preserve its verified Simple Chord Sheet capture/render/select/move/delete behavior.
1. Add Rhythm Section workflow lock coverage. Status: complete.
   - Pin the current workflow designation with a focused layout test.
   - Avoid production behavior changes unless a test exposes real drift.
2. Verify proportionally. Status: complete.
   - Run the focused `LeadSheetPageLayoutTests` guard for Rhythm Section.
   - Run the full SwiftPM suite after doc updates.
   - Use simulator compile only if app-target behavior changes.
3. Pause before new Rhythm Section systems. Status: complete; the active Rhythm Section side sprint now owns the next slice.
   - New rhythm-section layout/system changes should be separately scoped with the user.
   - Candidate future slices include rhythm cue editing polish, move-to-rhythm-slot UX, measure grouping, and section/cue surfaces.

Non-goals:

- No recognition, parser, compendium, OCR, symbol-ledger, or fixture changes.
- No key setup reintroduction for Rhythm Section Sheet.
- No Simple Chord Sheet above-measure free-hand lane leakage into Rhythm Section Sheet.
- No Lead Sheet pitched-note work.
- No broad renderer/export rewrite.

Acceptance criteria:

- `Rhythm Section Sheet` remains keyless at setup and in the header.
- It still renders the current staff system with clef/time-signature leading notation.
- Rhythms render between barlines when a rhythm map exists.
- Chords render above the staff and align to written rhythm attack centers.
- Above-measure free-hand lanes stay Simple-only; Rhythm Section below-measure articulation lanes are introduced only by the Rhythm Section side sprint.
- The sprint source-of-truth remains the first routing document.

Current local verification:

- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests/testRhythmSectionSheetPreservesCurrentRhythmAndChordWorkflow` passed with `1` test, `0` failures after adding the Rhythm Section workflow lock guard.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `348` tests, `36` skipped, `0` failures after opening Sprint 67 and adding the Rhythm Section workflow guard.

### Sprint 66: Profile-Driven Structure Defaults

Status: complete locally; retained here as Sprint 67 context until the combined local change set is committed.

Goal: decide whether the Sprint 65 layout-profile contracts should shape newly created chart structure and setup policy while keeping renderer/export behavior conservative.

Current state:

- Sprint 63 completed the chart-layout product taxonomy and selected `ChartLayoutStyle` as the implementation name.
- Sprint 64 implemented the durable New Chart chooser slice and verified the simulator picker flow.
- Sprint 65 implemented `ChartLayoutProfile` contracts for toolbar emphasis, measure defaults, notation-lane intent, and renderer routing.
- The chord-first release-candidate path remains the current working app baseline.
- Renderer branching has started only for the scoped `Simple Chord Sheet` blank-measure skeleton and Simple measure-attached chart-area freehand symbols. Rhythm Section Sheet and Lead Sheet still use the current staff renderer path.
- Further per-style renderer/system-layout work remains deferred until each slice is explicitly scoped with the user.
- `Simple Chord Sheet` is now defined: no key at setup, starting time/starting measures, default one measure if no extras are chosen, empty barline-to-barline measure space, chord writing inside measure white space, chart-paper freehand drawing that persists as editable/moveable measure-attached objects, and base-meter-aware chord placement without requiring rhythm-aware snapping.
- `Rhythm Section Sheet` is now defined as the current basic chart workflow: no official key setup for now, starting time/starting measures, real staff-line measures, rhythms written between barlines and snapped to the measure, chords written above in the chord lane, chords snapping to written rhythms and movable to other rhythms, and automatic beat-1 chord placement when no rhythm exists in a measure.
- `Lead Sheet` is now defined as the future notation-like layout: key/time signature/starting measures/clef setup, treble and bass clef only, staff-line measures, key-signature accidentals plus time signature before the first measure, no ledger lines for now, eventual written note/rhythm snapping to rhythm and staff-line pitch, and the normal chord lane above the measure.
- Sprint 66 has a model-level setup-policy contract: Simple Chord Sheet and Rhythm Section Sheet omit key/clef setup for now; Lead Sheet requires key and offers treble/bass clef only; all three keep time-signature and starting-measure setup.
- Shared chart-style invariant: no chart layout may offer or create a zero-measure chart. Starting-measure defaults and controls must clamp to at least `1`.
- The New Chart setup sheet now follows that setup policy: Simple Chord Sheet and Rhythm Section Sheet hide key/clef, Lead Sheet shows key and treble/bass clef, and all three keep time-signature plus starting-measure setup.
- `Chart.defaultClef` is persisted with legacy decode defaulting to treble. Initial setup stores the selected clef and creates `max(1, startingMeasureCount)` measures.
- New initial measures, appended/open measures, and `Chart.blank` measures now use the selected layout style's beat-grid default; initial/blank systems use the selected layout style's spacing mode.
- Preferred measures per system remains a profile contract for now. Executable system regrouping is deferred because changing rebuild chunking would alter the current rhythm-section workflow before the layout renderer slice is explicitly scoped.
- The first Simple Chord Sheet renderer slice now omits key header text, clef, leading time-signature glyphs, staff lines, slash/rhythm note rendering, and open-measure hint marks; it places the chord-writing band inside the blank measure body and keeps the blank space bounded by normal barlines.
- Simple Chord Sheet now has a free-hand symbol object path: chart-area lane only, measure-anchored `FreehandSymbol` objects, measure-relative frames, raw ink drawing data, z-order, editor/PDF rendering, chart-paper stroke capture, tap selection, paper-clamped drag/move with nearest-measure reanchoring, and delete controls.

Sprint 66 step-by-step plan:

0. Complete the user definition gate. Status: complete.
   - `Simple Chord Sheet` is defined.
   - `Rhythm Section Sheet` is defined as the current workflow designation.
   - `Lead Sheet` is defined as a small lead-sheet baseline; richer melody editing, ledger lines, and named pitch behavior remain deferred.
   - Record what stays common across all layouts before writing code.
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
   - Add focused model/editing tests for each layout style's initial structure.
   - Run the full SwiftPM suite after focused tests pass.
   - Run an iOS simulator compile if app-target coverage is touched.
5. Implement the smallest Simple Chord Sheet layout branch. Status: complete for blank-measure skeleton.
   - Hide key/staff/clef/leading time-signature visuals for Simple Chord Sheet.
   - Put the chord-writing band inside the blank measure body.
   - Keep rhythm-section refinement and richer lead-sheet melody/editing systems deferred.
6. Implement the first Simple free-hand symbol object checkpoint. Status: complete for capture/render/edit.
   - Store Simple free-hand symbols as measure-anchored raw ink objects in the chart-area lane.
   - Render saved free-hand symbols in the editor and PDF export.
   - Do not allow free-hand symbol capture in the chord lane.
   - Select saved symbols, move them across chart paper with nearest-measure reanchoring, and delete selected symbols.
   - Keep resizing, semantic classification, and rhythm snapping deferred.

Non-goals:

- No personal handwriting fixture expansion.
- No recognition score retuning from one writer's pass.
- No parser or compendium authority change.
- No default OCR expansion or symbol-ledger diagnostics cost.
- No broad layout-specific renderer/export rewrite beyond the scoped Simple Chord Sheet blank-measure skeleton and chart-area free-hand symbol rendering/editing.
- No full notation, melody-entry, playback, or broad editor rewrite.
- No layout-changing UI after chart creation until conversion rules exist.
- Keep existing saved chart decode compatibility intact.

Acceptance criteria:

- Layout profiles define key, time-signature, starting-measure, and clef setup policy.
- New draft setup uses layout-profile initial measure count.
- No layout can offer or create a zero-measure chart.
- New systems use layout-profile spacing mode.
- Preferred measures per system is pinned in profile tests but remains deferred as executable regrouping.
- New measures use layout-profile beat-grid defaults.
- `Lead Sheet` remains compatible with the current renderer path and four-measure system grouping.
- `Simple Chord Sheet` renders a blank barline-to-barline measure body without staff/key/clef/leading-time-signature visuals.
- Simple free-hand symbols persist as chart-area objects attached to a measure and stay separate from chord recognition/editing.
- Simple free-hand symbols can be selected, moved across chart paper, reanchored to the nearest measure, and deleted without enabling chord-lane recognition or Rhythm Section above-staff freehand capture.
- Tests pin all three layout families.
- The sprint source-of-truth remains the first routing document.
- Chord recognition stays writer-agnostic and proportional validation remains the default.

Current local verification:

- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `35` tests, `0` failures after updating the `Simple Chord Sheet` profile to match the user-defined default-one-measure rule.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `336` tests, `36` skipped, `0` failures after adding setup-policy contracts for key/time/starting-measure/clef behavior.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `36` tests, `0` failures after pinning the one-measure minimum invariant for layout defaults and blank charts.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `38` tests, `0` failures after wiring initial setup to starting-measure count, clef persistence, profile spacing, and profile beat-grid defaults.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `339` tests, `36` skipped, `0` failures after the setup/profile implementation.
- `xcodegen generate` completed; XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO` passed for the `iChart` scheme on the configured iPad simulator with one existing headermap warning and no errors.
- XcodeBuildMCP live simulator smoke launched `iChart`, opened the New Chart picker, verified Simple Chord Sheet setup hides Key/Clef and defaults Starting Measures to `1`, verified Rhythm Section Sheet setup hides Key/Clef and defaults Starting Measures to `8`, verified Lead Sheet setup shows Key and Clef with Starting Measures defaulting to `4`, and confirmed the library summaries after creation showed Simple `1` measure, Rhythm `8` measures, and Lead Sheet `4` measures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `30` tests, `0` failures after adding the Simple blank-measure renderer layout checks plus Rhythm/Lead header/staff guard checks.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `342` tests, `36` skipped, `0` failures after the Simple layout branch.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed for the `iChart` scheme on the configured iPad simulator with one existing headermap warning and no errors.
- XcodeBuildMCP live simulator smoke opened a saved Simple Chord Sheet and confirmed the editor renders `4/4` only in the header area, no key text, no clef, no leading time-signature glyph, no staff lines, and one blank barline-to-barline measure space.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `40` tests, `0` failures after adding Simple-only `FreehandSymbol` persistence and guard tests.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `31` tests, `0` failures after adding above/below lane geometry and free-hand symbol layout resolution checks.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `345` tests, `36` skipped, `0` failures after the Simple free-hand symbol capture/render checkpoint.
- XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO` passed for the `iChart` scheme on the configured iPad simulator with one existing headermap warning and no errors.
- Earlier XcodeBuildMCP live simulator smoke verified the historical above/below lane path. That evidence is superseded for Simple by the Sprint 68 chart-area freehand pivot and should not be treated as the current interaction target.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `42` tests, `0` failures after adding Simple free-hand symbol move/delete mutations and open-measure retention coverage.
- XcodeBuildMCP `test_sim -only-testing:iChartTests/LeadSheetFreehandSymbolEditOverlayGeometryTests CODE_SIGNING_ALLOWED=NO` passed with `4` tests, `0` failures after adding Simple free-hand selection/control/clamping geometry checks.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `347` tests, `36` skipped, `0` failures after the Simple free-hand selection/move/delete checkpoint.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed for the `iChart` scheme on the configured iPad simulator with one existing headermap warning and no errors.
- XcodeBuildMCP live simulator smoke opened a saved Simple Chord Sheet, entered `Free-Hand`, selected a saved upper-lane mark, deleted it, re-created/selected a new upper-lane mark, and moved it right inside the above-measure lane.
- Sprint 66 has all three layout styles defined, the safe setup/profile defaults implemented, the first Simple Chord Sheet blank-measure renderer skeleton verified, and Lead Sheet verified locally through clef/key-signature rendering plus the first clamped pitched-note proof. The original Simple above/below free-hand path is superseded by Sprint 68 chart-area freehand objects; remaining implementation should wait for later slices explicitly scoped to Simple freehand polish/semantic classification/rhythm snapping, Rhythm workflow refinement, richer Lead Sheet melody editing, or executable per-style system grouping.

## Completed Sprints Log

Append one entry here after each sprint completes. Each entry must include:

- sprint name
- commit range or final commit
- summary of what changed
- tests and live-pass evidence
- unresolved follow-up
- next sprint candidate

### Sprint 68: Chart Structure Systems Definition

- status: complete locally; core-loop milestone pushed on `codex/rhythm-section-core-authoring`
- final commit: `4dff695 Finalize Simple chart core authoring loop`
- summary: Returned from the Rhythm Section side sprint to the main chart-structure lane and implemented the V1 active-sheet foundation. Simple Chord Sheet now has manual row flow, chart-area freehand, margin-gated tools, cleaned-up tool tabs, iReal/handwritten-style visual cohesion, automatic chord placement/fit, role-based typography, MuseJazz assets, semantic chord tokens, and universal chord sizing. Rhythm Section keeps its V4 rhythm-aware core authoring path and automatic wrapping. Structured V1 objects for repeats, endings, point roadmap markers, optional model-only links, cue text, section-label layout support, and per-style export/readability are in place. Lead Sheet work remains archived under `docs/post-v1/lead-sheet/`.
- tests and evidence: focused and grouped SwiftPM/simulator verification was recorded throughout `docs/ichart-sprint-68-chart-structure-systems-definition-2026-05-29.md`; the final Simple typography/layout checkpoint passed full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` with `437` tests, `36` skipped, and `0` failures; `git diff --check` passed; fresh simulator wipe plus XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only; the user live pass confirmed the core loop is working and looking as intended.
- unresolved follow-up: run a recursive V1 readiness audit before further implementation, especially save/reopen, export from real app state, toolstrip consistency, stale-doc cleanup, and Rhythm Section visual polish parity.
- next sprint candidate: Sprint 69 V1 Readiness / Recursive Closeout Audit.

### Sprint 69: V1 Readiness / Recursive Closeout Audit

- status: complete locally
- final commit: this Sprint 69 closeout commit
- summary: Audited the active V1 product surface after the Simple core-loop milestone, classified remaining work, hardened persistence/save contracts, narrowed V1 creation to Simple Chord Sheet and Rhythm Section Sheet while preserving Lead Sheet compatibility, completed the first Rhythm Section visual cohesion pass, removed the dead rhythm confirmation path from the active live route, repaired the live V4 rhythm pipeline, added direct whole-note-circle handling, and recorded the V1 readiness matrix.
- tests and evidence: Sprint 69 focused and grouped verification is recorded in `docs/ichart-sprint-69-v1-readiness-audit-2026-05-31.md`. Key final evidence includes XcodeBuildMCP `RhythmicNotationQuantizerTests` with `83` passed, `1` optional replay skipped, and `0` failures after the direct whole-note-circle rule; V1 persistence/store proofs for Simple and Rhythm Section; repeated `git diff --check` passes; fresh simulator uninstall/reinstall build/run with the existing headermap warning only; and the final user-reported Rhythm Section app-surface pass green for layout, current v1 rhythm recognition, chord snapping, below-staff freehand, structured chart objects, and save/reopen.
- unresolved follow-up: export/share confidence and app-level save/reopen UX should move into the next app-experience lane rather than stay as audit blockers; Lead Sheet remains post-V1; rhythm-object editing, vamp count, and handwritten section/cue/articulation recognition remain deferred.
- next sprint candidate: Sprint 70 App Functionality and UX/UI, starting with project/library UX, export/share UX, save/reopen confidence, and tool/menu affordance polish.

### Sprint 1: Code Cleanup First

- status: complete
- final commit: `e040332 Document and clean up recognition sprint one`
- summary: Recovered the streamlined recognition architecture without score retuning. Symbol-ledger diagnostics are opt-in, semantic candidate construction moved out of `ChordInkRecognizer` into composer-owned code, and `StrokeClusterer` support helpers were split into `StrokeClustererSupport.swift` as a behavior-preserving refactor.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `iChart` scheme passed with `350` tests, `1` skipped, `0` failures using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs`; `git diff --check` passed.
- unresolved follow-up: `docs/handwriting-recognition-implementation-plan.md` and `docs/current-architecture-audit.md` remain historical/stale when they conflict with this file; no fresh user-facing `Chord Writing Test Chart` pass was run after cleanup because Sprint 1 was behavior-preserving and covered by existing recognition fixtures; branch still needs push/PR for GitHub checks.
- next sprint candidate: Sprint 2 is documentation authority cleanup plus PR/CodeQL hardening.

### Sprint 2: Documentation Authority And PR Hardening

- status: complete
- commit range: `2eedd48 Open sprint two authority cleanup` through `4ff784e Clarify sprint two doc authority`, plus the Sprint 2 closeout entry in this file
- summary: Marked stale planning docs as historical, split `README.md` authority links into active and historical groups, pushed `codex/symbol-ledger-recognition`, and opened draft PR [#4](https://github.com/beniandthe/ichart/pull/4) as the GitHub review surface for the recovery branch.
- tests and evidence: `git diff --check` passed; trailing whitespace scan found no hits; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures. PR [#4](https://github.com/beniandthe/ichart/pull/4) showed Dependency Review, SwiftPM, and iOS simulator checks passing before this closeout push; CodeQL was still pending at closeout.
- unresolved follow-up: PR [#4](https://github.com/beniandthe/ichart/pull/4) is draft and CodeQL/rerun checks need one final review before merge readiness. Sprint 3 is intentionally not selected yet.
- next sprint candidate: Review PR [#4](https://github.com/beniandthe/ichart/pull/4) status first, then choose between fixture tiering, composer scoring extraction, or product/editor polish.

### Sprint 3: Fixture Corpus Runtime Cleanup

- status: complete locally; PR checks must be rechecked after push
- commit range: `19b1b1e Close sprint two source of truth` through the Sprint 3 closeout commit containing this entry
- summary: Kept the full `646`-file ink fixture corpus default-on, added a decoded corpus cache to the test-only `InkFixtureLoader`, preserved deterministic fixture ordering and named fixture loading, and documented the fixture runtime policy in `iChartTests/Fixtures/Ink/README.md`.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter InkFixtureLoaderTests` passed with `2` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed. No fixture JSON files changed.
- GitHub evidence before the Sprint 3 push: PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, and iOS simulator checks passing; CodeQL was still pending.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/ichart/pull/4) after the Sprint 3 push; full critical/full fixture tiering remains deferred until test runtime becomes a proven blocker.
- next sprint candidate: Update the PR for any CodeQL/CI result first, otherwise choose between composer scoring extraction and product/editor polish.

### Sprint 4: Composer Scoring Policy Extraction

- status: complete locally; PR checks must be rechecked after push
- commit range: `a91af92 Close sprint three fixture corpus cleanup` through the Sprint 4 closeout commit containing this entry
- summary: Extracted `ChordInkCandidateScoringPolicy.swift` from `ChordInkCandidateComposer.swift`, moved `ChordInkCandidateComposerScoring` with the scoring policy, and left candidate selection, text variants, semantic sidecars, and score constants unchanged.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- GitHub evidence before the Sprint 4 push: PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, iOS simulator, and CodeQL passing on `a91af92`.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/ichart/pull/4) after the Sprint 4 push. The composer still owns glyph candidate selection, text variant expansion, and semantic sidecar candidate injection.
- next sprint candidate: Choose between another behavior-preserving composer split, semantic sidecar extraction, or a return to product/editor polish.

### Sprint 5: Semantic Sidecar Boundary Cleanup

- status: complete locally; PR checks must be rechecked after push
- commit range: `236f55d Close sprint four composer scoring extraction` through the Sprint 5 closeout commit containing this entry
- summary: Replaced the semantic `ChordInkCandidateComposer` extension with explicit sidecar types. `ChordInkRecognitionCandidateComposer` now coordinates base composition, semantic sidecar injection, and timing metrics, while `ChordInkSemanticCandidateComposer` owns semantic candidate recipes and contextual glyph promotion helpers. Candidate scores, semantic confidence constants, compendium validation, and recognition acceptance policy were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- GitHub evidence before the Sprint 5 work: PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `236f55d`.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/ichart/pull/4) after the Sprint 5 push. `ChordInkCandidateComposer.swift` still owns glyph candidate selection and text variant expansion, and `ChordInkSemanticCandidateComposer.swift` still needs a later behavior-preserving split.
- next sprint candidate: Choose between composer glyph-selection extraction, semantic contextualizer split, or a return to product/editor polish.

### Sprint 6: Composer Glyph-Selection Extraction

- status: complete locally; PR checks must be rechecked after push
- commit range: `267cfaf Close sprint five semantic sidecar boundary` through the Sprint 6 closeout commit containing this entry
- summary: Extracted glyph candidate selection and promotion rules from `ChordInkCandidateComposer.swift` into `ChordInkCandidateSelectionPolicy.swift`. The base composer now keeps sequence generation, text variant expansion, scoring delegation, and result metrics only. Selection thresholds, candidate promotion order, text variants, semantic sidecars, score constants, and recognition acceptance policy were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- GitHub evidence before the Sprint 6 work: PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `267cfaf`.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/ichart/pull/4) after the Sprint 6 push. `ChordInkCandidateComposer.swift` still owns text variant expansion, and `ChordInkSemanticCandidateComposer.swift` still needs a later behavior-preserving split.
- next sprint candidate: Choose between text variant extraction, semantic contextualizer split, or a return to product/editor polish.

### Sprint 7: Composer Text-Variant Extraction

- status: complete locally; PR checks must be rechecked after push
- commit range: `5cbc58f Close sprint six composer selection extraction` through the Sprint 7 closeout commit containing this entry
- summary: Extracted glyph text aliases, canonical minor-sixth display normalization, and compact/wrapper/slash lookalike text expansions from `ChordInkCandidateComposer.swift` into `ChordInkCandidateTextVariantPolicy.swift`. The base composer now keeps selected sequence generation, scoring delegation, result de-duplication, and composition metrics only. Variant expansion rules, selection rules, semantic sidecars, score constants, and recognition acceptance policy were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- GitHub evidence before the Sprint 7 work: PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `5cbc58f`.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/ichart/pull/4) after the Sprint 7 push. `ChordInkSemanticCandidateComposer.swift` still owns both semantic candidate recipes and contextual glyph promotion.
- next sprint candidate: Choose between semantic contextualizer split or a return to product/editor polish.

### Sprint 8: Semantic Glyph-Contextualizer Extraction

- status: complete; PR checks passed on `72cd12e`
- final commit: `72cd12e Close sprint eight semantic contextualizer extraction`
- summary: Extracted contextual glyph promotion from `ChordInkSemanticCandidateComposer.swift` into `ChordInkSemanticGlyphContextualizer.swift` and made `ChordInkRecognizer` call that sidecar explicitly. Semantic candidate recipes, contextual promotion thresholds, text variants, candidate selection, score constants, and recognition acceptance policy were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed. PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `72cd12e`.
- unresolved follow-up: `ChordInkSemanticCandidateComposer.swift` still owns many semantic candidate recipes and shared suffix-shape helpers; `StrokeClusterer.swift` and `StrokeClustererSupport.swift` remain large.
- next sprint candidate: Sprint 9 is PR merge readiness.

### Sprint 9: PR Merge Readiness

- status: complete; PR [#4](https://github.com/beniandthe/ichart/pull/4) was approved by the user to move out of draft
- commit range: `61caeb9 Open sprint nine merge readiness` through the Sprint 10 kickoff commit containing this entry
- summary: Recorded green Sprint 8/Sprint 9 CI evidence, refreshed the PR body with the recovered pipeline and sprint sequence, reviewed PR blockers, and kept Sprint 9 as documentation/metadata only. No recognition, editor, PencilKit, fixture, scoring, or sidecar behavior changed.
- tests and evidence: PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `61caeb9`. `git diff --check` passed for the Sprint 10 kickoff doc update.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/ichart/pull/4) after the Sprint 10 kickoff push. The PR is large and review-required; the main review risk remains size, especially the full ink fixture corpus and large recognition implementation files.
- next sprint candidate: Sprint 10 is product/editor polish audit.

### Sprint 10: Product/Editor Polish Audit

- status: complete; final closeout commit is the commit containing this entry
- commit range: `192c6c0 Open sprint ten product editor polish` through the Sprint 10 closeout commit containing this entry
- summary: Audited the recovered app against `open -> write -> recognize -> snap -> fix -> export`, then shipped the smallest user-facing fixes found in the live loop. The editor page now fits the portrait iPad viewport, export stays reachable from chord-entry and note-correction modes, and exported PDFs no longer leak editor-only placeholder copy into empty measures. No recognition scoring, parser authority, PencilKit capture policy, fixture corpus, or recognition sidecar behavior changed.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint10 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint10` passed with `311` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `iChart` scheme passed with `352` tests, `1` skipped, `0` failures using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs`; `git diff --check` passed.
- live app evidence: on the explicit iOS 26.4 iPad Air 11-inch (M4) simulator, `Chord Writing Test Chart` opened in `Chord` mode with the full title visible and page inside the viewport; export was enabled from chord-entry mode; Pro Preview reached PDF preview; empty measures exported as clean grids without `Tap the measure...` placeholder text. `Turnaround Study` proved the correction loop by changing rendered `C7` to `F7`, then restoring it to `C7`. A fresh Chord Writing Test Chart accepted synthetic simulator strokes into the recognition proposal flow, surfaced `Confirm Chord`, and committed typed `C7` as a structured rendered chord; the disposable chart was reset afterward.
- GitHub evidence: PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `ffc97b6` before this closeout commit; the PR is not draft and remains blocked only by required review.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/ichart/pull/4) after the Sprint 10 closeout push. The synthetic simulator stroke did not produce a reliable auto-read, so future handwriting-quality work should use real Pencil/user input or fixture replay rather than retuning from simulator swipe shapes.
- next sprint candidate: choose between PR review/merge follow-through, another small product/editor polish pass, or behavior-preserving semantic candidate recipe splitting.

### Sprint 11: PR Review Follow-Through

- status: complete; PR [#4](https://github.com/beniandthe/ichart/pull/4) merged into `main`
- commit range: `66dc5d2 Document chord ink clear decision` through merge commit `1b792df Merge pull request #4 from beniandthe/codex/symbol-ledger-recognition`
- summary: Recorded the product decision that accepting/rendering a chord consumes the chord-writing pass and clears the live chord ink layer. The unresolved review suggestion to preserve unconsumed chord ink was answered as intentionally out of scope for the current workflow, then resolved after user approval. No runtime behavior changed.
- tests and evidence: `git diff --check` passed for the Sprint 11 doc update. PR [#4](https://github.com/beniandthe/ichart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `66dc5d2`; the review thread was resolved; the PR merged into `main` as `1b792df` on 2026-05-23.
- unresolved follow-up: no PR review blocker remains. Future work should start from `main`, not `codex/symbol-ledger-recognition`.
- next sprint candidate: choose between a post-merge product/app audit, another small editor polish pass, behavior-preserving semantic candidate recipe splitting, or real-input handwriting validation.

### Sprint 12: Post-Merge App Audit

- status: complete; final closeout commit is the commit containing this entry
- commit range: `1e4ef82 Open sprint twelve post merge audit` through the Sprint 12 closeout commit containing this entry
- summary: Produced `docs/ichart-post-merge-app-audit-2026-05-23.md` as the written and visual post-merge app/architecture audit. The audit maps the whole app, app shell/persistence, user workflow, chord recognition pipeline, editor/export system, authority boundaries, live runtime paths, debug/tooling paths, local drift, bloat risks, and Sprint 13-15 recommendations.
- tests and evidence: main commit `31f1dde Start sprint twelve app audit` had SwiftPM tests, iOS simulator tests, and Analyze Swift passing on GitHub. Local audit verification initially found `14` untracked duplicate `iChartTests/Recognition/* 2.swift` files that were byte-identical to tracked tests but broke SwiftPM discovery.
- unresolved follow-up: the duplicate files required explicit cleanup approval before local verification could be clean again; Sprint 13 handled that approved cleanup and live smoke.
- next sprint candidate: Sprint 13 local hygiene and product smoke.

### Sprint 13: Local Hygiene And Product Smoke

- status: complete; final closeout commit is the commit containing this entry
- commit range: post-`31f1dde` cleanup through the Sprint 13 closeout commit containing this entry
- summary: Removed the `14` untracked duplicate `iChartTests/Recognition/* 2.swift` files after explicit user approval and proved the merged app path from `main`. No tracked fixture corpus, recognition score, parser, compendium, or chord ink lifecycle behavior changed.
- tests and evidence: `find iChartTests/Recognition -maxdepth 1 -name '* 2.swift' -print` returned no files; `swift test --scratch-path /tmp/iChartSwiftBuild-sprint12` passed with `311` tests, `1` skipped, `0` failures after duplicate cleanup; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `iChart` scheme passed with `352` tests, `1` skipped, `0` failures on iPad Air 11-inch (M4), iOS 26.4.1.
- live app evidence: launched `iChart`, verified the Projects library, opened `Chord Writing Test Chart`, entered chord mode, opened export from the editor, reached PDF preview/share, opened `Turnaround Study`, and verified rendered chord selection affordance. Correction behavior remains covered by automated chart editing and iOS simulator tests; no fragile coordinate-only correction edit was forced during smoke.
- unresolved follow-up: the library still exposes prototype debug/test-chart surface in debug/simulator builds and Workspace/Settings remain placeholder app-shell decisions.
- next sprint candidate: Sprint 14 editor surface boundary cleanup.

### Sprint 14: Editor Surface Boundary Cleanup

- status: complete; final closeout commit is the commit containing this entry
- commit range: post-Sprint 13 cleanup through the Sprint 14 closeout commit containing this entry
- summary: Reduced duplicated bridge coordination in `LeadSheetCanvasHostView` by extracting the repeated SwiftUI-to-UIKit property and callback wiring into one private `configure(_:context:)` helper. Native `PKCanvasView` behavior, chord recognition, chord ink lifecycle, placement, correction, and export behavior were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint14` passed with `311` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `iChart` scheme passed with `352` tests, `1` skipped, `0` failures on iPad Air 11-inch (M4), iOS 26.4.1; `git diff --check` passed.
- unresolved follow-up: `EditorView.swift` and `LeadSheetCanvasHostView.swift` remain broad surfaces; future work should continue with one small behavior-preserving extraction at a time.
- next sprint candidate: Sprint 15 decision point for user input.

### Sprint 15: Recognition Corpus And Runtime Authority Debloat

- status: complete; final closeout commit is the commit containing this entry
- summary: Decoupled the default recognition test lane from the full captured handwriting archive. `InkFixtureLoader` now exposes a compact default regression suite plus an explicit `ICHART_FULL_INK_FIXTURES=1` archive lane. Recognizer, glyph, and cluster tests use the compact suite by default while preserving full archive checks as opt-in. Captured fixture coverage tests moved behind the opt-in archive gate, and fixture docs now state that captured samples are regression evidence, not continuous training data or runtime authority.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint15` passed with `315` tests, `36` skipped, `0` failures; `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-sprint15-full` passed with `315` tests, `1` skipped, `0` failures; focused loader/recognizer/glyph/cluster/archive-integrity checks passed; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- behavior boundary: no fixture JSON files were deleted; no recognition score, parser, compendium, PencilKit, editor, chord ink lifecycle, or app runtime behavior changed.
- unresolved follow-up: the full fixture archive still exists and may need future repository/data hygiene discussion, but it is no longer default recognition authority. The next recognition-maintenance sprint should continue to avoid score retuning until it has real-input evidence.
- next sprint candidate: Sprint 16 decision point for user input.

### Sprint 16: App Shell Product Surface Debloat

- status: complete; final closeout commit is the commit containing this entry
- summary: Removed placeholder Workspace and Settings tabs from the active app shell, keeping Projects/Library as the first app surface. Moved the debug/simulator chord-writing test chart entry point out of the Library hero into a collapsed Developer Tools section, and gated the local Pro entitlement switch/debug copy so release-style surfaces no longer show a prototype-only purchase path.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint16` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator.
- visual evidence: simulator screenshot after launch showed Projects as the only top-level app surface, no Workspace/Settings tab bar, existing projects visible, and debug Developer Tools tucked below the project list.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, or StoreKit behavior changed. Debug/simulator chord-entry tooling remains available.
- unresolved follow-up: Library hero/Basic-cap copy still reads broad and marketing-like; a future product polish sprint can make it denser and more work-focused. StoreKit remains intentionally unimplemented.
- next sprint candidate: Sprint 17 decision point for user input.

### Sprint 17: Working Library Surface Debloat

- status: complete; final closeout commit is the commit containing this entry
- summary: Reworked the Projects/Library screen from a hero-led landing surface into a denser working chart list. The top area now uses a compact Local library header, New Chart action, chart count, and concise capacity text; chart rows are tighter and use smaller radii; debug Developer Tools remain collapsed below the chart list. Removed unused plan-summary and upgrade-summary accessors that were only carrying marketing copy through the Library model path.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint17` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch showed the Projects navigation title, compact Local library header, New Chart button, immediate visible chart rows, selected-chart affordance, and collapsed Developer Tools with no oversized hero card.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, chart persistence, entitlement rules, StoreKit, or export behavior changed.
- unresolved follow-up: Library organization remains minimal. Search, sort, archive, import, or richer project metadata should wait for an explicit future product sprint rather than creeping in as surface polish.
- next sprint candidate: Sprint 18 decision point for user input.

### Sprint 18: Chord Sheet Boundary Extraction

- status: complete; final closeout commit is the commit containing this entry
- summary: Moved chord ink confirmation and rendered-chord correction sheet UI, their pending DTOs, and fixture-copy status out of `EditorView.swift` into `iChart/Features/Editor/Components/ChordInkSheetViews.swift`. Moved the shared wrapping chip layout into `iChart/Features/Editor/Components/FlowLayout.swift`. This reduced `EditorView.swift` from roughly `2183` lines to roughly `1683` lines while keeping editor orchestration in place.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint18` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 18 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, chart persistence, entitlement rules, StoreKit, or export behavior changed. Chord accept, keep-ink, clear/rewrite, correction, and debug fixture-copy callbacks remain wired through `EditorView`.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1622` lines, and `EditorView.swift` still owns several modal/editor subviews. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 19 decision point for user input.

### Sprint 19: Rhythmic Confirmation Sheet Extraction

- status: complete; GitHub Actions passed on `7fb205f`
- final closeout commit: `7fb205f Extract rhythm confirmation view`
- summary: Moved rhythmic notation confirmation pending state and sheet UI out of `EditorView.swift` into `iChart/Features/Editor/Components/RhythmicNotationConfirmationSheetView.swift`. Removed the rhythm confirmation label helper from `EditorView.swift` and kept the existing shared `FlowLayout` component. This reduced `EditorView.swift` from roughly `1683` lines to roughly `1544` lines while keeping editor orchestration in place. This historical Sprint 19 confirmation path is now superseded by the 2026-06-01 Rhythm Section live route cleanup, which removes the rhythm confirmation sheet from the active runtime contract.
- tests and evidence: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint19` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 19 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Rhythm confirmation accept/rewrite callbacks remain wired through `EditorView`.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1622` lines, and `EditorView.swift` still owns note edit/time signature sheet UI. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 20 editor bridge cleanup gate.

### Sprint 20: Chord Edit Overlay Geometry Extraction

- status: complete; GitHub Actions passed on `cfbc1ff`
- final closeout commit: `cfbc1ff Extract chord edit overlay geometry`
- summary: Moved chord edit overlay frame math, delete/move control frame calculation, chord edit hit targeting, and the transparent overlay hit-test view out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetChordEditOverlayGeometry.swift`. The bridge keeps only the mode gate and drawing call site. This reduced `LeadSheetCanvasHostView.swift` from roughly `1622` lines to roughly `1531` lines while keeping native ink and editor orchestration in place.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint20 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint20` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 20 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Chord edit delete, move, and review routing remain wired through `LeadSheetCanvasHostView`.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1531` lines, with measure resize geometry, ink-scope support, gesture handling, ink persistence, recognition scheduling, and rhythm finalization still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 21 editor bridge cleanup gate.

### Sprint 21: Measure Resize Geometry Extraction

- status: complete; GitHub Actions passed on `4d8a2c3`
- final closeout commit: `4d8a2c3 Extract measure resize geometry`
- summary: Moved measure resize handle frame calculation, touch expansion, hit target creation, and `ActiveMeasureResizeDrag` out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetMeasureResizeGeometry.swift`. The bridge keeps the mode gate, selected-measure lookup, and gesture state handling. This reduced `LeadSheetCanvasHostView.swift` from roughly `1531` lines to roughly `1479` lines while keeping native ink and editor orchestration in place.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint21 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint21` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 21 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Measure resize gesture gating and chart update routing remain wired through `LeadSheetCanvasHostView`.
- GitHub evidence: main commit `4d8a2c3` passed CI and CodeQL on 2026-05-24, with CI covering SwiftPM tests, iOS simulator tests, and Analyze Swift. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1479` lines, with active ink-scope support, gesture handling, ink persistence, recognition scheduling, and rhythm finalization still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 22 editor bridge cleanup gate.

### Sprint 22: Active Ink Scope Extraction

- status: complete; GitHub Actions passed on `c567cf6`
- final closeout commit: `c567cf6 Extract active ink scope`
- summary: Moved active ink-scope resolution, page/chord writing frame helpers, and active-scope drawing-data lookup out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetActiveInkScope.swift`. The bridge keeps `PKCanvasView` sync, persistence, recognition scheduling, and editor orchestration. This reduced `LeadSheetCanvasHostView.swift` from roughly `1479` lines to roughly `1423` lines while keeping native ink behavior in place.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint22 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint22` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 22 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Active ink persistence, chord recognition scheduling, and rhythm finalization remain wired through `LeadSheetCanvasHostView`.
- GitHub evidence: main commit `c567cf6` passed CI and CodeQL on 2026-05-24, with CI covering SwiftPM tests, iOS simulator tests, and Analyze Swift. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1423` lines, with saved ink rendering helpers, gesture handling, ink persistence, recognition scheduling, and rhythm finalization still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 23 editor bridge cleanup gate.

### Sprint 23: Saved Ink Renderer Extraction

- status: complete; GitHub Actions passed on `00ec115`
- final closeout commit: `00ec115 Extract saved ink renderer`
- summary: Moved saved page ink, saved chord ink, and saved rhythmic-notation ink image rendering out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetSavedInkRenderer.swift`. The bridge keeps the draw-order gates, active-measure suppression, and chart data lookup. This reduced `LeadSheetCanvasHostView.swift` from roughly `1423` lines to roughly `1403` lines while keeping native ink display behavior in place.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint23 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint23` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 23 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Draw-order decisions, current active-rhythm-measure suppression, chord recognition scheduling, and rhythm finalization remain wired through `LeadSheetCanvasHostView`.
- GitHub evidence: main commit `00ec115` passed CI and CodeQL on 2026-05-24, with CI covering SwiftPM tests, iOS simulator tests, and Analyze Swift. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1403` lines, with gesture handling, ink persistence, recognition scheduling, and rhythm finalization still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 24 editor bridge cleanup gate.

### Sprint 24: Active Ink Persistence Extraction

- status: complete; GitHub Actions passed on `d77fa98`
- final closeout commit: `d77fa98 Extract active ink persistence`
- summary: Moved the active ink persistence write-back decision out of `LeadSheetCanvasHostView.swift` and into `LeadSheetActiveInkScope.swift`. The bridge still owns debounce/cancel timing, the current canvas drawing, local chart assignment, and `onChartChanged` callback routing. This reduced `LeadSheetCanvasHostView.swift` from roughly `1403` lines to roughly `1385` lines while keeping active ink persistence behavior in place.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint24 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint24` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 24 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence semantics, entitlement rules, StoreKit, or export behavior changed. Active ink debounce/cancel behavior, chord recognition scheduling, and rhythm finalization remain wired through `LeadSheetCanvasHostView`.
- GitHub evidence: main commit `d77fa98` passed CI and CodeQL on 2026-05-24, with CI covering SwiftPM tests, iOS simulator tests, and Analyze Swift. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1385` lines, with gesture handling, chord recognition scheduling, OCR image rendering, and rhythm finalization still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 25 editor bridge cleanup gate after Sprint 24 GitHub checks pass.

### Sprint 25: Chord Ink Image Renderer Extraction

- status: complete; GitHub Actions passed on `395d756`
- final closeout commit: `395d756 Extract chord ink image renderer`
- summary: Moved chord ink render-bounds calculation and OCR crop/image rendering out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetChordInkImageRenderer.swift`. The host still owns OCR request gating through `ChordRecognitionTrustArbiter`, provider invocation, metrics, target placement, scheduling, and callbacks. This reduced `LeadSheetCanvasHostView.swift` from roughly `1385` lines to roughly `1352` lines while keeping OCR sidecar behavior and chord ink target placement in place.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint25 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint25` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 25 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. OCR remains optional, ambiguity-only, compendium-gated, and invoked from the same host decision path.
- GitHub evidence: main commit `395d756` passed CI and CodeQL on 2026-05-24, with CI covering SwiftPM tests, iOS simulator tests, and Analyze Swift. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1352` lines, with gesture handling, chord recognition scheduling, and rhythm finalization still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 26 editor bridge cleanup gate after Sprint 25 GitHub checks pass.

### Sprint 26: Canvas Interaction Targeting Extraction

- status: complete; GitHub Actions passed on `40f873f`
- final closeout commit: `40f873f Extract canvas interaction targeting`
- summary: Moved shared tap target lookup, chord-writing band hit testing, chord move target placement, and `ActiveChordMoveDrag` out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetCanvasInteractionTargeting.swift`. The host still owns gesture recognizers, callbacks, chart mutation, chord correction routing, and redraw timing. This reduced `LeadSheetCanvasHostView.swift` from roughly `1352` lines to roughly `1319` lines.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint26 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint26` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 26 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Measure selection, chord edit tap routing, chord move placement, and current chord ink clearing behavior remain wired through `LeadSheetCanvasHostView`.
- GitHub evidence: main commit `40f873f` passed CI and CodeQL on 2026-05-24, with CI covering SwiftPM tests, iOS simulator tests, and Analyze Swift. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1319` lines, with chord recognition scheduling, rhythm finalization, note-selection lasso support, and interaction-mode state resets still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 27 editor bridge cleanup gate after Sprint 26 GitHub checks pass.

### Sprint 27: Note Selection Lasso Targeting Extraction

- status: complete; GitHub Actions passed on `61ded98`
- final closeout commit: `61ded98 Extract note selection lasso targeting`
- summary: Moved note-selection lasso frame calculation and incidental tap-dot filtering out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetNoteSelectionLassoTargeting.swift`. The host still owns note-selection gesture routing, selection callbacks, selected-measure clearing, ink clearing, and redraw timing. This reduced `LeadSheetCanvasHostView.swift` from roughly `1319` lines to roughly `1282` lines.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint27 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint27` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 27 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Note selection hit testing, lasso conversion, callback routing, and current chord ink clearing behavior remain wired through `LeadSheetCanvasHostView`.
- GitHub evidence: main commit `61ded98` passed CI and CodeQL on 2026-05-24, with CI covering SwiftPM tests, iOS simulator tests, and Analyze Swift. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1282` lines, with chord recognition scheduling, rhythm finalization, and interaction-mode state resets still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 28 editor bridge cleanup gate after Sprint 27 GitHub checks pass.

### Sprint 28: Chord Ink Recognition Targeting Extraction

- status: complete; GitHub Actions passed on `7e9ab7c`
- final closeout commit: `7e9ab7c Extract chord ink recognition targeting`
- summary: Moved chord ink recognition target selection and target-measure scoring out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetChordInkRecognitionTargeting.swift`. The host still owns recognition scheduling, request cancellation, OCR gating, recognizer execution, continuation grace, timing logs, callbacks, and current chord ink clearing behavior. This reduced `LeadSheetCanvasHostView.swift` from roughly `1282` lines to roughly `1231` lines.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint28 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint28` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 28 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Chord ink target placement geometry and scoring are behavior-preserving moves only.
- GitHub evidence: main commit `7e9ab7c` passed required GitHub Actions on 2026-05-24, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1231` lines, with chord recognition scheduling/timing, rhythm finalization, and interaction-mode state resets still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 29 editor bridge cleanup gate after Sprint 28 GitHub checks pass.

### Sprint 29: Chord Recognition Timing Extraction

- status: complete; GitHub Actions passed on `9f05177`
- final closeout commit: `9f05177 Extract chord recognition timing logging`
- summary: Moved chord recognition timing storage and debug timing log formatting out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetChordInkRecognitionTiming.swift`. The host still owns recognition scheduling, request cancellation, OCR gating, recognizer execution, continuation grace, proposal callbacks, and current chord ink clearing behavior. This reduced `LeadSheetCanvasHostView.swift` from roughly `1231` lines to roughly `1184` lines.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint29 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint29` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 29 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Timing values and debug log formatting are behavior-preserving moves only.
- GitHub evidence: main commit `9f05177` passed required GitHub Actions on 2026-05-24, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1184` lines, with chord recognition scheduling/continuation, rhythm finalization, and interaction-mode state resets still in one file. Continue one behavior-preserving extraction at a time.
- next sprint candidate: Sprint 30 editor bridge cleanup gate after Sprint 29 GitHub checks pass.

### Sprint 30: Chord Recognition Scheduling Policy Extraction

- status: complete; GitHub Actions passed on `a6fd6c2`
- final closeout commit: `a6fd6c2 Extract chord recognition scheduling policy`
- summary: Moved chord recognition idle-delay selection and continuation-grace decision out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetChordInkRecognitionScheduling.swift`. The host still owns timers, request IDs, cancellation, OCR gating, recognizer execution, proposal callbacks, and current chord ink clearing behavior. This reduced `LeadSheetCanvasHostView.swift` from roughly `1184` lines to roughly `1182` lines while making the remaining scheduling policy explicit.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint30 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint30` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 30 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence, entitlement rules, StoreKit, or export behavior changed. Continuation grace and idle delay behavior are behavior-preserving moves only.
- GitHub evidence: main commit `a6fd6c2` passed required GitHub Actions on 2026-05-24, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1182` lines, with recognition request execution/cancellation, rhythm finalization, and interaction-mode state resets still in one file.
- next sprint candidate: Sprint 31 editor bridge cleanup gate after Sprint 30 GitHub checks pass.

### Sprint 31: Rhythmic Notation Finalization Extraction

- status: complete; GitHub Actions passed on `63356d7`
- final closeout commit: `63356d7 Extract rhythmic notation finalization`
- summary: Moved rhythmic notation selection-change/tap finalization policy, live rhythmic drawing persistence, quantization frame construction, and rhythm-map apply/ink-clear helper logic out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetRhythmicNotationFinalization.swift`. The host still owns selection restoration, callbacks, validation messaging, canvas drawing access, and current chord ink clearing behavior. This reduced `LeadSheetCanvasHostView.swift` from roughly `1182` lines to roughly `1176` lines while making rhythmic finalization a named boundary.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint31 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint31` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 31 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence semantics, entitlement rules, StoreKit, or export behavior changed. Rhythmic finalization policy and apply helpers are behavior-preserving moves only.
- GitHub evidence: main commit `63356d7` passed required GitHub Actions on 2026-05-24, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1176` lines, with recognition request execution/cancellation and interaction-mode state resets still in one file.
- next sprint candidate: Sprint 32 editor bridge cleanup gate after Sprint 31 GitHub checks pass.

### Sprint 32: Interaction Mode State Policy Extraction

- status: complete; GitHub Actions passed on `fe1701a`
- final closeout commit: `fe1701a Extract interaction mode state policy`
- summary: Moved interaction-mode recognizer enablement, chord edit overlay visibility/interactivity, page ink canvas interactivity, ink tool selection, and state-reset decision policy out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetInteractionModeStatePolicy.swift`. The host still owns applying UIKit state, cancelling pending chord recognition work, clearing active drags, resigning first responder, and current chord ink clearing behavior. This reduced `LeadSheetCanvasHostView.swift` from roughly `1176` lines to roughly `1159` lines.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint32 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint32` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 32 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence semantics, entitlement rules, StoreKit, export behavior, or mode behavior changed. Interaction-mode policy values are behavior-preserving moves only.
- GitHub evidence: main commit `fe1701a` passed required GitHub Actions on 2026-05-24, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1159` lines, with recognition request execution/cancellation still in one file.
- next sprint candidate: Sprint 33 editor bridge cleanup gate after Sprint 32 GitHub checks pass.

### Sprint 33: Chord Recognition Request State Extraction

- status: complete; GitHub Actions passed on `c238964`
- final closeout commit: `c238964 Extract chord recognition request state`
- summary: Moved chord ink recognition request-state bookkeeping out of `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetChordInkRecognitionRequestState.swift`. The helper owns the pending work item, active request ID, last recognized drawing data, and continuation-grace drawing data. The host still owns scheduling delays, request execution, target selection, OCR gating, recognizer invocation, timing logs, proposal callbacks, chart mutation, and current chord ink clearing behavior. This reduced `LeadSheetCanvasHostView.swift` from roughly `1159` lines to roughly `1147` lines while grouping request state under a named boundary.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint33 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint33` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator; `git diff --check` passed.
- visual evidence: simulator screenshot after launch confirmed the app still opens to the compact Projects/Local library surface. Sprint 33 intentionally made no visible product change.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence semantics, entitlement rules, StoreKit, export behavior, or mode behavior changed. Request-state movement is behavior-preserving only; the host still owns recognition execution.
- GitHub evidence: main commit `c238964` passed required GitHub Actions on 2026-05-24, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: `LeadSheetCanvasHostView.swift` remains the largest live editor bridge at roughly `1147` lines. The remaining chord recognition request execution, OCR gate, recognizer invocation, proposal callback, and chart-mutation path is more entangled than the state bookkeeping and should be reviewed before further extraction.
- next sprint candidate: Sprint 34 editor bridge decision gate after Sprint 33 GitHub checks pass.

### Sprint 34: Editor Recognition Execution Audit

- status: complete; GitHub Actions passed on `4f1de60`
- final closeout commit: `4f1de60 Audit editor recognition execution path`
- summary: Paused the editor bridge extraction sequence and audited the remaining live chord recognition execution path in `docs/ichart-editor-recognition-execution-audit-2026-05-24.md`. The audit maps the path from `PKCanvasView` drawing change through scheduling, request-state guarding, target selection, `PencilKitInkAdapter`, background `ChordInkRecognizer`, optional OCR sidecar, main-thread continuation grace, `EditorView` proposal routing, trust-policy auto-render/confirmation, structured `ChordEvent` commit, diagnostics, and chord ink clearing.
- tests and evidence: doc/audit-only; `git diff --check` passed. Sprint 34 made no runtime code changes.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence semantics, entitlement rules, StoreKit, export behavior, or mode behavior changed. The audit explicitly recommends stopping blind bridge extraction before the remaining execution/OCR/callback/chart-mutation path.
- GitHub evidence: main commit `4f1de60` passed required GitHub Actions on 2026-05-25, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: choose Sprint 35 from product evidence or deliberate architecture design, not more automatic bridge slicing.
- next sprint candidate: Sprint 35 product evidence or recognition-session design decision after Sprint 34 GitHub checks pass.

### Sprint 35: Recognition Session Boundary Design

- status: complete; GitHub Actions passed on `09953fc`
- final closeout commit: `09953fc Design chord recognition session boundary`
- summary: Added `docs/ichart-recognition-session-boundary-design-2026-05-25.md` to define a future `ChordInkRecognitionSession` boundary before moving more of the live editor/recognition path. The design keeps UIKit/PencilKit state, active mode/scope guards, target selection, stale request validation, continuation-grace routing, proposal callbacks, auto-render/confirmation, chart mutation, diagnostics, and chord ink clearing outside the future session. The future session is limited to prepared recognition execution, optional OCR evidence, timing construction, and main-thread proposal payload delivery.
- tests and evidence: doc/design-only; `git diff --check` passed. Sprint 35 made no runtime code changes.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, rhythm quantization, chart persistence semantics, entitlement rules, StoreKit, export behavior, mode behavior, OCR authority, or chord ink clearing changed.
- GitHub evidence: main commit `09953fc` passed required GitHub Actions on 2026-05-25, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: choose whether the next architecture sprint should run real Pencil validation or implement the designed recognition-session boundary as a behavior-preserving code move.
- next sprint candidate: recognition generalization policy reset before selecting the next architecture sprint, because fixture capture language still implied a one-writer training habit.

### Sprint 36: Recognition Generalization Policy Reset

- status: complete; GitHub Actions passed on `6ab1d05`
- final closeout commit: `6ab1d05 Reset recognition fixture authority policy`
- summary: Made the writer-agnostic recognition rule explicit across the active source-of-truth, Sprint 34 audit, Sprint 35 recognition-session design, fixture README, and historical handwriting plan. Debug fixture capture wording now says `Copy Regression Fixture` and `Clear Ink`, and export errors refer to regression fixtures instead of ink samples. The old opt-in captured handwriting coverage count gates now skip even when `ICHART_FULL_INK_FIXTURES=1`, so they no longer pressure the project to keep expanding one writer's captured sample corpus.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint36 --filter ChordInkRecognizerTests` passed with `40` tests, `1` skipped, `0` failures; focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint36 --filter InkFixtureCoverageTests` passed with `32` tests, `32` skipped, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint36` passed with `315` tests, `36` skipped, `0` failures; opt-in retired coverage check `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-sprint36-full --filter InkFixtureCoverageTests` passed with `32` tests, `32` skipped, `0` failures and the retired-gates skip message; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Pro 13-inch (M5) simulator; simulator foreground launch/screenshot stayed on SpringBoard with a `FBSOpenApplicationServiceErrorDomain` preflight-busy log, so Sprint 36 does not claim visual app-surface proof; `git diff --check` passed.
- behavior boundary: no recognition score, parser, compendium, fixture JSON, PencilKit, chord ink lifecycle, rhythm quantization, chart persistence semantics, entitlement rules, StoreKit, export renderer behavior, mode behavior, OCR authority, or structured chord commit behavior changed. Runtime-facing changes are limited to debug/simulator fixture-copy wording and retired coverage-test gates.
- GitHub evidence: main commit `6ab1d05` passed required GitHub Actions on 2026-05-25, with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: real Pencil validation can observe generalization and record transferable regressions, but must not become a personal sample-collection loop. Future user-specific recognition or personalization requires explicit opt-in product architecture before any data is captured for that purpose.
- next sprint candidate: Sprint 37 real Pencil validation or recognition-session implementation decision after Sprint 36 GitHub checks pass.

### Sprint 37: Recognition Session Boundary Implementation

- status: complete; required GitHub Actions passed
- final closeout commit: `f8019c6 Extract chord ink recognition session`
- summary: Implemented the first `ChordInkRecognitionSession` boundary from the Sprint 35 design. `LeadSheetCanvasHostView.swift` still prepares request inputs, owns mode/scope guards, target selection, stale-request validation, continuation-grace requeue, proposal callbacks, and current chord ink lifecycle. The new `ChordInkRecognitionSession.swift` owns only prepared background recognizer execution, primary decision calculation for OCR gating, optional OCR sidecar evidence, timing construction, and main-thread payload delivery. Added app-target `ChordInkRecognitionSessionTests` for main-thread payload delivery and OCR gating.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint37 --filter ChordInkRecognizerTests` passed with `40` tests, `1` skipped, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint37-full` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme passed with `323` passed, `36` skipped, `0` failures, including the two new session tests; XcodeBuildMCP build/run succeeded on the configured iPad Pro 13-inch (M5) simulator; screenshot confirmed the app opens to the compact Projects/Local library surface; `git diff --check` passed.
- behavior boundary: no recognition score, parser, compendium, fixture JSON, PencilKit, chord ink lifecycle, rhythm quantization, chart persistence semantics, entitlement rules, StoreKit, export behavior, mode behavior, OCR authority, auto-render/confirmation routing, structured `ChordEvent` commit, diagnostics, continuation-grace policy, or chord ink clearing changed.
- GitHub evidence: main commit `f8019c6` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on 2026-05-25.
- unresolved follow-up: real Pencil validation is now the product-preferred next step because the repo-local session boundary is in place. Any further repo-local session work must remain behavior-preserving and keep auto-render/confirmation, commit, diagnostics, continuation grace, and ink clearing outside the session.
- next sprint candidate: Sprint 38 OCR-gate test hardening, then Sprint 39 real Pencil validation or product-evidence decision.

### Sprint 38: Recognition Session OCR Gate Test Hardening

- status: complete; required GitHub Actions passed
- final closeout commit: `85664a6 Harden chord recognition session OCR gate`
- summary: Added app-target coverage for the recognition-session OCR gate. `ChordInkRecognitionSessionTests` now proves that a clear primary recognition decision does not request OCR image generation, does not call the OCR provider, does not attach OCR candidates, and reports zero OCR candidate count even when an OCR provider is available.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint38 --filter ChordInkRecognizerTests` passed with `40` tests, `1` skipped, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint38-full` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme passed with `324` passed, `36` skipped, `0` failures, including all three session tests; `git diff --check` passed.
- behavior boundary: test-only hardening. No production code, recognition score, parser, compendium, fixture JSON, PencilKit behavior, chord ink lifecycle, chart persistence semantics, OCR authority, auto-render/confirmation routing, structured `ChordEvent` commit, diagnostics, continuation-grace policy, or chord ink clearing changed.
- GitHub evidence: main commit `85664a6` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on 2026-05-25.
- unresolved follow-up: real Pencil validation requires human hardware input. If continuing repo-local before that input, choose a product-evidence sprint rather than hidden training, score tuning, or blind extraction.
- next sprint candidate: Sprint 39 real Pencil validation or product-evidence decision after Sprint 38 GitHub checks pass.

### Sprint 39: Bounded Ink Renderer Product Proof

- status: complete; required GitHub Actions passed
- final closeout commit: `a0eb7a0 Add bounded renderer product proof`
- summary: Added an app-target renderer product-proof test that uses exactly three fixed ink fixtures (`C`, `Db7(b9)`, and `G/B`). The proof recognizes those strokes, commits structured `ChordEvent`s with source ink evidence, clears page chord ink after each commit, exports the chart through `PDFChartExporter`, and verifies the rendered PDF text contains the recognized chord output without editor placeholder copy.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint39 --filter ChordInkRecognizerTests` passed with `40` tests, `1` skipped, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint39-full` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme passed with `325` passed, `36` skipped, `0` failures, including `RendererProductProofTests`; `git diff --check` passed.
- behavior boundary: test-only product proof. No production code, recognition score, parser, compendium, fixture JSON, PencilKit behavior, chord ink lifecycle, chart persistence semantics, OCR authority, auto-render/confirmation routing, diagnostics, StoreKit, or export renderer implementation changed.
- GitHub evidence: main commit `a0eb7a0` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on 2026-05-25.
- unresolved follow-up: real Pencil validation can use a small target set and visual renderer evidence, but must not become an open-ended captured-ink loop. Add new ink only for transferable product regressions.
- next sprint candidate: Sprint 40 real Pencil renderer validation or visual renderer QA decision after Sprint 39 GitHub checks pass.

### Sprint 40: Visual Renderer QA

- status: complete; required GitHub Actions passed
- final closeout commit: `536d49d Add renderer visual QA proof`
- summary: Added `PDFRendererVisualQATests` as a bounded app-target visual QA harness for representative structured charts and the Sprint 39 product-proof path. The harness emits stable PDFs when `ICHART_RENDERER_QA_OUTPUT` is set, records a manifest, verifies expected chart/chord text, rejects editor placeholder copy, and keeps the ink product-proof path capped at three fixed fixtures so it cannot drift into a personal handwriting training loop. The QA pass found and fixed two export renderer defects: late-measure chord/timing labels now shift left instead of clipping at the right edge, and `PDFChartExporter` paints an explicit white page background so raster previews and thumbnails do not render transparent pages as black.
- tests and evidence: `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme passed with `326` passed, `36` skipped, `0` failures while writing QA PDFs to `/tmp/iChartRendererQA`; focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint40 --filter ChordInkRecognizerTests` passed with `40` tests, `1` skipped, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint40-full` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- visual evidence: generated `/tmp/iChartRendererQA/late-night-pocket-concert.pdf`, `/tmp/iChartRendererQA/turnaround-study-concert.pdf`, and `/tmp/iChartRendererQA/renderer-product-proof-concert.pdf`; rendered them to PNGs under `/tmp/iChartRendererQA/png` using `sips`; visually inspected all three. The final images show white page backgrounds, readable headers, intact representative chords including `Ab7(#11)`, `Bb△7`, `G-7`, `C7`, `C`, `Db7(b9)`, and `G/B`, and no editor placeholder text.
- behavior boundary: no recognition score, parser, compendium, fixture JSON, PencilKit behavior, chord ink lifecycle, chart persistence semantics, OCR authority, auto-render/confirmation routing, diagnostics, StoreKit, or training policy changed. Production changes are limited to export renderer layout/background correctness.
- GitHub evidence: main commit `536d49d` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on 2026-05-25. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: real Pencil validation still requires human hardware input and should remain a short product-loop pass, not an open-ended sample capture loop.
- next sprint candidate: Sprint 41 writing-to-render commit contract after Sprint 40 GitHub checks passed and the user asked to continue improving the writing-to-render pipeline.

### Sprint 41: Writing-To-Render Commit Contract

- status: complete; required GitHub Actions passed
- final closeout commit: `a1254f0 Centralize chord ink commit contract`
- summary: Centralized the successful chord-ink commit rule in `Chart.commitRecognizedChordInk`. The editor now calls one model-level operation that appends a structured `ChordEvent`, stores source ink evidence, and clears the active chord ink pass only after a successful append. If the target measure is unavailable, the operation returns `nil` and keeps the active chord ink available for retry. The bounded renderer proof and visual QA harness now use the same commit contract, so product evidence follows the same write-to-render path as the live editor instead of duplicating append/clear steps in tests.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint41 --filter ChartEditingTests` passed with `31` tests, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint41-full` passed with `316` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme passed with `327` passed, `36` skipped, `0` failures; `git diff --check` passed.
- behavior boundary: no recognition score, parser, compendium, fixture JSON, PencilKit behavior, OCR authority, auto-render/confirmation policy, diagnostics, StoreKit, export layout, or training policy changed. The chord ink lifecycle rule is unchanged, but is now enforced through one commit helper on success.
- GitHub evidence: main commit `a1254f0` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on 2026-05-26. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: real Pencil validation still requires human hardware input and should test the same product contract with a small target set; it must not become repeated personal sample capture or recognition retuning.
- next sprint candidate: Sprint 42 writing-to-render readiness QA after Sprint 41 GitHub checks passed and the user approved continuing architecture readiness through real-life testing prep.

### Sprint 42: Writing-To-Render Readiness QA

- status: complete; required GitHub Actions passed
- final closeout commit: `ae38df7 Add writing-to-render readiness QA`
- summary: Added `docs/ichart-real-life-testing-readiness-2026-05-25.md` as the real Pencil field-test handoff and centralized the bounded three-case product-proof fixture set in `WritingToRenderPipelineProof`. Added `WritingToRenderPipelineReadinessTests` to prove the bounded proof cases meet live trust-routing expectations and recognition-latency budgets without enabling symbol-ledger diagnostics. Updated renderer product proof and visual QA so they use the same centralized cases and pass through the live `ChordRecognitionTrustArbiter` decision before committing via `Chart.commitRecognizedChordInk`. Cross-checked sprint movement with README, V1 QA, and older architecture/milestone/basic-flow docs so older plans no longer read as current implementation authority.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint42 --filter WritingToRenderPipelineReadinessTests` passed with `1` test, `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint42-full` passed with `317` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `iChart` scheme passed with `328` passed, `36` skipped, `0` failures while writing renderer QA artifacts to `/tmp/iChartRendererQA-sprint42`; `git diff --check` passed.
- visual evidence: generated `/tmp/iChartRendererQA-sprint42/late-night-pocket-concert.pdf`, `/tmp/iChartRendererQA-sprint42/turnaround-study-concert.pdf`, and `/tmp/iChartRendererQA-sprint42/renderer-product-proof-concert.pdf`; rendered them to PNGs under `/tmp/iChartRendererQA-sprint42/png` using `sips`; visually inspected all three. The final images show white page backgrounds, readable headers, intact representative chords including `Eb△7`, `Ab7(#11)`, `Db-9`, `G13`, `C7(b9)`, `Bb△7`, `G-7`, `C7`, `C`, `Db7(b9)`, and `G/B`, and no editor placeholder text.
- behavior boundary: no recognition score, parser, compendium, fixture JSON, PencilKit behavior, OCR authority, auto-render/confirmation policy, diagnostics, StoreKit, export layout, or chord ink lifecycle changed. The product-proof tests now use the live trust/commit contract, but production runtime behavior is unchanged.
- GitHub evidence: main commit `ae38df7` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on 2026-05-26. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: real Pencil validation still requires human hardware input. The next pass should follow the readiness protocol and record product observations, not expand fixtures or retune recognition from one writer.
- next sprint candidate: Sprint 43 real Pencil product-loop field test after Sprint 42 GitHub checks pass.

### Sprint 43: Real Pencil Product Loop Field Test

- status: complete; required GitHub Actions passed
- final evidence commits: `8e384e6 Record sprint 43 field test export evidence` and `f427d50 Record sprint 43 field test findings`
- summary: Captured the first bounded real iPad/Apple Pencil product-loop pass in `docs/ichart-real-pencil-field-test-log-2026-05-26.md`. The pass confirmed that the recovered loop works in principle: writing felt native overall with small stroke breaks, `C` and `G/B` auto-rendered correctly but slowly, `Db7(b9)` had altered-extension recognition friction, accepted chord ink cleared, and local Preview/export metadata confirmed the generated PDF was legible. It also exposed product blockers: export/share was not available on iPad, and the exported PDF still used old card-style measure blocks instead of the actual chart page.
- tests and evidence: Sprint 43 evidence updates were doc/metadata only after the real hardware pass. Required GitHub Actions passed on main commit `f427d50` with SwiftPM tests, iOS simulator tests, and Analyze Swift passing. Supabase and Expo suites remained queued with zero check runs and are not treated as current required app health.
- behavior boundary: no code, recognition score, parser, compendium, fixture JSON, PencilKit behavior, export implementation, StoreKit behavior, chord ink lifecycle, OCR authority, or training policy changed. The field-test evidence is product evidence, not recognition training data.
- unresolved follow-up: export availability/fidelity needed to be fixed before another real Pencil pass; recognition latency, `Db7(b9)` altered-extension trust, and small stroke breaks remained as later product findings.
- next sprint candidate: Sprint 44 renderer/iPad export availability.

### Sprint 44: Renderer And iPad Export Availability

- status: complete; required GitHub Actions passed
- final closeout commit: `2501fdf Close sprint 44 export page rendering`
- summary: Replaced the old PDF card renderer with a shared page-layout export path. `PDFChartExporter` now renders through `LeadSheetPageLayoutEngine` and `LeadSheetNotationRenderer`, drawing the full lead-sheet page surface with header, systems, staff lines, chords, rhythmic notation, saved page ink, saved chord ink, and saved rhythmic notation ink. PDF export later became part of the Basic plan so export/share remains available without a Pro gate.
- tests and evidence: full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint44` passed with `317` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; XcodeBuildMCP focused iOS simulator export tests passed with `4` passed, `0` failures while writing `/tmp/iChartRendererQA-sprint44`; XcodeBuildMCP full iOS simulator `iChart` scheme passed with `329` passed, `36` skipped, `0` failures while writing `/tmp/iChartRendererQA-sprint44-full`; `git diff --check` passed.
- visual evidence: generated Sprint 44 PDFs were rendered to PNG via `sips` and visually inspected under `/tmp/iChartRendererQA-sprint44/png` and `/tmp/iChartRendererQA-sprint44-full/png`. The inspected images are portrait full lead-sheet pages with readable headers, systems, staff lines, and expected chords including `C`, `Db7(b9)`, and `G/B`, not old singular rounded measure-card blocks.
- behavior boundary: no recognition score, parser, compendium, OCR authority, symbol-ledger policy, fixture corpus, PencilKit capture, chord ink lifecycle, structured chord commit semantics, or StoreKit purchase implementation changed. The entitlement change is an explicit temporary field-test/export allowance, not a purchase system.
- GitHub evidence: main commit `2501fdf` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on 2026-05-26. Supabase and Expo suites may remain queued with zero check runs and are not treated as current required app health.
- unresolved follow-up: repeat the short real iPad/Pencil pass after GitHub green to confirm export/share reaches Preview/share from the device and exported output matches the full chart page. Recognition latency, `Db7(b9)` altered-extension friction, and small stroke breaks remain candidate product sprints after the export repeat.
- next sprint candidate: Sprint 45 post-export field-test decision gate after Sprint 44 GitHub checks pass.

### Sprint 45: Post-Export Field-Test Validation

- status: complete; required GitHub Actions passed
- final evidence commit: `f25641a Record sprint 45 field test results`
- summary: Recorded the bounded post-export iPad/Pencil pass in `docs/ichart-post-export-field-test-log-2026-05-26.md`. The pass confirmed the Sprint 44 export fix: export/share worked as expected, the chart exported as PDF to Preview, full-page export fidelity was acceptable, accepted chord ink cleared, `Db7(b9)` needed confirmation and then was good, and stroke breaks did not reproduce. The pass also confirmed the remaining lead blocker: clear auto-render cases `C` and `G/B` still take a couple seconds after ink.
- tests and evidence: user-reported real iPad/Pencil field-test evidence, with ink metadata present but not imported as fixtures/training data; `git diff --check` passed locally for the doc closeout; required GitHub Actions passed on main commit `f25641a`. The previous app-code verification remains Sprint 44: full SwiftPM tests, Python script compilation, focused/full iOS simulator tests, and visual PDF/PNG inspection passed before the field-test repeat.
- behavior boundary: no production code, recognition score, parser, compendium, fixture JSON, PencilKit behavior, export implementation, StoreKit behavior, chord ink lifecycle, OCR authority, symbol-ledger policy, or training policy changed. The on-screen duplicated-state comment from the pass is recorded as a visual observation requiring screenshot/repro if it persists, not as the current primary blocker.
- unresolved follow-up: investigate the live recognition latency path for clear cases before any trust/score retuning. Keep `Db7(b9)` confirmation-gated unless future general evidence justifies a policy change.
- next sprint candidate: Sprint 46 recognition latency and trust triage.

### Sprint 46: Recognition Latency And Trust Triage

- status: complete locally; GitHub verification pending after closeout push
- code commit: `72e6d91 Tune sprint 46 chord recognition scheduling`
- repeat-gate commit: `c2ac660 Set up sprint 46 latency repeat gate`
- summary: Measured and reduced one intentional scheduler-delay source without changing recognition scores or expanding handwriting fixtures. The default chord-ink idle delay moved from `1.2s` to `0.85s`, root-only continuation grace moved from `1.2s` to `0.55s`, extension prefixes kept full `1.2s` grace, and slash/altered chords stayed outside continuation grace. The repeat pass then showed the remaining slow cases are low-confidence `C` and `G/B`, while `Db7(b9)` was extremely quick and export worked.
- tests and evidence: focused XcodeBuildMCP scheduling tests passed with `5` tests, `0` failures; `swift test --scratch-path /tmp/iChartSwiftBuild-sprint46 --filter WritingToRenderPipelineReadinessTests` passed with `1` test, `0` failures and bounded recognizer/readiness runtime of `0.131s`; full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint46` passed with `317` tests, `36` skipped, `0` failures; full XcodeBuildMCP iOS simulator `iChart` scheme passed with `334` tests, `36` skipped, `0` failures; GitHub Actions passed on `72e6d91` and `c2ac660`; the real iPad/Pencil repeat is recorded in `docs/ichart-sprint-46-latency-repeat-log-2026-05-26.md`.
- behavior boundary: no personal fixture expansion, score retuning, default OCR expansion, symbol-ledger diagnostics cost, export/share change, or chord ink lifecycle change.
- unresolved follow-up: determine whether the remaining delay is confidence/trust routing, candidate conflict, recognizer compute, UI proposal/commit, ink clearing, or render handoff.
- next sprint candidate: Sprint 47 confidence and performance split triage.

### Sprint 47: Confidence And Performance Split Triage

- status: complete; required GitHub Actions passed
- instrumentation commit: `7d0347b Add sprint 47 chord timing instrumentation`
- capture setup commit: `b8add53 Set up sprint 47 timing capture`
- evidence commit: `413872a Record sprint 47 preview pass evidence`
- summary: Added debug-only console timing labels for final trust action/reason, editor proposal timing, commit mutation timing, and a parser/log template for bounded timing capture. The available simulator/Preview pass rendered and exported `C`, `G/B`, and `Db7(b9)` correctly, and committed diagnostics showed `C` and `G/B` auto-rendered with sub-2ms recognizer totals while `Db7(b9)` remained confirmation-routed as a close race.
- tests and evidence: focused `ChordRecognitionTrustArbiterTests`, full SwiftPM tests, full XcodeBuildMCP iOS simulator tests, Python script compilation, sample parser run, and `git diff --check` passed before the Sprint 47 setup/evidence commits. Required GitHub Actions passed on `7d0347b`, `b8add53`, and `413872a`.
- behavior boundary: no recognition score, parser, compendium, OCR authority, symbol-ledger policy, fixture corpus, PencilKit capture, export behavior, chord ink clearing, or training policy changed.
- unresolved follow-up: the Preview/pass metadata did not include the new console timing lines, so scheduler/proposal/commit/render latency remained unclassified even though recognizer compute looked low for `C` and `G/B`.
- next sprint candidate: Sprint 48 persistent timing telemetry.

### Sprint 48: Persistent Timing Telemetry

- status: complete; required GitHub Actions passed
- telemetry commit: `e984e2a Add sprint 48 persistent timing telemetry`
- summary: Persisted chord-entry timing evidence into diagnostics so future bounded passes do not depend on console capture. The bounded pass showed `C` and `G/B` felt quicker, with recognition/render/proposal/commit all low and scheduled idle now the main remaining time component.
- tests and evidence: focused `ChordEntryDiagnosticsTests`, full SwiftPM tests, full XcodeBuildMCP iOS simulator tests, Python script compilation, sample timing parser run including render handoff, `git diff --check`, and required GitHub Actions passed. The bounded pass diagnostics came from CoreSimulator app data for chart `DA226639-62AA-4DD0-8D9A-E5CEC1777F98`.
- behavior boundary: no recognition score, parser, compendium, OCR authority, symbol-ledger policy, fixture corpus, PencilKit capture, export behavior, chord ink clearing, or training policy changed.
- unresolved follow-up: `Db7(b9)` fell into manual correction with zero suggestions because candidate composition only saw suffix-like strings such as `#7b9`; this routed Sprint 49 to flat-root candidate availability rather than latency.
- next sprint candidate: Sprint 49 flat-root candidate availability.

### Sprint 49: Flat Root Candidate Availability

- status: complete; required GitHub Actions passed
- flat-root commit: `0d6ba7e Fix sprint 49 flat-root candidate availability`
- summary: Restored root-bearing candidate availability for fused flat-root altered chords by splitting an attached flat modifier away from a root-construction cluster when geometry supports that general interpretation. Added saved-chart replay diagnostics and a synthetic clusterer test without importing the user's pass as training data.
- tests and evidence: targeted saved-pass replay recovered `Db7(b9)` as the primary root-bearing match; focused clusterer test passed; focused `ChordInkRecognizerTests` and `WritingToRenderPipelineReadinessTests` passed; full SwiftPM tests passed with `319` tests, `36` skipped, `0` failures; full XcodeBuildMCP iOS simulator scheme passed with `336` tests, `36` skipped, `0` failures; Python script compilation and `git diff --check` passed; required GitHub Actions passed. The repeat pass on chart `ED98F246-3A73-493C-BF8A-9106DAE76F04` showed `C`, `G/B`, and `Db7(b9)` all auto-rendered correctly.
- behavior boundary: no personal handwriting fixture was imported, no recognition score was retuned, no OCR authority changed, no symbol-ledger diagnostics were enabled, and export/share plus chord ink clearing were untouched.
- unresolved follow-up: the pass felt smooth and correct, but the user observed it could still be a bit faster after the final ink stroke, especially for basic chords. Diagnostics showed the remaining time is mostly intentional scheduler idle rather than recognizer or render cost.
- next sprint candidate: Sprint 50 post-stroke responsiveness.

### Sprint 50: Post-Stroke Responsiveness

- status: complete; required GitHub Actions passed for app commit
- responsiveness commit: `a84e397 Tune sprint 50 post-stroke responsiveness`
- summary: Made a conservative scheduler polish after Sprint 49 proved recognition/render work was already low-cost. Normal chord-ink idle moved from `0.85s` to `0.75s`; root-only continuation grace moved from `0.55s` to `0.40s`; extension-prefix grace stayed `1.2s`.
- tests and evidence: focused writing-to-render readiness test passed; full SwiftPM passed with `319` tests, `36` skipped, `0` failures; focused XcodeBuildMCP scheduling tests passed with `5` tests, `0` failures; full XcodeBuildMCP iOS simulator scheme passed with `336` tests, `36` skipped, `0` failures; Python script compilation and `git diff --check` passed. The repeat pass on chart `3800A7BA-DA57-4596-A4F2-A3336FA5742B` showed `C` auto-rendering with a `405ms` final root-continuation pass, `G/B` auto-rendering at `782ms`, and `Db7(b9)` confirming with supported suggestions at `813ms`.
- behavior boundary: no recognition score, training data, OCR authority, symbol-ledger behavior, export/share, or chord ink clearing changed.
- unresolved follow-up: none for the bounded writing-to-render loop; the user confirmed it felt good and rendered when expected.
- next sprint candidate: Sprint 51 real-life polish.

### Sprint 51: Real-Life Polish

- status: complete; routed to Sprint 52 correction UX
- kickoff commit: `ec0b30b Close sprint 50 and open sprint 51`
- summary: Moved out of the bounded chord-recognition loop and into product polish planning. The user chose UX/UI for chord confirmation and the user correction loop as the first post-loop product lane.
- tests and evidence: Sprint 51 was doc/routing work, backed by Sprint 50's green broad app baseline and the user's confirmation that the writing-to-render pass felt good and rendered when expected.
- behavior boundary: no recognition score, fixture corpus, OCR authority, symbol-ledger behavior, PencilKit capture, export/share, or chord ink clearing changed in Sprint 51.
- unresolved follow-up: implement the first correction UX rules without creating a new handwriting training loop.
- next sprint candidate: Sprint 52 chord confirmation user loop.

### Sprint 52: Chord Confirmation User Loop

- status: complete; required GitHub Actions passed and user validated the loop as working
- implementation commit: `0a59588 Add sprint 52 chord confirmation user loop`
- validation setup commit: `b8b3f33 Set up sprint 52 manual UX validation`
- deletion-feedback commit: `bded045 Record deleted chord auto-render rejections`
- summary: Added the first local correction UX loop without turning recognition into handwriting training. Complete failures auto-clear for two attempts before direct input, close-race confirmation shows top-three supported choices, non-extremely-tight confirmed suggestions can create local user rules, manual entry outside suggestions records local exclusions, and deleting an ink-origin rendered chord records negative feedback against that exact ink/chord pair.
- tests and evidence: focused `ChordInkUserCorrectionMemoryTests` passed with `7` tests and `0` failures; focused `ChordEntryDiagnosticsTests` passed with `7` tests and `0` failures; XcodeBuildMCP focused iOS simulator `ChordInkUserCorrectionMemoryTests` passed with `7` tests and `0` failures; `git diff --check` passed; required GitHub Actions passed on `0a59588`, `b8b3f33`, and `bded045`. The user reported the UX seems to be working.
- behavior boundary: no fixture expansion, score retuning from one user's pass, default OCR expansion, symbol-ledger diagnostics cost, export behavior, PencilKit capture, or global recognition authority changed.
- unresolved follow-up: the correction loop must never become a write -> wrong render -> delete -> rewrite trap; future correction-memory work should route repeated negative feedback to confirmation/direct input rather than repeating the same wrong auto-render.
- next sprint candidate: Sprint 53 validation speed.

### Sprint 53: Validation Speed

- status: complete; direct-main app validation passed and CodeQL defer proved on `main`
- workflow commit: `89ec2dc Speed up sprint validation checks`
- summary: Reduced default sprint validation drag while preserving required check names. SwiftPM and iOS simulator jobs now detect app-impacting paths and no-op for docs/config-only changes. Direct-main `Analyze Swift` now reports an explicit CodeQL defer, while pull requests, scheduled weekly scans, and manual dispatch still run real Swift CodeQL.
- tests and evidence: local workflow YAML parse passed for `.github/workflows/ci.yml` and `.github/workflows/codeql.yml`; `git diff --check` passed; main commit `89ec2dc` passed `SwiftPM tests`, `iOS simulator tests`, `Analyze Swift`, and `Dependabot`. The `Analyze Swift` log showed CodeQL was deferred on the direct `main` push instead of running the full build/analyze lane.
- behavior boundary: no runtime recognition, correction-memory, PencilKit, export, editor, fixture, OCR, symbol-ledger, or app behavior changed.
- unresolved follow-up: verify the docs/config-only no-op path on the next source-of-truth-only push; keep real CodeQL on PR/schedule/manual runs.
- next sprint candidate: Sprint 54 product polish decision.

### Sprint 54: Confirmation UX Polish

- status: complete; required GitHub Actions passed and simulator validation improved the sheet feel
- polish commit: `03305eb Simplify chord confirmation UX`
- metadata follow-up commit: `d5fb582 Avoid duplicate chord diagnostic rows`
- summary: Simplified the chord confirmation sheet into a centered product chooser with selected chord, top-three suggestions, one manual input box, and compact Accept/Keep Ink/Rewrite actions. The user validated that the lighter sheet felt much better. A metadata follow-up changed render-handoff timing evidence to replace the matching commit diagnostic instead of appending a duplicate row for the same chord event.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint54-diagnostics --filter ChordEntryDiagnosticsTests` passed with `8` tests and `0` failures; XcodeBuildMCP iOS simulator compile-only build passed for the `iChart` scheme with `CODE_SIGNING_ALLOWED=NO`; `git diff --check` passed; required GitHub Actions passed on `03305eb`, `74781ce`, and `d5fb582`.
- behavior boundary: no recognition score, trust policy, parser authority, correction-memory policy, PencilKit capture behavior, export behavior, fixture corpus, OCR authority, symbol-ledger diagnostics cost, or chart mutation behavior changed.
- unresolved follow-up: do not continue redundant confirmation passes unless real use shows new friction. The next move should be a product-prioritization decision.
- next sprint candidate: Sprint 55 product prioritization.

### Sprint 55: Chord-First Product Polish

- status: complete; required GitHub Actions passed on final commit `1eebe00`
- commit range: `7740a3f` through `1eebe00`
- summary: Kept the roadmap centered on chord work. Rhythm-aware chord insertion now snaps to the nearest playable rhythm-slot attack/start position; chord-entry diagnostics record placement evidence and timing summaries; the audit script surfaces placement, drift, and timing evidence; compact suspended-chord recognition keeps `Absus` available without handwriting-specific fixtures; live chord writing keeps active strokes owned by `PKCanvasView`; and real iPad/device chord entry is Pencil-only while simulator builds keep pointer input for automation.
- tests and evidence: focused `MeasureRhythmMappingTests` passed with `15` tests and `0` failures; focused `ChordEntryDiagnosticsTests` passed with `8` tests and `0` failures; focused `ChordInkCandidateComposerTests` passed with `51` tests and `0` failures; focused `ChordInkRecognizerTests` passed with `40` tests, `1` skipped, and `0` failures; saved-state replay showed the three `Absus` rows matching `Absus` through confirmation; focused XcodeBuildMCP `LeadSheetInteractionModeStatePolicyTests` passed with `2` tests and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed; `xcodegen generate`, Python compile checks, and `git diff --check` passed; required GitHub Actions passed on the final commit.
- behavior boundary: no personal handwriting fixture expansion, no score retuning, no default OCR expansion, no symbol-ledger diagnostics cost, no export behavior change, and no change to the current accepted-chord ink clearing rule.
- unresolved follow-up: the fast-writing/Pencil-only changes still need one bounded real iPad/Pencil pass before more architecture work. The pass should determine whether the next implementation lane is placement/snapping, render/update handoff, candidate availability, confirmation/correction, or export fidelity.
- next sprint candidate: Sprint 56 chord field validation.

### Sprint 56: Chord Field Validation

- status: complete; required GitHub Actions passed and the bounded repeat pass was reported as golden
- commit range: `db52d7d` through `1fb2670`
- summary: Validated the Sprint 55 chord-first field path and tightened the parser/confirmation authority boundary. Real device chord entry remains Pencil-only, simulator builds keep pointer input for automation, unsupported confirmation suggestions such as `Db(b9)(b9)` are gated out before reaching the user, supported altered extensions remain available, and the repeat-pass setup captured the final validation contract.
- tests and evidence: Sprint 56 parser/confirmation authority fix `swift test --scratch-path /tmp/iChartSwiftBuild-sprint56-compendium` passed with `330` tests, `36` skipped, and `0` failures; focused XcodeBuildMCP iOS simulator recognition tests passed with `53` tests and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed for the repeat setup; `git diff --check` passed; required GitHub Actions passed on `1fb2670`. The user reported the repeat pass was "all golden."
- behavior boundary: no personal handwriting fixture expansion, no score retuning from one user's pass, no default OCR expansion, no symbol-ledger diagnostics cost, no export behavior change, and no change to accepted-chord ink clearing.
- unresolved follow-up: the recovery/audit arc is no longer the blocker. Continue through scoped chord-first side sprints, starting with placement/edit behavior, and keep validation proportional.
- next sprint candidate: Sprint 57 chord placement and edit loop.

### Sprint 57: Chord Placement And Edit Loop

- status: complete locally; required GitHub Actions need to run after push
- implementation commit: Sprint 57 closeout commit containing this entry
- summary: Improved the existing rendered-chord edit affordance without changing placement math. Delete and move controls are larger, the move control now has an explicit grip mark, active move state redraws immediately, and the moving chord gets a stronger highlight while dragged.
- tests and evidence: `xcodegen generate` passed; XcodeBuildMCP focused iOS simulator `iChartTests/LeadSheetChordEditOverlayGeometryTests` passed with `3` tests and `0` failures; focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint57-placement --filter MeasureRhythmMappingTests` passed with `15` tests and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed and launched `com.ichart.app` on the iPad simulator.
- behavior boundary: no personal handwriting fixture expansion, no recognition score retuning, no parser/compendium authority change, no default OCR expansion, no symbol-ledger diagnostics cost, no export behavior change, and no accepted-chord ink clearing change.
- unresolved follow-up: this only improves the first placement/edit affordance. Deeper placement UI, snap-target preview, or richer drag feedback can be revisited if real chart use shows remaining friction.
- next sprint candidate: Sprint 58 wrong render recovery and replace UX.

### Sprint 58: Wrong Render Recovery And Replace UX

- status: complete; required GitHub Actions passed on `b748b2a`
- implementation commit: `b748b2a Reroute rejected chord auto-renders`
- summary: Extended deleted-render feedback so a wrong auto-render can be blocked by stable candidate signature as well as exact ink digest. `ChordEvent` now stores a local `sourceCandidateSignature`, old chart snapshots decode that missing field as empty, and future similar passes with the same wrong winning candidate reroute to confirmation/direct input instead of repeating the same auto-render.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint58-recovery --filter ChordInkUserCorrectionMemoryTests` passed with `7` tests and `0` failures; focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint58-chart --filter ChartEditingTests` passed with `32` tests and `0` failures; XcodeBuildMCP focused iOS simulator `iChartTests/ChordInkUserCorrectionMemoryTests CODE_SIGNING_ALLOWED=NO` passed with `7` tests and `0` failures; `git diff --check` passed.
- behavior boundary: no personal handwriting fixture expansion, no recognition score retuning, no parser/compendium authority change, no default OCR expansion, no symbol-ledger diagnostics cost, no export behavior change, and no accepted-chord ink clearing change.
- unresolved follow-up: the reroute lands in the existing confirmation/direct-entry sheet. Sprint 59 should make that sheet feel less like a warning/debug fallback when it appears after deleted-render feedback.
- next sprint candidate: Sprint 59 confirmation and direct input polish.

### Sprint 59: Confirmation And Direct Input Polish

- status: complete; required GitHub Actions passed on `88feda5`
- implementation commit: `88feda5 Polish chord confirmation flow`
- summary: Turned the chord confirmation/direct-entry sheet into a calmer product loop. The sheet now uses compact top-three candidate buttons, a clearly labeled manual-entry field, concise reroute/close-race copy, and clearer `Accept Chord` / `Rewrite Ink` actions.
- tests and evidence: `xcodegen generate` passed; XcodeBuildMCP focused iOS simulator `iChartTests/ChordInkUserCorrectionMemoryTests CODE_SIGNING_ALLOWED=NO` passed with `7` tests and `0` failures; `git diff --check` passed.
- behavior boundary: no personal handwriting fixture expansion, no recognition score retuning, no parser/compendium authority change, no default OCR expansion, no symbol-ledger diagnostics cost, no export behavior change, no placement behavior change, and no accepted-chord ink clearing change.
- unresolved follow-up: candidate availability remains the next chord-first blocker for supported chord families that do not reliably enter the top supported candidates.
- next sprint candidate: Sprint 60 general candidate availability hardening.

### Sprint 60: General Candidate Availability Hardening

- status: complete; required GitHub Actions passed on `899f690`
- implementation commit: `899f690 Backfill supported chord candidate scores`
- summary: Hardened candidate-score availability without retuning recognition. The recognizer still keeps the top raw score prefix for diagnostics, but now backfills bounded unique supported candidates from beyond that prefix so confirmation/trust evidence can include compendium-approved chords even when unsupported numeric/noisy candidates occupy the top raw slots.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-sprint60-availability --filter ChordInkRecognizerTests` passed with `41` tests, `1` skipped by the opt-in full fixture archive gate, and `0` failures; `git diff --check` passed.
- behavior boundary: no personal handwriting fixture expansion, no recognition score retuning, no parser/compendium authority change, no default OCR expansion, no symbol-ledger diagnostics cost, no editor/export/placement/direct-input behavior change, and no accepted-chord ink clearing change.
- unresolved follow-up: if users still feel delay after supported candidates are visible, route to timing/render handoff evidence rather than score tuning.
- next sprint candidate: Sprint 61 raster/render handoff polish.

### Sprint 61: Raster/Render Handoff Polish

- status: complete locally; required GitHub Actions need to run after push
- implementation commit: Sprint 61 closeout commit containing this entry
- summary: Audited the writing-to-render handoff and closed without renderer/raster code changes. Current timing capture showed commit mutation stayed `3-7ms` and render handoff stayed `15-28ms`, while scheduler/continuation windows and complex-chord trust/OCR dominated perceived delay.
- tests and evidence: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed on the configured iPad simulator; screenshot verification passed; `python3 scripts/audit_chord_entry_diagnostics.py --app-data "$APP_DATA" --chart-id 57C55F1B-3860-43D1-9622-5FCF7D9EC403 --details --scores 8` reported `7` active diagnostics with timing evidence; `python3 scripts/analyze_chord_timing_logs.py` parsed the runtime log; `git diff --check` passed.
- behavior boundary: no code behavior change, no personal handwriting fixture expansion, no recognition score retuning, no parser/compendium authority change, no default OCR expansion, no symbol-ledger diagnostics cost, no editor/export/placement/direct-input behavior change, and no accepted-chord ink clearing change.
- unresolved follow-up: one `Db7(b9)` placement evidence mismatch appeared between diagnostic start `3` and current chart start `1`; route that as release-candidate placement evidence if it reproduces.
- next sprint candidate: Sprint 62 chord-first release-candidate pass.

### Sprint 62: Chord-First Release Candidate Pass

- status: complete; required GitHub Actions passed on `6e8ae16`
- setup commit: `4fa2f53 Set up sprint 62 release candidate pass`
- evidence commit: `5f9c4c8 Record sprint 62 pass evidence`
- closeout commit: `6e8ae16 Close sprint 62 release candidate pass`
- summary: Closed the chord-first side-sprint lane with one bounded release-candidate pass. The active chart committed `C`, `G/B`, `Db7(b9)`, and `Absus` as structured `ChordEvent`s; `Db7(b9)` used local correction memory from a close race instead of score retuning; placement evidence matched; render handoff stayed small; and a fresh PDF export opened in Preview with all four chords visible.
- tests and evidence: required GitHub Actions passed on `4fa2f53`, `5f9c4c8`, and `6e8ae16`; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed on the configured iPad simulator; `python3 scripts/audit_chord_entry_diagnostics.py --app-data "$APP_DATA" --chart-id 9F9DD955-91BF-4361-9B02-177B49C48A0C --details --scores 8` reported `4` active diagnostics, `0` missing diagnostics, `0` stale diagnostics for the active chart, matched placement, and timing evidence for all four chords; the fresh PDF export was modified at `2026-05-27 12:23:13 -0700`, identified as a one-page PDF, and rendered successfully through QuickLook.
- behavior boundary: no code behavior change, no personal handwriting fixture expansion, no recognition score retuning, no parser/compendium authority change, no default OCR expansion, no symbol-ledger diagnostics cost, no editor/export implementation change, and no accepted-chord ink clearing change.
- unresolved follow-up: no release-candidate blocker remains from the bounded pass. Future work should be chosen from product priorities rather than reopening the recovery/audit loop.
- next sprint candidate: Sprint 63 chart layout goals.

### Sprint 63: Chart Layout Goals

- status: complete planning handoff
- planning commit: `4ddaa27 Define sprint 63 chart layout goals`
- summary: Defined the three New Chart layout styles: `Simple Chord Sheet`, `Rhythm Section Sheet`, and `Lead Sheet`; selected `ChartLayoutStyle` as the implementation name; and documented the shared chart-structure systems that future layout work should use.
- tests and evidence: documentation/product planning pass; the Sprint 64 implementation slice now covers durable layout-style persistence, picker routing, and backward-compatible decode behavior.
- behavior boundary: no recognition, parser, compendium, OCR, symbol-ledger, handwriting fixture, export renderer, or chord ink lifecycle changes.
- unresolved follow-up: Sprint 64 owns the durable implementation, manual picker-flow validation, and the decision about whether to stop at the thin chooser slice or continue into layout-profile contracts.
- next sprint candidate: Sprint 64 New Chart layout-style chooser.

### Sprint 64: New Chart Layout Style Chooser

- status: complete implementation slice
- implementation commit: pending local Sprint 64/Sprint 65 change set
- summary: Implemented `ChartLayoutStyle` as durable chart state; routed `New Chart` through the three-choice layout picker; applied safe style/engraving defaults per layout style; surfaced the selected style in library rows and setup; and kept existing charts backward-compatible by decoding missing layout style as `Lead Sheet`.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-layoutstyle --filter 'ChartEditingTests|ChartLibraryStoreTests'` passed with `43` selected tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutstyle` passed with `334` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed and confirmed the three-choice picker, `Rhythm Section Sheet` setup handoff, and editor open from `Create Blank Page`; `git diff --check` passed.
- behavior boundary: no recognition, parser, compendium, OCR, symbol-ledger, handwriting fixture, layout-specific renderer, export branch, or chord ink lifecycle changes.
- unresolved follow-up: define layout-profile contracts before branching toolbar emphasis, measure defaults, or renderer/export behavior.
- next sprint candidate: Sprint 65 layout-profile contracts.

### Sprint 65: Layout Profile Contracts

- status: complete implementation slice
- implementation commit: pending local Sprint 64/Sprint 65 change set
- summary: Added a computed `ChartLayoutProfile` contract for each `ChartLayoutStyle`. Profiles now define toolbar emphasis, primary tool focus, measure defaults, notation-lane intent, renderer route, and existing style/engraving defaults without persisting duplicate profile state on charts.
- tests and evidence: focused `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `35` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `336` tests, `36` skipped, and `0` failures; `xcodegen generate` completed; XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO` passed for the `iChart` scheme on the configured iPad simulator; `git diff --check` passed; `git clean -ndX` showed no ignored/generated debris.
- behavior boundary: no recognition, parser, compendium, OCR, symbol-ledger, handwriting fixture, layout-specific renderer, export branch, editor UI branch, or chord ink lifecycle changes.
- unresolved follow-up: decide whether to make the profile contracts executable by applying initial measure count, preferred measures per system, spacing mode, and beat-grid defaults to new chart structure.
- next sprint candidate: Sprint 66 profile-driven structure defaults.

### Sprint 66: Profile-Driven Structure Defaults

- status: complete locally; pending final commit in the combined Sprint 64-67 local change set
- implementation commit: pending local Sprint 64-67 change set
- summary: Applied layout-profile setup policy and safe structure defaults, verified the New Chart setup differences for Simple/Rhythm/Lead, implemented the first Simple Chord Sheet blank-measure renderer branch, and added the original Simple above/below free-hand path. That path is now historical and superseded by Sprint 68 chart-area freehand objects while keeping recognition/editing separate from chord entry.
- tests and evidence: focused `ChartEditingTests` passed with `42` tests and `0` failures; focused `LeadSheetPageLayoutTests` passed with `31` tests and `0` failures; XcodeBuildMCP focused `LeadSheetFreehandSymbolEditOverlayGeometryTests` passed with `4` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `347` tests, `36` skipped, and `0` failures; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed with the existing headermap warning; live simulator smoke selected, deleted, re-created, selected, and moved a saved Simple upper-lane mark.
- behavior boundary: no recognition, parser, compendium, OCR, symbol-ledger, handwriting fixture, score tuning, broad renderer/export rewrite, Lead Sheet pitched-note work, or Rhythm Section workflow changes.
- unresolved follow-up: Simple free-hand resizing, semantic classification, rhythm snapping, Rhythm workflow refinement, richer Lead Sheet melody editing/ledger-line/named-pitch behavior, and executable per-style system grouping remain separately scoped future work.
- next sprint candidate: Sprint 67 Rhythm Section current workflow lock.

## Chord-First Side Sprint Queue

Use this queue for chord-specific product work after Sprint 56. `docs/ichart-chord-first-side-sprints-2026-05-27.md` is the supporting route map; this file remains the active sprint authority.

- Sprint 57: Chord Placement And Edit Loop: complete; GitHub Actions passed on `ece1924`.
- Sprint 58: Wrong Render Recovery And Replace UX: complete; GitHub Actions passed on `b748b2a`.
- Sprint 59: Confirmation And Direct Input Polish: complete; GitHub Actions passed on `88feda5`.
- Sprint 60: General Candidate Availability Hardening: complete; GitHub Actions passed on `899f690`.
- Sprint 61: Raster/Render Handoff Polish: complete locally; GitHub verification was superseded by later green commits.
- Sprint 62: Chord-First Release Candidate Pass: complete; GitHub Actions passed on `6e8ae16`.

## Next Sprint Backlog

Use this queue for routing after the active chord-first side-sprint lane. The user has approved continuing through scoped product polish work, but verification should stay proportional unless a sprint touches broad recognition, editor, export, or project configuration surfaces.

- If the full flow feels good, close the recovery/audit arc and move to feature prioritization.
- If correction friction returns after Sprint 52, route a future sprint to confirmation sheet interaction polish or direct-input affordances.
- If placement/snapping is the main issue, route a future sprint to chart placement polish.
- If Library/navigation friction dominates, route a future sprint to app-shell polish.
- If the repeat pass shows render/proposal/commit latency, route to an editor/render performance sprint.
- If the duplicated-screen observation persists with screenshot/repro, choose a visual/UI state bug sprint.
- Repeat visual renderer QA only when a new export/layout defect appears; Sprint 40 established the current PDF/PNG baseline.
- If real Pencil validation and renderer QA must wait, choose a repo-local product-evidence sprint with direct user value, such as Library organization or correction workflow friction.
- Inspect any remaining `ChordInkRecognitionSession` follow-up only if new evidence shows a boundary bug or maintenance hotspot, keeping UI, chart mutation, diagnostics, continuation grace, and chord ink clearing outside the session.
- Continue editor surface cleanup with another small modal/subview extraction from `EditorView.swift` if bridge extraction looks too entangled for a single sprint.
- Continue app-shell/product polish only if the next Library need is real organization work such as search, sort, archive, or import.
- Split semantic candidate recipes into smaller behavior-preserving files only if the review surface still feels too large.
- Discuss full fixture archive pruning only as repository/data hygiene, not as recognition training.

## Retired Or Stale Docs

Current authority:

- `docs/ichart-sprint-source-of-truth.md`: active sprint execution and recovery plan.
- `docs/ichart-post-merge-app-audit-2026-05-23.md`: Sprint 12 written and visual post-merge app/architecture audit.
- `docs/ichart-editor-recognition-execution-audit-2026-05-24.md`: Sprint 34 audit of the remaining editor-to-recognition execution boundary.
- `docs/ichart-recognition-session-boundary-design-2026-05-25.md`: Sprint 35 design for a future behavior-preserving recognition-session boundary.
- `docs/ichart-real-life-testing-readiness-2026-05-25.md`: Sprint 42 handoff from automated writing-to-render QA into real Pencil product validation.
- `docs/ichart-real-pencil-field-test-log-2026-05-26.md`: Sprint 43 real Pencil field-test evidence log.
- `docs/ichart-post-export-field-test-log-2026-05-26.md`: Sprint 45 post-export real Pencil validation log.
- `docs/ichart-recognition-latency-triage-2026-05-26.md`: Sprint 46 recognition latency evidence.
- `docs/ichart-sprint-46-latency-repeat-log-2026-05-26.md`: Sprint 46 real Pencil latency repeat gate.
- `docs/ichart-sprint-47-confidence-performance-triage-2026-05-26.md`: Sprint 47 confidence/performance split triage.
- `docs/ichart-sprint-47-timing-capture-log-2026-05-26.md`: Sprint 47 real-device timing capture gate.
- `docs/ichart-sprint-48-persistent-timing-telemetry-2026-05-26.md`: Sprint 48 persistent timing telemetry and bounded-pass setup.
- `docs/ichart-sprint-49-flat-root-candidate-availability-2026-05-26.md`: Sprint 49 flat-root candidate availability and bounded-repeat setup.
- `docs/ichart-sprint-50-post-stroke-responsiveness-2026-05-26.md`: Sprint 50 post-stroke responsiveness and bounded-repeat setup.
- `docs/ichart-sprint-51-real-life-polish-2026-05-26.md`: Sprint 51 real-life polish and product-flow evidence routing.
- `docs/ichart-sprint-52-chord-confirmation-user-loop-2026-05-26.md`: Sprint 52 chord confirmation and local user correction loop.
- `docs/ichart-sprint-52-manual-ux-validation-log-2026-05-26.md`: Sprint 52 bounded manual UX validation gate.
- `docs/ichart-sprint-53-validation-speed-2026-05-26.md`: Sprint 53 validation-speed policy and workflow cleanup.
- `docs/ichart-sprint-54-confirmation-ux-polish-2026-05-26.md`: Sprint 54 confirmation UX polish.
- `docs/ichart-sprint-55-chord-first-product-polish-2026-05-26.md`: Sprint 55 chord-first product polish.
- `docs/ichart-sprint-56-chord-field-validation-2026-05-27.md`: Sprint 56 bounded real-device chord validation.
- `docs/ichart-sprint-56-repeat-validation-log-2026-05-27.md`: Sprint 56 repeat validation gate and final field-pass checklist.
- `docs/ichart-chord-first-side-sprints-2026-05-27.md`: active chord-first side-sprint route map.
- `docs/ichart-sprint-57-chord-placement-edit-loop-2026-05-27.md`: Sprint 57 chord placement/edit loop.
- `docs/ichart-sprint-58-wrong-render-recovery-2026-05-27.md`: Sprint 58 wrong render recovery and replace UX.
- `docs/ichart-sprint-59-confirmation-direct-input-polish-2026-05-27.md`: Sprint 59 confirmation and direct-input polish.
- `docs/ichart-sprint-60-general-candidate-availability-hardening-2026-05-27.md`: Sprint 60 general candidate availability hardening.
- `docs/ichart-sprint-61-raster-render-handoff-polish-2026-05-27.md`: Sprint 61 raster/render handoff polish.
- `docs/ichart-sprint-62-chord-first-release-candidate-pass-2026-05-27.md`: Sprint 62 chord-first release-candidate pass.
- `docs/ichart-sprint-63-chart-layout-goals-2026-05-27.md`: Sprint 63 chart layout goals.
- `docs/ichart-sprint-64-new-chart-layout-style-chooser-2026-05-27.md`: Sprint 64 New Chart layout-style chooser.
- `docs/ichart-sprint-65-layout-profile-contracts-2026-05-27.md`: Sprint 65 layout-profile contracts.
- `docs/ichart-sprint-66-profile-driven-structure-defaults-2026-05-27.md`: Sprint 66 profile-driven structure defaults.
- `docs/ichart-sprint-67-rhythm-section-current-workflow-lock-2026-05-27.md`: Sprint 67 Rhythm Section current workflow lock.
- `docs/ichart-rhythm-section-v4-closeout-audit-2026-05-29.md`: Rhythm Section V4 core authoring closeout audit.
- `docs/ichart-rhythm-section-progress-log-2026-05-29.md`: Rhythm Section final integration breadcrumb log.
- `docs/core-design-document.md`: product intent and design rules.
- `docs/developer-mvp-spec.md`: MVP scope, subordinate to the core design document.
- `docs/repo-github-recognition-audit-2026-05-20.md`: evidence snapshot for the current recovery plan.

Historical or stale context:

- `docs/handwriting-recognition-implementation-plan.md`: original recognition architecture plus historical pass notes. Use for background only until a future sprint rewrites it.
- `docs/current-architecture-audit.md`: stale because it predates live chord-entry recognition.
- `docs/architecture-reset-proposal.md`: useful historical proposal, not the active sprint plan.
- `docs/implementation-milestones.md`: older execution sequence; do not use it to override this document.

## Update Protocol

At sprint completion:

1. Run the required verification commands.
2. Record the final commit or commit range.
3. Move the active sprint summary into `Completed Sprints Log`.
4. Record any unresolved risks.
5. Discuss the next sprint before editing `Active Sprint`.
6. Keep prior completed entries intact.

Do not start a new recognition or editor sprint from memory alone. Reopen this document, the latest audit/pass evidence, and the current git state first.
