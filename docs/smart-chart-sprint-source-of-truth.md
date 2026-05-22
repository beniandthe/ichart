# Smart Chart Sprint Source Of Truth

Status: active living sprint document
Created: 2026-05-20
Repo: `beniandthe/smart-chart`
Active branch: `codex/symbol-ledger-recognition`
Active baseline commit: Sprint 10 product/export checkpoint containing this entry; runtime checkpoint is `72cd12e Close sprint eight semantic contextualizer extraction`
Trusted checkpoint reference: `c60bb46 Polish altered chord recognition trust`

## Purpose

This document is the working source of truth for Smart Chart sprint recovery and forward planning.

Use it before starting recognition, editor, simulator, or architecture work. After each sprint completes, update this file in place: move the finished sprint into the completed log, record verification evidence, and define the next sprint only after discussing the next priority.

If this document conflicts with older recognition or architecture planning docs, this document wins for current sprint execution. `docs/core-design-document.md` still wins for product intent.

## Current Baseline

The active app runtime implementation state is the latest Sprint 8 checkpoint. Sprint 10 resumes product/editor polish from that recovered baseline:

- branch: `codex/symbol-ledger-recognition`
- runtime checkpoint: `72cd12e Close sprint eight semantic contextualizer extraction`
- PR readiness checkpoint: `61caeb9 Open sprint nine merge readiness`
- previous runtime checkpoint: `a738ed3 Close sprint seven text variant extraction`
- implementation state: Sprint 8 semantic glyph-contextualizer extraction; Sprint 9 merge-readiness documentation and PR review prep; Sprint 10 product/editor/export polish audit
- supporting audit: `docs/repo-github-recognition-audit-2026-05-20.md`
- latest local verification: Sprint 10 PDF export placeholder checkpoint passed `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint10` on 2026-05-22 with `311` tests, `1` skipped, `0` failures; the iOS simulator `SmartChart` scheme passed on the explicit iOS 26.4 iPad Air 11-inch (M4) simulator with `352` tests, `1` skipped, `0` failures
- latest GitHub verification: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on Sprint 10 PDF export placeholder commit `2eaa1a8`; the PR is not draft and remains blocked only by required review

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
- `646` ink fixtures remain default-on in the regression path; decoded fixture data is now cached inside the test loader to avoid repeated file-system churn.
- Full critical/full fixture tiering is deferred unless CI runtime or local loop cost becomes a real blocker.
- PR [#4](https://github.com/beniandthe/smart-chart/pull/4) is the active GitHub review surface; it was mergeable with all visible checks passing on Sprint 9 commit `61caeb9`.
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

### Sprint 10: Product/Editor Polish Audit

Status: active.

Goal: resume product work from the recovered recognition baseline by auditing the current app against `open -> write -> recognize -> snap -> fix -> export`, then choosing the smallest user-facing editor polish fix backed by current app evidence.

Non-goals:

- no recognition scoring changes
- no new recognition architecture or sidecars
- no fixture pruning or tiering unless validation cost becomes a real blocker
- no broad visual redesign
- no custom ink capture path that weakens native `PKCanvasView` feel

Tasks:

- Review `docs/core-design-document.md`, `docs/developer-mvp-spec.md`, this file, and the current editor implementation before changing code.
- Build and launch the current app on the intended simulator before judging handwriting or editor behavior.
- Audit the live product path: open/create chart, write chord ink, recognize, snap to structured chord event, correct/fix, and export/share.
- Record exact breakpoints and choose one smallest polish fix from current evidence.
- If editor/PencilKit code changes, regenerate the Xcode project and run the existing iOS simulator `SmartChart` scheme.

Current Sprint 10 audit notes:

- Product intent reviewed from `docs/core-design-document.md` and `docs/developer-mvp-spec.md`: Sprint 10 should protect the fast `open -> write -> recognize -> snap -> fix -> export` editor path, Apple Pencil/native PencilKit input, readable one-page charts, and PDF/export readiness.
- App evidence: on the explicit iOS 26.4 iPad Air 11-inch (M4) simulator, opening the Chord Writing Test Chart exposed a portrait editor clipping bug. The paper was wider than the visible canvas and the title rendered as a truncated `CHORD WRITING TES` / `CHORD WRITING '`.
- Root cause: `LeadSheetPageLayoutEngine` forced a `900` point minimum page width even when the editor host was about `772` points wide. No-composer title layout also stayed capped at `62%` of the header frame.
- Sprint 10 fix: keep the live editor responsive down to a `720` point minimum page width and allow no-composer titles to use the full paper width. This is layout-only and does not change recognition scoring, PencilKit capture, chord parsing, or commit behavior.
- Simulator evidence after the fix: the iOS 26.4 iPad Air 11-inch (M4) app build/run showed the full `CHORD WRITING TEST CHART` title and the paper stayed inside the portrait viewport.
- Local verification: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint10 --filter LeadSheetPageLayoutTests` passed with `27` tests, `0` failures; full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint10` passed with `311` tests, `1` skipped, `0` failures; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed with `351` tests, `1` skipped, `0` failures using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs`.
- App evidence after the first fix: the chord-writing loop opened directly into `Chord` mode as intended, but the top-bar export/share control was disabled while chord writing was active. That blocked the `write -> recognize -> snap -> fix -> export` path unless the user knew to toggle out of the mode first.
- Sprint 10 export fix: top-bar export is now available in chord-entry and note-correction modes because the export action already exits to browse before running. Free-hand page ink still keeps export locked while active.
- Simulator evidence after the export fix: on the explicit iOS 26.4 iPad Air 11-inch (M4) simulator, opening the Chord Writing Test Chart in `Chord` mode showed the export/share icon enabled; tapping it reached the expected Pro upgrade sheet in the free-plan state.
- Local verification after the export fix: full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint10` passed with `311` tests, `1` skipped, `0` failures; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed with `351` tests, `1` skipped, `0` failures using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs`.
- GitHub evidence before the PDF placeholder fix: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `bc8c63f`; the PR remained blocked only by required review.
- App evidence after the export reachability fix: using Pro Preview and exporting the Chord Writing Test Chart revealed that the PDF preview still leaked the editor instruction placeholder `Tap the measure in the editor to add a hit.` into empty measures.
- Sprint 10 PDF placeholder fix: `ChartPDFRenderer` now leaves empty measures as clean rhythm grids in exported PDFs instead of drawing editor-only instruction copy; `PDFChartExporterTests` now checks exported PDF text with PDFKit so the placeholder cannot regress.
- Simulator evidence after the PDF placeholder fix: on the explicit iOS 26.4 iPad Air 11-inch (M4) simulator, exporting the fresh Chord Writing Test Chart reached the PDF preview and the visible/accessibility text contained the title, page, measure, and beat labels without the old `Tap the measure...` placeholder.
- Local verification after the PDF placeholder fix: full `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint10` passed with `311` tests, `1` skipped, `0` failures; `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py` passed; `xcodegen generate` completed; iOS simulator `SmartChart` scheme passed with `352` tests, `1` skipped, `0` failures using `OTHER_CODE_SIGN_FLAGS=--strip-disallowed-xattrs`; `git diff --check` passed.
- GitHub evidence after the PDF placeholder fix: PR [#4](https://github.com/beniandthe/smart-chart/pull/4) had Dependency Review, SwiftPM, iOS simulator, Analyze Swift, and CodeQL passing on `2eaa1a8`; the PR is not draft and remains blocked only by required review.
- Fix-flow audit evidence: on the explicit iOS 26.4 iPad Air 11-inch (M4) simulator, opening `Turnaround Study`, enabling `Chord` mode, and tapping rendered `C7` opened the `Correct Chord` sheet for measure 3. Replacing the field text with `F7` and tapping `Update Chord` rendered `F7` back onto the chart; the sample chart was then restored to `C7`. No code change was needed for this audit pass.

Acceptance criteria:

- Current app/editor state is captured in this file or a supporting audit note.
- Any Sprint 10 code change is localized to the smallest user-facing product/editor issue found in the audit.
- Native `PKCanvasView` writing feel is preserved.
- Recognition behavior remains unchanged unless a tightly scoped product bug proves otherwise.
- Sprint 10 closes with local test evidence, simulator evidence when relevant, and a next backlog decision.

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

## Next Sprint Backlog

Discuss and choose one item after Sprint 10 is complete:

- Split semantic candidate recipes into smaller behavior-preserving files only if the review surface still feels too large.
- Continue product/editor polish based on the Sprint 10 audit findings.
- Merge PR [#4](https://github.com/beniandthe/smart-chart/pull/4) after review requirements and final checks are satisfied.
- Revisit fixture tiering only if CI runtime or local loop cost becomes a real blocker.

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
