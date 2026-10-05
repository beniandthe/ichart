# Fixed synchronized raster/trajectory development experiment

Freeze this protocol, producer, scorer, augmenter and synthetic tests before
fitting or development inference. Run exactly one matched two-arm fit; no
checkpoint, seed, parameter or writer-role search after seeing results.
This is research for the customizable handwriting pipeline, not a replacement
OCR engine or a change to the live app.

## Question and evidence boundary

The previous unaugmented dual encoder beat its matched raster control
(1,117 versus 1,035 exact glyphs) but trailed the historical augmented raster
encoder (1,229). That leaves an augmentation-regime confound. Test whether the
same fixed dual architecture with synchronized geometric augmentation can
improve the shared representation without writer-level deterioration.

The primary comparison is dual versus a newly fitted matched raster-only arm.
Identical nominal parameter counts do not imply identical effective capacity;
enabling the second branch changes information and active capacity. A positive
result does not isolate stroke order as the sole cause of a benefit.
No private ink, profile lessons, accepted answers, or the twelve newly labelled
Simple/Rhythm queries may enter training, tuning or this experiment's scoring.
No app, chart, teaching profile or live acceptance policy changes in this pass.

## Source and fixed writer roles

Use the preserved, unmodified UJI v2 text with SHA-256
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
The [official publication](https://archive.ics.uci.edu/dataset/177/uji%2Bpen%2Bcharacters%2Bversion%2B2)
documents real coordinates, ordered strokes, writer/session identifiers, and
CC BY 4.0 licensing. It records no timing; do not synthesize it.

Retain the existing `uji_personal.split_writers` roles: 32 fit writers, eight
already-observed development writers, and 20 reserved official test writers.
Both sessions and all 97 labels yield 6,208 training glyphs and 1,552
development queries (194 per writer). Parsing reserved records for source
completeness is allowed; transforming, encoding, fitting or inferring them is
not. These eight development writers are not a fresh or sealed test.

UJI does not provide `#`, `+`, `/`, `ø`, or `△`. Lowercase `b` and other ordinary
character samples do not establish musician-written symbol coverage. Supplied
isolated-character ownership also does not establish automatic ownership or
natural full-chord quality.

## Model and optimization

Reuse `personal_dual_view.PersonalDualViewEncoder`, without changing its
architecture, feature encoders, vocabulary, masks, or timing-channel exclusion.
Use only `rasterOnly` and `dual`; an inactive branch is zeroed after projection.
Bind the checkpoint to its trained mask; never enable a branch after fitting.
The raster branch is the existing 16/32/64/64 convolution stack; the trajectory
branch uses x/y, dx/dy, arc step, start/end/valid channels. The fused raw
128-vector drives the 97-way classifier; the normalized vector is retained
only for the separately declared personal diagnostic.

- CPU, four threads, deterministic PyTorch algorithms, initialization seed 29.
- Both arms start with bit-identical tensors and use the same seed-29 batch
  permutations and augmentation draws, reset for each arm.
- Cross-entropy only, batch 128, 30 epochs, AdamW learning rate 0.001, weight
  decay 0.0001, cosine scheduler to zero. No early stopping or class filtering.
- Evaluate the final epoch only. Finish both fits before development inference.

## Synchronized augmentation contract

Reuse the historical raster augmentation's bounded distribution and sampling
convention: four deterministic pseudorandom uniform-range draws per source
exposure, derived from a domain-separated SHA-256 of seed, epoch and source
identity. This new order-independent schedule is not the historical Torch RNG
sequence; both new arms receive exactly the same draws. Use grid
output-to-input angle in [-8,8] degrees, inverse scale in [0.9,1.1], and
normalized grid translations x in [-0.06,0.06], y in [-0.10,0.10]. These are
inverse-grid parameters, not incorrectly reported forward displacements.
Use bilinear sampling, zero outside the raster, `align_corners=False`, and the
historical rectangular aspect correction. No reflection or label alias.

Apply the exact inverse pixel-space affine to trajectory positions in the
already canonical frame. Raw-source recentering/max-dimension normalization
must not run after the transform: it would erase translation and uniform scale.
Compute each source's canonical-to-pixel isotropic scale from its original
geometry, using the frozen raster mapping (237/normalized width and
77/normalized height, minimum finite scale). Do not infer this scale from
resampled trajectory extrema, which can omit source extrema.

A fully coincident dot has source raster scale zero. Retain that raw scale in
metadata; use an explicitly named effective scale of 77 (the shorter usable
pixel span) only for its training augmentation, so its translated trajectory
and raster center agree. This convention invents neither source coordinates
nor timing and does not change unaugmented inference. Do not drop these rows.

Transform x/y, recompute within-stroke dx/dy and arc step, retain stroke order
and start/end/valid topology, keep timing channels unavailable and invalid
rows zero. Do not bridge pen lifts. Do not clip trajectory coordinates or
silently drop points to mimic raster clipping. Raster interpolation/thickness
changes are part of this distribution, not exact new human handwriting.
Neither arm uses augmentation at development inference.

Bind augmentation and permutation stream digests to the fit receipt and
require both arms' digests and exposure counts to match. The shared stream is
label-blind and independent of model outputs. Synthetic asymmetric-shape
checks must verify inverse direction, scale, translation, rotation and raster/
trajectory agreement; identity and source-preservation checks are required.

Draw source identities are the existing `personal-dual-view-v1` opaque SHA-256
of the pinned source digest and exact sample identity. Retain each epoch's
complete permutation ordinals. Stream framing is an eight-byte big-endian
payload length followed by the payload: little-endian int64 permutation bytes,
canonical JSON batch augmentation metadata, and little-endian Float32
trajectory then raster bytes (separate frames). An independent checker can
reconstruct the metadata/permutation streams without model or feature encoding;
feature-stream digests establish binding/equality, not independent re-encoding.

## Freeze before truth joins

Fit, prediction and scoring are separate CLI processes with exclusive new
output directories. Bind source, protocol, code dependencies, runtime,
initialization and both final checkpoint bytes by SHA-256. Preserve the exact
executed source and all histories. Reject changed, incomplete or aliased inputs.

Freeze all 1,552 queries and both arms' full 97 raw logits and 128 embeddings
before scoring. Include opaque IDs, exact unchanged inference feature hashes,
and complete original-stroke ownership indexes. Do not emit expected labels,
writers, label-bearing source IDs or correctness into prediction packets.
Scoring must validate complete frozen bytes and bindings before joining truth;
select first raw argmax in the bound vocabulary, never a desired lower rank.

## Predeclared endpoint and decision

Primary: exact case-sensitive 97-way first argmax on all 1,552 development
glyphs, paired dual versus matched raster. Retain all rows; report gains,
harms, each writer's counts, all label confusions and case-only misses.
Case folding, grammar or personal support cannot repair the primary answer.

Advancement to a subsequent blind app-domain comparison requires every rule:

1. Dual gains exceed harms against the matched raster control.
2. Exact two-sided writer-cluster sign-flip p < 0.05 over the eight writer
   deltas: enumerate all 256 sign assignments, including equality.
3. At least six of eight writers are non-worse.
4. No writer loses more than two of its 194 queries.
5. Dual reaches at least the pinned historical operational result of
   1,229/1,552. This floor is descriptive, not a matched causal comparison.

Pin historical `public-identity.json` SHA-256
`c4b6acc6caf76e0f7d0af9ee8036cd672673f1690e790fee3dcf14fea329c01b`.
Do not retune a failed candidate. A pass permits another independently reviewed
experiment only: it is neither shipping authorization nor calibrated trust.
The writer-cluster test assumes independent writers and sign symmetry; eight
already-observed clusters limit interpretation. Row McNemar is descriptive.

Keep duplicate-input diagnostics from the previous protocol: flag exact
training raster/trajectory or normalized-source copies without removing raw
rows; report the union-excluded novelty counts separately. These exclusions
must depend on inputs, not correctness.

## Optional-personalization secondary diagnostic

For each arm/writer, use the unchanged direct balanced one-hot ridge, lambda
0.1, fit on the 97 explicitly labelled session-one embeddings. Freeze all 97
session-two predictions before scoring their labels. Report gains/harms and
writer breakdowns on all 776 paired session-two queries plus copy exclusions.
No generic-logit addition or residual fit; do not select a personal method from
these results. This differs from the current Swift residual personal head.
All 97 classes are taught here, so this diagnostic cannot measure untaught
symbol safety. It cannot justify a personal default or override.

## Verification and nonclaims

Run nonzero synthetic producer/augmenter/scorer tests, unchanged model/source/
ridge regression checks, and an independent frozen-argmax/count/binding review.
Retain fit histories, stream receipts, frozen outputs, scores and command exit
statuses. Verify source/code/checkpoint preservation after execution.
No iOS build is warranted by Python-only research edits. Training and public
development scoring are not Core ML/Swift parity, iPad interaction, new-writer
natural-chord recognition, learning benefit in the app, or ship readiness.
