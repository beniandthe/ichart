# Explicit chord-domain rejection: candidate rejected

The fixed 47-output candidate failed all four advancement screens: both writer
folds, with and without copy exclusions. It reduced total wrong-legal UJI
outputs, but lost correct legal readings and introduced new wrong readings.
It remains offline. No app, profile, live recognition, device build, install,
upload, or release was changed by this experiment.

The [frozen protocol](personal-domain-reject-protocol-2026-10-03.md) tests one
specific training objective. It does not test whether the existing app-facing
complete-chord boundary is necessary; unsupported suggestions must still be
rejected. Restricting output identities alone does not prevent unsupported ink
from being misclassified as an allowed component.

## What was executed

Both arms used the same image-only encoder, seed-29 feature initialization,
exact raster pixels, source-label-balanced batches, and affine transformations.
The control had 102 literal classes. The candidate copied the 46 legal rows and
added one internal REJECT row initialized as the mean of the 56 forbidden rows.
Candidate ties and REJECT maxima were unresolved, with no runner-up rescue.
Loss was ordinary unweighted cross entropy; no threshold, seed, checkpoint,
writer-specific rule, or parameter was selected from query answers.

Each fold completed 30 epochs, 1,530 updates and 195,840 exposures per arm.
The 56 collapsed identities accounted for 3,584 of 6,528 exposures each epoch;
the reject pool was not balanced to the size of one legal class. Actual model
input hashes matched between arms, all scheduled fitting rows were used, and
all four final checkpoints were saved and reloaded successfully. Predictions
were frozen before the separate scorer opened truth. All 15,496 arm outputs
were finite and complete, with no retained numerical failures.

The combined synthetic gate ran **27 tests**, with zero failures or skips and
all warnings treated as errors. This verifies the experimental implementation,
not handwriting accuracy. A separate source review covered initialization,
role separation, sampling, actual paired inputs, checkpoints and scoring.
Before any real preparation, the protocol explicitly clarified that prediction
may read label-free fit fingerprints solely for duplicate accounting. That
clarification changed no training or decision rule.

## Evidence scope

The source was only the preserved prior training bundle: 6,208 UJI drawings
from 32 training writers and 3,865 HWRT training drawings. UJI writers were
deterministically split into two 16-writer blocks, with both sessions kept
together. Each fold had 6,199 fitting and 3,874 query rows. HWRT supplied a
shared 770-record query cohort across eight native IDs and five mapped shapes.

There were 7,748 query exposures but only 6,978 distinct query drawings. The
shared HWRT cohort is not two independent samples. HWRT writer identities are
unreliable, and the five novel labels remain source-confounded. These public
data have participated in previous research: this is internal writer-blocked
development, not fresh independent validation. No old eight-writer development
cohort, reserved writers, private lessons, chart answers, or new participants
were used. Full-chord accuracy, personal-learning benefit, Core ML/Swift parity,
Pencil experience and shipping rights were not established.

## Results

The following UJI rows include only the 41 legal original fragments. Each
arrow is **control → domain-reject candidate**; unresolved is not counted as a
correct chord. These are isolated fragments, not complete chord readings.

| Writer fold | Legal queries | Correct | Wrong legal | Unresolved | Gains / lost correct |
| --- | ---: | ---: | ---: | ---: | ---: |
| A16 → B16 | 1,312 | 1,076 → 1,036 | 114 → 98 | 122 → 178 | 35 / 75 |
| B16 → A16 | 1,312 | 1,021 → 980 | 141 → 128 | 150 → 204 | 28 / 69 |

Among those legal queries, the candidate introduced 22 and 34 new wrong-legal
readings respectively: 13/21 previously correct readings became wrong, and
9/13 previously unresolved readings became wrong. It reduced correct readings
for 13 of 16 query writers in each fold. The worst writer changes were −7 and
−8 correct readings, respectively.

Each fold also queried 1,792 forbidden UJI fragments. Wrong-legal outputs fell
from 138 to 136 in A16 → B16 and from 169 to 141 in B16 → A16. Those net changes
conceal **43 and 41 new forbidden-input → wrong-legal readings**. The candidate
has no forbidden output identity, but can still mistake an unsupported input
for a legal fragment.

Report HWRT separately; the same 770 queries were used for both folds:

| Writer fold's model | Correct HWRT readings | Wrong legal | Unresolved | Gains / lost correct |
| --- | ---: | ---: | ---: | ---: |
| A16 → B16 | 733 → 719 | 20 → 15 | 17 → 36 | 6 / 20 |
| B16 → A16 | 710 → 698 | 16 → 19 | 44 → 53 | 14 / 26 |

Correct readings of `#`, `ø`, and `△` declined in both folds. `/` declined in
the first and tied in the second; `+` stayed at 16/16 in both. HWRT introduced
four and eight new wrong readings. All five mapped-class and eight native-ID
summaries, every writer, full vectors, failures and paired transitions remain
in the saved score rather than being replaced by a pooled accuracy figure.

## Copy exclusion and fixed decision

The label-free union found 15 and eight affected query rows respectively, all
UJI rows that both arms read correctly. Excluding them leaves 1,297 and 1,304
legal queries; correct counts become 1,061 → 1,021 and 1,013 → 972. Every paired
gain, lost-correct count, new-wrong count and failed gate is unchanged. No HWRT
query was excluded.

Both raw and copy-excluded views in both folds passed complete-finite-output
and fewer-total-wrong-legal-UJI checks. All four views failed:

- Strictly more correct legal UJI readings.
- Non-worse correct readings for every query writer.
- Zero new correct-or-unresolved → wrong-legal readings.
- Non-worse correct readings for every mapped HWRT class.

The combined safety-only new-wrong counts are 69 and 83 per fold, not a pooled
recognition rate. Rejecting more inputs is not sufficient to advance a model
that also loses correct readings and makes new mistakes. This fixed candidate
is rejected; do not tune it on these answers or promote it into the app.

## Reproducible artifacts

Execution directory:
`/private/tmp/iChartDomainReject-20261003.2BkggD`.
Durable evidence destination:
`/Users/benirossman/.local/share/ichart/recognition-development/domain-reject-20261003.UFLEmv`.
The artifacts include prepared role-separated inputs, executed source snapshots,
training plans and logs, final weights, full frozen predictions, the complete
score, and the synthetic test log. Research artifacts remain outside Git.

| Artifact | SHA-256 |
| --- | --- |
| Protocol | `790ffda2fd09500a57f09da3f3dde3d18cfb8d8ad12c55b4850dbb97de43c552` |
| Data receipt | `d835b1e01ec21cdaac4f8882d8ef02309c3cd9960408b45fa17cc74a0b5023d5` |
| Final fit receipt | `556dbc308fc778ce6273910301b13ab1652742a474ed1a0d000f1ec65ef90bdb` |
| Frozen predictions | `849c4bdd2e4ec57934fcf8eff3c8f948f5803bbeafbeb08671712f337aa4994d` |
| Score | `363abc048a409c911bc93038827d6d6971d7f1b8daadf0eb28cfac0ac0cd3b3e` |
| Synthetic test log | `1e0889dc7ca80c3c84714c827775e3992abb6afeb57557e5916eb3f5ea36c117` |
| Independent verifier | `dc31d2d0d7cf05a65f808fbc7f47013979d8a5b3234357782fdfd2ac35a61e4b` |
| Independent reconciliation | `7fd3425634a4ba122deddbafc62245a9a0622a27add05e2462b751f291f0537b` |

The independent verifier ran once and found no discrepancies. Without importing
the model or production scorer, it rederived all 15,496 saved output decisions,
Float32 vector hashes, source-only copy masks, truth joins, per-source/writer/
class/native-ID summaries, paired transitions, and all four fixed screens.
It did not rerun models, open rasters or fitting labels, or independently prove
the original source provenance. Its scope is saved-artifact arithmetic and
binding verification, not fresh handwriting evidence.

The completed execution directory was copied to the fresh durable destination.
A recursive comparison found no differing or missing files. The repository
whitespace check is clean. The app-facing chord-domain boundary is unchanged;
the failed candidate and its research-only code are not bundled into the app.
