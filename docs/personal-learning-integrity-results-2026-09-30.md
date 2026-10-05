# Personal learning integrity and comparison lineage

## Observed result

The scoped Simulator gate executed **85 tests: 85 passed, 0 failed, 0 skipped**.
The result bundle, executed test list, exact tested source snapshots and two
synthetic UI attachments are retained at:

`/Users/benirossman/.local/share/ichart/recognition-development/dual-view-residual-20260930.2AifRF/app-gate/`

This is app implementation evidence, not recognition accuracy, a fresh writer
test, physical-device interaction, an installed iPad update or release readiness.
The previously saved user passes were not repeated or relabeled in this turn.

## Changes

`PersonalHandwritingModel.update` previously checked active chart capture only
before enqueuing its profile edit. It now checks again inside the store update,
before invoking the edit. If capture started while the work waited, it throws
`activeRun`, publishes the error and omits the success callback. The default
serial queue is unchanged; an internal serial-queue injection supports
deterministic tests.

Two suspended-queue tests start capture after teaching was queued, then resume
the worker. Both verify unchanged persisted profile bytes, revision and examples,
no success completion/learned flag, and the visible capture error. The practice
test additionally verifies teaching succeeds after capture stops.

This covers that queued transition, **not** a globally atomic transaction
between the evaluation and profile stores. Capture may still start after the
worker's check. Scoped read-only lock-order review found no inverse held-lock
cycle: these learning paths briefly read evaluation state while holding the
profile lock; evaluation updates release their snapshot lock before invoking
profile-accessing edits. No wider locking redesign was made.

Saved learned reports now carry the exact optional `profileLineage` stored at
run start. They validate a supplied summary against that same frozen profile
before fitting lessons or encoding queries. Missing legacy metadata stays
unknown; the live profile never fills it in. Paired ownership reports require
identical optional lineage, including the legacy nil/nil case.

The actual comparison screen shows tracked, untracked, mismatched and overlapping
lesson counts, and distinguishes unknown, empty, incomplete, overlapping and
disjoint intake metadata. Details are expandable. These local identifiers do
not establish original acquisition, chronological separation, consent, writer
identity or fresh handwriting. Rankings, scoring and learning rules were not
changed by this report/UI work.

## Executed gate

After fresh branch/toolchain/process/Simulator checks, regenerated from
`project.yml` with XcodeGen 2.45.4. Ran explicit `iChart.xcodeproj`, `iChart`
scheme, isolated DerivedData, signing disabled, serial focused tests on
`0D3454BE-1A21-4910-8FD6-FFD3EB43E908` (iOS Simulator 26.5, build 23F77).
Xcode 26.6 / 17F113 on macOS 26.5.2. `xcodebuild test` exited 0; verified actual
counts through `xcresulttool get test-results summary` and the executed tree:

| Class | Passed |
| --- | ---: |
| PersonalHandwritingModelTests | 14 |
| PersonalInkLearnedComparisonTests | 24 |
| PersonalInkOwnershipComparisonTests | 13 |
| PersonalLearnedComparisonModelTests | 5 |
| ProjectConfigurationTests | 29 |
| Total | 85 |

Exported and visually inspected the actual hosted comparison view at 820×1180
and 1180×820 points using the controlled test result. The summary, uncertainty
warning and expandable metadata fit without horizontal clipping. These are
synthetic UI screenshots, not observations of the user's iPad or live model.

Sandboxed Simulator/result-tool access initially failed; scoped host access
resolved it. That was an environment permission issue, not a product failure.
Existing deprecation, telemetry actor-isolation and public grouping-test warning
debt remains in the retained build log. No compile errors occurred.

## Tested source bindings

- PersonalHandwritingView.swift:
  `41e808b16cc13d5faa99bda1bcba0e09c64d68f5282bf370b0f67f007b2996d3`
- PersonalHandwritingModelTests.swift:
  `b8dde3139ba75d7305fe533c6614f7ebcf13dc1b6785ecb63784886389da714d`
- PersonalInkLearnedComparison.swift:
  `6324b0af32482366501d2e278ab0e58da6f6414de640863060be1df94e3fef15`
- PersonalInkOwnershipComparison.swift:
  `c37699f30e0287d605551b570b5ea858bc5007eb864131f1c893cf43c9fe9231`
- PersonalLearnedComparisonView.swift:
  `2f4816b62f532e2148253c59ebcb23e0e0c03995faee6f7a5df6b601c7b35c34`

The gate does not deploy or install anything, mutate production, change a user's
profile/journal/chart ink, commit/push changes, or promote experimental ML.
