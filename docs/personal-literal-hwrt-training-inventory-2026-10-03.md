# Additional literal chord component training coverage

The existing public HWRT source contains 2,439 training recordings with exact
labels matching 35 of the 41 original allowed chord fragments. The new intake
retains and authenticates those recordings without changing the app vocabulary,
fitting a model, or reading private ink. This makes a same-label, multi-source
training comparison possible to investigate; it does not establish that such a
comparison will improve recognition.

The preceding [domain-reject candidate](personal-domain-reject-results-2026-10-03.md)
was rejected. It must not be promoted on the strength of this source inventory.
The installed complete-chord boundary remains separate: unsupported complete
readings are rejected, while components such as `1` and `j` are allowed only
where valid chord grammar uses them, such as `C11` and `Cmaj7`.

## Coverage and selection

Selection is exact equality between a native source label and the frozen
allowlist. There is no case folding, TeX unescaping, visual alias, or new mapping.
All 35 classes were outside the previous missing-shape geometry intake.

| Coverage check | Observed result |
| --- | --- |
| Original allowed fragment labels | 41 |
| Exact native-label matches | 35 |
| Selected official training recordings | 2,439 |
| Uppercase chord roots covered | A, B, C, D, E, F, G |
| Missing literal labels | `%`, `(`, `)`, `.`, `t`, `º` |
| Selected geometry-invalid or timing-issue records | 0 |
| Selected exact raw-data or coordinate-serialization duplicate groups | 0 |

The existing five additional mapped shapes remain separate. Together with the
35 literal labels, their previously retained 3,865 training drawings would give
6,304 HWRT drawings across 40 model labels and 43 native IDs. This arithmetic is
coverage only; no combined training bundle was built in this pass. It does not
mean the six absent literal labels lack every possible equivalent encoding.

## Training only intake

The new `hwrt_literal_training_inventory.py` pins the original archive, prior
source receipt, full native-class metadata, and chord-domain bytes. It checks
the exact three archive members and reconciles all 151,159 training rows across
369 native classes. It parses trajectories only for the selected training
classes. The test member is hashed as bytes, not parsed as CSV or geometry, and
no test recording is emitted.

Selected coordinates and timestamps remain unchanged. Records retain native
IDs, training ordinals, opaque archive-bound record IDs, raw-data hashes,
coordinate-serialization hashes, and issue flags. Raw user IDs are not emitted.
Invalid rows would be retained, not silently dropped. The duplicate ledger is
explicitly restricted to selected training rows; its zero train/test-crossing
count must not be read as a cross-split check.

## Image collision qualification

The independent check intersected each selected training ordinal's
creator-defined image path with the existing authenticated full HASY pixel
ledger. It found **18 identical-image groups touching 34 selected training
paths**, including **nine native-label-conflict groups**. Five groups cross the
creator train/test boundary. This check used existing metadata and the pixel
ledger, not newly opened test geometry or image files.

The 34 affected training paths comprise 23 labeled `-`, two `1`, two `i`, and
seven `l`. Nine selected paths occur in conflicting-label groups and 13 in
cross-split groups; these subsets are not disjoint. No records were discarded.

These published-image collisions are not contradicted by zero exact trajectory
duplicates. Normalization can erase differences between distinct recordings.
They do not establish identical app-encoded inputs, actual copied handwriting,
the same writer, or recognition errors. HWRT and HASY represent the same source
recordings, not independent datasets. Source user IDs do not establish writer
independence; redistribution and model-shipping rights remain uncleared.

## Verification and next decision

Five focused synthetic tests passed with warnings treated as errors, zero
failures and zero skips. They cover literal selection, test-parser exclusion,
source/count/hash mismatches, retained malformed geometry, timing separation,
duplicate reporting, and output exclusivity. The real extraction then exited
successfully. A separate implementation review found no additional execution
blocker. Independent saved-artifact reconciliation reproduced all selected
record identities, counts, coordinate hashes and image-ledger intersections;
it was not a second independent extraction of the archive.

The next bounded step is to compute collision groups in the actual application
input representation and freeze copy/conflict handling before any fitting.
Then, if the data remain suitable, compare an unchanged baseline against the
same reader trained with additional same-label examples. Do not add a new
architecture, output policy or writer-specific exception to that comparison.
Reused public development evidence remains internal screening, not fresh
validation or a shipping decision.

No model fitting, inference, feature encoding, app source change, build,
installation, profile change, teaching, chart edit, or release occurred here.
The handwriting-evaluation and data-quality guidance kept source preparation
separate from accuracy and personalization claims.

## Reproducible evidence

Worktree: `codex/recognition-generalization-reset` at
`160aa31594903508e241802e21ca83ec447de849`, with existing changes preserved.
Runtime: Python 3.12.14. The scoped implementation and tests are under
`recognition_ml/ichart_recognition_ml/research/` and `recognition_ml/tests/`.

Durable run evidence is retained at
`/Users/benirossman/.local/share/ichart/recognition-development/hwrt-literal-training-20261003.6hZNYg`.
The original archive and source metadata remain in the prior
`hwrt-source-intake-20261003.hFiI3y` evidence directory.

| Artifact | SHA256 |
| --- | --- |
| New inventory module | `4902d36138826cd6903b3c9423b946dd99b8c472150e10749439e68d119ef0a5` |
| New synthetic tests | `f55fe68f754ebe825304b2ea941f83142d3dd6ce7f7b0185be2c7624fb4b186d` |
| Inventory receipt | `1f3e7b26c8bf31a884956f5f1fb938e27941c28d6cb0f76ae9085e02e52123be` |
| Selected training records | `3288da7e34071539e87882c8a10eeb6ed8acad1aadfc97ba7522248679954521` |
| Source HASY pixel ledger | `9fc0a0a41cfff52c73eac50dd470c430901b1a84e5d1739293360e557cbc8336` |
| Independent reconciliation report | `9d161ac0385a85cc431353ab31089bfc38007366931a40027644c97c1eb1013c` |
