# Customizable ML: sparse-profile investigation

Branch `codex/recognition-generalization-reset`, base `160aa31`. This pass changes
research training/personal-fitting code and tests, not live recognition or ink.
Protocols were written before their respective predictions:

- `personal-adaptability-training-protocol-2026-09-28.md`
- `personal-anchor-learning-protocol-2026-09-28.md`

## Findings

The first experiment trained through the personal residual learner, with a
matched generic-only control. Both used the same starting model, 32 training
writers, 640 episodes per arm, augmentation and optimization schedule. All
checkpoints are final-epoch checkpoints; no best-development selection was used.

These are correct top-ranked **isolated characters out of 772 eligible queries**
from eight previously inspected development writers. All 97 classes compete.
Four exact/normalized-copy queries remain present but excluded. This is not
full-chord accuracy, calibrated trust, fresh-device evidence or a sealed benchmark.

| Model | Without personal lessons | With 16 lessons | With 97 lessons |
| --- | ---: | ---: | ---: |
| Original visual encoder | 609 | 602 | 628 |
| Matched generic-only fine-tuning | 613 | 612 | 625 |
| Personal-objective fine-tuning | 617 | 614 | 624 |
| Original encoder + untaught-shape preservation prior | 609 | 614 | 628 |

**Do not promote the fine-tuned model.** Its better generic result does not
establish better personal learning. With a small profile, adaptation still makes
three fewer correct reads than its own generic head; the full profile also loses
four correct reads versus the original personalized model.

The sparse-profile breakdown identifies a concrete mechanism: all 29 new errors
with the original personal learner, and all 24 with personal-objective training,
are on **untaught labels**. Taught-label learning helps, but its corrections also
distort other classes. This is not a particular user's handwriting exception.

The fixed follow-up adds zero-correction constraints at public training feature
means for untaught labels, with no thresholds or scalar tuning. It changes the
personal fit, not the visual encoder, app baseline, examples or expected answers.

- Against the original generic model, sparse-profile gains/harms change from
  **22 gains / 29 harms** to **10 gains / five harms**.
- Taught-label reads change from 103/128 generic, to 124/128 unanchored personal,
  to 112/128 anchored personal. The constraint gives up useful recoveries too.
- Untaught-label reads are 506/644 generic, 478/644 unanchored and 502/644 anchored.
- Directly against the original personal learner, the anchor method recovers 25
  previously wrong reads but loses 13 previously correct reads: net +12, not an
  unqualified improvement for every input or writer.
- A full97 profile has no untaught anchors and exactly preserves the prior
  residual learner's outputs. An empty profile preserves generic output.

## Verification and evidence

The matched training experiment was repeated from the same frozen starting
checkpoint: both arms' entire checkpoint tensors are bit-identical, as are all
prediction/rank scores, episode plans and novelty exclusions. The initial attempt
to compare repeat reports ran before evaluation finished and reported a missing
file; the same live process was allowed to finish and the comparison then passed.
The anchor experiment was also repeated: its public anchor-bank bytes and
complete reports are identical. All 776 identities and the shared 772-query
denominator were checked independently. Anchor report SHA-256:
`3abe14e0845da4488a65db808455f1df8695df8515fe3a2d92c04862e3014391`.

**31 focused Python tests passed**, zero skips/failures, with runtime arithmetic
warnings treated as errors. They include independent NumPy/torch solver parity,
finite-difference gradient checks through personal fitting, frozen BatchNorm and
starting weights, class balance, writer/session separation, copy exclusion,
empty/full-profile limits, independent anchored normal equations, novel-label
handling, and changing query answers without changing predictions.

Evidence directory: `/tmp/iChartPersonalAdaptability-20260928.vxltRt/`.

- `run-01/`, `run-02-repeat/`: protocol/code/source bindings, complete episode
  plans, final weights, histories and per-query/per-writer results.
- `anchors-01/`, `anchors-02-repeat/`: frozen follow-up protocol, public feature
  anchor bank and complete results.
- `final-personal-tests.log`: the 31 executed focused tests.

The original source/checkpoint remain unchanged. The preserved private profile
and eight-run journal retain SHA-256 `96ca9e99461118c1383f8e04a8ac37eb4b23569022cac572586a746973777e29`
and `dec7d1190d53a6159d0cee2a07caf8f9d6a9c23fdd62cd0816bd9156a2b7418e`.
Those private data were not used to train, fit or select this experiment. The
20 reserved public writers were not rasterized, fitted or predicted.

## Next implementation boundary

The anchor prior is a research candidate, **not yet an app implementation**.
Carry its exact frozen math into a comparison-only Swift learner and verify
Python/Swift/Core ML parity before evaluating it on exact full-chord ink. Retain
the original comparison alongside it and keep disagreements visible. Do not
replace the live reader, fit confidence cutoffs to this development set, or ask
the user to repeat the same known chords to manufacture a quality claim.

General musical-symbol/suffix representation remains unresolved: UJI does not
provide `#`, `/`, `+`, `△` or `ø`. Fresh complete chords in both chart styles and
independent-writer evidence remain required. No device install, release, server
mutation, commit or push occurred in this pass. The long goal remains active.

Subsequent implementation: the comparison-only Swift port, actual Core ML parity
and full-chord replay are now complete. The latter did not repair the known
Rhythm endings. See [app comparison follow-up](personal-anchor-app-comparison-2026-09-28.md);
the research result is not promoted to the live reader.
