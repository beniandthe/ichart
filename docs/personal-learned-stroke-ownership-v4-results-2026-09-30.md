# Stroke ownership V4: weight ablation improves counts but remains rejected

The frozen V4 run completed and improved most observed development contexts
relative to V3, but failed the unchanged comparison-only integration gate.
Do not install or promote it, select a favorable arm, or relax the false-merge
rule. No app build, profile mutation, private-ink fit, reserved-writer evaluation,
commit, push or production change occurred in this experiment.

## Controlled change and implementation evidence

V4 changes only V3's base edge weighting from
`1/(edgeCount * eligibleTargetsForCardinality)` to `1/edgeCount`, then applies
the unchanged global positive/negative balancing formula. Targets, original
V1 whole-context feature family, target order, labels, architecture, numerical
helpers, schedule and decoder remain fixed. The canonical protocol was frozen
before implementation, fitting or predictions.

Independent pre-fit review caught an extra numerical change in the draft: it
had replaced V3's targetwise class-mass accumulation with vector sums. The
draft was repaired to retain `positive * base` / `negative * base` accumulation
in the original target order; the frozen protocol was not amended. Exact toy
weight, moment, minibatch, final-parameter and loss checks stayed exact. Only
diagnostic summation assertions use floating-point tolerance.

- Final combined gate: **102 tests executed, 102 passed, zero failures or skips,
  88.646 seconds**. These test implementation and evidence contracts, not
  handwriting accuracy. The 4,250-row fixture matches direct-array moments,
  batches, final parameters and losses exactly.
- Metadata-only preflight equals V3: **117,952 targets**, **1,207,443 edge rows**,
  **3,161 no-edge singles**, 19 training arms and 6,208 public source characters.
  Eligible targets total 114,791. Five-owner compositions remain evaluation-only.
- Reused genuine V3 AB/BA, label and cardinality arrays read-only; replay checked
  target boundaries, ordered owner labels and cardinalities before writing new
  weights. No features were regenerated, and no V3 model initialized V4.
- All five old arrays, including unused old weights, are content-bound. The
  fit/evaluation guards hash inputs in finally paths. V4 has its own new weights,
  manifest, checkpoint and reports, with all **27** dependency bindings.
- Fixed 202 → 64 → 32 → 1 ReLU, 15,105 parameters, seed 29, four deterministic CPU
  threads, 30 epochs, batch 512, AdamW 0.001/0.0001. Final epoch 30 was retained;
  optimizer time **82.747671583 seconds**, online weighted loss
  **0.0004917486080622594**. No checkpoint selection by loss or development score.
- Normalization standard deviations span 0.0108247902–0.6241108179; zero dimensions
  hit the 1e-6 floor. Bounded normalization avoids another full standardized cache.

Checkpoint SHA-256:
`8a4c6799daedeec1d0e8abba3b0e0565420c9da9ebf64fcf5fd44dc187d4a0a8`.

## Actual weighting and independent audit

Every eligible target now has base mass one. Base masses are 3,047 / 37,248 /
37,248 / 37,248 for one through four owners, rather than one per cardinality.
The base positive and negative masses are approximately 25,381.27665669 and
89,409.72334337. Global multipliers are approximately 2.261332271673 and
0.6419380113683; final positive and negative masses are each 57,395.5 up to
floating-point summation error.

| Owners | Final mass | Final share |
|---|---:|---:|
| One | 6,890.279431788 | 6.002456% |
| Two | 40,322.496239077 | 35.126879% |
| Three | 35,148.477597595 | 30.619541% |
| Four | 32,429.746731543 | 28.251123% |

A separate metadata-only calculation used exact rational counts, without model
or feature values. The post-fit independent audit passed 33 checks; maximum
base-class relative difference was 5.10e-13, maximum final cardinality mass
difference 1.02e-9, and maximum share difference 2.67e-15. These are rounding
differences, not changes to the mathematical weighting rule.

The independent audit rehashed all 27 current bindings, retained all 22 V3
bindings, V4/V3 small report/manifest/checkpoint/protocol inputs, public source,
new weights and retained small arrays. It independently reproduced writer
roles from public source headers. It checked the old AB/BA recorded hashes,
paths, headers, shapes, dtypes and sizes but deliberately did not duplicate
hashing their approximately 1.95 GB contents; the experiment's own guards did
hash those contents. No independent model or feature-value load occurred.

## Evaluation and strict report-only join

All **38,800** predictions completed: 25 contexts × 1,552 source-character
compositions on the same eight already-observed development writers. The
strict join reconciled **72 comparisons** and **111,744 matched rows**: 14 Swift
policy/arm comparisons, eight V1, 25 V2 and 25 V3. All ordered source IDs,
owners, writer summaries, edge confusion and source-index coverage are retained.

An independent stdlib-only audit rescored the saved expected-owner/predicted-group
rows without importing production scoring or model code. All 38,800 V4 rows,
25 contexts, 194 targets per writer/context, 72 comparisons and 111,744 unique
joined rows reconcile. It checked full/writer gains, harms, merges, splits,
index defects, edge margins, timings, root harms and all 779 new-context failure
rows. All seven join input hashes, fit-report linkage, protocol and 36 distinct
current code paths match. No saved bytes changed; no models, caches or feature
values were loaded by that audit.

Each row below has denominator 1,552. Gains and harms are matched target
changes, not differences inferred from unrelated totals.

| Context | Lossless Swift exact | V1 exact | V2 exact | V3 exact | V4 exact | V3 → V4 gains / harms |
|---|---:|---:|---:|---:|---:|---:|
| single32 | 1,192 | 1,538 | 1,539 | 1,540 | 1,537 | 2 / 5 |
| second16-gap3.2 | 886 | 1,539 | 1,530 | 1,524 | 1,529 | 9 / 4 |
| second16-gap8 | 979 | 1,539 | 1,532 | 1,528 | 1,532 | 6 / 2 |
| second16-gap16 | 979 | 1,543 | 1,536 | 1,533 | 1,536 | 4 / 1 |
| second32-gap3.2 | 774 | 1,531 | 1,522 | 1,519 | 1,524 | 11 / 6 |
| second32-gap8 | 914 | 1,537 | 1,528 | 1,526 | 1,526 | 6 / 6 |
| second32-gap16 | 914 | 1,538 | 1,529 | 1,525 | 1,525 | 6 / 6 |
| triple32-16-16-gap8-8 | no baseline | 1,457 | 1,523 | 1,519 | 1,524 | 8 / 3 |

V4 versus V3: **22 contexts improved, two tied, one worsened**. Across repeated
contexts, **461 gains / 171 harms**, net +290, with 37,838 exact partitions
versus 37,548. These are not 38,800 independent handwriting samples. Isolated
ownership regressed by three even as most composed contexts improved.

V4 versus V2: 13 contexts improved, two tied, ten worsened, with 379 gains /
333 harms, net +46. V4 versus V1 improves only the retained triple and worsens
all seven isolated/pair contexts; the eight-context net +11 does not erase
those regressions. V1/V2 comparisons change more than weighting and cannot
support a weight-only causal claim.

V4 grouped **112/112 isolated A–G examples** into correct owners, with zero new
geometry-correct A–G baseline harms. This is not letter identification or chord
recognition. The full isolated cohort still has 15 split failures. Across all
25 contexts, V4 has 113 false-merged targets and 877 false-split targets; these
counts can overlap. Four-owner exact counts span 1,480–1,526 and false merges
1–11; five-owner exact counts span 1,461–1,518 and false merges 8–16.

All **779 failures** in the 17 contexts without retained V1/Swift baselines
remain in the report. Every original index is covered exactly once across all
38,800 predictions: zero missing, duplicate or invalid indices. Source coverage
does not prove ownership correctness.

## Gate decision and limits

`eligibleForComparisonOnlyIntegration=false`, `productionEligible=false`.
No matched Swift arm/writer exact-count violation or isolated A–G violation.
The remaining decoded false-merge violations are:

| Pair context | Lossless Swift false-merged targets | V4 false-merged targets |
|---|---:|---:|
| second32-gap8 | 0 | 1 |
| second32-gap16 | 0 | 1 |

The fixed weighting rule improves V3's observed synthetic grouping results but
does not make forced grouping safe. Neither V1, V2, V3 nor V4 is promoted. Do
not keep changing weights, seeds, thresholds or architectures against these
same eight writers and call that fresh generalization.

The source is pinned public UJI, SHA-256
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Roles remain 32 training / eight observed development / 20 reserved. The unchanged
normalized-trajectory audit retains five development copy exposures in three
fingerprint groups, with no post-score exclusions. No reserved writer received
derived inputs or evaluation. No private accepted answer entered this experiment.

Desktop Python evaluation elapsed **137.376346792 seconds**. This is not iPad,
Swift/Core ML, Pencil or end-to-end latency. No natural-chord accuracy,
personal-learning benefit, calibrated trust, fresh-writer accuracy or ship
readiness follows from this component experiment.

Next work is source/evidence design for unsafe forced ownership decisions and
the larger ML/personalization pipeline, not another opportunistic weight fit.
See `personal-selective-ownership-next-step-2026-09-30.md` for the design boundary,
which is not a frozen architecture or calibrated recognition claim.
Any new candidate needs a frozen general method and evaluation boundary before
training. Comparison integration still requires a passing gate, Python/Core
ML/Swift parity and separate actual-device checks. Fresh full-chord writing in
both styles and another writer remain separate milestones. No more iPad writing
is requested for this component result.

Evidence directory:
`/Users/benirossman/.local/share/ichart/recognition-development/learned-ownership-v4-20260930.p6yvDY/`

- `training-plan.json` and `combined-unit-tests.log`
- `fit-v4/report.json`, `protocol.json`, `frozen-protocol.md`, checkpoint and cache
- `fit-v4.log`
- `evaluation-v4/report.json` and `evaluation-v4.log`
- `baseline-join-v4.json` and `baseline-join-v4.log`
