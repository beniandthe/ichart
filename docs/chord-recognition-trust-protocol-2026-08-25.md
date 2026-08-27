# Chord Recognition Trust Protocol

Date: 2026-08-25
Branch: `codex/chord-recognition-accuracy`
Current authority: this document plus `docs/chord-recognition-accuracy-branch-plan-2026-08-25.md`

## Purpose

This protocol keeps the chord recognition accuracy branch narrow and drift-aware. The branch may change grouping, glyph recognition, candidate composition, trust policy, recognition fixtures, and recognition diagnostics. It must not change chord lane UI, rendered edit mode, terminal barline rendering, ink persistence, sync, measure resize, or layout guide behavior unless a direct recognition-validation blocker is documented first.

The trust target is correctness, not maximum coverage. A no-read or confirmation is acceptable. A confident wrong read is not.

## Forbidden Paths

- Do not reintroduce OCR, Vision text recognition, or `VNRecognizeTextRequest` into the production chord recognizer.
- Do not add `PKStrokeRecognizer` or any iOS 27-only dependency on this branch.
- Do not use Scribble as the lane recognizer. Scribble may remain only in manual text-entry/correction surfaces.
- Do not let draft preview or tap-to-confirm flow write rendered chart content before the explicit Render Chords / Auto Render action.
- Do not expand cloud sync, ink persistence, editor mode architecture, measure resize, terminal barline, or layout-guide behavior for recognition accuracy work.

## Current Live-Code Audit

Observed before implementation:

- `iChart` and `iChartTests` have no live `ChordOCR`, `VNRecognize`, `ChordRecognitionTrustArbiter`, or `PKStrokeRecognizer` references.
- Scribble appears in correction/account text-field surfaces, not as the chord-lane recognizer.
- Historical docs still mention OCR sidecars and trust arbiters. Those notes are history, not current implementation authority.
- The active branch checkout is `/Users/benirossman/Documents/Smart Chart` on `codex/chord-recognition-accuracy`.
- The delegated worktree `/Users/benirossman/.codex/worktrees/d3b0/Smart Chart` is detached at `d60d37b` and must not be used for branch edits unless realigned.

## Required Recognition Shape

1. Capture lane-local PencilKit strokes.
2. Filter invisible/rendered artifact strokes for draft preview.
3. Detect and remove draft barline strokes before chord grouping.
4. Group chord ink left-to-right by semantic root starts.
5. Recognize glyphs inside each group.
6. Compose and normalize candidates through `ChordRecognitionCompendium`.
7. Apply trust policy.
8. Publish draft preview only.
9. Commit rendered chords/barlines only from explicit Render Chords / Auto Render flow.

Sequential grouping contract:

- A base root `A-G` starts a chord.
- Accidentals and suffix/extension glyphs stay with the active root.
- Slash-bass roots stay inside the active chord after a slash separator.
- The next base root starts the next chord.
- Once a next root starts, the previous group boundary must stay stable.
- Horizontal gap is fallback evidence only.

## Acceptance Gates

Each implementation slice must record:

- observed files changed
- focused Swift test command/result
- full fixture archive command/result, when applicable
- whether `xcodegen generate` changed tracked files
- Xcode simulator test result with nonzero selected tests and zero failures, when run
- physical iPad validation status, if claimed

Minimum local gates before final branch claim:

```bash
swift test --scratch-path /tmp/iChartSwiftBuild-recognition-trust --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|StrokeClustererTests|ChordInkSymbolLedgerTests|InkFixtureLoaderTests|InkFixtureCoverageTests|ChordEntryPassReplayTests|ChordInkSequentialGrouperTests|ChordInkRenderResolutionPolicyTests|ChordInkRecognitionSessionTests|ChordInkDraftPreviewTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'
ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-recognition-trust-full --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|StrokeClustererTests|ChordInkSymbolLedgerTests|InkFixtureLoaderTests|InkFixtureCoverageTests|ChordEntryPassReplayTests|ChordInkSequentialGrouperTests'
xcodegen generate
xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' test
```

The Xcode test result is not accepted from exit code alone. Confirm the `.xcresult` has nonzero selected tests and zero failures.

## Physical iPad Validation

Physical iPad behavior is the final acceptance signal for handwritten recognition. Before claiming final accuracy, write and render:

- roots `A`, `B`, `C`, `D`, `E`, `F`, `G`
- `D-7 E-7`
- `Cmaj7 Dmin7 Emin9`
- `Db-`
- `Db7sus`
- `Bb-7`
- `F#7`
- `G/B`
- `C7(b9)`
- `C7(#11)`
- `C7alt`
- chord repeat
- chord-plus-draft-barline sequences

Record each case as trusted, confirmed, no-read, wrong-read, or grouping failure. Do not count simulator or fixture proof as physical acceptance.

## Cautionary Future: Erase-As-Rejection

Status: parked. Do not implement this behavior on the current recognition branch unless it is explicitly reopened after trace-only proof.

The idea is useful but risky: if a handwritten chord produces a registered draft preview and the user erases that chord ink before Render Chords, the erase may be local negative evidence for that exact preview attempt. It is not proof that the chord symbol is wrong, and it is not proof that future rewrites of the same chord should be penalized.

If this is reopened later, required safety constraints are:

- Key the rejection to a draft-session identity: lane/system, anchor or measure bucket, stroke fingerprint, and candidate text.
- After the erase, clear the visible preview immediately when that ink spot is empty.
- If the same erased fingerprint at the same spot would produce the same candidate again, suppress it or downgrade it to confirmation/no-read instead of showing the same confident preview.
- If the user rewrites materially different ink, writes at a different anchor, or writes the same chord elsewhere, allow normal recognition again.
- Keep the rule draft-only. It must not create rendered chart content, mutate saved chart chords, or bypass explicit Render Chords / Auto Render.
- Keep the first implementation session-local. Do not persist rejection memory until a separate serialized correction-memory design is reviewed.
- DEBUG diagnostics may record candidate text, anchor bucket, and a stroke-fingerprint hash for replay. Production telemetry may record aggregate rejection counts only.

Future-only implementation sequence:

- Reproduce and trace the current erase path before code changes.
- Add tests for erase-to-empty clearing stale preview state.
- Add a draft-session rejection ledger keyed by target identity, stroke fingerprint, and candidate.
- Apply the ledger after recognition result construction and before preview replacement display.
- Add tests proving the same wrong candidate is suppressed for the erased spot, while materially new ink and the same chord elsewhere are still eligible.
- Add physical-iPad validation: write a wrong-preview case, erase it, confirm the stale preview disappears, then rewrite with materially different ink and confirm recognition is not globally poisoned.

## Drift Checklist

- [x] Current commit and branch recorded before code changes.
- [x] No OCR/Vision text recognition path added.
- [x] No `PKStrokeRecognizer` dependency added.
- [x] Scribble remains correction-only.
- [x] Render Chords / Auto Render remains the only rendered-content boundary.
- [x] Sequential grouping tests added before grouping implementation.
- [x] Replayable recognition-trace invariants added before further glyph/scoring work.
- [x] Known full-archive flat failures stayed visible until fixed.
- [x] Trust policy favors confirmation/no-read over confident wrong read.
- [x] Root-glyph volatility is gated at trust policy before additional glyph scoring changes.
- [x] Erase-as-rejection is parked as cautionary future work, not an active behavior change for this branch.
- [x] Aggregate telemetry only; no raw chord text, drawing payloads, chart titles, user names, emails, or support data added to production telemetry.
- [x] Physical iPad validation recorded for the current B+ architecture/stability claim; this branch does not claim A-level broad handwriting accuracy.

## Implementation Log

Commit `4014eaf` added this protocol and linked it from the branch plan.

Commit `442eea2` renamed live recognition decisions from auto-render terminology to trusted/confirm terminology while preserving the legacy `autoRendered` diagnostic resolution and serialized `rejectedAutoRenderRules` correction-memory key.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-trust-terminology --filter 'ChordInkRenderResolutionPolicyTests|ChordInkUserCorrectionMemoryTests|ChordInkRecognizerTests'`
- Result: pass, 59 selected XCTest cases, 1 expected full-archive skip, 0 failures.

Commit `920cbb3` added index-preserving stroke clusters, root-led sequential grouping, grouping tests, and targeter integration. Gap clustering remains fallback when sequential root evidence does not produce multiple groups.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-sequential-grouping --filter 'ChordInkSequentialGrouperTests|ChordInkRecognizerTests|StrokeClustererTests'`
- Result: pass, 64 selected XCTest cases, 2 expected full-archive skips, 0 failures.
- `xcodegen generate`
- Result: generated project, no tracked project churn.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -resultBundlePath /tmp/iChartSequentialGrouping-1787674648.xcresult -only-testing:iChartTests/ChordInkSequentialGrouperTests test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartSequentialGrouping-1787674648.xcresult --format json`
- Result: 7 total tests, 7 passed, 0 failed, 0 skipped.

Commit `cf3eec7` tightened trust gates for generated-sequence-limit risk, missing rooted glyph evidence, unsupported high-confidence candidate pressure, and live provider boundaries.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-trust-gates --filter 'ChordInkRecognizerTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 52 selected XCTest cases, 1 expected full-archive skip, 0 failures.
- `xcodegen generate`
- Result: generated project, no tracked project churn.

Commit `7af0592` fixed the captured D-flat flat-loop ranking failure, added negative lookalike coverage for `°`, `•`, `△`, and `6`, added `ChordRepeatCaptured01`, and introduced the named trust acceptance fixture set.

Validation:

- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-flat-fix --filter 'GestureTemplateRecognizerTests|ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled'`
- Result: pass, 14 selected XCTest cases, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-trust-acceptance --filter 'ChordInkTrustAcceptanceTests|InkFixtureLoaderTests|ChordInkRecognizerTests/testRecognizesChordRepeatSymbolWhenInkIsCloseAndStrokeOrderVaries'`
- Result: pass, 6 selected XCTest cases, 0 failures.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-flat-fix --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled'`
- Result: pass, 3 selected XCTest cases, 0 failures.
- `xcodegen generate`
- Result: generated project, no tracked project churn.
- `ICHART_FULL_INK_FIXTURES=1 xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -resultBundlePath /tmp/iChartRecognitionTrustFinal-1787675315.xcresult -only-testing:iChartTests/ChordInkSequentialGrouperTests -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/ChordRecognitionProviderBoundaryTests -only-testing:iChartTests/GestureTemplateRecognizerTests/testCapturedDFlatLoopsRankFlatBeforeDegreeDotAndSixLookalikes -only-testing:iChartTests/GestureTemplateRecognizerTests/testFlatLoopBoostDoesNotStealDegreeDotTriangleOrSixTemplates -only-testing:iChartTests/GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled -only-testing:iChartTests/ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled -only-testing:iChartTests/StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled test`
- Result: failed before selected tests ran because the simulator reported `Busy` / application preflight launch failure.
- `ICHART_FULL_INK_FIXTURES=1 xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'id=3619FD3E-3A11-4C33-AE7E-C9FFB905B1A8' -resultBundlePath /tmp/iChartRecognitionTrustFinalRetry-1787675374.xcresult -only-testing:iChartTests/ChordInkSequentialGrouperTests -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/ChordRecognitionProviderBoundaryTests -only-testing:iChartTests/GestureTemplateRecognizerTests/testCapturedDFlatLoopsRankFlatBeforeDegreeDotAndSixLookalikes -only-testing:iChartTests/GestureTemplateRecognizerTests/testFlatLoopBoostDoesNotStealDegreeDotTriangleOrSixTemplates -only-testing:iChartTests/GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled -only-testing:iChartTests/ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled -only-testing:iChartTests/StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartRecognitionTrustFinalRetry-1787675374.xcresult --format json`
- Result: 15 total selected simulator tests, 12 passed, 3 skipped, 0 failed. The skipped tests were full-archive opt-in tests because the Xcode test host did not receive `ICHART_FULL_INK_FIXTURES`; full-archive coverage is therefore proven by the SwiftPM full-archive commands above, not by this simulator run.

Music-theory context extraction:

- `docs/chord-recognition-music-theory-context-evidence-2026-08-25.md` records repo and web evidence for root, root-accidental, quality, extension, alteration, slash-bass, and chord-repeat roles.
- The current decision is to add theory only as a shared role-evidence layer for grouping, candidate composition, scoring, and confirmation. It must not expand parser coverage silently, reintroduce OCR/Scribble lane recognition, or become a key/progression auto-correction engine.
- Validation: documentation-only slice; no recognizer code or tests changed.

Commit `046bd45` added `ChordInkTheoryRoleContext`, pure role-context tests, and migrated `ChordInkSequentialGrouper` to consume shared root-start/slash-bass role evidence instead of private duplicated root/slash checks. The helper labels root base, root accidental, quality, chord extension, alteration accidental, alteration degree, slash separator, slash bass root, six-nine separator, parentheses, chord-repeat dots/slash, and unknown roles. This did not expand parser coverage or change lane UI/render flow.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-theory-role-context --filter 'ChordInkTheoryRoleContextTests|ChordInkSequentialGrouperTests'`
- Result: pass, 15 selected XCTest cases, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-theory-role-context-broad --filter 'ChordInkTheoryRoleContextTests|ChordInkSequentialGrouperTests|ChordInkRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 69 selected XCTest cases, 1 expected full-archive skip, 0 failures.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-theory-role-context-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkTheoryRoleContextTests|ChordInkSequentialGrouperTests'`
- Result: pass, 18 selected XCTest cases, 0 failures.
- `xcodegen generate`
- Result: generated project, no tracked project churn.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -resultBundlePath /tmp/iChartTheoryRoleContext-20260825-0954.xcresult -only-testing:iChartTests/ChordInkTheoryRoleContextTests -only-testing:iChartTests/ChordInkSequentialGrouperTests test`
- Result: failed before selected tests ran because the simulator reported `Busy` / application preflight launch failure.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'id=3619FD3E-3A11-4C33-AE7E-C9FFB905B1A8' -resultBundlePath /tmp/iChartTheoryRoleContextRetry-20260825-0955.xcresult -only-testing:iChartTests/ChordInkTheoryRoleContextTests -only-testing:iChartTests/ChordInkSequentialGrouperTests test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartTheoryRoleContextRetry-20260825-0955.xcresult --format json`
- Result: 15 total selected simulator tests, 15 passed, 0 failed, 0 skipped.

Semantic role-context composer slice migrated chord-repeat semantic candidate creation onto the shared theory role context. `ChordInkTheoryRoleContext` now exposes validated chord-repeat glyph candidates, `ChordInkRecognitionCandidateComposer` builds one role context per target, and `ChordInkSemanticCandidateComposer` no longer carries a private duplicate dot-slash-dot layout validator. This keeps chord-repeat evidence in the shared theory layer without changing lane UI, render timing, parser coverage, or trust thresholds.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-theory-semantic --filter 'ChordInkTheoryRoleContextTests|ChordInkCandidateComposerTests|ChordInkRecognizerTests/testRecognizesChordRepeatSymbolFromDotSlashDotInk|ChordInkRecognizerTests/testRecognizesChordRepeatSymbolWhenInkIsCloseAndStrokeOrderVaries|ChordInkRecognizerTests/testChordRepeatRecognitionCanBeTrustedWithoutRootEvidence'`
- Result: pass, 64 selected XCTest cases, 0 failures.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-theory-semantic-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests'`
- Result: pass, 64 selected XCTest cases, 0 failures.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=3619FD3E-3A11-4C33-AE7E-C9FFB905B1A8' -resultBundlePath /tmp/iChartRoleContextComposer-20260825-1003.xcresult -only-testing:iChartTests/ChordInkTheoryRoleContextTests -only-testing:iChartTests/ChordInkCandidateComposerTests -only-testing:iChartTests/ChordInkRecognizerTests/testRecognizesChordRepeatSymbolFromDotSlashDotInk -only-testing:iChartTests/ChordInkRecognizerTests/testRecognizesChordRepeatSymbolWhenInkIsCloseAndStrokeOrderVaries -only-testing:iChartTests/ChordInkRecognizerTests/testChordRepeatRecognitionCanBeTrustedWithoutRootEvidence test`
- Result: failed before selected tests ran because the simulator reported `Busy` / application preflight launch failure.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=FB72927F-8AE8-466D-B698-6F5840EBEA94' -resultBundlePath /tmp/iChartRoleContextComposer-20260825-1004.xcresult -only-testing:iChartTests/ChordInkTheoryRoleContextTests -only-testing:iChartTests/ChordInkCandidateComposerTests -only-testing:iChartTests/ChordInkRecognizerTests/testRecognizesChordRepeatSymbolFromDotSlashDotInk -only-testing:iChartTests/ChordInkRecognizerTests/testRecognizesChordRepeatSymbolWhenInkIsCloseAndStrokeOrderVaries -only-testing:iChartTests/ChordInkRecognizerTests/testChordRepeatRecognitionCanBeTrustedWithoutRootEvidence test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartRoleContextComposer-20260825-1004.xcresult`
- Result: 64 total selected simulator tests, 64 passed, 0 failed, 0 skipped.

Semantic glyph-contextualizer role-prefix slice migrated suspended/altered semantic boost prefix detection onto `ChordInkTheoryRoleContext.rootDescriptorPrefixLength`. The role scan now classifies active-root accidentals before checking for the next root, exposes direct prefix length, and allows a close A-G root behind a suffix lookalike only in the first glyph column. This preserves captured `F#7sus` evidence without letting later flat columns reopen as `C/G` roots. `ChordInkRecognizerTests` fixture assertions now include raw candidates, glyph columns, and candidate scores in failure messages because the full archive caught a real regression in this slice.

Validation:

- Initial full-archive attempt after the first role-prefix migration failed: `FSharp7susCaptured03` read as `B#7sus` instead of `F#7sus`.
- A broader attempted root-threshold relaxation failed with 19 full-archive regressions, mostly false `sus` reads for flat minor/major/altered fixtures. That change was narrowed before commit.
- `swift test --scratch-path /tmp/iChartSwiftBuild-role-contextualizer-fix2 --filter 'ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 68 selected XCTest cases, 1 expected full-archive skip, 0 failures.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-role-contextualizer-full-fix2 --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkSemanticGlyphContextualizerTests|ChordInkTheoryRoleContextTests|ChordInkTrustAcceptanceTests'`
- Result: pass, 19 selected XCTest cases, 0 failures.
- `xcodegen generate`
- Result: generated project, no tracked project churn.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=FB72927F-8AE8-466D-B698-6F5840EBEA94' -resultBundlePath /tmp/iChartRoleContextualizer-20260825-1014.xcresult -only-testing:iChartTests/ChordInkSemanticGlyphContextualizerTests -only-testing:iChartTests/ChordInkTheoryRoleContextTests -only-testing:iChartTests/ChordInkRecognizerTests/testRecognizesDefaultRegressionFixturesThroughPureSwiftPipeline -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/ChordRecognitionProviderBoundaryTests test`
- Result: failed before selected tests ran because the simulator reported `Busy` / application preflight launch failure.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=165234BC-33C0-48D7-896B-9AD058C13C53' -resultBundlePath /tmp/iChartRoleContextualizer-20260825-1015.xcresult -only-testing:iChartTests/ChordInkSemanticGlyphContextualizerTests -only-testing:iChartTests/ChordInkTheoryRoleContextTests -only-testing:iChartTests/ChordInkRecognizerTests/testRecognizesDefaultRegressionFixturesThroughPureSwiftPipeline -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/ChordRecognitionProviderBoundaryTests test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartRoleContextualizer-20260825-1015.xcresult`
- Result: 18 total selected simulator tests, 18 passed, 0 failed, 0 skipped.

Role-prefix trust acceptance fixture slice promoted the full-archive cases that caught the false-sus role-prefix regression into `InkFixtureLoader.trustAcceptanceFixtureNames`. Added coverage includes `FSharp7susCaptured03` plus flat minor, flat major, flat altered, and flat suspended fixtures that should not be stolen by contextual `sus` boosts.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-role-prefix-acceptance --filter 'ChordInkTrustAcceptanceTests|InkFixtureLoaderTests'`
- Result: pass, 5 selected XCTest cases, 0 failures.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=165234BC-33C0-48D7-896B-9AD058C13C53' -resultBundlePath /tmp/iChartRolePrefixAcceptance-20260825-1017.xcresult -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/InkFixtureLoaderTests test`
- Result: failed before selected tests ran because the simulator reported `Busy` / application preflight launch failure.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=42254D11-2E65-4586-AEBE-C6317AF2DD10' -resultBundlePath /tmp/iChartRolePrefixAcceptance-20260825-1018.xcresult -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/InkFixtureLoaderTests test`
- Result: failed before selected tests ran because the simulator again reported `Busy` / application preflight launch failure. No simulator XCTest pass is claimed for this test-list-only slice.

Base-letter iPad validation slice:

- Observed on physical iPad from user report: base `D` still did not read; `F` read as `E`; `E` sometimes read as `F`. Treat this as the source-of-truth failure for the base-letter group.
- Local audit found two matching glyph-layer issues: one-stroke `D` had no root heuristic and fell through to curved lookalikes; three-stroke `E`/`F` selection used first-stroke order instead of top/middle/bottom evidence. Captured `E` fixtures also ranked raw `5` above `E`, meaning later context was rescuing a weak base glyph.
- Fix scope: `GestureTemplateRecognizer` only. Added one-stroke `D` recognition below flat-glyph confidence, added top/middle/bottom evidence for `E`/`F`, added four-stroke block `E`, and protected flat loops from being stolen by the new `D` heuristic.
- No lane UI, render timing, edit mode, barline, ink persistence, sync, measure resize, OCR/Scribble, or Apple stroke-recognizer code changed.

Validation:

- Red focused gate before implementation: `swift test --scratch-path /tmp/iChartSwiftBuild-base-letters-red --filter 'GestureTemplateRecognizerTests/testOneStrokeRootDIsRecognizedBeforeCurvedLookalikes|GestureTemplateRecognizerTests/testRootFUsesBottomStrokeEvidenceInsteadOfStrokeOrder|GestureTemplateRecognizerTests/testRootEUsesBottomStrokeEvidenceInsteadOfStrokeOrder|GestureTemplateRecognizerTests/testCapturedBaseLetterFamiliesRankExpectedGlyphFirst'`
- Result: failed as expected. One-stroke `D` ranked `G`; top-first `F` ranked `E`; vertical-first block `E` did not rank `E`; captured `E` fixtures ranked `5` above `E`.
- Focused gate after implementation/tightening: `swift test --scratch-path /tmp/iChartSwiftBuild-base-letters-tight2 --filter 'GestureTemplateRecognizerTests/testOneStrokeRootDIsRecognizedBeforeCurvedLookalikes|GestureTemplateRecognizerTests/testRootFUsesBottomStrokeEvidenceInsteadOfStrokeOrder|GestureTemplateRecognizerTests/testRootEUsesBottomStrokeEvidenceInsteadOfStrokeOrder|GestureTemplateRecognizerTests/testCapturedBaseLetterFamiliesRankExpectedGlyphFirst|GestureTemplateRecognizerTests/testOneStrokeDHeuristicDoesNotStealFlatLoops|GestureTemplateRecognizerTests/testCapturedDFlatLoopsRankFlatBeforeDegreeDotAndSixLookalikes'`
- Result: pass, 6 selected XCTest cases, 0 failures.
- Recognition slice gate: `swift test --scratch-path /tmp/iChartSwiftBuild-base-letters-focused --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 136 selected XCTest cases, 2 expected full-archive skips, 0 failures.
- Full archive gate initially failed on `BFlatMajor13` because the new one-stroke `D` heuristic displaced a flat loop from the top three. The D confidence was lowered below valid flat confidence while remaining above the generic curved `G` fallback.
- Full archive rerun: `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-base-letters-full2 --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
- Result: pass, 3 selected XCTest cases, 0 failures.
- Physical iPad retest: pending fresh Debug install/launch after this slice.

D-only follow-up:

- Observed on physical iPad after the first base-letter patch: `E` and `F` were fixed in the chart, but `D` still did not read; occasional wrong read was `B`, with more frequent no-read. Treat this as the source-of-truth D failure.
- Local audit after the follow-up found the remaining uncovered shape: top-first one-stroke uppercase `D` fell through to the generic curved `G` path and produced no `D` candidate. Noisy two-stroke single-bowl `D` was already covered locally, but explicit B-captured regression coverage was added so future D widening cannot steal real `B`.
- Fix scope: `GestureTemplateRecognizer` only. The one-stroke D heuristic now accepts simple top-first single-bowl D contours while still keeping `D` below valid flat-loop confidence and preserving captured B fixtures.

Validation:

- Red focused gate before the D follow-up implementation: `swift test --scratch-path /tmp/iChartSwiftBuild-d-root-red --filter 'GestureTemplateRecognizerTests/testTopFirstOneStrokeRootDIsRecognizedBeforeCurvedLookalikes|GestureTemplateRecognizerTests/testNoisySingleBowlRootDDoesNotFallToB|GestureTemplateRecognizerTests/testCapturedBaseLetterFamiliesRankExpectedGlyphFirst'`
- Result: failed as expected. Top-first one-stroke `D` ranked `G` and had no `D` candidate; noisy two-stroke D and captured B/D/E/F fixtures already passed.
- Focused D/B/flat gate after implementation: `swift test --scratch-path /tmp/iChartSwiftBuild-d-root-green2 --filter 'GestureTemplateRecognizerTests/testTopFirstOneStrokeRootDIsRecognizedBeforeCurvedLookalikes|GestureTemplateRecognizerTests/testNoisySingleBowlRootDDoesNotFallToB|GestureTemplateRecognizerTests/testOneStrokeRootDIsRecognizedBeforeCurvedLookalikes|GestureTemplateRecognizerTests/testOneStrokeDHeuristicDoesNotStealFlatLoops|GestureTemplateRecognizerTests/testCapturedBaseLetterFamiliesRankExpectedGlyphFirst'`
- Result: pass, 5 selected XCTest cases, 0 failures.
- Recognition slice gate: `swift test --scratch-path /tmp/iChartSwiftBuild-d-root-focused --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 139 selected XCTest cases, 2 expected full-archive skips, 0 failures.
- Full archive gate: `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-d-root-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
- Result: pass, 3 selected XCTest cases, 0 failures.
- Physical iPad retest: pending fresh Debug install/launch after this D-only slice.

Screenshot D/B follow-up:

- Observed from physical iPad screenshot `Screenshot 2026-08-25 at 1.29.28 PM.png`: handwritten input was visually `D | D-7 | D°7 | D/F# |`; the draft preview read `? ? ? B/F# |`. Treat this as device evidence that grouping and barline removal were mostly working, slash-bass suffix recognition was active, and the active failure was D root/body evidence. The wrong concrete read was `B/F#`; the first three D-root groups remained no-read/confirmation placeholders.
- Diagnostic limitation: the live chord-entry JSONL recorder is simulator-only in the current code path, and chord-lane breadcrumbs are disabled unless `iChartChordLaneBreadcrumbsEnabled` is set. No device-side raw candidate JSON is claimed for this screenshot; the visible preview is the source-of-truth app read for this pass.
- Local red test reproduced the failure class: a screenshot-style two-stroke single-bowl `D` ranked `B` first (`B:0.9750,D:0.7535,...`) before the patch.
- Fix scope: `GestureTemplateRecognizer` only. Two-stroke `B` now requires measurable two-lobe body evidence instead of treating any noisy curved body as B. A lower-confidence noisy single-bowl `D` fallback now rescues D-shaped bodies whose middle band stays on the outside curve. Real B roots remain protected by captured B fixtures, shallow-waist B-flat fixtures, and the full-archive `B#+` regression.
- Important risk surfaced and resolved locally: an overly broad D boost stole `Bb` families as `Db`, and an overly strict B gate stole `B#+` as `D#+`. Those regressions were not accepted; B evidence was retuned around actual captured B geometry before this slice was considered locally green.

Validation:

- Red screenshot-style D gate before implementation: `swift test --scratch-path /tmp/iChartSwiftBuild-d-screenshot-red --filter 'GestureTemplateRecognizerTests/testScreenshotStyleTwoStrokeRootDDoesNotFallToB|GestureTemplateRecognizerTests/testTwoLobeRootBStillRanksBeforeD'`
- Result: failed as expected. Screenshot-style D ranked `B`; two-lobe B still ranked `B`.
- Focused D/B gate after final retuning: `swift test --scratch-path /tmp/iChartSwiftBuild-d-screenshot-green7 --filter 'GestureTemplateRecognizerTests/testScreenshotStyleTwoStrokeRootDDoesNotFallToB|GestureTemplateRecognizerTests/testTwoLobeRootBStillRanksBeforeD|GestureTemplateRecognizerTests/testCapturedBaseLetterFamiliesRankExpectedGlyphFirst|GestureTemplateRecognizerTests/testNoisySingleBowlRootDDoesNotFallToB'`
- Result: pass, 4 selected XCTest cases, 0 failures.
- Trust acceptance gate after final retuning: `swift test --scratch-path /tmp/iChartSwiftBuild-d-trust-green7 --filter 'ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
- Result: pass, 1 selected XCTest case, 0 failures.
- Recognition slice gate after final retuning: `swift test --scratch-path /tmp/iChartSwiftBuild-d-screenshot-focused2 --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 141 selected XCTest cases, 2 expected full-archive skips, 0 failures.
- Full archive gate after final retuning: `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-d-screenshot-full2 --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
- Result: pass, 3 selected XCTest cases, 0 failures.
- Physical iPad retest: pending fresh Debug install/launch after this screenshot D/B slice.

Physical iPad validation:

- Status: fresh Debug build installed and launched on the attached physical iPad at 2026-08-25 13:46 PT after the screenshot D/B patch. Retest pending for the same handwritten sequence: `D | D-7 | D°7 | D/F# |`.
- No final handwriting accuracy claim is made from simulator, fixture, build, install, or launch evidence alone.

Draft preview device diagnostics slice:

- Observed on physical iPad from user report/screenshot `IMG_0266.PNG`: a standalone handwritten `D` previewed as `D`, then after adding `D-7` the preview showed `? ? |`. Treat this as evidence that the draft preview currently represented two chord targets before the barline and that the earlier `D` read was not stable across the next full-lane preview recompute.
- Code audit found that draft preview recognition rebuilds targets from the current lane drawing and `ChordPreviewState.replaceDraftChords` replaces the draft chord list. It preserves draft identity/selected text by anchor, but it does not preserve a previous best read when a later pass returns no supported candidate for the same anchor.
- Added DEBUG-only device diagnostics to `ChordDraftPreviewDeviceDiagnostics`: JSONL is written to `Library/Application Support/iChart/chord-draft-preview-debug.jsonl` inside the app data container. It records targeting, single-target starts, recognition payloads, and preview replacement evidence, including target counts, stroke counts, lane fractions, supported candidates, accepted text, action, reason, confidence, top scores, and previous-to-new preview text transitions.
- Fix scope: diagnostic plumbing only. No OCR/Scribble/Apple stroke recognizer, lane UI, render timing, edit mode, barline rendering, ink persistence, sync, measure resize, or recognition decision behavior changed.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-device-draft-diagnostics3 --filter 'ChordDraftPreviewDeviceDiagnosticsTests'`
- Result: pass, 1 selected XCTest case, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-device-draft-diagnostics-slice --filter 'ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 142 selected XCTest cases, 2 expected full-archive skips, 0 failures.
- `xcodegen generate`
- Result: project regenerated.
- Physical iPad Debug build: `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -allowProvisioningUpdates build`
- Result: pass, build succeeded after fixing a UIKit-only initializer argument-order compile error caught by the first device build.
- Physical iPad install/launch: installed and launched at 2026-08-25 14:02 PT.
- Initial trace pull before editor/chord preview activity returned file-not-found, so no diagnostic event is claimed yet. Device reproduction and trace pull are pending.

Draft preview batch stroke-order fix:

- Physical iPad trace pulled after the `D` then `D-7` repro showed the real failure was not a broad D glyph failure. The standalone two-stroke `D` went through the single-target path and returned raw candidates `D`, `B`, `F` with `D` first. After adding `D-7`, targeting produced two batch targets; the first target had the same D bounds and two strokes, but the batch payload returned unsupported suffix-like candidates `ø`, `+`, `9`, and `ChordPreviewState.replaceDraftChords` replaced the previous renderable `D` with an unresolved `?`.
- Observed trace file: `/tmp/chord-draft-preview-debug-after-d-dminor7.jsonl`. Key timestamps: standalone `D` at `2026-08-25T21:05:37Z`; batch recompute after `D-7` at `2026-08-25T21:05:43Z`.
- Code audit found no separate batch recognizer. `ChordInkRecognitionSession.startBatch` maps every request through the same recognizer as single-target recognition, so the mismatch had to be in the per-target request content.
- Fix scope: `LeadSheetChordInkRecognitionTargeting.batchTargets` now preserves original drawing order when extracting each batch target's `PKStroke`/`InkStroke` slice from a geometrically grouped cluster. Grouping may still use geometric/root-led order to find chord boundaries, but recognizer replay receives the same stroke sequence the single-target path would have received.
- Device diagnostics were expanded to log per-target `strokeBounds` in sequence and glyph candidate columns per payload. This is still DEBUG-only device observability; it does not change recognition decisions, UI, render timing, edit mode, barlines, ink persistence, sync, measure resize, OCR/Scribble, or Apple stroke-recognizer behavior.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-batch-stroke-order --filter 'ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 142 selected XCTest cases, 2 expected full-archive skips, 0 failures.
- `xcodegen generate`
- Result: project regenerated.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=42254D11-2E65-4586-AEBE-C6317AF2DD10' -resultBundlePath /tmp/iChartBatchStrokeOrder-20260825-1414.xcresult -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests/testChordBatchTargetingPreservesOriginalStrokeOrderInsideTargets test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartBatchStrokeOrder-20260825-1414.xcresult`
- Result: 1 total selected simulator test, 1 passed, 0 failed, 0 skipped.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-batch-stroke-order-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled'`
- Result: pass, 2 selected archive tests, 0 failures.
- Physical iPad Debug build: `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -allowProvisioningUpdates build`
- Result: pass, build succeeded.
- Physical iPad install/launch: installed and launched at 2026-08-25 14:15 PT.
- Physical iPad retest: user replayed the same `D` then `D-7` sequence on the freshly installed batch stroke-order build and reported the visible preview worked.
- Verification trace: `/tmp/chord-draft-preview-debug-after-batch-order-success.jsonl`, pulled at 2026-08-25 14:17 PT. The final clear replay showed single-target `D` previewing as renderable `D`; after the `D-7` batch recompute, target 0 still produced raw candidates `D`, `B`, `F`, supported candidate `D`, and preview replacement preserved previous `D` as renderable. Target 1 produced `D-7` as the winning supported candidate over close `B-7`, and preview replacement added renderable `D-7`. `unresolvedDraftCount` was `0`.
- Remaining nuance: the final replay's first target `D` was still below the trust threshold (`confidence: 0` in payload decision terms, with `D` as the only supported candidate and top score `3.6955`), so it is a previewable/confirmable read rather than a high-trust read. This is acceptable for this slice because the bug being verified was batch recompute stability, not final trust promotion.

D glyph rollback audit:

- Question: after the batch stroke-order fix, are the earlier D/B glyph fixes still necessary or harmful?
- Temporary check: copied the current checkout to `/tmp/ichart-d-glyph-revert-check`, disabled only the D/B glyph effects there, and ran the focused D/B/flat/trust slice.
- Result without the D/B glyph effects: one-stroke D regressed to `G`, top-first one-stroke D regressed to `G`, and screenshot-style two-stroke D regressed to `B`. Trust acceptance still passed, meaning the broad fixture set alone does not exercise these handwritten D shapes.
- Current-code confirmation: `swift test --scratch-path /tmp/iChartSwiftBuild-d-glyph-current-check --filter 'GestureTemplateRecognizerTests/testOneStrokeRootDIsRecognizedBeforeCurvedLookalikes|GestureTemplateRecognizerTests/testTopFirstOneStrokeRootDIsRecognizedBeforeCurvedLookalikes|GestureTemplateRecognizerTests/testNoisySingleBowlRootDDoesNotFallToB|GestureTemplateRecognizerTests/testScreenshotStyleTwoStrokeRootDDoesNotFallToB|GestureTemplateRecognizerTests/testTwoLobeRootBStillRanksBeforeD|GestureTemplateRecognizerTests/testCapturedBaseLetterFamiliesRankExpectedGlyphFirst|GestureTemplateRecognizerTests/testOneStrokeDHeuristicDoesNotStealFlatLoops|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
- Result with current code: pass, 8 selected XCTest cases, 0 failures.
- Decision: keep the D/B glyph fixes for now. The batch-order fix solved the `D` to `?` recompute bug, but the D/B glyph fixes still prevent separate D-to-G and D-to-B regressions. Known harm checks are covered by B fixtures, flat-loop negatives, trust acceptance, and the full archive gates already recorded above.

Replayable recognition trace architecture slice:

- Added `ChordInkRecognitionTrace`, a pure Swift trace model over DEBUG device-diagnostic JSONL events. It builds recognition passes from targeting, payload, and preview-replacement events without depending on editor UI state.
- Added invariants for the failure class observed on the iPad: a later batch pass must not drop a previously renderable preview read, and a target that had supported candidates in single-target mode must not lose all supported candidates when replayed in batch with the same stroke fingerprint.
- Added synthetic trace tests for three cases: building single/batch passes, detecting the old `D` then `D-7` batch replay regression, and accepting the fixed stable replay where the previous `D` remains renderable.
- Kept this slice as validation plumbing only. No recognizer scoring, lane UI, render timing, edit mode, barline rendering, ink persistence, sync, measure resize, OCR/Scribble, or Apple stroke-recognizer code changed.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-recognition-trace --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests'`
- Result: pass, 4 selected XCTest cases, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-recognition-trace-slice --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 79 selected XCTest cases, 2 expected full-archive skips, 0 failures.
- `xcodegen generate`
- Result: project regenerated.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=42254D11-2E65-4586-AEBE-C6317AF2DD10' -only-testing:iChartTests/ChordInkRecognitionTraceTests -only-testing:iChartTests/ChordDraftPreviewDeviceDiagnosticsTests -resultBundlePath /tmp/iChartRecognitionTraceTests-20260825143318.xcresult test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartRecognitionTraceTests-20260825143318.xcresult`
- Result: 4 total selected simulator tests, 4 passed, 0 failed, 0 skipped.
- Physical iPad validation: not rerun for this slice. This slice captures and tests the trace invariant; it does not make a new handwriting accuracy claim.

Full-pass iPad trace audit:

- Device trace pulled from Ben's iPad `com.ichart.app` at `/tmp/chord-draft-preview-debug-full-pass-20260825-211156.jsonl`.
- Saved selected chart state pulled at `/tmp/ichart-library-state-full-pass-20260825-211344.json`.
- Trace window: one reset at `2026-08-26T04:03:49Z`, 142 diagnostic events through `2026-08-26T04:09:46Z`, 39 recognition passes, 16 single-target passes, 23 batch passes.
- `ChordInkRecognitionTrace.stabilityIssues` returned zero issues for the pulled trace. No previously renderable read was dropped by later batch replay, and no same-fingerprint target lost all supported candidates during batch replay.
- Saved rendered chart model contained 12 chord events on the selected chart: `D`, `D-7`, `D°7`, `D/F#`, `Db-7`, `C7(b9)`, `G/B`, `Db7sus`, `E△7`, `F△7`, `Bb-7`, and `C7(#11)`.
- The saved `Db7sus` model is encoded as root `D`, accidental `b`, quality `sus`, extension `7`; `ChordSymbol.displayText` has a dedicated `7sus` branch, so this is expected to display as `Db7sus`.
- Six no-supported payloads occurred during partial/in-progress writing, then later resolved. These did not drop earlier renderable reads.
- One transient wrong primary candidate appeared while writing the fourth D-family slash chord: the trace showed `B/F#` before the later settled `D/F#`. The policy action for that pass was `confirm` with a close-race reason, not `trusted`. This is not a final rendered failure in this pass, but it is useful evidence for the next trace invariant: close root races in slash chords should remain visibly confirm/no-trust until the root evidence settles.
- Diagnostic terminology note: `acceptedText` in `ChordInkRecognitionDecision` and device payloads means the selected/previewable candidate text, even when `action == confirm`; trust analysis must use `action`, not `acceptedText`.
- Added skipped-by-default replay hook `ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues`, enabled by `ICHART_CHORD_DRAFT_TRACE_FILE`, so future pulled iPad traces can be checked by the Swift trace model instead of ad hoc scripts.

Validation:

- `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/chord-draft-preview-debug-full-pass-20260825-211156.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-device-trace-replay --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
- Result: pass, 1 selected XCTest case, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-trace-default-after-replay-hook --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests'`
- Result: pass, 5 selected XCTest cases, 1 expected skip for the opt-in device trace replay, 0 failures.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=42254D11-2E65-4586-AEBE-C6317AF2DD10' -only-testing:iChartTests/ChordInkRecognitionTraceTests -only-testing:iChartTests/ChordDraftPreviewDeviceDiagnosticsTests -resultBundlePath /tmp/iChartRecognitionTraceDeepLook-20260825211817.xcresult test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartRecognitionTraceDeepLook-20260825211817.xcresult`
- Result: 5 total selected simulator tests, 4 passed, 1 expected skip, 0 failed.
- Physical iPad status: this is a real pulled iPad trace audit and saved-chart model audit. It supports the specific 12 rendered chord events listed above; it does not yet cover unobserved acceptance-list cases such as every isolated `A-G` root, `F#7`, `C7alt`, or chord repeat.

Morning close-race trace observation slice:

- Date/time: 2026-08-26 07:44-07:53 PT.
- Environment: real checkout `/Users/benirossman/Documents/Smart Chart`, branch `codex/chord-recognition-accuracy`, HEAD `31bd35d54b279920f3583f131b030ee5bdc3c445` before this slice. Ben's iPad was attached and available as `376D59F8-92F2-5260-B10E-BA0BEAF941AB`; installed app was `com.ichart.app` version `1.1.7` build `49`.
- Source device trace: `/tmp/chord-draft-preview-debug-morning-20260826-074451.jsonl`, pulled from the physical iPad app container. Saved selected chart state: `/tmp/ichart-library-state-morning-20260826-074451.json`.
- Added `ChordInkRecognitionTrace.observations` and `ChordInkRecognitionTraceObservationKind.closeRacePrimaryCandidateChanged`. This is warning-level review evidence, not a failing invariant.
- Observation identity uses the stable target slot context available in the DEBUG device payload: target index plus measure/system context and a coarse lane-fraction bucket. It intentionally does not rely only on exact stroke-bounds fingerprinting, because the real `D/F#` target's bounds shifted while the same ten-stroke batch slot was recomputed.
- The observation triggers only when two passes for the same target slot have overlapping supported candidates, both are held as `confirm` close races, and the selected primary candidate changes. This preserves the trust rule: volatile close races are not promoted to trusted reads.
- Real trace evidence: while writing the fourth first-row D-family slash chord, target index `3` in measure `A2F45418-9953-427A-B2C0-7E72038756E0` changed from selected `B/F#` at `2026-08-26T04:05:46Z` to selected `D/F#` at `2026-08-26T04:05:56Z`. Both passes had `strokeCount: 10`, overlapping supported candidates containing both `B/F#` and `D/F#`, and `action: confirm` with `closeRace: true`.
- This confirms the next architectural problem to inspect is root-stability evidence under close supported races, not another immediate UI/render patch. It does not mean `B/F#` would have rendered without explicit user action.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-close-race-trace --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests'`
- Result: pass, 9 selected XCTest cases, 2 expected opt-in skips, 0 failures.
- `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/chord-draft-preview-debug-morning-20260826-074451.jsonl ICHART_CHORD_DRAFT_TRACE_EXPECT_CLOSE_RACE_OBSERVATION=1 swift test --scratch-path /tmp/iChartSwiftBuild-close-race-device-trace --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues|ChordInkRecognitionTraceTests/testProvidedDeviceTraceSurfacesExpectedCloseRaceObservations'`
- Result: pass, 2 selected XCTest cases, 0 failures. This proves the pulled iPad trace has zero hard stability issues and at least one expected close-race candidate-change observation.
- `swift test --scratch-path /tmp/iChartSwiftBuild-close-race-slice --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
- Result: pass, 84 selected XCTest cases, 4 expected opt-in/full-archive skips, 0 failures.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-close-race-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
- Result: pass, 3 selected archive/trust XCTest cases, 0 failures.
- `xcodegen generate`
- Result: project regenerated.
- First simulator rerun after the reset-boundary test hit the known simulator launch/preflight `Busy` environment failure on `42254D11-2E65-4586-AEBE-C6317AF2DD10`; result bundle `/tmp/iChartCloseRaceTrace-20260826-075601.xcresult` selected only the launcher error, with 0 passed tests and 1 launcher failure. No product-test failure is claimed from that run.
- Controlled retry: `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -only-testing:iChartTests/ChordInkRecognitionTraceTests -only-testing:iChartTests/ChordDraftPreviewDeviceDiagnosticsTests -resultBundlePath /tmp/iChartCloseRaceTrace-20260826-075701.xcresult test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartCloseRaceTrace-20260826-075701.xcresult`
- Result: 9 total selected simulator tests, 7 passed, 2 expected opt-in skips, 0 failed.
- Scope note: no production recognizer scoring, glyph template, grouping, lane UI, render commit, edit mode, barline rendering, ink persistence, sync, measure resize, OCR/Scribble, or Apple stroke-recognizer behavior changed in this slice.

Root-glyph trust gate slice:

- Date/time: 2026-08-26 08:04-08:09 PT.
- Source evidence: the morning iPad trace showed the same target slot changing selected primary text from `B/F#` to `D/F#` while both passes were `confirm` close races and shared overlapping supported candidates. The problem was not a final render mutation; it was evidence that whole-chord score can look decisive while the first glyph column still contains unstable root evidence.
- Change scope: `ChordInkRecognitionPolicy` now confirms an accepted rooted chord when the accepted root glyph has a close or stronger alternate `A-G` root in the first glyph candidate column. It preserves trusted behavior when the accepted root glyph is clearly ahead, even with an alternate supported chord score present.
- This is a trust gate, not a glyph-template or UI patch. It does not change grouping, lane preview UI, render commit timing, edit mode, barline rendering, ink persistence, sync, measure resize, OCR/Scribble, or Apple stroke-recognizer behavior.

Validation:

- Red focused gate before implementation: `swift test --scratch-path /tmp/iChartSwiftBuild-root-race-red --filter 'ChordInkRecognizerTests/testResolutionPolicyPromptsWhenRootGlyphRaceIsCloseDespiteDecisiveChordScore'`
- Result: failed as expected because the previous policy returned `trusted` and did not flag the root race.
- Focused green contract: `swift test --scratch-path /tmp/iChartSwiftBuild-root-race-contract --filter 'ChordInkRecognizerTests/testResolutionPolicyPromptsWhenRootGlyphRaceIsCloseDespiteDecisiveChordScore|ChordInkRecognizerTests/testResolutionPolicyTrustsWhenAcceptedRootGlyphIsClearDespiteAlternateChordScore'`
- Result: pass, 2 selected XCTest cases, 0 failures.
- Broad recognition/editor slice: `swift test --scratch-path /tmp/iChartSwiftBuild-root-race-slice --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordInkRenderResolutionPolicyTests|ChordInkUserCorrectionMemoryTests'`
- Result: pass, 97 selected XCTest cases, 4 expected opt-in/full-archive skips, 0 failures.
- Full archive gate: `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-root-race-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
- Result: pass, 3 selected archive/trust XCTest cases, 0 failures.
- `xcodegen generate`
- Result: project regenerated.
- First simulator run on `0D3454BE-1A21-4910-8FD6-FFD3EB43E908` wrote `/tmp/iChartRootRacePolicy-20260826-080730.xcresult` but failed before real tests launched with simulator preflight `Busy`. `xcresulttool` showed 1 launcher failure, 0 passed tests, and 0 skipped tests, so no product-test failure is claimed.
- Controlled simulator retry after explicit boot: `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -only-testing:iChartTests/ChordInkRecognizerTests -only-testing:iChartTests/ChordInkRecognitionTraceTests -only-testing:iChartTests/ChordDraftPreviewDeviceDiagnosticsTests -only-testing:iChartTests/ChordInkRenderResolutionPolicyTests -only-testing:iChartTests/ChordInkUserCorrectionMemoryTests -resultBundlePath /tmp/iChartRootRacePolicy-20260826-080850.xcresult test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartRootRacePolicy-20260826-080850.xcresult`
- Result: 73 total selected simulator tests, 70 passed, 3 expected opt-in/full-archive skips, 0 failed.
- Physical iPad Debug build: `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -allowProvisioningUpdates build`
- Result: pass, build succeeded with Apple Development signing.
- Physical iPad install/launch: installed and launched on Ben's iPad at 2026-08-26 08:10 PT.
- Device-container repair note: while trying to reset only the draft-preview JSONL through `devicectl`, `Library/Application Support/iChart` was briefly replaced by a zero-byte file. The directory was restored with `--remove-existing-content true` against the exact `Library/Application Support/iChart` path, and `library-state.json` was restored from `/tmp/ichart-library-state-morning-20260826-074451.json`. A post-repair pull at `/tmp/ichart-library-state-post-repair-20260826-0814.json` matched the backup byte-for-byte, and the draft-preview trace was confirmed empty. No local `/tmp` backups were found for correction memory, telemetry queue, chord-entry diagnostics, or PDF-library files, so do not claim those app-support files were preserved if they existed before this reset attempt.
- Trace reset instruction: do not copy a file to `Library/Application Support/iChart` as a destination. Use the in-app canvas reset path, or copy a prepared directory to the exact `Library/Application Support/iChart` path only when repairing the directory itself.
- Physical iPad replay status: pending. Do not claim final handwriting accuracy from this gate until a fresh device pass is performed and the trace is pulled/replayed.

Physical root-race retest:

- Observed on physical iPad from user report on 2026-08-26: the full pass behaved well except a deliberately loose handwritten `D/F#` read visually as `B/F#`; a handwritten `B/F#` written next to it served as the control.
- Source device trace: `/tmp/chord-draft-preview-debug-root-race-retest-20260826-081942.jsonl`, pulled from the physical iPad app container. Saved chart state: `/tmp/ichart-library-state-root-race-retest-20260826-081942.json`.
- Trace facts: 17 JSONL events beginning with reset at `2026-08-26T15:17:08Z`. Targeting remained stable as chords were added: one target, then two, then three, then four. No hard trace stability issue was found.
- The standalone `D` target stayed `confirm`, not trusted: accepted text `D`, confidence `3.7518`, supported candidates `D|B`, first glyph `D:0.7518` vs `B:0.6994`.
- The `D-7` target stayed `confirm`, not trusted: accepted text `D-7`, confidence `4.1579`, supported candidates `D-7|B-7`, first glyph `D:0.7737` vs `B:0.6993`.
- The loose `D/F#` target selected primary `B/F#`, but policy action was `confirm`, not `trusted`. Supported candidates included `B/F#|D/F#|B/B#|D/B#|F/F#|F/B#`; top chord scores were extremely close: `B/F#` `5.0620` vs `D/F#` `5.0508`. The first glyph was also a close root race: `B:0.7022` vs `D:0.6570`.
- The control `B/F#` target selected `B/F#` and was `trusted`. Its first glyph had strong `B` evidence from the heuristic path: `B:0.9870` vs `D:0.6576`.
- Interpretation: the root-glyph trust gate worked for the loose `D/F#` case because the wrong primary candidate was held for confirmation. The remaining issue is primary candidate ordering for loose `D` versus `B`, not an implicit render-trust failure and not a batch-targeting drop.
- Do not tune the `D`/`B` scorer from this trace alone. This pulled trace records bounds and glyph/candidate scores, but not point-level physical ink from the bad sample.

Replayable device stroke capture slice:

- Added DEBUG-only `inkStrokes` to draft-preview diagnostic targets and recognition payloads. These stay in the local device JSONL diagnostics path and are not production telemetry.
- Added `ChordInkRecognitionTrace.replayableTargets`, plus fixture export helpers that take a user-supplied intended chord. This is deliberately not automatic: a wrong primary such as `B/F#` must not become the expected fixture label unless the user actually intended `B/F#`.
- Backward compatibility is required: existing bound-only traces remain loadable and simply produce no replayable targets.
- Next device protocol: install a fresh Debug build containing this slice, reset the local draft-preview trace, write only a deliberately loose `D/F#` plus a clean `B/F#` control, pull the JSONL, verify `ChordInkRecognitionTrace.stabilityIssues == []`, then export the loose `D/F#` target as a named fixture such as `DSlashFSharpLooseDevice01` if the point-level data confirms a transferable D/B root-shape failure.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-trace-export-hook --filter 'ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognitionTraceTests'`
- Result: pass, 13 selected XCTest cases, 3 expected opt-in trace skips, 0 failures.
- `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/chord-draft-preview-debug-root-race-retest-20260826-081942.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-trace-old-jsonl-compat --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
- Result: pass, 1 selected XCTest case, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-trace-export-slice --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordInkRenderResolutionPolicyTests|ChordInkUserCorrectionMemoryTests|ChordInkSequentialGrouperTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests'`
- Result: pass, 122 selected XCTest cases, 5 expected opt-in/full-archive skips, 0 failures.
- `git diff --check`
- Result: pass.
- `xcodegen generate`
- Result: project regenerated.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -resultBundlePath /tmp/iChartTraceExportHook-20260826-0835.xcresult -only-testing:iChartTests/ChordInkRecognitionTraceTests -only-testing:iChartTests/ChordDraftPreviewDeviceDiagnosticsTests -only-testing:iChartTests/ChordInkRecognizerTests/testResolutionPolicyPromptsWhenRootGlyphRaceIsCloseDespiteDecisiveChordScore -only-testing:iChartTests/ChordInkRecognizerTests/testResolutionPolicyTrustsWhenAcceptedRootGlyphIsClearDespiteAlternateChordScore test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartTraceExportHook-20260826-0835.xcresult --format json`
- Result: 15 total selected simulator tests, 12 passed, 3 expected opt-in skips, 0 failed.
- Physical iPad Debug build: `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartTraceReplayableStrokesDeviceDerived-20260826-0832 -allowProvisioningUpdates build`
- Result: pass, build succeeded with Apple Development signing. Existing unrelated warnings remain in `LibraryView.swift` and `IChartTelemetry.swift`.
- Physical iPad install/launch: installed and launched on Ben's iPad at 2026-08-26 08:32 PT.
- Trace reset note: after install/launch, `Library/Application Support/iChart/chord-draft-preview-debug.jsonl` still showed the older 08:18 timestamp, so do not claim the trace was cleared by launch alone. The next pull must filter by new timestamps and confirm that new events include `inkStrokes`.

Replayable stroke retest verification:

- Date/time: 2026-08-26 08:42-08:47 PT.
- Source device trace: `/tmp/chord-draft-preview-debug-trace-strokes-pass-20260826-084316.jsonl`, pulled from the physical iPad app container. Saved chart state: `/tmp/ichart-library-state-trace-strokes-pass-20260826-084316.json`.
- Trace facts: 12 JSONL events after a clean reset at `2026-08-26T15:42:21Z`: targeting, single-target recognition, preview replacement, another single-target recognition, preview replacement, then final batch recognition and preview replacement.
- Standalone `D` read as `D` and was held for confirmation, not trust: confidence `3.7949`, supported candidates `D|B`, first-glyph race `D:0.7949` vs `B:0.7480`.
- The loose intended `D/F#` read as primary `D/F#` and was held for confirmation, not trust: confidence `4.9473`, supported candidates `D/F#|B/F#|D9(#5)|F/F#|B9(#5)|F9(#5)`, close candidate score `B/F#:4.9356`, confidence gap `0.0469`, first-glyph race `D:0.7949` vs `B:0.7480`.
- After adding the control `B/F#`, final batch targeting produced exactly two targets: target 0 retained the loose `D/F#` with 14 captured ink strokes; target 1 read the control `B/F#` with 10 captured ink strokes and was trusted.
- Final preview replacement had `draftCount: 2`, `unresolvedDraftCount: 0`, and preserved target 0 as `D/F#` while adding target 1 as `B/F#`. This verifies left-target stability for this pass.
- Saved selected chart state had no committed `chordEvents`, while handwritten chord data remained present. This is expected when the pass only validates draft preview and the user has not explicitly tapped Render Chords.
- Exported replayable fixture candidate: `/tmp/DSlashFSharpLooseDevice01.json`, intended display text `D/F#`, expected cluster count `4`, expected top glyphs `D`, `/`, `F`, `#`, stroke count `14`. Promoted into the repository fixture archive in the following slice.

Validation:

- `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/chord-draft-preview-debug-trace-strokes-pass-20260826-084316.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-trace-strokes-device-replay-verify --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
- Result: pass, 1 selected XCTest case, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-current-trace-verify --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognizerTests/testResolutionPolicyPromptsWhenRootGlyphRaceIsCloseDespiteDecisiveChordScore|ChordInkRecognizerTests/testResolutionPolicyTrustsWhenAcceptedRootGlyphIsClearDespiteAlternateChordScore'`
- Result: pass, 15 selected XCTest cases, 3 expected opt-in trace skips, 0 failures.
- `git diff --check`
- Result: pass.
- Live-code boundary check: `rg -n "OCR|VNRecognize|ChordRecognitionTrustArbiter|PKStrokeRecognizer" iChart iChartTests` found only the provider-boundary test's forbidden-term list. `rg -n "Scribble" iChart iChartTests` found manual text/account-field surfaces and tests only, not the chord-lane recognition path.
- Interpretation: the current trace layer worked as intended. The observed loose `D/F#` is no longer a wrong primary in this pulled point-level trace, remains correctly confirm-gated because of a close `B/F#` race, and does not destabilize after a true `B/F#` control is added. This is targeted device evidence, not final acceptance for the full handwritten vocabulary.

Loose D/F# replay fixture promotion:

- Date/time: 2026-08-26 08:51-08:53 PT.
- Added `/Users/benirossman/Documents/Smart Chart/iChartTests/Fixtures/Ink/DSlashFSharpLooseDevice01.json` from the exported physical-iPad trace target. The fixture keeps the user-stated intended display text `D/F#`, not any wrong or alternate recognizer candidate.
- Added `DSlashFSharpLooseDevice01` to `InkFixtureLoader.trustAcceptanceFixtureNames` and to the slash-bass separator clustering spot check.
- Added a focused trust-acceptance regression asserting the intended loose `D/F#` remains the primary recognized display text, ranks above `B/F#`, keeps four glyph clusters `D`, `/`, `F`, `#`, and stays `confirm` with close-race root competitor `B`.
- Scope note: this slice adds replay evidence and tests only. It does not change recognizer scoring, glyph templates, grouping, lane UI, render timing, edit mode, barline rendering, ink persistence, sync, measure resize, OCR/Scribble, or Apple stroke-recognizer behavior.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-dslash-loose-fixture --filter 'ChordInkTrustAcceptanceTests|InkFixtureLoaderTests|StrokeClustererTests/testSlashBassKeepsSlashAsSeparatorCluster'`
- Result: pass, 7 selected XCTest cases, 0 failures.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-dslash-loose-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkTrustAcceptanceTests'`
- Result: pass, 6 selected archive/trust XCTest cases, 0 failures.
- `xcodegen generate`
- Result: project regenerated.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -resultBundlePath /tmp/iChartDSlashFSharpLooseFixture-20260826-0853.xcresult -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/InkFixtureLoaderTests -only-testing:iChartTests/StrokeClustererTests/testSlashBassKeepsSlashAsSeparatorCluster test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartDSlashFSharpLooseFixture-20260826-0853.xcresult --format json`
- Result: 7 total selected simulator tests, 7 passed, 0 failed, 0 skipped.
- `git diff --check`
- Result: pass.

Pre-push local verification pass:

- Date/time: 2026-08-26 09:00-09:05 PT.
- Checkout: `/Users/benirossman/Documents/Smart Chart` on `codex/chord-recognition-accuracy`, with the current uncommitted recognition/trace/doc fixture surface under verification.
- Scope audit:
  - `git diff --check`
  - Result: pass.
  - `rg -n "OCR|VNRecognize|ChordRecognitionTrustArbiter|PKStrokeRecognizer" iChart iChartTests`
  - Result: only the provider-boundary test's forbidden-term list matched.
  - `rg -n "Scribble" iChart iChartTests`
  - Result: manual text/account-field surfaces and tests matched; no chord-lane recognition provider matched.
- Focused recognition/trace Swift gate:
  - `swift test --scratch-path /tmp/iChartSwiftBuild-recognition-trust-final --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|StrokeClustererTests|ChordInkSymbolLedgerTests|InkFixtureLoaderTests|InkFixtureCoverageTests|ChordEntryPassReplayTests|ChordInkSequentialGrouperTests|ChordInkRenderResolutionPolicyTests|ChordInkRecognitionSessionTests|ChordInkDraftPreviewTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognitionTraceTests'`
  - Result: pass, 205 selected XCTest cases, 39 expected opt-in/full-archive skips, 0 failures.
- Full archive/trust Swift gate:
  - `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-recognition-trust-full-final --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|StrokeClustererTests|ChordInkSymbolLedgerTests|InkFixtureLoaderTests|InkFixtureCoverageTests|ChordEntryPassReplayTests|ChordInkSequentialGrouperTests|ChordInkTrustAcceptanceTests'`
  - Result: pass, 188 selected XCTest cases, 33 expected retired coverage-count or opt-in state-replay skips, 0 failures. Full archive recognition, glyph top-three, and clusterer tests were active and passed.
- Device trace replay gates:
  - `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/chord-draft-preview-debug-trace-strokes-pass-20260826-084316.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-device-trace-final --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
  - Result: pass, 1 selected XCTest case, 0 failures.
  - `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/chord-draft-preview-debug-morning-20260826-074451.jsonl ICHART_CHORD_DRAFT_TRACE_EXPECT_CLOSE_RACE_OBSERVATION=1 swift test --scratch-path /tmp/iChartSwiftBuild-device-trace-close-race-final --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues|ChordInkRecognitionTraceTests/testProvidedDeviceTraceSurfacesExpectedCloseRaceObservations'`
  - Result: pass, 2 selected XCTest cases, 0 failures.
- Project generation:
  - `xcodegen generate`
  - Result: project regenerated. `git status --short -- iChart.xcodeproj project.yml` showed no tracked project/config churn.
- Simulator XCTest gate:
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -resultBundlePath /tmp/iChartRecognitionFinal-20260826.xcresult -only-testing:iChartTests/ChordInkSequentialGrouperTests -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/ChordRecognitionProviderBoundaryTests -only-testing:iChartTests/ChordDraftPreviewDeviceDiagnosticsTests -only-testing:iChartTests/ChordInkRecognitionTraceTests -only-testing:iChartTests/ChordInkRecognizerTests/testResolutionPolicyPromptsWhenRootGlyphRaceIsCloseDespiteDecisiveChordScore -only-testing:iChartTests/ChordInkRecognizerTests/testResolutionPolicyTrustsWhenAcceptedRootGlyphIsClearDespiteAlternateChordScore -only-testing:iChartTests/StrokeClustererTests/testSlashBassKeepsSlashAsSeparatorCluster test`
  - Result: pass.
  - `xcrun xcresulttool get test-results summary --path /tmp/iChartRecognitionFinal-20260826.xcresult --format json`
  - Result: 27 total selected simulator tests, 24 passed, 3 expected opt-in trace skips, 0 failed.
- Physical iPad build/install smoke:
  - Device: Ben's iPad `376D59F8-92F2-5260-B10E-BA0BEAF941AB`, connected.
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartRecognitionDeviceFinal-20260826-0903 -allowProvisioningUpdates build`
  - Result: pass, build succeeded with Apple Development signing. Existing unrelated `IChartTelemetry.swift` main-actor warnings remain.
  - `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartRecognitionDeviceFinal-20260826-0903/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, `com.ichart.app` installed.
  - `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB com.ichart.app`
  - Result: pass, launched application with `com.ichart.app` bundle identifier.
- Remaining acceptance gap: a fresh handwritten physical-iPad acceptance pass and pulled trace/library-state audit are still required before checking the final physical validation item or claiming branch-level chord accuracy complete.

Base-letter grouping-regression correction:

- Date/time: 2026-08-26 09:58-10:20 PT.
- Observed on physical iPad from user report: a later full pass failed badly on base letters. `A` did not read, `B` read, later writing caused earlier unresolved/readable base-letter previews to collapse into `Bb`, and `G` became `F-`.
- Source device trace: `/tmp/chord-draft-preview-debug-base-letter-failure-20260826-0958.jsonl`, pulled from the physical iPad app container. Saved chart state: `/tmp/ichart-library-state-base-letter-failure-20260826-0958.json`.
- Trace facts: 36 JSONL events after reset at `2026-08-26T16:55:24Z`; installed app was `com.ichart.app` version `1.1.7` build `49`.
- Layer classification:
  - Not OCR, Scribble, or `PKStrokeRecognizer`.
  - Not rendered chart mutation; this happened in the draft-preview path before explicit Render Chords.
  - Not primarily preview replacement; preview replacement surfaced the result, but the incorrect target contents were already present.
  - Root cause class is grouping/root-role boundary authority plus glyph evidence feeding that boundary.
- Detailed trace interpretation:
  - `A` no-read was a glyph-evidence problem: the A-shaped input did not produce a supported A-root candidate strongly enough to compose a chord.
  - `B` read correctly as a standalone root.
  - `C` read correctly at first, but its glyph candidate column was close enough to a flat lookalike (`b` slightly above heuristic `C`) that a later batch pass grouped `B` and `C` into one target and composed `Bb`.
  - `G` becoming `F-` showed the same architectural failure class: a detached root-like glyph with a strong minor-suffix lookalike was swallowed into the previous `F` group and composed as `F-`.
- Suspect change confirmed in code review: the installed Debug build included the new theory-role context architecture, and `ChordInkSequentialGrouper` had been relying on theory role `opensChordGroup` decisions for group starts. That gave suffix/modifier interpretations too much authority over sequential chord boundaries.
- Corrective architecture change: restore grouping as an independent root-led detector with geometric detachment and slash-bass protection. `ChordInkTheoryRoleContext` remains available for semantic candidate/composer/trust work, but it must not be the sole authority for opening chord groups. Detached root-sized close races such as `b` versus heuristic `C` and `m` versus heuristic `G` can open a new group; attached flat/minor lookalikes stay inside the active chord; strong extension leads such as `9` over heuristic `C` do not create fake C groups.
- Scope note: this correction changes pure recognition grouping only. It does not change chord lane UI, draft preview timing, edit mode, barline rendering, ink persistence, sync, measure resize, terminal barline behavior, OCR/Scribble, or Apple stroke-recognizer behavior.

Validation:

- `swift test --scratch-path /tmp/iChartSwiftBuild-root-start-detector12 --filter 'ChordInkSequentialGrouperTests|ChordInkTheoryRoleContextTests|StrokeClustererTests/testSlashBassKeepsSlashAsSeparatorCluster'`
- Result: pass, 25 selected XCTest cases, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-base-letter-root-start-slice --filter 'ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordInkSequentialGrouperTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests'`
- Result: pass, 117 selected XCTest cases, 5 expected opt-in/full-archive skips, 0 failures.
- `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/chord-draft-preview-debug-base-letter-failure-20260826-0958.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-base-letter-failure-trace-final --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
- Result: pass, 1 selected XCTest case, 0 failures. This proves no hard trace-model stability issue in the pulled trace; it does not prove fixed recognition for that old already-targeted trace.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-full-ink-after-root-boundary-fix --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled'`
- Result: pass, 2 selected archive XCTest cases, 0 failures.
- `xcodegen generate`
- Result: project regenerated.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartDerived-root-boundary-xcode-20260826-1019 -resultBundlePath /tmp/iChartRootBoundaryRecognition-20260826-1019.xcresult -only-testing:iChartTests/ChordInkRecognitionTraceTests -only-testing:iChartTests/ChordDraftPreviewDeviceDiagnosticsTests -only-testing:iChartTests/ChordInkRecognizerTests -only-testing:iChartTests/GestureTemplateRecognizerTests -only-testing:iChartTests/ChordInkTrustAcceptanceTests -only-testing:iChartTests/ChordRecognitionProviderBoundaryTests -only-testing:iChartTests/ChordInkSequentialGrouperTests -only-testing:iChartTests/ChordInkTheoryRoleContextTests -only-testing:iChartTests/ChordInkSemanticGlyphContextualizerTests test`
- Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartRootBoundaryRecognition-20260826-1019.xcresult`
- Result: 117 total selected simulator tests, 112 passed, 5 expected opt-in/full-archive skips, 0 failed.
- Physical iPad status: pending fresh Debug install/retest after this correction. Required next pass is isolated base roots `A B C D E F G`, then the adjacent-root collapse cases `B C` and `F G`, then slash-bass control `D/F# B/F#`.
- Physical iPad build/install attempt: Ben's iPad was connected, but two `xcodebuild` device-build attempts against `/tmp/iChartRootBoundaryDevice-20260826-1021` wedged at `/usr/bin/codesign` after compilation. Both attempts were interrupted rather than installing an incomplete product. `codesign --verify --deep --strict --verbose=2 /tmp/iChartRootBoundaryDevice-20260826-1021/Build/Products/Debug-iphoneos/iChart.app` reported `code object is not signed at all`, so no fresh physical-device install is claimed for this correction yet.
- Follow-up after Apple sign-in: `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartRootBoundaryDevice-20260826-1034 -allowProvisioningUpdates build`
- Result: pass, build succeeded with Apple Development signing.
- `codesign --verify --deep --strict --verbose=2 /tmp/iChartRootBoundaryDevice-20260826-1034/Build/Products/Debug-iphoneos/iChart.app`
- Result: pass, signed app valid on disk and satisfied its designated requirement. Bundle metadata: `com.ichart.app`, version `1.1.7`, build `49`.
- `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartRootBoundaryDevice-20260826-1034/Build/Products/Debug-iphoneos/iChart.app`
- Result: pass, installed `com.ichart.app`.
- `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB com.ichart.app`
- Result: pass, launched `com.ichart.app`.
- `xcrun devicectl device info apps --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB`
- Result: device-side app listing confirmed `iChart`, bundle `com.ichart.app`, version `1.1.7`, bundle version `49`.
- Diagnostic file status immediately after launch: `Library/Application Support/iChart/chord-draft-preview-debug.jsonl` still showed the old 2026-08-26 09:56 PT file. This is expected if the launched app has not opened/recreated the editor canvas yet; do not treat the old file as the fresh retest trace. The next pull must confirm a new `stage:"reset"` row after the editor opens.

A-root construction correction:

- Date/time: 2026-08-26 11:03-11:13 PT.
- Observed on physical iPad from user report: after the rebuild loaded correctly, isolated base letters were still unstable; `A` did not read and `B` read, so the user stopped before writing more letters.
- Source device trace: `/tmp/ichart-a-root-regression-20260826-1105/chord-draft-preview-debug.jsonl`, pulled from the physical iPad app container.
- Trace facts:
  - The `A` input reached recognition as one target with three strokes.
  - Barline count was zero and invisible-stroke filtering was not involved.
  - The recognizer split the target into three glyph columns instead of one root glyph: the left leg ranked as `1`/slash/`9`, the crossbar ranked as `-`, and the right leg ranked as `1`/`7`.
  - The resulting raw candidates were unsupported `1-1`, `1m1`, `1-7`, and related strings, so the preview correctly showed no reliable read rather than a wrong rendered chord.
- Layer classification:
  - Not OCR, Scribble, or `PKStrokeRecognizer`.
  - Not lane UI or preview replacement.
  - Not draft barline removal.
  - Root cause class is intra-target glyph clustering plus root-shaped `A` evidence losing to suffix-number/line evidence.
- Corrective architecture change:
  - `StrokeClusterer` now has a strict root-`A` construction merge for two opposing diagonal legs that meet near the top and spread at the bottom. This lets a three-stroke `A` behave as one glyph before candidate composition.
  - `GestureTemplateRecognizer` now adds high-confidence constructed-root `A` evidence when a root-sized `A` frame has a middle crossbar. This protects both split-leg `A` input and existing continuous-body captured `A` input from being outranked by `5`, `1`, slash, or `-` suffix lookalikes.
  - The change is shape/role based, not a blanket `A` boost.
- Fixture update:
  - Added `iChartTests/Fixtures/Ink/ARootSplitDevice01.json` from the pulled device trace using the existing `ChordInkRecognitionTrace` fixture exporter. The expected chord comes from the user's stated intended input: `A`.
  - Added the fixture to the trust acceptance set.
- Scope note: this correction changes pure recognition clustering/glyph evidence only. It does not change chord lane UI, draft preview timing, edit mode, barline rendering, ink persistence, sync, measure resize, terminal barline behavior, OCR/Scribble, or Apple stroke-recognizer behavior.

Validation:

- Trace replay gate before code changes:
  - `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-a-root-regression-20260826-1105/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-current-trace-a-root-env --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
  - Result: pass, 1 selected XCTest case, 0 failures. This proves the pulled trace had no prior-renderable-drop stability failure; it does not mean the no-read was acceptable.
- Red focused gate before implementation:
  - `swift test --scratch-path /tmp/iChartSwiftBuild-a-root-red --filter 'StrokeClustererTests/testThreeStrokeRootACapturesLegsAndCrossbarAsOneGlyph|GestureTemplateRecognizerTests/testCapturedBaseLetterFamiliesRankExpectedGlyphFirst|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
  - Result: failed as expected. `ARootSplitDevice01` split into three clusters and did not match `A`; `ACaptured01` ranked `5` above `A`.
- Green focused gate after implementation:
  - `swift test --scratch-path /tmp/iChartSwiftBuild-a-root-green2 --filter 'StrokeClustererTests/testThreeStrokeRootACapturesLegsAndCrossbarAsOneGlyph|GestureTemplateRecognizerTests/testCapturedBaseLetterFamiliesRankExpectedGlyphFirst|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
  - Result: pass, 3 selected XCTest cases, 0 failures.
- Recognition slice gate:
  - `swift test --scratch-path /tmp/iChartSwiftBuild-a-root-focused --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|StrokeClustererTests|ChordInkSequentialGrouperTests|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests'`
  - Result: pass, 179 selected XCTest cases, 6 expected opt-in/full-archive skips, 0 failures.
- Full archive gate:
  - `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-a-root-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
  - Result: pass, 4 selected XCTest cases, 0 failures.
- Project generation:
  - `xcodegen generate`
  - Result: project regenerated. `git diff --check` passed and `git status --short -- iChart.xcodeproj project.yml` showed no tracked project/config churn.
- Physical iPad Debug build/install:
  - Device: Ben's iPad `376D59F8-92F2-5260-B10E-BA0BEAF941AB`, connected.
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartARootDevice-20260826-1114 -allowProvisioningUpdates build`
  - Result: pass, build succeeded with Apple Development signing. Existing unrelated `LibraryView.swift` deprecation and `IChartTelemetry.swift` main-actor warnings remain.
  - `codesign --verify --deep --strict --verbose=2 /tmp/iChartARootDevice-20260826-1114/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, signed app valid on disk and satisfied its designated requirement. Bundle metadata: `com.ichart.app`, version `1.1.7`, build `49`.
  - `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartARootDevice-20260826-1114/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, installed `com.ichart.app`.
  - `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB --terminate-existing com.ichart.app`
  - Result: pass, launched `com.ichart.app`.
  - `xcrun devicectl device info apps --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB`
  - Result: device-side app listing confirmed `iChart`, bundle `com.ichart.app`, version `1.1.7`, bundle version `49`.
- Physical iPad status: ready for fresh retest after this correction. Required next pass should begin with isolated `A`, `B`, and `C`, then continue through `D E F G`, and then recheck adjacent-root collapse controls `B C` and `F G`.

C/D detached-root absorption correction:

- Date/time: 2026-08-26 11:27-11:33 PT.
- Observed on physical iPad from user report: after the A-root rebuild, `A` began reading, but writing a later detached `D` caused an earlier `C` preview to become `Cb`. The user specifically noted that no flat mark was written near the `C`.
- Source device trace: `/tmp/ichart-c-to-cb-regression-20260826/chord-draft-preview-debug.jsonl`, pulled from the physical iPad app container.
- Trace facts:
  - `A` and `B` were stable and trusted in the pulled pass.
  - `C` first reached recognition as a one-stroke target and produced accepted text `C`.
  - After the later `D` was written, the targeter produced a widened target containing the old `C` stroke plus two `D` strokes. It did not produce a separate fourth target for the new `D`.
  - The widened target's glyph columns were `C` followed by a close-race second glyph with `D`, `B`, triangle, and `b` evidence. Candidate composition then supported `Cb`, `C△`, `Gb`, and `G△`; policy correctly held the result as confirmation because confidence was low, but the visible draft identity had still changed.
  - Preview replacement did not literally log an in-place `C` to `Cb` replacement for the same anchor bucket. The target's widened bounds shifted the anchor, so the previous `C` slot disappeared and a new `Cb` slot appeared. Product behavior is still a retroactive identity change caused by target absorption.
- Layer classification:
  - Not OCR, Scribble, or `PKStrokeRecognizer`.
  - Not rendered chart mutation; this remained in draft preview before explicit Render Chords.
  - Not primarily a flat-glyph scoring bug. The flat candidate appeared because the detached `D` strokes were incorrectly inside the `C` target.
  - Root cause class is grouping/targeting boundary proof: a detached root-sized but lower-confidence `D` after an existing chord was not strong enough to start a new group under the previous single root-start threshold.
- Corrective architecture change:
  - `ChordInkSequentialGrouper` now uses independent root-start evidence with separate thresholds for an initial root and a later detached root. A later detached root-sized `A-G` glyph can start the next group at lower confidence when it is geometrically separated from the active group.
  - Slash-bass protection remains in the root-start detector, so a bass root after `/` stays inside the active chord.
  - Suffix/modifier pressure and attached-lookalike checks remain active, so attached `b`, `m`, `7`, `9`, `13`, alteration marks, and parentheses do not become fake roots.
  - Group source indexes are sorted before `PKDrawing` slicing, preserving original drawing order inside targets.
  - `ChordInkRecognitionTrace` now flags target absorption when a later target contains a previously readable target's stroke fingerprint plus detached right-side strokes and changes supported chord identity. Attached accidental expansion is explicitly allowed.
- Scope note: this correction changes pure recognition grouping and trace invariants only. It does not change chord lane UI, draft preview timing, edit mode, barline rendering, ink persistence, sync, measure resize, terminal barline behavior, OCR/Scribble, or Apple stroke-recognizer behavior.

Validation:

- Focused grouping/trace gate:
  - `swift test --scratch-path /tmp/iChartSwiftBuild-c-d-root-boundary-focused --filter 'ChordInkSequentialGrouperTests/testDetachedLowConfidenceRootSizedDStartsNextGroupAfterC|ChordInkSequentialGrouperTests/testDeviceCThenDetachedDStaysAsSeparateSequentialGroups|ChordInkSequentialGrouperTests/testDetachedNineLookalikeDoesNotStartFakeCGroup|ChordInkSequentialGrouperTests/testAttachedFlatLookalikeDoesNotStartNextGroup|ChordInkRecognitionTraceTests/testDetectsDetachedTargetAbsorbingPreviouslyReadableTarget|ChordInkRecognitionTraceTests/testAllowsAttachedAccidentalToExtendPreviousRootTarget'`
  - Result: pass, 6 selected XCTest cases, 0 failures.
- Known-bad device trace gate:
  - `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-c-to-cb-regression-20260826/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-c-cb-trace-known-bad --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
  - Result: failed as intended with `.targetAbsorbedPreviouslyReadableRead`, pass index 4, target index 2, previous text `C`, new text `Cb`. This proves the trace invariant now catches the pulled bad behavior.
- Broad recognition slice:
  - `swift test --scratch-path /tmp/iChartSwiftBuild-c-d-root-boundary-slice --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|StrokeClustererTests|ChordInkSequentialGrouperTests|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordInkRecognitionTraceTests|ChordDraftPreviewDeviceDiagnosticsTests'`
  - Result: pass, 183 selected XCTest cases, 6 expected opt-in/full-archive skips, 0 failures.
- Full archive/trust gate:
  - `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-c-d-root-boundary-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
  - Result: pass, 4 selected XCTest cases, 0 failures.
- Project generation and diff hygiene:
  - `xcodegen generate`
  - Result: project regenerated.
  - `git diff --check`
  - Result: pass.
- Simulator XCTest gate:
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -resultBundlePath /tmp/iChartCDRootBoundary-20260826-1132.xcresult -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests/testChordBatchTargetingDoesNotAbsorbDetachedDIntoPriorCOpenLaneRoot -only-testing:iChartTests/ChordInkSequentialGrouperTests/testDeviceCThenDetachedDStaysAsSeparateSequentialGroups -only-testing:iChartTests/ChordInkRecognitionTraceTests/testDetectsDetachedTargetAbsorbingPreviouslyReadableTarget -only-testing:iChartTests/ChordInkRecognitionTraceTests/testAllowsAttachedAccidentalToExtendPreviousRootTarget test`
  - Result: pass.
  - `xcrun xcresulttool get test-results summary --path /tmp/iChartCDRootBoundary-20260826-1132.xcresult --format json`
  - Result: 4 total selected simulator tests, 4 passed, 0 failed, 0 skipped.
- Physical iPad Debug build/install:
  - Device: Ben's iPad `376D59F8-92F2-5260-B10E-BA0BEAF941AB`, connected.
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartCDRootBoundaryDevice-20260826-1132 -allowProvisioningUpdates build`
  - Result: pass, build succeeded with Apple Development signing. Existing unrelated `IChartTelemetry.swift` main-actor warnings remain.
  - `codesign --verify --deep --strict --verbose=2 /tmp/iChartCDRootBoundaryDevice-20260826-1132/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, signed app valid on disk and satisfied its designated requirement.
  - `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartCDRootBoundaryDevice-20260826-1132/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, installed `com.ichart.app`.
  - `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB --terminate-existing com.ichart.app`
  - Result: pass, launched `com.ichart.app`.
  - `xcrun devicectl device info apps --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB`
  - Result: device-side app listing confirmed `iChart`, bundle `com.ichart.app`, version `1.1.7`, bundle version `49`.
- Physical iPad status: ready for fresh retest after this correction. Required next pass should isolate `A B C D`, then specifically write `C` followed by a detached `D` and confirm the earlier `C` does not disappear or become `Cb`.

C/D repeat failure and target-route diagnostic stamp:

- Date/time: 2026-08-26 11:36-11:51 PT.
- Observed on physical iPad from user report: after the A-root build, the app again changed a previously readable `C` into `Cb` when a later detached `D` was written. This invalidates the earlier pending retest assumption.
- Source device trace: `/tmp/ichart-c-to-cb-repeat-20260826-113652/chord-draft-preview-debug.jsonl`, pulled from the physical iPad app container.
- Trace facts:
  - The trace has 18 JSONL events and reset at `2026-08-26T18:36:02Z`.
  - The bad trace predates the route-diagnostic stamp: every targeting/recognition/preview event has no `targetingDiagnosticsVersion` and no selected route field.
  - At line 13, targeting produced three targets after `A`, `B`, and `C`; target 2 contained one stroke and recognized as trusted `C`.
  - At line 16, after the later `D`, targeting still produced only three targets; target 2 widened from one stroke to three strokes and combined the old `C` stroke with two right-side `D` strokes.
  - The widened target's stroke bounds were `168.0966:20.0371`, `243.4993:0.9887`, and `232.8216:39.0195`. This is detached-root absorption, not a nearby flat mark.
  - The final target 2 payload selected `Cb` with `action: confirm`, confidence `3.8959820667028326`, raw candidates `CB|C|CD|CF|5D|(D|5B|(B|5F|(F|5|(`, and supported candidates `Cb`.
  - The trace invariant failed as intended with `.targetAbsorbedPreviouslyReadableRead`, pass index 4, target index 2, previous text `C`, new text `Cb`.
- Layer classification:
  - The failure is still grouping/targeting boundary proof, not OCR, Scribble, `PKStrokeRecognizer`, rendered chart mutation, or a primary flat-glyph fix.
  - Current source-level grouping and editor targeter tests using this fresh C/D geometry split the C and D correctly. That conflicts with the unstamped physical trace, so the next proof must distinguish stale installed build from a live route mismatch.
- Corrective observability change:
  - Added `LeadSheetChordInkRecognitionBatchTargetingResult` so the live editor route can carry targets plus diagnostics without changing the existing `batchTargets` API.
  - Added DEBUG-only targeting diagnostics fields: version, selected route, draft-barline cluster count, measure-lane cluster count, fallback cluster count, and selected cluster count.
  - Current diagnostic version stamp: `root-boundary-targeting-v2-2026-08-26`.
  - The route stamp is persisted into `ChordDraftPreviewDeviceDiagnostics` so the next iPad trace can prove whether live preview used `draft_barline_lane`, `measure_lane`, `gap_fallback`, or a collapsed/no-layout route.
- Validation:
  - `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-c-to-cb-repeat-20260826-113652/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-c-cb-repeat-trace --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
  - Result: failed as expected with `.targetAbsorbedPreviouslyReadableRead`, pass index 4, target index 2, previous text `C`, new text `Cb`.
  - `swift test --scratch-path /tmp/iChartSwiftBuild-targeting-diagnostics3 --filter 'ChordInkSequentialGrouperTests/testRepeatDeviceCThenDetachedDStaysSeparateAtFallbackGapBoundary|ChordDraftPreviewDeviceDiagnosticsTests'`
  - Result: pass, 2 selected XCTest cases, 0 failures.
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartDerived-repeat-cd-targeter-diagnostics -resultBundlePath /tmp/iChartRepeatCDTargeterDiagnostics-20260826-1148.xcresult -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests/testChordBatchTargetingDoesNotAbsorbRepeatDeviceDIntoPriorCOpenLaneRoot test`
  - Result: pass.
  - `xcrun xcresulttool get test-results summary --path /tmp/iChartRepeatCDTargeterDiagnostics-20260826-1148.xcresult --format json`
  - Result: 1 total selected simulator test, 1 passed, 0 failed, 0 skipped.
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartDerived-repeat-abcd-targeter -resultBundlePath /tmp/iChartRepeatABCDTargeter-20260826-1158.xcresult -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests/testChordBatchTargetingDoesNotAbsorbRepeatDeviceDIntoPriorCWithLeftNeighbors test`
  - Result: pass.
  - `xcrun xcresulttool get test-results summary --path /tmp/iChartRepeatABCDTargeter-20260826-1158.xcresult --format json`
  - Result: 1 total selected simulator test, 1 passed, 0 failed, 0 skipped. This proves current source splits the full `A B C D` targeter replay used for the regression; it does not prove the unstamped iPad build used the same live route.
  - `xcodegen generate`
  - Result: project regenerated.
  - `git diff --check`
  - Result: pass.
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartTargetingDiagnosticsDevice-20260826-1155 -allowProvisioningUpdates build`
  - Result: pass, build succeeded with Apple Development signing.
  - `codesign --verify --deep --strict --verbose=2 /tmp/iChartTargetingDiagnosticsDevice-20260826-1155/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, signed app valid on disk and satisfied its designated requirement.
  - `strings /tmp/iChartTargetingDiagnosticsDevice-20260826-1155/Build/Products/Debug-iphoneos/iChart.app/iChart | rg 'root-boundary-targeting-v2-2026-08-26'`
  - Result: pass, the physical-device binary contains the route-diagnostic version stamp.
  - `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartTargetingDiagnosticsDevice-20260826-1155/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, installed `com.ichart.app`.
  - `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB --terminate-existing com.ichart.app`
  - Result: pass, launched `com.ichart.app`.
- Physical iPad status: a stamped retest is now required before another recognition fix. Write only `C`, then a detached `D`, stop, and pull the trace. If the trace has `root-boundary-targeting-v2-2026-08-26` and still absorbs C plus D, fix the route shown by the diagnostic fields. If the stamp is absent, the device is not running the expected build.

Stamped C/D repeat failure and lane-root sequence correction:

- Date/time: 2026-08-26 12:00-12:17 PT.
- Observed on physical iPad from user report: one `C`, `D` pass previewed correctly, then a second `C`, `D` pass caused both pairs to display as `Cb`.
- Source device trace: `/tmp/ichart-current-device-trace-20260826-1210/chord-draft-preview-debug.jsonl`, pulled from Ben's iPad `376D59F8-92F2-5260-B10E-BA0BEAF941AB`.
- Trace facts:
  - The trace has 18 JSONL events and includes `targetingDiagnosticsVersion = root-boundary-targeting-v2-2026-08-26`.
  - The failing path used `route = measure_lane`; no `laneSequentialClusterCount` field exists in this installed v2 build.
  - First `C`, `D` pass at line 10 targeted two groups: target 0 was a one-stroke `C`, target 1 was a two-stroke `D`. Line 11 recognized `C` as trusted and `D` as confirm.
  - After writing the second `C`, line 13 still selected only two measure-lane targets even though fallback saw three clusters. Target 0 widened from the old `C` alone into the old `C + D` strokes, and line 14 selected `Cb`.
  - After writing the second `D`, line 16 still selected only two measure-lane targets even though fallback saw four clusters. Target 0 remained old `C + D`; target 1 became second `C + D`. Line 17 selected `Cb` for both targets.
  - The raw/supported evidence confirms this is target absorption: target 0 raw candidates included `CB|C|CD|CF|(D|9D|(B|9B`, supported candidates `Cb`; target 1 raw candidates included `CB|GB|C|G|CD|GD|CF|GF`, supported candidates `Cb|Gb`.
- Layer classification:
  - This is not OCR, Scribble, `PKStrokeRecognizer`, rendered chart mutation, or primarily a flat-glyph bug.
  - This is live targeting architecture: `measure_lane` selected broader measure buckets and regrouped earlier readable roots when later ink arrived.
  - The product invariant is left-target stability: adding a detached later root must not change an earlier readable `C` into `Cb`.
- Current source correction:
  - `LeadSheetChordInkRecognitionTargeting.batchTargetingResult` now computes `systemLaneSequentialClusters` before measure-lane clusters.
  - Route priority is `draft_barline_lane`, then `lane_root_sequence`, then `measure_lane`, then `gap_fallback`.
  - `lane_root_sequence` disables the old fragment-collapse check because root-start proof should not be undone by measure/size fallback.
  - `LeadSheetChordInkRecognitionBatchTargetingDiagnostics.version` is now `root-boundary-targeting-v3-2026-08-26` and includes `laneSequentialClusterCount`.
- Validation:
  - `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-current-device-trace-20260826-1210/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-current-device-trace --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
  - Result: failed as expected with two `.targetAbsorbedPreviouslyReadableRead` issues: pass index 3 target 0 changed `C` to `Cb`, and pass index 4 target 1 changed `C` to `Cb`.
  - `swift test --scratch-path /tmp/iChartSwiftBuild-lane-root-sequence-focused --filter 'ChordDraftPreviewDeviceDiagnosticsTests|ChordInkSequentialGrouperTests|ChordInkRecognitionTraceTests'`
  - Result: pass, 30 selected XCTest cases, 3 expected opt-in skips, 0 failures.
  - `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartDerived-lane-root-sequence-xcode -resultBundlePath /tmp/iChartLaneRootSequence-20260826-1208.xcresult -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests/testChordBatchTargetingDoesNotAbsorbRepeatDeviceDIntoPriorCWithLeftNeighbors -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests/testChordBatchTargetingDoesNotAbsorbRepeatDeviceDIntoPriorCOpenLaneRoot -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests/testChordBatchTargetingDoesNotAbsorbDetachedDIntoPriorCOpenLaneRoot -only-testing:iChartTests/ChordDraftPreviewDeviceDiagnosticsTests test`
  - Result: pass.
  - `xcrun xcresulttool get test-results summary --path /tmp/iChartLaneRootSequence-20260826-1208.xcresult --format json`
  - Result: 4 total selected simulator tests, 4 passed, 0 failed, 0 skipped.
  - `strings /tmp/iChartLaneRootSequenceDevice-20260826-1210/Build/Products/Debug-iphoneos/iChart.app/iChart | rg 'root-boundary-targeting-v3-2026-08-26|lane_root_sequence'`
  - Result: pass, the compiled physical-device binary contains the v3 stamp and lane-root route string.
- Physical iPad install status:
  - Initial v3 install attempt was blocked: two fresh `xcodebuild` physical-device builds compiled the v3 source but stalled inside `/usr/bin/codesign`.
  - `codesign --verify --deep --strict --verbose=2` on those app bundles reported `code object is not signed at all`, so neither bundle was installable evidence.
  - A `sample` of the hung `codesign` process showed it blocked in `SecurityServer::ClientSession::generateSignature`, and both installed Apple Development identities also hung when signing throwaway `/tmp` executables. This pointed to local keychain/private-key access, not iChart source.
  - After keychain access cleared, a retry succeeded: `codesign --force --sign B06AE40B261CDBFF2798ADE69D8F3EDEA8ED1C9A /tmp/ichart-codesign-retry-20260826-153825` signed and verified a throwaway executable.
  - `xcodebuild -quiet -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartLaneRootSequenceDevice-20260826-1539 -allowProvisioningUpdates build`
  - Result: pass, build succeeded with existing unrelated telemetry/library warnings.
  - `codesign --verify --deep --strict --verbose=2 /tmp/iChartLaneRootSequenceDevice-20260826-1539/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, signed app valid on disk and satisfied its designated requirement.
  - `strings /tmp/iChartLaneRootSequenceDevice-20260826-1539/Build/Products/Debug-iphoneos/iChart.app/iChart | rg 'root-boundary-targeting-v3-2026-08-26|lane_root_sequence'`
  - Result: pass, the physical-device binary contains the v3 stamp and lane-root route string.
  - `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartLaneRootSequenceDevice-20260826-1539/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, installed `com.ichart.app`.
  - `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB --terminate-existing com.ichart.app`
  - Result: pass, launched `com.ichart.app`.
  - Device-side app listing confirmed `iChart`, bundle `com.ichart.app`, version `1.1.7`, bundle version `49`.
- Device-container repair note:
  - While attempting to reset only the draft-preview JSONL, `devicectl device copy to --destination 'Library/Application Support/iChart/'` again replaced `Library/Application Support/iChart` with a zero-byte file instead of overwriting the child JSONL.
  - The directory shape was repaired by copying the empty JSONL to the exact child path `Library/Application Support/iChart/chord-draft-preview-debug.jsonl`.
  - After relaunch, the app recreated `library-state.json`, `performance-trace.jsonl`, and `telemetry-queue.json`.
  - The previous 15:40 local device `library-state.json` was not backed up before the reset attempt. Do not claim preservation of that local app-support state; use a new clean chart or cloud-restored state for the v3 validation pass.
- v3 physical-iPad failure:
  - A same-device `C D C D` pass emitted the v3 stamp but still selected only two lane sequential clusters after the second pair.
  - The trace showed the `D` construction strokes appended to the preceding `C`, and both pairs collapsed to `Cb`; this is a grouping/targeting failure first, not a flat-glyph fix.
  - The extracted iPad stroke regression failed before implementation with two groups instead of four.
- v4 source correction:
  - `LeadSheetChordInkRecognitionBatchTargetingDiagnostics.version` is now `root-construction-targeting-v4-2026-08-26`.
  - `ChordInkSequentialGrouper` now scores clustered glyphs in original writing order instead of left-to-right cluster stroke order.
  - `ChordInkSequentialGrouper` now applies a bounded lookahead for detached root-construction fragments before appending them to the active group, so a partial future `D` stem cannot contaminate a solved prior `C`.
  - `GestureTemplateRecognizer.isNoisySingleBowlDLikeBody` now tolerates denser PencilKit sampling up to 48 points while preserving the two-lobe `B` negative control.
- v4 local validation:
  - `swift test --scratch-path /tmp/iChartSwiftBuild-v4-cd-green2 --filter 'ChordInkSequentialGrouperTests/testLatestDeviceCThenDetachedDRepeatKeepsEveryRootGroupSeparate'`
  - Result: pass; the extracted v3 iPad `C D C D` strokes now produce four root groups.
  - `swift test --scratch-path /tmp/iChartSwiftBuild-v4-sequential-all --filter 'ChordInkSequentialGrouperTests'`
  - Result: pass, 16 selected tests, 0 failures.
  - `swift test --scratch-path /tmp/iChartSwiftBuild-v4-gesture --filter 'GestureTemplateRecognizerTests'`
  - Result: pass, 21 selected tests, 1 expected full-archive opt-in skip, 0 failures.
  - `swift test --scratch-path /tmp/iChartSwiftBuild-v4-trust --filter 'ChordInkTrustAcceptanceTests'`
  - Result: pass, 3 selected tests, 0 failures.
  - `swift test --scratch-path /tmp/iChartSwiftBuild-v4-chordink --filter 'ChordInk'`
  - Result: pass, 192 selected tests, 4 expected opt-in skips, 0 failures.
- Required next step:
  - Install a signed v4 physical-device build and repeat only `C D C D`. The pulled trace must show `route = lane_root_sequence`, `laneSequentialClusterCount = 4`, and no `.targetAbsorbedPreviouslyReadableRead` before this case is considered fixed on device.
- v4 physical-iPad install status:
  - `xcrun devicectl list devices` confirmed Ben's iPad connected as `376D59F8-92F2-5260-B10E-BA0BEAF941AB`.
  - `xcodebuild -quiet -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartRootConstructionDevice-20260826-1602 -allowProvisioningUpdates build`
  - Result: pass, build succeeded with existing unrelated telemetry/library warnings.
  - `codesign --verify --deep --strict --verbose=2 /tmp/iChartRootConstructionDevice-20260826-1602/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, signed app valid on disk and satisfied its designated requirement.
  - `strings /tmp/iChartRootConstructionDevice-20260826-1602/Build/Products/Debug-iphoneos/iChart.app/iChart | rg 'root-construction-targeting-v4-2026-08-26|lane_root_sequence'`
  - Result: pass, the physical-device binary contains the v4 stamp and lane-root route string.
  - `/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' /tmp/iChartRootConstructionDevice-20260826-1602/Build/Products/Debug-iphoneos/iChart.app/Info.plist`
  - Result: `com.ichart.app`, version `1.1.7`, bundle version `49`.
  - `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartRootConstructionDevice-20260826-1602/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, installed `com.ichart.app`.
  - `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB --terminate-existing com.ichart.app`
  - Result: pass, launched `com.ichart.app`.
- Required current physical validation:
  - Repeat only `C D C D` on the installed v4 app, then pull the trace.
  - Acceptance: `targetingDiagnosticsVersion = root-construction-targeting-v4-2026-08-26`, `targetingRoute = lane_root_sequence`, `laneSequentialClusterCount = 4`, no preview replacement from `C` to `Cb`, and no `.targetAbsorbedPreviouslyReadableRead`.
- v4 physical validation result:
  - User visual report: `C D C D` pass looked good on the attached iPad.
  - Pulled device files to `/tmp/ichart-v4-device-pass-20260826-160530`.
  - Device app-support listing before pull showed fresh `chord-draft-preview-debug.jsonl`, `library-state.json`, `performance-trace.jsonl`, and `telemetry-queue.json` modified at 4:04 PM.
  - Pulled `chord-draft-preview-debug.jsonl` contains 14 JSONL events: 1 reset, 1 single target, 1 finish single, 4 targeting, 3 finish batch, 4 preview replacement events.
  - Final targeting progression:
    - `2026-08-26T23:04:25Z`: `root-construction-targeting-v4-2026-08-26`, `gap_fallback`, `laneSequentialClusterCount = 0`, `selectedClusterCount = 1`.
    - `2026-08-26T23:04:27Z`: `root-construction-targeting-v4-2026-08-26`, `lane_root_sequence`, `laneSequentialClusterCount = 2`, `selectedClusterCount = 2`, target stroke counts `1/2`.
    - `2026-08-26T23:04:29Z`: `root-construction-targeting-v4-2026-08-26`, `lane_root_sequence`, `laneSequentialClusterCount = 3`, `selectedClusterCount = 3`, target stroke counts `1/2/1`.
    - `2026-08-26T23:04:31Z`: `root-construction-targeting-v4-2026-08-26`, `lane_root_sequence`, `laneSequentialClusterCount = 4`, `selectedClusterCount = 4`, target stroke counts `1/2/1/2`.
  - Final batch payloads: `C:trusted`, `D:confirm`, `C:trusted`, `D:confirm`.
  - Preview replacements stayed stable: `nil->C`, then `C->C,nil->D`, then `C->C,D->D,nil->C`, then `C->C,D->D,C->C,nil->D`.
  - `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-v4-device-pass-20260826-160530/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-v4-device-trace --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
  - Result: pass, 1 selected trace test, 0 failures.
  - Conclusion for this case: the v4 physical-device pass satisfies the `C D C D` acceptance gate. This does not yet claim broad base-letter or full-suite physical accuracy.
- v4 broader physical-iPad pass:
  - User visual report: a fuller pass looked good on the attached iPad.
  - Pulled device files to `/tmp/ichart-full-device-pass-20260826-1611`.
  - Device app-support listing before pull showed a fresh `chord-draft-preview-debug.jsonl` modified at 4:11 PM and sized 999 KB.
  - Installed app identity remained `com.ichart.app`, version `1.1.7`, bundle version `49`.
  - Pulled `chord-draft-preview-debug.jsonl` contains 146 JSONL events from `2026-08-26T23:04:16Z` to `2026-08-26T23:11:42Z`: 1 reset, 40 targeting events, 20 single-target starts, 20 single-target finishes, 18 batch finishes, 45 preview replacements, and 2 single-target skips.
  - Targeting route counts: 17 `lane_root_sequence`, 22 `gap_fallback`, and 1 `measure_lane`.
  - The base-letter sweep showed stable preview replacements for `A B C D E F G`; no later write changed a previous root into an accidental spelling. `D` remained deliberately conservative with `action = confirm` because the `D/B` runner-up remains close.
  - The slash-root control showed `D/F#` as the trusted primary beside a separate trusted `B/F#` control. `D/F#` still had nearby generated alternates such as `D/B#`, so uncommon-bass pressure should remain a trust-policy watch item, not a grouping blocker.
  - The trace still contains no-read and confirmation evidence that must not be treated as solved broad accuracy: no-reads at lines 71, 86, 100, 114, 118, 123, and 127; close/ambiguous confirmations at lines 53 (`D°` vs `Db`), 110 (`D7(#11)` vs `B7(#11)`), 136 (`D7` vs `B7`), and 140 (`D7sus` vs `B7sus`).
  - `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-full-device-pass-20260826-1611/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-full-pass-device-trace-1611 --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
  - Result: pass, 1 selected trace test, 0 failures.
  - Conclusion for this pass: the current v4 architecture is stable across the captured broader pass and the catastrophic preview-collapse failure did not recur. Remaining work should be driven by exported fixtures from the no-read/ambiguous complex-form regions only when the user's intended chord label is known.
- v4 labeled lane 2/lane 3 fixture follow-up:
  - User labels for the same pulled trace: lane 2 `D/F#` and `B/F#` previewed correctly; first `Db` previewed as `D°`/`Ddim`, then a rewrite previewed correctly. Lane 3 first `D-7` produced no preview, then a rewrite previewed correctly; following `Ab-7`, `D7`, and `B7` previewed correctly.
  - Trace classification:
    - `D/F#` and `B/F#` are separate targets with correct primaries; this is not slash-bass grouping, target absorption, or preview replacement.
    - The first `Db` failure is a glyph role/ranking issue: the flat-shaped third stroke satisfied round-quality lookalikes, giving `D°` score `4.07975` over `Db` score `4.07`.
    - The first `D-7` failure is a weak-root evidence issue: `D-7` existed in raw candidates, but the root column was `△:0.5518`, `B:0.5479`, `D:0.5440`, leaving no supported score above the acceptance threshold.
  - Fixture additions: exported `DFlatDiminishedRaceDevice01` with expected `Db`, and `DMinor7InitialNoReadDevice01` with expected `D-7`, from the user-labeled physical-iPad trace.
  - Rejected implementation attempt: demoting `°` and `•` for all `isFlatLike` strokes made the new `Db` fixture pass locally but failed the full archive by stealing captured diminished chords such as `C°` and `C°7`. That broad rule is explicitly not acceptable.
  - Accepted implementation:
    - Round-quality `°` and chord-repeat-dot `•` heuristics are demoted only for an open descending flat loop: one-stroke flat evidence with a high start, substantially lower end, and loose endpoint closure. Captured diminished circles, which close back near the top, keep their strong `°` evidence.
    - A weak loose single-bowl `D` body path now sits before the two-lobe `B` path. Its confidence is intentionally below the trust policy weak-root cutoff, so it can turn a no-read into a confirmable `D-7` without turning loose `D/B` races into trusted reads.
  - Validation:
    - Red fixture gate before implementation: `swift test --scratch-path /tmp/iChartSwiftBuild-device-labeled-red --filter 'GestureTemplateRecognizerTests/testCapturedDFlatLoopsRankFlatBeforeDegreeDotAndSixLookalikes|GestureTemplateRecognizerTests/testDeviceInitialDMinorSevenRootRanksDAboveBAndTriangle|ChordInkRecognizerTests/testDeviceDFlatDiminishedRacePrefersRootAccidentalButRequiresConfirmation|ChordInkRecognizerTests/testDeviceInitialDMinorSevenNoReadBecomesConservativeSupportedRead'`
    - Result: failed as expected on `DFlatDiminishedRaceDevice01` (`D°`, expected `Db`) and `DMinor7InitialNoReadDevice01` (nil, expected `D-7`).
    - Focused final gate: `swift test --scratch-path /tmp/iChartSwiftBuild-device-labeled-green3 --filter 'GestureTemplateRecognizerTests/testCapturedDFlatLoopsRankFlatBeforeDegreeDotAndSixLookalikes|GestureTemplateRecognizerTests/testDeviceInitialDMinorSevenRootRanksDAboveBAndTriangle|GestureTemplateRecognizerTests/testFlatLoopBoostDoesNotStealDegreeDotTriangleOrSixTemplates|GestureTemplateRecognizerTests/testTwoLobeRootBStillRanksBeforeD|ChordInkRecognizerTests/testDeviceDFlatDiminishedRacePrefersRootAccidentalButRequiresConfirmation|ChordInkRecognizerTests/testDeviceInitialDMinorSevenNoReadBecomesConservativeSupportedRead'`
    - Result: pass, 6 selected XCTest cases, 0 failures.
    - Broad recognition slice: `swift test --scratch-path /tmp/iChartSwiftBuild-device-labeled-slice2 --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkSemanticGlyphContextualizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordInkSequentialGrouperTests|ChordDraftPreviewDeviceDiagnosticsTests|ChordInkRecognitionTraceTests'`
    - Result: pass, 178 selected XCTest cases, 5 expected opt-in skips, 0 failures.
    - Full archive: `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-device-labeled-full2 --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|ChordInkTrustAcceptanceTests/testRecognizesTrustAcceptanceFixtureSet'`
    - Result: pass, 3 selected XCTest cases, 0 failures.
    - Device trace replay on the pulled lane 2/lane 3 pass: `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-labeled-full-pass-20260826-1631/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-full-pass-device-trace-after-labeled2 --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
    - Result: pass, 1 selected trace test, 0 failures.
    - Project regeneration: `xcodegen generate`
    - Result: pass; `iChart.xcodeproj` regenerated from `project.yml`.
    - Xcode simulator gate: `env ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-labeled-full-pass-20260826-1631/chord-draft-preview-debug.jsonl xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartDerived-device-labeled-xcode-20260826-1639 -resultBundlePath /tmp/iChartDeviceLabeledRecognition-20260826-1639.xcresult -only-testing:iChartTests/ChordInkRecognizerTests/testDeviceDFlatDiminishedRacePrefersRootAccidentalButRequiresConfirmation -only-testing:iChartTests/ChordInkRecognizerTests/testDeviceInitialDMinorSevenNoReadBecomesConservativeSupportedRead -only-testing:iChartTests/GestureTemplateRecognizerTests/testCapturedDFlatLoopsRankFlatBeforeDegreeDotAndSixLookalikes -only-testing:iChartTests/GestureTemplateRecognizerTests/testDeviceInitialDMinorSevenRootRanksDAboveBAndTriangle -only-testing:iChartTests/GestureTemplateRecognizerTests/testFlatLoopBoostDoesNotStealDegreeDotTriangleOrSixTemplates -only-testing:iChartTests/GestureTemplateRecognizerTests/testTwoLobeRootBStillRanksBeforeD -only-testing:iChartTests/ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues test`
    - Result: pass. `xcresulttool` summary reported totalTestCount `7`, passedTests `6`, skippedTests `1`, failedTests `0`. The skipped test was the opt-in trace replay because Xcode did not pass `ICHART_CHORD_DRAFT_TRACE_FILE` into the test host; the same trace replay is covered by the SwiftPM command above.
    - `git diff --check`
    - Result: pass, no whitespace errors.
    - Physical-device build: `xcodebuild -quiet -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartDeviceLabeledRecognitionDevice-20260826-1641 -allowProvisioningUpdates build`
    - Result: pass, with existing unrelated telemetry/library warnings.
    - Device build verification:
      - `codesign --verify --deep --strict --verbose=2 /tmp/iChartDeviceLabeledRecognitionDevice-20260826-1641/Build/Products/Debug-iphoneos/iChart.app`
      - Result: valid on disk and satisfies its Designated Requirement.
      - `/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' /tmp/iChartDeviceLabeledRecognitionDevice-20260826-1641/Build/Products/Debug-iphoneos/iChart.app/Info.plist`
      - Result: `com.ichart.app`, version `1.1.7`, bundle version `49`.
      - `strings /tmp/iChartDeviceLabeledRecognitionDevice-20260826-1641/Build/Products/Debug-iphoneos/iChart.app/iChart | rg 'root-construction-targeting-v4-2026-08-26|lane_root_sequence'`
      - Result: both strings present.
    - Physical-device install/launch:
      - `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartDeviceLabeledRecognitionDevice-20260826-1641/Build/Products/Debug-iphoneos/iChart.app`
      - Result: pass, installed `com.ichart.app`.
      - `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB --terminate-existing com.ichart.app`
      - Result: pass, launched `com.ichart.app`.
  - Required physical retest after install: first-write `Db` should no longer preview as `D°`; first-write loose `D-7` should become a confirmable supported read when the root shape matches the exported fixture. Do not claim this source fix accepted until the freshly installed iPad build is retested.
- Current trace pull and aggregate telemetry final addition:
  - Source device trace: `/tmp/ichart-current-trace-20260826-170053/chord-draft-preview-debug.jsonl`, pulled from Ben's connected iPad `376D59F8-92F2-5260-B10E-BA0BEAF941AB`.
  - Installed app identity at pull: `iChart`, bundle `com.ichart.app`, version `1.1.7`, bundle version `49`.
  - Pulled app-support files: `chord-draft-preview-debug.jsonl`, `library-state.json`, `performance-trace.jsonl`, and `telemetry-queue.json`.
  - Device trace facts: 74 JSONL events, including 22 targeting events, 15 batch finishes, 6 single finishes, and 23 preview replacement events. Route counts included 16 `lane_root_sequence` passes and 6 `gap_fallback` passes.
  - Recognition facts: the pulled pass replayed without hard stability issues. `Db`, `D-7`, and `D/F#` settled as recognized reads; the adjacent `B/F#` control remained separate and was confirmation-gated under root ambiguity. The final base sweep `A B C D E F G` stayed stable; `D` remained conservative/confirm while the other bases were trusted.
  - Preview replacement facts: no previous renderable preview text changed into a different renderable text in this pulled trace. The remaining unresolved rows were interim no-reads during writing/erasing, not evidence of target absorption.
  - Performance facts: `performance-trace.jsonl` did not show a draw/layout bottleneck in this pass (`editor.canvas.draw.end` stayed sub-3 ms max and `editor.canvas.layout.end` stayed sub-2 ms max). Any observed choppiness should be investigated as recognition cadence, Pencil/input timing, or preview scheduling rather than canvas draw/layout without new evidence.
  - Replay gate: `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-current-trace-20260826-170053/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-current-trace-after-preview-telemetry --filter 'ChordInkRecognitionTraceTests/testProvidedDeviceTraceHasNoStabilityIssues'`
  - Result: pass, 1 selected XCTest case, 0 failures.
  - Telemetry architecture fix: production preview telemetry now records aggregate handwriting-quality counters for `chord.preview_updated` only. Added aggregate fields include trust/confirm/no-read counts, close-race count, generated-sequence-limit count, cluster/target/candidate counts, confidence bucket, flow, decision, and result. Raw chord text, raw strokes, glyph columns, candidate text, drawing payloads, chart titles, user names, emails, and support data remain excluded from production telemetry.
  - Telemetry ingest fix: the app already allowed chord preview lifecycle events locally, but Supabase ingest did not. The server allowlist now accepts `chord.preview_updated`, `chord.preview_rendered`, `chord.preview_discarded`, and `chord.draft_barline_added`, plus the matching aggregate preview counters. Without this server-side fix, real-user handwriting telemetry would have stayed queued or rejected and could not support A-level accuracy work.
  - Validation:
    - `node --test supabase/functions/_shared/telemetry_ingest.test.mjs`
    - Result: pass, 11 selected Node tests, 0 failures.
    - `xcrun xcresulttool get test-results summary --path /tmp/iChartPreviewTelemetry-20260826-171138.xcresult --format json`
    - Result: pass, totalTestCount `3`, passedTests `3`, failedTests `0`.
    - `git diff --check`
    - Result: pass, no whitespace errors.
  - Confidence classification: this supports a B+ architecture marker for grouping stability and trust-gated preview behavior in the captured device passes. It is not an A-level handwriting accuracy claim. A-level requires aggregate real-user telemetry over varied handwriting plus continued fixture promotion for labeled wrong-read/no-read clusters.
