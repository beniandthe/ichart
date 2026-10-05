# Whole-chord factor experiment — final results

## Decision

**Reject the fixed recipe.** Do not promote its checkpoint, decoder, or layout
recipe into the app. This is an offline result on a synthetic whole-chord bridge;
it is not natural-chord accuracy, general recognition quality, personalized
learning benefit, trust calibration, application-runtime parity, or shipping
evidence.

The prespecified screen required positive primary paired net movement, zero input
failures, and no writer regression in either the primary or reversed
acquisition-order stress arm.
The aggregate conditions passed, but the writer guard failed: `trn_UJI_W08`
fell from **288/336** correct with the oracle-owner atomic control to **277/336**
with the factor model, a net loss of **11**. No post-result threshold, label,
writer, or layout adjustment was made.

## Frozen original-layout comparison

Each acquisition order contains 2,688 derived rows: eight observed development
writers, 168 synthetic chord labels, and two sessions. The forward and reverse
rows reuse the same underlying atom sources and are not independent samples.

| Acquisition order | Factor correct | Atomic control correct | Gains | Harms | Net |
| --- | ---: | ---: | ---: | ---: | ---: |
| Forward owner blocks | 2,524 / 2,688 | 1,866 / 2,688 | 701 | 43 | +658 |
| Reverse owner blocks | 2,506 / 2,688 | 1,866 / 2,688 | 687 | 47 | +640 |

The descriptive pooled count is **5,030/5,376**, but it must not be reported as
an independent pooled accuracy: the paired acquisition variants are derived from
the same source atoms. Both arms had zero retained input failures. The fixed
recipe nevertheless fails because its reversed-order writer guard is false.

## Prespecified layout probes

Both probes used the unchanged trained checkpoint and decoder. They changed only
the synthetic assembly geometry and were scored against each row's frozen
original-layout factor choice.

| Probe | Order | Probe correct | Original correct | Gains | Harms | Net |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Equal atom size | Forward | 806 / 2,688 | 2,524 / 2,688 | 22 | 1,740 | -1,718 |
| Equal atom size | Reverse | 831 / 2,688 | 2,506 / 2,688 | 24 | 1,699 | -1,675 |
| Zero atom gap | Forward | 867 / 2,688 | 2,524 / 2,688 | 26 | 1,683 | -1,657 |
| Zero atom gap | Reverse | 866 / 2,688 | 2,506 / 2,688 | 27 | 1,667 | -1,640 |

There were zero probe input failures. For each probe, every one of the eight
writers lost correct choices in both acquisition orders—all 16 writer/order cells
per probe were negative. These results show that this pipeline is highly sensitive
to the artificial assembly geometry. They do not isolate the learned weights as
the sole cause and do not reject all whole-input ML approaches.

## Evidence bindings

- Factor protocol SHA-256:
  `5424e847dc987b421f09de9f88b5d8b329553d8172d5b2d32e6a96e440265fd4`.
- Layout-probe protocol SHA-256:
  `210f6f85f01ef261d72d8eeeadc4404cc0609e850c604dd9465a41e9f007044e`.
- Pre-fit gate: **46/46** tests, zero failures/errors/skips; receipt SHA-256
  `a646028c288d66245d408587ef48bde3775a74e8acde5720a74db7c831f9232a`.
- Pre-layout gate: **7/7** tests, zero failures/errors/skips; receipt SHA-256
  `56ec0fdc4d98460f8f80b62596ac526b8d04a7c1842839f59472a4ac1874a361`.
- Frozen factor packet: 5,376 rows, SHA-256
  `c0176c26ba150364012e451165dde40f1db4e2aa537828ab35ad6284143e577e`.
- Frozen layout packet: 10,752 rows, SHA-256
  `9551d50e9fb52dafada63b14c68646f7db3a9d641570fd5634651eee2b49314b`.
- Original paired score SHA-256:
  `d1c2cb3b6bf6ebea8254529a9a4d0d6e8a77f7f3269643bb7ef0b7e7ff06e028`.
- Layout score SHA-256:
  `0ecc39c0ce56387ebba424a480459e4cfc7c11316728ef5162b7b5c0d8c00b98`.
- Independent arithmetic receipt SHA-256:
  `d9b84c98157b9c1e21ef2ae4e8b26f0c0eca5c0392f021d3b64f1b6eaba0ffd4`.
  It independently reconciles the published counts and bindings without loading
  the model, rerunning inference, or reading the raw prediction packets.

An isolated performance-only check found that an immutable cached grammar
topology reproduced all three ordered candidate strings and exact floating scores
for all **16,128** factor/probe rows: **48,384** exact candidate comparisons and
**16,128** exact first-choice comparisons, with no epsilon. Its receipt SHA-256 is
`961fd4193e332ccf8dce19baf03389c9c3574531a50bf53d6710b9f09d5bfa94`.
This establishes feasibility for a later decoder-performance change only; no
decoder implementation was changed. The initial bare-runtime NumPy import failure
and successful retry are retained in
`decode-topology-cache-runtime-attempts.txt` rather than omitted.

## Interpretation and next step

The experiment covered a narrow artificial family assembled from isolated source
atoms. Explicit-major, diminished, augmented, suspended, altered, half-diminished,
repeat, slash-bass, sharp-root, plus, slash, half-diminished glyph, triangle and
natural-symbol forms were absent. These remain requirements of the app, not
removed functionality. Real coarticulation, spacing and stroke timing were not
represented. It did not test natural whole-chord writing,
fresh writers, private user ink, the app's automatic grouping path, no-read
selection, or on-device parity.

The next defensible step is a writer-separated, broadly varied **natural
whole-chord** training and evaluation source with real acquisition geometry and
timing, while keeping unsupported chord families explicit. It must be frozen
before evaluation and must not introduce a `W08`-specific correction, tune on
private ink, or reuse observed answers to select a recipe.

The experiment is now permanently preserved at
`/Users/benirossman/.local/share/ichart/recognition-development/whole-chord-factor-20261002.K5sEY4`.
The exclusive copy and an independent read-only audit verified all **118 content
files / 322,166,609 bytes**, with no extras, symlinks or source changes. Its tree
SHA-256 is `ff2bfba1f1be68780935e68229a0eda08f3ca09446cba207f17ddba17a8f1d34`;
`preservation-manifest.json` SHA-256 is
`3841c82d01044b77196c1ea0480a91d0d9af73d817e042405f4e4296238c0230`.
The separate audit receipt is
`/Users/benirossman/.local/share/ichart/recognition-development/whole-chord-factor-20261002.K5sEY4-preservation-audit.json`, SHA-256
`551bbad6443921450ee8d6eb743eb2fd4467f283341b80bad15c7a9b594cd36c`.
The preserved result/execution document copies record their pre-preservation
state; this confirmation was appended afterward without mutating the preserved
tree. The manifest itself is an additional file, not part of the content count.

No app, profile, production model, build, commit, push, or deployment changed as
part of this experiment.
