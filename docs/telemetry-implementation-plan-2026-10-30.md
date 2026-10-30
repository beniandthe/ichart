# Telemetry implementation plan: useful findings and handwriting contributions

Date: October 30, 2026. Working branch: `codex/telemetry-feature-contracts`, based on main `2dab8316`.

The required outcome is a completed engineering loop: a feature promises a behavior, a local check records evidence when that promise is contradicted, the service retains and categorizes the finding, and an engineer reproduces, fixes and verifies it. Event volume and a populated queue alone do not demonstrate that the loop improved the product.

This plan includes the user-authorized handwriting-contribution handoff from “Rank three recognition architectures.” That contribution phase is separately scoped and must not delay the first diagnostics/incident-pipeline deliverable. Graph/MyScript remain paused. The contribution plan does not authorize recognition experiments, model or SDK runs, training, recognition builds or installs, raw-contribution activation or deployment, vendor uploads, or repurposing backups. The ordinary aggregate diagnostics backend was separately authorized and activated on October 30, as recorded below.

## Current implementation and evidence

The local implementation is described in [the pipeline operating guide](telemetry-feature-contract-pipeline.md). It adds versioned feature checks, a durable evaluation outbox, deterministic rules, deduplicated private incidents, six task categories, a five-minute worker, delivery/worker health and a read-only task consumer. The instrumented boundaries cover actual library save/load, sampled save readback, comparable source-ink reopen state, render source transfer and reprojection integrity. The export contract has a registry entry; that entry alone is not evidence of client coverage.

Validation and activation are separate. The parent run verified 136 focused iPad Simulator 26.5 tests passed with zero failures/skips on device `165234BC-33C0-48D7-896B-9AD058C13C53`, 25 ingest/schema Node checks, 13 native PostgreSQL checks and 14 Python consumer checks. The final validation record retains the result paths. A local replay of 443 minimally exported, anonymized historical events produced ten investigation/friction groups: seven cloud-operation groups and three correction groups. The rules excluded 129 cancellation, offline and equivalent-spelling events, leaving 314 linked evidence events. These are initial work candidates, not ten confirmed product defects or a reconstructed history of ink loss.

The queue reports distinct operations and affected charts only where valid operation/chart linkage exists, with linkage coverage alongside those counts. Legacy events without that linkage remain unknown; their event or installation counts cannot substitute for affected-chart counts. The parent checked that Graph/MyScript code was not modified.

The local replay does not activate collection, apply a production migration, run a production worker or create external issues. Historical data cannot prove invariants that older clients did not measure.

The subsequent authorized production activation is recorded in the
[backend deployment receipt](qa/telemetry-backend-deployment-2026-10-30.md).
Migration `20261030151740` and ingest version 43 are live. Scheduled runs at
8:20 and 8:25 a.m. Pacific processed 436 historical events and five synthetic
contract checks. The live queue contains ten open investigation/friction groups
supported by 308 retained historical evidence events. Two marked synthetic tasks
were verified and resolved without closing any historical task. Device probes,
raw handwriting contributions and the first actual product fix remain separate
delivery phases.

## Delivery phases and acceptance

| Phase | Work | Acceptance and dependencies |
| --- | --- | --- |
| 1. Validate the diagnostics pipeline | Complete app, ingest, database and consumer checks; inspect emitted envelopes as well as pure detector helpers; retain the anonymized historical replay. | Executed nonzero tests pass. Duplicate/late events and concurrent workers do not inflate evidence; failed evaluation retries visibly; safe rejection, intentional consumption, cancellation and offline behavior are not mislabeled as data loss. Missing delivery or contract coverage remains unknown. |
| 2. Activate the backend — completed October 30 | Applied the reviewed migration and deployed ingest version 43 after explicit authorization, before new clients. Verified private permissions, bounded backfill and real scheduled runs. | Six synthetic raw events were accepted once despite retry, the malformed event was rejected, two failure tasks were created, and passed/protected/ordinary unknown controls created none. Real Cron runs succeeded and drained pending work. Synthetic evidence is marked internal/debug; no historical task was closed. Release-build status still does not establish customer use. |
| 3. Release and verify device diagnostics | Deliver the client containing the new checks through the separately authorized release process. Check consent, opaque chart linkage, source counts, readback/reopen and delivery accounting with fresh device evidence. | Opt-out sends no new diagnostics; withdrawal invalidates queued records and identity; new fields survive ingest. Source ink and existing charts remain intact. The queue shows which contract versions/scopes are actually arriving and which remain unsampled or unknown. App diagnostics continue to exclude raw handwriting and chord text. |
| 4. Close the first product issue | Triage an evidence-backed task, retain a fresh reproduction, implement the bounded fix, and verify the affected behavior on the fixed build. | Record reproduction, cause, change, relevant automated/device evidence and fixed build. Resolve only with verification. A qualifying recurrence reopens the task. A lower event count, empty queue or absence of opted-in activity is insufficient. |
| 5. Design voluntary handwriting contributions | Complete the separate consent, disclosure, evidence, access, retention and deletion design below. | A reviewed implementation specification and disclosure matrix pass the contribution acceptance criteria. No collection is activated by completing this design. This phase does not block phases 1–4. |
| 6. Build and activate contributions, if separately authorized | Implement only the approved contribution specification, validate it with synthetic/local examples, then seek the distinct activation/release authorization. | Consent and deletion end-to-end tests pass; upload work stays outside live Pencil input; incident records hold only an opaque example reference. A release/activation decision names the consent version, allowed purposes, retention and access configuration. |
| 7. Evaluate a frozen recognition candidate, if separately authorized | Define a bounded experiment using an approved frozen dataset and candidate. | A separate instruction names the dataset/candidate, untouched evaluation split, budget and stopping/acceptance rules. Contribution intake or task categorization never starts training, tuning or promotion automatically. Graph/MyScript remain paused until the user changes that instruction. |

## Separate consent and disclosure design for phase 5

The proposed setting is **Help improve handwriting recognition**. It is optional and initially off, independent of **Share app diagnostics**, cloud backup and forum sharing. Refusal or withdrawal must leave normal chart functionality and cost unchanged. Existing backup permission and aggregate-diagnostics permission do not authorize recognition research.

Use two explicit contribution paths. **Share this example** authorizes the displayed, bounded example and its disclosed outcome history; it does not enroll the contributor in continuing collection. A separate optional continuing-sampling choice describes its sampling policy and can be withdrawn independently. An existing saved example requires permission covering that example and purpose before upload; enabling a setting cannot silently scan or repurpose older backups.

Before either choice, explain the exact stroke/region/context data, the fact that authorized people may review it, the evaluation purpose, who can access it, storage/retention, how to stop sharing, and how to request deletion. The initial proposed purpose is debugging and human-reviewed evaluation. Future training use is outside that initial purpose unless explicitly included in a separately reviewed consent version; do not reserve a vague unlimited reuse permission.

Record a consent receipt with purpose, version, presented disclosure version, decision time, allowed mode (single example or continuing sampling), pseudonymous contributor reference and withdrawal/deletion state. An upload grant must be purpose/version-bound, short-lived and checked again at acceptance; a revoked or stale grant must not revive a pending upload. Decide how signed-out contributors can retain a deletion receipt without collecting unnecessary contact details.

Prepare matching in-app explanations, the public privacy-policy change and an App Store privacy-disclosure matrix before activation. Updating policy text alone is not consent. Review every collected type, use, linkage, processor and retention class against the final implementation; voluntary collection is not automatically exempt from App Store disclosure. Pseudonymous contributor/session linkage must not be described as anonymous or automatically unlinked data.

Apple's current privacy guidance addresses collection consent, purpose changes, retention/deletion disclosure and withdrawal. Its App Store privacy guidance requires accurate collection/use/linkage answers. The current iChart policy, last updated October 15, 2026, describes aggregate diagnostics excluding drawing and chord content. The contribution proposal therefore needs an explicit policy/disclosure update rather than being treated as covered by that wording. These source checks guide the release design; they do not establish legal compliance. See [Apple privacy guidelines](https://developer.apple.com/app-store/review/guidelines/#privacy), [App Store privacy details](https://developer.apple.com/app-store/app-privacy-details/) and [the current iChart policy](https://useichart.com/privacy.html), checked October 30, 2026.

## Replayable contribution evidence

Use restricted example storage separate from ordinary telemetry. The ordinary event/incident/task path may carry an opaque `example_id`, contribution availability and bounded technical status. It must not contain raw strokes, chord text, source-content hashes, screenshots or full chart documents. Access to an incident does not by itself authorize raw-example access.

An example must preserve the complete relevant chord-writing region before recognition, correction or Render. The capture should include original strokes with stable within-example identities, source ownership, geometry, dimensions/transforms and available timing. Exclude unrelated chart regions, titles, headers, libraries and private documents. Missing timing or incomplete geometry must be marked, never synthesized as observed input. The exact allowed region and size limits are part of the approved schema.

| Immutable evidence | Required contents and interpretation |
| --- | --- |
| Initial source revision | Source revision ID, original stroke identities/order and data, relevant region, coordinate definitions/transforms, available timing and local capture state. Store immutable object integrity metadata only inside restricted example storage. |
| First attempt | First predictions and candidate/unresolved/error state bound to that source revision, model/pipeline identity and app/build context. A later successful attempt cannot overwrite the initial failure. |
| Correction history | Append selected, typed and grouping/ownership corrections with their source revision, timestamps and actor/provenance. Re-grouping creates a new derived revision linked to the original. |
| Render and persistence outcomes | Link Render, retained/consumed source ownership, actual save, comparable readback/reopen and any failures to the same example timeline. Keep unknown/incomplete outcomes explicit. |
| Labels and review | Store label origin, reviewer verification level, uncertainty and incomplete-case status. A typed correction or final rendered chord is an observed user action, not automatically independent ground truth or evidence that the first read was correct. |

Capture and upload must be bounded and asynchronous. The live Pencil path must not wait for serialization, network access, human review or contribution storage. Use limits for region size, queued examples, bytes, retry lifetime and cellular/background work. On failure or withdrawal, preserve the user's chart/source data while handling the contribution queue according to the disclosed policy.

## Dataset usefulness, access and deletion

Before continuing sampling, record a predetermined policy for ordinary successful sessions as well as failures, with explicit eligibility and inclusion rules. A failure-only collection is useful debugging material but cannot provide a representative accuracy denominator. Record selection reason and probability where applicable, plus missing/incomplete upload outcomes, so a later analysis can identify its population and bias.

Keep protected pseudonymous contributor and session linkage sufficient for deletion and for holding whole contributors out of development. Do not equate account, installation or session counts with verified writers; shared devices and multiple accounts can break that assumption. The linkage map is more restricted than raw-example review. Development and untouched evaluation must not share examples or source revisions from the same protected contributor grouping. Where contributor identity is uncertain, label that uncertainty and avoid claiming writer-independent evaluation.

Deduplicate repeated source revisions and backup-derived copies without merging distinct writing into one example. Preserve the first failed revision, its later derived revisions and correction history. Track uncertain, disputed, unreviewed and incomplete annotations separately from verified labels. Any export must carry purpose/consent eligibility, split membership, provenance and expiry metadata.

Before implementation approval, fill and review an exact retention matrix covering local pending captures, accepted raw objects, annotations, jobs, derived features, dataset exports, operational backups and consent/deletion audit records. Each row needs a numeric retention period, cutoff clock, deletion owner, retry/failure handling and maximum backup-removal delay. Those values are a release dependency; the existing aggregate telemetry retention must not be silently reused for contributed ink.

Withdrawal stops future capture/upload authorization immediately and invalidates queued grants. Deletion must traverse raw objects, annotations, pending/running jobs, derived data and every recorded export; block deleted examples from new exports or job restarts. Maintain an export inventory and minimal deletion tombstone so expired or revoked examples cannot return through a restore. Test operational backup restoration and the disclosed removal delay. If later authorized models are trained, disclose the actual deletion limits and process before that use; do not promise automatic untraining. Initial evaluation-only consent avoids making a training deletion promise that the implementation cannot meet.

## Contribution acceptance criteria and decisions required

Phase 5 is complete only when the reviewed specification supplies the exact schema, sampling/queue limits, access roles/processors, retention matrix, deletion route and disclosure text. Phase 6 activation additionally requires demonstrated tests for all of the following:

1. Both contribution choices start off; ordinary diagnostics, cloud backup and refusal do not enable contributions. Single-example permission cannot authorize later examples or old backups.
2. Consent purpose/version/time and mode survive the full upload path. Withdrawal during capture, queued upload, in-flight upload or job execution prevents unauthorized reuse and is handled as disclosed.
3. A source revision and its first failed prediction replay without being overwritten by correction or successful Render. Original stroke identities, transforms and source ownership remain recoverable; incomplete evidence is visibly marked.
4. Human/typed/selected/model-derived labels retain their provenance and uncertainty. Final rendering is never silently promoted to verified ground truth.
5. Raw examples are inaccessible through ordinary telemetry/task permissions, public links or guessed object IDs. Incident links use opaque references and enforce purpose-bound access.
6. Predetermined successful-session and failure sampling can be audited. Repeated source revisions are deduplicated; protected contributors and sessions remain separate across development and untouched evaluation.
7. Deletion removes an example from storage, annotations, pending/running work, derived data and recorded exports, and cannot be undone by retry or backup restore. Failures and maximum completion delays are visible and match the disclosed policy.
8. App explanation, consent UI, privacy policy and App Store disclosures describe the actual implementation and linkage. Collection remains disabled until those artifacts and activation are authorized.
9. Large/failed/offline uploads do not block Pencil interaction, alter chart/ink persistence or exhaust an unbounded queue. No contribution event starts recognition experiments, tuning, training or model promotion.

The next immediate delivery remains the aggregate diagnostics/incident pipeline and its first verified product fix. The contribution design provides the separately consented evidence path needed for future recognition work without changing the current pause or activating collection.
