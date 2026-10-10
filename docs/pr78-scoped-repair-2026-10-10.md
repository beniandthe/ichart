# PR #78 scoped repair — October 10, 2026

## Scope and cause

The user authorized fixing the remaining PR issues before merging. The clean
release worktree was fast-forwarded to PR head
`d45b1260d34b91c2380bd1ab059e07d4ac21db16`, based on verified main
`28a6c296f126f18eaa982f1f6007d2ba102f2a0e`. The unrelated dirty editor/research
worktree was not edited or included.

1. **Alteration telemetry:** the parser represents `C7alt` and `C7altered` as
   canonical quality `alt`, with no explicit numeric alterations. The issue
   bucket checked only the latter. It now includes the canonical quality too.
   Three new regressions cover matched reads, parseable no-read raw candidates,
   trusted suppression and non-altered/invalid negatives. The existing explicit
   `(b9)` coverage remains. No recognition rule, parser, render behavior,
   telemetry schema or server allowlist changed.
2. **Mounted review regression:** remote native CI found zero fields during
   non-nil sheet replacement. Waiting for any presented controller was already
   satisfied by the old sheet, followed by a fixed 500 ms delay. The test could
   also submit unchanged `F` / `G7` seeds without exercising live editing.
   The replacement now requires exactly two current-text fields attached to the
   test window with nonzero bounds, reacquiring the controller on each bounded
   poll. A timeout records diagnostics and throws before editing/rendering.
   Both fields are changed to `F7` / `G9` and checked against the second batch's
   exact IDs. Same-batch refresh has a test-harness processing acknowledgment.
   Original immutable-ink, zero-clear and no-implicit-accept assertions remain.

The original non-nil test passed five isolated local runs before the readiness
repair. Therefore the remote failure was not locally reproduced, and this is
not claimed as a proven production UI defect or a production UI behavior fix.
Production sheet/layout code is unchanged. Independent source review found no
remaining actionable issue after the refresh acknowledgment was added.

## Local verification

- Explicit `iChart.xcodeproj`, generated from authoritative `project.yml`,
  locked resolved packages, Xcode 26.6, iOS 26.5 isolated iPad Air Simulator.
  No signing, physical iPad install, saved QA chart change or purchase occurred.
- Original non-nil baseline: **1 test, 5 runs passed**, zero failures/skips.
- Telemetry SwiftPM class: **12 passed**, zero failures/skips.
- Initial native telemetry/snapshot selection: **16 passed**, zero failures/skips.
- Final mounted-review/review-input/typed-input selection: **15 tests, 75 runs
  passed**, zero failures/skips. Counts verified from `xcresulttool`; repetitions
  are not 75 unique tests.
- Full SwiftPM: **1,683 passed / 0 failed / 89 skipped**, 1,772 total.
- Full native: **2,386 passed / 0 failed / 103 skipped**, 2,489 total, verified
  from `xcresulttool`. Both replacement-sheet tests pass in full-suite ordering.
- `git diff --check` passes. Project generation leaves no project-file diff.

Local evidence is retained at `/private/tmp/iChartPR78Repair.CIhgK0`, including
`baseline.xcresult`, `focused.xcresult`, `repeated-final.xcresult`, native/SwiftPM
logs and the full native result bundle. This temporary path is a local receipt,
not a portable CI artifact or long-term archive.

## Remaining gate

Local verification is complete; commit/push only the scoped policy, two test
files and this documentation. Fresh actual PR checks at the resulting exact head
remain required; local tests do not establish remote success. Resolve the alteration review thread
only against the implemented fix and tests. An independent approving review is
still required; the connected identity is the PR author and cannot supply it.
No app archive/upload, public release, privacy publication, campaign activation
or subscription change is part of this repair.
