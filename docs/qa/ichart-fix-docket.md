# iChart Fix Docket

## Pencil taps in text fields

**FIX-026** addresses the period inserted when a Pencil tap is intended to focus
a field. A field tap opens typing. Tap the field’s Pencil icon to start Scribble,
then write in that field. The icon becomes a keyboard button while Scribble is
active. It switches back to typing without changing the draft. A pause between
words keeps Scribble active. Switching fields or leaving the editor clears it.

The text controls use the same accessory slot and keep the native selection and
draft. Header, Text, review panels, and library forms describe the new gesture.
All 62 focused Simulator tests passed, plus the cue walkthrough in both chart
styles. The walkthrough checked mode switching, field position, and saving or
canceling the draft. The physical Pencil tap and first Scribble stroke still
need an iPad retest.

## Protect chart edits from finger and palm contact

**FIX-025** is P1 because incidental contact could move or delete a saved
object. Select now takes Apple Pencil for on-chart selection, dragging, resizing,
correction, and red X controls. A finger can scroll from the same locations.
Measures, Repeats, and Time Signature still accept finger taps to target a
measure. Text accepts finger taps on measures and on the input field, and uses
Pencil to select an existing cue on the chart. The tool helper, tour, and How To
describe the new gestures.

The iPad Simulator exercised device touch routing in both chart styles. Finger
contacts on the chord body and red X were rejected for editing and accepted for
scrolling. Pencil could start the drag and delete at the red X. Chord, converted
mark, and measure targeting suites passed. After correcting a case-sensitive
guidance assertion, that suite and the largest text layout check also passed.

Development Build 157 combined FIX-022 through FIX-025 and was reopened for
physical retesting on November 13.

## Earlier text-entry work — November 13, 2026

FIX-026 supersedes the direct-writing gesture below with a Pencil control on the field.

**FIX-024: Make first-try text entry consistent across iChart.** Priority P2.
Use the shared native controls for ordinary text input. A tap or the keyboard
icon should start typing on the first try. Writing directly in the field should
start Scribble without an intermediate keyboard or sheet expansion. Keep secure
password fields on the system password control. Verify editor entry in both
chart styles, and check library, setlist, forum, and account flows at their
normal entry points. Keep search, draft, and submission behavior intact.

The implementation covers chart cues, library and setlist search, chart and
project names, PDF import, forum search/publishing/comments, account identity,
and Personal Handwriting text. The cue panel stays at the top while typing and
accepts finger or Pencil for Add, Apply, and Cancel. The Text helper, guided
tour, and How To explain tap-to-type and direct Pencil entry.

The focused iPad Air Simulator run passed 71 tests with no skips. This includes
landscape review input in both chart styles, forum search focus through refresh
and retry, publish sheet controls, and draft-only setlist/PDF name changes.
The actual-app cue walkthrough also passed in both styles. The first tap
typed with the panel in place, Cancel discarded its draft, and Edit reopened
the cue saved through Add.
Physical Apple Pencil acceptance of the follow-up is pending.

## Header and Review Chords — November 13, 2026

**FIX-023: Keep text entry steady on first focus.** The Header prompt opened with
a compact and a large presentation size. UIKit could expand it during text entry,
and repeated input-mode requests could update the native keyboard or selection
after a field already had focus. Header now opens at a single large size. Review
Chords keeps its Done control in the same toolbar position throughout editing.
The shared input bridge keeps Scribble available and avoids redundant input-hint
and selection updates. Header instructions describe direct Pencil writing and
one-tap keyboard access.

All 27 selected iPad Simulator tests passed, including Header focus and draft
preservation, repeated keyboard requests, Scribble admission, and software
keyboard reachability in landscape for both chart styles. The user confirmed on
Build 156 that Header stays in place and Scribble works. Fresh physical Review
Chords and keyboard-to-Pencil switching checks remain open.

Development Build 156 combined FIX-022 and FIX-023 and was reopened for
physical retesting on November 13.

## Rhythm system fit — November 12, 2026

**FIX-022: Fit a lone Rhythm measure into the preceding system.** An eight-measure
Rhythm setup at a 932-point canvas width produced rows of 4, 3, and 1. The initial
packing pass reserved extra width for the last open measure, although its rendered
width fit on the second row. After resolving widths, the layout can append a lone
measure to the preceding system when the full width fits within the paper margins.
Explicit row, key-change, and page breaks set boundaries for this automatic move.
Changing the chart key or instrument view keeps the same measure rows while the
rendered measure widths adapt to the key-signature gutter.
Shortening the preceding row with its terminal resize handle applies the same fit
check on release. Staff ink follows a verified singleton row join or its reverse
at the same paper width through display projection of its original archive. The
Measures helper and How To describe the gesture and the fit condition.

Verification covered 142 layout, split, and divider checks on macOS and 421 passing
iPad Simulator cases across the native run and the hosted guidance rerun. Three
optional device-capture replays were skipped. The five hosted guidance cases passed
after enabling accessibility on the test simulator. The captured Rhythm Measures
screen shows the resize helper, both handles, and the action controls. Physical
iPad acceptance is pending.

## Automatic cadence repair — November 7, 2026

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
| FIX-022 | Join an automatic single-measure Rhythm row to the preceding row when its rendered width fits. | Verified eight-measure reopen, actual resize commits, exact width threshold, explicit breaks, staff ink in both directions, and visible guidance. 142 macOS checks and 421 Simulator cases passed across runs, with three optional skips. Physical iPad acceptance pending. |
| FIX-023 | Stabilize Header and Review Chords text entry while keeping native Scribble. | 27 Simulator tests passed. On Build 156 the user confirmed stable Header and working Scribble. Physical Review Chords and keyboard-to-Pencil switching checks remain open. |
| FIX-024 | Apply first-try typing and Scribble to the rest of the app’s ordinary text inputs. | Implemented locally. 71 focused Simulator checks passed. Physical iPad retest pending. Password fields retain native secure entry. |
| FIX-025 | Use Apple Pencil for on-chart edits and finger gestures for navigation. | 53 distinct focused Simulator tests passed across two runs. Build 157 installed. Physical finger, palm, and Pencil retest pending in both styles. |
| FIX-026 | Reserve ordinary Pencil taps for typing and make Scribble a field action. | 62 focused Simulator tests and the cue walkthrough in both styles passed. Physical iPad retest pending. |

## Rhythm workflow status

| Ticket | Current result |
| --- | --- |
| RHY-002 | One source-bound review row; typed edits survive returning to writing and late recognition. Cross-style/mode recovery/reopen pass. |
| RHY-003 | Recognition guess/Your edit provenance is accurate; physical review/render/reopen acceptance retained. |
| RHY-004 | Rhythm's first chord anchors to beat one; neighboring groups remain distinct. Prior device acceptance retained. |
| RHY-005 | Save failure retains rendering and the latest Retry Save state. Injected failure/reopen controls pass. |
| RHY-006 | Reopened review uses current source and applicable edits; same-source render intent continues after recognition settles. |
| RHY-007 | Ending blockers preserve ink/approvals; affected device render/reopen retest passed. |
| RHY-008 | Handwritten chord-repeat symbols (%) remain supported. Bar-and-dot measure/range repeat ingestion stays retired. The November 13 Simulator replay passed in both styles and render modes, including source preservation and reopen. Fresh physical Pencil acceptance remains open. |

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

Retest FIX-026 first. In Header and Review Chords, use Apple Pencil to tap a
field and check that the keyboard opens with the draft intact. Use the Pencil
icon to start Scribble, write a word, pause, and write another word. Switch
back to typing and check both words are present. Repeat in a multiline cue.

1. Retest FIX-025 with a finger or resting palm over a selected chord and its red
   X. Check that a finger scrolls and Apple Pencil still moves and deletes the
   chord in both chart styles.
2. Retest FIX-024 ordinary text input on the physical iPad, including
   Text and Review in both chart styles and representative library, forum, and
   account fields.
3. Confirm FIX-022 on the installed Build 156 Rhythm chart. Reopen the eight-measure
   chart and verify the lone measure moves up only when its full width fits.
4. Retest handwritten chord-repeat symbols (`%` / dot-slash-dot) with Apple
   Pencil in both chart styles and render settings. The November 13 replay
   verified the corrected scope, source ink, and save/reopen. Also check ordinary
   barlines, endings, and measure/range repeats via **Tools > Repeats**.
5. Confirm the latest eligible/protected Rhythm divider gestures, style previews
   and forum PDF labels on the physical iPad. Continue checking fresh major-
   seventh and genuine half-diminished writing during normal use.
6. Verify the exact corrected revision's checks before its normal publication or
   merge. Source changes are not an App Store release or an iPad installation.
   Keep #96 open until its historical mechanism and any supported repair are
   established.

Marcato/new mark inputs, Graph/MyScript, ML-core and dedicated reader-retry work
remain parked. The historical ink-integrity investigation requires affected-chart
evidence before closure; this docket makes no new saved-data-loss claim.
