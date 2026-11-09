# Consecutive library chart deletion — FIX-018

Reported November 7, 2026 on iChart 1.2.4 (151). The user chooses **Delete** from
the chart row's three-dot menu. The first chart deletes; the next chart's
confirmation does not appear. Opening a chart and returning permits another
deletion. This is a confirmation presentation failure, not a report that a
confirmed deletion was lost.

## Scope and source evidence

The Build 151 source is preserved in a local file/hash snapshot before this
change. Its chord-drag runtime, geometry, tests and helper changes remain intact.
The only shared file touched again is `LibraryView.swift`.

Previously the library drove deletion through an optional request projected into
a Boolean alert binding, followed by a separate error alert on the same host.
That reset cleared the current request without identifying which presentation
was dismissing. The chart store itself has no first-deletion lock and resolves
the requested IDs afresh.

The candidate uses one item-based presenter for deletion and errors. Every item
has a unique identity. A dismissal for an older item cannot clear the next
request. Confirm and Cancel retire that exact item; the destructive action
retains the immutable confirmed IDs and retires its presentation before removing
the source row.

The chart/PDF store mutation, cloud tombstone rules, selection scope, saved
formats and editor behavior are unchanged. Existing confirmation text, Delete,
Cancel and error wording are reused. The three-dot menu, context menu and bulk
Select entry points still lead to the same confirmation. Guidance was checked
against those controls; this repair does not introduce a new gesture or recovery
step.

## Evidence boundaries

Before the repair, two external-process Simulator UI tests passed: consecutive
Rhythm/Simple row deletion, and cancellation then retry after a prior deletion.
They exercise real three-dot menus and exact chart names in each alert, not
direct store calls. This does **not** reproduce or disprove the iPad report.

Candidate checks include identity/dismissal ordering, immutable target ownership,
repeated error identity, current persistence/store regressions, and actual-app
menu tests across both chart styles. Additional UI cases cover editor return,
large previews in landscape, deletion to an empty library, bulk cancellation and
deleting only the selected rows. All fixtures are disposable Simulator charts.

Native results, signed artifact and any subsequent device installation are
recorded separately. No production chart is deleted as part of this task. Fresh
physical confirmation and consecutive-delete acceptance remain required.

## Library-only candidate checkpoint

Build 152 passed 118 focused native library/deletion/persistence/PDF checks and
four external-process Simulator UI walkthroughs, with no failures or skips in
those final gates. The UI cases include both chart styles, cancel/retry, exact
bulk selection, editor return, large previews and deleting to an empty library.

An earlier broader native run passed 150 of 152 cases. One case contained the
old selection implementation string; the selection assertion in the touched
library integration test was updated to the existing selection-scope policy and
passes in the final gate. The other case has eight stale help/gesture source
expectations, each independently confirmed to be false in the preserved Build
151 source too. That unrelated source-test debt is recorded locally; no product
behavior was changed to satisfy it.

The iPad candidate compiled and linked, then Xcode CodeSign rejected Finder
metadata in its generated product. A clean copy was signed with the same
generated entitlements, strictly verified, and archived. Bundle 1.2.4 (152),
entitlements matching 151 and the target device profile were verified. This
library-only artifact was **not installed**. The user reported the separate
repeat/tool-selection lockout before an installation handoff; the combined
candidate will include the ensuing tool repair and its own validation.
