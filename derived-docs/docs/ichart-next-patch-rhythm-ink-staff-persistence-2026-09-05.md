> Public archival derivative of a dated local planning/intake document. Private local identity details were removed; the original remains unchanged. This is historical planning, not current implementation, validation, pricing, or release status.

# iChart Next Patch Intake: Sheet Staff, Pagination, Ink Persistence, Performance, Chord Editing, And Measure Editing

Status: intake, not yet reproduced in code
Date: 2026-09-05
Reported from: physical iPad chart-authoring pass

## Observed User Report

While making a chart in Rhythm Sheet:

- The user wrote four bars on the first staff.
- The user added a repeat sign for those first four bars.
- The leading system's staff lines disappeared. The clef and key signature still appeared, but the actual staff lines were gone.
- The user has seen similar behavior in Simple Chord Sheet.
- Ink appears to shift up/down/around when clicking between different tools.
- Overall ink speed feels too slow while writing, not just during one isolated dense-page case.
- The user suspects the slowdown is related to sync/persistence state.
- With a good amount of rewrite ink already on the page, writing chords feels very slow, with visible drag/weight in the stroke response.
- The user suspects the slowdown may be related to persistent ink state.
- While erasing free-write ink, erasing is also very slow.
- Some erased free-write artifacts pop back after being erased.
- Free-write erase persistence must treat erasure as authoritative, so stale saved ink or sync replay cannot resurrect deleted strokes.
- The user is seeing root-recognition issues again, this time around `G` and `B`.
- The user expects the `G`/`B` root issues to be checkable in telemetry.
- Flats and other accidentals can register as completely different notes when written slightly too far from the base letter.
- The recognizer needs more grace for the space between a base note and attached flats, accidentals, or other chord qualifiers, without collapsing separate neighboring root letters into one accidentalized root.
- Rendered Rhythm Sheet chords visually look close to the correct placement, but the edit box is too large.
- Because the edit box is too large, the chord appears to render outside the intended first beat slot even when the chord text itself looks roughly placed.
- When the user tries to adjust chord size, the chord snaps back.
- The snap-back behavior appears to affect all adjusted chords, not just one isolated symbol.
- In Simple Sheet edit mode, a measure with three chords will not let the user move the third chord to the fourth beat.
- During that drag, the editor shows the green placement state for the last beat, but releasing the drag snaps the chord back to the third beat.
- Simple Sheet rendered chord drag preview and committed placement state are therefore disagreeing.
- The Rhythm Section Measures tool has no Join Measure feature.
- Joining adjacent Rhythm Section measures needs to be implemented.
- More broadly, Rhythm Section measure edits are not functioning as expected.
- Resizing a Rhythm Section measure can affect staff/system layout above it.
- Resizing can also change the beat placement of later measures and sometimes makes later measures larger.
- The Measures tool does not provide an Even Row / equalize-row action for Rhythm Section.
- Rhythm Section measure editing needs to realign with the Simple Chord Sheet measure-tool behavior where the contract is shared.
- A Rhythm Sheet created with 32 starting measures extended the first page instead of keeping the page at normal paper height.
- The first page became extraordinarily long, beyond a real chart page.
- Tapping Add Page then created a real new page with an extra measure, but the chart should not have needed a manual Add Page action to recover from the first page being overlong.
- The first page should snap to fixed page engraving bounds. If the starting measure count exceeds what the page can comfortably engrave, the layout should tighten/pack measures or paginate, not elongate the paper frame.

This note is a defect intake record, not a fix claim.

## Why This Matters

The editor must preserve visible musical context and handwritten ink identity across tool changes. A repeat sign must not suppress the first system's staff geometry, and switching tools must not reload, transform, or redraw saved ink in a different coordinate space.

Dense rewrite ink must also stay responsive. Persistence should protect the user's writing, but it must not put serialization, chart write-back, layout invalidation, recognition, or telemetry work into the live Pencil movement loop.

Erase persistence is part of the same trust boundary. When the user erases free-write strokes, the erased state must win over any stale saved drawing, pending persistence map, background sync replay, or restored canvas snapshot. Slow erasing is a performance issue; erased ink coming back is a data-integrity issue.

Accidental attachment needs to match how musicians write. A flat, sharp, natural, or suffix qualifier can be physically separated from the root while still belonging to the same chord. The fix cannot simply widen all grouping, because adjacent real roots such as `C D` must not collapse into `Cb` or another accidentalized note.

Rendered chord editing must match the visual placement model. If the user sees a chord in a beat slot, the hit/edit box and resize behavior should use the same geometry authority rather than a wider measure frame or stale free-position model.

Drag preview state and committed chord placement must also share the same authority. A green placement preview on beat four is not useful if the release transaction writes or normalizes the chord back to beat three.

The Measures tool should also support the normal structural edits users expect: stable resizing, row equalization, joining adjacent measures, and predictable row/system behavior. Rhythm Section should align with Simple Chord Sheet where both styles share measure-edit concepts, but it is not a mechanical copy because Rhythm Section measures can carry rhythm maps, repeats, cue text, roadmap anchors, and below-measure freehand articulations.

Page geometry must remain real page geometry. A large starting measure count must not stretch the first page's paper height; the layout engine should respect page bounds and decide between tighter measure packing, additional systems, or additional pages according to the chart style's engraving rules.

## Initial Classification

Likely failure classes to verify before patching:

- Rhythm Section renderer/layout regression: repeat-edge rendering or first-system leading notation may be changing the staff-line start/end bounds until the lines have zero or invalid width.
- Active ink scope handoff regression: switching tools may be persisting, reloading, or normalizing the same `PKDrawing` through a different frame.
- Coordinate-space mismatch: saved page, chord-lane, or rhythm-measure ink may be replayed using a stale page/system/measure frame after layout changes.
- Model anchoring gap: some ink may currently be tied to page/global coordinates when the product expectation is system- or measure-relative persistence.
- Dense-ink performance regression: persistent ink state may be causing too-frequent drawing serialization, chart mutation, layout invalidation, or telemetry enqueue work while the user is actively writing.
- Erase-sync persistence regression: erased free-write strokes may be losing to an older persisted `PKDrawing`, pending dirty-state write, background sync merge, or restored canvas snapshot.
- Erase performance regression: eraser movement on dense pages may be serializing full drawings, rewriting chart state, recomputing layout, or replaying persistence too often.
- Chord root recognition regression: `G` and `B` failures need to be classified through current trace/telemetry as glyph classification, root construction, batch grouping, confidence/trust, or preview replacement before changing recognition code.
- Accidental attachment tolerance gap: flats, sharps, naturals, and chord qualifiers written slightly apart from the base letter may be classified as a separate root or separate chord instead of attaching to the intended base note.
- Rendered chord edit geometry regression: Rhythm Sheet chord hit/edit boxes may still be using a broad measure, chord-lane, or legacy fraction frame while visual placement uses beat-slot geometry.
- Rendered chord resize persistence regression: manual chord-size adjustments may be written, then immediately overwritten by layout recomputation, slot normalization, selection refresh, or chart reload.
- Simple Sheet chord drag commit regression: green placement preview can target the fourth beat, while the release transaction or placement normalization restores the chord to its previous third-beat/order slot.
- Measures-tool parity gap: Rhythm Section needs the shared Simple Sheet measure-edit affordances where applicable, including stable resize semantics, even-row/equalize behavior, and Join Measure.
- Measure resize transaction regression: Rhythm Section resize may be committing a selected measure change in a way that triggers row/system reflow, changes later beat placement, or expands neighboring measures unexpectedly.
- Beat-placement drift after resize: rendered chord/rhythm beat positions may be recomputed from changed measure frames without preserving the user's intended beat/slot authority.
- Page-bounds regression: Rhythm Sheet initial layout may be allowing system count/content height to define paper height instead of clipping, tightening, wrapping, or paginating within fixed page bounds.
- Starting-measure pagination gap: large initial measure counts such as 32 need deterministic page/system distribution at chart creation, without requiring a later Add Page command to create valid paper geometry.

Do not assume system/measure anchoring is the immediate fix. First prove whether the drift is caused by layout recomputation, scope identity mismatch, persistence timing, or rendering with stale geometry.

Do not assume server telemetry contains raw chord text or drawing payloads. Use aggregate telemetry/failure buckets where available, and use pulled device traces for chord-specific diagnosis.

## Patch Plan

1. Capture the current iPad app container immediately after reproducing the issue.
   - Pull `Library/Application Support/iChart`.
   - Preserve `library-state.json`, performance traces, telemetry queue, and any ink/debug JSONL files.
   - Record installed app version/build and current git commit separately.
   - If the installed app is an App Store/TestFlight build, confirm whether `devicectl` can access the app data container before assuming local JSONL traces are pullable.
2. Reproduce in a clean local fixture.
   - Create or identify a Rhythm Sheet with first-system four-bar content and a repeat sign.
   - Verify whether leading staff lines disappear while clef/key remain visible.
   - Check Simple Chord Sheet separately if the symptom appears there too.
3. Trace layout and render authority.
   - Inspect `LeadSheetPageLayoutEngine` output for first-system staff frames before and after repeat insertion.
   - Inspect notation rendering bounds for staff lines, leading barline/repeat marker, clef, key signature, and measure body.
   - Confirm whether the staff-line draw path is skipped or receives collapsed coordinates.
4. Trace page bounds and starting-measure pagination.
   - Create a Rhythm Sheet with 32 starting measures and inspect page frames, system frames, rendered paper bounds, and export page count.
   - Verify whether page height is derived from fixed paper geometry or from total system content height.
   - Check whether automatic system packing should tighten row measure widths before increasing vertical page content.
   - Define whether overflow should paginate automatically at creation time or present a bounded page with clear continuation behavior.
   - Confirm Add Page remains a manual true-page insertion action, not a workaround for invalid first-page height.
5. Trace rendered chord edit geometry and resize persistence.
   - Compare visual chord text bounds, placement-slot bounds, hit/edit overlay bounds, and resize handle bounds in Rhythm Sheet.
   - Verify whether edit boxes are derived from placement guide geometry, measure body geometry, or a stale `manualLaneFraction`/free-position helper.
   - In Simple Sheet, create a measure with three chords and drag the third chord to the fourth beat.
   - Compare the drag preview target, green placement-slot state, release target, written `ChordEvent` placement/order/fraction, layout recomputation, and final rendered beat slot.
   - Verify whether slot normalization, chord ordering, `manualLaneFraction`, beat-index rounding, or adjacent-chord collision rules are preventing the third chord from committing to beat four.
   - Track one resize gesture from drag start through model write-back, layout invalidation, and redraw.
   - Confirm whether size changes are persisted in `ChordEvent` state or lost when slot placement recomputes rendered geometry.
   - Reproduce across multiple chords to determine whether this is global edit-overlay behavior or a per-measure/per-slot edge case.
6. Trace ink persistence across tool switches.
   - Record active ink scope identity, input frame, saved drawing bounds, and restored drawing bounds before and after switching tools.
   - Verify that tool changes persist outgoing dirty ink exactly once and reload the same scope in the same coordinate space.
   - Confirm no stale pending persisted-ink map or last-persisted snapshot is overriding newer live ink.
   - Repeat the same trace while erasing free-write ink, including partial erases and erase-to-empty.
   - Confirm erased strokes are removed from the live drawing, persisted drawing, restored drawing, and any sync/dirty-state cache.
   - Verify no older drawing snapshot can overwrite a newer erase operation after a tool switch, chart save, background persistence pass, or app relaunch.
7. Trace dense-ink performance.
   - Measure baseline writing latency on a normal page, a dense rewrite-ink page, and a page undergoing frequent sync/persistence updates.
   - Reproduce with a page that has substantial rewrite ink before writing chords.
   - Reproduce with the same page while erasing free-write ink.
   - Compare live Pencil latency against `editor.canvas.draw`, layout, persistence, recognition, and telemetry timing.
   - Check whether persistence is serializing full drawings too often or invalidating the full chart during active stroke input.
   - Separate canvas draw cost, eraser hit-testing cost, layout cost, persistence cost, recognition cost, and telemetry enqueue/upload cost.
   - Verify sync/write-back work is coalesced off the live Pencil movement path wherever possible.
8. Investigate root and accidental-spacing issues through evidence.
   - Pull the current iPad trace after a failing `G`/`B` pass.
   - Pull a current iPad trace where a flat, sharp, natural, or qualifier is written slightly farther from the base note and registers as a different note.
   - Check local chord draft preview diagnostics for top glyph candidates, root construction, grouping route, final action, and trust state.
   - Check telemetry failure buckets if the installed build emits them.
   - Distinguish target grouping, accidental glyph classification, accidental-to-root attachment, parser grammar, candidate scoring, and preview replacement.
   - Do not tune `G`/`B` or accidental-spacing heuristics until the failure class is known.
9. Redesign Rhythm Section Measures-tool parity with Simple Sheet.
   - Inventory every Simple Chord Sheet Measures-tool command and identify the shared contract that should also apply to Rhythm Section.
   - Define Rhythm Section-specific rules for resize, Even Row / equalize row, Join Measure, system breaks, measure insertion/deletion, and repeat boundaries.
   - Hold row/system geometry stable during active resize so the release position matches the preview instead of surprising the user.
   - Preserve beat/slot authority for chords and rhythm content when measure widths change.
   - Implement Even Row / equalize-row behavior for the selected Rhythm Section row without changing unrelated rows or upstream systems.
   - Define which adjacent Rhythm Section measure pairs are safely joinable.
   - Preserve chords and rhythm-map timing by remapping beat positions into the joined measure or refuse the join with clear behavior when remapping would be unsafe.
   - Preserve or deliberately resolve barlines, repeat boundaries, endings, section labels, cue text, roadmap anchors, and below-measure freehand attachments.
   - Add Join Measure to the Measures tool only when a valid adjacent target exists.
   - Keep all measure operations undoable and deterministic.
10. Add focused regression coverage.
   - A layout test proving first-system Rhythm Sheet staff lines remain drawable after a repeat sign is added to the first four bars.
   - A page-layout test proving a 32-measure Rhythm Sheet keeps fixed page height and either packs/paginates within valid page bounds.
   - A PDF/export test proving large-measure-count Rhythm Sheets export as real pages rather than one elongated first page.
   - A rendered chord edit test proving Rhythm Sheet edit boxes match slot-rendered chord bounds closely enough to edit the intended symbol.
   - A Simple Sheet chord-drag test proving the third chord in a three-chord measure can move to the fourth beat when the green placement preview indicates that target.
   - A resize persistence test proving manual chord-size changes either persist intentionally or are disabled/explained instead of visually snapping back.
   - A tool-switch persistence test proving saved ink does not move when switching between chord, rhythm, freehand, selection, repeat, and measure tools.
   - An erase persistence test proving deleted free-write strokes do not reappear after tool switches, saves, reloads, or erase-to-empty paths.
   - A dense-ink performance regression test or instrumentation fixture that bounds persistence/layout churn during active writing and erasing.
   - Root-specific recognizer tests only after a real `G`/`B` failure trace identifies the failing layer.
   - Accidental-spacing recognizer tests only after a real device trace identifies whether the failure is grouping, accidental attachment, or candidate scoring.
   - Boundary tests proving a legitimate spaced flat/accidental attaches to the base note while adjacent independent roots remain separate.
   - Model and layout tests proving Rhythm Section resize does not unexpectedly mutate later measure beat placement or upstream staff/system rows.
   - Model and layout tests proving Rhythm Section Even Row / equalize-row produces stable selected-row spacing.
   - Model and layout tests proving Rhythm Section Join Measure preserves supported content and refuses unsafe content.
   - If drift depends on page/system geometry, add a fixture that changes layout and asserts expected coordinate anchoring.
11. Validate on device before release.
   - Install the patch build on the iPad.
   - Create a 32-measure Rhythm Sheet and verify the first page stays at normal paper height.
   - Verify overflow measures are packed/paginated according to the chosen contract.
   - Recreate the four-bar first-staff repeat case.
   - In Simple Sheet, create a three-chord measure, drag the third chord to the final beat, and confirm release persists the fourth-beat placement.
   - Select and resize multiple rendered Rhythm Sheet chords, including first-beat-slot chords.
   - Resize Rhythm Section measures across first, middle, and row-end positions and verify preview/release match.
   - Use Even Row / equalize row on Rhythm Section and verify only the intended row changes.
   - Join adjacent Rhythm Section measures through the Measures tool and verify the resulting notation, chords, repeats, and ink placement.
   - Recreate a dense rewrite-ink page and write chords while monitoring trace/performance output.
   - Erase dense free-write ink, including partial erases and erase-to-empty, and confirm deleted strokes do not return during tool switches or after save/reopen.
   - Recreate the `G`/`B` root-recognition cases from the pulled trace.
   - Recreate the spaced-flat/accidental cases from the pulled trace.
   - Switch through the affected tools repeatedly.
   - Close/reopen the chart and confirm staff lines plus ink positions are stable.
   - Export a PDF and compare editor/PDF placement.

## Guardrails

- Do not change chord recognition, OCR, Scribble, parser, compendium, or chord trust thresholds for this patch.
- Do not introduce broad system/measure anchoring until the current drift mechanism is proven.
- Do not make Rhythm Section measure splitting broader unless committed rhythm maps, cue text, roadmap markers, repeats/endings, and freehand attachments are explicitly handled.
- Do not optimize performance by weakening persistence guarantees or dropping user ink.
- Do not optimize erasing by skipping authoritative delete persistence or allowing stale saved drawings to merge deleted strokes back into the canvas.
- Do not improve flat/accidental spacing by globally widening chord grouping in a way that merges adjacent independent roots or reintroduces `C D` to `Cb`-style failures.
- Do not fix oversized edit boxes by abandoning the placement-slot rendering contract or reintroducing free-position chord layout drift.
- Do not treat green drag preview as acceptance unless the released chord persists and re-renders in the same beat slot.
- Do not implement Rhythm Section Join Measure by silently dropping rhythm maps, chords, repeats, cue text, roadmap anchors, or attached ink.
- Do not widen committed Rhythm Section measure splitting as a side effect of adding join behavior.
- Do not claim Simple Sheet parity if Rhythm Section resize still changes upstream systems, later beat placement, or unrelated row widths unexpectedly.
- Do not allow starting-measure count or automatic system wrapping to stretch the physical page height.
- Do not regress the existing true Add Page behavior while fixing automatic pagination.
- Do not use aggregate telemetry as chord-specific proof unless the installed build actually emits the relevant failure buckets.
- Do not treat simulator success as physical Pencil acceptance. The final acceptance surface is a fresh physical iPad pass.

## Acceptance Criteria

The next patch can close this issue only when:

1. Rhythm Sheet first-system staff lines remain visible after adding a repeat sign across the first four bars.
2. Clef, key signature, repeat marks, measure lines, staff lines, chord lane, and rhythm area remain visually coherent in the same system.
3. A 32-measure Rhythm Sheet keeps fixed page height and uses valid measure packing or pagination instead of elongating the first page.
4. Add Page remains a true separate-page action and is not required to repair initial invalid page geometry.
5. Rendered Rhythm Sheet chord edit boxes align with the visually rendered chord and its intended beat slot.
6. In Simple Sheet, the third chord in a three-chord measure can be dragged to the fourth beat and remains there after release, redraw, save, and reopen.
7. Manual chord-size adjustments do not snap back unexpectedly across repeated chords.
8. Rhythm Section measure resizing has stable preview/release behavior and does not unexpectedly mutate upstream systems or later beat placement.
9. Rhythm Section Measures includes Even Row / equalize-row behavior for the selected row.
10. Rhythm Section Measures includes a Join Measure command for valid adjacent measures.
11. Join Measure preserves supported Rhythm Section content or refuses unsafe joins without silent data loss.
12. Handwritten ink does not shift when switching tools.
13. Erased free-write ink does not reappear after tool switches, chart save, close/reopen, app relaunch, or erase-to-empty.
14. Saved ink stays aligned after save/reopen and app relaunch.
15. Ink writing latency is acceptable on normal and dense pages, with sync/persistence work kept out of the live Pencil path where possible.
16. Dense rewrite-ink pages remain responsive while writing and erasing, with performance evidence separating draw, eraser hit-testing, layout, persistence, recognition, and telemetry cost.
17. `G` and `B` root failures are either fixed or classified as confirmation-gated/unsupported without confident wrong renders.
18. Flats, accidentals, and attached chord qualifiers tolerate realistic spacing from the base note without merging adjacent independent root letters.
19. PDF export agrees with the editor for the affected chart.
20. The fix is backed by focused tests plus physical iPad verification.

## Telemetry Snapshot: 2026-09-05 21:32 PT

Source: production Supabase `public.telemetry_events`, filtered to iChart `1.2.1` build `51`, `iPadOS`, last 12 hours. This is aggregate telemetry only. It does not include raw handwriting strokes, raw chord text, chart titles, names, emails, or support content.

Device/container state:

- A local device-discovery read identified a paired test iPad; its private device identity is omitted from this archival copy.
- `xcrun devicectl device info apps --include-all-apps --bundle-id com.ichart.app` reported installed `iChart` version `1.2.1`, build `51`, `Developer App = false`.
- A read-only `devicectl device copy from --domain-type appDataContainer --domain-identifier com.ichart.app --source 'Library/Application Support/iChart'` failed with `ContainerLookupErrorDomain error 3`.
- Therefore the current public install did not expose local debug JSONL files or `performance-trace.jsonl` through `devicectl`. Production DB telemetry was the only available source in this pass.

Production upload state:

- Last 12 hours for build `51` had 586 events from 2 installations and 3 sessions.
- The latest received production event was `2026-09-06 02:42:16Z` / `2026-09-05 19:42:16 PT`, about 1 hour 50 minutes before the query. Current just-written activity may still be queued or otherwise not represented in production telemetry yet.
- The most recent installation group (`iPad13,10`) showed 22 events, including two chart-created flows, but 0 chord events, 0 ink events, and 0 cloud events.
- The connected-iPad model group (`iPad13,2`) showed 564 events, including 178 chord events and 263 ink events. Its latest received event was `2026-09-06 01:24:57Z` / `2026-09-05 18:24:57 PT`.

Corroborated from production telemetry:

- A Rhythm Section chart setup completed with `measure_count = 32` at `2026-09-05 16:38:48 PT`.
- Later Rhythm Section editor events showed `measure_count = 33` starting at `2026-09-05 17:34 PT`, consistent with the report that Add Page added an extra measure after the original 32-measure page state.
- The connected-iPad group logged 247 `ink.persisted` events: 145 chord-scope and 102 page-scope.
- The same group logged 16 `ink.coordinate_space_reprojected` events.
- During the 32-measure Rhythm Section pass, page-scope coordinate reprojection repeatedly changed page-height frames, including `1584 -> 1752`, `1752 -> 1584`, and `1752 -> 1752`; chord-scope reprojection later mapped `1752 x 724` into `1188 x 596`.
- During the 33-measure post-Add-Page state, page/chord reprojection included `2944 x 724 -> 2944 x 724`, `2944 x 724 -> 1864 x 596`, and `2944 x 724 -> 1248 x 724`.

What this supports:

- The 32-measure / 33-measure sequence matches the user's page-bounds/Add Page report.
- The coordinate-space reprojection events match the class of "ink shifts when tool/layout state changes." They do not prove the exact visual shift, but they show the app is actively transforming saved ink between changing coordinate frames during the affected workflow.
- The high count of `ink.persisted` events and repeated reprojection make local persistence/canvas sync a plausible contributor to perceived ink heaviness. Production telemetry does not yet expose enough timing detail to prove this as the direct latency source.

What this does not prove:

- Production telemetry does not currently expose raw chord text or raw strokes, by design.
- The build `51` chord preview rows did not contain the newer issue-bucket keys such as `issue_count`, `root_issue_count`, `root_accidental_issue_count`, or `quality_issue_count`; rows-with-those-keys were 0 for both Rhythm Section and Simple Sheet preview telemetry.
- Therefore this production query cannot corroborate the current `G`/`B` root failures or the spaced-flat/accidental issue. Those still require a current DEBUG device trace or a later build that ships the aggregate issue-bucket telemetry.
- No recent `cloud.push_*` or `cloud.restore_*` events appeared in this filtered build-51 telemetry, so "sync state" currently points more strongly at local ink persistence/canvas sync than cloud sync unless cloud telemetry is missing or delayed.

Recognition timing seen in production telemetry:

- Rhythm Section `chord.preview_updated`: 77 preview events, 91 payloads, 82 matched, 67 trusted, 24 confirm, 9 no-read/unresolved. Median recognition time was about 4.49 ms, p95 about 40.27 ms, max 261.09 ms.
- Simple Sheet `chord.preview_updated`: 73 preview events, 141 payloads, 134 matched, 110 trusted, 31 confirm, 7 no-read/unresolved. Median recognition time was about 5.34 ms, p95 about 15.63 ms, max 20.68 ms.
- These recognition times do not explain broad Pencil drag by themselves. The stronger suspicion remains persistence, canvas drawing, layout invalidation, eraser hit-testing, or coordinate reprojection work.
