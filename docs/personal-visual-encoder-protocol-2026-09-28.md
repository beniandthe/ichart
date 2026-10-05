# Personal visual encoder: fixed development experiment

This is work on iChart's customizable ML layer, not another OCR engine. The
previous linear head over fixed geometric features produced 222/280 root-letter
matches versus 218/280 nearest-shape matches. Its 12 regressions prevent promotion.
This experiment changes the learned visual representation, then measures whether
explicit first-session personal examples help on a second writing session.

## Frozen before training or development predictions

- Public source: Prat et al., [UJI Pen Characters v2](https://doi.org/10.24432/C5FG8S),
  CC BY 4.0. Unmodified text SHA-256
  `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
  Preserve all coordinates/stroke boundaries; no invented timing. This public
  research source is not admitted to the production consent/corpus registry.
- Keep the 20 official `tst` writers unused by rasterization, fitting, or inference.
  Sort the 40 `trn` writers by SHA-256 of `personal-encoder-v1:` plus writer ID.
  The first eight are model-development writers; the remaining 32 train features.
  All 40 appeared in the previous geometric experiment: the eight are writer-held
  out from this encoder's training, **not** a fresh sealed product test.
- Fit on both sessions of all 97 source character labels for the 32 training
  writers (6,208 examples). Do not merge case, accents, digits, or punctuation.
  No device ink, profile labels, or known chord answers enter encoder training.
- Input is the existing Swift/Python `chord-ink-features-v1` 256x96 raster,
  aspect-preserving, foreground 1/background 0. No new ink normalization.
- Encoder: 2x average pooling; four 3x3 stride-2 convolution blocks with
  16/32/64/64 channels, batch normalization and ReLU; flatten 64x3x8; linear
  projection to 128 features. L2-normalize features for personal matching.
  A separate 97-label linear head on raw features supplies training supervision.
- Fixed training: seed 29, CPU deterministic algorithms, four threads, 30 epochs,
  batch 128, AdamW learning rate 0.001, weight decay 0.0001, cosine schedule to zero.
  No early stopping, parameter sweep, or selection against development answers.
- Training-only affine augmentation: uniform rotation +/-8 degrees, uniform
  scale 0.9..1.1, translation +/-3% width and +/-5% height. Correct rotation for
  the non-square raster aspect ratio; bilinear sampling, zero padding,
  `align_corners=false`. Never flip or relabel. Evaluation has no augmentation.
- Main development task: uppercase A-G, seven competing labels. Fit the existing
  class-balanced ridge formulation (lambda 0.1) to a writer's seven session-one
  embeddings, then rank their seven session-two samples. No query labels in fit.
- Controls: frozen geometric and fixed-feature ridge results joined by exact
  source digest/query identity from the previous Swift run; the same personal
  ridge procedure on the untrained encoder; learned-embedding nearest example;
  and the trained generic head restricted to the same seven labels. Also report
  generic 97-label performance on all development samples separately.
- Explicitly flag exact normalized support/query duplicates, identical query
  rasters in encoder training, and support/query raster collisions. Exclude them
  from novelty counts, not from the raw record. Report every writer, query,
  support identity, gain and harm. Do not call scores probabilities or trust.

## What this does not prove

UJI contains isolated characters, not full chords or the full musical-symbol
vocabulary. Root accuracy cannot establish suffix reading, segmentation,
open-set rejection, live Pencil latency, or usefulness of repeated corrections.
The model stays comparison-only. No live app recognition, acceptance threshold,
profile, chart, teaching policy, or native baseline changes in this experiment.
No export to production assets is authorized by a successful development score.

Learning an embedding for few-example matching is motivated by
[Prototypical Networks](https://proceedings.neurips.cc/paper/2017/hash/cb8da6767461f2812ae4290eac7cbc42-Abstract.html).
This first encoder uses supervised character training, not that paper's episodic
objective. Determinism is bounded to the recorded runtime/platform following
[PyTorch's guidance](https://docs.pytorch.org/docs/2.7/notes/randomness.html).

The next decision must follow the measured benefits **and regressions**, not
force this model into the app. Even a positive result requires musical-symbol,
full-chord, Swift/Core ML parity and fresh in-app paired evaluation.

## First result and fixed follow-up

The first run completed all 30 epochs without model/parameter selection. On the
eight development writers' 56 session-two A-G samples, learned personal ridge,
learned nearest example and the generic seven-way classifier each read 56/56.
Old geometric and fixed-feature ridge each read 43/56; untrained-encoder ridge
read 28/56. There were no copy exclusions. The generic 97-class head read
1,229/1,552 across both development sessions. These are different tasks.

The A-G result supports improving visual features but has a ceiling: it does
not demonstrate an additional personalization benefit over the generic head.
Before examining further predictions, freeze a secondary diagnostic using the
**same final checkpoint**, with no retraining or changes to the primary report:

1. Fit each development writer's personal ridge to all 97 explicitly labeled
   session-one examples; predict their session-two samples with all 97 labels
   competing. Compare against the generic 97-way head on the exact same queries.
   Report copy exclusions, gains/harms and per-writer results. This wider task
   tests the learning mechanism, not music-symbol or chord recognition.
2. Export the embedding only to a research-only Core ML package outside app
   assets. Check Python/Core ML feature parity on all 112 A-G support/query
   samples. Pass original trajectories, raster hashes, embeddings and personal
   rankings to Swift tests using the actual app rasterizer and ridge solver.
   No app recognizer, confidence, model manifest or installed binary changes.

No held-out writer is reassigned and the official 20 test writers remain unused.

## Verified results and decision

The encoder has 269,825 training parameters. Repeating the fixed 30-epoch run
produced **bit-identical checkpoint tensors**, with all 56 primary predictions
unchanged. Checkpoint SHA-256:
`5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`.

The 97-way personal follow-up evaluated 776 second-session queries. Four dot
rasters duplicate training/support shapes and are explicitly excluded from
novelty counts. On the same 772 eligible inputs, the personal head reads
**624/772** versus **609/772** for the generic head: **103 gains, 88 harms**.
Five writers improve and three worsen; one loses eleven correct results.
The small aggregate gain does not justify unconditional personal replacement.
This result is not comparable directly to the seven-class root task or to the
97-way generic result that includes both sessions.

### Runtime and numerical checks

- The pinned macOS NumPy runtime raised matmul divide/overflow/invalid warnings
  even on finite normalized 97x128 inputs. A new strict-arithmetic test reproduced
  the failure. Explicit contractions preserve the same ridge equation and remove
  the warning; an independent normal-equation residual test passes below 1e-11.
  No warnings are suppressed and regularization is unchanged. All 776 wider
  predictions/exclusions match the pre-repair report.
- Embedding-only export uses float32, CPU-only Core ML. Python/Core ML feature
  error is at most **2.682209014892578e-7** over all 112 A-G support/query inputs.
- Swift uses the actual app rasterizer on original trajectories: all 112 raster
  hashes and embeddings match; the actual `PersonalInkBalancedRidge` solver
  reproduces all 56 ordered rankings and scores within 1e-4. The harness's
  initial `/tmp` versus `/private/tmp` package-path digest error was fixed by
  hashing enumerated relative names. No mismatch was ignored.
- The final verified research package digest is
  `8e188ee85e90b8bc9a81ec742e827580d1cfece50d1af3017f385aaf13201d3c`.
  It is not in app assets and is not a production model manifest.
- Final gates: **164 Python tests passed**, with RuntimeWarnings treated as
  errors, and **44 Swift/macOS tests passed**, both zero failures/skips. These
  include query-label independence, copy exclusions, public/private runtime
  checks and existing learning/arbitration invariants. No new iOS build or
  physical-device handwriting test is claimed by those results.

### Exact private replay, not fresh accuracy

An opt-in Swift diagnostic fits only the existing profile's **12 explicit glyph
lessons**, using the frozen learned embedding, then replays the v26 device trace.
It preserves all 30 profile examples and source trace bytes. Whole-chord labels
are not turned into inferred glyph lessons. No profile teaching, output
acceptance, or chart rendering occurs. The existing stroke grouping is unchanged.

Across 12 observations / eight unique inputs:

- Previously misranked E/G and D/E roots now produce the intended E-flat-7 and
  D7 tokens in the simple-sheet samples; the Rhythm D7 also ranks D7 instead of
  the native B7. The final rewritten Rhythm middle input composes E-flat-7.
- The two major-triangle inputs still compose invalid `BbD7` and `EbD7`.
  Their root/flat/7 readings improve, but the saved profile has **no triangle
  label**. The forced-ranking diagnostic cannot produce an unlearned triangle.
  Invalid compositions remain invalid, not repaired using intended answers.

These inputs were already used for development and are not an unbiased accuracy
estimate. Personal outputs are uncalibrated ranks, not accepted app suggestions.
The remaining failure calls for musical-symbol coverage and trustworthy
composition/abstention, not an E/D/B-specific substitution or lower threshold.

Evidence directory: `/tmp/iChartPersonalEncoder-20260928.VjJgcH/`, containing
the first/repeated training runs, per-writer reports, pinned environment, weights,
Core ML parity packets, strict-numeric red/green logs, Swift gate and private
read-only replay. Dataset, model weights and private ink remain outside Git.
No installed-app change, new device build, production deployment or upload took
place. Fresh in-app checks in both styles and independent-writer full-chord
validation remain requirements; the long goal is **not complete**.
