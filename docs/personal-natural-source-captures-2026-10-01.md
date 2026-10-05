# Fresh natural-chord source captures — development evidence

## Scope and frozen inputs

Read-only pull from Ben's iPad on 2026-10-01. Installed app verified as
`com.ichart.app`, 1.2.1 (52). Worktree: `codex/recognition-generalization-reset`,
HEAD `160aa31594903508e241802e21ca83ec447de849`, with existing uncommitted work.
During the initial read-only capture and whole-page ML comparison, no physical
app reinstall, recognition policy change, chart mutation, teaching, threshold
selection or model promotion occurred. The subsequent generic correction and
its gates are recorded separately below.

Private evidence is preserved at:
`/Users/benirossman/.local/share/ichart/recognition-development/natural-source-20261001.YtzQL2`.
It contains the exact copied journal/profile/library, strict source exports,
source-only reviewer pages/plots, code/runtime maps and offline test results.
Do not distribute the private journal, source envelopes or profile.

| Capture | Ended run | Visible strokes / points | Live targets | Unassigned |
| --- | --- | --- | --- | --- |
| Simple | `1296D709-D8B8-4AF1-BD63-C0A8DE770605` | 44 / 698 | 8 | 0 |
| Rhythm | `EBE139C4-0C8D-4DF8-A7AF-7BF8A526E73E` | 60 / 649 | 9 | 1 |

Both runs are `cancelled` because they ended without scoring, while their source
capture state is `complete`. Every target record matches its source request,
revision, ordinal and exact recognition strokes. Canonical visible trajectory
bytes reproduce exactly; ownership plus unassigned indices account for every
visible fragment once. This proves capture/input integrity, not correct ownership.

- Simple source packet SHA-256:
  `0b0322170409992048f72e182210f9b0496206bb614863ed0dadd12c5d28da73`.
- Rhythm source packet SHA-256:
  `b5893094b5d6e33ca19ccc9338b4e861b1cc25b13876a5d3bd216d7d9be5b61c`.
- Exact journal SHA-256:
  `ef33fc0b3dd74e5314ea12a04f08325d53daabde31d815a1603f3f3bec0c1b4d`.
- Profile bytes remain unchanged, 34 examples, SHA-256:
  `73df2f92728d0b39cb9ea04c8ec6f1477b2ee50d9c6f36a15e44cbd97f121327`.

All twelve older run objects and fifteen older chart objects/ink fields are
unchanged. Two source charts were added. Both new runs freeze the same profile,
have no intended labels or teaching, and have zero recorded known-ink flags.
The seventeen live actions are ten trusted and seven confirm; fifteen are cache
hits. These categories and equality of baseline/personal defaults are not
correctness scores. Profile support lineage remains untracked/incomplete.

## Source-first boundary

Rhythm groups 6 and 7 are separated by only 4.877 source points. The group-7
opening pair has a 10.150-point gap from its remaining strokes. An incidental
two-point fragment, 46, is 0.263649 points wide and is retained as unassigned.
Generic usable-stroke filters exclude it before targeting because both its
width and height are below one point; it is not a barline exclusion or a lost
journal record. Removing it from adjacency also changes the available timing
gap from two shorter gaps to a 1.72725-second usable-stroke gap.

This identifies a narrow attachment/root-boundary question, not permission to
auto-merge. The writer replied `8` when asked for the counts in both passes;
the coordinator interpreted that as eight in each. After predictions and source
were preserved, the writer confirmed the final Rhythm region is `Amaj7(#11)`
followed by `B7`. This is writer-confirmed development intent, not an independent
blinded ownership annotation. The recorded split separates the preceding root
from its quality/parenthesized extension.
Do not use the count or an expected chord answer to select an inference group.

## Offline ML check and its limit

Added only an opt-in natural-source method in
`PersonalInkBlindPredictionFreezeTests.swift`. It binds the exact saved envelope
and enabled profile, verifies the pinned anchored runtime and actual code-file
hash map before/after, supplies no ownership groups/receipt, and retains an
explicit invalid-ink outcome. It does not change the production adapter/budgets.

The first compile exposed two test-helper `Dictionary.keys()` syntax errors;
those were fixed. Subsequent `xcresulttool` summaries verified one executed
test for Simple and one for Rhythm, each with zero failures and zero skips.
Both source-only full-page artifacts returned `automatic.outcome=invalid-ink`,
with no glyph predictions and null supplied/ownership arms. The reader's
existing automatic arm accepts at most sixteen glyph groups; a whole-page
request is not a per-chord comparison. Do not interpret this as a live-app
failure, a recognition-accuracy measurement, or successful natural-chord ML.
The artifacts are not eligible for the paired accuracy evaluator without the
required independently frozen ownership evidence.

The actual Swift profile commitment in both artifacts is
`f7c15b5a19bb14723cd7214b752cfdde09dba35d12aee722d753f8ae8b395ff9`.
The executed code-map commitment is
`95c64e20ebfafaecefeba40abe9d0f51dd9d36513386e2124419f967de6bb62c`.
The pinned runtime file-map commitment is
`31fdfad29ec20b50b180bd94b59b530268238f6cb93919828f463f0495d6a0df`.

## Exact live-route replay and conditional per-target ML

The subsequent source-bound replay reconstructed the saved chart geometry and
ran normal live preparation without intended labels, expected counts, profiles,
or recorded target groups supplied to inference. It reproduced the recorded
nine-target Rhythm partition via `lane_root_sequence`, before and after the
batch-load bound. The source-47 glyph's leading candidates were triangle
`0.999`, flat `0.980`, and G `0.970`. Its root-start probe returned modifier-led G
with the observed 1.727251768-second pause, but no root without timing. Removing
timing from the entire row, with unchanged geometry and indices, joined the
raised suffix to the A-root input while preserving the separate B-root input.
This establishes temporal-only false-root authorization in this development
capture; it does not establish a general recognition-accuracy rate.

Two focused checks (Rhythm route replay and Simple per-target ML) executed with
zero failures/skips; the subsequent Rhythm per-target ML check executed once
with zero failures/skips. Counts were verified with `xcresulttool`.

The new conditional diagnostic queried every retained live target without
supplying glyph ownership. Simple: 8/8 returned glyph proposals, 28 proposed
glyph groups covered all 44 source strokes. Rhythm: 9/9 returned proposals,
31 groups covered 59 target-owned strokes; fragment 46 remained unassigned,
retained, and unqueried. There were six Simple and five Rhythm shared-to-personal
top-choice differences. A `read` outcome means the reader returned proposals,
not that they were correct. The proposals visibly include incorrect glyphs;
no whole-chord accuracy, verified glyph ownership, or across-writer quality is
claimed. This diagnostic ran after writer confirmation, and explicitly records
`predictionChronologyVerified=false` and `accuracyMeasured=false`.

Both target reports bind code map
`4d164c1104e2b291f080990a4f742683ad68ce59910226c5a1ba2d14cbf0ac9c`,
the same pinned runtime, and the same Swift profile commitment as above.
`personalTop1` is the existing original residual head, not the anchored ranking
or the native app's chord decision. The production live path still uses the
maximum-trust template recognizer and optional local shape suggestions; this
ML comparison remains an offline/DEBUG diagnostic, not automatic promotion.
No fresh examples were taught and no ML weights were changed.

## Generic candidate and remaining gate

The candidate correction removes temporal-only authorization for a leading
symbolic quality lookalike when ordinary independent spatial-root evidence and
existing explicit root-lookalike overrides are absent. It does not change
timing constants, confidence thresholds, intended labels, ML weights, or trust
acceptance. The saved-source regression checks the writer-confirmed boundary
only after inference, preserving every other target and unassigned fragment.
It is a development regression, not a fresh blind test.

The final candidate gate executed 91 tests with zero failures and zero skips,
verified through `xcresulttool`. It covers the complete focused sequential
suite, edited-target ownership, exhaustive target snapshots, baseline-preserved
personal arbitration, content-free preparation telemetry, and exact Rhythm
source regression. A separate exact Simple-source replay executed once with
zero failures/skips and preserved the original eight-target partition.

The synthetic matrix varies roots A–G, all five quality symbols, five pause
conditions, close/detached geometry, two representable scales, and four
confidence ladders including ties. Stronger-root, slash, non-symbolic modifier,
existing explicit plus/root override, and hard-pause source-conservation
controls remain covered. These are policy/regression tests, not independent
handwriting accuracy trials.

The native maximum-trust diagnostic on the repaired Rhythm input returns
`A△7(#11)` and `B7` as separate **confirm** decisions. The repaired partition
preserves all other groups and retains fragment 46 unassigned; every source
fragment is accounted for exactly once. The candidate code-file-map commitment
is `c6a2873e4ba396f8b4a88390071d07008a134450c9cf7796d2d004e7b61bc3b6`.
The pipeline identity was then bumped to
`maximum-trust-v31-symbolic-pause-boundary-v1-2026-10-01`, so old and new
captures cannot share an algorithm identifier. The same 91-test gate passed
again with zero failures/skips. The final code-map commitment is
`a44d363925462fbeaa0a753190c28e9f24ae1893d020c9ccefc3389e5fb2e53f`.

Two earlier candidate invocations failed compilation in new test code before
execution (string quoting, then a wrong prepared-source validation API). The
next invocation executed 91 tests: 90 passed and the new matrix failed because
it incorrectly expected the existing plus/root override to accept an equal
confidence tie during a tight continuation. Its expectation was corrected to
match the unchanged strict-confidence production contract; production was not
loosened. Failed logs/results are retained alongside the final passing gate.

A truly close independent letter that is misranked as a quality symbol remains
an ambiguity risk. Whole-chord trust/review must remain unchanged. This narrow
policy is not a repair for every digit/parenthesis ambiguity or tiny-fragment
filtering. Counterexamples, source conservation, and a fresh on-device pass are
required before calling the correction ready. Independent natural-chord/writer
evidence remains necessary for general accuracy or shipping claims.

## Physical development handoff

The final v31 development build 53 was compiled, signature-verified, installed,
and launched on Ben's iPad; device app metadata reported 1.2.1 (53). The final
executable SHA-256 is
`bcd8270ac5f9181b9b5713a2cadf6b27bcd1aa4d3ff469dc20fcb578f1e39fe2`;
its compiled strings contain the distinct v31 identifier. Embedded DEBUG
comparison resources were byte-identical to the already tested pinned package.
No rejected/new model was embedded. Installation/launch is not Pencil or UI
acceptance, and the next fresh handwriting pass remains pending.

Pre/post final installation profile and evaluation journal digests remain the
same as the original frozen copies. Both libraries contain 17 charts. One
Simple chart's `pageHandwrittenChordData` was reserialized at startup: encoded
length 19,724 → 19,756. Every other chart field remained identical. A read-only
macOS PencilKit check decoded both archives: identical 44 strokes/698 points,
stroke order, paths, creation dates, transforms, ink types/colors, point sizes,
force/orientation/opacity/timing, drawing bounds, and per-stroke render bounds;
zero masked strokes in either. Archive bytes changed without any measured
stroke-geometry/style change. This is not physical visual acceptance.

Private logs, frozen reports, before/after copies, hash maps, failed attempts,
passing `xcresult` bundles, and the preservation check are retained under
`/Users/benirossman/.local/share/ichart/recognition-development/symbolic-boundary-20261001.m9ANyI`.
No commit, push, upload, production deployment, or goal-completion claim is part
of this handoff.
