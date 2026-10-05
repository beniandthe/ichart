# Personal adaptive head: fixed first experiment

This is the customizable layer inside iChart, not a replacement OCR engine.
Version `personal-balanced-ridge-v1` learns a regularized linear visual head
from explicit per-user labels. No model is connected to live chord resolution.

## Fixed before public-data predictions

- Existing `PersonalInkShape` normalization, reciprocal distance features
  `1 / (1 + distance)`, unit L2 norm, one-hot targets, class-balanced sample
  weights, ridge penalty 0.1. No label-specific features, thresholds, or rules.
- Native base recognition, personal opt-in state, source ink, profile/journal
  persistence, and acceptance policy stay unchanged. There is no calibrated
  confidence or automatic render authority.
- Whole-chord examples train a whole-chord comparison head; explicit individual
  symbols train a separate symbol head. A whole label never creates inferred
  symbol training labels. Model construction and prediction do not save data.
- Source revisions identify immutable heads; explicit save/remove/correct
  operations determine the next model. Deleted/relabelled lessons do not enter
  a newly built head. An old frozen evaluation remains reproducible.
- Opt-out is enforced before fitting or feature extraction. Comparison tools
  must not silently enable a disabled profile to construct the head.

## Independent-writer personalization-method check

Use the public **UJI Pen Characters Version 2** dataset only as an isolated
root-letter experiment. Published source: F. Prat, M. Castro, D. Llorens,
A. Marzal, J. Vilar (2008), UCI Machine Learning Repository,
[DOI 10.24432/C5FG8S](https://doi.org/10.24432/C5FG8S).
The [UCI dataset page](https://archive.ics.uci.edu/dataset/177/uji+pen+characters+version+2)
lists CC BY 4.0, 60 writers, 97 characters, two non-consecutive sessions, and
40 `trn` versus 20 `tst` writers. Data stays outside Git and outside the
production corpus/consent registry. Public research use is not a production
model-promotion or corpus-eligibility claim.

1. Parse and validate the complete source format/counts/identities. Preserve
   coordinates, stroke boundaries, repeated points, and the source digest.
   No invented timestamps. No writer merges across site/split identifiers.
2. Fixed task: uppercase A–G only, with all seven classes competing. One first-
   session example per root is the writer's personal setup; the second-session
   sample of each root is the query. Do not inspect query labels during fitting.
3. First run only on the 40 official development writers (280 queries). Reserve
   the 20 official test writers. Report the query/support identities and assert
   disjointness; exclude any exact normalized support/query trajectory copies
   from novelty counts, with exclusions visible rather than replaced.
4. Compare the existing geometric nearest-label ranking and its existing
   distance/margin abstention with the fixed learned ranking. Report top-1,
   per-writer counts, per-root confusion, gains and harms, and current-method
   accepted/error/no-read counts. Learned rankings have **no acceptance policy**.
   Do not compare forced learned coverage to current abstention as if they were
   equivalent confidence decisions.
5. No parameter sweep or changes fitted to the known iPad answers. Any later
   feature/model revision must be recorded as a new development experiment;
   test writers cannot be used for model selection or threshold tuning.

This provides multi-writer evidence about learning personal root-letter shapes.
It does not test accidentals, chord qualities, suffix segmentation, full chords,
open-set rejection, iPad input latency, fresh in-app handwriting, or ship readiness.
Those remain requirements of the active goal.

## Verification

Closed-form and weighted normal-equation tests validate the fit, and synthetic
tests cover repetition balance, correction/revision changes, frozen snapshots,
malformed data, contradictory labels, and separation from live suggestions.
Opt-in exact-device replay records both whole and composed-symbol rankings
without changing the original profile or using intended answers as model input.
Passing those checks is not a recognition-quality result.

## First development result

The source archive was downloaded from the official UCI link. ZIP SHA-256:
`0881b522911b99d9922820289441b50fd3d307f71cd7f9cc70e86872424a5f90`.
Unmodified `ujipenchars2.txt` SHA-256:
`cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
Parser checks confirmed 11,640 records, 60 distinct writers, 97 labels and two
complete sessions each. The 20 official test writers were parsed only for
structural validation; none were fitted or predicted.

The fixed 40-development-writer run completed all 280 planned A–G queries;
none was an exact normalized support-trajectory copy.

| Method | Top-1 correct | Prediction/acceptance scope |
| --- | ---: | --- |
| Existing geometric nearest label | 218/280 | Forced ranking, not trust |
| Learned personal head | 222/280 | Forced ranking, no acceptance policy |

There are 16 gains and 12 harms, a net four-query gain. This is insufficient
evidence to promote the head into live suggestions. The current geometric
distance/margin gate passes 164 queries, 13 with wrong labels; those are
isolated personal-matcher outcomes, **not** the app's native/arbitrated trust
decisions or actual rendered chords. Every writer contributes seven queries,
so writer-macro and micro accuracy coincide here. Per-writer outcomes and full
rankings are retained. No thresholds, labels, or parameters were changed after
seeing these results, and the reserved writers remain unused.

The existing shape descriptor is therefore not made reliably discriminative
simply by fitting a linear head over it. The next model work must improve the
learned visual representation and test whether explicit additional examples
help, not hide these harms through forced acceptance or tune exceptions to the
known iPad chords. Additional root-letter results would still not complete the
full-chord, fresh in-app, or calibrated-trust requirements.

Evidence directory: `/tmp/iChartPersonalAdaptiveHead-20260928.dfNhl5/`.
`public-root-development.json` SHA-256:
`b37bc1b75d5cba6361edf20b67cbb3432c365eca1ae612a05806c50d661f75ef`.
No raw public data or private profile/ink has been added to the repository.

The fit follows the weighted ridge formulation documented by the primary
[scikit-learn implementation](https://github.com/scikit-learn/scikit-learn/blob/main/sklearn/linear_model/_ridge.py).
The Swift Cholesky solver is independently implemented and tested against both
a closed-form case and its weighted normal equations. No scikit-learn runtime
or external inference service is used by the Swift personal head.
