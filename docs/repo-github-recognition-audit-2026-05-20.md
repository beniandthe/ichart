# Smart Chart Repo, GitHub, and Recognition Pipeline Audit

Status: audit report
Date: 2026-05-20 18:51 PDT
Repo: `beniandthe/smart-chart`
Local branch: `codex/symbol-ledger-recognition`
Local commit: `9479a94 Checkpoint symbol ledger diagnostics`

## Executive Summary

The repo is not dirty and the latest recognition branch is green, but the architecture has become too heavy for the current product loop.

The cleanest live chord pipeline should be:

```text
PKCanvasView native ink
-> PencilKitInkAdapter
-> ChordInkRecognizer facade
   -> StrokeClusterer
   -> GestureTemplateRecognizer
   -> ChordInkCandidateComposer
-> ChordRecognitionCompendium / ChordSymbolParser
-> ChordInkRecognitionPolicy + optional trust sidecar
-> Editor commits a structured ChordEvent
```

Everything else should either be diagnostics-only, test-only, or removed from the default path.

The biggest audit findings:

1. `docs/handwriting-recognition-implementation-plan.md` has stopped being a tight implementation plan. It now mixes the original source-of-truth architecture, checkpoint evidence, pass history, fixture coverage, and backlog notes.
2. `ChordInkRecognizer` is no longer just a facade. It orchestrates the normal pipeline, injects semantic candidate fixes, creates ledger diagnostics, performs match filtering, and reports timing.
3. `StrokeClusterer.swift` and `ChordInkCandidateComposer.swift` have become the two main bloat/performance risk files. They contain real value, but also many family-specific repairs that should be inventoried as explicit passes.
4. `ChordInkSymbolLedger` is correctly documented as diagnostics-only, but it currently runs inside every recognition call and recomposes prefix candidates. That is not dead code, but it is extra runtime work on the live path.
5. OCR is still compendium-gated and only requested for ambiguous primary reads, which is the right boundary. It should remain optional and should not become a second live authority.
6. GitHub is structurally clean but branch management is not: `main` is protected and stale, the active recognition branch is 18 commits ahead, and there is no PR for it.

## GitHub State

Remote:

- URL: `https://github.com/beniandthe/smart-chart`
- Default branch: `main`
- Default branch SHA: `01cd774 Add handwriting recognition implementation plan`
- Visibility: public
- Issues: none returned by `gh issue list`
- Open PRs: one Dependabot PR, `#3`, `Bump actions/dependency-review-action from 4 to 5 in the github-actions group`
- Recognition PRs: none for `codex/symbol-ledger-recognition` or `codex/recognition-v1-consolidation`

Remote branches:

| Branch | SHA | Relative to `origin/main` |
| --- | --- | --- |
| `main` | `01cd774` | baseline |
| `codex/chord-recognition-hard-reset` | `1e36e97` | 3 commits ahead |
| `codex/other-chord-recognition` | `393c3bc` | 4 commits ahead |
| `codex/recognition-v1-consolidation` | `35238f8` | 6 commits ahead |
| `codex/symbol-ledger-recognition` | `9479a94` | 18 commits ahead |
| `dependabot/github_actions/github-actions-89cfe148ea` | `ddf35ee` | 1 commit ahead |

Local-only branch drift:

- `codex/recognition-v1-consolidation` is locally at `0233e6e`, which is 3 commits ahead of `origin/codex/recognition-v1-consolidation`.
- `codex/pipeline-1-chord-trust` is local only at `c60bb46`.
- `codex/trust-cleanup-test-data` and `codex/v3-confidence-builder` both point at old commit `491a672`.

GitHub Actions:

- Workflows: `CI`, `CodeQL`, `Dependency Review`, `Dependabot Updates`
- Latest current-branch CI: success for `9479a94` on `codex/symbol-ledger-recognition`
- Latest old recognition-v1 CI: failure for `35238f8` on `codex/recognition-v1-consolidation`
- CodeQL runs on `main`, PRs to `main`, schedule, and manual dispatch. It does not run on `codex/**` push unless a PR exists.

## Repo Inventory

Top-level tracked/active areas:

| Area | Files or size | Notes |
| --- | ---: | --- |
| `SmartChart/Recognition` | 11 Swift files, 9703 lines | Main recognition weight |
| `SmartChart/Features/Editor` | 12 Swift files across editor/components, 7594 lines | Live UI integration, PencilKit, diagnostics hooks |
| `SmartChart/Services` | 8 Swift files, 3241 lines | Parser, compendium, diagnostics, layout/export support |
| `SmartChart/Models` | 13 Swift files, 3539 lines | Structured chart domain |
| `SmartChartTests/Fixtures/Ink` | 645 JSON fixtures, 6.7 MB, 267828 lines | Valuable corpus, heavy repo/test surface |
| `ThirdParty/NotationFonts` | 3.4 MB | Expected SMuFL metadata/fonts |
| `.build` | 754 MB local ignored build output | Not tracked |
| `build/DerivedData` | local ignored build output | Not tracked |

Generated/local files:

- `SmartChart.xcodeproj/` exists locally and is ignored by `.gitignore`.
- `project.yml` is the source of truth for XcodeGen.
- No untracked files are present.
- No tracked `DerivedData`, `.xcodebuildmcp`, replay JSON, `.DS_Store`, or live diagnostic JSONL artifacts were found.

## Target Boundaries

SwiftPM target:

- `Package.swift` builds a library target.
- It intentionally excludes `SmartChart/App`, `SmartChart/Features/Editor`, `SmartChart/Features/Library/LibraryView.swift`, `Resources`, and one SwiftUI shared file.
- SwiftPM tests are excellent for pure domain/recognition behavior but do not compile the live editor UI.

Xcode/iOS target:

- `project.yml` includes the whole `SmartChart` app and resources.
- GitHub CI regenerates the project with `xcodegen generate`.
- iOS simulator CI is the main protection for app/editor compile coverage.

Audit implication:

- `swift test` passing is necessary but not sufficient for live chord-entry safety.
- For any cleanup touching `EditorView.swift`, `LeadSheetCanvasHostView.swift`, PencilKit, OCR, or SwiftUI sheets, run Xcode/iOS simulator tests too.

## Recognition System Map

### 1. Symbolic Authority

Primary files:

- `SmartChart/Services/ChartParsers.swift`
- `SmartChart/Services/ChordRecognitionCompendium.swift`
- `SmartChart/Models/ChordEvent.swift`
- `SmartChart/Models/MusicTheory.swift`

Current role:

- Final validation and normalization of chord tokens.
- Rejects unsupported aliases such as major suffix text that the app does not support.
- Provides user-facing candidate filtering.

Audit status: keep as final authority.

Cleanup note:

- `BasicMajorChordCompendium` is now a compatibility wrapper around `ChordRecognitionCompendium`; it is legacy naming and should eventually be removed from app/tests.

### 2. Ink Model and PencilKit Adapter

Primary files:

- `SmartChart/Recognition/InkTypes.swift`
- `SmartChart/Recognition/PencilKitInkAdapter.swift`
- `SmartChart/Models/Chart.swift`
- `SmartChart/Models/ChartEditing.swift`

Current role:

- Pure Swift `InkPoint`, `InkStroke`, `InkCluster`, bounds, metrics, OCR candidate, recognition result, and policy structs.
- Converts `PKDrawing` into recognition-native strokes.
- Stores chord ink separately in `Chart.pageHandwrittenChordData`.

Audit status: keep.

Cleanup note:

- `InkTypes.swift` is becoming a mixed bag of raw ink data, policy, metrics, OCR models, fixture models, and decisions. It should probably split into smaller files once the pipeline stabilizes.

### 3. Stroke Clustering

Primary file:

- `SmartChart/Recognition/StrokeClusterer.swift` at 2972 lines.

Current role:

- Groups strokes, splits accidental/suffix fragments, repairs root/sharp/minor/sus/slash/altered-family cases, and returns ordered glyph clusters.

Audit status: keep, but this is the largest bloat/performance risk.

Concern:

- The file has many family-specific repair passes chained in `cluster(_:)`, including sharp construction, adjacent `1`/`13`, minor seventh suffix, dominant alterations, suspended suffixes, and slash-bass splitting.
- Those passes are valuable because they came from real failures, but they are hard to reason about as one 3k-line unit.

Recommended cleanup:

- Split into named deterministic passes:
  - base temporal/spatial grouping
  - root construction repair
  - accidental repair
  - suffix digit splitting
  - altered-dominant repair
  - suspended repair
  - slash-bass repair
- Keep the output contract unchanged while extracting files.

### 4. Glyph Recognition

Primary files:

- `SmartChart/Recognition/GestureTemplateRecognizer.swift` at 1730 lines.
- `SmartChart/Recognition/ChordGlyphTemplateLibrary.swift`

Current role:

- Point-cloud/template recognition plus heuristic candidates.
- Returns ranked `GlyphCandidate` arrays.

Audit status: keep, but watch heuristic growth.

Concern:

- The recognizer has template matching and glyph-shape gates in the same file.
- This is still aligned with the plan, but future additions should be data/fixture-driven rather than more embedded glyph branches.

### 5. Candidate Composition

Primary file:

- `SmartChart/Recognition/ChordInkCandidateComposer.swift` at 1618 lines.

Current role:

- Generates chord string candidates from glyph columns.
- Uses max 3 alternatives per cluster, max 4096 generated sequences, max 32 returned candidates.
- Applies many scoring knobs for slash, suspended, altered, triangle, sixth, flat/root collisions, and unexplained clusters.

Audit status: keep, but reduce scoring sprawl.

Concern:

- The scoring struct is now a compact map of historical fixes.
- Candidate generation is controlled by caps, but still can be expensive and opaque when the ledger recomposes prefixes too.

Recommended cleanup:

- Preserve the composer as the only place that turns glyph columns into candidate strings.
- Move semantic candidate injection out of `ChordInkRecognizer` and into explicit composer rules or small composer sub-resolvers.

### 6. Recognition Facade

Primary file:

- `SmartChart/Recognition/ChordInkRecognizer.swift` at 1995 lines.

Current role:

- Runs clusterer, glyph recognizer, contextual glyph adjustments, composer, semantic candidate injections, compendium matching, ledger snapshot, and metrics.

Audit status: too much responsibility.

Concern:

- The facade is doing more than orchestration.
- It injects semantic candidates such as diminished, altered extension, sharp-eleven, minor-eleventh, sixth, and suspended candidates after composer output.
- That creates a second candidate-composition authority beside `ChordInkCandidateComposer`.

Recommended cleanup:

- Make `ChordInkRecognizer` a thin orchestrator again.
- Route all candidate construction through `ChordInkCandidateComposer`.
- Keep metrics in the facade, but keep music semantics out of the facade.

### 7. Trust Policy

Primary files:

- `SmartChart/Recognition/InkTypes.swift`
- `SmartChart/Recognition/ChordRecognitionTrustArbiter.swift`

Current role:

- `ChordInkRecognitionPolicy` auto-renders above confidence `3.95`.
- Close-race gap is `0.04`.
- OCR can resolve primary/OCR agreement if primary was otherwise confirm-worthy and confidence is close enough.

Audit status: keep, but centralize.

Concern:

- Trust logic is split between primary policy and OCR arbiter.
- That split is acceptable only if the arbiter stays a sidecar and never bypasses compendium validation.

Recommended cleanup:

- Keep one final `ChordInkRecognitionDecision`.
- Let OCR decorate or support that decision; do not let it become a separate final-recognition path.

### 8. OCR Sidecar

Primary files:

- `SmartChart/Recognition/ChordOCRCandidateProvider.swift`
- `SmartChart/Recognition/ChordRecognitionTrustArbiter.swift`
- `SmartChart/Features/Editor/Components/LeadSheetCanvasHostView.swift`

Current role:

- Uses Apple Vision text recognition when available.
- Runs only when the primary decision is confirmation or close-race.
- Normalizes through `ChordRecognitionCompendium`.

Audit status: acceptable, but optional.

Concern:

- OCR is runtime work on the recognition queue.
- It should stay off the primary path unless there is an explicit ambiguity.

Recommended cleanup:

- Put OCR behind a clearly named feature/policy switch.
- Keep raw OCR out of UI unless compendium-normalized.

### 9. Symbol Ledger

Primary files:

- `SmartChart/Recognition/ChordInkSymbolLedger.swift`
- `SmartChartTests/Recognition/ChordInkSymbolLedgerTests.swift`
- `SmartChart/Services/ChordEntryDiagnostics.swift`

Current role:

- Records stable left-to-right symbol evidence, running prefixes, final candidate support, and primary agreement.
- Tests assert it is diagnostics-only and does not take authority.

Audit status: useful, but should not run by default forever.

Concern:

- The ledger currently runs inside every `ChordInkRecognizer.recognize(strokes:)` call.
- It also calls `candidateComposer.compose(glyphCandidates:)` for each running prefix.
- That means a diagnostics-only layer is still on the live runtime path.

Recommended cleanup:

- Add a recognizer option such as `includeSymbolLedgerDiagnostics`.
- Default it to false outside debug/simulator or explicit pass-audit mode.
- Preserve the tests and diagnostics path for audits.

### 10. Live Editor Integration

Primary files:

- `SmartChart/Features/Editor/Components/LeadSheetCanvasHostView.swift`
- `SmartChart/Features/Editor/EditorView.swift`
- `SmartChart/Features/Editor/EditorCanvasMode.swift`

Current role:

- Native `PKCanvasView` is the writing surface.
- Chord mode uses a 1.2 second idle delay and a 1.2 second continuation grace delay.
- Recognition runs on `com.smartchart.chord-ink-recognition` queue.
- Accepted candidates append structured `ChordEvent` values and clear page chord ink.
- Debug/simulator diagnostics are recorded after chord acceptance/correction.

Audit status: keep native ink, but slim diagnostic hooks.

Concern:

- `EditorView` schedules chord diagnostic reconciliation on every chart change when rendered chords exist.
- This is debug/simulator-gated, but it is still editor complexity mixed into product UI.

Recommended cleanup:

- Move diagnostic reconciliation behind an explicit debug service facade.
- Keep normal chart editing unaware of how diagnostics are backfilled.

### 11. Diagnostics and Replay

Primary files:

- `SmartChart/Services/ChordEntryDiagnostics.swift`
- `SmartChart/Services/ChordEntryDiagnosticCoverage.swift`
- `scripts/audit_chord_entry_diagnostics.py`
- `SmartChartTests/Recognition/ChordEntryPassReplayTests.swift`

Current role:

- Records live recognition outcomes.
- Audits rendered chord events against diagnostic events.
- Can reconcile missing diagnostic rows from rendered chart state.
- Replay test is skipped unless `SMART_CHART_STATE` is set.

Audit status: keep as tooling, not as product path.

Concern:

- Reconcile rows prove coverage but should not be treated as recognition evidence.
- This warning exists in the plan and should stay explicit in any future audit docs.

### 12. Fixture Corpus

Primary area:

- `SmartChartTests/Fixtures/Ink`

Current facts:

- 645 JSON fixtures.
- 247 canonical names after stripping `CapturedNN`.
- 228 names have multiple samples.
- 19 names have a single sample.
- 6.7 MB on disk.
- 267828 fixture lines.

Audit status: valuable but heavy.

Concern:

- The corpus is a core regression asset, but keeping every captured sample in the main repo/test loop makes each pass heavier.
- `testRecognizesEveryInkFixtureThroughPureSwiftPipeline` took 14.819 seconds during this audit run.
- Full `ChordInkRecognizerTests` took 23.093 seconds.

Recommended cleanup:

- Keep a curated always-on fixture set for CI.
- Move extended corpus checks to a separate nightly/manual test mode if local loop speed becomes painful.
- Preserve all fixtures somewhere, but separate "critical CI fixtures" from "full corpus evidence".

## Retired or Absent Systems

These old paths are deleted relative to `main`:

- `.github/scripts/plot-chord-learning-shapes.py`
- `.github/scripts/summarize-chord-telemetry.py`
- `SmartChart/Features/Editor/ChordRecognitionProposal.swift`
- `SmartChart/Features/Editor/Components/ChordRecognitionConfirmationSheetView.swift`
- `SmartChart/Resources/ChordRecognition/chord-recognition-base-seed.jsonl`
- `SmartChart/Services/ChordRecognition.swift`
- `SmartChart/Services/ChordRecognitionIntent.swift`
- `SmartChart/Services/ChordRecognitionLearning.swift`
- `SmartChart/Services/ChordRecognitionTelemetry.swift`
- `SmartChartTests/ChordRecognitionTests.swift`
- `docs/chord-recognition-pipeline-v3.md`

These experimental names are not present in the current tracked tree:

- `ChordInkSymbolCache`
- raster close-race resolver files
- direct custom chord-ink capture layer files
- red diagnostic trail files

Audit conclusion:

- The earlier cache/raster/direct-input detours are not currently sitting in the branch as tracked code.
- The remaining bloat is mainly inside the current recognized path, not leftover orphan files.

## Documentation Drift

### `docs/handwriting-recognition-implementation-plan.md`

Problem:

- It starts as the architecture source of truth.
- It says `main` is the source of truth, but current work lives 18 commits ahead on `codex/symbol-ledger-recognition`.
- It contains a large fixture/pass chronology and current checkpoint notes.
- It now has both original milestones and post-implementation evidence in one file.

Recommendation:

- Replace it with a short living architecture contract:
  - pipeline diagram
  - authority boundaries
  - live path
  - diagnostic-only path
  - current accepted scope
  - explicit deferred scope
- Move fixture/pass history to `docs/recognition-pass-log.md` or `docs/archive/`.

### `docs/current-architecture-audit.md`

Problem:

- It says chord interpretation remains outside the current live path.
- The current branch now has live chord-entry recognition and rendering.

Recommendation:

- Mark stale or replace with this audit after cleanup decisions are made.

### `docs/architecture-reset-proposal.md`

Problem:

- Still useful conceptually, but marked proposal-only and pre-recognition-branch.

Recommendation:

- Keep as historical context, not source of truth.

## Performance Risk Ranking

1. `StrokeClusterer`: many sequential repair passes and geometry checks on every recognition.
2. `ChordInkCandidateComposer`: sequence generation capped at 4096, plus many scoring branches.
3. `ChordInkSymbolLedger`: diagnostics-only but recomposes prefixes during every recognition.
4. OCR sidecar: Vision work is gated, but can still add latency on ambiguous reads.
5. Debug diagnostics: simulator/debug reconciliation on chart changes adds editor complexity.

## Recommended Streamlining Plan

### Phase 1: Freeze the Authority Boundary

Define this rule in the plan and tests:

```text
Only ChordRecognitionCompendium / ChordSymbolParser can validate a final chord token.
Only ChordInkCandidateComposer can compose glyph columns into final candidate strings.
ChordInkRecognizer orchestrates; it does not invent semantic candidates.
OCR and symbol ledger are sidecars; they never bypass compendium validation.
```

### Phase 2: Make Diagnostics Optional on the Runtime Path

- Add a recognizer option to include/exclude symbol ledger diagnostics.
- Default it off outside debug/audit modes.
- Keep the diagnostic recorder and audit script.
- Confirm timing before/after with existing metrics.

### Phase 3: Split the Giant Recognition Files Without Behavior Changes

Extract from `StrokeClusterer.swift` first:

- `StrokeClustererBasePass`
- `RootStrokeRepairPass`
- `AccidentalStrokeRepairPass`
- `SuffixStrokeRepairPass`
- `SlashBassStrokeRepairPass`

Extract from `ChordInkCandidateComposer.swift` second:

- candidate generation
- text variants
- scoring policy
- family-specific candidate support

The goal is not to retune yet. It is to make the current behavior readable and measurable.

### Phase 4: Rewrite the Plan

Rewrite `docs/handwriting-recognition-implementation-plan.md` down to a tight source of truth and move history out.

Suggested sections:

- Current source-of-truth branch/commit
- Live chord pipeline
- Authority boundaries
- Diagnostics-only tools
- Supported v1 chord grammar
- Deferred systems
- Test matrix
- Cleanup backlog

### Phase 5: GitHub Cleanup

- Open a PR for `codex/symbol-ledger-recognition` or create a cleanup branch from it.
- Use that PR to run CodeQL on the recognition work.
- Decide whether `c60bb46` or `9479a94` is the cleanup base:
  - `c60bb46` if you want no ledger runtime cost.
  - `9479a94` if you want to keep ledger evidence but gate it.
- Close or delete old remote recognition branches after the clean pipeline lands.
- Merge or dismiss Dependabot PR `#3`.

## Verification Run

Commands run during this audit:

```bash
git fetch --all --tags
gh repo view beniandthe/smart-chart --json ...
gh pr list --repo beniandthe/smart-chart --state all --limit 80 --json ...
gh issue list --repo beniandthe/smart-chart --state all --limit 80 --json ...
gh run list --repo beniandthe/smart-chart --limit 30 --json ...
swift package describe --type json
swift test --scratch-path /tmp/SmartChartSwiftBuild-audit
python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py
git diff --check
```

Results:

- `swift test`: 309 tests, 1 skipped, 0 failures.
- Python script compile: passed.
- `git diff --check`: passed.
- Worktree before report: clean.
- Latest GitHub CI for `9479a94`: success.

## Bottom Line

The current repo is recoverable. The problem is not random orphan code; most old dead systems have already been removed. The problem is that the live recognizer absorbed too many jobs while responding to real failures.

The next cleanup should not start by deleting fixture evidence or retuning recognition. It should first restore the architecture boundary:

```text
cluster -> glyph -> compose -> compendium -> trust -> commit
```

Then diagnostics, OCR, and ledger evidence can stay useful without becoming hidden authorities or default runtime cost.
