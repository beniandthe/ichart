# Frozen dual-view runtime parity gate

This gate exports the three final-epoch weights from the completed glyph
experiment without fitting, selecting, repairing or altering any learned
tensor. It tests numerical and feature-contract portability only. It does not
test recognition accuracy, fresh writers, full-chord ownership, personalization
quality, iPad behavior or production eligibility.

## Bound inputs and preservation

Fit directory:
`/Users/benirossman/.local/share/ichart/recognition-development/dual-view-glyph-20260930.ttfIcd/fit`.
Fit receipt SHA-256:
`ce60efb539ce4d0897e0c339e6d1e1d90485ec07798aa1da499047482724a46f`.
All 11 original code/protocol snapshots, vocabulary and three arm-specific
weight files must match that receipt before export and afterward. The old
producer, scorer, tests and experiment protocol remain byte-identical.
No source dataset is loaded; no private ink/profile is read or written.
No training, score or development-rule change is permitted.

New export code, its synthetic tests, this protocol, Swift harness and the
actual app feature sources used by the harness are hash-bound before the
first conversion. All output directories are new and exclusive. Preserve any
failed output/logs; do not overwrite or silently relax a failed numerical gate.

## Fixed representation and runtime

Export all three arm masks: `rasterOnly`, `trajectoryOnly`, `dual`.
Use Core ML Tools 9.0, ML Program, explicit float32 computation and float32
input/output tensor types, minimum deployment macOS 13, CPU-only inference.
Apple's [typed execution guidance](https://apple.github.io/coremltools/docs-guides/source/typed-execution.html)
and [input/output documentation](https://apple.github.io/coremltools/docs-guides/source/model-input-and-output-types.html)
motivate making the precision and shapes explicit; documentation is not proof
that this export passes.

Inputs: `inkTrajectory` [1,1,256,10], `inkRaster` [1,1,96,256].
Outputs: `personalEmbedding` [1,128], `genericLogits` [1,97].
Require both input descriptions, both output descriptions, the exact shapes
and float32 types after conversion and Swift model compilation, including
inactive-input arms. No variable output shape or implicit float16 is accepted.
Bind research-only scope, arm, fit, original weight, vocabulary and original
feature contract in package metadata. Package-tree hash and a detached fixture
hash identify the exact artifacts used by the Swift runner.

## Synthetic input cohort

Exactly 12 hand-built, unlabeled original-stroke cases, fixed in code before
conversion: `singlePoint`, `horizontal`, `vertical`, `corner`, `curve`,
`unequalMultiStroke`, `reversedDirection`, `reversedStrokeOrder`,
`timedMultiStroke`, `retimedMultiStroke`, `translatedMultiStroke`,
`scaledMultiStroke`. They cover degenerate geometry, different aspect ratios,
point/stroke order and timing availability. No case has a intended chord,
glyph label, writer identity or correctness field. Freeze actual coordinates
in the exporter snapshot before execution.

Encode features using the existing Python implementation. Swift must recreate
features from original strokes using the actual app rasterizer and trajectory
encoder, not fixture-provided precomputed arrays as its model inputs. Compare
exact uint8 raster bytes and exact little-endian float32 trajectory hashes.
Feature mismatch is a gate failure, not a reason to replace app input with
Python features or loosen equality.

Retain every raw Torch vector and Core ML Python vector for all 12 x 3
arm/case cells, and compare every scalar: 128 embedding and 97 logit values per
cell. Absolute maximum error must be <=1e-4 for embeddings and <=1e-3 for
logits. All values must be finite, embedding L2 norm within 1e-4 of one,
and first argmax must agree in the bound vocabulary order. Do not pick
matching lower ranks or labels to decide portability.

Additional probes use each case's features: set timing channels 5 and 6 to
fixed finite values (0.37 and 1), leaving geometry unchanged, for all three
arms; zero the full inactive input for `rasterOnly`/`trajectoryOnly`. Require
each resulting output to remain within the same numerical tolerances of that
runtime's unperturbed output. This gives 36 base predictions, 36 timing probes
and 24 inactive-input probes per Core ML runtime, 96 total. These probes test
frozen input masks, not real timing accuracy. Include timed/no-timing variants
as original-stroke cases independently of the direct input-channel probes.

## Actual execution and acceptance

The Python producer checks fit/code/weight identities, converts the fixed
checkpoints, runs every base/probe through CPU-only Core ML and writes a
fixture/receipt only after its checks pass. The standalone Swift runner loads
those exact packages, validates compiled model descriptions and metadata,
recomputes features, runs the 96 predictions, compares every base vector to
Torch and Core ML Python, and checks the same mask probes. No labels or
accuracy scores enter either process.

Require actual nonzero executed unit-test cases, terminal exit 0 for export,
Swift compilation and Swift inference, exact expected counters and immutable
input/source/package hashes. Malformed, missing, stale or altered detached
hashes, feature hashes, shapes or arm bindings must fail closed. Retain failure
evidence. Root independently reconciles counters and hashes before reporting
parity. Run only this isolated macOS harness, not an app build/install; it is
not an on-iPad adapter or interaction gate.

Passing this gate permits only preparing the separately predeclared blind
app-domain comparison. It cannot promote the candidate or repair the remaining
shared-model/personalization accuracy deficits. The active goal remains open.
