# Matched musical symbol stroke field experiment

Freeze this protocol, executable source, tests, and input identities before
training. Run one matched two-arm fit, with no checkpoint, seed, mapping, or
parameter search after predictions. This is a representation and coverage
experiment for the existing customizable ML pipeline, not a new OCR service,
an app update, or evidence that personalization already improves.

## Question and boundaries

Does local stroke direction and endpoint information improve a shared encoder
over the same rendered image alone, while retaining existing-symbol behavior?
The original HWRT strokes supply five musical shapes absent from UJI. Both
arms use the same records and image plane. This isolates the added spatial
channels within this architecture, not stroke order as the sole cause of any
effect. The field does not encode acquisition order across separate strokes.

No private ink, saved setup examples, accepted answers, prior labeled chart
queries, or reserved UJI test writers enter encoding, fitting, or scoring.
No profile, chart, live reader policy, or installed model changes. The broader
raw classifier vocabulary is diagnostic training state only: actual-top domain
projection rejects unsupported outputs without promoting a lower legal rank.
Lexical fragments are not complete chords or accepted reader suggestions.

## Fixed sources and mapping

Use the pinned UJI v2 source with SHA-256
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Reuse `uji_personal.split_writers`: 32 training writers and both sessions give
6,208 rows; eight already-observed development writers give 1,552. The 20
reserved writers may be parsed for source completeness only, never encoded.

Use the completed original-HWRT intake receipt SHA-256
`f705c1696878bcc105f3b543dc381f3e78b7dff27e7693864280ac25e5e15545`.
Bind the creator join report
`8b8bd704f05ff3be6fde18856c42618b05a9ba4da6a49cdb598fd212b27cec91`,
HASY intake receipt
`ab9293fb5f81f9dd39ee9ade02f01ecb2bd203d783686f6e28dedab977f220d2`,
and its bound labels and pixel-duplicate ledger. See the completed
[source audit](personal-hwrt-stroke-source-audit-2026-10-03.md).

Only these existing visual mappings are used, with both native ID and LaTeX
validated. No other similar-looking source class is admitted.

| Native IDs | Native labels | Model label | Train | Development |
| --- | --- | --- | ---: | ---: |
| 196 | `+` | `+` | 81 | 9 |
| 922 | `/` | `/` | 478 | 54 |
| 266, 948 | `\#`, `\sharp` | `#` | 1,173 | 131 |
| 950 | `\emptyset` | `ø` | 853 | 97 |
| 959, 977, 152 | `\triangle`, `\vartriangle`, `\Delta` | `△` | 1,280 | 144 |

This is 3,865 original-HWRT training rows and 435 original-HWRT test rows.
These are the original HWRT partition roles, not HASY fold 1. Each trajectory
and corresponding HASY ordinal must stay together. HASY PNGs are provenance
and copy-audit evidence only, not training input. HWRT user IDs are unreliable
as writer identities; its result is sample-level development evidence. Its
new labels are confounded with source domain. Neither source is fresh natural
chord evidence, and their results must not be pooled into one accuracy number.
ODbL source/model shipping rights remain uncleared by this research.

## Representation and source integrity

Reuse the frozen `personal_stroke_field` geometry: five float32 planes of
shape 96 by 256, containing app-exact occupancy, tangent x/y, stroke starts,
and stroke ends. Both arms receive the same five-plane tensor. The control
zeros planes 1 through 4 inside its forward method. Channel zero is the
existing app rasterizer output divided by 255, not a resized HASY bitmap.

Preserve original x/y and stroke boundaries without source-specific flips,
rescaling, pen-lift bridges, or synthetic trajectories. Timing is omitted for
both sources, including all four nonmonotonic-time recordings within this
mapped subset. Retain original intake timestamps in the audit; omission from
the model is not source repair. All mapped rows fit the existing feature
limits. If encoding fails, stop rather than dropping the row.

Prepare training features only before fitting. Both complete fits must finish
before development feature encoding or inference. Use disk-backed float32
arrays and bounded batches instead of retaining the entire field corpus in
RAM. Retain exact occupancy, full-field, and normalized-coordinate hashes.
Preserve every raw development row; mark input-copy exclusions before joining
correctness, using the union of training collisions and repeated development
inputs under those hashes. Report raw and copy-excluded counts separately.

## Architecture and training

Use the same five-input 16/32/64/64 convolutional encoder, 128-dimensional
embedding, and 102-way raw classifier in both arms. Vocabulary is the sorted
97 UJI labels followed by `#`, `+`, `/`, `ø`, `△`. Initialize both complete
state dictionaries identically with seed 29; do not start from prior fitted
weights. The earlier one-channel model is not the matched causal control.

- CPU with four threads and deterministic algorithms.
- Cross-entropy, batch 128, AdamW learning rate 0.001 and weight decay 0.0001.
- Exactly 30 epochs with cosine learning-rate decay to zero, final epoch only.
- Every epoch includes all 64 examples of each old UJI class once, plus 64
  examples of each novel class. Novel samples cycle through deterministic
  class-specific shuffled pools, reshuffling only when a pool is exhausted.
  Record full pool coverage and multiplicity; do not label repeats as new data.
- Each epoch has 6,528 exposures and 51 updates; each arm has 195,840 exposures
  and 1,530 updates. Reset sampling, batch permutation, and augmentation streams
  identically for the two arms.
- Reuse `sample_affine_draws` and `augment_stroke_fields`: historical bounded
  inverse-grid angle, scale and translations, with synchronized rotation of
  tangent vectors. No reflection, timing, label change, or inference augmentation.

Bind and compare initialization, exposure schedule, batch permutations,
augmentation draws, and feature-stream digests. Both final checkpoints must
save and reload exactly and contain finite tensors. Failed or incomplete fits
cannot publish a success receipt. A resumed or altered recipe is a new
experiment, not a silent continuation of these results.

## Prediction freeze and scoring

Prediction and scoring are separate commands with new output paths. Prediction
opens only blind development fields/IDs and the bound final checkpoints, not
truth metadata. Freeze both arms' full 102 logits and 128 embeddings with
opaque IDs and feature hashes before scoring opens the labels. All source,
protocol, code, data, and weight identities must still match their receipts.

Score first raw argmax, case-sensitive, with no lower-rank selection, grammar
repair, or personal support. Use the actual Swift domain export SHA-256
`5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010`,
bound to unchanged `ChordRecognitionDomain.swift`, plus the five novel musical
labels. A forbidden raw winner projects to no-read, without renormalization.
Report correct, wrong permitted, unresolved, paired corrections/regressions,
writer-level results, all five mapped classes, and all eight HWRT native IDs.

Advancement requires every raw-data condition below, not merely aggregate gain:

1. UJI gains exceed harms on all 1,552 rows, with exact two-sided writer-cluster
   sign-flip p below 0.05 over all 256 sign assignments, including equality.
2. At least six of eight UJI writers are non-worse; none loses more than two
   of 194 queries. Candidate raw UJI correctness reaches the historical
   descriptive floor of 1,229; this floor is not a matched causal comparison.
3. The 41-label UJI chord-fragment subset also has gains exceeding harms.
4. On UJI out-of-domain truth, there are zero control-no-read to
   candidate-permitted-read transitions and no increase in total potential
   permitted reads. These are glyph projection errors, not observed wrong chords.
5. On 435 HWRT development rows, gains exceed harms overall, and none of the
   five mapped classes loses correct readings. Native-alias results stay visible.

Repeat paired gains, writer sign-flip and writer/OOD safety checks after the
input-copy union exclusion. These must also pass; the absolute 1,229 floor is
raw-only. Do not relax a failed rule or select an alias, writer, or checkpoint
from outcomes. Eight previously observed writer clusters limit interpretation;
the sign-flip test assumes independent clusters and sign symmetry.

## Next step after the result

A pass permits an independently reviewed, blind app-domain and optional-learning
experiment, not model installation or shipping. This phase does not fit a
personal head, establish untaught-symbol safety, or claim improved learning.
Those remain required before a personalized candidate can advance. A failure
keeps both models offline and determines the next evidence-based intervention.
Python research tests are not Core ML parity, Swift runtime parity, physical
Pencil acceptance, fresh full chords in either chart style, or ship readiness.
