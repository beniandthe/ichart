# HASYv2 source intake: coverage candidate, not recognition evidence

The official [creator deposit](https://zenodo.org/records/259444) was downloaded,
checksum-pinned, audited in place and independently reconciled. All 168,233
source PNGs and 369 native classes remain. In this full-source intake pass, no
adapter, model fit/inference, chord-label mapping or app activation was performed.
Earlier September 28 HASY mapped-symbol continuation and frozen-head expansion
were actually fitted and rejected; see
[the retained results](personal-symbol-training-results-2026-09-28.md).
The audited archive is not a newly discovered source. This is auxiliary public
raster research, not unseen-writer or natural-chord recognition evidence.

Work stayed in recognition-generalization-reset at base HEAD
160aa31594903508e241802e21ca83ec447de849. Existing dirty changes were preserved.

## Executed intake and integrity

The 34,597,561-byte archive matches published MD5
fddf23f36e24b5236f6b3a0880c778e3 and recorded SHA256
7c3ffe709e8c2b83f6ab7d8afc79f7b5f46421657981b1752d22a0ed0052aa2d.
The bounded stream reader checks every tar member, unique image path, native
symbol ID/LaTeX join, class count and classification-fold record. It never
extracts the archive to the filesystem, runs the archived helper or loads its
pickle caches. All 28 CSV/text files are preserved as inert evidence.

There are 168,274 members: 168,261 regular files and 13 directories, totaling
149,489,023 expanded member bytes. All 168,233 images decoded as single-frame
32x32 RGB, with zero invalid/uniform rasters. Native RGB pixels are hashed with
an explicit geometry/mode frame; no resizing, polarity conversion or trajectory
fabrication occurs. Source user IDs are preserved as opaque public provenance,
not reliable writer identities. Every canonicalCodepoint remains null.

The README claims 168236 images, three more than the actual PNG/label inventory;
the [paper](https://arxiv.org/pdf/1701.08380) reports the observed 168233. There
are no orphan/missing PNG joins or class-count mismatches. No row was dropped
to repair that documentation discrepancy, and filename contiguity is not
assumed.

## Missing-symbol families: native identities only

These classes provide coverage candidates, not approved chord-glyph mappings.
Mathematical semantics and confusable shapes must stay separate until review.

| Native ID | Native label | Observed rows |
| --- | --- | ---: |
| 196 | + | 90 |
| 922 | / | 532 |
| 266 | \\# | 1,067 |
| 948 | \\sharp | 237 |
| 1394 | \\o | 314 |
| 1385 | \\O | 237 |
| 950 | \\emptyset | 950 |
| 974 | \\varnothing | 461 |
| 1184 | \\diameter | 195 |
| 959 | \\triangle | 316 |
| 977 | \\vartriangle | 112 |
| 152 | \\Delta | 996 |

## Duplicate and split findings

Raw PNG and native pixels have identical group membership: 166,443 unique
hashes, 502 duplicate groups containing 2,292 rows, with 1,790 excess copies.
132 groups contain 1,181 rows with different native symbol IDs/labels. This
does not establish that every conflict is erroneous: some native semantics
can share visual forms. Preserve the conflicts; do not silently relabel or
interpret ambiguous copies as clean single-label supervision.

Every supplied classification fold has unique rows, zero train/test path
overlap, and full 168,233-path union coverage. Each path appears in test once
and training nine times. However, identical native pixels cross the folds:

| Fold | Crossing pixel groups | Affected test rows |
| --- | ---: | ---: |
| 1 | 138 | 228 |
| 2 | 105 | 149 |
| 3 | 131 | 218 |
| 4 | 143 | 232 |
| 5 | 135 | 240 |
| 6 | 138 | 226 |
| 7 | 125 | 228 |
| 8 | 137 | 232 |
| 9 | 129 | 227 |
| 10 | 117 | 218 |

These are sample folds, not reliable writer-independent validation. The paper
explicitly states user IDs are unreliable. Duplicate content also prevents
interpreting path-disjointness as input independence. Future use requires
source-only duplicate-group planning and explicit conflict disposition before
any fit. The verification-task files were preserved/hashed only, not evaluated.

## Licensing and use boundary

The paper declares ODbL for the dataset. The archived helper/software's license
is not a replacement dataset grant. No independent individual-image grant or
trained-model/shipping permission has been established. The intake stays local,
auxiliaryTrainingOnly=true and productionEligible=false. See the original
[ODbL terms](https://opendatacommons.org/licenses/odbl/1-0/) for its scope; this
audit does not provide a legal determination or clear an app release.

## Independent reconciliation and tests

A separate stdlib/Pillow audit imported no intake/model helper. It independently
reconstructed all native joins, counts, rasters, duplicate memberships and fold
partitions. A second comparison verified every manifest identity/source index,
native label/opaque user ID, flag/status and every raw/native-pixel fingerprint
against the pinned archive, all 369 class rows, all 12 requested families,
36 output artifact hashes, three code/contract bindings and 28 inert metadata
hashes. Exact raw/pixel duplicate ledgers and all ten pixel-crossing ledgers match.

Earlier independent comparison reports had only verifier JSON-key/order schema
mismatches; those reports remain. The source, intake outputs, mapping and counts
did not change to obtain the final passing comparison.

The intake gate executed 16 synthetic tests with warnings as errors and no
failures/skips. The combined residual/intake gate executed 33 tests with zero
failures/skips. These are engineering/data-quality checks, not recognition gains.

| Artifact | SHA256 |
| --- | --- |
| Frozen intake contract | fbe7550cd3697a3dc2f1a05e1425921f99550a3f682824780367aae9ae57e881 |
| Intake implementation | 4e294788bad85391616fcac61dcfd76f258a767999c27a6e2a8f0edfd17126e6 |
| Synthetic tests | 42bb01ae60874b559d5e100bdf214f7c016aef4d9e5e3df8d8fa0bfc8b9b3797 |
| Actual source receipt | ab9293fb5f81f9dd39ee9ade02f01ecb2bd203d783686f6e28dedab977f220d2 |
| Actual row manifest | 4d604325cae34dc7d08ebb533d30a5469d60a9a50dcc8db135c6287ffab95c3b |
| Independent audit report | 9bef9cc2e887f4b323edd668cf01ff731ba512f4395674353941450570aa4e22 |
| Independent audit script | 7f169fdc9fe96df8ee66d95b6d706dba7e44e7b9b7fb64b47e44b40d6fa651a7 |
| Independent comparison script | e58d37fb6725725cf6bd5d5c2979f93ef2a89f0e85b976992bcbbd331bfb2c77 |
| Final independent comparison | 71f65629d0d223920c8c24cfd2a94a49397e97579e23def63714b4d529e45a01 |

Temporary original: /private/tmp/iChartHASYIntake-20261001.7KQfwS.
Independent originals: /private/tmp/iChartHASYIndependentAudit-20261001.w1GZqR.
The local preservation receipt binds archive, intake, comparison reports/scripts
and this documentation/source snapshot without deleting originals.

## Next boundary

Review native symbol shapes and explicitly define auxiliary label/geometry
contracts and duplicate/conflict handling before training. Improve the ML
representation rather than tune the failed additive statistic or introduce
handwriting-specific spelling rules. This source cannot satisfy fresh-writer
promotion evidence by itself. No profile/chart/ink changes, app build/install,
model export, commit or push occurred.
