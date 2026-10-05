# Confirmed symbols from saved chord handwriting

This advances the optional personal learning loop, not an alternate recognition
engine. It does not establish improved recognition accuracy or replace live
recognition with the development ML model.

## Why this is needed

The current ML symbol learner consumes explicitly labeled glyph examples.
Whole-chord corrections previously supplied only the separate whole-chord
ranker; a saved `D7` did not automatically teach its final `7` shape. Inferring
all individual labels from a chord string would turn a segmentation error into
bad training data.

## App flow

Open **My Handwriting → Review Saved Examples → a whole chord → Teach Symbols**.
The screen shows the original saved ink and proposed symbol pieces. Each menu
starts with **Choose symbol…**. Label only pieces containing one complete
symbol; leave merged or incorrectly cut pieces unselected. Tap **Teach N
Symbols** to save the explicit selections. Opening or leaving the screen does
not teach anything. Existing setup remains available for shapes that cannot be
separated safely.

The receipt reports the example count before and after saving. Saving teaches
the ordinary local profile, so these glyphs are available to the existing
personal layer and to subsequent development ML comparisons. This is not
end-to-end sequence-model training or automatic labeling of whole corrections.

## Preservation and learning boundaries

- Grouping proposes pieces, never their labels. Every original saved stroke
  must appear once, with the same point coordinates. Existing saved examples
  are normalized/bounded profile data, not original page-space captures.
- All selected labels are validated before learning on a value copy. A stale
  source, reset, opt-out, invalid selection, or capacity eviction of the source
  rejects the edit. No partial set of labels is saved.
- The store commits on the existing background queue. Active chart-test
  capture is checked before queueing and again at edit time; the run retains
  its separate frozen profile. This is not a cross-store transactional lock.
- Whole-chord ink is retained. New symbols record source-example and stroke
  indexes; duplicate standalone lessons retain their existing provenance.
  Removing a whole chord does not remove independently confirmed glyphs.
- Optional provenance decodes with old profiles. Current profile, chart ink,
  historical test labels/scores, and old frozen profiles are not silently
  migrated or retroactively taught.
- The trained Core ML reader remains optional Debug comparison-only. No new
  engine, acceptance threshold, automatic rendering, cloud training upload,
  or production dependency is introduced.

## Verified locally

Worktree `recognition-generalization-reset`, branch
`codex/recognition-generalization-reset`, base HEAD `160aa31` plus the existing
uncommitted recognition work. Source project regenerated with XcodeGen.

- **24 SwiftPM tests passed**, covering symbol teaching, learned-model
  composition, and the teaching catalog. A controlled encoder proves a
  confirmed symbol reaches the learned reader while the generic read stays
  unchanged. It is wiring evidence, not measured handwriting accuracy.
- **67 iOS Simulator tests passed, 0 failed, 0 skipped**, confirmed with
  `xcresulttool`. Includes 29 project-configuration tests, the 24 model tests,
  10 existing editor/profile tests, and 4 new symbol-teaching editor tests.
- **3 additional iOS tests passed, 0 failed, 0 skipped**: the actual bundled
  Core ML model loads and produces valid features, and the comparison model
  preserves frozen profiles/reports and respects opt-out. This is runtime and
  learning-boundary evidence, not an accuracy score.
- New editor tests exercise persistent reload, unchanged source/historical
  journal bytes, active capture, and reset/opt-out after opening stale UI.
- Actual SwiftUI screen attachments were inspected at 820×1180 and 1180×820.
  Original ink, piece previews, menus, and disabled-until-selected Teach
  control are visible in both orientations. This is not a complete interactive
  app navigation or physical Pencil acceptance test; the Simulator app session
  is signed out.
- The current physical-device profile and journal were backed up before device
  preparation. The profile still contains 12 glyph and 18 whole-chord examples.
  No real handwriting labels were selected or taught by the agent.

Evidence directory: `/tmp/iChartSymbolTeaching-20260928.HUDfIj/`.
`focused-01.xcresult` and `ios-summary-01.json` contain the iOS test evidence;
`attachments/` contains the inspected portrait/landscape renders. Private
profile backups remain outside the repository.

## Device preparation, not installation

The paired wired iPad was visible to CoreDevice and Xcode with Developer Mode
enabled. The Debug device build reached CodeSign, which failed with
`errSecInternalComponent`. The generated app is unsigned; no new app was
installed or launched on the physical iPad. A signing-identity check found
three valid identities, while a read of the login-keychain settings failed
with an authentication error. No credentials were read, supplied, or changed.

The prepared device bundle contains the same pinned development comparison
manifest (`d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1`).
`device-build-01.log` records the signing failure. The current-device profile
and journal backups exactly match the previously preserved evidence hashes;
their contents were not changed during this pass.

## Still required

Verify installed-device navigation and menu/save behavior; run genuinely fresh
complete chords in both chart styles with frozen pre-test profiles. Compare
the shared and personalized model on identical inputs, count regressions and
no-reads, and keep replay separate from new handwriting. New-writer evidence
is still required before claiming generalization or ship readiness. Do not
promote the known-regressing research model variants based on this UI work.
