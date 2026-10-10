# Bounded support metric results

The fixed support-conditioned metric candidate is rejected. It completed its
single planned training run but changed no chord-domain decisions in either
the fitting or internal-check writer group. Matching-writer lessons did not
outperform unrelated-writer lessons. No new model enters the app.

This is an offline, reused-public-data experiment on isolated characters, not
a fresh handwriting trial or complete-chord accuracy result. It does not
establish benefit for the user's handwriting or across app users.

## Comparison and result

The protocol was frozen before optimization in
`personal-support-metric-protocol-2026-10-03.md`. The encoder, classifier,
128-dimensional features, and full 97-class anchor bank remained unchanged.
Only the support-conditioned metric scorer was fitted: 30 epochs, 32 episodes
per epoch, and exactly 960 Adam updates. All four scorer parameter tensors
changed, the checkpoint reloaded exactly, and prediction replay was deterministic.

All 64 episodes and 6,208 scheduled query exposures were retained, with no
prediction failures. The two catalogs reuse the same drawings; the internal
check contains 1,552 distinct drawings, not 3,104 independent samples.

| Internal-check cohort, each catalog | All query exposures | Chord-domain targets | Baseline correct | Matching lessons correct | Unrelated lessons correct |
| --- | ---: | ---: | ---: | ---: | ---: |
| Raw | 1,552 | 656 | 532 | 532 | 532 |
| Excluding source copies | 1,548 | 652 | 528 | 528 | 528 |

These counts are identical for the fixed 10- and 21-example catalogs. They
are glyph counts after rejecting non-domain raw winners, not complete chords.
Across all 6,208 exposures, both candidate arms changed zero domain decisions.
There were zero domain corrections, lost correct reads, or new wrong reads.
That absence of regressions is not enough: the candidate fails the required
positive gain, matching-over-unrelated support, and per-session benefit gates
in every internal-check catalog/cohort combination.

Full-97 diagnostics do not rescue the result. Internal-check correctness is
1,249 raw and 1,245 after copy exclusions in all three arms. The matching arm
changes one full-97 decision in the fitting group, losing a correct out-of-domain
classification; both old and new outputs remain rejected by the chord boundary.
This exact recipe will not be retuned against these observed answers.

This was not a disabled inference path. Every internal-check candidate logit
row differed numerically from baseline. Maximum matching-support changes were
0.14227 for the 10-example catalog and 0.08971 for the 21-example catalog,
but no internal-check winning class changed.

## Verification and provenance

The final warnings-as-errors engineering gate executed 29 tests, with zero
failures or skips. It includes a synthetic 960-update lifecycle, real parameter
updates, immutable inputs, checkpoint reload, forbidden answer-file reads,
copy and role accounting, strict domain projection, and artifact tampering.
These tests validate implementation contracts, not recognition quality.

An independent prepared-artifact check reconciled all episodes, donor choices,
copy ledgers, source ownership, feature values, anchors, and the seed-43 update
order. The eligible exposure totals were 3,090/3,104 for fitting and 3,096/3,104
for the internal check. All 23 unavailable stored-source rows were accounted
for, including 11 in the two later writer groups; no catalog lesson was missing.

The first preparation attempt stopped before producing artifacts because an
old receipt bound a previous Swift source hash. The only source difference was
the added exact-lesson persistence helper and an access-level change, not stroke
normalization. The new experiment loader authenticates all 13 crossfit and 23
centroid generation files against their archived bytes, accepts only that exact
reviewed old/new transition, and records historical and executed code separately.
Old validators, source caches, receipts, and the fixed model recipe were not changed.

Predictions were frozen before the separate scorer opened the internal-check
answer sidecar. The writer groups have appeared in earlier research; this
separation prevents fitting-stage answer access but does not make the reused
data fresh or previously unseen evidence.

The independent scorer reconstructed all 6,208 rows and exactly matched the
entire result: raw and copy-excluded cohorts, taught/untaught strata, writers,
sessions, and gates. It also reconstructed all 960 training-input hashes and
authenticated checkpoint bytes and input/anchor bindings. It did not rerun
optimization or independently deserialize the checkpoint; exact state reload
was verified by the execution runner and bound in its authenticated receipt.

## Evidence locations

Execution directory: `/private/tmp/iChartSupportMetric-20261003.bjh4UE`.
Durable archive, copied and recursively compared with no differences:
`/Users/benirossman/.local/share/ichart/recognition-development/support-metric-20261003.VgD9eP`.

| Artifact | SHA256 |
| --- | --- |
| Fixed protocol | `bc94d5b92815119ba70d8c2abeb5b54dc42b1ec9801cc6bebbae2a07993decad` |
| Preparation commitment | `c2272fea6d504e41b5dbcb93e099278ce2a0d93027fcf1f31bfd97ae713ab5bf` |
| Fit receipt | `91321a3d0a2722844a5c1f3ef9e8668e7df1b1437c18d1e71f591d8d3a794d3c` |
| Final weights | `17a1671db811d8f97a60151ddcc3099b26743a26a9b0428545ecd5365f4a4dce` |
| Frozen predictions | `9e947bbfd614d53b9f7457e92edd2af8b1cd2d293c682e38e8466d8830174046` |
| Scored result | `8505b23656596e5a42f6278aef275b264d53cb7387b5676c65140ec80a4419eb` |
| Independent scored reconciliation | `0f39c95ccfe91a2b300d8240e6bbf63e8ac0b79c3e1316a0fdfe53a1b928d4a3` |

No private ink, profile, chart, app build, installation, commit, push, or
deployment was changed in this pass. The chord-only reader boundary remains
separate from this rejected personalization experiment.
