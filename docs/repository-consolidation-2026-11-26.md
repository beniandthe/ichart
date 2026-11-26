# Repository consolidation — November 26, 2026

## Scope and source coverage

The user authorized auditing and combining the active non-ML work so the normal
public beta has one repeatable source path. The integration review is
[Prepare iChart 1.9.4 (199) and reconcile editor CI](https://github.com/beniandthe/ichart/pull/113).
Its live head/checks and eventual merge receipt determine readiness; this audit
is not a claim that pending hosted checks have passed.

At inventory, GitHub had four branches: protected `main`, the original
`codex/build-199-1.9.4` candidate, its `codex/build199-ci-repair` integration, and
one Dependabot CodeQL branch. There were two open pull requests. Preserve recovery
refs before removing superseded branch names; do not bypass main protection.

The active Codex editor chain through `4eae2c73` is included in the Antigravity
candidate `71b25144`: all 1,343 tracked app/test/package/config files are present.
The six differences are the later focus repair, its input-isolation coverage,
Build 199 metadata, and the updated guidance contract. Nine historical local
feature branch heads, plus the Fix037 head, are ancestors of the completed Codex
feature head; they are not additional unmerged features. The separate dirty fix
docket matches the candidate byte-for-byte.

## Changes and validation boundaries

- Keep the existing shipped keyboard responder fix. Correct stale Measures
  guidance tests and implicit-tail/explicit-boundary fixtures without changing
  app behavior, source-ink/range assertions or recognition deadlines. The cadence
  fixture waits for the existing ink canvas to own first responder before input.
- Include the pending CodeQL action update from 4.39.1 to 4.39.3. Its original
  dependency PR is superseded only after this reviewed change reaches `main`.
- Run full native CI once per pull-request update, then on `main` after merge.
  Keep manual dispatch and all required job names. Feature-branch push tests
  previously duplicated the pull-request tests. Research remains explicit opt-in.
- Provide tracked, shared agent entry instructions and a handoff contract.
  Exact ownership, immutable source and receipts must be acknowledged before
  integration; a local activity note does not establish automatic communication.

The test-only repair commit `ddab0e81` passed 97 selected native tests locally
(93 passed, four optional private-fixture skips, zero failures), followed by five
fresh-host cadence repetitions. Its two hosted SwiftPM runs each executed 2,163
tests (92 skipped, zero failures). Its full hosted Simulator and CodeQL outcomes
are separate receipts. Subsequent workflow/coordination maintenance requires new
checks on the final PR head; do not reuse an earlier green badge.

## Preserved work

The original mixed Documents checkout remains intact. All 20 tracked dirty paths
were classified: already represented readability/build-cache/marketing work,
parked NeuralInk wiring, or old deletions that must not replace the current app.
Older marketing copies would restore retired handwritten measure-repeat promises.
The duplicate recognition-session file would create duplicate declarations.

One unique non-ML slash-batch recognition prototype and its focused tests are
preserved privately as a follow-up. No surviving app caller constructs its
optional repair request, and its old session implementation lacks current
cancellation/cache/lifecycle safeguards. It is not a safe whole-file import.
A November 6 clarity audit is proposed-work evidence, not an implemented feature.
The private snapshot manifest records origin paths, hashes and the missing caller.

Do not reset, clean, blanket-commit or delete the mixed checkout, research
corpora/models, saved ink, device backups, QA evidence, or old worktrees on the
basis of age or a timed-out inventory. Git bundles cover committed objects;
uncommitted and untracked work requires its own verified private snapshot.

## Build and deployment gates

Use [the shared workflow](agent-coordination.md) and the
[fix docket](qa/ichart-fix-docket.md) for current ownership and physical retests.
`project.yml` is authoritative; regenerate with XcodeGen and keep build caches
outside iCloud. A zero-selected-test invocation is not validation.

Before merging, require all protected checks on the final candidate, resolved
conversations, and the live production auto-deploy guard. Keep main's strict
checks, linear history and no-force-push policy. Build/sign from the exact accepted
source with the normal public-beta packaging guard. Free Pro remains on; paid
staging inputs and local preview flags stay outside this release lane.

Source review, local tests, hosted tests, archive/signing, physical saved-data
readback, and Apple processing/distribution are separate receipts. This cleanup
does not claim new physical Pencil acceptance, an uploaded build, or a backend
rollout. Automatic cross-product hook execution still needs genuine runtime
proof; checked-in instructions make the manual handoff durable meanwhile.
