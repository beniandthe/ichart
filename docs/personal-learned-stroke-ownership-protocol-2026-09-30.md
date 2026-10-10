# Learned stroke ownership experiment v1

Frozen before fitting or inspecting this model's development predictions.
This experiment addresses a measured upstream limitation of the customizable
recognizer: geometric grouping decides symbol membership before learned glyph
classification. It does not replace the native recognizer, alter the visual
encoder, change personal lessons, consume private handwriting, or confer trust.

## Source, independence and roles

Use only the unchanged UJI Pen Characters v2 text, SHA-256
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Reuse `uji_personal.split_writers`: original 32 official trn writers for fitting,
SHA-first eight official trn writers for development, and all 20 official tst
writers sealed. Parsing the entire file for structural/source validation is
allowed; reserved trajectories must not be featured, fitted or evaluated.
The eight development writers have existing descriptive measurements. They
are independent of fitting, not fresh sealed product-test evidence. No private
profile, saved chord label, device ink, or writer-specific substitution is used.

The dataset provides isolated characters, not naturally written chords or the
complete musical vocabulary. Synthetic juxtaposition cannot establish natural
spacing, timing, connected-writing behavior or new-user product accuracy.

## Examples fixed without predictions

For each role, both sessions and all 97 records per writer are retained. Singles
use maximum point-derived dimension 32, translation to the origin. Pairs reuse
the prior `public-pair-v1:` SHA ordering inside writer/session and each record's
cyclic successor. First dimension 32, second 16 or 32, gap 3.2, 8 or 16, both
bottom aligned at y=32: six separate arms. Preserve every source point, stroke
boundary, order and metadata under translation plus uniform scaling only.
Zero-extent characters use scale one, with explicit accounting.

A frozen evaluation-only triple stress check uses `public-triple-v1:` ordering
and cyclic successors one and two within the same writer/session. Dimensions
are 32, 16, 16; both gaps 8; bottoms y=32. It is never training data and is not
used for model, threshold, checkpoint or hyperparameter selection.

Ground-truth membership supplies the binary same-owner target for every
unordered pair of source strokes, including within-character positives in
synthetic contexts. It never enters feature construction or the decoder. The
model does not receive labels, writer/source IDs, stroke ordinal, expected group
count, character logits, intended chords or chord grammar. Stroke indexes are
opaque ownership handles, not numerical features.

## New derived feature contract

Schema `stroke-affinity-context-v1`, 202 float32 values. This is separate from
the unchanged visual/raster schema. Reject nonfinite geometry, empty strokes,
more than 64 strokes or 8,192 total points. The new model can only assign whole
strokes; one uninterrupted stroke spanning multiple symbols is unsupported.

Equal-arc resampling to 32 points per stroke is feature computation only. Dot
strokes repeat their one location. Original trajectories remain immutable and
are the only classifier inputs reconstructed from returned source indexes.
Scale s is the whole target's maximum point-derived width/height; for zero
extent use one. Ordered pair A/B has these 22 values:

1. A width, height and original arc length divided by s; same three for B.
2. Sampled centroid B-minus-A x/y offsets divided by s.
3. Start/start, start/end, end/start, end/end distances divided by s.
4. Centroid distance and minimum sampled-point distance divided by s.
5. Nonnegative horizontal and vertical bounding-box gaps divided by s.
6. Nonnegative horizontal and vertical overlaps divided by s.
7. Endpoint direction cosine, zero if either endpoint displacement is zero.
8. Each stroke's arc/(arc + endpoint distance + s*1e-6).
9. Whole-target width/(width + height), zero if target extent is zero.

The remaining values are three 60-bin histograms centered on A's bounding-box
center, from: A+B; A+B plus three nearest remaining strokes; and the entire
target. Neighbors use minimum sampled-point distance to A or B and canonical
geometry-content tie breaks, not stroke ordinal. Each histogram uses its own
maximum radius, radial upper fractions 1/16, 1/8, 1/4, 1/2, 1 and 12 equal angular
bins in [0, 2*pi), radial-major order. Counts are divided by the number of sampled
points. Zero-radius points occupy radial zero/angular zero. No PCA or geometry
parameters are selected on development data.

## Fixed learned head and fit

Separate research-only ReLU MLP: 202 -> 64 -> 32 -> 1. Same-owner logit is the
mean of the two ordered-direction logits. It is not a calibrated trust score.
Standardization uses training-only feature means/std across both directions,
with the same final class-balanced per-target weights as the fit; std floor
1e-6. Model-fitting API receives feature tensors, binary targets and
weights only. Each target contributes total edge weight one (1/edge count),
with global class balancing from weighted training mass. All seven arms have
equal target counts. Single-stroke targets have no edges, are explicitly
excluded from the loss, and remain included in partition evaluation.

Seed 29, deterministic CPU, four threads, 30 epochs, shuffled batch size 512,
AdamW learning rate 0.001 and weight decay 1e-4. Use only the final checkpoint;
no development-selected checkpoint, sweep, early stopping or best-arm selection.
Fit command constructs training features only; a separate command evaluates
the frozen artifact. Persist protocol, source, code and model digests and roles.

## Source-preserving decoder

Start from singleton source indexes. For each possible cluster merge, sum all
cross-edge symmetric logits; take the largest strictly positive increase in
the within-group affinity objective. Repeat until no positive merge exists.
Ties are lexicographic index-tuple ties, not answer selection. This greedy
correlation-clustering approximation is not an exact global optimum. It uses
no expected group count or grammar and cannot guarantee correct boundaries.
Return sorted original index groups, covering every index exactly once. Reject
invalid, missing or duplicated edges, bad indexes and nonfinite scores. Source
ink is never rewritten, consumed or cleared by this experiment.

## Measurement and promotion boundary

Record binary edge confusion and complete source-owner partitions separately.
Report every arm and writer: exact owner matches, false-merged groups/pairs,
false-split owners/targets, index coverage defects and timing. Include per-target
partitions and gains/harms against the existing Swift geometry policies where
matching measurements exist. Never substitute two returned groups for exact
ownership, or add group-level failures to owner-level counts.

Audit source bytes, fit/evaluation trajectory-copy overlap, split independence,
label-independent features/decoding, source immutability and finite arithmetic.
Add executed unit tests for the new contract. A better public component result
still requires Python/Core ML/Swift parity, comparison-only app integration,
genuinely fresh full-chord evidence in both styles and a separate new writer
before any recognition-quality or shipping claim. If results regress materially,
retain the artifact/report as a failed experiment and do not install it.

Predeclared first-arm integration gate: zero source-index defects; no lower exact
partition count on any comparable arm or writer than the lossless geometric
baseline; no higher false-merged-pair count on any comparable pair arm; and no
new isolated A-G ownership failures where the geometric baseline is correct.
This deliberately conservative gate is for deciding whether to spend the next
step on comparison-only app integration, not auto-acceptance or shipping. A
failure may still teach us where the model needs independent data or a different
architecture; it cannot be erased by choosing the best spacing, changing the
threshold, or presenting an aggregate as success. Triple stress failures remain
explicit and are not hidden by the pair-only comparison.

## Research rationale

Stroke geometry and local/global shape context have been used for learned
mathematical-symbol segmentation. This design is an engineering inference, not
a reproduction of the published method: it removes class logits/time adjacency,
uses all stroke pairs and a different model/decoder. The paper reports important
generalization and over-segmentation limits. [Hu and Zanibbi, ICDAR 2013](https://www.cs.rit.edu/~rlaz/files/HuICDAR2013.pdf)
Dataset terms and limits: [UCI UJI Pen Characters v2](https://archive.ics.uci.edu/dataset/177/uji%2Bpen%2Bcharacters%2Bversion%2B2).
