# Personal handwriting demo

## Current follow-up — 2026-09-28

The original-demo description and verification below are historical. The current v27 follow-up uses the persistent **Saved Chart Test** flow described in [the evaluation log](personal-handwriting-evaluation-2026-09-28.md), and now exposes every one of the personal model's 26 supported symbols for explicit teaching. **Quick setup** has 16 cards, including the formerly omitted major triangle; **Learn Missing Symbols** only offers symbols without a saved glyph example. The visible **Choose Examples → Choose one symbol** menu allows a single symbol to be added or retaught. Whole-chord examples do not silently label their constituent symbols, and coverage is not an accuracy score.

The existing profile is preserved; merely opening, choosing, clearing, or skipping setup does not teach. Focused symbol setup returns to the overview, while Quick setup retains its optional transition to Saved Chart Test. Both chart styles share this flow. See the dated evaluation log for current device status and remaining recognition errors; the original v19 test totals below are not v27 acceptance evidence.

**My Handwriting → Review Saved Examples** now shows each saved ink sample beside its label and source. The trash button and an explicit confirmation remove only that selected example, not every example with the same label. Cancel leaves it unchanged. Other examples, charts, opt-in settings, and frozen past test results are preserved; an active Saved Chart Test prevents profile edits. A wrong label is never automatically replaced with a guessed label. Use Choose Examples separately if a replacement lesson is wanted.

## What this pass delivers

An optional, local example-learning profile in the actual iChart editor, shared by Simple Chord Sheet and Rhythm Section Sheet. Open the chart-title menu → **My Handwriting**. The Chords tool offers it once for first use; Done skips it.

1. **Learn My Handwriting** offers 15 skippable cards: roots, accidentals, minor/seventh/slash symbols, and complete chords. Saving explicitly confirms the displayed label. Finish Early is supported.
2. **Test Fresh Ink** runs the unchanged base recognizer and the personal layer on the same unlabeled drawing. Only after prediction does the user enter the intended chord. Recording a result does not train. **Teach This Example** is a separate action.
3. In either chart style, personal suggestions appear in the normal draft/review flow. They require review; native matches, scores, and trust evidence are not overwritten. Confirmed reviews can add labeled examples when the profile and learning are enabled.
4. Rendered-chord editing has a separate, default-off **Teach this handwriting correction** option. Transposition, ordinary musical edits, erasure, automatic predictions, and unrelated ink do not train this layer.
5. Profile use and review learning can be disabled independently. Reset deletes the personal example bank, not chart content. Existing committed chords/ink are not retroactively rewritten.

## Implementation and limits

- This is a bounded, nearest-example model over normalized visible ink geometry, not a newly trained universal neural recognizer. It preserves aspect ratio, tolerates translation/scale/stroke-order changes, and rejects distant or conflicting labels.
- Whole-chord matching and compositional symbol matching are supported. Symbol composition requires a match for every cluster; an unread suffix cannot simply be dropped.
- Up to 192 examples, at most six per label/type. Features are prepared at profile update/load, and immutable snapshots are used off the drawing callback. Per-target recognition caching is keyed by profile revision as well as the base ink cache.
- Examples stay in the app's Application Support/PersonalHandwriting/profile-v1.json, excluded from backup and protected on iOS. No new cloud transport or raw-ink telemetry is introduced. Existing chart sync behavior is unchanged.
- Pipeline identity: `maximum-trust-v19-personal-demo-v1-2026-09-26`. The underlying standard recognizer is still V19; the suffix identifies this demo.
- The comparison scorecard covers the current screen session. Exact saved-shape matches are excluded from its fresh-test count; this is not a substitute for independent-writer evaluation. Scores are not uploaded. Reset or leaving the screen does not preserve a benchmark history.
- This does not redesign upstream chord grouping or train the future writer-independent model. It may improve recognizable shapes without solving grouping, missing captures, or all recognition errors.

## Acceptance test

Complete the setup in normal handwriting, then test newly written chords—including combinations not present in setup. Compare before entering the label. Score both improvements and regressions, teach a misread only after scoring, then write a new instance. In both chart styles, check the review suggestion, confirm/correct, and write another fresh instance. Toggle profile use off/on to compare new reads. Check that live Pencil ink remains immediate as the page fills.

Automated tests establish flow and safety properties, not natural-handwriting accuracy. Mock-baseline tests deliberately return a wrong chord to prove routing; their improvements are not an accuracy claim. The remaining product question is whether fresh human handwriting improves enough to justify further personalization work.

## Verification

- Simulator: **70 executed, 70 passed, 0 failed, 0 skipped** in `/tmp/iChartPersonalDemo-TouchTests-20260926.xcresult`. Includes native recognition/review regressions, profile contracts, label-blind comparison/learning separation, profile-revision cache invalidation, and native PencilKit hit-testing through the SwiftUI pad's border inside a scroll view.
- Synthetic full-profile benchmark: 192 stored examples, 30 lookups, mean **0.073 ms** in that Simulator run. This measures the personal lookup, not total recognition latency or physical-Pencil responsiveness.
- Earlier retry: a Simulator runner stalled before app launch, was interrupted, and was restarted once. The interrupted bundle is not counted as a passing test run.
- Visual inspection: the chart-title menu, profile overview, and guided setup were inspected in the Simulator. A decorative border was made noninteractive, and the pad's native hit routing now has a regression test. The Mac locked during the final manual drawing check; physical handwriting acceptance remains unverified.
- Physical build: Debug signed with the existing Apple Development identity; `codesign --verify --deep --strict` passed. Installed and launched `com.ichart.app` on the paired iPad Air (4th generation), iPadOS 26.6.2. No Release-signing changes, App Store upload, or GitHub push.
- Reusable output: `/tmp/iChartPersonalDemoDevice-20260926/Build/Products/Debug-iphoneos/iChart.app`. Version/build remain **1.2.1 (51)**; the pipeline identifier above distinguishes the demo. All source changes remain uncommitted alongside the existing in-progress work.
