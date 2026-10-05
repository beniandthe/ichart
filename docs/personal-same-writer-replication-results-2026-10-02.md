# Fixed same-writer replication — scored result

## Decision

The predeclared original-residual 34→37 criterion passes: one correction in
each chart style, zero correct-to-failed regressions. Both corrections are
fresh D-flat-7 inputs. This repeats a local lesson-transfer signal, not general
recognition quality or shipping readiness. Experimental ML remains behind the
captured native reader and stays comparison-only.

Branch `codex/recognition-generalization-reset`, HEAD
`160aa31594903508e241802e21ca83ec447de849`, existing dirty worktree preserved.
Capture used iChart 1.2.1 build 55 on the paired physical iPad. The model recording
used the separately pinned Swift/Core ML Simulator comparison described in the
[unchanged experiment contract and freeze handoff](personal-same-writer-replication-protocol-2026-10-02.md).

## Fixed outcomes

All cells are correct / wrong non-null read / no-read counts on six labelled
captured targets per style. No alternate hypothesis or lower-ranked candidate
was selected after labels. These are not calibrated or across-writer accuracy
percentages, and automatic glyph ownership remains unverified.

| Method | Simple | Rhythm |
| --- | ---: | ---: |
| Captured native baseline | 6 / 0 / 0 | 6 / 0 / 0 |
| Captured native profile 37 | 6 / 0 / 0 | 6 / 0 / 0 |
| Shared ML | 3 / 0 / 3 | 1 / 0 / 5 |
| Original residual, profile 34 | 4 / 0 / 2 | 2 / 0 / 4 |
| Original residual, profile 37 | 5 / 0 / 1 | 3 / 0 / 3 |
| Linear anchored, profile 34 | 3 / 0 / 3 | 1 / 0 / 5 |
| Linear anchored, profile 37 | 3 / 0 / 3 | 1 / 0 / 5 |

Primary 34→37: two no-read→correct changes, zero regressions and no other chord
output changes. The shared→original37 comparison gives four corrections, but
includes historical personalization and is not the three-lesson effect.
Anchored 34→37 has no changes. Native/profile readings are identical, so this
does not demonstrate a native live personalization gain.

The user saved six written chords and six labels in each run, no grouping flags
or query teaching. Every target is eligible: no known-ink, missing-original-input,
missing-written, extra-captured, unassigned-source or barline-source exclusion.
User experience flags report no slow ink or unexpected earlier-chart changes;
these are user reports, not instrumented latency/stability measurements.

## Input and scoring audit

The completed journal differs from its stopped-unannotated source at exactly
22 permitted paths: 12 intended-label additions and ten completion/count/
experience fields. All 18 historical runs are structurally unchanged. Every
source/ink snapshot, native prediction/action, frozen profile/lineage, timing,
record identity/order and teaching field remains unchanged. Live profile bytes
still match the same 37-example checkpoint. Queries remain untaught holdouts.

The existing deterministic scorer completed successfully without inference,
support fitting, parser rescue or model changes. An independent calculation
without importing the scorer reconciled all seven bound inputs, complete
12-target coverage, all target rows and method counts, and both primary paired
changes. It independently applied the fixed positive-net-in-each-style and
zero-regression rule. The prior one-test model recording, three-test composition
and fourteen-test scoring-contract gates remain separate engineering evidence.

The pre-writing refreshed-map limitation, non-independent labels and unverified
glyph ownership recorded in the protocol remain material. Passing the numeric
criterion does not erase them. No physical app rebuild/install, profile write,
teaching, render, commit, push or production change followed from these scores.

## Bounded failure evidence and next boundary

All twelve fixed automatic arms returned complete ranks with available anchors.
The remaining original-37 failures are invalid complete first-choice token
streams, not missing model invocation: one Simple and three Rhythm no-reads.
Their symbol hypotheses include minor `m`→`n`, `9`→`1`, `7`→`>` and root
`B`→`8` confusions. This identifies a symbol-evidence/composition boundary;
it does not independently establish the true glyph partition or justify replacing
these characters with the intended answers.

The current profile has zero explicit glyph examples for `m` and `9`. Both are
already supported by `PersonalInkProfile.glyphLabels`, the setup symbol catalog
and explicit symbol-teaching UI. Missing local support is a measured coverage
gap, not proof that two additional lessons will resolve the four failures or
that existing `B`/`7` lessons handle every variation.

This ends the fixed three-lesson replication. Do not retune it, teach these
evaluated queries, select a new winning head or promote ML because it passed a
relative-learning gate. A separately frozen coverage/variation experiment may
use new explicit symbol lessons and genuinely fresh compositions; it must retain
untaught controls, all failures and the baseline. No other people are required
for that local learning test. Across-writer evidence and the full goal remain
unfinished, and no personal answer-specific recognition rule was introduced.

## Evidence

Private source/labels, seven pinned inputs, request, copied scorer source and
score are retained outside Git in
`/Users/benirossman/.local/share/ichart/recognition-development/same-writer-replication-score-20261002.05ZTkR`.
The frozen ranks/compositions and exact code/model snapshots remain in the
previously identified freeze/readiness checkpoints.

Completed journal SHA256:
`029960f14774796a71ab10c9d09c753a909908c2324d0bbde64ce4d484bffcad`.
Scoring request SHA256:
`25ec242bf87d745eddda2ebd50d95e893ab4f1b7cbdb13f4de3eaf633f27fb97`.
Score SHA256:
`02d5bbe1ecce06fa45d7c236859221cc9012aaccfdd54ff5ae4504415c153592`.
Scorer SHA256:
`06a8278ce438e911212d62b545b9d3b4596fd0dc1df279dbd192b33209780197`.
