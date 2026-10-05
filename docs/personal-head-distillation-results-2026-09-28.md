# Shared-head preservation experiment: do not promote

This pass stays within the customizable visual ML model. It does not integrate
an alternate engine or modify the app, personal profile, comparison bundle or
acceptance policy. Branch `codex/recognition-generalization-reset`, base
`160aa31`, previous dirty work preserved.

The [predeclared protocol](personal-head-distillation-protocol-2026-09-28.md)
compares identical 102-output starting checkpoints. Only the shared linear
classifier is trained; original visual features and personal anchor geometry
are held fixed. A supervised mixed-source control is compared with the same
training plus an old-teacher preservation objective. Both executed all
**20 epochs × 50 updates** before either development prediction was evaluated.

## Result

Neither candidate clears the fixed public comparison gate. Distillation reduces
the control's regression but does not eliminate it. No learning-rate, temperature,
coefficient or checkpoint was selected from these outcomes, and no failed arm
was replayed against private chords to look for a favorable exception.

Same **772 eligible public UJI session-two characters**, eight previously used
development writers; four copied inputs excluded. Personal columns use explicit
session-one lessons and the existing anchored personal learner.

| Shared model | Generic | Personal, 16 lessons | Personal, 97 lessons |
| --- | ---: | ---: | ---: |
| Original 97 outputs | 609 | 614 | 628 |
| Starting frozen expansion | 606 | 612 | 624 |
| Supervised output-head update | 586 | 594 | 608 |
| Output-head update with distillation | 605 | 611 | 625 |

Against the original, the distilled candidate changes generic correctness with
**19 gains / 23 harms**, sparse16 with **19 gains / 22 harms**, and full97 with
**20 gains / 23 harms**. Sparse16 deteriorates for five writers, improves for two,
and is unchanged for one. Mean preservation is not per-writer preservation.
All 1,552 development feature vectors remain bit-identical to the original.

HASY is reported separately: official fold-1 **sample-level** development, not
writer-separated or full-chord evidence. Old/new groups have 538/433 examples.

| Shared model | Old classes | Five new symbols |
| --- | ---: | ---: |
| Original | 307/538 | 0/433 (missing outputs) |
| Starting frozen expansion | 304/538 | 421/433 |
| Supervised head | 427/538 | 419/433 |
| Distilled head | 409/538 | 415/433 |

Improved symbol-image recognition therefore still does not establish improved
handwritten chord recognition. The HASY license/shipping and writer-identity
limitations from the earlier symbol report remain. All 20 reserved UJI writers
remain outside rasterization, fitting and inference. No private ink was used.

## Checks and artifacts

**56 focused Python tests executed, zero failures/skips**, including six new
checks for the padded KL formula and temperature scaling, detached teachers,
unchanged input/head ownership, inference-mode input handling, deterministic
fitting, matched control loss, invalid inputs and paired gain/harm reporting.
Runtime warnings were errors. `pip check` and `git diff --check` pass.

The two full fits were not repeated: both fail the predeclared stop gate. The
toy fitting repeat verifies implementation determinism, not a full-run repeat.
No iOS build/install or fresh handwriting validation is claimed for this pass.

Local evidence: `/tmp/iChartPersonalHead-20260928.jj6q0c/`.

- `run-01/report.json`: full per-row, per-writer and per-class predictions,
  comparisons, source/code hashes and gate outcomes. SHA-256
  `effd6092df8af93a43b633840fe4621464a19a89065514f5e1bfb00eac115ea5`.
- Frozen protocol SHA-256
  `0b87f1608884bb92ed6351f5d978545cb38403c64c9c720b50d0cc3a157b1568`.
- Supervised model SHA-256
  `8346f11765b2215e8a4ecfd622bb9782d0e94ae442228116f06249a556779348`.
- Distilled model SHA-256
  `596d9ed4f01f70ed65ee5b7fa01ad7f7dc008169496a6dad66c40ff46f2083a0`.
- `run-01.log`, `all-tests-01.log`: executed fit/evaluation and test output.

Runner: `python -W error::RuntimeWarning -m
ichart_recognition_ml.research.personal_head_distillation`, with `--checkpoint`
(original), `--expansion` (pinned frozen-expansion run), `--source`, `--hasy`,
`--protocol`, and a new `--output` directory. Research artifacts stay outside app
resources. No commit, push, deployment or profile editing was performed.

## Implication for the current work

Preserve the prepared explicit-symbol-teaching app flow and original comparison
model. That work can test whether reviewed personal examples improve **fresh**
full chords, once device signing is available. Do not claim the older saved
whole-chord lessons automatically provide verified symbol labels. Do not keep
tuning this preservation coefficient against the same eight writers or known
private failures and present that as general recognition progress.
