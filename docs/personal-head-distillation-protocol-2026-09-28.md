# Shared output learning without changing personal visual features

This is a fixed research experiment within the existing customizable ML reader,
not an alternate recognition engine. Earlier full-network mixed-source training
improved symbol images but regressed handwriting; adding only five outputs kept
the old digit errors. Test whether updating all classifier outputs, with an
explicit old-reader preservation objective, offers a better tradeoff.

## Frozen inputs and boundary

- Original encoder/teacher: SHA-256
  `5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`.
- Starting 102-output checkpoint: frozen expansion SHA-256
  `71ee9e135114156a56778a6f2110f5ff51191ce58c58c81412e9be1e771089da`;
  expansion report `45d1f3e1926b5eef238a4b44ab495636ca25a6c3261706772da18f0d140d0be3`.
- Keep every convolution, BatchNorm statistic and projection parameter fixed.
  Train only the 102-way linear classifier on its **raw** projection features.
  The normalized 128-dimensional personal representation stays bit-identical.
- Reuse the pinned UJI and HASY sources, mappings, exclusions and roles from the
  symbol-coverage protocol. Only UJI's 32 training writers and HASY fold-1
  training images fit this shared head. No private profile or chart input.
- Never rasterize, fit on, or infer on the 20 reserved UJI writers. The eight
  development writers are already-used development evidence, not a sealed test.

## Fixed matched arms, before predictions

Both arms start at the exact expanded checkpoint. Precompute raw training
features once, with no new augmentation. Use float32 CPU fitting, four threads,
deterministic algorithms, 20 epochs of 50 updates, AdamW learning rate 0.0005,
weight decay 0.0001, cosine schedule to zero. Each update samples 64 UJI and 64
HASY training examples with replacement, balanced within each source by class.
Use generators seeded 29 (UJI) and 30 (HASY) identically across the two arms.

1. **Supervised control:** 102-way cross-entropy over the 128 labeled examples.
2. **Distilled head:** the identical supervised loss plus one times a
   temperature-2 KL divergence from the original 97-class teacher, evaluated
   only on that update's 64 UJI training inputs. Pad the teacher distribution
   with five exact zeros for the new classes; normalize the student over all
   102 classes. Multiply KL by temperature squared. Detach all teacher/features.

The concept follows [Hinton, Vinyals and Dean's distillation paper](https://arxiv.org/abs/1503.02531).
This protocol's coefficient and temperature are fixed, not selected using
development or private chord answers. Train both final checkpoints before
evaluating either. No early stopping, hyperparameter sweep, best-epoch selection,
new segmentation rule, grammar rescue, score calibration or acceptance change.

## Comparison and stopping rule

Evaluate the unchanged original, expanded start, supervised control and distilled
head on exactly the same public inputs. Preserve the original 97 UJI-derived
anchor means and add only the five HASY-training means for the added symbols.
The personal learner and fixed sparse16/full97 lesson labels do not change.

Report generic and anchored-personal counts, gains/harms, writer-level changes,
per-class changes and all row predictions for the 772 eligible UJI session-two
queries. Report HASY old/new classes separately, including per-class counts;
HASY's 971 sample-level development images do not establish writer independence.

A candidate merits further comparison only if UJI generic/sparse16/full97 counts
are at least the original 609/614/628, HASY old-class reads exceed the expanded
start's 304/538 and new-class reads are at least the earlier mixed model's
411/433. These exploratory gates are not statistical or shipping guarantees.
If neither arm clears them, document the failure and do not export or install it.
If an arm clears them, repeat deterministically and replay the already-verified
private inputs with unchanged explicit lessons, without using those answers to
refit or tune. Retain failures as failures; no conditional fixes for those chords.

Any later app promotion still requires fresh full chords in both styles, usable
on-device correction/learning and separate-writer evidence. This experiment has
no app packaging, installation, profile mutation or recognition authority.
