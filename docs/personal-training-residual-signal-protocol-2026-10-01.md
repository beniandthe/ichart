# Training-only residual signal diagnostic: fixed before execution

This is one diagnostic of the additive support-mean statistic, not a new
recognition recipe, quality evaluation or app candidate. Do not reuse the
rejected B8 centroid-transport outcomes for tuning. No optimizer, coefficient
search, encoder/scorer forward, new inference, private ink, development or
reserved tensors are permitted.

## Bound input

Use only the retained fitA A16 raw unit embeddings and their source rows from
the completed centroid preparation. The encoder was fitted on these writers;
leave-one-writer-out means do not make the query embeddings unseen-writer data.
All 3,104 rows, including 12 stored-shape-unavailable raw rows, stay present.

| Input | SHA256 |
| --- | --- |
| centroid-receipt.json | c4c895caee391b6076018244b9b5a8a19230c8052a95776d0d7459a90dea9bad |
| training-features.npz | 78f220cfe8052d847ba9c6119c747decd0c0243dd0d66b8ebd0413516aff5163 |
| training-rows.json | 0fd4d41c38070a43bc1e13ba89f38cd03f558a6876b1785f6d58dd9c89748c73 |

Require the exact A16 writers in that pinned receipt, the 16 x 2 x 97 source
grid, lexically sorted unique source IDs, full sorted 97-character vocabulary,
fitA generator, finite float32 [3104,128] unit embeddings, canonical bound row
JSON, and raw raster plus normalized trajectory SHA256 fingerprints. The receipt
must still bind the pinned fitA checkpoint/state and official public source.
Do not open the pooled crossfit feature file or any checkpoint for computation.

## Fixed computation

For each focal writer w and label c, compute an **unnormalized** float64 class
mean mu[w,c] using the other 15 A16 writers, first averaging each session's 15
embeddings and then the two session means equally. Never normalize this mean.
Use this same focal-excluding mean for the focal writer and all 15 donors.

Residual r[w,s,c] = embedding[w,s,c] - mu[w,c]. For each fixed task K,
estimate t[w,s,K] by averaging residuals over its exact support labels:

- core10: A B C D E F G b - 7
- catalog21: core10 plus m o 6 9 2 4 5 1 3 ( )

Predict opposite-session residuals only on untaught labels. Run session 1 -> 2
and session 2 -> 1 for every writer and both tasks (64 cells). For every query,
retain squared Euclidean residual errors for:

1. zero residual;
2. the focal writer's support mean;
3. each of the other 15 writers' same-task, same-support-session support means.

The unrelated control is the arithmetic mean of the 15 **errors**, not an
averaged donor vector or a favorable selected donor. All donors remain named
in the recorded output. No outcome-based donor/label selection is allowed.
Unit-embedding residuals are not passed into the generic classifier, whose
projection inputs are unnormalized. No recognition accuracy is computed here.

## Source-copy ledger and counts

For each query, compare raw raster and normalized trajectory hashes to the
other 15 writers' prototype/contributor rows and its own support rows. This
union also covers all unrelated support donors. Keep every scheduled record;
record each copy reason and matching source ID before geometry outcomes.
The primary aggregate uses only sourceOnlyNoCopy queries. Raw scheduled
aggregates are separate diagnostics, not a fallback to obtain a pass.

Scheduled exposures are core10 16 x 2 x 87 = 2,784 and catalog21
16 x 2 x 76 = 2,432: total 5,216, from 2,784 distinct query sources.
Report eligible/excluded/distinct/repeated counts by task and cell, including
zero-eligible cells explicitly. This uses raw geometry rather than the app's
stored setup shape, so it is an optimistic training diagnostic.

## Predeclared next-action screen

For **each** task, the primary no-copy mean focal error must be strictly less
than both zero and mean-unrelated error. In addition, for every writer/task,
its query-weighted mean across both directions must not exceed either control.
Finite outputs and nonempty eligible cells are required. No epsilon, statistical
threshold, task substitution, scalar fit, or later rescue changes this screen.

If all conditions hold, additive support contains evidence worth a distinct
query-canonicalization experiment (inverse style correction), with empty-support
identity and full97 competition. That still requires a new protocol and held-out
writer evidence; this diagnostic authorizes no model promotion.

If any condition fails, stop investing in a single additive support mean on
this representation as the next mechanism. Change symbol/style representation
or data coverage rather than tune transport/loss/scales on scored B8 data.
Failure does not reject every form of personalization.

## Publication and verification

Freeze this protocol and implementation/test hashes before the actual run.
Use exclusive fresh output outside Git. Publish a source-bound plan first,
then per-query geometry and the fixed screen. Recheck input/code hashes before
publishing. Independently recompute at least all cell and task aggregates from
bound vectors/rows, confirm the copy ledger and counts, and preserve evidence.
Do not modify the app, current profile, learning labels or chart ink. A nonzero
synthetic test gate is engineering evidence only.
