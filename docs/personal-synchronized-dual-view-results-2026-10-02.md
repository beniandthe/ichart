# Synchronized dual-view representation: executed result, 2026-10-02

## Decision

The new synchronized raster-plus-trajectory encoder improves the aggregate
public development result, but **fails its fixed writer-regression guard**.
Keep both checkpoints offline; do not advance this candidate, relax the guard,
retune against its misses, or activate it in iChart. The recognition and optional
personal-learning goal remains active, not achieved by this experiment.

This is an executed two-arm training experiment, not another OCR engine or a
claim that the customizable ML pipeline already improves live app recognition.
No app, chart, profile, device, private-query or production change was made in
this research continuation. The twelve newly labelled Simple/Rhythm queries
remain evaluated holdouts, not training data.

## Frozen question and execution

The [pre-fit protocol](personal-synchronized-dual-view-protocol-2026-10-02.md)
tests synchronized geometric augmentation of the unchanged dual architecture
against a newly fitted, matched raster-only arm. The earlier unaugmented dual
experiment exceeded its unaugmented raster control but trailed the historical
augmented operational encoder. This pass addresses that augmentation-regime
confound; it does not isolate trajectory order from added information/capacity.

Source: preserved UJI Pen Characters v2, SHA-256
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
The [official UCI source](https://archive.ics.uci.edu/dataset/177/uji%2Bpen%2Bcharacters%2Bversion%2B2)
describes isolated characters, writer/session identities, coordinates and stroke
order, with CC BY 4.0 licensing. No source timing was invented. Preserve that
dataset's attribution with any redistribution. Its ordinary character inventory
does not establish musician-written sharp, slash, half-diminished or major-triangle
coverage, automatic glyph ownership, or complete handwritten-chord recognition.

The existing roles were fixed before execution: **32 fit writers / 6,208 glyphs**,
**eight already-observed development writers / 1,552 glyphs**, and **20 reserved
official-test writers / 3,880 glyphs**. Reserved records were parsed only for
source completeness; they were not transformed, encoded or inferred. Both
sessions and all 97 classes remain in the primary denominator. The development
writers are not unseen or sealed-test evidence.

Both arms used identical seed-29 initial tensors, shared training permutations
and augmentation draws, batch 128, 30 epochs, CE-only AdamW at 0.001 with weight
decay 0.0001 and cosine decay to zero, deterministic CPU execution with four
threads. Each completed 1,470 updates and 186,240 source exposures. Both fits
finished before any development prediction; only their final checkpoints were
evaluated. No search, early stopping, class filtering or post-result retuning.

The augmentation retains the historical bounded distribution but uses a new
hash-derived, order-independent draw schedule, not the historical Torch random
sequence. Raster inverse sampling and the corresponding forward physical-pixel
trajectory affine are synchronized. Per-source scale derives from original
bounds, not resampled extrema; degenerate dots retain the explicit zero-source
scale/effective-augmentation-scale convention. Derived trajectory channels are
recomputed without bridging pen lifts, synthesizing timing, clipping trajectory
points or renormalizing away translation/scale. Inference encoding is unchanged
and unaugmented.

All 1,552 queries × two arms retain full raw 97-class logits, 128-vector
embeddings, opaque identifiers, inference-feature hashes and original stroke
indexes. The prediction packet contains no intended labels, writer identities
or correctness. A separate scorer validated the bindings before joining source
truth and used first raw argmax, without case folding, notation aliases, grammar,
personal support or desired lower-rank selection.

## Primary result

These are exact, case-sensitive isolated-glyph counts, not chord accuracy.

| Model | Correct / 1,552 |
| --- | ---: |
| Newly trained matched augmented raster-only | 1,216 |
| Newly trained synchronized dual | 1,248 |
| Pinned historical operational reference, unmatched | 1,229 |

Dual corrects **85** raster errors and introduces **53** errors: net **+32**.
The exact eight-writer sign-flip calculation is **10/256 = 0.0390625**;
seven writers are non-worse. This assumes independent writer clusters and sign
symmetry, with only eight already-observed development writers. It is not a
new-writer guarantee. The historical floor is descriptive, not a matched causal
comparison or a claim of the best possible representation.

| Development writer | Raster / 194 | Dual / 194 | Gains | Harms | Net |
| --- | ---: | ---: | ---: | ---: | ---: |
| UJI W04 | 145 | 151 | 12 | 6 | +6 |
| UJI W06 | 164 | 168 | 10 | 6 | +4 |
| UJI W08 | 159 | 155 | 9 | 13 | **−4** |
| UJI W11 | 150 | 159 | 13 | 4 | +9 |
| UPV W35 | 157 | 162 | 9 | 4 | +5 |
| UPV W43 | 158 | 162 | 7 | 3 | +4 |
| UPV W47 | 136 | 137 | 13 | 12 | +1 |
| UPV W56 | 147 | 154 | 12 | 5 | +7 |

Four required rules pass: gains exceed harms; writer p < 0.05; at least six
writers are non-worse; dual reaches the historical 1,229 floor. The fifth rule
fails: **W08 loses four, above the predeclared maximum of two**. Every rule was
required. The saved decision is therefore ineligible for advancement and
nonproduction. Novelty filtering does not repair that failure.

The input-only duplicate union flags seven queries, leaving 1,545: raster
1,209 correct, dual 1,241, with the same 85 gains / 53 harms. Raster, trajectory
and normalized-source copy counts overlap (7, 7, 5); do not sum them. Raw primary
rows were not removed. Case-only misses remain errors: raster 115, dual 110.

## Secondary personal-learning diagnostic

The fixed direct balanced one-hot ridge head, lambda 0.1, uses each writer's 97
labelled session-one examples to predict 97 session-two examples. Answers were
fixed in memory before correctness scoring; this diagnostic does not have a
separate durable pre-annotation personal-prediction packet. All 97 classes are
taught. It differs from the app's Swift residual head and cannot establish
untaught-symbol safety or justify a personal default.

| Arm | Generic correct / 776 | Personal correct / 776 | Gains | Harms | Net |
| --- | ---: | ---: | ---: | ---: | ---: |
| Raster-only | 607 | 618 | 99 | 88 | +11 |
| Dual | 625 | 631 | 96 | 90 | +6 |

Raw per-writer personal deltas in the table's writer order are raster
`+4, −7, +5, 0, +13, −1, −11, +8`; dual
`0, −3, +7, +2, +6, −2, −8, +4`. Aggregate benefit coexists with many new errors
and writer regressions. The four-copy-excluded diagnostic has 772 queries:
raster 603→616 (99 gains / 86 harms), dual 621→628 (96 / 89). This is not a safe
learning override and does not change the existing profile or learning recipe.

## Executed verification and limits

- Focused research gate: **52 executed, 52 passed, zero failures/skips**, with
  warnings treated as errors. It covers frozen source/model/scorer contracts,
  augmentation direction/topology, source preservation, producer bindings and
  fixed decision guards. It is not an iOS or recognition-accuracy test count.
- Actual fit, prediction and scoring processes completed with exit 0. Retained
  histories contain all 60 arm-epochs and 3,104 prediction cells; checkpoint
  tensors changed from initialization and remain bound to their trained mask.
- Independent standard-library verification froze all first-argmax answers
  before reading source truth or the score, then reproduced primary, per-writer,
  per-label/confusion, novelty and decision arithmetic exactly. It validated all
  18 current/preserved dependency byte bindings, source, protocol, checkpoint
  bytes, source mappings, roles and retained permutation/draw-metadata streams.
  It did not regenerate feature tensors, replay Torch randomness, refit a model
  or independently reproduce ridge inference. Feature-stream hashes verify
  equality/binding, not an independent feature re-encoding. Its separate
  count-only personal review matches the saved personal summaries.
- The executed final verification confirms source/code preservation, trained
  tensors, counts, independent agreement and the nonzero 52-test gate.
- A broader old dual-view/export test preflight executed 60 cases with one
  existing JIT/Core ML export error: a tracing warning was promoted by `-Werror`
  at a Python shape check and surfaced as `SystemError`. Its failed log is
  retained. It is **not** a passing broad/export gate; no warning was suppressed
  and no export/parity claim is made.

Runtime: Python 3.12.14, Torch 2.7.0, NumPy 2.0.2, macOS 26.5.2 arm64, CPU four
threads. No dependency installation or OS upgrade was required. No Core ML
export, Swift application-feature/runtime parity, iPad build/install/launch,
Pencil interaction, natural-chord transfer or unseen-writer accuracy was tested.

## Preserved evidence and next boundary

Exact public source, historical reference, frozen protocol and 18 dependencies,
both weights, fit ledger, label-free predictions, score, independent argmax and
count receipts, execution checker, failed/successful test logs and this result
are retained in a fresh non-overwriting folder outside Git:

`/Users/benirossman/.local/share/ichart/recognition-development/synchronized-dual-view-20261002.H6BAAm`.

| Artifact | SHA-256 |
| --- | --- |
| Fit receipt | `0591400c1ea14d7cfa5c95931bb354b2431026422c2525592e08fad26d56ac51` |
| Frozen predictions | `77ed985ac988d7200c4ced4ba146700d1cff94f6680ae3eb6696bc7b85335dd0` |
| Score | `9d0add14ce9ae099e96e5c0052a06df4dfaa6511f2cb82056a9f60f22918d13e` |
| Independent counts | `86e7d11e3736cd5e9c77477b17b6e4705fda7d757a7afe8db86fb61e50062f11` |
| Execution verification | `fa7b0df0932798cd52eedd0669cb9cb49130ee20b880d7e33cf403dfbb0fe480` |

The preservation manifest binds every retained file. Checkpoints and bulky
data remain outside the repository; research code/tests/protocol/results are
source changes only. No commit, push, upload or deployment was performed.

Do not ask the writer to repeat these tests, teach the twelve private queries,
open the reserved twenty writers, or tune this failed candidate to its errors.
Further advancement needs a separately justified general mechanism and a new
frozen evaluation, plus independently reviewed app-domain/multiwriter evidence
before a live integration decision. This pass establishes aggregate public-glyph
progress and a concrete writer-safety failure, not a completed recognition goal.
