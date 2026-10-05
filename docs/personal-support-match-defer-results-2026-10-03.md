# Joint lesson matching results

The fixed lesson-matching recipe completed training and failed its predeclared
safety checks. Same-writer lessons improved aggregate recognition and beat the
fixed unrelated-writer control, but also damaged correct readings and produced
new wrong reads. Keep these models outside the app. Do not retune this recipe
against these outcomes or count these reused public glyphs as fresh handwriting.

This report continues `personal-support-match-defer-core-results-2026-10-03.md`
and applies `personal-support-match-defer-protocol-2026-10-03.md`. The live app,
private chart ink, saved handwriting profile, and earlier evaluation freezes
were not changed by this experiment. The separate chord-only correction shortcut
fix is documented in `chord-reader-domain-boundary-2026-10-03.md`.

## Executed comparison

The filtered loader reconstructed 6,208 public glyph rasters from 32 recorded
writer IDs, two sessions, and 97 literal source labels. All raw raster and
trajectory hashes matched the frozen source ledger. The compact support bundle
contains exactly 1,344 requested stored images, each checked against its stored
raster and trajectory hashes. No requested support failed; the 23 unavailable
unrequested shapes remain recorded. Geometry from the eight development and
20 reserved writer IDs was not constructed.

Both directions trained a generic cross-entropy control and the joint
match-or-defer model. All four models started with identical complete seed-29
state. Each finished 30 epochs and 1,920 optimizer updates, encoding 216,000
support-plus-query rows per model. Direct encoder-input hashes matched between
arms at every update. Batch-normalization exposure matched, the control matcher
remained unchanged, and the candidate encoder and both matching heads changed.
Final checkpoints reloaded successfully. No held-out checkpoint selection was
performed.

All 128 held-out episodes were frozen before the separate scorer opened truth
and copy ledgers. The packet retains full 97-way logits, support/query vectors,
strict match-or-defer routes, true/wrong support controls, and domain projections.
It contains 12,416 query exposures per arm across two catalogs, representing
6,208 distinct writings. Predictions replayed exactly without changing model
state; generic predictions were invariant to the support context. There were
zero invalid prediction rows.

## Results and failed safety checks

Each raw row below includes 1,312 supported-domain query glyphs and 1,792
out-of-domain queries. The two catalogs reuse the same query glyphs. Correctness
means literal glyph equality, not complete-chord recognition or musical-alias
accuracy. An unsupported raw winner remains unresolved; it cannot promote a
legal runner-up into a reading.

| Fit to held-out split | Lessons | Generic control correct | Joint generic correct | Same-writer final correct | Wrong-writer final correct | Personal gains | Personal harms | Net |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A16 to B16 | 10 | 1,053 | 1,054 | 1,056 | 1,041 | 28 | 26 | +2 |
| A16 to B16 | 21 | 1,053 | 1,054 | 1,105 | 1,044 | 77 | 26 | +51 |
| B16 to A16 | 10 | 1,024 | 1,022 | 1,025 | 1,010 | 41 | 38 | +3 |
| B16 to A16 | 21 | 1,024 | 1,022 | 1,084 | 1,012 | 96 | 34 | +62 |

Personal gains and harms compare the final personalized result with that
candidate's own generic result. The baseline comparison is separately reported;
joint training itself changed the generic reader.

| Fit to held-out split | Lessons | Correct or unread to wrong | Untaught correct readings harmed | New domain outputs on rejected out-of-domain ink | Lowest writer net |
| --- | ---: | ---: | ---: | ---: | ---: |
| A16 to B16 | 10 | 27 | 26 | 10 | -2 |
| A16 to B16 | 21 | 34 | 26 | 55 | 0 |
| B16 to A16 | 10 | 42 | 37 | 10 | -4 |
| B16 to A16 | 21 | 43 | 29 | 53 | -1 |

Both lesson sizes beat the fixed wrong-writer control in final correctness on
paired rows. This is evidence of a same-writer support signal in this public
glyph experiment. It does not satisfy the safety requirements: every fold and
catalog introduced new wrong readings and untaught-symbol harms. The joint
generic branch also introduced 14 and 20 correct-or-unread-to-wrong regressions,
and 14 and 26 new domain outputs on rejected out-of-domain inputs, respectively.
Its domain net versus the control was +1 and -2.

The paired no-copy view excluded 11 query exposures per catalog in A16 to B16
and 12 in B16 to A16, leaving 1,301 and 1,300 supported-domain queries. All four
method correct counts fell by the corresponding 11 or 12; gains, harms, new
wrong reads, and the rejection decision were unchanged. Every raw and no-copy
fold/catalog cell failed the fixed screen. No failing case or writer was removed
to improve the outcome.

## Implementation verification

The integration run executed 47 tests with all warnings treated as errors.
After an independent review caught a prediction-time provenance mismatch, the
evaluator was aligned with the trainer's exact stored trajectory/raster sidecars;
its final eight tests passed. These gates cover source separation, compact
support, actual paired gradient updates, identical forwarded inputs, inactive
control matching, target-only training reads, strict routing, frozen prediction
authentication, and counterexamples for every safety gate. These are engineering
checks, not recognition-quality evidence.

The independent review also clarified the fixed writer comparison before any
prediction: compare total final correctness, including generic fallback.
Counting explicit lesson matches alone could falsely suggest benefit when both
contexts already produced the same correct output.

A separate standard-library-only verifier reconstructed the entire score object
from frozen logits, committed truth, and copy ledgers. All rows, counts, gates,
bindings, and the rejection decision matched exactly. It also checked the saved
training trace for the complete schedule, paired input hashes, normalization
exposure, initialization, and unchanged control matcher. It authenticated the
saved replay evidence; it did not rerun inference. The reconciliation report is
`independent-reconciliation.json`, SHA-256
`872365f60a04b62a932a443824d4a0d532dd3564d5f285cc71cb80a5c0cc2d63`;
the verifier is `independent_recount.py`, SHA-256
`52005b9a8b3544a5bd8c2ad62c48f14fb4310a0236f4208e125982c882620dd3`.

## Preserved evidence

Execution artifacts originated at
`/private/tmp/iChartSupportMatchDeferExecution-20261003.KEUEUI`.
The preserved copy is
`/Users/benirossman/.local/share/ichart/recognition-development/support-match-defer-20261003.KEUEUI`.
The receipt, rasters, separate truth, source plan, four final models, full
prediction packet, scores, logs, Simulator result bundle, and executed source
snapshot are retained together. The five principal receipt, prediction, score,
and snapshot hashes below were rechecked after copying. Private ink and profiles
are absent.

| Artifact | SHA-256 |
| --- | --- |
| Fixed protocol | b8bc1c371f3e5cfd60c8f8867e8380148d93d7105ff62289c4ff1b02484d5c33 |
| Data receipt | d0fca2fb74e643101b25247530415ddd2611ff7e0a87bcc99091e53477368e8c |
| Fit receipt | 74574a8db6816150896bfb781905d15f4e2354f84ca499ddd4f9b8f8680c26e7 |
| Frozen predictions | 49183adb624e690c4f50b99e41de1d4616f35ad5cbac51518f7baa3c75243c03 |
| Score | 28037b416f85307a020901fa4061f6d70434a3b120caca26b9a5fe66297987b5 |
| Executed source snapshot | d801b86d20140b548fe8b50dc781c9167ebfbf538221c01176296cbc4c525e31 |

Runtime was Python 3.12.14, Torch 2.7.0 and NumPy 2.0.2, using four deterministic
CPU threads. Worktree: `recognition-generalization-reset/Smart Chart`, branch
`codex/recognition-generalization-reset`, HEAD
`160aa31594903508e241802e21ca83ec447de849`, with unrelated local work preserved.

## Scope of the conclusion

The 21-lesson condition shows useful recognition signal but unsafe automatic
substitution. This experiment does not establish a shippable personalized
reader. Its fixed failed recipe remains rejected. Any successor needs a new
declared development/evaluation boundary; these scored queries cannot become a
fresh validation set. No Swift/Core ML promotion, physical-device installation,
fresh chart-writing score, commit, push, or release is claimed.
