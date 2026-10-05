# Personal lesson action selection protocol

This bounded offline experiment tests whether the frozen lesson matcher contains
enough numerical evidence to select helpful substitutions without introducing
wrong readings. It does not retrain the recognizer or change the app. The prior
joint match and defer recipe remains rejected; its predictions are preserved.

## Decision being learned

The previous target meant that a symbol had a lesson, not that the lesson was
safer than the baseline. The successor keeps the exact `genericCEControl` read
as its fallback. Only the frozen joint model's actual explicit support winner
can be a proposal. A deferred read never creates a proposal from a runner up.

The target is HELP if the proposal is correct and the baseline is not, HARM if
the proposal is wrong while the baseline is correct or unresolved, and NEUTRAL
otherwise. A finite, unique HELP argmax selects the proposal. Any other result,
missing proposal, tie, or invalid numerical evidence keeps the baseline.
There is no score blending, learned class exception, writer identifier feature,
or hand tuned confidence threshold.

This is a project hypothesis, not a reproduction of a published estimator.
Learning to defer motivates separating prediction from action utility;
published results do not establish this experiment's calibration or accuracy.
See [Mozannar and Sontag](https://proceedings.mlr.press/v119/mozannar20b.html).

## Frozen data roles

Use only A16 to B16 outputs from
`support-match-defer-20261003.KEUEUI`. The original predictions hash is
`49183adb624e690c4f50b99e41de1d4616f35ad5cbac51518f7baa3c75243c03`;
the score hash is
`28037b416f85307a020901fa4061f6d70434a3b120caca26b9a5fe66297987b5`;
the forward plan hash is
`c6fa6c953a87c471c18316cfa39f818869a9b50ac8327363e921486ed9988995`.

Keep the existing plan's B writer order. The first eight are meta fit and the
last eight are a one shot internal development check. Verify these sets against
`support-signal-20261001.Ww687Z/inner-roles.json`, hash
`47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa`.
The A16 base model writers, B8 meta fit writers, and B8 check writers are disjoint.
All B outcomes have already been scored in prior experiments. This is reused
development evidence, never fresh validation or independent confirmation.

No new CNN inference, private ink, profile update, eight development writer
geometry, or twenty reserved writer geometry is permitted. Wrong support is
diagnostic only and never enters fitting: the old cyclic donor crosses the B8
split. Each B8 has 3104 catalog exposures but only 1552 distinct writings.

## Fixed features and fit

Use ten class symmetric scalars in this order: baseline probability for the
proposal, baseline maximum probability, baseline top two probability margin,
baseline entropy divided by log vocabulary size, baseline domain read flag,
proposal agreement with baseline, proposal minus DEFER matcher logit, proposal
minus best other support matcher logit, proposal prototype cosine, and proposal
cosine minus best other prototype cosine. No raw embedding axes, label strings,
source identifiers, query position, or query truth enter the classifier.

Fit a float64 linear ten input three output classifier, with zero initialized
weights and bias, full batch Adam at learning rate 0.01 and weight decay 0.001,
1000 steps, final weights only. Use CPU four threads and deterministic kernels.
Use only eligible true support proposals from meta fit rows without existing
copy reasons. Weight each exposure by the reciprocal of its source's eligible
exposure count, so repeated catalogs do not double the writing's weight.
Standardize features using that weighted fit subset only; constant feature
scales become one. Loss is the equally weighted mean of each target class's
weighted cross entropy. Stop if any of the three target classes is absent.
There is no checkpoint selection, hyperparameter search, or result based retry.

## Evidence sequence and acceptance

Authenticate parent artifacts, extract and exclusively save answer free feature
rows first. In a separate process, create only the first B8 action target
sidecar. The fitter accepts that sidecar, not the original scored artifact.
Freeze all routed check predictions before the scorer joins check truth.
Bind protocol, code, features, roles, targets, and fitted weights by hashes.

Report raw and existing no copy cohorts separately for both catalogs, including
baseline correct, wrong, unresolved, corrections, regressions, unresolved to
wrong, untaught harms, new out of domain outputs, and per writer differences.
No copy is primary; raw is a required diagnostic with the same safety gates.
Each catalog and cohort must have positive domain net gain, no correct or
unresolved to wrong transitions, no untaught harms, no new out of domain reads,
no writer with negative net, true support final correctness above the fixed
wrong support diagnostic, and complete finite evidence. Zero interventions is
not success. Any failed gate rejects this fixed selector without retuning it
against these results. Even passing would not authorize app promotion or a
recognition quality claim without a separately frozen fresh writing test.
