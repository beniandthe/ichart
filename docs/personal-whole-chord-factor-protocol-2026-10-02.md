# Fixed whole-chord factor bridge — research protocol

## Question and boundary

The synchronized isolated-glyph candidate remains rejected. This is a different
general mechanism: encode a complete chord once and train the existing ten-head
`DualViewChordModel` to predict its compositional factors, without proposing an
internal glyph partition. Do not add CTC, modify a live recognizer, or change the
optional personal head in this pass. The existing source-ownership loss is the
rationale, not the new private answers or a selected development-writer miss.

This workload is explicitly **synthetic chord layout made from real isolated
public handwriting**. It is not natural chord writing, fresh-writer accuracy,
trust calibration, a user-personalized head, or a shipping candidate. It can
falsify the usefulness of the existing whole-input factor path before acquiring
and adjudicating natural multiwriter chord sequences. A better synthetic result
does not establish that the current app's recognition issues are fixed.

## Fixed source and workload

Use unchanged UJI Pen Characters v2 SHA-256
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`,
with the existing source-only 32-fit / eight-observed-development / 20-reserved
writer split. The [official source](https://archive.ics.uci.edu/dataset/177/uji%2Bpen%2Bcharacters%2Bversion%2B2)
contains ordered coordinates, not timing. Parsing completeness is allowed;
no reserved writer may reach composition, normalization, encoding or inference.
No private chart/query/profile example is used, even as a selection target.

For each allowed writer and each of two sessions, construct the full Cartesian
grid of A–G natural/flat roots and these twelve canonical descriptors:
`empty`, `6`, `7`, `9`, `11`, `13`, `-`, `-6`, `-7`, `-9`, `-11`, `-13`.
This is 14 pitches × 12 descriptors = 168 strings. Labels must pass the existing
strict canonical parser and factorizer, not a handwritten alias map.
Use each literal character's original atom from that same writer/session.
Repeated `1` in `11` reuses one observed glyph; it is not another human sample.

Root maximal dimension is 32; every other atom is 16. Uniform normalization and
affine translation use the existing geometry primitives, baseline bottom 32,
positive inter-atom gap 8. Retain all original points, stroke boundaries and
within-atom acquisition order, with no supplied/fabricated timing. Each chord
gets two input-order variants: spatial-forward owner blocks and reversed owner
blocks at identical spatial positions. Reversed order is synthetic acquisition
stress, not evidence of natural delayed writing. Both variants enter training;
development forward is primary and reversed is a separately reported stress
arm. They share physical atoms and must not count as independent examples.

Expected training: 32 × 168 × 2 sessions × 2 orders = **21,504 derived targets**.
Expected development: eight × 168 × 2 × 2 = **5,376**, with **2,688 per order**.
The actual human source count and reuse multiplicities must remain disclosed.
Only fourteen distinct source characters feed this grid: 896 observed fit atoms
and 224 development atoms, reused extensively. Ordinary lowercase `b` is a
synthetic flat-role proxy here, not verified musician-written flat notation.
The fixed root/suffix size and gap provide an artificial layout/role cue.
All source/role plans are published before fitting. Feature overflow or malformed
input is a retained failure, never a shortened/omitted success. Refuse training
if expected coverage cannot be encoded without dropping input.

Every target binds original atom IDs, exact source geometry, affine transforms,
transformed source indexes, complete owner membership, source/derived hashes,
stroke/point counts and the minimum required trajectory samples. Root and
suffix points cannot disappear into a preprocessing shortcut. The existing
whole-target feature encoder may arc-length resample only within its declared
contract; original points remain in provenance and rasterization. A label-free
prediction projection contains opaque IDs and complete input, not canonical
truth, writer names, source-label IDs or a desired glyph count.

This grid covers plain/minor qualities, natural/flat roots and six extensions.
It does not cover explicit-major, diminished, augmented, suspended, altered,
half-diminished, repeats, slash bass, `#`, `+`, `/`, `ø`, `△`, natural symbol or
real coarticulation/spacing. Literal `o` is not silently mapped to diminished.
The absent families remain requirements of the full goal, not removed functions.

## Fit and output

Use unchanged `DualViewChordModel` default configuration, feature schema and
ten-head output contract. Seed 29, deterministic CPU four threads, batch 128,
AdamW learning rate 0.001 and weight decay 0.0001, cosine decay to zero across
exactly 30 epochs; final checkpoint only. No early stopping, search, new
augmentation, private correction, source-role change or outcome-driven retuning.
The only training order variation is the two explicit synthetic source variants.

Apply categorical cross-entropy and Bernoulli alteration loss on the existing
active conditional factor targets. Do not train validity or kind: every source
is declared valid/rooted, so there is no no-read/invalid/repeat evidence. Inactive
slash-bass placeholders must not be supervised. Loss is the equal mean over
globally supervised conditional heads, using actual active masks. Constant
absent slash/alteration labels are limited family supervision, not calibration
on unsupported handwriting. Preserve and freeze all ten raw output vectors.

Identity ranking is explicitly **conditional on valid rooted notation**:
exclude the repeat kind branch from the existing decoder, keeping the declared
raw factor distributions and grammar. This conditioning must be independent
of query truth, documented and tested; it is not a trusted recognition action.
No score/validity threshold or no-read acceptance is fitted or assessed here.
Synthetic timing stays unavailable/zero: a model that sees time channels has
not learned behavior on real nonzero timing in this study.

## Fixed atomic control and scoring

Use the pinned operational 97-class Core ML visual encoder and vocabulary, with
manifest SHA-256 `d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1`.
Validate its declared package/weight identity and CPU-only runtime before use.
Do not reconstruct absent Torch weights, retrain the control or use the newly
rejected synchronized dual checkpoint.

The control is supplied **exact source-owner glyph groups in spatial order**.
Encode each original transformed owner through the unchanged app-compatible
rasterizer; retain full 97 logits and first-argmax tokens. Compose the complete
raw string through the strict canonical parser; invalid remains null. No case,
`m`/`o`, enharmonic, expected-label or lower-rank rescue. This is a disclosed
raw-greedy oracle-owner control, not the richer Swift canonical-probability
search or the live automatic route. Whole-factor grammar versus atomic-greedy
and different training supervision are confounds: a gain cannot be attributed
solely to removing grouping. Raster-hash caching is permitted only with every
owner/member retained; cached repetitions are not independent input samples.

Fit, whole-input prediction, atomic prediction and scoring are separate
append-only processes. Bind source/protocol/code/checkpoint/runtime/input
hashes; freeze every full output before the separate truth join. No target may
be removed for an unread/incorrect answer or feature failure.

Primary endpoint: exact canonical first choice on all 2,688 forward targets,
paired whole versus fixed atomic. Report corrections, regressions, null outputs,
input failures, all eight writer counts and component/label-family errors.
Reversed stress reports the same quantities on its own 2,688; do not pool them
as independent trials. Raw denominators precede input-copy diagnostics.

The bridge merits a subsequent natural-source experiment only if there are
zero input drops, positive primary net, no primary writer net below zero, and
no reversed-stress writer net below zero against the same fixed control. These
are a falsification screen, not a calibrated statistical accuracy claim or
shipping permission. No outcome-driven threshold relaxation or reserved-writer
evaluation rescues failure. Personalization benefit is **not tested** by this
factor path; its lack of the pinned 128-vector glyph interface is explicit.
A failure rejects this fixed synthetic factor recipe, not all whole-input
recognition or the idea of optional personalized ML.

## Engineering gate and remaining goal

Before actual fitting: execute nonzero source-provenance/role/projection,
whole-feature coverage, active-loss, trained-state/checkpoint, raw prediction,
conditional-decoder and atomic-control synthetic tests. Preserve exact executed
code; independently audit contracts and scoring. Record actual fit history and
changed parameters. A successful training process alone is not a recognition
result. No iOS build is warranted for a research-only Python implementation.

The original goal still requires natural full chords in both chart styles,
independent writers, optional reviewed learning benefit without regressions,
full symbol coverage, application feature/runtime parity, Pencil responsiveness,
ink preservation and real-device acceptance. No app/profile/device writes,
automatic acceptance, commit, push, deployment or production use in this pass.
