# Public glyph ownership diagnostic

This is a component diagnostic for the customizable ML pipeline, not a product
accuracy test or authority to replace the installed recognition route. Freeze
the following protocol before running partitions or examining their scores.

## Source and split

Use the unchanged [UJI Pen Characters v2 source](https://archive.ics.uci.edu/dataset/177/uji%2Bpen%2Bcharacters%2Bversion%2B2),
credited to Prat, Castro, Llorens, Marzal and Vilar, CC BY 4.0. Archive SHA-256 is
0881b522911b99d9922820289441b50fd3d307f71cd7f9cc70e86872424a5f90;
unmodified text SHA-256 is
cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61.
Strictly parse all 11,640 records only for source/split validation. Select the
same eight development writers as the visual-encoder protocol: sort the forty
official trn writers by SHA-256 of `personal-encoder-v1:` plus writer ID and take
the first eight. Both sessions and all 97 characters yield 1,552 records.
The twenty official tst writers remain unused by grouping, rasterization,
inference or fitting. No personal profile, device answer or device ink is input.

## Fixed geometry and grouping arms

Preserve all points, stroke boundaries, order and available metadata. Never
invent times, pressures or new trajectories. Record four separate coordinate
arms: unmodified public coordinates, and translation plus uniform scaling to a
maximum dimension of 24, 32 or 48 points. These affine representations are
explicit diagnostics, not a silent change to training or app normalization.
UJI and UPV use different ink units per millimetre; raw-coordinate counts cannot
be interpreted as app-scale handwriting behavior. No scale is selected from
the answers or promoted by a better result.
Valid zero-extent records translate to the origin with scale one, retain all
points, and are explicitly counted; no artificial glyph extent is invented.

Run the current semantic-normalization and preserve-original-ink policies
separately. The partitioner receives only strokes, never labels, source IDs,
writer IDs, expected group counts or desired chord outputs. No model fit,
threshold sweep, grammar fallback or private-case substitution is performed.

## Ownership and encoder-input measures

Each public record is independently known to contain one character. Report
whether it yields one complete group, extra groups, missing, duplicate or
out-of-range source indexes, and exact source-stroke preservation. A one-group
count without exact ownership does not pass the component measure. For legacy
input, check the actual grouped strokes; for lossless input, reconstruct the
original strokes from sorted source indexes as the comparison pipeline does.
On complete 32-point groups additionally compare actual raster pixels from the
original and grouped encoder inputs. Report the number of checks explicitly;
do not count unmeasured rasters as equal. Labels are consulted only after the
partitions and input checks are fixed, for class-level summaries.

Persist every arm's denominator, per-writer and per-character counts, and failed
record identities/group ownership. Write an additive report without overwriting
an existing report. Verify unchanged source bytes. Ordinary invariant tests
cover affine/metadata preservation and ownership scoring independent of labels.
Passing tests establish the measurement contract, not a high ownership rate.
Bind each new report to the exact measurement and grouping source-file digests,
not only the measurement version and policy names.

## Separate adjacent-character diagnostic, fixed before its scores

An isolated-character partition rate cannot measure adjacent-symbol merging.
Use the same 1,552 development records, not the reserved twenty writers. Within
each writer/session, order all 97 records by SHA-256 of `public-pair-v1:` plus
their immutable source ID. Compose each record with its cyclic successor. This
gives 1,552 reproducible pairs, selected without prediction/score inspection;
identities select source records but never enter grouping.

Keep six geometry arms separate: first-character maximum dimension 32 points;
second-character maximum dimension 16 or 32 points; horizontal bounding-box gap
3.2, 8 or 16 points. Align both characters' point-derived bottom bounds at y=32.
Only translate and uniformly scale each independent trajectory; preserve every
source point, stroke boundary/order and available metadata. Count zero-extent
characters explicitly. These are synthetic compositions of public handwriting,
not fresh real-world chords or a representative spacing distribution.

Run only the same two existing policies, with no threshold/model changes.
Supply the two original stroke-ownership sets only to the scorer, after grouping.
Report exact two-owner partition matches, cross-owner merged groups, owners
split across groups, missing/duplicate/out-of-range indexes, and actual
encoder-input preservation. A correct count of two groups is insufficient.
Persist separate denominators/per-writer counts, failure identities and source
code digests; never overwrite the isolated report or use pair labels to pick a
grouping. These measurements do not run classification or personalization.

## Limits and decision

These development records have already been used for encoder research; they
are not sealed new-writer product evidence. Isolated characters can expose
over-splitting or dropped ink but cannot expose false merging between adjacent
characters. The separately frozen pair diagnostic tests that boundary with
synthetic compositions, not a representative chord-writing distribution.
Equal ownership does not establish classification accuracy,
musical-symbol vocabulary coverage, full-chord reading, trust calibration,
personalization gains, live latency or shipping readiness. Keep the native
baseline, original ink, saved evaluations and personal profile unchanged.

Current evidence audit found no concrete Python/Core ML/Swift raster or tensor
mismatch. The installed representation is supervised on isolated UJI characters,
not chord sequences; its shared vocabulary excludes sharp, slash, major triangle,
plus and half-diminished symbols. Explicit glyph lessons extend the personal
vocabulary. Whole-chord lessons fit a separate candidate head and do not train
composed glyph reads. Lossless source coverage alone does not certify correct
symbol boundaries: the measured private E-minor-7 input retains its small dash
but groups it with the root. No label-specific repair is justified by that case.

Evidence directory for this diagnostic:
/Users/benirossman/.local/share/ichart/recognition-development/public-grouping-20260930.BWxcGv/.
The existing installed v29 app and model remain unchanged during this diagnostic.

## Measured development results

The optional measurements and seven ordinary invariant cases executed: nine
tests, nine passed, zero failures, zero skips. Passing means the measurement
contract executed, not that grouping quality passed a release threshold.
Reports are additive and code-bound: `isolated-report-v2-codebound.json` and
`pair-report-v1.json`; `combined-swift-01.log` contains the executed gate.
The earlier isolated v1 report is retained and has identical ownership counts.
No model inference, fitting, personal learning, device answer substitution or
reserved-writer evaluation occurred.

Both existing grouping policies produced the same isolated ownership partitions:

| Coordinate arm | Complete single-character ownership / 1,552 | Split records |
| --- | ---: | ---: |
| Maximum dimension 24 points | 1,203 | 349 |
| Maximum dimension 32 points | 1,192 | 360 |
| Maximum dimension 48 points | 1,150 | 402 |
| Unmodified public coordinates | 1,142 | 410 |

Every source index was covered exactly once: no missing, duplicated or invalid
indexes. Lossless reconstructed inputs were exact. Legacy grouped inputs had
8, 12, 8 and 13 actual input/order mismatches in the arms above, respectively;
these are not evidence of dropped geometry. The complete 32-point cohort had
1,192 raster comparisons under each policy and zero pixel mismatches or failed
comparisons. This checks only the measured complete groups, not all split groups.
At 32 points, uppercase A–G retained one-character ownership for 110/112 examples
(F 14/16, all other roots 16/16). Disconnected dots, punctuation and accented
characters contributed many splits; all sixteen lowercase j examples split.
The overall split rate must not be presented as a full-chord error rate.

The six synthetic pair arms also had identical exact-match and cross-owner
merge counts under the two policies. Split-owner counts below are specifically
the lossless policy; the legacy policy's wrapper semantics produce slightly
different split-owner counts and remain separately recorded in JSON.

| Second character maximum dimension | Gap | Exact two-owner matches / 1,552 | Cross-owner merged groups | Split owners |
| --- | ---: | ---: | ---: | ---: |
| 16 points | 3.2 points | 886 | 174 | 612 |
| 16 points | 8 points | 979 | 1 | 650 |
| 16 points | 16 points | 979 | 0 | 650 |
| 32 points | 3.2 points | 774 | 327 | 576 |
| 32 points | 8 points | 914 | 0 | 723 |
| 32 points | 16 points | 914 | 0 | 723 |

Counts have different grains: a pair can contain more than one merged group or
split owner. They must not be added together as failed-pair counts. The compact
spacing arms expose cross-character merging without private handwriting or
expected chord labels entering the partitioner. None of these arms selects a
new threshold, scale or grouping for the app.

Decision: source preservation is necessary but insufficient. The next ML
improvement must address symbol boundaries and representation/vocabulary with
independent ownership evidence, rather than train the recognizer to reproduce
answers to this user's saved chords. Native baseline and explicit review stay
in place; shipping/new-writer accuracy is not established by these diagnostics.
