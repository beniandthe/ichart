# iChart Rhythm Section Side Sprint Plan

Status: complete locally; Rhythm Section core and V4 gate verified, deferred systems definition-gated
Date: 2026-05-27
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Purpose

This side sprint moves `Rhythm Section Sheet` from a behavior-locked designation into its own core authoring lane. The goal is not a new chart-layout engine yet; it is the smallest durable pass for measure actions, rhythm-lane auto-render, chord snapping, and below-staff free-hand articulations.

## Scope

- Keep Rhythm Section setup keyless and clefless.
- Keep starting time and starting measures.
- Preserve the hard minimum of one measure.
- Keep staff-line measures and chord lane above the staff.
- Keep rhythm notation inside the measure lane.
- Add Rhythm Section free-hand articulation objects below the staff only.
- Keep chord snapping routed through `MeasureRhythmMap`, resolved rhythm slots, and beat fallback.

## Implementation Steps

1. Branch from the current Sprint 64-67 working tree.
   - Use `codex/rhythm-section-core-authoring`.
   - Carry the verified layout-style chooser, profile defaults, Simple Chord Sheet lane work, and Sprint 67 workflow lock.

2. Generalize free-hand symbol lanes by layout profile.
   - Simple Chord Sheet support has since moved to measure-attached chart-area freehand objects; Rhythm Section remains below-measure only.
   - Rhythm Section Sheet supports below-measure lane only.
   - Lead Sheet has no free-hand symbol lanes for now.

3. Add core measure actions.
   - Convert the Measures tab to an explicit menu.
   - Add `Edit Measures`, `Add Measure at Beginning`, and `Add Measure After Selected`.
   - Preserve existing manual measure-width resizing.

4. Move exact-fit rhythms to auto-render.
   - Exact-fit rhythm passes arm a short grace window, then commit only if the same live canvas snapshot still exactly fits the measure.
   - Underfilled, overflow, and unsupported rhythm passes stay local to the selected measure while the user is still writing.
   - `RhythmicNotationCompendium` gates final values to the supported v1 rhythm vocabulary and exact meter fit before the rhythm map commits.
   - Dirty rhythm ink stays owned by the live `PKCanvasView` during active writing so stale model sync cannot erase fast strokes before persistence or render.
   - Rhythm auto-render reads from a stable live-canvas snapshot instead of persisting raw rhythm ink to the chart model on every idle tick.
   - The exact-fit grace window lets final beams, dots, or rest cleanup strokes cancel and reschedule the pending render before ink clears.
   - Sloped handwritten beams are recognized as beamed-eighth connectors only when they cover two stems, leaving the compendium and exact meter fit as the final gate.
   - Folded beam/right-stem handwriting is recognized as a beamed-eighth connector only when paired with notehead evidence, and protected beamed reads no longer fall through to longer dotted-value reinterpretation when the measure is still underfilled.
   - Auto-render now consumes a `RhythmicNotationMeasureProposal` instead of only a final value list. Exact-fit proposals ending on a quarter-like stem with a playable eighth alternative request an extra stability window, which keeps last-beat beamed-eighth ink from clearing before the beam can land.
   - Rhythm Recognition V2 safety starts at the auto-render boundary: exact-fit values must also be safe to auto-apply before the host clears live ink. Current V4 evidence can auto-apply strong single-crop whole-note reads, while tiny low-information whole-like marks and single whole-rest measures remain review-only.
   - Live ink tools expose a left-side write/erase tab. Ink tools always open in write mode, and erase mode wipes only the active live `PKCanvasView` strokes without touching rendered chart items.
   - Post-erase rhythm rendering is stricter but not blocked: erasing an extra symbol can still commit if the remaining ink is naturally exact-fit, while stretched/reinterpreted exact-fit paths stay local until replacement ink is written.
   - Raw-ink beamed-eighth repair: the visual pass now keeps a stemmed notehead from being claimed as an eighth rest before its attached stem/dot can form the intended note, and local touch-up strokes around a beamed pair are included in the protected beamed-eighth event instead of forcing fallback reinterpretation.
   - Follow-up raw-ink evidence showed the pipeline itself is not reliable enough: when the visual pass returns `nil`, fallback meter-fit can still invent an exact measure. Live auto-render and selection finalization now require natural exact fit while Rhythm Recognition V3 rebuilds the recognizer from ordered ink primitives and phrase hypotheses.
   - Rhythm Recognition V3 first slice now adds ordered ink primitives, symbol hypotheses, phrase hypotheses, and explicit `commit` / `keepWriting` / `needsReview` decisions. Live auto-render and tap-away finalization require V3 `commit`; fallback-created exact fits can no longer clear ink.
   - Rhythm Recognition V3 visual-rest slice now promotes quarter rests, half rests, and whole rests into visual phrase hypotheses. Quarter/half rest phrases can commit when naturally exact; single whole-rest measures remain manual-review; quarter-rest bodies are protected from eighth-rest and beamed-eighth stealing.
   - Rhythm Recognition V3 phrase-ambiguity slice now sends tight mixed rest/note clusters to `needsReview(.ambiguousPhrase)`: the manual quantizer can still return the intended values, but live auto-render will not clear ink when adjacent rest and note symbols are visually entangled.
   - Rhythm mode now resolves a real authoring measure when entered, and tapping the already-active Rhythm tab repairs a missing selection instead of only opening the rhythm guide. This keeps the measure-owned rhythm canvas available before the user starts writing.
   - Rhythm auto-render now rechecks a stable stroke-shape snapshot instead of comparing PencilKit serialized `Data`, so metadata churn in an otherwise unchanged live drawing cannot make the pipeline silently go stale.
   - Temporary runtime auto-apply trace logging was removed after the stable snapshot pass was verified; the product path keeps the stable snapshot guard without a new default diagnostic stream.
   - Rhythm Recognition V3 uncovered-ink handling now keeps recognized visual phrases inside the V3 path when extra visible strokes remain: exact visual symbols plus leftover ink become `keepWriting(.uncoveredStrokes)` and do not fall back to legacy meter fitting.
   - Rhythm Recognition V3 competing-exact handling now distinguishes close full-measure alternatives from generic manual review: low-information whole-measure marks stay `needsReview(.manualReview)`, while near-tied exact phrase reads become `needsReview(.competingExactPhrases)`.
   - Rhythm Recognition V3 non-visual-fallback handling now fails closed locally: the manual quantizer can still use the legacy fitter for tooling and diagnostics, but live V3 decisions return `keepWriting(.nonVisualFallback)` with no proposal whenever exact fit depends on the non-visual fallback path.
   - Rhythm unread-ink feedback now draws a local red dashed overlay only for completed-looking non-commit rhythm decisions with a localized unread target. Underfilled/no-ink states stay quiet, commits clear the overlay, and the feedback is not persisted or used as recognizer training.
   - Rhythm unread-ink feedback now targets V3 uncovered-stroke bounds when the decision includes them, so extra unread strokes can be highlighted directly. Broad review/fallback states no longer fall back to framing the whole live drawing.
   - Rhythm Recognition V4 is now implemented as a raster/template phrase gate ahead of the V3 safety bridge. It normalizes live rhythm ink into measure-relative symbol crops, matches those crops against a deterministic visual compendium, validates exact values through `RhythmicNotationCompendium` and `MeasureRhythmMap`, and only commits when visual evidence plus render alignment agree.
   - V4 unread-symbol feedback now targets the failing crop when a visible rhythm symbol cannot be accepted and the phrase is completed-looking. It does not show while the measure is still underfilled, and it does not use whole-frame fallback for broader review states.
   - V4 semantic visual gating now blocks exact-fit commits unless the symbol class has matching evidence: slashes cannot come from stemmed notehead crops, dotted values require detached dot evidence, and single eighth values require flag or beam evidence. Quarter-like unflagged stems may extend stability or produce review, but cannot drive a live auto-render as eighths.
   - V4 rest-crop ownership now keeps strong rest evidence inside rest-only template alternatives, protects strong quarter/half/whole rest matches from the generic eighth-rest hook, and reattaches adjacent eighth-rest dots to following tails after compound symbol splitting.
   - V4 non-exact phrase ownership now keeps strong template underfills and overflows local instead of handing them to older meter-fit paths. Completed unsupported crops stay local with crop-level unread evidence, single-unit unflagged-stem alternatives become manual review only, and beamed-template overcount cases can still fall back to the proven visual bridge.
   - V4 raster normalization now rejects tiny isolated noise marks before crop grouping. Clear phrases can still commit, while meaningful unsupported strokes remain local and can surface crop-level unread feedback.
   - V4 render comparison now has explicit pass/fail coverage: aligned exact phrases can clear the final gate, and exact values with bad visual spacing cannot auto-commit.
   - V4 visual note anchors are now reused by the separate Lead Sheet baseline after the Rhythm Section detour, including separate pitch anchors from beamed-eighth crops. This does not change Rhythm Section rendering, which still treats rhythm maps as slash/rest notation.
   - V4 internals now live in `RhythmicNotationRasterTemplateRecognizer.swift` beside the quantizer, while `RhythmicNotationQuantizer` remains the entrypoint and V3/visual/fallback bridge.
   - Shared proposal, phrase, primitive, decision, reason, candidate, and candidate-path types now live in `RhythmicNotationRecognitionTypes.swift` so the rhythm contract is no longer buried inside the quantizer implementation.

5. Add chord snap visibility.
   - Keep chord insertion/move snapping routed through the existing rhythm-slot and beat fallback helpers.
   - Draw the selected moving chord's guide line to its resolved beat/rhythm attack target.

## Guardrails

- Do not tune chord recognition.
- Do not expand personal handwriting fixtures.
- Do not enable OCR by default.
- Do not add symbol-ledger runtime cost.
- Do not add Section/System layout behavior in this side sprint.
- Lead Sheet pitched-note systems are not owned by this side sprint. The separate main-sprint baseline now uses V4 anchors for clamped in-staff notes without changing Rhythm Section behavior.

## Verification Log

- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `43` tests, `0` failures after profile-owned free-hand lanes and beginning-measure insertion landed.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests` passed with `33` tests, `0` failures after Rhythm Section below-staff free-hand layouts and chord snap-guide anchors landed.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter MeasureRhythmMappingTests` passed with `17` tests, `0` failures after adding the rhythm compendium exact-fit gate coverage.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, `0` failures.
- XcodeBuildMCP focused `test_sim` for terminal quarter-like stem proposal gating, completed last-beat folded beams, folded beamed-eighth success, and ambiguous-stem grace policy passed with `4` tests, `0` failures.
- XcodeBuildMCP focused `test_sim` for Rhythm Recognition V2 whole-measure safety passed with `4` tests, `0` failures.
- XcodeBuildMCP focused `test_sim` for ink write/erase policy passed with `3` tests, `0` failures.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `56` tests, `0` failures, including connected, loose, direct, sloped, folded, false-exact-fit, last-beat beam, extended-stability auto-apply, V2 manual-review safety, ink write/erase policy, and post-erase natural exact-fit coverage.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `46` tests, and `0` failures after the raw-ink beamed-eighth visual pass repair.
- Latest copied simulator raw-ink trace showed measure 2 had `visual=nil` and fallback exact-fit `quarter, dottedQuarter, dottedQuarter`; after the natural-exact-fit safety gate the same proposal reports `proposal.canAutoApply=false`.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `57` tests, and `0` failures after blocking non-natural exact-fit rhythm commits.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `60` tests, and `0` failures after adding V3 commit/keep-writing/review decision coverage.
- Earlier copied raw-ink replay evidence showed measure 1 as `v3.decision=commit`, while the bad measure 2 path depended on non-visual fallback exact fit. The current V3 gate keeps that class local as `keepWriting(.nonVisualFallback)` with no proposal handed back to live auto-render or selection finalization.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `51` tests, and `0` failures after the V3 visual-rest slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `62` tests, and `0` failures after the V3 visual-rest slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `63` tests, and `0` failures after the V3 phrase-ambiguity slice.
- XcodeBuildMCP focused `test_sim` passed with `4` tests and `0` failures after adding rhythm-entry measure resolution and V3 slash-decision regressions.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `110` tests, and `0` failures after the rhythm-entry measure selection repair.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the rhythm-entry measure selection repair.
- XcodeBuildMCP `test_sim` for `LeadSheetInteractionModeStatePolicyTests` passed with `12` tests and `0` failures after replacing serialized-data equality with stable rhythm ink snapshots.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `111` tests, and `0` failures after adding stable rhythm auto-apply snapshots.
- Latest live simulator pass after the stable snapshot repair matched the expected loop: the first measure committed `slash, slash, slash, slash`, the next measure committed `quarter, quarter, quarter, eighth, eighth`, and later underfilled/ambiguous attempts stayed local instead of forcing a commit.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the stable rhythm auto-apply snapshot repair; `git diff --check` passed.
- After removing temporary runtime auto-apply trace logging and the one-off live-trace replay helper, XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` still passed with `111` tests and `0` failures; full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` still passed with `354` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `112` tests and `0` failures after the V3 uncovered-ink slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V3 uncovered-ink slice; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` and screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for close competing exact phrases and whole-measure manual review passed with `2` tests and `0` failures after adding the V3 competing-exact-phrase reason.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `114` tests and `0` failures after the V3 competing-exact-phrase slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V3 competing-exact-phrase slice; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` and screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for non-visual fallback exact-fit handling passed with `1` test and `0` failures after confirming fallback-created exact fits stay local with no proposal.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `115` tests and `0` failures after the non-visual-fallback slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the non-visual-fallback slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the non-visual-fallback slice with the existing headermap warning only; screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for unread rhythm ink feedback policy and frame geometry passed with `2` tests and `0` failures after the unread-ink-feedback slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `117` tests and `0` failures after the unread-ink-feedback slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the unread-ink-feedback slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the unread-ink-feedback slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP focused `test_sim` for unread rhythm ink feedback policy, full-frame fallback, and targeted uncovered-stroke frame geometry passed with `3` tests and `0` failures after the targeted-unread-stroke-feedback slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `118` tests and `0` failures after the targeted-unread-stroke-feedback slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the targeted-unread-stroke-feedback slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the targeted-unread-stroke-feedback slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `80` tests and `0` failures after the V4 raster/template phrase gate and crop-level unread feedback slice.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `125` tests and `0` failures after the V4 raster/template phrase gate.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 raster/template phrase gate.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V4 raster/template phrase gate with the existing headermap warning only; screenshot proof showed the app launched to Projects.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `67` tests and `0` failures after the V4 semantic visual gate.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `128` tests and `0` failures after the V4 semantic visual gate.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 semantic visual gate; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V4 semantic visual gate with the existing headermap warning only.
- XcodeBuildMCP `test_sim` for `LeadSheetInteractionModeStatePolicyTests` passed with `17` tests and `0` failures after tightening unread feedback to completed-looking, localized targets only.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `129` tests and `0` failures after the unread-feedback targeting rule.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the unread-feedback targeting rule; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the unread-feedback targeting rule with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for the V4 rest phrase gate passed with `1` test and `0` failures after the rest-crop ownership repair.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `69` tests and `0` failures after broadening V4 rest, dotted, and long-value phrase coverage.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `131` tests and `0` failures after the V4 rest-crop ownership slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 rest-crop ownership slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V4 rest-crop ownership slice with the existing headermap warning only; screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for V4 underfill, overflow, unsupported-crop, and unflagged-eighth review gates passed with `5` tests and `0` failures after the V4 non-exact ownership slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `72` tests and `0` failures after the V4 non-exact ownership slice.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `134` tests and `0` failures after the V4 non-exact ownership slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 non-exact ownership slice.
- `git diff --check` passed after the V4 non-exact ownership slice, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for V4 noise rejection, unsupported-crop, and clear-quarter phrase coverage passed with `3` tests and `0` failures after the raster-normalization noise slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `73` tests and `0` failures after the V4 raster-normalization noise slice.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `176` tests and `0` failures after V4 render-comparison acceptance coverage and the Lead Sheet key-signature baseline.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `356` tests, `36` skipped, and `0` failures after V4 render-comparison acceptance coverage and the Lead Sheet key-signature baseline.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only after V4 render-comparison acceptance coverage and the Lead Sheet key-signature baseline.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after V4 visual note anchors were reused for mixed Lead Sheet note/rest and beamed-eighth finalization.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `186` tests and `0` failures after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after the behavior-preserving V4 core extraction.
- XcodeBuildMCP grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures after the V4 core extraction.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the V4 core extraction; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after the shared recognition-type and candidate/path extraction.
- XcodeBuildMCP grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures after the shared-type/candidate extraction.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the shared-type/candidate extraction; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, and `0` failures after the V3 phrase-ambiguity slice; `git diff --check` passed.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, and `0` failures after the V3 visual-rest slice; `git diff --check` passed.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, and `0` failures after the fail-closed rhythm safety gate; `git diff --check` passed.
- Earlier XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetChordEditOverlayGeometryTests`, and `LeadSheetFreehandSymbolEditOverlayGeometryTests` passed with `45` tests, `0` failures.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V3 decision slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library on the configured `iPad Pro 13-inch (M5)` simulator.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V3 visual-rest slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library on the configured `iPad Pro 13-inch (M5)` simulator.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V3 phrase-ambiguity slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library on the configured `iPad Pro 13-inch (M5)` simulator.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the rhythm-entry measure selection repair with the existing headermap warning only; the simulator is open on a Rhythm Section chart in `Rhythmic Notation` mode with write mode active and a measure selected.
- The updated simulator build/run launched successfully on `iPad Pro 13-inch (M5)` with the existing headermap warning only, and the latest Rhythm Section chart reopened in `Rhythmic Notation` mode with the left ink tool tab visible in write mode; tapping the eraser switched the highlighted mode.
