# Recognition build pass — 2026-09-26

Working branch: `codex/recognition-generalization-reset`.
Base commit: `160aa31`; this record describes the uncommitted working tree.

## Changes completed in this pass

- Evaluation revalidates the actual canonical development-selection report,
  its exact bytes, selected architecture/loss, optimization settings, and frozen
  final-training seed. A different valid comparison report is rejected before
  predictions, including when supplied to descriptive evaluation.
- Model commands validate the full metadata/manifest boundary but open only
  their own feature partition. Training works with calibration/sealed features
  absent; calibration and evaluation require only their respective features.
  Export requires no raw corpus feature mount. Full corpus audits still check
  every referenced artifact.
- Study presents recognizer execution/configuration errors as “Recognition
  unavailable.” Those captures retain their saved ink, require technical
  exclusion, and cannot be marked as ordinary completed no-read predictions.
  The persisted outcome uses the existing `technical-failure` / `not-run`
  representation, with no completed-recognition latency. Completed no-read
  predictions remain distinct.
- Recreated the missing research environment with Python 3.12.14 and the
  repository's pinned NumPy, PyTorch, Core ML Tools, and Pillow versions at
  `/Users/benirossman/.cache/ichart-recognition-ml-py312`.

## Current verification

| Gate | Observed result |
| --- | --- |
| Python suite | 153 tests, zero failures |
| Recognition Study Simulator suite | 126 tests, zero failures, zero skips; confirmed with `xcresulttool` |
| Synthetic model export and Swift inference | Dual-view, trajectory-only, and raster-only passed; ten output heads and three decoded candidates each |
| Maximum CPU parity error | Dual-view `3.5763e-7`; trajectory-only `1.9372e-7`; raster-only `3.5763e-7` (limit `1e-4`) |
| Physical arm64 Study build | Succeeded; Development signature verified with `codesign --verify --deep --strict` |
| iPad installation | Succeeded for `com.ichart.recognitionstudy` |
| iPad launch | `devicectl` confirmed application launched |

The calibration partition-isolation test intentionally uses a tiny synthetic
model without correct chord candidates. It reaches and is rejected by the
calibration-supervision gate. That rejection is expected; the test does not
claim successful calibration or useful recognition.

Simulator result bundle:
`/tmp/RecognitionStudyCurrent-20260926-01.xcresult`.

Installed artifact:
`/tmp/RecognitionStudyDevice-20260926-01/Build/Products/Debug-iphoneos/RecognitionStudy.app`.

The physical device was the paired, wired iPad Air (4th generation), running
iPadOS 26.6.2, with Developer Mode enabled. App version/build: `1.2.1 (51)`.
The existing Study app was updated in place. The production `com.ichart.app`
bundle was not installed or replaced by this pass.

## Meaning and next dependency

The installed Study app uses the Apple Vision engineering baseline. No learned
weights or learned-provider bundle configuration were supplied. The exported
models exercised by the cross-runtime gate were temporary synthetic fixtures;
they were not installed as a usable chord recognizer.

This pass proves pipeline behavior and Study startup. It does not demonstrate
better handwriting recognition, new physical handwriting acceptance, or
writer-independent accuracy. It does not retroactively qualify the existing
ten-prompt engineering captures as training data.

The next accuracy-bearing dependency is an eligible independent-writer chord
corpus: consented captures, independently adjudicated labels, and separate
development, calibration, and sealed writer groups. The collection server and
client components remain local and unwired; reviewed policy/configuration,
authentication/consent UI, and deployment are still needed for an external
pilot. Additional code tests cannot replace that data or demonstrate model
quality. No commit, push, deployment, TestFlight upload, or production promotion
was performed in this pass.
