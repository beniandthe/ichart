# Train the visual model to support personal learning

This is a fixed development experiment in our customizable ML pipeline, not an
alternate recognizer. Freeze this protocol before training or inspecting its
predictions. It has no live recognition, trust, profile-write or render authority.

## Question and matched control

Does training through the existing personal residual learner improve its use of
a small explicit handwriting profile, compared with the same amount of ordinary
training? The motivation is differentiating through an inner closed-form learner
([Bertinetto et al., 2019](https://arxiv.org/abs/1805.08136)). Our residual objective
below is an experiment, not a reproduction of that paper's accuracy results.

- Start all arms from `personal-visual-encoder-v1`, weights SHA-256
  `5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`.
  Keep the same CNN, 128 unit features, 97 generic labels, and app rasterization.
- Keep the existing public UJI v2 split: 32 training writers, eight development
  writers and 20 reserved writers. The latter are structurally parsed only,
  never rasterized, fitted or predicted. No private handwriting trains this model.
- Compare the unchanged starting model, matched generic-only fine-tuning, and
  generic-plus-personal fine-tuning. No parameter sweep, early stopping, best
  checkpoint selection or changing settings after development results.
- Ten epochs, seed 29, CPU four threads, deterministic operations. AdamW learning
  rate 0.0001, weight decay 0.0001, cosine decay across ten epochs. BatchNorm stays
  in evaluation mode in both arms: query samples cannot affect support features
  through batch statistics. All learned parameters still receive gradients.
- Each epoch uses both session directions for every training writer (64 episodes).
  Each episode draws 16 distinct support labels uniformly without replacement
  from one session; queries are all 97 labels of the other session. Identical
  normalized-trajectory or raster support copies are removed from that episode's
  queries. Both arms get identical episodes, augmentation and optimizer steps.
- Apply only the existing label-blind affine augmentation, separately to every
  support/query input. No augmentation during development prediction.
- Generic objective: mean cross-entropy on all support and query images.
  Personal objective: generic objective plus the mean, over queries, of the sum
  of squared errors between the adapted score vector and its training one-hot
  label. The personal term has fixed coefficient 1. It is not cross-entropy over
  negative residual scores and does not treat those scores as probabilities.
- The differentiable inner learner is the app comparison's class-balanced ridge
  fit to `oneHot(support) - softmax(supportLogits)`, lambda 0.1. Predictions are
  `softmax(queryLogits) + queryFeatures * fittedWeights`. Gradients pass through
  the solve, the support residuals, support features and query features. Training
  query labels enter the outer loss only, never the personal fitting API.

## Evaluation and decision boundary

Evaluate only the final model of each arm on the same eight development writers,
session one for explicit lessons and session two for queries. Use two fixed
profiles: all 97 lessons, and 16 labels chosen by sorting the vocabulary by
SHA-256 of `personal-adaptability-v1:sparse16:` plus label. All 97 classes remain
competitors for every query, including labels absent from the small profile.

Use one conservative novelty denominator for every model/profile: exclude any
query whose normalized trajectory or raster equals any of that writer's 97
session-one samples or any encoder-training sample. Retain every excluded row
and reason. Report generic and personalized top-1, gains **and harms**, taught
versus untaught labels, per-writer results, and all query identities/rankings.
The development writers have already been inspected in earlier experiments;
they are not a fresh independent benchmark. Do not touch the 20 reserved writers.

Validate the differentiable learner against the existing independent NumPy
solver, check its gradients numerically, prove query answers do not enter fitting
or alter predictions, and assert writer/session isolation before rasterization.
Persist the protocol, code hashes, source/starting-weight hashes, episode plan,
both complete training histories and checkpoints in a new evidence directory.

Even a positive result does not promote a model into iChart. UJI contains isolated
characters, not complete chords; it lacks `#`, `/`, `+`, `△` and `ø`. Musical-symbol
coverage, fresh complete chords in both styles, independent writers, runtime
parity and selective trust remain separate requirements. A loss on this experiment
must be recorded rather than worked around with user/chord-specific rules.
