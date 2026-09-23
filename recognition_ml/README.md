# iChart recognition ML workspace

This directory is the reproducible, writer-independent data-contract boundary for
future chord-recognition training and evaluation. It intentionally contains no
handwriting, labels, model weights, checkpoints, or generated manifests.

The checked-in code currently provides:

- a frozen feature contract matching the app's `chord-ink-features-v1` tensors;
- strict JSONL record parsing and raw feature-artifact validation;
- strict canonical chord labels matching the Swift `ChordNotation` language;
- active-consent and authenticated-provenance metadata requirements;
- writer-, session-, geometry-cluster-, and lineage-disjoint split checks;
- deterministic corpus-manifest generation and verification;
- a deterministic dual-view trajectory/raster PyTorch model with factor logits
  matching the Swift runtime contract;
- deterministic trajectory-only and raster-only ablations plus a development-
  writer-only DTW comparison baseline;
- weights-only checkpoint save/load with exact corpus, feature, output-head, and
  model-configuration bindings;
- development-only training and sealed-writer descriptive factor evaluation;
- writer-micro and writer-macro descriptive reports with selective-risk,
  no-read, calibration, latency, and required collection-stratum slices;
- joint-path one-vs-rest calibration math matching the Swift selective policy;
- an exact, non-overwriting bridge from canonical Recognition Study trajectory
  packets to the frozen trajectory and raster feature artifacts; and
- a whole-session Recognition Study intake gate that verifies the frozen
  ten-prompt engineering pass, every capture/outcome commit and digest, and the
  deterministic features while preserving an explicit non-corpus status; and
- compiled Core ML shadow-model export with deterministic directory
  fingerprinting and a Swift-compatible sidecar manifest.

Passing these contracts does **not** establish recognition accuracy, no-read
quality, or production authority. Corpus v2 can represent independently
adjudicated notation and legitimate negative/open-set no-read examples, while
ambiguous ink and collection failures are explicitly excluded from model
supervision. Every actual corpus must still contain both eligible classes in
the required writer-disjoint roles. Calibration artifacts, selective
thresholds, promotion gates, and no-read trust remain fail-closed until those
examples and the required independent sealed evidence exist. Research
authorization, consent withdrawal checks, protected registry verification,
label adjudication, and a genuinely independent-writer corpus remain external
prerequisites.

## Portable feature artifacts

Each record references two files beneath a caller-supplied data root:

- trajectory: exactly 2,560 finite little-endian Float32 values (`10,240` bytes),
  shape `[1, 256, 10]`, encoding `float32-le`;
- raster: exactly `256 x 96` grayscale UInt8 values (`24,576` bytes), encoding
  `uint8-gray`.

Both files are bound by lowercase SHA-256 and exact byte count. Absolute paths,
path traversal, symlinks escaping the data root, unknown fields, non-canonical
UUIDs/hashes, NaN/Infinity, and incomplete metadata are rejected.

## Commands

Run from this directory without installing dependencies:

```sh
python3 -m unittest discover -s tests -v
python3 -m ichart_recognition_ml validate-records \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features
python3 -m ichart_recognition_ml build-manifest \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --dataset-version pilot-001 \
  --output /protected/corpus/manifest.json
python3 -m ichart_recognition_ml validate-manifest \
  --manifest /protected/corpus/manifest.json \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features
```

Mechanically validate an exported local Recognition Study pass and stage its
deterministic features:

```sh
python3 -m ichart_recognition_ml import-study-session \
  --study-root /private/export/RecognitionStudy \
  --local-session-id <local-session-uuid> \
  --output-dir /private/staging/study-pass-001
```

`receipt.json` from this command is deliberately marked
`local-engineering-only-not-corpus-eligible-v1` and
`mechanical-validation-only`. Prompt intent and the writer's own confirmation
remain self-reported diagnostics—not independently adjudicated ground truth.
The command never emits corpus JSONL, assigns a writer or split, establishes
consent/provenance, or makes a capture eligible for training, calibration, or
sealed evaluation. A future collection authority must satisfy those missing
boundaries under a separately versioned protocol.

Install optional tooling only in an isolated research environment:

```sh
python3 -m pip install -e '.[training,export]'
```

Train a deterministic development-only checkpoint:

```sh
python3 -m ichart_recognition_ml train \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --manifest /protected/corpus/manifest.json \
  --model-identifier dual-view-pilot-001 \
  --output-dir /protected/runs/pilot-001
```

Run a descriptive sealed-writer factor evaluation. This emits no gate receipt
and never claims no-read trust:

```sh
python3 -m ichart_recognition_ml evaluate \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --manifest /protected/corpus/manifest.json \
  --checkpoint /protected/runs/pilot-001/checkpoint.pt \
  --output-dir /protected/runs/pilot-001-evaluation
```

Fit the exact Swift joint-path temperature on calibration writers. The command
requires a checkpoint trained with both eligible notation and no-read examples,
and a calibration role containing both classes. It emits a fit report only—no
thresholds, gate receipt, or production authority:

```sh
python3 -m ichart_recognition_ml calibrate \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --manifest /protected/corpus/manifest.json \
  --checkpoint /protected/runs/pilot-001/checkpoint.pt \
  --fit-dataset-identifier calibration-writers-001 \
  --output-dir /protected/runs/pilot-001-calibration
```

Export the same uncalibrated checkpoint for learned-shadow runtime testing:

```sh
python3 -m ichart_recognition_ml export \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --manifest /protected/corpus/manifest.json \
  --checkpoint /protected/runs/pilot-001/checkpoint.pt \
  --model-identifier dual-view-pilot-001 \
  --detached-manifest-sha256 <release-envelope-sha256> \
  --output /protected/runs/pilot-001/ChordInk.mlmodelc \
  --manifest-output /protected/runs/pilot-001/ChordInk.manifest.json
```

`calibrate` and `evaluate --require-promotion-gate` deliberately refuse when the
bound eligible development rows do not include both notation and adjudicated
no-read supervision. Calibration also refuses unless its own writer-disjoint
role supplies both classes and the decoded observations contain positive and
negative candidate/no-read paths. No command silently falls back to partial
metadata, an in-sample split, unverified feature files, top-three softmax
renormalization, or a fabricated no-read claim. Temperature scaling is defined
as `joint-path-one-vs-rest-v1`: each decoded raw joint log probability is
converted to a binary logit, divided by temperature, and passed through sigmoid
without renormalizing surviving candidates.
