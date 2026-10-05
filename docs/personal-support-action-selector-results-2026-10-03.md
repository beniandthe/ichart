# Personal lesson action selection results

The fixed selector is rejected. Learning explicit helpful versus harmful actions
preserved the baseline on deferral and produced net gains, but still replaced
correct and unresolved readings with wrong ones. It must not enter the app or
be tuned against these outcomes. This result does not invalidate personalized
learning generally; it rejects this particular frozen matcher and linear action
selector combination.

## What was tested

The [fixed protocol](personal-support-action-selector-protocol-2026-10-03.md)
used existing A16 to B16 public predictions. The baseline and matcher were not
refitted. A linear classifier learned only from the first eight B writers;
the remaining eight were a one shot reused development check. The check writers
had already contributed to previous results, so this is not fresh or independent
recognition evidence, and it does not measure complete handwritten chords.

The fit used 561 eligible no copy exposures from 380 distinct writings: 59 HELP,
52 HARM, and 450 NEUTRAL. Inverse exposure weights gave total class weights of
40.5, 38.5, and 301 respectively. The fixed 1000 step fit completed with finite
loss and final loss 0.3578722148117581. Runtime was Python 3.12.14, PyTorch 2.7.0,
NumPy 2.0.2, deterministic CPU four threads, float64, and no batch normalization
updates. Neither private ink nor the reserved writer data was used.

## Reused check outcomes

Each catalog contains the same 1552 distinct writings from eight writers and
two sessions. Do not add their denominators together as independent samples.
The raw cohort contains 656 permitted glyph queries and 896 outside the domain.
The existing no copy cohort excludes four already correct queries, leaving
1548 queries including 652 permitted glyphs. Gains and harms are unchanged by
that exclusion.

| Lesson catalog | Correct baseline raw and no copy | Correct selected raw and no copy | Corrections | Previously correct made wrong | Unresolved made wrong within domain | New outside domain reads | Lowest writer net |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 10 symbols | 536 / 532 | 538 / 534 | 12 | 10 | 0 | 0 | -1 |
| 21 symbols | 536 / 532 | 555 / 551 | 29 | 10 | 2 | 6 | 0 |

All ten previously correct regressions in each catalog occurred on untaught
symbols. Two writers had net minus one with the ten symbol catalog. The larger
catalog had no negative writer net, but that did not satisfy the zero new wrong
read requirement. True support produced more correct final outputs than the
fixed wrong support diagnostic in both catalogs; that signal is not enough to
overcome the safety failures. Wrong support was never fitted, and its old cyclic
donor crosses the B8 split, so it is descriptive evidence only.

Raw baseline totals were 536 correct, 96 wrong, and 920 unresolved. The ten
symbol selector produced 538 correct, 95 wrong, and 919 unresolved; the larger
selector produced 555 correct, 94 wrong, and 903 unresolved. These aggregate
improvements conceal unacceptable individual substitutions, which is why the
paired transition gates take precedence over headline accuracy.

The meta fit summaries also failed safety: the ten symbol catalog had 16 gains,
6 regressions and no new outside domain reads; the larger catalog had 32 gains,
3 regressions, 2 unresolved to wrong transitions and 3 new outside domain reads.
There were no dropped, invalid, or nonfinite check rows. All four check cells
(two catalogs by raw and no copy) failed the frozen safety screen.

## Verification and retained evidence

Ten focused synthetic tests passed with zero failures or skips and warnings
treated as errors. They cover target definitions, numeric and label symmetry,
fallback preservation, weighted fit determinism, duplicate row rejection, and
paired safety accounting. They establish implementation behavior, not accuracy.

A separate standard library verifier reconstructed all eight summaries and
writer cohorts exactly from frozen outputs and the pinned parent score. It
checked all 6208 row joins, exact baseline preservation, 561 fit rows and 380
distinct sources, inverse exposure weights, disjoint writer roles, and every
unique HELP or fallback decision. It reproduced the rejection without model
inference or importing the experiment helpers. The reconciliation receipt hash
is `a699e49e725be77b96da73ced3e849db4587fe058b29a6fb6f2d8b2333fb2ed1`;
the verifier script hash is
`4e4e30acbae0debafc6ed42930fb4bec49e48c3937400c9d71f8fbc187d9077e`.

Execution bundle: `/private/tmp/iChartSupportActionSelector-20261003.8mQD3R`.
Durable evidence destination:
`/Users/benirossman/.local/share/ichart/recognition-development/support-action-selector-20261003.8mQD3R`.

| Artifact | SHA256 |
| --- | --- |
| Protocol | `2508c75f8709c159163dec41c00aa4146dce00ae4d9e531bdc154031a84f0591` |
| Answer free feature freeze | `f10ee93c326d971f72abc6db2964ae98dfc8a9f98e68d916d559d309f51727a8` |
| Meta fit only targets | `c69b1a0a62dd8864b254a3f37d20b82b2ad2a490da34936c36ed9379e71b78eb` |
| Fit and state receipt | `f92ea83001b591fc624f14af406b117343e4ce21d0346ba526d30fc663a01120` |
| Frozen routed predictions | `7bdd20c90e1a1d1bcda54c0f4fa361fbb0dca4bb67c46ff1a372722f93c73331` |
| Paired score | `8dd854db68188191c64163d6f9412784a4e8ad9adb5697c607a36e51b005a6f2` |

The bundle binds the prior prediction source, writer roles, current code and
tests. The fitter received only the first B8 target sidecar. The staging process
read the historical score to create that sidecar; this is an explicit reuse of
already scored development data, not a blind experiment. All routed check
outputs were saved before the separate scorer joined check answers.

The separate [chord only reader restriction](chord-reader-domain-boundary-2026-10-03.md)
remains implemented and Simulator verified. It is not a model promotion and has
not been installed on the iPad. No app, chart, profile, old evidence, or model
weights were changed by this offline selector run. No commit or push occurred.
