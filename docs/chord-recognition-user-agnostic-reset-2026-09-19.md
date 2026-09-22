# User-Agnostic Chord Recognition Reset

Date: 2026-09-19
Branch: `codex/recognition-generalization-reset`
Starting commit: `d3141bf58705962b93043a57aed9ab706f8628c5`

## Decision

Stop tuning the legacy recognizer against the retained handwriting archive.

The existing engine remains a useful product baseline and regression oracle,
but its fixture accuracy and fixed trust score do not measure performance on an
unseen writer. Future recognition work must be selected and calibrated on
writer-disjoint data. The current legacy engine, any learned challenger, and
their trust policy must be evaluated through the same frozen protocol.

This reset preserves the app's non-destructive ink, explicit Render Chords
flow, parser/compendium, PencilKit transform and eraser handling, persistence,
and correction-memory isolation. It replaces the evidence model before it
replaces the recognizer.

## Independent audit consensus

Eight independent read-only audits covered architecture, fixture leakage,
dataset design, primary handwriting research, iPad/Core ML feasibility,
telemetry/privacy, trust UX, and adversarial falsification. They agreed on the
following conclusions:

1. No current result establishes writer-independent accuracy.
2. The archive is development/regression data because it has repeatedly guided
   code changes and has no writer-disjoint holdout.
3. Deterministic transformations of a retained drawing test invariance, not a
   new person or independent sample.
4. The current trust evidence is correlated with the primary recognizer. The
   symbol ledger and scale/rotation/density probes are useful instability
   signals, but they are not independent corroboration.
5. Persistent correction memory can make repeated testing on one installation
   look better or more conservative than the raw recognizer. Base recognition
   and personalized resolution must be scored separately.
6. Privacy-safe production telemetry can measure operational behavior, but it
   has no intended-chord ground truth and therefore cannot measure accuracy.
7. The scalable technical direction is a learned, on-device, compositional
   recognizer with a grammar constraint and calibrated abstention—not another
   expanding forest of chord-specific thresholds.

## Current data-quality findings

The retained archive contains:

| Property | Current value | Valid interpretation |
|---|---:|---|
| Fixture JSON files | 660 | Known-input regression cases |
| Distinct expected chord labels | 212 | Vocabulary breadth |
| Filenames containing `Captured` | 522 | Naming convention only |
| Filenames containing `Device` | 14 | Naming convention only |
| Fixtures with writer ID | 0 | Writer independence cannot be measured |
| Fixtures with session/source ID | 0 | Session leakage cannot be measured |
| Fixtures with dataset split | 0 | No train/calibration/test boundary |
| Fixtures with consent/license provenance | 0 | Not eligible for model training |
| Fixtures with complete cross-stroke chronology | 9 | Timing studies are mostly unsupported |
| Blind writer-disjoint samples | 0 | Population accuracy is unmeasured |

Every fixture has only `name`, expected text/glyph/cluster fields, and strokes.
`Captured` is inferred from a filename substring, and the importer creates that
suffix automatically when a name collides. It is not provenance.

The legacy archive is now classified as:

```text
datasetVersion = legacy-regression-v1
provenance = unknown
evaluationEligible = false
```

All generated variants inherit the source fixture's non-independent status.

## What the existing evidence can still prove

- Stability for the exact retained fixture geometries.
- Deterministic translation, scale, rotation, density, and direction
  invariants on those geometries.
- Parser and vocabulary compatibility for represented chord forms.
- Conservative rejection behavior on the exact tested inputs.
- Specific live-device behavior for a named build, chart, and writing pass.
- Performance for the exact replayed workload and hardware.

It cannot prove cross-writer top-one accuracy, calibrated confidence,
population trusted-error rate, or user-agnostic recognition.

## Architecture boundary

### Keep

- PencilKit transform application and bitmap-erasure visible-fragment handling.
- Page, system, lane, and barline targeting infrastructure.
- Chord parser, canonical representation, compendium, and typed vocabulary.
- Explicit review/no-read behavior and user-triggered Render Chords.
- Source-ink persistence and pipeline-version provenance.
- Local correction memory only as a separately measured, reversible layer that
  may demote or rerank but cannot promote an uncertain base result to trusted.
- Direction-independent geometric invariants such as angle to an axis.

### Quarantine as legacy hypotheses

- Retained-fixture-specific B, D, sharp, minor, plus, diminished, and timing
  thresholds.
- V17-V21 repair policies selected from the visible archive.
- Same-recognizer transformation agreement as proof of correctness.
- The dirty V21 direction-review experiment and retained-plus rule.
- Aggregate fixture pass counts described as trust acceptance or accuracy.

### Replace

- Single-prototype glyph matching plus glyph-specific heuristic thresholds.
- Greedy, irreversible stroke-to-chord and stroke-to-glyph partitions.
- Hand-assigned candidate bonuses presented as confidence.
- Binary `trusted`/`confirm` disposition.
- Review batches that make the user inspect already trusted chords.
- Acceptance criteria that can pass through no-read behavior without reporting
  usable coverage.

## Target recognizer

The leading architecture hypothesis is a compositional, dual-view recognizer:

1. Preserve the actual visible PencilKit geometry after transforms and masks.
2. Generate multiple plausible chord/group boundaries instead of making one
   irreversible upstream split.
3. Encode the online trajectory as normalized point deltas, time deltas,
   pen-up/stroke-boundary markers, scale/aspect context, and a padding mask.
4. Run a compact on-device trajectory model (initially a TCN or small
   convolutional/recurrent encoder).
5. Run a small raster/spatial branch over the same visible ink so a different
   stroke order does not destroy otherwise identical visual evidence.
6. Decode component tokens—root, accidental, quality, extension, alteration,
   slash, and bass—rather than classifying every whole chord as a separate
   class.
7. Constrain decoding with the existing chord grammar while retaining blank,
   incomplete, unknown, and N-best hypotheses. Grammar legality must not create
   visual confidence.
8. Calibrate the complete decoded result on unseen calibration writers.
9. Auto-accept only when the calibrated result clears the frozen risk gate and
   ownership is stable. Otherwise show focused confirmation, candidate review,
   or a true no-read.

The legacy rules engine, a multi-writer DTW baseline, raster-only model,
trajectory-only model, and dual-view model must compete under the same blind
protocol. The learned architecture wins only if it improves writer-macro
accuracy and risk/coverage at acceptable physical-iPad latency.

The first implementation boundary is deliberately pre-model: preserve the
complete prepared trajectory in a deterministic, versioned packet without
resampling, truncation, fixed tensor dimensions, or normalization selected from
the retained archive. Recent dual-view results make trajectory-plus-raster a
credible experiment, not a foregone winner; concrete encoding and architecture
choices still require writer-disjoint development data and ablation evidence.

## Trust and interaction contract

Recognition disposition and target lifecycle are separate concepts.

### Disposition

| Disposition | Meaning | UI behavior |
|---|---|---|
| `autoAccept` | Calibrated, stable, in-distribution result above the frozen threshold | Included in Render Chords without individual review |
| `confirm` | One useful leading candidate, but below auto-accept | One explicit confirmation |
| `candidateReview` | Several plausible candidates with no decisive winner | No preselected acceptance; musician chooses |
| `noRead` | No defensible candidate, unstable ownership, unsupported, or out-of-distribution | Blank/`?`; rewrite or typed entry |
| `corrected` | Explicit post-prediction change | Retain as a local outcome label, not global truth |

An uncertain chord must not cause trusted chords to appear as editable review
rows. A no-read must not prefill a plausible chord that can be accepted by
inertia.

### Target lifecycle

```text
collecting -> stable -> frozen -> committed
```

Once frozen, later unrelated ink cannot change a target's stroke ownership or
interpretation. Reopening requires an explicit edit or ink change inside that
target. Stale generations cannot update a newer or frozen target.

## Writer-independent corpus contract

Every study sample requires immutable metadata:

- lowercase dataset-scoped HMAC-SHA-256 pseudonym derived from a random
  research participant identifier and dataset secret;
- a separate service-stable person-linkage HMAC in protected provenance so the
  same participant cannot re-enter a different dataset role under a new
  dataset-scoped pseudonym;
- capture session ID;
- source versus derivative lineage;
- writer-disjoint split;
- the explicit `writer-independent-capture-v2` capture/evaluation protocol;
- chart style and orientation;
- pace and relative writing-size bucket;
- handedness, Pencil-experience bucket, and construction variation
  (`rootFirst`, `modifierFirst`, or `mixedOrRetraced`);
- coarse device-performance class;
- app build and recognition-pipeline version;
- isolated stroke-payload SHA-256;
- versioned exact/near-duplicate and legacy-leakage cluster ID;
- opaque ground-truth record ID;
- opaque UUID for a revocable consent record.

Labels and raw strokes must live outside the application repository and outside
ordinary production telemetry. The service-stable person linkage remains only
in the protected consent/cohort provenance; aggregate receipts carry only
receipt-scoped writer commitments. All sessions and derivatives for a person
stay in one split across every dataset, not merely within one manifest.
Synthetic variants never increase the independent denominator. All cohorts
must be checked against one protected registry that also contains the legacy
archive/template denylist. Exact hashes plus a versioned near-duplicate scanner
assign leakage clusters before split validation.

The new validator verifies an Ed25519-signed provenance snapshot supplied from
an allowlisted collection-service key. It fails on writer/session overlap,
noncanonical dataset-writer or stable-person hashes, reuse of one protected
person across development/calibration/sealed roles in any registry dataset, a
session mapped to multiple people, inconsistent dataset-writer-to-person
mapping, duplicate exact payloads, leakage clusters that cross writers or
splits, multiple human samples in one leakage cluster, duplicate independent
labels, inactive/revoked consent, consent that is not bound to the canonical
writer and stable-person HMACs, recognition-evaluation scope, and dataset
version, missing or denylisted cohort-registry records, manifest/registry
identity or lineage disagreement, protocol-version mismatch, broken derivative
lineage, lineage cycles, and invalid registry hashes. A manifest author cannot
mint a fresh cluster, rotate a participant's dataset pseudonym to change their
role, or borrow another participant's active consent and still pass validation.

The validator recomputes both registry Merkle roots from the canonical signed
records, requires the manifest to contain every and only evaluation-eligible
row assigned to its dataset, and checks leakage clusters across the complete
signed registry rather than only the selected manifest. The caller must also
supply the current registry and consent roots, minimum monotonic epochs, and a
validation time. That makes an older correctly signed consent snapshot fail
after a revocation or registry update instead of remaining replayable forever.

The validator does not itself discover visual near-neighbors or query a consent
backend. Those are explicit upstream evaluator requirements, represented by the
versioned leakage registry and protected consent-ledger snapshot. Until the
collection service, registry builder, near-neighbor scanner, and production key
custody exist, the schema is a fail-closed contract—not evidence that the checks
have been run on real study data.

## Capture and ground truth

The domain population is musicians and notation-literate users who plausibly
write chord symbols with Apple Pencil. Collection must include both Simple
Chord Sheet and Rhythm Section Sheet, portrait and landscape, multiple device
performance classes, left- and right-handed writers, different Pencil
experience, natural/fast/careful pace, small/normal/large writing, and natural
construction-order variation.

Capture both isolated prompted chords and full realistic rows. Include natural
negative/open-set ink, erasure, rewrite, interruption, retracing, barline
adjacency, row wrapping, same-root consecutive chords, and delayed modifiers.

Ground truth distinguishes:

1. prompted intended chord;
2. writer's immediate confirmation of intent;
3. independent music-literate transcription of the visible ink;
4. adjudication when readers disagree.

Legible-valid samples form the normal accuracy denominator. Human-ambiguous
samples test abstention. Execution errors and technical failures are reported
separately rather than silently discarded.

Before sealed evaluation, a separate Ed25519-signed ground-truth registry must
commit to every and only eligible independent human capture in the manifest.
It contains salted commitments rather than chord text, requires two distinct
music-literate readers, requires a distinct adjudicator when their committed
labels disagree, and freezes both the final-label commitment and legibility
class. The validator recomputes its content-derived Merkle root and requires an
externally supplied current registry version, root, minimum monotonic epoch,
and unexpired validation window. This prevents a manifest author from omitting
difficult labels, substituting one reader for two, silently changing ambiguous
ink to legible, or replaying a stale but correctly signed label snapshot.

## Split discipline

- Assign writers to development, calibration, and sealed-test cohorts before
  augmentation or model work.
- Keep all sessions and derivatives from one writer in one split.
- Hide sealed strokes and labels from implementation code and engineers.
- Evaluate a signed recognizer artifact in an isolated, no-network runner.
- Return aggregate metrics in an Ed25519-signed receipt. Verify it with an
  allowlisted evaluator public key and bind it to the expected sealed split,
  protocol version, evaluation manifest, provenance snapshot, ground-truth
  registry version/epoch/snapshot/root, recognizer and evaluator artifact
  hashes, pipeline/calibration/metric versions, and preregistered gate hash.
- Issue one externally recorded evaluation authorization for one frozen
  candidate and holdout epoch. The receipt must bind that authorization. A
  consumed authorization cannot be reused; another inspection requires alpha
  spending or a replacement sealed-writer cohort.
- Consume a receipt only through the fail-closed evidence boundary: require a
  short-lived, allowlisted-signature freshness checkpoint for the currently
  active provenance and frozen-label snapshots, then atomically mark the
  authorization used and spend its preregistered holdout alpha. A failing gate
  still consumes the authorization; otherwise selective publication can hide
  earlier failed inspections. Alpha is keyed by a stable physical-holdout ID,
  not by rotating provenance or label snapshot hashes.
- If a sealed failure is inspected to guide a repair, burn that holdout,
  promote it to development, and collect a replacement cohort.

A first falsification pilot should use at least 30 entirely new writers and a
sealed cohort of at least 10 writers. This can reject a bad architecture; it is
not a final population claim. A stronger ship-grade study should exceed 100
writers with at least 40 sealed writers and writer-clustered uncertainty.
Learning curves and confidence intervals, not the round number alone, determine
whether more data are needed.

The pilot receipt and gate count only the sealed cohort, so its minimum is 10
independent writers. Development and calibration writers must never be added to
that receipt to reach the 30-writer total-study requirement.

## Metrics

Report natural-frequency and family-balanced sets separately, both pooled and
macro-averaged by writer:

- exact full-chord top-one accuracy;
- correct chord visible in top three;
- component accuracy for root, accidental, quality, extension, alteration,
  slash bass, and repeat;
- target ownership and boundary precision/recall;
- trusted selective risk and trusted coverage;
- confirmation, candidate-review, manual-only, and no-read rates;
- ambiguous/negative false-trust rate;
- calibration error, Brier score, and reliability curve;
- risk-versus-coverage curve;
- mutation rate after target freeze;
- first-preview and stable-preview p50/p95/p99 latency;
- per-writer, chart-style, device, orientation, pace, size, handedness,
  Pencil-experience, construction-variation, and chord-family slices.

Confidence bounds used by a gate must be reproducible from per-writer
sufficient statistics, not accepted as numbers asserted by an evaluator. The
current contract carries receipt-scoped committed per-writer counts and treats
the writer—not the chord attempt—as the independent unit. It recomputes a
one-sided writer-level empirical-Bernstein bound over per-writer rates, with one
preregistered overall family-wise alpha divided equally across exact accuracy,
top-three accuracy, trusted risk, and the companion future-writer pass-
probability bound. A writer with many attempts therefore cannot create hundreds
of fictitious independent observations, and zero observed errors still produce
a nonzero upper risk. The receipt binds the manifest, current
provenance snapshot, separately protected ground truth, and writer commitments
into content-derived Merkle roots.

The writer-level bound is intentionally conservative. Ten perfect sealed
writers cannot establish a sub-0.5% unseen-writer error claim, regardless of how
many chords each wrote. A ten-writer pilot is a structural and falsification
gate: it can reject a weak architecture and exercise the full protocol, but it
cannot pass a strict ship-confidence threshold. Ship claims require a larger
sealed writer cohort, learning-curve evidence, and an analysis plan selected
before opening that holdout.

This bound estimates the mean per-writer rate under the frozen capture protocol.
It is not a worst-writer guarantee and does not directly estimate the chance a
new writer meets a minimum bar. A ship study should therefore preregister a
per-writer pass predicate and an exact lower bound on the population pass
probability as a companion metric. Slice thresholds are point guardrails unless
their own multiplicity-adjusted uncertainty analysis was preregistered.

The gate also binds an explicit list of required strata. Both natural-frequency
and family-balanced populations plus chord-family, component, chart-style,
device, orientation, pace, size, handedness, Pencil-experience, and construction
variation slices must be present with preregistered minimum distinct-writer and
sample counts plus accuracy, coverage, and trusted-wrong limits. The mandatory
`writer-independent-capture-v2` values include the `repeat` component, both
device classes, both handedness buckets, both Pencil-experience buckets, and
all three construction variations. Omitting a hard slice is a gate failure.
Mutually exclusive slices must exactly partition their population overall by
both samples and receipt-scoped writer membership. Externally expected slice
identities, human counts, distinct-writer counts, and writer-membership Merkle
roots must match the signed receipt. Component slices may overlap, but each
remains bounded by its population overall. A prolific writer therefore cannot
make a difficult stratum look independently covered.

No-zero-error claim is absolute. With zero errors in `n` approximately
independent observations, the rough one-sided 95% upper bound is `3/n`; writer
clustering makes uncertainty larger. High trusted precision must always be
paired with a minimum useful coverage gate so rejecting everything cannot pass.

## Initial falsification gates to preregister before the first sealed pilot

These are point-estimate, safety, coverage, and systems targets for a structural
pilot, not current results and not a population-accuracy claim. Strict
writer-level confidence thresholds belong to the later ship gate and are
expected to fail with only ten sealed writers. For example, ten of ten passing
writers has a 74.1% one-sided 95% marginal lower bound, but only a 64.5% lower
bound when the same .05 overall error budget is split across all four gate
claims:

- zero observed trusted wrong reads on human-legible pilot samples;
- zero trusted outputs unsupported by reader consensus on ambiguous/negative
  samples;
- at least 85% exact primary accuracy overall;
- at least 95% correct-in-top-three recovery;
- at least 55% trusted coverage overall and 35% for every sealed writer and
  chart style;
- no more than 2% combined execution/technical failures, with all exclusions
  reconciled against the complete sealed manifest;
- at least 98% target-boundary F1;
- zero incorrect mutation of a frozen prior chord;
- recognizer compute p95 at most 150 ms and last-Pencil-up to stable-preview p95
  at most 1.1 seconds on the oldest supported hardware.

The final ship gate must be stricter and chosen before opening the ship holdout.

## Telemetry and privacy

Current production telemetry intentionally excludes chord text and raw drawing
data. It can measure no-read, trust/review distribution, candidate pressure,
latency, and correction categories, but not correctness.

Cloud-backed chart `sourceInkData` is application data, not consent for model
training. It must not be repurposed.

A prompted benchmark can initially compute correctness on-device and upload
only content-free aggregates under explicit study consent. Raw-stroke donation,
if needed for training, requires a separate opt-in research surface, consent
ledger, authenticated ingest, private storage, access auditing, retention and
deletion enforcement, dataset lineage, and refreshed privacy disclosures.
Ordinary telemetry must remain separate.

## Implementation sequence

1. Reclassify the current archive as legacy regression and remove acceptance
   semantics. The historical XCTest class name remains only so old focused
   commands still execute tests instead of returning a false green with zero
   selected tests. **Implemented in this branch.**
2. Add writer/provenance/split/derivative manifest validation and CI leakage
   contract tests. **Implemented in this branch, including signed provenance,
   recomputed Merkle roots, current checkpoint/expiry enforcement, complete
   eligible-membership reconciliation, service-stable cross-dataset person
   linkage, global role/session leakage checks, full-registry geometry leakage
   checks, consent-to-writer/person/scope/dataset binding, explicit v2 capture
   metadata, and registry-to-sample binding; the real near-neighbor scanner,
   protected cohort registry, consent service, and production key custody remain
   to be built.**
3. Define a signed aggregate evaluation receipt and isolated evaluator
   interface. **The aggregate schema, cryptographic verification, artifact/split
   binding, signed/current ground-truth registry contract, dataset-component and
   receipt-scoped writer commitments, per-writer sufficient-statistic
   reconciliation, per-hard-stratum distinct-writer coverage, writer-unit
   uncertainty bound, zero-trusted-wrong rule, mandatory v2 diversity slices,
   population/slice reconciliation, one-use authorization identity, exact
   writer-pass probability bound, and preregistered four-claim family-wise gate
   binding are implemented in this branch. Labels and ink remain outside the
   receipt. A fail-closed consumption boundary plus a lock-atomic reference
   ledger now reject independently signed receipt replay, same-holdout alpha
   overspending, stale/revoked provenance or label checkpoints, and selective
   replay after a failed gate or an authentic malformed receipt. Durable
   external transactional storage,
   collection/label/freshness services, the isolated evaluator, and production
   evaluator/freshness-key custody are not yet built.**
4. Preserve a canonical, versioned snapshot of stroke-to-target ownership at
   recognition preparation time. **Implemented in this branch with stable
   pre-barline-fragment indices and explicit source-stroke, barline,
   target-owned, and unassigned-fragment evidence. The snapshot is diagnostic
   evidence only: it does not change candidates, confidence, trust decisions,
   UI, persistence, telemetry, or claim improved accuracy.**
5. Preserve prepared trajectories in a versioned, deterministic, lossless
   packet before selecting model features. **Implemented in this branch with
   exact point/stroke order, stored bounds, timing availability, coordinate
   space, and IEEE-754 values. It performs no normalization, resampling,
   truncation, feature selection, model inference, live integration,
   persistence, or transport. The packet is raw handwriting data; validity or a
   byte digest proves neither consent, provenance, writer independence, label
   correctness, nor recognition accuracy. Its digest identifies exact stored
   bytes, not semantically equivalent trajectories, and must not be used as the
   near-neighbor or leakage identity.**
6. Build an explicitly consented prompted-capture pilot that disables
   correction memory and records base versus adapted outcomes separately.
   **An isolated, local-only Recognition Study engineering app is implemented
   with prompted capture, lossless trajectory storage, base-result review,
   explicit execution-error/ambiguity/technical-failure outcomes, crash-safe
   recovery, and correction/adaptation fixed off. It intentionally cannot claim
   consent, provenance, corpus eligibility, or writer independence. The
   consented collection service and independently adjudicated corpus remain
   external work.**
7. Split trust into structured dispositions and fix all-draft review batching.
   **The learned-route contracts now represent calibrated auto-accept,
   confirmation, candidate review, and no-read separately and fail closed when
   artifacts or receipts are absent or invalid. No learned route has production
   authority in this branch, so the production UI has not been switched to an
   unproven policy.**
8. Add a frozen target lifecycle and cooperative cancellation. **Implemented
   for draft recognition: targets progress through collecting, stable, frozen,
   and committed states; exact prepared-stroke ownership prevents unrelated
   later ink from retroactively changing a frozen draft; no-read results retain
   ownership; and cancelled targeting publishes no partial alternative set.
   Multiple boundary partitions are preserved as canonical, deduplicated,
   observation-only hypotheses while the legacy selected partition remains the
   sole production authority.**
9. Establish classical, raster, trajectory, and dual-view shadow baselines.
   **Implemented as deterministic Python comparison baselines and ablations,
   including a development-writer-only DTW baseline and an external legacy
   result adapter. They have not been evaluated on a real writer-disjoint
   corpus, so this is executable infrastructure rather than a quality result.**
10. Train and convert the leading model to Core ML with fixed, versioned input
   encoding and an explicit unknown class. **The strict corpus-v2 loader,
   deterministic dual-view training/checkpoint pipeline, no-read supervision,
   versioned Swift feature/runtime contracts, calibration command, and Core ML
   export/compile smoke path are implemented. No eligible independent-writer
   corpus, trained weights, calibrated artifact, or promoted production model
   exists yet.**
11. Calibrate on unseen writers, then run the sealed holdout once per frozen
   candidate. **Calibration, writer-micro/writer-macro reporting, selective-risk
   metrics, signed receipt validation, and one-use holdout authorization
   contracts are implemented and fail closed. This step is not complete in the
   evidentiary sense because no unseen-writer calibration cohort or sealed
   holdout has been collected or run.**
12. Run multi-writer physical-iPad acceptance in both chart styles, followed by
    persistence, erasure, responsiveness, and release regression gates.
    **Not started: the isolated Study target builds for arm64, but it has not
    been signed and run on the physical iPad, and no multi-writer acceptance
    evidence exists.**

The software-side foundation through model export is therefore implemented and
testable. Recognition-quality promotion remains deliberately blocked on new
people, independently adjudicated data, a frozen trained artifact, calibration,
one sealed evaluation, and physical-device acceptance. Passing repository tests
must not be reported as completion of those external evidence gates.

## Primary references

- Graves et al., *Unconstrained On-line Handwriting Recognition with Recurrent
  Neural Networks* (BLSTM/CTC):
  https://proceedings.neurips.cc/paper_files/paper/2007/file/4b0250793549726d5c1ea3906726ebfe-Paper.pdf
- Carbune et al., deployed Gboard online handwriting recognition:
  https://link.springer.com/article/10.1007/s10032-020-00350-4
- Lodh et al., 2025 preprint on jointly using online trajectories and offline
  raster features (architecture hypothesis, not validation for this app):
  https://arxiv.org/abs/2506.20255
- Oh et al., writer-independent online music-symbol recognition and stroke-order
  sensitivity: https://link.springer.com/article/10.1007/s10032-017-0281-y
- Guo et al., calibration of modern neural networks:
  https://proceedings.mlr.press/v70/guo17a.html
- Geifman and El-Yaniv, SelectiveNet:
  https://proceedings.mlr.press/v97/geifman19a
- Cattelan and Silva, post-hoc confidence estimators for selective
  classification under distribution shift:
  https://proceedings.mlr.press/v244/cattelan24a.html
- Maurer and Pontil, writer-unit empirical-Bernstein construction used by the
  preregistered mean-rate gate:
  https://www.cs.mcgill.ca/~colt2009/papers/012.pdf
- Clopper and Pearson, exact binomial confidence construction for the companion
  new-writer pass-probability gate:
  https://doi.org/10.1093/biomet/26.4.404
- HOMUS online music-symbol dataset:
  https://grfia.dlsi.ua.es/homus/
- IAM-OnDB writer-independent evaluation precedent:
  https://fki.tic.heia-fr.ch/databases/iam-on-line-handwriting-database
- Apple Core ML documentation: https://developer.apple.com/documentation/coreml
