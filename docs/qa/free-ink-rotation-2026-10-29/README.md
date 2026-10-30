# Free Ink rotation — October 29, 2026

The user reported that handwriting written in landscape crumples together in portrait, and writing started in portrait spreads apart in landscape. The connected main app was verified as `com.ichart.app` version 1.2.3 build 86. This isolated branch starts at the delivered build-86 source, `45b8e4b2`; the older, dirty notation-readability checkout remains intact.

## Cause and change

The page ink policy mapped each pen stroke's center independently into the resized page or musical anchor, while retaining that stroke's size. Consequently, spacing between strokes changed even when each individual pen mark retained its shape. One-stroke rotation coverage did not detect this.

Free Ink now groups strokes into handwritten line bands and chooses a common musical-anchor or page-local transform for the entire line. Word whitespace is retained in both initial orientations. A line wider than the narrower paper is scaled uniformly, with its horizontal position bounded to the paper. It is never squeezed on one axis independently.

The active page canvas retains the source drawing and coordinate space through geometry-only updates, including stale same-chart model echoes while dirty. Both synchronous and idle persistence save that source, so fitting in portrait does not permanently shrink a landscape original. Loading saved ink also retains its original source and, where already normalized, its exact archive bytes. Actual drawing/erase edits establish the current edited geometry as the new source; deleted ink must not return from an older rotation baseline.

Grouping uses a sorted vertical-interval sweep, with a small margin for detached dots/accents. Independent notes on the same writing line deliberately share a transform to preserve their whitespace. Separate vertical lines keep independent anchoring; a tall connecting stroke can join multiple lines. No semantic handwriting recognition is involved.

## Verification

- Original build-86 policy: the initial six regression methods produced **5 failed / 1 passed**, including up to 85 points of relative stroke displacement in a short invented phrase.
- Final editor gate: **713 passed / 13 skipped / 0 failed**, 726 total, across the previous editor gate plus the new Free Ink and dirty-rotation classes. The 13 skips require optional saved-source/device fixtures; no fresh personal-library replay is claimed.
- All **10 new synthetic Free Ink methods passed**: both initial orientations, large word gaps, neighboring musical anchors, repeated rotation, dirty live drawing, stale model echoes, all three V1 chart styles, uniform fit, save/reopen, edits after fitting, and passive-vector/shared-PDF-renderer agreement.
- After the user approved backup and installation, a fresh current-library gate passed **4/4, no skips**. It round-tripped the current 17-chart library, PDF/setlist data, and replayed the affected chart's original ink through portrait save/reopen and repeated orientation/tool changes. The affected-chart replay is an eleventh optional source-backed method. Its original archive/coordinate space and exact return geometry passed; the read-only fixture remained unchanged. Private ink-only previews stay ignored under `.build` and were visually inspected.
- Control-point positions and transformed pen dimensions are checked directly. Stateless reprojection allows at most one point of whole-line placement quantization from PencilKit's rounded bounds; live canonical-source restoration remains within 0.01 points.
- Synthetic before/after ink attachments were visually inspected. They contain invented marks only.
- `xcodegen generate`, `git diff --check`, and Swift syntax parsing passed.
- Signed main app **1.2.3 (87)** compiled successfully and passed `codesign --verify --deep --strict` and bundle/version readback.

## Scope and delivery state

The implementation changes are confined to page-ink grouping, the shared page-ink transform policy, page-only canvas source/persistence handling, and the build-number/test expectations. Existing generic chord/header/rhythm reprojection remains unchanged. Graph/MyScript projects, recognition providers/models, backend code, persisted Chart schema, and library migrations are unchanged.

**Main iChart 1.2.3 (87) is installed in place and verified running on the connected iPad.** The user explicitly approved a fresh local backup, installation, and saved-content verification. The initial automatic-approval rejection of a broad data copy was resolved by that authorization. No prior backup was restored.

The new immutable baseline contains **62 files / 62,772,492 bytes**, including **17 charts, 19 PDFs, one 15-entry setlist**, and three profile/correction/evaluation files. The live library and the subsequent stopped snapshot were exact before installation. All 62 baseline hashes remain unchanged.

Before first launch, all **27 Application Support files** matched byte-for-byte. iOS renamed four SplashBoard snapshot-cache files; their content hashes matched as a multiset. After launch, every chart object and its order, ink archives and coordinates, all PDF documents/manifests, setlist data, and three profile/correction/evaluation files remained exact. All **53 other `com.ichart.*` app metadata records** remained exact. The final live library matched the audited post-launch checkpoint, and the new main-app executable remained running.

Strict full-container and post-launch Application Support comparisons remain false because startup changed bookkeeping/diagnostics and iOS caches. These differences are recorded separately in the ignored backup evidence rather than excluded from the comparator. Physical user acceptance of the rotation feel remains pending. No push, PR, merge, or publication has been performed.

The full library has exactly two startup metadata differences: `selectedChartID` is now explicit and points to the first existing chart (the unchanged startup fallback), and `entitlements.subscription.lastVerifiedAt` changed to an approximately 9.4-days-earlier value. The latter's cached/remote source was not traced; every other subscription/plan/status/access field is exact. All other library fields, including projects, cloud metadata and deletion tombstones, are exact. The performance trace retains its original prefix plus 788 bytes/five startup events. The new queue contains six events: two `cloud.push_started`, two `cloud.push_failed`, one `auth.state_changed` and one `subscription.entitlement_changed`. This ink fix does not establish the cause of those cloud events or validate cloud synchronization. The strict results remain false; content preservation is reported by the separately verified categories above.

## Local evidence

- Branch: `codex/free-ink-rotation`
- Final test bundle: `/private/tmp/ichart-free-ink-87-final.xcresult`
- Current-library test bundle: `/private/tmp/ichart-free-ink-87-current-library.xcresult`
- Signed package: `.build/installed-main-app-1.2.3-87/iChart.app`
- Immutable backup and install/readback audits: `.build/device-backups/2026-10-29-free-ink-87/`
- Logs, summaries, exact gate arguments, and synthetic previews: `.build/`
- Source hashes and test/build receipt: `receipt.json` beside this document.
