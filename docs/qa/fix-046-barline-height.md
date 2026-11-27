# FIX-046 follow-up: partial-height barlines

Base: `a967413760393eee0e28c4959a1d7edc4601f6cf`, accepted local Build 204.
The user reports improved mixed writing with a remaining chord/barline misread
and asks whether separator strokes must span the blue lane.

## Contract and reproduced failure

Ordinary up/down direction was already symmetric. The old ordinary rule
required 62% lane overlap and a 22-point minimum; a wider allowance needed
78% in an engraved gap or 88% outside it. A controlled half-lane test failed
in both styles, at upper/middle/lower positions, in both directions and with
single/double boundaries. The baseline four-method run had two failed methods:
96 assertions in the short-bar cases, plus an unrelated isolated slash-bass
reader miss. The negative control now distinguishes source preservation from
raw-reader accuracy; positive C/G expected answers remain strict.

A fresh running-app diagnostic copy retained nine pending strokes. Normal
editor geometry reconstructed its saved 756 x 1372 registration exactly at a
932 x 2168 page size, with a 128-point Simple writing lane. Both separator
strokes were grouped into neighboring chord targets; both targets had no match.
Native source images independently show `| Db9 | E`. This is retained saved
source, not a stopped-app backup or fresh physical-Pencil acceptance.

## Repair

The contextual detector accepts clear ordinary separator shapes down to 45%
lane overlap, keeping the 22-point floor and existing angle limits. The short-only
route requires 0.90 straightness, excluding a flagged seven while preserving
the gently wavy short-divider and actual saved source controls. It also keeps
rendered-glyph overlap exclusion, chord-stem/bowl/accidental/repeat ownership,
and existing source coverage/consumption checks. Newly admitted short strokes
require complete original unmasked source. The old masked and wider-stroke
routes keep their previous rules. No reader scores, models, cadence timers,
modal, confirmation or additional pause changed.

The existing paper helper and detailed/How To guidance explain shorter strokes
and both directions. Legacy helpers retain their layout-specific split/form
constraints. The pipeline identity records this material structural change.

## Verification at this checkpoint

Private receipts: `/private/tmp/ichart-fix046-barline-height-20261127`.

- `height-baseline.xcresult`: four methods; half-lane admission fails across
  all 24 requested combinations. Direction controls and prior-height matrix
  are separate from shorter-length support.
- `short-bar-focused.xcresult`: 36 total, 35 passed, one failed method. All
  mixed half-height, chord-source, mask, direction and guidance checks passed.
  The new blank test counted the normal open continuation tail before Done;
  it now calls the normal finish operation before asserting one finished bar.
- `private-source-before-after.json`: unchanged nine-stroke source and exact
  saved registration. Before: zero separators and two no-match targets.
  After: separator source indices [0, 5], Db9 sources [1, 2, 3, 4] and E sources
  [6, 7, 8]. Both actual reader answers are correct. Expected labels are checked
  after inference and never supplied as recognition input.

## Final source-freeze verification

- The first combined 324-case run exposed an old test calling an isolated
  28-point vertical line a chord stem without any chord body. That old height
  proxy now tests accepted short-divider ownership. A separate completed B
  construction using the same stem must retain all chord source.
- The 325-case run then passed with one optional source-replay skip. A final
  short-stroke control found a genuine new suffix hazard: a 24-point flagged
  seven was claimed as a divider, reducing C7 to C. `suffix-safety.xcresult`
  has two methods, one passed and one failed before the short-only shape guard.
- `final-suffix-native.xcresult`: **327 total, 326 passed, zero failed, one
  optional private-source feedback check skipped**. Includes short single and
  double dividers, high/middle/low placement, both directions, gentle wobble,
  real C/G reads, genuine B/D/F/F-sharp/B-flat/percent/slash controls, clipped
  source, short blank-measure creation through Done, existing source safety,
  endings and guidance. The real Editor rapid half-height workflow exercises
  Automatic and Manual in both chart styles without changing timing bounds.
- `final-private-replay.xcresult` separately checks exact saved registration,
  real inference and reviewed source partition; Automatic and Manual component
  transactions render two chords and two dividers, archive all seven chord
  strokes, preserve the original eight events and clear pending ink. Full
  chart/source equality is checked after encode/decode. Expected answers are
  asserted after inference, never supplied as recognition input.
- `device-build-final.xcresult`: signed 1.9.4 (205), explicit build override.
  The stage passes strict code-signature, bundle/version, team, development
  entitlement and connected-device provisioning checks. The frozen application
  source manifest matches the final build. Earlier local prototype artifacts
  remain parked separately; they were not installed.

A fresh saved-work confirmation was received before any stop. At source freeze,
Build 205 installation and fresh physical Pencil acceptance remain separate
pending gates. The prepared workflow is
`.build/device-backups/2026-11-27-fix046-barline-height-build205`; its eventual
`final-summary.json` records the backup/install and saved-content readback.
