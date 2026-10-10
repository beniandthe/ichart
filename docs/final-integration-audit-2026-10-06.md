# Final integration audit — 2026-10-06

Scope: the existing Simple/Rhythm app flow, ink/layout/export integrity, and
destructive-action safety. This is not a recognition study, security sweep,
billing change, GitHub push, distribution archive or publication authorization.
Keep research parked and preserve existing user data.

Active tree: `codex/app-release-normalization` in
`/Users/benirossman/.codex/worktrees/app-release-normalization/Smart Chart`.
Installed starting candidate: Development Debug **1.2.1/73**.
Delivered candidate: Development Debug **1.2.1/74**, installed and launched on
the physical iPad. Overall physical workflow accepted by the user on 2026-10-07;
see the acceptance record below for the evidence boundary.
Receipt directory: `/private/tmp/iChartFinalIntegrationAudit-20261006.IMApTd/`.

## Findings and verification

| Check | Current evidence | Status |
| --- | --- | --- |
| Dirty chord ink → rotate → add stroke → save/reopen | Real native canvas-owner tests reproduce the old stale width and pass with the scoped coordinate handoff repair in both styles | Automated repair verified; covered by overall user acceptance |
| Ordinary long/two-line performance cues | Wrapped text measurement and PDF drawing share the same bounds; independent raster inspection confirms all endings in both styles/fonts | Clipping and below-cue/stem contact repaired; overall user acceptance recorded |
| Clear Draft Ink with retained drawing but empty preview | Native mounted EditorView controls pass for no ink, represented preview and retained sub-threshold ink | Shared eligibility repaired; overall user acceptance recorded |
| Chart/PDF deletion and setlist source preservation | Read-only review found immutable confirmation targets and transactional PDF staging/rollback; store/runtime regressions executed | No additional defect established; individual destructive touch steps not separately reported |

`InitialRegressions.xcresult`: **3 executed, 0 passed, 3 failed, 0 skipped**,
verified with `xcresulttool`. One method exercises dirty rotation in both styles;
two methods exercise long and multiline cue export in both styles. The failing
test/PDF receipts are retained separately from any eventual passing gate.

`ClearAvailabilityBaseline.xcresult`: **3 executed, 2 passed, 1 failed, 0 skipped**.
The failure is the retained-ink/no-preview state, not an accessibility harness
failure: both the no-ink negative control and preview-present positive control
passed. The new eligibility keeps destructive confirmation unchanged and does
not claim recognition admitted the tiny drawing.

`TargetedRepairs.xcresult`: **11 passed, 0 failed, 0 skipped**. These cover the
three reproduced fixes, active-tool/repeated rotation, cue typography and
above/below stacking/page clearance. Independent raster inspection of all eight
cue exports confirmed the endings, but exposed an older below-cue/stem contact:
the quarter stems end at staff bottom +10 while the cue frame starts at +5.
The cue repair was extended narrowly to reserve actual notation paint bounds,
not just the staff rectangle.

The first broader snapshot (`AppFullVerified.xcresult`) reports **2,240 passed,
0 failed, 103 skipped / 2,343 total**. Its skips are 48 opt-in full historical
ink fixtures, 16 provided saved-state/device replays, 37 personalization
research/runtime replays and 2 live backend tests. Core editor, deletion and
setlist regressions executed. This snapshot precedes the final notation-clearance
repair and is not the final delivered-source gate.

The first SwiftPM attempt did not compile because the width-reset policy was
located in the package-excluded editor folder. That unchanged model/layout
operation was moved to Services. The subsequent `swiftpm-verified.log` executed
**1,689 cases: 1,599 passed, 1 failed, 89 skipped**. Its single failure exposed a
non-UIKit natural-width estimate derived from an already-clipped slot. That
fallback repair preserves natural size across viewport widths, matching the
native contract; the test was retained without weakening its assertion. This
failed receipt remains separate from the passing final rerun.

The notation-clearance extension reserves the actual painted note/stem/flag/beam
bounds for below cues, retains manual offsets, and does not change the requested
cue font or scale. The final native cue export test covers both styles, both
fonts, ordinary long cues and explicit newlines. Eight exported PDFs were
independently rastered; the four Rhythm PDFs were inspected again after the
stem-clearance extension. All endings are present and text clears the notation.
A single cue taller than a page is not split into a new multi-page text flow.

`AppDelivery.xcresult` retained **2,240 passed, 1 failed, 103 skipped**. The single
failure was the new test comparing regenerated note UUIDs between independent
layout passes; geometry and musical fields matched. The test now normalizes only
those generated IDs and still compares every other note field and bound.
`swiftpm-delivery.log` retained **1,598 passed, 2 failed, 89 skipped**: the old
height-based width floor still reserved excess horizontal space for short
chords. Its removal is confined to the non-UIKit natural-width fallback; native
font measurement is unchanged. The corrected shared-layout gate executed
**136 tests, 136 passed, 0 failed, 0 skipped**.

`AppFinalDelivery.xcresult` subsequently reports **2,241 passed, 0 failed,
103 skipped / 2,344 total**, verified with `xcresulttool`. The final frozen-source
gate, after the last non-UIKit-only edit, independently passed:

- `AppFrozenFinal.xcresult`: **2,241 passed, 0 failed, 103 skipped / 2,344 total**.
  Command exit 0; summary and actual skipped test-case nodes checked with
  `xcresulttool`. This is the final native gate, not the earlier snapshot.
- `swiftpm-frozen-final.log`: **1,600 passed, 0 failed, 89 skipped / 1,689 total**,
  full SwiftPM command exit 0 and nonzero XCTest execution verified.
- `device-frozen-final.log`: signed iOS Development Debug build passed. The
  preserved artifact is `PreservedFinalApp/iChart.app`, **1.2.1/74**. Strict deep
  code-signature verification passed; the normal bundle contains no comparison
  model, research-study app, or private profile/journal resource. This is not a
  distribution archive or App Store signing result.
- `release-audit-final-source.sha256`: 1,163 source/test/resource/config files;
  `release-audit-final-project.sha256` separately binds the generated project
  and resolved dependencies. Both verification commands passed after building.
  `final-device-executable.sha256` binds the preserved executable.

Shared SwiftPM skips are 48 historical ink fixtures, 5 provided saved-state/
trace replays, 34 research/profile/runtime checks and 2 live backend tests.
Native skip categories remain those recorded above. No core editor, delete or
setlist case was silently skipped. Live cloud and research results are not
implied by these ordinary app suites.

## Delivery and preservation

Build **1.2.1/74** was installed from the preserved, signature-verified artifact
and launched through CoreDevice on the physical iPad. The install and process
launch commands each completed successfully; neither is a Pencil acceptance
test. No commit, push, distribution archive, upload, billing or production
telemetry deployment was performed in this audit.

Immediately before installation, `BeforeInstallFinalSupport` captured the
existing Application Support data: **5 charts, 49 deletion records, 11 PDFs,
1 setlist and 70 handwriting examples**. The earlier pre-install backup is
also retained. `AfterInstallSupport` contained the same 19 files with identical
bytes and no additions or removals.

`AfterLaunchSupport` retained all chart fields and saved ink, PDFs, setlists,
deletion records and handwriting profile exactly. Changes were confined to
entitlement refresh, clearing `selectedChartID`, and the performance trace.
No saved-ink reencoding exception or equivalence waiver was needed for this
candidate. The content-free comparisons are retained as
`after-install-preservation.jsonl` and `after-launch-preservation.jsonl` alongside
the read-only backups. No existing library item was exercised destructively.

## Bounded physical acceptance

On **2026-10-07**, after receiving the build-74 physical checklist, the user
reported: “ok i think that clears the physical gaps”. Record this as overall
user acceptance of the delivered workflow and close that physical workflow gate.
It is not an instrumented observation, a per-step execution log, an accuracy
measurement, or release approval. In particular, do not claim all nine scenarios
below were individually observed or that destructive touch checks were separately
confirmed. Keep the checklist as a reproducible reference; do not start another
open-ended recognition or UI iteration solely because acceptance was concise.

Use only disposable local charts and exports named **Audit A**, **Audit B** and
**Audit C**. A is Simple, B is Rhythm; C is an unselected survivor/control. Do not
delete existing charts or PDFs to conduct this audit.

1. In A and B, write two draft chords. Correct one with Scribble and the other
   with keyboard, scroll between rows, return to writing, reopen review and
   render once. Check edited text, retained ink and no duplicate rendering.
2. With another two-draft batch, rewrite only one target and verify the other
   target's ink/text survive. Move a rendered chord off-grid, compress its width,
   Reset Width, save/reopen and compare the exported PDF. Height and musical
   values should not change.
3. Leave pending ink in portrait, rotate while staying in Write & Render, add
   another chord, leave/reopen in landscape, then render/export. Check both old
   and new writing for movement, stretching, loss or changed measure targeting.
4. On one dense page, check visible Pencil latency, erasure/palm handling,
   portrait/landscape, key change, repeat/setup staff lines, long header/cue,
   margins and coda/form-marker size. Check both fonts and dark/light appearance
   in chart/setlist/PDF reader; export should retain light paper.
5. Export A, B and C. Add a disposable setlist containing **C, A, C**.
6. On C, keep rendered notation and Free Ink, add pending draft ink, then use
   Clear Draft Ink → Cancel and subsequently Confirm. Only pending draft ink
   should disappear after confirmation; save/reopen to verify.
7. Select only charts A and B, cancel deletion once, then confirm. Reopen and
   verify C survives and all three exported PDFs still open.
8. Select only PDFs A and B, cancel once, then confirm. C's PDF and editable chart
   must survive. In the setlist, the missing A entry should remain unavailable
   and skippable between the two C entries in either direction.
9. Remove the missing setlist entry and delete the disposable setlist. C's source
   PDF should still open. No other library item should have changed.

## Exit rule

Fix only reproduced blockers and verify the frozen final source with the full
native and SwiftPM suites, nonzero counts and explicit skipped-test reasons.
Record physical acceptance separately from tests/install/launch. Entitled cloud
backup/restore, current-candidate production telemetry, distribution mechanics
and the free-month decision remain in the existing release gates. Do not restart
an open-ended feature or ML cycle.
