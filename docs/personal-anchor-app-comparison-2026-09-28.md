# Anchored personal learner: app comparison and runtime proof

Branch `codex/recognition-generalization-reset`, base `160aa31`; existing dirty
work preserved. This follows `personal-adaptability-results-2026-09-28.md`. It does
not promote the learner into the live reader or add another recognition engine.

## Implementation

`PersonalInkAnchoredResidualHead` ports the frozen normal equations with
double-precision Cholesky and the original learner's input, opt-out and stale
context checks. Public anchors never count as personal lessons. Empty/full
profiles preserve the original learner exactly. Explicit novel labels do not
invent shared training examples.

The Debug comparison now shows shared, original personal and new personal reads
on identical grouped ink, the same frozen pre-test profile and the same visual
model. It never automatically prefers the new result. Both personal variants
retain strict complete-input composition; whole-chord guesses stay separate.
Optional report fields preserve decoding of earlier reports. The UI explicitly
notes that the new method can also lose useful corrections.

Version-two packages optionally include a pinned `public-anchors.json`. Missing
or altered anchors fail visibly. Vocabulary, feature shape and encoder binding
are validated. The pinned version-one package still loads with its original
identity and no anchored result. Build inclusion remains opt-in and Debug-only;
only the model, manifest and public anchors are copied, never private profiles,
raw ink, expected answers or parity packets. Stale anchor resources cannot be
silently reused with a legacy package.

- Version-two manifest SHA-256:
  `d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1`.
- Public anchor SHA-256:
  `e1670f855301f2fdb7970d2a4d23a30ffd82e76a242347867751b6c4c78a76ed`.
- Visual-model package and weights are unchanged from the original comparison.

```sh
python3 scripts/package_personal_comparison.py \
  /tmp/iChartPersonalResidual-20260928.4FAreZ/coreml-01 \
  /a/new/directory/PersonalMLComparison \
  --anchors /tmp/iChartPersonalAdaptability-20260928.vxltRt/anchors-01/public-anchor-bank.json
```

Use the existing explicit Debug build flags documented in
`personal-learned-app-comparison-2026-09-28.md`. Omitting `--anchors` packages the
original comparison. These `/tmp` artifacts are not a durable clean-checkout
model distribution; none was added to shipping resources.

## Executed verification

- **27 Swift/macOS tests passed**, zero skips/failures. Actual Core ML inference
  on all **1,552 public development trajectories**, then all expected top-five
  rankings for sparse16 and full97: **1,552 ranked queries** across the two
  profiles. Every expected order matches. Maximum errors: embeddings
  4.3213367462158203e-7, logits 2.47955322265625e-5, anchored scores
  2.8012373318730965e-6, all below the fixed 1e-4 tolerance.
- **77 iOS Simulator tests passed**, zero skips/failures, verified with
  `xcresulttool`. Includes actual bundled model/anchor loading, fit invariants,
  saved reports, frozen profiles, opt-out, exact-input capture in both chart
  styles and project configuration.
- **Seven packaging tests passed**, including default-off, Release refusal,
  allowlisted resources and non-destructive stale-artifact failure.
- Portrait/landscape attachments of the actual comparison view were inspected;
  result variants are readable. These use a controlled test profile/model, not
  recognition evidence or physical-device interaction proof.
- `xcodegen generate` succeeded and `git diff --check` passed. No generated
  project membership was patched by hand. No physical-iPad install occurred.

## Full-chord replay: limitation remains

The runtime replay used the same frozen 30-example private profile and 12 v26
observations / eight unique inputs. Profile and trace bytes are unchanged.
Every prior shared, original-personal and whole-candidate result is also
unchanged, checked field-by-field against the previous strict replay.

The new method retains the Simple inputs' B-flat-7, E-flat-7 and D7 reads. It does
**not** repair Rhythm endings: strings still include `BbsD`, `EbS9`, `D>` and
`EbT`, none composing into a complete chord. Unread endings are not dropped and
intended answers are not selected from lower ranks. The profile lacks a triangle
lesson; shared training lacks several musical symbols. This is development
replay, not fresh accuracy.

Next work must investigate symbol/endings representation, coverage and grouping
in complete chords. Matching runtime math and a sparse-character improvement
are insufficient to replace the live reader. Preserve explicit learning and
paired comparison; no hand-picked chord rules or repeated known-answer tests.

Evidence: `/tmp/iChartAnchoredApp-20260928.gvCNjo/`:
`swift-runtime-01.log`, `exact-trace-01.json`, `anchored-ios-01.xcresult`,
`packaging-tests.log`, and `screenshots/`. Inspected images:
`F52DF679-8C92-4E4F-A641-2FD3CB3E21A4.png` (portrait),
`F44F488F-C2D5-495C-97C0-AC37E9757E48.png` (landscape).

No private teaching, chart rewrite, live-reader change, physical install,
credential access, backend deployment, commit, push or release occurred. The
goal remains active; fresh full chords and independent writers are still needed.

## Follow-up: symbol training, no promotion

The exact-input audit confirmed correct grouping for the saved Rhythm failures.
Two public-data training approaches now exercise missing shared symbol coverage;
the constrained one preserves the original visual features and reads both saved
triangles, but digit failures and measured substitutions remain. Neither changes
this app bundle or the live reader. See
[symbol-training results](personal-symbol-training-results-2026-09-28.md).
