# Tool selection recovery and responsiveness — FIX-019 / FIX-020

Reported November 7, 2026 on installed iChart 1.2.4 (151). Rhythm Repeats could
start a repeat but could not select an end measure. The user also reported that
no measure could be selected inside Repeats and that tool switching felt slow
and buggy. The earlier consecutive library deletion report remains FIX-018 and
is retained in the combined candidate.

## Confirmed selection cause

The new Build 151 chord-drag patch rejected the ancestor canvas selection tap
whenever a logical editable target existed. Measure targets remain registered
inside Measures, Repeats and Time Signature, but those modes hide and disable
the transparent object-edit overlay. The ancestor recognizer therefore gave
their taps to an unavailable owner. This regression is absent from accepted
Build 149 source `d8774fa7`; it is not attributed to the tool-explainer baseline.

The repair suppresses the canvas selection tap only when the object overlay is
visible, interactive and has an enabled tap recognizer. It preserves the active
overlay's ownership in Select and Text, including chord body dragging, explicit
delete/width controls, cues and double taps. Pending repeat/ending/delete state,
measure IDs, models and saving rules are unchanged.

The prepatch native run executed seven cases: two layout diagnostics and five
gesture-routing cases. Three routing cases failed with 59 assertions; Browse
and Text controls passed. The failures reproduce measure-tool admission,
reentry and stale inactive-overlay ownership using real UIKit recognizers and
synthetic finger/Pencil touch objects. They are distinct from fresh physical
Pencil timing or actual-app Start Repeat/End Repeat acceptance.

## Scope audit and guidance

The user authorized coordination with **Improve tool explainers and workflow**.
That chat completed a read-only source/history review, agreeing on the new 151
guard and identifying the missing actual touch workflow coverage. Its review
note is retained locally under `.build/workflow-source-review-20261107/review.md`.
It made no app edits, builds, device actions or deployment in this investigation.

| Tool/path | Intended canvas ownership and verification target |
| --- | --- |
| Measures and measure-delete range | Canvas tap selects a new measure; pending range survives retargeting and Cancel releases it. |
| Repeats and ending ranges | Canvas tap changes the current end while preserving the start and active tool. End Repeat completes the range. |
| Time Signature | Canvas tap selects the measure and opens meter choices; cancelling either stage permits a new target. |
| Text | Active object overlay owns cue/measure taps; Guide and cue-panel dismissal must release suspension. |
| Select | Active overlay retains chord/cue/measure ownership and all Build 151 drag/delete protections. |
| Free Ink, Write & Render, Header | Writing intentionally owns input. The normal tool strip remains available; measure selection is not enabled while writing. |
| Form Markers | The visible sheet suspends the canvas intentionally and has its own measure picker. Add/Cancel dismiss normally. |

The Measures/Repeats/Time Signature helpers and How To already describe tapping
a measure and choosing the endpoint. Their controls and recovery text were
checked; this patch restores that promised behavior without adding a step or
modal prompt. Source inspection found no other deterministic persistent panel
lockout in the reviewed Guide, Layout, Form Markers, Text, meter and ending
dismissal paths. This is a bounded audit, not proof that every timing-dependent
input failure is impossible.

## Bounded performance repair

Editor body updates independently recomputed the system count and estimated
canvas height. Selected-measure helper queries also repeatedly built page layout
for the same document. The actual-engine diagnostic with synthetic populated
32-measure fixtures measured median sizing-pair costs of about 1.6 ms in Rhythm
and 2.4 ms in Simple on Simulator. These measurements establish redundant work;
they do not establish the physical iPad's tap delay or a single complete cause.

`EditorCanvasGeometryCache` is retained by each editor and keeps one height entry
and one page-layout entry. They have separate sizes and compare the complete
Chart and CGSize. Tool, selection and helper-only changes reuse geometry. Direct
musical, width, appearance, coordinate-space and ink edits invalidate the entry
even when `updatedAt` is unchanged. The cache preserves the existing engine
calls and height math, emits no publisher updates, and does not serialize, hash,
decode, normalize or modify source archives to build its key. Layout algorithms,
ink handoff, viewport animation, recognition and persistence remain unchanged.

A larger chord draft can still require synchronous scope handoff when returning
to Write & Render. Existing serialization/residency behavior makes its cost
input-dependent. That remains a profiling lead; no additional production change
or expanded telemetry was introduced for it.

## Candidate validation boundary

The combined candidate is Build 153. Native tests cover the repaired admission
path, actual selection actions, cache geometry parity/invalidation, ink archive
preservation and the prior chord-drag protections. External-process UI cases
exercise normal menus and actual canvas coordinate taps in both chart styles,
including repeat completion and panel cancellation. They must verify visible
measure context, rather than merely assign selection or inspect capability
flags. The repeat walkthrough leaves both synthetic fixture charts saved for
independent normal-repository readback.

Build/test results, signed artifact and any iPad installation are separate gates.
Build 152 was a signed library-only checkpoint and was not installed. Fresh
saved-work confirmation, stopped backup, in-place installation and saved-content
readback remain required before a device handoff. Physical repeated-delete,
repeat selection, chord dragging and perceived tool responsiveness remain user
acceptance checks after that installation.

## Verified Build 153 checkpoint

- Native: 468 passed, zero failures, two opt-in private saved-ink replays skipped
  because no private fixture environment was supplied. This includes the five
  formerly failing/control routing cases, full interaction policy, viewport and
  ink navigation, cache parity/invalidation, retained chord-drag guards, library
  and PDF persistence.
- Actual Simulator UI: nine distinct walkthroughs passed across the final
  selected runs. These cover both-style repeat start/end, Measures range Cancel,
  both stages of meter dismissal/retargeting, Text Guide/cue dismissal,
  cold Write & Render entry/reentry in both modes, Form Markers, and the four
  consecutive/bulk/cancel library cases.
- The first meter recovery test assumed a visible Cancel button. Regular-width
  iPad presents meter choices as a popover and hides that role button. The test
  was corrected to use real tap-outside dismissal; the rerun passed in both
  styles without another app-source change.
- Independent normal Simulator repository readback after repeat completion and
  termination found exactly the UI-selected spans: Simple measures 1–4 and
  Rhythm measures 1–2. Both endpoint measures retain their object attachment.
  This is saved-state evidence, not a normal app-reopen or physical-Pencil claim.
- Captured Text and completed Rhythm Repeat screens were inspected: the helper,
  context, tool controls and selected-measure highlight are visible and agree.
- The repeated sizing diagnostic uses one engine-pair build for all repeated
  unchanged lookups in each fixture. Timing remains Simulator-only.
- Device compilation/linking completed. Xcode CodeSign rejected generated
  Finder metadata; a clean generated app copy was signed and strictly verified
  with the original generated entitlements. Bundle 1.2.4 (153), unchanged 151
  entitlements, target-device eligibility and an unexpired profile were checked.

The signed archive, complete recoverable source patch, source-file hashes,
native/UI summaries and `validation-receipt.json` are retained locally under
`.build/tool-routing-153-20261107/`. Build 153 has not yet been installed at this
checkpoint; the current physical build was read back as 151. The unrelated
pre-existing help/source assertion debt from the earlier broader library run is
documented in the FIX-018 note and remains separate from these passing gates.

## Physical iPad installation

Build 153 was installed after the user explicitly confirmed all current work,
including review/correction text, was saved. Only the freshly identified
production app was stopped. Two complete current backups match exactly across
70 files / 63,813,710 bytes. The update was installed in place; no uninstall or
library restore occurred.

Prelaunch saved data matched exactly, apart from platform SplashBoard replacement.
After a normal startup, the app was stopped for two further independent copies,
which match across 70 files / 65,041,720 bytes. The strict saved-content comparison
and independent audit passed for all 18 charts, 366 source-ink archives, 12 page
notation archives, one header archive, 22 PDFs, one setlist with 15 references,
three correction/profile files and 83 deletion records. Preferences are retained
apart from one bounded StoreKit clock. The retired diagnostic checkpoint remains
byte-exact with its existing stale binding, recorded separately.

The only library-value change is missing UI selection becoming the first
unchanged saved chart, matching the unchanged startup sanitizer. Subscription
verification metadata is unchanged. Fresh hash-bound technical queue rotation
and WAL-backed URL-cache bookkeeping were classified separately; cache row
payloads were not inspected and no backend/delivery health claim is made. The
existing technical performance trace is unchanged. Snapshots were not rewritten.

The independent audit passed before final handoff. A second normal launch with
no injected app arguments left iChart 1.2.4 (153) running as PID 12215. Evidence is
in `.build/tool-routing-153-20261107/install153/installation-receipt.json` and
`independent-preservation-audit.json`. Physical repeated-deletion, repeat
selection, Pencil dragging and perceived tool responsiveness remain the user's
fresh acceptance checks; installation and saved-content preservation do not
substitute for them.
