# Training-only support signal audit

Scope: diagnose whether the current setup lessons contain useful information,
before fitting another personal learner. No new candidate, recognition-accuracy
claim, app/profile/ink change, private-data use, development/reserved inference,
export, install, or promotion. Base HEAD
`160aa31594903508e241802e21ca83ec447de849`.

The preceding support-retrieval candidate failed its fixed development screen.
It remains rejected and frozen. This audit must not reopen those predictions,
query truth, scores, or private examples. It reads only the preserved training
crossfit bundle. The audit is in-sample learner-training diagnostics: neither
held-out meta validation nor fresh-writer accuracy.

## Fixed inputs and procedure

- Input directory:
  `/Users/benirossman/.local/share/ichart/recognition-development/support-retrieval-20261001.WmWgZ3/crossfit`.
- Receipt SHA:
  `d2a31e73d53b25b812f0ba4f24f812014515606f97a20e6b7170eaf94d0e20d2`.
- Features SHA:
  `b1bbb6066ef2bd1d5cc0398df2d9713fb60f6086ec501bb0687fce81976faaef`.
- Use the existing source-only `episode_plan(..., epochs=1)` without changes:
  32 training writers, both opposite-session directions, independent 10-label
  and 21-label setup subsets, seed 29, 128 episodes. Retain unavailable setup
  shapes and all fitting/support copy exclusions in the audit evidence.
- Each generic feature generator fitted the complementary 16 training writers,
  never the writer supplying that row. Each retained setup/query row uses its
  already-recorded generator. No new model inference or fitting.
- Reuse exact stored-support and raw-query features. Deduplicate exact
  feature/probability/explicit-label support triplets before balancing. Cache
  weights are `softmax(10*cosine - log(label multiplicity))`, scattered by
  explicit support label into the full 97-class vocabulary.
- Record all mixtures `(1-alpha)*generic + alpha*cache`, for the fixed grid
  `[0, .01, .03, .05, .1, .2, .35, .5, .75, 1]`. This grid diagnoses the tradeoff;
  it does not select a deployable alpha, rescue the failed learner, or authorize
  a new development evaluation. No subset, temperature, learned parameter or
  alpha is chosen by writer/query outcome.
- Report full query-exposure counts and distinct physical query counts
  separately. The same physical query can occur in both K tasks; it is not
  independent evidence twice. Keep task, writer, session and taught/untaught
  strata, paired corrections/regressions and balanced negative log likelihood.
- Count taught baseline mistakes whose explicit true-label setup evidence is
  the highest cache score. Also count initially correct untaught queries that
  a mixture overtakes. These labeled diagnostics must never be inference inputs.
- Retain complete source-only episode/exclusion records and immutable input,
  protocol and code hashes before and after computation. Fail on non-training
  writers, incomplete query roles, invalid matrices or missing strata.

## Interpretation and next-action boundary

If no fixed mixture improves training answers, do not spend another fit trying
to extract recognition improvement from this cache unchanged. Investigate
representation/support quality or domain coverage instead. If some mixture
improves aggregate training answers but harms writers or untaught cases, that
demonstrates a learning/safety tradeoff, not a safe setting. If the tradeoff
supports another learner, first specify a genuinely writer-blocked training-only
selection path. The existing two generators cannot automatically be called a
leakage-free inner-validation pipeline: an inner validation writer can have
entered the other generator that supplies meta-training features.

An independent audit will reconcile the arithmetic from frozen outputs without
using production/app data. Focused tests must cover identity at alpha zero,
full probability mass, class/support permutation and exact-duplicate invariance,
source-role rejection, exposure versus physical-row accounting and paired
gain/harm arithmetic. Passing these tests does not establish chord recognition.

This distinction follows the separation of selection and generalization in
[scikit-learn's nested-validation guidance](https://scikit-learn.org/stable/auto_examples/model_selection/plot_nested_cross_validation_iris.html).
Explicit-support retrieval remains motivated by
[Matching Networks](https://arxiv.org/abs/1606.04080), not by an assertion that
its published results establish iChart's handwriting accuracy.
