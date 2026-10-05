# Frozen dual-view features with the existing residual learner

Freeze this protocol, implementation and synthetic tests before running the
diagnostic. This is one fixed diagnostic, not a new model, parameter search,
personal acceptance policy or production candidate promotion.

## Question and boundary

The completed dual-view experiment used direct one-hot replacement ridge for
its personal diagnostic. The app instead learns a correction to the shared
scores. Test that existing residual method on the already frozen dual features
before spending effort integrating this weaker shared encoder into the app.
Do not reinterpret a favorable result as fresh handwriting or chord accuracy.

Only the dual arm is tested. Do not choose among raster, trajectory and dual
after seeing these outcomes. No shared encoder/neural/Core ML inference,
checkpoint load, retraining, augmentation,
private ink, profile mutation, acceptance change or reserved-writer use.

## Immutable parents

All parents are from the completed fixed public experiment under
`dual-view-glyph-20260930.ttfIcd` in the local recognition-development evidence
directory. Preserve every parent and its existing eleven code bindings.

- Fit receipt SHA-256:
  `ce60efb539ce4d0897e0c339e6d1e1d90485ec07798aa1da499047482724a46f`.
- Label-blind prediction packet SHA-256:
  `06cae336f6bd00960a75669cace55fd6d3400a847b9d2e30602c297de4d27328`.
- Scored reference SHA-256:
  `898825e57a45bc1467fa17ee7de8bb4407ef3eae7b03c959153400b93d42195c`.
- Dual weights binding (read and validate receipt; do not load or infer):
  `ed722707ad992b6c282dd6f416ac173bc972c7517b1804d72c08f57cbf1a1507`.
- Vocabulary SHA-256:
  `2fc83d80121b8177598f563b7253ee6bb8de2a38e45fbd825bb2e656c52cfb59`.
- Unchanged Python residual source SHA-256:
  `cd8922f542c1c4dd1f3cd2e7c44e2e677412ded238227780565b2dd99c55959d`.
- Unchanged Swift residual source SHA-256:
  `c37df45b299e9013eb26f67e44d96a94b545c90dc949cd24f36426c85e94885f`.
- Prior sparse-profile selector source SHA-256:
  `1f0b981a4bea5119765c5cbfb211ff5fe932b7c7296ea4985a989d05c0fdaaf8`.

## Fixed source roles and support

Use only the eight already observed development writers, both sessions,
with exactly 97 records per session. Session one is explicit labeled support;
session two is held out from fitting. These are not fresh writers or sealed
evaluation data. Keep all 97 class competitors in both regimes.

Primary regime: 16 session-one labels per writer, selected by the unchanged
`personal-adaptability-v1:sparse16:<label>` SHA-256 ordering, sorted for fit.
The frozen labels are `!`, `E`, `F`, `L`, `T`, `Z`, `d`, `g`, `j`, `k`, `n`,
`t`, `w`, `x`, `Ó`, `á`. This is a prior public sparse-profile diagnostic,
not the musician-facing setup prompt set or evidence of chord-symbol coverage.
Do not select support from query errors, confidence, root letters or user reads.

Secondary explanatory regime: all 97 session-one labels per writer, ordered
by exact vocabulary label. Queries are ordered by opaque ID in both regimes.
Support and query IDs must be exact and disjoint for each writer/regime. This
matches the earlier direct-ridge diagnostic's support, not a typical app profile.
The existing full-support direct-ridge predictions remain a named frozen
reference; do not refit or silently compare them as sparse-support predictions.

## Fixed algorithm

Call the unchanged `personal_residual.ResidualHead` with lambda 0.1,
temperature-one softmax of all 97 raw shared logits, per-row multiplier
1/sqrt(class count), effective squared-loss weight 1/count, and residual targets
one-hot minus shared scores. Query rank is shared
scores plus learned correction (implicit alpha 1). No anchor bank, clamp,
threshold, adaptation-strength search, leave-one-out selector or grammar.
Negative adjusted scores are legal ranking values, not probabilities or trust.
Tie ordering follows the existing residual implementation (descending score,
then label). Shared baseline preserves the parent's first-argmax vocabulary
ordering. No personal output replaces the frozen shared prediction.

## Separate prepare, predict and score processes

Prepare validates exact parents and complete writer/session/ID/input-hash
bindings. Its metadata projection uses only writer/session and session-one
support labels from the scored/source parent; session-two intended labels,
correctness, reference predictions and novelty must not influence the plan.
It writes a strict label-blind plan: explicit labels appear only in
support rows. Query rows contain opaque IDs, writer/session, hashes, features
and raw logits, never intended labels, label-bearing source IDs, correctness,
reference predictions or novelty decisions. Fit/predict accepts only this
schema, with unknown keys rejected. Its learner receives support labels and
features/scores plus query features/scores, never expected query labels.

Predict freezes all 776 query predictions for each of the two regimes before
any truth join. Write complete baseline and corrected rankings, support IDs,
vocabulary and algorithm/source/plan bindings; publish the prediction receipt
last in an exclusive new directory. Scoring is a separate process that first
validates unchanged plan/prediction bytes, complete coverage and bindings, then
joins the frozen parent truth. Recomputed shared argmax from all query logits
must equal every frozen parent dual prediction, catching vocabulary/order drift.
Answer changes cannot change saved predictions. Test the pure metadata
projection/predictor with mutated query truth: projected learner inputs and
numerical predictions remain identical. Artifact bindings intentionally change
if parent bytes change; do not confuse those checksums with model outputs.

Bind protocol, new code/tests, the unchanged residual implementations and
selector, runtime and parent bytes by SHA-256. Reject output aliases/symlinks
and existing directories. Preserve parents and code before/after execution.
Publish final scoring/verification receipts last; a partial run is not a pass.

## Counts and interpretation

The primary comparison is sparse16 residual versus the same frozen dual shared
argmax on all 776 paired queries. Report paired gains/harms, every writer and
class, and sparse taught-label versus 81 untaught-label aggregates. Full97
residual versus shared and versus the frozen full97 direct-ridge reference are
secondary/explanatory. The direct reference is joined only at scoring; it is
not a separate label-blind prediction artifact.

Also report the same conservative 772-row novelty cohort as the frozen
full-support reference, with its four original copy exclusions kept identical
across methods/regimes. This common cohort does not claim all excluded sparse
queries are copies of the sparse support; it fixes comparability. Keep all
excluded rows visible. Do not create new eligibility rules from correctness.

The 772-row comparison is secondary, never a replacement for the primary 776.
Report worst writer delta and gain/harm distribution without
inventing a promotion threshold after results. These descriptive diagnostics
cannot establish cross-writer generalization, uncertainty calibration, natural
ownership, chord composition, Swift residual parity on these tensors, iPad
behavior or ship readiness. A negative result is retained, not retried away.

## Verification

Synthetic tests cover fixed normal-equation arithmetic, exact empty-profile
baseline, all-competitor rankings, query-label isolation, strict field/role and
finite-shape validation, altered/missing/duplicate bindings, paired denominators
and retained excluded rows. Peer review protocol and code before actual fitting.
Reconcile nonzero executed tests and exact row counts independently afterward.
Do not build/install the app for this research-only diagnostic; separately
changed app integrity/UI code receives its own nonzero focused test gate.
