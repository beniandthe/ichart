# Bound execution of the single centroid-transport experiment

This supplements the fixed mathematical protocol, without changing its model,
loss, learning schedule, support catalog, acceptance conditions or claim ceiling.
Protocol SHA `0ab2689ae4042e855470ccbce08c1df289a71c1629190c8d6870e0f008fd4769`.
Base HEAD `160aa31594903508e241802e21ca83ec447de849`; existing dirty worktree.
No actual centroid or head outcomes have been inspected when writing this file.

## Training-domain centroid preparation

Use the retained raw public source at
`/Users/benirossman/.local/share/ichart/recognition-development/public-grouping-20260930.BWxcGv/source/ujipenchars2.txt`,
SHA `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Hash the complete source, then select only WORD blocks for the pinned A16
encoder-fitting writers. Skip all other coordinate payloads opaquely; do not
call the unfiltered source loader or instantiate excluded writers' strokes.
Source labels of A16 are permitted training labels, not query truth.

Validate the selected exact 16-writer x two-session x 97-label grid in sourceID
order against retained raw raster and normalized-trajectory fingerprints.
All 3,104 raw rows contribute, including the 12 rows whose stored setup shapes
were unavailable. Do not apply query-copy or stored-availability exclusions to
these fitting-domain rows. Use raw source strokes, no setup normalization or
augmentation, and the exact frozen fitA encoder/feature implementation.
Load and validate the pinned checkpoint metadata/schema/state; set eval mode,
no gradients, deterministic CPU/four threads, original batches of 128.

Preserve 3,104 float32 unit outputs and their source rows. For each ordered
vocabulary class, take float64 means per session (16 rows each), average those
two means and L2-normalize, rejecting nonfinite/zero norms. Outputs:
`centroids.npz` (one centroids float64[97,128] array),
`training-features.npz` (one features float32[3104,128] array),
`training-rows.json` (canonical vocabulary and new fitA source rows), and
`centroid-receipt.json` (canonical exact source/parent/role/checkpoint/state,
code/runtime, grid and artifact hashes). Verify inputs/state unchanged afterward.
This is in-sample training-domain inference only, not new-writer recognition.

## Head experiment and prediction/answer boundary

Preparation pins the exact centroid receipt SHA, checks parent and role bindings,
and materializes only the metaFit B8 feature/logit rows (1,552) from the existing
fitA-generated parent. Do not mix fitB-generated features or prepare failed
validation/development/reserved/private tensors. Float32 parent features/logits
are promoted to float64 without changing their geometry or normalization.

Freeze all eight LOO fold plans before any head update. Each fold has seven
fitting writers and a disjoint eighth writer. Fix source-hash ordering and donor
mapping in code before execution. For fitting episodes, donors are a derangement
within the seven fitting writers. For OOF episodes, donors come only from those
seven. Correct/unrelated supports share exact app-domain labels, session and K.
No availability-driven substitution from the rest of the 97-way vocabulary.
Insufficient declared support fails before fitting; unavailable source rows
remain explicit. Each fold executes 30 x 28 = 840 updates, total 6,720, final
checkpoint only. Record finite losses/gradients, meaningful parameter deltas,
checkpoint/reload identity and the expected algebraically canceled final bias.

Training queries screen encoder/source-support copies, but are not excluded
merely because they themselves are head-fitting examples. OOF queries additionally
screen the complete seven-writer raw/stored head-fitting source union. Freeze
every exclusion reason before prediction; scheduled/raw diagnostics are not
silently dropped. No outcome-based removal or recipe adjustment.

Keep training targets scoped to each fold's seven writers. Store OOF scoring
truth separately; the fit/predict loader must not read it or query-label metadata.
After a fold checkpoint is frozen, forward accepts centroid/support/query/logit
tensors only, never query truth or source identities. Commit every full97 generic,
correct-support and unrelated-support OOF probability packet before scoring.
Scoring requires the exact prediction digest before joining held-out labels.
Report all writer/task/session/stratum outcomes, missing app glyphs, non-app
stress classes, scheduled/eligible/excluded/unavailable counts and distinct/repeated
sources. Invalid predictions remain failures, not removed samples.

## One result, no rescue

Apply the original fixed screen separately per K: strict improvement over generic
and unrelated support, no negative writer net, zero untaught harms. Failure
rejects the single recipe; no width, loss, centroid, threshold or epoch search.
No final B8 fit is executed by this runner. A pass requires a separately reviewed
final-fit step before fresh handwriting, runtime parity and app integration.
Reserved writers remain untouched; all B8 evidence is previously used internal
reuse, not fresh or confirmatory accuracy. Keep the app/profile/ink unchanged.
