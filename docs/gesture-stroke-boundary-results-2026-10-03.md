# Gesture stroke boundary comparison results

The comparison-only sampler fixes the demonstrated pen-up interpolation
mechanism, but it failed the predeclared recognition regression rule. It
corrected no top glyphs and lost one previously correct top glyph. Keep it
disabled. This is not a recognition improvement or an app-ready change.

## What changed and what stayed fixed

The legacy template reader resamples the flattened point list, including
invisible travel between strokes. Synthetic tests demonstrate that two different
drawings with identical flattened points and stroke counts receive identical
legacy sampling. The candidate samples only actual stroke segments and retains
stroke endpoints, while preserving order, normalization and distance rules.

Both template and input geometry use the chosen mode. Removing the artificial
connections is therefore not a simple correction of a training versus runtime
mismatch; it changes the matcher's evidence. It does not make the reader
independent of stroke order or direction. The learned raster and trajectory
encoders already preserve stroke boundaries and were not changed.

`GestureTemplateRecognizerConfiguration` still defaults to `legacyJoinedPath`.
The candidate is explicitly opt-in as `preserveStrokeBoundaries`, and the
normalization cache separates the modes. No live grouping, recognition, trust,
editor or teaching caller was switched. No app was installed on the physical
iPad. No model fit, weight change, profile update, ink edit, commit, push,
upload or release was performed in this comparison.

The existing chord-domain boundary remains intact. The executed tests include
rejection of unsupported glyphs, standalone non-chord fragments, punctuation
stripping and promotion past an invalid top reading. Valid complete forms such
as `C11`, `C13` and `Cmaj7` remain supported.

## Frozen comparison and denominators

Followed the [predeclared protocol](gesture-stroke-boundary-comparison-2026-10-03.md).
All 660 standard fixture files were hashed before candidate execution. The
replay decoded only stroke data, not expected glyphs, and froze both complete
rank lists on the same 2,349 clusters. A separate host process joined the
existing fixture expectations only after the prediction attachment existed.
The source-only test also verifies that changing expected fields does not
change decoded strokes or recognition inputs.

The scored subset contains 592 fixtures and 2,005 glyphs whose expected glyph
count agrees with the cluster count and whose original stroke ownership is
complete. The other 68 fixtures remain in the frozen artifact and exclusion
report: 22 have count mismatches and 59 have missing original-stroke ownership,
with 13 in both categories. No paired arrays were truncated. These exclusions
are input/ownership diagnostics, not findings that the candidate caused those
upstream conditions. A count-aligned expectation order is not an independent
annotation of stroke ownership.

| Existing fixture subset | Glyphs | Legacy correct | Candidate correct | Corrections | Lost correct |
| --- | ---: | ---: | ---: | ---: | ---: |
| All scored glyphs | 2,005 | 1,574 | 1,573 | 0 | 1 |
| Single stroke | 1,256 | 962 | 962 | 0 | 0 |
| Multiple strokes | 749 | 612 | 611 | 0 | 1 |

Wrong top glyphs increased from 431 to 432; neither mode had an empty top
candidate in this subset. Two additional wrong readings changed to other wrong
readings. The sole lost correct glyph was the existing `F` expectation in
`FSharpMinor7Captured03.json`. This identifies the failed regression; it is not
permission to add a fixture-specific correction. No thresholds, templates,
heuristics, sample allocation or exceptions were adjusted after the results.

These are previously observed regression fixtures, not fresh handwriting,
natural full-chord accuracy, writer-independent evidence, learned-model quality
or personalization benefit. The result neither validates the legacy reader's
absolute accuracy nor permits promotion of this candidate.

A separate verifier independently recomputed every paired count, per-glyph
summary, changed row, ownership exclusion and gate without importing the host
scorer. All checked fields agree exactly. It also verified source inventories,
code hashes, full saved rank order and all 344 unscored clusters. The verifier
did not run recognition again or tune the candidate.

## Executed checks

All three serialized Simulator commands completed with exit status zero.
`xcresulttool` summaries and individual test trees confirm nonzero execution:

- 70 integrity and compatibility tests passed, including 11 new sampler tests.
- 161 existing recognition, maximum-trust, grouping and provider-boundary tests
  passed using the unchanged default mode.
- Two replay tests passed and produced the complete frozen comparison artifact.

That is 233 passed tests, zero failures and zero skips. Five existing optional
full-archive tests were deliberately excluded from the first two gates; the
new isolated glyph replay covers the pinned archive without implying a
full-chord or complete ownership benchmark. The Simulator was the iPad A16 on
iOS 26.5. The worktree branch was `codex/recognition-generalization-reset`, at
HEAD `160aa31594903508e241802e21ca83ec447de849` with existing uncommitted work.

The independently reviewed source and test files retained their frozen hashes
after execution, and `git diff --check` passed. The baseline source copy is
explicitly reconstructed by reversing only this candidate's changes; it is
not presented as a pre-edit capture. Its remaining HEAD diff matches the two
preexisting chord-domain filtering changes.

## Evidence files

Durable evidence destination:
`/Users/benirossman/.local/share/ichart/recognition-development/stroke-boundary-20261003.wpxY1c`.
The original gate directory is
`/private/tmp/iChartStrokeBoundary-20261003.Z0fugY`.

| Artifact | SHA256 |
| --- | --- |
| Frozen protocol | `a6251f091e2796f5355f229eb8fb20b57ed4f76eade0f85ae96ec474f3746cd7` |
| Recognizer source | `d6f74ac90e50eb22051799fe3105b6239331e04f8b78d2a1c833a064c42b929c` |
| Sampler tests | `fa6cc2877936bdae2cf116b201a926c9b61441d3283ecc9bf51169e5ec3c6c75` |
| Replay test | `e09ced0c74e8b685d30fbbfd7a174c92bc21a5d0aa5d8917ea6c065146bea333` |
| Paired prediction packet | `ad159ddd072d8be7d170d1351e10f69f38ac41913fc2604c25d758a58ccf58fa` |
| Separate host score | `6008dc2a0838d6bf4d47590dc1db11fa45b0bce2494c4eaeabb389343dc75320` |
| Independent reconciliation | `07a49a2497d0aa8d5f2523795209cd24b57c399bd5f5c1eb3802f25d8d487501` |

The raw packet is the JSON attachment under `replay-attachments`; `score.json`
retains all exclusions, changes and per-glyph counts. The directory also keeps
all three `.xcresult` bundles, logs, test summaries, source inventory and scorer.
