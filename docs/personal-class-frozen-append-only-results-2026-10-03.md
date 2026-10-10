# Class frozen learning comparison results

The fixed public-handwriting screen completed on 2026-10-03 and rejected this
candidate for app integration. Freezing untouched correction columns preserved
their scores exactly, but did not prevent changed columns from overtaking them
or creating new permitted reads from previously unresolved inputs. The live
personalized reader, private profiles and chart ink were not changed.

## Scope and fixed decision

The protocol is `personal-class-frozen-append-only-protocol-2026-10-03.md`,
SHA-256 `582d403c069a8650785e111e15731dce8945283dfc963cc0432564769ab6b39b`.
It was recorded before the fits or candidate predictions. The lambda, teaching
history, domain, sample schedule and rejection gates were not retuned after
scoring. The full-refit arm remains a diagnostic control, not a replacement
selected from this result.

Both encoder views reused the same eight public development writers and 776
distinct session-two samples. Each writer retained the original ten-example
history and appended eleven explicitly labeled lessons. No query label entered
a fit; all support bytes, vectors and weight snapshots were frozen before any
query prediction. A separate scoring command opened truth only after validating
the complete prediction freeze, including exact reproduction of every learned
score from its saved weights.

This is an isolated-glyph development screen, not complete-chord accuracy,
fresh handwriting or two independent datasets. The original app-runtime cache
still has unverified training-writer membership. The CE-control fit records 32
training writers disjoint from these eight development writers. Neither view
establishes user-agnostic app recognition. No private or reserved handwriting,
new participant, new raster or encoder inference was used.

## Read counts

Each raw domain cohort contains 328 samples: 80 old-label, 88 added-label and
160 remaining-label samples. The domain comes from the actual Swift reader
policy. The raw 97-class winner is rejected when outside it; an allowed runner-up
is never promoted. Permitted glyph fragments are not necessarily valid standalone
chords, and raw model outputs remain forensic data, not reader suggestions.

| Encoder view | Arm | Correct | Wrong permitted glyph | Unresolved |
| --- | --- | ---: | ---: | ---: |
| Original app runtime | Generic | 275 | 22 | 31 |
| Original app runtime | Reference 10 | 271 | 29 | 28 |
| Original app runtime | Full refit 21 diagnostic | 278 | 27 | 23 |
| Original app runtime | Class frozen 21 candidate | 276 | 29 | 23 |
| Writer separated CE control | Generic | 270 | 26 | 32 |
| Writer separated CE control | Reference 10 | 265 | 34 | 29 |
| Writer separated CE control | Full refit 21 diagnostic | 271 | 33 | 24 |
| Writer separated CE control | Class frozen 21 candidate | 267 | 36 | 25 |

The existing source-copy exclusions remove four correctly read dot samples in
every arm. Thus the no-copy domain cohort is 324: every correct count above is
four lower, and wrong/unresolved counts are unchanged. Old/added cohorts remain
80/88; the remaining cohort is 156. No exclusion was chosen from these results.

## Gains and harms

The comparison baseline is the fixed ten-lesson reference, not whichever arm
looks most favorable. Raw and no-copy paired outcomes are identical.

| Encoder view | Gains | Harms | Net | Old-label harms | Remaining-label harms | Lowest writer net |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Original app runtime | 5 | 0 | 5 | 0 | 0 | 0 |
| Writer separated CE control | 5 | 3 | 2 | 0 | 3 | -2 |

All gains occurred in the eleven added labels. All 86 untouched correction
columns and their scores are bit-identical across all valid queries. The three
CE-control literal-glyph regressions are `n → m`, `º → o` and `u → m`; the latter
two occur in the same writer. Although `º` and `o` can be equivalent diminished
aliases in chord context, this predeclared screen measures exact glyph labels.
That literal regression is not evidence of a wrong complete chord. The metric
was not changed after seeing it; the other harms and out-of-domain gate already
prevent promotion independently.

## Rejection of unsupported inputs

Both views also scored all 448 out-of-domain samples. These are secondary
source-level false-permitted-glyph counts, not accepted complete chords.

| Encoder view | Generic false permitted | Reference false permitted | Full refit false permitted | Candidate false permitted | Newly permitted where reference was unresolved |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original app runtime | 40 | 43 | 45 | 46 | 3 |
| Writer separated CE control | 38 | 42 | 42 | 45 | 3 |

The zero-new-out-of-domain-read gate fails in both views and both raw/no-copy
cohorts. The CE-control view additionally fails the zero-untaught-harm and
nonnegative-every-writer gates. Positive aggregate net does not override those
failures. The candidate remains offline and is rejected without retuning.

## Verification and artifacts

Parent verification executed 22 Python tests with warnings treated as errors:
five unchanged residual tests, six class-frozen invariants and eleven evaluator
tests. All passed, with zero skips. Coverage includes nonzero synthetic fits,
exact numeric reproduction, original-source joins, malformed-history rejection,
invalid-row retention, complete denominators and pre-truth tamper rejection.
These passes establish engineering integrity, not recognition benefit.

The bounded independent source review cleared execution before the real fit.
After the freeze, a separate verifier reconstructed the entire score object
from all raw 97-score arrays and pinned truth/copy IDs without importing the
evaluator or calling a model. Its reconstruction matched exactly, including
every writer, stratum, harm and failed gate. It independently verified all four
frozen artifacts, nine executed-code hashes, four inputs, five app-runtime
artifacts, the CE checkpoint and all 86 untouched weight/score columns.
The output directory is
`/private/tmp/iChartClassFrozenAppendOnly-20261003.vWyrmK`.
Temporary artifacts may expire; their saved descriptions and hashes do not
make them a shipped app or a fresh device test.

- Evaluator SHA-256: `27145c8334813480b86856f10b63ae50556df39b6ebb979a21b2c1930b43ec53`.
- Evaluator tests SHA-256: `df69fd3c4c677d3383c38fdbe1a88892879acd65726450fb4c152ebd46422a71`.
- Structural test log: `205a0defb867c671d40207353d9c678e04b08d998d859b93a9dc8b94d4b6a4e4`.
- Freeze receipt: `6eeaad5be9f59c829c256668d920a2468b024c3eea32ebaefeb535491d8584cc`.
- Frozen predictions: `bcf6094a28a95ec12e371d23d4f8a40258281799c0c169762876089c1a4437ec`.
- Separate score: `e5a5d1c3dc4eb666eb87e99429eaaceb925b72b2e6a571f7576f3109aa92a112`.

The separate chord-only reader boundary remains implemented and locally tested;
see `chord-reader-domain-boundary-2026-10-03.md`. This failed learner screen does
not undo that boundary or justify promoting the learner. No iPad install,
launch/Pencil test, commit, push or production deployment occurred here.
