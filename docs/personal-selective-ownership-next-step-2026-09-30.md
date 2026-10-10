# Next ML boundary: selective ownership, not another weight ablation

Design note only. No new architecture, risk level, calibration threshold or fit
is selected here. V1–V4 remain rejected and immutable. The current eight public
development writers are observed development evidence, not a fresh quality test.

## Structural problem established by source

`stroke_affinity.partition_from_logits` validates the complete pair table,
starts with singleton groups and greedily merges the pair of groups with the
largest positive aggregate cross-edge logit. It returns one complete partition;
there is no unresolved outcome. For a two-stroke input, its single positive
edge necessarily merges the strokes. Do not overgeneralize this to every
two-owner multi-stroke input: negative aggregate edges can prevent later merges.

V4's counts do not establish that changing the decoder alone would repair its
errors. They do establish that this weight-only candidate remains unsafe under
the frozen gate. Continuing weight/seed/threshold searches on the same observed
cohort would not establish user-agnostic recognition.

## Proposed contract to develop before another fit

The research ownership boundary should be explicit:

- `resolved`: one supported, complete partition with a provenance receipt.
- `unresolved`: competing partitions, insufficient evidence, incomplete search,
  or unsupported input, with original strokes preserved.

A structurally valid partition is not automatically a trusted partition.
Uncalibrated logits, very large margins, numerical parity and passing toy tests
must not authorize `resolved`. A future scoring/search implementation must
state its candidate universe and completeness limits. If it cannot support its
decision for an input, it returns unresolved rather than claiming certainty.
This contract can be built and toy-tested without spending reserved or private
writer evidence or modifying the app's current recognizer.

Continue the ML/personalization direction, not an alternate OCR engine:
lossless strokes → ownership evidence → resolved groups or review → shared
visual representation → optional personal prototypes/head → chord grammar and
trust/review. Personal teaching may help symbol identity inside an accepted
group. It must not force ownership, override grouping uncertainty, change
source strokes, or erase unresolved ink. Generic/personal disagreement remains
reviewable. Current isolated-character encoder evidence is not full-chord proof.

## Research rationale and limits

The primary [graph-decomposition paper](https://arxiv.org/abs/1812.09737) combines
learned graph evidence with cycle constraints and higher-order potentials. It
supports investigating structured partition scoring rather than only independent
edge decisions. Its reported tasks are not chord handwriting; this is a design
inference, not evidence of recognition improvement here. No particular graph
architecture or approximate solver has been selected for iChart.

[Conformal Risk Control](https://arxiv.org/abs/2208.02814) develops expected-risk
control for monotone losses and generalizes split conformal prediction. It may
inform a later selective decision protocol. It does not provide perfect reads
for this app. A risk policy, its statistical assumptions, calibration units and
fresh calibration population must be declared before outcomes are inspected.
No cutoff or risk level is chosen from V1–V4 results in this note. Approximate
candidate search cannot silently claim coverage of omitted partitions.

## Required evidence after the contract

Freeze the architecture/loss/search/calibration method and capture protocol
before another selection run. Fresh natural full-chord writing in both chart
styles must remain separate from pasted public-character compositions. Assign
writer-disjoint training, calibration and sealed test roles before derived input
construction. Annotate ownership independently from the model's output and
intended chord answer, with review/adjudication rather than accepted-answer
shortcuts. Keep personal support and evaluation queries in different sessions.

Measure ownership, visual reading with oracle ownership, visual reading with
predicted ownership and generic-versus-personalized reading separately. Retain
per-writer gains, harms, unresolved coverage and false merges; repeated contexts
are not independent writers. The 20 reserved UJI writers remain sealed now and
would only be a secondary public component gate, not natural-chord validation.

No new iPad handwriting is requested for this design note. Another writer and
separate natural-chord evidence will ultimately be required for the quality
claim, while contract and capture tooling can proceed without that claim.
