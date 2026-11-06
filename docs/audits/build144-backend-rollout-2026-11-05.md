# Build 144 backend rollout plan — 2026-11-05

**Prepared for review; no production migration, function deployment or upgrade has been performed.** This plan accompanies the [app/database audit](build144-app-db-audit-2026-11-05.md), based on merged commit `00f7901538074670251cd6626c1efa88a3bd1aec`. The installed iPad remains on Build 144. Source validation is distinct from production acceptance.

## Reviewed changes and validation

| Artifact | Purpose | SHA-256 at review |
|---|---|---|
| `supabase/migrations/20261106045008_atomic_storekit_subscription_authority.sql` | Atomic verified StoreKit claim/notification authority and notification ledger | `64bf0a0100f5ba84b649affcdd1ce663d928bb288cf7063fdb3506e7377a2d3e` |
| `supabase/migrations/20261106045138_search_forum_home_pagination.sql` | RLS-preserving literal search before pagination/ranking limits | `2068b777d69c452c2d1c683936fe0c2e2ef8402ce99e21632bf41fa15f8d0e02` |
| `supabase/functions/_shared/supabase_subscription_authority_store.mjs` | Both authority writers use one RPC, with no split-REST fallback | `e3e40de1445201f4c977e8f65b28052ca775a07ceaeea17c73c35a7b11fb55fd` |
| `supabase/functions/_shared/app_store_signed_data_verifier.mjs` | Pin `jsrsasign` to 11.1.5; retain Apple server library 3.1.0 | `7ba755c8d04e937708971b0f6510658f4dcffcb66ef06c5d96cd94ca25c1b4ce` |
| `supabase/functions/_shared/account_deletion.mjs` | Complete bounded inventory, owner/path validation, fail-closed cleanup and bounded deletion concurrency | `abbdf2323a551d117651ca016bd3ebe8ee91381cffc7bb058b56ca82489b2c75` |

Root validation on isolated PostgreSQL 17.6 passed 17 financial serial control groups and six actual two-session concurrency tests. Final forum SQL passed all 35 pgTAP assertions with the documented local Auth/Storage/Cron adapters, including the Unicode-query follow-up. The 25-file Node backend rerun passed 659 tests. These results establish source/local behavior; they do not establish hosted gateway, bundle, production latency or deployment success.

The separate `.github/workflows/storekit-authority.yml` prepares the actual fixture/migration and serial/concurrent controls on digest-pinned PostgreSQL 17.6 with isolated ephemeral storage, no container network/host ports and bounded resources. Its YAML and Bash blocks passed syntax validation; its GitHub execution remains pending. Existing `ci.yml` is unchanged.

Financial review found no additional source defect in the reviewed patch: original → owner → row locks serialize both writers, including absent rows and original replacement; ledger/update failures roll back together. Existing stale/null/duplicate rules, millisecond clock ordering, numeric transaction ties, owner conflicts and omitted-versus-null fields are retained. The service-only function has no generic dynamic SQL or private-schema dependency.

Forum review found no privilege bypass: the function remains `SECURITY INVOKER`, checks current identity/Pro access, relies on table RLS and blocked-author policy, and returns published/flagged posts only. Literal `strpos` does not use the existing full-text index; a rare or unmatched query can inspect the visible catalog despite the 20-song/three-post output bound. No query-plan speedup is claimed. A cross-runtime probe confirmed that Swift and live PostgreSQL lowercase Greek `ΟΣ` differently. The client wire correction preserves cleaned NFC text and lets SQL lowercase both the query and stored metadata. Greek sigma and U+0130 have focused wire controls and passing SQL controls; the migration is unchanged. Final native acceptance passed 3,232 tests with 120 skipped and zero failures, including the wire, paging and mounted forum controls. Portable acceptance passed 1,948 tests with 92 skipped and zero failures; unsigned Release compilation passed. See the [final source validation](build144-evidence/validation.json).

## Publication order after approval

1. Freeze the reviewed commit, both migration hashes, function source/config/lock manifests, current hosted versions and rollback source bundles. Refresh the intended project identity (`pausvvwoazbvmzyrebwl`) and migration history; stop on unexpected pending migrations or drift. Do not change campaign enablement, billing, retention policy or authentication settings as part of this rollout.
2. Apply only the two reviewed additive migrations above, in timestamp order, through the repository migration workflow. They add functions; they do not rewrite customer rows. Confirm recorded migration versions and function bodies against the frozen files before deploying dependent code.
3. Perform the read-only privilege/integrity checks below. Keep the existing backend live if those checks fail.
4. Deploy **both** authority entry points with their reviewed shared helper and patched verifier: `app-store-server-notifications` and `storekit-subscription-claims`. Preserve their current gateway settings: notification `verify_jwt = false` with Apple signature verification; claim `verify_jwt = true` plus authenticated ownership binding. A partial rollout leaves the old writer race possible. Verify both hosted source bundles and allow pre-deployment in-flight requests to finish before declaring the authority change active.
5. Deploy `storekit-complimentary-offers` as a separate verifier-dependency update. It also imports the patched verifier through `complimentary_offer_runtime.mjs`; campaign preparation/confirmation is not a smoke test. Preserve all campaign/window/QA/signing configuration and `verify_jwt = true`.
6. Deploy `account-deletion` separately with its reviewed cleanup helper and existing `verify_jwt = true`. Do not invoke deletion against any customer account for verification. Its cleanup correction does not require a new RPC migration.
7. Verify hosted bodies/configuration for all four changed entry points and record aggregate technical errors. Only then ship/install the app client using `search_forum_home`; missing RPC intentionally produces a clear unavailable error, not incomplete recent-feed search. App installation and App Store release remain separate steps.

Other shared authority-store importers use unchanged authentication/configuration/key helpers: forum actions, telemetry, retention, recognition-study consent/collection/upload and complimentary bookkeeping. They do not call the authority writer factory and do not require deployment for the atomicity fix. Preserve parked research configuration.

## Read-only production checks

- Inspect `pg_proc`, function bodies and ACLs: `public.apply_storekit_subscription_authority(jsonb,uuid)` must be invoker, `search_path=pg_catalog`, service-role executable and denied to PUBLIC/anon/authenticated; its independent `current_user` check must remain. Confirm service-role public-schema USAGE, subscription SELECT/INSERT/UPDATE and ledger SELECT/INSERT, plus expected RLS bypass. Existing live table permissions were verified; the migration does not expand them.
- Inspect `public.search_forum_home(text,integer,timestamptz,uuid)`: invoker/stable, empty search path, authenticated EXECUTE only, denied to PUBLIC/anon/service_role. Confirm underlying SELECT/RLS/block policies and current Pro predicate, without granting private-schema access.
- Use a read-only transaction for SQL smoke. An empty-original authority call under the service role can validate its harmless `missing_original_transaction` result; do not submit a customer original/notification UUID/transaction. Validate search through no-identity/Basic denial and an approved operator QA identity using aggregate counts only. No positive entitlement mutation, complimentary prepare/confirm, deletion or synthetic ledger insert belongs in production smoke.
- Recheck aggregate pointer integrity (missing referenced snapshots and owner/chart mismatches), subscription original uniqueness and newer mapped ledger clocks versus authority, plus invalid indexes, waits/errors and service health. Preserve customer content and ledger history. A zero anomaly count is a bounded observation, not proof that historical races never occurred.
- Live catalog evidence records authenticated and authenticator `statement_timeout=8s`, authenticator `lock_timeout=8s`; admin/global statement timeout is 120s. These are observed role/session settings, not a measured hosted search latency guarantee. Do not attempt to enforce the outer query budget by setting `statement_timeout` inside the running search function.

## Dependency and hosted bundle proof

The three Apple-verifying entry directories contain `deno.json` with a frozen adjacent `deno.lock`; lock format is v5 and the direct pins are `jsrsasign@11.1.5` and `@apple/app-store-server-library@3.1.0`. Each reviewed lock has 48 npm entries and SHA-256 `6737c95b408a55cb33313f3267bfdf7e58ee1ba0c859a51fbdb3134ec3389d92`; Apple's transitive edge also resolves to the sole jsrsasign 11.1.5 copy. Retain each entry point's lock/config in the release artifact.

The final checksum-pinned Deno 2.9.8 gate, with task-owned child HOME/XDG configuration and an empty npmrc, checked all three entry points, rejected a deliberately stale lock, left the reviewed locks unchanged and passed 15 offline controls (14 actual patched-verifier controls plus one real SDK request control). The reviewed exact-version advisory metadata covered all 48 npm entries with no affected version reported at that snapshot. See [dependency validation and lifecycle limits](../edge-dependency-validation.md); jsrsasign remains end-of-life debt, not a newly maintained dependency.

Local results do not prove hosted packaging. CLI 2.109.0's reviewed source-upload path does not explicitly include `deno.lock`. Local Edge Runtime 1.73.13 discovers locks and supports v5 conversion, but complete stale-lock rejection through its ESZIP packaging path was not established. Existing/next hosted transitive provenance and frozen-lock enforcement remain unverified. Before rollout, establish a supported packaging path with equivalent immutable dependency provenance; stop if this cannot be established. After rollout, compare hosted source/import pins and available bundle metadata with the approved packet. Do not describe local Deno compatibility as hosted-runtime acceptance or silently change verification algorithms/trust/fallback to bypass this boundary.

## Rollback

Restore affected Edge versions before revoking/dropping the authority RPC. Both authority writers must return to their saved compatible versions first; verify that no deployed/in-flight writer still calls the RPC. Leave the additive function in place while that is uncertain. Preserve every committed subscription and notification ledger row; rollback is not a ledger deletion or historical reconciliation.

Roll back the search client before removing its RPC. Leaving the additive search function installed is the safer rollback when clients may still use it. Restore complimentary/account-deletion Edge versions independently if needed, using the saved bundle/configuration; do not attempt to reverse real billing or deletions with database edits. Any migration removal must be a reviewed forward migration, not a rewrite of applied history.

## Managed PostgreSQL upgrade — separate approval and outage window

Production reports `17.6.1.127`; the Dashboard offers `17.11.0.018`. No upgrade has been triggered. This operational change is separate from the two RPC migrations and Edge deployment and needs its own approved downtime/recovery window; duration has not been established.

The Dashboard shows seven daily physical backups, 2026-10-30 through 2026-11-05. Storage object contents are excluded and PITR is off. Before scheduling, refresh backup freshness/restore readiness and create/verify a separately protected Storage-object backup/inventory; do not assume database recovery restores PDFs. Confirm recovery ownership and the provider-supported recovery path before accepting the outage. Do not promise an in-place downgrade.

The read-only targeted compatibility preflight found zero user `ltree` indexes, PGP-encrypt function uses, `btree_gist` floating-point indexes and custom non-builtin selectivity operators. Record and review installed extension compatibility and the official 17.11 changes again at scheduling time. Those zero counts cover the named checks only. After an approved upgrade, verify database/Auth/REST/Storage health, migrations/grants, aggregate chart pointer integrity and read-only RPC smoke before reopening normal release work.

## Evidence locations

Working backend evidence is under `/private/tmp/ichart-build144-app-db-audit-20261105`: `financial-serial-results.json`, `financial-concurrency.log`, `forum-pgtap-final-result.json`, `forum-isolated-pg17-README.md`, `backend-unit-rerun-result.json`, `backend-unit-rerun.log`, `edge-final-test.log`, `db-authority-permissions-and-bodies.json`, `db-timeout-configuration-result.json`, `db-storage-and-upgrade-result.json`, and `db-console-recovery-observations.json`. The final forum test source SHA-256 is `a9ac1354f37e844efb1506f3d43ac9e8d49589f6ad5285e2124a0ef9872db751`.

Compact dependency/advisor, frozen Deno, exact-version advisory, recovery and database health receipts are retained in [build144-evidence](build144-evidence/), alongside the [source SHA-256 manifest](build144-evidence/source-manifest.json). Bulky temporary evidence paths above remain working artifacts, not hosted deployment receipts. A production release receipt still needs actual migrated/deployed versions and verified hosted package provenance.
