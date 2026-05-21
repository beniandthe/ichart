# Smart Chart Sprint Source Of Truth

Status: active living sprint document
Created: 2026-05-20
Repo: `beniandthe/smart-chart`
Active branch: `codex/symbol-ledger-recognition`
Active baseline commit: `9479a94 Checkpoint symbol ledger diagnostics`
Trusted checkpoint reference: `c60bb46 Polish altered chord recognition trust`

## Purpose

This document is the working source of truth for Smart Chart sprint recovery and forward planning.

Use it before starting recognition, editor, simulator, or architecture work. After each sprint completes, update this file in place: move the finished sprint into the completed log, record verification evidence, and define the next sprint only after discussing the next priority.

If this document conflicts with older recognition or architecture planning docs, this document wins for current sprint execution. `docs/core-design-document.md` still wins for product intent.

## Current Baseline

The active app state is the current branch head:

- branch: `codex/symbol-ledger-recognition`
- commit: `9479a94 Checkpoint symbol ledger diagnostics`
- supporting audit: `docs/repo-github-recognition-audit-2026-05-20.md`
- latest local verification: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed on 2026-05-20 with `309` tests, `1` skipped, `0` failures
- latest GitHub CI noted in the audit: success for `9479a94`

`c60bb46` remains the trusted checkpoint reference. It represents the last known-good altered-chord trust polish baseline before the symbol-ledger drift/recovery work. Do not treat `c60bb46` as the active implementation baseline unless a future sprint explicitly chooses a reset.

Known drift at this baseline:

- `ChordInkRecognizer` is doing too much orchestration plus semantic candidate injection.
- `ChordInkSymbolLedger` is diagnostics-only by policy and is now gated off by default on the live recognition path.
- `StrokeClusterer.swift` and `ChordInkCandidateComposer.swift` contain the largest behavior and performance risk because many pass-specific repairs now live in large files.
- The old handwriting plan mixes original design, historical pass notes, checkpoint evidence, and current backlog.
- `docs/current-architecture-audit.md` is stale because it says chord interpretation is outside the live path.
- No tracked cache/raster/direct-ink detour files remain in the current tree; remaining bloat is inside the current recognition path.

## Product North Star

The product workflow remains:

```text
open -> write -> recognize -> snap -> fix -> export
```

Product rules:

- Smart Chart is chord-first and rhythm-aware, not full notation software.
- Native Apple Pencil writing feel matters more than custom capture workarounds.
- Recognition proposes; structured chart objects decide.
- Correction speed matters more than perfect recognition.
- Raw ink should support reinterpretation, but the chart must not depend on raw ink alone.

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
- Fixture corpus pruning or tiering.
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
- Native `PKCanvasView` stays the writing renderer unless a future sprint explicitly proves a better native-feeling path.

## Active Sprint

### Sprint 1: Code Cleanup First

Status: complete, pending commit.

Goal:

Recover the streamlined recognition architecture while preserving current recognition behavior.

Starting point:

- branch: `codex/symbol-ledger-recognition`
- baseline: `9479a94`
- trusted checkpoint reference: `c60bb46`

Non-goals:

- Do not retune recognition scores.
- Do not add raster/classifier authority.
- Do not reintroduce custom direct-ink rendering.
- Do not prune the fixture corpus.
- Do not expand supported chord vocabulary.
- Do not change product UX unless a tiny wiring change is required to keep diagnostics optional.

Implementation tasks:

1. Gate symbol-ledger diagnostics. Done 2026-05-21.
   - Add an explicit recognition option for ledger diagnostics.
   - Default ledger diagnostics off for the live recognition path unless debug/audit mode asks for them.
   - Preserve ledger tests and diagnostic recording support.
   - Ensure debug/audit usage can still record ledger snapshots and assessments.

2. Restore `ChordInkRecognizer` as an orchestrator. Done 2026-05-21.
   - Inventory semantic candidate injection currently living in the recognizer.
   - Move candidate-construction responsibility toward composer-owned rules without behavior changes.
   - Keep recognizer responsibilities to pipeline execution, matching, metrics, optional sidecars, and result assembly.

3. Begin behavior-preserving file splits. Done 2026-05-21.
   - Split large recognition code only when the extracted names preserve existing behavior exactly.
   - Prioritize `StrokeClusterer` pass boundaries before scoring rewrites.
   - Keep each extracted pass deterministic and fixture-covered.

4. Keep OCR sidecar gated and compendium-first. Done 2026-05-21.
   - Preserve current ambiguity-only request behavior.
   - Keep invalid or partial OCR diagnostic-only.
   - Do not let OCR become a second final answer path.

5. Preserve native writing feel. Done 2026-05-21.
   - Keep `PKCanvasView` as the only chord ink renderer.
   - Do not restore the custom direct-capture visual trail or synthetic line renderer.

Progress notes:

- 2026-05-21: Task 1 completed. `ChordInkRecognitionOptions` now gates symbol-ledger snapshots and assessments. Plain `recognize(strokes:)` uses `.live` and returns no ledger payload; debug/audit callers can request `.includingSymbolLedgerDiagnostics`.
- 2026-05-21: The live canvas host keeps the ledger off by default. Simulator/debug audit runs can opt in with launch argument `-SmartChartSymbolLedgerDiagnostics` or environment variable `SMART_CHART_SYMBOL_LEDGER_DIAGNOSTICS=1`.
- 2026-05-21: Verification after Task 1: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `xcodegen generate` completed; iOS simulator `SmartChart` scheme tests passed with `350` passed, `1` skipped, `0` failed.
- 2026-05-21: Task 2 completed. Semantic candidate construction moved behind `ChordInkCandidateComposer.composeRecognitionCandidates(...)`, contextual glyph promotion moved behind `ChordInkCandidateComposer.contextualizedGlyphCandidateGroups(...)`, and the moved rule set was split into `SmartChart/Recognition/ChordInkSemanticCandidateComposer.swift`. `ChordInkRecognizer` now stays focused on pipeline execution, matching, metrics, optional sidecars, and result assembly. No score values or candidate ordering rules were intentionally changed.
- 2026-05-21: Verification after Task 2: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile` passed for the three diagnostic/import/watch scripts; `xcodegen generate` completed and included `ChordInkSemanticCandidateComposer.swift`; iOS simulator `SmartChart` scheme tests passed on simulator `93794540-AC0D-4A87-8C31-C96B95A4F7C9` with `350` passed, `1` skipped, `0` failed; `git diff --check` passed.
- 2026-05-21: Task 3 completed. `MutableInkCluster` plus shared `InkBounds`, `InkStroke`, and `InkPoint` recognition helpers were split into `SmartChart/Recognition/StrokeClustererSupport.swift`; duplicate local `InkBounds` helpers were removed from `GestureTemplateRecognizer.swift`. This was a file split only: no scoring, clustering thresholds, or candidate ordering values were intentionally changed.
- 2026-05-21: Tasks 4 and 5 reviewed during cleanup. OCR remains ambiguity-only and compendium-gated through the existing trust arbiter path, and chord handwriting remains on native `PKCanvasView` with no custom direct-ink renderer restored.
- 2026-05-21: Verification after Sprint 1 cleanup: focused suites passed for `StrokeClustererTests` (`7` tests), `GestureTemplateRecognizerTests` (`9` tests), and `ChordInkRecognizerTests` (`39` tests); `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile` passed for the three diagnostic/import/watch scripts; `xcodegen generate` completed and included both `ChordInkSemanticCandidateComposer.swift` and `StrokeClustererSupport.swift`; iOS simulator `SmartChart` scheme tests passed on simulator `93794540-AC0D-4A87-8C31-C96B95A4F7C9` with `350` passed, `1` skipped, `0` failed using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs` to strip local macOS provenance xattrs at signing.

Acceptance criteria:

- Existing recognition results remain unchanged.
- Ledger evidence remains available in debug/audit mode.
- The live recognition path no longer pays default diagnostics-only ledger cost.
- `ChordInkRecognizer` has a narrower orchestration role than at baseline.
- No fixture files are removed.
- Native chord handwriting still uses `PKCanvasView`.
- The active sprint, completed sprint log, and next backlog remain clear in this document.

Required verification:

```bash
swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1
python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py
git diff --check
```

Additional verification if editor/PencilKit code changes:

```bash
xcodegen generate
xcodebuild test -scheme SmartChart -destination "$SIMULATOR_DESTINATION" OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs
```

Do not use `CODE_SIGNING_ALLOWED=NO` for simulator test verification on this branch; it can build but fail app preflight launch.

For live simulator confidence after code cleanup:

```bash
scripts/audit_chord_entry_diagnostics.py --strict --details --scores 3
```

Use the disposable `Chord Writing Test Chart` for any user-facing pass.

## Completed Sprints Log

Append one entry here after each sprint completes. Each entry must include:

- sprint name
- commit range or final commit
- summary of what changed
- tests and live-pass evidence
- unresolved follow-up
- next sprint candidate

### Sprint 1: Code Cleanup First

- status: complete, pending commit
- commit range: `9479a94..working tree`
- summary: Recovered the streamlined recognition architecture without score retuning. Symbol-ledger diagnostics are opt-in, semantic candidate construction moved out of `ChordInkRecognizer` into composer-owned code, and `StrokeClusterer` support helpers were split into `StrokeClustererSupport.swift` as a behavior-preserving refactor.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed with `350` tests, `1` skipped, `0` failures using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs`; `git diff --check` passed.
- unresolved follow-up: Working tree is not committed yet; `docs/handwriting-recognition-implementation-plan.md` and `docs/current-architecture-audit.md` remain historical/stale when they conflict with this file; no fresh user-facing `Chord Writing Test Chart` pass was run after cleanup because Sprint 1 was behavior-preserving and covered by existing recognition fixtures.
- next sprint candidate: Discuss whether Sprint 2 should be documentation authority cleanup, PR/CodeQL hardening, fixture-tier cleanup, composer scoring extraction, or a return to editor/product polish.

## Next Sprint Backlog

Discuss and choose one item after Sprint 1 is complete:

- Rewrite `docs/handwriting-recognition-implementation-plan.md` into a concise historical architecture contract.
- Mark `docs/current-architecture-audit.md` stale or replace it with current architecture status.
- Open a PR for the recovered branch so CodeQL runs on the recognition work.
- Decide whether to keep all fixture tests always-on or split critical CI fixtures from full corpus checks.
- Continue recognition cleanup by extracting composer scoring policy without retuning.
- Return to product/editor polish once the architecture boundary is stable.

## Retired Or Stale Docs

Current authority:

- `docs/smart-chart-sprint-source-of-truth.md`: active sprint execution and recovery plan.
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
