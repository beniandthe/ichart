# Supabase Integration Runbook

Status: Sprint 1-5 implementation guide for iChart account/profile and Pro cloud chart backup/sync.

Plan policy authority: `docs/ichart-plan-policy-source-of-truth.md`

## Product Access Model

- Account creation/sign-in is mandatory for production Basic and Pro users.
- Auth, email verification, password recovery, profile, and subscription identity are the base trust layer.
- Chart authoring, local save, and export remain local-first and must not depend on chart cloud sync.
- Basic includes the complete local chart-writing tool, PDF/export, and a 3-chart local library cap.
- Cloud chart backup/sync/restore is a Pro subscription feature because it carries storage, security, support, and operational cost.
- Forums access is Pro-only.
- Until StoreKit/subscription entitlement wiring is implemented, the current signed-in chart sync path is an interim QA path. Before production rollout, gate `ChartCloudSyncService` and Forums behind active Pro entitlement.
- If Pro expires, cloud backup/sync and Forums should pause clearly.
- If a downgraded Basic account has more than 3 local charts, the app should prompt the user to choose which local charts to remove until only 3 remain.
- Downgrade pruning is local-only and must not enqueue cloud deletion tombstones.
- Remote chart backups should receive a clear grace period, recommended default 30 days, before cloud retention cleanup. Charts removed locally during downgrade pruning remain in cloud backup until the grace period ends.

## Local Setup

1. Install the Supabase CLI:
   - Homebrew: `brew install supabase/tap/supabase`
   - Or use the official package manager instructions from Supabase.
   - The local QA script can also fall back to `npx --yes supabase` when a global CLI is not installed.
2. Copy `.env.example` to `.env` and fill in local or project keys.
3. Confirm `supabase/config.toml` exists. It defines the local API/database ports and allows `ichart://auth-callback`.
4. Start local services: `supabase start`
5. Reset local database from migrations: `supabase db reset`
6. Run database tests when the CLI is available: `supabase test db`
7. Run the local QA harness: `scripts/run_supabase_local_qa.sh`

The checked-in local config keeps email confirmations and secure password changes enabled. Local integration tests confirm throwaway signup accounts through Mailpit before signing in.

The local QA harness intentionally derives `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from `supabase status -o env` after the local stack is running. It does not use `.env`, so remote project settings cannot accidentally redirect local RLS/integration tests.

## App Configuration

The app reads these values from the Xcode scheme environment or generated Info.plist build settings:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_ANON_KEY` as a temporary legacy fallback

For simulator QA, make sure the values reach the launched app process, not only the xcodebuild environment. With XcodeBuildMCP, `build_run_sim CODE_SIGNING_ALLOWED=NO` is enough to compile/install, but remote-account QA should relaunch the installed app with explicit runtime env:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "<publishable-key>"
}
```

If Settings shows `Account services offline` and Chart Sync shows `Cloud backup unavailable`, the app is running unconfigured. Relaunch with runtime env before treating account/sync behavior as a product failure.

Do not commit `.env`, service-role keys, JWT secrets, Stripe secrets, or dashboard export files.

## Dashboard Settings

- Parked follow-up: after the iChart domain and custom SMTP sender are configured, update the hosted Reset password template to use the direct app recovery link below and repeat password-reset QA from a fresh email.
- Enable email/password auth.
- Keep email verification enabled for production.
- Keep secure password changes enabled.
- Add `ichart://auth-callback` to Supabase Auth redirect URLs.
- Supabase rejects hosted email-template edits on free/default email provider projects. Configure custom SMTP before customizing production email templates.
- Configure the Reset password email template to avoid one-time HTTPS link prefetch/consumption:
  ```html
  <h2>Reset your password</h2>
  <p>We received a request to reset your iChart password.</p>
  <p><a href="ichart://auth-callback?token_hash={{ .TokenHash }}&type=recovery">Reset password in iChart</a></p>
  <p>If you did not request this, you can safely ignore this email.</p>
  ```
- During simulator QA, the verification link may open a blank browser page if it redirects to `ichart://auth-callback` outside the simulator. After opening the link, return to iChart and sign in with the same email/password.
- During password-reset QA, use the direct app recovery link. Settings should show `Set new password` before saving the replacement password.
- Temporary hosted-link fallback: if a reset email still contains the default `https://.../auth/v1/verify?token=...&type=recovery` link while the dashboard template is being updated, do not open it in a desktop browser first. Extract the `token` value, open `ichart://auth-callback?token=<token>&type=recovery` in the simulator, and let iChart verify it through Supabase Auth.
- Use the anon/publishable key in the app only.
- Keep the service-role key server-side only for future webhooks/admin jobs.

## Remote Deployment Checklist

1. Link the local repo to the Supabase project: `supabase link --project-ref <project-ref>`
2. Preview pending migrations: `supabase db diff --linked`
3. Push migrations: `supabase db push`
4. Confirm RLS is enabled on `profiles`, `chart_documents`, `chart_snapshots`, `subscriptions`, and `devices`.
5. Confirm the app redirect URL is present: `ichart://auth-callback`
6. Confirm no raw card data exists in database tables.

## QA Checklist

Use `docs/supabase-production-readiness-checklist.md` as the release-candidate checklist. Use `scripts/run_supabase_production_readiness.sh` for the secret-free automated gate, and add `SMART_CHART_RUN_LOCAL_SUPABASE_QA=1` when the local Supabase stack is ready for reset/RLS/integration verification.

- Unconfigured build launches and edits charts locally.
- Create account, resend verification, sign in, refresh session, and sign out.
- Request password reset and return to the app through `ichart://auth-callback`.
- Save profile fields to `profiles`.
- With active Pro entitlement, create, edit, delete, relaunch, sync, and restore charts after reinstall/sign-in.
- Without active Pro entitlement, confirm charts save locally, PDF/export remains available, Chart Sync clearly reports that cloud backup requires Pro, and Forums are locked.
- When a Basic account already has more than 3 local charts from a prior Pro period, confirm the app requires user-selected local pruning down to 3 charts.
- Confirm downgrade-pruned local charts do not create remote deletion tombstones and remain restorable from cloud snapshots until the grace period ends.
- Make offline edits, regain network, tap Sync Now, and confirm state recovers.

## Opt-In Integration Tests

Normal test runs stay secret-free and skip live Supabase checks. To run the live integration test directly:

```sh
SMART_CHART_SUPABASE_INTEGRATION=1 \
SUPABASE_URL=http://127.0.0.1:54321 \
SUPABASE_PUBLISHABLE_KEY=<local-publishable-key> \
swift test --filter SupabaseIntegrationTests
```

The integration test creates a throwaway account, saves a profile, creates a chart document, inserts a whole-chart snapshot, points the document to that snapshot, then tombstones the document. It does not use or require a service-role key.

If local Auth reports the email-send rate limit during repeated QA runs, the integration test waits out the local one-minute window and retries once.
