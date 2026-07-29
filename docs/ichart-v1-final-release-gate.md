# iChart V1.0 Final Release Gate

Status: Active release-gate source of truth
Created: 2026-07-15
Last refreshed: 2026-07-29
Current candidate baseline: iChart V1.0 App Review account-deletion repair build `1.0 (33)`
Current App Review state: Build 32 rejected for Guideline 5.1.1 account deletion
Current public-release blocker: Build 33 account-deletion repair package, App Review notes/recording, and Apple approval
Post-baseline fixes included: chart cloud-backup provenance, explicit restore
behavior, current outside-QA polish, refreshed App Store screenshots and full
logo app icon, and public-site source cleanup

This document is the final release gate and ordered plan for iChart V1.0.
If another planning document conflicts with this file on launch ordering, gate
status, or release blockers, this file wins until it is replaced by a newer
release-gate document.

Supporting docs:

- `docs/v1-production-deployment.md`
- `docs/ichart-v1-1-roadmap.md`
- `docs/supabase-production-readiness-checklist.md`
- `docs/supabase-pro-upgrade-switch-checklist.md`
- `docs/ichart-storekit-subscription-runbook.md`
- `docs/ichart-plan-policy-source-of-truth.md`
- `docs/app-store-testflight-metadata-draft.md`

## 1. Current Release Call

Build 33 is the planned V1.0 App Review repair build. It supersedes build 32
only to address App Review feedback for Guideline 5.1.1: apps that support
account creation must let users initiate account deletion in the app.

Build 32 was rejected by App Review on 2026-07-29 under `5.1.1 Legal:
Privacy - Data Collection and Storage` because iChart supports account creation
but did not include an in-app account deletion option. The included
subscription group and subscription products were rejected only because the
associated app version was rejected.

Build 33 acceptance before resubmission:

- Settings > Account exposes `Delete Account` for signed-in users.
- Deletion uses a destructive confirmation and signs the app out after the
  server accepts deletion.
- The account-deletion server path requires authenticated user bearer auth,
  rejects malformed/oversized/unconfirmed requests, deletes server-owned
  account data for only the authenticated user, and then deletes the Supabase
  Auth user.
- `account-deletion` is deployed as a Supabase Edge Function with
  `verify_jwt = true`.
- App Review Notes explain the deletion path:
  Settings > Account > Delete Account.
- A physical-device recording is attached in App Review Notes showing sign-in
  or account creation, navigation to the deletion option, and the deletion
  flow through confirmation.

Build 32 superseded build 31 only to address App Review feedback: App Store
metadata now avoids the inappropriate subtitle use of Apple product terms, and
the signed-out account panel defaults to an explicit, prominent Sign In flow
for the provided review account.

Build 31 superseded the build 30 candidate baseline because the first
submission used generic App Store media and the smaller previous icon
treatment. Build 31 kept the accepted V1 app behavior while refreshing the App
Store screenshot set and binary-backed app icon.

Build 30 completed the final TestFlight QA acceptance window with no incoming
critical QA blockers as of 2026-07-24. Build 31 is a media/build-number
replacement for that accepted V1 state.

The chart cloud-backup provenance fix is now part of the candidate baseline. It
prevents automatic backup from silently pulling or resurrecting stale cloud
charts during local editing, and keeps cloud restore as an explicit Settings
action.

The app was resubmitted to App Review on 2026-07-25 after replacing build 30
with build 31 and the refreshed iPad screenshot set. Public availability still
depends on Apple approval, final release controls in App Store Connect, and
normal release-day monitoring.

The build 31 App Review rejection was repaired and resubmitted on 2026-07-27
with build 32 attached to the same App Store Connect submission. Build 32 was
then rejected on 2026-07-29 for missing in-app account deletion.

Current verified source baseline:

- Build 33 archive/upload app-source commit: pending.
- Build 32 archive/upload app-source commit: `68fd288`.
- Build 31 archive/upload app-source commit: `da55cf1`.
- Last code/test gate head before doc-only release-evidence updates: `2ad1bc5`.
- `2ad1bc5` differs from the uploaded build source only by the test-target
  build-number gate assertion update.
- Later release-evidence doc updates do not alter the app target.
- GitHub CI passed for `68fd288` on 2026-07-27; CodeQL passed for the repair
  commit during the build 32 repair checks.
- There are no open PRs.
- Remote Supabase migrations are aligned through `20260714172551`.
- `scripts/run_supabase_production_readiness.sh` passed.
- Supabase shared Node authority/function tests passed before account-deletion
  repair: `64/64`.
- Supabase shared Node authority/function tests passed after account-deletion
  repair: `75/75`.
- SwiftPM passed locally on the current candidate: `654` tests,
  `38` skipped, `0` failures.
- Focused Swift tests passed: `94` tests, `2` skipped, `0` failures.
- A generic iOS Simulator build succeeded from the generated Xcode project.
- Signed archive and upload completed for `com.ichart.app`, version `1.0`,
  build `32`; build `32` is superseded by the planned build `33` account
  deletion repair.
- Supabase `account-deletion` Edge Function is deployed and active with
  `verify_jwt = true`.
- `account-deletion` unauthenticated hosted smoke returns `401`
  `UNAUTHORIZED_NO_AUTH_HEADER`.
- TestFlight Outside QA accepted build `1.0 (30)` behavior; build `1.0 (31)`
  is the App Store media/icon replacement package.
- App Store Connect submission `06b203db-9cdf-401b-bf58-78066c20ad0b` was
  rejected on 2026-07-27 for subtitle wording and Sign In actionability. Build
  `32` repaired those issues but was rejected on 2026-07-29 for missing
  in-app account deletion.
- App-facing `public` tables have RLS enabled.
- `private` schema is not usable by `anon` or `authenticated`.
- `forum_chart_pdfs` storage is private, PDF-only, and capped at 10 MB.
- Edge Function unauthenticated/bad-input smoke checks fail closed as expected.
- No tracked or non-ignored untracked `.env`, key, cert, provisioning, `.p8`,
  PEM, or mobile provisioning files were found.
- Public site source has been moved back to prelaunch-safe App Store wording
  until a real public App Store or pre-order URL is verified and deployed.

Current remaining release caveats:

1. Supabase Auth advisor still reports insufficient MFA options. This is tracked
   but should not force a half-built user MFA flow into V1.
2. Local Supabase reset/RLS integration QA still depends on Docker/OrbStack
   being available.
3. Dedicated local history scanners such as `gitleaks` or `trufflehog` were not
   installed during the latest sweep.

## 2. Fixed Production Facts

Do not change these during the V1.0 release gate unless a release blocker proves
they are wrong.

- App name: `iChart: Quick-Notation Charts`
- Bundle ID: `com.ichart.app`
- Supabase project ref: `pausvvwoazbvmzyrebwl`
- Supabase URL: `https://pausvvwoazbvmzyrebwl.supabase.co`
- Support site: `https://useichart.com`
- Support URL: `https://useichart.com/support`
- Privacy URL: `https://useichart.com/privacy`
- Support email: `support@useichart.com`
- Monthly product: `com.ichart.app.pro.monthly`
- Annual product: `com.ichart.app.pro.annual`
- TestFlight/native auth callback: `ichart://auth-callback`
- Universal links: post-V1 follow-up unless explicitly reprioritized.
- Observability for V1: Apple-native crash/TestFlight feedback plus in-app
  Help/Contact path. Do not add Sentry, Firebase, or analytics SDKs during this
  release gate.

## 2.1 V1.1 Forward Promise

Do not expand the V1.0 release promise to include these items. They are the
V1.1 goal and statement moving forward:

- Key signatures.
- Select input for rhythm notation.
- Enharmonic transposition and preferences.
- Additional chord coverage for obscure and less-common chord symbols.

Use `docs/ichart-v1-1-roadmap.md` as the source of truth for V1.1 scope. In
V1.0, Rhythm Section rhythm notation remains Free-Write unless data already
exists as rendered rhythm maps; the retired handwritten rhythm recognizer should
not be reintroduced as a release blocker.

## 3. Supabase Plan Decision

This section refers to the Supabase infrastructure plan, not the iChart Basic
app tier.

Verified from Supabase pricing/docs on 2026-07-15:

| Plan | Relevant included limits/features | V1.0 release call |
| --- | --- | --- |
| Free | 50k MAU, 500 MB database, shared CPU/500 MB RAM, 5 GB egress, 1 GB file storage, 500k Edge Function invocations, custom SMTP, community support, no automatic backups, 1 day API/database logs, project pauses after 1 week of inactivity, leaked-password protection not included | Acceptable for tiny trusted QA only. Not acceptable for public paid V1. |
| Pro | Starts at $25/month, 100k MAU, 8 GB database disk, 250 GB egress, 100 GB file storage, 2M Edge Function invocations, email support, daily backups stored 7 days, 7-day logs, no project pausing, leaked-password protection available, spend cap available | Correct V1.0 production plan. Upgrade here before public release. |
| Team | Starts at $599/month, everything in Pro plus SOC2/ISO posture, project-scoped/read-only access, dashboard SSO, priority email support/SLA, 14-day backups, 28-day logs | Not needed for V1 unless an enterprise/compliance requirement appears. |

Decision:

- Use Supabase Free only while waiting for the non-Discover card and for limited
  outside QA with trusted testers.
- Upgrade to Supabase Pro before public App Store V1.0 release.
- Keep spend cap on at first.
- Do not use Team for V1.0 unless a specific compliance, SSO, SLA, or enterprise
  access-control need appears.

Primary Supabase references:

- https://supabase.com/pricing
- https://supabase.com/docs/guides/platform/billing-on-supabase
- https://supabase.com/docs/guides/auth/password-security
- https://supabase.com/docs/guides/functions/schedule-functions
- https://supabase.com/docs/guides/security/platform-security

## 4. Ordered Release Gates

Follow this order. Do not skip ahead to public App Store submission until every
P0 gate is closed.

### Gate 0 - Freeze the candidate baseline

Status: Complete for build 30.

Acceptance:

- [x] Confirm `main` and `origin/main` point to the candidate commit.
- [x] Confirm no open PRs.
- [x] Confirm CI and CodeQL passed on the candidate commit.
- [x] Confirm build 29 was manually tested and accepted before the final polish
  fixes.
- [x] Package and upload TestFlight build 30 from current `main`.
- [x] Confirm TestFlight build 30 was manually tested and accepted as V1.0
  candidate.
- [x] Record any tester-facing known issues that are accepted for V1.0.

Commands:

```sh
git status --short --branch
git log -1 --oneline --decorate
gh pr list --state open --limit 20
gh run list --branch main --limit 5
```

### Gate 1 - Upgrade Supabase to Pro

Status: Complete on 2026-07-23.
Priority: P0 before public release.

Acceptance:

- [x] Supabase organization/project is on Pro.
- [x] Spend cap is on unless deliberately changed.
- [x] Billing owner/payment method is confirmed.
- [x] Project no longer has Free-plan production risk: project pausing, no
  automatic backups, thin support/log posture.

Notes:

- This is not needed to keep testing with two trusted external QA users.
- This is required before public paid V1.0 launch.

2026-07-23 result: the organization shows Pro Plan, spend cap is enabled, and
the initial `$25.00` invoice is paid.

### Gate 2 - Harden Supabase Auth

Status: Leaked-password protection complete; MFA advisor intentionally deferred
unless V1 scope changes.
Priority: P0 for leaked-password protection, P1 for MFA user-flow expansion.

Acceptance:

- [x] Enable leaked-password protection.
- [x] Set password requirements deliberately. Minimum: do not allow weak
  production passwords below the current policy.
- [x] Confirm email/password provider remains enabled.
- [x] Confirm email verification remains enabled.
- [x] Confirm anonymous auth is disabled unless intentionally changed.
- [x] Confirm custom SMTP remains configured through `support@useichart.com`.
- [x] Confirm password reset and signup confirmation flows still land in
  `ichart://auth-callback` and are protected by pending-flow state in app code.
- [x] Decide MFA posture for V1. Recommended: document warning as post-V1 unless
  a complete enrollment/recovery UX is added and tested.

2026-07-23 update: leaked-password protection is enabled, minimum password
length is `8`, secure email change remains enabled, secure password change
remains enabled, email auth remains enabled, email confirmation remains enabled,
and anonymous sign-ins remain disabled. Custom SMTP is enabled with sender
`support@useichart.com`, sender name `iChart`, host `smtp.ionos.com`, port
`587`, and SMTP user `support@useichart.com`. Auth Site URL and redirect
allowlist include `ichart://auth-callback`. Supabase advisors now report only
the expected MFA warning. A live password-recovery request for the existing QA
account returned HTTP `200` through the public Auth API with redirect
`ichart://auth-callback`.

Validation:

```sh
supabase db advisors --linked --output json
```

Expected after Pro/auth hardening:

- Leaked-password warning is cleared.
- MFA warning may remain if V1 intentionally ships without MFA/passkeys.

### Gate 3 - Finish subscription retention automation

Status: Complete as of 2026-07-23.
Priority: P0 before public paid V1.0.

Why this matters:

The app policy says canceled-but-paid-through users keep Pro until
`entitlement_expires_at`; after true expiration or grace deadline, cloud backups
are removed by server-side retention cleanup, while local charts are never
silently deleted. That policy needs a real scheduler and email path before broad
public release.

Acceptance:

- [x] Set `ICHART_RETENTION_JOB_SECRET` as a Supabase Edge Function secret.
- [x] Set `RESEND_API_KEY` or the chosen provider secret as a Supabase Edge
  Function secret.
- [x] Set `ICHART_RETENTION_EMAIL_FROM`, preferably
  `iChart <support@useichart.com>`.
- [x] Enable/install `pg_cron` and `pg_net`, or choose an equivalent trusted
  scheduler.
- [x] Schedule `subscription-retention-jobs` as a POST request.
- [x] Scheduler includes either
  `Authorization: Bearer <ICHART_RETENTION_JOB_SECRET>` or
  `x-ichart-retention-job-secret: <ICHART_RETENTION_JOB_SECRET>`.
- [x] Run against a release-gate retention row and confirm warning/deletion
  events behave correctly.
- [x] Confirm missing email-provider secrets leave email events queued rather
  than silently dropping them.
- [x] Confirm the job never deletes local device charts.

2026-07-23 production evidence:

- Resend domain `useichart.com` is verified and ready to send.
- Supabase Edge Function secrets exist for `ICHART_RETENTION_JOB_SECRET`,
  `RESEND_API_KEY`, and `ICHART_RETENTION_EMAIL_FROM`.
- `pg_cron`, `pg_net`, and Vault are installed/enabled.
- Cron job `ichart-subscription-retention-hourly` is active at
  `17 * * * *` and reads the scheduler secret from Vault.
- Manual pg_net smoke request returned `202` with `email_status: processed`,
  `emails_sent: 1`, and `emails_failed: 0`.
- DB evidence after the smoke: `retention_events = 1`, `sent_events = 1`,
  `failed_events = 0`, `pending_retention_count = 0`, and
  `deleted_subscription_count = 1`.

Validation:

```sh
supabase functions list --project-ref pausvvwoazbvmzyrebwl
supabase secrets list --project-ref pausvvwoazbvmzyrebwl
supabase db query --linked "select to_regclass('cron.job') as cron_job_table, exists(select 1 from pg_extension where extname = 'pg_cron') as pg_cron_installed, exists(select 1 from pg_extension where extname = 'pg_net') as pg_net_installed;"
```

Do not put retention secrets in docs, chat, Xcode settings, `.env.example`, or
the app bundle.

### Gate 4 - Enable database transport hardening

Status: Complete as of 2026-07-23.
Priority: P0/P1. Treat as P0 if any direct DB clients exist outside Supabase
managed paths.

Acceptance:

- [x] Inventory direct Postgres clients: local scripts, GitHub Actions,
  Supabase CLI, Edge Functions, external tools.
- [x] Confirm every direct DB client can use SSL.
- [x] Enable Postgres SSL enforcement.
- [x] Re-run readiness and remote DB smoke checks.

2026-07-23 production evidence:

- `supabase ssl-enforcement get --project-ref pausvvwoazbvmzyrebwl
  --experimental` reports `database: true`.
- `scripts/run_supabase_production_readiness.sh` passed after the SSL switch.
- Live Edge Function smokes still fail closed with the expected
  `400`/`401` responses.

Validation:

```sh
supabase ssl-enforcement get --project-ref pausvvwoazbvmzyrebwl
# Enable only after the client inventory is confirmed.
# supabase ssl-enforcement update --project-ref pausvvwoazbvmzyrebwl --enable-db-ssl-enforcement
```

### Gate 5 - Re-run database, RLS, storage, and secret checks

Status: Complete for remote production checks as of 2026-07-23; local Supabase
reset/RLS integration remains optional when Docker/OrbStack is available.
Priority: P0.

Acceptance:

- [x] `scripts/run_supabase_production_readiness.sh` passes.
- [x] `supabase migration list --linked` shows local and remote alignment.
- [x] `supabase db advisors --linked --output json` has no unaccepted P0/P1
  findings.
- [x] All app-facing public tables still have RLS enabled.
- [x] `private` schema still denies `anon` and `authenticated` usage.
- [x] Forum PDF bucket remains private, PDF-only, and capped.
- [x] Edge Function public boundaries still fail closed.
- [ ] Dedicated history scanner runs, or GitHub secret scanning/push protection
  is verified as active.

Core commands:

```sh
scripts/run_supabase_production_readiness.sh
supabase migration list --linked
supabase db advisors --linked --output json
supabase functions list --project-ref pausvvwoazbvmzyrebwl
supabase secrets list --project-ref pausvvwoazbvmzyrebwl
```

RLS/storage checks:

```sh
supabase db query --linked "select n.nspname as schema, c.relname as table, c.relrowsecurity as rls_enabled from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.relkind = 'r' and n.nspname in ('public','storage') order by n.nspname, c.relname;"
supabase db query --linked "select nspname, has_schema_privilege('anon', nspname, 'USAGE') as anon_usage, has_schema_privilege('authenticated', nspname, 'USAGE') as authenticated_usage from pg_namespace where nspname in ('public','private','storage') order by nspname;"
supabase db query --linked "select id, public, file_size_limit, allowed_mime_types from storage.buckets order by id;"
```

Function smoke checks:

```sh
curl -i -X POST https://pausvvwoazbvmzyrebwl.supabase.co/functions/v1/app-store-server-notifications \
  -H 'content-type: application/json' \
  --data '{}'

curl -i -X POST https://pausvvwoazbvmzyrebwl.supabase.co/functions/v1/storekit-subscription-claims \
  -H 'content-type: application/json' \
  --data '{}'

curl -i -X POST https://pausvvwoazbvmzyrebwl.supabase.co/functions/v1/forum-post-actions \
  -H 'content-type: application/json' \
  --data '{}'

curl -i -X POST https://pausvvwoazbvmzyrebwl.supabase.co/functions/v1/account-deletion \
  -H 'content-type: application/json' \
  --data '{}'

curl -i -X POST https://pausvvwoazbvmzyrebwl.supabase.co/functions/v1/subscription-retention-jobs \
  -H 'content-type: application/json' \
  --data '{}'
```

Expected unauthenticated/bad-input shape:

- App Store notifications missing signed payload: `400`.
- StoreKit claim without auth: `401`.
- Forum post actions without auth: `401`.
- Account deletion without auth: `401`.
- Retention job without scheduler secret: `401`.

### Gate 6 - Switch/confirm Apple production subscription authority

Status: Sandbox/TestFlight authority is working; production authority must be
confirmed before public App Store release.
Priority: P0.

Acceptance:

- [ ] App Store Connect app ID and subscription products are final.
- [ ] App Store Server Notifications V2 production URL is configured where
  Apple requires it.
- [ ] Supabase Edge Function secrets match the target environment.
- [ ] `APP_STORE_ENVIRONMENT` is set intentionally for the target phase:
  `Sandbox` for TestFlight sandbox checks, `Production` for production App Store
  traffic.
- [ ] `APP_STORE_APP_APPLE_ID` is set before production verification.
- [ ] App Store root certificates are current.
- [ ] StoreKit product fetch, purchase, restore, claim, entitlement row, Pro
  unlock, downgrade/expiry behavior, and cross-account duplicate rejection are
  verified after any environment switch.

Do not bundle App Store Connect API keys, Apple signing keys, service-role keys,
or verifier secrets into the app.

### Gate 7 - Final TestFlight outside-QA evidence

Status: Accepted for V1.0 submission.
Priority: P0 before App Store submission.

Acceptance:

- [x] Build 30 was assigned as the active outside-QA build for final behavior
  acceptance.
- [ ] At least two outside testers can create new accounts.
- [ ] At least one tester exercises Basic: create/edit/export/reopen charts.
- [ ] At least one tester exercises Pro sandbox purchase/restore and Forums.
- [x] Build 30-specific polish is verified: repeat-tool pending selections show
  visual feedback and double-tap chord correction remains keyboard-only,
  uncluttered, and bounded to the correction sheet.
- [x] No critical crashes, data loss, account lockout, purchase/restore failure,
  or chart export corruption is seen.
- [x] Any accepted known issue is written down in this doc or the release notes.
- [x] Build 31 repeated the repo/CI gate; Supabase/backend state is unchanged
  from the earlier final gate.

2026-07-24 acceptance note: outside QA remains available for ongoing signal, but
no critical build-30 QA blockers were reported during the final acceptance
window. The release call is to proceed with the same accepted app behavior.

2026-07-25 replacement note: build `1.0 (31)` replaces build `1.0 (30)` for
App Store submission media quality. The app behavior is unchanged; build 31
adds the refreshed ten-image iPad screenshot package and full-logo app icon.

2026-07-27 repair note: App Review rejected build `1.0 (31)` for metadata
wording around Apple product terms in the subtitle and for the review Sign In
button being judged non-actionable. The repair keeps version `1.0`, bumps the
build to `32`, uses the App Review-safe subtitle `Fast charts for musicians`,
and makes Sign In the default signed-out account mode.

2026-07-27 repair resubmission update:

- Submission ID: `06b203db-9cdf-401b-bf58-78066c20ad0b`.
- Date resubmitted: 2026-07-27.
- Status: `Waiting for Review`.
- Items submitted together:
  - `iOS App 1.0`, build `1.0 (32)`.
  - `iChart Pro`, subscription group.
  - `iChart Pro Monthly`, subscription
    `com.ichart.app.pro.monthly`.
  - `iChart Pro Annual`, subscription
    `com.ichart.app.pro.annual`.
- Manual release remains selected, so approval alone should not automatically
  make V1.0 public.

2026-07-29 account-deletion repair update:

- App Review rejected build `1.0 (32)` for Guideline `5.1.1 Legal: Privacy -
  Data Collection and Storage`.
- Required repair: users must be able to initiate account deletion from inside
  iChart because the app supports account creation.
- Implemented repair target: build `1.0 (33)` with Settings > Account > Delete
  Account, Supabase `account-deletion` Edge Function, hosted privacy/support
  copy updates, and App Review notes/recording evidence.
- The local public-site source is updated, but live `https://useichart.com`
  still needs the changed `privacy.html` and `support.html` deployed before
  resubmission if App Review metadata continues to point to those URLs.

### Gate 8 - App Store public submission package

Status: Build 32 rejected; build 33 account-deletion repair in progress.
Priority: P0.

2026-07-20 website/App Store readiness update:

- Local `public-site/useichart` source now has a launch-facing home page with current support/privacy routes and prelaunch-safe CTAs.
- Live `https://useichart.com` must be checked after deployment from the
  updated local source before this gate can be marked complete.
- App Store metadata draft has been revised toward the current `handwrite clean charts at paper speed` positioning and away from automatic cleanup/messy-chart language.
- Screenshot plan is drafted, but actual App Store screenshot assets still need capture/export at Apple-accepted iPad sizes.
- Do not use the launch-video end-card wording `Available on the App Store` publicly until the App Store product page or pre-order page is live.

2026-07-24 App Review prep update:

- Build `1.0 (30)` is attached to App Store Connect version `1.0`.
- App Review notes are saved for build `1.0 (30)`.
- Manual release remains selected.
- App pricing is set to Free, and availability is configured for all 175
  countries or regions.
- The iPad screenshot set has five current screenshots attached.
- The `iChart Pro` subscription group was added to the App Review submission.
- App Review Contact Information and demo review account credentials were
  entered in App Store Connect. The demo account password is stored in local
  Keychain item `iChart App Review Account` and must stay out of chat, docs,
  git, and local scripts.

2026-07-24 App Review submission update:

- Submission ID: `d83d8099-934d-4cfd-a381-04edb2150367`.
- Date submitted: 2026-07-24 at 3:08 PM Pacific.
- Submitted by: Beni Rossman.
- Status: Developer removed/replaced on 2026-07-25.
- Items submitted together:
  - `iOS App 1.0`, build `1.0 (30)`.
  - `iChart Pro`, subscription group.
  - `iChart Pro Monthly`, subscription
    `com.ichart.app.pro.monthly`.
  - `iChart Pro Annual`, subscription
    `com.ichart.app.pro.annual`.
- Manual release remains selected, so approval alone should not automatically
  make V1.0 public.

2026-07-25 App Review replacement update:

- Replacement submission ID: `06b203db-9cdf-401b-bf58-78066c20ad0b`.
- Date submitted: 2026-07-25 at 8:28 PM Pacific.
- Submitted by: Beni Rossman.
- Status: `Waiting for Review`.
- Items submitted together:
  - `iOS App 1.0`, build `1.0 (31)`.
  - `iChart Pro`, subscription group.
  - `iChart Pro Monthly`, subscription
    `com.ichart.app.pro.monthly`.
  - `iChart Pro Annual`, subscription
    `com.ichart.app.pro.annual`.
- Ten refreshed 13-inch iPad screenshots are attached in order:
  `01-chart-editor-first-dance.png` through
  `10-rhythm-chart-last-dance.png`.
- The build 31 App Store Connect icon thumbnail resolves to the regenerated
  full-logo iChart icon.
- Manual release remains selected, so approval alone should not automatically
  make V1.0 public.

Acceptance:

- [x] App metadata final.
- [x] Privacy policy URL live.
- [x] Support URL live.
- [x] App privacy nutrition answers complete and truthful.
- [x] Subscription review notes complete.
- [x] App Review contact information and demo/review account credentials are
  entered user-side in App Store Connect.
- [x] Screenshots and preview media match the current app.
- [x] Known issues are either fixed or acceptable for V1.
- [x] Version/build numbers are final.
- [x] Final archive is created from the accepted app-source commit; later
  commits are limited to test-target gate alignment and release-evidence docs.
- [x] Release evidence is saved: build number, commit hash, CI URL, Supabase
  checks, App Store Connect state, and QA notes.

### Gate 9 - Release day and first-week watch

Status: Pending.
Priority: P1 after approval.

Acceptance:

- [ ] Support inbox is monitored.
- [ ] TestFlight/App Store crash and feedback channels are monitored.
- [ ] Supabase logs are checked daily during the first week.
- [ ] App Store Server Notification function is checked for errors.
- [ ] Retention job schedule is checked after the first run.
- [ ] StoreKit restore path is rechecked after public availability.
- [ ] A hotfix branch process is ready if the accepted V1.0 build needs a fast
  patch.

## 5. What Is Allowed Before Supabase Pro

Allowed:

- Continue trusted outside QA.
- Collect tester notes.
- Add no-risk documentation updates.
- Fix critical bugs only if they are clearly reproducible and release-blocking.
- Prepare App Store metadata, screenshots, review notes, and support docs.

Not allowed:

- Public App Store launch.
- Broad public beta link.
- Marketing push to unknown users.
- Any release promise that depends on automatic retention email/deletion until
  the job is scheduled and verified.

## 6. Security Rules That Stay Non-Negotiable

- Secrets never go into chat, git, Xcode settings, docs, `.env.example`, or app
  bundles.
- The iOS app embeds only client-safe Supabase URL and publishable key.
- Service-role and secret keys stay server-side only.
- Subscription rows remain read-only from the app.
- Cloud Backup and Forums are gated by server-enforced active Pro checks, not
  only client UI.
- Automatic chart backup uploads only chart-level cloud-enrolled charts; legacy
  local charts remain local-only until the user explicitly taps `Back Up Now`.
- Cloud delete tombstones are sent only for charts with a confirmed cloud backup
  record.
- Forum attribution is server-owned from locked profile names.
- Published forum PDFs require validated post-bound provenance.
- StoreKit purchases use stable per-account `appAccountToken` binding.
- App Store notifications are idempotent by notification UUID and cannot rewind
  subscription authority with stale signed dates.
- Auth callbacks require pending local state and compatible flow type.
- Phone verification remains legacy/post-V1 unless a complete flow is built.

## 7. Deferred Follow-Ups

These are intentionally not required for V1.0 public release unless a new risk
appears.

- Universal links for auth callback.
- Passkeys or full MFA enrollment/recovery UX.
- App Store Server API current-status polling beyond the current verified
  notification/claim path.
- Sentry/Firebase/third-party analytics SDKs.
- Team/Enterprise Supabase plan.
- Public moderation dashboard beyond current forum provenance, pending,
  publish/withdraw/remove, voting, reporting, and abuse policy controls.

## 8. Final Go/No-Go Rule

Release can move to public App Store only when:

1. Build 30, or a newer intentionally approved build, remains product-green.
2. Supabase Pro is active.
3. Leaked-password protection is enabled.
4. Retention job secrets and scheduler are live.
5. DB SSL enforcement has either been enabled or explicitly risk-accepted after
   direct-client inventory.
6. Remote Supabase advisors, readiness wrapper, RLS/storage checks, function
   smoke checks, and CI are green.
7. Apple production subscription/server-notification settings are confirmed.
8. Outside-QA evidence shows no critical V1 blockers.

If any P0 item is not complete, stay in TestFlight/outside-QA and do not submit
for public release.
