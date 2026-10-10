# Existing residual learner on frozen dual-view features

## Result and decision

The predeclared primary result is **negative**. With 16 taught symbols per
writer, exact identity changed from **572/776 to 569/776**: 12 gains and 15
harms. Teaching helped the taught classes while degrading untaught classes.
This combination is not promoted into the app or made a default recognizer.
No parameter sweep, conditional exception or second tuned fit was run.

These are public isolated characters from eight already-observed development
writers. They are not the user's saved chart passes, fresh writers, natural
chords, a typical musician setup or evidence of ship readiness.

| Fixed comparison | Shared correct | Residual correct | Gains | Harms | Net |
| --- | ---: | ---: | ---: | ---: | ---: |
| Primary: sparse16, all queries | 572/776 | 569/776 | 12 | 15 | -3 |
| Sparse16: common parent cohort, secondary | 568/772 | 565/772 | 12 | 15 | -3 |
| Full97, all queries, secondary | 572/776 | 581/776 | 11 | 2 | +9 |
| Full97: common parent cohort, secondary | 568/772 | 577/772 | 11 | 2 | +9 |

The sparse support used the unchanged prior public selector, not a set chosen
from errors or chord roots. All 97 labels remained competitors. Its breakdown:

- Taught 16 labels: **95 → 106/128**, 12 gains, 1 harm.
- Untaught 81 labels: **477 → 463/648**, 0 gains, 14 harms.
- Two writers improved, two tied, four worsened; worst writer -2/97.
- Full97 had five improved writers, two ties and one worsened (-1/97).

The fixed 772-row cohort keeps the parent's four full-support copy exclusions
identical across methods. It is a secondary comparability cohort, not a claim
that all four queries are copies of sparse support. All 776 raw rows remain.

The frozen full97 direct-ridge reference scored 585/776. Full97 residual scored
581/776 against it, with 121 gains and 125 harms. That reference is secondary,
has different per-row decisions, and was not refitted or reinterpreted as sparse
teaching. The full-support gain cannot rescue the sparse primary result.

## What this resolves

Earlier dual-view personalization used a replacement classifier; the app's
original ML comparison uses a residual correction to shared scores. This
diagnostic tested that exact existing residual method on the frozen dual
features, without loading/running the encoder or changing its weights.
The sparse regression therefore persists under the app's correction method;
the mismatch alone did not explain it away.

The useful next ML question is how to learn from sparse teaching while preserving
untaught readings. That requires a general training/adaptation objective and
writer-separated evaluation, not rules for this user's accepted chords. Neither
this result nor the previous native runtime-parity pass justifies embedding the
weaker dual shared encoder as the app default. No new experimental learner,
trust threshold or replacement policy was selected from these outcomes.

## Executed and independently reviewable gate

Frozen protocol, implementation and tests were peer-reviewed before actual
fitting. Root independently executed **14/14 synthetic tests**, 0 failures or
skips, warnings treated as errors (9 new diagnostic + 5 unchanged residual).
The standard-library runner completed in 4.145 seconds. A preliminary pytest
attempt executed zero tests because pytest was absent; that tooling log is
retained separately. No package installation or code change was needed.

Then ran three separate CLI processes, each exiting 0:

1. Prepare: validated immutable parents/source, projected 776 explicit support
   records and 776 strictly label-blind query records.
2. Predict: fit only the fixed lambda-0.1, alpha-1, class-balanced residual head;
   froze 1,552 regime/query rows with complete 97-label baseline and corrected
   rankings before scoring. Shared order uses raw-logit first argmax; residual
   ties use the unchanged label order. No query answer enters this process.
3. Score: first validated/recomputed the complete truth-free predictions, then
   joined frozen truth. Every shared top-1 matched the parent prediction.
   Retained raw, per-writer, per-label, taught/untaught and exclusion counts.

Exact validated input/code bytes were checked before and after publication.
The source, fit receipt, parent prediction/score and original dual weight hashes
still match the frozen parents. No shared model inference, reserved-writer
encoding, private handwriting, profile/journal mutation or acceptance occurred.

Evidence root:
`/Users/benirossman/.local/share/ichart/recognition-development/dual-view-residual-20260930.2AifRF/`

It retains all 17 bound source snapshots, actual logs, label-blind plan,
predictions, scoring and final receipts. The separate app gate in `app-gate/`
executed 85 tests with zero failures/skips; see
[learning-integrity results](personal-learning-integrity-results-2026-09-30.md).
Those app checks do not prove recognition quality or a physical-device update.

Independent post-run reconciliation passed: all 1,552 regime rows and 3,104
complete rankings, writer/class/case-confusion subtotals, paired counts and
unchanged four exclusions reconcile. All 17 current/frozen diagnostic bindings,
11 parent bindings and pinned artifact hashes match. The separate review also
confirmed the actual 14-test and 85-test receipts. Its append-only receipt is
`independent-counts.json`, SHA-256
`f77f3c0607c7917b083a8ec6b354f1f4004cf2b71e736091cc9b63af584e3e68`.

Evidence limits: only the nine new Python tests were included in this frozen
source set; the five executed existing residual tests lack historical source
bindings. ProjectConfigurationTests executed 29 cases but its source was not
copied into the app evidence folder. The 85-test gate did not execute
PersonalOwnershipComparisonModelTests. These are explicit scope/provenance
limits, not missing or failed executed tests.

## Artifact bindings

- Protocol: `2ba1be71e20eba3decf86a7367207f0ee76468ba0c5a6883e6b580a824293a8f`
- Module: `c8c5c8d00227353547b0d9ef4865f504f23f6b332a0bfc1fd857e4a92f2770e5`
- Tests: `ebe9cdceb39d56c8a5c8bf9a5f7253538e0ff919e0f6f762229ba45ab2cfa2d0`
- Plan: `395eb856217d8550b62cc5fd8204a8bccc622e53cbc656398da2275773592da1`
- Predictions (13,685,953 bytes):
  `082ae6b394e3344a9ee3130da3441661487af3cf064b00640eccd8fc4f2a70b6`
- Prediction receipt:
  `b4ca17e1d3cc141738d899d67d1cb5b904044a82ccb0d184181a5b6567bd502c`
- Score (1,218,048 bytes):
  `c7f8c499664d8c01622b5d6665afc82440f9204ea7d49273892acf4493b49edb`
- Final verification receipt:
  `70c242305421c154f7a4ad1e34ad014e7f73b394de8a8080b88952b88ded056d`

This turn did not install/sign an iPad build, commit/push, deploy production or
change the recorded user tests. Cross-writer natural-chord accuracy, calibrated
review/no-read behavior and real-device interaction remain open requirements.
