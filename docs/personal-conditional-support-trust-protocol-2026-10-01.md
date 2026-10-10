# Fixed conditional setup-trust learning experiment

Scope: optional personalization research, not a replacement OCR engine. No app,
profile, ink, live recognition, telemetry, private examples, shipping, export or
installation changes. Base HEAD `160aa31594903508e241802e21ca83ec447de849`.
The previous support-retrieval candidate stays rejected and frozen. This single
recipe must not be retuned against its internal outcomes or known private chords.

## Hypothesis and fixed learned-stage roles

The completed training signal audit showed setup-cache ranking information, but
every tested nonzero uniform mixture introduced untaught errors. Test whether
a conditional scalar gate can use additional class-equivariant agreement and
support-reliability evidence, instead of increasing a global mixture weight.
This does not assume those features are sufficient or that their scores are
calibrated correctness probabilities.

- Frozen parent training crossfit directory:
  `/Users/benirossman/.local/share/ichart/recognition-development/support-retrieval-20261001.WmWgZ3/crossfit`.
  Receipt SHA `d2a31e73d53b25b812f0ba4f24f812014515606f97a20e6b7170eaf94d0e20d2`;
  features SHA `b1bbb6066ef2bd1d5cc0398df2d9713fb60f6086ec501bb0687fce81976faaef`.
- Frozen source-only role manifest:
  `/Users/benirossman/.local/share/ichart/recognition-development/support-signal-20261001.Ww687Z/inner-roles.json`;
  SHA `47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa`.
- Use fitA only, weights SHA
  `1cfbcd2c11fe5173bbd7367121fdb9c4c1d965618d9272a6c7421dd6901261c1`.
  A16 fitted that encoder. The existing source-hash-defined B16 order assigns
  the first eight writers to meta fitting and the last eight to internal
  validation. All three learned-stage writer sets are disjoint. No fitB
  features, earlier learner weights, development writers, reserved writers
  or private ink may enter this experiment. No new encoder inference/fitting.
- The B rows were already used by earlier learner fits and the signal audit.
  This is writer-disjoint internal reuse evidence, not a fresh, blinded,
  sealed or confirmatory generalization test. Do not restore freshness by
  repartitioning. The full-32 operational encoder remains unchanged; calibration
  transfer to it is not established by a fitA-only result.

## One fixed cache and fourteen symmetric gate inputs

The cache uses exactly the existing signal-audit implementation: deduplicate
exact feature/probability/explicit-label triplets, score `10*cosine`, subtract
log remaining lesson multiplicity per label, softmax over supports, then scatter
by explicit label into the full vocabulary. No new temperature or learned
relation. Cache and encoder parameters are frozen throughout gate fitting.

Gate inputs, in order:

1. Generic maximum probability.
2. Generic top-one minus top-two probability margin.
3. Generic entropy divided by log vocabulary size.
4. Cache maximum probability.
5. Cache top-one minus top-two probability margin.
6. Cache normalized entropy.
7. Mean generic probability over all exact cache-top tied classes.
8. Generic probability mass on the unique explicit taught-label set.
9. Maximum query/support cosine.
10. Best cosine among cache-top-label supports minus best cosine among other
    supports; zero contrast if no other-label supports exist.
11. Mean explicit self-label generic probability of all geometrically tied
    nearest supports belonging to cache-top labels.
12. Unique explicit taught-label count divided by vocabulary size.
13. Fraction of all exact generic-top tied classes that are explicitly taught.
14. Indicator that generic-top and cache-top tied-class sets intersect.

All exact score ties are treated symmetrically; no arbitrary class/support
argmax may select a learned input. These are shared scalar relations, not raw
embedding axes, codepoint embeddings, learned class-axis weights, writer/session
IDs or query answers. Require finite CPU float64 features, normalized features
and full normalized probability inputs. Unit tests must include nonzero learned
weights when checking class/support/basis transformations and duplicate lessons.

Gate `MLP14->32(tanh)->1`, sigmoid. Seed 41, hidden 14->32 layer uses standard
seeded initialization; only the final 32->1 weight is zero with its bias -2.
Output is `(1-gate)*generic + gate*cache`. Empty support returns generic exactly.
Untaught relative ordering is preserved, but a taught class can overtake a
correct untaught prediction. That risk is scored rather than claimed absent.

## Fit, frozen before actual execution

Only eight meta-fit writers enter the optimizer. Thirty epochs, seed 41,
AdamW lr .001 / weight decay .0001, cosine schedule with T_max 30. Every epoch
has both opposite-session directions and independent K10/K21 support episodes
per writer: 32 actual updates/epoch, 960 total. Each epoch shuffles the complete
32 direction list with the same source-only torch generator, then selects an
independent permutation of eligible stored setup shapes for each episode.
Generate and freeze all 960 source-only episode plans before optimization;
different epochs deliberately use different source-only support subsets.
Opposite-session queries include all 97 labels except fixed generic-fit raw
raster/normalized-trajectory copies or that episode's raw/stored support copies.
Retain every exclusion and unavailable setup shape; no outcome-based removal.

Use the existing equal-stratum probability loss:
`0.5*mean(taught NLL) + 0.5*mean(untaught NLL)`, requiring both strata. Support
labels are explicit lessons; supervised query labels are optimizer targets only,
never inference inputs. No internal-validation writer enters an update or a
training episode. Final epoch only, no checkpoint, threshold or alpha selection.
Retain all source-only episode plans, real update counts, finite gradient/loss
history, changed-parameter evidence, gate statistics, weights and code/input
bindings before/after fitting. Cache feature preparation may be cached because
it is frozen and answer-blind; it must not change the number/order of updates.

## Internal prediction, scoring and advancement boundary

Prepare the eight internal-validation writers' source-only complete episode
plan with independent seed 42, one pass: 32 episodes, both sessions and K10/K21.
Reuse stored support and raw query features generated by fitA, not newly inferred
rasters. Freeze final learner/code/protocol/parent bindings before prediction.
Serialize exclusive finite full97 generic/candidate probabilities and source
plans, then commit their exact SHA before a separate scorer joins query labels.
Preparing metadata/grid/copy roles is source-only; query truth cannot enter the
five-tensor candidate interface. All scheduled/excluded/eligible exposures and
distinct source indices must remain explicit; task repetition is not independent
physical sampling. Invalid predictions remain failures in the denominator.

Fixed advancement screen: candidate must strictly improve its own generic
baseline in both K tasks, have no negative per-writer task net, have nonnegative
untaught net, and introduce zero untaught harms. Report each support-session
direction and all taught/untaught corrections/regressions, not just aggregate
NLL or a favorable subset. No aliases, grammar rescue, top-k restricted ranking,
retuning, extra alpha/temperature, or candidate selected from this validation.
Failure rejects this fixed recipe. Passing permits only separately specified
fresh writer-disjoint natural-chord and application-runtime checks; it does not
authorize integration or promotion. Baseline and exact visible ink stay intact.

Focused tests must demonstrate the new features' tie symmetry, transformations,
empty/duplicate behavior, finite full mass, source-only disjoint stages, real
synthetic training/save/reload, parent/code tamper rejection and separate frozen
prediction/scoring arithmetic. Independent verification must reconcile actual
source plans and scored outcomes. This remains isolated public-character
research; full chords, both chart styles, fresh writers and Pencil behavior
remain required parts of the active recognition goal.
