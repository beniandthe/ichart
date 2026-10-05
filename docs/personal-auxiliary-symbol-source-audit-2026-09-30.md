# Auxiliary symbol sources — bounded source-quality audit

No dataset download, training, private-ink read or reserved-writer evaluation was performed for this source audit. These are candidate training sources, not independent evidence of app accuracy.

## HWRT / HASY

The creator's [HASY paper](https://arxiv.org/html/1701.08380v1) says HWRT contains online point-sequence recordings and HASY is their 32×32 raster derivative, with exactly the same recordings/classes. Do not count them as independent corpora. Its symbol tables include sharp, slash, plus, triangle/Delta, and slashed-circle visual classes. Slashed-circle mathematical/letter labels are visual proxies, not music-half-diminished semantic labels.

The author explicitly warns that user IDs do not reliably identify writers: pooled Detexify recordings share one ID, people can share accounts, and anonymous writers can have multiple IDs. Consequently, these data cannot establish a new-writer gate. The paper declares an ODbL dataset license; commercial inclusion requires resolving the applicable obligations rather than assuming the paper's license controls the data.

[HWRT's official record](https://zenodo.org/records/50022) describes trajectories plus user-ID metadata. Genuine trajectories may support an auxiliary development experiment. Derived rasters must retain the same recording identity/provenance; raster-to-vector paths must never be presented as observed pen strokes.

## JAZZMUS

The [creator paper](https://arxiv.org/html/2509.05329v1) describes photographed/scanned jazz lead sheets, not online stroke trajectories. Its official split is by musical piece, not a demonstrated writer-disjoint split. Labels represent semantic chord equivalence; the authors explicitly did not relabel every image to match the exact handwritten spelling, such as maj7 versus triangle7. These labels therefore cannot directly supervise exact glyph ownership or every symbol variant without additional annotation.

The [official dataset card](https://huggingface.co/datasets/PRAIG/JAZZMUS) declares CC-BY-NC-4.0 and gated access. Public source/code availability does not authorize commercial dataset use. Do not place this dataset in the shipped-model training path without separate clearance; do not accept gates or share contact information on the user's behalf.

## Decision

Do not replace the customizable pipeline with either dataset's recognizer. HWRT is a plausible auxiliary true-stroke source for missing visual atoms after license/label/overlap review. HASY does not add independent samples, and JAZZMUS is not directly usable commercial atomic supervision as published. Neither replaces a genuinely writer-disjoint, app-domain test with reliable writer identity and blinded ownership/glyph annotation.
