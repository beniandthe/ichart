# Stroke direction diagnostic results

The rejected stroke-field model is strongly sensitive to direction features
even when its visible ink image is unchanged. This is a controlled feature
perturbation of reused public data, not fresh handwriting, a new accuracy
milestone, a personalization benefit, or a deployable fix. The original failed
advancement verdict remains unchanged. No app, chart, profile, device build,
or production service changed.

## What ran

Followed the [frozen diagnostic protocol](personal-stroke-direction-diagnostic-protocol-2026-10-03.md).
All 1,987 saved public fields were included in their original order. Both
frozen models first reproduced every original Float32 logit and embedding
exactly. Only then did the diagnostic negate the two tangent planes and
exchange the start/end planes, preserving the occupancy image byte for byte.
The image-only control remained exactly unchanged for every drawing. There
were zero failed or dropped outputs and no weight or batch-normalization
updates. No geometry source, private ink, reserved writer, or training example
was opened. This tests reversal within all strokes, not acquisition order
between strokes.

Transformed predictions were saved before the separate score command opened
truth and the old score. No fit, threshold, best-direction choice, averaging,
label change, or error-specific exception was introduced.

## Measured sensitivity

All counts below concern the stroke-field model. Correctness means literal
isolated-glyph identity, not a complete chord. Sources are not pooled.

| Public cohort | Drawings | First choice changed | Original correct | Reversed correct | Corrections | Regressions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| All UJI labels | 1,552 | 1,186 | 1,254 | 351 | 29 | 932 |
| UJI permitted chord fragments | 656 | 516 | 557 | 135 | 11 | 433 |
| Five mapped HWRT shapes | 435 | 183 | 419 | 253 | 7 | 173 |

On permitted UJI fragments, wrong permitted outputs rose from 46 to 337 and
no-reads from 53 to 184. On the 896 non-domain UJI drawings, permitted guesses
rose from 66 to 422; 377 previous no-reads became wrong permitted outputs.
Forbidden raw winners still became no-reads rather than promoting a legal
runner-up. These are fragment-level outcomes, not observed wrong chords.

Every one of the eight UJI development writers lost literal correct readings
under reversal. In fixed writer order W04, W06, W08, W11, W35, W43, W47, W56,
original-to-reversed counts were 149 to 44, 167 to 42, 163 to 40, 155 to 40,
163 to 46, 154 to 48, 144 to 34, and 159 to 57 (194 drawings each).

HWRT correct counts were sharp 130 to 8 of 131, plus 9 to 3 of 9, slash 42 to
42 of 54, half-diminished shape 95 to 60 of 97, and triangle 143 to 140 of
144. Equal slash totals conceal paired changes; they do not imply invariance.
HWRT writer identity is unreliable, and these five classes are confounded
with source. The plus cohort is especially small.

Excluding the same seven input-copy rows gave UJI 1,247 to 344 correct out of
1,545, and permitted fragments 550 to 128 out of 649. Flip, correction, and
regression counts were unchanged. HWRT had no copy exclusions. Complete raw
and copy-excluded summaries, per-writer/per-shape views, and original gain/harm
cohorts are retained in the score, without selecting a rule from those cohorts.

## Separate diagnosis of the original failures

The original matched candidate's 56 UJI literal regressions comprised 20
case-only, nine letter/digit, two diacritic-related, and 25 other confusions.
Its permitted-truth subset contained 13 wrong permitted outputs and ten
no-reads. All 16 newly introduced non-domain permitted guesses selected old
domain labels, not the five new symbols. Neither case folding nor routing only
the newly added shapes addresses this failure set. The original candidate
remains rejected; this descriptive analysis does not change its labels or gates.

## Interpretation and next boundary

This experiment establishes dependence on direction/endpoints in this frozen
model. It does not prove that reversing strokes is typical writing behavior,
that direction dependence caused the original natural-ink errors, or that
removing direction will improve recognition. Reversal is not a proposed fix.

A justified next candidate is a direction-neutral geometry representation:
retain the visible shape and undirected local orientation while removing the
sign of motion and start-versus-end distinction. That intervention still needs
its own training-only specification, matched fit, and unchanged safety checks.
It must not be selected by trying seeds, thresholds, or writer exceptions on
these known development answers. This pass did not implement or fit it.

Any later app promotion still requires runtime parity and fresh natural-chord
evidence in both chart styles. Further own-writer tests are permitted, but no
additional human participants are required, and broad writer-generalization
claims remain out of scope. Learning remains optional and offline until its
benefit and regressions are separately established.

## Verification and preserved evidence

Root executed 24 distinct focused tests with warnings as errors: seven new
diagnostic tests, nine frozen evaluator tests, and eight stroke-field tests.
All passed, with zero skips. Independent source review caught one missing
complete zero-length synthetic stroke fixture; it was added before real
inference, and all seven new tests passed again. These are integrity checks,
not recognition accuracy evidence. The final executed code is preserved
separately from the pre-fixture snapshot.

A separate standard-library verifier independently authenticated the pinned
artifacts and all 1,987 unique ordered joins, recomputed every original and
transformed Float32 vector hash and literal/domain decision, and reproduced
every raw/copy-excluded summary, all eight writer and five shape summaries,
the original gain/harm cohorts, and every thin scored row. It found no
discrepancy and confirmed exact image-control equality and zero failed
outputs. It did not rerun either model or re-encode source geometry; those
claims remain distinct from independent saved-output arithmetic.

Original execution directory:
/private/tmp/iChartStrokeDirection-20261003.zLw5gz

Local evidence archive:
/Users/benirossman/.local/share/ichart/recognition-development/stroke-direction-20261003.yd0CI5

The prediction packet was saved at 17:19:52 PDT and score at 17:20:34 PDT on
October 3, 2026. These filesystem times supplement enforced phase ordering.

| Artifact | SHA256 |
| --- | --- |
| Frozen protocol | 6d130183b2d2c29208b55f7361e6dea554ec04facaa8a9d8d5e2d0c7cf291d28 |
| Diagnostic module | 1202a0c7017a39be793b339f1e86ec5a50edd8b89c9c6ab4faa8c7f45e1d2d4a |
| Final diagnostic tests | 6d9092a98510a033082cb6107641c07d6e8181eb93f4afa2be11e3b98c07372b |
| Transformed predictions | c48df4cb4628a70b2e4aa4417ce42fdccfd804561ff7a148dd3c2a94c261f3ed |
| Score | 6174c4fc8e0ad7b72a16953ca2e9adedbf627f4e26a0ce5c3a0b3d37bb03a98b |
| Original error diagnosis | d9aecc129f99bb0bfc9f8079c05378b9ea2d909d20d213f9736e498239991228 |
| Original domain breakdown | 6d75ffa0586582d3826c2142c3bda48ae6b81a249c129b18ceaeb73103a6364d |
| Independent verification script | da34eab9480629b9182dcd1e4ee7504e8e4b2138811d3d0b448fcc43263d6e0f |
| Independent reconciliation | bc66d8325bc4f8812b23ecc106a911d3b188fd92b0171b361723859f73ad847a |

The execution artifacts were copied to the local archive and compared byte
for byte. The completed reconciliation and this report are included in the
final archive check; no original fit or result was overwritten.
