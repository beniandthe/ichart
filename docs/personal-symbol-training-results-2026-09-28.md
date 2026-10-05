# Customizable model: symbol coverage and digit failures

Branch `codex/recognition-generalization-reset`, base `160aa31`; previous dirty
work preserved. **No alternate engine was added. No candidate from this pass is
promoted to the live reader.**

## What the exact replay established

One executed Swift/Core ML replay test passes, zero failures/skips. It verifies
each glyph's reconstructed original points against the actual cluster input,
then reproduces every generic top-three label/score within 1e-12. Twelve
observations contain eight unique inputs; the inspected raster contact sheet
shows the expected separate roots, flats, triangles and sevenths. These known
Rhythm errors are visual classifications, not missing/merged strokes. No
grouping heuristic or confidence threshold was changed.

Private source/profile hashes and contents remain unchanged. These are already
seen development inputs, not fresh handwriting or independent-writer evidence.

## Implemented and executed

- Pinned, streaming HASYv2 bitmap loader; no archive extraction or execution.
  It retains sample IDs, visual-label mappings and source/raster hashes. Of
  9,418 selected images, 26 are quarantined: six identical-raster label conflicts,
  18 within-role copies and two train/development copies. Usable: **8,421
  training**, **971 development**. No fabricated trajectories or timing.
- Fixed matched-update continuation: unchanged model, UJI-only control, and
  UJI/HASY mixture. Both fits executed **20 × 50 updates**. Public prediction
  was performed only after both final checkpoints were fixed.
- Constrained alternative: original encoder, BatchNorm, projection and 97
  output rows frozen; fit five new symbol rows with class-balanced full-batch
  regularized L-BFGS. Executed the fixed **200-iteration cap / 207 evaluations**;
  do not claim convergence beyond that cap. Loss 1.999441 → 0.896307.
- All 1,552 UJI development embeddings are bit-identical to the original under
  the constrained model; original-logit maximum error is **0.0** in this run.
  Its first 97 public anchor rows exactly match the previously verified bank.
- **39 focused Python tests pass**, zero failures/skips, covering existing
  visual/personal learning plus mappings, raster normalization, quarantine,
  role isolation, frozen extension and deterministic output-only fitting.
  `git diff --check` passes. Pinned Pillow is included in the training extra.

No iOS build/install is claimed for these Python research candidates. The
existing optional Debug comparison bundle, live reader, saved personal profile,
charts and ink are untouched. No credential access, commit, push or deployment.

## Public development results — separate populations

UJI: the same 772 eligible session-two glyphs from eight development writers,
after session-one personal examples. Four copied inputs remain excluded. These
development writers were already used in prior experiments, not sealed evidence.
All 20 reserved writers remain untouched by rasterization, fitting and inference.

| Model | Generic | Personal, 16 examples, anchored | Personal, 97 examples, anchored |
| --- | ---: | ---: | ---: |
| Original | 609/772 | 614/772 | 628/772 |
| UJI-only continuation | 611/772 | 609/772 | 617/772 |
| Mixed-source continuation | 603/772 | 608/772 | 615/772 |
| Frozen original + five symbol outputs | 606/772 | 612/772 | 624/772 |

Frozen expansion versus original: four eligible generic decisions change to
slash, including three previously correct characters. With anchored learning,
sparse16 has one gain/three harms; full97 has one gain/five harms. Preserving
parameters does not imply preserving every answer when new competitors exist.

HASY: **sample-level** official fold-1 development, not writer-independent
accuracy. Its [paper](https://arxiv.org/html/1701.08380v1) explicitly describes
unreliable user IDs. The [dataset](https://zenodo.org/records/259444) is ODbL 1.0;
shipping eligibility has not been established. Do not pool this population with
UJI or quote these results as chord/personalization accuracy.

| Model | Previously represented classes | Five new symbols |
| --- | ---: | ---: |
| Original | 307/538 | 0/433 (absent outputs) |
| UJI-only continuation | 302/538 | 0/433 |
| Mixed-source continuation | 447/538 | 411/433 |
| Frozen original + five symbol outputs | 304/538 | 421/433 |

The constrained model's new-symbol breakdown: sharp/hash 129/131, plus 8/9,
slash 52/54, slashed circle 92/95, major triangle 140/144. These scores are
uncalibrated rankings, not acceptance probabilities or live-Pencil results.

## Saved chord replay — promotion fails

Python replay uses exact Swift-verified grouping and the unchanged 12 explicitly
labeled glyph lessons. It does not extract guessed symbol lessons from the 18
confirmed whole-chord examples or use query answers. The starting model's raw
tokens match the actual Core ML replay; scores agree within 1e-4.

Mixed continuation reads one saved triangle and Rhythm D7, but turns previously
correct Simple B-flat-7 into `BbT`, so it is rejected as a replacement.

The frozen-output candidate preserves all four Simple inputs and reads both
major-triangle shapes. The Rhythm raw strings remain `Bb△D`, `Eb△9`, `D>` and
`EbT`. In particular **`Eb△9` is a valid but wrong chord** for the earlier
major-7 input: parsing is not a correctness or trust gate. None of these outputs
is accepted into a chart or silently repaired to the expected answer.

Next work should address digit representation and how confirmed personal
examples teach new full-chord handwriting. The current open-vocabulary personal
head learns the explicitly labeled glyph examples; whole-chord lessons feed a
separate closed-set ranker. Whole-chord labels must not be silently treated as
verified per-glyph labels. Any alignment/sequence-learning change needs its own
general, reviewable evidence. Do not add a rule just for these saved sevenths.
Fresh full chords in both styles and independent writers remain necessary.

## Reproduction and evidence

All local artifacts: `/tmp/iChartPersonalSymbols-20260928.IOApkf/`.
Protocols are the sibling `personal-symbol-training-protocol-2026-09-28.md`
and `personal-symbol-expansion-protocol-2026-09-28.md`.

- `glyph-verified.log/json`, `exact-inputs.png`: exact-model-input diagnostic.
  Report SHA-256 `d6a716fc3765cd35993bea3d3233fdde346de53975ad6f8e89aef09e2a3d2f92`.
- `run-01/report.json`, `training-01.log`, source `bitmap-manifest.json`:
  matched continuation. Report SHA-256
  `21e4acbf0a721217b1214b09b17011008f814c5d3cdef26114cd15f3865f4166`.
- `frozen-01/report.json`, `frozen-01.log`: output-only learning.
  Report SHA-256 `45d1f3e1926b5eef238a4b44ab495636ca25a6c3261706772da18f0d140d0be3`;
  saved model SHA-256 `71ee9e135114156a56778a6f2110f5ff51191ce58c58c81412e9be1e771089da`.
- `private-replay-01.json`, `private-frozen-01.json`: local rank-only replay.
- `all-personal-tests-02.log`: 39 executed tests. Private input is not in Git.

Both runners take `--checkpoint`, `--source` (pinned UJI), `--hasy` (pinned
archive), `--protocol`, and a new `--output` directory. Use the pinned training
extra, `python -W error::RuntimeWarning -m
ichart_recognition_ml.research.personal_symbol_training` or
`ichart_recognition_ml.research.personal_symbol_expansion`. Outputs are research
artifacts outside shipping resources, not an installable recognition fix.
