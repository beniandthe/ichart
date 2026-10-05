# Same-label handwriting source comparison

## Current outcome

The candidate fails the predeclared advancement screen in both writer folds,
both with and without exact-copy exclusions. It gains 16 correct UJI readings
in one fold but loses three in the other, and introduces new wrong readings in
both. This source-substitution recipe is not promoted. It establishes neither
fresh chord accuracy nor personal-learning benefit. The live reader, model
resources, charts, ink and profiles have not changed during this experiment.

Preparation retained 2,405 new public HWRT training drawings across all 35
literal-overlap classes and excluded 34 records. Both candidate-only fits and
the prediction/scoring commands completed successfully. The unchanged control
was reused. These are fixed public-development comparisons, not fresh user
tests or shipping evidence.

The comparison follows the frozen
`personal-same-label-transfer-protocol-2026-10-03.md`, SHA256
`cbab15675ed16698c0a9cfb32f420df1ef54c80bd6054cd034b793f9ba713061`.
It was recorded before inspecting the new encoded collision results or
selecting eligibility. The candidate substitutes same-label training drawings
for repeated UJI exposures; the control architecture, initialization, targets,
optimizer, augmentation and update budget remain fixed. The existing frozen
102-way control can be reused rather than fitted again.

## Input and eligibility evidence

All 2,439 retained literal-training trajectories encoded successfully using
the existing Python raster adapter. Independent reconciliation checked every
new Float32 plane, pixel hash, model-plane hash and normalized-coordinate
fingerprint. It also checked the 10,073 prior occupancy planes against their
pinned pixel hashes and the exact Float32 `uint8 / 255` mapping. It did not
recompute the old field file's whole-file hash or inspect its auxiliary planes.

There are no new-to-prior raster or normalized-geometry collisions. The only
new-only raster collision is one nine-record, same-label `-` group. There are
no new-only normalized-geometry collisions. The eight-decimal normalized
fingerprint is a conservative copy check, not byte-exact trajectory equality.

The fixed eligibility graph contains 2,431 components: 2,430 singletons and
the nine-record group. Exactly 26 components, comprising 34 records, are
excluded by the predeclared HASY pixel-duplicate-path rule. The nine-record
group is among those excluded components. No additional class-conflict or
prior-input exclusion occurs. All 35 classes remain nonempty; the smallest
retained class has 43 drawings. Every original source record is preserved.

Eligibility uses only new training labels, input fingerprints and the pinned
HASY duplicate ledger, never prior-row labels, predictions or held-out answers.
The published selected IDs, reasons, representatives, components and counts
have been independently audited against the exact receipt. The root executed
seven focused eligibility tests with warnings treated as errors: all passed,
none skipped. The earlier raster-adapter gate passed six tests.

One initial CLI invocation rejected a relative protocol path before creating
output. Retrying with its exact absolute path succeeded. No code, source,
policy or exclusion rule changed between invocations.

## Local artifacts

Preparation directory:
`/private/tmp/iChartLiteralRaster-20261003.JuSqfQ`.
Its verified data, eligibility and independent reconstruction artifacts are
also preserved in
`/Users/benirossman/.local/share/ichart/recognition-development/same-label-transfer-20261003.JuSqfQ`.
The initial archive copy was compared recursively with `diff -qr`, exit 0.

- Encoded data receipt:
  `37c49925e8aff8774bf46c6e7b5e6a1686d68ce6bad37b1c29f36b63cac8e6b5`.
- New raster tensor:
  `ef8248ebab5f399e8da50c3f870ff840822229dd4d423ea7dd11af7ae9a6549e`.
- Encoded metadata:
  `a9ac2321281fd6ae32a9c81eed41c11e8448cc8fc9f58b74f0bcd189a0b9cdc1`.
- Independent raster reconciliation:
  `23351bda9060343261d29738cd0cd6a15a0c48ef51a1a599a19bd13f54173da0`.
- Eligibility receipt:
  `f1bb67bb5010c0b724c8b53b9c9de7d7b1caae380c398c1ce3021b1f2a0d8f3f`.
- Independent eligibility reconstruction:
  `50af088fd7d8c4d9570534bf7b205969b84315bce6662c16c9ea29f3c78be6c4`.

The exact eligibility-receipt hash is the fitting boundary for this run.
General-purpose loader hardening is not substituted for checking this actual
immutable artifact. Public source writer identity remains unestablished; the
HASY and HWRT records are not independent datasets. This preparation does not
prove Swift/Core ML parity, fresh handwriting accuracy or shipping eligibility.

## Evaluation implementation checks

The new candidate-only evaluator reuses the exact frozen 102-way control
vectors and the unchanged control decoding policy for both arms. It records
the shared input-only copy mask in an exclusive manifest before the first
candidate forward call, then commits complete vectors or explicit failures
before the separate scorer opens query truth. The manifest is a hash-bound
sibling artifact, so a byte-identical archive remains independently readable
after a temporary directory expires.

The root ran all six focused evaluator tests with every Python warning treated
as an error: six passed, none failed or skipped. Independent code review found
no experimental-validity blocker. These tests cover pipeline contracts and
synthetic arithmetic; they are not model accuracy measurements.

Evaluator SHA256:
`ee28e554be6d0a785098df96c890f49340483341964f8f27638ab556e946b82b`.
Evaluator test SHA256:
`34ec150035dd5991778081ab57433ec8c5f1a6776bfdeaad795b9a2678849736`.

## Fixed fit execution

The root's combined warning-clean gate executed 23 unique tests: seven
eligibility, ten trainer and six evaluator cases. All passed, with zero skips.
The trainer cases include two actual synthetic gradient updates, unchanged
input checks, fresh initialization, full schedule coverage, replayed affine
draws and failure retention. Independent code review found no protocol blocker.

Trainer SHA256:
`5b8caf4961531f402486ef72f0cd036501f384ad987f0e9ee073f9f1e733911c`.
Trainer test SHA256:
`99e6b7940c2c4fed1200d44796fa319c3a328878d6b95664c2fc0e7dda1464db`.
Combined test log SHA256:
`e91143986f3e3a6ffd693e42c94b5b7c48e5acf60e48ca5116c730eda7b38f75`.

The completed two-fold candidate-only process is preserved under
`/private/tmp/iChartSameLabelFit-20261003.5jglGP`, with progress in `fit.log`
and immutable execution files in `fit/`. The run manifest SHA256 is
`00d63e58564411153bb17e1e0c6cd2aefb5fcd5a7ee18ffbc509324599058249`.
The process read the durable new-data and eligibility copies listed above.
Both folds completed 30 epochs, 1,530 updates, 195,840 exposures and 33,600
same-label substitutions. Each recorded the exact prescribed affine-draw
stream. Final checkpoints were saved, reloaded and state-checked. The process
exited 0 and published its success receipt last; no fit restart was needed.

The separate prediction command then committed the common copy masks and both
model/source identities before inference. It froze 7,748 paired query exposures
(6,978 distinct drawings) before the scorer opened truth. All candidate and
control outputs are finite, with zero recorded output failures. The prior
control vectors were retained exactly, and the same 102-way decoder was used
for both arms. The old rejected 47-way candidate was not part of this comparison.

## Scored outcome

Each raw UJI fold has 3,104 symbol queries: 1,312 allowed chord fragments and
1,792 out-of-domain negatives. An unsupported leader remains unresolved.
Correct below counts a correct allowed reading, not correct rejection of a
negative; do not divide it by all 3,104 and call that general accuracy.
These are isolated symbols, not complete naturally written chords.

| UJI view | Queries | Correct: control → candidate | Wrong legal: control → candidate | Unresolved: control → candidate |
| --- | ---: | ---: | ---: | ---: |
| A16-to-B16, raw | 3,104 | 1,076 → 1,092 | 252 → 228 | 1,776 → 1,784 |
| A16-to-B16, common no-copy | 3,089 | 1,061 → 1,077 | 252 → 228 | 1,776 → 1,784 |
| B16-to-A16, raw | 3,104 | 1,021 → 1,018 | 310 → 317 | 1,773 → 1,769 |
| B16-to-A16, common no-copy | 3,096 | 1,013 → 1,010 | 310 → 317 | 1,773 → 1,769 |

The first fold gains 58 correct readings but loses 42 previously correct ones;
the second gains 51 and loses 54. New correct-or-unresolved-to-wrong-legal
transitions number 60 and 85 respectively. These transition counts are unchanged
by the copy exclusions. Correct counts decline for five of 16 query writers
in the first fold and nine of 16 in the second. An aggregate gain in the first
fold does not erase those regressions.

The 770 HWRT queries are the same shared cohort in both folds, not 1,540
independent drawings. Their correct counts change 733 → 731 and 710 → 714;
wrong-legal counts change 20 → 21 and 16 → 22. Sharp-symbol correct counts
decline 226 → 224 and 224 → 223. In the second fold, slash improves 68 → 76
while half-diminished declines 153 → 150. All per-class, per-native-symbol and
per-writer counts remain in the score artifact.

Both folds fail the no-new-wrong, every-writer-nonworse and every-mapped-class-
nonworse screens in both copy views. The second fold also fails the strictly-
more-correct and fewer-total-wrong-legal screens. Copy removal does not reverse
the verdict. The recipe must not be rescued by selecting a different epoch,
ratio, seed, writer exception or threshold from these outcomes. No new model
entered the app, and no additional human participant is required for this work.

Completed artifact SHA256 values:

- Fit receipt:
  `9303057ae789cc73ddd1263867c4b86d230398a4e1c840d2c3dbfeba3fa30a53`.
- Pre-inference input manifest:
  `fbdd82fa82ed400cede798b35d472883568cd7f040474f16a8e3541cb5ed81b7`.
- Frozen predictions:
  `84d11faacdc684c0d4c1d3276fa5567f88a8ee5e44aa9d55551c51c37f54baef`.
- Score:
  `2442271e3b16cf8f1371f9cdb5cfcceb01c404ccd6fed7380f0f8d1017307c9c`.

## Independent reconciliation and preservation

Independent reconstruction found no schedule or scoring discrepancy. The plan
verifier rebuilt every replacement slot and target, the 32/32 class mixture,
all source multiplicities and the 8,604-row actual-fit fingerprint packet in
each fold. It authenticated all 41 code files and both saved checkpoint byte
hashes. It did not deserialize the models or independently regenerate actual
forward-input/draw streams; those remain authenticated execution-ledger
commitments, distinct from the independent plan reconstruction.

A separate scoring verifier used no evaluation scoring helpers. It rederived
the saved 102-way decoding, vector hashes, common copy masks, source joins,
every raw/no-copy writer/class/five-shape summary and all six advancement
checks. Every reported result matched exactly. The original full control
vectors are unchanged. No model was loaded or rerun by either verifier.

- Independent plan-and-fit report:
  `4d7cf0918ac369e0ebf61d865bcd7d57b41968a5a9bbff56addef1c022359f36`.
- Plan-and-fit verifier:
  `85bccc23f41f68a66b0bc792c62b66cd965627be49c1fcbebf185f5a32ddbef0`.
- Independent scoring report:
  `0c4e995beac80784efc6d0a54516a0de664510d16be7a87a4d7a1e9745b06141`.
- Independent scoring verifier:
  `9225e6e22a977b3ef4d35c3906832f955d20a532222a5d47d61ad2c594ac6533`.

The complete fit, executed code, frozen protocol, predictions, manifests,
scores, logs and both independent verifiers are durably archived at
`/Users/benirossman/.local/share/ichart/recognition-development/same-label-fit-20261003.5jglGP`.
Its recursive comparison with the completed temporary run returned exit 0.
All source rows and failed-candidate evidence are retained. Nothing was
installed, committed, pushed or deployed in this pass. The long-running
recognition objective remains open; this exact candidate is rejected rather
than adjusted against the now-observed outcomes.
