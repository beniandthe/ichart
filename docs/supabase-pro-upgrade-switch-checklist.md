# iChart Supabase Pro Upgrade Switch Checklist

Status: Pro upgrade, retention scheduler, and SSL enforcement complete
Created: 2026-07-23
Project ref: `pausvvwoazbvmzyrebwl`

Use this checklist when the non-Discover card is ready. Do not paste payment
details, secrets, passwords, API keys, or recovery links into chat or docs.

## 1. User-Owned Billing Switch

This is the moment Codex should stop and hand control to the account owner.

- [x] In Supabase, confirm the selected organization/project is the iChart project:
  `pausvvwoazbvmzyrebwl`.
- [x] Choose Supabase Pro, not Team, for V1.0.
- [x] Keep spend cap on unless there is a deliberate reason to allow overages.
- [x] Confirm the billing owner/payment method.
- [x] Confirm the project now shows the paid plan as active.

2026-07-23 result: the organization shows Pro Plan, spend cap is enabled, and
the initial `$25.00` invoice is paid.

Do not enable public App Store release yet. Return to the remaining checks
below first.

## 2. Auth Hardening After Upgrade

- [x] Enable leaked-password protection.
- [x] Confirm email/password auth remains enabled.
- [x] Confirm email verification remains enabled.
- [x] Confirm anonymous auth remains disabled unless explicitly changed.
- [x] Confirm custom SMTP still sends from the iChart support sender.
- [x] Confirm password reset and signup confirmation still route through
  `ichart://auth-callback`.
- [x] Re-run Supabase advisors after the change.

2026-07-23 result: leaked-password protection is enabled, minimum password
length is `8`, custom SMTP is enabled with sender `support@useichart.com`, Auth
Site URL and redirect allowlist use `ichart://auth-callback`, and the only
remaining Supabase Auth advisor warning is MFA. A live password-recovery request
for the existing QA account returned HTTP `200` through the public Auth API.

Recommended V1.0 decision: document the MFA advisor as a post-V1 warning unless
a complete enrollment, recovery, and support flow is implemented and tested.

Reference:

- https://supabase.com/docs/guides/auth/password-security

## 3. Subscription Retention Scheduler

The code-side retention function exists, but the production scheduler and
secrets must be finished before public paid release.

- [x] Set `ICHART_RETENTION_JOB_SECRET` as an Edge Function secret.
- [x] Set the chosen email provider secret, such as `RESEND_API_KEY`, as an Edge
  Function secret.
- [x] Set `ICHART_RETENTION_EMAIL_FROM`, preferably
  `iChart <support@useichart.com>`.
- [x] Enable/install `pg_cron` and `pg_net`, or choose an equivalent trusted
  scheduler.
- [x] Schedule `subscription-retention-jobs` as a recurring authenticated POST.
- [x] Include either `Authorization: Bearer <secret>` or
  `x-ichart-retention-job-secret: <secret>` in the scheduled request.
- [x] Run the job against a release-gate retention row before trusting public
  retention.
- [x] Confirm missing email-provider secrets leave email events queued instead of
  silently dropping them.
- [x] Confirm cleanup never deletes local device charts.

2026-07-23 result: Resend verified `useichart.com`; Supabase secrets exist for
`ICHART_RETENTION_JOB_SECRET`, `RESEND_API_KEY`, and
`ICHART_RETENTION_EMAIL_FROM`; `pg_cron`, `pg_net`, and Vault are installed; and
cron job `ichart-subscription-retention-hourly` is active at `17 * * * *`.
Manual pg_net smoke returned `202` with `email_status: processed`,
`emails_sent: 1`, and `emails_failed: 0`.

Reference:

- https://supabase.com/docs/guides/functions/schedule-functions

## 4. Database Transport Hardening

Do not flip SSL enforcement until direct DB clients are inventoried.

- [x] Inventory direct Postgres clients: Supabase CLI, local scripts, GitHub
  Actions, Edge Functions, and any external DB tools.
- [x] Confirm each direct client can connect with SSL.
- [x] Enable Postgres SSL enforcement in Database Settings only after the inventory
  is clean.
- [x] Expect a brief database restart when SSL enforcement changes.
- [x] Re-run database smoke checks after the restart.

2026-07-23 result: `supabase ssl-enforcement get --project-ref
pausvvwoazbvmzyrebwl --experimental` reports `database: true`, and the
production readiness wrapper plus live Edge Function smoke checks passed after
the switch.

Reference:

- https://supabase.com/docs/guides/platform/ssl-enforcement

## 5. Required Verification After Upgrade

Run these from the repo after the dashboard switch and security toggles:

```sh
git status --short --branch
git diff --check
scripts/run_supabase_production_readiness.sh
supabase migration list --linked
supabase db advisors --linked --output json
supabase functions list --project-ref pausvvwoazbvmzyrebwl
supabase secrets list --project-ref pausvvwoazbvmzyrebwl
supabase ssl-enforcement get --project-ref pausvvwoazbvmzyrebwl
```

If local Supabase is available:

```sh
ICHART_RUN_LOCAL_SUPABASE_QA=1 scripts/run_supabase_production_readiness.sh
```

Expected public-boundary smoke results:

- App Store notification missing signed payload returns `400`.
- StoreKit claim without auth returns `401`.
- Forum post action without auth returns `401`.
- Subscription retention job without scheduler secret returns `401`.

## 6. Evidence To Save

- Supabase plan active.
- Spend cap state.
- Auth advisor output.
- Security/performance advisor output.
- SSL enforcement decision and result.
- Retention scheduler configuration proof without revealing secrets.
- Readiness wrapper output.
- Any live QA rows used for retention warning/deletion proof.
