# Rhythm Section Chord Systems Plan - 2026-08-27

## Current Authority

This document is the source of truth for the Rhythm Section chord systems integration step. It supersedes older Rhythm Section chord-lane notes only for this branch's integration contract. It does not supersede product/account policy, release policy, or the chord-recognition trust protocol.

The official branch is `codex/rhythm-section-chord-systems` in `/Users/benirossman/Documents/Smart Chart`. It is branched from local `3946405` (`Lock live ink input to Apple Pencil`), so it includes the Pencil-only live ink input policy in addition to the chord recognition trust work merged to `main` through `78146db` (`Improve chord recognition trust pipeline (#61)`).

The current chord recognition authority remains:

- `docs/chord-recognition-accuracy-branch-plan-2026-08-25.md`
- `docs/chord-recognition-trust-protocol-2026-08-25.md`

This document only defines the Rhythm Section integration contract. It does not reopen OCR, Scribble lane recognition, `PKStrokeRecognizer`, or implicit chart mutation.

## Cross-Referenced Policy Map

- `docs/chord-lane-auto-render-course-correction-2026-08-21.md` controls the chord lane workflow: ink stays draft-only, draft chords and draft barlines render together, and `Render Chords` is the commit boundary.
- `docs/chord-recognition-trust-protocol-2026-08-25.md` controls recognizer trust: no OCR, no `PKStrokeRecognizer`, no lane Scribble, no confident wrong reads, and physical iPad evidence is required for handwriting claims.
- `docs/ink-canvas-layer-state-flow-audit-2026-08-24.md` controls live ink risk: the active `PKCanvasView` owns visible ink while editing, persistence stays bounded to idle/tool-exit/render paths, and any Pencil-feel claim needs physical iPad validation.
- `docs/ichart-rhythm-section-chart-plan-2026-05-27.md` controls Rhythm Section product shape: staff-line measures, rhythm inside the measure lane, chords above staff, rhythm-slot chord snapping when rhythm exists, beat-grid fallback when it does not, and below-staff free-hand articulation only.
- `docs/ichart-rhythm-section-v4-closeout-audit-2026-05-29.md` controls Rhythm Recognition boundaries: V4 is deterministic, fail-closed, and unrelated to this chord-lane integration unless an explicit rhythm-recognition bug is separately scoped.
- `docs/measure-resize-hitbox-performance-plan-2026-08-24.md` controls rendered resize/edit risk: do not change resize transactions, hit-target arbitration, or layout-guide behavior for this branch.
- `docs/future-blockers-before-major-push-2026-08-25.md` keeps cloud sync, editor extraction, validation gaps, warning cleanup, and optional chord-lane product additions parked unless directly blocking this integration.
- `docs/ichart-plan-policy-source-of-truth.md` remains the authority for account, Basic/Pro, cloud, Forums, subscription, and privacy policy. This branch must not change entitlement or cloud behavior.

## Observed Facts

- Rhythm Section charts already include chord entry in their layout profile while preserving rhythm/staff context.
- Rhythm Section layout already renders a thin chord band above staff/measures.
- The active chord ink scope already covers an expanded writing lane around that thin band, so Apple Pencil input can be forgiving without visually thickening the lane.
- The deterministic chord recognizer, sequential grouping, trust policy, preview state, trace diagnostics, and explicit `Render Chords` flow are layout-agnostic.
- Draft barline preview existed globally, but barline render was structurally simple-chart-only because it used `splitSimpleChordMeasure`.

## Product Contract

Rhythm Section chord mode should feel like the Simple Chord Sheet chord lane for input:

- users write chords and barlines in one horizontal chord lane;
- the visible Rhythm Section chord lane remains thin;
- the staff, rhythm hits, slashes, cue text, roadmap objects, and measure barlines continue to render below that lane;
- draft previews remain draft-only until explicit `Render Chords`;
- rendered chords and barlines commit together when all renderable draft chords have supported reads.

The visual result remains Rhythm Section, not Simple Chord Sheet:

- the chord band stays thin above the staff;
- the writeable chord ink frame may be taller than the visible band for Pencil usability;
- committed measures, barlines, staff lines, rhythm hits/slashes, cue text, roadmap marks, and articulations render below the chord band using Rhythm Section layout rules;
- existing rhythm-slot snapping remains the placement authority when a rhythm map exists;
- beat-grid fallback remains the placement authority when no rhythm map exists.

## Guardrails

- Do not thicken the visible Rhythm Section chord band.
- Do not use Simple Chord Sheet continuation rows for Rhythm Section charts.
- Do not split committed Rhythm Section measures in this slice.
- Do not redistribute existing rhythm maps, cue text, roadmap objects, or handwritten rhythmic notation.
- Do not change chord lane UI, edit mode architecture, sync, export, measure resize, terminal barline behavior, or page ink behavior except where a direct rhythm chord-lane validation blocker is found.
- Keep OCR, lane-level Scribble recognition, and `PKStrokeRecognizer` out of the recognition path.
- Do not tune chord recognition, rhythm recognition, parser coverage, compendium rules, correction memory, or trust thresholds on this branch.
- Do not preserve leftover chord ink after successful render unless a future product sprint explicitly changes the current chord-entry lifecycle.

## Integration Matrix

Safe in this branch:

- deterministic chord recognition and root-led grouping for Rhythm Section chord-lane preview;
- shared draft preview state and explicit `Render Chords`;
- draft barline detection/removal before chord grouping;
- same-pass draft chord plus draft barline render for blank open Rhythm Section measures;
- live ink input policy and scheduling behavior already shared by the editor;
- existing rendered chord edit paths where they already work for Rhythm Section.

Unsafe in this branch:

- splitting committed/contentful Rhythm Section measures;
- redistributing rhythm maps, raw rhythm ink, cue text, roadmap objects, repeats/endings, section labels, or measure-attached freehand;
- adding new Rhythm Recognition V4 behavior;
- adding candidate picker/manual correction UI/confidence overlays;
- changing cloud sync, StoreKit, export, terminal/coda, measure resize, or broad editor architecture.

## Implementation Sequence

1. Keep the current branch and do not create a replacement branch unless this one becomes unrecoverable.
2. Prove the current recognition/trust pipeline is present on the Rhythm Section branch.
3. Add tests that Rhythm Section chord targeting uses the same root-led/draft-barline route as Simple Chord Sheet targeting while retaining the thin chord band.
4. Add render tests that trusted draft chords commit into Rhythm Section measures only after explicit render.
5. Add a Rhythm Section draft-barline commit path for blank open measures only. A rendered barline may split the current open Rhythm Section authoring measure and keep the right segment open.
6. Preserve drawn lane segmentation for draft chord placement when chords and barlines render together.
7. Keep committed-measure splitting parked until there is a separate rhythm-map redistribution design.

## Implementation Status

- Branch authority is established on `codex/rhythm-section-chord-systems`.
- The first implementation slice adds a blank-open-measure Rhythm Section split helper, layout-style-aware draft barline commit routing, Rhythm Section segment-width preservation, and draft-segment chord placement priority.
- The first test slice covers open-measure splitting, committed/contentful split refusal, thin-band versus writable-frame geometry, same-pass `C | F | G` render, committed-measure no-op behavior, and draft-barline route targeting.
- No recognizer tuning, OCR/Scribble/`PKStrokeRecognizer`, lane UI redesign, edit architecture rewrite, cloud sync, export, terminal, resize, or rhythm-recognition change is part of this slice.

## Verification Checklist

- [x] `xcodegen generate` completed after source/test changes.
- [x] `git diff --check` passed.
- [x] Forbidden recognition-provider grep passed: `rg -n "OCR|VNRecognize|PKStrokeRecognizer|Scribble" iChart iChartTests docs/chord-recognition-trust-protocol-2026-08-25.md docs/rhythm-section-chord-systems-plan-2026-08-27.md` found no live OCR, Vision, or `PKStrokeRecognizer` provider; Scribble hits are manual text/account surfaces, tests, or docs.
- [x] Focused SwiftPM model/recognition gate: `swift test --scratch-path /tmp/iChartSwiftBuild-rhythm-chord-model-recognition-final --filter 'ChartEditingTests/testSplitOpenRhythmSectionMeasure|ChordInkRecognizerTests|ChordInkSequentialGrouperTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'` executed 78 tests, skipped 1 opt-in full-archive fixture, and failed 0.
- [x] Full SwiftPM gate: `swift test --scratch-path /tmp/iChartSwiftBuild-rhythm-chord-full-final` executed 775 tests, skipped 41 opt-in tests, and failed 0.
- [x] Opt-in full chord ink fixture gate: `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-rhythm-chord-full-fixtures-final --filter 'ChordInkRecognizerTests|StrokeClustererTests'` executed 65 tests and failed 0.
- [x] Simulator Rhythm Section chord-system gate: `xcodebuild -project iChart.xcodeproj ... -only-testing` selected 6 Rhythm Section chord targeting/render/model tests in `/tmp/iChartRhythmChordSystemsFinal-20260826-211715.xcresult`; `xcresulttool` reported 6 passed, 0 failed, 0 skipped.
- [x] Simulator live-ink/input-policy gate: `xcodebuild -project iChart.xcodeproj ... -only-testing` selected 6 live-ink/editor policy tests in `/tmp/iChartRhythmLiveInkPolicyFinal-20260826-211748.xcresult`; `xcresulttool` reported 6 passed, 0 failed, 0 skipped.
- [x] Physical iPad build gate: `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' build` succeeded for `Ben's iPad` in `/tmp/iChartRhythmChordSystemsDeviceBuildFinal-20260826-211804.xcresult`.
- [ ] Physical iPad pass before any final claim: Rhythm Section chart, thin chord lane, `C | F | G`, `D/F#`, `Db`, `D-7`, barline-plus-chord sequence, render, close/reopen.

## Branch And Commit Protocol

- Commit only from `/Users/benirossman/Documents/Smart Chart` on `codex/rhythm-section-chord-systems`.
- Keep the branch based on the current post-recognition, post-live-ink implementation stack. Do not branch from the detached delegated worktree.
- Before each commit, record the changed files, rerun the smallest relevant focused gate, and run `git diff --check`.
- Before pushing or opening a PR, rerun the full verification checklist above and confirm `xcresulttool` shows nonzero selected simulator tests with zero failures.
- If physical iPad behavior contradicts local gates, classify the failure before coding: recognition/glyph, grouping/targeting, preview replacement, render commit, live ink persistence, or Rhythm Section layout.
- If a fix requires committed-measure redistribution, rhythm-recognition tuning, editor extraction, sync, export, resize, or terminal/coda behavior, stop and open a separate plan/branch instead of widening this one.

## Physical iPad Acceptance Log

Record the first device pass here before final product acceptance:

| Case | Expected | Observed | Classification |
| --- | --- | --- | --- |
| Thin chord lane | visible band remains thin; writing area is forgiving | pending | pending |
| `C | F | G` | previews and renders as three Rhythm Section measures below lane | pending | pending |
| `D/F#` | previews/renders correctly or confirms instead of wrong trusted read | pending | pending |
| `Db` | previews/renders correctly or confirms/no-reads rather than wrong trusted read | pending | pending |
| `D-7` | previews/renders correctly or confirms/no-reads rather than wrong trusted read | pending | pending |
| barline-plus-chord sequence | draft barlines and chords render together only after `Render Chords` | pending | pending |
| rendered edit | rendered Rhythm Section chords remain editable through existing Chord/Edit behavior | pending | pending |
| close/reopen | committed chords/measures persist; draft ink does not reappear | pending | pending |

## Current Risk

The first implementation deliberately supports open-measure Rhythm Section barlines only. If a user draws a barline inside an already committed Rhythm Section measure, this branch should not split it. That behavior needs a separate design because committed rhythm measures can contain rhythm maps, cue text, roadmap anchors, and handwritten rhythmic notation.
