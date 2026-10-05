# Offline decoder grammar cache

## Scope

This small performance-only change was implemented **after** the fixed
whole-chord factor experiment completed, failed its screen, and was preserved.
It does not change that verdict, an iPad recognizer, a trained model, a profile,
ink, acceptance thresholds, no-read behavior or personalized learning.
No build/install, commit, push or deployment occurred.

`recognition_ml/ichart_recognition_ml/decode.py` now caches only immutable
valid suffix topology in a bounded eight-entry LRU keyed by the exact quality,
extension and alteration label tuples. Every input's probabilities, alteration
subset scores and ranking are recomputed. Quality/extension/mask traversal,
left-associated floating addition, canonical ties and all ten output heads
remain unchanged. No inputs, user information or recognition results are cached.

## Verification

The root executed the existing and new decoder tests with warnings as errors:
**13 tests, zero failures, errors or skips**, exit code 0. Tests include exact
full `DecodeResult` parity against an uncached suffix reference, ties, synthetic
factor-grid/random logits, count clamping, malformed contracts, immutable
topology, separate contract keys and cessation of topology parser work after
warmup. Independent read-only source review found no semantic blocker.

The implemented decoder also reproduced all **16,128** frozen raw prediction
rows and **48,384** ordered candidate strings/floating scores exactly, without
an epsilon. Input/packet and implementation hashes were unchanged before/after.
This read raw logits and their stored decoder outputs only—not source truth,
private ink or model weights—and did not rerun model inference or accuracy
scoring. The packet parity check took about **17.75 seconds** for decoding.

A separate isolated benchmark decoded 192 synthetic ten-head rows twice per
arm. The preserved uncached decoder took **11.3633 seconds**, the implemented
decoder **0.4746 seconds**: **23.94x** faster in this benchmark, with exact
candidate and no-read score equality. This is offline evaluator performance,
not measured app, Pencil, end-to-end model or user-visible latency.

## Bound evidence

- Preserved original decoder SHA-256:
  `f5de03f74d6011478c0737fd2fb775632b8bef1d68c61cd025250f551fa3b161`.
- Implemented decoder SHA-256:
  `2bcfa27a870658b2e3b775b4571cb347fe6c5f5a1b23ab9217a75ff8e36c2b8b`.
- New tests SHA-256:
  `fde76236d203595cf7161cb2e16cb346a866f78fb1e0ce24278ba5de569fe493`.
- Root gate receipt SHA-256:
  `8c36bcede0a9e98c966d7efe9117e8d4d8531674f140b4c1460b3da56151619d`.
- Implemented benchmark receipt SHA-256:
  `66c5b3fc330bc19f747805046ccafc6b19aa8e651fb8772ca5fc885caf2348e3`.
- Implemented full-packet parity receipt SHA-256:
  `7ddc0320e7984368e94d1e8ac8585eba0a640ed046f01dfaaaaa3dcd8284807e`.

Execution helper, receipts, test log and changed-source snapshots are permanently
preserved at
`/Users/benirossman/.local/share/ichart/recognition-development/decode-grammar-cache-20261002.ChLqJC`.
The exclusive copy and a separate root byte-for-byte check verified **10 content
files / 52,173 bytes**; tree SHA-256
`ed47c3a414e32fe9c989e68f93ec08d81ba248761cda16e59a0e6095875fb274`.
The additional preservation manifest SHA-256 is
`6007031aabd17c6a4be8a620dd3e353f5a270413963faf138bb5c01ebb242d15`.
The preserved document snapshot precedes this confirmation. The old decoder
and raw packets remain in the separate immutable
`whole-chord-factor-20261002.K5sEY4` experiment; no files in that tree changed.

The remaining recognition-quality step needs natural complete chords across
independent writers and explicit learning/support versus fresh-query separation.
This efficiency work supplies no evidence of accuracy or learning benefit and
does not authorize another private-answer-tuned or synthetic-template rescue.
