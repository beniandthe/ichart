# One fixed native-shape auxiliary transfer probe

Local offline research only. This protocol is fixed before source preparation,
fitting or prediction. No app, profile, ink, acceptance threshold, reserved-writer
inference or distributed model changes are authorized by this experiment.

## Hypothesis and prior failures

HASY was already fitted on September 28: joint UJI/HASY continuation with mapped
102 outputs regressed existing handwriting; a frozen representation plus five
outputs also regressed decisions. Those recipes remain rejected. The October 1
full-source audit is source-integrity evidence, not new recognition evidence.
NIST sequential pretraining produced modest aggregate transfer but failed
personal/writer safety. Cross-writer contrastive and sparse residual recipes
also failed. Their checkpoints, results and protocols remain unchanged.

This single probe asks whether discrimination among all 369 native mathematical
shapes produces useful target features when the auxiliary head is discarded
before UJI fitting. It is not another OCR engine, a mapped-symbol mixture, or a
new confidence rule. Head size and task differ, so any effect concerns the
source-plus-task package, not source alone. UJI cannot measure missing chord
symbols (#, +, /, slashed circle or major triangle).

## Fixed source-only preparation

Use the audited HASYv2 archive SHA
`7c3ffe709e8c2b83f6ab7d8afc79f7b5f46421657981b1752d22a0ed0052aa2d`,
intake receipt SHA
`ab9293fb5f81f9dd39ee9ade02f01ecb2bd203d783686f6e28dedab977f220d2`,
and manifest SHA
`4d604325cae34dc7d08ebb533d30a5469d60a9a50dcc8db135c6287ffab95c3b`.
Retain native symbol IDs/LaTeX only; no aliases, canonical mappings, trustworthy
writer identity, invented trajectories, supplied-fold accuracy or HASY holdout.

Exclude all members of cross-native-label pixel groups; collapse same-label
pixel copies to the lexically smallest sample ID. Adapt every remaining source
with the existing `personal_symbol_data.normalize_bitmap`: binary inversion,
foreground crop, bilinear aspect-fit into 240x80, centered on 256x96. Apply the
same conflict exclusion and deterministic collapse to adapted-raster collisions.
Preserve an explicit source/exclusion ledger. All 369 native classes must retain
at least one usable representative; otherwise stop, without shrinking vocabulary.

Select 31,744 candidate exposures: 86 per native class plus one for the ten
classes with lowest SHA256 of `native-shape-transfer-v1` + NUL + native ID.
Within each class sort by SHA256 of that salt + NUL + sample ID, tie-break by
sample ID, and cycle only after exhausting available clean representatives.
Record distinct/repeated exposures, every selected native/adapted hash and each
class count. Control uses the complete canonical 6,208 training UJI sources,
327 exposures per exact class plus one for the lowest-hash 25 classes under the
same salt, cycling the 64 writer/session examples per class. No dev/reserved
source is rasterized for fitting or used to select training exposures.

## Fixed paired fit

Arms: `uji97ReplayPretrain` and `hasy369NativePretrain`. Same seed-29 original
`PersonalVisualEncoder` trunk/projection/BatchNorm tensors. Auxiliary heads are
deterministic `Linear(128, n)` initialized with seed 29 independently of the
trunk; n is 97 or 369. Save their initial and final states, but discard both.

Pretraining is exactly five epochs, 248 batches of 128 exposures: CE, AdamW
learning rate 0.001, weight decay 0.0001, cosine T_max=5, four CPU threads,
deterministic algorithms. Reuse fixed `pretrain_batch_plan` and original affine
augmentation, seed 29 independently per arm and phase. Batch-position plans and
augmentation RNG traces must agree; pixels need not agree across sources.

Restore the complete original seed-29 97-way head exactly, preserving each
arm's learned trunk/projection/BN. Fresh optimizer; same CE/AdamW, cosine
T_max=30; original UJI plan of 30 epochs x 32 batches x 194 rows. Both phases
total 2,200 updates per arm. Match final UJI batch plans and augmented inputs.
Final checkpoint only; no early stopping, hyperparameter grid or epoch choice.
Freeze both final checkpoints and 6,208-row training-only feature bundles before
any development prediction. Bind source, code, protocol, plans and outputs.

## One frozen reused-development screen

Use the existing source packet and stored-support geometry for 776 session-two
queries from eight already-observed UJI development writers. Freeze predictions
before opening truth or the exclusion ledger. Keep full 97-class competition;
fixed anchored personal head, ridge 0.1, core10/catalog21 supports only. Anchors
come solely from each final model's 32 UJI training writers. Retain every invalid
attempt as wrong. Report raw and existing no-copy views, class, writer, taught,
untaught, app/non-app and the pre-existing non-ASCII35 stress subset. Add a
source-only exact adapted-HASY/query raster-copy ledger before scoring; exclude
such copies symmetrically in both arms and report any denominator change.

Both tasks and both raw/no-copy views must meet all fixed guards: generic net
candidate/control >=0; personal net candidate/control >0; untaught personal
net >=0; no negative writer personal delta; personal net versus own generic >0;
zero untaught harms versus own generic; generic and personal net >=0 on the
fixed non-ASCII35 stress subset. Nonfinite/incomplete evidence cannot pass.
These are a development futility screen, not fresh accuracy or calibrated trust.

If this probe fails, stop this HASY raster-transfer recipe: no changed sampler,
head, schedule, alias or reserved-writer rescue. A pass licenses only a separate
fresh app-domain evidence gate, not shipping or activation. HASY user IDs are
unreliable, and commercial derived-weight distribution rights remain unresolved.

Baseline, profile, chart ink and all twenty reserved UJI writers stay untouched.
