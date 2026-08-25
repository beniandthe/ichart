# Chord Recognition Accuracy Branch Plan

Date: 2026-08-25
Branch: `codex/chord-recognition-accuracy`
Baseline: `d60d37bd837bf05867479cce315be91e4d1b4f70`
Scope: chord recognition grouping, glyph classification, candidate composition, trust policy, fixtures, and recognition diagnostics only.
Trust protocol: `docs/chord-recognition-trust-protocol-2026-08-25.md`

## Current Git State

Observed at branch start:

- `/Users/benirossman/Documents/Smart Chart` was clean on `main` at `d60d37bd837bf05867479cce315be91e4d1b4f70`.
- `origin/main`, local `main`, and `codex/chord-recognition-accuracy` all pointed at `d60d37bd837bf05867479cce315be91e4d1b4f70`.
- The working checkout was switched to `codex/chord-recognition-accuracy`.
- The task worktree at `/Users/benirossman/.codex/worktrees/d3b0/Smart Chart` was detached at the same commit; it is not the project checkout for this branch.

Branch naming note: the older course-correction docs mention `codex/chord-correction-accuracy`; this branch uses the delegated name `codex/chord-recognition-accuracy`.

## Required-Doc Summary

`docs/chord-recognition-accuracy-course-correction-2026-08-21.md` defines the recognition contract:

- Prefer accuracy, trust, and correctness over coverage.
- Target at least 90% correctness on supported vocabulary under realistic iPad writing.
- No-read is acceptable; confident wrong reads are not.
- Later ink must not retroactively rewrite an earlier preview group.
- OCR is not the production backbone and must not be used for render trust.
- Sequential grouping is the central product rule: a base root `A-G` starts a chord, suffix/accidental glyphs stay with that chord, and the next base root starts the next chord.

`docs/chord-lane-auto-render-course-correction-2026-08-21.md` defines the lane/render boundary:

- Ink remains draft-only until explicit `Render Chords`.
- Draft chords and draft barlines render together.
- Lane UI, rendered edit behavior, barline workflow, and measure/layout behavior are out of scope for this branch.
- Recognition fixes must not modify chord-lane architecture.

`docs/future-blockers-before-major-push-2026-08-25.md` records non-recognition work that stays parked:

- cloud sync push failure audit
- editor architecture extraction
- remaining editor validation gaps
- warning cleanup
- optional chord-lane product additions

Current supporting docs also reinforce this boundary:

- `docs/ink-canvas-layer-state-flow-audit-2026-08-24.md` says chord preview may inspect and persist draft chord ink, but must not commit rendered content or alter recognizer accuracy on that branch.
- `docs/measure-resize-hitbox-performance-plan-2026-08-24.md` explicitly excludes chord recognition accuracy, OCR, candidate scoring, and parsing rules from resize/hitbox work.
- `docs/unified-edit-tool-system-plan-2026-08-22.md` keeps draft chord ink and draft barlines owned by the Chord tool until explicit `Render Chords`.

## Current Recognizer Pipeline

Observed source flow:

1. Live chord ink is captured as `PKDrawing` in `LeadSheetCanvasHostView`.
2. Draft-preview flow filters invisible rendered artifacts with `ChordInkDraftVisibleStrokePolicy`.
3. Draft barlines are detected by `ChordDraftBarlineRecognizer` and removed before chord recognition.
4. `LeadSheetChordInkRecognitionTargeting.batchTargets` converts drawing strokes through `PencilKitInkAdapter`, chooses target measure/lane anchors, and splits batch targets.
5. Batch splitting currently falls back to `ChordInkBatchClusterer`, which is horizontal-gap based.
6. `ChordInkRecognitionSession` runs `ChordInkRecognizer` off the main thread and returns payloads on the main thread.
7. `ChordInkRecognizer` clusters strokes with `StrokeClusterer`, ranks glyphs with `GestureTemplateRecognizer`, contextualizes glyph candidates, composes chord candidates, matches against `ChordRecognitionCompendium`, and records metrics.
8. `ChordInkRecognitionPolicy` decides auto-render versus confirmation, but `ChordInkRecognitionFlow.canRenderChord` is currently false for both `draftPreview` and `tapToConfirm`.
9. `EditorView` commits draft chords and barlines only from `commitChordInkDraftBatch` after the user taps `Render Chords`.

Observed OCR state:

- `git grep` found no live `ChordOCR`, Vision, `VNRecognize`, or `ChordRecognitionTrustArbiter` references outside docs.
- Scribble remains present in manual text-entry/correction sheet code, not as the lane recognizer.

## Test And Fixture Audit

Current recognition test surface:

- `iChartTests/Recognition/ChordInkRecognizerTests.swift`
- `iChartTests/Recognition/GestureTemplateRecognizerTests.swift`
- `iChartTests/Recognition/ChordInkCandidateComposerTests.swift`
- `iChartTests/Recognition/StrokeClustererTests.swift`
- `iChartTests/Recognition/ChordInkSymbolLedgerTests.swift`
- `iChartTests/Recognition/InkFixtureCoverageTests.swift`
- `iChartTests/Recognition/ChordEntryPassReplayTests.swift`
- `iChartTests/Editor/ChordInkRecognitionSessionTests.swift`
- `iChartTests/Editor/ChordInkDraftPreviewTests.swift`

Fixture facts:

- `iChartTests/Fixtures/Ink` contains 645 JSON fixtures.
- 512 fixture files are captured samples and 133 are seed/template-style samples.
- Captured fixtures cover 199 distinct expected display texts.
- The default regression suite uses 18 fixture names through `InkFixtureLoader.defaultRegressionFixtureNames`.
- The full archive is opt-in through `ICHART_FULL_INK_FIXTURES=1`.

Current coverage strengths:

- base/root fixtures exist for `A-G`, including captured `D`, `E`, and `F` samples.
- fixture coverage protects common accidentals, minors, dominant extensions, altered dominants, slash bass, suspended forms, major-triangle forms, diminished/half-diminished, and chord repeat.
- recognition phase metrics already expose cluster, glyph, contextual, compose, semantic, match, total time, stroke count, cluster count, candidate count, and generated-sequence limit state.
- symbol-ledger diagnostics exist but are disabled by default.

Current gaps against the course-correction contract:

- Multi-chord same-lane grouping is still primarily gap-based, not root-led sequential grouping.
- There is no dedicated product contract test for `D-7 E-7` as two chords based on the second root.
- There is no dedicated product contract test for `Cmaj7 Dmin7 Emin9` proving earlier groups stay immutable when later roots appear.
- Existing batch tests prove separated groups and target ordering, but not semantic root-start grouping.
- The 90% target is not yet tied to a named measured fixture set, failure taxonomy, or iPad capture protocol.
- Device validation still needs a repeatable `chord-preview-diagnostics.jsonl` collection path for no-read, wrong-read, close-race, and trust-suppression cases.

## Assumptions To Validate

- Sequential grouping can be implemented below the UI layer by adding a recognition-aware grouping stage that operates on lane-local `InkStroke`/`InkCluster` data.
- The existing gap splitter can remain as fallback when root evidence is insufficient.
- The current fixture archive is enough to establish a regression baseline, but not enough to claim final product acceptance without fresh physical-iPad writing.
- Symbol-ledger diagnostics can help explain group stability and prefix support, but should remain diagnostic until a failing product case proves it should affect trust.

## Risks

- Overfitting: many existing tests encode complex suffix-specific patches. New changes must favor transferable visual/grammar rules.
- False authority: any OCR or Scribble-backed shortcut would violate the branch boundary.
- UI churn: changes in `EditorView`, rendered edit, chord lane geometry, measure resize, cloud sync, or ink persistence are out of scope unless they block recognition validation.
- Performance: complex suffix composition has previously hit the generated-sequence limit; every recognition change must watch timing metrics.
- Misleading proof: simulator and unit tests can establish deterministic behavior, but only physical iPad writing can validate real handwritten accuracy.

## Implementation Plan

### Step 1: Baseline Recognition Report

- Run a focused pure-Swift recognition suite for recognizer, clusterer, composer, glyph, ledger, loader, and fixture coverage tests.
- Run the full fixture archive with `ICHART_FULL_INK_FIXTURES=1`.
- Capture a local report with fixture count, pass/fail count, top failures, timing buckets, generated-sequence limit hits, and no-read versus wrong-read categories.
- Do not change recognizer behavior in this step.

### Step 2: Product Contract Tests For Sequential Grouping

- Add focused tests for same-lane sequences:
  - `D-7 E-7` groups into two chords.
  - `Cmaj7 Dmin7 Emin9` groups into three chords.
  - suffix-only fragments do not become independent chord events.
  - a solo vertical barline stroke is removed before chord recognition.
- Prefer tests around a pure grouping/targeting API before touching `LeadSheetCanvasHostView`.
- Use seed/template strokes first, then add one real captured fixture only if an iPad pass exposes a transferable regression.

### Step 3: Recognition-Aware Sequential Grouping

- Introduce a small grouping component that receives ordered lane-local strokes or glyph clusters.
- Detect probable base-root starts using `A-G` glyph evidence and root-body confidence.
- Keep accidentals, suffixes, slash-bass parts, and extensions with the active root until the next probable base root.
- Keep the current horizontal-gap splitter only as fallback for low-confidence/no-root cases.
- Return stable group boundaries and source stroke indices without changing lane UI or render commit behavior.

### Step 4: Root And Suffix Accuracy Pass

- Audit failures by family, not by isolated chord name:
  - `D` root body evidence
  - `E` versus `F` stroke/shape evidence
  - `7`, `9`, `11`, `13` as suffixes, not roots
  - `-`, `m`, `sus`, `7sus`
  - slash bass and altered dominant wrappers
- Add failing tests before each accuracy fix.
- Prefer no-read/confirmation over confident wrong reads when evidence is ambiguous.

### Step 5: Trust And Diagnostics Tightening

- Review `ChordInkRecognitionPolicy` only after grouping and glyph evidence tests are stable.
- Keep `ChordInkRecognitionFlow.canRenderChord == false` for draft preview.
- Add aggregate diagnostics only:
  - confidence bucket
  - candidate count
  - stroke/glyph count
  - route name
  - timing bucket
  - generated-sequence-limit flag
  - trust/no-read category
- Do not log raw chord text, drawing payloads, chart title, user names, email, or support data.

### Step 6: Simulator And Physical-iPad Validation

- Simulator/current build cases:
  - `C`
  - `D`
  - `E`
  - `F`
  - `C6`
  - `C7sus`
  - `Dmaj7`
  - `Bb-7`
  - same-lane multi-chord sequence
  - multi-system sequence
- Physical iPad cases before acceptance:
  - plain roots `A-G`
  - `D-7 E-7`
  - `Cmaj7 Dmin7 Emin9`
  - `C6`
  - `C7sus`
  - `Bb-7`
  - `G/B`
  - one ambiguous/no-read case
- Record observed preview text, whether previous previews changed, whether Render Chords produced matching rendered output, timing feel, and any diagnostic category.

### Step 7: Commit Policy

- Commit after each focused slice:
  - plan/report only
  - contract tests
  - grouping implementation
  - one accuracy family at a time
  - diagnostics only if needed
- Each commit must keep recognition changes separate from lane/render/edit/layout/cloud work.
- Before each commit, run `git diff --check` and the smallest relevant focused tests.
- Before final branch handoff, run the full fixture archive, relevant Xcode tests with `xcresulttool` proof of nonzero tests and zero failures, and physical-iPad validation notes.

## Stop Conditions

Stop and document the dependency if:

- a fix requires changing chord lane UI, rendered edit behavior, measure resize, terminal barline rendering, cloud sync, or ink persistence.
- OCR or Vision is needed to make the change pass.
- a test only passes by encoding one writer-specific glyph workaround.
- batch grouping still depends only on horizontal gaps for same-lane multi-chord writing.
- previous preview groups still change after a later base root is written.
- simulator/device environment failures are being mistaken for recognizer failures.
- physical iPad behavior contradicts unit or simulator assumptions.
