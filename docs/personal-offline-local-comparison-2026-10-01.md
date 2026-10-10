# Offline local-learner connection

## Authorized scope

The user approved adding this separate offline comparison on 2026-10-01.
This is an engineering path, not promotion of a recognition candidate. It does
not alter the live reader, chart rendering, review acceptance, saved profiles,
model weights, or the installed iPad app. No shipping claim follows from it.

The existing natural local-anchor protocol fixes the learner: RBF width
`0.16684838059285878`, regularization `0.1`, per-label balanced lessons, and
zero-residual public anchors for untaught shared classes. The control remains
the unchanged linear anchored head. No intended chord, expected target count,
query label, or selected recognition rule is an input to either fit or query.

## Connection and integrity contract

- Fit only explicitly saved `.glyph` examples, sorted by immutable example ID.
  Whole-chord examples are not decomposed, encoded, or used as fit support.
- Use the same frozen 128-dimensional app raster encoder, public anchor bank,
  ordered shared vocabulary, softmax scores, and zero padding for explicitly
  taught novel symbols in both arms. Missing/incompatible anchors fail closed.
- Retain the complete vocabulary ranking, original stroke indexes, exact
  embeddings/base scores, and their commitments. Rank values are not calibrated
  confidence probabilities or authority to accept/render a chord.
- Reject disabled or changed profiles, including changes that retained the same
  revision, before/after encoding. Preserve the exact profile and source ink.
- Validate any existing lesson provenance against stored ink. Missing legacy
  provenance remains unknown; it does not become fresh, independently acquired,
  or training-eligible evidence.
- Automatic source grouping is the unchanged lossless grouping diagnostic.
  Supplied groups require complete, non-overlapping source coverage and remain
  conditional diagnostics; structural validity is not verified ownership.
- The concrete runtime exporter must load `PersonalInkVisualEncoder`, which
  verifies pinned manifest, package, anchor bytes, model shapes/type, and weights
  metadata. Protocol-injected test encoders do not establish runtime lineage.

## Fixed verification sequence

1. Run synthetic boundary tests for explicit lesson selection, unchanged inputs,
   complete ranks, stale/disabled profiles, malformed source partitions, missing
   or incompatible anchors, and technical failures without fallback.
2. Export the two retained natural captures using the frozen pre-test profiles
   and observed live target partitions. Preserve all nine Simple and eight
   Rhythm attempts; do not repair the false ninth target to improve scoring.
3. Freeze all actual encoder inputs/outputs, fit support, complete ranks, exact
   source/profile/runtime/code commitments, and every invalid/no-read outcome.
   Verify unchanged inputs again before publishing a new artifact.
4. Refit the unchanged Python linear/local references using those exact frozen
   numerical inputs. Compare every rank and score, with maximum absolute score
   error at most `1e-4`. This verifies the Swift connection/head calculation on
   real app features, not independent Python-to-Core-ML conversion parity.
5. Only subsequently join any evaluation labels in a separate diagnostic. The
   captures were already inspected in prior work, so prediction chronology and
   blind annotation are not independently verified. No recognition promotion is
   allowed from this diagnostic; the earlier conditional-owner accuracy gate
   still requires independent ownership/identity receipts.

## Current limits

The exact historical public trajectory/reference/checkpoint files are missing.
The retained compiled Core ML package and public anchors are intact. This new
connection gate does not reconstruct or claim to rerun the missing historical
encoder-parity experiment. Numerical head parity, source preservation, fresh
recognition accuracy, independent writers, physical-device performance, and
shipping readiness remain separate evidence lanes.
