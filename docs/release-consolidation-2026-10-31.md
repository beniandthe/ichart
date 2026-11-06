# Regular iChart consolidation — 1.2.4 (103)

**Historical build record.** Handwritten repeat ingestion described below was
[retired on November 5, 2026](handwritten-repeat-ingestion-retirement-2026-11-05.md).
It is not a current product promise. Measure-based **Tools > Repeats**, existing
saved repeat notation, and ending editing remain supported.

This candidate brings the regular app work into a single source tree based on
main. It preserves the existing chart, source-ink, PDF-library and setlist storage
contracts. Device backups and private test captures remain local.

## Included product work

| Area | Combined behavior |
| --- | --- |
| Chord recognition | Automatic rendering is the default. The optional manual render/preview workflow lives in settings. Completed targets render incrementally, protect active handwriting, preserve row width, and retain source ink for double-tap correction. Existing native/Vision fallback readers supply editable supported candidates. |
| Handwritten structure | Automatic measures, repeat signs and handwritten ending brackets use a structural grace interval. Splits preserve previously rendered chord positions and ending/repeat ranges. Ending labels and ranges remain editable. |
| Repeat endings | Custom labels and open/closed ends coexist with selectable, measure-snapped Move and Lengthen controls. Drag previews commit on lift and reject stale chart/layout state. |
| Free Ink and navigation | Fixed paper coordinates, rotation persistence and deferred raster refresh coexist with one-finger page scrolling, Pencil margin scrolling, and two-finger pan/zoom. |
| Review and correction | Corrections retain the source reference and location. Text fields remain scrollable above the software keyboard. Rendered chords expose the ordinary double-tap editing path. |
| PDF library and offline setlists | Personal PDFs import without rewriting their bytes and can join offline setlists. Existing PDF identifiers, native metadata and setlist references survive a forward upgrade. Verified restored sessions tolerate typed offline profile-fetch failures; authorization and decoding errors stay strict. |
| Notation and access | Previously merged notation readability, repeat-sign rendering, flexible endings, Free Pro/beta access and Forum publication behavior are retained. |
| Typed chords | Unicode sharp and flat aliases are accepted at text entry, including slash basses; canonical storage grammar remains unchanged. |
| Diagnostics | Feature-contract, automatic-render, authoring-handler and live-canvas checks share the current consent/withdrawal boundary. Backend detector source and already-deployed migrations are included. Consolidation itself does not deploy the backend or resolve incidents. |

## Integration boundaries

The feature donors were the current automatic-render source checkpoint,
`codex/pdf-import-setlists`, and the later direct-ending controls from
`codex/write-render-repeat-endings`. Existing squash merges were compared by
content rather than treated as missing solely because their old commits were
not ancestors of main. Host/editor changes were integrated selectively to retain
the current automatic-render and ink-preservation code.

Graph, MyScript, isolated study capture/publication scaffolding, personal learning,
training, model artifacts and frozen recognition experiments remain parked in
their existing worktrees and refs. No new research candidate is promoted or
embedded in this build. The shared Vision reader gains cancellation/source-current APIs for the regular app fallback. Other research source already on main is unchanged.
The paper-scan/Pro Scan document is preserved as a plan, not delivered product
functionality.

PDF import is a forward upgrade. After importing a personal PDF, an older binary
that cannot decode `personalImport` is not a supported rollback. Any replacement
build must retain the compatible decoder and local reader.

## Validation

Local validation passed:

- Full SwiftPM: 1,810 passed, 0 failed, 91 skipped (1,901 total).
- Entire native app suite: 3,071 passed, 0 failed, 114 skips (3,185 total).
  Execution on the configured iPad A16 simulator and the integration regression
  classes was verified from the result bundle.
- Backend/workflow contracts: 778 passed, 0 failed, 0 skipped, including the
  updated 24 wrapper, seven selector and four workflow-scope checks.
- The 59 focused consent regressions are included in the native total.

CI selects the real A16 fixture used by the keyboard/viewport tests. Its wrapper
ensures a real software keyboard and restores the original host keyboard and
simulator accessibility preferences, including absence and integer/boolean
values, on success, failure and cancellation. Keyboard telemetry tests use real
first-responder/keyboard transitions and await queue cleanup before removing
fixtures. Review-action tests wait for stable layout and presentation geometry
before initiating their separate scroll, so visibility during focus motion does
not count as a settled viewport.

An intermittent first-event capture in the hosted keyboard telemetry check remains
under investigation. The check retains its original event deadline and
consent/action assertions. Bounded state traces now distinguish probe
invalidation from completed observation with missing delivery. No product cause
has been established from the available evidence.

Fresh hosted validation is recorded with the consolidation pull request. Private device receipts retain complete before/after inventories;
raw chart/ink data, physical-device identifiers and local operator configuration
are intentionally absent from this publication. Automated checks establish their
tested contracts; physical recognition timing and interaction acceptance remain
separate user observations.
