# Support-retrieval learner: fixed candidate rejected

The candidate did not improve recognition. It produced the exact same top-one
labels as its frozen generic baseline on all 1,552 scheduled predictions.
Zero new errors is useful safety evidence, but zero corrections is not useful
personalization. Do not promote or retune this fixed candidate on these queries.

Branch `codex/recognition-generalization-reset`; base HEAD
`160aa31594903508e241802e21ca83ec447de849`. This pass used public UJI writers,
not private handwriting, user acceptance answers, chart corrections, or special
rules for particular codepoints. No app/profile/ink, live model, telemetry,
physical device, release, commit or push changed.

## Executed experiment

The [fixed protocol](personal-support-retrieval-protocol-2026-10-01.md) was
finalized before model fitting and development scoring. Two identical-initialized
temporary 97-way visual encoders each fitted 16 of the existing 32 training
writers and exported only the complementary 16. Each completed 30 epochs and
750 real optimizer updates. Their 6,208 out-of-fold records retain writer,
session, source, original/stored pixel and normalized-trajectory identities.
The operational full-32 encoder was not changed.

The Python setup-shape adapter matched all 248 retained Swift support geometry
and pixel goldens before fitting. Its 23 unavailable training setup shapes stay
explicit; they cannot become invented lessons. All raw records remain present.
Twenty-three raw records matching their feature generator's fitting pixels or
normalized trajectories are excluded from meta-query loss by source-only checks.
Opposite-session support-copy checks are retained in every episode plan.

One shared scalar-relation/cache learner completed 1,280 actual updates in ten
epochs using only out-of-fold public features and explicit support labels.
All eight parameter tensors changed; every epoch had finite nonzero gradients.
No learned embedding-coordinate projection, codepoint embedding, class-axis
matrix, writer ID or query truth enters prediction. Exact repeated lessons are
deduplicated before class balancing. A scalar gate mixes the full generic
distribution with explicit-support retrieval. Untaught relative ordering is
structurally preserved; overtaking by a taught class is still a measured risk.

The twofold-to-full-encoder probability-calibration shift remains a limitation.
The fitted result rejects this recipe, not every possible retrieval learner.

## Frozen prediction and results

The final learner was frozen before consuming the existing full-32 CE feature
packet. Exact Swift-stored support geometry/probabilities were reused; no
development encoder rerun or reconstructed Python-only support geometry was
substituted. Candidate inference receives exactly five tensors. Historical
linear-anchored ranks are controls only. All prediction bytes were serialized
and SHA-256 committed before the separate scorer opened query truth/copy files.

These are exact codepoint identities for isolated characters from eight
previously observed development writers, not natural-chord or fresh-writer
accuracy. Every task retains 776 raw queries and the fixed 772 no-copy view.
All 1,552 readings were valid; no query was dropped or grammar-rescued.

| Lesson task | Generic /776 | Linear anchored /776 | Retrieval /776 |
| --- | ---: | ---: | ---: |
| core10 | 612 | 609 | 612 |
| catalog21 | 612 | 612 | 612 |

No-copy counts are respectively 608/605/608 and 608/608/608 out of 772.
Retrieval versus generic has **zero gains, zero harms, zero changed top-one
labels** in both tasks, including untaught strata. Versus linear it recovers
three core10 errors with no losses, but catalog21 exchanges four gains and four
harms and is negative for one writer. Those linear differences are not new
recognition ability: the candidate stayed at generic's answers.

Independent forward diagnostics distinguish that failure from a disconnected
learner: probabilities changed on all 1,552 rows, by up to 0.03013 per cell.
The fitted gate mixed approximately 2.27–3.22 percent cache evidence (mean
2.78 percent). Those changes were not sufficient to change a top-one label.
No stronger gate was tried after seeing this outcome.

The frozen advancement screen fails because both tasks must improve their own
generic baseline, both must strictly beat linear, and no writer may be worse
than linear. No gate/initialization/threshold/checkpoint/label subset was changed
after these outcomes. The 20 reserved writers were not transformed or inferred.
UJI still lacks app glyphs `# + / ø △`; literal `b`, `o`, `-` are visual/codepoint
proxies, not independently verified musical-symbol handwriting.

## Verification and evidence

The final focused Python gate executed **31 tests, 31 passed, zero failed or
skipped**. It includes real synthetic encoder updates, a real synthetic
1,280-update learner fit/save/reload, nonzero-weight permutation/basis tests,
exact empty-support identity, duplicate invariance, balanced loss, role/copy
guards, goldens, parent-binding tamper rejection, full output mass and scoring
chronology. The first synthetic fit-path run rejected macOS's temporary-path
alias; resolving that test path fixed the test. Its initial failure log remains
preserved. No fitting recipe or model behavior changed to repair it.

An independent verifier re-derived all source/fold/shape/copy metadata and
reconstructed 2,793,600 OOF feature/logit cells from the final checkpoints
bit-for-bit (maximum error 0), without development/reserved inference. Report
SHA `947ef4463ac2f37e32187c578bc1f326f1e6eaa8d1427f827a18e7f93195403b`.

An independent scorer reconciled every one of the 1,552 rows, task/writer/stratum
counts and the frozen advancement screen. A separate NumPy calculation from the
frozen weights reproduced all 150,544 probability cells within `1.11e-16` and
every full 97-label rank order exactly. The original matrix-product verifier
emitted runtime warnings despite finite matching outputs; that script and report
remain preserved. A second verifier used the same formulas with explicit
`einsum(optimize=False)` contractions and passed with `RuntimeWarning` treated as
an error, without warnings. This changed verifier arithmetic only, not fitting,
frozen predictions, scores, or selection. Warning-clean report SHA
`7d9b518d9e49bb51004399e83612b053c146298655fad2bd29455341fd1f1bf3`;
verifier SHA `8e68009f798910fc73d9cc42bbca6ed17183d6519030579ae4619c4dc5a353ee`.

Native reader, sequential grouper and its test hashes still match their pre-pass
pins. No XCTest/build/signing/install or fresh Pencil test is claimed for this
research-only pass.

Durable evidence directory:
`/Users/benirossman/.local/share/ichart/recognition-development/support-retrieval-20261001.WmWgZ3`.
It retains both generator checkpoints, all OOF features/roles, exact episode
plans, learner weights/receipts, prediction/score bytes, logs, source snapshots,
input references and independent verification. Earlier failed candidates and
source bundles remain unchanged and are not deleted.

Key SHA-256 bindings:

- Protocol: `638533ec5bc3a1b29dc2cf9d01b0c683bebb57ba3290e6decbe80ac130675c78`.
- Crossfit receipt: `d2a31e73d53b25b812f0ba4f24f812014515606f97a20e6b7170eaf94d0e20d2`.
- OOF feature file: `b1bbb6066ef2bd1d5cc0398df2d9713fb60f6086ec501bb0687fce81976faaef`.
- Learner weights: `7f5cc4c2cb074f39bfaea3fca4e212ca6960d70ac210de56382f35be41d82549`.
- Learner receipt: `27e40d815c0b0bdcd20e3145b1843eb7eb488e41eb7ef22dbc5021f8f8c61f43`.
- Predictions: `cabf39806354e27f457adb02fc3ac6faaa935d441dfe649db100e19a0a07fd5d`.
- Score: `fa177d4f3026b86b7a91e0ed26cf9a7c451cb169286622d401af994491b548aa`.

The recognition goal remains open. These repeatedly observed eight writers must
not become a parameter-selection loop. Future optimization needs independently
specified training-only validation and fresh writer-disjoint app-domain evidence;
repeating known private chords or making the gate stronger until this screen
passes would not establish general recognition. No new iPad writing is requested
by this rejected experiment.
