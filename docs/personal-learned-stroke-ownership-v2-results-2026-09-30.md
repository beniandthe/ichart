# Learned stroke ownership v2: measured results

Outcome: the fixed revision improves the retained three-character stress and
isolated A-G ownership, but regresses all six matched pair arms versus v1 and
still fails the unchanged comparison-only integration gate. Do not install or
promote it. These are public ownership-component measurements, not chord-reading,
personalization, fresh-writer or shipping results.

## Executed evidence

Evidence directory:
`/Users/benirossman/.local/share/ichart/recognition-development/learned-ownership-v2-20260930.YfLpW7/`

- `combined-unit-tests.log`: 69 executed, 69 passed, zero failures/skips. This
  includes exact direct-versus-bounded statistics, minibatches, final parameters
  and losses over 4,250 synthetic rows crossing 4,096/512-row boundaries.
- `provenance-recheck.log`: two affected tests executed and passed after adding
  the retained comparator/test hashes. This four-line provenance repair changed
  no features, targets, weights or model mathematics.
- `training-plan.json`: metadata-only preflight before fitting.
- `fit-v2/report.json`: one fixed 30-epoch final fit; 32 training writers, 6,208
  source characters, 117,952 derived targets, 1,207,443 unordered stroke-pair rows.
  Single/pair/triple/quad training contexts; no five-character training context.
- `evaluation-v2/report.json`: eight observed development writers, 1,552 source
  characters reused across 25 arms, 38,800 partition checks. Those checks are not
  38,800 independent handwriting samples or complete handwritten chords.
- `baseline-join-v2.json`: strict exact-case joins to unchanged code-bound Swift
  geometry reports and all eight retained v1 arms. The other 17 arms have no
  historical comparator. All arm/writer denominators and summaries reconcile.

The artifact is a 15,105-parameter model with SHA-256
`06add177488c76f91ce466d0e5ba35c756dfb9547611697a9569658d2193f72e`.
All 17 source/protocol/test bindings match the current frozen files. V1 source,
protocol, tests, weights and reports remain intact. No private ink, personal
lessons or the 20 reserved writers entered fitting or model evaluation.

## Matched results

Every denominator below is 1,552. Exact means every original source stroke
belongs to the correct character owner, not merely that the group count matches.

| Context | Lossless geometry exact | V1 exact | V2 exact | V1 -> V2 gains / harms | Geometry / V2 merged targets |
| --- | ---: | ---: | ---: | ---: | ---: |
| Isolated, dimension 32 | 1,192 | 1,538 | 1,539 | 4 / 3 | 0 / 0 |
| Second dimension 16, gap 3.2 | 886 | 1,539 | 1,530 | 3 / 12 | 174 / 0 |
| Second dimension 16, gap 8 | 979 | 1,539 | 1,532 | 3 / 10 | 1 / 0 |
| Second dimension 16, gap 16 | 979 | 1,543 | 1,536 | 1 / 8 | 0 / 0 |
| Second dimension 32, gap 3.2 | 774 | 1,531 | 1,522 | 4 / 13 | 327 / 4 |
| Second dimension 32, gap 8 | 914 | 1,537 | 1,528 | 0 / 9 | 0 / 2 |
| Second dimension 32, gap 16 | 914 | 1,538 | 1,529 | 0 / 9 | 0 / 3 |
| Triple 32/16/16, gaps 8/8 | No matched Swift result | 1,457 | 1,523 | 82 / 16 | No matched Swift result / 0 |

No matched arm/writer total is below the lossless geometry baseline. Individual
geometry-correct harms remain: 2 isolated cases and 1/1/1/2/3/3 pair cases in the
table's order. These are per-arm cases, not an independent unique-case total.

Isolated A-G ownership is 112/112 versus v1's 111/112 and geometry's 110/112.
This does not establish that those letters were classified correctly. There are
zero new geometry-correct A-G ownership harms. No B-specific rule or private
expected-answer substitution was introduced.

The retained triple has 0 merged targets and 29 split targets, versus v1's
83 merged and 13 split targets. The net gain is 66 exact partitions, comprising
82 gains and 16 harms. V2 jointly changed pair geometry, training contexts and
weighting; these results do not isolate the effect of any one change.

The unchanged gate still rejects V2 because second-dimension-32 gaps 8 and 16
have 2 and 3 merged targets respectively where geometry has zero. The corresponding
v1 counts were 2 and 2. `eligibleForComparisonOnlyIntegration` is false.

## Longer contexts and source safety

The six four-character arms range from 1,483 to 1,517 exact partitions per 1,552;
their merged-target counts range from 3 to 13 and split-target counts from 32 to
62. Five-character evaluation-only arms range from 1,467 to 1,511 exact; merged
targets range from 6 to 11 and split targets from 33 to 81. These are reused
characters in fixed synthetic placements, not natural chord-writing coverage.

All 831 failures in the 17 new arms remain in the comparison report. Merged and
split target counts can overlap and must not be summed as distinct failures.
Every one of the 38,800 partitions covers all original indexes exactly once:
zero missing, duplicated or invalid indexes. Correct coverage is not correct
recognition.

## Weighting, independence and timing

Base loss mass before global class balancing is approximately one at each
cardinality. Final single/pair/triple/quad masses are respectively
1.25030469 / 0.94668397 / 0.91090567 / 0.89210567, summing to four; positive and
negative class masses are approximately two each. Final weights determine both
ordered-direction feature statistics. Zero dimensions reached the 1e-6 floor.

Five development source records have normalized-trajectory copy exposure to
training across three fingerprint groups, all period/dot cases. The fixed cohort
retains them, with no score-conditioned exclusion. Within-training/development
duplicate counts remain eight/two. Development is observed research data; the
20 official test writers remain sealed.

Optimizer time was 80.25 seconds; evaluation took 278.45 seconds on desktop
Python. Median/p95 feature-plus-inference-plus-decoder times were approximately
0.135/1.425 ms isolated, 1.517/4.790 ms for second32-gap8,
4.476/9.870 ms for the retained triple, and 12.583/24.768 ms for
five32-16-16-16-16-gap8-8-8-8. These are not iPad, Swift/Core ML or live Pencil
latency measurements.

No app build, device install, recognition-route change, chart/profile mutation,
commit, push, backend or production change occurred in this experiment.

## Next bounded experiment

Keep V1 and V2 immutable. Run one controlled feature-family ablation: preserve
V2's broader contexts, weights, architecture and fitting schedule, but use the
original whole-context V1 feature family. This separates that feature change
from the joint V2 revision; it does not insert a spacing cutoff, B repair,
answer-conditioned rule or confidence threshold chosen to erase these failures.
Freeze its separate protocol before implementation or predictions. A passing
component gate still requires runtime parity, responsiveness and genuinely fresh
full-chord tests in both styles plus a different writer before quality claims.
