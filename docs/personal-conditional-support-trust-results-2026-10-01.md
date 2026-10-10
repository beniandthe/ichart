# Conditional setup-trust result: rejected

The one predeclared conditional gate was actually fitted and independently
scored. It failed the trust screen. Do not export, activate, retune against
these validation rows, or consume reserved writers to rescue this recipe.
The app, operational full-32 encoder, profiles and visible ink remain unchanged.

## What was tested

Base HEAD: `160aa31594903508e241802e21ca83ec447de849` in the existing dirty
`recognition-generalization-reset` worktree. Python 3.12.14, NumPy 2.0.2,
Torch 2.7.0, deterministic CPU execution with four threads.

This is the optional customizable-ML path, not an alternate OCR engine:
the frozen encoder and fixed labeled-example cache remain unchanged, while
one shared scalar gate learns how much to mix the cache with generic evidence.
Its fourteen inputs contain symmetric probability/agreement and lesson
reliability summaries, not writer IDs, raw feature axes, class embeddings or
query answers. The protocol was frozen before the actual fit:

`aef2c1db98bc12bce63575f11b0fd7930306c18d4d3b1350880cbeec09647680`

The generic encoder fitted A16; the gate fitted the first B8; the remaining B8
provided internal validation, using fitA-generated features only. All three
learned-stage writer sets are disjoint. These B rows were already used by
earlier work and the signal audit: this is internal reuse/selection evidence,
not fresh or confirmatory accuracy. No development, reserved or private
handwriting was evaluated. Calibration transfer to the operational encoder
was not tested.

## Real optimizer and input counts

All 960 source-only episode plans were written before optimization. The run
completed 30 epochs × 32 actual updates, final checkpoint only, with finite
losses/gradients and all four parameter blocks changed. Delta norms were
3.65122 (hidden weight), 0.145603 (hidden bias), 1.46355 (final weight) and
0.0166410 (final bias). Epoch-one/epoch-thirty mean balanced NLL was
0.634167/0.537195. Support subsets differ between epochs; these means do not
establish convergence or validation improvement. The final epoch's observed
gate range was 0.0004863–0.946418: this was not a zero-update or inert gate.

Training retained 93,120 scheduled query exposures, 92,700 eligible exposures
and 420 source-copy exclusions, across 1,552 source indices repeated 60 times.
There were 14,880 support exposures and 420 unavailable-setup exposures.
Repeated exposures are not independently drawn physical samples.

Validation retained all 32 episodes: 3,104 scheduled exposures, 3,096 eligible,
eight source-copy exclusions and zero invalid predictions. The same 1,552
source indices appear once per K task; 1,548 remain eligible per task.
Unavailable setup records were explicit: eight exposures from four indices.
Only the source-only no-copy cohort drives the fixed screen; raw scheduled
results remain in the diagnostic packet. Invalid eligible outputs would count
as wrong, not be dropped.

## Paired eligible outcomes

| Explicit setup examples | Eligible exposures | Generic correct | Candidate correct | Corrections | Regressions | Net correct | Untaught harms |
|---|---:|---:|---:|---:|---:|---:|---:|
| 10 | 1,548 | 1,245 | 1,223 | 29 | 51 | −22 | 50 |
| 21 | 1,548 | 1,245 | 1,252 | 30 | 23 | +7 | 20 |

The candidate improved taught-character net counts by 28/27, but damaged
untaught-character counts by 50/20. Across both repeated tasks it corrected
59 exposures and regressed 74, for net −15. Those totals are task exposures,
not counts of unique independently written mistakes.

Six of eight writers regressed in K10; two of eight regressed in K21. The
fixed screen required strict aggregate improvement in both K tasks,
nonnegative net for each writer×K cell, nonnegative untaught net and zero
untaught harms. K10 failed all four conditions; K21 met aggregate improvement
only. Writer/session/stratum cells and exact gain/harm exposure IDs are retained
in `score.json`. No aliases, chord-grammar rescue, restricted ranking,
threshold/alpha selection or outcome-based exclusions were applied.

## Verification and pre-fit repairs

The final combined gate executed **69 tests, zero skipped**, with all warnings
treated as errors. It includes nonzero-weight class/support/basis transformations,
exact and robust near ties, duplicate/empty/full-mass contracts, real synthetic
960-update fitting, exact checkpoint reload, tamper rejection, and real-loader
prediction tests. These are engineering tests, not handwriting accuracy.

Root and independent source review caught and repaired two issues before any
actual fit or candidate outcomes: the model loader decoded source-label
metadata, and training plans omitted explicit unavailable-setup records.
The repaired predictor only hashes parent metadata bytes; it never decodes
per-query labels. Final weights and exclusive full97 prediction bytes were
committed before a separate scorer joined query labels.

A separate NumPy verifier imported no candidate preparation/inference code.
Torch was used only to deserialize weights. It independently reconstructed
the cache, all fourteen inputs, learned gate and full97 probabilities, and
reconciled all source plans, exclusions, unavailable records, scored rows and
writer/task/session/stratum cells. All 3,104 candidate rows matched, maximum
absolute error `1.9984014443252818e-15` (tolerance `1e-12`). It passed with
RuntimeWarnings treated as errors. It independently reproduced the failed
screen; no rank restriction or rescue occurred.

## Retained evidence and bindings

Temporary run: `/private/tmp/iChartConditionalSupportTrust-20261001.miOggZ`.
Durable bundle: `/Users/benirossman/.local/share/ichart/recognition-development/conditional-support-trust-20261001.miOggZ`.
The durable receipt verifies every copied artifact and source snapshot and
retains references to the separately preserved parent inputs. Originals are
not removed.

| Artifact | SHA256 |
|---|---|
| Core source | `7d8f12125ace76ee903306a308caa9ed172ece2d9962189e02be84a723050a31` |
| Core tests | `781bf2c938db797f63386e3d1ba731f9f5cf883dea0dc114c3b85f1029c35000` |
| Evaluator | `523260f026a17da5ecb50617c866c5a89fc444a013b1c8477d0ac929d9f1c6cc` |
| Evaluator tests | `6f26532b8adb9c5de318aafcad73f1231f5c6f0de444f23dcc0e9ff369f0c1c5` |
| Final weights | `0fc0096f9d57d43ac7518e9768c9643cab1c207e7bba4a28074fd7be2b68db4b` |
| Fit receipt | `6f349defbc1fccdded6df5963c6f346fb885538ea220577e0e4ea0e98f39a789` |
| Prediction commitment | `9d5ae462c2e866a4fa333d6a6ac13a47c821c65adb6b75ae1afb69d102295872` |
| Full97 predictions | `6b7938a5866c552f263995b6bda6f23a85f744cbca348acc0c07fa55a88d74cb` |
| Separate score | `5efd1baffb134d7bf8a0a69bcbcfa6aa44a01b4d18b5f80617ee7312bcb8bc15` |
| Independent verifier | `68725431e385ce10435275758e6825cd625e7b1da059250c244119b6491e9d60` |
| Independent result | `d29305ec60b83caf34674a25b8e010bcc3e7fd5783f3be9d289582b41edba3e4` |

## Boundary and next work

This result rejects one fixed conditional mixture. It does not prove that
personalized ML is impossible. It does show that these reliability inputs and
the equal-stratum NLL recipe do not keep untaught recognition safe in the
internal screen. Increasing personalization strength or selecting a favorable
support count is not an evidence-backed fix.

Any different recipe needs a separately frozen, training-derived rationale;
these validation predictions cannot become an optimization or tuning target.
The reserved writer set remains untouched. Fresh independent handwriting,
full natural chords in both chart styles, application feature/runtime parity
and Pencil interaction remain requirements of the active recognition goal.
No app build, device install, new-writer claim, profile change, export,
commit, push or release is established by this research pass.
