# Smart Chart Rhythm Recognition Rebuild Plan

Status: implemented locally; V3 fail-closed bridge and V4 raster/template phrase gate verified
Date: 2026-05-28
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Trigger

The latest simulator pass showed the current rhythm recognizer pipeline is not dependable enough for live authoring. The raw ink was good enough to preserve, but the rendered rhythm could still come from a fallback meter-fit rewrite after the visual pass failed.

Latest trace evidence:

- Measure 1 produced a natural visual exact fit: `dottedHalf, eighth, eighth`.
- Measure 2 had `visual=nil`, then fallback chose `quarter, dottedQuarter, dottedQuarter`.
- That fallback result was exact in 4/4 only because the meter-fit path stretched ambiguous groups into a measure total.
- The proposal reported `isNaturalExactFit=false`, which means it should not have cleared ink or rendered automatically.

Latest V4 trigger:

- The fail-closed V3 path preserved ink when clear rhythms did not render, but the feedback could still feel like whole-measure blame.
- The next product problem is not another threshold patch. The recognizer needs deterministic raster/template evidence before it can clear live rhythm ink with confidence.
- V4 therefore sits before the V3 bridge when it has strong visual authority, and V3 remains available only as a conservative keep-writing/review bridge when V4 cannot naturally own the phrase.

## Rebuild Contract

The rhythm recognizer must become a bottom-up phrase recognizer, not a meter-first fitter.

1. Capture raw PencilKit strokes as the only input authority.
2. Normalize strokes into ordered ink primitives.
3. Build local rhythm-symbol hypotheses from primitives.
4. Assemble hypotheses into a left-to-right rhythm phrase.
5. Validate the phrase against the rhythm compendium.
6. Commit only when the phrase naturally fills the measure.
7. Keep raw ink local and editable when the phrase is underfilled, overflowed, unsupported, or ambiguous.

Exact meter fit is a final validation gate, not a search strategy that may reinterpret weak groups just to complete a measure.

## Immediate Safety Gate

Live rhythm commit now fails closed:

- `RhythmicNotationMeasureProposal.canAutoApply` requires `isNaturalExactFit`.
- Live auto-render cannot clear ink for non-natural exact paths.
- Explicit selection finalization also routes through the same proposal safety gate instead of direct quantize, so tapping away cannot commit a fallback meter rewrite.
- The skipped-by-default simulator trace prints `proposal.canAutoApply` to expose this boundary while debugging live raw ink.

This does not solve the full recognition problem. It prevents the current weak fallback from creating false confidence while the recognizer is rebuilt.

## V3 Architecture Direction

The next implementation slice should introduce a small internal V3 recognizer beside the current quantizer before replacing it:

- `RhythmInkPrimitive`: stroke-derived primitives such as notehead, stem, beam, dot, slash, rest-shape, and cleanup mark.
- `RhythmSymbolHypothesis`: symbol candidates with covered stroke IDs, local bounds, value candidates, and ambiguity reason.
- `RhythmPhraseHypothesis`: left-to-right symbol sequence with covered strokes, uncovered strokes, natural duration total, and compendium result.
- `RhythmRecognitionDecision`: `commit`, `keepWriting`, or `needsReview`.

Commit rules:

- `commit` only when one phrase covers the relevant ink, naturally totals the measure, and passes the compendium.
- `keepWriting` for underfilled measures, uncovered strokes, or competing phrase totals.
- `needsReview` for exact totals that depend on a non-natural rewrite, low-information whole-measure marks, or unresolved rest/note collisions.

## Implemented V3 Slice

The first V3 slice is now in place:

- `RhythmInkPrimitive` records ordered primitive stroke evidence for each pass.
- `RhythmSymbolHypothesis` records the covered stroke IDs, local bounds, candidate values, and selected value for each visual symbol group.
- `RhythmPhraseHypothesis` records phrase source, primitives, symbols, uncovered strokes, natural values, natural units, target units, and compendium status.
- `RhythmRecognitionDecision` separates `commit`, `keepWriting`, and `needsReview`.
- Live auto-render and selection finalization now require a V3 `commit`; `keepWriting` and `needsReview` preserve the ink.
- The legacy candidate fitter can still support manual quantize and diagnostics, but exact fits from that path now return `keepWriting(.nonVisualFallback)` in the live V3 decision path instead of handing back a review proposal.
- The second V3 slice makes rests first-class visual hypotheses: quarter rests and half rests can commit as natural visual phrases, single whole-rest measures remain visual but require manual review, and clear quarter-rest bodies are protected from being stolen by eighth-rest or beamed-eighth passes.
- The phrase-ambiguity slice now fails tight mixed rest/note clusters closed: manual quantize can still resolve the phrase, but live auto-render returns `needsReview(.ambiguousPhrase)` when adjacent rest and note symbols are too visually entangled to clear ink confidently.
- Slash notation now has explicit V3 decision coverage for both standard and loose/short slash phrases, confirming that supported slash-only measures still reach `commit` rather than falling into review-only fallback.
- Live auto-apply stability now uses a stroke-shape snapshot instead of `PKDrawing.dataRepresentation()` equality, so serialized PencilKit metadata changes do not turn unchanged visible ink into a stale scheduled pass.
- Temporary runtime auto-apply trace logging and the one-off live-trace replay helper were removed after the stable-snapshot pass was captured, leaving the snapshot guard without a new default diagnostic stream.
- The uncovered-ink slice keeps visual recognition authoritative when extra visible strokes remain: recognized visual symbols now carry uncovered stroke indices, and an otherwise exact visual phrase with leftover ink returns `keepWriting(.uncoveredStrokes)` instead of falling through to legacy fallback.
- The competing-exact-phrase slice separates close full-measure alternatives from generic manual review: low-information whole-measure marks still report `needsReview(.manualReview)`, while near-tied exact phrase reads report `needsReview(.competingExactPhrases)` and cannot auto-clear ink.
- The non-visual-fallback slice removes fallback-created exact fits from the proposal path entirely: live auto-render and selection finalization get no proposal when the visual recognizer cannot build the phrase, while manual quantize can still return the legacy fitter's values for tooling and diagnostics.
- The unread-ink-feedback slice turns completed-looking non-commit V3 decisions into local visual feedback: underfilled/no-ink states stay quiet so in-progress writing is not noisy, and feedback is UI-only. It does not train, retune, persist diagnostics, or change the recognizer authority.
- The targeted-unread-stroke-feedback slice uses V3 uncovered-stroke evidence when available: `keepWriting(.uncoveredStrokes)` highlights the unread primitive/stroke bounds instead of wrapping the whole live drawing. Broader review/fallback reasons stay quiet unless they can provide a localized unread symbol or primitive target.

## Implemented V4 Raster/Template Gate

The first V4 slice is now in place as a sibling core beside the existing quantizer. `RhythmicNotationQuantizer` remains the public entrypoint and V3/visual/fallback bridge; `RhythmicNotationRasterTemplateRecognizer` owns the V4 raster input, crop/template matching, phrase decisions, render comparison, and visual note anchors:

- `RhythmPhraseSource.rasterTemplate` identifies decisions that come from the deterministic V4 visual gate.
- `RhythmInkRasterInput` normalizes live rhythm strokes into measure-relative raster cells and ordered symbol crops.
- `RhythmSymbolCrop`, `RhythmVisualTemplate`, `RhythmTemplateMatch`, and `RhythmVisualCompendium` provide a writer-agnostic visual compendium for the supported v1 rhythm vocabulary.
- `RhythmRenderComparison` checks whether an exact phrase visually aligns with the ink positions before auto-commit. Exact meter alone is not enough.
- V4 searches visual template matches first, assembles left-to-right phrase candidates, then uses `RhythmicNotationCompendium.accepts` plus `MeasureRhythmMap.resolvedSlots` as the meter/value authority.
- V4 commits only when visual templates, exact meter fit, no meaningful unread crop, and render alignment agree.
- V4 returns `keepWriting` for unsupported visible crops and leaves non-authoritative cases to the existing fail-closed bridge instead of letting legacy fallback auto-render a live exact fit.
- Beamed eighth pairs now have dedicated V4 phrase coverage in first, middle, and final beat positions, including protection from quarter-note lookalike early commits.
- The V4 semantic visual gate now requires value-specific evidence before exact-fit can drive a commit: slash values cannot come from stemmed notehead crops, dotted values require detached dot evidence, and single eighth values require flag/beam evidence. An unflagged quarter-like stem may extend stability or require review, but it cannot force live auto-render as an eighth.
- Red unread-ink feedback now waits until the phrase is completed-looking before drawing, and only draws localized unread targets: V4 unread symbol crop bounds or V3 uncovered primitive bounds. It no longer falls back to a whole-measure/live-ink frame for broad unread states.
- V4 rest-crop ownership now keeps strong rest evidence inside rest-only template alternatives, protects strong quarter/half/whole rest matches from the generic eighth-rest raster hook, and reruns eighth-rest dot-to-tail reattachment after compound symbol splitting. Adjacent eighth rests now remain separate dot/tail crops, and rest-owned phrases no longer fall into close note/rest exact-fit competition.
- V4 phrase coverage now includes dotted quarter, dotted half, long-value mixtures, quarter rests, half rests, adjacent eighth rests, and whole-rest review through the raster/template source when crops are complete.
- V4 non-exact phrase ownership now keeps strong template underfills as `keepWriting(.underfilled)`, strong template overflows as `keepWriting(.overflow)`, and completed phrases with unsupported crops local with unread-symbol evidence. A single-unit unflagged-stem exact alternative can only produce manual review, never live auto-render, and beamed-template overcount cases fall back to the existing visual safety bridge instead of blocking proven beamed reads.
- V4 raster normalization now rejects tiny isolated noise marks before crop grouping, so specks and accidental taps do not create unsupported crops or block a clear exact phrase. Non-tiny unsupported marks still stay local with crop-level unread evidence.
- V4 render comparison now has explicit reject and accept coverage: exact meter values with bad visual spacing cannot auto-commit, while aligned exact-fit phrases can pass the render-alignment gate.
- V4 visual note anchors now support the first Lead Sheet pitched-note baseline. After the rhythm decision accepts a Lead Sheet phrase, the same deterministic crops provide notehead anchor positions for staff-step snapping on note-capable slots; stem-down staff notes are protected from being treated as single eighths just because their noteheads live above the stem.
- Mixed note/rest Lead Sheet commits now use V4 anchors only for note-capable slots, so rests can remain rendered rest glyphs while notes become clamped in-staff pitched-note events.
- Beamed-eighth V4 crops can provide separate Lead Sheet pitch anchors for each accepted eighth value, preserving per-note staff positions even when one crop owns the beamed group.
- Lead Sheet finalization stays fail-closed unless visual note anchors cover every note-capable slot exactly once; partial, duplicate, or rest-slot pitch assignments do not commit.
- The behavior-preserving V4 extraction keeps the raster/template core in `SmartChart/Features/Editor/Components/RhythmicNotationRasterTemplateRecognizer.swift` while the quantizer owns the public API and existing bridge decisions.
- Shared rhythm recognition contracts now live in `SmartChart/Features/Editor/Components/RhythmicNotationRecognitionTypes.swift`, keeping proposal safety, phrase hypotheses, primitives, decisions, reasons, candidates, and candidate paths inspectable without reopening the quantizer body.

This is still deterministic, local, and writer-agnostic. It does not add ML, OCR, personal handwriting fixtures, global retraining, or a default diagnostic stream.

Latest copied simulator trace:

- Measure 1: `v3.decision=commit`, `v3.source=visual`, `v3.natural=["dottedHalf", "eighth", "eighth"]`.
- Measure 2 fallback path: `v3.decision=keepWriting`, `v3.reason=nonVisualFallback`, and no live/selection proposal is handed back when exact fit depends on the legacy non-visual fitter.
- Stable-snapshot live pass: measure 1 committed `slash, slash, slash, slash`; measure 2 committed `quarter, quarter, quarter, eighth, eighth`; follow-up underfilled and ambiguous phrases stayed local.
- Latest saved-state check after the user's non-rendered quarter-note pass showed the selected Rhythm Section chart still preserved the raw rhythm ink on measure 2 with no rhythm map committed. The unread-ink feedback slice keeps that fail-closed behavior and adds a local red overlay only when the stable decision is completed-looking and can identify the specific unread symbol or primitive.
- Latest V4 live-pass diagnosis showed two remaining false exact-fit risks: a stemmed notehead crop could be treated as a slash, and quarter-like symbols after a beamed pair could be stretched into dotted-quarter/eighth alternatives. The semantic visual gate now blocks those paths from confident auto-render unless the ink supplies the needed slash, dot, flag, or beam evidence.

Latest verification:

- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `51` tests, and `0` failures after the V3 visual-rest slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `62` tests, and `0` failures.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `63` tests, and `0` failures after the V3 phrase-ambiguity slice.
- XcodeBuildMCP focused `test_sim` passed with `4` tests and `0` failures after adding rhythm-entry measure resolution and V3 slash-decision regressions.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `110` tests, and `0` failures after the rhythm-entry measure selection repair.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the rhythm-entry measure selection repair.
- XcodeBuildMCP `test_sim` for `LeadSheetInteractionModeStatePolicyTests` passed with `12` tests and `0` failures after the stable rhythm auto-apply snapshot repair.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `111` tests, and `0` failures after adding stable rhythm auto-apply snapshots.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the stable rhythm auto-apply snapshot repair; `git diff --check` passed.
- After temporary trace cleanup, XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` still passed with `111` tests and `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` still passed with `354` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `112` tests and `0` failures after the V3 uncovered-ink slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V3 uncovered-ink slice; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` and screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for close competing exact phrases and whole-measure manual review passed with `2` tests and `0` failures after adding the V3 competing-exact-phrase reason.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `114` tests and `0` failures after the V3 competing-exact-phrase slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V3 competing-exact-phrase slice; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` and screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for non-visual fallback exact-fit handling passed with `1` test and `0` failures after confirming the live V3 path returns `keepWriting(.nonVisualFallback)` with no proposal.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `115` tests and `0` failures after the non-visual-fallback slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the non-visual-fallback slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the non-visual-fallback slice with the existing headermap warning only; screenshot capture succeeded.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `352` tests, `36` skipped, and `0` failures after the V3 phrase-ambiguity slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V3 phrase-ambiguity slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP focused `test_sim` for unread rhythm ink feedback policy and frame geometry passed with `2` tests and `0` failures after the unread-ink-feedback slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `117` tests and `0` failures after the unread-ink-feedback slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the unread-ink-feedback slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the unread-ink-feedback slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP focused `test_sim` for unread rhythm ink feedback policy, full-frame fallback, and targeted uncovered-stroke frame geometry passed with `3` tests and `0` failures after the targeted-unread-stroke-feedback slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `118` tests and `0` failures after the targeted-unread-stroke-feedback slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the targeted-unread-stroke-feedback slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the targeted-unread-stroke-feedback slice with the existing headermap warning only; screenshot proof showed the app launched to the Projects library.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` and `LeadSheetInteractionModeStatePolicyTests` passed with `80` tests and `0` failures after the V4 raster/template gate and crop-level unread feedback slice.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `125` tests and `0` failures after the V4 raster/template gate.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 raster/template gate.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V4 raster/template gate with the existing headermap warning only; screenshot proof showed the app launched to Projects.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `67` tests and `0` failures after the V4 semantic visual gate.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `128` tests and `0` failures after the V4 semantic visual gate.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 semantic visual gate; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V4 semantic visual gate with the existing headermap warning only.
- XcodeBuildMCP `test_sim` for `LeadSheetInteractionModeStatePolicyTests` passed with `17` tests and `0` failures after tightening unread feedback to completed-looking, localized targets only.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `129` tests and `0` failures after the unread-feedback targeting rule.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the unread-feedback targeting rule; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the unread-feedback targeting rule with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests/testV4DecisionCoversRestPhrasesThroughRasterTemplateGate` passed with `1` test and `0` failures after the rest-crop ownership repair.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `69` tests and `0` failures after broadening V4 rest, dotted, and long-value phrase coverage.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `131` tests and `0` failures after the V4 rest-crop ownership slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 rest-crop ownership slice; `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded after the V4 rest-crop ownership slice with the existing headermap warning only; screenshot capture succeeded.
- XcodeBuildMCP focused `test_sim` for V4 underfill, overflow, unsupported-crop, and unflagged-eighth review gates passed with `5` tests and `0` failures after the V4 non-exact ownership slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `72` tests and `0` failures after the V4 non-exact ownership slice.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, and `ChartEditingTests` passed with `134` tests and `0` failures after the V4 non-exact ownership slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `354` tests, `36` skipped, and `0` failures after the V4 non-exact ownership slice.
- `git diff --check` passed after the V4 non-exact ownership slice, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for V4 noise rejection, unsupported-crop, and clear-quarter phrase coverage passed with `3` tests and `0` failures after the raster-normalization noise slice.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `73` tests and `0` failures after the V4 raster-normalization noise slice.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `176` tests and `0` failures after the V4 render-comparison acceptance test and Lead Sheet key-signature baseline.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `356` tests, `36` skipped, and `0` failures after the V4 render-comparison and Lead Sheet key-signature baseline.
- `git diff --check` passed, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only after the V4 normalization and Lead Sheet key-signature baseline.
- XcodeBuildMCP focused `test_sim` for Lead Sheet pitched-note finalization passed with `2` tests and `0` failures, and XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `76` tests and `0` failures after adding V4 visual note anchors and stem-down quarter protection.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `182` tests and `0` failures after the Lead Sheet pitched-note baseline.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `360` tests, `36` skipped, and `0` failures after the Lead Sheet pitched-note baseline; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for mixed Lead Sheet note/rest finalization passed with `1` test and `0` failures; XcodeBuildMCP focused `test_sim` for beamed-eighth pitch-anchor finalization passed with `1` test and `0` failures; XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after mixed note/rest and beamed-eighth pitch-anchor finalization.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `186` tests and `0` failures after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures after tightening Lead Sheet pitch coverage to require every note-capable rhythm slot.
- `git diff --check` passed after the mixed Lead Sheet note/rest plus beamed-eighth pitch-anchor slice and after the pitch-coverage guard doc audit, and XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after extracting the V4 raster/template core into `RhythmicNotationRasterTemplateRecognizer.swift`.
- XcodeBuildMCP grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures after the V4 core extraction.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the V4 core extraction; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.
- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after extracting shared rhythm recognition types and candidate/path structs into `RhythmicNotationRecognitionTypes.swift`.
- XcodeBuildMCP grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures after the shared-type/candidate extraction.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the shared-type/candidate extraction; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only.

## Guardrails

- Do not tune from one writer's handwriting as training.
- Do not add personal raw ink to committed fixtures.
- Do not expand OCR.
- Do not retune chord recognition.
- Do not let diagnostics become a runtime default cost.
- Keep the existing `MeasureRhythmMap`, resolved slots, and chord snapping as the structured chart authority after a rhythm phrase commits.
