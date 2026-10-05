# Stroke ownership v2: pair-local context protocol

Freeze this single follow-up before implementation, fitting or v2 predictions.
V1 remains a rejected-for-integration but retained research artifact. Do not
modify its code, tests, protocol, checkpoint or code-bound reports. This is a
general engineering revision, not a targeted B repair or a causal ablation.

## Hypothesis and inference contract

V1 divides pair geometry by the entire target's extent. Adding distant strokes
changes pair-relative geometry even if the pair itself is unchanged. The code
establishes that dependency; v1's triple failures do not prove that dependency
caused all errors. Remove this dependency and broaden training contexts in one
declared revision, without claiming the two effects have been isolated.

Create separate module/schema `stroke-affinity-pair-local-v2`, still 202 float32
values. The first 22 values and pair histogram are computed from A+B alone,
including resampling in the pair-local coordinate frame. Geometry scale is the
pair union's maximum point-derived width/height, or one for zero extent. Replace
the whole-target aspect feature with pair-union aspect. Preserve all other
geometric feature meanings and the five-radial/twelve-angular histogram bins.
Local and global histograms still use the surrounding target and the declared
geometry-only nearest-neighbor selection; those features may legitimately
change with context. No expected count, character label, writer ID, ordinal,
class logits or desired chord enters features or decoding.

Add a toy invariant proving that appending distant strokes leaves the first
22 geometry values and the pair histogram unchanged. Do not require the entire
feature vector, model score or partition to be context-invariant. Preserve
v1's finite/type/size guards, symmetric averaging, complete-edge greedy decoder,
original-source reconstruction and zero-defect coverage contract.

## Source and fixed contexts

Use unchanged UJI text SHA
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Retain exactly the original 32 training/eight observed-development/20 sealed
writer roles. No private ink, saved intended chords, personal lessons or new
writer answers enter this experiment. Development remains observed research
data, not a sealed product or fresh-writer test.

Training contains every original isolated character at maximum dimension 32;
and cyclic two-, three- and four-character synthetic contexts within each
training writer/session. Use the existing `public-pair-v1:` ordering for pairs,
`public-triple-v1:` for triples, and new `public-quad-v2:` for quadruples, each
SHA-256 prefix plus source identity, with cyclic successors. Preserve each
trajectory's points, boundaries, order and metadata under uniform affine
placement only. Bottom alignment remains y=32.

For each composed cardinality use the same six arms: first character maximum
dimension 32, all remaining characters maximum dimension 16 or 32; every
adjacent bounding-box gap 3.2, 8 or 16. These are declared synthetic contexts,
not a representative natural chord-writing or superscript distribution.
No arm is selected after scores. There are 6,208 source records, 6,208 single
targets and 37,248 targets at each composed cardinality: 117,952 training targets.
The exact point/stroke/edge storage plan must execute before fitting.

## Fit and artifact isolation

Retain v1's 202 -> 64 -> 32 -> 1 ReLU architecture, seed 29, deterministic
four-thread CPU, 30 epochs, batch 512, AdamW 0.001/1e-4, symmetric mean logits,
training-only weighted normalization, 1e-6 std floor and final-checkpoint-only
selection. Only the data/feature revision and declared weighting change.

Before global binary class balancing, each cardinality has total base loss mass
one. Within a cardinality, each target with at least one edge has equal base
mass; its edges divide that mass equally. Thus an edge's base weight is
1/(edgeCount * eligibleTargetCountForCardinality). Single-stroke targets remain
in evaluation but have no training edge loss. Apply one global positive/negative
mass balancing step afterward; this can change the final mass per cardinality
and must be reported honestly. Use the final weights for both-direction mean/std.
No cardinality, owner count or target answer is an inference feature.

Stream derived targets and use a bounded feature/cache strategy if the preflight
exceeds reasonable RAM. Such a mechanical storage implementation must retain the
same fixed row order, values, weights, shuffle and fitting objective; it cannot
silently subsample, select labels or change the protocol. If infeasible, report
it before fitting and explicitly revise the unexecuted protocol rather than
claim this prescribed run executed.

Bind the new artifact to v1 dependencies plus v2 source/protocol/test digests.
Fit and evaluation stay separate. Audit unchanged source bytes and normalized
trajectory-copy exposure without post-score cohort exclusions. Never overwrite
v1 evidence or alter its source bindings to reuse its reported success.

## Evaluation and unchanged integration gate

Evaluate all eight development writers, all source records, singles and all six
arms at composed cardinalities two, three and four. Preserve the exact v1
matched pair arms and existing triple stress (dimensions32/16/16, gaps8/8,
`public-triple-v1:` ordering) so that gains and harms against v1 can be joined.

Add evaluation-only five-character contexts, using `public-five-stress-v2:`
ordering with cyclic successors, the same six declared size/gap arms and bottom
alignment. No five-character context is training data or a model/threshold
selection source. This holds out compositions, not additional writers.
The 20 official tst writers remain unused by features, fitting and evaluation.

Report binary edges, complete ownership, decoded merged/split targets, source
index defects, all arms/writers, root A-G harms, duplicate exposure and desktop
timing separately. Keep the v1 conservative gate against the unchanged lossless
Swift baseline: zero source-index defects, no lower exact arm/writer count, no
more false-merged targets on matched pair arms, and no new baseline-correct
isolated A-G failure. Do not relax the gate after looking at predictions.
Also retain all v1 comparison gains/harms and every new context failure; a good
matched-pair total cannot establish robustness on longer writing.

Even a passing component gate only permits spending the next step on optional
comparison-only app integration. Python/Core ML/Swift parity, fresh full-chord
handwriting in both chart styles, actual iPad responsiveness and a separate new
writer remain necessary before recognition-quality or ship-readiness claims.
