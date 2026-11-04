# Repository maintenance — November 4, 2026

This records repository housekeeping, source preservation and remaining review
work. It does not promote a new app build or change application behavior.

## Current source and review work

| Item | Verified disposition |
| --- | --- |
| Main baseline | `4fb03664670f90ed477fdebfc8fbf181f7b2a1a2`, build 108, merged through [PR #94](https://github.com/beniandthe/ichart/pull/94). |
| Active application candidate | Draft [PR #95](https://github.com/beniandthe/ichart/pull/95), head `3f34524fa9a19951b90ddccb7db50058492b45ed`, branch `codex/build136-integration`. Its source declares 1.2.4 (137). |
| Forum follow-up | `8c79e13a7aff0efbfe6e2c9e5ae88dc6149dc854` is already an ancestor of the PR #95 head. Its existing local checkout and evidence are retained. |
| Native CI defect | [Issue #96](https://github.com/beniandthe/ichart/issues/96) records an executed keyboard-probe telemetry failure on main. No repair or successful retry is inferred. |
| Current local Fix Docket | The primary checkout has a newer, uncommitted 422-line version of `docs/qa/ichart-fix-docket.md`, covering the same 24 IDs as the 102-line PR #95 summary. Preserve its local case history and reconcile individual claims before publishing it. |

PR #95 remains a draft. At the audit checkpoint its actual pull-request native,
SwiftPM and CodeQL jobs were running; its green branch-push jobs had scope-skipped
native/SwiftPM execution. The candidate's physical acceptance and Apple delivery
are separate gates. A later result belongs to its own head/run and must be read
back before promotion.

## Completed cleanup

- Pruned **11 missing, unlocked worktree registrations**, after copying every
  worktree administrative directory and index. All 11 indexes matched their
  recorded HEAD. No existing checkout directory was removed.
- Retired **20 superseded pre-108 local branch aliases** into
  `refs/archive/repo-maintenance-20261104/heads/…`. Their exact commits are also
  in the verified recovery bundle. Eight matched merged checkpoint trees; the
  others have the selective-integration/supersession evidence recorded in the
  [November 2 inventory](release-consolidation-2026-11-02.json).
- Deleted three inactive remote donor branches, with atomic exact-SHA deletion
  guards after confirming no open PR or branch rule depended on them.
- Pruned four already-absent remote-tracking refs and removed two orphaned
  upstream settings. The old PDF and build-108 checkouts remain intact.

| Deleted remote donor | Preserved exact head | Integration evidence |
| --- | --- | --- |
| `codex/free-pro-access-2026-10-15` | `990af78328455d888a5537d02cbf3cf41014f8b5` | Merged PR #83; coverage verified in PR #94's inventory. |
| `codex/pdf-import-setlists` | `877368d0cd354d85a7b3c50df91c4a5d1ecc9761` | Closed PR #85 was selectively integrated by PR #91; PR #94 retained the reusable PDF QA controls/runbooks. |
| `codex/telemetry-feature-contracts` | `344b355f271548fde27f8cd1e1ac3047800b2534` | Closed PR #90 was selectively integrated by PR #91, retaining later privacy changes. |

The remote application branches after donor cleanup are `main` and the active
PR #95 branch. This maintenance change may temporarily add its own PR branch.
Squash-merge ahead counts alone were never used as proof of missing or
disposable work.

## Recovery record

The private archive is
`~/.local/share/ichart/repository-archives/2026-11-04-maintenance/`.
Its `PRESERVATION-RECEIPT.json` records a verified **409,715,073-byte**
`all-refs.gitbundle`, containing all **88 original refs** plus **35 explicit
recovery refs**, including the five recent reflog-only variants. Bundle SHA-256:

```text
1750f237a3f56b122a3b1a5db9236397a72a5070687267d7261c681e227289ba
```

The archive also holds original ref/worktree manifests, worktree indexes and
administrative metadata, common Git configuration/reflogs, the primary tracked
patch, and exact copies of the primary AGENTS file and current Fix Docket.
The latter's SHA-256 at this checkpoint is
`59a3d08594f39b86ea111cee3ab098aedf456bd12d3d3fbb3b7dec6455787cff`.

Inspect a recovery ref before recreating a branch. For example:

```sh
git show --stat refs/archive/repo-maintenance-20261104/heads/codex/free-pro-access-2026-10-15
git switch -c codex/restore-free-pro refs/archive/repo-maintenance-20261104/heads/codex/free-pro-access-2026-10-15
```

The bundle's original branch names can also be fetched into a new recovery
branch. Verify the bundle first, choose an unused destination name, and avoid
resetting or replacing an occupied checkout. Deleted remote donor heads are
additionally retained under
`refs/archive/repo-maintenance-20261104/remotes/origin/…`.

## Work retained in place

The primary checkout still contains its original 11 tracked edits and 35,097
untracked paths, including parked research and the active docket. Existing
worktrees, private QA/device backups, signed products and historical evidence
remain in place. The missing locked recognition archive retains its registration.
No model, Graph/MyScript or user-parked experiment was resumed.

Four post-108 local-only branches remain active/recoverable:
`codex/authoring-integrity-boundary`, `codex/next-build-authoring-integrity`,
`codex/ipad-reader-retry-receipt` and `codex/free-ink-selection-checkpoint`.
The current rhythm, articulation, build-136 and Forum donor chain is retained.

Do not recursively clean the primary `.build` directory. It contains registered
build-136/Forum worktrees and two independent source repositories, as well as
dependencies, custom helpers, backups and QA evidence. The hidden source
repositories were inspected read-only and their committed source is contained
in PR #95, but their complete original directories remain preserved.

Connectivity-only `git fsck` passed. `git count-objects` reports an empty
`refs` directory in the current Codex worktree's administrative directory; it
is a 64-byte directory entry, not a corrupt Git object. No garbage collection,
reflog expiry or `git clean` was performed.

## Remaining health work

Main's native [run 41511701346](https://github.com/beniandthe/ichart/actions/runs/41511701346/job/125504885486)
failed `testActualKeyboardProbeRechecksEnabledActionAndRejectsOldConsentDwell`.
The probe assessed reachable controls successfully, but no event reached the
production telemetry queue. Deferred completion, authoritative admission and
append outcomes were not distinguished by the trace. Keep the deadline and
existing production-queue/stale-consent assertions; [issue #96](https://github.com/beniandthe/ichart/issues/96)
defines the evidence needed for a repair. PR #95 contains the same test and
relevant production blobs, so its source does not establish a fix.

Separately, main's scheduled CodeQL analysis **2080973540** completed on the
exact main commit, with **27 rules / zero results / no error or warning**.
This does not turn the native failure green.

The 41 existing Dependabot alerts identify Pillow in the parked
`recognition_ml/pyproject.toml` toolchain (five critical, 23 high, 13 medium).
They remain visible and were not dismissed or changed during housekeeping.
This inventory is not an exploitability assessment. Existing branch protection,
secret scanning, push protection and dependency-security settings were retained.

Before merging PR #95, refresh its exact head, actual hosted checks and review
dispositions, reconcile the newer local docket, and obtain the outstanding
physical acceptance. A documentation-only housekeeping check does not validate
the app or clear issue #96.
