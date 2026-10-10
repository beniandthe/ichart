# Conditional visual identity — actual model results

## Outcome

This pass separated automatic stroke ownership from generic visual identity using the same frozen Core ML model. Both remain measured weaknesses. It did not change live recognition, train a model, teach a profile, accept/render/erase ink, or establish new-writer or natural-chord accuracy.

The source-only `readSuppliedOriginalGroups` API preserves original stroke metadata and supplied outer order, validates complete coverage before encoding, and reuses the existing generic/personal/anchored ranking loop. It returns identity hypotheses, not resolved ownership or accepted chords. Historical prediction, learning and selective-unresolved boundaries remain unchanged.

## Fixed execution

Contract: `docs/personal-conditional-identity-protocol-2026-09-30.md`, SHA-256 `ab44700ee24f4e00114b736287898d9beec760aa498714fc7c36e77107a933db`.

Artifact directory:

`/Users/benirossman/.local/share/ichart/recognition-development/conditional-identity-20260930.a2quEt`

- UJI source SHA: `cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61`.
- Same eight already-observed development writers; 1,552 isolated samples and 1,552 fixed adjacent pairs. The 20 reserved writers were not transformed or inferred on.
- Unchanged generic 97-way encoder; package SHA `c51029092ea80e6d2621db4606f7051139177169dc9d036b89c9e74b2f5988f5`. Empty enabled profile; zero glyph/whole-chord support lessons. Primary scores use generic ranks only.
- Isolated points32 and fixed second32-gap8 pair arms. All seven isolated zero-extent glyphs and their fourteen pair occurrences retained; no invented extent or dropped queries.
- Both source-owner and automatic-lossless readings frozen before expected labels enter scoring. No chord-parser or whole-chord inference in the diagnostic.

## Reconciled results

Counts below are exact raw character-token identities, including case, not semantic chord recognition.

| Measurement | Isolated symbols | Adjacent pairs |
| --- | ---: | ---: |
| Queries | 1,552 | 1,552 |
| Complete exact automatic owner partitions | 1,192 | 914 |
| Exact ordered tokens with source-owner groups | 1,229 | 972 |
| Exact ordered tokens with automatic groups | 930 | 561 |
| Source-owner-only correct queries | 299 | 411 |
| Automatic-only correct queries | 0 | 0 |
| Neither correct | 323 | 580 |
| Source glyphs | 1,552 | 3,104 |
| Source-owner top-1 glyph identities correct | 1,229 | 2,458 |
| Exact-owner automatic glyphs eligible for identity scoring | 1,192 | 2,381 |
| Eligible automatic top-1 identities correct | 930 | 1,858 |

The source-owner/automatic difference demonstrates lost raw-token reads from the grouping path in these controlled public inputs. It does not estimate a natural-chord improvement. Even with supplied ownership, 323/1,552 isolated raw identities remain different from source labels. Some differences are case ambiguity rather than a different musical meaning: seven of the eight strict uppercase-C misses were lowercase-c outputs. Do not reinterpret the strict token scores as app chord error rates.

All 3,104 rows, paired outcomes, owner-index partitions, per-writer and per-label denominators were independently recomputed. All 3,573 exact-owner group matches produced identical generic ranks across the two routes, supporting the separation of grouping from identity. Merged/split groups have no desired-answer-aligned single-glyph score. Correct token output and correct ownership are separately scored.

Primary report SHA: `c4b6acc6caf76e0f7d0af9ee8036cd672673f1690e790fee3dcf14fea329c01b`.

## Engineering verification

- Initial SwiftPM focused regression gate: 39 executed, 39 passed, zero failures.
- Actual Core ML/public diagnostic plus source-contract tests: 12 executed, 12 passed, zero failures. The provided-runtime method performed all 3,104 queries; this was not a skipped/mock-runtime success.
- iOS app/test bundle build: initial diagnostic-test expression hit an optimizer type-checking limit; decomposing concatenation and zero-extent counting into typed locals repaired it. The app source and ranking/scoring behavior were not changed by that repair.
- Final isolated iOS gate: **72 executed, 72 passed, zero failed, zero skipped**, confirmed from `ios-focused.xcresult` summary and all per-case identities. Classes: ProjectConfiguration 29; LearnedComparison 21; OwnershipComparison 11; SuppliedGroupIdentity 7; ConditionalPublicIdentity synthetic checks 4. The actual-model method was explicitly excluded here because it had already run on macOS.
- Source/model hashes were unchanged throughout the model execution. Its complete executed diagnostic source is retained as `executed-PersonalInkConditionalPublicIdentityTests.swift` (SHA `1db25720c8f75b2d826f177bd4d173f62f04af79b0e62a9c163fabc491f8ff8c`). After that execution, the test-only compiler decomposition produced final test-file SHA `1ba937f4dbbaf510e65b948372f10c631373887ddda0eff6acf76bf262c806c3`. No actual-model rerun is claimed for the final compiler spelling; the iOS constructor goldens passed.
- All 36 retained V1–V4/Swift source bindings and four ownership checkpoint/training-report hash pairs still match. No rejected ownership model was loaded or promoted.
- Remote fetch/prune was rejected by the environment's approval review; read-only local branch, toolchain and runner checks proceeded. No remote-state refresh, commit or push is claimed.

## Evidence retained

`public-identity.json` has every row, partitions, original-input SHA, readings, source IDs, generic ranks, scoring and source/runtime/code bindings. `inputs-before.json` and `inputs-after-model.json` match. The compiler-only delta is isolated in `inputs-after-compiler-repair.json`; it matches `inputs-final.json` after iOS testing.

`independent-score-review.json` is the initial scoring receipt. The first `independent-input-rank-review.json` ran the added rank assertion but did not expose that check in its unchanged output schema; it must not be cited as a separately described rank-verification receipt. The append-only `independent-input-rank-review-v2.json` explicitly records 3,573 rank-equality checks, every-row reconciliation and its review-script SHA. Earlier receipts remain unchanged.

Build/test logs, source snapshots, verification scripts, and the xcresult summary/test identities are retained alongside the report. No physical-device pull, signing, install/launch, visual app acceptance, production mutation, release or distribution occurred.

## Next ML boundary

Do not tune a fifth ownership fit or symbol thresholds against these eight observed writers. The next intervention needs both broader shared symbol exposure and a structured ownership objective; optional personal adaptation remains downstream, not an ownership oracle or replacement for the shared model.

Before selecting that intervention on natural chords, implement label-blind source-index annotation packets and independently adjudicated ownership, followed by a separate isolated-group identity-label pass. Bind both to the original canonical trajectory packet. Reviewers must not see intended chords, recognizer proposals, accepted reviews or personal profiles. Use new nonsealed writer-disjoint app-domain inputs, freeze predictions before scoring, and retain a separate sealed final gate.

The auxiliary-source audit is in `docs/personal-auxiliary-symbol-source-audit-2026-09-30.md`. HWRT offers genuine additional symbol trajectories but not reliable writer identity; HASY duplicates those recordings as rasters; JAZZMUS has exact-visual-label and noncommercial-license limits. They cannot supply missing independent validation by themselves.

The recognition goal remains open. No additional user writing is requested from this component pass, and no recognition-improvement or ship-readiness claim is made.
