# iChart Fix Docket

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
