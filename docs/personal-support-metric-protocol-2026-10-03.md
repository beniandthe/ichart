# Bounded support metric experiment

This is one offline test of whether confirmed lessons can improve handwriting
comparison geometry without damaging untaught symbols. It is not an app change
or a promise of better recognition. Freeze this protocol before optimization;
do not adjust its recipe after inspecting candidate predictions or outcomes.
Base HEAD is `160aa31594903508e241802e21ca83ec447de849` in the existing dirty
recognition worktree. Preserve all previous experiments and user data.

## Hypothesis and limits

The residual learner changes every output column from sparse lessons. Previous
support-only mixtures could not repair untaught-versus-untaught rankings, while
centroid translation and joint matching did not pass their safety screens.
This candidate instead changes one shared positive-definite metric inside the
subspace spanned by class-relative lesson deviations. All classes still compete.
The encoder, its classifier, and training-domain class anchors remain frozen.
The hypothesis is that these deviations contain transferable writer style;
they can also contain class-specific variation or noise. That must be tested.

Task-conditioned metrics are an established research direction, for example
[TADAM](https://proceedings.neurips.cc/paper/2018/hash/66808e327dc79d135ba18e051673d906-Abstract.html).
The construction below is our bounded experiment, not a reproduction of that
paper, and its image-classification findings do not establish chord accuracy.
No model weights or additional dataset are acquired for this test.

## Fixed mathematical construction

Inputs are finite CPU float64 tensors: normalized 128-dimensional query and
confirmed-support embeddings, 97 normalized class anchors in the frozen
vocabulary order, support labels, and unchanged generic query logits.
Query labels, writer identities, source identities, and taught-status flags
never enter the forward interface. Detach all input tensors from gradients.

Deduplicate exact repeated support embeddings with the same label. Reject an
identical embedding assigned conflicting labels. A support residual is
`d_i = support_i - anchor[label_i]`. Let `w_i` give equal total mass to each
represented label and equal mass to its distinct lessons. Compute
`context = sum_i w_i d_i`, including exact zero residuals.

A shared network maps `[d_i, context]` through `Linear(256,32)`, GELU, and
`Linear(32,1)`. Set `alpha_i = tanh(output_i)`. The last layer starts at exact
zero; initialize the hidden layer using seed 43 without mutating global RNG.
For nonzero residuals let `u_i = d_i / norm(d_i)` and define
`Delta = 0.25 * sum_i w_i alpha_i u_i u_i^T`, `M = I + Delta`.
Exact zero residuals contribute zero while retaining their balance weights.

The update is symmetric and its spectral norm is at most 0.25, hence M has
eigenvalues in [0.75,1.25]. Its action is zero outside the residual span.
That last property does not mean every cosine score of an orthogonal query
is unchanged: anchor normalization can still change those scores.

For every class c return
`baseLogit_c + 10 * (cos_M(query, anchor_c) - cos_I(query, anchor_c))`.
Use the M inner product and M quadratic norms, rejecting nonfinite or
nonpositive forms. Empty support or entirely zero residuals return exact
generic logits. At zero-initialized update, identical cosine arithmetic must
produce exact generic logits without branching away the learning gradient.
No class mask, proposal-only winner, output alias, confidence threshold,
defer selector, or new acceptance rule is learned.

## Fixed training recipe

Use frozen fitA features and generic logits, and the retained A16-only anchor
bank. Meta-fit uses only the first B8 writer block in the existing role
manifest. The last B8 is a separate internal check, not fresh validation.
These groups are disjoint from the encoder's A16 fitting writers. Both B8
blocks have been used in earlier research; reuse must remain visible.

Support catalogs are fixed: core10 `A B C D E F G b - 7`, and catalog21 adds
`m o 6 9 2 4 5 1 3 ( )`. Use each writer's session 1 as lessons for session 2
queries, and vice versa. Each role has 8 writers x 2 directions x 2 catalogs
= 32 episodes. A missing catalog lesson fails setup; never substitute another
label. These isolated characters omit real sharp, plus, slash, half-diminished,
and triangle glyphs. Latin b and o and the dash are proxies, not musical data.

Run 30 epochs with all 32 meta-fit episodes each epoch, a seed-43 permutation
per epoch, exactly 960 updates, final checkpoint only. Use Adam, learning rate
0.001, weight decay zero, no scheduler, clipping, augmentation, or early stop.
Use deterministic CPU execution with four threads and the existing Python
3.12.14, NumPy 2.0.2, Torch 2.7.0 runtime.

Loss is mean full97 cross-entropy over eligible query rows, plus
`1.0 * mean KL(generic || candidate)` on untaught rows, plus
`0.1 * sum(Delta^2)`. Both taught and untaught strata must remain present.
This deliberately does not boost taught examples to half the loss. Query
answers are supplied only to the training loss from a meta-fit-only sidecar.
KL and the norm bound do not guarantee decision safety; the external failure
criteria below test that empirically. No wrong-writer query loss is fitted.

## Source and prediction separation

Authenticate the existing crossfit receipt
`d2a31e73d53b25b812f0ba4f24f812014515606f97a20e6b7170eaf94d0e20d2`,
features `b1bbb6066ef2bd1d5cc0398df2d9713fb60f6086ec501bb0687fce81976faaef`,
metadata `97653c8a59077588a886cdee2577f94084cf704f55435f320016720870642332`,
role manifest `47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa`,
fitA weights `1cfbcd2c11fe5173bbd7367121fdb9c4c1d965618d9272a6c7421dd6901261c1`,
and A16 centroid receipt
`c4c895caee391b6076018244b9b5a8a19230c8052a95776d0d7459a90dea9bad`.
Reuse their authenticated loaders without new encoder inference. Do not
instantiate reserved or private handwriting or mix fitB-generated embeddings.

Prepare plans, input hashes, code hashes and the complete update order before
optimization. The source planner may inspect labels to identify explicit
catalog lessons and establish complete source grids. It writes query labels
to a separate scoring sidecar; the predictor does not read it. Fitting reads
only meta-fit targets. Forward plans retain opaque query indices and explicitly
labeled support indices, not query answers. Source metadata used for the
planner is not evidence that this already-observed dataset became blind.

Choose an unrelated support donor among meta-fit writers excluding the query
writer. For each episode select the donor with the lowest SHA256 of canonical
ordered support source IDs, matching the same catalog and support session.
Pin this mapping before fitting. The wrong-writer arm applies the identical
fitted adapter with this support; do not change its strength or availability.

Retain all 97 scheduled queries per episode in the prediction packet. Before
fitting, declare copy reasons using raw/stored raster and normalized-trajectory
fingerprints: encoder fitting sources, the union of true/wrong support, and,
for internal-check queries, the complete meta-fit raw/stored source union.
Compare the actual raw query raster and normalized trajectory against both raw
and available stored reference forms; do not exclude a raw query solely because
an unused stored rendering of that query matches. This rule is source-only.
Use a common no-copy cohort for all arms; retain raw results as diagnostics.
Explicitly record unavailable support and every exclusion; never zip-truncate,
silently drop invalid rows, or filter on outcomes. Invalid predictions stop
advancement rather than disappearing from the denominator.

Freeze every full97 generic, matching-support and wrong-support logit row,
checkpoint digest, input plan and state digest before the separate scorer
joins internal-check labels. The predictor must not load decoded source
metadata or query-label sidecars. Verify deterministic replay, unchanged
encoder/anchor/input/model bytes, and exact checkpoint reload.

## Domain boundary and fixed failure criteria

Keep internal negative classes only as rejection evidence. The app-facing
view accepts a unique actual top glyph only when the existing chord-reader
domain allows it; otherwise the result is unresolved, with no lower-ranked
legal substitute. Glyph-domain admissibility is not standalone chord validity:
digits and quality letters still require the existing complete chord grammar.
This experiment changes neither boundary nor the installed readers.

Report both full97 glyph diagnostics and the existing domain-rejected view.
For each catalog, report raw and no-copy totals, taught/untaught strata,
writer/session results, corrections, lost correct readings, wrong/no-read
transitions, out-of-domain false accepts, and distinct/repeated source counts.
One isolated glyph is not one chord and repeated episodes are not new drawings.

Each of the two catalogs must satisfy every condition in both raw and no-copy
internal-check cohorts: positive correct-read gain over generic; strictly more
correct reads than the wrong-support arm; no negative writer net; zero untaught
lost-correct readings; zero generic-correct or generic-unresolved to wrong
transitions; zero new out-of-domain false accepts; complete finite evidence.
Apply these conditions to the domain-rejected view, while retaining all full97
diagnostics. Any failure rejects this exact candidate without retuning against
these results or consuming the sealed public-writer set to rescue it.
Also require matching support to beat wrong support separately in each session
direction for each catalog and cohort. Record source-identical lessons before
feature deduplication and reject conflicting explicit labels; do not count copied
lessons as additional evidence.

## Required verification and claim ceiling

Synthetic tests cover identity with learnable gradients, symmetry and spectral
bound, duplicates and conflicting labels, support/class permutation, finite
input rejection, no upstream gradients, complete-vocabulary changes, source
roles/copy denominators, answer-free prediction, hash tampering, real optimizer
updates, checkpoint reload, and scoring coverage. Test counts are engineering
evidence, not accuracy. Independently reconcile the source plan and score.

A pass permits only a separately frozen next evidence step. It does not
authorize app promotion. Fresh natural chords in both chart styles and
application-runtime parity remain necessary. No new people, device build,
profile teaching, chart changes, commit, push, or release are part of this pass.
