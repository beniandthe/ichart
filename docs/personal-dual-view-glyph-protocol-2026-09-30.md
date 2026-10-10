# Shared glyph identity: fixed raster/trajectory information experiment

Freeze this protocol, model, fit/prediction implementation, scorer and synthetic
tests before training or development inference. One fixed experiment; no
checkpoint, seed, architecture, threshold or writer-role search after results.
This is customizable-pipeline research, not an alternate OCR engine or a live
acceptance change.

## Question and boundaries

The current glyph encoder retains aspect ratio but sees only a raster. It
therefore loses acquisition order, stroke direction and pen-lift topology.
Investigate whether the existing trajectory representation adds useful shared
identity information without sacrificing writer-level results. The WACV
[online-handwriting study](https://openaccess.thecvf.com/content/WACV2022/html/Ott_Joint_Classification_and_Trajectory_Regression_of_Online_Handwriting_Using_a_WACV_2022_paper.html)
provides research motivation for using trajectory information; it does not
establish a benefit for chord symbols, this architecture or this app.

This experiment assumes supplied isolated-character ownership. It cannot solve
stroke ownership, natural full-chord reading or trust calibration. Current
personal profiles, private handwriting, app acceptance, ink and baseline remain
untouched. No learned candidate becomes production eligible through this gate.

## Source and roles

- Unmodified public UJI v2 text SHA-256:
  `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
- Preserve the existing `uji_personal.split_writers` 32/8/20 roles. Both sessions
  of all 97 labels for the 32 training writers give 6,208 training glyphs.
  Both sessions of the eight already-observed development writers give 1,552
  queries. These eight are not fresh writers or a sealed quality test.
- Strict source parsing may enumerate the 20 official test writers to validate
  source completeness. Do not transform, encode, fit or infer their records.
- No HASY/HWRT, generated trajectories, private labels or private ink. UJI
  contains no timing: do not invent timing or claim a timing benefit.
- Keep the pinned prior `public-identity.json` report, SHA
  `c4b6acc6caf76e0f7d0af9ee8036cd672673f1690e790fee3dcf14fea329c01b`,
  only as a separately named historical Core ML inference reference. Its
  source-owner isolated route has 1,229/1,552 exact raw identities. It is not a
  trainable checkpoint, matched architecture or fresh evaluation.

## Fixed model and optimization

All three arms use the identical parameterization and initialization. Input
information masks, not architecture size, define `rasterOnly`, `trajectoryOnly`
and `dual`. Zero an inactive branch after projection. Do not alter targets or
allow a desired answer into model calls.
Identical nominal parameters do not mean identical effective capacity: enabling
the second trainable branch changes both representation and active capacity.
The causal contrast is enabling that branch in this fixed architecture, not
proof that stroke order alone causes a benefit. Bind checkpoint identity to its
arm mask; never enable an inactive branch after fitting.

- Raster branch: current `PersonalVisualEncoder` convolution and raw projection:
  average pool 2; four 3x3 stride-2 Conv/BatchNorm/ReLU blocks, channels
  16/32/64/64; flatten 64x3x8; linear 128.
- Trajectory branch: existing `chord-ink-features-v1` [256,10] tensor, selecting
  x, y, dx, dy, arc-step, stroke-start, stroke-end and valid (eight channels).
  Time value and time availability channels are excluded even when supplied.
  Conv1d 8→32 k7/p3/ReLU; 32→64 k5/s2/p2/ReLU;
  64→64 k3/s2/p1/ReLU; adaptive average pool 8; linear 512→128.
- Concatenate projected branches, linear 256→128, raw 97-way classifier;
  L2-normalize the fused 128 features for the unchanged personal ridge fit.
- CPU, four threads, deterministic PyTorch algorithms, seed 29. Reset identical
  initial tensors and the seed-29 permutation generator for each arm.
- 30 epochs, batch 128, AdamW learning rate 0.001, weight decay 0.0001,
  cosine learning-rate schedule to zero; cross-entropy only. No early stopping.
- No augmentation in any arm. This avoids unsynchronized trajectory/raster
  views. It differs from the historical raster experiment, so only the matched
  new raster arm supports the primary information comparison.
- Save and evaluate the fixed final epoch only. Fit every arm before any
  development predictions. Do not run a second tuned fit from these outcomes.

## Freeze before score

Fit and prediction are separate CLI processes. Bind protocol, code, source,
runtime, initial tensors and each final weight file with SHA-256. New exclusive
output directories only; reject aliases/symlinks and preserve old artifacts.
Assert equal parameter keys/count and bit-identical initial tensors for all arms.
Bind the domain-separated opaque-ID derivation in the code snapshot, without
including label-bearing source IDs in prediction output.

Prediction must retain every query and all three arms. It emits opaque IDs,
original source-index groups, exact raster/trajectory hashes, 128 features and
all 97 raw logits in the bound vocabulary order. It must not emit labels,
writers, label-bearing source IDs, correctness or intended chord text.
No model selection occurs in prediction. Scoring first validates frozen packet
bytes, code/fit/weight/source bindings and the complete cohort; only then join
the source labels. Expected labels cannot change frozen predictions.

## Endpoints and interpretation

Primary: exact raw 97-way argmax on all 1,552 supplied-owner development queries,
dual versus matched raster. Ties use bound vocabulary order. Record all paired
gains/harms, per-writer and per-label counts and complete confusion tables.
ASCII case-only misses are a separate diagnostic, not relabeled successes.
No grammar, canonical alias, lower matching rank or personal head selects the
primary answer.

Advancement to a subsequent blind app-domain glyph test requires all of:
dual gains exceed harms; exact two-sided writer-cluster sign-flip p < 0.05;
at least six of eight writers are non-worse; no writer loses more than 2/194
queries. The sign-flip statistic is the absolute sum of the eight per-writer
paired correct-count deltas; enumerate all 256 sign assignments and count
absolute statistics at least as large as observed, including equality. Writers
are the units, not 1,552 independent glyphs. Its symmetry/independent-writer
assumptions and eight-cluster limits still apply. Row-level exact two-sided
McNemar is descriptive only, not the advancement test. These fixed
development guardrails are not a statistical guarantee, calibrated trust or
authorization to ship. Report a failure without editing the rule or retries.
Trajectory-only and the historical Core ML output are secondary diagnostics.

Optional-personalization diagnostic: for each arm/writer, fit the existing
direct one-hot class-balanced ridge `personal_visual_encoder.fit_personal`
(lambda 0.1, no added generic logits and no residual targets) only to 97
explicitly labeled session-one
embeddings, and predict all 97 session-two embeddings before reading their
labels for correctness. Report generic-versus-personal gains/harms per writer.
No personal result overwrites generic outputs. Query labels do not enter fit.
This is 776 paired session-two queries, not the 1,552-row shared-model endpoint,
and is distinct from the current Swift residual personal head. Do not choose
between direct and residual methods after outcomes.

Retain all rows in primary counts. Separately mark query raster or trajectory
duplicates of training input and normalized source-trajectory fingerprints;
mark session-two duplicates of personal support likewise. Report novelty
counts with those copies excluded, never silently remove them from raw rows.
Copy detection uses source/features, not correctness. Normalization collisions
are not independent new handwriting. Freeze the exclusion rules before scores.

## Verification and nonclaims

Synthetic tests must exercise both branches, inactive-input independence,
timing-channel independence, finite shapes, deterministic identical starts,
source preservation and pre-encoding writer-role guards. Scorer tests must
exercise missing/duplicate/altered bindings, first-argmax selection, query-label
independence, paired denominators and exact McNemar arithmetic.
Also test writer-cluster sign-flip arithmetic and that duplicated correlated
rows cannot create additional writer units.

Retain source/model/code hashes before and after execution, actual nonzero test
case counts, fit histories, frozen logits, scores and independent count review.
No iOS build is necessary unless app/Swift code changes. Successful Python
training is not Core ML/Swift parity, iPad interaction or improved recognition
on genuinely fresh natural chords. All those requirements remain open.
