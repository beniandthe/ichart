# BHMSDS auxiliary raster intake

Status: source acquired and decoded; not adapted, fitted, exported or used to
claim recognition accuracy. This source is separate from all holdouts.
The creator describes 27,000 cropped/scaled photographed symbols from only
a few people, declares the dataset MIT-licensed, and documents literal plus
and slash symbols. Preserve the archived notice; writer diversity is limited.
Primary source: [creator repository](https://github.com/wblachowski/bhmsds).

## Pinned source and observed inventory

Creator commit `07d208e41923b061e338c241e59daacdd2752d53`.
Archive SHA `5e109303251854908f361e35bf260ebb30248fa9967bd70d2bf3703df11a5274`.
Compressed bytes 15,738,590; 27,006 ZIP entries / 10,048,408 expanded bytes.
An exact-prefix/path/regular-file/budget inventory precedes PNG decoding.
The archive is read in place, not indiscriminately extracted.

The actual source has 18 filename labels with exactly 1,500 images each:
`0` through `9`, `dot`, `minus`, `plus`, `slash`, `w`, `x`, `y`, `z`.
IDs are four-digit `0000` through `1499`. All 27,000 decode as single-frame
28x28 eight-bit grayscale PNGs with black foreground / white background.
All pass the raster-validity check; this is not semantic label verification.
There is one raw-PNG duplicate pair, also one decoded-pixel duplicate pair,
within the same source label. Both rows remain; no silent deduplication.

The archived README lists `*` while filenames use `dot`. This inconsistency
is explicit; neither a star nor a dot canonical mapping has been invented.
All rows retain literal filename labels and `canonicalCodepoint=null` pending
a separately reviewed model adapter. Missing symbols such as sharp, half
diminished and major triangle have not been synthesized from this source.

## Contract and verification

Every source row retains its original archive member, source index, raw PNG
hash and geometry-framed native pixel hash, without inversion or fake strokes.
Writer/session IDs remain null. Flags explicitly say auxiliary-training-only,
no new-writer evidence and no observed trajectory. It may inform a future
image branch; it does not provide genuine Pencil trajectories or a writer split.

Eight synthetic contract tests passed, zero skipped, with warnings as errors.
Tests include pinned source identity, exact zero-padded names, unsafe/archive
budget rejection, missing/extra classes, invalid/empty/full raster retention,
raw/pixel duplicates across labels, archived notices and non-overwriting output.
Python 3.12.14 / Pillow 11.3.0. Actual source validation retains all 27,000 rows.
A separate read-only verifier imported no intake or model code. It decoded
every original PNG, reproduced each raw/native-pixel hash, reconciled literal
IDs, flags, dimensions, counts and duplicate groups, and byte-compared original
README/LICENSE files. All rows matched, with unchanged inputs and importer.

Temporary evidence: `/private/tmp/iChartBHMSDSIntake-20261001.IQHIVH`.
Durable evidence:
`/Users/benirossman/.local/share/ichart/recognition-development/bhmsds-intake-20261001.IQHIVH`.
The preservation receipt verifies all copied artifacts/source snapshots;
the archive and original temporary evidence were not deleted.

| Artifact | SHA256 |
|---|---|
| Intake source | `b650d422abe7963132087e72af9d0b0daafd74818003e2f00948dadee1a85590` |
| Intake tests | `564b7ceef7f26602eed82ca92d22cba4237b0894cb5e4554a783f9d3b4484a51` |
| Source row manifest | `11ffacca4dcf924e1479fec5c9418d0b75cc4ef332fa3c8c716abdc95988ef82` |
| Source receipt | `30a13c61177d87e7d47c28e3c739d38db862d0eaf859bd28e5d8e8c08dcd6a3d` |
| Archived README | `ef820e2e1984633ec68eabbd34c42213f360bff3d1fdd14c5e237d0b46c0c6c6` |
| Archived MIT notice | `5392ff373b71d9a49e7809d5de60d01c9fd55885df48c726b45a232f4df110f7` |
| Independent verifier | `09b23d966530550a5150fa9b67a54b60ae0fc7c6c6a6ffc1d171956696bfc1e6` |
| Independent result | `8e5296dace9cc9b9fa8f60ab7db29b217cc79fb2db415b58c072321ee77cc438` |

No recognition experiment, app change or shipping permission is implied by
this intake. A future adapter needs explicit symbol/polarity/geometry review,
duplicate-aware training use and source-license notice retention. The present
all-class centroid experiment does not use these rasters.
