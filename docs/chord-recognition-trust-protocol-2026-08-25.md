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
swift test --scratch-path /tmp/iChartSwiftBuild-recognition-trust --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|StrokeClustererTests|ChordInkSymbolLedgerTests|InkFixtureLoaderTests|InkFixtureCoverageTests|ChordEntryPassReplayTests|ChordInkSequentialGroupingTests|ChordInkRenderResolutionPolicyTests|ChordInkRecognitionSessionTests|ChordInkDraftPreviewTests'
ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-recognition-trust-full --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|StrokeClustererTests|ChordInkSymbolLedgerTests|InkFixtureLoaderTests|InkFixtureCoverageTests|ChordEntryPassReplayTests|ChordInkSequentialGroupingTests'
xcodegen generate
xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' test
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

- [ ] Current commit and branch recorded before code changes.
- [ ] No OCR/Vision text recognition path added.
- [ ] No `PKStrokeRecognizer` dependency added.
- [ ] Scribble remains correction-only.
- [ ] Render Chords / Auto Render remains the only rendered-content boundary.
- [ ] Sequential grouping tests added before grouping implementation.
- [ ] Known full-archive flat failures stay visible until fixed.
- [ ] Trust policy favors confirmation/no-read over confident wrong read.
- [ ] Aggregate telemetry only; no raw chord text, drawing payloads, chart titles, user names, emails, or support data added to production telemetry.
- [ ] Physical iPad validation recorded before final accuracy claims.
