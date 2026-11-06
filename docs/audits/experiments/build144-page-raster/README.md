# Deferred Build 144 per-paper saved-ink raster experiment

Status: deferred on 2026-11-05. Production `LeadSheetSavedInkRenderer.swift` is restored exactly to merged baseline `00f7901538074670251cd6626c1efa88a3bd1aec`; PDF export again uses the full-document saved-ink raster and the existing external paper clip. No coordinate, source-ink, saved-archive, or tool behavior change ships from this experiment.

The proposed change rasterized each requested paper's intersection with the complete saved Free Ink writing frame. Projection still used the complete saved document's source and target coordinate spaces; cache keys included each crop's bounds and origin. This bounded the synthetic raster's dimensions to the requested paper. It did not establish a measured runtime speedup, eliminate repeated full-drawing projection on cache misses, or establish a device memory guarantee. The existing full-document raster allocation concern remains open.

## Exact pixel validation

Root ran the native Simulator suite using the accessibility wrapper, followed by a focused diagnostic run. Diagnostics are in `/private/tmp/ichart-build144-app-db-audit-20261105/native-pixel-diagnostics.log` and its adjacent `native-pixel-diagnostics.xcresult` (local validation artifacts; not committed). The focused run executed 63 tests with 24 failures, all from the two experimental full-document-versus-paper-crop pixel tests. The archived raster class executed five tests with 24 failures.

The comparator independently converted both opaque paper images to standard sRGB, 8-bit, premultiplied RGBA and required every channel to match exactly. It retained exact image size, scale, orientation, pixel dimensions, paper-frame intersections, and source/archive checks. Failures include differing-pixel/channel counts, maximum absolute channel delta, a raw-RGBA pixel bounding box, the first eight pixel samples, and expected/actual/red-mask synthetic image attachments.

- At 1x, affected cases differed at two to six pixels out of 919,360 per paper. Maximum channel delta was 24/255 (Rhythm Section Sheet, balanced engraving, paper 1: six pixels, bounds [80,488] through [97,506]); some expected pale stroke-edge pixels became white.
- At 2x, affected cases differed at five pixels out of 3,677,440, maximum channel delta 1/255, bounds [346,2058] through [351,2063].
- At 3x, affected cases differed at four pixels out of 8,274,240, maximum channel delta 1/255, bounds [273,1593] through [276,1595].
- Retina deltas repeated identically after JSON save/reopen and with coordinate-less legacy fallback in both chart styles. Source ink bytes and the saved coordinate-space value were unchanged.
- The uncached full-document repeat control passed in both chart styles at 1x, 2x, and 3x. The cache was reset between independent old-path rasterizations, and the test required distinct image instances.
- The observed differences are true pixels, not merely PNG container differences. The fixture's crop bounds are already integer-aligned at the tested scales; observed mismatches include interior pixels. Neither a pixel-grid rounding fix nor an edge halo is demonstrated by this evidence. No tolerance was accepted.

The renderer optimization is deferred to preserve baseline pixels. The meter-predecessor context, sparse saved-rhythmic-ink index, and unique per-export PDF directory fixes remain independent active changes.

## Recoverable artifacts and resumption

`page-raster-experiment.patch` preserves the renderer change relative to the merged baseline, the one PDF call-site crop argument, and the complete experimental test file. `SavedInkPageRasterizationTests.swift.txt` is an exact noncompiled copy of the diagnostic test source (SHA-256 `2736604d9e7aeae5bf2ddc55369dd263d342441f65d462ad4f6f04c2f191c87b`). The patch is archival and is not part of the app or test targets.

Revisit on an isolated branch and review the patch before applying it. Regenerate the Xcode project if restoring the experimental test. Preserve the exact old-path pixel control, source/archive assertions, both chart styles, coordinate-less legacy data, multiple engraving presets, and boundary-crossing strokes. First isolate the remaining PencilKit rasterization/recolor/composition difference. A replacement needs an evidenced rendering correction before it is eligible for the shipped build; changing tolerances does not resolve the current failure.
