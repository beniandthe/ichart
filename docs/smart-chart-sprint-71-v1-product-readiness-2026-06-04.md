# Smart Chart Sprint 71 V1 Product Readiness And Release Hardening

Status: opened locally; Slice 1 implemented locally; GitHub Actions fix ready for branch rerun
Date: 2026-06-04
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

Sprint 71 starts after Sprint 70 closed the active editor-functionality lane through chart-wide transposition, typed/handwritten headers, ink-session hardening, pen responsiveness, measure editing, rendered-chord correction, navigation locking, and Rhythm Section layout controls.

The goal is to harden the app into a V1 product surface while the visual/UI overhaul can continue independently. This sprint should make the app feel trustworthy around projects, saved work, export/share, and release hygiene without reopening recognition behavior or expanding Lead Sheet.

## Active V1 Surface

- Simple Chord Sheet remains the handwritten/iReal-style chord-grid authoring surface.
- Rhythm Section Sheet remains the structured staff-based hit/rhythm chart surface.
- Lead Sheet remains post-V1 compatibility/archive only.
- Project/library, save/reopen, export/share, and release readiness are the main Codex-owned lanes.

## Slice 1: Project And Library Actions

Implementation contract:

- Add working project/library actions before broader polish: rename chart, duplicate chart, and delete chart.
- Keep actions model-backed through the library store/repository path so the saved library snapshot remains the authority.
- Preserve selected-chart behavior after each action:
  - Rename keeps the same selected chart.
  - Duplicate selects or clearly exposes the duplicate without mutating the original chart identity.
  - Delete moves selection to a neighboring chart when possible and never leaves stale selected-chart references.
- Delete must remove the saved chart document entry, not only the visible row.
- Duplicate must copy chart content while giving the new chart a fresh chart identity and a clear duplicate title.
- Keep developer/debug surfaces hidden or gated from the production-facing library surface.

Implementation checkpoint:

- `ChartLibraryStore` now owns model-backed `renameChart`, `duplicateChart`, and `deleteChart` operations.
- Rename trims titles, rejects empty titles, updates `updatedAt`, preserves the selected chart, and persists through the repository snapshot.
- Duplicate respects chart capacity, copies chart content, gives the duplicate a fresh chart identity, assigns a deterministic `Copy` / numbered-copy title, updates creation/update dates, inserts the duplicate beside the source chart, selects it, and persists the result.
- Delete removes the chart from the saved library snapshot, keeps existing valid selection when deleting another chart, selects the next/previous neighboring chart when deleting the selected chart, and clears selection when the library becomes empty.
- Batched store mutations suppress intermediate persistence so saved snapshots do not briefly contain stale selected-chart IDs.
- The Library row surface now exposes an action menu and context menu for rename, duplicate, and delete, with destructive delete confirmation.
- The Developer Tools section is removed from the production-facing Library surface; the debug store helper remains available to tests/debug code.

## Candidate Continuing Order

1. Project/library UX: rename, duplicate, delete, clearer metadata, and less developer-facing library behavior.
2. Export/share UX: obvious export flow, PDF preview confidence, file naming, and app-created export proof.
3. Save/reopen confidence: visible but quiet saved-state behavior.
4. Release hygiene: build settings, app metadata, test gates, stale docs, and PR/CI readiness.
5. Toolstrip/menu affordances: only remaining naming, hit-target, and active-menu state polish not covered by the user-side UI overhaul.

## Guardrails

- No chord-recognition score retuning.
- No rhythm-recognition score retuning.
- No OCR expansion.
- No personal handwriting fixture expansion.
- No default diagnostics stream.
- No global recognizer retraining from live passes.
- No Lead Sheet feature expansion before V1.
- No broad UI redesign that conflicts with the user-owned appearance pass.

## Verification Plan

- Focused model/store tests for rename, duplicate, delete, selected-chart cleanup, and repository snapshot persistence.
- Focused library UI tests where stable enough to protect visible actions.
- `git diff --check`.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`.
- Fresh simulator build/run before live app-surface validation.
- Update this doc and the source of truth after each major integration.

## Verification Log

- Slice 1 focused SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartLibraryStoreTests`
- Result: `22` tests, `0` failures.
- Full SwiftPM: `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
- Result: `489` tests, `36` skipped, `0` failures.
- `git diff --check` passed.
- Slice 1 app build/run: XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only after the row-action polish.

GitHub Actions audit checkpoint:

- Branch run `26921373138` failed in the iOS simulator job at `cf6c137` while SwiftPM stayed green.
- The failing assertions were PDF/export text checks for rendered chord strings. Local simulator reproduction showed the PDF text was present but extracted by PDFKit as separated semantic chord tokens such as `Db 7(b9)` and `G /B`, with music-symbol glyphs such as triangle sometimes omitted from extracted text.
- The fix adds `XCTAssertPDFExtractedTextContains` for chord-text export assertions only. It keeps exact text assertions for titles, labels, placeholders, and non-chord content while normalizing PDFKit extraction artifacts from role-based semantic chord rendering.
- Focused XcodeBuildMCP simulator export group passed with `7` tests and `0` failures after the fix.
- Full XcodeBuildMCP simulator test suite passed with `608` tests, `37` skipped, and `0` failures.
- Full SwiftPM passed again with `489` tests, `36` skipped, and `0` failures.
- `git diff --check` passed.
