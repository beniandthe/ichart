# HASYv2 auxiliary raster intake contract

Purpose: source-quality and missing-symbol coverage audit only. No model fit,
recognition inference, app change, chord-label mapping or writer-generalization
claim. Preserve native classes; canonicalCodepoint remains null on every row.

Official source: https://zenodo.org/records/259444, HASYv2.tar.bz2.
Published MD5: fddf23f36e24b5236f6b3a0880c778e3.
Downloaded bytes: 34,597,561. SHA256:
7c3ffe709e8c2b83f6ab7d8afc79f7b5f46421657981b1752d22a0ed0052aa2d.

Preflight headers/CSV inventory (no raster inference): 168,261 regular files,
13 directories, 149,489,023 expanded member bytes. Exactly 168,233 labeled PNG
paths and 369 native classes; each class's observed count matches the sum of
symbols.csv training_samples and test_samples. The archive README's 168236
image claim is inconsistent with this inventory; do not invent three images,
require contiguous filename numbers, or silently drop source rows.

Intake must stream/read regular tar members in place; never extractall, execute
hasy_tools.py or load pickle caches. Bound the archive to 40 MiB, members to
180,000, total expanded bytes to 256 MiB, PNG members to 64 KiB, text/CSV members
to 16 MiB. Reject duplicate or unsafe names, links, devices, unexpected paths,
or corrupted joins. Directories must be the observed root/task/fold directories;
regular files must be hasy-data/v2-*.png or the observed 28 text/CSV files.

Validate unique image-path grain, native symbol_id -> latex integrity, every
PNG/source-label join, exact 369 classes/168233 rows and all class counts. Keep
raw PNG hash and framed native decoded-pixel hash with dimensions/mode. Decode
all rasters; retain invalid/uniform status rows rather than quietly remove them.
Do not invert/rescale rasters in this intake or invent trajectories.

Preserve sourceUserID as public-source provenance, but mark
writerIdentityReliable=false, sessionID=null, trajectoryObserved=false,
auxiliaryTrainingOnly=true, newWriterEvidence=false and productionEligible=false.
Keep mathematical confusable labels separate, especially number sign/sharp,
slashed lowercase/uppercase letters, empty sets/diameter, triangle/Greek Delta.

Native target families: literal + and /; LaTeX \\#, \\sharp, \\o, \\O,
\\emptyset, \\varnothing, \\diameter, \\triangle, \\vartriangle, \\Delta.
Record each native ID/count independently. This list is an audit selection,
not an approved chord mapping. No outcome-based source removal is allowed.

Audit raw-byte and native-pixel duplicate groups, including conflicting labels.
For all ten supplied classification folds, validate each row against the main
record table, within-partition uniqueness, train/test path overlap, full union
coverage and test assignment multiplicity across folds. Record duplicate pixel
groups crossing train/test, not only identical path overlaps. Those are sample
folds, not reliable writer-independent validation. Verification-task files are
preserved and hashed; no verification-task model/evaluation is run in this pass.

Preserve archived README and helper as inert source evidence. The paper declares
ODbL for the dataset; software MIT is not dataset permission. Archive lacks a
separate individual-content grant. This local intake provides no shipping or
trained-model licensing clearance; those questions remain unresolved.

Use a fresh exclusive output directory outside Git; bind code/tests/contract and
source hashes, row manifest, per-class/fold summaries and duplicate ledgers in a
receipt. Recheck hashes before publication. Synthetic intake tests and actual
source inventory are engineering/data-quality evidence, not recognition gains.
