# Direction neutral stroke field results

The fixed experiment completed on October 3, 2026 and failed its advancement
screen. Removing stroke-direction polarity preserved the intended geometry
and improved average isolated-symbol scores, but did not produce a sufficiently
safe replacement for the image-only control. Keep this candidate offline.
No app model, chart, profile, installation, or production service changed.

This is research for the existing customizable recognition pipeline, not an
alternate live reader. It does not establish whole-chord accuracy, a benefit
from personal examples, or readiness to ship.

## Comparison and integrity

Followed the [frozen protocol](personal-unoriented-stroke-field-protocol-2026-10-03.md)
without changing the seed, schedule, labels, checkpoint, thresholds, or gates
after seeing evaluation answers. Both models received the same original
drawings, complete initial weights, and spatial augmentation. The candidate
adds local unoriented stroke geometry and endpoint union to the app's ink
image; the control masks these auxiliary planes.

All 10,073 training rows matched the preserved source, label, order, ink image,
and normalized geometry. Global stroke reversal plus enumeration reversal
produced identical auxiliary planes and ink images on every training row.
Synthetic tests separately covered subset reversal, retracing, crossings,
subdivision, dots, tensor rotation, and exact control augmentation. These are
representation checks, not evidence of better natural handwriting recognition.

Training used 6,208 UJI drawings from 32 writers and 3,865 HWRT drawings. Both
arms completed 30 epochs, 1,530 updates, and 195,840 exposures. Repeated
exposures are not independent examples. The control's final weights,
sampling schedule, and affine stream exactly reproduced the previous fixed
experiment. Its full outputs also matched all 1,987 prior evaluation outputs.

Only after the completed-fit check were the 1,552 drawings from eight reused
UJI development writers and 435 HWRT test drawings encoded. Every prediction
retains 102 finite logits and a 128-value embedding, frozen before the scorer
opened truth. Reserved writers, private ink, saved lessons, and chart answers
were not used. The finalized synthetic gate executed 29 tests with warnings
treated as errors, zero failures, and zero skips.

## Results

Corrections and regressions compare the literal first predictions on identical
drawings. They are symbol counts, not complete-chord success rates. Sources
are reported separately rather than pooled.

| Development cohort | Drawings | Image control correct | Neutral field correct | Corrections | Regressions |
| --- | ---: | ---: | ---: | ---: | ---: |
| All UJI labels | 1,552 | 1,237 | 1,255 | 70 | 52 |
| UJI chord-fragment labels | 656 | 549 | 561 | 27 | 15 |
| Five mapped HWRT shapes | 435 | 405 | 415 | 12 | 2 |

The newly mapped shape counts were sharp 130 to 131 out of 131; plus 9 to 8
out of 9; slash 34 to 38 out of 54; half-diminished shape 91 to 96 out of 97;
and major triangle shape 141 to 142 out of 144. HWRT writer identity is not
reliable for writer-level inference, and these five labels are confounded
with their source. The plus cohort is especially small.

Seven UJI drawings were excluded by the recomputed input-copy union. The
no-copy totals were 1,230 to 1,248 out of 1,545 for all UJI labels and 542 to
554 out of 649 for chord-fragment labels. Corrections, regressions, writer
net changes, HWRT counts, and failed gates were unchanged.

## Why the candidate stays offline

Four predeclared conditions failed in both raw and copy-excluded scoring:

- One writer lost three correct readings, exceeding the allowed loss of two.
- The writer-level sign-flip result was 0.125, not below 0.05. Across the
  eight writers the net changes were -1, 0, +5, +7, +5, -3, +3, and +2.
- Plus-sign recognition regressed by one drawing; not every mapped class
  was non-worse.
- Eighteen non-domain drawings changed from rejected to permitted-symbol
  guesses. Total permitted guesses on these drawings decreased from 74 to
  71, but that aggregate improvement does not erase the new false accepts.

Unsupported raw winners still become unresolved; a lower-ranked legal label
is not promoted. Permitted isolated fragments are not complete chord
suggestions. The app's complete-chord presentation boundary remains separate
and unchanged.

The result supports reversal robustness of this feature representation, not
a claim that direction dependence caused the user's errors or that its removal
fixes them. Reused development writers cannot provide fresh statistical
confirmation after repeated research. Do not repair these results with
writer, class, example, or direction-specific exceptions. No new candidate
weights enter the app, and no personalization benefit or shipping rights
are established.

## Preserved evidence

Workspace branch `codex/recognition-generalization-reset`, HEAD
`160aa31594903508e241802e21ca83ec447de849`, with pre-existing uncommitted work
preserved. Execution used Python 3.12.14, Torch 2.7.0, NumPy 2.0.2, and four
deterministic CPU threads on macOS arm64. No commit or push occurred.

The execution directory is `/private/tmp/iChartUnorientedField-20261003.XOcG6Y`.
The durable local evidence directory is
`/Users/benirossman/.local/share/ichart/recognition-development/unoriented-field-20261003.uAqHZv`.
It retains the feature files, metadata, frozen protocol and executed code,
training plan, weights, predictions, separate score, and logs outside Git.

| Artifact | SHA256 |
| --- | --- |
| Frozen protocol | `4d72f1e61e409e8da9c563dc7a8eca430370675b5b6fa81eeab9dad327178fe3` |
| Training receipt | `b1f8df4e0876cb5e236a9acdd00e1c899660b33ad6ccdd8baadfc8f47ac3dd6e` |
| Fit receipt | `4422ee7a1fac545ae75a81fe48d8f5f5bb9d1b10cc22c353dc519f1b6d4850b1` |
| Development receipt | `9942c53c4ed177d1f988eb3d79d2064947170b26bd6e5b75c95308fa0efe180c` |
| Frozen predictions | `222306bc86c00128af5a2dd579ead309d6050c74358b8e6889260c125f513086` |
| Score | `1c7e9fac7f0bf5e754963e0ff59ae7d8f8e50f7074d95cd26e1551cae12b289a` |
| Independent score reconciliation | `8e7df067132f07369ff1ae329c57d7fabc48689c91417c5d70432018a1e3dd2f` |
| Independent verifier | `6e6c132d4f3b141126687d3d6fb42fbed8666d48bbbdc702fb478c9cf3196b3f` |

Independent training metadata reconciliation passed for all rows, bindings,
and source roles. It checked the saved reversal ledger's consistency, not an
independent recomputation of feature geometry. The separate standard-library
verifier checked all 3,974 finite output vectors and hashes, recomputed literal
first predictions, confirmed prior-control output equality, and reproduced
copy exclusions, raw and no-copy summaries, and every fixed gate without
importing the experiment scorer.
It also checked the recorded fit ledgers, reconstructed schedule, and all
30 executed-code bindings. No discrepancies were found. It did not execute
models or read weights, field arrays, or corpora; weight-state and augmentation
hashes remained receipt commitments in this independent check.

The complete execution directory and durable copy were compared byte for byte.
The candidate remains rejected; passing implementation and reconciliation
checks does not override the failed recognition conditions.
