# iChart Fix Docket

## Active fix — November 7, 2026

**FIX-021: Incremental Automatic Write & Render cadence.** After Build 153, the
user reports earlier chords remain handwriting until the writing sequence ends,
then several render together. The saved rendering preference is Automatic.
Priority P1: the main authoring loop must make progress as the writer moves on.

Degree: completion scheduling and protected partial rendering. Preserve the
installed selection/drag/library repairs and all source ink. Earlier complete
independent chords should render at safe pen-up opportunities while later groups
continue. Do not assign a new PencilKit drawing during an active stroke, relax
current-source ownership, render over unfinished writing, split delayed suffixes,
or add a mandatory pause/review step.

Source review found a shared structural idle hold before independent chord
selection and an idle-only separate-row completion path. The incremental reader
already retains independent results; possible whole-canvas preparation starvation
requires timing evidence. These mechanisms predate 153. Existing tests inject
multiple completed glyphs in one pen episode or call rendering directly; they do
not establish sequential-writing cadence through the real editor scheduler.
New regressions will interleave real begin/change/end callbacks in both styles,
including barline/row transitions, and verify exact unfinished source and saved
results. Build 154 now passes 28 focused cases, including the previously failing
shipping-editor sequence and the mark's own future deadline in both styles.
The final broader selection has 727 passing cases and six optional capture
replays skipped across the combined run and one corrected legacy help-test
rerun. Build 154 was installed in place on November 8 with fresh matching stopped-app
backups and direct pre/postlaunch content preservation. Fresh physical cadence
acceptance remains pending. See [cadence repair evidence](automatic-render-cadence-2026-11-07.md).

## Installed selection repair — November 7, 2026

**FIX-019: Restore canvas measure selection inside tools.** In installed Build
151, Repeats cannot select a new measure; the same guard also blocks Measures
and Time Signature. Native tests reproduce this in both chart styles with
synthetic direct/Pencil touches. The cause is a guard introduced by the Build
151 chord-drag patch, not the accepted Build 149 explainer baseline: it gives
measure taps to an edit overlay even when that overlay is hidden or disabled.
Priority P1 because normal repeat/ending and measure workflows cannot finish.

Degree: a focused touch-owner correction. Suppress the ancestor measure tap only
for a live edit overlay. Preserve Select's chord movement/delete/resize ownership,
Text's overlay selection, repeat-start state and all source ink. Existing helper
instructions already promise tap-to-select and End Repeat; restore their actual
behavior rather than adding another step or modal stop. The tool-explainer chat
has been contacted for a read-only regression audit.

**FIX-020: Tool switching responsiveness.** Audit active tools and remove repeated
layout calculations on transient mode, selection or helper changes. The sizing
engine-pair diagnostic measured approximately 1.6 ms (Rhythm) and 2.4 ms (Simple)
for populated 32-measure fixtures in Simulator. This proves repeated work, not
physical iPad tap latency. Keep layout output, ink, navigation, recognition and
animations unchanged; validate cache invalidation against the full chart and
logical size. Fresh physical responsiveness acceptance remains open.

## Library repair checkpoint — November 7, 2026

**FIX-018: Consecutive chart deletions from the library.** The user reports that
the first three-dot **Delete** works, but the next chart's **Delete Chart?**
confirmation does not appear until a chart is opened and the library revisited.
Observed production version: 1.2.4 (151). Priority P2; deletion is blocked until
navigation resets the screen.

Degree: a focused library presentation change shared by all chart styles. Keep
the immutable chart IDs, existing confirmation wording, store deletion, cloud
tombstones, PDFs, setlists and saved ink unchanged. Use one identifiable alert
presenter and bind dismissal to the exact presented request. Dismiss the
confirmed request before deleting its source row. Baseline Simulator menu tests
pass, so the physical failure is not yet reproduced or closed. See
[FIX-018 validation](library-consecutive-deletion-2026-11-07.md).

## Previous fix — November 7, 2026

**FIX-017: Reliable, smooth rendered-chord dragging.** Priority P1 because a
movement attempt can reach deletion. The user reports Apple Pencil in **Select**
on a Rhythm Section Sheet; the connected iPad is running 1.2.4 (149). The relevant
gesture, targeting and placement source matches the current integration baseline.

The code exposes overlapping chord-body/delete/resize targets and inconsistent
pan admission/startup hit tests. The repair protects the chord body, retains one
touch-down target, separates tap deletion from dragging, and uses a transient
movement preview. Direct dragging in Select selects the chord and moves it in
one gesture. Chord identity, original source ink, musical timing, saved width and
existing placement rules must survive movement, cancellation and reopening.

Degree: a focused editor interaction change; no recognition or schema change.
Source repair, native regression checks, visible Simulator checks and fresh
physical Pencil acceptance are separate evidence gates. The focused native gate
passed 120 tests with no failures or skips on the installed Build 149 source
baseline. Captured previews in both layouts and the wrapped Select helper were
checked visually. Fresh physical Pencil acceptance remains pending. See
[FIX-017 validation](chord-drag-2026-11-07.md).

## Current override — November 5, 2026

The user clarified that chord-repeat symbols (`%` / dot-slash-dot) remain
supported in **Write & Render**. Only handwritten bar-and-dot measure/range
repeat ingestion is retired after the Build 143 Rhythm Section Sheet failure.
Use **Tools > Repeats** for measure repeats/ranges. Preserve saved repeat objects
and source ink, normal barlines and handwritten ending brackets. The basic
telemetry reduction remains unchanged. See the [corrected scope](../handwritten-repeat-ingestion-retirement-2026-11-05.md)
and [correction handoff](chord-repeat-scope-correction-2026-11-05.md).

The Build 136–138 results below remain historical. They do not validate the
corrected chord-repeat candidate, promise a bar-and-dot reader repair or
authorize a physical iPad action.

## Historical Build 137–138 checkpoint

Updated November 4, 2026. This is the source-controlled status summary for the
Build 136 history, installed Build 137 and pending Build 138 repeat repair.
Detailed device snapshots and handwriting archives remain local and are excluded
from this document.

### Recorded installation and acceptance

iChart 1.2.4 (137), source `71491e50`, is installed after an authorized
backup, in-place update and normal launch. Independent stopped postlaunch
readback verified all chart fields and source ink, 20 PDFs and one setlist with
15 PDF references. The library changed only in deletion-record order. All
preferences were byte-exact before launch; afterward 17 of 18 keys retained
exact values and types, the rendering preference stayed unchanged, and one
StoreKit last-checked timestamp advanced within the launch window.

The Build 136 checkpoint `6ffeb1442a04ec020a036c7da653ff2051e70363` and its
validation receipts remain historical evidence. See
[Build 136 source consolidation](build-136-consolidation.md) and the
[Build 137 forum follow-up](forum-browse-followup-137.md) for their separate
native, local-server and app-walkthrough lanes.

The user passed the Build 137 keyboard review checks in both Simple Chord Sheet
and Rhythm Section Sheet. A later physical Simple Chord Sheet check in Automatic
mode failed: written repeat barlines became chords. Two saved-source replays
fail on `71491e50` and pass with the Build 138 repair; the captured ink remains
private. The correction permits shorter bars only within complete Simple repeat
signs, while ordinary barlines and other chart styles retain their existing gates.
Nine procedural public regressions include manual/automatic commitment and a
coder round trip with prior chord sources retained. Full local native validation
passed 3,373 cases with zero failures and 119 skips (3,492 total), without private
replay code or ink in the project. Hosted CI/review results belong to the exact
then-current PR #95 head; physical repeat acceptance was still open at this
checkpoint. That ingestion acceptance lane is now retired by the November 5 decision.

At that checkpoint, the affected Write & Render helper, How To and recovery
wording were checked in Automatic and Manual contexts. The then-existing copy
described complete bars and two dots, tall ordinary barlines, and the applicable
render/review actions. The November 5 retirement supersedes that copy and removes
the repeat-writing instructions.

Issue #96 remains open: the historical missing-telemetry-event mechanism is
unidentified, and no production repair is claimed. Installation and preservation
do not establish a complete physical workflow matrix or an App Store release.

## Write & Render contract

Automatic and Manual Render with Preview must render independently placeable
supported writing without a modal stop, repeated readiness tap or compulsory
review of unrelated ink. Keep unplaced source visible, editable and saved, with
inline recovery.

Supported review text remains the user's choice while source and target match.
Preserve source ownership through partial rendering, correction, retry, rotation,
save and reopen. Preview, user edit, rendered result and saved data remain distinct.

## Fix status

| Ticket | Implemented behavior | Status or remaining evidence |
| --- | --- | --- |
| FIX-001 / RHY-001 | Recognize ordinary barlines separately from chords; commit eligible Rhythm dividers and independent notation. | Ordinary-divider preservation remains required. Only bar-and-dot measure/range repeat ingestion was retired November 5; chord-repeat symbols remain supported. Historical Build 137/138 controls do not validate the corrected candidate. Unrepresentable cuts retain ink. |
| FIX-002 | Improve supported F roots; retain E, 7 and vertical controls. | Prior device acceptance retained; bounded reader/render/reopen controls pass. |
| FIX-003 | Correct triangle/half-diminished ownership, candidate retention and same-root quality editing. | Native/portable controls pass; user reports improvement. Fresh-writing accuracy remains under observation. |
| FIX-004 / FIX-014 | Render clear fermatas/accents with attachment/float, selection, smooth drag/guide, delete/undo and Restore Ink. | Both styles implemented; prior baseline accepted. Marcato remains parked. |
| FIX-005 | Load author badges independently and show accurate profile statistics. | Local gateway and actual two-account app visibility checks pass. Awards/revokes remain operator actions; no production awards made. |
| FIX-006 | Preserve comment drafts/history; support stable earlier-page chronology and retry. | Actual two-account publication/download, vote/comment, paging, badges and return checks pass. The 137 follow-up repairs narrow cards, persistent search/focus and submitted-query return/retry state. |
| FIX-007 | Bind delayed saves by chart ID; reject duplicate identities before backup. | Persistence regressions pass. Historical incident still requires affected-chart evidence. |
| FIX-008 | Keep review input focus/scroll stable while retaining editing/render actions. | Native controls pass; the user passed Build 137 keyboard review checks in both chart styles. The later bar-and-dot ingestion retirement does not change that keyboard evidence. |
| FIX-009 | Preserve following meter-change anchors across Simple measure splits. | Both render settings and file-backed source/range checks pass. |
| FIX-010 | Export legacy Rhythm staff ink using the editor's chart-aware geometry. | Actual PDF, save/reopen and visual controls pass. |
| FIX-011 | Preserve publisher-view PDF metadata; label unsupported legacy metadata Instrument view unknown. | Both styles/views pass. Download leaves printed notes and PDF bytes unchanged. |
| FIX-012 | Derive inline split recovery from the actual blocker. | Independent progress and source/rhythm/mark preservation pass. |
| FIX-013 | Preview engraving in the chart's own style and appearance. | Native/visual controls pass; fresh physical check pending. |
| FIX-015 | Move an existing chord to beat one only in a newly formed final singleton measure. | Both styles/modes pass; requested device retest passed. Multi-chord placement retained. |
| FIX-016 | Select an eligible divider and use its red X to merge; target Rhythm's staff divider. | Model/canvas/layout/reopen/guidance controls pass; fresh physical gesture check pending. |
| FIX-017 | Drag a rendered chord directly in Select; protect its body from control overlap and keep movement separate from deletion; use a lightweight movement preview. | 120 native checks passed with no failures or skips on the Build 149 baseline; both-style previews/helper and edge controls checked. Build 151 installed with fresh backup and saved-data readback. Fresh physical Pencil acceptance pending. |
| FIX-018 | Keep successive library row-menu deletion confirmations independently identified; reject stale dismissal of a newer request. | Build 153 installed with fresh backup and strict saved-data readback; 4 actual-app library cases pass. Original 2 prepatch menu cases also passed, so physical cause/acceptance remains open. |
| FIX-019 | Allow measure taps in tools whose edit overlay is inactive; retain active overlay ownership in Select/Text. | Prepatch 3 routing cases failed; all 5 routing cases now pass. Full both-style Start Repeat/end selection/End Repeat UI passes, with exact saved endpoint readback. Combined 153 native gate: 468 pass, 2 private replay skips, 0 failures; 9 unique UI walkthroughs pass. Installed and reopened after independent preservation audit; physical acceptance pending. |
| FIX-020 | Reuse unchanged editor sizing/layout results on tool-only updates with full-chart/size invalidation. | Both-style parity, ink/timestamp invalidation, independent cache sizes and zero-publication checks pass. Repeated unchanged sizing uses one engine-pair build. Physical response still requires acceptance. |
| FIX-021 | Render completed independent chords while later ink continues, preserving active/unfinished source, structure and delayed suffix ownership. | Build 154 installed November 8 with saved-content preservation verified. Both styles: 28 focused cases pass; broader selection 727 passing and six optional skips across combined run/help-test rerun. Fresh physical cadence acceptance pending. |

## Rhythm workflow status

| Ticket | Current result |
| --- | --- |
| RHY-002 | One source-bound review row; typed edits survive returning to writing and late recognition. Cross-style/mode recovery/reopen pass. |
| RHY-003 | Recognition guess/Your edit provenance is accurate; physical review/render/reopen acceptance retained. |
| RHY-004 | Rhythm's first chord anchors to beat one; neighboring groups remain distinct. Prior device acceptance retained. |
| RHY-005 | Save failure retains rendering and the latest Retry Save state. Injected failure/reopen controls pass. |
| RHY-006 | Reopened review uses current source and applicable edits; same-source render intent continues after recognition settles. |
| RHY-007 | Ending blockers preserve ink/approvals; affected device render/reopen retest passed. |
| RHY-008 | Bar-and-dot measure/range repeat ingestion remains retired after the Build 143 Rhythm failure. The user clarified that handwritten chord-repeat symbols (%) remain supported; the corrected candidate needs its own validation. Earlier controls stay historical. Preserve the measure-based tools and saved repeat/source data. |

## Approved style boundaries

- Simple fermatas/accents attach to rendered chords or float; Rhythm also targets
  rendered notes and staff ink. Simple raw handwriting remains an unsupported target.
- Rhythm divider deletion is limited to content the merged measure can preserve.
  Timed notes, mapped slots, pair-owned ink, incompatible structure or a merge
  that could move other staff handwriting keep a boundary protected. True
  siblings of a drawn split may merge when those preservation checks pass.
- Forum PDFs preserve the publisher's view. Personal PDFs contain rendered
  content and saved Free Ink; unresolved Write & Render ink stays editable but is excluded.
- Engraving presets apply to the current chart and its PDF. Sheet appearance
  does not convert the chart's musical layout type.

## Remaining checks and parked work

1. Validate the corrected split: handwritten chord-repeat symbols (`%` /
   dot-slash-dot) work in both chart styles and render settings; bar-and-dot
   measure/range repeat ingestion stays absent. Preserve saved-repeat/source
   compatibility, ordinary barlines/endings and **Tools > Repeats**. Earlier
   broad-retirement tests do not validate this correction or establish fresh
   physical Pencil acceptance. Physical forum acceptance remains separate.
2. Confirm the latest eligible/protected Rhythm divider gestures, style previews
   and forum PDF labels on the physical iPad. Continue checking fresh major-
   seventh and genuine half-diminished writing during normal use.
3. Verify the exact corrected revision's checks before its normal publication or
   merge. Source changes are not an App Store release or an iPad installation.
   Keep #96 open until its historical mechanism and any supported repair are
   established.

Marcato/new mark inputs, Graph/MyScript, ML-core and dedicated reader-retry work
remain parked. The historical ink-integrity investigation requires affected-chart
evidence before closure; this docket makes no new saved-data-loss claim.
