# Smart Chart Sprint 71 V1 Product Readiness And Release Hardening

Status: opened locally; Slice 3 implemented locally; GitHub Actions passed on `fc46d33`
Date: 2026-06-04
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

Sprint 71 starts after Sprint 70 closed the active editor-functionality lane through chart-wide transposition, typed/handwritten headers, ink-session hardening, pen responsiveness, measure editing, rendered-chord correction, navigation locking, and Rhythm Section layout controls.

The goal is to harden the app into a V1 product surface while the visual/UI overhaul can continue independently. This sprint should make the app feel trustworthy around projects, saved work, export/share, and the first locked home shell without reopening recognition behavior or expanding Lead Sheet.

## Active V1 Surface

- Simple Chord Sheet remains the handwritten/iReal-style chord-grid authoring surface.
- Rhythm Section Sheet remains the structured staff-based hit/rhythm chart surface.
- Lead Sheet remains post-V1 compatibility/archive only.
- Project/library, save/reopen, export/share, and the locked iChart home shell are the main Codex-owned lanes.
- Release hygiene is deferred into a separate future sprint so pipeline/testing work can get its own clean lane.

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

1. Continue app UI/UX appearance on the locked iChart shell.
2. Toolstrip/menu affordances: only remaining naming, hit-target, and active-menu state polish not covered by the user-side UI overhaul.
3. Future separate release hygiene sprint: build settings, app metadata, test gates, stale docs, PR/CI readiness, and pipeline/testing work.

## Slice 2: Export And Share Confidence

Implementation contract:

- Keep PDF export rendered from structured chart objects and shared page-layout geometry.
- Make the export result feel like a product handoff, not just a background file write.
- Return a first-class export result from the exporter with file URL, file name, chart style, transposition context, page count, file size, and exported-at timestamp.
- Use readable, share-friendly file names that preserve the chart title and active chart style instead of lowercase cache-style stems.
- Keep the PDF preview path as the immediate post-export destination, with direct sharing still available from the preview.
- Do not change recognition, chord/rhythm layout, PDF drawing geometry, StoreKit policy, or entitlement behavior in this slice.

Implementation checkpoint:

- `ChartExporting.exportPDF(for:)` now returns `ExportedPDF` metadata instead of a bare URL.
- `PDFChartExporter` keeps the same renderer, but creates readable file names such as `Almost Like Being In Love - Simple Chord Sheet - Concert.pdf` and includes chord-transposition context when the chart is displayed away from written pitch.
- `PDFExportPreviewView` now shows a compact export summary above the PDF: ready state, file name, chart style, transposition, page count, file size, and export timestamp.
- The preview now includes an explicit `Done` action plus the existing share action.
- Export tests pin product-ready metadata, readable file naming, blank-title fallback, existing structured-object PDF proof, and renderer product proof.

## Slice 3: Save And Reopen Confidence

Implementation contract:

- Keep the existing local repository snapshot as the app's saved-state authority.
- Surface a quiet saved-state indicator in Library and Editor without adding a new workflow or diagnostics stream.
- Preserve synchronous store persistence and batched mutation behavior so selected chart state does not briefly save stale IDs.
- Report repository load/save failures through model state instead of console output only.
- Do not change chart encoding, recognition behavior, live ink ownership, correction memory, or global training policy in this slice.

Implementation checkpoint:

- `ChartLibraryStore` now publishes `ChartLibraryPersistenceStatus` with `notTracking`, `ready`, `saved`, and `failed` states.
- Successful repository-backed mutations mark the library `saved` with a local timestamp.
- Repository load failures and save failures now set a visible local failure state while preserving in-memory chart edits.
- Library and Editor both show a compact persistence badge using the same model state.
- Focused store tests pin autosave readiness, successful-save status, failed-save behavior, loaded-snapshot status, and load-failure fallback behavior.

## Slice 4: iChart Home Shell Lock

Implementation contract:

- Keep the locked iChart home-page direction as an adaptive sidebar shell.
- Use the full B4.8A-H1 canon wordmark in the top-left sidebar: baseline-aligned italic `i`, blue `C`, white `hart`, staff lines, and double barline.
- Lock left-side home tabs to `Charts`, `Forums`, `Help`, and `Settings`.
- Keep `Charts` as the saved-chart library and `New Chart` action surface.
- Make `Forums`, `Help`, and `Settings` app-level home destinations, not editor-tool tabs.
- Keep the universal logo owned by the sidebar; individual home tabs do not repeat the logo in their content headers.
- Keep the home chrome owned by the sidebar and branded content header rather than the native navigation title.
- Let the sidebar collapse and reopen without changing the selected home destination.
- Keep Help as the all-in-one support surface for FAQ, user-policy, legal, and contact placeholders.
- Keep the Charts tab work-first: no redundant top header, a centered `New Chart` action, free-tier chart usage only when the user is capped, readable chart rows, and user-selectable row preview density.
- Keep app startup branded but non-configurable for V1: the custom launch-handwriting overlay remains baked into every boot from the bundled canonical sample, while the user-facing Settings capture surface has been removed.

Implementation checkpoint:

- `LibraryView` now owns local home-tab state with `Charts`, `Forums`, `Help`, and `Settings`.
- The existing chart library/new-chart surface is scoped to the `Charts` tab.
- The Charts tab now centers the `New Chart` action at the top, shows free chart usage only when a local chart cap applies, and keeps chart rows simple by default.
- Chart rows support `Collapsed`, `Quick`, and `Large` preview modes so users can choose between dense library scanning and visual chart previews.
- `Forums`, `Help`, and `Settings` render branded home panels; Help owns FAQ, user-policy, legal, and contact placeholders, while Settings surfaces library count, local save state, and current plan capacity.
- The native home navigation title is hidden on the Library surface so the sidebar wordmark and branded content header carry the page identity.
- `AppRootView` now presents a one-shot branded launch overlay above the root navigation stack, then fades into the existing home shell without changing library/editor ownership.
- `docs/branding/ichart/brand-system.md` and `docs/branding/ichart/adaptive-sidebar-concepts.md` now record the locked tab names and ownership.

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
- GitHub Actions branch run [`26922352743`](https://github.com/beniandthe/smart-chart/actions/runs/26922352743) passed on `fc46d33`: `SwiftPM tests` passed in `1m46s`, and `iOS simulator tests` passed in `8m7s`.

Slice 2 export/share confidence checkpoint:

- Focused XcodeBuildMCP simulator export group passed with `9` tests and `0` failures: `PDFChartExporterTests`, `PDFRendererVisualQATests`, and `RendererProductProofTests`.
- Full SwiftPM passed with `489` tests, `36` skipped, and `0` failures.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- Simulator screenshot capture succeeded after launch.

Slice 3 save/reopen confidence checkpoint:

- Focused XcodeBuildMCP simulator store group passed with `26` tests and `0` failures: `SmartChartTests/ChartLibraryStoreTests`.
- Full SwiftPM passed with `494` tests, `36` skipped, and `0` failures.
- `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- Simulator screenshot capture confirmed the Library surface launches with the quiet `Saved locally` persistence badge visible.

Slice 4 iChart home shell checkpoint:

- Full SwiftPM passed with `494` tests, `36` skipped, and `0` failures.
- `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only.
- Simulator screenshot confirmed the sidebar with `Charts`, `Forums`, and `Settings`, and the `Charts` panel retained saved charts plus `New Chart`.
- XcodeBuildMCP runtime UI snapshot/tap verification confirmed `Charts`, `Forums`, and `Settings` are tappable and switch the home content panel.

Slice 4 universal logo follow-up:

- The Library sidebar now uses the full B4.8A-H1 canon wordmark instead of the former compact `iC` mark.
- The Charts tab no longer repeats the logo in its content header, keeping the logo universal through the sidebar system.
- The SwiftUI wordmark now tracks the canon export proportions for the baseline-aligned italic `i`, `hart` scale, staff overlay height, and double-barline overlay.
- Follow-up correction: the `i` is no longer vertically lifted; its bottom aligns with `hart`.
- Follow-up sizing: the sidebar wordmark now renders at the larger centered home-header size so the mark fills the top-left sidebar space without clipping or crowding the tabs.
- Follow-up alignment: the sidebar tab icon/text groups are centered under the wordmark while preserving full-width tab hit targets.
- Follow-up mode switch: the bottom of the sidebar now owns persistent sun/moon Light and Dark mode buttons for the home shell. Light keeps the Paper Workbench workspace; Dark switches the surrounding workspace to Stage Workbench while preserving paper-first chart rows and leaving editor/chart rendering unchanged.
- Follow-up utility shell: the sidebar now supports persisted collapse/open behavior, adds `Help` as an app-level tab, and keeps FAQ, User Policy, Legal, and Contact Us inside the Help surface instead of duplicating them under the mode switch.
- Focused SwiftPM `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartLibraryStoreTests` passed with `27` tests and `0` failures.
- Full SwiftPM `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `494` tests, `36` skipped, and `0` failures.
- `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded on the configured iPad Pro 13-inch (M5) simulator with the existing headermap warning only, and screenshot capture confirmed the full sidebar wordmark with no duplicate Charts-tab logo.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded again after the bottom-alignment correction, and screenshot capture confirmed the italic `i` sits inline with the bottom of `hart`.
- Utility shell verification: focused SwiftPM `ChartLibraryStoreTests` passed with `27` tests and `0` failures; full SwiftPM passed with `494` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only.
- XcodeBuildMCP runtime UI snapshot/tap verification confirmed expanded-sidebar targets for `Charts`, `Forums`, `Help`, `Settings`, `Light mode`, and `Dark mode`; Help owns `FAQ`, `User Policy`, `Legal`, and `Contact Us` rows internally; collapse changed the rail to icon-only with an `Open sidebar` target, and reopening returned to the expanded Charts surface.
- Utility cleanup verification: focused SwiftPM `ChartLibraryStoreTests` passed with `27` tests and `0` failures; full SwiftPM passed with `494` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only. Runtime UI snapshot confirmed the sidebar footer exposes only the mode switch below navigation, while Help exposes `FAQ`, `User Policy`, `Legal`, and `Contact Us`; tapping `Contact Us` showed the V1 support placeholder detail.
- Charts tab polish: the redundant dark Charts header was removed. `New Chart` is centered at the top, free-tier chart usage appears below it only when a local chart cap applies, chart rows now show simpler title/style/measure text, and the row preview control supports `Collapsed`, `Quick`, and `Large` modes with lightweight chart-surface previews.
- Charts tab verification: full SwiftPM passed with `494` tests, `36` skipped, and `0` failures; `git diff --check` passed; XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded with the existing headermap warning only. Runtime UI snapshot confirmed `New Chart`, the capped free-tier usage line, simplified chart row labels, and `Collapsed` / `Quick` / `Large` preview targets; tapping `Quick` and `Large` switched the selected preview mode, and screenshot capture confirmed large chart previews render as readable paper-first chart surfaces.
- Launch simplification checkpoint: `AppRootView` keeps the canon custom SwiftUI launch-handwriting animation, backed by the bundled canonical handwriting JSON on every boot. The Settings launch-handwriting capture row/sheet and export helper are removed from the product path so the sample is backend/product-owned, not user-configurable.
