# Local personal learning: bounded development result

This pass changes the personal fitting rule over the same frozen ML visual
encoder. It does not try another OCR engine, modify the live recognizer,
rewrite a private profile, or install a new app.

Protocols were fixed before their respective predictions:

- `personal-local-learning-protocol-2026-09-28.md`
- `personal-local-anchor-protocol-2026-09-28.md`

## Public-character comparison

All results below use the same **772 eligible isolated-character queries** from
eight already-inspected development writers, session-one support and session-two
queries. All 97 generic labels remain competitors. Four copied queries remain
recorded and excluded. The 20 reserved writers were not rasterized, fitted or
predicted. This is not full-chord or fresh-device accuracy.

| Personal learner | Sparse16 correct | Sparse gains / harms vs generic | Full97 correct |
| --- | ---: | ---: | ---: |
| No personal learning | 609 | — | 609 |
| Original linear residual | 602 | 22 / 29 | 628 |
| Existing linear + public shape constraints | 614 | 10 / 5 | 628 |
| Local kernel residual | 614 | 12 / 7 | 639 |
| Local kernel + same public shape constraints | 615 | 11 / 5 | 639 |

The kernel width, `0.16684838059285878`, was derived once from training-writer
cross-session same-character distances: 3,104 pairs, 3,097 eligible after copy
and zero-distance exclusions. The visual weights and lambda 0.1 stayed fixed.
The follow-up reused this exact width and the existing public anchor bank.

The local-only method failed its small-profile harm gate and is not promoted.
Adding the existing untaught-shape constraints passed the predeclared
**comparison-only** next-step gate. This is a modest sparse-profile gain, not
an across-the-board improvement:

- Versus the existing linear-anchor method, sparse16 has **four gains and three
  harms**, net one. Two writers lose one correct read each, two gain, and four
  are unchanged. Correct counts by writer remain available in the reports.
- Taught sparse labels improve from 103/128 generic to 113/128. Untaught labels
  remain 502/644 versus 506/644 generic. Personal learning still causes errors.
- Full97 improves 20 previously wrong reads but loses nine previously correct
  reads versus the linear personal learner, net 11. Its 639/772 result is an
  upper-profile character experiment, not an attainable quick-setup promise.
- An empty profile preserves generic output. With full generic-label coverage,
  no untaught constraints remain and the constrained local method exactly
  reproduces the local-only method.

## Preserved full-chord recordings: no repaired endings

After the public gate was fixed and passed, a Python diagnostic compared the
methods on the eight unique previously seen v26 recordings. It reused exact
Swift-verified stroke groups, the same original encoder and the unchanged
12 explicitly labeled glyph lessons. Whole-chord labels were not converted
into guessed symbol lessons. Query answers were not fitting inputs.

Both new methods preserve the four previously correct Simple raw readings.
The four Rhythm raw readings remain `BbsD`, `EbS9`, `D>` and `EbT`, unchanged
from the original personal learner. Nothing was accepted into a chart or
repaired with the expected chord. This Python replay is not an on-device run
and is not fresh handwriting.

**Decision:** do not replace the live reader or the current Debug comparison
bundle on this evidence. The public result warrants further comparison, but
changing the fitting rule alone did not fix the observed chord failures. Keep
symbol/representation coverage and the explicit correction-to-symbol learning
loop as open requirements; do not claim a fix or tune a private-chord exception.

## Verification

- **50 focused Python tests passed, 0 failures/skips**, with runtime arithmetic
  warnings treated as errors. Eleven new tests cover independent weighted
  kernel equations, empty/full limits, explicit novel labels, duplicate class
  balance, input ownership, order invariance, training-only width construction,
  copy exclusion, source/reference binding and query-answer isolation.
- Local-only reports and width artifacts reproduce byte-for-byte. The
  constrained-local report also reproduces byte-for-byte in a separate run.
- The diagnostic's original-model labels and generic scores still match the
  earlier actual Core ML replay (score tolerance 1e-4). The new kernel learner
  itself has **not** been ported to Swift or validated in Core ML/iPad runtime.
- Original weights, preserved private profile and eight-run journal retain
  their earlier SHA-256 values. No private examples were taught or removed.
- No device signing retry, install, server mutation, commit, push or release
  occurred in this pass. The previously prepared device build still requires
  the user's Mac signing access; this research does not change that bundle.

Evidence directory: `/tmp/iChartPersonalKernel-20260928.KDkZBj/`.

- `run-01/`, `run-02-repeat/`: local-only fixed-protocol experiment.
- `anchors-01/`, `anchors-02-repeat/`: fixed constrained follow-up.
- `all-tests-02.log`: 50 executed tests.
- `private-replay-01.json`: local-only private diagnostic, kept outside Git.

Local-only report SHA-256:
`739b2b7c7d408bddb0a6b8f21dc09a9e23fc6266a18b65d8dc6f67230804f660`.
Training-width artifact SHA-256:
`33ed8df132011bbec26ceb419d7c0dc71aaaf6a257d0330461a260dd1348471e`.
Constrained-local report SHA-256:
`41bfd253bdc5d705e653720a77093dbd584d7487ae6487be15a4e661f8010bf3`.
Private diagnostic SHA-256:
`3ebf9945481c308136b41e906e6f1278e94479f6975fc2a2b1281201db0a456d`.

The goal remains active: genuinely fresh complete chords in both chart styles,
independent-writer evidence, calibrated review behavior and a successful
physical-device learning flow are still missing. Neither passed tests nor this
development-character improvement establishes recognition quality or shipping
readiness.
