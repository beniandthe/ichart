# iChart file import, paper scanning, and Pro Scan

Date: 2026-10-23
Status: Implementation plan; no product implementation or deployment completed by this document.

## 1. Outcome and product boundaries

Deliver useful document import first, then add optional OpenAI conversion into an editable iChart. Each milestone must produce an observable result and be releasable without the later milestones.

| User action | Input | Saved result | Processing | Recommended access |
| --- | --- | --- | --- | --- |
| **Import File** | PDF from Files; subsequently screenshots/photos from Files or Photos | Original document in the PDF Library | Local copy; images become ordered PDF pages | Basic and Pro, with file/resource limits |
| **Scan Paper Chart** | Camera capture of physical paper | Original multipage document in the PDF Library | On-device document capture and page preparation | Basic and Pro, with file/resource limits |
| **Pro Scan — Create Editable iChart** | Selected pages from either source above | Reviewable draft, then a new native iChart | Explicit online OpenAI request paid by iChart | Server-verified eligible Pro plus page allowance |

These are recommended packaging decisions for implementation, not claims about the current public app. Local document intake does not spend AI allowance. Pro Scan must also work on an existing imported PDF; users should not have to scan it again.

Preserve the current native-chart capacity and downgrade policies. Decide imported-document capacity separately rather than accidentally counting every source PDF as a native chart. Recommended initial behavior: no additional subscription gate for local intake, with explicit per-file/page/storage safeguards. Keep setlist access under its separately confirmed product policy.

Suggested UI:

- PDF Library: **Import File**, **Scan Paper Chart**.
- Original document detail: **Add to Setlist** and **Pro Scan — Create Editable iChart**.
- Pro Scan: select supported pages, show allowance impact and online-processing disclosure, then **Create Draft**.
- Review: original and draft, unresolved items, manual corrections, then **Save as New iChart**.
- Converted chart: **View Original** where the local source is available.

## 2. Verified starting point and release-base gate

Read-only inspection found the following development-source foundation:

- The current workspace is on `codex/chord-telemetry-failure-buckets`, at `ad6cbee`, with unrelated local changes. It predates the inspected setlist implementation.
- The Graph worktree at `the parked Graph worktree` contains PDF-library storage, PDF preview, ordered PDF-based setlists, and the performance reader. Its inspected commit is `1c384425`; it is a research/Lab configuration, not an approved release base.
- Setlist entries reference PDF item IDs. Personal PDFs can fit that model without changing setlists into live native-chart references.
- PDF sources currently distinguish chart exports and forum downloads. Personal imports and camera captures need their own source representation.
- PDF metadata currently requires native layout/transposition fields. Those fields must become optional or export-specific for imported documents.
- Existing server code has authenticated request and verified StoreKit subscription conventions. No Pro Scan endpoint, job system, or page allowance exists in the inspected source.

**M0 — baseline before app changes:** identify and refresh the intended release branch/commit, inspect its actual setlist code and current capabilities, then implement in an isolated `codex/` branch/worktree. Preserve current dirty files and active Graph/MyScript work. Reuse the relevant document/setlist code deliberately; do not ship a research app configuration wholesale.

There is a policy/code question to resolve during M0: `docs/ichart-plan-policy-source-of-truth.md` places setlists among Pro features. The entitlement enum has a `setlistsAndVersionHistory` value labeled **Project Organization**, while the inspected Lab navigation presents `SetlistsView` directly and that view has no capability guard. An existing functioning setlist paywall has therefore not been established. Record the intended release policy and apply it deliberately before public rollout. This does not block the local import proof and does not authorize an unrelated paywall change.

M0 deliverable: recorded base SHA, selected app scheme/bundle identifier, feature availability, focused verification commands, and a preserved fixture pack. Record these in the implementation PR.

## 3. Milestones and immediate success proofs

### M1a — one real PDF into an existing setlist

**Build:** Files PDF picker, personal-import source, title, actual PDF validation, owned local copy, and existing library/setlist integration. Start with readable, unlocked PDFs. Reject locked, empty, malformed, or oversized inputs clearly. Establish configurable limits after trying genuine large documents on target hardware.

Make import persistence transactional: stage the copy, validate it, durably commit the library manifest, then publish the new item. Failed writes must leave the prior library intact. Preserve existing item IDs and exports/forum files when migrating metadata.

**First proof on a physical iPad:**

1. Import a genuine two-page PDF from Files/iCloud Drive and name it.
2. Add it to a setlist with an existing iChart export; reorder and navigate songs/pages.
3. Using a disposable fixture copy, remove the external source file, force-quit iChart, enable airplane mode, and reopen.
4. Verify the owned copy, page order, title, setlist order, and navigation still work.
5. Verify cancel, duplicate filenames, malformed/locked files, failed storage writes, and setlist deletion. Deleting a setlist must retain its documents.
6. Verify an old export/forum manifest upgrades without losing files or changing IDs. Personal imports must not join forum-download subscription cleanup.

**Deployable result:** internal TestFlight build with personal PDF import. It can progress to public release after its own release checks, independent of scanning/AI. Source inspection, a build, installation, device proof, upload, and public availability are separate checkpoints.

### M1b — screenshots and photo files

**Build:** image intake from Files/Photos, orientation normalization, page ordering/rotation/removal, and image-to-PDF creation through the same saved-document path. Keep original image bytes or an immutable original asset alongside prepared pages; page edits must not destroy the only source. Avoid a new annotation subsystem in this milestone.

**Proof:** choose two screenshots, correct order/orientation, save one document, and repeat M1a's offline reopen/setlist workflow. Inspect chord extensions and accidentals at reading zoom; a generated PDF is insufficient if small symbols have become unreadable. Exercise cancellation and a high-resolution image on target hardware.

**Deployable result:** file and screenshot/photo import, still with zero model requests. M1a can ship first if image handling needs more work.

### M2 — scan physical paper

**Build:** Apple's document camera, supported-device check, camera purpose description through `project.yml`, capture/retake, page review/title, and the same local save destination. A completed camera scan creates an original document; it does not invoke Pro Scan.

**Proof on a supported physical iPad:** capture two paper pages, retake one, save, add to a setlist, force-quit, and read all pages offline. Verify cancellation, denied camera access, and unsupported-device behavior; file import remains available. A simulator cannot establish camera success.

**Deployable result:** **Scan Paper Chart**, independently useful without OpenAI configuration.

### M3a — native editable import without AI

Run this engineering track in parallel with M1/M2 after M0. It must not delay their releases.

**Build:** versioned `ScanChartDraft` transfer format and deterministic importer into existing `Chart`/`Measure`/`ChordEvent` types. Start with a known four-bar fixture containing a major seventh, a minor seventh, two chords in a bar, and a slash-bass chord. Add explicit meter and beat placement to this first fixture.

**Proof:** fixture becomes a new editable chart; edit a chord, transpose, save, force-quit/reopen, export PDF, and use that export in a setlist. Original document stays linked and readable. Verify source and converted chart can be managed without silent cascading deletion. This proves the importer and persistence, not model recognition.

### M3b — one real page through OpenAI

**Build:** internal-only server extraction path using a dedicated project key in backend secrets, a fixed supported model configuration, Structured Outputs, and the M3a importer. Begin with three self-authored clear printed pages and known expected chord/measure data. Include a deliberately ambiguous/unsupported input to exercise review behavior.

Initial experiment envelope: developer allowlist, one page per job, one active job per account, server-enforced request/input/output/attempt caps, at most one explicitly justified targeted reread, and a conservative server spend-reservation ceiling (proposed $10 total before review). Reconcile actual provider usage. Configure provider spend controls too, but do not treat a project budget/alert as a proven hard cutoff. These are experiment limits, not a public allowance or measured cost promise.

**Proof:** a real billed request returns a draft that becomes an editable chart on the iPad and passes the M3a workflow. Save input hash, output, model/prompt/schema/importer versions, latency, provider usage, estimated billed cost, and a human comparison of chord identity, order, bar assignment, omissions, and timing. Record every correction.

All explicitly supported musical fields on the three proof pages must match ground truth after review. Capture errors before review separately. A hand-corrected result cannot be counted as an automatic recognition pass. Ambiguous input must remain reviewable and must not silently invent missing information.

**Deployable result:** an internal proof service behind an allowlist/disabled customer flag. This is evidence that the full technical path works; it does not establish customer-chart accuracy.

### M4 — protected Pro Scan beta

**Supported input at entry:** one song, one clear printed page, chord-and-bar charts with explicit measure boundaries. Require user confirmation of missing meter/timing. Detailed rhythmic hits, melody, dense scores, complex roadmaps, and broad handwriting support are deferred until evaluated separately.

**Build before inviting customers:**

- A distinct `proScan` entitlement and UI label. Do not reuse the existing generic handwriting-recognition feature name.
- Server identity and verified paid-service eligibility before provider spending. Follow current cloud-service policy for grace/legacy local Pro; unlimited local chart capacity alone does not authorize paid API calls. Canceled-but-still-paid-through eligible Pro remains eligible.
- Durable jobs, selected-source ownership, atomic page-allowance reservation, per-account concurrency, rate/page/byte/token limits, a global spending control, and a server kill switch.
- App progress, background/relaunch recovery, original/draft review, manual corrections, unresolved/unsupported content, and atomic **Save as New iChart**.
- A usage display with defined reset date and clearly stated allowance behavior on failures.
- Private temporary processing assets, deletion/retention behavior, owner-only results, and sanitized operational logs.

**Access/cost proof:** anonymous, Basic, expired, revoked, forged-client-Pro, and ineligible grace/legacy accounts cause zero extraction requests. An eligible account succeeds. Another account cannot read its sources, job, or result. Repeated taps, concurrent submissions, timeouts, and app restarts do not reserve allowance twice or blindly repeat a paid extraction.

**Customer usefulness proof:** evaluate at least 20 varied charts with documented permission to process them, including a held-out set not used to tune prompts. Compare final supported musical content against ground truth; measure raw errors, corrections, omissions, time to usable chart, manual-entry time for the same material, p50/p95 latency, provider cost, and failures. Report unsupported input separately rather than inflating success with easy pages.

Initial beta exit target: at least 80% of supported held-out charts reach a correct reviewed result faster than manual entry, with a median time saving of at least 50%. These are proposed product gates, not current results. Every known content omission in the evaluation must either be represented or called out in review; investigate silent omissions before widening availability. Correct rendering alone cannot satisfy this gate.

Set the public monthly page allowance from measured usage and contribution cost. Keep an explicit beta allowance in server configuration; do not advertise unlimited conversion. If quality or correction time fails the gate, narrow supported inputs or continue internal work while M1/M2 remain useful.

**Deployable result:** allowlisted Pro beta, then staged Pro rollout once access, persistence, usefulness, and cost gates pass.

### M5 — expand on the proven foundation

Add separate evaluation buckets and releases for multipage songs, targeted rereads, clear chord handwriting, section labels, rhythmic notation, batch import, annotations, and source-document cloud backup. Bar-and-dot measure/range repeat ingestion is retired by the corrected November 5, 2026 decision and is excluded from these proposed recognition buckets; supported chord-repeat symbols (`%` / dot-slash-dot) remain distinct. MusicXML import and live native-chart setlist references are independent future features.

## 4. Shared document and native-draft contracts

### Original document

M1a needs an immutable owned PDF, stable asset ID, source kind, original filename/title, page count, byte size, and local asset location. Native export metadata is optional and shown only when meaningful. Add source hashes and preparation mappings when image preparation or Pro Scan introduces those dependencies; a full asset-history/trash subsystem is not a prerequisite for the first PDF import.

Do not store scanned pages in `sourceInkData`; that field holds Pencil drawing data. A scan does not recreate original Pencil strokes.

Deleting/canceling a conversion leaves the original intact. Existing explicit PDF deletion behavior remains valid for M1a. Once drafts/charts reference a source, handle explicit source deletion with a clear warning or retained copy and an honest missing-original state; conversion must never silently delete or replace the source. Personal imports do not automatically become Forum-upload candidates; preserve existing Forum provenance restrictions.

### ScanChartDraft v1

Use a compact transfer format rather than asking the model to emit internal persistent `Chart` JSON. Include schema version, ordered systems/measures, raw chord text, observed meter/key, optional beat positions/durations, section/cue observations, unresolved/unsupported content, and source page/crop references.

Application code owns UUIDs, ownership, subscription state, cloud intent, validation, and library insertion. Normalize through `ChordSymbolParser`/`MeterParser`, then run `MeasureTimingValidator`. Reject invalid references, overflow/overlaps, unsupported symbols, incomplete/refused responses, and resource limits gracefully. A parser pass proves admissible data, not faithful transcription.

Absent timing remains unknown until the user approves a placement convention or corrects it. Do not silently equate graphical spacing with beat duration. Record observed versus inferred versus user-confirmed information. Source crops prepared by the app provide references; model-supplied precise coordinates are not inherently trustworthy.

Keep draft review separate from committed chart creation. Unresolved required fields block final save unless the user explicitly resolves them or accepts a clearly labeled supported simplification. Saving twice or resuming after interruption must not create duplicate charts.

### Setlists and cloud behavior

Today’s inspected setlists contain saved PDF snapshots. Imported originals fit directly; a converted native chart joins through PDF export. Clearly communicate that later native edits require exporting/updating that snapshot. Live linked native setlists are outside the first release.

Originals are local-first. Temporary server copies for AI processing are not cloud backup. Existing native-chart backup may carry the converted chart, but must not claim to back up its original PDF/image automatically. A restored converted chart must remain usable if its local original is unavailable, with honest **Original unavailable on this device** behavior. Source-asset backup needs its own milestone and restore test.

## 5. Pro Scan backend design

Use the existing Supabase auth/subscription authority and a dedicated OpenAI project secret. The public app calls iChart endpoints, never receives the key, and never controls quota or job-completion authority.

Proposed server contracts:

- **Prepare source:** authenticate and authorize a server-issued owner/job-scoped private upload, or verify an existing private object owned by the caller. Validate actual content, hash, selected pages, and byte/page counts before paid processing. Caller-supplied owner fields, arbitrary URLs/storage paths, or page counts are not authority.
- **Create/finalize job:** bind the validated source hash and selected pages to identity, eligibility, supported limits, and owner-scoped request ID; atomically reserve final page allowance and persist/queue the job. Any preliminary upload reservation must be reconciled without duplicate allowance consumption.
- **Process job:** claim a bounded attempt, record provider submission/response IDs, extract only selected pages, validate the result, then mark review-ready or failed.
- **Read job/result:** owner-only status, review data, and allowance information. Resume by job ID after relaunch.
- **Retry/cancel:** explicit state transitions with attempt limits and reconciled allowance; no unconditional duplicate extraction.

Persist jobs, attempt/usage records, and allowance reservations. Enforce uniqueness for owner/request ID and reject reuse with changed payload/parameters. Reserve/finalize/release allowance in short transactions; never hold database locks during model calls. Use owner RLS for exposed records plus explicit grants where needed; privileged counters and provider data are server-only. Apply the same ownership boundary to private storage.

Job states should distinguish created/queued, processing, reconciling an unknown provider outcome, review-ready, failed, canceled, and locally saved. App save and provider processing are separate events. Track enough state to prevent duplicate local insertion after a crash.

External API submission and database commit are not one atomic transaction. An ambiguous timeout/crash must enter reconciliation rather than blindly creating a new provider request. Repeated app actions should reuse the logical job; do not promise exactly-once external billing without proving provider-supported behavior.

For public beta, use durable dispatch/recovery and scheduled reconciliation. Do not rely on the iPad staying open or on an untracked Edge Function background task. Supabase has finite worker/request limits; an OpenAI background response with its ID durably recorded, bounded polling/webhook handling, and reconciliation is one candidate. Confirm model/account support and retention settings in M3; select the simplest design that passes app-termination and worker-restart tests.

Separate user allowance from provider billing: a failed scan may still incur provider cost. Proposed user policy is reservation on accepted work, consumption on review-ready supported results, release on system failure, and no extra allowance for bounded system retries. Discarding a review-ready draft does not refund its completed processing. Track the provider cost regardless. Define cancellation after processing starts explicitly in the UI.

Before beta, set temporary-source/result retention, deletion jobs, provider-file cleanup, account-deletion behavior, and first-use disclosure. Avoid promising zero provider retention. Store only operational identifiers/versions/status/cost in routine logs; keep raw chart content out of analytics.

## 6. Work packages and implementation seams

Paths below are repository-relative targets to confirm on the selected release base. New names are proposed, not existing implementations.

| Work package | Existing seams | Proposed additions / verification |
| --- | --- | --- |
| Document intake and persistence | `iChart/Services/PDFLibraryStore.swift`, `PDFLibraryStoreTests.swift` | `DocumentImportService`; legacy manifest migration; atomic writes; real PDF fixtures |
| Library, preview, setlist integration | `LibraryView.swift`, `PDFExportPreviewView.swift`, `SetlistsView.swift`, `PDFSetlistStore.swift` | Import/source UI, truthful metadata, unchanged stable references; offline device proof |
| Image preparation and camera | `project.yml`, document intake above | Image page review, VisionKit wrapper, camera purpose text; physical-camera proof |
| Native draft importer/review | `Chart.swift`, `Measure.swift`, `ChordEvent.swift`, `ChartParsers.swift`, `MeasureTimingValidator.swift`, chart repository | `ScanChartDraft`, `ScanChartImporter`, review/source linkage; fixture plus save/edit/transpose/reopen proof |
| Paid-service capability | `AppEntitlements.swift`, subscription authority modules | Explicit Pro Scan capability; paid-through/grace/expired/legacy tests; no client-only spending gate |
| Pro Scan server | `supabase/functions/_shared/`, function entrypoint pattern, migrations/RLS tests | Job API/worker, private processing assets, quotas/attempt ledger, provider adapter, reconciliation, cleanup |
| Release/operations | existing CI and production-readiness scripts | Feature flags, allowlist, cost/error reporting, staged smoke tests and rollback |

## 7. Verification and rollout rules

Use a small evidence ledger per milestone: build SHA/configuration, exact fixture/source hash, executed checks and counts, device/OS, observed result, unresolved issue, and release checkpoint. Keep these claims separate:

1. source/fixture validation;
2. actual model transcription before correction;
3. native importer and manual review;
4. physical-device persistence, editing, and offline use;
5. access, quotas, interruptions, and provider-cost behavior;
6. backend deployment and smoke test;
7. TestFlight upload/processing/install;
8. public App Store release and observed availability.

Use `project.yml` as authoritative: regenerate via XcodeGen, build/test the selected `iChart.xcodeproj`/scheme, and inspect actual selected/executed test results. Add tests for the new contracts and failure paths; a PDF-looking header or zero selected tests is not document validation.

Backend rollout order: local tests and RLS/access checks → staging → deployment with customer flag off → eligible/ineligible production smoke checks → internal TestFlight → allowlisted beta → staged general Pro availability. Use additive compatible migrations. Keep the previous app functional. Disable Pro Scan server-side to stop new work while retaining originals, drafts, and completed charts; reconcile/cancel in-flight work safely. Document rollback for local manifest changes before shipping them.

## 8. First implementation batch

- [ ] Complete M0 release-base and policy reconciliation.
- [ ] Create genuine PDF/image fixtures and an old-manifest migration fixture.
- [ ] Implement M1a personal PDF import and honest document metadata.
- [ ] Complete the physical-iPad import → setlist → offline reopen proof.
- [ ] Package the first internal TestFlight build and record each distribution checkpoint.
- [ ] In parallel, implement M3a deterministic native draft import.
- [ ] Configure a dedicated test OpenAI project/secret when API implementation starts, then run M3b under its experiment budget.
- [ ] Advance image intake, camera capture, and protected Pro beta independently as their gates pass.

This planning turn does not call the OpenAI API, inspect secrets, upload customer charts, deploy a backend, or publish an app. Implementation and release evidence must be recorded as that work occurs.

## 9. Source references

- Inspected development files: Graph worktree `iChart/Models/PDFSetlist.swift`, `iChart/Services/PDFLibraryStore.swift`, `iChart/Features/Library/SetlistsView.swift`, native models/parsers/timing validator, `project.yml`, subscription authority modules, and RLS migrations. Current shipped behavior was not verified.
- Repository policy: `docs/ichart-plan-policy-source-of-truth.md` and existing production deployment/StoreKit runbooks. Reconcile release-specific drift during M0.
- [Apple file importer and security-scoped URLs](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aoncompletion%3A%29).
- [Apple document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller) and [supported-device check](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller/issupported).
- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [image-reading limitations](https://developers.openai.com/api/docs/guides/images-vision), [background processing](https://developers.openai.com/api/docs/guides/background), and [data controls](https://developers.openai.com/api/docs/guides/your-data).
- [Supabase Edge Function limits](https://supabase.com/docs/guides/functions/limits) and [changelog](https://supabase.com/changelog). The changelog flags explicit table exposure changes enforced on 2026-10-30; verify grants/exposure deliberately when implementing new data access.
