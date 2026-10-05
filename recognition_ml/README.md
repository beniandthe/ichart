# iChart recognition ML workspace

**Parked as of 2026-10-05.** This retained research workspace is not the active
app release backlog. Start at [Project state](../docs/project-state.md) for app
work and [Parked recognition research](../docs/parked-recognition/README.md) for
snapshot branches, evidence, and reopening conditions. The commands below are
reproducibility references, not instructions to resume experiments automatically.

Normal app CI does not install this workspace or run model experiments. Its
contracts and the separate RecognitionStudy app remain available through the
CI workflow's explicit `run_recognition_research` dispatch input. Swift app
recognition safety and parser tests remain in normal app validation.

This directory is the reproducible, writer-independent data-contract boundary for
future chord-recognition training and evaluation. It intentionally contains no
handwriting, labels, model weights, checkpoints, or generated manifests.

### Personal visual features: isolated development research

`ichart_recognition_ml.research.personal_visual_encoder` trains the visual
representation used by a local personal classifier on public, writer-separated
character data. It is **not another OCR service**, a production corpus intake,
or a promoted recognizer. Setup examples train a separate per-person head;
query answers cannot enter that fit. The optional export command emits an
embedding-only research Core ML package outside app assets. Swift diagnostics
check it through the actual app rasterizer and personal ridge solver.

The frozen configuration, attribution, results and scope limits are in
[`personal-visual-encoder-protocol-2026-09-28.md`](../docs/personal-visual-encoder-protocol-2026-09-28.md).
Use the pinned `[export]` dependencies and a new output directory per run:

```sh
python -m ichart_recognition_ml.research.personal_visual_encoder \
  --source /path/to/ujipenchars2.txt \
  --geometric-report /path/to/public-root-development.json \
  --output /path/to/new-research-run
python -m ichart_recognition_ml.research.personal_encoder_export \
  --source /path/to/ujipenchars2.txt \
  --run /path/to/new-research-run \
  --output /path/to/new-research-export
```

Neither command modifies profiles, charts, the native recognizer, production
acceptance, or installed apps. Public isolated-character performance must not
be reported as chord accuracy. Official test writers remain reserved.

### Additional writer-identified raster source: offline intake only

`research.nist_sd19` audits the public NIST SD19 second-edition `by_write`
PNGs against the first-edition checked `.cls` labels. It preserves exact label
bytes, image/label hashes and source paths, groups all form templates and fields
of the same documented writer together, and keeps `hsf_4` reserved. Raw-file
copies and decoded-raster copies have separate cross-split receipts. No labels
are inferred from form prompts or directory class aliases.

```sh
python -m ichart_recognition_ml.research.nist_sd19 \
  --png-zip /absolute/path/to/by_write.zip \
  --cls-zip /absolute/path/to/1stEdition1995.zip \
  --seed nist-sd19-offline-intake-v1 \
  --development-fraction 0.1 \
  --foreground black --verify-rasters \
  --output /absolute/path/to/new-source-audit
```

The exclusive output directory contains a compact source/split/quality receipt
and a streaming `samples.jsonl`. This is a source-integrity boundary, not corpus
eligibility or evidence of recognition accuracy. Images are unresized 128x128
rasters; they are never presented as observed Pencil trajectories or silently
converted to the app's feature schema. The alphanumeric vocabulary does not
provide music-symbol coverage. SD19-specific commercial rights remain unresolved
from the current source metadata; even a passing audit records no training or
shipping eligibility. No model, app, chart, or profile is changed by this command.

Before any later experiment, `research.nist_sd19_quarantine` creates a separate
clean integrity manifest and a recoverable quarantine of **all** members of
every repeated raw-PNG or decoded-raster hash group. Its rule is independent of
labels or prediction outcomes; it does not select one favorable representative.
Supply the exact, previously verified source-summary SHA-256:

```sh
python -m ichart_recognition_ml.research.nist_sd19_quarantine \
  --source-summary /absolute/path/to/source-audit/summary.json \
  --source-samples /absolute/path/to/source-audit/samples.jsonl \
  --summary-sha256 <verified-source-summary-sha256> \
  --output /absolute/path/to/new-clean-integrity-subset
```

Retained rows are byte-identical to the original stream. Removed rows retain
their complete provenance and exact original line bytes. Neither command
modifies its input, and a clean integrity subset still does not establish
commercial rights, training eligibility, or handwriting-recognition accuracy.

### Fixed broad-writer transfer: local research only

`research.nist_sd19_training_source` prepares a separate, hash-bound raster
selection from the clean training role only: one source per recorded writer
and exact ASCII class, then 512 writers per class. Its explicit nearest-neighbor
bbox transform produces binary 256x96 images within the native visible envelope;
it does not invent trajectories or claim native vector-geometry parity.
Selection, source/adapted pixels, counts and unresolved rights remain recorded.

`research.personal_broad_transfer` compares that 31,744-row source with an
exposure-matched replay of the existing UJI training sources. Both use five
62-class pretraining epochs, a complete reset to identical original 97-class
heads, then the same 30-epoch UJI fine-tune. NIST planes are memory-mapped;
UJI repeats are represented by indices. Both pretraining and final checkpoints
and training-only feature bundles are retained outside the repository.

The fit requires the exact additive, dated local-research-use decision in
addition to the unchanged unresolved-rights source receipts. NIST's stated
OCR training/research purpose supports this experiment, not a commercial
derived-weight shipping claim. Do not integrate or distribute its weights.

```sh
python -m ichart_recognition_ml.research.personal_broad_transfer \
  --source /absolute/path/to/ujipenchars2.txt \
  --nist-dir /absolute/path/to/prepared-nist-training \
  --protocol /absolute/path/to/frozen-caller-protocol.json \
  --research-decision /absolute/path/to/frozen-research-use-decision.json \
  --output /absolute/path/to/new-paired-fit
```

Use `research.personal_broad_transfer_evaluation` in separate
`prepare`, `predict`, then `score` operations. It retains all paired attempts,
uses only final UJI training embeddings as personal anchors, preserves the
exact prior Swift-stored supports, and opens query truth only after predictions
are frozen. Its fixed screen also reports the 35 UJI classes absent from
pretraining. The eight reused writers are descriptive development evidence;
neither a passing screen nor these tests establishes new-writer, natural-chord,
Swift/Core ML runtime, or physical-Pencil accuracy.

See the frozen
[`broad-transfer protocol`](../docs/personal-broad-transfer-protocol-2026-10-01.md).
No query-dependent retuning, app/profile changes, release or production
eligibility is part of this workflow.

### Matched raster / trajectory glyph research

`research.personal_dual_view` adds ordered-trajectory geometry to the shared
glyph representation, with raster-only and trajectory-only masked controls.
All arms start from identical tensors; inactive branches are zeroed after
projection. This estimates enabling a second representation/active tower, not
stroke-order causality or full-chord recognition. UJI timing channels are
excluded; all three arms use no augmentation.

The fixed protocol is
[`personal-dual-view-glyph-protocol-2026-09-30.md`](../docs/personal-dual-view-glyph-protocol-2026-09-30.md).
Fit all three final checkpoints before a separate prediction process freezes
all development logits. Only the separate scorer joins query labels. The eight
already-observed writers are development evidence, not a fresh app-domain gate.

```sh
python -m ichart_recognition_ml.research.personal_dual_view fit \
  --source /absolute/path/to/ujipenchars2.txt \
  --protocol /absolute/path/to/personal-dual-view-glyph-protocol-2026-09-30.md \
  --output /absolute/path/to/new-fit
python -m ichart_recognition_ml.research.personal_dual_view predict \
  --source /absolute/path/to/ujipenchars2.txt \
  --protocol /absolute/path/to/personal-dual-view-glyph-protocol-2026-09-30.md \
  --fit /absolute/path/to/new-fit \
  --output /absolute/path/to/new-predictions
```

Use canonical absolute paths and new exclusive output directories. This path
does not modify the live app, profiles, saved ink, acceptance or production
model assets. Keep generated weights and reports outside Git.

The checked-in code currently provides:

- a frozen feature contract matching the app's `chord-ink-features-v1` tensors;
- strict JSONL record parsing and feature-artifact validation, including the
  frozen per-channel ranges, binary flags, and `0`/`255` raster alphabet;
- strict canonical chord labels matching the Swift `ChordNotation` language;
- active-consent and authenticated-provenance metadata requirements;
- writer-, session-, geometry-cluster-, and lineage-disjoint split checks;
- an exhaustive, bounded, label-blind root-capture leakage scanner that emits
  immutable exact/high-similarity/manual-review candidates without assigning
  clusters or qualifying the corpus;
- a strict dual-independent-review resolver that recomputes the source scan,
  requires every candidate decision, rejects transitive contradictions, and
  deterministically prepares unsigned cluster assignments for a protected
  registry service;
- deterministic corpus-manifest generation and verification;
- a versioned, deterministic dual-view trajectory/raster PyTorch model with
  coarse temporal and spatial layout preserved through pooling, factor logits
  matching the Swift runtime contract, and a writer-balanced per-head training
  objective;
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
- compiled Core ML shadow-model export with exact whole-directory fingerprint
  binding and a Swift-compatible sidecar manifest.

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

Model operations validate the complete corpus metadata and manifest, then
open feature bytes only for the role they consume: development for comparison
and training, calibration for temperature fitting, and sealed evaluation for
assessment. Export uses the frozen checkpoint without opening corpus features.
Full artifact audits (`validate-records`, `build-manifest`, and
`validate-manifest`) still verify every referenced file. Training therefore
works while held-out handwriting is physically unavailable, and a refused
evaluation does not open sealed features during command preflight.

## Portable feature artifacts

Each record references two files beneath a caller-supplied data root:

- trajectory: exactly 2,560 finite little-endian Float32 values (`10,240` bytes),
  shape `[1, 256, 10]`, encoding `float32-le`;
- raster: exactly `256 x 96` grayscale UInt8 values (`24,576` bytes), encoding
  `uint8-gray`.

Both files are bound by lowercase SHA-256 and exact byte count. Absolute paths,
path traversal, symlinks escaping the data root, unknown fields, non-canonical
UUIDs/hashes, NaN/Infinity, out-of-contract trajectory channels, nonbinary
trajectory flags or raster pixels, and incomplete metadata are rejected.

## Commands

Run with Python 3.10 or newer from this directory without installing optional
model dependencies. The scanner uses the native integer population-count
operation introduced in Python 3.10 so its exhaustive pilot bound remains
practical; older interpreters are intentionally outside the package contract.

```sh
python3 -m unittest discover -s tests -v
python3 -m ichart_recognition_ml validate-records \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features
python3 -m ichart_recognition_ml scan-leakage \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --output-dir /protected/audits/pilot-001-leakage-scan
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

`scan-leakage` validates every referenced feature artifact and exhaustively
compares every pair of consented human lineage roots, up to the frozen v1
capacity guard. Candidate generation uses only payload/feature digests and
trajectory/raster geometry; chord labels, writers, splits, and declared
clusters cannot affect a pair decision. The immutable report binds the exact
record set, feature schema, scanner configuration, and scanned artifact
digests. It remains `candidate-generation-only` and `corpus_qualified: false`
even when it finds no candidates. Exact and near-neighbor candidates still
require protected adjudication and registry assignment; an empty thresholded
candidate list is not proof that a corpus is leak-free.

After two independent protected reviewers resolve every emitted pair, prepare
deterministic cluster assignments with:

```sh
python3 -m ichart_recognition_ml finalize-leakage-adjudication \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --scan-report /protected/audits/pilot-001-leakage-scan/leakage_scan.json \
  --adjudication /protected/reviews/pilot-001-adjudication.json \
  --output-dir /protected/audits/pilot-001-cluster-preparation
```

This command reruns the exact scan and refuses a missing, added, reordered, or
tampered candidate. Each pair needs distinct first and second reviewer HMAC
commitments. Agreement is final without an adjudicator; disagreement requires
a third distinct reviewer commitment and bound final decision. Digest-identical
content cannot be split, and transitive same/distinct contradictions fail. The
receipt remains `unsigned-registry-preparation-only`, `registry_signed: false`,
and `corpus_qualified: false`: reviewer hashes are commitments, not verified
identities, and only the separately protected service can authenticate them,
issue the cohort registry, and sign a current snapshot.

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
Current semantic outcomes use `recognition-study-semantic-outcome-v2` and
persist bounded end-to-end provider-call latency in integer microseconds for
every non-technical observation. That measurement includes provider feature
preparation, inference, and decoding; it is not a first-preview UI latency.
Interrupted captures and recognizer execution/configuration errors are recorded
as `not-run` technical failures with no completed-recognition latency. Study
requires exclusion of those captures and reports them separately from completed
no-read predictions. The importer still accepts canonical legacy v1 outcomes only when the
latency field is absent, and emits an
`recognition-study-session-import-receipt-v2` receipt whose baseline
observations expose the structured value (or `null` for legacy/technical
records).
The command never emits corpus JSONL, assigns a writer or split, establishes
consent/provenance, or makes a capture eligible for training, calibration, or
sealed evaluation. A separately versioned server authority, strict client
transport, protected exact-byte queue, and finite upload coordinator now exist
for a future reviewed collection deployment. A protected durable withdrawal
barrier also purges queued raw captures before network access and prevents
collection from reopening after acknowledgement. These components are not
wired into this local import path or app lifecycle, and they do not
retroactively authorize local engineering captures.

Install optional tooling only in an isolated research environment:

```sh
python3 -m pip install -e '.[training,export]'
```

The optional dependency versions are intentionally pinned to the toolchain used
by the export gate. Export declares and validates the complete Core ML source
interface, compiles the exact `.mlmodelc`, runs two fixed
PyTorch-versus-Core-ML probes on CPU, refuses any categorical winner change or
maximum absolute logit error above `1e-4`, and records that evidence in the
manifest. The Swift runtime is correspondingly fixed to CPU-only inference;
calibration from PyTorch logits must not be combined with an unvalidated ANE
execution path. The manifest SHA binds every byte of one compiled directory; it
is an artifact-integrity identity, not a claim that separate Apple compiler
runs are byte-for-byte reproducible (compiler analytics metadata can differ).
Manifest v4 also requires the exact training-checkpoint digest and byte count,
checkpoint contract, selected architecture, and bound development-record
digest/sample/writer counts. Export refuses missing provenance or an
architecture mismatch, and the Swift runtime rejects a malformed provenance
record. These bindings make an artifact traceable; they do not make its source
corpus eligible or establish model quality.

Run the cross-runtime gate with that pinned environment to train and export
fresh synthetic dual-view, trajectory-only, and raster-only shadow models,
load every exact compiled artifact through the production Swift adapter,
execute inference, and decode its factor logits:

```sh
ICHART_RECOGNITION_PYTHON=/path/to/pinned/venv/bin/python \
  scripts/run_coreml_cross_runtime_gate.sh
```

Train a deterministic development-only checkpoint:

```sh
python3 -m ichart_recognition_ml train \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --manifest /protected/corpus/manifest.json \
  --development-selection-report /protected/runs/pilot-001-development-comparison/development_model_comparison.json \
  --model-identifier dual-view-pilot-001 \
  --output-dir /protected/runs/pilot-001
```

The current `chord-ink-dual-view-v2-layout-preserving` architecture retains an
8-bin temporal map and a 3x8 raster map before fusion. This prevents global
average pooling from making otherwise similar root, suffix, and slash-bass
glyphs positionless. Checkpoints use an exact v2 architecture binding and will
not load under a different architecture. For every active output head, each
development writer contributes the same total loss mass regardless of how many
attempts that writer supplied. Global weights are normalized once under a
versioned mini-batch contract; shuffled batches never renormalize away the
writer or class objective, and batch-size-weighted losses reconstruct the
global weighted loss. These are structural generalization safeguards, not
evidence of accuracy. Training also creates deterministic, same-writer
trajectory derivatives with whole-stroke order reversed and stroke direction
reversed while preserving the raster geometry; invalidated timing channels are
cleared. Every original capture receives one fixed share of its writer's loss
budget, and all derivatives divide that source share, so a multi-stroke sample
cannot gain influence merely by producing more variants. These transformations
exercise construction-order invariance but never increase a writer or
independent-sample count. The model still requires real writer-disjoint
development, calibration, and sealed cohorts.

`categorical_class_reweighting` is checkpoint-bound. `none` preserves the
writer-only objective. `categorical-inverse-frequency-v1` additionally
downweights common categorical factor labels while leaving independent
Bernoulli alteration bits writer-balanced. Neither mode is presumed superior:
use only the mode selected by the grouped development-writer comparison, and
never choose it from calibration or sealed results.

`model_architecture_id` is also checkpoint-bound. The training and checkpoint
loader support every architecture the comparison can select—dual-view,
trajectory-only, or raster-only—and reconstruct the exact matching model
family before accepting its weights. The common two-input Core ML interface is
preserved even when an ablation deliberately ignores one view.

Before freezing the architecture, compare the dual-view model against its
trajectory-only and raster-only ablations with grouped development-writer
cross-validation:

```sh
python3 -m ichart_recognition_ml compare-development-models \
  --records /protected/corpus/records.jsonl \
  --data-root /protected/corpus/features \
  --manifest /protected/corpus/manifest.json \
  --output-dir /protected/runs/pilot-001-development-comparison
```

The comparison requires at least four development writers and both notation
and adjudicated no-read supervision in every training fold. It compares every
raster-only, trajectory-only, and dual-view architecture under both the
writer-only and versioned categorical inverse-frequency objectives. It
balances whole writers across folds, averages held-out top-path accuracy by
writer and seed, and deliberately never reads calibration or sealed feature
bytes. Its selected candidate is development-only model-selection evidence,
never a calibration, promotion, or trust receipt. Pass the canonical report
itself to the subsequent `train` command. The loader verifies its exact schema,
corpus/writer/fold commitments, candidate coverage, writer-weighted aggregates,
winner, and frozen tie-break rule. Training derives the architecture, loss
treatment, optimization configuration, and final training seed from that
report. The first report-declared comparison seed is the frozen final-training
seed; a post-comparison seed override is rejected. Training binds the exact
report-byte SHA-256 into checkpoint v6 and Core ML manifest v4.
Conflicting copied flags are rejected. Omitting the report remains available
for synthetic or exploratory development runs, but the checkpoint and manifest
then explicitly say `unselected-development-training`; that path is not model-
selection evidence.

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

When the caller adds `--require-promotion-gate`, it must also pass the exact
canonical `--development-selection-report`. The evaluator revalidates that
report against the current records and requires its byte digest, selected
architecture, loss treatment, frozen final seed, and optimization
configuration to match the checkpoint. A copied metadata claim is not accepted
as model-selection evidence. The command remains descriptive and emits no
production gate receipt.

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

The export command derives training provenance from the loaded, corpus-bound
checkpoint. Callers cannot replace those fields with command-line assertions.
The emitted JSON status repeats the checkpoint, development-record, and
architecture identities so release automation can reconcile them with the
manifest before packaging.

`calibrate` and `evaluate --require-promotion-gate` deliberately refuse when the
bound eligible development rows do not include both notation and adjudicated
no-read supervision. The promotion-gate evaluation additionally refuses an
exploratory checkpoint that does not bind the exact frozen grouped
development-writer comparison report. Calibration also refuses unless its own
writer-disjoint role supplies both classes and the decoded observations contain
positive and negative candidate/no-read paths. No command silently falls back
to partial metadata, an in-sample split, unverified feature files, top-three
softmax renormalization, or a fabricated no-read claim. Temperature scaling is
defined as `joint-path-one-vs-rest-v1`: each decoded raw joint log probability
is converted to a binary logit, divided by temperature, and passed through
sigmoid without renormalizing surviving candidates.

## Customizable-model symbol research (not the production pipeline)

`research.personal_symbol_training` and `research.personal_symbol_expansion`
continue the local customizable visual model. They do not invoke another OCR
engine, ingest private corrections into shared training, or emit a production
manifest. Install the `training` extra for the pinned PyTorch/NumPy/Pillow
dependencies. Sources are provided explicitly, hash-checked, and kept outside
Git. No archive code is executed or extracted.

The fixed mixed-source and frozen-output-only comparisons, their data/license
limits, and the failed live-reader promotion decision are recorded in
[`personal-symbol-training-results-2026-09-28.md`](../docs/personal-symbol-training-results-2026-09-28.md).
The output-only experiment preserves the learned visual features and original
97 classifier rows while fitting five missing symbols, but new classes can
still cause substitutions. Its ranks are not calibrated confidence. These
research artifacts must not replace the default app bundle or bypass the
writer-separated full-chord promotion gates above.

`research.personal_local` and `research.personal_local_anchors` test local
personal corrections over that same frozen encoder, with training-only kernel
width and the existing public untaught-shape constraints. They do not change
the live reader or personal profiles. The small public-character improvement,
remaining regressions, unchanged recorded full-chord errors, and reproducible
evidence are documented in
[`personal-local-learning-results-2026-09-28.md`](../docs/personal-local-learning-results-2026-09-28.md).

`research.personal_head_distillation` tests updating the shared output layer
while freezing personal visual features, with a matched supervised control and
an old-reader preservation objective. Both fixed candidates failed the public
handwriting gate and remain research-only. See
[`personal-head-distillation-results-2026-09-28.md`](../docs/personal-head-distillation-results-2026-09-28.md)
for the separate populations, gains/harms, executable protocol and stop decision.

## Blind natural-ink annotation (engineering-only)

### Export a newly saved local development capture

With the whole-source capture build, use a blank **Simple Chord Sheet**, open
**My Handwriting → Saved Chart Test → Before corrections**, start capture, and
write a user-chosen natural complete-chord row in **Chords** at normal speed.
Do not render, confirm, transpose, change style, teach, or rewrite for a better
result. Wait for previews/source saving to settle, then **End without scoring**;
do not enter intended answers. Repeat in a blank **Rhythm Section Sheet** and
keep both source charts. This collects one-writer development evidence only;
independent blinded readers are a later accuracy gate, not required to start
collection.

After an authorized read-only copy of the local evaluation journal, extract one
ended run into a **new** private directory (Python 3.12, no training extra):

```sh
python3.12 -m ichart_recognition_ml.research.blind_ink_capture \
  --journal-json /protected/capture/evaluation-v1.json \
  --run-id <saved-run-UUID> \
  --output-dir /protected/capture/new-source-export
```

Extraction requires `sourceCaptureState: complete`, matching request/revision,
an exhaustive visible-fragment partition and recognition map, exact target
record inputs, and consistent frozen-profile support metadata. Pending captures
and legacy runs without full source evidence fail before output writes. The
stored canonical `trajectory.json` bytes are unchanged: no thumbnails, geometry
normalization, intended answers, predictions, model calls or feature generation
are used to repair missing evidence. Existing blind-packet limits still apply:
4 MiB, 256 strokes, 8,192 points per stroke and 32,768 total points; larger valid
app snapshots are refused, never trimmed.

The command prints `sourcePacketSHA256` for the existing `prepare-ownership`
command below. It also saves `source-envelope.json`, `capture-provenance.json`
and a receipt-last `prepared-receipt.json`, exclusively with private permissions.
Keep the envelope/provenance private: they retain layout/index bindings and the
frozen profile. The retained PencilKit bytes are **color-normalized recognition
input**, not raw pre-normalization drawing archival. Writer identity, consent,
freshness and accuracy are not verified; `trainingEligible` remains false.
Distribute only the separately prepared blind reviewer HTML, not this export
directory or the original journal.

### Prepare independent annotation later

`research.blind_ink_annotation` and `research.blind_ink_tool` provide an offline
review path for separating ownership errors from isolated-symbol errors. They
do not fit a model, call a recognizer, teach a personal profile, or make records
training/evaluation eligible. No private chart, public-writer query, or reserved
test population is read implicitly.

The coordinator supplies one exact `ink-trajectory-packet-v1` file and its
expected SHA-256. The ownership reviewer page contains only that prepared ink,
opaque bindings and neutral instructions. Do not distribute Study outcomes,
capture ordinals, filenames containing answers, profiles, intended chords,
recognizer candidates or other reviews alongside it.

From this directory with Python 3.12 (no training extra required):

```sh
python3.12 -m ichart_recognition_ml.research.blind_ink_tool prepare-ownership \
  --trajectory-json /protected/capture/trajectory.json \
  --expected-source-sha256 <original-canonical-packet-sha256> \
  --output-dir /protected/review/new-ownership-job
```

Give **only** `ownership-review.html` to two separately verified reviewers. Each
uses their assigned pseudonymous hash, groups whole original strokes, attests
to blind review and downloads a review JSON. Groups cover every original packet
index exactly once. A stroke shared by multiple symbols is nonseparable under
this whole-stroke contract: record unresolved rather than split points. Empty
strokes are retained and force unresolved ownership. Duplicate points, signed
zero, timing state/bits and acquisition order are not repaired or discarded.
Invalid/nonenclosing bounds or unrepresentable global extents fail explicitly.

```sh
python3.12 -m ichart_recognition_ml.research.blind_ink_tool freeze-ownership \
  --ownership-packet /protected/review/new-ownership-job/ownership-packet.json \
  --first-review /protected/review/first.json \
  --second-review /protected/review/second.json \
  --writer-id-hash <verified-writer-hash> \
  --output-dir /protected/review/new-ownership-freeze
```

Agreement can freeze a partition; disagreement stays unresolved unless a third,
distinct blind adjudicator supplies `--adjudication-review`. Review hashes and
their complete evidence are retained and recomputed before downstream use.
Canonical group sorting is unordered ownership equality/job bookkeeping, **not
an inferred symbol or chord reading order**.

```sh
python3.12 -m ichart_recognition_ml.research.blind_ink_tool prepare-identity \
  --ownership-packet /protected/review/new-ownership-job/ownership-packet.json \
  --ownership-receipt /protected/review/new-ownership-freeze/ownership-receipt.json \
  --output-dir /protected/review/new-isolated-jobs
```

Unresolved ownership blocks this command. Each generated HTML shows one exact
isolated source group. Identity reviewers must not be the writer, ownership
reviewers/adjudicator, or people exposed to the full sample. Distribute jobs in
opaque shuffled order, **not** sibling jobs or the whole directory;
that assignment/exposure control remains the coordinator's responsibility.
Ownership labels cannot be changed from the identity stage. Preserve exact,
case-sensitive single-codepoint spelling, or record human ambiguity/no-read;
there are no suggested labels or whole-chord canonicalization.

```sh
python3.12 -m ichart_recognition_ml.research.blind_ink_tool freeze-identity \
  --identity-packet /protected/review/new-isolated-jobs/identity-<opaque-hash>.json \
  --ownership-packet /protected/review/new-ownership-job/ownership-packet.json \
  --ownership-receipt /protected/review/new-ownership-freeze/ownership-receipt.json \
  --first-review /protected/review/glyph-first.json \
  --second-review /protected/review/glyph-second.json \
  --output-dir /protected/review/new-identity-freeze
```

The actual parent receipt supplies writer and ownership-role exclusions; callers
cannot substitute a different role list. Disagreement remains human-ambiguous
unless a third eligible adjudicator reviews the same isolated packet.

Outputs are exclusively created in a new directory; nothing is overwritten.
Publication is receipt-last, not an atomic whole-directory operation: an
interrupted write may leave a partial directory. Do not use a directory without
a complete validated receipt. `verify-bundle --bundle-dir <directory>` checks
every recorded artifact digest and refuses missing/extra/modified files.
Browser pages have no external assets or network calls; numeric display fitting
does not rewrite the stored source trajectory.

Hashes and checked attestations prove only mechanical consistency, not actual
human identities, independence, consent, annotation correctness, or a fresh
writer split. All bundle receipts retain `trainingEligible: false`. Research
consent/provenance, independent role verification, label-blind assignment,
writer-disjoint natural captures in both chart styles, and a separate sealed
evaluation gate are still required. Synthetic flow tests are infrastructure
evidence, not recognition-quality evidence.

Verification on 2026-09-30: 51 focused Python/JavaScript/CLI and existing packet/
feature regression tests executed and passed, with no skips. The native in-app
browser visually verified grouping, ungrouping, isolated Unicode entry and
stale-export invalidation on synthetic ink. Browser-visible ownership and glyph
exports were independently rebound through the Python contracts. A completed
browser download was not observed; the corrected UI says "Download requested"
and offers a canonical copyable export. No model inference, natural-handwriting
accuracy evaluation, app build/install, profile teaching or release occurred.

## Blind paired ML evaluation bridge (engineering-only)

`PersonalInkBlindPredictionFreeze` freezes the current Swift shared/personal
glyph hypotheses from one exact canonical prepared trajectory. It accepts no
symbol truth, intended chord or expected-label list. Both automatic and supplied
arms query the existing `readSuppliedOriginalGroups` path with original stroke
objects. Automatic grouping retains the current `losslessSourceV2` construction;
no new grouping model, chord composition, whole-chord rescue or teaching runs.
Byte/stroke/point budgets and complete supplied partitions are checked before
query encoding. Exact profile equality is checked before, between and after
arms; disabled/stale profiles and technical encoder failures fail the export.
Representational invalid ink retains an explicit complete no-read arm rather
than partially exporting recognized groups. SHA commitments bind source,
ownership receipt, profile, encoder runtime and code. Callers must actually
verify runtime/code commitments and preserve input artifacts; hashes are not
authentication or proof that predictions preceded label exposure.

`research.blind_ink_evaluation` joins the frozen hypotheses to recomputed
ownership and identity receipts by exact original-index sets, not labels,
spatial proximity or min-index reading order. Ownership agreement, conditional
shared identity, conditional personal identity, gains and harms are separate
counts. Identity is case-sensitive single-codepoint spelling, not semantic
chord equivalence. Automatic identity is attributed only to exact matched
owners; both the matched-owner and all-resolved-owner denominators are recorded.
Unresolved ownership remains in query counts. Every resolved owner requires an
identity freeze, including human ambiguity/no-read; missing/duplicate evidence
fails rather than silently excluding it. Model invalid-ink/no-read is not a
correct read. A zero denominator produces null, never a perfect score.

From this directory:

```sh
python3.12 -m ichart_recognition_ml.research.blind_ink_evaluation \
  --manifest /protected/evaluation/blind-evaluation-manifest.json \
  --output-dir /protected/evaluation/new-paired-report
```

The manifest is canonical JSON with version `blind-ink-evaluation-manifest-v1`
and a `queries` array (1–512 records). Each record explicitly supplies paths
`prediction`, `ownershipPacket`, `ownershipReceipt`; `identityArtifacts` is an
array of `{ "packet": "...", "receipt": "..." }`. Paths resolve relative to
the manifest. `metadata` contains `writerIDHash`, `querySessionIDHash`,
`supportSessionIDHashes`, `chartStyle` (`simple-chord-sheet` or
`rhythm-section-sheet`) and `evidenceClass` (`synthetic-contract-test` or
`development-capture`). Writer/session identifiers are lowercase SHA-256
commitments. Support sessions must be unique and disjoint from the query
session, and writer identity must match the ownership receipt. These declarations
do not themselves prove provenance or that a support profile contains only those
sessions; that requires a separately verified capture/lesson ledger.

One report requires one runtime/code/encoder and one profile/support-session
set per writer; exact duplicate source packets are refused. Rates retain their
numerators and denominators, and counts are sliced by declared writer, query
session, chart style and evidence class. Output uses an exclusive new directory
and receipt-last publication (not atomic directory publication). Preserve the
manifest, every referenced artifact and `evaluation-receipt.json`; an interrupted
directory without its receipt is not a completed evaluation.

This is not a training, threshold-selection or sealed-evaluation gate. Report
flags remain `trainingEligible: false`, `newWriterAccuracyVerified: false`,
`fullChordAccuracyMeasured: false`, `metadataProvenanceVerified: false` and
`predictionChronologyVerified: false`. No annotation or hypothesis is accepted
into a personal profile or chart. Independent real reviewers, consent/source
provenance, verified support/query session separation, fresh writer-disjoint
natural captures in both styles and separate full-chord/order evaluation remain
required before recognition-quality or ship claims.

## Fixed, out-of-writer support retrieval (research only)

`research.personal_support_crossfit` generates public training features from two
temporary 16-writer encoders; neither fits the writers whose features it exports.
`research.personal_support_retrieval` fits one class-equivariant scalar relation
and gate on those features. The operational full-32 encoder, app and profiles
stay unchanged. No raw learned feature-axis or codepoint embedding is used.

The recipe and scope are fixed in
`docs/personal-support-retrieval-protocol-2026-10-01.md`. Run from this directory:

```sh
python3.12 -m ichart_recognition_ml.research.personal_support_crossfit \
  --source /protected/public/ujipenchars2.txt --output /protected/new/crossfit
python3.12 -m ichart_recognition_ml.research.personal_support_retrieval \
  --crossfit /protected/new/crossfit --output /protected/new/learner
```

The evaluator has separate `prepare`, `predict` and `score` commands. `prepare`
binds the pinned prior CE packet, learner directory and protocol; `predict` adds
that commitment and writes exclusive prediction bytes. Only `score` receives
truth/copy paths, plus the committed prediction SHA and pinned prior packet.
Complete97 probability/rank outputs and fixed raw/no-copy denominators are
required; aliases, parser rescue, rank restriction and query-selected tuning are
not part of the route. Parent data/code bindings are checked before and after
fitting, and the learner loader validates the saved parent-binding artifact.

The executed candidate **failed**: all 1,552 top-one labels were identical to
generic. Zero gains/harms is not improved recognition. Do not export, promote,
retune or consume reserved writers to rescue it. The full result and artifact
bindings are in `docs/personal-support-retrieval-results-2026-10-01.md`.

## Training-only setup-signal audit and internal role planner

`research.personal_support_signal_audit` diagnoses the fixed support-cache
tradeoff without fitting a candidate or selecting an alpha. It accepts only the
pinned training crossfit bundle, retains every source-only exclusion, freezes
full97 generic/cache predictions before explicit supervised-training scoring,
and distinguishes repeated task exposures from distinct source/ink hashes.

```sh
python3.12 -m ichart_recognition_ml.research.personal_support_signal_audit \
  --crossfit /protected/preserved/crossfit --output /protected/new/audit.json
```

The executed audit found useful taught-example signal, but every tested nonzero
uniform weight introduced untaught errors. It is not a safe personalization
setting; see `docs/personal-support-signal-results-2026-10-01.md`.
`research.personal_support_inner_roles.inner_roles(receipt, rows)` returns a
source-only A16 encoder / B8 meta-fit / B8 internal-validation manifest using
fitA only, with exact parent artifact and code bindings. It requires a validated
`load_crossfit_bundle` parent. Its `freshValidation=false` is intentional:
disjoint learned stages do not turn previously used rows into fresh evidence.
Neither tool fits, advances, exports or activates a recognition model.

## Conditional setup trust (fixed research experiment, rejected)

`research.personal_conditional_support_trust` learns a fourteen-scalar gate
between the frozen generic encoder and labeled-example cache. Only the gate
learns: no alternate OCR engine, codepoint embeddings, raw feature-axis weights
or writer-specific rules. Source-only A16/B8/B8 roles separate encoder fitting,
gate fitting and internal validation; previously used rows remain internal
reuse evidence, not fresh accuracy.

The executed fixed fit completed 960 updates. Its separately committed full97
predictions were scored before any recipe revision. K10 corrected 29 and
regressed 51; K21 corrected 30 and regressed 23. Untaught harms were 50/20.
It failed the predeclared writer/task/untaught screen and remains offline.
Do not retune on these queries, consume reserved writers to rescue it, or
export/activate the rejected candidate.

The evaluator exposes separate `prepare`, `predict` and `score` operations:
prediction decodes no query-label metadata, and scoring requires the exact
prediction SHA before joining query truth. Source-only no-copy outcomes drive
the screen; raw scheduled results, invalid outputs, every copy exclusion and
unavailable setup shape remain explicit. The final combined gate executed
69 warning-clean tests. Independent NumPy reconstruction matched all 3,104
prediction rows and reproduced the rejection. Full bindings and limitations:
`docs/personal-conditional-support-trust-results-2026-10-01.md`.

## Matched training risk and all-class next core (research only)

`research.personal_support_training_risk` diagnoses the exact rejected final
gate and its original seed-41 initialization on the same retained training
plans, without another fit or validation inference. Full97 distribution
digests are committed before a separate supervised scorer joins targets.
Independent arithmetic reconciliation confirms lower balanced NLL but final
1,863 gain / 2,072 harm exposures, including 2,037 untaught harms. These are
repeated training exposures, not independent samples or generalization.
Bindings: `docs/personal-support-training-risk-results-2026-10-01.md`.

`research.personal_centroid_transport` uses lesson residuals to transport all97
class centroids with a shared scalar scorer and exact empty-support identity.
Its objective includes baseline-margin preservation and an unrelated-support
control. `research.personal_training_centroids` regenerated all3,104 A16 raw
embeddings with the pinned fitA encoder, never the fitB-generated retained A16
features. `research.personal_centroid_transport_experiment` then completed eight
seven-fit/one-held-out B8 folds, 6,720 actual updates, and separately frozen
full97 prediction/scoring steps. It has no final-B8-fit operation.

The fixed experiment **failed**: both app-domain teaching catalogs produced
zero corrections, zero regressions and no improvement over unrelated-writer
support. All top-one decisions remained generic; probabilities changed slightly.
Independent reconstruction matched all9,312 finite full97 probability vectors,
source-copy ledgers, score groups, checkpoint bindings and rejection. The focused
27-test gate is engineering evidence, not fresh chord accuracy. Keep the recipe
offline and rejected without retuning or reserved-writer rescue. Details and
durable artifact bindings: `docs/personal-centroid-transport-results-2026-10-01.md`.

## Additive writer signal diagnostic (training geometry only)

`research.personal_training_residual_signal` computes one fixed diagnostic
from pinned fitA A16 unit embeddings, without training or model inference.
Focal-excluding unnormalized means, opposite-session untaught queries, all15
named unrelated controls and a source-copy ledger are committed before geometry.
All 5,216 scheduled records were retained; 5,192 were no-copy eligible. The own
support mean beats unrelated means but loses to zero correction in both tasks,
so this single additive statistic is rejected unchanged. Independent arithmetic
matched every record and aggregate exactly; 17 warning-clean synthetic tests
are engineering evidence only. Details:
`docs/personal-training-residual-signal-results-2026-10-01.md`.

## BHMSDS auxiliary intake (no model use yet)

`research.bhmsds_source_intake` validates one commit/SHA-pinned public archive,
preserves every raw/native-pixel identity and its original MIT notice, and
reports duplicate/invalid rows without silently discarding them. All 27,000
source rasters decoded and independently reconciled. Writer/session IDs and
canonical mappings remain unknown; no trajectories or writer split are
invented. The README `*` versus filename `dot` mismatch is explicit. Source
labels include plus/slash, but no model adapter, fit or recognition improvement
is established. See `docs/personal-bhmsds-source-intake-2026-10-01.md`.

## HASYv2 auxiliary intake (source quality only)

`research.hasy_source_intake` reads the checksum-pinned official tar in place,
keeps every native label and raster, and audits all 369 classes/168,233 rows.
Independent reconstruction matched every manifest identity/raw/native-pixel
hash and all duplicate/fold ledgers. The README's 168236 count discrepancy,
502 exact-image duplicate groups (132 cross-label), and pixel copies crossing
all 10 path-disjoint folds are explicit. Writer IDs are unreliable; canonical
mapping and shipping/model license clearance remain unset. This is auxiliary
research, not new-writer evidence; this full-source intake did not adapt or fit
a model. Earlier September 28 mapped-symbol continuation and frozen-head HASY
experiments did run and were rejected; see
[`symbol-training results`](../docs/personal-symbol-training-results-2026-09-28.md).
The focused
16-test intake gate and combined 33-test gate are engineering evidence only.
Details: `docs/personal-hasy-source-intake-results-2026-10-01.md`.

## Fixed native-shape auxiliary transfer (completed, rejected)

`research.hasy_native_training_source` prepares all 369 unaliased native classes
with fixed native/adapted conflict filtering and salted balancing. The completed
source has 30,451 distinct selected images and 1,293 repeated exposures; no
observed trajectories or reliable writer IDs are invented. The separate source
verification reproduced every selected normalized raster and target.

`research.personal_native_shape_transfer` executed a matched UJI97 replay versus
HASY369 auxiliary pretrain, discarded both heads, reset the exact original97
head and ran the same UJI target fit: 2,200 updates per arm. The separate
`research.personal_native_shape_transfer_evaluation` froze predictions before
truth, retained all 3,104 attempts and reported all classes/writers/strata.
The 28-test warning-clean engineering gate passed, but the actual development
candidate failed writer/untaught safety. **Do not promote or retune this recipe.**
No app/profile/ink changed; reserved writers remain sealed. Dataset/model rights
remain unresolved for distribution, and no fresh natural-chord accuracy was
measured. See the
[`frozen protocol`](../docs/personal-native-shape-transfer-protocol-2026-10-01.md)
and [`results`](../docs/personal-native-shape-transfer-results-2026-10-01.md).
