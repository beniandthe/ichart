# Complete-token composer: saved public-rank diagnostic

## Decision

Keep the composer comparison-only. It recovered some parser-eligible matches from lower retained ranks, but also produced grammar-valid hypotheses on many grammar-ineligible source strings. Neither grammar validity nor complete source coverage establishes correct ownership or a trustworthy read. No live recognition, model weights, profile, chart, or acceptance behavior changed in this pass.

This is replay of already-observed public character and mechanically adjacent-character ranks, not natural chord writing, a new-writer gate, or personalized recognition accuracy. The two ownership routes are paired observations of the same queries. Supplied source owners are diagnostic supervision, not an automatic grouping solution.

## Fixed results

Every construction arm retained all 1,552 queries. Only 240 isolated-character strings and 20 paired-character strings were parser-eligible. Eligibility was determined after freezing predictions; it does not establish actual chord intent. The first returned candidate was fixed as the selected hypothesis. Matching any returned candidate remained a separate coverage count.

| Arm / ownership route | Greedy canonical matches | Fixed-first canonical matches | Any-retained coverage | Grammar-valid hypotheses on ineligible strings |
| --- | ---: | ---: | ---: | ---: |
| Isolated / automatic | 207 / 240 | 217 / 240 | 221 / 240 | 253 / 1,312 |
| Adjacent pair / automatic | 14 / 20 | 18 / 20 | 18 / 20 | 60 / 1,532 |
| Isolated / supplied source owners | 219 / 240 | 229 / 240 | 233 / 240 | 279 / 1,312 |
| Adjacent pair / supplied source owners | 15 / 20 | 19 / 20 | 19 / 20 | 52 / 1,532 |

Automatic-route paired counts were 14 gains and zero harms on the parser-eligible subset. There were still seven wrong first candidates and 18 empty results on that subset. Gains occurred for five of the eight already-observed writers; they were not universal. Canonical matching normalizes case and notation aliases, so raw-token matching is retained separately in every row and must not be replaced by these counts.

Independent reconciliation also counted the frozen greedy output on parser-ineligible rows as an exploratory baseline warning comparison: automatic-route grammar-valid presence rose from 18 to 253 isolated queries and from six to 60 adjacent pairs (24 to 313 combined). This is a much larger expansion of hypotheses than the 14 parser-eligible recoveries, but the constructions do not represent actual app chord intent or a calibrated false-acceptance rate. No threshold or selection rule was changed after observing these counts.

Automatic grouping itself was unchanged: exact source-owner partitions were 1,192 / 1,552 isolated queries and 914 / 1,552 adjacent pairs. No correct canonical first candidate in this diagnostic occurred under a wrong automatic partition/order. That zero is not evidence of an ownership resolver or false-acceptance calibration. All hypotheses remained unaccepted and unrendered.

All retained-rank searches completed. Three automatic-pair rows and four supplied-owner-pair rows exceeded the three-candidate result cap. No failed rows were omitted; the observed corpus had zero composer failures. A synthetic 65-stroke complete input verifies that a composer-limit failure remains in scoring denominators rather than being erased by the scorer.

## Execution and evidence

Protocol was fixed before execution: `docs/personal-complete-token-public-replay-protocol-2026-09-30.md`, SHA `17cee56e347990546583cc7ca1a400881f05bfde058d1b01bfb3f44ef20c3d1d`. Input report SHA is `c4b6acc6caf76e0f7d0af9ee8036cd672673f1690e790fee3dcf14fea329c01b`; composer SHA remains `d2988c65de55ee43e8462cbee5063c532f27c43a479c2c1f9307acb92562d288`.

Evidence folder: `/Users/benirossman/.local/share/ichart/recognition-development/complete-token-public-20260930.zmN8SV/`.

- The blind decoding projection excludes expected labels, label-bearing source IDs, writer IDs, personal ranks and correctness fields. Both generic routes for all 3,104 rows were frozen before a separate scoring process joined labels. No model was re-inferred or fitted.
- `predictions.json` is the retained initial packet. Before any scoring, the scorer's over-composer-limit failure guard was corrected and its source dependencies were added to the code snapshot. `predictions-v2.json` binds the corrected harness. All prediction rows are identical between packets; only source metadata bindings changed. Neither packet was overwritten.
- Final prediction SHA: `ead05291feee4519fb04007e32846700ff1cfd42304b8fde9d4785d4e82a07cb`. Score SHA: `b9941fc30bf759c18c0f8baa4f3cbbd2adf0df2c53beead05c5f26181fb4d0ec`.
- Thirteen distinct Swift/macOS checks passed: eleven synthetic checks, one actual 3,104-row freeze, and one separate 3,104-row scoring gate. The iOS app/test bundle built, and 59 distinct focused iOS Simulator tests passed with zero failures/skips. Provided replay/scoring methods were explicitly excluded from that iOS run because they had already executed on macOS; they were not skipped successes.
- No reserved writer transformations/inference, private-data collection, profile teaching, physical-device build/install/launch, release, commit, or push occurred.

## Remaining recognition work

This component cannot repair missing visual evidence or incorrect ownership. The shared learned model, structured stroke ownership and optional personal adaptation still need improvement and independent natural-chord evidence in both chart styles. Do not promote this result into live automatic acceptance, choose an answer-matching candidate after scoring, or report these public parser subsets as user-agnostic chord accuracy.
