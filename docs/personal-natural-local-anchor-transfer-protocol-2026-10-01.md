# Natural local-anchor transfer — frozen comparison protocol

## Decision boundary

This is one comparison-only development experiment, frozen before fitting or
prediction. It does not train or replace the shared encoder, change the live
reader, select an acceptance threshold, or authorize rendering. The candidate
is the already measured local residual plus public untaught-shape constraints;
the sole learned control is the current linear anchored residual. Native v31
template/shape output remains unchanged and is context, not a selectable arm.

The method is writer-agnostic, but these natural captures are from one writer.
Passing cannot establish writer-independent accuracy, calibration, production
eligibility, or shipping readiness.

## Frozen model and personal-fit rules

Both arms use the unchanged operational raster encoder, its 128-dimensional
unit embedding, generic logits/vocabulary, rasterizer, and original weights
SHA-256 `5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`.
Bind the exact Core ML package, manifest, vocabulary, width artifact SHA-256
`33ed8df132011bbec26ceb419d7c0dc71aaaf6a257d0330461a260dd1348471e`,
and public anchor bank SHA-256
`e1670f855301f2fdb7970d2a4d23a30ffd82e76a242347867751b6c4c78a76ed`.
Bind `personal_local.py`, `personal_local_anchors.py`, `personal_anchors.py`,
the two Swift residual heads, learned comparison, visual encoder, rasterizer,
composer, packet, and scoring sources before fitting. Do not substitute the
dual-view, symbol-expansion, distilled, or adaptation-trained checkpoints.

- **Control:** the unchanged `PersonalInkAnchoredResidualHead` linear fit.
  Retain lambda `0.1`, per-label balance, one unit-weight zero-correction public
  mean anchor for every untaught generic class, and the existing treatment of
  explicit novel symbols.
- **Candidate:** `personal_local_anchors.fit_local_anchored` exactly. Use
  `k(x,y) = exp(-||x-y||² / 0.16684838059285878)`, lambda `0.1`, and the same
  public anchor bank. For lesson rows use weight
  `1/sqrt(number of examples with that label)`; untaught generic anchors have
  unit weight and zero residual. With points comprising lessons plus anchors,
  `D` the row weights, `K` the RBF matrix, and `R` the lesson residuals followed
  by zero anchor rows, solve `(D K D + 0.1 I) beta = D R`, retain
  `coefficients = D beta`, and rank
  `genericScores(query) + k(query, points) coefficients`.

No width, lambda, anchor weight, feature, class subset, score cutoff, seed,
answer-specific rule, or fallback may change after predictions. Both arms must
have the same vocabulary and complete competitor set.

## Frozen support and lineage limit

Use the exact 34-example profile frozen with these captures. Only its **16
explicit glyph examples** are support. The 18 whole-chord examples are excluded
from both fits and may not be aligned, decomposed, pseudo-labeled, or used as
anchors. Report `supportExampleCount = 16` and the actual distinct support-class
count and multiplicities after strict profile validation; never describe the
16 examples as sixteen labels or classes.

Bind the profile bytes and selected lesson IDs, labels, embeddings, generic
scores, feature hashes, and support projection before query inference. The
profile's acquisition/consent/writer/session lineage is untracked or incomplete;
report that status explicitly. It is development support, not training-eligible
or independent-writer evidence. No lesson is added, relabeled, removed, or
requested from the user.

## Frozen natural inputs

Read only canonical target packets from these retained roots:

- `/private/tmp/iChartAnchoredFreeze-20261001.1ZWFre/source-simple`
- `/private/tmp/iChartAnchoredFreeze-20261001.1ZWFre/source-rhythm`

Before model work, freeze the exact relative file list, bytes, byte counts, and
SHA-256 digests; verify them again on every exit path. Do not read source images
or query truth during preparation or prediction. The writer reported eight
written chords in each style, while observed live targeting retained nine
Simple target packets and eight Rhythm target packets. These facts must remain
separate: neither the reported count nor a desired count may select, merge,
split, reorder, or discard a packet. Retain all 17 observed attempts, including
invalid, unsupported, empty, unassigned, and no-read outcomes.

## Prediction freeze and ownership arms

Fit both heads completely before reading any query identity or chord truth.
Process query packets in an answer-independent order. For every arm and glyph,
freeze source indexes, exact embedding/base-score hashes, the complete ranking,
top-one token, fit identity, profile commitment, encoder identity, and all
source/code/runtime commitments. Run the unchanged fixed-first composer before
truth join; it may return a strict first chord or no-read. It may not choose a
lower candidate because it matches an answer, drop unconsumed ink, or force one
chord from a target.

1. **Observed-live automatic arm:** preserve each frozen live target boundary
   and use the unchanged automatic lossless glyph grouping. This is a
   development diagnostic only. It cannot determine advancement, even if its
   output agrees with later truth.
2. **Conditional source-owner arm:** may execute only after complete ownership
   and isolated-glyph identity receipts have been independently frozen against
   the original canonical packets. Reviewers must not see recognizer ranks,
   profile lessons, intended chords, or accepted app output. Supplied owners
   must cover each source index exactly once and preserve independently reviewed
   outer order. Missing or unresolved evidence remains visible and prevents a
   passing gate; it is never replaced by automatic ownership.

Prediction artifacts are immutable and written before a separate scoring
process opens identity receipts. Any mixed profile, encoder, code map, source
packet, or incomplete row set fails the execution rather than producing a
partial success.

## Scoring and fixed gate

Score advancement only on the conditional source-owner arm. Reconstruct every
ranking and fixed-first chord from frozen numerical outputs before joining
identity. A glyph is **taught** only when its independently reviewed identity is
present in the frozen explicit-support class set; all other resolved identities
are untaught. Keep raw-token equality separate from parser canonicalization.

Report, for both styles and combined: all attempts, ownership/identity resolved
and unresolved counts, supported and unsupported counts, glyph correct/no-read,
taught and untaught gains/harms, strict complete-chord exact/no-read, paired
chord gains/harms, automatic-versus-conditional ownership, and every row. A
control-correct to candidate-wrong or candidate-no-read transition is a harm.
A strict chord gain requires the candidate's fixed first complete chord to equal
the independently reviewed ordered token chord when the control does not.

The candidate may advance only to a later comparison-path implementation when
all three conditions hold on the complete conditional denominator:

1. zero untaught glyph harms versus the linear anchored control;
2. zero strict complete-chord harms versus that control; and
3. at least one strict complete-chord gain versus that control.

If evidence is incomplete, the gate is not passed. If any condition fails,
retain the result and do not promote this fixed candidate. Do not claim that one
failed candidate retires all RBF/personalization methods, and do not rescue it
with another width, threshold, selected subset, repeated writing, or new lesson.

## Planned parity gate and limits

Before a natural result can support app comparison, implement the exact
candidate in a separate Swift comparison path. On identical frozen lessons,
anchors, embeddings, generic scores, and queries, Python and Swift must match
the complete vocabulary/rank order and first choice for every row, with maximum
absolute score error `<= 1e-4`. Independently verify the weighted normal
equations, duplicate-label balance, lesson/anchor order invariance, empty/full
limits, explicit novel labels, input immutability, and stale/disabled-profile
failure. Preserve source, profile, model, anchor, code, protocol, prediction,
score, and parity hashes before and after execution.

This protocol-writing step performs no profile fit, model inference, truth
read, ownership review, Swift implementation, build, install, or release.
