# iChart V1.1.1 Health Diagnostic

Checked: 2026-08-12T17:23:23Z
Build-prep update: 2026-08-12T18:04:00Z
Branch: `codex/v1-1-1-trust-bugfixes`

## Overall Status

Local repo/app health is green. Full SwiftPM and full iOS simulator tests pass.

Release/live readiness is yellow because the latest hosted support/verify pages
are not live yet and one production QA account remains from the live auth-flow
test.

No red release-blocking code test failure was found in this pass.

## What V1.1.1 Touched

### Auth And Verification Trust

Touched:

- `iChart/App/Auth/IChartAuthStore.swift`
- `iChart/Features/Library/LibraryView.swift`
- `public-site/useichart/verify.html`
- `public-site/useichart/support.html`
- `docs/app-text-qa-inventory-2026-06-15.md`
- `docs/supabase-production-readiness-checklist.md`
- `docs/ichart-v1-2-roadmap.md`
- `iChartTests/ProjectConfigurationTests.swift`

Affected systems:

- first-run account screen defaults to Create Account
- pending verification state restoration
- pending auth-flow lifetime/email matching
- replacement verification email copy and rate-limit copy
- hosted browser handoff instructions
- support-page account-link instructions
- app-text QA and production-readiness docs

Current local finding: green. The app/source/docs/site no longer contain the
old confusing local phrases `Send Verification Email`, `Send One New Email`,
`newest iChart email`, `Use only the newest`, or `Do not use old iChart
emails`, excluding unrelated social docs.

Live finding: yellow. The live hosted pages are stale relative to local source.

- Local `public-site/useichart/verify.html` SHA256:
  `02eefdeedf8453f1e2304669f4ac598a14e39ca02b584eafee3dd0f057b5d6db`
- Live `https://useichart.com/verify.html` SHA256:
  `557444d849e83e0b1e79d6e3df2a4f7ec85616364f5f7ff761c8c6c54d7da3a7`
- Local `public-site/useichart/support.html` SHA256:
  `93ff19c3776af7a96ea2a50ee0ab8b5d4bfb31442bc7a60b81f97cd56c21e491`
- Live `https://useichart.com/support.html` SHA256:
  `5dcfab962583088fd47a31f5a4ef69c5eb5bf0d89de5dc50d587f04a1c20156a`

Live stale copy evidence:

- `verify.html` still has fallback steps that say `Tap Send Verification Email`.
- `support.html` still says `open iChart and tap Send Verification Email`.

Required action before claiming hosted sync: upload/overwrite the two local
files on IONOS and re-run cache-busted rendered/content checks.

### Manual Chord Alias Trust

Touched:

- `iChart/Services/ChartParsers.swift`
- `iChart/Services/ChordRecognitionCompendium.swift`
- `iChartTests/ChordSymbolParserTests.swift`
- `iChartTests/Recognition/ChordInkFixtureExporterTests.swift`
- `docs/ichart-v1-1-chord-coverage-baseline.md`

Affected systems:

- manual chord confirmation/correction
- typed chord entry
- chord fixture export validation
- compendium support printout/docs

Current finding: green. Major seventh aliases now cover forms like `CM7`,
`C M 7`, `C major 7`, and existing triangle/maj forms. Minor seventh aliases
cover `C-7`, `Cm7`, `Cmin7`, and spaced/written minor forms across chromatic
spellings. Unsupported bare major suffixes such as `CM`, `Cmaj`, `Cmajor`, and
`C major` still reject instead of guessing.

### Chord Placement, Time Signatures, And Layout

Touched:

- `iChart/Models/ChartEditing.swift`
- `iChart/Features/Editor/EditorView.swift`
- `iChart/Services/LeadSheetPageLayout.swift`
- `iChart/Features/Editor/Components/LeadSheetChordEditOverlayGeometry.swift`
- `iChartTests/ChartEditingTests.swift`
- `iChartTests/LeadSheetPageLayoutTests.swift`
- `iChartTests/Editor/LeadSheetChordEditOverlayGeometryTests.swift`
- `iChartTests/PDFChartExporterTests.swift`

Affected systems:

- selected-measure time signature targeting
- first-measure meter change behavior
- chord lane reservation next to inline time signatures
- simple chord sheet late-beat x-positioning
- rhythm-section continuation leading-barline spacing
- ending/coda roadmap marker layout and edit hit areas
- PDF export text/layout proof coverage

Current finding: green by automated coverage. Tests verify selected measure
receives the meter change, beat/subdivision positions move progressively, local
meter changes reserve a chord-safe lane, rhythm continuation stanzas avoid the
old fake-measure spacing, and ending/coda symbols have larger glyph-safe frames.

Manual visual QA is still recommended before release packaging because these
are visual/layout trust fixes.

### Roadmap And Release Docs

Touched/created:

- `docs/ichart-v1-1-1-bugfix-plan.md`
- `docs/ichart-v1-2-roadmap.md`
- `docs/ichart-v1-3-roadmap.md`
- `docs/ichart-v1-1-chord-coverage-baseline.md`
- `docs/app-text-qa-inventory-2026-06-15.md`
- `docs/supabase-production-readiness-checklist.md`

Current finding: green after one local fix. A stale V1.2 acceptance criterion
still said `Send Verification Email`; it was corrected in this pass to match
`Email Didn't Arrive?` and `Send Replacement Email`.

## Verification Run

Initial pass:

- `swift test --scratch-path /tmp/iChartSwiftBuild-v111-health`
  - 693 tests executed
  - 38 skipped
  - 0 failures
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=C95FB514-9CA7-4A50-B9FB-794F1934A087' -derivedDataPath /tmp/iChartDerived-v111-health GENERATE_INFOPLIST_FILE=YES test`
  - 794 tests executed
  - 38 skipped
  - 0 failures
  - result bundle: `/tmp/iChartDerived-v111-health/Logs/Test/Test-iChart-2026.08.12_10-19-37--0700.xcresult`
- `git diff --check`
  - clean
- local stale auth wording search
  - clean

Build 40 pass after V1.1.1 version bump:

- `xcodegen generate`
  - completed
  - generated local `iChart.xcodeproj/project.pbxproj` reports
    `MARKETING_VERSION = 1.1.1` and `CURRENT_PROJECT_VERSION = 40`
  - note: `iChart.xcodeproj/project.pbxproj` is ignored/generated; commit
    authority is `project.yml`
- `xcodebuild -project iChart.xcodeproj -scheme iChart -showBuildSettings`
  - `MARKETING_VERSION = 1.1.1`
  - `CURRENT_PROJECT_VERSION = 40`
  - `PRODUCT_BUNDLE_IDENTIFIER = com.ichart.app`
- `swift test --scratch-path /tmp/iChartSwiftBuild-v111-build40-config --filter ProjectConfigurationTests`
  - 29 tests executed
  - 0 failures
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=C95FB514-9CA7-4A50-B9FB-794F1934A087' -derivedDataPath /tmp/iChartDerived-v111-build40-build GENERATE_INFOPLIST_FILE=YES build`
  - build succeeded
- `swift test --scratch-path /tmp/iChartSwiftBuild-v111-build40-full`
  - 693 tests executed
  - 38 skipped
  - 0 failures
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=C95FB514-9CA7-4A50-B9FB-794F1934A087' -derivedDataPath /tmp/iChartDerived-v111-build40-test GENERATE_INFOPLIST_FILE=YES test`
  - 794 tests executed
  - 38 skipped
  - 0 failures
  - result bundle: `/tmp/iChartDerived-v111-build40-test/Logs/Test/Test-iChart-2026.08.12_11-02-49--0700.xcresult`
- Built simulator app Info.plist
  - version: `1.1.1`
  - build: `40`
  - bundle id: `com.ichart.app`
- Simulator launch proof
  - installed and launched on `C95FB514-9CA7-4A50-B9FB-794F1934A087`
  - app reached the Library UI
  - screenshot: `/tmp/ichart-v111-build40-launch-after5.png`
  - visible footer: `v1.1.1 - Aug 12, 2026`

Expected skips:

- live Supabase integration tests require `ICHART_SUPABASE_INTEGRATION=1`
- full ink fixture archive requires `ICHART_FULL_INK_FIXTURES=1`

## Production Supabase Read-Only Check

Project: `pausvvwoazbvmzyrebwl`
Probe time: 2026-08-12 17:21:20Z

The fresh QA signup account remains as the only `rossmanben+ichart-*` auth
user:

- auth users: 1
- created: 2026-08-12 16:58:57.383930Z
- confirmation sent: 2026-08-12 16:58:57.415954Z
- confirmed: 2026-08-12 17:02:02.088696Z
- last sign-in: 2026-08-12 17:02:02.102904Z
- profile scaffold rows: 1
- subscription scaffold rows: 1
- sessions: 1
- refresh tokens: 1
- chart documents: 0
- chart snapshots: 0
- devices: 0
- storage objects: 0

Finding: green for flow evidence, yellow for metrics hygiene. The QA account
proves create-account/confirm/sign-in/profile/subscription scaffold worked, but
it adds one artificial account/session/subscription row to production metrics
until explicitly removed.

Supabase advisor findings:

- Security WARN: insufficient MFA options enabled for Auth.
- Security INFO: `public.app_store_notification_events` has RLS enabled with no
  policies. This can be intentional if it is server-only/no client access, but
  should stay documented.
- Performance INFO: multiple unindexed foreign-key and unused-index advisories,
  mainly forum/subscription/chart tables. These are backlog/performance hygiene,
  not introduced by this V1.1.1 app patch.

## Worktree Hygiene

Yellow:

- There are unrelated or at least non-app-patch social/marketing doc changes in
  the dirty worktree:
  - `docs/marketing/social-media/content-calendar-template.csv`
  - `docs/marketing/social-media/social-launch-watch-state.md`
  - `docs/marketing/social-media/social-listening-response-queue.md`
  - untracked social launch analysis docs
- V1.1.1/V1.2/V1.3 roadmap docs are untracked and need to be intentionally
  staged for the release commit.

## Required Next Actions

1. Upload `public-site/useichart/verify.html` and
   `public-site/useichart/support.html` to IONOS, overwrite live files, and
   re-check cache-busted content for `Email Didn't Arrive?` and `Send
   Replacement Email`.
2. Keep the release metadata target as V1.1.1 build 40 unless App Store Connect
   rejects build 40 as already used.
3. Decide whether to remove the production QA account now or keep it briefly as
   evidence. If removed, use an explicit cleanup pass and re-check counts.
4. Stage only the intended V1.1.1 release files. Do not accidentally include
   unrelated social launch docs unless they are part of this commit.
5. Do one final manual visual QA pass on simulator/device for:
   - account pending verification screen and replacement drawer
   - simple chord sheet late beat placement
   - time signature selected-measure targeting
   - local time signature plus beat-1 chord collision
   - rhythm continuation stanza start
   - endings and coda symbols in editor and PDF
