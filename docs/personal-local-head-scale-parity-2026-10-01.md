# Fixed local-ML head — operational-scale arithmetic gate

## Outcome and scope

The comparison-only local RBF/untaught-anchor head matches its Python reference
at the app's actual feature/vocabulary dimensions. The focused iOS Simulator
gate executed **9 tests: 9 passed, 0 failed, 0 skipped**. Twelve synthetic queries
retained all 98 competitors, so every rank order and all 1,176 score cells were
compared. The overall maximum score error was `4.440892098500626e-16`, below the
frozen `1e-4` tolerance.

This is mathematical-head evidence. No handwriting, profile, source chart,
encoder inference, teaching, live routing, acceptance, render, device install,
production change, or release enters the new test. Synthetic anchors and
features are unit vectors, not an encoder's actual embeddings or learned anchor
values. It does not establish recognition accuracy or safety across writers.

Branch: `codex/recognition-generalization-reset`.
HEAD: `160aa31594903508e241802e21ca83ec447de849`.
The preexisting dirty work was preserved. The rejected construction candidate
remains removed; native reader/grouper bytes still match the tested v31 source.

## Frozen cases and full denominator

The unchanged pinned model manifest declares 128 features and 97 unique ordered
shared labels. Both synthetic cases add one explicitly taught novel label.
Width remains `0.16684838059285878`; regularization remains `0.1`. No parameter,
class, expected choice, confidence threshold, or recognition rule was changed.

| Case | Glyph lessons | Distinct lesson labels | Untaught anchors | Fit points | Features | Competitors | Queries |
| --- | --- | --- | --- | --- | --- | --- | --- |
| sparse16 | 16 | 13 | 85 | 101 | 128 | 98 | 6 |
| maximum192 | 192 | 1 | 97 | 289 | 128 | 98 | 6 |

The sparse case uses twelve public vocabulary labels plus a novel symbol and
three duplicate labels. The maximum case teaches only the novel symbol, leaving
every shared class anchored; it tests the supported 192-lesson budget with this
operational vocabulary. This is not the separate 512-label theoretical limit.
Queries are exact/near lessons, an untaught synthetic anchor, a novel lesson,
an opposite feature, and independent synthetic unit noise. No query truth or
private fit data selects a prediction.

The test validates strict schemas and byte commitments, all unit/finite features,
all normalized full-vocabulary bases, exact recomputed support/anchor counts,
all complete rankings, immutable fixture bytes, and the fixed head contract.
The original eight head tests also ran, including the independent four-feature
Python fixture. Fit and each query are timed immediately around the head call;
XCTest comparisons are outside those timing intervals.

## Single-run cost diagnostic, not an iPad benchmark

Xcode `26.6 (17F113)`, Debug configuration, ARM64 iOS Simulator
`0D3454BE-1A21-4910-8FD6-FFD3EB43E908`, iPad (A16) simulated model, iOS `26.5`.
The test compiler command includes `-O`; these are Mac-hosted optimized results,
not physical-iPad performance or calibrated latency percentiles.

| Case | Swift fit ms | Six Swift queries total ms | Maximum score error |
| --- | --- | --- | --- |
| sparse16 | 1.977625 | 0.141875 | 4.440892098500626e-16 |
| maximum192 | 10.799958 | 0.319333 | 8.326672684688674e-17 |

All six per-query durations are preserved in the test log. There was one measured
fit per case, no timing acceptance threshold, no warm-up/percentile study, and no
Core ML rasterization/load/prediction, memory, energy, or Pencil/UI cost measure.
These timings cannot justify a live integration or imply that ink lag is fixed.

## Commitments and preservation

Local evidence root: `/private/tmp/iChartLocalHeadScale-20261001.FsyNlk`.

- Fixture (1,363,014 bytes):
  `dee6122a950d69fa103b709c4339f6064b77030b3477d2e5a5eefb263302f0a4`.
- Deterministic generator, seed 1729:
  `b123e866500216df34e3532a2d004acfedfa07c203ce485760581b966bcc1a0c`.
- Unchanged local head:
  `364aef40aae7d8e4ae373abe3779071ac85b7395f82413cd3e72c800a2d1ef5f`.
- New isolated scale test:
  `ee9a5067169a532838bd0dfeb093f1def39ea38d6095bb453c3b7da060989cfa`.
- Pinned public vocabulary/model manifest:
  `d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1`.

The generator binds and rechecks the four exact Python reference sources before
writing a new immutable fixture. The fixture, generator, reference code, Swift
sources, log and xcresult are retained separately from the natural-ink evidence.
The test source was added through XcodeGen project generation, not a hand-edited
Xcode project. No recognition code or fit algorithm changed in this pass.

## Remaining operational and quality gates

The pinned Core ML package metadata and existing loader really declare FLOAT32
`inkRaster [1,1,96,256]` → `personalEmbedding [1,128]` and `genericLogits [1,97]`.
The loader pins package/manifest/public-anchor hashes and uses the app rasterizer
and CPU-only inference. Static metadata is not a fresh encoder-parity execution.

The historical all-1,552 public encoder/linear-anchor parity packet and expected
report are currently missing from their documented temporary roots. A bounded
persistent-cache lookup did not recover them. A later grouped-identity report
is not a substitute: it lacks original trajectories plus complete embedding and
logit arrays. The historical result therefore cannot be presented as a fresh
current-runtime gate. Regenerated/restored public fixtures must be independently
bound before that gate runs; the existing anchored test also needs stronger
packet-byte/metadata/raster commitments before an arbitrary compatible packet
could safely be accepted.

The separate offline local-head/profile/encoder comparison addition is still
pending user approval after its permission rejection. No attempt was made to
work around that rejection. After permission, the real encoder fit/query seam,
exact immutable profile/lesson projection, complete fixed-first outputs, and
source-owner/identity receipts still need verification. The natural-ink candidate
must demonstrate paired gains without untaught-symbol or complete-chord harms
before promotion. Physical-iPad latency and genuinely fresh independently
reviewed handwriting in both styles remain separate uncompleted gates.
