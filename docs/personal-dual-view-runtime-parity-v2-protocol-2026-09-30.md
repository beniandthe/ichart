# Frozen dual-view export representation v2

This is an export-portability protocol, not a recognition-accuracy experiment.
The original fit, development predictions, scoring, v1 export protocol, exporter,
tests, Swift gate, failed packages and diagnostics remain immutable. There is no
retraining, label use, reserved-writer inference, private-ink evaluation, change
to the live recognizer, or app/profile mutation under this protocol.

## Reason for this version

The v1 trajectory export fails numerical and timing-input invariance on the
native Core ML CPU runtime. A separate Swift diagnostic reproduced the Python
failure with 9/9 exact input readbacks and stride-aware output access. Both gather
and slice-concat versions fail; a gather-only explanation was rejected.

The predeclared operation-isolation diagnostic's 18 predictions show that
transposing the rank-four input before selecting channels passes all three
sentinel/timing/zero cases. That is only an export candidate, not a full-model
fix. The precise compiler/kernel defect and other OS/device behavior are not
established. Failed alternatives are retained; no quality score selected this
expression.

## Sole semantic change

Replace the original export execution expression:

`trajectory[:, 0, :, :].index_select(2, indexes).transpose(1, 2)`

with:

`trajectory.permute(0, 1, 3, 2)[:, 0, :, :].index_select(1, indexes)`

The persistent original `indexes` buffer is exactly `[0,1,2,3,4,7,8,9]`.
No new parameter/buffer is created. Original model state keys, every tensor's
bytes, all three arms, branch masking, towers, projection, fusion, classifier,
normalization, shapes, vocabulary, metadata fields and seed remain unchanged.
The original training/model source is not edited. An isolated export wrapper
expresses the equivalent selection order and runs the same model modules.

## Preconversion equivalence gate

Use the original v1 protocol's 12 fixed, unlabeled synthetic raw-stroke cases.
For each arm run all 36 base, 36 timing and 24 inactive-input cells (96 total).
Compare original eager, original traced, rewritten eager and rewritten traced
Torch outputs, also checking against retained v1 Torch diagnostic vectors.
Both outputs must be finite with unchanged shapes/types and bit-identical
float32 bytes in every cell. Retain an exclusive equivalence receipt containing
all cell output digests/counts and original state identities before/after.
Bind the exact parent v1 failure diagnostic and the 18-cell stage diagnostic
receipts in that equivalence artifact, including their source and package
identities. Reject the candidate before conversion if any equality or
preservation fails.

## Complete runtime gate

All requirements in `personal-dual-view-runtime-parity-protocol-2026-09-30.md`
remain in force except the explicit version/binding changes below. In particular:

- Both inputs remain `[1,1,256,10]` and `[1,1,96,256]` float32; outputs remain
  `[1,128]` and `[1,97]` float32. No input/feature adapter change is permitted.
- Use MLProgram, FLOAT32 execution and input/output declarations, CPU-only,
  macOS13 minimum target, and the recorded Core ML Tools 9 runtime.
- Use the **original model**, not the rewritten wrapper, for fixture Torch
  reference values. Saved packages must match that model, not merely themselves.
- Require all 96 predictions in each Python and Swift runtime, exact original
  feature bytes from the actual five app Swift encoders, and every output scalar
  against original Torch/Python references. Keep embedding tolerance `1e-4`,
  logit tolerance `1e-3`, first-argmax, finiteness, norm and invariance gates.
- Inspect the saved MIL selector order and preserve packages/inputs/sources.
  The reordered selector subgraph is the only allowed execution-graph change;
  learned constants and downstream topology must remain identical.
- Before any v2 conversion, authenticate the two retained v1 packages against
  fixed tree digests/byte counts and learned-blob digests/byte counts in the
  source-bound exporter. The raster digest must match its pre-candidate v1
  fixture. For trajectory, retain the parent failure/source lineage and prior
  direct checkpoint-constant comparison; the fixed package identity is pinned
  before v2 execution, not claimed to be a previously signed manifest.
- After the 96-cell Torch gate, also export one original-expression **dual**
  control via the frozen v1 converter into `control/dual-v1.mlpackage` in the
  new exclusive output. It is a structural control only: no control predictions,
  fixtures, labels, quality scores or promotion. Compare candidate dual learned
  blob bytes and downstream dynamic topology to this control; validate the
  control's original selector and preserve/bind its package identity before and
  after. This adds one conversion, not another prediction or architecture search.
- Any failure rejects this attempt. Do not retune tolerance, change a case,
  replace weights, or erase prior outputs. A success receipt is written last.

The export container schema becomes `personal-dual-view-coreml-export-v2`;
fixture cell schema remains v1 because its contract is unchanged. The new Swift
success receipt is `personal-dual-view-swift-parity-receipt-v2`.

The v2 export receipt adds exactly `equivalenceReceiptRelativePath`,
`equivalenceReceiptSHA256`, and `equivalenceReceiptByteCount` to the original
four top-level fields. The relative path is `equivalence-receipt.json`; the
detached export-receipt digest therefore anchors the equivalence artifact.
Before model load, the Swift gate verifies the equivalence file identity,
`schemaVersion=personal-dual-view-export-equivalence-v2`, `passed=true`,
`predictionCount=96`, `outputScalarCount=21600`, and
`retainedV1ReferenceCellCount=72`. It checks preservation afterward. All detailed
Torch/state/parent checks are performed before export; Swift still independently
compares every runtime output against original Torch fixture values.

Source binding includes all 20 original v1 dependencies plus these four files
(24 in total): this protocol; `personal_dual_view_export_v2.py`;
`test_personal_dual_view_export_v2.py`; `PersonalDualViewCoreMLParityGateV2.swift`.
Hash the exact protocol and every dependency before use. Bind the same frozen
fit receipt `ce60efb539ce4d0897e0c339e6d1e1d90485ec07798aa1da499047482724a46f`
and its exact original three weight artifacts. Publish in a fresh directory.

## Permitted conclusion

Success establishes synthetic portability of these frozen weights under this
recorded CPU environment and equivalent export expression. It does not prove
recognition improvement, trustworthy automatic personalization, new-writer
accuracy, iPad execution, app integration, or ship readiness. Those remain
separate gates. This protocol does not authorize install, commit, push, release,
production deployment, or changes to saved handwriting profiles.
