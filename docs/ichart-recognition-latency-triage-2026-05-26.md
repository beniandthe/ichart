# iChart Recognition Latency Triage

Status: Sprint 46 repeat complete; scheduler latency improved but low-confidence clear cases remain
Date: 2026-05-26
Source of truth: `docs/ichart-sprint-source-of-truth.md`
Trigger evidence: `docs/ichart-post-export-field-test-log-2026-05-26.md`
Repeat pass log: `docs/ichart-sprint-46-latency-repeat-log-2026-05-26.md`

## Purpose

Sprint 46 investigates the couple-second delay after clear chord ink for `C` and `G/B`.

This is latency and trust routing work, not handwriting training. Do not add personal ink fixtures, score retuning, or corpus expansion before measuring where the live delay is spent.

## Current Timing Path

The live chord-entry path schedules recognition after a fixed idle delay:

```text
PKCanvasView drawing changed
-> scheduleChordInkRecognition()
-> LeadSheetChordInkRecognitionScheduling.idleDelay(...)
-> DispatchQueue.main.asyncAfter(default 0.85s)
-> ChordInkRecognitionSession.start(...)
-> ChordInkRecognizer.recognize(...)
-> optional OCR only when trust policy needs ambiguity evidence
-> LeadSheetChordInkRecognitionTimingLogger.log(...)
-> optional continuation-grace reschedule
-> onChordInkRecognitionProposal
```

Current configured delays:

- default chord-ink idle delay: `0.85` seconds
- default continuation-grace delay: `1.2` seconds
- root-only continuation-grace delay: `0.55` seconds

## Initial Evidence

The first repo-local Sprint 46 test is `LeadSheetChordInkRecognitionSchedulingTests`.

It proves:

- Before tuning, `LeadSheetChordInkRecognitionScheduling.idleDelay` returned the configured default delay.
- Before tuning, a clear root like `C` could pay the initial `1.2s` idle delay plus a `1.2s` continuation-grace recheck before the proposal was sent.
- The same drawing data does not repeat continuation grace forever.
- `G/B` and `Db7(b9)` do not use that continuation-grace path because slash-bass and altered chords are outside the simple-continuation guard.

This means:

- At least part of the perceived `C` delay is intentional scheduler policy, not recognizer compute.
- `G/B` latency is likely the normal idle delay plus writing/user-perception/render handoff, not the root-continuation grace path.
- `Db7(b9)` behaving as confirmation-gated remains expected.

## Sprint 46 Scheduler Adjustment

Sprint 46 makes a narrow scheduler-policy change:

- The normal chord-ink idle delay is reduced from `1.2s` to `0.85s`.
- Root-only continuation grace is reduced from `1.2s` to `0.55s`.
- Extension prefixes such as `A9` still keep the full `1.2s` continuation grace.
- Slash chords such as `G/B` and altered chords such as `Db7(b9)` still do not use continuation grace.

Expected product impact:

- A clear root-only case such as `C` can now propose after about `1.4s` of scheduler time instead of about `2.4s`.
- `G/B` can propose after the shorter normal idle window because it does not use continuation grace.
- `Db7(b9)` remains confirmation-gated and outside the simple continuation path.

## Verification

- Before scheduler tuning, XcodeBuildMCP focused iOS simulator test `iChartTests/LeadSheetChordInkRecognitionSchedulingTests` passed with `4` tests, `0` failures on the configured `iPad Pro 13-inch (M5)` simulator.
- Before scheduler tuning, `swift test --scratch-path /tmp/iChartSwiftBuild-sprint46 --filter WritingToRenderPipelineReadinessTests` passed with `1` test, `0` failures; the bounded recognizer/readiness pass completed in `0.187s`, keeping recognizer compute well below the product-loop latency budget.
- `xcodegen generate` completed after adding the app-target scheduling test.
- After scheduler tuning, XcodeBuildMCP focused iOS simulator test `iChartTests/LeadSheetChordInkRecognitionSchedulingTests` passed with `5` tests, `0` failures.
- After scheduler tuning, `swift test --scratch-path /tmp/iChartSwiftBuild-sprint46 --filter WritingToRenderPipelineReadinessTests` passed with `1` test, `0` failures; the bounded recognizer/readiness pass completed in `0.131s`.
- After scheduler tuning, `swift test --scratch-path /tmp/iChartSwiftBuild-sprint46` passed with `317` tests, `36` skipped, `0` failures.
- After scheduler tuning, XcodeBuildMCP full iOS simulator test for scheme `iChart` passed with `334` tests, `36` skipped, `0` failures on `iPad Pro 13-inch (M5)`.
- GitHub Actions passed on main commit `72e6d91`, with Analyze Swift, iOS simulator tests, and SwiftPM tests all successful.

## Next Evidence To Gather

- Use Sprint 47 to split the remaining product issue into confidence/ink accuracy and conflict/performance/render time.
- Inspect existing debug timing logs from a live/simulator pass if available:
  - `delay`
  - `idle`
  - `recognition`
  - `ocrMs`
  - `best`
- Only after measuring in Sprint 47, choose whether the fix belongs in trust/confidence policy, ink interpretation, or UI/render handoff.

## Real iPad/Pencil Repeat Result

The post-tuning repeat pass is recorded in `docs/ichart-sprint-46-latency-repeat-log-2026-05-26.md`.

Results:

- `C` and `G/B` were low confidence and still took time.
- `Db7(b9)` was extremely quick.
- PDF export completed without issues.

Conclusion:

- Sprint 46 isolated and improved one scheduler-policy source of delay, but the remaining product hurdle is no longer pure debounce.
- The next work should measure low-confidence/conflict routing and render/commit handoff separately before any recognition scoring, fixture, or trust-policy change.

## Guardrails

- Do not expand fixture corpus.
- Do not tune recognition scores from this one writer's iPad pass.
- Do not enable symbol-ledger diagnostics by default.
- Do not make OCR run for clear `C` or `G/B` reads.
- Do not change export/share, PDF rendering, or chord ink clearing in this sprint.
