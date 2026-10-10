# Saved Chart Test — first evaluation pass

## What this tests

The original recognizer and the personal handwriting layer process the **same fresh ink** in the real chart editor. This is a local paired comparison, not a newly trained universal model or proof of writer-independent accuracy.

The first pass is 20 chords: 10 in each chart style, before teaching any corrections. Keep the existing setup profile. Do not repeat setup or reset the profile.

## Steps on the iPad

1. Create a new blank **Simple Chord Sheet**. Use a name such as `Recognition Test — Simple Before`. Finish chart setup with enough measures for 10 chords.
2. Open the chart-title menu → **My Handwriting** → **Saved Chart Test**.
3. Leave **Before corrections** selected. Tap **Start capture in Simple Chord Sheet**. The panel closes. The profile is frozen for this run and automatic personal learning is paused.
4. Select **Chords**. Write 10 complete chords at your normal size and speed across several measures, including a full row. A repeatable suggested set is: `C`, `G`, `B`, `D`, `F#m7`, `Bb7`, `Ebmaj7`, `Am7`, `D7`, `G/B`. These are writing prompts, not hints sent to the recognizer. Do not render/confirm the chords, transpose, change chart style, or copy/paste prior ink during capture. Do not keep rewriting just to obtain a better score.
5. Wait for previews to settle. Open the chart-title menu → **Saved Chart Test** (this direct entry stays enabled while capture is active). Tap **Refresh saved count** if needed, then **Stop capture & label**. The target count can differ from 10; this is evidence, not a reason to rewrite the chart.
6. For each captured shape, type what you intended and tap **Save label**. Use **Incorrect grouping** for two chords merged together, one split apart, or an incomplete target. Use **Edit label** to repair a typing mistake before finalizing. A captured complete chord with no recognition result still receives its intended label; do not mark it as a grouping error merely because recognition failed.
7. Enter **10** as the number of complete chords written. Set the two experience flags accurately: delayed writing and unexpected changes to earlier chords. Tap **Finish & save results**.
8. Create a new blank **Rhythm Section Sheet** named `Recognition Test — Rhythm Before`. Repeat steps 2–7 with **Before corrections**, the same 10 prompts, and newly written ink. Do not teach corrections between these two initial runs.
9. Leave the test charts and profile intact and tell Codex **“both before tests are done.”** Results survive closing/reopening the app. No screenshots or manual export are required while the iPad is connected.

After reviewing the initial results, choose a few scored mistakes and tap **Teach this correction** in the completed run. Then create two new blank charts, select **After corrections**, and repeat using fresh handwriting. Teaching never changes the old scores or their saved frozen profile. Do not teach incorrectly grouped fragments as whole chords.

## What is recorded

- A local frozen profile and revision, pipeline identifier, phase, chart style, and chart identifier (not chart title).
- The latest delivered draft snapshot, normalized target geometry, measure position, base/personal top choices, decision actions, recognition timing, cache-hit status, and exact-replay flags.
- Human labels supplied only after capture stops; grouping flags, total intended chord count, and the two experience flags.
- Explicit teaching markers, separate from scoring. No automatic evaluation-label training.

The file is `Library/Application Support/PersonalHandwriting/evaluation-v1.json` inside iChart's data container. It is excluded from backup and uses iOS file protection. No new telemetry upload or cloud transport is added. Existing chart sync behavior is unchanged.

## Interpretation and limits

- Missing-count gaps count against the whole-chart denominator when targets map cleanly to chords. Split/merged targets, count mismatches, or replayed ink withhold a whole-chart accuracy score; the UI labels any remaining score as a limited target-only result.
- Report improvements and regressions separately. A no-read is not a correct result. A wrong review suggestion is not the same as a silently committed wrong chord.
- Stored timing is recognition processing/scheduling time, **not** Pencil-to-screen latency. Cached lookups are marked and must not be pooled into cold-recognition timing as if they were equivalent.
- The capture replaces intermediate draft snapshots; partial strokes do not become extra test attempts. Results arriving from a different run, before capture began, or after it stops cannot rewrite the scored run.
- Capture follows the latest delivered preview. Wait for the final preview before stopping. The intended-count and grouping checks expose missing capture; this pass does not reconstruct every raw Pencil event or automatically adjudicate merged/split chords.
- The journal retains up to 16 runs and 64 targets per run, with bounded geometry and a 24 MB file limit. It does not silently evict old runs. An unreadable journal fails closed and preserves the original file.
- These tests are a diagnostic pilot. Additional writers, each with a separate profile and fresh evaluation, are still required for generalization claims. Skipping setup must also be evaluated before a broader trial.

## Verification

- **Automated checks:** 84 executed tests passed, 0 failed, 0 skipped, confirmed with `xcresulttool`. Final result bundle: `/tmp/iChartPersonalEvaluationTests-Ready-20260928.xcresult`.
- **Simulator flow:** visually checked starting capture, returning through the chart-title menu while Chords is active, stopping, labeling, saving, and reopening results. Both chart styles expose the active test entry. Synthetic pen input produced a saved no-read and a recoverable scorecard; this verifies capture plumbing, not natural-handwriting accuracy.
- **Signed device build:** Debug 1.2.1 (51), pipeline `maximum-trust-v19-personal-evaluation-v1-2026-09-28`. `codesign --verify --deep --strict` passed for `/tmp/iChartPersonalEvaluationDevice-20260928/Build/Products/Debug-iphoneos/iChart.app`.
- **Physical iPad:** installed successfully and launched successfully with `devicectl` after the initial OS launch refusal cleared. Installation and launch are verified separately from handwriting quality. No evaluation run was started on the physical iPad by this setup pass.
- **Existing setup preserved:** the personal profile pulled before and after installation was byte-identical, retaining all 16 examples. Do not repeat setup before the first two tests.
- **Scope:** evaluation is ready for the user's fresh-ink pass. This is not evidence that personalization improves recognition, and is not a ship-readiness or generalization claim. No GitHub push, App Store upload, or production deployment was performed in this pass.

## First physical-iPad readout — September 28

Collected the local journal and current profile read-only at 08:27 PDT. The user omitted Bb7 from both runs. Both saved runs already declare nine intended chords and contain nine labeled targets, so no denominator repair or source edit was needed. The runs completed at 08:23 and 08:25 PDT, both in `beforeCorrections` under the pipeline above.

| Chart style | Standard exact top choice | Personalized exact top choice | Improvements | Regressions |
| --- | ---: | ---: | ---: | ---: |
| Simple Chord Sheet | 9/9 | 8/9 | 0 | 1 |
| Rhythm Section Sheet | 7/9 | 5/9 | 0 | 2 |
| Combined | 16/18 | 13/18 | 0 | 3 |

Exact means equality to the user's saved canonical label, including chord quality and slash bass. These are suggestion/top-choice results, not automatic-commit rates.

| Chart style | Intended | Standard | Personalized |
| --- | --- | --- | --- |
| Simple | C | C | G |
| Rhythm Section | C | C | G |
| Rhythm Section | Ebmaj7 | Eb+ | Eb+ |
| Rhythm Section | Am7 | Am7 | Bb7 |
| Rhythm Section | D7 | B7 | E7 |

All incorrect suggestions have a `confirm` action. No incorrect `trusted` result appears in the saved records. Personalization also changed four baseline-trusted results into confirmation requests, including a correct D in Simple; it therefore added review burden as well as three top-choice regressions. This does not establish what a user would eventually render after review.

### Integrity and limitations

- Both frozen profiles are structurally identical, match the current device profile, remain enabled with 16 examples, and have no taught evaluation records. The profile contains 13 glyph and 3 whole-chord examples.
- All 18 target IDs and geometry fingerprints are distinct. All records have nonempty geometry, labels, valid capture timestamps within their run, and no known-ink or grouping flags. The intended labels match the nine-prompt list without Bb7 in each run. No missing target or no-read is recorded in these final snapshots.
- Both runs report `inkFeltSlow = false` and `unexpectedChartChanges = false`. Those are user-entered flags, not measured Pencil latency or a complete temporal stability trace.
- Fifteen of 18 final results are cache hits. The timing fields describe the last delivered recognition batch and cannot support an independent cold-inference benchmark or Pencil-to-screen latency claim.
- This journal saves the final target snapshot, not every interim prediction. It cannot rule out all transient/retroactive reads. The Simple records all have measure index 1; no independent per-system placement conclusion is drawn from that field.
- One writer, one shared profile, nine chord types, and two styles are a small diagnostic sample, not a writer-independent accuracy estimate. The two styles were freshly written, not identical-ink layout comparisons.

### Diagnosis and next decision

`PersonalInkSnapshot.applying` accepts a close personal shape match without requiring agreement with baseline evidence. `ChordInkRenderResolutionPolicy` then places any personal suggestion first and makes it the confirmation default, even when the baseline decision is trusted. The evaluation records the same preference. This is a general arbitration problem, not a reason to add C/G- or user-specific exceptions. The journal does not retain the winning personal match source/distance, so it does not establish which example or descriptor component caused each false match.

Do not teach these evaluation records yet. First correct the policy for disagreements: an uncalibrated personal shape match must not automatically displace a supported baseline reading. Preserve the current samples/profile as a before snapshot. Use these 18 samples as regression evidence after an authorized implementation change; then collect fresh handwriting to evaluate both newly introduced failures and genuine gains. The unchanged Rhythm Ebmaj7 and D7 errors remain separate baseline-recognition problems.

Only source inspection, local extraction, and analysis were performed for this readout. No app source, iPad profile, saved run, chart, or production service was changed.

Local evidence: `/tmp/iChartPersonalEvaluationReadout.GCPLD0/evaluation-v1.json` and `profile-v1.json`. SHA-256 respectively: `bd0b8d8d08c919931109ea0acc8f5f3f2b21699362e4117e1e419c3fb7fbab2b`, `625f9bc327b3a7c69d6f28ad28a2bce8b1c4bace75c95756d4f0edeb8289dcff`. Raw ink and profile examples are not added to the repository.

## Follow-up implementation — protected baseline and deliberate learning

Pipeline: `maximum-trust-v20-personal-arbitration-v1-2026-09-28`. This supersedes the instruction above to wait before teaching: the safer policy is now installed, but teaching remains a deliberate user action. The original measured results above are historical evidence and have not been rescored or edited.

### Behavior implemented

- One label-agnostic arbitration policy is shared by chart review, the quick comparison, and Saved Chart Test. A trusted native reading stays the default when a personal shape suggestion disagrees. The alternative remains reviewable. Agreement no longer adds an unnecessary confirmation step.
- Against a weak native reading, a conflicting personal default requires a whole-chord match supported by a nearby, explicitly taught example. Setup examples, symbol composition, and merely confirming a prediction are not sufficient to displace that reading. Personal recovery of a missing reading remains review-only. No personal result acquires automatic trust.
- Similarity distance and runner-up separation are not probabilities. The existing shape thresholds were not tuned to these chord labels or this writer. The record now retains personal source, distance, support counts, arbitration disposition, stable measure ID, and visual order so later disagreements are diagnosable.
- Explicit teaching upgrades an identical setup/confirmed example's provenance instead of silently discarding the instruction as a duplicate. Repeated teaching is idempotent; a distant correction cannot lend its authority to a different nearby example.
- A completed run offers **Teach N labeled examples**, with confirmation. It uses the user's labels, skips incorrectly grouped/already-taught targets, and updates the local profile without changing the run's frozen profile, recorded predictions, or old scores. Teaching is blocked while capture is active. Individual teaching remains available. Returning to the overview refreshes the example count.
- This pass does not change chart geometry, rewrite ink, train a new neural model, or add cloud uploads. It strengthens the existing on-device example-based personal layer.

### Development replay, not a new accuracy test

An opt-in Swift replay consumes a supplied local journal; no private ink is embedded in the repository. It reuses the **recorded native predictions** and rematches the saved normalized ink against the frozen personal profile. It does not rerun OCR or recreate raw Pencil events.

| Replay | Simple | Rhythm Section | Interpretation |
| --- | ---: | ---: | --- |
| Original recorded personalized choices | 8/9 | 5/9 | Historical iPad result |
| New policy with the same 16-example setup profile | 9/9 | 7/9 | Removes the three observed personal regressions; matches the recorded native baseline |
| Teach the other style's nine labels in memory, then evaluate distinct ink | 9/9 | 8/9 | One transfer gain, no new regression in these samples |

The transfer gain is Rhythm **Ebmaj7**: its recorded native choice was Eb+, and the corrected personal example becomes a review-only Ebmaj7 default. **D7 remains unresolved.** Training and test fingerprints are distinct, but these samples were already inspected during development; this is not a held-out accuracy estimate or evidence of new-writer generalization. The in-memory experiment did not teach the actual iPad profile.

### Final verification and device state

- **100 executed Simulator tests passed, 0 failed, 0 skipped**, verified from `xcresulttool`. Coverage includes cross-label arbitration, correction provenance, opt-out, repeat-teaching idempotence, unchanged historical scores, capture in both chart styles, cache behavior, and project configuration. Result: `/tmp/iChartPersonalArbitration-20260928.nQfpu2/final.xcresult`.
- **One opt-in journal replay test passed**, report `/tmp/iChartPersonalArbitration-20260928.nQfpu2/personal-replay.json`. **One device-trace stability test passed** against the latest nonempty captured v19 preview session. Neither is fresh-v20 handwriting evidence.
- **Simulator visual check:** the old scorecard reopens with its original scores and v19 identifier. The new batch-teaching control displays a readable confirmation explaining the learning action; tapping outside dismisses it without teaching the synthetic test ink. This is interaction verification, not handwriting recognition validation.
- **Signed Debug 1.2.1 (51) built**, strict code-sign verification passed, and the app **installed and launched successfully** on the paired physical iPad at approximately 08:56 PDT. No signing settings or credentials were changed.
- Pulled only the personal profile/journal again after installation. Both are **byte-identical** to the pre-install copies: 16 examples and the two completed nine-target before runs remain intact. Evidence directory: `/tmp/iChartPersonalArbitration-20260928.nQfpu2/`, with `personal-before` and `personal-after` copies. No user chart or profile was taught/reset by this pass.
- No commit, GitHub push, production deployment, or App Store action was performed. This is a testable improvement to the personal learning path, not ship-readiness proof.

### Next fresh-ink pass

1. On the iPad, open **My Handwriting → Saved Chart Test**, select the completed **Simple Chord Sheet · Before corrections** run, tap **Teach 9 labeled examples**, and confirm. Teach this run only; do not teach the Rhythm run yet. Do not reset or repeat setup.
2. Create a new blank Simple Chord Sheet. Open Saved Chart Test, select **After corrections**, and start capture.
3. Write these **12** complete chords once at your normal size and speed across several measures, including a full row: `C`, `G`, `B`, `D`, `F#m7`, `Ebmaj7`, `Am7`, `D7`, `G/B`, `F#7`, `Ebm7`, `A7`. The last three are new whole-chord combinations, not training prompts. None of these prompts is supplied as a recognition hint.
4. Wait for previews to settle, stop capture, label each target, and save the actual written count and experience flags. Do not rewrite to improve a score; flag grouping failures honestly. Do not render/confirm during capture.
5. Repeat on a new blank Rhythm Section Sheet with **After corrections** and the same 12 prompts, freshly written. Do not teach anything between the two after runs.
6. Leave the ink/results intact and report that both after tests are complete. Compare standard versus personal on the **same new ink within each run**, with gains, regressions, no-reads, grouping gaps, and review burden separate. Do not attribute a cross-version before/after change solely to teaching.

The next gate is no new personal top-choice regression plus reproducible gains on genuinely new ink, followed by writer-separated testing with independent profiles. A small zero-regression pass is necessary development evidence, not a guarantee. If fresh results remain harmful or show no benefit, investigate the descriptor/model evidence rather than adding per-chord exceptions.

### ML direction and supporting primary resources

Apple's [updatable nearest-neighbor classifier](https://apple.github.io/coremltools/docs-guides/source/updatable-nearest-neighbor-classifier.html) supports labeled-vector personalization on device. Merely wrapping the existing descriptor in Core ML would not establish better recognition. A learned embedding, as in [Prototypical Networks](https://proceedings.neurips.cc/paper/2017/hash/cb8da6767461f2812ae4290eac7cbc42-Abstract.html), is a distinct future model change requiring a suitable writer-separated corpus. [Calibration research](https://proceedings.mlr.press/v70/guo17a.html) also supports treating confidence calibration as a measured property, not calling shape distance a probability. This implementation therefore keeps personal predictions reviewable while collecting the paired, labeled evidence needed to decide whether the personal model actually helps.

## Follow-up capture integrity correction — source only, not installed

A read-only pull at 08:59 PDT found the iPad profile and journal still byte-identical to the post-install copies above: no new after-corrections run or teaching action was saved yet. The installed app remains **v20**. This follow-up did not restart, reinstall, teach, or otherwise change the iPad app.

Code review found that capture deduplication compared only ink fingerprints. A later delivered prediction, review decision, personal evidence, target placement, or timing change for the same normalized ink could therefore be lost. A regression test first reproduced this: the saved observation remained a no-read after a later C prediction had been delivered. This establishes a recorder defect, not that either original physical-iPad run encountered it; historical records cannot retrospectively prove their final observation was dropped.

The source now compares all captured content after applying the existing replay flags, ignoring only newly generated record IDs and capture timestamps. Identical deliveries remain deduplicated, but changed evidence is retained. Run scoping, post-stop immutability, saved labels, and frozen profiles are unchanged. No recognition threshold, match selection, or training rule changed.

Three added regressions cover updated predictions/timing for unchanged ink, changed placement/personal evidence, and idempotent repeated delivery with duplicate-ink flags. **46 executed Swift XCTest cases passed, zero failures**, including the evaluation, arbitration, and personal-profile suites. The subsequent **iOS Simulator gate passed 103 tests, zero failures or skips**, verified using `xcresulttool`; this also covers both chart-style capture adapters and the recognition-session integration. These are logic/integration checks, not new physical-handwriting acceptance. Evidence: `/tmp/iChartPersonalFollowup-20260928.rxYlOs/evaluation-red.log`, `evaluation-green.log`, and `capture-final.xcresult`.

Source pipeline identifier is reserved as `maximum-trust-v21-personal-capture-v2-2026-09-28` so the next installed build can be distinguished from the current test build. Its Simulator build/test gate is complete. The physical Debug build also succeeded and passed strict code-sign verification; `/tmp/iChartPersonalEvaluationDevice-20260928/Build/Products/Debug-iphoneos/iChart.app` now contains the v21 artifact. **Installation remains pending; the iPad stays on v20.** Check for active device capture before a later installation and do not replace an in-progress handwriting pass. For any intervening v19/v20 results, report the capture limitation explicitly and compare available delivered-preview traces before making a final-latest-prediction claim. Existing scores must never be silently rewritten.

## Fresh v20 readout and learning-save verification

The 09:19 PDT read-only pull contains four completed runs: the two original before runs and the two fresh runs. Both fresh runs are marked `afterCorrections`, but their frozen profiles and the current iPad profile are still the original enabled 16-example profile. No record is marked taught. The user explicitly reports tapping Teach and confirming it; do not describe this as a skipped instruction. The available files establish that learning did not persist, not why the device action failed.

| Fresh run | Written | Captured targets | Correctly grouped, labeled targets | Standard exact | Personal exact | Grouping flags |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Simple | 12 | 12 | 12 | 11/12 | 11/12 | 0 |
| Rhythm Section | 12 | 13 | 11 | 11/11 | 11/11 | 2 |

Rhythm's **whole-chart accuracy is withheld**, not 100%. Its two flagged targets are the root and replacement suffix of one intended chord. The root fragment was delivered as **trusted A**, while the suffix was a no-read. This remains a trust failure; excluding grouping targets from exact-choice scoring must not hide it. Simple's incorrect choice was Eb diminished seventh for intended Eb major seventh. There are no personal gains or regressions in either fresh run with the unchanged profile. Both user experience flags are false.

All 25 final captured targets have distinct fingerprints. The final delivered trace matches each saved journal's text, actions, measure IDs, and visual order. This specifically checks the earlier v20 recorder limitation for these final observations; it does not certify every intermediate preview. Analysis uses `readout.jq` in the local evidence directory below. The data-quality check deliberately separates grouping, classification, learning state, and recorder integrity.

### Edited suffix is not untouched-ink instability

The device-trace stability test flags the transition from A-7 to A plus a no-read. Inspecting stroke coordinates and creation times shows the original minor/seventh suffix was removed and replaced roughly six seconds later, while the two root strokes remained. Therefore the evidence is an **edited-suffix reattachment failure**, not proof that untouched ink changed solely because later chords were added. No prompt-derived Am7 exception or recognition-threshold adjustment was made. Reattaching edited ink safely, including the trusted-fragment problem, remains open.

### Fixed-training local replay

The replay now identifies every run by ID, phase, pipeline and source hash, and accepts an explicit training-run selection. Training was fixed to the originally prescribed Simple nine-example before run, not chosen by which transfer scored best. In memory, those labels produce 25 examples. Replaying the personal layer against the recorded native predictions gives:

| Fresh testing run | Eligible targets | Recorded native exact | Replayed personal exact | Gains | Regressions |
| --- | ---: | ---: | ---: | ---: | ---: |
| Simple | 12 | 11 | 12 | 1 | 0 |
| Rhythm Section | 11 | 11 | 11 | 0 | 0 |

The Simple Eb major seventh becomes the review default instead of the native diminished seventh. This is promising **counterfactual replay**, not actual physical-device teaching, a new OCR run, or writer-independent accuracy. It excludes the two grouped fragments and does not fix their ownership. Original evidence and the physical profile were not modified by replay.

### v22 implementation and checks

Pipeline: `maximum-trust-v22-personal-save-receipt-v1-2026-09-28`. This includes the v21 capture correction plus:

- Explicit teaching stores a durable receipt with taught record IDs, profile generation/revision, time, and before/after counts. The UI shows **Learning saved** only after the profile and journal operations complete, and displays teaching failures in an alert as well as the existing error text. Confirmations capture the selected run rather than resolving whichever run is current afterward. Old frozen profiles and scores remain unchanged.
- An After corrections test now requires actual new explicit whole-chord learning since a completed baseline in the same profile generation. Merely changing the phase, toggling the profile, or adding setup examples cannot qualify. The current saved example count is visible before capture. Historical runs retain their old labels and scores; they are not silently reclassified.
- A separate label-agnostic row-routing fix accepts one complete root group on a system. Previously every populated row had to contain at least two groups; the first chord on a subsequent row invalidated the entire page's row-based partition and selected another grouping route. Single-group acceptance is limited to system-lane grouping, preserves exhaustive stroke ownership, and leaves within-measure splitting safeguards unchanged. This is not the edited-suffix fix.

Verification:

- The pre-change Simulator UI taught the **exact original Simple nine examples** on an isolated copy and persisted 16 → 25 examples. This did not reproduce the iPad failure; it rules out a consistently failing batch operation on those samples, not all physical-device/UI failures.
- The v22 Simulator UI displayed the no-learning warning and disabled After corrections capture at 16 examples. Confirmed teaching on an isolated nine-example Rhythm copy displayed **Learning saved**, persisted its receipt with 16 → 25 examples, and enabled the fresh-test start. Synthetic Simulator data was restored afterward. None of this taught the physical iPad.
- **48 executed portable Swift tests passed**, zero failures, covering personal matching, arbitration, evaluation receipts and gates. These overlap the following iOS gate and are not additional independent accuracy observations.
- **98 iOS Simulator tests passed**, zero failures/skips, verified via `save-receipt.xcresult`. New model/store cases cover reopening saved receipts, visible failure without false success, retry after failed profile writes, idempotent teaching, and phase/revision/setup-only rejection.
- The first row fixture attempt lacked an explicit system break and failed fixture setup; it is not counted as product-red evidence. With a valid two-system fixture, **two tests failed against the old route**. After the fix, **201 tests passed, zero failed, two optional device-ink replay tests skipped**, verified via `row-isolation-green.xcresult`. Synthetic A–G roots exercise the new-row invariant in both styles; they are regression geometry, not recognition-accuracy data.
- The Debug device build succeeded and strict code-sign verification passed. **v22 installed and launched on the paired physical iPad at 09:34 PDT.** The four completed runs and original 16-example profile were byte-identical before and after installation. No active capture/labeling session was interrupted. The temporary device artifact path previously holding v21 now holds v22.
- No commit, push, production deployment, upload, new neural-model training, or automatic teaching of physical-device evidence occurred.

Local evidence: `/tmp/iChartPersonalTeaching-20260928.J2rjev/` contains the saved pull, readout query, replay report, result bundles, device build/install/launch records, isolated Simulator copies, and pre/post-install profile checks. Journal SHA-256 at 09:19 PDT: `2c78df388fab2a803f369ef57acf93e5699284ec0a9d410efbab4296a76aabdd`. Profile SHA-256: `625f9bc327b3a7c69d6f28ad28a2bce8b1c4bace75c95756d4f0edeb8289dcff`. Raw handwriting remains outside the repository.

Next physical-device step is **teaching verification only**: select the original Simple before run (08:12, nine captured), teach nine and confirm, then verify Learning saved and 16 → 25. Do not request another full writing pass until the saved profile/receipt is pulled and checked. After that, fresh untrained ink and independent-writer testing are still needed; the goal is not complete or ship-ready.

## Physical teaching verified — 09:36 PDT

The user reported **Learning saved, 16 → 25**. A read-only pull at 09:36:59 PDT confirms it on the physical iPad:

- The enabled profile contains 25 examples, including nine explicit whole-chord corrections from the original Simple before run only. Its original 16 examples and profile generation are unchanged.
- The receipt's profile revision matches the saved profile, and its nine taught record IDs exactly match the taught records. Correction labels match the user's labels for that run.
- All four historical runs, frozen profiles, predictions, labels, timing and scores remain structurally identical when excluding only the newly added teaching flags and receipt. The other three runs have no teaching flags.
- This verifies successful device persistence for this attempt. It does not identify the cause of the earlier unsuccessful attempt or establish fresh recognition improvement.

Evidence: `/tmp/iChartPersonalTeachVerified-20260928.maU0Zv/personal-current/`. Saved profile SHA-256: `7771b1e0e3350acbb87ab0bfcc47476d05e0b1fb688d4516b26e8b2a366f4af6`. No rebuild, automatic training, chart change, or new evaluation was initiated by this read-only verification.

The next step is now the previously specified fresh 12-chord protocol in **two new blank charts**, using After corrections and checking **25 examples** before each capture. Write the same ordered set across two rows, naturally, without copying old ink or rewriting errors for a better score. Stop, label or flag grouping, enter the actual written count, and save. Do not teach between runs or after either run until collected. Compare standard versus personal within each run on identical newly written input; analyze first-chord-on-new-row behavior separately from erased-suffix ownership. The target remains no new personal regressions and reproducible new-ink gains, not a claim that one writer's pass proves generalization.

## Fresh v22 paired validation — collected 09:46 PDT

Both new runs completed on the physical iPad with the same enabled 25-example profile, revision `15A55AF3-F051-413A-A7F2-55C1FDE5235D`. No examples were added between the runs. Each contains 12 user-labeled targets for 12 reported written chords, with no grouping/reused-ink flags. All 24 fingerprints are distinct, with no overlap with earlier evaluation records. These are fresh examples from one writer, not an independent-writer benchmark.

| Chart style | Native exact choices | Personalized exact choices | Gains | Regressions | Trusted wrong choices |
| --- | ---: | ---: | ---: | ---: | ---: |
| Simple Chord Sheet | 9/12 | 11/12 | 2 | 0 | 0 |
| Rhythm Section | 11/12 | 11/12 | 0 | 0 | 0 |

Simple run: `BB049EAC-0E57-4B96-8413-F3FA335DE1B3`. Personal review recovered B from a native no-read and selected the intended D7 over native D minor. E-flat major seventh remained an incorrect A6(b5) review choice; there was no qualifying personal suggestion. Rhythm run: `45E0D3F4-0076-47F8-9FE0-6ED468F401B2`. D remained a no-read, without a qualifying personal suggestion. The remaining failures were not automatically trusted. Both runs record no perceived slow ink or unexpected chart changes; these are user responses, not measured Pencil latency.

### Evidence reconciliation and regression checks

- Native `finish_batch` decisions match the recorded baseline. The separate `preview_replace` events match the personalized text actually displayed for all 24 targets. The payload diagnostic still records the native decision, even when its candidate list includes personal alternatives; comparing its `acceptedText` directly with the personal journal gives a false mismatch. The readout now checks each stage against its corresponding evidence, with pipeline, style, and capture-time bounds.
- At the first recognized chord on row two, each style retains six first-row targets plus one second-row target. The first-row prepared ink and native reads are exactly unchanged, and `lane_root_sequence` remains selected. This is captured-device evidence for the v22 row-routing fix, not proof about incomplete roots, arbitrary layouts, or edited-suffix reattachment.
- The existing trace stability check executed once for the new Simple session and once for the new Rhythm session, each with zero failures. The analyzer is a bounded diagnostic, not a handwriting-accuracy benchmark or proof of every intermediate state.
- The opt-in personal replay now checks saved-default, action, and arbitration parity for captures from the current pipeline, while treating older pipelines as counterfactual replay. One replay test executed with zero failures; all 24 new targets reproduced their saved personal choices from the frozen profiles and saved ink. The combined latest-trace/replay command executed **two tests, zero failures**. Replay did not modify the evidence or iPad profile.
- This continuation changed only the replay test and this evidence log in the repository. No recognition thresholds, chord-specific rules, installed app, personal profile, chart ink, neural weights, or production services were changed.

The validation workflow required separating native decisions from displayed personal choices before accepting the improvement claim. The current milestone is **persisted learning plus a measured benefit on fresh handwriting**, with no observed harm in these 24 targets. It is not general recognition accuracy or ship readiness. The previous erase/rewrite suffix ownership failure remains open; its temporal-boundary cause was inspected, but no writer-specific workaround was added. Independent writers, broader chord vocabulary, and edit/rewrite behavior remain unproven.

Local evidence: `/tmp/iChartPersonalEditOwnership-20260928.KE3SMO/`. The `personal-0949` directory name is only a label; its actual device pull completed at **09:46:57 PDT**, with the trace at **09:46:58 PDT**. Journal SHA-256: `fa1fadbb81f7ab158dcbd4ee7673da011c213f1ba19bba7e9b968ee200b2a494`. Profile SHA-256 remains `7771b1e0e3350acbb87ab0bfcc47476d05e0b1fb688d4516b26e8b2a366f4af6`. `validate-readout.jq`, `v22-personal-parity.json`, and the trace/test logs preserve the calculations and checks. Raw handwriting remains outside the repository.

## v23 normal-review feedback correction — Simulator verified, not installed on iPad

The erased-suffix investigation did not justify changing production grouping. A label-blind local probe combined adjacent targets in the retained trace and ran the portable recognizer and frozen 25-example profile on the combined ink. None of the 13 distinct boundary hypotheses had a qualifying personal suggestion. In particular, combining the edited root and replacement suffix still gave a native no-read and no personal suggestion. One probe test executed successfully and checked that its source trace and profile were unchanged. This rules out the proposed simple merge as a demonstrated recognition repair for this example; it does not settle ownership generally. No grouping rule, timing threshold, recognition threshold, or chord-specific exception was changed.

Separately, inspection found a concrete feedback defect: both normal review acceptance handlers stored every choice as `confirmedReview`, including a user changing the default or filling in a no-read. The arbitration policy deliberately requires nearby explicit correction evidence to replace an uncertain native default, so these corrections were not carrying the intended evidence type.

The shared review-learning path now:

- Compares canonical chord text with the **actually presented default**, not the native recognizer's earlier choice. Choosing a different offered candidate or typing a valid label for a no-read records `explicitCorrection`.
- Keeps unchanged choices and equivalent spelling as `confirmedReview`. Accepting a personalized default is not independent correction evidence merely because it differs from the native read.
- Requires the existing review-learning opt-in for **both** kinds of normal review learning. Existing explicit Teach and rendered-chord correction semantics are unchanged. Disabled profiles, active evaluations, reset generations, and opt-out checks still gate queued learning.
- Runs only after successful human review commits, in the common single/batch editor flow used by both chart styles. Automatic rendering is unchanged and does not call this learning path.

Validation on `codex/recognition-generalization-reset`, HEAD `160aa31` plus the ongoing uncommitted work:

- Red-first classifier test: five tests executed; two cases failed with 113 assertions reproducing corrections/no-reads incorrectly tagged as confirmations. After the fix, all five pass.
- Focused SwiftPM gate: **53 tests executed, zero failures**. Includes feedback classification, arbitration, profile learning/persistence, and evaluation checks.
- Explicit-project iPad Simulator gate after `xcodegen generate`: **61 tests passed, zero failed or skipped**, confirmed with `xcresulttool`. Includes review-learning integration, displayed-versus-native default handling, opted-out confirmations/corrections, evaluation freeze, session behavior, and saved-test model checks. Synthetic changed geometry verifies the source tag reaches arbitration; it is not new-writer accuracy evidence.
- Simulator install and launch succeeded for `com.ichart.app`, Debug 1.2.1 (51), pipeline `maximum-trust-v23-review-learning-v1-2026-09-28`, on `0D3454BE-1A21-4910-8FD6-FFD3EB43E908` (iOS 26.5). The My Handwriting panel was visually inspected in the Simple Sheet UI Fixture; the learning explanation and reset control remain reachable by scrolling. This is a panel/startup check, not an end-to-end physical Pencil correction test.

No physical-iPad install, teaching, chart mutation, commit, push, or production deployment occurred in this continuation. The prior fresh v22 results are not relabeled as v23 evidence. Existing saved confirmations are not retroactively promoted: their original displayed choice is not reliably recoverable. The erased-suffix failure, wider vocabulary, and independent-writer generalization remain open.

Local evidence: `/tmp/iChartPersonalBoundary-20260928.kBYe1n/` (`feedback-red.log`, `feedback-green.log`, `personal-focused.log`, `review-learning-xcode.log`, `review-learning.xcresult`). Boundary probe: `/tmp/iChartPersonalEditOwnership-20260928.KE3SMO/edited-suffix-boundary-probe.json` and `.log`. Authorized raw handwriting stays outside the repository.

## v23 physical build, installation, and preservation — 10:09 PDT

The next continuation verified that normal review corrections can be traced through the existing profile and evaluation path: the saved profile retains example source and revision; recognition refreshes personal results on profile-revision changes; saved chart tests freeze that profile and store native/personal choices, actions, and correction-support evidence. No additional telemetry system was added.

The physical iPad was visible to CoreDevice and Xcode, wired, paired, unlocked, with its tunnel connected and Developer Mode enabled (iPad Air 4, iPadOS 26.6.2). A pre-install read-only pull found 25 enabled examples (16 setup, nine explicit corrections), six completed evaluation runs, and no active capture. Its profile and journal hashes match the previously verified v22 evidence.

The focused Simulator result bundle was re-read: **61 passed, zero failed, zero skipped**. No source changed after that gate. Project generation and whitespace checks passed; the physical Debug build exited zero. Strict deep code-signature verification passed, the provisioned application identifier is `N6G8X4K46U.com.ichart.app`, the target iPad is included, and the provisioning profile expires June 21, 2027. The compiled executable contains `maximum-trust-v23-review-learning-v1-2026-09-28`; version/build remains 1.2.1 (51). No credentials were read and no signing settings were changed.

Installation of `com.ichart.app` succeeded, launch succeeded at 10:09:15 PDT, and a subsequent device process query found the installed executable running as PID 1382. This establishes build/sign/install/launch, not physical handwriting quality or visual acceptance.

Before-versus-after-launch copies are byte-identical:

- Profile: `7771b1e0e3350acbb87ab0bfcc47476d05e0b1fb688d4516b26e8b2a366f4af6`.
- Evaluation journal: `fa1fadbb81f7ab158dcbd4ee7673da011c213f1ba19bba7e9b968ee200b2a494`.
- Chart library: `da98697cbfe26b92cadf0450e28d7a8d79820e83aad55ba8c89265da3b1e2448`.

Local evidence and preserved prior app: `/tmp/iChartPersonalV23Device-20260928.KNP606/`. New device executable SHA-256: `e3c98f134bdc66cde3ba31197bf5edcdeea6330b5046b58c20c34c428b148505`. Device app: `/tmp/iChartPersonalEvaluationDevice-20260928/Build/Products/Debug-iphoneos/iChart.app`. This continuation made no recognition changes, taught no examples, and did not commit, push, or deploy production services.

Next device gate is deliberately small: in a new test chart of either style, write four to six self-chosen chords using normal entry, correct only genuine errors in **Review & Render**, and finish rendering. Do not start Saved Chart Test or use Teach during this step: capture intentionally freezes learning, and explicit Teach would test a different path. If there are no genuine errors, report that without manufacturing a wrong example. Collect the profile and trace before requesting a later fresh, frozen-profile comparison. This checks ordinary-review learning; it cannot establish independent-writer accuracy. The erased-suffix issue and broader recognition evidence remain open.

## v24 review-input repair and profile identity — September 28

The user wrote five chords in a Simple Chord Sheet on v23, reported incorrect E-flat-major-seven and D7 reads, and could not correct them in **Confirm Chords**. Their screenshot shows the actual batch review sheet, a `Fb△7` default, no visible keyboard, and massively expanded footer buttons. The retained final v23 trace has five native payloads: C7, Fb△7, Bb7, G-7, and a no-read. These are not five verified intended labels; no score or automatic teaching is inferred from them.

A read-only pull preserved the current chart's source chord ink (9,048 base64 characters, zero rendered chords), the preview trace, the 25-example profile, and the six-run evaluation journal. The screenshot is UI evidence, not authority to change chord labels. Raw handwriting remains outside the repository.

The shared review UI now uses bounded, Dynamic-Type-scaled buttons accepting finger, Pencil, and pointer input. The canvas/toolbar Pencil-only behavior remains the default. Each batch row has an explicit keyboard **Edit** action, which disables Scribble interception for that row and requests first responder. UIKit focus uses a live binding and transfers between rows without a SwiftUI update prematurely resigning the previous responder; stale end-edit callbacks cannot clear the newly selected row. Scroll-to-focus keeps the selected row reachable. Single-chord confirmation and rendered-chord correction share the compact, touch-enabled review buttons as well. No recognizer threshold, chord-specific exception, or implicit render/learning was introduced.

Separately, synthetic testing found that translation/scaling roundoff could make repeated confirmation of the same saved trajectory consume new personal-example slots and eventually evict explicit correction evidence. Profile identity now compares matching stroke/point sequences with a normalized-coordinate tolerance of `1e-8`; this is a roundoff tolerance, not recognition-distance matching. Distinct subpixel geometry remains distinct. Explicit corrections can repair the same transformed trajectory without deleting merely similar handwriting. No-op profile updates no longer rewrite the file or invalidate the revision/cache. Existing profiles are not migrated, relabeled, or retroactively trained.

Validation:

- Profile identity red tests reproduced duplicate examples and correction-evidence loss on synthetic transformed ink; store red tests reproduced no-op revision/file changes. The final focused SwiftPM gate executed **57 tests with zero failures**.
- The initial UIKit review test reproduced **488-point-tall footer buttons**. After bounding the buttons, a stronger row-switching test still failed; focus handling was revised before device installation.
- The final explicit-project iPad Simulator gate executed **100 tests, zero failures, zero skips**, confirmed by `xcresulttool`. It includes actual hosted UIKit fields and controls, explicit Edit actions, forward/backward focus changes, corrected-value retention, Scribble exclusion on keyboard entry, compact footer geometry, touch-policy isolation, and edited values reaching the explicit Render callback. It also covers profile identity/persistence, feedback classification, opt-out/evaluation freezes, arbitration, and saved-test behavior. Input tests allow UIKit's keyboard/scroll animation to settle rather than assuming a fixed 100 ms transition.
- The hosted-view screenshot shows compact footer controls and corrected values retained across rows. These are Simulator/UI-input checks, **not** physical-Pencil keyboard acceptance or recognition-quality evidence.

Pipeline identifier: `maximum-trust-v24-review-input-v1-2026-09-28`. Evidence: `/tmp/iChartReviewInput-20260928.vJFvyF/` (`review-input-red.xcresult`, `review-input-green.xcresult`, `review-input-focus.xcresult`, source-ink/profile backups, and test attachments). Profile identity evidence: `/tmp/iChartPersonalIdentity-20260928.FSySoq/`. Device build/install status is recorded separately below. No source ink was cleared, no examples were taught, and nothing was committed, pushed, or deployed to production in this repair.

### v24 physical installation — 10:49 PDT

The Debug device build exited zero; strict deep signature verification passed. The compiled executable contains the v24 identifier above, version/build 1.2.1 (51), SHA-256 `2eed0c10b5273b5b91dbbba9c44a6ff3e9ef4ec78cbda240cb9c8c17bd6be122`. Its provisioning profile includes the target iPad and expires June 21, 2027. The previously installed v23 app is preserved locally in the evidence directory. No credentials or signing settings were changed.

Installation succeeded on the paired physical iPad; launch succeeded at **10:49:39 PDT** and a subsequent process check found the installed executable running as PID 1412. This is build/sign/install/launch evidence, not physical keyboard/Pencil acceptance.

Post-launch preservation checks:

- Personal profile and evaluation journal are byte-identical to pre-install: profile SHA-256 `7771b1e0e3350acbb87ab0bfcc47476d05e0b1fb688d4516b26e8b2a366f4af6`, journal `fa1fadbb81f7ab158dcbd4ee7673da011c213f1ba19bba7e9b968ee200b2a494`. The profile remains enabled with review learning on and 25 examples; no teaching occurred.
- The current Simple chart remains present with zero rendered chords. Its drawing bytes changed size from 9,048 to 9,076 base64 characters, so whole-library byte equality is **not** claimed. Native PencilKit decoding compared both drawings: all **18 strokes**, bounds, transforms, point counts, positions, sizes, force, opacity, azimuth, altitude, time offsets, ink types, and colors are equal. `pageHandwrittenChordData` is the only changed key on that chart. The app returns to the library (`selectedChartID` is nil), so reopen the same chart to resume review.

Next acceptance step: use that existing five-chord draft, open **Review & Render**, tap **Edit** on the wrong rows, replace their text with the intended chords, verify all five, and explicitly render. Do not start another saved evaluation, rewrite the source ink, or use Teach for this step. The physical keyboard behavior and normal-review learning must still be checked; the reported recognition errors remain open rather than being counted as fixed by this UI repair.

### v24 ordinary review accepted; fresh transfer test pending — 10:57 PDT

The user subsequently confirmed: **“Yes, Edit and the keyboard worked”**, including the question about switching between chord rows. A fresh read-only device pull found six rendered chords in the same Simple chart: C7, Ebmaj7, Bb7, G-7, D7, and A. Each retains source ink and the v24 pipeline identifier. The original five targets remain, plus a sixth two-stroke target in the new device trace. Native PencilKit comparison found **all 18 original strokes exactly preserved** inside the rendered events' 20 source strokes. The page draft is cleared after explicit rendering, while the per-chord source ink is retained. Counts were verified from the serialized `systems[].measures[].chordEvents[]` hierarchy; `Chart.measures` is a computed property, not a JSON field.

The saved profile grew from **25 to 31 examples**. The two changed labels, Eb△7 and D7, are `explicitCorrection`; C7, Bb7, G-7, and A are `confirmedReview`. The evaluation journal is byte-identical to before this ordinary-review step, so these examples did not come from scoring or Teach. New profile revision: `AD73D7D9-691C-466F-9C44-FB47D2E60DC4`; SHA-256 `97e62b4b7058e613bec9004ba68f40b0670199ee063c06e372919ec313cc5be0`. Chart library SHA-256: `54e5663965068db1043a1991969543b14e0b0a20ceaf2aa852fb787e88034f23`.

A bounded, label-blind diagnostic was added under `PersonalInkBoundaryReplayTests`. It enumerates contiguous stroke partitions using the existing glyph distance/margin requirements and requires every point to be owned exactly once before consulting grammar. With the pre-review 25-example profile it tested **50 partitions across the five old targets**. It did not recover supported alternatives for the reported errors; it also produced an A7 hypothesis for the target displayed as Bb7. The fifth target's existing glyph-based personal suggestion was A against a native no-read. This is evidence against shipping that simple partition experiment as a repair. No grouping rule, matching threshold, or production recognizer changed.

The diagnostic executed once successfully on the old profile and once on the updated profile, verifying that its source files were unchanged. With the updated profile, replay of the same six captured inputs proposes their six reviewed labels, including Eb△7 and D7. This verifies retrieval of learned examples only, **not generalization to new handwriting**. The current v23 session stability check executed once with zero failures. An earlier accidentally broader all-history trace check failed on a dropped A-7 preview at pass 17/target 7; that historical finding is retained in the log and is not relabeled as a failure or success of the current five-chord session.

Evidence remains in `/tmp/iChartReviewInput-20260928.vJFvyF/`: `glyph-boundary-probe.json/.log`, `latest-session-stability.log`, `trace-after-review.jsonl`, `library-after-review.json`, `personal-after-diagnostic/`, and `after-review-replay.json/.log`. No app source or installed build changed during this diagnostic continuation.

#### Predeclared next comparison

Use new blank charts, one Simple Chord Sheet and one Rhythm Section Sheet, on v24. In **My Handwriting → Saved Chart Test**, select **After corrections**, verify 31 examples, and start capture before writing. Write eight fresh chords in each style, in this order:

1. First system: C7, Ebmaj7, Bb7, D7.
2. Next system: Gm7, Eb7, Dm7, A7.

Write normally once, without rewriting errors for a better outcome. Do not render, confirm, transpose, or teach during these captures. After previews settle, stop capture, label the intended shapes, report grouping/missing targets, enter the actual total written, and save results. Do not teach between styles; both runs must freeze the same profile. The two recently corrected labels test fresh-example transfer; the unchanged choices and related-but-different chords test whether learning introduces harm.

Read out native versus frozen 31-example personal choices on identical inputs, and replay the retained pre-review 25-example profile on that same fresh ink to separate the effect of these new corrections from older personalization. Report count/ownership integrity, exact matches, no-reads, gains, harms, fresh/duplicate flags, and the user's ink/retroactive-change flags. Old-ink retrieval and same-writer fresh results remain separate from independent-writer generalization. Wider vocabulary, erased-suffix ownership, and cross-writer evidence remain open; passing these two short runs would not establish ship readiness.

### v24 fresh paired results and exact-input recording repair — 11:26 PDT

Both predeclared runs completed on the unchanged v24 recognizer and the same frozen 31-example profile. Simple run `17C711BE-D5E4-4743-A677-1ED4C1AD9DC1`; Rhythm run `C22C12A5-2ED4-4EC4-B8E0-ECCA1DB15318`. Each has eight labeled targets, eight reported written chords, zero missing/grouping/known-ink exclusions, seven snapshots, and no reported slow ink or unexpected chart changes. There are 16 eligible, distinct captured inputs. No teaching occurred between runs or during analysis.

| Chart style | Recorded native | Frozen older profile (25; replay) | Recorded current profile (31) |
| --- | ---: | ---: | ---: |
| Simple Chord Sheet | 6/8 | 7/8 | 7/8 |
| Rhythm Section Sheet | 6/8 | 7/8 | 8/8 |
| Total | 12/16 | 14/16 | 15/16 |

There are three gains over native, one gain over the older profile, and zero correct-to-wrong changes against either reference in this sample. Native has one no-read (Rhythm D7); both personal profiles recover it. The latest corrections uniquely improve fresh Rhythm Ebmaj7; older personalization already handles the Simple Ebmaj7 and Rhythm D7 cases. Simple A7 remains misread as A- by all three paths and remains in review, not trusted. There are zero recorded trusted-wrong decisions in this sample. These are same-writer results on eight chord labels, not cross-writer accuracy or release readiness.

#### Replay mismatch caught before accepting the comparison

The first paired comparison failed its decision-parity guard. Legacy saved tests contain normalized thumbnail geometry, not the exact page-space input. On Rhythm Eb7, normalization merged the root and flat into one cluster: exact input partitions `[0,1,2] / [3] / [4]`; preview partitions `[0,1,2,3] / [4]`. Replaying the preview invented an A7 personal alternative absent from the live result. The selected Eb7 remained correct, but ignoring this changed disposition would have hidden a replay-contract error.

The successful comparison used exact original strokes recovered from the local device trace. Recovery requires matching pipeline, chart style, timestamp window, measure, visual order, fraction, and exact normalized geometry; missing or ambiguous matches fail closed. Intended labels and predictions are not used to select the input. All 16 recovered inputs reproduce the recorded live text, review action, and arbitration disposition. Only then was the older profile replayed on those same inputs. Labels affect scores only; no profile or source file is written. The failed normalized replay remains in the evidence directory.

#### Implemented repair and verification

New optional `recognitionStrokes` retain the exact input separately from bounded preview strokes, during opt-in local evaluation capture only. Replay and explicit Teach prefer this exact input. Legacy journals continue loading with missing exact input explicitly represented. Storage retains existing journal limits and bounds exact input at 64 strokes / 32,768 points; oversized input is rejected, not silently truncated. No recognizer, matching threshold, trust policy, or chart geometry changed.

- Focused Swift tests: **65 passed, zero failures or skips**, including the two real completed runs. The final comparison/cluster diagnostic separately passed all six selected tests.
- iOS gate: **61 passed, zero failures or skips**, verified with `xcresulttool`; covers capture in both styles, all 257 points of a dense synthetic stroke surviving save/reload, legacy loading, teaching/model persistence, project configuration, and Edit/keyboard row switching.
- Signed Debug device build passed. Strict signature verification passed. Installed at 11:23 PDT and launched at **11:24:19 PDT**; process subsequently verified as PID 1431. Version remains 1.2.1 (51), recognition identifier remains v24 because the recognition algorithm is unchanged. New executable SHA-256: `7a88af2fb5449dbe46c77f018822dc86f3127b0fae501434ffb21eac746ce6fc`.
- Profile and evaluation journal remain byte-identical before/after installation (31 examples; journal SHA-256 `dec7d1190d53a6159d0cee2a07caf8f9d6a9c23fdd62cd0816bd9156a2b7418e`). All nine charts remain. Two PencilKit archives reserialized, so whole-library byte equality is not claimed: native decoding verified **62 identical strokes** including points, transforms, styles, masks, random seeds, and timestamps. All other chart fields are unchanged; app-level entitlements/selected-chart state refreshed on launch.

Evidence: `/tmp/iChartPersonalV24Fresh-20260928.ovu1ZP/`, especially `paired-exact-input-comparison.json`, `paired-comparison-detail.log` (retained failure), `exact-capture-unit-final.log`, `exact-capture-ios.xcresult`, device build/install/launch logs, before/after backups, and `ink-preservation.log`. No user handwriting is added to the repository. No commit, push, production deploy, credential access, or automatic teaching occurred in this pass.

Next milestone: retain this same-writer improvement without specializing rules to these answers. Broaden fresh vocabulary and verify erase/rewrite ownership, then gather independent-writer paired evidence before claiming generally trustworthy recognition. The current 16 inputs are now development evidence and must not be reused as unseen validation after further tuning. The two completed runs do not need to be repeated for the recorder repair.

### v25 edit-continuity implementation — 2026-09-28

The user confirmed that Edit and keyboard navigation work on the physical iPad. A second writer is not currently available; the user asked to continue app work. Cross-writer accuracy remains unverified. No new global chord/glyph matching rule or timing threshold was fitted to this user's answers.

#### Measured failure and scope

Historical local input showed an already-written chord losing two suffix strokes, followed about six seconds later by two replacement strokes inside its former footprint. The existing grouper split it into a trusted root and an unread suffix. The two root strokes were unchanged. This is erased/replaced ink with lost ownership, not an untouched chord retroactively changing. A separate merged-input recognition probe still returned no-read and no qualifying personal suggestion: repairing grouping does **not** establish that the classifier now reads the chord correctly.

`ChordInkEditedTargetOwnership` now tracks this interaction without labels, candidate scores, personal examples, or handwriting-speed thresholds. A partially erased target retains its old footprint while any original stroke survives. New same-lane input entirely within that footprint may rejoin only as unions of whole proposed targets. Existing neighboring and previously unassigned ink cannot be claimed as new replacement ink. Overlapping ownership, duplicate identities, invalid geometry, and mixed-owner targets require review rather than guessed merges. Growing pen-down paths with preserved point prefixes do not count as erasure; complete erasure releases ownership and restoring the original strokes clears edit review.

The adapter runs in the existing background preparation path, before target-load filtering, in both Simple and Rhythm styles. It preserves exact source indices and PencilKit paths; original drawing data remains untouched. Request-local `requiresEditReview` prevents an old cached trusted root from bypassing confirmation. Native and personal result caches remain context-free. Local opt-in evaluation and diagnostic records retain this review context, separately from the exact recognition strokes. No production telemetry schema or backend changed.

Scope is deliberately session-local: chart/layout/coordinate changes, clearing/rendering, and full erasure reset ownership; superseded request results cannot advance state. This is not a migration of historical damaged ink, nor a guarantee across app restarts or arbitrary partial-path erasures. No ownership is inferred after the old geometry has been discarded. A fresh device erase/rewrite pass is still required before claiming physical interaction acceptance.

#### Evidence and failed checks retained

- Historical label-blind replay verified 22 complete-input snapshots, six affected outputs, and exhaustive target partitions. One incomplete snapshot is excluded because a missing target cannot prove an erasure. Five affected outputs reunite the split root/suffix; one mixed-neighbor output remains separate and requires review. No chord label enters the policy.
- The separate v24-only replay contains 15 complete snapshots and zero ownership/review changes. These are historical regressions, not fresh recognition accuracy.
- Focused Foundation tests: 69 passed, zero failures/skips, including synthetic delay/translation/scale, undo, full erase, duplicate identity, unassigned ink, trust policy, review resolution, evaluation persistence, and the historical replay.
- The initial iOS gate passed 52 cases and failed one new synthetic flow test. Diagnosis: the fixture applied the suffix template's built-in horizontal offset twice, placing it as a separate chord before erasure. The fixture geometry was corrected; no recognizer rule changed. Its next focused run executed one passing test covering both chart styles. The initial result bundle remains available.
- Final review additionally caught an overlapping-footprint edge: ambiguous replacement ink itself must require review, not just its possible owners. That guard and retention of both pending owners now have a repeated-snapshot assertion. The 69-test Foundation gate and 118-test iOS gate were rerun after this change.

Evidence directory: `/tmp/iChartEditOwnershipState-20260928.EpNxfR/`. Local handwriting inputs remain outside the repository. The recognizer identity is now `maximum-trust-v25-edit-ownership-v1-2026-09-28`, so prior v24 results cannot be mislabeled as v25 accuracy. The user's 31-example profile and completed paired runs are backed up and are not being taught or rescored by this change.

#### Final verified gates — 12:06 PDT

- iOS result `edit-ownership-verified-ios.xcresult`: **118 passed, zero failed, zero skipped**, confirmed with `xcresulttool`. Includes preparation in both chart styles, exact index/PencilKit preservation, edit-review cache hits and paired capture, scope isolation, review input, draft/render behavior, and project configuration.
- Final 69-test Foundation gate passed. The separately filtered v24 non-edit replay passed all 16 selected cases, including the opt-in historical trace case; no missing-input skips were counted as passes.
- Simulator installed/launched the final code, PID 27347. Screenshot `simulator-smoke.png` shows the signed-out welcome page; this is startup proof, **not** a live handwriting/editor visual-acceptance claim.
- The first physical signing operation waited for key access. The user approved the prompt. An incremental signed rebuild then incorporated the final overlapping-footprint guard, succeeded, and passed strict code-signature verification. No credentials were read or copied.
- Physical iPad installed the final Debug app at **12:04:52 PDT** and launched at **12:05:30 PDT**; subsequent process check confirmed PID 1464. App version is 1.2.1 (51), pipeline v25. Executable SHA-256: `fe00d97b5c89e32be096e63b4e5e28e8141f9e6088e5f10b32735fb9db79f948`.
- Before/after profile and evaluation journal are byte-identical: 31 examples, revision `AD73D7D9-691C-466F-9C44-FB47D2E60DC4`. Hashes remain `97e62b4b7058e613bec9004ba68f40b0670199ee063c06e372919ec313cc5be0` and `dec7d1190d53a6159d0cee2a07caf8f9d6a9c23fdd62cd0816bd9156a2b7418e`. There was no active evaluation run at launch.
- All **nine charts are unchanged**, including their serialized chord-ink archives; no drawings required the native reserialization fallback comparison. Other chart fields also compare equal. This does not assert equality of unrelated app-level selected-chart/entitlement state.
- `git diff --check` passed. No commit, push, production deployment, automatic teaching, or historical score rewrite occurred.

Next device check: in each style, naturally write a few chords, wait for the preview, erase/rewrite one suffix, and leave the live ink unrendered for comparison. The edited chord should remain reviewable, unaffected neighbors should not change, and uncertain ownership must not become a silently trusted leftover root. Broader unseen vocabulary, arbitrary partial-path edits, restart/layout-transition ownership, and independent-writer validation remain open; this pass is an edit-safety improvement, not proof of higher classifier accuracy.

### Fresh v25 device pass and v26 neighbor isolation — 2026-09-28

The user completed ordinary-chart tests in both styles and confirmed the final intended labels: Simple **B♭7, E♭7, D7**; Rhythm **B♭maj7, E♭maj7, D7**. Read-only device capture at 12:14 PDT contains 39 v25 events and 12 recognition snapshots, from 12:08:46 through 12:10:40 PDT. The 31-example profile and evaluation journal are byte-identical to their pre-v25 copies. The nine prior charts are unchanged; two new charts retain 12 and 16 PencilKit strokes respectively. No teaching or rendering was performed by this diagnostic.

#### Observed results, not an accuracy benchmark

- Simple's final previews match all three confirmed labels. However, at 12:09:46 and 12:09:48 the base grouper absorbed the unchanged first chord into the partially erased/replaced second chord: recognition groups contained `[9, 3]` and `[10, 3]` strokes instead of three chords. The combined reads required review. The preview reducer retained the old first preview plus an unresolved mixed draft; that is not correct grouping. A one-test trace stability gate failed with `targetAbsorbedPreviouslyReadableRead`; the failure is retained rather than relabeled as a pass.
- Subsequent Simple full erasure/rewrite restored three groups. The final edited second chord required review; neighboring exact input and previews remained stable. This does not erase the earlier failure.
- Rhythm retained three groups through its edit. The second preview changed from E♭7 to E♭maj7 and required edit review. Its unchanged first and third final previews were **E♭maj7** and **B7**, not the intended **B♭maj7** and **D7**. Both were review decisions, not trusted reads. These two recognition errors remain open.
- Thus four of these six final displayed previews match the user-confirmed intent. This is one writer's small edit exercise, with no recorded paired-evaluation run; it is not a generalization estimate or a new-writer acceptance gate.

#### Implemented candidate

Pipeline identity is `maximum-trust-v26-edit-neighbor-isolation-v1-2026-09-28`. Prior stroke ownership can now separate a mixed target only when it contains one partially erased owner and complete unchanged neighbors, their old horizontal footprints do not overlap, and every new stroke lies inside the edited owner's horizontal footprint with vertical overlap. Taller rewritten suffixes are permitted; ambiguous outside ink, overlapping/unknown owners, missing input, different lanes, and append-only changes do not authorize separation. The edited target remains review-only.

The policy returns an exhaustive original target/stroke-index partition. The PencilKit adapter reconstructs each group from those exact source strokes, preserving paths, transforms, dates, and pressure; it does not alter the stored page drawing. Session preparation honors a restored split even when the base grouping route offers a single fallback target. No root-specific rule, expected label, personal answer, global glyph threshold, or score adjustment was introduced. The personal profile is unchanged.

#### Verification so far

- Label-blind replay of all 12 new snapshots restores the two mixed groups to `[4, 5, 3]` and `[4, 6, 3]`, with only the middle group marked for edit review. Every input stroke occurs exactly once. This is a counterfactual partition check, not freshly observed v26 device behavior or recognition accuracy.
- Focused Foundation gate: **38 passed, zero failed/skipped**, covering ownership, selective decisions, and personal arbitration. Synthetic isolation covers translation, scale, either spatial direction, taller replacements, repeated snapshots, ambiguous new input, other lanes, append-only input, and empty targets.
- First iOS gate: **119 passed, one failed, zero skipped**. The failing new test assumed removing the third chord would still reproduce a one-target collapse. In that two-chord variant the base grouper already kept the owners separate. All preservation assertions passed. The unsupported fixture assumption was removed; the required recorded multi-target collapse assertion remains.
- Final iOS gate: **120 passed, zero failed/skipped**, verified using `xcresulttool`. Captured trajectories reconstructed as PencilKit input exercise preparation in both layout styles, with and without the third chord. Separate adapter tests verify exact source indices and native PencilKit stroke preservation. Reconstruction is not an untouched physical-device capture or an OCR accuracy test.
- A historical non-edit replay initially used an incorrect v24 version filter and correctly failed its nonzero-snapshot assertion. With the exact recorded version `maximum-trust-v24-review-input-v1-2026-09-28`, the gate verifies 15 complete snapshots with zero ownership/review changes. Neither failed command was counted as successful validation.
- Simulator installed and launched the candidate, PID 29749. This is startup proof only; physical installation and fresh acceptance are separate gates.
- Read-only personal-evidence diagnostic: one test passed, using the frozen 31-example profile and final Rhythm strokes. The first target's personal suggestion is E♭maj7 (wrong for confirmed B♭maj7); the third has no qualifying personal suggestion and retains the ambiguous B7 native read. Bounded stroke-contiguous glyph partition enumeration did not uncover a supported intended read for either error. A whole-input-as-glyph hypothesis returned A for the third target; that diagnostic result is **not** a production proposal. No threshold, glyph split, profile, or learned example was changed. The remaining errors cannot be declared fixed by the ownership repair.

Physical v26 build reached `/usr/bin/codesign` and was waiting for key access at 12:30 PDT. The user was asked to approve the macOS prompt themselves. The iPad still runs v25 until signature verification and installation complete; compilation/signing progress is not installation evidence.

#### Physical v26 installation — 12:34 PDT

The pending build subsequently exited successfully. Strict deep signature verification passed; the executable contains `maximum-trust-v26-edit-neighbor-isolation-v1-2026-09-28`. Debug version/build remains 1.2.1 (51); executable SHA-256 is `2c0e13bfd5f40b54354d52666cbf4475599e405b9b272a84cd0a599f7562d441`.

The paired wired iPad installed v26 at 12:33:28 PDT and launched it at 12:33:47 PDT. CoreDevice process inspection confirmed PID 1470 running the newly installed bundle. Signing is no longer the blocker. No credential was read or copied, no release build was uploaded, and no production service was changed. Fresh erase/rewrite acceptance on this installed version is still pending.

Post-install preservation check passed for all 11 charts. The two new chord drawings were reserialized, so byte equality was not assumed: native PencilKit comparison verified all 28 strokes, bounds, masks, transforms, random seeds, creation dates, point locations, sizes, pressure, opacity, and orientation unchanged. All other chart fields compare equal. The profile and evaluation journal are byte-identical to their pre-install copies (31 examples; revision unchanged).

Next physical check can reuse the two existing three-chord charts: enter Chords and wait for previews to seed the new session's ownership, then erase/rewrite the middle chord's ending in each style. Leave ink unrendered and do not Teach. This checks fresh editing on v26, not whether old handwriting is retroactively reclassified correctly. The tested installed build stays unchanged while this pass is performed.

Evidence directory: `/tmp/iChartV25DeviceReview-20260928.MQd1ZS/`. Authorized local raw trajectories and the profile remain outside the repository. The live recognition errors, cross-writer evidence, restart/layout ownership limits, and arbitrary partial-path erasure remain unresolved. This patch does not make the recognition system ship-ready.

### Physical v26 edit pass and edit-independent personalization — 2026-09-28

Read-only capture at 12:42 PDT contains 14 v26 events and four recognition snapshots from 12:37:09–12:37:54 PDT. The user confirmed the final middle chord is **E♭7 in both styles**. The first and third input paths are exactly unchanged from the previously confirmed B♭7 / D7 (Simple) and B♭maj7 / D7 (Rhythm).

#### Observed device behavior

- Both styles retain three recognition targets before and after the edit. All four untouched neighbors retain their exact point paths and previous preview text. Only the edited middle targets receive the edit-review flag. The one-test captured-trace stability gate passes with zero failures.
- No `edit_continuity` regrouping event occurs: the base grouper already keeps three targets in these snapshots. Thus this is a fresh v26 edit check with no observed neighbor regression, **not direct physical exercise of the mixed-target splitting branch** proved in the earlier replay.
- Simple final previews are **B♭7, E♭maj7, D7**. The native middle read is E♭7 with corroborated recognition evidence, but the separate edit-review flag demotes its action to confirmation. The old personalization handoff treats that safety demotion as weak recognition evidence and replaces the correct native read with the personal E♭maj7 suggestion.
- Rhythm final previews are **E♭maj7, E♭maj7, B7**. Its middle native read is E♭ minor (`Eb-`), also requiring edit review, and personalization selects E♭maj7. Neither is the intended E♭7. Its unchanged first and third errors remain as documented above. All four wrong final displayed previews require review; none is a trusted displayed decision in this captured pass.
- Only two of the six final displayed previews match the confirmed intent. Four targets reuse unchanged earlier input, so this is **not a six-chord fresh accuracy benchmark**. Neither edited middle preview is correct.
- The 31-example profile and evaluation journal remain byte-identical to the post-v26-install copies. All 11 charts remain present; only the two test charts' chord-ink data and update timestamps differ. Stored chord-ink stroke counts are 12 (Simple) and 14 (Rhythm); no rendered chord/chart field or other chart changed.

#### Scoped v27 candidate

`maximum-trust-v27-edit-independent-personal-v1-2026-09-28` separates native recognition evidence from the request-local edit-review action. Personalization retains the same existing rule that protects a trusted native read, even when that read must be reviewed because its ink was edited. The actual render decision still uses the original edit flag. Genuinely uncertain native evidence and no-reads retain their existing explicit-correction/recovery behavior, and personal alternatives remain visible.

No glyph threshold, geometry, grouping, expected chord label, stored example, or learned model changes. The rule is label-independent. New paired-evaluation captures retain `baselineRecognitionAction` separately from the gated action, so offline replay does not confuse required review with weak native evidence. Older unedited records still load; older edited captures without the missing arbitration input fail closed in comparison instead of inventing evidence or silently changing their scores.

The regression test failed before the fix across all roots A–G and four quality/extension forms (one failing test method, two passing; 756 conflicting pairs). After the fix, the focused Foundation gate passes **54 tests, zero failures/skips**. This candidate does not correct the Rhythm native errors and is not a ship-readiness claim.

#### Candidate verification

- iOS build-for-testing passed. The first iOS test attempt had **64 passed, one failed, zero skipped**: the new replay harness incorrectly invoked the inner `ChordInkRecognizer` rather than the editor's full `ChordInkMaximumTrustRecognizer`, omitting trust-validation evidence. Its failed report is retained as `v27-edit-replay.json` and is **not valid parity evidence**.
- The harness was corrected to use the same full recognition route as `LeadSheetCanvasHostView`. The native-match, trust-outcome, gated-action, and recorded-preview parity assertions were retained. The final iOS gate passes **65 tests, zero failures/skips**, verified with `xcresulttool` in `v27-verified-ios.xcresult`.
- Exact captured-input replay reproduces all four snapshots / 12 target observations using the frozen 31-example profile. Only the two edited middle defaults change. Simple changes from the incorrect E♭maj7 to native **E♭7**, still requiring review. Rhythm changes from E♭maj7 to native **E♭ minor**, also still requiring review and **still wrong** for the user-confirmed E♭7. The other ten observations retain their defaults and all four edited-pass neighbors retain their prior previews.
- Cache-hit tests verify that toggling request-local edit review cannot enable a conflicting personal override or change cached native recognition. Paired evaluation and persisted capture tests retain the ungated evidence action separately while keeping the final review action. Missing old edited evidence fails closed in comparison. All source trace/profile bytes remain unchanged.

This is a verified arbitration repair on captured input, not new handwriting or independent-writer accuracy. In particular, stable neighbor ownership does not make the Rhythm chord reads correct, and corroborated native evidence is not a calibrated guarantee of correctness. The existing restart/layout ownership limitation is unchanged. No further user handwriting is necessary to investigate these already-captured recognition failures.

Evidence directory: `/tmp/iChartV26DeviceReview-20260928.lznGyf/`. Raw source captures remain unmodified outside the repository. The physical iPad still runs v26 at this point; no new signing, installation, teaching, commit, push, or production change has been performed.

### Explicit missing-symbol setup — 2026-09-28

The frozen 31-example profile contains 18 whole-chord examples and 13 glyph examples, but only 12 distinct glyph labels: A–G, flat, sharp, minor dash, 7, and slash. The original guided setup never offered the major triangle, despite the personal model supporting it, and offered no individual-symbol chooser. An E♭maj7 whole-chord correction does not label its triangle; inventing that label from unverified segmentation would violate explicit teaching.

`PersonalInkSetupCatalog` now provides all 26 supported glyphs, a 16-card Quick setup (13 core glyphs plus the original three whole-chord cards), and a read-only missing-symbol plan. For the unchanged physical profile, 14 symbols are missing, with the major triangle first. The overview reports coverage separately from accuracy. Its main action offers missing symbols for an existing profile; **Choose Examples → Choose one symbol** exposes every supported symbol for focused teaching or additional examples. Duplicate glyph examples and whole-chord examples do not falsely increase symbol coverage.

The selected card plan is frozen until the user completes or exits it: saving a card cannot cause the next index to skip a newly removed gap. Each Save retains the existing explicit-label learning path. Focused setup returns to the overview; Quick setup retains the optional Saved Chart Test transition. Merely viewing, choosing, clearing, or skipping cards does not teach, enable, or replace a profile. No recognizer threshold, native classifier, geometry, grouping, automatic-learning policy, telemetry service, or chart content was changed in this addition.

#### Checks and limits

- Focused Foundation gate: **40 passed, zero failed/skipped**. Catalog tests cover all supported labels, uniqueness, duplicate/whole-example coverage, read-only planning, and a stable running plan. A synthetic composition test fails to propose a chord with an unsupported triangle, then proposes the complete unseen chord after the triangle is explicitly taught. This proves the mechanism with artificial shapes, not live or independent-writer accuracy.
- iOS build-for-testing passed. The final focused iOS gate after the menu-affordance repair executed **73 tests, all passed, zero failed/skipped**, verified using `xcresulttool` in `visible-menu-ios.xcresult`. Includes profile/model, evaluation model/capture, setup coverage, and project configuration checks. This does not duplicate the earlier v27 exact-input replay or turn its remaining wrong reads into passes.
- Simulator installed/launched the latest app, PID 33398. Both chart-style title menus open the shared My Handwriting flow. Normal tapping opens the visible Choose Examples menu; the menu exposes all 26 symbols; choosing △ opens **Example 1 of 1**, with Save disabled for empty ink. Clear and Skip return without learning. Quick setup shows **Example 1 of 16** and Finish Early reaches Saved Chart Test with the correct Rhythm style.
- The first menu implementation used a primary-action Menu, which hid alternative setup behind a long press. Visual inspection caught this and it was replaced with a separate, visible Choose Examples button before the final gate. The Simulator profile remains byte-identical before and after navigation, SHA-256 `6a0c3ff2beff7fcbc8e6f3a18be726d5fffaee5b9bcf0e242cb4d67c3e045993`. This is the Simulator's one-example test profile, not the physical user's 31-example profile. No drawing was taught in this UI check.
- The physical Debug build passed, strict signature verification passed, and the executable contains `maximum-trust-v27-edit-independent-personal-v1-2026-09-28`. Read-only pre-install backups confirm the physical 31-example profile and evaluation journal retain their previously recorded hashes; all eight saved evaluation runs are complete. No credentials were read or copied.

This closes a teaching-coverage omission, **not** the remaining live B♭maj7 / D7 / Rhythm E♭7 recognition failures. The current personal matcher still tries whole-chord evidence before symbol composition; a new triangle example alone is therefore not guaranteed to overcome an already qualifying wrong whole-chord match. That precedence and the native errors require separate, label-independent investigation. User-specific expected answers and threshold tuning have not been introduced.

Evidence directory: `/tmp/iChartPersonalCoverage-20260928.ueAJzG/`, including `individual-major-symbol.png`, Foundation/iOS logs, signed-build log, and scoped pre-install backups. Physical installation/preservation results are recorded separately below when verified. No commit, push, upload, or production deployment occurred.

#### Physical v27 installation and preservation — 13:16 PDT

The paired iPad accepted installation of the signed Debug app and launched it at **13:15:32 PDT**. Process inspection confirms PID **1498** running the newly installed bundle. Version/build remains **1.2.1 (51)**; pipeline identity is v27 as above, and executable SHA-256 is `c27c414a582f96150e9f51d3868872a8f029426c0f21fc19cc35fc648b1a5e15`. The build completed without an additional user signing intervention.

Post-install read-only comparison preserves all **11 charts**. One chord drawing was reserialized; native PencilKit comparison verifies all **14 strokes** in that drawing unchanged, including bounds, masks, transforms, ink, dates, seeds, point locations, sizes, pressure, opacity, and orientation. Other drawings are byte-identical, and all other chart fields compare equal. `ink-preservation.log` records the check.

The physical 31-example profile and eight-run evaluation journal are byte-identical to the immediate pre-install backups, with unchanged SHA-256 hashes `97e62b4b7058e613bec9004ba68f40b0670199ee063c06e372919ec313cc5be0` and `dec7d1190d53a6159d0cee2a07caf8f9d6a9c23fdd62cd0816bd9156a2b7418e`. No evaluation capture or teaching was started. Installation/launch and preservation are verified; fresh physical handwriting, the new focused teaching UI on hardware, and recognition quality after new examples remain unverified. No additional handwriting request is necessary for the next investigation of whole-chord versus complete-symbol evidence.

### Evidence-route investigation and reviewable example removal — 13:43 PDT

The read-only diagnostic compared the current personal suggestion with whole-chord-only and symbol-only snapshots of the same frozen 31-example profile. Across the four captured v26 snapshots (12 target observations, eight unique inputs), there are **zero complete symbol-route suggestions and zero whole-versus-symbol conflicts**. Thus whole-first precedence is not hiding a complete alternative in this pass. Individual glyph matching frequently rejects or misranks the inputs before composition. No precedence, threshold, grammar, or recognition rule was changed on the basis of these labels.

An offline alternative shape comparison used 32 arc-length-resampled points and exact one-to-one point assignment, with translation/uniform-scale normalization and no rotation or aspect-ratio distortion. This was informed by the primary [point-cloud recognizer research](https://depts.washington.edu/acelab/proj/dollar/pdollar.html), but is an independent diagnostic, not a copied implementation or a reproduction of its published gesture results. Assignment was checked against 24 small exhaustive cases and input-order/normalization invariants. Ranking improved for the captured B and D roots but remained wrong for other roots, accidentals, and whole chords. No acceptance thresholds were fitted, and none of this experimental matcher was added to the app. Rankings on these development inputs are not accuracy or Pencil-latency evidence.

Visual comparison of stored samples found two examples labeled A: one compound shape resembling D♭ and one actual A. The user confirmed the first was an accidental setup save. It has **not** been silently relabeled or deleted. A diagnostic clone excluding exactly that example contains 30 entries; the persisted 31-example source remains byte-identical. Exclusion changes **none** of the 12 whole/symbol/current suggestions or reported top-two glyph rankings. This mislabeled lesson merits cleanup but does not explain the observed failures. Both route diagnostics passed their nonzero-input and source-preservation assertions; the exclusion replay executed one passing test.

#### Shared example-management implementation

Both chart styles now expose **My Handwriting → Review Saved Examples**. Each row shows the actual normalized saved ink, label, and provenance; a 44-point trash control opens a compact native alert with explicit Cancel and Remove actions. Removal is by exact example UUID, preserves other same-label examples and opt-in flags, updates the profile revision/cache identity, and uses the existing save-first store update. It cannot run during an active evaluation capture. Frozen saved-test profiles and historical scores remain unchanged. No replacement label is guessed or taught.

- Focused Foundation gate: **39 passed, zero failed/skipped**. Includes selected-example removal, same-label neighbor preservation, unchanged generation/opt-ins, unknown-ID no-op, persistence, new-snapshot invalidation, and old frozen-snapshot retention.
- Final iOS gate: **77 passed, zero failed/skipped**, verified with `xcresulttool` in `example-review-final-ios.xcresult`. Model tests additionally verify active-capture refusal and byte-identical completed evaluation journals after explicit removal.
- Simulator UI was inspected through both chart styles. The initial confirmation popover had an unclear Cancel affordance; it was replaced with the final native alert and visually checked. Cancel left the Simulator profile byte-identical. This was the Simulator's synthetic one-example profile, not a physical-user deletion.
- Final Debug build and strict signature verification passed. The physical iPad installed the update and launched at **13:37:19 PDT**; process inspection confirmed PID **1506** in the newly installed bundle. Version/build remains **1.2.1 (51)** and recognition identity remains v27 because the matcher did not change. Executable SHA-256: `47ab500ee5e1ffcedff89f1d3c570ded4537f18ce7837cdee8a65591cb415fe6`.
- Post-install capture at **13:40 PDT** preserves all **11 charts**, all serialized ink, and every other chart field. No native drawing reserialization fallback was needed. The physical profile and eight-run evaluation journal retain the hashes above, with **31 examples**. No credentials, automatic teaching, backend, commit, push, or release operation was involved.

Evidence directory: `/tmp/iChartPersonalEvidence-20260928.z7NEpu/`. Authorized raw drawings and personal examples stay outside the repository. The user has been asked to remove only the confirmed accidental A through the new screen, with an expected count of 31 → 30; that physical action is pending at this checkpoint. No additional handwriting is needed to investigate the existing failures. Native Rhythm errors, personal shape discrimination, and independent-writer accuracy remain unresolved; this update improves inspectability and correction of learned data, not proven recognition quality or ship readiness.

### Rejected local-support gate and isolated pretrained-engine replay — 14:16 PDT

Two development experiments were evaluated without changing the installed iChart
recognizer, acceptance rules, or teaching policy. Neither supports promotion.

#### Local-part support: rejected

The opt-in `PersonalInkEvidenceReplayTests` diagnostic now compares each nearby
whole-chord example with separated horizontal ink components. Boundaries depend
only on stroke bounds, not inferred or expected labels. Connected strokes are
not split, and invalid isolated components remain explicit rather than being
dropped. This uses the existing whole/glyph distance cutoffs (0.065/0.075) only
as a diagnostic; it does not change the matcher or introduce new tuned cutoffs.

On the v26 failure trace, the stricter support requirement rejects every
qualifying current whole-chord suggestion, including correct ones. More
importantly, identity-matched replay of the earlier 16 paired records shows that
it would lose **all three** demonstrated personal recoveries: Simple E♭maj7,
Rhythm E♭maj7, and Rhythm D7. It was therefore rejected, not loosened until those
known labels passed. The final Foundation gate executed **41 tests, zero
failures/skips**. Synthetic invariants cover scale/translation/order independence
and retaining unsupported dots; the real replay preserves source/profile bytes.

#### Fixed Google digital-ink model: not a drop-in replacement

The separate developer harness in `recognition_ml/ios_digital_ink_probe/` uses
official GoogleMLKit 8.0.0 / MLKitDigitalInkRecognition 7.0.0 with the fixed
`en-US` model. It is not linked into iChart or RecognitionStudy. Original stroke
order, points, and recorded timing are passed without resampling or expected
labels, personal examples, preceding text, or custom vocabulary. Translation
of spatial/time origins and conversion to SDK Float/integer-ms types are
explicit adapter operations, not bitwise coordinate preservation.

Primary inference uses no context. A separately fixed secondary configuration
uses an empty preceding context and the unpadded ink bounds as the writing area.
Neither configuration is selected per chord. Input recognition is on-device;
Google's SDK may send usage/performance metrics and downloads its model.
Production adoption would require a separate dependency/privacy decision.
See the official [iOS guide](https://developers.google.com/ml-kit/vision/digital-ink-recognition/ios)
and [ML Kit terms/privacy details](https://developers.google.com/ml-kit/terms).

The initial physical XCTest runner failed during framework copying/signing and
was canceled; **no physical XCTest pass is claimed**. The standalone app-only
build subsequently succeeded after the user's normal macOS signing approval.
Strict signature verification passed. Bundle
`com.ichart.development.digitalinkprobe`, version **0.1.0 (1)**, was installed on
the paired iPad and launched at **14:09:12 PDT**. Its executable SHA-256 is
`43e70177154b35592fcb28805c0ce0d2bf58f7c9334b932a49d2718cee53c2d8`.
SDK Swift concurrency/deployment-target and toolchain search-path warnings
remain in the build log; compilation is not a warning-free claim.

The app returned a complete report for **30 distinct exact trajectories / 60
inferences**, exactly one result per input per configuration. Input SHA-256
`97076338a3aee6ebff1b309d34a3b18c86ff0d6650ba1d51cc7122908cb02177`
matches the host packet; raw report SHA-256 is
`5a9b2d32c4c62af9e5defc15f8282bc0f632998bdd04ad90b0ebc930e1c751e9`.
Expected labels were joined only after inference. The earlier paired records
join through the trace's exact stroke objects, style, measure identity, and
recorded normalized-input fingerprint; every selected record has exactly one
distinct input identity. Six final edited inputs use the already-confirmed
user intent and latest pass per style. Eight other/intermediate inputs remain
unscored, not silently counted as independent labeled trials.

| Captured set | Existing native | Existing personal | ML Kit primary top-1 | ML Kit bounds top-1 |
| --- | ---: | ---: | ---: | ---: |
| Earlier paired Simple + Rhythm | 12/16 | 15/16 | 3/16 | 4/16 |
| Six final edited inputs | 3/6 | Not scored here | 1/6 | 1/6 |

These are top-1 matches against the same saved intended chords, **not** general
accuracy or trust estimates. Minimal notation equivalence does not change any
top-1 count. For the earlier 16 inputs, correct-candidate recall is 7/16 within
the first five for both settings, and 8/16 primary versus 10/16 bounds anywhere
in the returned list. Choosing an expected lower-ranked result would not make
the recognition correct. Examples of raw first choices include C for C7, D for
D7, and ordinary-word-like output for major-triangle chords. The engine is
missing chord endings and symbols, not simply presenting different notation.

Six pure Python scoring tests pass, checking source hash/identity completeness,
duplicate/missing results, separate raw/equivalent/top-N counts, unknown baseline
values, and refusal to repair missing or wrong chord components. The 60 SDK
inferences have a 3.515 ms median and 176.069 ms maximum including the first
inference. Those figures exclude download, input capture, queueing, and editor
rendering: they do **not** demonstrate improved live Pencil responsiveness.

The fixed pretrained engine is rejected as a drop-in candidate on this evidence.
No expected-answer substitutions, language-model rescoring, acceptance rules,
or model training were added to make these examples pass. These are development
replays from one writer and already-seen traces; no independent-writer or fresh
handwriting validation has occurred.

#### Device state and remaining work

iChart was returned to the foreground at **14:09:51 PDT**, without replacing its
v27 binary. The 14:15 scoped read-only pull preserves all **11 charts and their
serialized ink** against the previous snapshot. The saved eight-run evaluation
journal is byte-identical, SHA-256
`dec7d1190d53a6159d0cee2a07caf8f9d6a9c23fdd62cd0816bd9156a2b7418e`.

The physical profile now has **30 examples**. Exact comparison confirms that
only the user-confirmed accidental A example and the profile revision changed;
the genuine A and every other example/setting remain. This verifies the requested
cleanup through the app, not a new recognition improvement. Profile SHA-256 is
`96ca9e99461118c1383f8e04a8ac37eb4b23569022cac572586a746973777e29`.
The separate probe has no iChart container access and performed no teaching.

Evidence: `/tmp/iChartPersonalLocalSupport-20260928.0Nqzh0/`, including the
private identity-join script, raw packet/report, `probe-scored.json`, signed build
logs, and scoped device-state pulls. Private handwriting/profile material is
not added to Git. No commit, push, backend deployment, release, or credential
access occurred. Native symbol errors, personal discrimination on changed
handwriting, and cross-writer validation remain open; the long goal is active.

### Customizable learned head — 2026-09-28, 14:37 PDT

Following the user's direction to focus on the customizable ML layer,
alternate OCR-engine exploration is stopped. The baseline recognizer is not
replaced. `PersonalInkAdaptiveHead` now implements a local, regularized visual
classifier trained from explicitly labeled personal examples, rather than
only selecting the closest saved shape. This is a trained linear head, not a
neural feature encoder, and it remains **comparison-only**.

The head uses fixed label-blind spatial features, class-balanced fitting, and
immutable profile revisions. Fitting fails when personalization is disabled,
examples/features are invalid, or fewer than two labels exist. Explicit
corrections affect only a newly fitted model; previously frozen models retain
their predictions. Whole-chord labels cannot silently train guessed individual
symbols. Regression scores are not probabilities, have no acceptance threshold,
and cannot render chords. Source inspection confirms no live recognition,
personal-suggestion, or editor call site invokes this new model.

The opt-in exact-trace comparison fits separate whole-chord and symbol heads
from the unmodified 30-example profile. It replays all 12 v26 observations / 8
unique inputs and the 22 unique v24 trace inputs. Several root/symbol errors
remain. Six v24 inputs are already represented by the current profile and are
explicitly marked known; they must not become fresh-accuracy evidence. This is
model-development evidence, not a new user test or a demonstrated fix.

To avoid selecting changes solely against this user's known handwriting, the
same personal learning procedure was tested on public UJI v2 development data:
40 separate writers, one first-session example per uppercase A–G, and 280
second-session queries. The learned ranking gets **222/280**, versus **218/280**
for the existing geometric ranking: 16 gains and 12 harms. This small net gain
does **not** justify enabling the head in live recognition. Twenty reserved
writers are unused by fitting or inference. This is isolated-root personalized
development evidence, not full-chord accuracy, open-set calibration, or app
ship readiness. The fixed protocol, attribution, checksums, per-writer limits,
and interpretation are in
[the adaptive-head protocol](personal-adaptive-head-protocol-2026-09-28.md).

#### Final verification

- **50 Foundation tests passed, zero failures/skips**, including the actual
  public-data run, exact private replay with source-preservation checks,
  closed-form/normal-equation solver checks, opt-out, and existing learning,
  arbitration, and setup tests. Final public predictions match the first run.
- iOS build-for-testing passed after XcodeGen regeneration. The final iOS gate
  executed **71 tests, zero failures/skips**, verified with `xcresulttool` in
  `adaptive-final-ios.xcresult`; this includes the final opt-out test. These
  are Simulator tests, not physical handwriting or live UI acceptance.
- No new physical app installation, learned-weight persistence, private-data
  upload, profile mutation, teaching, commit, push, or deployment occurred.
  The physical iPad retains the previously installed v27 behavior. The private
  source profile retains SHA-256
  `96ca9e99461118c1383f8e04a8ac37eb4b23569022cac572586a746973777e29`.

Evidence directory: `/tmp/iChartPersonalAdaptiveHead-20260928.dfNhl5/`. The next
learning work is a stronger learned visual representation and explicit-example
adaptation, with writer-separated evaluation. Lowering thresholds or adding
expected-answer exceptions would not address the observed limitation. Fresh
in-app results in both styles and independent-writer full-chord validation
remain outstanding; the active goal is not complete.

### Learned personal visual features — 2026-09-28

The next pass trained a small CNN feature encoder for the **customizable ML
layer**, not another pretrained OCR service. Native chart recognition and the
installed app remain unchanged. The 32-writer training split and eight-writer
development split were frozen before predictions; the 20 official test writers
remain unused by fitting/inference. No private handwriting trained the encoder.

On 56 development A-G queries, learned personal ridge and generic seven-way
classification both read 56/56, versus 43/56 for the previous geometric/fixed
features. This supports learning better visual features but does not establish
an additional personalization benefit at that task's ceiling. The wider fixed
97-character follow-up gives personal 624/772 versus generic 609/772, with
103 improvements **and 88 regressions**. It is not safe to replace the generic
prediction unconditionally. No confidence or acceptance thresholds were fitted.

The 30-epoch training repeat reproduced every checkpoint tensor exactly. The
Core ML embedding matches Python within 2.683e-7; actual Swift app rasterization
and the personal ridge solver reproduce all 112 support/query features and all
56 ordered rankings. This is verified macOS/Core ML execution, not iPad UI or
live Pencil latency evidence.

Read-only replay then used the 12 explicit glyph examples in the existing
30-example profile against all 12 v26 observations/eight unique inputs. The
learned features recover E-flat-7 and D7 compositions that the old fixed features
misranked, including the Rhythm D7 native B7 failure. Major-triangle inputs
remain invalid because the profile has no triangle lesson. Neither intended
answers nor whole-chord labels were used to create missing glyph training data.
Source trace/profile bytes and the current installed app are not modified.

See the [fixed protocol and full evidence](personal-visual-encoder-protocol-2026-09-28.md)
for controls, copy exclusions, per-writer limitations, numerical repair and
reproducibility. This is a substantive feature-learning gain, not a shipping or
fresh-handwriting accuracy claim. Next work must retain those feature gains while
covering musical symbols and controlling harmful personal overrides, then verify
fresh full chords in both chart styles. The long goal remains active.

### Learned correction layer and app bridge — September 28, 15:50 PDT

The fixed residual experiment keeps the trained generic classifier intact and
learns corrections from explicit personal examples. On the same 772 eligible
97-way development inputs it reads 628, versus generic 609 and replacement-head
624, with 24 gains/five harms versus generic. This is fewer harms **and fewer
recoveries** than the replacement head's 103 gains/88 harms. Full Python/Core ML/
Swift parity passes for all 1,552 original inputs and 776 query rankings. See the
[residual protocol](personal-residual-learning-protocol-2026-09-28.md).

The learned model is now wired to an explicitly opted-in Debug Saved Chart Test
comparison, not the live chart reader. It fits only the frozen pre-test profile,
supports explicitly labeled novel musical symbols, separates whole-chord ranks
from symbol composition and saves append-only local comparison reports. It never
teaches from intended test labels, overrides the native result or changes ink.
The current eight old saved runs lack exact recognition coordinates and cannot
be scored using substitute thumbnails. New captures in both styles preserve the
original input; this path is covered by the iOS gate.

Final verification: 70 iOS Simulator tests, 17 Swift/macOS tests, 16 Python model
tests and five packaging-boundary tests passed. iOS test counts/skips were
verified from the result bundle. Portrait/landscape comparison UI attachments
were inspected using controlled fixture data. No physical install occurred.

The actual runtime's unchanged private replay still misses several Rhythm-sheet
endings and whole-chord ranks can confuse minor/dominant and major examples.
The replay also caught the new comparison using tolerant text cleanup that
could drop an unread suffix (D> → D). Negative tests reproduced four such prefix
reads; the comparison now uses complete-input parsing, and the final 70-case
iOS/17-case macOS gates pass with those cases included. No live recognizer rule
or model score was changed to make the intended answer appear.
The comparison exposes this instead of promoting a wrong candidate. Musical
suffix representation, trustworthy selection and genuinely fresh/full-chord/
independent-writer verification remain required. Full details, paths and build
boundary: [learned app comparison](personal-learned-app-comparison-2026-09-28.md).
The goal is active; a wired comparison is not recognition completion.

### Sparse-profile ML learning investigation — 2026-09-28

A fixed matched-control training experiment is complete and reproducible, using
only the existing 32 public training writers. Training through personal fitting
did not establish better personalization: its sparse-profile adaptation still
lost three reads versus its own generic head, and its full-profile result fell
below the original model. That checkpoint is not promoted.

The breakdown exposed untaught-label harm. A separate, frozen personal-fitting
experiment constrains updates at public training feature means for labels not
explicitly taught by the profile. On the same 772 eligible development-character
queries, sparse-profile results change from 602 to 614 correct; gains/harms versus
the fixed 609-correct generic model change from 22/29 to 10/5. Taught-label
recoveries also decrease, so this is a tradeoff, not solved recognition. Full97
profiles preserve the existing 628-correct output exactly. Both experiments and
all rankings were repeated; 31 focused tests pass with no skips/failures.

No live model, app profile, chart ink, device build or recognition trust policy
changed. The anchor prior still needs a comparison-only Swift implementation,
runtime parity and full-chord testing. Musical-symbol coverage and fresh-writer
evidence remain unresolved. See [complete results and next boundary](personal-adaptability-results-2026-09-28.md).

### Anchored learner app port — 2026-09-28

The constrained learner is now available beside the original method in the
opted-in Debug comparison. Original saved reports and the pinned legacy model
remain compatible; no live recognizer or profile data changed. Actual Core ML
inference and Swift fitting reproduce all 1,552 expected top-five rankings
across sparse16/full97 profiles. Gates: 27 Swift/macOS tests, 77 iOS Simulator
tests verified through xcresulttool, and seven packaging tests, all passing
without skips. Portrait/landscape comparison attachments were inspected.

Private exact-input replay preserves all earlier results but does not repair
the known Rhythm-sheet symbol/endings failures. This blocks promotion, not
continued general ML work. The next focus is complete-chord symbol representation,
coverage and grouping, not a different engine or specific-user exceptions.
[Full evidence and runtime boundaries](personal-anchor-app-comparison-2026-09-28.md).
