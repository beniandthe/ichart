# Learned personalization: app comparison bridge

This advances the customizable ML pipeline. It does not introduce an alternate
OCR engine or replace live recognition. Branch: `codex/recognition-generalization-reset`,
base HEAD `160aa31`, existing dirty recognition work preserved.

## Implemented flow

An explicitly opted-in Debug build exposes **Saved Chart Test → a completed run
→ Compare learned ML model**. It loads the verified learned encoder, fits local
personal weights, then displays the recorded app result, shared-ML reading and
ML-plus-personal reading for the same exact ink. Details expose symbol choices
and separate closed-set whole-chord candidates. There is no render or acceptance
API, confidence percentage, automatic teaching or hidden fallback.

- The run's pre-test profile is the only fitting source. Current corrections
  cannot improve old results retroactively. Model inference receives no intended
  labels; those remain display/scoring evidence only.
- Symbol lessons fit the residual head. An explicitly taught musical symbol
  absent from the 97-character generic vocabulary is appended with zero generic
  score and learns through the same residual equation. This general mechanism
  is not proof that one triangle lesson will fix arbitrary triangle writing.
- Whole-chord lessons fit a separate balanced linear head over the learned
  features. Its closed-set ranks are shown as candidates, never used to replace
  a complete symbol read or to invent individual symbol labels.
- Every grouped input stroke must be accounted for. Only top symbol choices
  compose; unread parts are not dropped and grammar does not search lower ranks
  for a desired answer. Generic quality-word letters remain available even when
  they are not in the setup-example catalog. Exact replay exposed the tolerant
  compendium dropping punctuation (D> became D). Four new negative cases failed
  before switching this comparison path to `ChordSymbolParser`'s complete-input
  parsing, then passed. The live parser/compendium itself was not modified.
- Original recognition coordinates are required. All eight older saved runs
  in the inspected September 28 journal lack them. The UI explains why they
  cannot run this comparison; thumbnails are not substituted. New captures in
  both chart styles already retain original coordinates/timing independently of
  the thumbnail. Missing/grouping/known-ink cases stay visible.
- Opt-out is checked before work. Profile changes/opt-out during computation
  discard its pending result. Existing profiles, examples, saved evaluations,
  native readings and chart ink are unchanged.
- Each completed comparison saves a new local report under
  `Application Support/PersonalHandwriting/learned-comparisons-v1/`. Reports bind
  model identity, frozen profile revision and a SHA-256 of the source run.
  Existing reports cannot be overwritten. No network or training upload occurs.

## Model/build boundary

The app loader pins manifest SHA-256
`4b60c912270201408123038ea6a1fe105a4462045d3d5760c62d7fcad1198e60`
and validates the exact package digest, vocabulary, metadata, float32 tensor
names/shapes and finite outputs before use. It uses CPU-only Core ML with the
existing app rasterizer. It does not fetch models or load arbitrary artifacts.

`scripts/package_personal_comparison.py` packages only the verified model and a
public attribution/contract manifest. It excludes trajectories, parity queries,
private profiles and expected answers. The build script is opt-in and refuses
Release inclusion. A stale resource directory with opt-in off fails visibly;
the script does not delete existing data or silently keep a stale model.

Reproduce this exact local development build:

```sh
python3 scripts/package_personal_comparison.py \
  /tmp/iChartPersonalResidual-20260928.4FAreZ/coreml-01 \
  /a/new/directory/PersonalMLComparison
xcodegen generate
xcodebuild build -project iChart.xcodeproj -scheme iChart \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  ICHART_INCLUDE_PERSONAL_ML_COMPARISON=YES \
  ICHART_PERSONAL_ML_ARTIFACT_DIR=/a/new/directory/PersonalMLComparison \
  CODE_SIGNING_ALLOWED=NO
```

The `/tmp` trained artifact is local research evidence, not a reproducible
clean-checkout model distribution. The ordinary build does not require it and
does not expose the comparison link. Durable model distribution remains work
before shipping; no binary is added to production assets here.

## Verified this pass

- **70 iOS Simulator tests passed**, zero failures/skips, verified using
  `xcresulttool`. Includes actual bundled Core ML loading, enabled/disabled
  model flow, frozen-profile learning, separately saved reports, non-overwrite,
  exact-input capture in both chart styles, original evaluation invariants and
  project configuration. One intermediate initializer actor-isolation compile
  error was repaired before this successful gate.
- **17 Swift/macOS tests passed**, zero failures/skips, including actual runtime
  parity and exact private-trace replay; **16 Python personal-model tests** and
  **five packaging-boundary tests** passed. The Python model tests treat runtime
  arithmetic warnings as errors.
- Portrait and landscape attachments of the actual comparison view were
  rendered and visually inspected. They use a controlled test model/profile,
  not handwriting-accuracy evidence or physical-device interaction proof.
- No live recognition call site uses the comparison. No physical build/install,
  chart rewrite, profile teaching, Git commit/push, server deployment or release
  occurred in this pass.

Evidence directory: `/tmp/iChartLearnedAppBridge-20260928.p0xhN7/`.
Final iOS result: `bridge-strict-final.xcresult` (70 tests). Runtime/private replay:
`strict-composition-green.log`, `exact-trace-strict-composition.json`; negative
reproduction: `strict-composition-red.log`. UI rendering:
`bridge-verified-ios.xcresult` attachments (before minor wording corrections).

## Measured limitation and next work

Read-only replay through the new runtime used 12 old v26 observations / eight
unique inputs and the unchanged 30-example profile. The Simple-sheet inputs
compose B-flat-7, E-flat-7 and D7. Several Rhythm-sheet endings still become
non-chord tokens/no complete read; the shared 97-character head dominates those
cases. The frozen profile has no triangle lesson. Whole-chord rankings also
confuse E-flat-7 with an E-flat-major-7 example. This is evidence **against**
promoting the new comparison as the live reader, not a reason to pick a matching
lower-ranked answer or learn from intended test labels.

Next recognition work must address musical-symbol/suffix representation and
learning from changed handwriting using general data/evaluation rules, then
test genuinely fresh full chords in both styles and independent writers. The
app comparison is now wired for that evaluation; it does not establish that
personalization currently improves fresh full-chord accuracy or that we can ship.

## Subsequent anchored comparison

The optional version-two package now adds the constrained personal learner
alongside—not in place of—the original method. The original pinned package and
saved reports remain compatible. Runtime parity passed, but known Rhythm-sheet
endings are still unresolved. See [anchored app comparison and exact gates](personal-anchor-app-comparison-2026-09-28.md).
