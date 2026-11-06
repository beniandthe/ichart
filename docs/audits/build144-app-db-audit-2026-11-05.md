# Build 144 app and database audit

Status: source audit and local remediation validation complete. Production changes require the separate rollout packet. The installed iPad remains on Build 144.

November 6 merge follow-up: the full PR native run passed, but a same-head push
run exposed a two-second deadline in an unchanged fallback-independence test.
The test now holds fallback explicitly, admits the neighbor after that hold is
entered, and verifies its real render before release. Its watchdog cannot release
fallback or satisfy the ordering claim. All original source/layout assertions
remain. Fifty repetitions and the full fallback-session class passed; see the
[focused receipt](build144-evidence/ci-fallback-fixture-2026-11-06.json). The
production runtime is unchanged by this test-only follow-up. The November 5
source manifest below remains the original audit checkpoint; final new-head
hosted checks and merge identity are recorded by PR #103.

## Accepted baseline and boundaries

- User-designated baseline: iChart 1.2.4 (144), installed from merged PR #102 commit `00f7901538074670251cd6626c1efa88a3bd1aec`, tree `97df96b43de9431ba72a0f7ab186da2323281740`.
- Working branch: `codex/build144-app-db-audit`, based directly on that merge. The iPad remains on the accepted baseline during this audit.
- Preserve handwritten chord-repeat `%`/dot-slash-dot ingestion. Handwritten bar-and-dot measure/range repeat ingestion remains retired; use Tools > Repeats.
- Preserve charts, ink, PDFs, setlists, recovery evidence and parked refs. ML core, Graph and MyScript remain parked. No new device stop/install is part of this audit.
- Live database reads use schema, technical metadata, aggregate counts and bounded log groups. No chart JSON, handwriting, accounts, support/mail or raw content is collected for the audit. Existing automation stays paused.
- Working evidence: `/private/tmp/ichart-build144-app-db-audit-20261105`. Final validation and publication/deployment status will be recorded separately.

## Coverage and concrete findings

| ID | Priority | Area and evidence | Remediation / current state |
|---|---|---|---|
| A01 | P1 | Failed initial library load creates a preview fallback with a live repository; later mutations can overwrite the unread file. | Write quarantine, explicit read-only retry, cloud exclusion and dedicated accessible recovery UI implemented. Fault, reopen, retry and mounted UI coverage added. |
| A02 | P1 | Non-cooperative cloud completion may apply old-account restore or backup metadata after cancellation/account switch. | Generation/account guards precede post-await side effects; held-service tests cover supersession. Equal auth-context notifications no longer restart real work. |
| A03 | P1 | Cloud restore selects full history through a capped API. Live database has 26,007 snapshots; 13 live document pointers lie outside their owner's newest 1,000 history rows. | Keyset document paging and bounded latest-ID fetches validate owner/chart/payload identity and reject incomplete required data. Fixture imposes a smaller 37-row cap over more than 1,000 records. |
| A04 | P2 | Backup pushes every included chart with a fresh revision, even unchanged. Four REST operations per chart; snapshot relation occupies 1,583,718,400 bytes. | Optional durable content ACK skips unchanged automatic uploads; manual backup forces verification/write. ACK hashes canonical stored JSON, legacy normalization uploads once, and only matching current content receives backup metadata. Zero-write paths retain optional prior dates. |
| A05 | P2 | PDF save publishes before manifest persistence and may leave a phantom entry/orphan on write failure. | Durable candidate before publication, current-manifest merge, bounded rollback and destination-race preservation implemented. |
| A06 | P2 | Forum download completion can outlive its post/account/detail; friendly-name cache paths can collide. | Request/session/post/owner/access guards and unique cache directories implemented. Late completion cannot publish or clear newer busy state. |
| A07 | P2 | Concurrent same-title PDF exports share a temporary path and can replace another publication's PDF before reading. | Unique per-export directory preserves human filename and bytes returned to earlier callers. Cleanup targets only the failed operation. |
| A08 | P2 | Paired ending/barline preparation repeats the same ending detector. Normal preparation runs four passes where two suffice. | Shared raw structural results remove two repeated detector passes while preserving ambiguous original-stroke exclusion. This is a call-count improvement, not a measured latency claim. |
| A09 | P2 | Per-measure meter/predecessor and rhythmic-ink lookup repeatedly flatten/scan all measures during layout/redraw. | Local predecessor context and sparse per-draw ink index remove repeated full-list scans. Cross-page meter and one-pass sequence controls added. |
| A10 | P2, deferred | Saved page ink rasterizes a full document for each clipped PDF page before bounded cache admission. | The per-paper prototype changed real pixels: 2–6 pixels at scale 1, up to 24/255 channel delta; 4–5 pixels at Retina, up to 1/255. Exact uncached full-document controls pass. Restored the renderer byte-for-byte to the accepted baseline and removed the crop call. The [recoverable experiment](experiments/build144-page-raster/README.md) retains source and evidence for future work. No raster-memory improvement is shipped or claimed. |
| A11 | P2 | Debug builds enable detailed candidate/ink diagnostics by default with unbounded pending disk work. | Explicit default-off opt-in, eight-operation nonblocking admission and an 8 MB append ceiling preserve existing evidence. Release/Simulator remain disabled. |
| A12 | P3 | Actual Build 144 warnings include deprecated onChange and PostgREST detail APIs, ignored return values and unused locals. | Deprecated APIs, unused URL helper/locals and ignored return-value warnings corrected. Final compiler output is recorded below. |
| A13 | P2 | Current-state/parked-work docs name superseded candidates/branches and missing worktree directories. | Docs updated to distinguish accepted Build 144, this unvalidated successor, preserved refs and absent paths. No history removed. |
| A14 | P1 | Live notification authority helper records the idempotency ledger before a separate authority PATCH; a failed PATCH or concurrent stale notification can lose/order updates. | Additive service-only invoker RPC makes ledger/order/authority one transaction for both claim and notification writers. Actual PG17 serial and concurrency controls pass. No production change yet. |
| A15 | P2 | Forum search filters capped recent/top candidates before matching, hiding valid older results. | Additive authenticated invoker RPC applies literal normalized matching before ranking/limits, with precise keyset paging and explicit Load More. Response caps are not scan-cost bounds. Required before new client installation. |
| A16 | Review | Advisors report missing foreign-key indexes, intentional service-only RLS tables, callable auth-scoped definers, MFA options and unused indexes. | Qualified against workload/catalog/source: seven authenticated definer bodies match exactly and remain owner-scoped; no private client grants. Preserve fail-closed stores and necessary indexes. |
| A17 | P2 | Account deletion inventory can truncate posts/objects at a server cap or treat a failed Storage listing as empty. | Stable paged inventory, strict owned PDF paths, fail-closed enumeration and ten-delete concurrency bound implemented; 1,001-row and failure controls pass. No customer deletion invoked. |
| A18 | P2 | Superseded auth operations can publish old profiles/state/errors or clear newer busy state. | Controller operation generations protect published state and pending-flow mutations. Six held-service regressions added. Underlying SDK session persistence remains a separate boundary, listed below. |
| A19 | P1/P2 | Optional Pillow and Edge jsrsasign pins match reviewed security advisories. | Optional Pillow raised to 13.0.0 without activating ML; jsrsasign pinned to 11.1.5. Three frozen Deno graphs, actual-version crypto tests and a CI gate added. Published alert closure and hosted dependency provenance remain separate. |
| A20 | P2 | Swift lowercases Greek `ΟΣ` to `οσ`, while the live database lowercases it to `ος`; pre-lowercased query misses uppercase metadata. | Wire keeps NFC-composed, whitespace-clean text case; SQL lowercases both query and metadata. Exact scalar wire and SQL regressions added. Turkish dotted-I mismatch was investigated and not reproduced. |
| A21 | Operations | Managed Postgres security/minor update available; recovery is daily-only and excludes Storage objects. | Verified seven daily backups, PITR off, target 17.11.0.018 and targeted compatibility checks. Separate upgrade/recovery approval packet prepared; no outage or charge initiated. |
| A22 | P2/P3 | Existing readiness scanner flags three baseline synthetic literals and prints matching values; a template anywhere on a line can suppress a real finding. | Exact quoted path-scoped exceptions, per-match/nested-assignment detection and redacted diagnostics implemented. All six rules remain; 14 regressions and the actual repository scan pass. New CI coverage and a scan-only command preserve default readiness behavior. |

## Database observations so far

Production project `pausvvwoazbvmzyrebwl` reports ACTIVE_HEALTHY on Postgres 17.6.1.127. Initial reads at 2026-11-05 evening Pacific found:

- 8 of 60 configured database connections, no waiting locks or other open long transactions, no invalid/unready user indexes, no reported checksum failures or deadlocks. Statistics are cumulative since their reset; they are not rates.
- Database size 1,642,384,531 bytes, mostly chart snapshot history. Snapshot JSON stored size 1,504,821,772 bytes. No missing non-null latest-snapshot targets or owner/chart pointer mismatches.
- 107 chart documents (62 live), 26,007 snapshots across 21 owners; largest owner history 24,453. All live null-pointer documents have at least one matching history row; no observed live document lacks both a pointer and history.
- The 37 baseline migration versions exactly match the 37 live versions. This branch adds two unapplied migrations. Version equality alone is not full schema equality; the separately reviewed seven definer bodies do match.
- All public tables report RLS enabled. Eight private service tables have RLS off but no direct client grants; fourteen intentionally private/fail-closed stores have RLS but no policies. No generic client policy was added. Health advisors report no findings; all user constraints validate. Seven authenticated security-definer bodies/attributes match latest migrations exactly, with empty search paths and owner-scoped authority. No observed newer mapped ledger clock lies beyond saved authority; that does not prove historical races never occurred.
- The bounded 24-hour log aggregation has successful chart REST calls and no chart-route HTTP errors; this does not prove the cause of the two client-side cloud-push failure events observed during installation.

The live API cap is 1,000 rows. Authenticated and authenticator statement timeouts are 8 seconds; response limits do not establish search latency. Fourteen missing-FK-index suggestions affect tables of 0–107 rows, including four empty parked-study relations. Fourteen unused-index notices are insufficient grounds to delete recovery/performance structures. MFA options and fixed Auth connection allocation remain configuration decisions.

The Dashboard offers Postgres 17.11.0.018 from 17.6.1.127. Seven daily physical backups cover October 30–November 5, 2026; Storage contents are excluded and PITR is off. The private PDF bucket contains two objects. Targeted preflight found zero affected user ltree indexes, btree_gist floating-point indexes, custom selectivity operators or public/private PGP-encrypt function references. This covers only those checks, not an upgrade rehearsal. Installed CLI is 2.109.0 and remains unchanged. See the [separate rollout and recovery plan](build144-backend-rollout-2026-11-05.md). Relevant primary sources:

- [Postgres 17.11 upgrade changes](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes)
- [CLI v3 targeting and confirmation changes](https://supabase.com/changelog/supabase-cli-v3)
- [Advisor qualification](https://supabase.com/docs/guides/observability/advisors)

## Parked work and measurement backlog

Ordinary Build 144 contains no research model bundle or PersonalMLComparison payload. The product personalization gate is false and profile loading is guarded. Some shared learned/personal types still compile; this is build footprint, not measured runtime cost. Preserve compatibility and recoverable refs rather than deleting shared types without a reference/build proof.

PDF main-thread opening, repeated setlist/project lookup, full batch archive serialization and incremental full-point hash keys are measurement candidates. They are not claimed speedups or automatic rewrite targets. Snapshot retention/deletion was not changed; the client fix prevents redundant future uploads while retaining recovery history.

The auth-controller guard does not serialize preexisting SDK writes to authClient or persistent/shared session stores. Full credential-operation serialization needs separate design and service-level acceptance. No credential storage or trust policy was changed. jsrsasign is patched for the reviewed catalog but is past upstream support; Apple's published SDK still depends on it. A future replacement must validate both paths. Local frozen locks do not establish hosted bundler lock enforcement. The two installation cloud failure events remain unexplained by the bounded successful HTTP log groups. Fresh physical Pencil interaction, App Store crash analytics and a production upgrade/recovery rehearsal are not supplied by these local tests.

## Validation and delivery

Coverage includes startup/auth/profile, library/cloud persistence, editing/rendering/review in both public chart styles, legacy page geometry, PDF import/library/export, setlists/projects, forum publication/search/download ownership, StoreKit/retention/account deletion, telemetry/diagnostic boundaries, build/dependency configuration and parked source. This is source and local regression evidence; it does not assert every possible interaction has been exercised.

| Gate | Result |
|---|---|
| Backend Node, all 25 unit files | 659 passed, 0 failed |
| Atomic StoreKit SQL, real PostgreSQL 17.6 | 17 serial control groups and 6 competing-session tests passed |
| Forum SQL/RLS, real PostgreSQL 17.6 | 35 pgTAP assertions passed; explicit Auth/Storage/Cron adapters, synthetic rollback-only data |
| Actual-version Edge dependencies | 3 frozen entrypoints, 15 offline tests passed; stale-lock negative control rejected; 48 exact npm advisory queries completed with no affected match |
| Pillow 13.0.0, isolated Python 3.12 | 43 synthetic decoder/intake tests passed; no training or corpus processing |
| Parked-model packaging boundary | 7 tests passed |
| Readiness scanner | 14 tests and actual repository scan passed; default full readiness pipeline not substituted by scan-only |
| Portable full suite | Final source: 2,040 executed, 1,948 passed, 92 skipped, 0 failed |
| Native full suite | Final source: 3,352 executed, 3,232 passed, 120 skipped, 0 failed on isolated Air11/iOS26.5. `xcresulttool` verifies the device/counts; wrapper verifies both original preferences restored. |
| Release iPad compilation | Final restored-renderer source: BUILD SUCCEEDED, unsigned generic iOS arm64. Remaining source warning is the baseline Debug-only preview branch; AppIntents metadata notice is tooling. |
| Production readback, 2026-11-06 05:31 UTC | 13/60 connections, 0 waiting locks, 0 invalid user indexes; 26,007 snapshots, 1,642,384,531 database bytes; 37 migrations and neither new RPC present |

Two invalid native runner attempts are retained as setup evidence: wrong initial device size, then omission of the existing accessibility/software-keyboard wrapper. A valid wrapped run executed 3,356 tests and exposed four failed methods: two obsolete test assumptions and two strict crop pixel comparisons. The crop experiment was deferred rather than relaxing its thresholds. The fresh final run passes all 3,352 remaining tests with verified preference restoration.

Compact technical receipts are retained in [build144-evidence](build144-evidence/), including [final validation](build144-evidence/validation.json) and [SHA-256 source inputs](build144-evidence/source-manifest.json); bulky working logs/xcresults remain under `/private/tmp/ichart-build144-app-db-audit-20261105`. None contains customer chart JSON, ink or account rows. The [backend rollout plan](build144-backend-rollout-2026-11-05.md) separates source validation, deployment, upgrade and recovery. No production change or iPad update has occurred. This is a review branch; merge, hosted CI, production migration/function deployment and App Store delivery each require their own actual receipts.
