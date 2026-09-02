# iChart 1.2.1 Build 51 App Store Connect Notes

Date: 2026-09-02
Release source branch: `main`
Release source commit: release bump commit containing this file
Version: `1.2.1`
Build: `51`
Bundle ID: `com.ichart.app`
Distribution target: App Store Connect

## Public App Store "What's New"

> iChart 1.2.1 improves the chart-writing workflow with clearer chord-tool guidance, Help and Settings updates, true multi-page Add Page export behavior, and more predictable Simple Chord Sheet chord placement.

## TestFlight / Review-Facing Update Notes

- Includes the current UI/UX pass for first-use guidance, Help, Settings, chord-tool labeling, and chart setup copy.
- Adds true Add Page behavior so later pages are separate chart pages, inherit chart settings, and export as multi-page PDFs.
- Updates Simple Chord Sheet chord rendering to use deterministic placement slots for more predictable chord positioning.
- Keeps chord recognition in the explicit draft workflow until the user chooses `Render Chords`.
- Maintains the existing account, local library, PDF export, Pro subscription, and Forums boundaries.

## Release Gate Log

- Release bump commit: pending local commit.
- `xcodegen generate`: completed locally before commit.
- Release build settings verification: completed locally before commit; Xcode resolves `MARKETING_VERSION=1.2.1`, `CURRENT_PROJECT_VERSION=51`, `PRODUCT_BUNDLE_IDENTIFIER=com.ichart.app`, manual App Store signing, team `N6G8X4K46U`, and provisioning profile `iChart App Store`.
- Main GitHub Actions after release bump: pending.
- Release archive: pending.
- Export/upload to App Store Connect: pending.

## App Review Metadata Reminders

- Use the App Review notes from `docs/app-store-testflight-metadata-draft.md`.
- Put the App Review account password only in App Store Connect review metadata, never in source, chat, GitHub comments, or public release notes.
- Do not describe iChart as full notation engraving software or automatic rhythm recognition.
