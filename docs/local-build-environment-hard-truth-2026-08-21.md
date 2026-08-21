# Local Build Environment Hard Truth

Date established: 2026-08-21
Repo: `/Users/benirossman/Documents/Smart Chart`
Project: iChart / Real Chart

This is the required local workflow for Codex, Xcode, Simulator, and Ben's iPad. Do not guess. Before claiming a build, test, smoke, device install, archive, upload, or release state, verify the relevant gate below and report the exact result.

## Verified Baseline

Current verified toolchain:

- Xcode path: `/Applications/Xcode.app/Contents/Developer`
- Xcode: `26.6` (`17F113`)
- Swift: Apple Swift `6.3.3`
- XcodeGen: `2.45.4` at `/Users/benirossman/.local/bin/xcodegen`
- App bundle id: `com.ichart.app`
- Test bundle id: `com.ichart.tests`
- Development team: `N6G8X4K46U`
- Current app version/build at setup time: `1.1.7 (49)`
- Source of truth for project generation: `project.yml`
- Generated project: `iChart.xcodeproj`
- Scheme: `iChart`
- Canonical simulator: `iChart Local QA iPad 26.5`
- Canonical simulator id: `0D3454BE-1A21-4910-8FD6-FFD3EB43E908`
- Canonical simulator runtime: iOS `26.5` (`23F77`)
- Physical device name: `Ben's iPad`
- Physical device CoreDevice id: `376D59F8-92F2-5260-B10E-BA0BEAF941AB`
- Physical device UDID: `00008101-000415AC1E9B001E`
- Physical device model: iPad Air 4th generation (`iPad13,2`)
- Physical device OS at setup time: iPadOS `26.5.2` (`23F84`)
- Physical device connection at setup time: wired, paired, tunnel connected, Developer Mode enabled

Environment fix applied on 2026-08-21:

- Debug signing is explicit automatic signing in `project.yml`.
- Release signing remains manual with `Apple Distribution` and provisioning profile `iChart App Store`.
- Reason: CLI device Debug builds failed with `"iChart" requires a provisioning profile` until Debug automatic signing was explicit.

## Verified Setup Results

These commands were run successfully on 2026-08-21:

- `xcodegen generate`
- `git status --short --branch` clean except intended doc/signing edits
- `xcodebuild build-for-testing -project iChart.xcodeproj -scheme iChart -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' CODE_SIGNING_ALLOWED=NO -quiet`
- `xcodebuild test -project iChart.xcodeproj -scheme iChart -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -only-testing:iChartTests/ProjectConfigurationTests CODE_SIGNING_ALLOWED=NO -quiet`
- Result: `ProjectConfigurationTests` passed `29/29`, `0` failed, `0` skipped
- Simulator install path: `Debug-iphonesimulator/iChart.app`
- Simulator launch result: `com.ichart.app: 10737`
- Physical iPad Debug build passed with `-allowProvisioningUpdates`
- Physical iPad install passed with `devicectl`
- Physical iPad launch passed with `devicectl`

Known warning debt at setup time:

- `LibraryView.swift`: deprecated `onChange(of:perform:)`
- `IChartTelemetry.swift`: `UIDevice.current` main-actor isolation warnings in simulator builds

Warnings are not blockers unless they become errors, multiply during the touched work, or relate to the feature being changed.

## Never Guess Rules

- Do not say the iPad is connected unless both CoreDevice and Xcode destinations see it.
- Do not say tests passed unless the result summary shows nonzero tests and zero failures.
- Do not treat simulator proof as physical iPad proof.
- Do not treat physical install/launch as product acceptance.
- Do not treat archive/export as TestFlight upload.
- Do not treat TestFlight upload as App Review submission.
- Do not treat App Review approval as public availability without checking public state.
- Do not run repeated blind retries. After two identical failures, stop and classify the blocker.
- Do not use bare `xcodebuild -scheme iChart`; always pass `-project iChart.xcodeproj`.
- Do not edit `iChart.xcodeproj` directly. Edit `project.yml`, then run `xcodegen generate`.

## Required Preflight Before Any Build

Run these first:

```sh
cd "/Users/benirossman/Documents/Smart Chart"
git status --short --branch
git fetch --all --prune
git status --short --branch
ps aux | rg 'xcodebuild|simctl|devicectl' | rg -v rg || true
xcode-select -p
xcodebuild -version
xcodegen --version
```

Required interpretation:

- The branch must be the intended branch for the task.
- Dirty files must be intentional and understood.
- No stale `xcodebuild`/`simctl`/`devicectl` process should be running before a new build/test.
- If `xcodegen` is missing, stop. Do not use the generated project as source of truth.

## Required Project Generation Gate

Run after any `project.yml`, source membership, signing, package, target, or build-setting change:

```sh
xcodegen generate
git diff --check
git status --short --branch
```

Required interpretation:

- Generated project drift is acceptable only when caused by the current intended change.
- Unexpected generated project drift is a blocker.

## Simulator Environment Gate

Use the canonical simulator unless the task explicitly requires another device size:

```sh
xcrun simctl list devices available | rg 'iChart Local QA iPad 26.5'
xcrun simctl boot 0D3454BE-1A21-4910-8FD6-FFD3EB43E908 2>/tmp/ichart-local-qa-boot.err || true
xcrun simctl bootstatus 0D3454BE-1A21-4910-8FD6-FFD3EB43E908 -b
```

If simulator launch/test reports `Busy` or preflight errors:

```sh
xcrun simctl shutdown all
xcrun simctl boot 0D3454BE-1A21-4910-8FD6-FFD3EB43E908 2>/tmp/ichart-local-qa-boot.err || true
xcrun simctl bootstatus 0D3454BE-1A21-4910-8FD6-FFD3EB43E908 -b
```

If the same simulator preflight error happens twice after shutdown/bootstatus, stop and report a runner-state blocker. Do not continue product debugging from that signal.

## Minimal Build Gate

Use this before any smoke or device install:

```sh
xcodebuild build-for-testing \
  -project iChart.xcodeproj \
  -scheme iChart \
  -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' \
  CODE_SIGNING_ALLOWED=NO \
  -quiet > /tmp/ichart-local-build-for-testing.log 2>&1
```

If it fails:

```sh
tail -n 220 /tmp/ichart-local-build-for-testing.log
```

Do not proceed to simulator UI or iPad work until this passes, unless the task is specifically to fix build failure.

## Minimal Test Gate

Use this as the cheap mandatory project health test:

```sh
xcodebuild test \
  -project iChart.xcodeproj \
  -scheme iChart \
  -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' \
  -only-testing:iChartTests/ProjectConfigurationTests \
  CODE_SIGNING_ALLOWED=NO \
  -quiet > /tmp/ichart-project-configuration-tests.log 2>&1
```

Read the result:

```sh
xcrun xcresulttool get test-results summary \
  --path "$(ls -td ~/Library/Developer/Xcode/DerivedData/iChart-*/Logs/Test/Test-iChart-*.xcresult | head -1)"
```

Required interpretation:

- `totalTestCount` must be greater than `0`.
- `failedTests` must be `0`.
- For this gate, expected result is `29` tests passed.

## Focused Test Gate

For feature work, run only tests covering the touched behavior first:

```sh
xcodebuild test \
  -project iChart.xcodeproj \
  -scheme iChart \
  -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' \
  -only-testing:iChartTests/<TestClassName>/<testMethodName> \
  CODE_SIGNING_ALLOWED=NO \
  -quiet > /tmp/ichart-focused-tests.log 2>&1
```

Rules:

- Use exact XCTest names.
- Verify nonzero test execution with `xcresulttool`.
- Do not keep adding focused tests after failures without first identifying whether the failure is code, fixture, signing, simulator runner, or test filter.

## Simulator Smoke Gate

After the minimal build gate:

```sh
APP_PATH="$(ls -td ~/Library/Developer/Xcode/DerivedData/iChart-*/Build/Products/Debug-iphonesimulator/iChart.app | head -1)"
xcrun simctl install 0D3454BE-1A21-4910-8FD6-FFD3EB43E908 "$APP_PATH"
xcrun simctl launch --terminate-running-process 0D3454BE-1A21-4910-8FD6-FFD3EB43E908 com.ichart.app
```

Required interpretation:

- Install must exit `0`.
- Launch must return a process id.
- This proves app startup only. It does not prove visual behavior.

## Physical iPad Connection Gate

Run both checks:

```sh
xcrun devicectl list devices
xcrun devicectl device info details --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB
xcodebuild -showdestinations -project iChart.xcodeproj -scheme iChart | rg "Ben|00008101-000415AC1E9B001E|iOS,"
```

Required interpretation:

- `devicectl` must show `Ben's iPad` connected.
- Device details must show wired transport, paired state, tunnel connected, and Developer Mode enabled.
- `xcodebuild -showdestinations` must include `id:00008101-000415AC1E9B001E, name:Ben's iPad`.

If any of these fail, the iPad is not ready for Codex-controlled device QA.

## Physical iPad Debug Build Gate

Run:

```sh
xcodebuild build \
  -project iChart.xcodeproj \
  -scheme iChart \
  -destination 'id=00008101-000415AC1E9B001E' \
  -configuration Debug \
  -allowProvisioningUpdates \
  -quiet > /tmp/ichart-physical-ipad-debug-build.log 2>&1
```

If it fails:

```sh
tail -n 260 /tmp/ichart-physical-ipad-debug-build.log
```

Known signing rule:

- Debug uses automatic signing.
- Release uses manual App Store signing.
- Do not change Release signing to fix Debug device builds.

## Physical iPad Install And Launch Gate

After the physical Debug build gate:

```sh
DEVICE_APP_PATH="$(ls -td ~/Library/Developer/Xcode/DerivedData/iChart-*/Build/Products/Debug-iphoneos/iChart.app | head -1)"
xcrun devicectl device install app \
  --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB \
  "$DEVICE_APP_PATH" \
  --timeout 60
xcrun devicectl device process launch \
  --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB \
  --terminate-existing \
  com.ichart.app \
  --timeout 30
```

Required interpretation:

- Install output must include `bundleID: com.ichart.app`.
- Launch output must say the application launched.
- This proves install/launch only. The user's live iPad observation is still the visual/product acceptance signal.

## Visual QA Gate

For editor, handwriting, chord lane, layout, PencilKit, or recognition work:

- Automated tests are necessary but not sufficient.
- Simulator launch is necessary but not sufficient.
- Physical iPad launch is necessary but not sufficient.
- Acceptance requires direct simulator screenshot/video review or user-observed physical iPad behavior.

Record:

- branch
- commit
- app version/build
- simulator id or iPad id
- exact scenario
- expected behavior
- observed behavior
- screenshot/video path if available
- whether this is proof, partial proof, or a blocker

## Analysis And Telemetry Gate

Use privacy-safe aggregate data only:

- allowed: event counts, confidence buckets, timing buckets, chart style, candidate count, rendered count, unresolved count
- disallowed: raw chord text, drawing payloads, chart titles, user names, emails, PII

Do not inspect Gmail/support or mutate Supabase production unless the task explicitly authorizes it.

## Release Packaging Gate

Release packaging is separate from local QA. Do not run upload/submission commands without explicit user approval.

Before archive/export:

```sh
git status --short --branch
xcodegen generate
git diff --check
xcodebuild test \
  -project iChart.xcodeproj \
  -scheme iChart \
  -destination 'id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' \
  -only-testing:iChartTests/ProjectConfigurationTests \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
```

Archive/export proof is not upload proof. Upload proof is not TestFlight availability. TestFlight availability is not App Review. App Review approval is not public availability until checked.

## Efficiency Rules

- Start with the smallest gate that can answer the question.
- Use one canonical simulator unless viewport/device size is the point of the test.
- Run full suites only for broad changes, release gates, or when focused tests are insufficient.
- Do not run more than two retries of the same failing command without changing the blocker hypothesis.
- Always inspect the log tail or result bundle after failure before rerunning.
- Use `multi_tool_use.parallel` for independent reads; do not serialize basic repo/toolchain checks.
- Keep implementation branches scoped. Chord-lane workflow and recognition accuracy must not be patched together.

## Current Branch Expectations

Course-correction branches:

- `codex/chord-lane-auto-render`: chord lane UI/render/edit/barline workflow only
- `codex/chord-correction-accuracy`: recognizer grouping/accuracy/trust only
- `codex/chord-course-correction-docs`: documentation baseline

If work crosses these boundaries, stop and split the change before coding.
