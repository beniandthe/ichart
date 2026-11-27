# FIX-046: mixed writing at normal pace

## Scope and evidence

Baseline: `46d818d56c4716bdb73713fd5bb87b89020d8d50`, accepted local Build 203.
The reported symptoms are barlines becoming chord input, missing chord reads,
and retained ink with an unexplained progress indicator during faster mixed
writing. The supplied screenshot predates the paper-layout changes. Its
original draft was subsequently edited and cleared, so it cannot establish an
exact reproduction on the current build.

Retained source handwriting matching the screenshot passage was recovered
locally from saved chord archives. The erased original barlines and failed
draft census were not recovered. Any replay combining that handwriting with
reconstructed dividers is labeled accordingly; private source is not included
in this repository.

## Reproduced boundaries

- Each drawing change canceled serialization/preparation, while automatic
  rendering required a complete census at the latest whole-drawing revision.
  A deterministic shipping-Editor test held real preparation while later
  handwriting continued. The earlier completed chord failed to progress.
- A lane-spanning line inside the existing 18-degree angle allowance could
  fail the separate width rule and enter chord targeting. A modestly wavy
  divider could lose ownership when a second distinct neighboring root arrived.
  Both cases failed with the real preparation path in both paper chart styles.
- A steep supported chord-repeat slash overlaps barline geometry. The safety
  test failed before the ownership protection, while completed B/D/F stems and
  an actual double barline with same-side dots remained negative controls.

## Repair boundaries

Keep one immutable preparation pass in flight and drain the newest source.
An older pass may advance only a verified unchanged leading portion; it never
becomes authority for the whole newer drawing. Current-source validation uses
ordered stroke identity, including paths, timing, masks, transforms and seeds,
rather than trusting a delegate revision alone. Partial commits retain every
newer source stroke, require rightward separation or a verified later writing
row, and revalidate source ownership and layout before synchronous consumption.

Do not replace canvas ink during an active Pencil stroke. Old serialization
must not overwrite newer resident ink. Canceled generations, source edits,
layout changes and user corrections invalidate the appropriate old work.
Existing recognition trust rules and writing/maturity timers remain unchanged.
A paper transaction includes completed chords through its selected closing
boundary. Earlier mature boundaries may form a joint transaction while a newer
boundary retains its own full grace; approved complete ending spans keep their
existing selection priority.

Barline geometry retains the existing angle limit and requires full-lane
coverage and proven complete unmasked original strokes for its wider allowance.
The old strict and rendered-chord-gap mask behavior remains supported.
Compound identity uses the owned group time origin rather than the whole
drawing origin, preserving exact points and inter-stroke intervals. Supported chord-repeat ownership and chord
stems must remain intact. Retired handwritten bar-and-dot range repeat ingestion
is not restored.

Feedback exposes existing retained-source/placement reasons and identifies
saved handwriting without claiming an active read. The existing feedback area,
optional correction action and tool layout remain. Quick guidance and How To
describe mixed writing consistently; no new pause, modal or confirmation step
is introduced.

## Verification record

Private local receipts: `/private/tmp/ichart-fix046-natural-writing-20261127/`.

- `structure-red.xcresult`: 4 executed, 3 failed, 1 passed, 0 skipped. The
  slash-bass control initially compared equivalent B/C-flat spellings; its
  criterion now also uses an isolated-reader control and independent pitch and
  quality expectations. The slanted/wavy source-ownership failures were real.
- `cadence-red.xcresult`: 1 executed, 1 failed, 0 skipped. The earlier completed
  chord was absent during continuous later input.
- `percent-safety-red.xcresult`: 6 executed, 5 passed, 1 failed, 0 skipped. The
  original slanted/wavy cases passed; the added steep-percent safety case failed.
- Portable production-reader/parser regression run: 315 executed, 4 optional
  full-fixture archive replays skipped, 0 failures. This does not exercise UIKit
  scheduling.

Additional intermediate findings:

- The first combined native run exposed a structural transaction using the
  first selected barline to exclude completed interior chords. That selection
  now uses the closing boundary. Both the held-Pencil and slow-preparation
  continuous-writing workflows passed after that repair.
- A later current census exposed a separate mature-pair selection failure
  when a third boundary was still young. Its focused rerun is pending.
- The Manual workflow test initially picked Render Chords by native-tree
  order when Review & Render was also available. The toolbar intentionally
  supports independently ready notation. The test now selects the complete
  existing review route, without changing production toolbar behavior.
- Affine test drawings compared before and after PencilKit serialization
  produced exact-source mismatches. Fixture expectations now use indexed
  strokes from the same canonical persisted drawing. No production identity
  guard or comparison tolerance was changed.
- The first opt-in private replay found equal whole-row and isolated labels
  across four contexts, but some isolated labels differed from ground truth.
  The revised diagnostic reports unscaled original, relocated isolated and
  whole-row answers separately. Accuracy misses remain recorded as diagnostic
  limits, separate from exact ownership and context-invariance assertions.

- `mature-compound-reanchor.xcresult`: 9 executed, 9 passed, 0 skipped.
  Includes the mature boundary pair, unchanged double-bar subset, changed
  point/time rejection controls and existing retained-split contracts.
- `private-canonical-replay.xcresult`: 1 executed, 1 passed, 0 skipped; four
  style/layout contexts. All 32 target source checks use canonical persisted
  fragments, and every whole-row answer matches the corresponding isolated
  answer. The original unscaled row reads 7/8; B-minor has no match. Relocated
  Simple reads 7/8; relocated Rhythm reads 6/8 because A-minor becomes E even
  in isolation. These accuracy limits are recorded, not asserted away as fixed.
- `broad-native.xcresult`: 315 total, 308 passed, 6 failed, 1 skipped. Four
  failures were old full-census/reader-start assumptions; their replacement
  checks require exact source conservation and prevent duplicate commits.
  The actual masked-fragment targeting and barline-feedback regressions were
  repaired; existing bitmap-erased acceptance tests remain unchanged.

## Source-freeze verification

- `final-combined-native.xcresult`: 317 total, 316 passed, 0 failed, 1 optional
  private-source feedback test skipped. Covers both chart styles, current
  paper and legacy layouts, Automatic and Manual, slow preparation, held Pencil,
  mature barline subsets, edited/masked/erased source, pending suffixes,
  drawing-before-delegate races, exact consumption and save/reopen, existing
  structural/endings/retained-split contracts and tool guidance.
- The last intermediate run passed all production/source assertions but
  checked a held A reader before waiting for it to start. The final test adds
  that start condition inside the existing 0.95-second bound; held-reader and
  exact source assertions remain. Application code and timing did not change.
- `device-build.xcresult`: local development build succeeded as 1.9.4 (204).
  Build number 204 is an explicit Xcode build override; baseline `project.yml`
  remains unchanged. The staged artifact passes strict deep code-signature,
  bundle/version, team, development entitlement and connected-iPad profile
  checks. Its application source matches the final native snapshot exactly.

Local code/test manifests, signed artifact and receipts live in the private
receipt directory above. The prepared stopped-app backup/install/readback
workflow is at `.build/device-backups/2026-11-27-fix046-natural-writing-build204`.
Its eventual `final-summary.json` and preservation receipts record the device
result separately from this source freeze. A fresh saved-work confirmation is
required before stopping the iPad app. Physical Pencil acceptance remains open;
no source review, automated replay or install receipt proves broad handwriting
accuracy or the original erased failure sequence.
