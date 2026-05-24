# Smart Chart Sprint Source Of Truth

Status: active living sprint document
Created: 2026-05-20
Repo: `beniandthe/smart-chart`
Active branch: `main`
Active baseline commit: `1b792df Merge pull request #4 from beniandthe/codex/symbol-ledger-recognition`
Trusted checkpoint reference: `c60bb46 Polish altered chord recognition trust`

## Purpose

This document is the working source of truth for Smart Chart sprint recovery and forward planning.

Use it before starting recognition, editor, simulator, or architecture work. After each sprint completes, update this file in place: move the finished sprint into the completed log, record verification evidence, and define the next sprint only after discussing the next priority.

If this document conflicts with older recognition or architecture planning docs, this document wins for current sprint execution. `docs/core-design-document.md` still wins for product intent.

## Current Baseline

The active app runtime implementation state is the merged recovery branch from PR [#4](https://github.com/beniandthe/smart-chart/pull/4):

- branch: `main`
- merge checkpoint: `1b792df Merge pull request #4 from beniandthe/codex/symbol-ledger-recognition`
- runtime checkpoint: `72cd12e Close sprint eight semantic contextualizer extraction`
- product/editor checkpoint: `c76a356 Close sprint ten product editor audit`
- PR review follow-through checkpoint: `66dc5d2 Document chord ink clear decision`
- PR readiness checkpoint: `61caeb9 Open sprint nine merge readiness`
- previous runtime checkpoint: `a738ed3 Close sprint seven text variant extraction`
- implementation state: recognition recovery, product/editor polish audit, PR review follow-through, PR [#4](https://github.com/beniandthe/smart-chart/pull/4) merge, Sprint 12 post-merge app audit, Sprint 13 local hygiene/product smoke, Sprint 14 editor boundary cleanup, Sprint 15 recognition corpus debloat, and Sprint 16 app-shell debloat are complete; awaiting Sprint 17 user input
- supporting audit: `docs/repo-github-recognition-audit-2026-05-20.md`
- Sprint 12 audit artifact: `docs/smart-chart-post-merge-app-audit-2026-05-23.md`
- latest local verification: Sprint 16 passed `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint16` on 2026-05-24 with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed through XcodeBuildMCP with `321` passed, `36` skipped, `0` failures on the configured iPad Air 11-inch (M4) simulator; build/run succeeded; visual screenshot confirmed the app opens directly to Projects without Workspace/Settings tabs and with debug Developer Tools tucked below the project list.
- latest GitHub verification: main commit `31f1dde Start sprint twelve app audit` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on 2026-05-23; PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `66dc5d2`; the review thread was answered/resolved by product decision, and the PR merged into `main` as `1b792df` on 2026-05-23

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
- The full ink fixture archive remains test-only evidence, not runtime authority or user handwriting training data. Default recognition, cluster, and glyph tests now use a compact transferable regression suite; full archive/captured coverage runs are opt-in through `SMART_CHART_FULL_INK_FIXTURES=1`.
- Fixture pruning/deletion remains deferred. Sprint 15 changes default test authority, not the archived fixture files.
- PR [#4](https://github.com/beniandthe/smart-chart/pull/4) merged the recovery branch into `main`; it is no longer the active review surface.
- The local duplicate `SmartChartTests/Recognition/* 2.swift` files found during Sprint 12 were removed after explicit approval; no duplicate files remain in that directory.
- No tracked cache/raster/direct-ink detour files remain in the current tree; remaining bloat is inside the current recognition path and broad editor surfaces.

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

## Active Sprint

### Sprint 17: User Decision Point

Status: waiting for user input.

Goal: choose the next product or maintenance sprint after Sprint 16 removed the most obvious unfinished app-shell surfaces.

Current state:

- The app opens directly to Projects/Library.
- Workspace and Settings placeholder tabs are no longer active navigation.
- The chord-writing test chart entry point remains available only under debug/simulator Developer Tools.
- The local Pro entitlement switch is debug/simulator-only until StoreKit or a real purchase path exists.

Candidate directions to discuss:

- Continue app-shell/product polish by deciding whether the Library hero and free-tier copy should be more compact.
- Continue editor surface cleanup with one behavior-preserving extraction from `EditorView.swift` or `LeadSheetCanvasHostView.swift`.
- Validate handwriting quality with real Pencil/user input before any recognition retuning.
- Split semantic candidate recipes into smaller behavior-preserving files only if review surface still feels too large.
- Discuss full fixture archive pruning only as repository/data hygiene, not as recognition training.

Non-goals until the user chooses Sprint 17:

- No recognition score retuning, parser/compendium changes, or fixture deletion.
- No StoreKit implementation unless explicitly selected.
- No removal of debug/simulator chord-entry tooling.
- No direct change to the current chord ink lifecycle rule; rendered chord still clears the chord ink pass.

## Completed Sprints Log

Append one entry here after each sprint completes. Each entry must include:

- sprint name
- commit range or final commit
- summary of what changed
- tests and live-pass evidence
- unresolved follow-up
- next sprint candidate

### Sprint 1: Code Cleanup First

- status: complete
- final commit: `e040332 Document and clean up recognition sprint one`
- summary: Recovered the streamlined recognition architecture without score retuning. Symbol-ledger diagnostics are opt-in, semantic candidate construction moved out of `ChordInkRecognizer` into composer-owned code, and `StrokeClusterer` support helpers were split into `StrokeClustererSupport.swift` as a behavior-preserving refactor.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed with `350` tests, `1` skipped, `0` failures using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs`; `git diff --check` passed.
- unresolved follow-up: `docs/handwriting-recognition-implementation-plan.md` and `docs/current-architecture-audit.md` remain historical/stale when they conflict with this file; no fresh user-facing `Chord Writing Test Chart` pass was run after cleanup because Sprint 1 was behavior-preserving and covered by existing recognition fixtures; branch still needs push/PR for GitHub checks.
- next sprint candidate: Sprint 2 is documentation authority cleanup plus PR/CodeQL hardening.

### Sprint 2: Documentation Authority And PR Hardening

- status: complete
- commit range: `2eedd48 Open sprint two authority cleanup` through `4ff784e Clarify sprint two doc authority`, plus the Sprint 2 closeout entry in this file
- summary: Marked stale planning docs as historical, split `README.md` authority links into active and historical groups, pushed `codex/symbol-ledger-recognition`, and opened draft PR [#4](https://github.com/beniandthe/smart-chart/pull/4) as the GitHub review surface for the recovery branch.
- tests and evidence: `git diff --check` passed; trailing whitespace scan found no hits; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures. PR [#4](https://github.com/beniandthe/smart-chart/pull/4) showed Dependency Review, SwiftPM, and iOS simulator checks passing before this closeout push; CodeQL was still pending at closeout.
- unresolved follow-up: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) is draft and CodeQL/rerun checks need one final review before merge readiness. Sprint 3 is intentionally not selected yet.
- next sprint candidate: Review PR [#4](https://github.com/beniandthe/smart-chart/pull/4) status first, then choose between fixture tiering, composer scoring extraction, or product/editor polish.

### Sprint 3: Fixture Corpus Runtime Cleanup

- status: complete locally; PR checks must be rechecked after push
- commit range: `19b1b1e Close sprint two source of truth` through the Sprint 3 closeout commit containing this entry
- summary: Kept the full `646`-file ink fixture corpus default-on, added a decoded corpus cache to the test-only `InkFixtureLoader`, preserved deterministic fixture ordering and named fixture loading, and documented the fixture runtime policy in `SmartChartTests/Fixtures/Ink/README.md`.
- tests and evidence: focused `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter InkFixtureLoaderTests` passed with `2` tests, `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed. No fixture JSON files changed.
- GitHub evidence before the Sprint 3 push: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, and iOS simulator checks passing; CodeQL was still pending.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/smart-chart/pull/4) after the Sprint 3 push; full critical/full fixture tiering remains deferred until test runtime becomes a proven blocker.
- next sprint candidate: Update the PR for any CodeQL/CI result first, otherwise choose between composer scoring extraction and product/editor polish.

### Sprint 4: Composer Scoring Policy Extraction

- status: complete locally; PR checks must be rechecked after push
- commit range: `a91af92 Close sprint three fixture corpus cleanup` through the Sprint 4 closeout commit containing this entry
- summary: Extracted `ChordInkCandidateScoringPolicy.swift` from `ChordInkCandidateComposer.swift`, moved `ChordInkCandidateComposerScoring` with the scoring policy, and left candidate selection, text variants, semantic sidecars, and score constants unchanged.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- GitHub evidence before the Sprint 4 push: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, and CodeQL passing on `a91af92`.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/smart-chart/pull/4) after the Sprint 4 push. The composer still owns glyph candidate selection, text variant expansion, and semantic sidecar candidate injection.
- next sprint candidate: Choose between another behavior-preserving composer split, semantic sidecar extraction, or a return to product/editor polish.

### Sprint 5: Semantic Sidecar Boundary Cleanup

- status: complete locally; PR checks must be rechecked after push
- commit range: `236f55d Close sprint four composer scoring extraction` through the Sprint 5 closeout commit containing this entry
- summary: Replaced the semantic `ChordInkCandidateComposer` extension with explicit sidecar types. `ChordInkRecognitionCandidateComposer` now coordinates base composition, semantic sidecar injection, and timing metrics, while `ChordInkSemanticCandidateComposer` owns semantic candidate recipes and contextual glyph promotion helpers. Candidate scores, semantic confidence constants, compendium validation, and recognition acceptance policy were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- GitHub evidence before the Sprint 5 work: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `236f55d`.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/smart-chart/pull/4) after the Sprint 5 push. `ChordInkCandidateComposer.swift` still owns glyph candidate selection and text variant expansion, and `ChordInkSemanticCandidateComposer.swift` still needs a later behavior-preserving split.
- next sprint candidate: Choose between composer glyph-selection extraction, semantic contextualizer split, or a return to product/editor polish.

### Sprint 6: Composer Glyph-Selection Extraction

- status: complete locally; PR checks must be rechecked after push
- commit range: `267cfaf Close sprint five semantic sidecar boundary` through the Sprint 6 closeout commit containing this entry
- summary: Extracted glyph candidate selection and promotion rules from `ChordInkCandidateComposer.swift` into `ChordInkCandidateSelectionPolicy.swift`. The base composer now keeps sequence generation, text variant expansion, scoring delegation, and result metrics only. Selection thresholds, candidate promotion order, text variants, semantic sidecars, score constants, and recognition acceptance policy were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- GitHub evidence before the Sprint 6 work: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `267cfaf`.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/smart-chart/pull/4) after the Sprint 6 push. `ChordInkCandidateComposer.swift` still owns text variant expansion, and `ChordInkSemanticCandidateComposer.swift` still needs a later behavior-preserving split.
- next sprint candidate: Choose between text variant extraction, semantic contextualizer split, or a return to product/editor polish.

### Sprint 7: Composer Text-Variant Extraction

- status: complete locally; PR checks must be rechecked after push
- commit range: `5cbc58f Close sprint six composer selection extraction` through the Sprint 7 closeout commit containing this entry
- summary: Extracted glyph text aliases, canonical minor-sixth display normalization, and compact/wrapper/slash lookalike text expansions from `ChordInkCandidateComposer.swift` into `ChordInkCandidateTextVariantPolicy.swift`. The base composer now keeps selected sequence generation, scoring delegation, result de-duplication, and composition metrics only. Variant expansion rules, selection rules, semantic sidecars, score constants, and recognition acceptance policy were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- GitHub evidence before the Sprint 7 work: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `5cbc58f`.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/smart-chart/pull/4) after the Sprint 7 push. `ChordInkSemanticCandidateComposer.swift` still owns both semantic candidate recipes and contextual glyph promotion.
- next sprint candidate: Choose between semantic contextualizer split or a return to product/editor polish.

### Sprint 8: Semantic Glyph-Contextualizer Extraction

- status: complete; PR checks passed on `72cd12e`
- final commit: `72cd12e Close sprint eight semantic contextualizer extraction`
- summary: Extracted contextual glyph promotion from `ChordInkSemanticCandidateComposer.swift` into `ChordInkSemanticGlyphContextualizer.swift` and made `ChordInkRecognizer` call that sidecar explicitly. Semantic candidate recipes, contextual promotion thresholds, text variants, candidate selection, score constants, and recognition acceptance policy were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkRecognizerTests` passed with `39` tests, `0` failures; `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1 --filter ChordInkCandidateComposerTests` passed with `49` tests, `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint1` passed with `310` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed. PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `72cd12e`.
- unresolved follow-up: `ChordInkSemanticCandidateComposer.swift` still owns many semantic candidate recipes and shared suffix-shape helpers; `StrokeClusterer.swift` and `StrokeClustererSupport.swift` remain large.
- next sprint candidate: Sprint 9 is PR merge readiness.

### Sprint 9: PR Merge Readiness

- status: complete; PR [#4](https://github.com/beniandthe/smart-chart/pull/4) was approved by the user to move out of draft
- commit range: `61caeb9 Open sprint nine merge readiness` through the Sprint 10 kickoff commit containing this entry
- summary: Recorded green Sprint 8/Sprint 9 CI evidence, refreshed the PR body with the recovered pipeline and sprint sequence, reviewed PR blockers, and kept Sprint 9 as documentation/metadata only. No recognition, editor, PencilKit, fixture, scoring, or sidecar behavior changed.
- tests and evidence: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `61caeb9`. `git diff --check` passed for the Sprint 10 kickoff doc update.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/smart-chart/pull/4) after the Sprint 10 kickoff push. The PR is large and review-required; the main review risk remains size, especially the full ink fixture corpus and large recognition implementation files.
- next sprint candidate: Sprint 10 is product/editor polish audit.

### Sprint 10: Product/Editor Polish Audit

- status: complete; final closeout commit is the commit containing this entry
- commit range: `192c6c0 Open sprint ten product editor polish` through the Sprint 10 closeout commit containing this entry
- summary: Audited the recovered app against `open -> write -> recognize -> snap -> fix -> export`, then shipped the smallest user-facing fixes found in the live loop. The editor page now fits the portrait iPad viewport, export stays reachable from chord-entry and note-correction modes, and exported PDFs no longer leak editor-only placeholder copy into empty measures. No recognition scoring, parser authority, PencilKit capture policy, fixture corpus, or recognition sidecar behavior changed.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint10 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint10` passed with `311` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed with `352` tests, `1` skipped, `0` failures using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs`; `git diff --check` passed.
- live app evidence: on the explicit iOS 26.4 iPad Air 11-inch (M4) simulator, `Chord Writing Test Chart` opened in `Chord` mode with the full title visible and page inside the viewport; export was enabled from chord-entry mode; Pro Preview reached PDF preview; empty measures exported as clean grids without `Tap the measure...` placeholder text. `Turnaround Study` proved the correction loop by changing rendered `C7` to `F7`, then restoring it to `C7`. A fresh Chord Writing Test Chart accepted synthetic simulator strokes into the recognition proposal flow, surfaced `Confirm Chord`, and committed typed `C7` as a structured rendered chord; the disposable chart was reset afterward.
- GitHub evidence: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `ffc97b6` before this closeout commit; the PR is not draft and remains blocked only by required review.
- unresolved follow-up: recheck PR [#4](https://github.com/beniandthe/smart-chart/pull/4) after the Sprint 10 closeout push. The synthetic simulator stroke did not produce a reliable auto-read, so future handwriting-quality work should use real Pencil/user input or fixture replay rather than retuning from simulator swipe shapes.
- next sprint candidate: choose between PR review/merge follow-through, another small product/editor polish pass, or behavior-preserving semantic candidate recipe splitting.

### Sprint 11: PR Review Follow-Through

- status: complete; PR [#4](https://github.com/beniandthe/smart-chart/pull/4) merged into `main`
- commit range: `66dc5d2 Document chord ink clear decision` through merge commit `1b792df Merge pull request #4 from beniandthe/codex/symbol-ledger-recognition`
- summary: Recorded the product decision that accepting/rendering a chord consumes the chord-writing pass and clears the live chord ink layer. The unresolved review suggestion to preserve unconsumed chord ink was answered as intentionally out of scope for the current workflow, then resolved after user approval. No runtime behavior changed.
- tests and evidence: `git diff --check` passed for the Sprint 11 doc update. PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `66dc5d2`; the review thread was resolved; the PR merged into `main` as `1b792df` on 2026-05-23.
- unresolved follow-up: no PR review blocker remains. Future work should start from `main`, not `codex/symbol-ledger-recognition`.
- next sprint candidate: choose between a post-merge product/app audit, another small editor polish pass, behavior-preserving semantic candidate recipe splitting, or real-input handwriting validation.

### Sprint 12: Post-Merge App Audit

- status: complete; final closeout commit is the commit containing this entry
- commit range: `1e4ef82 Open sprint twelve post merge audit` through the Sprint 12 closeout commit containing this entry
- summary: Produced `docs/smart-chart-post-merge-app-audit-2026-05-23.md` as the written and visual post-merge app/architecture audit. The audit maps the whole app, app shell/persistence, user workflow, chord recognition pipeline, editor/export system, authority boundaries, live runtime paths, debug/tooling paths, local drift, bloat risks, and Sprint 13-15 recommendations.
- tests and evidence: main commit `31f1dde Start sprint twelve app audit` had SwiftPM tests, iOS simulator tests, and Analyze Swift passing on GitHub. Local audit verification initially found `14` untracked duplicate `SmartChartTests/Recognition/* 2.swift` files that were byte-identical to tracked tests but broke SwiftPM discovery.
- unresolved follow-up: the duplicate files required explicit cleanup approval before local verification could be clean again; Sprint 13 handled that approved cleanup and live smoke.
- next sprint candidate: Sprint 13 local hygiene and product smoke.

### Sprint 13: Local Hygiene And Product Smoke

- status: complete; final closeout commit is the commit containing this entry
- commit range: post-`31f1dde` cleanup through the Sprint 13 closeout commit containing this entry
- summary: Removed the `14` untracked duplicate `SmartChartTests/Recognition/* 2.swift` files after explicit user approval and proved the merged app path from `main`. No tracked fixture corpus, recognition score, parser, compendium, or chord ink lifecycle behavior changed.
- tests and evidence: `find SmartChartTests/Recognition -maxdepth 1 -name '* 2.swift' -print` returned no files; `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint12` passed with `311` tests, `1` skipped, `0` failures after duplicate cleanup; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed with `352` tests, `1` skipped, `0` failures on iPad Air 11-inch (M4), iOS 26.4.1.
- live app evidence: launched `Smart Chart`, verified the Projects library, opened `Chord Writing Test Chart`, entered chord mode, opened export from the editor, reached PDF preview/share, opened `Turnaround Study`, and verified rendered chord selection affordance. Correction behavior remains covered by automated chart editing and iOS simulator tests; no fragile coordinate-only correction edit was forced during smoke.
- unresolved follow-up: the library still exposes prototype debug/test-chart surface in debug/simulator builds and Workspace/Settings remain placeholder app-shell decisions.
- next sprint candidate: Sprint 14 editor surface boundary cleanup.

### Sprint 14: Editor Surface Boundary Cleanup

- status: complete; final closeout commit is the commit containing this entry
- commit range: post-Sprint 13 cleanup through the Sprint 14 closeout commit containing this entry
- summary: Reduced duplicated bridge coordination in `LeadSheetCanvasHostView` by extracting the repeated SwiftUI-to-UIKit property and callback wiring into one private `configure(_:context:)` helper. Native `PKCanvasView` behavior, chord recognition, chord ink lifecycle, placement, correction, and export behavior were unchanged.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint14` passed with `311` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed with `352` tests, `1` skipped, `0` failures on iPad Air 11-inch (M4), iOS 26.4.1; `git diff --check` passed.
- unresolved follow-up: `EditorView.swift` and `LeadSheetCanvasHostView.swift` remain broad surfaces; future work should continue with one small behavior-preserving extraction at a time.
- next sprint candidate: Sprint 15 decision point for user input.

### Sprint 15: Recognition Corpus And Runtime Authority Debloat

- status: complete; final closeout commit is the commit containing this entry
- summary: Decoupled the default recognition test lane from the full captured handwriting archive. `InkFixtureLoader` now exposes a compact default regression suite plus an explicit `SMART_CHART_FULL_INK_FIXTURES=1` archive lane. Recognizer, glyph, and cluster tests use the compact suite by default while preserving full archive checks as opt-in. Captured fixture coverage tests moved behind the opt-in archive gate, and fixture docs now state that captured samples are regression evidence, not continuous training data or runtime authority.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint15` passed with `315` tests, `36` skipped, `0` failures; `SMART_CHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint15-full` passed with `315` tests, `1` skipped, `0` failures; focused loader/recognizer/glyph/cluster/archive-integrity checks passed; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed.
- behavior boundary: no fixture JSON files were deleted; no recognition score, parser, compendium, PencilKit, editor, chord ink lifecycle, or app runtime behavior changed.
- unresolved follow-up: the full fixture archive still exists and may need future repository/data hygiene discussion, but it is no longer default recognition authority. The next recognition-maintenance sprint should continue to avoid score retuning until it has real-input evidence.
- next sprint candidate: Sprint 16 decision point for user input.

### Sprint 16: App Shell Product Surface Debloat

- status: complete; final closeout commit is the commit containing this entry
- summary: Removed placeholder Workspace and Settings tabs from the active app shell, keeping Projects/Library as the first app surface. Moved the debug/simulator chord-writing test chart entry point out of the Library hero into a collapsed Developer Tools section, and gated the local Pro entitlement switch/debug copy so release-style surfaces no longer show a prototype-only purchase path.
- tests and evidence: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint16` passed with `315` tests, `36` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `git diff --check` passed; `xcodegen generate` completed; XcodeBuildMCP iOS simulator `SmartChart` scheme test passed with `321` passed, `36` skipped, `0` failures; XcodeBuildMCP build/run succeeded on the configured iPad Air 11-inch (M4) simulator.
- visual evidence: simulator screenshot after launch showed Projects as the only top-level app surface, no Workspace/Settings tab bar, existing projects visible, and debug Developer Tools tucked below the project list.
- behavior boundary: no recognition score, parser, compendium, fixture, PencilKit, editor chord lifecycle, or StoreKit behavior changed. Debug/simulator chord-entry tooling remains available.
- unresolved follow-up: Library hero/free-tier copy still reads broad and marketing-like; a future product polish sprint can make it denser and more work-focused. StoreKit remains intentionally unimplemented.
- next sprint candidate: Sprint 17 decision point for user input.

## Next Sprint Backlog

Discuss and choose one item for Sprint 17:

- Tighten Library hero/free-tier copy into a denser working library surface.
- Continue editor surface cleanup with one behavior-preserving extraction from `EditorView.swift` or `LeadSheetCanvasHostView.swift`.
- Validate handwriting quality with real Pencil/user input before any recognition retuning.
- Split semantic candidate recipes into smaller behavior-preserving files only if the review surface still feels too large.
- Discuss full fixture archive pruning only as repository/data hygiene, not as recognition training.

## Retired Or Stale Docs

Current authority:

- `docs/smart-chart-sprint-source-of-truth.md`: active sprint execution and recovery plan.
- `docs/smart-chart-post-merge-app-audit-2026-05-23.md`: Sprint 12 written and visual post-merge app/architecture audit.
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
