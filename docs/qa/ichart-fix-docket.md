# iChart Fix Docket

Updated November 4, 2026. This is the source-controlled status summary for the
Build 136 history, installed Build 137 and pending Build 138 repeat repair.
Detailed device snapshots and handwriting archives remain local and are excluded
from this document.

## Current checkpoint

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
current PR #95 head; fresh physical repeat acceptance remains open.

The affected Write & Render helper, How To and recovery wording were checked in
Automatic and Manual contexts. Existing copy already describes complete bars and
two dots, tall ordinary barlines and the applicable render/review actions; no
instruction or control change is needed.

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
| FIX-001 / RHY-001 | Recognize barlines separately from chords; commit eligible Rhythm dividers and independent notation. | Prior native controls pass; the Build 137 physical Simple/Automatic repeat check failed. Build 138 local native validation passes; exact-head hosted CI/review is tracked in PR #95 and physical repeat acceptance is pending. Unrepresentable cuts retain ink. |
| FIX-002 | Improve supported F roots; retain E, 7 and vertical controls. | Prior device acceptance retained; bounded reader/render/reopen controls pass. |
| FIX-003 | Correct triangle/half-diminished ownership, candidate retention and same-root quality editing. | Native/portable controls pass; user reports improvement. Fresh-writing accuracy remains under observation. |
| FIX-004 / FIX-014 | Render clear fermatas/accents with attachment/float, selection, smooth drag/guide, delete/undo and Restore Ink. | Both styles implemented; prior baseline accepted. Marcato remains parked. |
| FIX-005 | Load author badges independently and show accurate profile statistics. | Local gateway and actual two-account app visibility checks pass. Awards/revokes remain operator actions; no production awards made. |
| FIX-006 | Preserve comment drafts/history; support stable earlier-page chronology and retry. | Actual two-account publication/download, vote/comment, paging, badges and return checks pass. The 137 follow-up repairs narrow cards, persistent search/focus and submitted-query return/retry state. |
| FIX-007 | Bind delayed saves by chart ID; reject duplicate identities before backup. | Persistence regressions pass. Historical incident still requires affected-chart evidence. |
| FIX-008 | Keep review input focus/scroll stable while retaining editing/render actions. | Native controls pass; the user passed Build 137 keyboard review checks in both chart styles. Repeat recognition and broader rendering acceptance remain separate. |
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
| RHY-008 | Historical repeat acceptance remains prior evidence. Build 137 Simple/Automatic repeat writing failed and two replay controls reproduce it. Build 138 local native validation passes; exact-head hosted CI/review is tracked in PR #95 and physical repeat acceptance is pending. |

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

1. Validate the Build 138 repeat-repair candidate with PR #95. Require native
   controls, hosted CI/review and a fresh Simple/Automatic physical repeat check
   before closing the Build 137 failure. The earlier local forum walkthrough and
   fixture cleanup are complete; physical forum acceptance remains separate.
2. Confirm the latest eligible/protected Rhythm divider gestures, style previews
   and forum PDF labels on the physical iPad. Continue checking fresh major-
   seventh and genuine half-diminished writing during normal use.
3. Verify the exact Build 138 PR head's hosted CI/review before promoting the
   consolidation to `main`. Source consolidation is not an App Store release.
   Keep #96 open until its historical mechanism and any supported repair are
   established.

Marcato/new mark inputs, Graph/MyScript, ML-core and dedicated reader-retry work
remain parked. The historical ink-integrity investigation requires affected-chart
evidence before closure; this docket makes no new saved-data-loss claim.
