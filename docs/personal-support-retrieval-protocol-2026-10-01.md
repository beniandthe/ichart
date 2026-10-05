# Fixed support-retrieval learning experiment

Scope: offline, public-writer research only. No app/profile/ink, production,
acceptance, export, install, or shipping changes. Base HEAD
`160aa31594903508e241802e21ca83ec447de849`. This changes the personal learner,
not the operational encoder. No private examples, acceptance answers, learned
codepoint exceptions, or development-selected settings may enter fitting.

## Hypothesis and sources

Learn how to retrieve explicit support examples and when to mix them with a
fixed generic prediction, rather than fitting a global residual head. The
support-conditioned approach is motivated by [Matching Networks](https://arxiv.org/abs/1606.04080)
and the cache approach by [Tip-Adapter](https://arxiv.org/abs/2207.09519).
Those papers do not establish sparse handwriting safety; this is a new bounded
test, not their reported accuracy or a reproduction.

## Training evidence, frozen before execution

- UJI source SHA `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
  Only the existing 32 training writers / 6,208 records may enter model
  fitting or training-feature inference. The observed eight development
  writers and 20 reserved writers are excluded from every training stage.
  The sole geometry-only exception is validation of the 248 already-stored
  public setup-support goldens; their predictions/truth cannot inform fitting.
- Split the sorted 32 training writers by ascending SHA-256 of
  `personal-support-retrieval-v1:fold:<writer>`: first 16=A, last 16=B.
- Fit two disposable `PersonalVisualEncoder(97)` generators, seed 29 identical
  initialization. A fits A only and exports features for B only; B reverses
  the roles. Raw 97-way CE, AdamW lr .001/wd .0001, cosine 30 epochs, original
  affine augmentation. Each epoch visits each of its 3,104 records once in a
  seed-29 torch permutation, batches 128. Final checkpoint only. No query or
  development-based checkpoint selection. Each generator has 750 updates.
- Export raw query rasters and setup-stored support rasters from held-out
  training writers only. The support adapter mirrors `PersonalInkShape`'s
  48x32 normalization and 128-point/stroke decimation; verify its geometry
  and pixels against the retained app support fixture before training.
  Unsupported setup shapes remain explicit failures, not invented extent.
- Retain source IDs, writer/session/class roles, original/stored pixel and
  normalized trajectory hashes, fold membership, final weights, histories,
  and feature receipts. Opposite-session meta queries matching generic-fit
  raw ink/pixels or their own raw/stored support ink/pixels are excluded by source-only
  checks. No outcome-selected exclusions.

## One class-equivariant learner

For every query/support pair, only these seven scalar inputs are learned:
cosine similarity, query probability of the explicit support label, support
probability of that label, normalized query/support entropy, query/support
top-one margin. No raw feature coordinates, codepoint embeddings, learned
class-axis matrices, writer/session IDs, or query answers enter prediction.

Deduplicate exact feature/probability/explicit-label lessons before balancing;
duplicates are not independent evidence. Pair score =
`10*cosine + MLP7→32(tanh)→1`; final MLP layer starts at zero.
Subtract log remaining lesson multiplicity per label, softmax over supports, and scatter
weights by explicit label into a full-97 cache. Gate inputs are query maximum,
query margin, normalized query entropy, maximum support cosine, maximum cache
mass, and unique support label count divided by class count. Gate is
`sigmoid(MLP6→32(tanh)→1)`, final layer zero with bias -4. Prediction is
`(1-gate)*generic + gate*cache`. Empty support returns generic exactly. All
untaught class ordering is preserved; a taught class can still overtake a
correct untaught one, so that risk must be measured, not claimed absent.

Fit ten epochs, seed 29, AdamW lr .0001/wd .0001, cosine ten. Every epoch has
one 10-label and one 21-label episode per writer/session direction (128
updates/epoch, 1,280 total). Selectable support labels must have a valid stored
setup shape, checked without model outcomes; retain unavailable-shape counts
and require at least 21 eligible labels in every session. Each subset is an
independent seed-29 torch permutation of those eligible labels; opposite-session
queries include all 97 classes except the
source-only exclusions. Equal-stratum loss:
`0.5*mean(taught negative log probability) + 0.5*mean(untaught negative log probability)`.
Require both strata; no label/result-selected sampling. Final epoch only.

## Evaluation and limits

Freeze weights/code/protocol before applying the learner to the exact cached
full-32 CE encoder feature packet. Encoder SHA
`59bd1e9de8c349cef7209663245cb2b5582497fa31d70207502f1e38ded115d3`;
prediction packet SHA
`6dea2572ced1c8c21fe8523b8fc9d192bb7cfe427a58fb32908e77e664ff5fe9`.
Reuse its exact Swift-stored support geometry and generic probabilities, not
prior personal ranks as inputs. This encoder remains unchanged. Half-encoder
to full-encoder calibration shift is a known limitation.

Core10/catalog21: all 97 session-two queries for each observed writer; 776 raw
and fixed 772 no-copy queries per task. Predictions must be serialized and
hashed before a separate scorer opens truth/copy ledgers. Compare generic,
existing linear-anchored, and new retrieval ranks. Complete finite rankings;
no parser/aliases, top-k rescue, abstention deletion, selected subset, or tuning.

Advance only if retrieval strictly beats linear in both tasks/views, improves
its own generic baseline, has no negative per-writer or untaught net delta
versus linear, and introduces zero untaught harms versus generic. Failure
rejects this fixed candidate without retuning it on the same queries. Passing
permits only a separately specified fresh-writer/runtime test, not promotion.

Tests must demonstrate class permutation equivariance, support permutation and
duplicate-lesson invariance, no learned class axis, empty support identity,
no query-answer input, finite full probability mass, cross-fold-only training,
source-only copy handling, actual nonzero gradients and weight updates.
Previously observed public writers are not fresh or sealed evidence. This
isolated-character research cannot establish natural-chord/device accuracy.
