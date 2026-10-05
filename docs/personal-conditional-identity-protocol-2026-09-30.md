# Conditional visual identity diagnostic — frozen before execution

This is a research-only component diagnostic, not an ownership resolver, a new recognizer, a live app change, or a new-writer accuracy gate. The existing visual encoder, vocabulary, geometry policies and profile are frozen. No weights, thresholds, seeds or labels will be selected from its outcomes.

## Source-only inference seam

Add `PersonalInkLearnedComparison.readSuppliedOriginalGroups(_:originalIndexGroups:currentProfile:)`. Its inputs are original `InkStroke` objects, an ordered partition of original source indexes, and the exact frozen profile. There is no intended-answer, expected-group-count, glyph-label, prompt, accept, render or teach input/API.

Validate the encoder's existing prepared-feature geometry limits and complete, nonempty, unique, in-range coverage (1–16 groups). Unlike the app's whole-chord/profile-learning shape gate, the conditional glyph diagnostic must retain valid single-point/zero-extent glyphs supported by the rasterizer; it must not normalize, pad, drop or invent ink. Preserve outer group order; sort indexes within each group to preserve original acquisition order and reconstruct the exact original stroke objects/metadata. A complete partition is not evidence of correct ownership. Return source-index receipts and generic/personal/anchored glyph ranks only, with no resolved/confidence/accepted-chord state and no whole-chord rescue. Reuse the existing ranking loop; preserve all historical prediction routes and serialized reports.

## One bounded public execution

- Source: existing UJI `ujipenchars2.txt`, SHA-256 `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
- Population: the same eight already-observed development writers selected by `PublicGlyphOwnership.developmentRecords`; all 1,552 samples, 97 labels, two sessions. They are diagnostic data, not fresh or sealed evidence.
- Reader: unchanged pinned Core ML visual encoder, its complete 97-way vocabulary. An enabled empty profile gives no personal support fit. Primary scores use generic ranks only; no restricted A–G classifier, additional lessons or private profile.
- Arms: all isolated samples normalized to 32-point maximum extent; and the existing deterministic two-owner construction with both glyphs at maximum extent 32 and gap 8. `PublicPairOwnership` is file-private and its file is retained hash-bound evidence, so copy its exact deterministic constructor into the new diagnostic helper, bind the original file hash, and test its metadata/golden construction. Do not edit retained helpers, select an answer-dependent subset, or introduce a different spatial rule.
- For each query, freeze the reading from source-provenance owner groups and from automatic lossless geometry groups before joining source glyph labels for scoring. Query identities and inputs bind to source/code/model hashes. Known source concatenation establishes public ownership; intended text never establishes grouping.
- No reserved-writer trajectories may be transformed, inferred on, scored or used for fitting/selection. No private chart ink, device pull, dataset download or model training in this execution.

## Separate measurements

1. Oracle/source-owner generic top-1 glyph identity, all 97 labels, with per-writer/per-label counts.
2. Automatic exact ownership partition and ordered group correspondence, independently of identity.
3. Automatic identity only where a group exactly equals one source owner; no desired-answer alignment of merged/split groups.
4. Full ordered top-1 token sequence equality, before chord parsing; public non-chord symbols cannot become grammar failures.
5. Paired oracle/automatic token outcomes and per-writer denominators. Preserve every query including read failures; do not drop wrong groups or unsupported symbols.

Invalid source partition is a hard error before encoding. Invalid/oversized source ink is a hard diagnostic error, not a silent exclusion. Technical encoder errors fail the execution; no partial report is a successful result. Write one immutable result with all row receipts and model/source/code identities.

## Gate and interpretation

Use focused nonzero Swift tests for partition validation, original metadata/order, stale/disabled profiles, shared ranking equivalence, no whole-chord encode, and unchanged legacy/selective behavior. Run the actual compiled Core ML model, not a mock, for the public diagnostic. Preserve retained V1–V4 source/checkpoint/report hash bindings.

This test identifies measured component weaknesses on observed public writers. It cannot justify another fit on those writers, improved live recognition, calibrated ownership, natural full-chord accuracy or ship readiness. Natural handwriting still needs blinded independent ownership/isolated-glyph annotation and fresh writer-disjoint evaluation. The annotation path must not show intended chords, recognizer suggestions or personal profiles to ownership reviewers.
