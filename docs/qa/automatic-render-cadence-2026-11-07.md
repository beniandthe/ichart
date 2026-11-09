# Automatic Write & Render cadence — Build 154

Date: November 7, 2026. Docket: FIX-021.

Status: local repair tested in both chart styles; Build 154 installed in place
on November 8 after fresh saved-work confirmation and two matching stopped-app
backups. Direct saved-content checks passed before and after its first normal
launch. Fresh physical Pencil/cadence acceptance remains pending. No public push,
backend repair or release was performed.

## Problem and evidence

The user reports earlier chords remain handwriting while later chords are
written, then several render together after the whole passage stops. The user
confirmed that barlines or ending brackets are mixed into the sequence. The
saved rendering preference was Automatic.

The prepatch shipping-editor workflow used real PencilKit begin/change/end
callbacks, current-source preparation, the normal editor render scheduler and
a deterministic reader that can hold the next target unfinished. Ordinary
separate-measure chords and an ordinary row transition passed in both styles.
One original open measure containing F, an internal barline, then G and A failed
eight cadence/source-expectation assertions across both styles before eventually
batching after global idle. Separate policy tests reproduced unrelated
structure and overlapping-horizontal-position row holds.

The shared structural wait and row restriction predate Build 153; this does not
attribute their origin to the 153 selection/cache repairs. Growing preparation
cost was measured with synthetic buffers, but no physical iPad latency diagnosis
or recognition-accuracy claim follows from that diagnostic.

## Repair

- Independent completed chords can progress while unrelated structure remains
  pending. Verified different writing rows can complete older targets without
  mistaking a nearby raised or lowered suffix for a separate row.
- Each unchanged structural source receives its existing two-second grace from
  its first accepted current-source census. Later writing elsewhere does not
  restart that clock. Erasure, replacement, ambiguous ownership, disappearance,
  chart/mode changes and relevant scope/profile/options changes invalidate age.
  Archived stroke dates never create eligibility.
- Observation happens synchronously after census acceptance. A next Pencil
  stroke beginning before SwiftUI's queued render attempt cannot defer the
  mark's first observation. This race was reproduced in an intermediate
  candidate and fixed without lengthening the test's writing pause.
- The editor schedules the next future structural or final-chord deadline.
  Expired/refused deadlines do not poll. A ready preceding chord and an eligible
  barline can use one guarded transaction even while a later reader waits.
- A split keeps the original measure ID on its left. Exact retained right-side
  source is assigned a canonical destination anchor only after full fresh
  preparation proves one-to-one ownership and unchanged physical writing rows.
  Draft IDs, archives and explicit corrections remain attached to that source;
  a fresh collecting lifecycle prevents stale recognition authority.

Pen-down replacement, stale-census consumption, source-coverage relaxation,
suffix splitting, output/retained-ink collisions and mandatory new review stops
remain prohibited. Manual preview isolation and commands retain their original
behavior. Automatic helper, guide, Settings, accessibility, Quick Start and How
To copy describe progress between strokes and pausing for the final chord.
Existing conditional review recovery remains documented. `%` chord repeats
remain supported; retired bar-and-dot measure-repeat ingestion is not restored.

## Verification

- Explicit Xcode project generation and Simulator build-for-testing succeeded.
- All **28 focused tests passed**, including the formerly failing hosted-editor
  sequence in both styles, progression while the next reader waits, no mutation
  during a continuing Pencil stroke, the structure's own scheduled future wake,
  exact retained/saved source, and coder reopen checks.
- The broader selection executed **733 cases**: 726 passed, six optional local
  capture replays skipped, and one legacy help-source test failed eight stale
  assertions already documented against Build 153. Those assertions were updated
  to the current concrete UI/gesture implementation. A test-only rebuild and
  rerun of that one case passed. The final selected set therefore has **727
  passing cases and six optional skips** across those runs. Application source,
  resources and configuration stayed byte-exact during the test correction.
- Coverage includes Automatic rendering/readiness/feedback/placement/structure,
  current-source and continuation policies, Manual review/recovery, ending
  review, incremental orchestration, and the installed drag/selection/cache and
  library repairs. Native hosted views check guidance layout; synthetic reader
  tests do not establish physical handwriting-recognition accuracy.
- Device compilation/linking completed. Xcode signing encountered the known
  Finder-metadata restriction. A clean `ditto --norsrc` copy was stripped of
  unsupported extended attributes, signed with the existing development identity
  and generated entitlements, and passed deep strict signature verification.
  Version/build, unchanged Build 153 entitlements, target-device provisioning and
  unexpired profile were checked. Installation was completed separately below.

Build/test artifacts, immutable baseline copies, source pins, app manifest and
signed ZIP are under `.build/automatic-cadence-20261107`; detailed Xcode result
bundles and logs are under `/private/tmp/ichart-chord-drag-20261107`.

## Installation and saved-content readback — November 8

The candidate was reverified against its signed-file manifest and ZIP checkpoint,
then installed over Build 153. The two current stopped backups matched exactly:
70 files and 65,041,720 bytes. Both independent postlaunch copies also matched
exactly: 70 files and 63,806,502 bytes.

Prelaunch and postlaunch comparisons preserve all 18 charts, 366 source-ink
archives, 12 page-notation archives, one header archive, 22 PDFs, one setlist with
15 references, three correction/profile files and all 83 deletion records.
Musical content and source ink are unchanged. The retired 119-summary diagnostic
checkpoint remains byte-exact with its preexisting stale binding.

The postlaunch comparison separately validates two bounded cloud timestamps,
one preference clock, tombstone ordering, platform snapshots/cache bookkeeping
and a fresh technical queue transition. These observations do not establish
backend or telemetry-delivery health. Fresh per-file/snapshot/evidence bindings
are under `.build/automatic-cadence-20261107/install154-20261108`.

## Physical acceptance still required

On the iPad, write an ordinary passage with chords and internal barlines in Automatic
in each style. Completed earlier chords and eligible dividers should advance at
safe pen-up opportunities before the whole passage stops. Keep suffixes close;
verify no output appears over unfinished writing. Reopen the chart and inspect
the retained source and cleared consumed draft separately. Recheck Manual
previews and the installed selection/drag/library behavior. Do not mark physical
acceptance complete from Simulator or signing evidence.
