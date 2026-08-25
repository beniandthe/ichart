# Chord Recognition Baseline Report

Date: 2026-08-25
Branch: `codex/chord-recognition-accuracy`
Baseline commit: `5ab43ad` (`Plan chord recognition accuracy branch`)

## Purpose

This report records the first recognition-only baseline after the branch plan. It does not change recognizer behavior.

## Commands

Focused default recognition gate:

```bash
swift test --scratch-path /tmp/iChartSwiftBuild-recognition-accuracy-plan --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|StrokeClustererTests|ChordInkSymbolLedgerTests|InkFixtureLoaderTests|InkFixtureCoverageTests|ChordEntryPassReplayTests'
```

Full archive recognition gate:

```bash
ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-recognition-accuracy-full --filter 'ChordInkRecognizerTests|GestureTemplateRecognizerTests|ChordInkCandidateComposerTests|StrokeClustererTests|ChordInkSymbolLedgerTests|InkFixtureLoaderTests|InkFixtureCoverageTests|ChordEntryPassReplayTests'
```

## Results

Focused default recognition gate:

- Result: pass
- Executed: 162 tests
- Skipped: 36 tests
- Failures: 0
- Note: skips are expected because full ink fixture archive tests are opt-in.

Full archive recognition gate:

- Result: fail
- Executed: 162 tests
- Skipped: 33 tests
- Failures: 4
- Log: `/tmp/ichart-recognition-full-archive-20260825.log`

Failing assertions:

- `ChordInkRecognizerTests.testRecognizesFullInkFixtureArchiveWhenEnabled`
  - `DFlatMinorCaptured01`
  - expected `Db-`
  - actual match `nil`
  - confidence `0.0`
- `GestureTemplateRecognizerTests.testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled`
  - `DFlat7susCaptured03`
  - expected glyph `b`
  - actual top three glyphs: `["\u{00B0}", "\u{2022}", "6"]`
- `GestureTemplateRecognizerTests.testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled`
  - `DFlatMinorCaptured01`
  - expected glyph `b`
  - actual top three glyphs: `["\u{00B0}", "\u{2022}", "6"]`

The failure count is four because `DFlatMinorCaptured01` fails both match and confidence assertions in the recognizer replay, plus one glyph assertion, and `DFlat7susCaptured03` fails one glyph assertion.

## Interpretation

Observed facts:

- The default compact recognition suite is green.
- The full archive is not green at branch start.
- The full-archive failure shape points at flat accidental glyph ranking for specific D-flat captured samples, not OCR, UI, or render flow.
- `StrokeClustererTests.testClustersFullInkFixtureArchiveWhenEnabled` passed under `ICHART_FULL_INK_FIXTURES=1`, so the immediate failure is not a full-archive cluster-count failure.

Assumptions:

- `DFlatMinorCaptured01` is a useful known failure to keep visible while building the branch, but it should not become the first implementation target unless it blocks the sequential grouping contract.
- The first code slice should still target same-lane sequential grouping before tuning D-flat accidental recognition.

Risks:

- Fixing the D-flat samples first could repeat the previous pattern of isolated glyph patches without addressing the product flow.
- Counting the default suite as accuracy proof would be misleading because it samples only 18 fixture names by default.

Next action:

- Add product contract tests for same-lane sequential grouping before changing glyph scoring.
- Keep the D-flat full-archive failures in the baseline report so later recognition changes can distinguish new regressions from existing failures.
