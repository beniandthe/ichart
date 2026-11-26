# iChart Fix Docket

## New intake in fix order — November 21, 2026

1. **FIX-037 · P1 · Resize overlapping chords and place them near the left barline.**
   Medium editor interaction fix, following FIX-017. An adjacent chord could
   cover the selected chord's resize target, and the beat-one snap acted as
   the minimum x position for a chord move.

   In both chart styles, **Select** now shows left and right grips next to the
   chord glyphs. Covered grips shift clear of neighboring chord bodies and
   stay visually connected to their chord. The chord and edge are captured
   when the Pencil contacts the grip. Resizing preserves the other chord
   records, the selected chord's measure and beat, and the source ink.

   The first drag guide is labeled **1** and snaps to beat one. A chord can
   move farther left within the same measure. Its leading edge crossing the
   barline selects the previous measure in the row. First-measure signatures
   and repeat markings retain clearance. Older saved placements keep their
   engraving inset, and a deliberate placement before the guide survives
   reopening. The Select helper and How To describe both gestures.

   Implemented in `ed52dd8` on `codex/fix-037-chord-resize-and-barline`.
   The iPad Simulator passed 538 tests with two optional device-data replays
   skipped. SwiftPM passed 151 placement and layout tests. The mounted
   regressions exercised both styles, including a Pencil grip admitted before
   selection changed, placement on either side of the left barline, and
   retention of chord placement and source ink through a save/load round trip.
   Build 175 (1.9.4) was installed in place on the physical iPad after two
   matching full backups. Both postlaunch readbacks matched all 27 charts,
   640 saved ink archives, one project, 37 PDFs, and three setlists with 22
   links. App startup changed the subscription verification timestamp and
   other bookkeeping. The user confirmed on November 23 that resizing
   overlapping chords and moving chords to the left barline work in both
   chart styles on Build 175.

2. **FIX-038 · P2 · Make Text cue placement and editing predictable.**
   Medium editor workflow fix, related to FIX-034. Adding a cue discarded
   the tap position inside the measure. Dragging showed the translated cue,
   but release treated the Pencil point as the cue's left edge. Padded
   controls could also steal taps near other cues or adjacent controls.

   In **Tools > Text**, a tap picks a measure and snapped beat. A blue marker
   shows the anchor, and the **Above** or **Below** entry panel names the
   destination. Switching between Keyboard and Scribble keeps the same
   destination and draft. **Edit** keeps the current tool active and applies
   to the selected cue. **Cancel** discards the draft.

   Visible neighboring text is protected from padded edit-control hit
   areas, and the cue controls have separate targets.

   Implemented in `d5776d3` on `codex/fix-038-text-placement`. All 522 focused
   iPad Simulator tests and 332 SwiftPM tests passed. Both chart styles were
   exercised for placement, editing and cancellation, Keyboard and
   Scribble switching, dragging, PDF rendering, and save/reopen.
   Build 176 (1.9.4) was installed in place on the physical iPad after two
   matching full iChart backups. Two postlaunch readbacks matched all 27
   charts, 640 ink archives, one project, 37 PDFs, and three setlists with
   22 links. The library's two sync timestamps advanced and deletion
   tombstones reordered without changing their membership. The user verified
   Text placement and editing on Build 176 and reported that vertical cue
   moves still changed staff spacing.

   The vertical-move follow-up keeps the cue on its measure and beat during
   a straight up or down drag. Dragging the cue or using **Move Up or Down**
   uses the available space near it, with the same staff positions and
   page breaks through preview, release, save, and reopen. **Reset
   Position** restores automatic placement. Follow-up `2f3c632` passed
   286 focused iPad Simulator tests and 344 SwiftPM tests, covering both
   chart styles, both drag routes, PDF rendering, and persistence.
   Build 177 (1.9.4) was installed in place and relaunched on the physical
   iPad after two matching full iChart backups. The prelaunch comparison
   and two postlaunch readbacks preserved all 27 charts, 640 ink archives,
   one project, 37 PDFs, and three setlists with 22 links. The two library
   sync timestamps advanced, and deletion tombstones reordered with the
   same membership. Physical Pencil retesting remains open.

   Build 177 Pencil feedback identified sticky horizontal movement,
   difficulty positioning cues before the first barline, redraw lag, and
   a bulky vertical control. The follow-up keeps the original grab point
   and follows the Pencil continuously between beats. The cue's leading
   edge determines the measure, and a blue attachment line and dot switch
   at the barline. The guide disappears in the row margin. Cues can sit
   before the first barline, and the right margin is available when the
   whole cue fits. Saved margin positions use a row edge measure as a
   reference. Deleting that reference measure also deletes the cue.

   Both drag routes move the same cached cue text and guide independently
   of the page drawing. The compact up/down handle keeps a separate touch
   target and the **Move Up or Down** accessibility action. The Edit
   panel identifies saved row margins and shows the measure without a
   snapped beat for freely positioned cues. Vertical moves still keep
   staff spacing and page breaks fixed.

   Follow-up `9e32bdd` passed 309 iPad Simulator tests and 364 SwiftPM
   tests. Coverage includes both chart styles, continuous motion across
   barlines, attachment and margin guide changes, steady backing canvas
   during mounted drag gestures, PDF placement, and save/reopen.
   Build 178 (1.9.4) was built and signed from that revision, and its
   development profile was verified for the iPad. The signed app is staged
   at `/private/tmp/ichart-fix038-spacing-qa/signed-build178/iChart.app`.
   Build 178 was installed in place after two byte-identical stopped-app
   backups. The app launched after the iPad was back online. Two live
   readbacks matched the saved content of all 27 charts, 640 ink archives,
   one project, 38 PDFs, and three setlists with 22 links. Startup updated
   selection, subscription history under the same Free plan, and cloud
   backup metadata. Device verification is recorded in
   `.build/device-backups/2026-11-23-fix038-build178/installation-complete.json`.

   Build 178 Pencil feedback identified the detached height control,
   redundant cue reset, limits at nearby chord and staff bounds, and a
   guide that slid within the current measure. The follow-up makes the
   cue body the press-and-hold grab target for both directions. The cue
   moves within the page body while staff spacing and pagination stay
   fixed. The guide touches the middle of the attached measure and
   changes anchors at the barline. Cues in the row margin have no guide.
   Cue Reset Position was removed. Endings and form marks keep their
   height controls.

   Follow-up `1414069` passed 324 iPad Simulator tests and 373 SwiftPM
   tests. Coverage includes press-and-hold, touch-down drift, measure
   context after release, page-range placement, the guide at each
   measure's center, save/reopen, and PDF output in both chart styles.
   Build 179 (1.9.4) was built and signed from that revision. Its iPad
   development profile was verified. The signed app is staged at
   `/private/tmp/ichart-fix038-spacing-qa/signed-build179/iChart.app`.
   Build 179 was installed in place and relaunched after two byte-identical
   stopped-app backups. Two live readbacks matched the saved content of
   all 27 charts, 640 ink archives, one project, 38 PDFs, and three
   setlists with 22 links. Startup refreshed the selected chart's cloud
   backup acknowledgement and the library sync timestamps. The receipt
   is `.build/device-backups/2026-11-23-fix038-build179/installation-complete.json`.
   Build 179 Pencil feedback confirmed the grab workflow and identified
   two follow-ups. Fit the rendered cue outline to its text, grow the
   existing Add/Edit field as lines are entered, and allow the first
   system's cues to move into the space above it. Use the same placement
   in drag preview, chart reopen, and PDF export. Keep the staff and
   page geometry fixed during vertical moves.

   Follow-up `a31eaf8` fits the cue outline to its rendered lines and
   grows or shrinks the existing Add/Edit field in place. Return adds a
   line in the same cue. First-system cues can now move above the
   system to the paper's top inset, with editing controls below the
   cue at the top edge. The drag preview, saved chart, and PDF agree.
   Passed 345 iPad Simulator and 374 SwiftPM tests covering both chart
   styles.

   Build 180 (1.9.4) was signed from `a31eaf8`, installed in place, and
   relaunched after two byte-identical stopped-app backups. Both
   postlaunch readbacks matched the saved content of all 27 charts,
   640 ink archives, one project, 38 PDFs, and three setlists with 22
   links. Startup updated sync timestamps and reordered the deletion
   records. The receipt is
   `.build/device-backups/2026-11-23-fix038-build180/installation-complete.json`.
   The Build 180 iPad retest confirmed that multiline fields resize and
   cues move above the first system in both chart styles.

3. **FIX-039 · P2 · Show immediate feedback for tools and actions.**
   Broad interaction and accessibility pass. A tap can be hard to
   distinguish from one the app did not receive. Use a shared visible
   pressed state and acknowledge accepted selections or actions at the
   control. Use the existing blue outline with a fill or shape change.
   Apply it to tools, dropdown rows, and app actions. On the chart,
   selection highlights and handles convey the actual chart state.
   Verify enabled, disabled, selected, and pending states with finger
   and Apple Pencil where applicable. Feedback must leave
   gesture routing, layout, and Write & Render cadence intact.

   Build 181 introduced the shared pressed outline for custom tool, Library, Project,
   Setlist, and Forum buttons. Pencil controls and Keyboard/Scribble
   acknowledge accepted actions in place. Build 181 also added a brief
   blue ring and check at accepted canvas taps. The repeat guide points
   to the highlighted measure before End Repeat.

   Commit `f542730` passed all 10 new Simulator feedback tests and 351
   SwiftPM tests.
   The clean Simulator comparison matched all 83 existing test outcomes
   against Build 180, including 17 hosted accessibility failures in
   both revisions. The real-app repeat range and cue entry workflows
   passed in both chart styles. Rendering cadence checks also passed.
   The physical iPad retest was pending at this checkpoint.

   Build 181 (1.9.4) was signed from `f542730`, installed in place, and
   relaunched after two byte-identical iChart container backups. Both
   postlaunch readbacks matched all 27 charts, 640 ink archives, one
   project, 38 PDFs, and three setlists with 22 links. Startup updated
   sync timestamps and reordered deletion records. The receipt is
   `.build/device-backups/2026-11-23-fix039-build181/installation-complete.json`.

   Build 181 iPad feedback identified missing dropdown and subtool
   feedback and controls whose padding did not accept taps. The
   follow-up targets the entire visible title box and tool buttons,
   adds the shared feedback to native dropdown triggers, and includes
   the visible padding in chart, PDF, and project-chart card actions.
   The card action and its trailing menu remain independently tappable.

   Follow-up `16247b1` passed five real-app Simulator workflows, 32
   focused native tests, and 351 SwiftPM checks. Both chart styles
   passed edge taps on the title, Tools, Add, repeat controls, text
   controls, and Write & Render. The landscape Library test opened a
   chart from the card padding and then used the separate action menu.
   A Simulator recording captured the full-width title highlight.
   Physical iPad retest of this follow-up is pending.

   Build 182 (1.9.4) was signed from `16247b1`, installed in place,
   and relaunched after two byte-identical stopped-app backups. The
   first live copy was interrupted by the iPad file service. Two fresh
   readbacks on retry matched all 27 charts, 640 ink archives, one
   project, 38 PDFs, and three setlists with 22 links. Startup updated
   sync timestamps and reordered deletion records. The receipt is
   `.build/device-backups/2026-11-23-fix039-build182/installation-complete.json`.

   The Build 182 iPad retest narrowed feedback to tools and commands.
   Remove the extra acknowledgement from measure selection and other
   canvas taps. Use full-width buttons with the shared pressed outline
   inside Tools, Rendering, Measures Add and Delete, Repeat Measures,
   Add Ending, Manage, and Restore Ink. Keep the existing chart selection
   and pending-range cues.

   Commit `440ad85` passed nine Simulator workflows, 31 focused iOS
   tests, and 351 SwiftPM checks. In both chart styles, tapping the
   trailing blank space opened each of the four visible Tools destinations.
   Menu dismissal and reopening, sheet handoffs, repeat and delete
   ranges, and Automatic and Manual Write & Render also passed.
   A Simulator recording showed the full-width pressed outline on
   Add Multiple After… in both styles.

   Build 183 (1.9.4) was signed from `440ad85`, installed in place,
   and relaunched after two byte-identical stopped-app backups. The
   iPad file service interrupted the second live copy. Two fresh
   readbacks on retry matched all 27 charts, 640 ink archives, one
   project, 38 PDFs, and three setlists with 22 links. Startup refreshed
   sync timestamps and reordered deletion records. The receipt is
   `.build/device-backups/2026-11-23-fix039-build183/installation-complete.json`.
   The user accepted the Build 183 iPad retest and moved on to FIX-040.

   On Build 199, six Simulator walkthroughs passed for Quick Actions and
   editor menu handoffs in both chart styles at regular and narrow widths.

4. **FIX-040 · P2 · Give Basic chart PDFs a small iChart credit.**
   **Closed · November 24, 2026.** The user confirmed the iPad footer
   retest in both chart styles and reported that AirPrint works.

   Paid-launch product decision and focused export change. Use a small
   **Made with iChart** signature in the page margin, with a first-page
   footer as the starting design. At paid rollout, use the effective
   Basic entitlement when generating a new chart PDF, including the same
   PDF used by Share or Print. Pro exports keep their current layout.
   Keep unlimited Basic PDF export, protect imported originals and
   previously saved PDFs byte for byte, and preserve Forum publication
   credit. Verify both chart styles, dense and multipage charts, and
   exports before and after a plan change. Confirm the credit clears
   notation and Free Ink and survives printing.

   Implemented in `f5c77de` on `codex/fix-040-basic-pdf-credit`. The paid Basic
   editor export fits page-one notation and Free Ink above a 28-point
   footer space and keeps the same paper dimensions and page count.
   The footer is part of the saved PDF used by preview and the system
   Share sheet. Paid Pro, Pro grace, legacy local Pro, and both free
   beta choices use the standard export. Forum creator credit retains
   its own rendering path. Exports remain unlimited in Basic.

   The paid-policy Simulator opened Export PDF and Share in both chart
   styles. Both saved PDFs had one first-page credit. Dense two-page
   fixtures kept bottom-edge handwriting and identical later-page
   rendering. Existing saved and imported PDFs passed byte comparisons
   across plan changes. SwiftPM passed 111 checks. The focused iOS
   suite passed 71 of 72 tests, including all 22 PDF exporter tests.
   The one hosted legacy Forum accessibility failure reproduced at
   the same assertions on Build 183 source `440ad85`.

   Build 184 (1.9.4) was signed from `f5c77de` in the normal free-beta
   configuration, installed in place, and reopened after two byte-identical
   stopped-app backups. Both live readbacks preserved 27 charts, 640 saved
   ink archives, one project, 38 PDFs, and three setlists with 22 links.
   Startup refreshed sync timestamps and reordered deletion records. The
   paid Basic footer remains a Simulator-verified path. The device receipt
   is `.build/device-backups/2026-11-23-fix040-build184/installation-complete.json`.

   The separate offline **iChart PDF QA** Build 185
   (`com.ichart.app.pdfcreditqa`) was installed beside regular Build 184.
   Its local Basic test setting runs the production exporter with synthetic
   two-page Simple and Rhythm charts. Both PDFs generated on the physical
   iPad contained the credit on page one only. Visual review confirmed
   that the footer clears the bottom-edge handwriting in both styles.
   The regular app's build and installed container identity matched
   before and after. The user confirmed the footer looks good in both
   chart styles on the iPad.
   The receipt is
   `.build/fix-040-ipad-pdf-qa-20261123/verification/installation-complete.json`.

5. **FIX-041 · P3 · Redesign the chart editor tool flow.**
   **Closed · November 24, 2026.** The user accepted Build 197 on the
   iPad in Simple Chord Sheet and Rhythm Section Sheet, including a
   narrow window. The final retest confirmed the Quick Actions chevrons
   and centered blue heading.

   Editor workflow redesign. iPad feedback on Builds 186 and 187 found
   the quick actions redundant and the tool flow more complicated.
   Rollback `7eb1f40` removes both prototypes from the source and restores
   the exact pre-quick-action tree at `f5c77de`. Use the restored top
   toolbar and Tools menu as the baseline for the redesign.

   Walk through Select, Write & Render, Free Ink, and Measures, including
   Repeats, Time Signature, Text, and Form Markers in Tools. Map each
   workflow from opening the tool through selecting a target, applying or
   canceling, and returning to the chart. Give each action a clear primary
   entry point and show the controls relevant to the current step. Use
   the walkthrough to identify extra taps, repeated controls, and mode
   changes that make common actions harder to complete.

   Evaluate the full sequence when tools are used together. A switch
   should carry a compatible selection forward and leave the next tool
   ready for input. Keep uncommitted actions local to the tool, make
   cancellation predictable, and preserve draft ink when switching
   between chart edits and Write & Render. Compare common tasks with
   Build 188 on the same chart. Record duplicate entry points, taps,
   menus opened, backtracking, and time until the next action is ready.

   Review visual design alongside each workflow. Size popovers to their
   contents and available space. Keep labels legible, full rows tappable,
   and the main action visible at narrow widths and larger text sizes.
   Use type, spacing, color, borders, and containers to distinguish the
   current tool, selected target, next action, and destructive actions.
   Test opening, dismissing, and reopening menus without shifting the
   canvas or covering the chart target the action needs.

   Verify Simple Chord Sheet and Rhythm Section Sheet in wide and narrow
   windows, in portrait and landscape. Start a repeat, tap a different
   measure to set its endpoint, and verify both End Repeat and Cancel.
   Check measure selection, time-signature placement, text cues, form
   markers, and switching back to Write & Render. Keep writing and
   rendering continuous, keep tool tap targets and feedback consistent,
   and confirm existing charts and ink survive save and reopen. Update the
   contextual helper, accessibility guidance, Quick Start, and How To
   wherever a tool's entry point or behavior changes.

   Repeats is the first redesign slice in `5bc6203`. The existing
   Tools > Repeats row shows Start Repeat and Repeat This Measure
   directly. End Repeat and Cancel occupy those same positions while
   placing a range. The contextual helper and How To use the new path.
   Simulator walkthroughs passed in Simple and Rhythm at standard and
   360-point editor widths. They verified single-measure placement,
   changing the range endpoint, cancellation, applying the range, and
   stable action positions and canvas placement. All 351 focused SwiftPM
   checks passed. The Repeats controls remain legible at 360 points.
   Several top toolbar labels wrap or truncate at that width. Include
   those labels in the toolbar review.

   Build 189 (1.9.4) was signed from `5bc6203`, installed in place,
   and reopened after two byte-identical stopped-app backups. Both
   postlaunch readbacks preserved the selected chart, 27 charts,
   640 saved ink archives, 1 project, 38 PDFs, and
   3 setlists with 22 links. The user accepted the direct repeat
   buttons and reported that Manage still hid actions that belong with
   repeats and endings. The receipt is
   `.build/device-backups/2026-11-23-fix041-repeat-actions-build189/installation-complete.json`.

   The Repeats follow-up at `05ca34a` and `a6ebeae` removes Manage.
   Remove Repeat sits with the repeat actions. Edit Ending and Remove
   Ending sit with Add Ending. The actions are disabled until the
   selected measure has a repeat boundary or falls under an ending.
   Shared boundaries and overlapping endings prompt for an exact mark.
   Editing an existing ending returns to Repeats, and removing a single
   ending uses the existing delete confirmation pattern. At compact
   widths, text-only labels keep the direct actions legible.

   Three Simulator walkthroughs passed in both chart styles at standard
   and 360-point widths. They verified disabled states on unrelated
   measures, exact repeat removal at a shared boundary, editing and
   removing an ending from inside its range, and stable Start Repeat,
   End Repeat, and Cancel placement. All 351 focused SwiftPM checks passed.

   Build 190 (1.9.4) was signed from `a6ebeae`, installed in place,
   and reopened after two byte-identical stopped-app backups. Both
   postlaunch readbacks preserved the selected chart, 27 charts,
   640 saved ink archives, 1 project, 38 PDFs, and
   3 setlists with 22 links. The user accepted the direct repeat and
   ending actions on Build 190 as the pattern for the remaining tool
   redesign. Resume FIX-041 from this checkpoint: put common actions
   directly beside their tool, show when the selection makes them
   available, and ask for a specific target when more than one matches.
   Keep the controls readable and the canvas steady at narrow widths.
   The receipt is
   `.build/device-backups/2026-11-24-fix041-repeat-management-build190/installation-complete.json`.

   The Measures follow-up at `d422366` puts the insertion and deletion
   actions directly in the Measures tool, with text labels in a compact
   two-row layout. The top toolbar is the single entry to Measures.
   Select still offers row actions for the chosen measure. Layout opens
   the existing sheet with target-specific choices and availability.
   Delete Measure confirms the selected measure by number. When the
   first-measure action only resets a trailing barline, it is labeled
   Reset Barline. Delete Range uses Delete To and Cancel in the same
   positions while the endpoint changes and keeps the canvas steady.

   Focused SwiftPM checks passed (351). Simulator walkthroughs passed
   in Simple and Rhythm at standard and 360-point widths, including
   range retargeting and cancellation, single-measure deletion with
   confirmation, and selection when switching tools. Layout retained
   its explanation and selection on reopen. Multiple insertion still
   opens its count sheet, and Rhythm kept a ninth measure on a full
   row.

   Build 191 (1.9.4) was signed from `d422366`, installed in place,
   and reopened after two byte-identical stopped-app backups. Both
   postlaunch readbacks preserved the selected chart, 27 charts,
   640 saved ink archives, 1 project, 38 PDFs, and
   3 setlists with 22 links. The direct Measures actions are ready
   for physical retesting. The receipt is
   `.build/device-backups/2026-11-24-fix041-measures-build191/installation-complete.json`.

   Build 191 iPad feedback found that the blank measure added after a
   final one-measure repeat looked like part of the repeat. The closing
   repeat now draws at the new measure’s leading boundary. The new measure
   stays open for writing and keeps its own ID across save and reopen.
   Older saves did not record whether an empty trailing measure had been
   explicitly added, so their existing layout is preserved.

   Measures now shows the five row actions at the left edge of the chart.
   In narrow windows they sit directly below the Measures toolbar to keep
   the full chart width. Actions follow the selected measure and become
   unavailable during Delete Range. The separate Measure Layout sheet was
   removed. Measures guidance, Quick Start and How To describe the direct
   actions.

   Source checkpoint `1e110fb` passed 352 focused SwiftPM checks and 179
   iOS Simulator unit and hosted editor checks. The repeat-boundary
   regression covers both styles at editor and PDF sizes after reopening.
   Nine distinct UI walkthroughs passed, including direct row moves in
   both styles at regular and 360-point widths. The direct Measures
   walkthroughs were rerun at both widths after the last control change.
   The hosted editor verified larger-text placement and reachability.

   Build 192 (1.9.4) was signed from `1e110fb`, installed in place, and
   reopened on the iPad. Two independent stopped-app backups matched
   byte for byte. Both postlaunch readbacks matched the saved chart
   content, including the selected chart, 27 charts, 640 ink archives,
   1 project, 38 PDFs, and 3 setlists with 22 links. Physical retesting of
   Add One After and the direct Layout buttons is pending. The receipt is
   `.build/device-backups/2026-11-24-fix041-layout-repeat-build192/installation-complete.json`.

   The user approved the left-side Layout placement in Build 192 and
   asked for a more raised button treatment. The Layout actions now
   have a subtle edge and shadow with a pressed state. Disabled actions
   stay flat, and Reduce Motion suppresses the movement.

   The saved Simple chart from the retest had a single-measure repeat
   at measure 13 and a separate blank measure 14 with a saved width.
   The original repeat range was already correct. The renderer treated
   the saved blank measure as trailing space and drew the repeat close
   past its left edge. A blank open measure with a saved width now
   keeps its boundary, including in older charts. The editor and PDF
   share that boundary geometry.

   In Measures, a repeat closing measure offers Add Inside Repeat and
   Add After Repeat. Inside includes the new measure in the repeat.
   After keeps the existing endpoint. Add Multiple… uses the same
   placement in its count sheet and defaults to After Repeat. When
   repeats share the same ending, Inside extends the outermost repeat
   ending there.

   Source `ca6f889` passed 212 focused SwiftPM checks and 365 iOS
   Simulator unit and hosted checks. The saved measure 13–14 case
   replayed locally and showed the actual left barline in both the
   editor and PDF. Four UI walkthroughs passed, including inside and
   after insertion at regular and 360-point widths in both styles.
   Build 193 (1.9.4) was signed from `ca6f889`, installed in place,
   and reopened on the iPad. Both stopped-app backups matched byte for
   byte. Both postlaunch readbacks verified the selected chart,
   all 27 charts, 640 ink archives, 1 project, 38 PDFs, and 3 setlists
   with 22 links. The previous saved measure now has a verified
   editor/PDF boundary in Simulator. Physical retesting of that
   boundary, the two placement choices, and the raised Layout buttons
   is pending. The installation receipt is
   `.build/device-backups/2026-11-24-fix041-repeat-placement-build193/installation-complete.json`.

   The next iPad feedback requested a single home for Layout actions.
   The rail stays visible across editor modes, with the existing inline
   placement in narrow windows. Its actions follow the selected measure
   in Select and Measures, and disable during incompatible tools,
   panels, and range deletion. The two duplicate Select shortcuts were
   removed. Layout commands invoked from Select keep Select active.
   Even System Measures gives the measures matching widths. Fill Row
   remains the action for a lone measure on a Simple Chord Sheet.

   The raised button face now applies across the editor tool bar, tool
   menus and rows, and tool panels. Press depth keeps the existing tap
   feedback and selected/destructive colors. Canvas editing handles
   and operating-system alerts retain their own controls.

   Testing exposed a Write & Render stall when the ink canvas changed
   focus while the editor was updating. Focus now changes after the
   update ends and follows the current tool and review panel state.

   Source `e72edf6` passed 212 focused SwiftPM checks and 56 native
   Simulator checks, including button appearance, Pencil input,
   divider selection, text cues, and review focus. The persistent
   Layout actions passed UI walkthroughs in both styles at regular
   and 360-point widths. Cold Write & Render entry, Done, and reentry
   passed in both chart styles with Automatic and Manual rendering.

   Build 194 (1.9.4) was signed from `e72edf6`, installed in place,
   and reopened on the iPad. Two stopped-app backups matched byte
   for byte. Both postlaunch readbacks preserved the selected chart,
   all 27 charts, 640 ink archives, 1 project, 38 PDFs, and 3 setlists
   with 22 links. The installation receipt is
   `.build/device-backups/2026-11-24-fix041-persistent-layout-build194/installation-complete.json`.

   The user accepted the persistent Layout actions and the raised tool
   buttons on iPad in both chart styles. Repeats now opens straight
   from the top toolbar. Start Repeat in the sidebar and in Repeats
   shares the same range and becomes End Repeat during placement.

   Add Text, Form Markers, and Time Signature open from the sidebar.
   Text keeps Above and Below with the existing entry panel. Form
   Markers presents point-marker buttons above the chart and applies
   to the selected measure. Time Signature presents presets and
   Custom…, then uses the existing scope choices. Custom supports
   numerators 1–24 and denominators 2, 4, 8, and 16. The sidebar wraps
   below the tool controls in narrow windows, where the toolbar uses
   compact text labels. The on-screen guidance and How To describe the
   new entry points.

   Local source is committed as `0e5794c`. Focused validation passed
   213 SwiftPM checks and 273 hosted iOS checks. Two opt-in saved
   device replay checks were skipped. Simulator walkthroughs covered
   the sidebar routes and shared repeat controls in both styles at
   regular and 360-point widths, text cue retargeting, direct Segno
   placement, time-signature scope cancellation, and a custom 11/8
   meter. Build 195 (1.9.4) was signed from `0e5794c`, installed in
   place, and reopened on the iPad. Two independent stopped-app
   backups matched byte for byte. Both postlaunch readbacks matched
   the selected chart, 27 charts, 640 ink archives, 1 project, 38
   PDFs, and 3 setlists with 22 links. The receipt is
   `.build/device-backups/2026-11-24-fix041-sidebar-tools-build195/installation-complete.json`.

   Following the iPad walkthrough, Quick Actions gained Hide and Open.
   Hiding frees the chart's left margin or the button rows above it in
   a narrow window. Repeat placement has one End Repeat action where
   the range started, with Cancel in Repeats. Hiding Quick Actions
   mid-range moves End Repeat to Repeats and keeps the range selected.
   Form Markers and Time Signature center each button row above the
   chart. The quick explainer and How To use the new controls.

   Local commit `2dea774` passed 212 focused SwiftPM checks and six
   Simulator walkthroughs. The walkthroughs covered both chart styles
   at regular and 360-point widths, including centered rows, recovering
   chart space, and finishing or canceling a repeat as Quick Actions
   opens and closes. Build 196 (1.9.4) was signed from `2dea774`,
   installed in place, and reopened after two matching stopped-app
   backups. Both postlaunch readbacks preserved the selected chart
   content, all 27 charts, 640 ink archives, 1 project, 38 PDFs, and
   3 setlists with 22 links. Startup refreshed one chart's backup
   metadata. The receipt is
   `.build/device-backups/2026-11-24-fix041-quick-actions-build196/installation-complete.json`.

   The iPad retest confirmed the Build 196 flow. The follow-up replaces
   the sidebar toggle's visible words with left and right chevrons,
   matching the library sidebar. The blue Quick Actions heading centers
   over the controls when expanded. The editor guide and How To
   describe the chevrons. Local commit `ab23d3f` passed 34 SwiftPM
   checks and the Quick Actions walkthrough in both chart styles at
   regular and 360-point widths. Build 197 (1.9.4) was signed from
   `ab23d3f`, installed in place, and reopened after two byte-identical
   stopped-app backups. Both postlaunch readbacks matched the selected
   chart, 27 charts, 640 ink archives, 1 project, 38 PDFs, and 3 setlists
   with 22 links. The receipt is
   `.build/device-backups/2026-11-24-fix041-quick-actions-chevron-build197/installation-complete.json`.

   The rollback passed 351 focused SwiftPM checks. Simulator walkthroughs
   verified opening all four Tools destinations and selecting and applying
   distinct repeat endpoints in both chart styles.

   Prototype history is recorded in `ff89a45`, `78a5444`, and `8d806c2`.
   The installed Build 187 receipt records backup and save verification at
   `.build/device-backups/2026-11-23-fix041-build187/confirmed-retry/installation-complete.json`.

   Rollback Build 188 (1.9.4) was signed from `7eb1f40`, installed in
   place, and reopened after two byte-identical stopped-app backups.
   Both postlaunch readbacks preserved the selected chart, 27 charts,
   640 ink archives, 1 project, 38 PDFs, and 3 setlists with
   22 links. The user confirmed that the original Tools menu and repeat
   workflow work on the iPad in both chart styles. The receipt is
   `.build/device-backups/2026-11-23-fix041-rollback-build188/installation-complete.json`.

6. **FIX-042 · P3 · Add a staff row in one action.**
   **Parked · November 24, 2026.** The user chose to skip this ticket.

   New chart-editing feature. Define what **Add Staff Row** inserts, how
   many measures it starts with, and whether it inserts after the selected
   row or at the end. Build on the existing measure insertion and row
   breaks and define how the new row carries key and time signature
   across pages. In Rhythm, verify that it adds an editable staff row.
   Evaluate an equivalent **Add Row** action for Simple Chord Sheet.
   Check insertion, undo, reopen, and export while preserving existing
   measure order, attached ink, repeats, and endings.

For the editor tickets, update the on-screen tool helper and **How To**
with the controls and gestures verified in both styles.

## New intake in fix order — November 16, 2026

1. **FIX-029 · P1 · Ordinary barlines take ownership of their ink**
   (follow-up to FIX-001 / RHY-001). Medium recognition and grouping fix.
   When a divider is written with chords, its stroke can become a B or get
   absorbed into a chord on either side. Replay the actual mixed handwriting
   and trace where the stroke is assigned. Resolve eligible divider ink before
   assembling neighboring chord groups. Verify a standalone B and a B next to a
   barline, tight spacing, ink written in either order, and dividers on new and
   existing boundaries. Check Automatic and Manual with Preview in Simple and
   Rhythm. Independent eligible marks should keep rendering while a doubtful
   mark stays editable on the page.

   **Implemented locally.** The iPad Simulator passed 136 focused checks,
   including mixed chord and divider writing in both styles and both render
   modes, an existing boundary, captured B stems, and a retained divider with
   independently placeable chord ink. The mixed editor test used the regular
   Render Chords control in Manual and verified exact chord source archives.
   Build 162 was installed after a verified backup. The user confirmed on iPad
   that barlines work in both chart styles and Write & Render keeps going.

2. **FIX-030 · P1 · Protect triangle major sevenths from unsupported readings**
   (follow-up to FIX-003). Medium recognition fix. Repeated
   `B♭∆7 → B♭ø7/C` mixes a quality error with an added bass note. Replay the
   exact strokes and check triangle/7 grouping, half-diminished scoring, and the
   slash-bass admission separately. Give a supported triangle-plus-7 reading
   priority and require distinct slash and bass-note evidence for an inversion.
   Verify fresh Pencil examples and replay in both chart styles and render modes.
   Include real `B♭ø7`, real `B♭∆7/C`, and ambiguous writing as controls.
   Check the saved rendered chord and the available correction candidates.

   **Implemented locally in Build 164.** On the Build 163 iPad retest, the
   three intended `B♭∆7` chords saved as `B♭∆7`, `B6(b3)`, and `B♭−7`.
   The replay isolated two failures: joined triangle strokes split apart, and
   isolated glyph guesses displaced the written flat and seven. The fix
   recognizes the joined triangle and uses the complete written shape to
   support each glyph's intended role. The existing evidence requirements
   for half-diminished quality and slash bass still apply.

   All three original Pencil samples rendered as `B♭∆7` in the iPad Simulator
   in Simple Chord Sheet and Rhythm Section Sheet, with both Automatic and
   Manual with Preview. Manual used the regular **Render Chords** button.
   The replay verified the saved chord, all six source strokes per sample,
   and a clear draft after reopening. The existing mixed-barline and
   Automatic cadence checks passed. Build 164 is installed on the paired iPad
   after two matching stopped-app backups. Two independent postlaunch
   readbacks verified all 21 charts, 499 saved ink archives, 27 PDFs, and
   two setlists. The user accepted the Build 164 retest on November 18
   and asked to continue down the docket.

3. **FIX-031 · P1 · Stabilize Scribble focus and show both input modes**
   (follow-up to FIX-008, FIX-023, FIX-024, and FIX-026). Medium shared input
   fix. Start with Chord Edit and Review Chords. When Scribble is selected, an
   initial Pencil tap in an unprepared field should get that field ready for
   handwriting. The box should already be stable for the first intended stroke,
   with the draft and selection retained. The software keyboard opens only in
   Keyboard mode. Place labeled **Keyboard** and **Scribble** controls side by
   side on Scribble-capable fields and make the selected mode visible and
   accessible. Keep secure passwords keyboard-only. Retest the initial tap,
   first written stroke, pause, mode switch, and focus change on the physical
   iPad, then verify the shared behavior in Header, cues, and other fields.

   **Implemented locally in Build 165.** Shared text fields show labeled
   **Keyboard** and **Scribble** controls with an accessible selected state.
   The first Pencil tap in Scribble prepares the field with its software
   keyboard suppressed. Switching modes preserves the draft and selection.
   Account passwords keep secure keyboard entry. Updated the on-screen
   help, accessibility hints, and **How To** for the new controls.

   The iPad Simulator passed 42 focused tests. Mounted checks covered Review
   Chords, Edit Chord, Header, search, endings, and the cue panel. Mixed chord
   and barline rendering passed in both chart styles. Build 165 is installed
   on the paired iPad. Two stopped-app backups matched byte for byte, and both
   postlaunch readbacks verified all 23 charts, 517 saved ink archives,
   29 PDFs, and two setlists. The user verified the first Pencil tap and
   switching between Scribble and Keyboard on Build 165.

4. **FIX-032 · P2 · Restore compact sign-in and search fields.** Small-to-medium
   layout regression. Compare Sign In, account forms, and library, setlist, and
   forum search against their intended single-line height and width. Check the
   shared wrapper's padding and sizing before changing per-screen layout. Use
   compact single-line fields for ordinary controls, with room for accessibility
   text sizes and a usable touch target. Verify keyboard, search submission,
   native secure entry, and the new mode controls in both iPad orientations.

   **Implemented locally in Build 166.** Sign In and search use 44-point
   single-line fields at standard text sizes and grow with accessibility
   text. Account forms and search groups have width limits on wide iPads.
   In narrow panes, Sort or Search moves below the field while the field
   keeps its Keyboard and Scribble controls. Password remains native secure
   keyboard entry.

   38 distinct iPad Simulator checks passed, including mounted Sign In,
   accessibility signup, Forum search and submission, Setlists, and Add to
   Setlist. Native secure focus passed. The separate password keyboard
   shortcut and fresh Pencil work need a physical iPad retest.
   Build 166 is installed on the paired iPad. Two stopped-app backups matched
   byte for byte, and both postlaunch readbacks verified all 23 charts,
   517 saved ink archives, 29 PDFs, and two setlists. The user confirmed the
   field sizes, password shortcut, and Scribble on Build 166.

5. **FIX-033 · P2 · Make handwritten accents easier to render**
   (follow-up to FIX-004 / FIX-014). Small recognizer calibration. Use real missed
   accents to determine which normal variations in angle, stroke length, and
   meeting point the detector rejects. Tune the accent path with genuine
   one- and two-stroke examples. Verify that similar ordinary handwriting stays
   editable and that a recognized accent still attaches, floats, and restores
   its source strokes in both styles.

   **Implemented locally in Build 167.** Free Ink accepts mildly rounded or
   tilted accents and uneven legs with a small gap when they converge near a
   shared tip. The nearby-ink veto still applies. The Free Ink guide and
   **How To** explain that an accent can be drawn in one or two strokes.

   41 iPad Simulator checks and 23 portable checks passed. Mounted Simple
   and Rhythm tests verified floating and chord-attached accents, saved
   stroke paths, and Restore Ink. A comparison of 1,356 saved Free Ink
   stroke prefixes found no change in recognition or stroke ownership.
   The positive tests used constructed accents because the local captures
   did not contain an identified recent miss. Build 167 is installed on the
   paired iPad. Two stopped-app backups matched byte for byte, and both
   postlaunch readbacks verified all 23 charts, 517 saved ink archives,
   29 PDFs, and two setlists. The user confirmed that accents work better in
   both chart styles on Build 167.

6. **FIX-034 · P2 · Give cues, endings, and form marks room to coexist.**
   Larger editor and engraving fix. Capture real overlaps first and identify
   which objects need automatic clearance and which need more manual range.
   Use shared placement rules for cues, repeat endings, and form markers, then
   allow useful position overrides that preserve the musical anchor and ending
   span. Verify both chart styles, crowded rows, reflow, save and reopen, and PDF
   output. Give moved objects a way to return to their default position.

   **Implemented locally in Build 168.** Both chart styles space conflicting
   annotations automatically. In Select, tap a cue, ending, or form mark and
   drag **Move Up or Down**. **Reset Position** restores automatic spacing.
   The vertical move preserves measure anchors and ending spans.

   Replaying 102 layouts of 15 saved annotation-bearing charts cleared the
   reproduced cue/ending overlap and preserved page and system counts.
   Crowded fixtures passed in both styles, including row reflow, save and
   reopen, drag, reset, and PDF placement. 173 portable checks and 91 distinct
   iPad Simulator checks passed. Build 168 is installed on the paired iPad
   after two byte-for-byte matching backups. Both postlaunch readbacks
   verified 23 charts, 517 saved ink archives, 29 PDFs, and two setlists.
   On Build 168, the user confirmed improved placement and reported that
   the height control lagged sideways drags and small vertical moves shifted
   staff spacing.

   **Follow-up signed in Build 169.** The height control and connector follow
   a cue, form mark, or measure-snapped ending during the drag. Small vertical
   moves use the existing gap first. Actual clearance limits can still move
   a system. In the saved-chart replay, six small cue moves at a clearance
   limit shifted the row while the cue stayed at the same paper height.
   Reopening charts with existing custom cue offsets can reclaim space under
   the new layout rules. Page grouping and anchors were preserved across 202
   replayed views. The follow-up passed 196 portable and 108 iPad Simulator
   checks, with PDF layout checked in both styles. Build 169 is installed
   after two matching stopped-app backups. Both postlaunch readbacks verified
   all 23 charts, 517 saved ink archives, 29 PDFs, and two setlists. The user
   confirmed on Build 169 that the control follows sideways drags and staff
   spacing holds in both chart styles.
   [Build 169 QA](../../../fix-034-followup-20261118/build-169-qa.txt) · [Install verification](../../../install169-20261118/install-verification.json)

7. **FIX-035 · Roadmap · Convert a PDF into an editable iChart.** New feature.
   The current import saves the document in the PDF Library. Start from the
   [existing conversion plan](../ichart-import-paper-scan-pro-scan-plan-2026-10-23.md).
   Pick a first supported input and prove the review-to-native-chart workflow
   with a fixture. Keep the source PDF and create a separate, reviewable chart
   draft that can be corrected, transposed, saved, reopened, and exported.
   Decide recognition coverage, handling of uncertain material, and any online
   processing or usage allowance before shipping conversion.

   **First local implementation.** A saved personal PDF can open **Create
   Editable Chart** for one-page chord grids with selectable text and `|`
   barlines. Review retains the source and flags measures that need a
   correction. The new Simple Chord Sheet uses 4/4 and even chord spacing
   starting at beat one. The chart's Actions menu can reopen its original
   PDF. The conversion runs on device and follows normal chart capacity.
   The simulator workflow verified correction, save and reopen, chord edit,
   transpose, and export with byte-exact source retention. 130 focused
   SwiftPM tests and 53 iPad Simulator tests passed. Build 170 was installed
   after two matching stopped-app backups. Two postlaunch checks verified
   25 charts, 640 saved ink archives, 32 PDFs, and three setlists. The user
   confirmed the four-bar sample converted and saved as an editable chart on
   the iPad. A PDFKit check of the existing one-page personal PDF found no
   selectable text. The other personal import in the install backup has
   multiple pages. Both fall outside the first converter's input format.
   [Build 170 QA](../../../fix-035-20261120/build-170-qa.txt) · [Install verification](../../../install170-20261120/install-verification.json)

   **Drawn-barlines follow-up in Build 171.** The review reads selectable
   chords against drawn single-staff measure dividers across multiple PDF
   pages. It labels rows with their original PDF page. On the supplied
   concert sheet, a visual reference and production replay matched 36 measures
   on page one and 38 on page two. All 93 chord entries, ten empty measures,
   printed spellings, and the original PDF were verified after save and reopen
   on the iPad Simulator. Both import formats passed the focused suite of
   130 SwiftPM and 55 iPad Simulator tests. Build 171 is installed after two
   matching stopped-app backups. Two postlaunch checks verified 26 charts,
   640 saved ink archives, 33 PDFs, and three setlists. The user converted
   and reopened the chart on the iPad. Two readbacks confirmed all 74
   measures and 93 chord entries in source order, including ten empty measures
   and the bass-only changes. The linked PDF matched the original bytes.
   [Build 171 QA](../../../fix-035-drawn-barlines-20261120/build-171-qa.txt) · [iPad chart readback](../../../fix-035-drawn-barlines-20261120/ipad-concert-sheet-verification.json)

8. **FIX-036 · Product decision · Update Basic and Pro.** Check the
   [current plan policy](../ichart-plan-policy-source-of-truth.md) against the
   app's gates before revising the entitlement matrix.

   - **PDF to editable chart · Agreed for paid launch.** Creating a new
     editable chart from a PDF requires paid Pro, including the current
     on-device converter. Basic includes importing, reading, and sharing
     original PDFs without using local chart slots. Editing and exporting
     saved charts, including converted charts, stays available after downgrade.
     Apply the three-chart Basic cap to new chart creation. Reconcile the older
     over-cap editing lock in the paid-plan policy before changing access.
     If cloud-assisted conversion ships, include a Pro page allowance based
     on observed processing costs.

   - **Local PDF setlists · Agreed for paid launch.** Basic includes unlimited
     local setlists and offline access to saved PDFs. Pro adds backup, restore,
     and cross-device sync for the setlist and its PDFs. Live band sharing is a
     later Pro feature. After downgrade, downloaded setlists remain editable
     and playable locally. Sync and live sharing pause.

   - **Projects · Agreed for paid launch.** Pro includes creating and
     organizing song Projects and duplicating instrument variants inside them.
     After downgrade, keep existing Projects visible as read-only groups. All
     member charts stay openable, editable, and exportable in both the group
     and the Charts library. Keep individual instrument views available in
     Basic and apply its creation cap when saving another chart.

   - **Forums · Agreed for paid launch.** Signed-in Basic users can browse and
     search published charts, read details and discussion, and see contributor
     badges. Keep reporting and blocking available wherever people can browse.
     Paid Pro includes new full PDF downloads, chart submission, voting, and
     commenting. Previously saved forum PDFs remain playable offline in the
     PDF Library and setlists after downgrade. Replace the older paid-plan
     download cleanup rule when implementing the split.

   - **Fonts and chart styles · Agreed for paid launch.** Simple Chord Sheet
     and Rhythm Section Sheet stay in Basic, with standard fonts and
     readability controls. Paid Pro adds the more expressive font choices
     in both styles. More fonts can join the Pro collection later. Keep the
     applied font on existing charts through downgrade, editing, and export.
     The proposed first lineup puts Petaluma, MuseJazz, and Finale Jazz in
     Pro, with Finale Broadway, the new-chart default, and the standard
     engraved choices in Basic.

   **Implemented locally in `8684370`.** SwiftPM and iPad Simulator checks
   covered saved chart edits above the cap, both chart styles and saved fonts,
   PDF import and conversion, retained Forum downloads, and linked PDF
   setlist backup, restore, and reopening after downgrade. The release
   candidate defaults to the current free beta. Build 172 is installed on
   the iPad as a local paid-plan preview. Two postlaunch readbacks matched
   27 charts, 640 ink archives, one Project with three chart references,
   34 PDFs, and three setlists with 22 PDF references. The user then switched
   from Pro to Basic and reopened the saved content on the iPad. Two
   independent readbacks after that retest matched the charts and ink,
   Project membership, PDF library, and setlists against the verified install
   baseline. Hosted rollout remains open.
   [Implementation and QA](../../../fix-036-20261120/source/docs/qa/ichart-fix-docket.md)
   · [Build 172 install verification](../../../install172-20261120/install-verification.json)
   · [Physical downgrade readback](../../../install172-20261120/downgrade-readback.pKHDii/downgrade-verification.json)

## Measure rows and Free Ink — November 14, 2026

**FIX-027: Fit measure inserts and adjacent-row moves.** Priority P1.
**Closed · November 24, 2026.** The Simple and Rhythm iPad retests confirmed
the row moves after reopening, with measure order preserved.

In Rhythm Section Sheet, Add One After must fit a new measure in the selected
row, including a ninth measure in a row of eight. Verify even widths and the same row membership
after reopening. In both chart styles, Join Row Above and Move to Row Below must
work from an interior measure and across automatically wrapped rows. Verify that
the boundary shifts through the selected measure, the affected rows fit the page,
and musical order, measure contents, and protected key and page boundaries are
preserved.

**FIX-028: Keep Free Ink with its music.** Priority P1.
**Closed · November 24, 2026.** The Simple Build 198 and Rhythm Build 199
iPad retests confirmed that ink follows moved measures and dragged chords,
with the original saved ink and anchors preserved after reopening.

Existing handwriting within a measure or directly below it should follow the measure during insert,
resize, or row movement. Writing directly below one identifiable chord should
follow the chord when moved. Verify Simple and Rhythm with existing ink,
connected writing, standalone page notes, a save and reopen, and PDF projection.

Build 160 was tested locally on iPad. The Rhythm Section Sheet retest confirmed
that measure rows and their handwriting stayed together after saving and
reopening. Saved-data readback confirmed the original measure order and stroke
paths. Simulator walkthroughs covered Add One After on a full Rhythm row and
both row moves in Simple and Rhythm. Native tests cover measure and chord
identity and shared editor/PDF ink projection.

Build 197 on the iPad was verified on November 24. On that revision,
both Simulator row-move walkthroughs passed at regular and narrow widths
in both chart styles. Eighteen hosted tests passed, covering row reflow,
saved ink and PDF projection, and ink following a dragged chord after
reopen. On the physical Simple chart, the user confirmed that the Free Ink
followed the measure and remained aligned after reopening. Saved-data readback
confirmed the new row grouping and preserved measure order. The same retest
found that Free Ink stayed behind when the chord moved. The chord move saved
with the same chord ID, and the saved ink still contained all eight strokes.

The failed groups overlap the bottom of the full Simple chord layout frame
while sitting beneath the visible chord. The attachment policy now accepts
this limited overlap on Simple and retains the measure and neighboring-chord
checks. In the local policy replay of the actual saved groups, Build 197
attached zero of four groups and the candidate attached all four.
Local commit `7592806` passed 32 hosted checks, including a new
cross-measure Simple drag and reopen regression. The regression verifies
that the original ink archive is preserved and that neighboring handwriting
and page notes stay in place. Build 198 (1.9.4) was signed from `7592806`,
installed in place, and reopened after two byte-identical stopped-app
backups. Both postlaunch readbacks matched all 27 charts, 641 ink archives,
1 project, 38 PDFs, and 3 setlists with 22 links. A comparison by the test
chart's stable ID verified the saved row layout, chord placement, original
ink archive, and anchors. The user accepted the Simple Chord Sheet Apple
Pencil retest on Build 198. A separate read-only iPad verification found
the same chord saved in a different measure with its symbol, original
Free Ink archive, and anchors preserved. Measure order and row membership
also matched. The installation and retest receipts are
`.build/device-backups/2026-11-24-fix028-simple-chord-ink-build198/installation-complete.json`
and `.build/device-backups/2026-11-24-fix028-simple-chord-ink-build198/physical-retest/verification.json`.

The Build 198 physical Rhythm retest found that Free Ink stayed behind
after both a row edit and a chord drag. A read-only comparison confirmed
the changed row grouping and chord placement, identical measure order and
chord IDs, and all nine new strokes saved in the gap between the chord
and staff. The candidate lets ink directly below one chord follow it even
when the group overlaps the lower chord frame. Nearby ink in that gap
can fall back to the owning measure when its staff moves.

In the local replay of the saved stroke bounds, the candidate projected
all nine strokes with the measure and the seven directly beneath the
chord with the modeled chord drag. The preexisting strokes stayed fixed
in those replay scenarios. Build 198 projected none of the nine in
either scenario. The two hosted regressions cover the chord drag and row
movement through reopening, with separate stationary ink controls.
Local commit `4eae2c7` passed 34 focused tests and 223 editor and ink
preservation checks, with two opt-in device replays skipped. Build 199
(1.9.4) was signed, installed in place, and reopened after two
byte-identical stopped-app backups. Both postlaunch readbacks preserved
27 charts, 641 ink archives, 1 project, 38 PDFs, and 3 setlists with
22 links. The affected chart's row layout, chord placements, original ink
archive, and anchors matched the retest readback. The user accepted both
the measure move and chord drag on the physical iPad after reopening.
Two readbacks agreed that the saved row grouping changed from five plus
seven measures to six plus six, all 12 measures kept their order, and the
same chord saved in measure 5 after moving from measure 6. The original
Free Ink archive, anchors, and articulations matched the backup exactly.
The receipts are
`.build/device-backups/2026-11-24-fix028-rhythm-ink-build199/installation-complete.json`
and `.build/device-backups/2026-11-24-fix028-rhythm-ink-build199/physical-retest/verification.json`.

The user authorized building, backing up, and installing each finished
iPad fix in this chat as part of the same workflow.

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

**FIX-025: Protect chart edits from finger and palm contact.** Priority P1.
**Closed · November 24, 2026.** The user accepted the finger and palm
protection in Select and moved on to the next check.

Incidental contact could move or delete a saved object. Select now takes
Apple Pencil for on-chart selection, dragging, resizing,
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
FIX-027's Add One After and Join Row Above commands explicitly assign measures
to a row and refit the affected widths. FIX-022 applies when ordinary layout
wraps an unassigned measure onto a row of its own.
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
| FIX-025 | Use Apple Pencil for on-chart edits and finger gestures for navigation. | Closed. 53 distinct focused Simulator tests passed across two runs. The user accepted the finger and palm protection in Select. |
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

The next open device check is FIX-022 automatic Rhythm row fit. Use a measure
that wrapped onto a row of its own during ordinary layout. Check that it
joins the preceding row automatically when it fits after normal sizing or
after shortening that row with its resize handle. Add One After and Join
Row Above explicitly refit the selected rows under FIX-027.

The later FIX-031 and FIX-032 retests already covered the first Pencil tap,
Scribble/Keyboard switching, and Scribble in sign-in and search fields.

For FIX-026, use Apple Pencil to tap a field in Header and Review Chords and
check that the keyboard opens with the draft intact. Use the Pencil
icon to start Scribble, write a word, pause, and write another word. Switch
back to typing and check both words are present. Repeat in a multiline cue.

1. Retest FIX-024 ordinary text input on the physical iPad, including
   Text and Review in both chart styles and representative library, forum, and
   account fields.
2. Retest handwritten chord-repeat symbols (`%` / dot-slash-dot) with Apple
   Pencil in both chart styles and render settings. The November 13 replay
   verified the corrected scope, source ink, and save/reopen. Also check ordinary
   barlines and endings, and use **Repeats** for single-measure and range repeats.
3. Confirm the latest eligible/protected Rhythm divider gestures, style previews
   and forum PDF labels on the physical iPad. Continue checking fresh major-
   seventh and genuine half-diminished writing during normal use.
4. Verify the exact corrected revision's checks before its normal publication or
   merge. Source changes are not an App Store release or an iPad installation.
   Keep #96 open until its historical mechanism and any supported repair are
   established.

Marcato/new mark inputs, Graph/MyScript, ML-core and dedicated reader-retry work
remain parked. The historical ink-integrity investigation requires affected-chart
evidence before closure; this docket makes no new saved-data-loss claim.
