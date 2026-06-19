# iChart — macOS Handoff

Updated: 2026-04-22

## Purpose

This document is the quickest way to resume iChart on a Mac after the Windows planning/scaffolding phase.

Use this together with:
- `README.md`
- `docs/core-design-document.md`
- `docs/developer-mvp-spec.md`
- `docs/technical-architecture.md`
- `project.yml`

## What is already in the repo

### Docs
- Product scope is aligned around a rhythm-aware chord-chart app, not full notation.
- Monetization is explicitly documented as:
  - mandatory Basic account for identity, recovery, profile, and subscription state
  - local-first chart authoring
  - Basic 3-chart cap with complete local tool and PDF/export access
  - Pro subscription for unlimited chart capacity, Forums, cloud chart backup/sync/restore, and other service-backed features

### App scaffold
- `project.yml` defines an iPad app target plus a unit-test target via XcodeGen.
- `iChart/` contains a SwiftUI library/editor shell.
- `iChartTests/` contains unit tests for parsing, transposition, timing validation, editing, and entitlement behavior.

### Current prototype behavior
- Library screen with sample charts and a new-chart flow
- Editor shell with:
  - chart title
  - document key
  - meter controls
  - toolbar menus for fonts, transpose, notation, and text
  - measure cards with rhythm-aware chord-event rendering
- Monetization scaffolding with:
  - legacy entitlement enum names pending migration to Basic / Pro subscription wording
  - Basic 3-chart cap logic
  - prototype upgrade sheet
  - prototype plan switcher in the library

## Important known gaps

These are not bugs in the handoff. They are expected unfinished areas:
- no generated `.xcodeproj` is checked in yet
- no PencilKit capture yet
- no real handwriting recognition yet
- no real PDF render/share flow yet
- no StoreKit integration yet
- no SwiftData persistence yet
- no Mac-side build verification has happened yet

## First steps on the Mac

If full Xcode is not installed yet, you can still validate that the shared chart logic compiles:
- `swift build`

1. Install or verify:
   - Xcode
   - Xcode command-line tools
   - XcodeGen
2. From the repo root, run:
   - `xcodegen generate`
3. Open the generated `iChart.xcodeproj` in Xcode.
4. Confirm the target/device setup is iPad-oriented.
5. Run the unit tests.
6. Launch the app in the iPad simulator.
7. If available, run it on the physical iPad.

## Important local build note

If the repo is stored in a file-provider-managed `Documents` location, Xcode may attach Finder or File Provider metadata to in-repo build output and codesigning can fail.

Use a DerivedData path outside the repo for command-line builds and tests:
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.4.1' -derivedDataPath /tmp/iChartDerivedData build`
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.4.1' -derivedDataPath /tmp/iChartDerivedData test`

## First things to validate in Xcode

Validate these before doing new feature work:
- sample charts load in the library
- new chart creation works
- editor shell renders without layout issues
- meter controls behave correctly
- locked Pro actions show the upgrade sheet in Basic mode
- prototype plan switching updates the UI
- test target compiles and executes

## Files to look at first

- `project.yml`
- `iChart/App/IChartApp.swift`
- `iChart/App/AppRootView.swift`
- `iChart/Features/Library/ChartLibraryStore.swift`
- `iChart/Features/Library/LibraryView.swift`
- `iChart/Features/Editor/EditorView.swift`
- `iChart/Models/Chart.swift`
- `iChart/Models/AppEntitlements.swift`
- `iChart/Shared/SampleData/ChartSamples.swift`

## Good next implementation steps after Mac validation

Recommended next work once the project opens and runs:
- generate the Xcode project and fix any compile issues
- keep PDF/export available in Basic and wire Pro gates around cloud sync and Forums
- replace in-memory chart storage with SwiftData
- build the selection inspector
- add PencilKit capture and the first ink-grouping pipeline

## Notes from the Windows phase

- The repo was restructured from docs-only into a docs + app scaffold layout.
- Old duplicate docs were removed and replaced with a real `docs/` directory.
- A real `.gitignore` and XcodeGen `project.yml` were added.
- The current branch contains all of that work as one coherent bootstrap checkpoint.
