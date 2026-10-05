# One matched adaptation-aware continuation fit

Freeze this protocol and the implementation before actual fitting. This is a
single development experiment, not an app-default change or a parameter search.

## Question and causal comparison

The frozen dual encoder's sparse residual learner gained 12 answers but damaged
15, including 14 untaught answers. Test whether training the representation for
the exact learner can improve sparse teaching without sacrificing generic or
untaught recognition. This changes the training objective, not recognition
thresholds, user-specific rules, the app's residual solver, or its acceptance.

Initialize one generic control and one adaptation-aware candidate from the same
unchanged final dual checkpoint under `dual-view-glyph-20260930.ttfIcd`:
`fit/weights/dual.pt`, SHA-256
`ed722707ad992b6c282dd6f416ac173bc972c7517b1804d72c08f57cbf1a1507`.
The public source SHA-256 is
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Keep the same 97-label vocabulary, 128-dimensional normalized features, dual
architecture and eight geometry channels. No timing channels or augmentation.

## Fixed training design

Only the existing 32 training writers may enter training or feature encoding
during fitting. The eight observed development writers and twenty reserved
writers never enter the optimizer. Use ten final-only continuation epochs,
seed 29, four CPU threads, deterministic PyTorch algorithms, AdamW learning
rate 0.0001 and weight decay 0.0001, cosine schedule with T_max 10. Reset the
optimizer/scheduler identically for both arms. Freeze BatchNorm running
statistics by using evaluation mode, while allowing gradients in all trainable
parameters. Do not pick a best epoch or restart after seeing development data.

Each epoch has 64 directed episodes: every training writer in both directions,
session one support to session two query, and the reverse. Shuffle episode order
with a seed-29 generator. For support, use a fixed SHA-256 permutation of the
97 vocabulary labels keyed by
`personal-dual-adaptation-v1:training-support:<label>`; take consecutive rotating
windows of 16 labels starting at `16 * global_episode_index mod 97`. This balances
support counts within one across all 640 episodes and does not specialize the
model to the previously observed sparse16 evaluation labels. Bind the complete
episode plan and support counts before training. No query correctness influences
support. Exact support/query normalized-trajectory or raster copies are excluded
from the outer training loss before fitting; record all exclusions and actual
query counts. All 97 output classes remain competitors in every episode.

Let z be raw shared logits, x be normalized features, and Ys the explicit support
one-hot labels. With support frequency multiplier b = 1/sqrt(class frequency),
fit the unchanged residual normal equation in float64:

    Xw = b * Xs
    Rw = b * (Ys - softmax(zs))
    W = Xw.T @ solve(Xw @ Xw.T + 0.1 * I, Rw)
    adjusted = softmax(zq) + xq @ W

Use the existing differentiable `personal_adaptability.adapted_scores` with
float64 inputs and synthetic parity/gradient tests against the unchanged NumPy
ResidualHead. No learned lambda, alpha, temperature or ranking calibration.
Adjusted values can be negative and are ranking scores, not probabilities or
confidence. Cross-entropy of these scores is a fixed training surrogate only.

Generic loss uses query rows only, not the 16 overrepresented support rows:

    control = 0.5 * CE(zq, yq) + 0.5 * CE(zq, yq)
    candidate = 0.5 * CE(zq, yq) + 0.5 * CE(adjusted, yq)

Both arms use identical examples, episode order, initial tensors, optimizer,
schedule and step counts. Only the second half of the loss changes. Query truth
is allowed solely as an outer training target for these training writers;
development prediction receives no query labels.

## Frozen development readout

Separate fit, prediction and score processes. Freeze both final checkpoints,
histories, source/protocol/code/runtime/parent hashes and episode manifest before
any development encoding or inference. Freeze complete generic features/logits
for all 1,552 already observed development glyphs, and the complete sparse16
residual rankings for all 776 session-two queries in both arms, before joining
query truth. Query IDs are opaque; only session-one support rows expose labels
to the learner. Reuse the prior sparse selector unchanged: `!`, `E`, `F`, `L`,
`T`, `Z`, `d`, `g`, `j`, `k`, `n`, `t`, `w`, `x`, `Ó`, `á`.
Use all 97 vocabulary competitors and unchanged NumPy residual inference.
Validate hash bindings, complete coverage, finite shapes, exact roles, and
prediction arithmetic before scoring. Publish completion receipts last and
refuse existing outputs/aliases. Preserve original source, checkpoint and prior
evidence. Predictions must be invariant to changed query answer labels.

Primary endpoint is candidate residual versus matched-control residual over all
776 paired queries. Report every writer, class, gain/harm, and candidate taught
128 and untaught 648 versus its own generic result. Report candidate versus
control generic on all 1,552. Keep all rows, including copies; a clearly named
secondary conservative novelty cohort may use the same four exclusions from
the prior full-support diagnostic but may not replace these primary counts.

The candidate is worth freezing for a later independent-writer gate only if all
four development-stage conditions hold:

1. Candidate residual is better than control residual over 776.
2. Candidate taught residual is better than its own taught generic over 128.
3. Candidate untaught residual is no worse than its own untaught generic over 648.
4. Candidate generic is no worse than control generic over 1,552.

Failure of any condition means this fixed intervention did not meet its joint
goal. Retain the negative result, do not tune support sets, alpha/lambda, loss
weights, epochs or conditional routing to rescue it. Historical dual generic
1,117/1,552 and older raster 1,229/1,552 are context, not matched causal controls.

## Verification and limits

Synthetic tests and independent code review precede actual fitting. Tests cover
balanced deterministic role-separated plans, copy exclusions, exact residual
math and gradients, equal arm scales and starting state, unchanged BatchNorm
buffers and original checkpoint, query-answer isolation, complete competitors,
and rejected tampered/missing artifacts. Reconcile nonzero executed tests and
all paired counts independently after scoring.

This is isolated public character research. No private ink/profile/chart change,
reserved-writer inference, app-default switch, signing, installation, production
deployment or shipping claim. The eight development writers already influenced
the design; a win is not fresh-writer or natural-chord evidence. Do not build a
new app bridge unless the fixed candidate first meets the declared conditions.
