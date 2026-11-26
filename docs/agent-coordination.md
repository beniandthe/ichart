# iChart shared coordination contract

This is the common entry point for Codex, Gemini, and Antigravity. It defines a handoff contract, not a shared chat history or an automatic messaging service.

## One integration and release path

`beniandthe/ichart` on GitHub is the source authority. Start task branches from the agreed base, review their changes in a pull request, integrate into `main` after the required checks pass, and archive/export the exact verified source for release. One integration owner selects the candidate and records its head. One release owner handles the signed artifact, distribution scope, and device preservation gates. Source integration, CI, Apple processing, installation, and saved-data readback are separate outcomes.

Each assistant uses a distinct task checkout or worktree and branch. Record the actual path and head before editing; do not infer them from a folder name, branch prefix, or old chat. Prefer durable local workspaces and build caches outside iCloud. A temporary checkout must have its commits and evidence retained before it is retired. A current candidate and an older parked checkout must never both be called the active integration source.

The task owner records owned paths before changing them. If another task owns an overlapping path, stop that edit and resolve ownership with the integration owner. Do not reset, blanket-merge, blanket-commit, or clean another assistant's working tree. An existing feature may already be represented by newer code even when its old commit is not an ancestor; establish ancestry or compare the relevant source and tests before importing it again.

## Handoff and acknowledgement

The owner maintains one current task record in the reviewed pull request or agreed docket. Use this template when transferring responsibility. Link evidence without copying credentials, raw user content, or private command output.

```text
Task / scope:
State: owned | handed-off | acknowledged | blocked | complete
Owner / recipient:
Checkout / branch:
Base HEAD / candidate HEAD: full commit IDs
Owned paths:
Changes and affected user guidance:
Verification: result, executed/skipped counts, exact tested head, receipt location
Unmerged or parked work preserved at:
Next action / blocker:
Acknowledged by / exact acknowledged HEAD:
```

The recipient reads the candidate and receipts, then explicitly acknowledges that head before continuing. The sender cannot acknowledge for the recipient. New commits require a refreshed handoff and acknowledgement. A written claim that tests passed is not a test receipt; a recorded command is not proof of success. Missing or failed Git inspection means **unknown**, not clean. Keep local tests, hosted checks, Simulator observations, physical iPad results, and deployment readbacks distinct.

## Preservation and rollout boundaries

- Keep the original mixed `/Users/benirossman/Documents/Smart Chart` checkout and paused ML/research lanes intact. Do not resume or publish parked work merely to make branches match. Keep iPad backups, QA evidence, and important ignored files out of blanket cleanup.
- Before retiring a branch or checkout, record its head and dirty state, prove where its intended changes are represented, and preserve a verified recoverable ref or bundle. Uncommitted and untracked work needs a separate private snapshot; a Git bundle alone does not preserve it. A failed inspection is not permission to discard anything.
- Preserve normal public free Pro. Keep Supabase **Deploy to production** OFF until a separately authorized backend rollout. Merging backend source does not authorize applying pending migrations, deploying workers, or activating paid access.
- Use the current `project.yml` version/build and the release verifier for the final candidate. Do not copy old release numbers or use one head's receipts to certify another. Follow the [public-beta release procedure](public-beta-release.md), refreshing its candidate-specific inputs. Distribution needs its own authorization and fresh saved-state/backups before an iPad update or potentially automatic TestFlight distribution.

## Audit checkpoint: November 26, 2026

This dated checkpoint is evidence of the audit baseline, not an automatically updated claim about the current checkout or CI.

- The integration candidate was the Build 199 CI repair pull request, based on `ddab0e81ef1afcecfdc3f4e340641c80f9e8b311`, in `/private/tmp/ichart-build199-ci-repair-20261126/source`. Refresh its current head and all applicable push/PR checks before acting.
- The active Codex feature source was `4eae2c73fec4aaeee55f06492814735a074d7f29`; Antigravity's consolidated source was `71b2514438738bde22b722ff3a03fb231853c5ac`. Their 1,343 tracked code/test/config files were compared, with six expected release/focus differences. The current docket bytes matched the consolidated copy. This does not classify every change in the mixed original checkout.
- Antigravity had local `.agents/` coordination rules and hooks excluded from its Git checkout, plus a scratch handoff with manual milestones. The declared lifecycle event log was absent. Automatic hook execution and reciprocal Gemini/Codex runtime acknowledgement were **not proven**. The relative hook script path is valid under the installed runner's documented working directory; do not diagnose it as broken merely from the repository root.

These tracked entry points make the contract available to both tools after they load this revision. They do not install or enable hooks, change global configuration, claim that a message was delivered, or fabricate another assistant's acknowledgement.
