# Fixed m/9 lesson-transfer check: failed

## Decision

The predeclared original-residual 37→39 criterion fails. Simple loses one
previously correct chord with no correction; Rhythm gains one but loses one.
Both regressions are complete `D/F#` reads becoming no-reads. Adding these two
explicit setup lessons did not demonstrate safe local transfer. This ends the
fixed intervention; do not vary prompts, refit to queries, select another head
or ask for repeats until a favorable result appears.

The experimental reader also remains substantially behind the captured standard
reader. It stays comparison-only. This rejects this intervention/reader outcome,
not every possible ML personalization architecture. General handwriting trust,
live ML behavior and shipping readiness remain unproven.

Authoritative checkout: `recognition-generalization-reset`, branch
`codex/recognition-generalization-reset`, HEAD
`160aa31594903508e241802e21ca83ec447de849`, existing dirty worktree preserved.
Sources came from the paired physical iPad with installed metadata 1.2.1 build
55. Prediction recording used the separately pinned Swift/Core ML Simulator
runtime; installed executable/model bytes and live physical ML were not verified.

## Exact fixed outcomes

Cells are correct / wrong non-null / no-read counts on six user-labeled captured
targets per style. These are not across-writer or calibrated accuracy percentages.

| Method | Simple | Rhythm |
| --- | ---: | ---: |
| Captured standard baseline | 5 / 0 / 1 | 4 / 0 / 2 |
| Captured standard profile 39 | 5 / 0 / 1 | 4 / 0 / 2 |
| Shared ML | 1 / 0 / 5 | 1 / 0 / 5 |
| Original residual, profile 37 | 2 / 1 / 3 | 2 / 1 / 3 |
| Original residual, profile 39 | 1 / 1 / 4 | 2 / 1 / 3 |
| Linear anchored, profile 37 | 1 / 0 / 5 | 1 / 0 / 5 |
| Linear anchored, profile 39 | 1 / 1 / 4 | 1 / 1 / 4 |

Primary Simple: zero corrections, one correct→no-read regression, zero
no-read→wrong changes; net −1. Primary Rhythm: one `G9` no-read→correct
correction, one `D/F#` correct→no-read regression, zero no-read→wrong changes;
net zero. Combined: one correction, two regressions, net −1. The two styles
share six chord identities reordered, not twelve independent identities.

Other primary changes remain wrong→wrong: Simple intended `E-9` moves `G#`→`G9`;
Rhythm intended `E-9` moves `E#`→`E9`. These are not corrections. Secondary
anchored outputs introduce one no-read→wrong harm per style; they cannot rescue
the failed primary. Captured standard/profile readings are unchanged and yield
nine correct targets, zero wrong non-null reads and three no-reads in total.

All twelve targets are eligible. Each style reports six complete written chords,
six captures, zero grouping flags, known-ink or missing-original-input exclusions,
missing/extra attempts, unassigned fragments or barline fragments. The fixed task
postflight passes with no label/order/count deviations. Structural coverage and
user grouping flags do not independently establish semantic glyph ownership.

Both experience forms report no slow ink or unexpected chart changes. These are
user reports, not instrumented latency or stability measurements.

## Annotation and scoring integrity

The completed journal preserves all 22 run IDs/order and all historical 20 runs.
Exactly 22 paths change, all whitelisted: twelve intended labels and two sets of
status/finish/count/two experience fields. Every original ink/source snapshot,
record identity/order, native reading, frozen profile/lineage and teaching field
is unchanged. No query was taught. The current profile remains byte-identical
to the pre-writing 39-example candidate; original 37 examples remain intact.

The unchanged fixed scorer joined the seven byte-bound artifacts without
inference, fitting, label rescue, parser changes or profile writes. An independent
read-only calculation reconciled eligible rows, primary/standard counts, all
primary corrections/regressions and the failed fixed rule. The 103 current/frozen
source commitments and complete five-file runtime map still match. This is
committed-path integrity, not literal whole-repository immutability.

The previous one-test actual recorder and five-test composition gates passed
with zero failures/skips, verified from xcresult summaries and test trees. The
preparation's 30 synthetic v2 scoring tests remain engineering evidence only.
No new physical app build/install, render, query teaching, commit, push or
production change occurred while recording/scoring this result.

## Next boundary

Two read-only audits locate the regressions at the final automatic group's
personal residual rank, before composition. Both targets retain the same four
groups covering ten strokes: `[[0,1],[2],[3,4,5],[6,7,8,9]]`. Earlier first choices
remain `D`, `/`, `F`; source packet, grouping, shared ranks, encoder/runtime/code
identity are equal across support arms.

- Simple last group: `#` score 0.649580→0.559753, while `ñ` changes only
  0.629991→0.630274. The top-choice stream becomes `D/Fñ`.
- Rhythm last group: `#` score 0.612363→0.542143, while `F` changes only
  0.573138→0.573370. The top-choice stream becomes `D/FF`.

These are uncalibrated ranking scores, not probabilities. Complete composition
correctly returns no-read. The damage is not `m` or `9` overtaking `#`; the old
class's correction is weakened by the refit. Shared/anchored hypotheses are
already invalid on both targets, and the original reference had overcome those
shared errors. Their continued weakness also remains part of the model boundary.

`PersonalInkResidualHead` uses one Gram matrix over every glyph lesson and fits
every output column. Each nonmatching lesson contributes `0 - baseScore[class]`.
Adding examples therefore changes corrections for all classes, not just their
labels. This supports collateral interference as the observed mechanism; it does
not independently attribute the cause to `m`, `9` or their joint interaction.
No post-result ablation was run. The new labels were already in the encoder's
97-class vocabulary, so novel-label padding is not this explanation.

A bounded successor hypothesis is an append-only update that freezes all
pre-existing class columns except labels explicitly updated by the new lessons.
That would prevent this particular old-column suppression, but competing newly
updated columns could still introduce wrong reads. It is not a proven cure.
Before app integration, specify a writer-separated public development comparison
with frozen reference, unchanged encoder/grouping/parser, exact untouched-score
invariance, explicit added-label gain and untaught/writer-level harm gates. Do
not switch catalog/threshold after scores or claim natural-chord quality from it.

Any successor must be a separately specified general learning mechanism, not
threshold/answer patches on these queries. Preserve these now-labeled runs as
development evidence, not future fresh evaluation; keep the standard reader and
exact ink protected. No further handwriting is required solely to finish this
rejected intervention.

## Evidence commitments

Private annotation, unchanged current profile, exact request, task postflight,
request-preparation recipe and score remain outside Git at
`/Users/benirossman/.local/share/ichart/recognition-development/glyph-coverage-score-20261003.IJWx1U`.
The source/rank/composition checkpoint is recorded in the
[query-freeze handoff](personal-append-only-glyph-query-freeze-2026-10-03.md).
The [fixed protocol](personal-append-only-glyph-coverage-protocol-2026-10-02.md)
and mapped code/model bytes are not rewritten by this report.

- Completed journal SHA256: `416bfd37255ba63116acac1fcffd64aa32d2716bc5344aa308ba8926cf48fc22`.
- Current candidate profile SHA256: `7f201d3266b2592cd82b199ac8b8dac6e7d82b655a9319ea184b02cc246a2173`.
- Score request SHA256: `edf27d3c738393a815c1cd20e661e0d3edc55aab3f5b3955ec0ec3e06a58ff15`.
- Score SHA256: `7af8bc47315e59f35124f48c3704a63b6001d225f744fb8f488d58ded7f1a548`.
- Scorer SHA256: `186f6d960432e0403d118c539d6356eae2a5b381b8f25145180462aaf0ea1bb4`.
