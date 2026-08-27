# iChart 1.2 Build 50 TestFlight Notes

Date: 2026-08-27
Branch: `codex/v1-2-build50-release`
Base commit: `aecaabea088967de12cf2ab15c319a060909cba9`
Package intent: App Store Connect upload for TestFlight / Apple processing after PR #54 through PR #66 landed on `main`.

## Build Metadata

- Marketing version: `1.2`
- Build number: `50`
- Bundle identifier: `com.ichart.app`
- Team: `N6G8X4K46U`
- Release signing profile: `iChart App Store`

## Included Source Changes Since Build 49

- PR #54: Add explicit-render chord lane workflow.
- PR #55: Add unified Edit mode and terminal filler safeguards.
- PR #56: Update GitHub Actions dependencies.
- PR #57: Fix simple chord terminal barline measures.
- PR #58: Stabilize ink responsiveness and persistence.
- PR #59: Improve measure resize and chord edit guides.
- PR #60: Fix terminal repeat rendering and coda marker bounds.
- PR #61: Improve chord recognition trust pipeline.
- PR #62: Guard lane root targeting coverage.
- PR #63: Install XcodeGen without Homebrew in CI.
- PR #64: Lock live ink input to Apple Pencil on physical devices while preserving simulator automation.
- PR #65: Integrate Rhythm Section chord systems and related recognition/preview diagnostics.
- PR #66: Update tutorial and help UX for the Simple Chord Sheet walkthrough.
- `d60d37b`: Document future blockers before next major push.

## Verification Log

- `xcodegen generate`: pass.
- `git diff --check`: pass.
- `swift test --scratch-path /tmp/iChartSwiftBuild-v1-2-build50-config-20260827-002 --filter ProjectConfigurationTests`: 29 tests, 0 failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-v1-2-build50-full-20260827-001`: 793 tests, 41 skipped, 0 failures.
- Release build settings checked with `xcodebuild -project iChart.xcodeproj -scheme iChart -showBuildSettings -configuration Release -destination generic/platform=iOS`: version `1.2`, build `50`, bundle `com.ichart.app`, team `N6G8X4K46U`, manual App Store signing profile `iChart App Store`.
- Pending: release archive.
- Pending: App Store Connect export.
- Pending: App Store Connect upload.

## Evidence Boundaries

- This package is source-control, simulator/build, archive/export, and App Store Connect upload evidence.
- It is not physical iPad acceptance evidence.
- App Store Connect upload does not mean external TestFlight review, App Review submission, or public release unless those later states are explicitly observed.
