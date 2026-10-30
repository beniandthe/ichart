# Zoomable Free Ink paper — build 89, October 29, 2026

The user rejected build 88's unzoomable fixed page. The requested interaction is a landscape viewport onto an enlarged section of the same portrait paper, with pinch zoom and pan. Both ink shape and its position relative to the paper must stay fixed.

## Delivery

Main iChart **1.2.3 (89)** is installed in place and verified running on the connected iPad. A fresh complete backup was captured before installation. The final live library matches the final complete post-launch snapshot byte for byte. Physical pinch/pan/rotation acceptance on Becoming remains pending; simulator and source-data checks do not establish the user's device experience.

## Behavior and implementation

- A native `LeadSheetDocumentViewport` owns pan and pinch. It zooms a plain container around the original canvas. Canvas bounds, ink coordinates, notation geometry and persistence remain in logical paper coordinates.
- Initial presentation fits the paper width and starts at the top. Landscape therefore shows a larger section of a portrait document. Pinch ranges from one quarter to four times fit-width magnification. Smaller content is centered. Toolbar chrome remains outside the viewport.
- Rotation retains the user's zoom relative to fit-width and the logical paper point under the viewport center. At document edges, offsets clamp to the reachable content. Model echoes, ink saves and tool changes preserve the camera instead of resetting it.
- In Free Ink and other ink-editing modes, two direct fingers pan; in Browse/Select, one finger pans. Pinch accepts direct fingers. Pencil input stays with the existing drawing canvas. Gesture setup preserves external scroll locks. Native pinch touch filters are installed on the first layout after UIKit creates its recognizer.
- New documents use the existing PDF default portrait width of 932 points and a 1100-point base page height. Logical document height is independent of viewport height. Existing saved ink retains its authored width, including historical wide pages; no destructive width or ink migration is performed.
- The legacy parent gesture gate and vertical viewport restoration bypass the native viewport. Raster sharpness follows magnification with an eight-times scale limit and a 16-megapixel whole-canvas backing-store budget. This changes display resolution only.
- Build 88's exact paper-coordinate ink transform remains. No page-stroke grouping, translation, fitting or rescaling is reintroduced. Graph/MyScript, recognition providers/models and persisted schemas are unchanged.

## Validation

Final gates use the same production-source hashes:

| Gate | Passed | Skipped | Failed |
| --- | ---: | ---: | ---: |
| Editor, navigation, layout, ink persistence and export | 935 | 10 optional source replays | 0 |
| Appearance, separate process | 7 | 0 | 0 |
| Fresh current-device library, including Becoming's source ink | 4 | 0 | 0 |

Nine native viewport tests cover initial fit, first-layout pinch creation, multi-page focus, model/mode updates, external scroll lock, centered small content, document height changes, new-document reset and edge clamping. They include 64 rotation cycles in both starting orientations and 32 transitions between centered and scrollable content. Camera comparisons allow one physical pixel for UIKit offset rounding; ink/layout comparisons retain strict 0.01-point or exact identity checks.

Four integration tests mount the actual EditorView and use real toolbar actions. They verify unchanged logical geometry through rotation and pinch/pan, reachability of far-right legacy ink, camera preservation through tool/model changes, ink save/reopen fidelity and stable toolbar/window/viewport frames. Synthetic screenshots were visually inspected at portrait fit, landscape fit and landscape zoomed out. The landscape chrome's top 240 rows are pixel-identical at fit and zoomed out. Three bounded-raster tests cover ordinary, multipage and extreme finite sizes without allocating huge backing images. Existing exported-PDF pixel checks remain in the passing editor gate.

The previous build-88 combined-process PDFKit accessibility teardown crashes remain unresolved. Build 89's editor and appearance suites pass in separate processes; no combined-run or production PDF-lifecycle fix is claimed. Earlier failed results remain documented in `../free-ink-fixed-paper-2026-10-29/README.md`.

An independent final source review found no actionable issue. No recognition, model, resource or RecognitionStudy file changed. `git diff --check` passes. No push, PR, merge or publication was performed. The older dirty primary checkout remains untouched.

## Data preservation

The fresh immutable pre-install backup contains **62 files / 62,374,559 bytes**. Live and stopped library captures matched before installation. All backup hashes remain exact.

Before first launch, all **27 Application Support files** matched byte for byte. Four SplashBoard cache paths were renamed with identical content-hash multisets. All 53 other `com.ichart.*` app metadata records remained exact.

The first complete post-launch readback retained the complete library byte for byte. During the later check, normal cloud backup advanced 19 timestamps: `cloudBackupStatus.lastBackedUpAt` on each of 17 charts and the two library cloud sync/backup timestamps. The final complete readback and a later live library capture agree. Every other library and chart field, chart order, all ink archives/metadata, all 19 PDFs and their metadata, the one 15-entry setlist, and all three profile/correction/evaluation files remain exact. All 53 other app metadata records still match.

The final strict chart-object, library, Application Support, container and `materialDataExact` flags remain **false**; they were not relaxed to hide those timestamps. A separate classification verifies that the 19 values advanced and all other library/chart fields are identical. Final Application Support has 25/27 original files exact: library timestamps and the performance trace differ. Full-container differences also include caches, the same SplashBoard renames and the preference key `SKTransactionUpdatesLastChecked`. The first post-launch snapshot briefly included the normal telemetry queue. These observations do not turn the strict comparisons green.

No older backup was restored. Private charts, device metadata, provisioning material, source-ink previews and raw diagnostics remain ignored under `.build`.

## Evidence and next physical check

- Branch: `codex/free-ink-rotation`
- Signed package: `.build/installed-main-app-1.2.3-89/iChart.app`
- Fresh backup/readbacks: `.build/device-backups/2026-10-29-free-ink-89/`
- Final audit: `after-launch-final-audit.json`; timestamp classification: `final-cloud-timestamp-classification.json`; live/process check: `final-live-verification.json` under that backup folder.
- Editor result: `/private/tmp/ichart-free-ink-89-editor.xcresult`
- Appearance result: `/private/tmp/ichart-free-ink-89-appearance.xcresult`
- Current-library result: `/private/tmp/ichart-free-ink-89-current-library.xcresult`
- Source hashes: `.build/zoom-viewport-source-hashes.json`
- Synthetic previews: `.build/zoom-viewport-focused-previews/`
- Compact structured receipt: `receipt.json`

Open Becoming, pinch to a comfortable writing size, pan with two fingers in Free Ink, then rotate in both directions. The visible area may change with viewport shape or deliberate navigation; ink must keep its shape and position relative to the paper and notation. Confirm that pinch/pan feels stable on the physical iPad before calling the interaction accepted.
