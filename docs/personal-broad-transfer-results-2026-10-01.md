# Broad-writer source-transfer result: reject for advancement

Completed 2026-10-01 under the unchanged
[frozen protocol](personal-broad-transfer-protocol-2026-10-01.md).
Local research only; no app/profile/recognizer changes or model distribution.

## Executed fit and reconciliation

The prepared NIST subset contains 31,744 distinct adapted rasters: 512 recorded
training writers per exact ASCII class, covering all 2,783 eligible training
writer IDs. The hash-based selection passed its minimum-count condition without
lowering the budget. No held-out NIST image was decoded. A source-only pre-fit
check found no adapted training-image duplicates or exact pixel copies of the
776 retained UJI development queries; no query truth was opened for that check.

Both actual models completed five pretraining and thirty target-training epochs,
2,200 optimizer updates each. Their initial tensors, pretraining label-position
plans/affine RNG traces, and final UJI batch plans/augmented inputs match. Both
complete 97-class heads were restored from identical original initial tensors
after pretraining. Pretraining and final checkpoints are retained. Root rebuilt
all 6,208 final UJI training embeddings per model from the saved checkpoints and
verified exact equality to the emitted bundles. No development inference
occurred during fitting; no reserved features were constructed.

Twenty-seven focused synthetic tests passed with zero failures/skips: 11 source
adapter, 11 model-fit, 5 evaluation. These verify implementation contracts,
including a real synthetic gradient step, not recognition accuracy or app QA.

## Frozen descriptive results

All 3,104 task/model attempts were serialized and validated before query truth
or the exclusion ledger was opened. These are eight previously observed public
development writers, 97 session-two queries each; they are not fresh-writer or
natural-chord evidence. All queries were readable; no invalid row was dropped.

Correct counts, raw denominator 776 per task:

| Task | Matched UJI generic | NIST generic | Matched UJI personal | NIST personal |
| --- | ---: | ---: | ---: | ---: |
| core10 | 618 | 625 | 616 | 626 |
| catalog21 | 618 | 625 | 619 | 627 |

Correct counts, pre-existing no-copy denominator 772:

| Task | Matched UJI generic | NIST generic | Matched UJI personal | NIST personal |
| --- | ---: | ---: | ---: | ---: |
| core10 | 614 | 621 | 612 | 622 |
| catalog21 | 614 | 621 | 615 | 623 |

Generic candidate/control changes are 29 gains, 22 harms, net +7 in each view.
Personal candidate/control changes are 33 gains/23 harms/net +10 for core10 and
32 gains/24 harms/net +8 for catalog21. The 35 classes absent from pretraining
have net +3 generic and personal against the control, so that extra guard passes.

However, personalization versus the candidate's own generic rankings has:

- core10: 2 gains, 1 harm; the harm is untaught.
- catalog21: 4 gains, 2 harms; both harms are untaught.

Candidate-personal/control-personal per-writer deltas also remain negative for
two writers in core10 and three in catalog21. In source writer order
W04, W06, W08, W11, UPV-W35, W43, W47, W56, the deltas are:
core10 `0, +2, +1, +1, -2, +2, +8, -2`;
catalog21 `-1, +1, 0, 0, -2, +2, +9, -1`.
Raw and no-copy deltas agree. Aggregate gains do not replace these failed guards.

The predeclared 21-app-codepoint slice has denominator 168: generic 147→151,
core personal 147→153 and catalog personal 150→155. These are descriptive
subsets, not a rescue for the failed full-vocabulary/per-writer trust screen.
Five musical glyph labels remain absent from UJI. Nothing here measures full
chord composition, glyph ownership, review flow, confidence calibration or
Pencil behavior through Swift/Core ML.

## Disposition and identities

`passesFixedFutilityScreen=false`; disposition
`reject-fixed-candidate-no-retuning`. The representation shows a modest
development gain, but the unchanged optional learner still damages untaught
symbols and results are not consistent across writers. Do not promote, retune
the frozen candidate on these same queries, or consume reserved writers to
justify a failed development screen. The stronger operational baseline is
unchanged. It was not recreated here, and no current paired comparison establishes
that this candidate is superior to it.

The experiment was not conditional on private handwriting or user answer
acceptance. It used public source training labels and predetermined public
setup examples, with query truth isolated until after prediction freeze.
NIST's commercial derived-weight status remains unresolved; the separate
dated local-research decision does not establish a shipping license.

Evidence is preserved outside Git in
`/Users/benirossman/.local/share/ichart/recognition-development/broad-transfer-20261001.XPsxbN`.

- Caller protocol: `29f5e52a85ced2fc2c0a208bf7899ca9d434dbe7d725adbbcb7892fe7c93aeca`.
- Fit receipt: `6eb9982bbc546f1f1ce2e7306c62dc1e5788cebc12713ac1ca2e7c7f2dc4f835`.
- Control weights: `b488ff6d24ac6b809565bab3709c09328ef55ca4e42769dfb137f18122a9fc6a`.
- Candidate weights: `ffeac656313996199aae0441fd44c020dbdf8fd12065f866641928251af72bbf`.
- Frozen predictions: `5b24b6622da0d915e0ffbdec8d8a16a76e2baa899695a1bcce1f438c59816235`.
- Score: `26a527b4b3018609f79698436fe28846782284ddbe56d4a26b7040e342a10ae1`.

The long-term recognition goal remains open. Further learner/representation
work needs a new general hypothesis and predeclared comparison; this failed
candidate is not a release or fresh-writing milestone.
