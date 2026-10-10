# Fixed broad-writer source-transfer experiment

Predeclared before either fit or development inference, 2026-10-01.
Local offline research only. No private ink, app/profile changes, model
distribution, calibrated acceptance, signing, installation or release.

## Question and scope

Does pretraining the existing visual representation on a broader set of
documented writer groups improve generic recognition and the unchanged
optional anchored-linear learner, compared with the same amount of pretraining
on the existing UJI training corpus? This changes the pretraining source,
not a rule selected from a user's handwriting or intended chord answers.

This is an application-specific transfer experiment. The general rationale is
that learned visual features can transfer after target-task fine-tuning, while
source/target distance can impair transfer; the experiment tests that rather
than assuming it. [Yosinski et al., 2014](https://arxiv.org/abs/1411.1792)
studied natural-image networks, not this glyph model or its accuracy.

[NIST SD19](https://www.nist.gov/srd/nist-special-database-19) describes its
corpus as training materials intended for handwriting/OCR research. This
supports the bounded local research purpose here. The dataset-specific
commercial/derived-model rights category remains unresolved under
[NIST's policy](https://www.nist.gov/open/license). The prior source receipts
retain their unresolved-rights and training-eligibility fields; this protocol
does not rewrite those receipts or establish commercial eligibility. Bind a
separate dated research-use decision with `localResearchFitAllowed=true` and
`commercialUseOrDerivedWeightShippingAllowed=false` to every fit receipt.
Do not distribute data, fitted weights or integrate them into the app.

## Source and fixed selection

- UJI Pen Characters v2 source SHA-256:
  `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
  Existing strict adapter and 32 training / 8 observed development / 20
  reserved writer split. Fit may rasterize only the 6,208 training records.
- NIST PNG archive SHA-256:
  `39958e28827eb0d7d54f7e4c31c6cc36689b38aa218a4fc1e810c5413e7a35b8`.
  Clean source manifest SHA-256:
  `50cc2ac1a9bb7b4b36f22dd2ae305fd97677c66be137921c285a28e3cb0fcedc`.
  Quarantine receipt SHA-256:
  `c3fcb61a36a2dc8d9347a8fa7bd9ee07fd0c656ea509afc31fd21bd3d0a31741`.
- NIST source already has documented-ID-disjoint train/dev/reserved roles and
  all members of exact PNG/pixel copy groups quarantined. Documented writer
  IDs are not certified distinct people. Only clean `train` rows may be
  selected or decoded. No names/full forms or held-out rasters are opened.
- Both pretraining corpora have the exact 62 ASCII alphanumeric labels,
  preserving case and spelling. Select one NIST source per `(writer,label)`
  by a deterministic salted source-ID hash, then select 512 distinct recorded
  writers per label by a deterministic salted writer/label hash. No visual
  quality, model score, development outcome or label-conflict rescue selects
  a representative. Fail rather than reduce a deficient class.
- Control: for each of the same 62 labels, hash-order the 64 original UJI
  training writer/session rows and repeat that list eight times. Candidate:
  512 selected NIST writer groups per label. Each corpus has 31,744 rows.
- NIST remains raster-only: invert explicitly black foreground, validate the
  existing unresized source pixel hash, crop its nonzero bounding box, resize
  with Pillow nearest-neighbor interpolation while preserving aspect ratio to fit
  the 240 by 80 visible interior, center in a zero-background 256 by 96 plane. Record source
  and adapted hashes; no invented trajectories, stroke timing or thinning.
  This preserves binary pixels within the app's visible raster envelope, not exact Pencil geometry
  parity. Scan thickness and source-domain differences remain part of the
  intervention. UJI keeps the original app-mirroring feature encoder.

## Fixed matched training

- Arms: `ujiReplayPretrain` and `nistBroadPretrain`.
- Original `PersonalVisualEncoder`: raster-only CNN, normalized 128-dimensional
  embedding, original 97-label final classifier and original affine augmentation.
- Identical seed-29 original 97-class model initialization. Each pretraining
  head is initialized by selecting the same 62 original classifier rows.
- Pretraining: 5 epochs, 31,744 rows each, 248 batches of 128 rows per epoch.
  Identical deterministic label/row-position batch plans and affine random
  draws in both arms. CE loss; AdamW learning rate 0.001, weight decay 0.0001;
  cosine schedule over 5 epochs. No label aliases or contrastive objective.
- After pretraining, discard both 62-class heads. Restore the complete 97-class
  classifier from the original identical initial tensors; retain each arm's
  learned trunk/projection and BatchNorm state. This prevents retaining a
  pretraining head with no coverage for the remaining 35 UJI symbols.
- Fine-tune both arms on the same 6,208 UJI training records: 30 epochs using
  the existing full-vocabulary 32-by-194 batch plan, original affine draws
  restarted at seed 29, new AdamW/cosine state with the same 0.001/0.0001
  settings. CE only, no development selection, final epoch only.
- Four CPU threads, deterministic algorithms. Freeze protocol/code/runtime,
  selection, raster identities, initial and reset tensors, all batch and
  augmentation plan hashes, histories, final checkpoints and training-only
  feature bundles. No seed, epoch, sampler, support or threshold sweep.
- The intervention includes the corpus and its raster domain, not just writer
  count. Equal training budgets do not remove that domain difference. The
  historical stronger operational Core ML encoder is preserved; neither arm
  recreates its missing original PyTorch fit or establishes superiority to it.

## Frozen development evaluation

After both final checkpoints exist, freeze a fresh derivative commitment before
inference. Reuse exactly the retained public app-local-transfer fixture:
fixture SHA `d3de7699f1175b8a77aab37eaf64ab2a3e47042cd58cc7416839122cd4baa55d`,
app report SHA `52b97f84d40998a22f2c10402ff7ece5dae57a4f54cc744c11e0284d9015a618`.

Eight previously observed development writers, all 97 session-two queries per
writer: 776 per task per arm. Preserve invalid rows. `core10` and `catalog21`
use their exact existing app-stored support geometry and verified Swift raster
hashes. Build each model's anchors only from its final 6,208 UJI training
embeddings, not from NIST, queries or private examples. Keep the anchored-linear
residual objective and regularization 0.1, full 97-class competition and no
local/RBF head. Serialize all vectors/ranks/support/model/anchor bindings before
opening query truth or copy exclusions. No aliases, parser or top-k rescue.

Report raw and pre-existing no-copy views with per-writer, taught/untaught,
app-available/non-app, the 35 UJI-only classes absent from pretraining, gains,
harms and net deltas. These reused development
writers provide a descriptive futility screen only. No reserved writer feature
construction, new-writer accuracy or natural chord accuracy is authorized here.

## Fixed disposition

Plan a separate fresh-writer/runtime-parity gate only if all conditions hold in
both tasks and raw/no-copy views:

1. Candidate generic correct count is at least the matched control's.
2. Candidate anchored-personal correct count strictly exceeds the control's.
3. No writer or untaught stratum has a negative candidate-personal/control delta.
4. Candidate personalization strictly improves its own generic count, with zero
   untaught harms against its own generic rankings.
5. The 35 UJI-only-class stratum has no negative candidate/control delta in
   either generic or personalized rankings.

Otherwise reject this fixed candidate for advancement, preserve all outcomes,
and do not retune it against these queries. A pass is not live-promotion or
commercial-use authorization. Neither source covers all musical glyphs:
UJI lacks `# + / ø △`; NIST has only ASCII alphanumerics. Literal `b`, `o`, `-`
remain codepoint proxies, not certified musical forms. Isolated-character
results do not establish grouping, complete chord accuracy, trust calibration,
Pencil behavior or user-agnostic accuracy in either chart style.
