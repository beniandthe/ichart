# Gesture stroke boundary comparison

Test one concrete representation defect before another model fit. The legacy
template reader concatenates all stroke points before arc-length sampling.
It therefore allocates samples to invisible pen-up jumps. Two drawings with
the same flattened points and stroke count can receive identical normalized
geometry even when their drawn segments differ. This is a source-derived
mechanism, not proof that it caused a particular user's misread.

## Candidate and unchanged behavior

Add an explicit comparison mode that resamples each nonempty stroke separately.
Preserve both endpoints of every positive-length stroke and at least one point
from every dot or zero-length stroke. Distribute the remaining fixed sample
budget deterministically by within-stroke arc length.
Return no normalized template if that budget cannot preserve every stroke.
Preserve acquisition order, global bounds, isotropic scale, sample centroid,
distance, templates, heuristics, candidate limits and downstream grammar.
Single-stroke normalization uses the original resampler unchanged. The cache
key includes the normalization mode.

The existing joined-path mode remains the default. Do not enable the candidate
in grouping, live recognition, teaching, trust probes or the editor during this
comparison. No pipeline-version change, app installation, profile migration or
saved-ink rewrite is warranted by a comparison-only implementation. The learned
trajectory encoder already preserves stroke boundaries and remains unchanged.

## Checks before result interpretation

Synthetic tests must demonstrate the old boundary-collapse counterexample,
absence of interpolated points in a pen-up gap, single-stroke parity, finite
fixed-length output for dots and degenerate paths, deterministic allocation,
capacity rejection, source immutability and cache-mode isolation. Run existing
gesture, baseline recognition, maximum-trust, grouping and domain-boundary
tests without changing their expectations.

Use only the existing standard JSON fixtures in `iChartTests/Fixtures/Ink`,
excluding `InkReview`. Pin the full filename and byte-hash inventory before
executing the candidate. This archive is previously observed regression data,
not training, a sealed holdout or independent handwriting evidence. Do not load
the iPad's current ink, teaching profile or evaluation journal.

The pre-execution inventory has 660 files. SHA256 of the UTF-8 compact JSON
array of ASCII filename-sorted `{name,sha256}` records is
`d1a7e076a6040619a6ac8a0450c20c89888ff42885fdc2f6b82e38e1e645a874`.

For every fixture, freeze both readers' ranks on the exact same clusters from
the unchanged clusterer before joining expected glyphs. Keep fixture hashes,
original stroke ownership, all clusters and both complete candidate lists.
Do not choose fixtures, cluster boundaries, labels, candidate limits or rules
from outcomes. A separate host-side scorer joins the frozen result with the
existing fixture expectations. Count-mismatched fixtures are reported
separately; never truncate paired arrays to make them align. Report exact top
glyph counts, corrections, regressions and unread outcomes on aligned fixtures,
plus the full unscored mismatch denominator. Complete-chord quality and
grouping quality are not measured by this isolated glyph comparison.

## Decision boundary

A structurally correct sampler is not sufficient to replace the reader.
Any lost correct top glyph blocks live adoption in this pass; report gains and
harms rather than tuning around the failed examples. Preserve the candidate
offline if blocked. A clean regression comparison would permit a separately
planned consistent integration across grouping and recognition, followed by
fresh writing in both chart styles. It would not establish user-agnostic
accuracy, ML personalization benefit, calibration or shipping readiness.
