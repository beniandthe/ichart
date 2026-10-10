# Stroke direction sensitivity diagnostic

Freeze this protocol and new diagnostic code before running transformed inputs.
The completed HWRT stroke-field candidate remains rejected. This diagnostic
asks whether its predictions change when the visible image is identical but
pen-direction features reverse. It does not fit, calibrate, select, rescue, or
promote either model, and cannot establish fresh handwriting or personalization
benefit. The existing development answers are already known; this is not a new
blind accuracy trial.

## Fixed inputs and transformation

Use only the preserved HWRT stroke-field run under
/Users/benirossman/.local/share/ichart/recognition-development/hwrt-stroke-field-20261003.8ZTPn0.

- Fit receipt SHA256: 1ca3d5d29dd292312a386d27c2e0b4a169ac9d1d1fa1bd56acb54685e07216a0.
- Development receipt SHA256: e1f49705e3bfa249287d13ef011457b057763da17b228e3b4802d13a9150bf3f.
- Original predictions SHA256: ee3aab3135b609117c9556ffbd119bb26424bffb43b277db7f81116d82c303f0.
- Original score SHA256: 13cddbf669ced84f13ffd68f947149dc38519bfecae2d88196f2b00eb3fff836.

For every one of the 1,987 existing five-plane fields, perform exactly one
algebraic transform: occupancy stays identical, tangent x and y are negated,
and the start and end planes are exchanged. No geometry rotation, reflection,
stroke permutation, cropping, source-specific rule, timing, or label change.
Apply the transform to all rows, not selected errors or writers.

This field-space operation corresponds algebraically to reversing direction
within every stroke, not reversing acquisition order between strokes. Validate
against synthetic point-reversed geometry, including curved, multiple,
crossing, retraced, zero-length, and dot strokes. Explicitly allow feature
encoder rounding in those synthetic comparisons. Do not claim byte-exact
source-point re-encoding for every real drawing: actual source rows are not
reopened. Occupancy preservation within this diagnostic is byte-exact.

## Execution boundaries

Reuse the final models through the strict frozen loader, unchanged CPU runtime
of four threads with deterministic algorithms, and the original batch size
128 and row order. Both models remain in evaluation mode with unchanged
weights and batch-normalization state. No private ink, profile, training
examples, reserved writers, raw source records, or optimizer is opened.

Authenticate receipts, inputs, fields, original prediction bytes, and code.
First reproduce both arms' original logits and embeddings byte-exactly at
Float32 precision for every row. If this fails, stop before transformed
inference and classify the replay problem; never overwrite old predictions.
Then infer the transformed fields, retaining complete 102-score and
128-embedding vectors, opaque IDs, hashes, and failures in fresh output files.
Require the image-only control's transformed outputs to be byte-identical to
its reproduced original outputs. Do not silently drop a failed row.

Prediction opens blind fields and IDs but never opens or hashes truth. A
separate scoring command first authenticates the saved transformed prediction
bytes, then opens truth and the original score. Recheck bound inputs, code,
model state, and protocol before publication. New outputs never replace the
original fit, score, or failed advancement verdict.

## Fixed measurements and interpretation

Report raw winner changes, permitted-output changes, complete-output failures,
logit/embedding changes, and image-control equality. After the separate truth
join, report original versus reversed correct counts, gains, regressions, and
permitted wrong/no-read counts for UJI, its 41-label chord-fragment subset,
out-of-domain UJI, HWRT, each of the five mapped shapes, and all eight writers.
Report the original gain and harm cohorts descriptively, without selecting an
operating rule from them. Repeat raw and the existing seven-row copy-excluded
views; do not invent new exclusions. No source-pooled accuracy.

A prediction change with fixed occupancy establishes sensitivity to these
directional channels in the frozen model. It does not show that reversal is a
natural writing style, that this sensitivity caused the original regressions,
or that removing direction would improve recognition. Zero changes would not
prove full stroke-order or partial-stroke reversal invariance. No averaged
outputs, direction selection, test-time ensemble, new threshold, or writer
exception is permitted. Any subsequent intervention requires its own fixed
training-only design and evaluation; this diagnostic cannot promote a model.

Published stroke-order-free recognition work distinguishes spatial geometry
from the ordering of pen actions, but does not validate this model or this
counterfactual. See [Okumura, Uchida, and Sakoe](https://www.cs.ucf.edu/courses/cap6105/fall2010/readings/Okumura.pdf).
That paper is background only; the local source and measured outputs decide
this diagnostic.
