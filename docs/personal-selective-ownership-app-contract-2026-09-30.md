# Selective ownership: frozen comparison-plumbing contract

Freeze before implementation. This is an app-connected uncertainty/evidence
boundary, not a new fitted recognizer, calibration experiment or promotion of
V1–V4. No private/reserved input, model artifact, learner setting or current
live recognition/arbitration function changes. Completion of this contract is
not completion of the handwriting-recognition goal.

## Meaning and API

Add an ink-only assessment immediately after the lossless source-index grouping
proposal in `PersonalInkLearnedComparison.predict`, before query encoding. It
receives only source stroke count and proposed original-index groups, never a
profile, intended answer, expected chord/glyph count, ranking or accepted text.
Use the existing feature-schema source limit and comparison group limit, not a
new data-tuned threshold. Reject empty, out-of-range, duplicated or incomplete
index partitions before any query encoding. Retain group order and source-index
order within each group; do not claim an expected owner count.

The present policy has one honest outcome: `unresolved`, reason
`uncalibratedGeometryProposal`, with versioned proposal evidence. Structural
coverage is recorded separately and cannot become correctness/confidence.
There is deliberately no constructor for a calibrated/resolved result in this
version. A later real ownership model requires its own frozen evidence contract.

Add a new opt-in grouping identity, `selective-lossless-ownership-v3`, without
changing legacy/default or lossless-v2 behavior. This mode validates original
geometry, proposes lossless indexed groups and returns unresolved before
encoding any query group or whole-chord input. It preserves source-index
proposals and all original source ink. Complete generic/personal/anchored reads
are nil; optional personal weights cannot resolve ownership. No rendering,
acceptance, teaching, erasure or journal-flag mutation is introduced.

## Real app connection and fair evidence

The existing comparison button should generate a paired report:

1. The unchanged legacy hypothesis comparison, retaining all original ranks,
   composed suggestions and scores for diagnosis.
2. The new selective-lossless comparison, retaining every unresolved complete
   fresh target as a no-read in the same eligibility set and denominator.

Fit the run's frozen profile once and reuse that model/encoder for both routes;
do not double encode lessons unnecessarily. Neither route receives intended
answers during inference. Both reports must bind the same run, source/evaluation
digests, encoder, frozen profile generation/revision, lesson counts and pair ID,
with distinct explicit grouping identities. Pair construction must reject
mismatches. Keep capture-level `groupingIssue` separate; do not use it to drop
a new unresolved attempt. Old reports decode without fabricated ownership data.

Persist the pair as one append-only file containing both reports, so one failed
save cannot look like a fully saved pair. Preserve the previous single-report
API for historical tests/callers. Live opt-out/profile-change checks still gate
publication and saving. A failed save publishes neither paired report. Do not
overwrite any source run, profile or previous report.

The actual comparison UI must show the legacy hypotheses and the selective
ownership outcome together, the retained original-index proposal, and an
explicit unresolved count/coverage explanation. It must state that all
nontrivial ownership is uncalibrated here and that zero committed wrong reads
with zero resolved reads is not recognition improvement. Call proposed groups
groups, not verified symbols. Preserve the existing no-lesson, known-ink,
missing-input, unsupported-input, older-report and zero-attempt explanations.
No extra mode selector or teaching action is necessary for this comparison.

## Executed validation required

- Ink-only partition guards, stable Codable version and backward decoding.
- No expected labels/counts/profile or agreement can resolve ownership.
- No selective query or whole-chord encoding; original proposal preserved.
- Legacy and lossless-v2 outputs remain unchanged, including old encoding.
- One frozen fit for a pair; matching source/profile/model identity enforced.
- Same eligible denominator; unresolved versus unsupported counted separately.
- Atomic append-only pair save, opt-out/stale/save-failure publication checks.
- Actual model/button path selects paired mode; view exposes unresolved state
  and retained proposals in portrait and landscape.
- Focused iOS tests must execute nonzero cases, with zero failures/skips checked
  using `xcresulttool`; source-declared counts are not a test result.
- Recheck all retained V1–V4/Swift code and artifact bindings without regenerating
  features, loading rejected models or consuming reserved writers.

Use the canonical simulator with a fresh isolated DerivedData/result directory.
Device install/launch and real Pencil interaction are separate evidence; do
not call this a better recognizer or ship-ready build based on this plumbing.

## Review refinement before acceptance

The first executed gate exposed two old configuration assertions looking for
direct chart commit and drawn spacing in `EditorView`, though the existing
live-canvas transaction now owns that call. Update the assertions to follow
the coordinator/current-drawing/coverage chain; do not restore cached-ink
clearing or weaken behavioral render tests.

Independent source review also requires paired counter reconciliation against
eligible rows (not just equality or an unresolved-plus-unsupported sum), and a
lock-held profile-store transaction encompassing the paired stale check, save
and publication. A later background lesson update cannot interleave within
that boundary. The transaction must not mutate or reenter the profile store;
historical single-report behavior remains unchanged. These refinements do not
change inference, calibration or the recognition-quality claim.

For a paired receipt only, classify `record.knownInk` as the existing known-ink
exclusion when exact saved input is unsupported, after capture-grouping
precedence. This preserves reconstructible eligibility without altering old
standalone report output, inference, rankings, or its scorecard. Do not silently
intersect eligible sets to compensate for incomplete evidence.
