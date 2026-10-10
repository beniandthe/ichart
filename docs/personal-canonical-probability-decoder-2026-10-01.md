# Full-distribution canonical chord hypotheses

2026-10-01, comparison/research only. No live recognition, review acceptance,
rendering, learning, chart, profile or device-install change.

## Implemented boundary

`PersonalInkMLCanonicalProbabilityDecoder` is a new, separate decoder. The
historical additive top-three composer is preserved for reproducible controls.
The new `PersonalInkLearnedComparison.readSuppliedOriginalCanonicalHypotheses`
seam obtains the full generic softmax vector through the existing encoder,
without substituting any personal residual ranking or intended answer.

The seam requires the lossless-source comparison route, a current enabled
profile and complete/disjoint supplied source-index groups. Legacy and selective
unresolved-ownership routes cannot call it to bypass their stop. These checks
establish structural coverage, not correct visual ownership or reading order.
Every group's original stroke values and acquisition order are retained.

## Decoder behavior

- Accept finite full categorical distributions, unique NFC single-scalar
  labels, including alternatives below the historical three-rank cutoff.
- Search a deterministic bounded Cartesian lattice using summed log
  probabilities. Parse complete paths only; never discard an unread token to
  turn a partial string into a valid chord.
- Combine raw paths with the same canonical display using log-sum-exp, yielding
  distinct candidates rather than duplicate `Cm7` / `C-7` display rows.
- Keep exact tokens, input indexes, ranks, per-column probabilities, source-index
  groups and path scores for every observed alias.
- Account for examined, grammar-rejected, accepted, omitted and unexamined mass.
  Partial canonical mass is a lower bound; unexplored mass supplies a
  conservative upper bound. Result caps do not silently terminate search.
- A disclosed near-tie numerical guard prevents a tiny floating-point margin
  from producing a ranking-only certificate. Neither a certificate nor legal
  grammar is handwriting confidence, calibrated probability or a trusted read.

The product of column probabilities assumes conditional independence under
the supplied groups. Input sum-drift normalization uses the whole distribution,
never only grammar-valid survivors. Huge Cartesian counts are represented as
overflowed bookkeeping rather than rejection of otherwise valid ink.

This does not manufacture absent generic glyph classes, fix a wrong partition,
or replace live recognition. There is intentionally no automatic render or
teaching path, and no claim that the new hypotheses improve natural handwriting.

## Executed verification

Xcode 26.6, normal Debug, canonical iOS 26.5 iPad Simulator:

- Build-for-testing passed after generation from `project.yml`.
- Decoder, new adapter integration, historical composer/hypothesis integration
  and project-configuration gate: **62 passed, 0 failed, 0 skipped**.
- Existing learned-comparison/blind-freeze regression gate: **37 passed,
  0 failed, 4 skipped**. Skips are optional externally supplied Core ML/source
  export tests without their required fixture/runtime/output environment; they
  are not evidence of new model or natural-ink inference.
- Counts confirmed from `xcresulttool`, not command exit alone.

The 14 new decoder/integration tests include rank-four recovery, coherent joint
ordering versus the additive counterexample, canonical alias aggregation, mass
and tail bounds, cap/overflow receipts, malformed distributions, exact-ink
adapter input, no historical-read change, and stale/disabled/invalid/unsupported
requests stopping before query encoding. All are synthetic/invariant evidence.

Test bundles and summaries are retained with the cross-writer experiment under
`/private/tmp/iChartCrossWriter-20261001.76JPPS` until durable preservation.
No physical iPad build, install, Pencil interaction or fresh writer test occurred.
