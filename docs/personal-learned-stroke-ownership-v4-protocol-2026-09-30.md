# Stroke ownership V4: frozen equal-target-weight ablation

Freeze before V4 implementation, fitting or predictions. Preserve every V1/V2/V3
source, test, protocol, cache, checkpoint and report. This is one general public
component experiment, not an app build, user-answer repair or model/threshold
grid. V3 failed the unchanged gate and is not promoted.

## Question and sole changed rule

Hold V3's broad targets, original V1 whole-context feature family, architecture,
schedule and decoder fixed. Replace only V3's cardinality-balanced base edge
weight `1/(edgeCount * eligibleTargetsForCardinality)` with unchanged V1's
equal-eligible-target rule `1/edgeCount`. Then perform the same one global
positive/negative balancing step and the same final-weight AB/BA feature-moment
calculation. The balance factors and weighted moments will naturally change;
their formulas, reduction order, dtypes and 1e-6 standard-deviation floor do not.

V1's final normalized single/pair shares were approximately 11.55795%/88.44205%.
V2/V3's single/pair/triple/quad shares were 31.25762%/23.66710%/22.77264%/22.30264%.
V2/V3 give one eligible isolated target 12.2245 times a composed target's base
mass. These source/metadata facts motivate this test; they do not prove the
cause of any prediction error. V1 versus V3 also changes contexts and optimizer
updates, so that comparison is not a weight-only experiment.

Only V3 versus this fixed V4 tests the changed allocation rule, under one seed
and an already-observed cohort. It restores V1's rule, not V1's complete
objective, update count or expected performance. Neither development scores nor
training loss may select a different rule, checkpoint, arm, threshold, seed or
schedule. Do not change expected owner counts or infer with character labels,
writer IDs, source ordinals, private accepted answers or correction labels.

## Immutable data and efficient feature reuse

Public UJI SHA-256 remains
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Retain the same 32 training/eight observed development/20 reserved writers.
Reserved writers receive no derived features, grouping, rasterization, fitting
or evaluation. No private ink, lessons or whole-chord corrections enter training.

The exact V3/V2 stream has 117,952 targets from 6,208 public source characters,
19 arms, 1,207,443 edges and 3,161 no-edge singles. Eligible counts are 3,047
singles and 37,248 each at two, three and four owners. Preserve all source IDs,
points, stroke/timing/bounds metadata, placements, owners, edge row order and
labels. Five-owner training is forbidden. Metadata-only preflight must reconcile
these counts before any feature access or fitting.

Reuse the genuine, unchanged V3 raw AB/BA float32 feature mappings and
labels/cardinality arrays read-only. Do not duplicate or regenerate them and do
not load the V3 model for initialization. Verify V3's actual version/schema,
source/writer/role/protocol/code bindings, training plan, cache manifest and all
referenced array content digests before reuse. Derive only new weights by
replaying the unchanged training-only target stream. For each target, check
edge-count slice boundaries, ordered owner-derived labels and cardinality
against the referenced arrays before assigning `1/edgeCount` to its rows.
No-edge targets contribute no loss. Reject wrong roles before derived access.

V4 writes only its fresh weights, manifests, checkpoint and reports in a new
append-only evidence directory. Its manifest must explicitly identify immutable
V3 cache references, their content hashes and row/dtype contracts; do not relabel
an old cache/report as V4 or mutate old arrays. Preserve every referenced file,
source, canonical protocol and code with finally hash guards, including failed
operations. Bind all actual reused V1/V2/V3 dependencies/tests/protocols and the
new V4 source/test/protocol paths. Genuine V4 version is
`public-stroke-affinity-experiment-v4`; feature schema stays
`stroke-affinity-context-v1`, count 202.

## Frozen fitting and implementation checks

Every eligible target now has base mass one. Base cardinality masses therefore
equal the eligible target counts, not one each. Report actual positive/negative
masses, global multipliers and final cardinality masses/shares; do not describe
them as equal or as the old V1 shares. Training-only statistics use those final
balanced weights with unchanged bounded numerical helpers.

Retain 202 → 64 → 32 → 1 ReLU, 15,105 parameters, seed 29, deterministic four-thread
CPU, 30 epochs, batch 512, AdamW 0.001/0.0001, symmetric mean logits, float32
normalized minibatches, float64 weighted moment accumulation and final epoch
only. There are still 2,359 batches/epoch and 70,770 optimizer updates. Use the
unchanged V2 bounded moment/minibatch/fitting helpers, not patched globals.

Before the sole public fit, synthetic tests must establish exact V1-rule
target/global-class weighting versus a direct reference, unchanged features,
labels and row order, read-only cache references, complete writer-role guards,
all provenance bindings and failed-operation preservation. A 4,250-row toy
fixture must match direct-array moments, batches, final parameters and losses
exactly. Check nonzero executed tests with zero failures/skips. Independent
pre-fit review is required. Never run a fit while bound code/tests are changing.

## Evaluation, joins and unchanged gate

Use the exact retained 25-arm/eight-development-writer stream: 38,800 targets,
1,552 per arm, with five-owner compositions evaluation-only. The unchanged V1
ink-only prediction/decoder and pure retained scoring helpers may be reused.
Scoring and cardinality audits occur after prediction. Emit genuine V4 metadata;
do not relabel earlier reports or patch their validators.

Report-only strict joins must reconcile all V4 arm/writer/owner/index/edge
summaries and match V3/V2 on all 25 arms, V1 on its eight, and Swift on seven
arms for each policy. Preserve gains and harms, merged/split targets and groups,
edge confusion, A–G harms, index defects, desktop timings and every failure in
the 17 contexts without V1/Swift baselines. Comparisons outside V3/V4 remain
descriptive, not weight-only causal experiments. The trajectory-copy audit
remains unchanged exposure accounting; no post-score exclusions.

Retain the same lossless-Swift gate: zero original-index defects in all arms; no
lower exact matched-arm/writer count; no higher false-merged-target count on
matched pair arms; no new geometry-correct isolated A–G ownership failure. Do
not relax it or select the best-looking prior model. Passing permits only the
next optional comparison-integration step, not production recognition.

No natural-chord accuracy, calibrated trust, personal-learning benefit,
fresh-writer accuracy, iPad latency or ship claim follows from this component
experiment. Python/Core ML/Swift parity, fresh full-chord handwriting in both
chart styles, actual Pencil responsiveness and a different writer remain
separate required evidence. No new iPad handwriting is requested for this fit.
