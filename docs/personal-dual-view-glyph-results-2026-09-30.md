# Dual-view shared glyph ML: completed development experiment

The frozen dual-view candidate passed the predeclared matched-architecture
development gate. It did **not** establish better recognition than the older
operational encoder, safe personalization, fresh-writer accuracy or full-chord
recognition. Retain it as a research candidate; do not promote it to live
acceptance.

## What actually ran

This was actual learning and inference, not a replay of previously saved ranks.
The [protocol](personal-dual-view-glyph-protocol-2026-09-30.md), producer, scorer
and synthetic tests were frozen before fitting. All three arms started with
bit-identical tensors, used the same 30-epoch optimization and saw only the
6,208 public glyphs from 32 training writers. No private ink or accepted user
answers entered fitting. No timing was invented or used.

After all three fits finished, a separate process froze every arm's raw logits
and embeddings on all 1,552 queries from eight already-observed development
writers. Another process then joined labels and scored those frozen outputs.
The 20 official test writers were parsed for source completeness but were not
encoded, transformed or inferred. No seed, checkpoint, rule, architecture or
personalization-method search followed these results.

## Shared-model result

Exact, case-sensitive first argmax over the fixed 97-label vocabulary:

| Arm | Correct / all queries | Exact glyph rate |
| --- | ---: | ---: |
| Matched raster only | 1,035 / 1,552 | 66.69% |
| Matched trajectory only | 1,093 / 1,552 | 70.43% |
| Matched dual view | 1,117 / 1,552 | 71.97% |

Dual versus matched raster produced 168 gains and 86 harms: net +82 correct
glyphs, or +5.28 percentage points. All eight writer-level net changes were
positive. The exact two-sided writer-cluster sign-flip calculation was 2/256,
p = 0.0078125. All four frozen advancement rules passed: gains exceed harms,
p < 0.05, at least six writers non-worse, and worst writer loss at most two
queries. The units of that calculation are eight writers, not 1,552 independent
glyphs. The sign-symmetry/independent-writer assumptions and small cohort remain
limitations, and these writers are not a fresh sealed test.

| Development writer | Raster correct / 194 | Dual correct / 194 | Net |
| --- | ---: | ---: | ---: |
| UJI W04 | 123 | 137 | +14 |
| UJI W06 | 139 | 150 | +11 |
| UJI W08 | 136 | 140 | +4 |
| UJI W11 | 119 | 139 | +20 |
| UPV W35 | 129 | 144 | +15 |
| UPV W43 | 127 | 136 | +9 |
| UPV W47 | 117 | 125 | +8 |
| UPV W56 | 145 | 146 | +1 |

The separately named historical Core ML source-owner result remains
1,229/1,552 (79.19%), 112 correct glyphs above dual. It came from a different
architecture/training regime with augmentation; it is not a matched causal
control. Consequently neither a claim of beating the existing recognizer nor
a claim that trajectory alone caused the gain is justified. The matched arms
have identical nominal parameters, but their input masks change active
representation and effective capacity.

Case-only misses were retained as errors: raster 108, trajectory 109, dual 108.
No grammar alias, intended answer, lower-ranked matching hypothesis or personal
head selected the primary output. These glyph rates are not chord accuracy or
calibrated confidence.

## Novelty diagnostic

The primary retains every query. The frozen secondary copy rules identified
seven queries matching training rasters or trajectories; five also matched
normalized source-trajectory fingerprints. These reasons overlap and must not
be summed. Excluding their union gives 1,545 queries:

| Arm | Correct / novelty queries |
| --- | ---: |
| Raster | 1,028 / 1,545 |
| Trajectory | 1,086 / 1,545 |
| Dual | 1,110 / 1,545 |

The dual/raster pairing still has 168 gains, 86 harms and net +82. These
exclusions were defined without correctness and do not turn the observed
development cohort into fresh handwriting evidence.

## Personalization is still not a safe unconditional replacement

The secondary diagnostic used the predeclared direct one-hot ridge fit,
lambda 0.1, with 97 session-one labeled examples per writer. It predicted each
writer's 97 session-two queries before using their labels for correctness.
This is 776 paired queries, not the 1,552-query primary. It is not the current
Swift residual personal head and does not modify any live profile.

| Embedding arm | Generic correct / 776 | Personal correct / 776 | Gains | Harms | Net |
| --- | ---: | ---: | ---: | ---: | ---: |
| Raster | 514 | 501 | 147 | 160 | −13 |
| Trajectory | 551 | 590 | 139 | 100 | +39 |
| Dual | 572 | 585 | 132 | 119 | +13 |

Dual personalization lost nine correct queries for one writer, despite its
positive aggregate. Raster lost as many as 13 for a writer; trajectory lost as
many as six. These exchanges are inconsistent with a maximum-trust automatic
override. No personalization advancement rule was declared, so selecting a
route from these secondary results would be development-cohort selection,
not independent validation.

Four session-two queries met the frozen training/support-copy exclusion rules,
leaving 772. Generic/personal novelty counts were raster 510/498 (147 gains,
159 harms), trajectory 547/587 (139 gains, 99 harms), and dual 568/581
(132 gains, 119 harms). All raw rows and their copy flags remain in the score.

## Executed verification and retained evidence

- 20 distinct producer/scorer synthetic Python cases and 11 existing
  ridge/source cases: 31 passed, zero failures, zero skips.
- All 90 training epochs completed; all 4,656 arm/query predictions were
  retained. Fit, prediction, scoring and both verification commands exited 0.
- A separate standard-library verifier independently froze saved argmaxes,
  parsed source roles, recomputed the complete primary paired counts,
  per-writer/per-label counts, exact writer sign-flip and gate decision, and
  matched the scorer. It did not independently rerun model inference or the
  personal fits.
- The execution verifier checked all 11 bound source snapshots, source/fit/
  prediction/score hashes, final weight masks and changed trained tensor states,
  30-epoch histories per arm, nonzero distinct test cases and personal-query
  denominators. Source, code and fitted artifacts remained unchanged.
- The regression-triage guidance kept this representation experiment separate
  from app acceptance and answer-specific patches. The hard-truth build
  guidance limited verification to the changed Python research layer: no iOS
  build, Core ML export/Swift parity, device install/launch or UI accuracy claim.

Permanent evidence directory:
`/Users/benirossman/.local/share/ichart/recognition-development/dual-view-glyph-20260930.ttfIcd/`.

| Artifact | SHA-256 |
| --- | --- |
| Public source | `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61` |
| Fit receipt | `ce60efb539ce4d0897e0c339e6d1e1d90485ec07798aa1da499047482724a46f` |
| Frozen predictions | `06cae336f6bd00960a75669cace55fd6d3400a847b9d2e30602c297de4d27328` |
| Score | `898825e57a45bc1467fa17ee7de8bb4407ef3eae7b03c959153400b93d42195c` |
| Independent primary-count receipt | `c4943669cf0e79f6cc77198425391a4baa5e13c748897815b8d5679074abf5e1` |
| Execution verification receipt | `a0b08e96434acc06bc6233823517082fbff4d006b6e24d5e05b407b240180ed6` |

Retain exact executed code, weights, frozen predictions, scores, verifiers and
logs. Do not replace the evidence with a tuned rerun. No live app, user profile
or ink was mutated by this pass. No commit, push or release was performed.

## Next legitimate gate

Retain the dual checkpoint as a research candidate only. Before an app-domain
test, verify its Core ML/Swift numerical contract in an isolated comparison
path. Then predeclare a blind, genuinely fresh-writer isolated-glyph comparison
of this checkpoint, its matched raster control and the operational encoder on
identical untouched examples with independently supplied ownership/identity.
Do not refit on these eight observed writers or choose new rules from their
answers. Obtaining those fresh examples remains an external evidence need.

Full-chord stroke ownership, music-symbol coverage (the public 97-label source
does not supply the full chord vocabulary), optional personal learning,
selective review/no-read behavior, latency, both chart styles and natural-chord
accuracy remain separate requirements. The long-term goal is not completed.
