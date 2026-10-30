# Free Ink navigation performance — build 90, October 29, 2026

The user confirmed that build 89's zoom, pan and fixed-paper ink behavior works, then reported that navigation felt slightly laggy. This pass reduces display work without changing camera, ink, notation or persistence geometry.

## Result

Main iChart **1.2.3 (90)** is installed in place and verified running. The complete post-launch library and final live library are byte-identical to the fresh pre-install backup. In a later physical test, the user confirmed that zoom/pan feels much smoother on Becoming and the ink still stays in place. Automated redraw checks are not frame-rate measurements; the structured receipt retains its original pre-feedback state.

## Change and evidence

Build 89 requested a raster-scale update on every zoom callback. That method unconditionally dirtied the full canvas, whose drawing code traverses every page and music system. Its backing image can reach the existing 16-megapixel limit. Repeated unchanged SwiftUI updates also requested display work. The transparent overlay views are hit surfaces, not additional notation-render passes.

Build 90 composites the existing rendered document throughout an active pinch, drag or momentum scroll. It coalesces display-quality requests and applies the latest actual zoom once navigation settles. Host updates use that same gate. Requests with unchanged zoom, raster target and actual view scales do no work; changed zoom still refreshes screen-sized controls even at the raster cap. A genuine overlay-scale reset is repaired.

The gate tracks zoom, pan and deceleration independently. It handles either pinch/pan end order, ignores delegate notifications inside programmatic geometry updates, clears stale activity on detach or document replacement, and releases an interrupted momentum wait at the start of a new pinch when native scrolling is no longer decelerating. The existing focal-point, fit-width, offset, logical-size and ink-transform calculations are unchanged.

The existing iPad trace from build 89 contains 16 sampled canvas draws, with a median of 1.62 ms and a maximum of 3.74 ms, and no slow-draw event. It samples early drawing rather than full gesture/compositor pacing. It does not establish the reported lag's end-to-end duration or a separate pan bottleneck. The supported conclusion is removal of avoidable raster requests; physical improvement still needs the user's comparison.

## Validation

| Final gate | Passed | Skipped | Failed |
| --- | ---: | ---: | ---: |
| Editor, navigation, layout, persistence and export | 944 | 10 optional source replays | 0 |
| Appearance, separate process | 7 | 0 | 0 |
| Fresh current-device library and Becoming source-ink replay | 4 | 0 | 0 |

Six new native-viewport lifecycle tests verify: 60 simulated pinch updates produce no display refresh during the gesture and one at completion; overlapping pinch/pan/model requests wait for momentum to finish; either gesture-end order works; plain pan adds no raster request; rotation during pinch preserves focus without raster work; detachment recovers; and a new pinch releases interrupted momentum. These are delegate-lifecycle replays on a real UIScrollView, not physical touch/frame-rate tests.

Three new small layer-state tests verify that 30 identical scale requests leave the canvas clean, changed zoom at the raster cap refreshes controls once, and a reset overlay scale is repaired. Existing exact-ink tests, actual EditorView integration checks, PDF-output checks and 64-cycle rotation tests remain unchanged and pass in the final gate. Camera rounding tolerance remains one physical pixel; exact ink/layout criteria are unchanged.

Editor and appearance suites run in separate processes because the earlier combined build-88 run had a PDFKit accessibility teardown crash. No combined-run or production PDF-lifecycle fix is claimed. Prior failed results remain documented in `../free-ink-fixed-paper-2026-10-29/README.md`.

## Data preservation and delivery

The fresh complete pre-install backup contains **62 files / 62,533,862 bytes**. Live and stopped library captures agreed. The backup is read-only and all hashes remain exact. Only the main `com.ichart.app` process was stopped; other installations were identified separately.

Before first launch, all **27 Application Support files** matched byte for byte. Four SplashBoard snapshots were renamed with identical content-hash multisets. After launch, all 17 complete chart objects, chart order, every ink field, the entire library, all 19 PDFs and metadata, the one 15-entry setlist and three profile/correction/evaluation files remain exact. The final live library matches both the full post-launch readback and the original fresh backup. All 53 other `com.ichart.*` app metadata records remain exact.

Strict full-container and Application Support flags remain false for runtime diagnostics/cache differences: 26/27 original support files match, the performance trace changed and the telemetry queue was added. No comparator exclusions were introduced. The separate saved-content flag is true. No old backup was restored.

Graph/MyScript, recognition providers/models, stored schemas, ink transforms, exports and notation layout were not changed by this pass. An independent scheduling review found no further concrete issue. No push, PR, merge or publication was performed. Raw private data, device identifiers, provisioning material and diagnostics remain ignored under `.build`.

## Evidence and next check

- Branch: `codex/free-ink-rotation`
- Signed package: `.build/installed-main-app-1.2.3-90/iChart.app`
- Fresh backup/readbacks: `.build/device-backups/2026-10-29-free-ink-90/`
- Audits: `after-install-audit.json`, `after-launch-audit.json`, `final-live-verification.json` under that backup directory.
- Editor result: `/private/tmp/ichart-free-ink-90-editor.xcresult`
- Appearance result: `/private/tmp/ichart-free-ink-90-appearance.xcresult`
- Current-library result: `/private/tmp/ichart-free-ink-90-current-library.xcresult`
- Source hashes: `.build/zoom-performance-source-hashes.json`
- Pre-patch trace summary: `.build/zoom-performance-89-trace-summary.json`
- Compact receipt: `receipt.json`

Physical acceptance: the user compared build 90 on Becoming and confirmed smoother navigation with stable ink. Existing pixels magnify during navigation and sharpen at rest. No further rendering changes are required for this report.
