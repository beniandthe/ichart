# Fixed cross-writer representation experiment

Frozen before fitting or inference, 2026-10-01. Research/comparison only.
No private handwriting, live recognizer, profile, chart, telemetry, install or
acceptance-policy change is part of this experiment.

## Question

Does explicitly training the existing runtime embedding to place the same
character from different writers nearby improve general recognition and the
fixed, optional anchored-linear learner without damaging untaught characters?
This is a representation intervention, not a tuning pass over the rejected
local residual head, a new OCR engine, or a handwriting-specific rule.

This is an application-specific joint supervised-contrastive regularizer, not
a reproduction of the original paper's two-view pretraining/projection recipe.
Reference: [Supervised Contrastive Learning](https://arxiv.org/abs/2004.11362).

## Fixed fit

- Exact UJI Pen Characters v2 source SHA-256:
  `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
- Existing strict adapter and historical hash-based 32 training / 8 observed
  development / 20 reserved writer split. Only the 6,208 training-role source
  records may be rasterized during fit. Reading complete source metadata to
  validate completeness does not authorize reserved feature construction.
- Original `PersonalVisualEncoder`: raster-only CNN, 128-dimensional normalized
  runtime embedding, raw-embedding 97-class classifier. Original affine
  augmentation, unchanged feature encoder and vocabulary.
- Two arms, trained from scratch from identical seed-29 initial tensors:
  `crossEntropyControl` and `crossWriterContrastive`.
- Control: 97-way cross-entropy. Candidate: same cross-entropy plus **0.1** times
  the mean per-positive negative log contrastive loss (outside-log/Eq. 2).
- Temperature **0.07**, normalized runtime embedding, same-label/different-writer
  positives. Same-label/same-writer pairs, including self, are excluded from
  the denominator rather than treated as negatives. Different labels are
  negatives. Invalid/empty/nonfinite contracts fail; anchors without positives
  are explicitly skipped and an all-skipped batch contributes differentiable
  zero. The actual frozen sampler gives every training anchor a positive.
- Each epoch has **32 batches of 194 rows**. Every batch contains two records
  for each of all 97 labels, always from different writers. Per-label seeded
  pairing/session order uses each training source exactly once per epoch.
  Both arms consume identical batch plans and augmentation draws.
- 30 epochs, final epoch only; AdamW learning rate 0.001, weight decay 0.0001,
  cosine schedule over 30 epochs; deterministic algorithms, four CPU threads.
  No seed, checkpoint, coefficient, temperature, support or threshold sweep.
- Preserve exact protocol JSON/Markdown, source/code/runtime identities,
  initial tensors, all epoch plans/augmentation identities, final weights and
  training history. Neither fit may infer development/reserved samples.

The original operational strong Core ML encoder is retained. Its original
PyTorch checkpoint/complete fit receipt is unavailable, so this new CE control
is not a continuation of, or exact recreation of, its weights. Historical
strong-encoder scores are context, not this experiment's causal control.

## Frozen descriptive development evaluation

After both final checkpoints exist, bind them and the prediction/scoring code
before inference. Reuse the exact public app-local-transfer input geometry:

- Fixture SHA `d3de7699f1175b8a77aab37eaf64ab2a3e47042cd58cc7416839122cd4baa55d`.
- App profile/report SHA
  `52b97f84d40998a22f2c10402ff7ece5dae57a4f54cc744c11e0284d9015a618`.
- Eight previously observed development writers; all 97 session-two queries
  per writer, **776 per task per arm**, no invalid-row dropping.
- Mandatory `core10` setup labels `A B C D E F G b - 7` and `catalog21` setup
  labels `A B C D E F G b - 7 m o 6 9 2 4 5 1 3 ( )`.
- Use the exact app-stored normalized/decimated support strokes from the
  preserved prepared profiles, not a newly invented Python normalizer. Verify
  each support raster against its recorded Swift raster identity before fit.
- Make a fresh public anchor bank per model from its 32 training writers only.
  Keep the existing anchored-linear residual formula/regularization 0.1 and
  full 97-class competition fixed. Do not include the rejected local/RBF head.
- Freeze all generic and anchored-personal score vectors, feature vectors,
  rank receipts, support/model/anchor bindings before opening query truth.
  Do not rescue case/notation aliases or use parser output for scoring.
- Report raw and the pre-existing source-only no-copy view; every row retained.
  Per writer, taught/untaught, available-app/non-app, gains, harms, net deltas
  and complete discordant IDs are mandatory. App-normalized support and
  Python-model evaluation are not Swift/Core ML application-runtime parity.

The eight writers have been repeatedly used in development. This evaluation is
descriptive and a futility screen, not new-writer validation or a ship gate.
The 20 reserved writers remain un-rasterized and un-inferred in this pass.

## Fixed disposition

Only plan a separate, frozen reserved-writer/runtime-parity gate if all hold:

1. Candidate generic raw/no-copy correct counts are at least the CE control.
2. Candidate anchored-personal correct counts strictly exceed the matched CE
   anchored-personal counts for both tasks in raw/no-copy views.
3. No writer or untaught stratum has a negative candidate-personal versus
   CE-personal delta, for either task in raw/no-copy views.
4. Candidate personalization strictly improves its own generic counts for
   both tasks in raw/no-copy, with **zero untaught harms** against its generic
   rankings. Untaught safety is not replaced by overall net improvement.

Otherwise reject the fixed candidate for advancement; retain all outcomes and
do not retune it against these same queries. A pass is not authorization for
live promotion and does not prove chord recognition quality. UJI contains only
21 of the app's 26 glyph labels: `# + / ø △` are absent. Literal `b`, `o`, `-`
remain visual/codepoint proxies, not certified musical forms. Isolated glyph
evidence cannot establish natural-chord ownership, grouping, review UX,
calibrated confidence or fresh accuracy in either chart style.
