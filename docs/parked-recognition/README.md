# Parked recognition research

Parked on 2026-10-05 so app work can use the finite
[release backlog](../project-state.md). This is a retained index, not a deletion
or a claim that handwritten chord recognition is impossible.

## Recoverable source snapshots

| Local branch | Snapshot | Purpose |
| --- | --- | --- |
| `codex/park/recognition-research-2026-10-05` | `417113a` | Recognition research, evaluation infrastructure, reports, and retained app maintenance fixes from the generalization-reset tree. |
| `codex/park/stroke-direction-2026-10-05` | `f4b4ffe` | Earlier stroke-direction/reader investigation preserved separately. |

The active app branch is `codex/app-release-normalization`. Local refs are not a
GitHub backup or a completed remote push. Inspect a snapshot without altering
the current app tree:

```sh
git show codex/park/recognition-research-2026-10-05:recognition_ml/README.md
git log --oneline codex/park/stroke-direction-2026-10-05
```

Use an isolated checkout/worktree if research is deliberately reopened. Do not
reset the release branch or restore an old snapshot over charts/profiles.

## What remains where

- [`recognition_ml/`](../../recognition_ml/README.md): offline trainers, contracts,
  source auditing, model conversion, evaluation, and reproducibility commands.
- `iChart/Features/RecognitionStudy/` and `iChartStudyTests/`: separate collection/
  comparison app and tests. `project.yml` retains their schemes.
- `iChart/Recognition/Learned/` and retained app tests: runtime interfaces,
  safety/compatibility code, and comparison infrastructure. Code needed by the
  current app remains in place; this directory is not an approved default model.
- `docs/personal-*`, grouping/domain reports, and referenced protocols: original
  dated evidence and rejected approaches remain in their paths so links still
  resolve.
- Original worktrees `/Users/benirossman/.codex/worktrees/recognition-generalization-reset/Smart Chart`
  and `/Users/benirossman/.codex/worktrees/717e/Smart Chart`: retained local files.
- Generated datasets, model binaries, ignored files, and Python caches were not
  copied into source snapshots. They remain at their original local locations.
  Source refs do not back up those files. Research reports identify durable
  local artifacts under `/Users/benirossman/.local/share/ichart/recognition-development/`;
  `/private/tmp/` build artifacts may expire. Verify an artifact before using it.

No chart, profile, frozen prediction, or label should be rewritten merely to
normalize the source repository. Retain privacy/consent boundaries around local
handwriting evidence; ordinary telemetry is not a handwriting-training corpus.

## Evidence worth retaining

- [Append-only glyph lessons](../personal-append-only-glyph-coverage-results-2026-10-03.md):
  on 12 captures of six identities across two styles, standard reader 9 correct /
  0 wrong / 3 unread; tested residual profile after added lessons 3 correct /
  2 wrong / 7 unread. This is a small controlled comparison, not overall accuracy.
- [Support-match/DEFER experiment](../personal-support-match-defer-results-2026-10-03.md):
  some same-writer gains on public glyphs, but every fixed acceptance screen
  failed. No model was promoted.
- [Lesson input fidelity](../personal-lesson-input-fidelity-2026-10-03.md):
  real storage and learning-workflow repairs worth retaining in the app. Their
  tests establish those repairs, not personalized fresh-writing improvement.
- [Chord-only domain boundary](../chord-reader-domain-boundary-2026-10-03.md):
  app reader/display safeguards and their dated deployment records.

## Available checks and conditions for reopening

The CI workflow's `run_recognition_research` boolean dispatch input runs the
separate RecognitionStudy suite and Python/Core ML contracts. These are retained
engineering checks, not accuracy certification. They are not required for every
ordinary app edit. The normal iChart tests still cover app recognition behavior.

Reopen an experiment only with a written new hypothesis, immutable inputs,
predictions frozen before labels/teaching, a fixed acceptance rule accounting for
new wrong reads, and a bounded time/compute budget. Decide in advance how a failed
result changes the plan. Do not retune against the same observed evaluation until
it looks favorable. The current app release is not conditional on that research.
