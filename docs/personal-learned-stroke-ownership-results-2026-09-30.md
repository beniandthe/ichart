# Learned stroke ownership v1: measured results

Outcome: large public-component gains, but the predeclared comparison-only app
integration gate failed. Do not install or promote this artifact. It is not a
recognition-quality, personalization-quality, new-user or shipping result.

## Executed evidence

Evidence directory:
`/Users/benirossman/.local/share/ichart/recognition-development/learned-ownership-20260930.JSKBX8/`

- `combined-unit-tests.log`: 41 executed, 41 passed, zero failures/skips.
- `fit-v1/report.json`: one fixed final-epoch fit, 32 original public training
  writers, 6,208 source characters and 43,456 derived targets. 154,983 unordered
  stroke-pair rows; 3,161 single-stroke targets excluded only from loss. No private
  ink, personal profile, reserved-writer inference or development model features
  entered fitting. A predeclared trajectory-copy audit used development geometry
  solely for exposure accounting, not fitting or selection.
- `evaluation-v1/report.json`: frozen checkpoint, eight observed development
  writers, 1,552 source characters reused across eight contexts: 12,416 total
  partition checks. These are not 12,416 independent handwritten chords.
- `baseline-join-v1.json`: exact-case join to unchanged, code-bound Swift geometry
  reports, with full/per-writer reconciliation and separate gains/harms.

The 15,105-parameter model's weight SHA-256 is
`63d3925873be5eade2ec30a7a4c3d12d3c3767527f6b9d318b57a3656ae2fff5`.
The frozen protocol and all feature/training source digests are retained with
the artifact. Thirty epochs were fixed before evaluation; no best checkpoint,
spacing arm, threshold sweep or desired-answer substitution was selected.
Source bytes and experiment code remained unchanged during fitting/evaluation.
The combined test's first launch was prevented by sandbox log-write permissions
before execution; the scoped permitted rerun executed all 41 cases successfully.

## Matched ownership results

Primary baseline is the lossless geometry policy. All denominators below are
1,552, using the same development source IDs for each matched arm. A success is
the exact source-owner partition, not merely the correct number of groups.

| Context | Geometry exact | Learned exact | Recovered cases | Newly damaged cases | Geometry / learned merged targets |
| --- | ---: | ---: | ---: | ---: | ---: |
| Isolated character, maximum dimension 32 | 1,192 | 1,538 | 350 | 4 | 0 / 0 |
| Second dimension 16, gap 3.2 | 886 | 1,539 | 653 | 0 | 174 / 1 |
| Second dimension 16, gap 8 | 979 | 1,539 | 561 | 1 | 1 / 1 |
| Second dimension 16, gap 16 | 979 | 1,543 | 564 | 0 | 0 / 0 |
| Second dimension 32, gap 3.2 | 774 | 1,531 | 758 | 1 | 327 / 5 |
| Second dimension 32, gap 8 | 914 | 1,537 | 624 | 1 | 0 / 2 |
| Second dimension 32, gap 16 | 914 | 1,538 | 625 | 1 | 0 / 2 |

No matched arm/writer had a lower total exact-partition count. That aggregate
does not erase individual harms. Isolated A-G ownership was 111/112 versus
110/112 in geometry: two F recoveries, but one new B split. The gate explicitly
forbids this new baseline-correct root failure. The B is a public development
example, not this user's saved handwriting or a new B-specific repair target.

The two wider second-dimension-32 arms also introduced two false-merged targets
each where the baseline had none. Thus `eligibleForComparisonOnlyIntegration`
is false. The standalone triple stress has no matched Swift baseline: 1,457/1,552
exact partitions, 83 merged targets, 13 split targets. Those failure counts can
overlap and must not be added as if they were distinct targets.

Every one of the 12,416 predicted partitions covered every source index exactly
once: zero missing, duplicated or invalid indexes. This is an ownership/source
coverage fact, not proof that symbols were grouped correctly or ink recognized.

## Independence, arithmetic and latency boundaries

Five development source records have exact normalized-trajectory copy exposure
to training, all period/dot examples; three fingerprint groups. They remain in
the fixed cohort and are explicitly recorded, not removed after seeing scores.
There are also two within-development duplicate samples and eight within-training
duplicates. The exposure audit uses the existing eight-decimal normalized
trajectory fingerprint, not a claim of exact raw-source identity.

Training standard deviation range was approximately 0.0111 to 0.6630, with zero
dimensions reaching the predeclared 1e-6 floor. No unseen-bin floor issue was
observed in the training statistics; this does not establish calibration.

Desktop Python evaluation took 12.57 seconds in total. Median/p95 per-target
feature-plus-inference-plus-partition timing was approximately:

- Isolated: 0.129 / 0.688 milliseconds.
- Second dimension 32, gap 8: 0.722 / 2.318 milliseconds.
- Triple stress: 2.252 / 4.658 milliseconds.

These are desktop component timings, not iPad, live Pencil latency or Swift/Core
ML parity. No new iOS build, device install, authentication/billing change,
recognition-route change, personal teaching or private-chart mutation occurred.

## Next bounded work

Keep the v1 artifact, frozen source and reports intact. Investigate the general
context-cardinality weakness before app integration: training included only one-
and two-symbol contexts, while whole-target scaling and global shape context
change when extra symbols are present. The triple failures support investigating
this distribution shift; they do not prove its cause.

The next protocol must be frozen before fitting and should address context
invariance and broader independently labeled public training contexts, not insert
a B rule, apply user acceptance as an oracle, or tune to saved private chord
answers. Retain the original 32 training/eight observed-development/20 sealed
roles and explicitly separate component comparisons from fresh full-chord and
new-writer evidence. Optional personal classification and the installed safe
baseline remain unchanged while this grouping experiment matures.
