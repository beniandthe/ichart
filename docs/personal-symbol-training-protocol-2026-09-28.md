# Customizable model: fixed public symbol-coverage experiment

This is continued training of our visual model, not another OCR engine. Freeze
this protocol before fitting or viewing candidate predictions. Research only;
no app replacement, automatic chord acceptance, private-ink training or profile
mutation. The baseline artifact and prior reports stay intact.

## Diagnosis and sources

The exact v26 replay contains eight unique inputs. A runtime assertion verifies
that reconstructing each glyph from its original stroke indexes preserves every
point and reproduces the actual Core ML rankings. The inspected contact sheet
shows complete, separate roots, flats, major triangles and sevenths. The known
Rhythm failures are visual classifications, not missing/merged strokes in these
inputs. No new grouping heuristic is warranted by this evidence.

The shared 97-class model has no `#`, `+`, `/`, `ø` or `△` output. Its personal
layer can learn explicitly labeled novel symbols, but the frozen profile has no
triangle lesson. Broad symbol training is therefore a model-coverage change,
not a rule selecting the user's expected chord from lower-ranked hypotheses.

- Existing UJIv2 source/splits/model are unchanged. Initial weights SHA-256:
  `5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0`.
- Additional data: Martin Thoma, [HASYv2, DOI 10.5281/zenodo.259444](https://zenodo.org/records/259444).
  Archive SHA-256 `7c3ffe709e8c2b83f6ab7d8afc79f7b5f46421657981b1752d22a0ed0052aa2d`;
  official MD5 `fddf23f36e24b5236f6b3a0880c778e3`. Dataset license **ODbL 1.0**;
  do not confuse the paper's CC BY license with the dataset license. No shipping
  eligibility or legal conclusion follows from this research use.
- HASY's [paper](https://arxiv.org/html/1701.08380v1) says user IDs are unreliable.
  Its official fold-1 holdout is **sample-level development only**, not sealed
  evidence and not a writer-separated benchmark. Do not pool its accuracy with
  the UJI writer-separated development results.

## Frozen data treatment

Only single characters already in UJI's vocabulary and five new labels are used.
Visual aliases: `\\#`, `\\sharp` → `#`; `\\flat` → `b`;
`\\Delta`, `\\triangle`, `\\vartriangle` → `△`; `\\emptyset` → `ø`.
Other mathematical labels are excluded, never coerced into chord symbols.
Keep all 97 old labels, including non-chord distractors.

HASY bitmaps stay bitmaps: invert black ink, crop foreground, fit within a
240×80 region centered in the 256×96 model input, preserve aspect ratio and use
bilinear interpolation. Do not fabricate trajectories, timing, or writer IDs.
The app's vector rasterizer and feature schema do not change. Validate original
32×32 binary source pixels. Stream archive files without extracting or running
anything. Preserve source IDs and hashes. Quarantine identical-raster label
conflicts, training/holdout copies, and repeated same-role images before fitting.

UJI uses the same 32 training writers and eight development writers. All 20
reserved test writers remain untouched by rasterization, fitting and inference.
Development copies of training/support ink remain excluded and reported.

## Fixed experiment

Three reports: unchanged starting model, UJI-only continuation control, and
mixed-source continuation. Both continuation arms have the same 102-class
architecture: copy the encoder and all old classifier rows; initialize the five
new rows identically with seed 29. No checkpoint selected using development or
private results. Evaluate the final epoch only.

- 20 epochs × 50 updates, batch 128; AdamW lr 0.0005, weight decay 0.0001,
  cosine schedule to zero; CPU, four threads, deterministic algorithms.
- Control: 128 class-balanced UJI training draws per update.
- Mixed: 64 class-balanced UJI + 64 class-balanced HASY training draws.
- Existing label-blind geometric augmentation is unchanged. BatchNorm running
  statistics stay frozen in both arms; trainable affine parameters still learn.
- The fixed total update budget controls for additional optimization, not equal
  exposure to every original UJI example. Report that distinction.

Report raw generic ranks on the HASY development samples (overall, each class,
old versus novel classes, macro average). Do not call this personalization or
full-chord accuracy. On UJI development session two, evaluate generic, original
residual personalization and anchored personalization with the same fixed
16-label and 97-label session-one profiles. Public anchors use only the source
training images that each arm's encoder was fitted on. Report gains and harms,
not just totals; scores remain uncalibrated rankings.

Private saved chords may be replayed **after** training and public evaluation,
with the original explicit profile only. They never select epochs, fit shared
weights, silently teach symbols, or supply a grammar repair. Any such replay is
already-seen development evidence, not fresh recognition accuracy. If the
candidate trades symbol coverage for regressions, do not promote it. Fresh full
chords in both styles and independent-writer tests remain required.
