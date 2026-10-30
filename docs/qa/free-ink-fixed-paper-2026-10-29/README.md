# Fixed paper for Free Ink — build 88, October 29, 2026

The user tested build 87 on **Becoming**: handwriting no longer deformed but still moved around the canvas. The acceptance requirement is now explicit: retain both the handwriting's exact position on the paper and its size on the first rotation in either direction.

## Result

**Main iChart 1.2.3 (88) is installed in place and verified running on the connected iPad.** The fresh current-data backup and final post-launch readback preserve all 17 chart objects/order/ink, 19 PDF documents and metadata, one 15-entry setlist, three profile/correction/evaluation files, and all 53 other `com.ichart.*` app metadata records. Manual iPad rotation and two-finger-pan acceptance remain pending.

## Change

- Free Ink uses exact saved paper coordinates. Musical anchors remain layout metadata; rotation no longer translates, groups, scales, fits or infers anchors for page handwriting. Generic header/chord/rhythmic mapping is unchanged.
- The editor keeps one logical document width once Free Ink exists or its tool is entered. Existing ink seeds that width from its saved coordinate space. New ink locks the actual logical width before the first stroke, including viewports below the layout engine's minimum. The toolbar follows the viewport; paper and notation stay fixed, at scale 1 and aligned to the top left.
- Both scroll axes expose the full original paper. Free Ink uses exactly two direct fingers to pan; Pencil remains ink. The old margin blocker is disabled in this mode. Original parent gesture configuration restores on mode exit, detach or reparenting. Repeated layout does not reassign already-correct recognizer settings. The tool hint explains the two-finger gesture.
- PDF export uses the same authored paper width. Legacy saved paper below today's minimum or above the lead-sheet cap is retained at its canonical width rather than clipped. No Chart schema or ink-archive migration is introduced.
- Build 87's line grouping/fitting code is removed from the current implementation; its source and delivery remain recoverable in commits `79b5daf7` and `8e99b9b1`.

Graph/MyScript projects, recognition providers/models, backend code and lab installations were not edited. The older dirty notation-readability checkout remains intact. No push, PR, merge or publication was performed.

## Validation and limits

The stricter no-movement cases failed **11/11** against the previous ink movement/fitting policy. Earlier shape-only assertions allowed a common translation and did not establish absolute placement on the first rotation.

Final validation uses the same source and simulator configuration in separate processes:

- Editor/navigation/layout/export partition: **920 passed / 10 optional source replays skipped / 0 failed** (930 total).
- Appearance partition: **7 passed / 0 skipped / 0 failed**.
- Exact test-ID audit: the partitions cover all **937** original IDs, with no missing, unexpected, overlapping or duplicate IDs.
- Final current-device library gate: **4 passed / 0 skipped / 0 failed**, including Becoming compared directly with its raw source drawing on the first portrait and landscape loads, repeated rotation/tool changes, persistence and source-fixture immutability.

The new production-editor tests mount the actual EditorView, activate real toolbar controls, rotate the viewport and compare retained paper, notation frames and exact stroke/nib positions. They verify a wide document's far-right ink is reachable at scale 1 and a portrait-origin document does not widen in landscape. Native-scroll configuration/restoration tests and actual exported-PDF pixel checks cover navigation and six combinations of layout style/authored width. Source and signed-package hashes are retained in the receipt.

**The two combined-process runs remain failed.** Both aborted in PDFKit accessibility while forming a weak reference to a PDFView during teardown of an unchanged PDF appearance-test fixture. The following PencilKit harness does not instantiate the changed Free Ink host. The appearance class passes in its own process. This supports a cross-test PDF accessibility lifetime race but does not prove production PDF dismissal unaffected; no PDF lifecycle fix is claimed here. The combined results, crash report and partition coverage audit remain recorded rather than relabeled green.

## Backup and delivery

The final fresh baseline contains **62 files / 60,108,365 bytes**. Live and stopped library snapshots agreed before installation. The backup is read-only and all 62 hashes remain exact. Before first launch, all **27 Application Support files** matched byte-for-byte. iOS renamed four SplashBoard snapshots with identical content hashes.

After launch, saved content remains exact. Strict container and Application Support comparisons remain **false**: 25/27 support files match; the library differs only in deletion-tombstone ordering (complete records remain identical as a multiset), and the performance trace changed. All other library fields are exact. Diagnostic/cache differences remain in the audit, with no comparator exclusions. The first post-launch full transfer dropped its device socket; that partial copy was not used. A new complete transfer succeeded and supplied the comparison. Final live library bytes match that checkpoint and the build-88 executable remains running.

No older backup was restored. Private charts, handwriting, device metadata, provisioning material, actual-ink previews and diagnostic artifacts stay ignored under `.build`.

## Evidence and next test

- Branch: `codex/free-ink-rotation`
- Signed app: `.build/installed-main-app-1.2.3-88/iChart.app`
- Backup and readbacks: `.build/device-backups/2026-10-29-free-ink-88/`
- Main gate: `/private/tmp/ichart-free-ink-88-editor-verified.xcresult`
- Appearance gate: `/private/tmp/ichart-free-ink-88-appearance.xcresult`
- Current library gate: `/private/tmp/ichart-free-ink-88-current-library.xcresult`
- Failed combined runs: `/private/tmp/ichart-free-ink-88-regression.xcresult`, `/private/tmp/ichart-free-ink-88-verified.xcresult`
- Coverage audit: `.build/free-ink-88-test-partition-coverage.json`
- Structured delivery receipt: `receipt.json`

Next physical test: open Becoming, rotate in both directions and confirm handwriting stays in the same place relative to the paper and notation. In Free Ink, use two fingers to pan a page that extends beyond the viewport. Screen coordinates can naturally change when scrolling; the stored paper coordinates and ink size must not.
