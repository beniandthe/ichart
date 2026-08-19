# iChart 1.1.6 Build 49 TestFlight Notes

Date: 2026-08-19
Branch: `codex/1.1.6-build49-testflight`
Base commit: `1cd8872378a856ee32a27d18980734364d91528f`
Package intent: internal TestFlight distribution after PR #52 and PR #53 landed on `main`.

## Branch cleanup

- Deleted local stale branches whose upstreams were gone or whose pointers were superseded by merged `main`:
  - `codex/fix-pr52-review-barlines`
  - `codex/post-1.1.6-next-build`
  - `codex/chord-lane-draft-barlines`
- Left `codex/fix-rhythm-section-chord-spacing-boxes` in place because it still tracks `origin/codex/fix-rhythm-section-chord-spacing-boxes`.

## Warnings to carry forward

- Xcode still reports the iOS 17 deprecation for `onChange(of:perform:)` in `iChart/Features/Library/LibraryView.swift`.
- Xcode still reports Swift main-actor UIDevice warnings in `iChart/App/Telemetry/IChartTelemetry.swift`.
- The Simulator launch smoke reached the chart list, but the currently booted QA simulator was rotated 180 degrees at screenshot time. Treat this as simulator state unless reproduced in a fresh orientation pass.
- The Supabase readiness script skipped local Supabase reset/RLS integration because `ICHART_RUN_LOCAL_SUPABASE_QA` was not set. Non-mutating secret checks, Node function tests, focused Swift tests, and full SwiftPM passed.

## Build metadata

- Previous Apple-submitted build: `1.1.6 (48)`.
- This TestFlight package bumps only the build number to `1.1.6 (49)`.
