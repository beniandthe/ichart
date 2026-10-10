# Stroke ownership V3: controlled feature ablation rejected

The frozen V3 run completed, but failed the unchanged comparison-only
integration gate. Do not install, promote or select this candidate based on a
good arm. No new app build, profile mutation, private-ink fit, reserved-writer
evaluation, commit, push or production change occurred in this experiment.

## What this comparison isolates

V3 uses the unchanged V1 whole-context 202-float32 feature extractor and
prediction function with the exact V2 target stream, supervision, weighting,
normalization procedure, model architecture, optimizer, shuffle, schedule and
decoder. The feature family is the sole changed experimental variable relative
to V2. Feature statistics and learned parameters naturally differ.

The canonical protocol was frozen before V3 implementation, fitting and
predictions. This is one fixed seed and the already-observed public development
cohort, not a new-writer quality test. V1 versus V3 also changes training contexts
and weighting, so that comparison cannot separate those effects. No owner
count, character label, writer ID, source ordinal or private correction answer
enters feature extraction or decoding.

## Executed gates and fit

- Final combined Python gate: **86 tests executed, 86 passed, zero failures or
  skips, 51.809 seconds**. The earlier 86-test run also passed; it is a repeated
  execution, not 172 unique tests. A pre-fit comparator repair tightened its
  required provenance set from 19 to all 22 harness bindings. Omission of every
  required path is tested. V1/V2 files and gate rules stayed unchanged.
- A 4,250-row toy fixture crosses bounded moment/minibatch blocks and exactly
  matches direct-array mean, standard deviation, normalized batches, final
  parameters and losses. This is implementation parity, not handwriting accuracy.
- Metadata-only preflight exactly equals V2: **117,952 targets**, **1,207,443
  edge rows**, **3,161 no-edge singles**, 19 training arms and 6,208 public source
  characters from the same 32 training writers. No five-owner training.
- Full training summary and saved labels/weights/cardinality digests equal V2.
  Cardinality base masses are one before global class balancing. Final masses
  remain approximately **1.250305 / 0.946684 / 0.910906 / 0.892106** for one through
  four owners; they are not equal after balancing.
- Fixed 202 → 64 → 32 → 1 model, 15,105 parameters, seed 29, four-thread
  deterministic CPU, 30 epochs, batch 512, AdamW 0.001/0.0001. Final epoch 30
  retained, with online weighted loss 0.00157817539244 and optimizer time
  **81.124144709 seconds**. Minimum recorded training loss occurred at epoch 25;
  it did not change selection.
- Normalization standard deviations span 0.0105652874–0.6317613721; zero
  dimensions hit the 1e-6 floor. Raw feature mappings use bounded normalization,
  not a second full normalized feature cache.
- All **22 current code/protocol bindings** and checkpoint/protocol/cache-manifest
  hashes matched. Independent review also checked cache metadata/file sizes and
  all 17 retained V1/V2 source bindings. It did not load the model or raw arrays,
  inspect evaluation output, or independently rehash raw cache arrays. The fit's
  own guards rehashed cache inputs around optimization.

Checkpoint SHA-256:
`7709450a1ac3b714f21c8b5e25f95cf8b78c22a627986772612d4ef990c03cd5`.

## Evaluation and strict join

All **38,800** frozen partitions completed: 25 arms, 1,552 per arm, the same eight
observed development writers. The strict report-only join reconciled **47**
comparisons: 14 Swift-policy/arm comparisons, eight V1 and 25 V2 comparisons.
All ordered source IDs, expected owners and arm/writer summaries are retained.

Each row below has denominator 1,552. `V2 → V3 gains / harms` are matched target
changes, not differences inferred from two unrelated totals.

| Arm | Lossless Swift exact | V1 exact | V2 exact | V3 exact | V2 → V3 gains / harms |
|---|---:|---:|---:|---:|---:|
| single32 | 1,192 | 1,538 | 1,539 | 1,540 | 4 / 3 |
| second16-gap3.2 | 886 | 1,539 | 1,530 | 1,524 | 4 / 10 |
| second16-gap8 | 979 | 1,539 | 1,532 | 1,528 | 3 / 7 |
| second16-gap16 | 979 | 1,543 | 1,536 | 1,533 | 3 / 6 |
| second32-gap3.2 | 774 | 1,531 | 1,522 | 1,519 | 10 / 13 |
| second32-gap8 | 914 | 1,537 | 1,528 | 1,526 | 7 / 9 |
| second32-gap16 | 914 | 1,538 | 1,529 | 1,525 | 5 / 9 |
| triple32-16-16-gap8-8 | no retained Swift baseline | 1,457 | 1,523 | 1,519 | 9 / 13 |

V3 grouped **112/112 isolated A–G examples** into the correct stroke owners,
matching V2 and versus V1's 111/112. This does **not** mean it recognized 112
letters or chords correctly. It introduced zero new geometry-correct isolated
A–G ownership harms. The full isolated cohort still has 12 split failures and
four geometry-correct non-root harms.

Against V2, three arms improved in exact count, one tied and **21 worsened**.
All six pair arms worsened. Across the repeated-arm table there are 311 gains
and 555 harms, a net -244; those are not independent new handwriting samples.
The retained triple still improves versus V1 by 62 (80 gains, 18 harms), but
regresses versus V2 by four. V3's retained triple has two merged targets and 31
split targets versus V2's zero and 29. Merge and split target counts can overlap.

Four-owner exact counts span 1,463–1,518 and false-merged targets 5–21; five-owner
evaluation-only exact counts span 1,419–1,515 and false-merged targets 5–29.
The report preserves **1,050 failures** in the 17 contexts with V2 but no retained
V1/Swift baseline, rather than inventing an earlier baseline or excluding them.

Every original source index remains covered exactly once across all 38,800
predictions: **zero missing, duplicate or invalid indexes**. That is source
coverage, not proof of correct ownership.

## Gate decision

`eligibleForComparisonOnlyIntegration=false`, `productionEligible=false`.
No matched arm/writer exact-count violation and no new isolated A–G violation.
The three decoded false-merge violations are:

| Pair arm | Lossless Swift false-merged targets | V3 false-merged targets |
|---|---:|---:|
| second16-gap16 | 0 | 1 |
| second32-gap8 | 0 | 2 |
| second32-gap16 | 0 | 4 |

The false-merge rule was not relaxed. Neither V2 nor V3 is promoted.

## Scope, timings and next step

The source is the pinned public UJI character dataset, SHA-256
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Writer roles stay 32 training / eight observed development / 20 reserved.
The development cohort reuses 1,552 source characters across 25 synthetic
contexts; it is not 38,800 independent natural-chord samples. The unchanged
normalized-trajectory audit records five development copy exposures in three
fingerprint groups, retained with no post-score exclusions.

Desktop Python evaluation elapsed **136.685619792 seconds**. Selected total
feature/prediction median / p95 times in milliseconds are single32
0.1333 / 0.7013, second32-gap8 0.7285 / 2.3314, retained triple 2.2742 / 4.6866,
and five32-16-16-16-16-gap8-8-8-8 6.0694 / 11.8198. These are not Swift/Core ML,
iPad, live-ink or end-to-end latency measurements; no responsiveness claim.

The fixed feature ablation does not rescue V2's pair regressions. Its observed
results favor V2's pair-local family over this whole-context replacement on most
arms, but do not establish an optimal feature family or isolate the effects of
the broader training targets and cardinality-balanced objective. Next: diagnose
that objective change from source and retained evidence, then freeze one
general controlled ablation before any further fitting. No private accepted
answer, label-specific patch, arm selection or threshold grid. No additional
iPad handwriting is requested yet.

Evidence directory:
`/Users/benirossman/.local/share/ichart/recognition-development/learned-ownership-v3-20260930.GIux2D/`

- `training-plan.json`
- `combined-unit-tests.log` and `combined-unit-tests-final-provenance.log`
- `fit-v3/report.json`, `protocol.json`, `frozen-protocol.md`, checkpoint and cache
- `fit-v3.log`
- `evaluation-v3/report.json` and `evaluation-v3.log`
- `baseline-join-v3.json` and `baseline-join-v3.log`
