# iChart Sprint 53: Validation Speed

Status: complete
Date: 2026-05-26
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Goal

Keep validation trustworthy without making every small product pass wait on the longest security/build lane.

## Trigger

Sprint 52's chord confirmation/user loop is functionally validated by the user, and the next blocker is workflow drag: waiting roughly 15 to 20 minutes for every small pass makes product iteration feel heavier than the code changes justify.

## Rules

- SwiftPM and iOS simulator checks remain the default app-health gates for app-impacting changes.
- Documentation/config-only passes should not run full app test suites when no app, package, project, script, or test file changed.
- CodeQL remains real security coverage, but it does not need to block every direct `main` sprint push.
- CodeQL still runs on pull requests, weekly schedule, and manual dispatch.
- Do not weaken writer-agnostic recognition policy, correction-memory boundaries, or any runtime recognition behavior as part of CI cleanup.

## Implementation

- Direct `main` pushes keep an `Analyze Swift` check run, but that check explicitly reports CodeQL as deferred.
- Pull requests, scheduled runs, and manual runs execute real Swift CodeQL analysis.
- SwiftPM and iOS simulator jobs detect app-impacting paths and no-op quickly for docs/config-only passes while preserving the existing required check names.

## Acceptance Criteria

- A docs-only push should complete the required check contexts quickly without running SwiftPM, Xcode simulator tests, or CodeQL.
- An app-impacting push should still run SwiftPM and iOS simulator tests.
- A pull request should still run real CodeQL.
- The workflow files should remain valid YAML and pass `git diff --check`.
- The source-of-truth doc should record the tradeoff clearly so future sprint checkups do not mistake deferred CodeQL for a missing app test.

## Verification Plan

- `git diff --check`
- Inspect workflow syntax and path rules locally.
- Push and confirm required check contexts complete.
- After push, confirm the direct-main `Analyze Swift` job reports the intentional defer instead of spending the full CodeQL build time.

## Verification Evidence

- Local workflow YAML parse passed for `.github/workflows/ci.yml` and `.github/workflows/codeql.yml`.
- `git diff --check` passed.
- Main commit `89ec2dc Speed up sprint validation checks` passed `SwiftPM tests`, `iOS simulator tests`, `Analyze Swift`, and `Dependabot`.
- The direct-main `Analyze Swift` log explicitly reported: `CodeQL is deferred on direct main pushes; it still runs on pull requests, the weekly schedule, and manual dispatch.`
- `Analyze Swift` completed quickly instead of running the full Swift CodeQL build.

## Follow-Up

- Use the next doc-only/source-of-truth closeout commit to prove the docs/config-only no-op path for SwiftPM and iOS simulator jobs.
- Keep full app validation for app-impacting changes and broad project configuration changes.
