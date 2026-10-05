# Dual-view Core ML export: bounded runtime parity passed

The frozen dual-view glyph candidate now passes the declared Python/Core ML and
standalone Swift CPU portability gates on the recorded Mac. An export-only
selector rewrite resolved the measured native layout failure without retraining,
changing recognition rules, changing inputs, relaxing tolerances, or touching
the installed app or handwriting profiles. This is **not** a recognition-quality,
new-writer, full-chord, iPad, personalization-safety, or release result.

## Failure retained, not erased

The original [v1 protocol](personal-dual-view-runtime-parity-protocol-2026-09-30.md)
and exporter remained frozen. The actual v1 attempt exited 1 on timing/inactive
invariance before publishing a final export receipt. Raster-only passed its
fixture; trajectory-only failed; dual was not exported in that attempt.

A separate 72-prediction diagnostic against the two retained packages found
trajectory base-logit error up to 75.794092 and 11/12 base argmax mismatches.
Torch ignored timing channels exactly; the native trajectory program did not.
The saved selector constants and all 12 learned trajectory tensors matched the
original checkpoint. Numerical tolerance was not the explanation.

Unlabeled operation probes then narrowed the problem without user answers:

- Identity versus two selector expressions: 9 Python predictions, only 5 exact.
- C/Fortran/padded input layouts: 18 predictions, same nonzero failures.
- Direct Swift input/output indexing: 9 predictions, input readback exact for
  all 9, but only 5 outputs exact. This ruled out a Python-only bridge/readout
  explanation for the reproduced defect.
- Six view/selection stages: 18 predictions. Squeeze-only and rank-4 transpose
  before selection were exact in all 3 probes each; the other 4 expressions
  failed both nonzero probes. The exact underlying compiler/kernel cause was
  not established.

All failed artifacts, executed source versions and logs were retained. The v1
diagnostic counts are not successful v1 parity or accuracy measurements.

## Precisely bounded correction

The separately frozen [v2 protocol](personal-dual-view-runtime-parity-v2-protocol-2026-09-30.md)
allows only the equivalent selector expression:

```python
# Original
x[:, 0, :, :].index_select(2, indexes).transpose(1, 2)
# Export wrapper, same indices and mathematical values
x.permute(0, 1, 3, 2)[:, 0, :, :].index_select(1, indexes)
```

`indexes` remains `[0, 1, 2, 3, 4, 7, 8, 9]`. All 43 original state entries,
parameter/buffer aliases, checkpoint bytes, tower masks, fusion, output heads,
normalization and original training/scoring sources were preserved.

Before conversion, original eager, original traced, rewritten eager and
rewritten traced outputs were byte-identical for all 96 declared cells.
Exactly 72 raster/trajectory cells also matched retained v1 Torch references.
The 24 dual cells used the original fitted Torch model, not candidate outputs,
as their numerical oracle.

Saved-program inspection required the new selector feeding the trajectory
convolution. Candidate downstream dynamic operation sequences and complete
learned-weight blobs matched the pinned retained v1 packages, or, for dual,
one new original-expression control package. The control was created only
after Torch equivalence passed and performed **zero predictions**. This is a
structural and byte-identity comparison, not full graph-attribute isomorphism
or universal operator-equivalence proof.

## What actually passed

| Check | Executed result |
| --- | --- |
| Focused exporter unit tests | 20 passed; 0 failures or skips |
| Final standalone Swift compilation | Exit 0 |
| Four-way Torch equivalence | 96/96 cells bit-exact |
| Python Core ML CPU predictions | 96/96 passed |
| Swift Core ML CPU predictions | 96/96 passed |
| Each runtime's cell coverage | 36 base + 36 timing + 24 inactive-input |
| Each runtime's output coverage | 21,600 scalars: 128 embedding + 97 logits per cell |
| Swift versus Python maximum error | 0 for both complete output vectors |
| Native timing/inactive invariance | All 60 comparisons exactly zero |
| Native versus original Torch max error | Embedding 1.3411045e-7; logits 1.7166138e-5 |
| Unchanged declared tolerances | Embedding 1e-4; logits 1e-3 |
| Swift comparison counters | 43,200 reference scalars; 13,500 invariance scalars; 21,600 fixture scalars; 252 argmax checks |

The Swift gate compiled the five actual app packet/raster/trajectory feature
sources and checked exact fixture feature bytes before prediction. It validated
fixed shapes, FLOAT32 contracts, finite values, embedding norms, first argmax,
metadata, detached fixture hashes and complete model-package identities.
All 24 bound source files, fixtures, model packages, fit artifacts and original
model state were preserved. A second agent independently reconciled the actual
artifacts without model loading/inference or writes.

The root's auxiliary read-only reconciliation script initially rejected its
own assumptions about inactive trajectory input and nullable retained dual
references. Only that auxiliary script was corrected; both frozen parity gates,
their inputs, outputs and acceptance thresholds remained unchanged. Final
reconciliation exited 0; prior script versions/partial logs are retained.

## Durable evidence

Failed v1 evidence root:
`/Users/benirossman/.local/share/ichart/recognition-development/dual-view-runtime-parity-20260930.bmxl5o`.

V2 evidence root:
`/Users/benirossman/.local/share/ichart/recognition-development/dual-view-runtime-parity-v2-20260930.H4E42I`.
The evidence boundary is `export/`, detached `swift-parity-receipt.json`, and
`verification-v2/`; unrelated recoverable accidental-checkout copies outside
that boundary are not export artifacts.

| Artifact | SHA-256 |
| --- | --- |
| Export receipt | `4dcc5d1ad30c0fd011a0aa10d02ea346c34ea0e08839320ee71091ea099319e5` |
| Equivalence receipt | `67631b7137bc469a9895036535aa6d8ec3cf83cfc08cd1ebba600b2b8fba0b1b` |
| Swift receipt | `eb2dee06449f3baf03585599052440398a82f4977e8b62712899a51153593fc0` |
| Executed final Swift binary | `5e78667b99e4e3c0b4d28f1fb45be6136184633f67e34167070015776f627a2d` |
| Final root reconciliation | `446582bc1dd913a7f2c4a44b027ad87e809532c1ad03fdde922d4950974ab4a5` |

`verification-v2/sources/` contains exact snapshots of all 24 bound files.
Verification logs, final binary and root reconciliation scripts/results are
retained alongside them. The compiled-binary hash and host facts are procedural
observations, not embedded attestation in the Swift receipt.

Recorded environment: macOS 26.5.2 / 25F84, arm64, kernel 25.5.0,
Xcode 26.6 / 17F113, Swift 6.3.3, Python 3.12.14, Torch 2.7.0,
NumPy 2.0.2, Core ML Tools 9.0; FLOAT32 MLProgram, CPU-only, macOS 13 target.
Execution completed September 30 local time / October 1 UTC.

## Remaining recognition work

The [development glyph result](personal-dual-view-glyph-results-2026-09-30.md)
is unchanged: dual 1,117/1,552 (71.97%) versus matched raster 1,035/1,552
(66.69%), on eight already-observed writers. It still trails the separately
trained historical encoder's 1,229/1,552 result. Those are glyph rates, not
full-chord accuracy or fresh-writer evidence.

Unconditional dual personalization still has net +13 over 776 paired queries
but loses 9 for one writer; it is not safe to silently replace shared-model
reads. Next work must retain baseline outputs, keep personal suggestions
reviewable, freeze any safety/evaluation rule before predictions, and evaluate
genuinely new handwriting in both chart styles. No reserved test writer,
private ink, live acceptance route, profile, iPad app, build/sign/install,
commit, push, deployment or release was changed by this portability pass.
