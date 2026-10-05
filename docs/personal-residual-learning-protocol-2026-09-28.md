# Personal correction learning: fixed development experiment

The learned visual encoder improved root discrimination, but fitting an entirely
new personal classifier caused 88 regressions versus its generic head on the
772 eligible wider-character development queries. This experiment keeps that
same frozen encoder and generic head, learning only a personal correction to
their normalized scores. It is part of the customizable ML pipeline, not an
alternate OCR-engine comparison.

## Frozen before predictions

- Reuse exactly `personal-visual-encoder-v1`, checkpoint SHA-256
  `5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`.
  No encoder retraining, private handwriting, or expected device answers.
- Keep the existing 32 training, eight development and 20 reserved UJI v2 writer
  split. This is further **development**, not sealed evidence. Reserved writers
  are not rasterized, fitted or predicted.
- Let `X` be a person's session-one unit embeddings, `P` the frozen generic
  softmax-normalized scores for those same inputs, and `Y` their explicit one-hot
  labels. Fit class-balanced ridge to `Y - P`, with the **same lambda 0.1**:
  minimize `sum_i w_i ||x_i W - (y_i - p_i)||^2 + 0.1 ||W||^2`, where
  `w_i = 1 / count(explicit label_i)`.
- At inference, rank `p_query + x_query W`. The generic model itself remains
  immutable. Empty lessons give zero correction. Correcting or deleting a lesson
  means fitting a new snapshot from the revised explicit data, not accumulating
  opaque state or learning from the model's own guesses.
- Softmax here is only a fixed numerical normalization (temperature one), not
  calibrated confidence. Corrected scores can be negative; do not clamp, call
  them probabilities, or give them acceptance authority.
- Evaluate the same session-one -> session-two seven-way A-G and 97-way character
  tasks. Compare generic, prior full personal head and new correction head on
  exactly the same identities/copy exclusions. Report gains **and harms**, every
  writer and every query. Query labels never enter any personal fit.
- No parameter sweep, identity/root-specific exceptions, reranking with intended
  answers, score thresholds, live app changes, or production promotion.

The objective uses standard [multi-target ridge regression](https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.Ridge.html),
but the residual-target choice is an experiment here, not a claim of published
recognition quality. Musical-symbol coverage, unknown-input rejection, fresh
full chords in both styles and independent-writer validation remain open.

## Measured result and runtime verification

The fixed residual experiment reads **628/772** eligible 97-way development
queries, versus **609/772** for the unchanged generic classifier and **624/772**
for the previous replacement personal head. Relative to generic it has **24
gains and five harms**. The replacement head had 103 gains and 88 harms: the new
method avoids many regressions but also gives up many recoveries. Aggregate
improvement does not authorize live replacement. All three read 56/56 in the
separate seven-way A–G task; that task shows no additional personal benefit.

The float32 CPU-only Core ML export retains both embedding and generic logits.
On 1,552 original development trajectories, maximum Python/Core ML absolute
errors are 4.3213367462158203e-7 (embedding) and 2.47955322265625e-5 (logits).
The actual Swift rasterizer and residual solver reproduce all 776 ordered
top-five query rankings/scores within 1e-4. Four duplicate dot inputs remain
explicitly excluded from the 772-query novelty denominator.

Package digest: `c51029092ea80e6d2621db4606f7051139177169dc9d036b89c9e74b2f5988f5`.
The runtime gate executed 14 Swift/macOS tests with zero failures/skips, including
the exhaustive parity test. Evidence: `/tmp/iChartPersonalResidual-20260928.4FAreZ/`.
No reserved writer or private handwriting entered training or the public fit.

## App comparison bridge, not model promotion

The next implementation adds the model to an explicitly opted-in **Debug-only**
Saved Chart Test comparison. It is not called by the live recognition session,
renderer, preview arbitration or chart mutation path. See
`personal-learned-app-comparison-2026-09-28.md` for its exact behavior, checks,
remaining complete-chord failures and reproducible packaging instructions.
