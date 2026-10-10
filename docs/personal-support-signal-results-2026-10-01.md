# Setup lessons contain signal, but uniform mixing is unsafe

This is a completed training-only feasibility diagnostic, not a new recognition
candidate or a generalization result. No alpha was selected. The prior failed
learner stays rejected. No app, profile, ink, live recognizer, physical device,
telemetry, release, commit or push changed.

Base HEAD `160aa31594903508e241802e21ca83ec447de849`; branch
`codex/recognition-generalization-reset`. The
[fixed protocol](personal-support-signal-protocol-2026-10-01.md) and source-only
alpha grid were declared before the audit. Only the preserved public UJI
training feature bundle was used. Development/private/reserved data were not
opened, and no encoder or learner was fitted or newly inferred.

## Measured signal and tradeoff

128 one-epoch episodes covered 32 training writers, both opposite-session
directions, and K10/K21 independently chosen setup subsets. The same query row
appears once per K task: 12,416 scheduled exposures become 12,370 scored
exposures, representing 6,185 distinct eligible source rows, not 12,370
independent samples. All eligible raw-pixel, normalized-trajectory and joint
fingerprints are distinct; those fingerprints still do not establish independent
physical sampling. The 23 generic-fit-copy rows account for 46 excluded
exposures; there are no own-support-copy exclusions. The 23 unavailable setup
shapes remain explicit and are not invented lessons.

The frozen protocol's phrase "distinct physical query counts" was too strong
for the available provenance. The executed report narrows that requirement to
source-index and ink-fingerprint counts and explicitly sets
`physicalSampleIndependenceEstablished=false`; physical independence remains
unverified rather than inferred from IDs. The original protocol is preserved
without a post-result edit.

The deterministic cache uses the original fixed `10*cosine` relation, exact
support-triplet deduplication and label multiplicity balancing. It is not the
previous learner's trained relation. Each task retains the full 97 vocabulary.

| Training task | Baseline correct / query exposures | Taught baseline mistakes | True label highest in cache |
| --- | ---: | ---: | ---: |
| K10 | 4,773 / 6,185 | 151 | 136 |
| K21 | 4,773 / 6,185 | 300 | 249 |

Thus the cache contains the correct top label for 385 of 451 taught mistake
exposures. This is potential information, not 385 achieved safe corrections:
the learner cannot know at inference whether the query is one of these labeled
mistakes, and repeated K exposures are not independent evidence.

The independent descriptive check found mean cache top-one mass of 0.65611
for K10 and 0.57368 for K21. For the 385 correct-cache taught mistake
exposures, mean top-one mass is 0.79630 and mean top-two margin is 0.67036.
This does not support a generally flat-cache explanation in these training
episodes; these uncalibrated score averages do not establish safety. No new
temperature or confidence threshold was tried. Descriptive report SHA:
`b122ec4872c84fbfdfa395d683fe2c322c3cccbf534bee314d6475a507f2ccee`.

| Fixed cache weight | Corrected exposures | Broken exposures | Broken untaught exposures | Net correct |
| --- | ---: | ---: | ---: | ---: |
| 0% | 0 | 0 | 0 | 0 |
| 1% | 2 | 1 | 1 | +1 |
| 3% | 14 | 8 | 7 | +6 |
| 5% | 19 | 13 | 12 | +6 |
| 10% | 35 | 30 | 29 | +5 |
| 20% | 91 | 75 | 73 | +16 |
| 35% | 194 | 240 | 237 | -46 |
| 50% | 318 | 1,174 | 1,169 | -856 |
| 75% | 375 | 7,341 | 7,319 | -6,966 |
| 100% | 385 | 8,061 | 8,015 | -7,676 |

No tested nonzero weight improves both K tasks without introducing untaught
errors. At 20%, aggregate K10/K21 nets are +7/+9, but nine/eleven writers have
negative task nets. That is not a safe personal setting. At 100%, every query
is forced into the limited taught vocabulary; its failure is expected rather
than evidence that the underlying full-vocabulary recognizer lost capability.

Mean equal-stratum per-episode NLL is 0.74227 at zero and 0.68657 at 5%, but
NLL improvement does not remove the measured top-one regressions. This audit
does not prove an optimization gap in the rejected learner: its learned
relation and varying gate were not used. Its near-zero gate cannot be explained
solely by having more untaught classes, because the loss weights the two
strata equally. Initialization/optimization adequacy remains an open question,
not a claimed cause.

## Writer-role implementation and verification

Added a reusable source-only internal role builder. It uses one frozen generator
only: fitA was trained on A16 and exported B16; the existing source-hash-defined
B order splits into eight meta-fit and eight internal-validation writers.
The three learned-stage writer sets are disjoint, both inner roles have 1,552
source rows, and every selected feature comes from fitA. The saved manifest
binds the generator weights, full parent receipt, source, metadata, features,
protocol, parent code and planner code; mutation tests prevent parent aliases.
This addresses the cross-generator leakage risk of naively repartitioning
mixed out-of-fold features.

These B rows were previously used by the all32 learner and this diagnostic.
The manifest explicitly says `freshValidation=false`, internal reuse/selection
only. Repartitioning old data does not restore freshness. No learner or
selection rule was executed from this manifest.

The final focused Python gate executed **47 tests, all passed, none skipped**.
This includes the previous 31 crossfit/learner/evaluation tests, ten cache-audit
tests and six role-builder tests. The initial actual audit failed only at JSON
export because a NumPy comparison produced a NumPy scalar. It was repaired at
the source with an explicit Python boolean and a serialization regression test.
The initial failure and initial 46-test log remain preserved. The alpha grid,
source, exclusions, probability formulas and protocol were unchanged.

An independent NumPy verifier reconstructed the source-only RNG plan,
exclusions, generic/cache probabilities and all ten mixtures without calling
the audit's prediction/scoring helpers or a learned model. It reproduced all
123,700 top-one decisions exactly and checked 11,998,900 finite probability
cells with full mass. Every exposure/task/writer/session/stratum correction,
regression and NLL matched; the maximum scalar discrepancy was `8.22e-15`
against tolerance `1e-12`. It passed with runtime warnings treated as errors,
without warnings. Full rank orders were not compared, and no such claim is made.
Reconciliation SHA:
`13383d4a4e00bb7b8210760ff9593c34a0607084d7c63b8b860f40fa90e43641`.

## Artifact bindings and next action

- Protocol SHA: `71c89c33e0162a0b77591beae6976e6cfec7a99f5651ec043528e3c95c492376`.
- Full audit SHA: `5d42122ae6bc2cf56acefcd13f64e79f06af4650730ef99fd2d740e56d99c493`.
- Truth-free prediction SHA: `8142aab5898c0626785a4f23043e766c413ec2652eb29f64d1b2bd91cbab88bb`.
- Internal role manifest SHA: `47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa`.

The next learner should address when explicit setup evidence can safely
override the baseline, rather than choosing a stronger constant weight from
this table. Any optimization/selection must stay within training-only roles,
preserve full-vocabulary and untaught outcomes, and document reused evidence.
Fresh writer-disjoint natural handwriting in both chart styles and application
runtime parity remain separate required gates. No new iPad test is requested
by this diagnostic, and no deployable recognition improvement is claimed.

Durable evidence is retained at
`/Users/benirossman/.local/share/ichart/recognition-development/support-signal-20261001.Ww687Z`,
with the original failure log, final 47-test log, full audit, role manifest,
independent verifier/reconciliation, code snapshots and preserved parent
artifact references. The preceding experiment and source bundles remain intact.
