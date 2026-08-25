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

## Drift Checklist

- [x] Current commit and branch recorded before code changes.
- [x] No OCR/Vision text recognition path added.
- [x] No `PKStrokeRecognizer` dependency added.
- [x] Scribble remains correction-only.
- [x] Render Chords / Auto Render remains the only rendered-content boundary.
- [x] Sequential grouping tests added before grouping implementation.
- [x] Known full-archive flat failures stayed visible until fixed.
- [x] Trust policy favors confirmation/no-read over confident wrong read.
- [x] Aggregate telemetry only; no raw chord text, drawing payloads, chart titles, user names, emails, or support data added to production telemetry.
- [ ] Physical iPad validation recorded before final accuracy claims.

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

Physical iPad validation:

- Status: not yet run. No final handwriting accuracy claim is made from simulator or fixture evidence alone.
