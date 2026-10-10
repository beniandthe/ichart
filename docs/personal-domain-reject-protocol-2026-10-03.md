# Chord domain learning with explicit rejection

Freeze this protocol and the executable implementation before real preparation
or fitting. Test one new output objective, not another seed, geometry, or
threshold sweep. Earlier generic character models were trained to distinguish
unsupported characters and only filtered afterward. This candidate learns
legal chord fragments plus a single rejection outcome. It is research toward
the existing optional-personalization pipeline, not an app model promotion.

## Fixed hypothesis and output contract

Use the frozen image-only encoder architecture from the matched HWRT stroke
experiment: five input planes with auxiliary planes masked to zero, identical
convolution, normalization and 128-dimensional projection. The control retains
its 102 literal outputs. The candidate has the 41 legal original fragments in
the pinned app domain, followed by `#`, `+`, `/`, `ø`, `△`, then `REJECT`.
No unsupported character is a candidate output identity. `REJECT` is internal
and presents as unresolved, not as text. Fragments such as `1` and `j` remain
legal only within valid complete chord context; this experiment cannot relax
the installed complete-chord presentation boundary.

Both models start afresh. Construct the original seed-29 102-way model, copy
its complete feature state to both arms, copy the legal classifier rows exactly
to the candidate, and initialize its rejection row to the arithmetic mean of
the 56 forbidden weight rows and biases, without a log-count offset. Preserve
global RNG state. Use ordinary unweighted cross entropy. The control receives
literal targets; the candidate maps every forbidden target to REJECT.

Both arms receive identical batches and augmentations. Inference uses only
the candidate's own 47 scores: a unique legal maximum is a fragment, while a
REJECT maximum or any tied maximum is unresolved. No legal runner-up promotion,
post-fit threshold, ensemble, parser rescue, or per-writer rule. The control's
first-argmax projection remains unchanged. Explicit teaching-label validation
allows only the same 46 legal fragments and never REJECT or unknown labels.
This is compatibility groundwork, not evidence of a personal-learning benefit.

An explicit learned reject output is a distinct hypothesis from the prior
support/action selectors. Research on [selective recognition](https://proceedings.mlr.press/v97/geifman19a.html)
supports evaluating risk together with coverage; it does not validate this
architecture. [Outlier Exposure](https://arxiv.org/abs/1812.04606) also reports
that a reject-class approach was not the strongest method in its benchmarks.
The present choice is therefore a falsifiable app-domain experiment, not a
claim that the literature guarantees it will work.

## Sources and internal splits

Use only the preserved original stroke-field TRAINING bundle at
`/Users/benirossman/.local/share/ichart/recognition-development/hwrt-stroke-field-20261003.8ZTPn0/training-data`.
Its receipt SHA256 is
`5e00aa3ce986a07b7a3d4547ebc80b42307cf37a85f9f2e82870b6508b6957e5`;
training metadata SHA256 is
`56cdb11b58b6b02f36b30b7ed23c870681c44885af4bbd27cd5020bbdf761977`.
The pinned app domain SHA256 is
`5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010`.
Authenticate the parent receipt, full field-file hash, metadata, labels, source
roles and every extracted image hash. Never modify parent code or receipts.

There are 6,208 UJI drawings from exactly 32 training writers and 3,865 HWRT
training drawings. Sort the 32 IDs by SHA256 of UTF-8
`ichart-domain-reject-writer-v1` + NUL + writer ID, then ID as tie breaker.
The first 16 form A; the other 16 form B. Train A and query B, then train B and
query A. Both sessions of a writer stay together. No examples from the eight
old development writers or twenty reserved writers are loaded or inferred.

For each of the eight HWRT native IDs, sort training recordings by SHA256 of
UTF-8 `ichart-domain-reject-hwrt-v1` + NUL + opaque ID, then opaque ID.
The first floor(n/5) form a shared internal query cohort; the rest form the
shared fitting cohort. Expected counts are 770 query and 3,095 fitting rows.
HWRT queries are reused across the two model folds and must not be counted as
independent duplicate samples. HWRT writer identities remain unreliable;
this portion is record-level evidence only. The official HWRT test partition
is not used. The five HWRT-only labels remain source-confounded.

Each fold therefore has 6,199 fit rows and 3,874 query rows. Across folds,
query exposures are 7,748 but distinct query drawings are 6,978. These data
have participated in earlier research; this is internal writer-blocked model
development, not new independent validation or a sealed holdout.

Prepare immutable one-channel Float32 raster artifacts from parent plane zero,
without changing normalization or coordinates. Separate fit labels from blind
query IDs/hashes and a truth sidecar. Preparation may materialize all internal
roles; fitting may open only its fold's fitting artifacts. After both folds
finish, prediction may open blind query artifacts and own-fold label-free fit
fingerprints solely for duplicate accounting. Those fingerprints contain only
opaque IDs, raster hashes, and normalized-geometry hashes, never fitting labels
or truth; they cannot enter model inputs or routing. Do not mix private lessons,
chart answers, or public query labels into fitting or routing.

## Frozen training and scoring

For each fold, keep the old training recipe: seed 29, CPU four threads,
deterministic algorithms, AdamW at 0.001 with weight decay 0.0001, cosine
schedule over 30 final-only epochs, and batches of 128. Each epoch schedules
64 examples for each original source label, totaling 6,528 exposures and
51 updates. Each UJI label has 32 fitting drawings, cycled twice per epoch.
For every source label, order fitting rows by SHA256 of UTF-8
`ichart-domain-reject-cycle-v1` + NUL + opaque ID, then opaque ID; epoch e
(zero-based) takes positions (64*e+j) modulo class size for j in 0...63.
Shuffle that epoch's combined list with an independent NumPy default_rng(29+e).
Use the frozen affine draw generator with a fresh seed-29 stream per fold.
Both arms finish exactly 1,530 updates and 195,840 exposures per fold.

The reject pool is balanced across its 56 original source identities, not
balanced to the size of one legal class: it has 3,584 of 6,528 exposures per
epoch. This intentional class collapse must not be hidden in reporting.
All original fitting rows must appear during the full schedule. New checkpoint
and receipt versions identify the 47-way objective; old checkpoints cannot
masquerade as it. Freeze source/code/protocol, roles, plan, initialization,
actual input hashes, finite updates, and final saved/reloaded states. There is
no earlier final-state sentinel for these different fitting splits.

Freeze both arms' full logits and embeddings for every query before the
separate scorer opens truth. Retain failures. For each fold, recompute copies
using parent normalized-geometry hashes and extracted image hashes, including
fit-query overlaps and within-query repeats; retain raw and copy-excluded
views. Report UJI legal, UJI forbidden, every writer, all five HWRT shapes and
eight native IDs separately, with correct, wrong-legal, unresolved, and every
paired transition. Do not score REJECT as a correct chord or pool the sources.

In BOTH folds and BOTH raw/copy-excluded views, advancement requires complete
finite outputs, strictly more correct legal UJI readings than control, fewer
total wrong-legal UJI readings, no reduction in correct readings for any query
writer, no new correct-or-unresolved to wrong-legal transition on any UJI/HWRT
query, and non-worse correct counts for every mapped HWRT class. Report accepted
coverage and lost correct reads explicitly. Reject-all fails the correct-read
requirement. No threshold or rule may be chosen from these answers.

A failure leaves this fixed candidate offline. Even a pass only earns the next
reviewed comparison of optional learning and actual chord writing; it cannot
prove source-independent generalization, calibration, natural full-chord
accuracy, Core ML/Swift parity, or ship readiness. No app/profile change,
additional human participant, upload, release, or license clearance is implied.
