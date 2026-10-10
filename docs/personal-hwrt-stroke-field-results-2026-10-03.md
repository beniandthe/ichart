# Matched musical symbol stroke field results

The fixed experiment completed on October 3, 2026 and failed its advancement
screen. Additional stroke information improved the newly covered musical
shapes, but did not establish a safe general replacement for the matched image
control. Both models remain offline. No app model, chart, profile, device
installation, or production service changed in this pass.

This is public isolated-glyph development evidence, not fresh natural chords,
personalization benefit, or shipping readiness. An independent standard-library
verifier reproduced every raw and no-copy summary and every fixed gate from
the frozen logits and truth without importing the experiment scorer or running
either model again.

## Fixed comparison

Followed the [predeclared protocol](personal-hwrt-stroke-field-protocol-2026-10-03.md)
without changing labels, thresholds, seeds, checkpoints, or scoring after
seeing predictions. The original HWRT strokes and existing UJI source fed
the same app rasterizer. One model used the image plane; the other also used
local stroke direction and endpoints. Both had the same 102-way architecture,
initial weights, examples, batch order, and affine augmentation stream.

Training used 6,208 UJI drawings from 32 training writers and 3,865 original
HWRT drawings. Both final models completed 30 epochs, 1,530 updates, and
195,840 exposures. Every training record was scheduled at least once;
repeated exposures were not counted as independent examples. Matching actual
forward-input stream hashes were recorded for both arms.

Only after completed-fit verification were 1,552 drawings from the eight
previously observed UJI development writers and 435 native HWRT test drawings
encoded. All 1,987 predictions were saved before the scorer opened truth.
There were no dropped rows or failed outputs. Reserved UJI writers, private
ink, saved setup examples, and chart-test answers were not encoded or scored.

## Results

Corrections and regressions compare literal first argmax predictions on the
same drawings. These are glyph counts, not full-chord success rates.

| Development cohort | Drawings | Image control correct | Stroke field correct | Corrections | Regressions |
| --- | ---: | ---: | ---: | ---: | ---: |
| All UJI labels | 1,552 | 1,237 | 1,254 | 73 | 56 |
| UJI chord-fragment labels | 656 | 549 | 557 | 31 | 23 |
| Five mapped HWRT shapes | 435 | 405 | 419 | 14 | 0 |

The sources are not pooled. HWRT writer identifiers are unreliable, and the
five new labels are confounded with their source. Its result is sample-level
evidence only. The plus-sign cohort contains just nine development drawings.

| Mapped shape | Drawings | Image control correct | Stroke field correct |
| --- | ---: | ---: | ---: |
| Sharp | 131 | 130 | 130 |
| Plus | 9 | 9 | 9 |
| Slash | 54 | 34 | 42 |
| Half-diminished shape | 97 | 91 | 95 |
| Major triangle shape | 144 | 141 | 143 |

Seven UJI drawings were excluded by the input-copy union; no HWRT drawing was
excluded. The no-copy UJI totals were 1,230 versus 1,247 correct out of 1,545.
Paired corrections, regressions, writer net changes, and the failed gates
were unchanged. Both raw and no-copy results are retained.

## Why the candidate does not advance

Three predeclared gates failed in both analyses:

- One writer lost six correct readings, exceeding the allowed loss of two.
  Writer net changes were +3, 0, +3, +3, +4, -6, +6, and +4 in the fixed
  order W04, W06, W08, W11, W35, W43, W47, W56.
- The exact two-sided writer sign-flip probability was 44/256 = 0.171875,
  not below 0.05. The aggregate gain does not establish consistent benefit
  across these eight reused development writers.
- Among 896 non-domain UJI drawings, 16 control no-reads became permitted
  fragment guesses. Total permitted guesses decreased from 74 to 66, but
  that does not satisfy the separate zero-new-error requirement.

A descriptive post-score check found that all 16 new permitted guesses were
existing-domain labels, not the five added shapes, and occurred across seven
writers. This does not justify a writer exception, alias-only model routing,
or a tuned rejection threshold. These are isolated-glyph projection errors,
not observed wrong complete chords. Forbidden raw winners remained no-reads;
the evaluator never substituted a lower-ranked legal candidate.

All other frozen gates passed, including complete finite outputs, net gains
on the old chord-fragment subset, all five new classes non-worse, and seven
of eight writers non-worse. Those successes do not override the three failures.

## Execution and verification

Root executed 41 warning-clean synthetic tests: 26 for the new data, training,
and evaluation code; eight existing stroke-field tests; seven source-intake
tests. There were zero failures or skips. Source-only independent review found
no blocking issue before the real run. A separate standard-library verifier
reconciled planned sampling, source identities, writer membership, full UJI
coverage, native label mappings, and repetition counts. That check proves the
plan, not the completed optimizer steps. The final independent check also
reconciled all eight native aliases, all five mapped classes, every joined
scored row, rebuilt input-copy reasons, artifact bytes, current and executed
code, final checkpoint hashes, and the completed fit's saved 30-epoch,
1,530-update, 195,840-exposure ledgers. No discrepancy was found. This is an
independent arithmetic and artifact check, not a second model execution.

The first development-preparation command stopped before source/feature work
because its CLI had not initialized Torch's frozen CPU runtime. The retained
launcher sets four CPU threads and deterministic algorithms, then calls the
unchanged data module. This satisfies the existing runtime guard; no source,
protocol, checkpoint, seed, or score changed, and there was no refit. Both the
failed log and successful invocation wrapper are retained.

The training receipt was saved at 16:38:12 PDT, the completed fit at 16:48:28,
the development receipt at 16:50:24, predictions at 16:50:42, and the score at
16:50:57. These filesystem times supplement the enforced execution order;
they are not the sole evidence for it.

## Evidence and next boundary

Preserved local evidence directory:
/Users/benirossman/.local/share/ichart/recognition-development/hwrt-stroke-field-20261003.8ZTPn0

The archived execution artifacts were compared byte for byte with the run
directory. The final independent script and report were subsequently copied
and checked against their recorded SHA256 identities.

Original execution directory:
/private/tmp/iChartHWRTStrokeField-20261003.ujud19

| Artifact | SHA256 |
| --- | --- |
| Frozen protocol | 3cda2bcb7c64a79c3ef4371a8ef01fb1df0e0e75512a7f2f49f39cdc58ff9d13 |
| Training receipt | 5e00aa3ce986a07b7a3d4547ebc80b42307cf37a85f9f2e82870b6508b6957e5 |
| Completed fit receipt | 1ca3d5d29dd292312a386d27c2e0b4a169ac9d1d1fa1bd56acb54685e07216a0 |
| Development receipt | e1f49705e3bfa249287d13ef011457b057763da17b228e3b4802d13a9150bf3f |
| Frozen predictions | ee3aab3135b609117c9556ffbd119bb26424bffb43b277db7f81116d82c303f0 |
| Score | 13cddbf669ced84f13ffd68f947149dc38519bfecae2d88196f2b00eb3fff836 |
| Runtime launcher | 8721cf6c88093ee09dd609d437433f6857cd4b67f4d7ee14b4c84330fe37f559 |
| Independent reconciliation | c792d9fe6cd5bd7a70adcabbf96299bded6600139f1f1d52d46f421c0a907c1c |
| Independent verification script | 7097894b4e05bb8f9736f9a5d67f90cb88beb2b6dabf2caa113777525f7f9a3d |

Do not rerun this recipe to select a favorable seed or checkpoint. The next
permitted work is general failure diagnosis using the preserved evidence,
followed by a separately frozen training-only intervention if justified.
There is no promotion to Core ML, Swift runtime, or the personalized app flow
from this result. Any future candidate still needs optional-learning safety,
application-runtime parity, and fresh natural-chord evidence in both chart
styles. Additional human participants are not required; any future own-writer
test must retain its limited generalization claim. Source/model shipping
rights remain uncleared by this research.
