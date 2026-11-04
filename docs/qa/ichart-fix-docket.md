# iChart Fix Docket

Updated November 4, 2026. This is the source-controlled status summary for the
Build 136 consolidation. Detailed device snapshots and handwriting archives
remain local and are excluded from this document.

## Current checkpoint

iChart 1.2.4 (136) is installed from checkpoint
`6ffeb1442a04ec020a036c7da653ff2051e70363`. An authorized backup and independent
postlaunch reads verified saved-state and preference preservation, with no QA
launch overrides. The user reports improved recognition; a complete physical
style/mode matrix was not specified.

The cumulative installed-source native selection has 1,526 final passing cases
and no remaining failures; seven optional replay methods were explicitly
excluded. Portable recognition has 256 passes and two optional skips. Local
forum verification has 25 actual HTTP gateway cases, 170 database-policy
assertions and 56 Edge unit tests passing. Integration adds a default build-number
update and 34 passing project-configuration tests. See
[Build 136 source consolidation](build-136-consolidation.md) for the distinct
evidence lanes. Hosted backend contracts and Dependency Review passed at the
Build 136 PR head; iOS, SwiftPM and CodeQL were cancelled before execution due
to runner acquisition. The hosted gate and promotion to `main` remain pending.

The actual local forum app walkthrough is complete. It reproduced browsing
defects and verified the local [Build 137 forum follow-up](forum-browse-followup-137.md):
50 focused native checks and all three real-app walkthrough methods pass.
Build 136 remains installed; the follow-up awaits publication and device acceptance.

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
| FIX-001 / RHY-001 | Recognize barlines separately from chords; commit eligible Rhythm dividers and independent notation. | Both styles/modes pass. Unrepresentable cuts retain ink. |
| FIX-002 | Improve supported F roots; retain E, 7 and vertical controls. | Prior device acceptance retained; bounded reader/render/reopen controls pass. |
| FIX-003 | Correct triangle/half-diminished ownership, candidate retention and same-root quality editing. | Native/portable controls pass; user reports improvement. Fresh-writing accuracy remains under observation. |
| FIX-004 / FIX-014 | Render clear fermatas/accents with attachment/float, selection, smooth drag/guide, delete/undo and Restore Ink. | Both styles implemented; prior baseline accepted. Marcato remains parked. |
| FIX-005 | Load author badges independently and show accurate profile statistics. | Local gateway and actual two-account app visibility checks pass. Awards/revokes remain operator actions; no production awards made. |
| FIX-006 | Preserve comment drafts/history; support stable earlier-page chronology and retry. | Actual two-account publication/download, vote/comment, paging, badges and return checks pass. The local 137 follow-up repairs narrow cards, persistent search/focus and submitted-query return/retry state. |
| FIX-007 | Bind delayed saves by chart ID; reject duplicate identities before backup. | Persistence regressions pass. Historical incident still requires affected-chart evidence. |
| FIX-008 | Keep review input focus/scroll stable while retaining editing/render actions. | Regression-tested and previously accepted on device; software-keyboard evidence remains separate. |
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
| RHY-008 | Boundary repeats preserve independent progress; original device acceptance and current controls retained. |

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

1. Review and publish the local Build 137 forum follow-up if approved. The actual
   local app walkthrough is complete, including both-style publication/download,
   two-account participation and saved-server readback. Its disposable fixture
   was removed. No physical device update has been performed for that candidate.
2. Confirm the latest eligible/protected Rhythm divider gestures, style previews
   and forum PDF labels on the physical iPad. Continue checking fresh major-
   seventh and genuine half-diminished writing during normal use.
3. Complete hosted CI and review before promoting the consolidation to `main`.
   Source consolidation is not an App Store release.

Marcato/new mark inputs, Graph/MyScript, ML-core and dedicated reader-retry work
remain parked. The historical ink-integrity investigation requires affected-chart
evidence before closure; this docket makes no new saved-data-loss claim.
