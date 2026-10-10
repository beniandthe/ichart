# Chord-only reader boundary — 2026-10-03

## Outcome and evidence boundary

Implemented the requested chord-only domain boundary across the native reader,
personal learned comparison arms, conditional complete-token decoders, and
Study presentation. The selected Simulator gates passed with nonzero case
counts verified from both Xcode result summaries and individual test trees:

| Gate | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| iChart: 12 selected recognition/parser suites | 341 | 0 | 2 |
| RecognitionStudy: Vision reader/provider and typed learned provider | 22 | 0 | 0 |

The two skipped cases are the explicitly opt-in full-archive tests:
`ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled` and
`GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled`.
Default regression fixtures, valid chord families/aliases, composition,
recognizer trust, and the new rejection contracts did execute.

This is reader-boundary and compatibility evidence, not fresh handwriting
accuracy, a learned-model promotion, or shipping readiness. Build 57 is now
installed and launched on the physical iPad; Pencil interaction is not yet
verified. Profile and evaluation bytes are unchanged. Five drawings were
reserialized during the earlier build 56 launch, with every public stroke property verified equal;
see the preservation details below. Historical prediction freezes and scored
queries were not changed. No commit, push, or production deployment occurred.

The final comparison-display follow-up passed another 39 focused Simulator
tests with no failures or skips. It prevents standalone contextual fragments
from appearing as proposed-group readings; valid complete chords retain their
fragments. This is additional display-policy evidence, not an accuracy result.

## Policy

- The shared `ChordRecognitionDomain` derives permitted glyphs/fragments from
  the typed chord language and explicit supported musical aliases, rather than
  the much broader character-training vocabulary.
- Roots remain A–G. Contextual fragments remain available: `1` in `11`/`13`,
  lowercase `j` in `maj`, quality words, accidentals, alterations, slash bass,
  and exact chord-repeat spellings. A permitted fragment is not by itself a
  valid complete chord or a legal root.
- Unsupported glyphs cannot become displayed chord candidates. An illegal
  raw winner in any written column leaves that read unresolved; a legal
  runner-up is not promoted to manufacture a replacement.
- A missing/rejected column is not dropped before native prefix recovery or
  semantic composition. Existing recovery rules for otherwise permitted
  musical evidence were not redesigned in this pass.
- Complete input still must pass chord grammar. The compendium no longer
  strips arbitrary punctuation or folds accented letters into valid notes.
- Native template/heuristic vocabulary is restricted before candidate limits.
  ML reader projections and the comparison glyph UI use the same boundary.
  Vision no-grammar output becomes no-read rather than displayed raw text.
- Raw learned ranks, model tensors, original probabilities and historical
  diagnostic receipts remain intact for artifact compatibility and auditing;
  they are not reader candidates or chord suggestions. No scores are
  renormalized after rejecting unsupported labels.
- Both complete-token decoders block accepted paths when a raw column winner
  is forbidden. The probability decoder retains the original examined,
  rejected, and unexamined mass; it cannot issue a replacement candidate or
  ranking certificate for an illegal-winner read.

## Provenance

Policy identities for the initial domain boundary:

- Shared boundary: `chord-recognition-domain-v1`.
- Native pipeline: `maximum-trust-v32-chord-domain-v1-2026-10-03`.
- Study Vision provider: `apple-vision-text-baseline-v2-strict-display-domain`.
- Rank decoder: `conditional-complete-token-lattice-v2-chord-domain-v1`.
- Probability decoder: `canonical-probability-lattice-v2-chord-domain-v1`.

Model weights, model-head vocabulary, learner identities, and forensic Codable
schemas were not changed. The broader encoder/head is retained only as raw
evidence; reader projections and newly versioned decoders enforce the current
policy. Experimental personalization remains comparison-only.

The earlier fixed m/9 append-only experiment remains a failed intervention.
Its frozen results were not rerun, relabeled, or presented as improved by this
patch. See `personal-append-only-glyph-coverage-results-2026-10-03.md`.

## Verification artifacts

Local gate directory:
`/private/tmp/iChartChordDomainGate-20261003.2gzbQh`.

Successful app gate: `iChart4.xcresult`, `iChart4.log`,
`iChart4-summary.json`, and `iChart4-tests.json`.
Successful Study gate: `Study.xcresult`, `Study.log`,
`Study-summary.json`, and `Study-tests.json`.
`tested-source.sha256` records 23 changed source/test files; all 23 verified
unchanged after the successful app gate. `git diff --check` was clean.

Earlier attempts are retained in that directory: one compile failure repaired
without changing ordering, an old synthetic test that required forbidden-winner
promotion, a comment-only provider-scan failure, and one floating-point literal
assertion. The final gate reran all 12 selected suites after those repairs.
The probability-versus-additive ranking test still keeps its original numbers
and Cartesian universe, with musical-domain fillers that remain invalid in
their grammatical positions. Raw-probability, exact-ink, profile, and Codable
integration assertions were preserved.

These temporary paths are local build evidence and may expire. The next quality
claim requires a new frozen protocol and fresh writing after a separately
verified physical-device build; do not score the already-labeled queries again
as independent recognition evidence.

## Legacy correction suggestions

A follow-up reader-path audit found that `PendingChordCorrection` could display
an unsupported persisted candidate signature as a correction shortcut. Its
normalizer returned unmatched raw text. Although committing a correction already
required a valid chord, displaying that shortcut violated the reader boundary.

The normalizer now returns only complete compendium matches. Unsupported legacy
or imported candidates are omitted from suggestions; stored signatures, raw
input, and the manual edit field are preserved. Valid aliases still normalize
and deduplicate in their original suggestion order.

The focused Simulator gate passed 11 tests with zero failures or skips: three
new `ChordInkCorrectionSuggestionDomainTests`, seven `ChordRecognitionDomainTests`,
and the existing `ChordInkReviewInputTests` keyboard/focus case. Counts and test
names were verified through `xcresulttool` summary and individual test-tree data.
The result is `CorrectionSuggestions.xcresult` under
`/private/tmp/iChartSupportMatchDeferExecution-20261003.KEUEUI`.

The tested full-file hashes are
`069d76341e71f439d23a837979e0a5b78a57080b3a48b37ba7cd868d3d8ba588`
for `ChordInkSheetViews.swift` and
`6e73244a5bf3a64cadb0c545aead74a9f78bfec71bffa20b1a75c924331dd5f1`
for the new test file. This follow-up is included in installed build 56. The
Simulator test does not establish Pencil behavior or recognition accuracy.

## Physical iPad build and data preservation

The regenerated project built version 1.2.1, build 56, successfully for iOS
with the existing Development signature. macOS verified the complete app
signature outside the sandbox; the sandbox-only trust check was inconclusive.
The paired iPad reported build 56 installed, launched it as process 9764, and
still reported that process running in the subsequent check. No signing
credentials were read or entered by the agent.

The comparison resources are byte-identical to the existing frozen runtime.
No rejected research model or new learned weights entered this build. All
23 reader-gate source hashes and the two correction-follow-up hashes were
rechecked against the tested files.

Two preinstall copies were identical. The postlaunch check found:

- All 68 saved profile examples and 22 evaluation runs retain identical file
  bytes. The journal contains 18 complete and four cancelled runs.
- All 27 charts remain present. Five PencilKit data blobs changed archive
  bytes. Their 108 total strokes have equal point locations, timing, size,
  opacity, force, azimuth, altitude, secondary scale, threshold, creation dates,
  transforms, bounds, masks, masked ranges, random seeds, ink types/colors, and
  required content versions when decoded through PencilKit on macOS.
- All other chart fields are structurally identical. The root entitlements
  field changed; this is recorded separately from chart preservation.

The existing chart decode path reserializes nonempty PencilKit drawings even
when no color normalization is needed. That is consistent with the byte-only
changes, not proof of a particular internal PencilKit serialization cause.
Both original and postlaunch archives are retained; neither was restored over
the live library.

The durable local evidence directory is
`/Users/benirossman/.local/share/ichart/recognition-development/chord-domain-device-20261003.NzclWL`.
It contains the exact signed installed app, successful build log, installation
and launch receipts, before/after backups, and `verify_preservation.swift` plus
`preservation.json`. Physical handwriting acceptance remains untested.

## Complete chord context in the comparison panel

The final source audit found that the ML comparison disclosure could display
the fragment `1` by itself. The lexical projection correctly allowed it inside
`11` and `13`, but the disclosure did not require complete chord context.

`Prediction.chordDomainPresentationLabels` now validates the entire projected
top-token sequence for each arm through the existing complete composer. If
any group is missing, forbidden, or the sequence cannot form a supported chord,
every displayed group for that arm is unresolved. Lower-ranked labels are not
promoted. Raw ranks, scores, Codable fields, stored results, and model behavior
remain unchanged. The view reads only this computed presentation.

The focused Simulator gate executed 39 tests with zero failures or skips. Its
two new tests cover standalone `1`, `j`, `ñ`, and `J`; illegal top-rank
nonpromotion; missing or invalid interior groups; and retained contextual
fragments in `C11`, `C13`, and `Cmaj7`. `xcresulttool` confirmed both new test
names and the total nonzero test count.

Build 57, version 1.2.1, replaces build 56 on the iPad. Its signed build and
signature verification succeeded; installation was verified independently.
It launched as process 9773 and remained running. All 27 charts, including
their archived ink bytes, are structurally identical before and after this
update. The profile and evaluation journal retain identical bytes. Two
preinstall snapshots matched. Comparison model resources remain byte-identical
to the prior frozen runtime. Physical Pencil acceptance is still untested.

The final local evidence directory is
`/Users/benirossman/.local/share/ichart/recognition-development/chord-context-device-20261003.OZCxzd`.
It retains the final app, result bundle and extracted test summaries,
source identities, build/install/launch records, and data-preservation copies.

## Scored candidate rejection follow up

A final audit found an internal distinction still missing from the native reader. A standalone contextual fragment such as `1` could not be displayed or accepted as a chord, but it remained in `candidateScores` with a nil display match. Its score correctly prevented a nearby weaker chord from becoming trusted. Two regression tests reproduced the unwanted scored-candidate membership before the repair.

The reader now separates complete supported chord scores from `rejectedCandidateConfidence`, a numeric rejection-only signal. The same original top-eight window, minimum score, first-text deduplication, and maximum rejected score are retained. Supported scores keep their original values and order. Removing invalid text therefore does not renormalize probabilities, promote a runner-up, or weaken the existing confirmation requirement. A defensive fallback still handles manually constructed older results with nil-display scores.

The composer and `rawCandidates` remain a diagnostic transcript and an indication that ink produced evidence. Removing fragments there would discard rejection evidence before scoring and change no-read delivery. Those raw strings are not accepted chords, review choices, or personal suggestions. Historical diagnostics and learned-model output heads remain intact; this is not a claim that invalid labels were deleted from raw diagnostic JSON or model tensors.

The new pipeline identity is `maximum-trust-v34-chord-only-scored-candidates-2026-10-03`. Model weights, score thresholds, chord grammar, and supported notation are unchanged. `1` still participates in `11` and `13`, and `j` in `maj`; neither is a complete chord. This pass also includes the separately documented lossless-lesson storage and explicit-learning evaluation-flow fixes.

The final iPad Simulator gate passed **331 tests, zero failures, zero skips**, independently counted from the result summary and test tree. It covers native recognition, maximum-trust and selective decisions, composition, review suggestions, session behavior, both chart-style capture adapters, comparison display boundaries, and learning eligibility. The opt-in full ink archive test was explicitly excluded; the default regression fixtures executed. The five new rejection-evidence tests verify unchanged scores/order, the original rejection window, exact confirm-versus-trusted boundary, no-read behavior, and separation of raw diagnostics from suggestions. These are regression and boundary checks, not fresh recognition accuracy evidence.

Evidence is under `/private/tmp/iChartLessonFidelityDevice-20261003.zI1r7N`: `rejected-score-red.log`, `rejected-score-green.log`, `ChordOnly-iPad.xcresult`, `ChordOnly-summary.json`, `ChordOnly-tests.json`, and `final-source.sha256`. The earlier learning-flow gate in the same directory passed 142 Simulator tests with no failures or skips before this final scored-candidate split. The gates overlap and must not be summed as unique coverage.

Version 1.2.1 build 60 compiled and passed development-signature verification with these final sources. All seven source/test hashes in the final manifest were rechecked unchanged after the build; comparison resources match the prior frozen package byte-for-byte. The final device check still reports Ben's iPad unavailable. Build 60 is prepared but was not installed or launched, and no physical chart, ink, profile, or journal was changed. `device-build60.log` and `final-device-availability.json` retain the build and availability records.
