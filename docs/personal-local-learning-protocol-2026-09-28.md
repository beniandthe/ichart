# Local personal corrections over the existing ML representation

Fixed development experiment, written before new predictions. This is a
different personal fitting rule for the same frozen visual model, not another
OCR engine or a replacement for the app's live recognizer.

## Motivation and fixed model

Sparse-profile experiments showed that a global linear correction can improve
taught labels while harming untaught ones. Public mean-shape anchors reduced
those harms but also lost recoveries. Test whether a nonlinear local residual
fit can confine a lesson's effect to similar shapes.

Use the original encoder weights SHA-256
`5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`.
Do not retrain it, change its 97 labels, rasterizer, 128 unit features, or
baseline scores. Keep the same 32 training / eight development / 20 reserved
UJI writers. Reserved writers are never rasterized, fitted or predicted.
No private handwriting is used in this experiment.

## Local learning rule

Kernel ridge regression gives a closed-form nonlinear fit using a kernel;
the [official method documentation](https://scikit-learn.org/stable/modules/kernel_ridge.html)
describes this distinction. This experiment applies it to personal residuals,
not to calibrated classification probabilities.

- Form `k(x,y) = exp(-||x-y||² / width)` over the existing unit embeddings.
- Set `width` once from **training writers only**: the median positive squared
  distance between a writer's session-one and session-two examples of the same
  character. Exclude normalized-trajectory copies, raster copies and zero
  feature distances. Preserve all pair identities and exclusions. No width
  search or adjustment after development predictions.
- Retain lambda `0.1` and the existing per-label class balance. For explicit
  lessons, `D[i,i] = 1/sqrt(number of lessons with label_i)` and
  `R = oneHot(explicitLabels) - genericScores`. Solve
  `(D K D + 0.1 I) beta = D R`, then predict
  `genericScores(query) + k(query, lessons) D beta`.
- Fit only explicit support labels. All 97 generic classes still compete.
  Explicit novel symbols may be appended with zero generic mass, as in the
  existing learner, but are not fabricated from whole-chord labels.
- Empty profiles reproduce the generic result. Duplicating the same lesson
  within one label must not change its total fitting weight. Validate finite
  unit features, normalized base scores, vocabulary and dimensions. Store
  immutable owned arrays; fitting must not mutate callers' inputs.
- Keep this candidate separate from both existing personal learners. No
  expected-answer lookup, grammar rescue, confidence cutoff, per-writer rule,
  per-chord exception, private profile edit, or automatic rendering.

## Comparison and next-step gate

Reuse the frozen sparse16 and full97 support sets, session-two queries and
copy exclusions from `personal-adaptability-v1` and the anchored follow-up.
Require all 776 identities and the shared 772 eligible-query denominator;
compare generic, linear personal, anchored personal, and local-kernel personal.
Report correct counts, paired gains AND harms, taught/untaught results and
per-writer results. Query answers enter scoring only after predictions are fixed.

Advance to a separate app comparison only if both sparse and full correct
counts are at least the best existing personal result for that profile, and
sparse harms against the generic reader are no greater than the anchored
method. Report per-writer losses even if this development gate passes. Do not
weaken the gate or tune the width to obtain a positive result.

Validate the dual solve against independent weighted normal equations, class
balance, empty/novel-label limits, lesson/vocabulary ordering, input ownership,
query-label isolation and training-only width construction. Bind reports to
source, original weights, frozen protocol/code, training-pair width artifact,
and both earlier reports. Repeat a completed experiment to verify determinism.

These eight development writers have already been inspected; this is not a
sealed benchmark or fresh-writer validation. UJI contains isolated characters,
not complete chords, and lacks several musical symbols. Even a positive result
needs Swift/Core ML parity, full-chord checks, genuinely fresh handwriting in
both chart styles, and independent-writer evidence before any accuracy or ship
claim. A negative result stays visible and is not installed into the app.
