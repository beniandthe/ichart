# Stroke ownership v3: controlled feature-family ablation

Freeze before implementation, fitting or v3 predictions. Retain all V1/V2 code,
tests, protocols, checkpoints and reports unchanged. This is a single general
public-component experiment, not an app build or a targeted chord/root repair.

## Question and sole changed variable

V2 jointly changed features, training contexts and weighting. Its retained
triple improved, all six pair arms regressed versus V1, and its conservative
integration gate failed. Those observations do not identify which change caused
which effect. Hold V2's targets, weighting, architecture, schedule and decoder
fixed, and replace only its feature family with the original V1 whole-context
202-float32 features (`stroke-affinity-context-v1`). Use the unchanged V1
`all_pair_features` directly. Do not modify V1 or patch V2 globals.

Feature statistics will naturally change with the input features; their
training-only weighting, reduction, dtype and floor remain identical. Only V2
versus this fixed V3 is the controlled feature-family comparison, within this
one seed and observed cohort. Neither the result nor the minimum training loss
may select another feature variant, checkpoint, arm, threshold or hyperparameter.

No expected owner count, character label, writer ID, source ordinal, private
chord answer or user acceptance enters inference features or decoding. Maintain
original-object reconstruction, finite/type/size guards, symmetric logits and
complete original-index coverage. Whole-chord correction labels are not stroke
ownership supervision.

## Fixed source, targets and fitting

Public UJI source SHA stays
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Retain the original 32 training/eight observed-development/20 reserved writers.
No private ink or personal lessons enter this fit. Reserved writers receive no
features, grouping, rasterization, fitting or evaluation.

Use the exact V2 target stream: 6,208 isolated targets and 37,248 each at two,
three and four owners, totaling 117,952. Preserve ordered source IDs, all points,
stroke boundaries, timing/bounds metadata, owners, placement and six arms per
composed cardinality. Prefixes remain `public-pair-v1:`, `public-triple-v1:` and
`public-quad-v2:`; dimensions 32 then 16/32, gaps 3.2/8/16, bottom alignment 32.
The existing metadata-only preflight must reconcile all counts before fitting:
1,207,443 edge rows and 3,161 no-edge singles. Five-owner training is forbidden.

Base edge weight is 1/(edgeCount * eligibleTargetCountForCardinality), giving
each cardinality base mass one before one global positive/negative balancing
step. Retain final weights for AB/BA training-only moments. Final cardinality
masses must be reported, not described as equal. The public trajectory-copy
audit remains exposure accounting only, with no post-score exclusions.

Retain 202 -> 64 -> 32 -> 1 ReLU, 15,105 parameters, seed 29, deterministic
four-thread CPU, 30 epochs, batch 512, AdamW 0.001/1e-4, symmetric mean logits,
float32 inputs, float64 weighted moment accumulation, 1e-6 std floor and final
epoch only. Reuse unchanged pure V2 target/weight/fit helpers where possible;
create new wrappers/artifacts with genuine V3 version/protocol bindings. Never
relabel a V3 report as V1 or V2 to bypass their validators.

Raw .npy mappings and bounded normalization may preserve RAM, but values, row
order, weights, shuffle and objective must match the direct-array reference.
Check exact mean/std, minibatches and final parameters/losses on a multiblock toy
fixture before the sole public fit. Reject wrong roles before derived features.
Bind every actual reused dependency, new source/test and canonical protocol.
Use fresh append-only output directories; verify source/code/artifact digests in
finally guards, including failed operations. No V1/V2 cache or evidence mutation.

## Evaluation and unchanged gate

Evaluate the frozen final checkpoint on the exact V2 25-arm/eight-writer cohort:
38,800 targets, 1,552 per arm, with evaluation-only five-owner compositions using
`public-five-stress-v2:`. Preserve pair and retained triple identities, all ordered
owner mappings, and every original stroke index. This holds out compositions,
not additional writers. Do not use the 20 reserved writers for model selection.

Make strict report-only joins to both V1 and V2 and the unchanged Swift geometry
reports. Reconcile every cohort/arm/writer summary; report gains, harms, decoded
merges/splits, edge confusion, A-G harms, index defects and desktop timings.
The other contexts retain explicitly absent historical baselines rather than
inventing them. Validate actual V3 version/schema/protocol/weights/code digests.

The same lossless-Swift gate remains: zero source-index defects across all arms;
no lower exact matched-arm/writer count; no more false-merged targets on matched
pair arms; no new geometry-correct isolated A-G failure. Do not relax it based on
predictions. Retain every regression versus V1/V2 and every new-context failure.
Do not choose the best-looking model/arm or hide a bad longer-context result.

Passing only permits the next optional comparison-only app-integration step.
It does not establish natural-chord accuracy, calibrated trust, personalization
benefit, fresh-writer accuracy or readiness to ship. Python/Core ML/Swift parity,
actual iPad responsiveness and prospective full-chord handwriting in both chart
styles plus a different writer remain required.
