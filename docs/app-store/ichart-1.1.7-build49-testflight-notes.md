# iChart 1.1.7 Build 49 TestFlight Notes

Date: 2026-08-19
Branch: `codex/1.1.7-build49-testflight`
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
- The first TestFlight attempt used `1.1.6 (49)`, but App Store Connect rejected it because the `1.1.6` train is closed after approval.
- This TestFlight package advances the marketing version to `1.1.7 (49)`.

## Validation evidence

- `xcodegen generate`: pass, no tracked project diff.
- `git diff --check`: pass.
- `swift test --filter ProjectConfigurationTests`: 29 tests, 0 failures.
- `swift test`: 710 tests, 38 skipped, 0 failures.
- `scripts/run_supabase_production_readiness.sh`: non-mutating checks passed with full SwiftPM run skipped only because it was run separately.
- `xcodebuild test -project iChart.xcodeproj -scheme iChart`: succeeded on simulator `4C1D2CA2-5E1C-4CF1-95EE-F16EA7343384` with 870 tests, 38 skipped, 0 failures.
- Release device compile with signing disabled: pass.
- After the App Store Connect train rejection, the `1.1.7` version correction reran `xcodegen generate`, `git diff --check`, `swift test --filter ProjectConfigurationTests`, and Xcode build-setting verification.

## Packaging evidence

- Signing identity: `Apple Distribution: Benjamin Rossman (N6G8X4K46U)`.
- Provisioning profile: `iChart App Store`, bundle `N6G8X4K46U.com.ichart.app`, expires `2027-06-20`.
- First archive attempt: `/Users/benirossman/Library/Developer/Xcode/Archives/2026-08-19/iChart-1.1.6-build49-20260819-091310.xcarchive`.
- First archive metadata: bundle `com.ichart.app`, version `1.1.6`, build `49`, team `N6G8X4K46U`.
- First exported IPA: `/tmp/ichart-build49-export-20260819-091413/iChart.ipa`.
- First local App Store Connect export: succeeded.
- Corrected archive: `/Users/benirossman/Library/Developer/Xcode/Archives/2026-08-19/iChart-1.1.7-build49-20260819-092314.xcarchive`.
- Corrected archive metadata: bundle `com.ichart.app`, version `1.1.7`, build `49`, team `N6G8X4K46U`.
- Corrected exported IPA: `/tmp/ichart-1.1.7-build49-export-20260819-092457/iChart.ipa`.
- Corrected local App Store Connect export: succeeded.

## Upload status

- Initial command-line App Store Connect upload did not complete because Xcode had no usable App Store Connect account credential on this machine.
- After Xcode sign-in, App Store Connect rejected `1.1.6 (49)` with code `90062` and code `90186`: the `1.1.6` train is closed for new build submissions.
- The corrected `1.1.7 (49)` upload did not leave the machine because `xcodebuild` still cannot load App Store Connect credentials for account identifier `15188795-D012-4DAB-B3E7-21A3D2ADB8F4`.
- Xcode error: `Invalid credentials in keychain ... missing Xcode-Username`, followed by `exportArchive Failed to Use Accounts`.
- The corrected package is ready for upload once the local Xcode account keychain entry is repaired or an App Store Connect API key/app-specific password upload route is available.
