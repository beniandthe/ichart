# Original stroke data for chord symbol research

The original HWRT recordings can supply real pen trajectories for an offline
comparison of image and stroke representations. Source intake and the
creator-defined image join are verified. Model accuracy, canonical chord-label
mapping, writer independence, and release licensing are not established by this
audit. No fitting, inference, app update, private-ink read, or reserved-writer
evaluation was performed in this pass.

This follows the installed chord-only reader boundary. Native source labels
remain source metadata, not newly accepted reader symbols. Nonselected source
classes are counted for integrity checks but their trajectories are not parsed
or retained by the intake.

## Source and provenance

The [HWRT release](https://zenodo.org/records/50022) provides the original
2015 trajectories. The archive has a `.tar` suffix but contains bzip2 data.
The intake verifies its exact size, MD5 and SHA-256 before parsing and again
before publishing its receipt. It reads three regular members in a single
streaming pass, without extracting or executing archive content.

The [creator conversion script](https://github.com/MartinThoma/HASY/blob/acb4401393e97a092f8d2900c81428366b28b070/create_hasy.py)
defines the link to published HASY images: enumerate all test rows followed by
all training rows and name image `i` as `hasy-data/v2-{i:05d}.png`. This is an
archive-bound ordinal identity, not a native recording ID. An independent
implementation checked all 168,233 corresponding metadata rows against HASYv2,
with zero path, native-symbol, LaTeX, or source-user mismatches.

HWRT and HASY represent the same underlying recordings. They must never be
counted as independent handwriting samples. The source-user field is not a
verified writer identity; it is hashed in retained records and explicitly
marked unreliable for writer-disjoint claims.

The creator declares the database ODbL on the
[official data page](https://www.martin-thoma.de/write-math/data/). This audit
does not clear dataset or model redistribution. The source remains research
only; shipping rights require a separate review.

## Executed checks

| Check | Observed result |
| --- | --- |
| Declared native classes | 369, every declared train and test count reconciled |
| Source rows | 151,159 training and 17,074 test, totaling 168,233 |
| Selected native families | 12, totaling 5,507 recordings |
| Selected coordinate validity | All 5,507 have nonempty usable trajectories |
| Selected timing issues | Six recordings have nonmonotonic within-stroke time |
| Selected exact coordinate duplicates ignoring time | Zero groups |
| Exact raw-data duplicates across the full source | Four groups, 14 records, two train/test crossings |
| Full-source raw duplicate label conflicts | Zero; all four groups belong to an unselected class |
| Published selected PNGs found | All 5,507 |
| Current renderer matches published RGB pixels | 5,339 exact, 168 differ |

The 12 selected native labels are `+`, `/`, `\#`, `\sharp`, `\o`, `\O`,
`\emptyset`, `\varnothing`, `\diameter`, `\triangle`, `\vartriangle`, and
`\Delta`. They are coverage candidates for missing musical shapes, not an
approved many-to-one chord mapping. Every retained `canonicalChordLabel` is
null. In particular, similar-looking mathematical labels do not automatically
become the half-diminished chord symbol.

Original coordinates and timestamps remain unchanged. The six timing anomalies
are flagged, not repaired. Coordinate hashing is exact serialization of x/y
arrays without timestamps; zero matches does not exclude normalized-image
duplicates, approximate copies, or repeated samples from the same writer.

The existing, hash-bound HASY decoded-pixel ledger was checked separately.
Its 502 corpus-wide duplicate groups include 132 native-label conflicts,
but none touches any of the 5,507 selected paths, including collisions with
unselected paths. This supports an exact-copy-controlled, record-level paired
split. It does not establish writer independence or exclude approximate copies.

The independent renderer followed the 2017 creator algorithm without parameter
tuning. Under Pillow 11.3.0, the 168 nonidentical images each differ by 1–7 RGB
pixels. No regenerated PNG was byte-identical. The composite reproduction
check therefore correctly reports failure even though the recording metadata
join passes. Use official published PNGs when claiming the HASY raster view;
do not silently replace them with modern rerenders.

## Implementation and verification

`recognition_ml/ichart_recognition_ml/research/hwrt_source_intake.py` implements
the pinned intake. Its production CLI has no archive-checksum override and
writes outside Git into a new directory. It rejects unsafe, duplicate,
unexpected, linked, oversized, and missing archive members; validates CSV
schema and counts; and publishes the source receipt last. Invalid selected
geometry would remain in the output with issues rather than being dropped.

Seven synthetic tests executed with warnings treated as errors: seven passed,
zero failures, zero skips. The real archive intake then completed successfully.
A separate inventory script and independent creator-join verifier supplied
cross-checks. Root reconciliation confirmed artifact hashes, source/test
identities, all per-family counts, selected ordinal uniqueness, retained
timing flags, and the failed full-pixel-reproduction result. These are source
integrity checks, not recognition-accuracy tests.

The exact intake module SHA-256 is
`ef183816e3f22cc72d9fd56e7ef8796d22547f0b085431984f7dfab9bc9abf92`;
its test SHA-256 is
`a32f7faea180053afea9ce0b2bc2d175abdd9d484067838b6a6862e8fb403a72`.

## Evidence and next decision

Durable local evidence is retained under
`/Users/benirossman/.local/share/ichart/recognition-development/hwrt-source-intake-20261003.hFiI3y`.
It includes the original archive, inert creator-source snapshot, independent
inventory, intake outputs, duplicate ledger, join and pixel report, executed
checks, source/test snapshots, and earlier failed execution logs.

The next decision is a frozen, matched representation experiment using the
same underlying recordings in both arms. Before fitting, fix the musical
label mapping, copy-aware split, exact input representations, training budget,
and old-symbol harm criteria. Published-image comparisons and app-raster
controls must be named separately. Do not infer writer independence from the
source user IDs, treat synthetic combinations as fresh chords, or reuse the
user's labeled queries as new evidence. No learner is promoted by this audit.

The paired runner must bind the HWRT receipt, HASY labels and pixel ledger,
creator script, and independent join report. Keep the trajectory and image
of each creator ordinal in the same split. The HWRT intake receipt alone
does not attest the cross-source pairing.
