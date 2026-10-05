# Same label handwriting source comparison

This is one fixed, offline test of source diversity for existing chord
components. It substitutes additional literal-label HWRT training drawings for
repeated UJI exposures, without changing the reader architecture, output
vocabulary, grammar, optimization budget, or decoding policy. It is not an
app update or a test of complete-chord accuracy or personal-learning benefit.

These rules are recorded before inspecting the new encoded collision results,
selecting eligible records, or fitting a candidate. No ratio, seed, checkpoint,
threshold, class alias, writer exception, or exclusion may be selected from
prediction outcomes. Unexpected implementation failures must be documented;
they do not authorize changing the experiment's scientific rules.

## Bound sources

Use only the retained 2,439 literal HWRT training records and their frozen
Python raster adapter, plus the existing domain-reject experiment's two
internal writer folds. The parent fitting bundle has 3,104 UJI drawings and
3,095 existing five-shape HWRT drawings per fold. Its 770 shared HWRT queries
must not be admitted to fitting. Preserve the original A16 and B16 writer
membership and both sessions. Do not open the old eight-writer development
cohort, reserved writers, private lessons, chart answers, or official HWRT test
geometry.

Parent data receipt SHA256:
`d835b1e01ec21cdaac4f8882d8ef02309c3cd9960408b45fa17cc74a0b5023d5`.
Parent fit receipt:
`556dbc308fc778ce6273910301b13ab1652742a474ed1a0d000f1ec65ef90bdb`.
The new inventory receipt is
`1f3e7b26c8bf31a884956f5f1fb938e27941c28d6cb0f76ae9085e02e52123be`.
Before fitting, bind this protocol, the new encoded data receipt, eligibility
artifact, full schedules, baseline weights and executed code by SHA256 in a
new immutable run manifest. Output counts and hashes are execution evidence,
not adjustable experiment parameters.

## Fixed copy and conflict handling

Preserve all source records; exclusions create a separate eligible-ID list.
Use raster-byte hashes and the existing eight-decimal normalized-coordinate
fingerprints as two distinct conservative matching rules. The latter is not
byte-exact geometry or a trajectory-model tensor.

Build connected components over the new records and the prior 10,073-row
training metadata using equality of either hash. Prior metadata includes
writers later held out in the internal folds. Ignore all prior-row labels
when deciding eligibility.

1. Exclude every new record in a component touching any prior record,
   regardless of that prior record's label, source or future fold.
2. Exclude every new record in a component touching a selected training path
   in any published HASY pixel-duplicate group. This conservative rule applies
   to all 34 previously identified paths, not just conflicting-label groups.
3. Exclude new-only components containing more than one literal training label.
4. For a remaining same-label component, retain only the lexicographically
   smallest opaque ID; retain each singleton.

Record every applicable exclusion reason, representative and component.
Do not use prediction confidence, held-out labels, or visual reinterpretation
to reinstate an excluded row. All 35 literal classes must retain at least one
eligible record; otherwise stop this experiment rather than silently narrow
its class scope or change the rules. Publish counts and repeated-exposure
multiplicities. This policy does not claim to remove approximate copies or
establish writer independence.

## Matched schedule and model

Reuse the prior frozen 102-way control checkpoints and raw query outputs;
retraining an identical control is unnecessary. Authenticate their receipt,
weights, full schedules, query IDs and input hashes. Do not reuse the rejected
47-way candidate or its scored results.

Start each new candidate from the original seed-29 control initialization,
not the trained control. The complete initial state digest must equal
`d3ccc13b94cce764ddecc31d43d09f155848e6951a4f6c24ad0d10508b4bd332`.
Keep the one-plane Float32 raster input with four exact-zero auxiliary planes,
the same encoder and 102-way classifier, AdamW learning rate 0.001 and weight
decay 0.0001, ordinary unweighted cross entropy, and 30-epoch cosine schedule.

Replay the saved parent epoch row order. Each own-fold UJI record occurs
exactly twice per epoch. For each of the 35 literal-overlap labels, replace
only its second occurrence with a same-label eligible HWRT record; the first
occurrence stays unchanged. All other positions remain unchanged. Cycle each
new class pool in SHA256 order of `same-label-hwrt-cycle-v1`, NUL and opaque ID,
breaking ties by opaque ID. Replacement slot j in epoch e uses
`(32 * e + j) modulo class pool size`, with e zero-based and j following the
saved epoch slot order within that label.

Thus each overlap class has 32 UJI and 32 added HWRT exposures per epoch.
Other old classes keep 64 UJI exposures; each of five existing HWRT shapes
keeps its original 64 exposures. Both comparisons retain 6,528 exposures and
51 batches per epoch, batch size 128, 30 epochs, 1,530 updates and 195,840
total exposures. Replay the original seed-29 affine draw stream; its digest
must be `1fb59eaa47d693eab351ea9b909659fd48b66eb411dd06ac7767a884e7ebeabc`.
Targets, unaffected input slots, augmentation and budget remain identical.
Changed input hashes at replacement slots are expected and recorded, not
misrepresented as identical-input pairing. Use the final epoch only.

## Prediction and assessment

Freeze a common input-only no-copy union using both arms' actual fitting
fingerprints before inference. Do not reuse the old exclusion masks. Keep all
raw queries and report both raw and common no-copy results. Verify that the
reused control outputs correspond to the identical frozen query inputs.
Freeze complete candidate logits or explicit failures before the separate
scorer opens truth. Apply the same existing 102-way control decoding to both
arms; forbidden leaders remain unresolved, with no lower-ranked rescue.

Keep the parent advancement screen unchanged in each fold and copy view:
complete finite outputs, strictly more correct legal UJI readings, fewer total
wrong-legal UJI readings, no worse query writer's correct count, no new
correct/unresolved-to-wrong-legal transition, and no worse mapped HWRT class.
Report corrections, lost correct readings, new wrong readings, unresolved
counts, each writer, each class, and the five shared HWRT shapes separately.
The repeated 770 HWRT queries are one shared cohort, not independent evidence
in both folds. A failed screen prevents promotion; it must not be rewritten
after results are seen.

These public development sources have research history. Passing this internal
screen would justify further evaluation, not general recognition, fresh-writing,
Core ML or Swift parity, on-device personalization, or ship-readiness claims.
Any later user test uses the user's own fresh handwriting in both chart styles;
no additional people are required. App ink, baseline and profiles stay intact.
