# Public app-runtime local-learning result: fixed candidate rejected

Date: 2026-10-01. Branch `codex/recognition-generalization-reset`.
Base HEAD `160aa31594903508e241802e21ca83ec447de849`.
This pass changes no live recognition, user profile, chart, physical iPad,
telemetry or production system. The long-term recognition goal remains open.

## Verdict

The fixed local-RBF anchored learner failed both predeclared development tasks.
It is not a better replacement for the linear anchored control on this evidence.
Keep it offline; do not promote it, retune it on these outcomes or consume the
historically reserved writer set to try to rescue it.

These are author-labeled isolated public characters, not natural chords or
shipping accuracy. UJI contains 97 character classes, two samples per writer
and 60 writers; see the [official UCI dataset description](https://www.archive.ics.uci.edu/dataset/177/uji%2Bpen%2Bcharacters%2Bversion%2B2).
Eight previously observed development writers were evaluated. No reserved
writer was rasterized, inferred or used for a personal fit. The original model
training-membership receipt remains missing; this does not prove new-writer
generalization or reproduce Python-to-Core-ML encoder conversion parity.

## Executed app gate and numerical validation

- Xcode 26.6, normal Debug, canonical iOS 26.5 iPad Simulator.
- 42 XCTest cases passed, zero failed and zero skipped, confirmed by xcresulttool.
  Includes the real-runtime exporter, 12 comparison/freeze tests and 29 project
  configuration tests. This is not a new physical-device test or installation.
- All 16 profiles use actual `PersonalInkProfile.learn(.glyph, .setup, nil)`
  normalization/decimation. All profiles were frozen before encoder construction
  and all fits completed before the first query. No existing user profile was used.
- 248 support lessons, 1,552 scheduled queries, 1,552 valid readings, zero dropped
  or invalid queries. All 97 labels compete in every query, with full rankings.
- Independent Python residual refits matched all 451,632 score cells and full
  rank orders on exact exported Swift embeddings/base scores. Maximum absolute
  errors: shared 0, linear 1.33e-15, local 7.33e-15.
- Python and Swift raw rasters matched for all 1,552 development source records.
  Exact source/support label and deterministic-ID reconciliation also passed.
- Ancillary parser strings exist in the full Reading DTO but were never used
  for selection or scoring. The protocol's “No parser” restriction means no
  parser-based scoring/selection; it is not a claim of zero parser invocations.

## Complete aggregate outcomes

Correct codepoint top-one reads, raw denominator 776 per task:

| Fixed lesson set | Shared | Linear anchored control | Local anchored candidate |
| --- | ---: | ---: | ---: |
| core10 | 613 | 617 | 615 |
| catalog21 | 613 | 619 | 619 |

Source-only copy checks reproduced four dot records. They remain in the raw
denominator. The separate fixed no-copy denominator is 772, with correct counts:
core10 shared 609, linear 613, local 611; catalog21 shared 609, linear 615,
local 615. Removing copies does not change the disposition.

Paired local versus linear outcomes:

| Task | Gains | Harms | Net | Untaught gains/harms | App-available gains/harms |
| --- | ---: | ---: | ---: | --- | --- |
| core10 | 1 | 3 | -2 | 1 / 2 | 0 / 1 |
| catalog21 | 5 | 5 | 0 | 2 / 3 | 3 / 2 |

Against shared, core10 gains 4/harms 2; catalog21 gains 8/harms 2. Both have
zero untaught gains and two untaught harms against shared. Those shared-reference
untaught harms are in the non-app stress slice, not musical app glyphs. They
still fail the frozen all-97 safety gate and cannot be omitted after the run.

The 21 available app codepoints have 168 queries/task: core10 shared 149,
linear 154, local 153; catalog21 shared 149, linear 156, local 157. Thus even
the app-relevant primary slice is worse than the linear control. The larger
lesson task cannot rescue the primary failure, and its one-read net advantage
still includes two newly wrong app-relevant readings against linear.

Raw/no-copy per-writer tables, taught/untaught, app-available-untaught, non-app
stress, every discordance and diagnostic actual-stored-support copy reason
are retained in score-v2.json. No result-selected thresholds, label subsets,
width, regularization, rank rules, grammar rescue or writer exclusions were used.

UJI does not cover five app glyphs: `# + / ø △`. Literal `b`, `o` and `-` are
codepoint/visual proxies, not independently certified musical-symbol handwriting.

## Evidence and chronology

Exact evidence bundle, retained outside Git and telemetry:
`/Users/benirossman/.local/share/ichart/recognition-development/public-app-local-transfer-20261001.IGj03b`.

The original pre-inference fixture, protocol, truth/copy hashes, code/runtime
maps, producer/scorer/runner tool map and execution commitment are preserved.
The complete immutable prediction artifact is retained, not only summary scores.

A read-only audit found additional independent-scorer validation gaps, not an
observed prediction/formula error. A separate v2 verifier tightened finite-rank,
same-ID label/ink/profile/model, exact truth/cohort and tools-map checks on the
SAME frozen predictions. Original verifier/results remain preserved. V2 was
post-run revalidation, not part of the original pre-inference tools map. Every
common result row, cohort, condition and disposition remains identical.
Independent source/UUID reconciliation is likewise post-run, with no model
rerun, cohort change or reserved-writer rasterization.

Key SHA-256 receipts:

- Protocol: `fa9b3e8f9dd1d5ad296b8b1adb18a0e7f328d76407ff452f705ca7e43fe08f2e`.
- Fixture: `d3de7699f1175b8a77aab37eaf64ab2a3e47042cd58cc7416839122cd4baa55d`.
- Prediction: `52b97f84d40998a22f2c10402ff7ece5dae57a4f54cc744c11e0284d9015a618`.
- Code map, 84 files: `a6cf643f6e51eda60385ee5996cd561ba73db73d5b9142f663b8225998f48f08`.
- Runtime map, unchanged 5 files: `31fdfad29ec20b50b180bd94b59b530268238f6cb93919828f463f0495d6a0df`.
- Original tools map: `1c49942bf36d8dd82795f649f84235284fc2b9ee558bd5c726d813808a20d7f7`.
- Original execution commitment: `fc0ecddeb82539b9424b7cd14acafe4bfbbf896411e40e28dc2c834f436af9dc`.
- V2 verifier: `7d68d9fc4205175c8ba3cf4957cc525739113bd48f059d63043eb35159ecefb7`.
- V2 numerical validation: `0934e518b9d99bb6055d5caaa096936e591efd68d1027d8d4cde593cfc9ae166`.
- V2 score: `042efa357adf83a47773a2f1c07d88b1cf2d19118f217664c1b75c860578d88f`.

Native v31 grouping, its tests and the native reader remain byte-identical to
their pre-pass pins. No rejected grouping heuristic was revived.

## Next work boundary

This result does not disprove optional personalization. It rejects this fixed
local-head substitution. The next improvement must change general glyph/model
evidence or independently reviewed data coverage, then face a new fixed
development gate; it cannot consist of rules for these writers or hand-selected
misreads. Musical-symbol coverage and independently verified natural-chord
ownership remain prerequisites for a relevant fresh multiwriter quality claim.
Continue baseline-preserving, explicit correction/review/teaching; do not equate
the successful connection or test run with a recognition-quality improvement.
