# Joint lesson matching experiment protocol

Declared before real fitting or prediction on 2026-10-03. This experiment tests
whether a jointly trained visual encoder can recognize a match to explicit
handwriting lessons and otherwise defer to its own generic result. It is
research only. It does not change the live reader, chart ink, user profile,
installed app, or previously rejected experiments.

## Reason for this experiment

The fixed class-frozen residual experiment failed its predeclared safety gates.
Preserving untouched score columns did not preserve untouched rankings. Earlier
uniform mixture and frozen-feature gate experiments also introduced untaught
errors. These results do not establish that every possible personalization
method fails; they rule out those particular recipes for app integration.

This successor trains the encoder and lesson applicability together rather
than refitting residual score columns. Using class prototypes in a learned
representation is motivated by
[Prototypical Networks for Few-shot Learning](https://arxiv.org/abs/1703.05175).
The match-or-defer architecture and safety rules below are experimental choices
for iChart, not accuracy guarantees from that paper.

## Fixed source boundary

Use only the existing UJI public research source and its already recorded
32-writer crossfit metadata. Do not use private chart queries or profiles,
the eight development writers, or the 20 reserved writers. Their names and
source headers may be checked for role separation. The complete source bytes
may be hashed, but a training32-filtered parser must skip numerical coordinate,
stroke, and sample construction for all 28 excluded writers. Loading every
writer's geometry and filtering afterward is not permitted.

The parent metadata contains 6,208 distinct source IDs: 32 recorded writer IDs,
two sessions, and 97 literal corpus labels. Preserve its exact hash-ranked
A16 and B16 folds. Each model fits one fold and is evaluated on the other;
recorded writer IDs are separated for each fit, not certified human identities.
These are reused public research sources, not a fresh blind test. Labels have
been available in earlier research and are used to train the opposite fold.

The parent directory is
`/Users/benirossman/.local/share/ichart/recognition-development/support-retrieval-20261001.WmWgZ3/crossfit`.

| Binding | SHA-256 |
| --- | --- |
| Official UJI source | cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61 |
| Parent fit receipt | d2a31e73d53b25b812f0ba4f24f812014515606f97a20e6b7170eaf94d0e20d2 |
| Parent fit plan | 75adca9c1b19b0b4b54328ffb010d8fccedaf085cf43496e0f2d20269bc9be3e |
| Parent metadata | 97653c8a59077588a886cdee2577f94084cf704f55435f320016720870642332 |
| Swift-exported chord domain | 5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010 |

Do not initialize from the parent fitted models or train on their cached
embeddings. New fitting must encode the source rasters with the candidate and
control models. A source-only schedule is not proof that those rasters have
been prepared or that a model has been trained.

Support uses the existing application lesson-storage geometry adapter without
changing its bounds, endpoint retention, or decimation. Query glyphs use the
raw application raster adapter. Bind actual raw and stored trajectory/raster
hashes to every source. Missing stored shapes remain explicitly unavailable;
never replace them with raw or zero images. Reject duplicate payloads within a
support profile rather than counting alternate IDs as independent lessons.

Test both fixed public intersections of the actual setup catalogs:

- `core10`: `A B C D E F G b - 7`.
- `catalog21`: the core plus `m o 6 9 2 4 5 1 3 ( )`.

These are intersections, not the complete app catalogs. This source lacks
`#`, `+`, `/`, `ø`, and `△`. Literal `b`, `o`, and `-` are proxies, not evidence
of real flat, diminished, or musical minus glyph accuracy. All requested and
actually available lesson counts must be reported separately.

## Fixed model and routing

Retain the existing 97-output `PersonalVisualEncoder`: raster input
`[N,1,96,256]`, generic logits `[N,97]`, and normalized features `[N,128]`.
Mean-pool distinct confirmed examples for each exact support label in stable
source-ID order, then normalize each prototype. Pooling stays differentiable.

A shared `512 -> 64 -> 1` GELU relation network scores each query/prototype
pair using query, prototype, absolute difference, and elementwise product.
A query-only `128 -> 64 -> 1` GELU network supplies one DEFER score. Compare
the available support scores with DEFER. Learned layers receive only numerical
tensors, never writer IDs, literal support labels, query labels, or source IDs.
Confirmed support labels are external sidecars for pooling and interpreting
an index; query truth is separate loss/scoring data.

Only a unique support score strictly above every other support score and DEFER
may name its explicitly confirmed label. Any tie or DEFER winner preserves
this candidate's own generic logits exactly. Empty support skips the matcher
and uses that same fallback. Revalidate the allowed-label sidecar when routing.
The fallback is not the control or production reader: joint training may have
changed the candidate generic model, which must be checked separately.

Generic prediction uses its actual raw 97-way winner. If that winner is outside
the Swift-exported domain, the reader result is unresolved. Do not promote an
allowed runner-up or normalize forbidden characters into a chord. The 97 corpus
classes remain internal supervision for recognizing and rejecting irrelevant
ink; unsupported literal outputs are never reader suggestions. An allowed
glyph fragment is not a complete grammatical chord.

There is no residual correction, mixture coefficient, selected threshold,
chord-specific rule, user-specific answer exception, or query-label lookup.
False support matches can still harm correct generic results; a synthetic
counterexample must be retained alongside fallback tests.

## Matched training schedule

For each fold, use two arms: `genericCEControl` and `jointMatchDefer`. Create
one complete initial model state from seed 29 and deep-copy it into both arms
and both folds. Verify the entire initial state is identical, including encoder,
classifier, relation network, DEFER network, and buffers. The control's matcher
is unused. For every update, both arms encode
the same single concatenated support-then-query batch with the same order,
augmentation draws, and batch-normalization exposure. Separate support/query
encoder calls are not an acceptable matched control. Apply augmentation to
one concatenated support-then-query tensor before splitting; verify identical
transformed bytes and order for both arms. Batch-normalization running states
may diverge as the models learn, but their batch sizes and input exposure must
match at every update.

Each epoch schedules every training writer, both query-session directions,
and both catalogs once: 16 x 2 x 2 = 64 episodes. Each episode contains all
97 raw query glyphs from the query session and available stored support from
the opposite session. The fixed schedule is 30 epochs, 1,920 optimizer updates
per arm per fold. This is different from the old 750-update crossfit recipe;
the new candidate and control share the new schedule exactly.

Order episodes by SHA-256 of
`personal-support-match-defer-v1:epoch:` followed by the epoch and episode ID,
using the same order for both arms. Use AdamW, learning rate 0.001, weight decay
0.0001, and update-level cosine annealing with `T_max=1920`. Restart the same
Torch augmentation generator at seed 29 for each arm. Retain the existing
label-blind affine augmentation: rotation within 8 degrees, scale 0.9 to 1.1,
and horizontal/vertical translations within 0.03/0.05. Use deterministic CPU
execution with four threads. Retain final epoch only; do not select a checkpoint
using held-out scores.

Both arms minimize query generic cross-entropy. The candidate additionally
minimizes match-or-defer cross-entropy, giving taught and untaught query cohorts
equal one-half weight. Derive both target arrays from one training-only label
sequence and vocabulary. A requested lesson with unavailable stored geometry
is not taught to the matcher. Retain a separate unavailable-request cohort.

Before fitting, test single-call encoding, support permutation equivariance,
truth exclusion from numerical forward, strict ties, source identity checks,
exact generic fallback, and gradients from matcher loss to both retained
support/query embeddings and encoder parameters. A support raster gradient
from batch-normalization coupling alone does not prove that the matcher learns
from support. Reject unusable training profiles or empty loss cohorts instead
of silently changing the schedule.

## Frozen evaluation and controls

Evaluate both held-out folds in both session directions and both catalogs.
Retain all 97 queries per episode and report unique sources separately from
catalog/support exposures. Do not count repeated queries as independent data.
Use true writer support and a wrong-writer control whose donor is the next
writer cyclically in the frozen held-out fold order. Freeze donors before
geometry or scoring; do not search for a favorable donor. The true and wrong
profiles must have the same actual available-label set for the strict writer
comparison. Preserve both availability vectors. Any mismatch is recorded as
evidence unavailable and fails the comparison gate, rather than choosing another
donor or attributing extra label coverage to writer style.

Bind protocol, code, source schedule, model weights, runtime, support bytes,
and query vectors before prediction. Prediction must not open evaluation
targets, scoring truth, or outcome-based exclusions. Freeze raw logits,
match/defer scores, route, and domain-projected output before a separate scorer
joins labels. Preserve raw and no-copy results. The no-copy ledger includes
raw/stored raster and trajectory matches to actual fit inputs and both true
and wrong support sources, using one paired denominator. Keep every source and
reason in the raw view. Missing eligible taught/untaught cohorts are an explicit
evidence limitation, never an excuse to omit an episode.

Report generic-control changes separately from personalization changes. For
each catalog and writer, report taught, untaught, unavailable-request, supported
domain, and out-of-domain outcomes; gains, harms, wrong reads, and unresolved
reads. Raw out-of-domain class names are forensic research data, not candidate
chord suggestions. Literal corpus-label equality is not a complete-chord or
musical-alias accuracy score.

## Stop rules fixed before fitting

Every rule must hold in both folds, both catalogs, and raw/no-copy views:

- Candidate generic domain correctness is no worse than the matched generic
  control, with no new domain outputs on rejected out-of-domain inputs.
- Neither the candidate generic branch versus its matched control nor
  personalization versus its own generic branch may introduce a wrong
  non-null domain result on a domain query that was previously correct or
  unresolved. Turning a no-read into a wrong read is not a safety improvement.
- Personalization gives strictly positive domain net correction over the
  candidate's own generic result.
- There are zero personalization harms on untaught supported-domain glyphs.
- No writer has negative personalized-versus-own-generic domain net correction.
- True-writer support has strictly more routed domain-correct glyphs than the
  fixed wrong-writer support control on the same paired rows, for each fold and
  catalog. Mismatched available-label sets cannot satisfy this gate.
- Personalization introduces no domain output on an out-of-domain query where
  its own generic result was unresolved.
- Missing support, duplicate payloads, nonfinite values, source mismatches,
  incomplete cohorts, or nondeterministic replay cannot be hidden or repaired
  by outcome-dependent selection.

A failure rejects this fixed recipe for app integration. Preserve the failed
result; do not retune the architecture, optimizer, catalogs, donors, sampler,
domain, or stop rules against it. Passing would permit a separate Swift/Core ML
runtime comparison, not promotion. Runtime parity and genuinely fresh reviewed
writing in both chart styles remain required before any app recognition or
ship-readiness claim. No additional person needs to be recruited for this work.
