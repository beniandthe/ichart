# Supabase Integration Runbook

Status: Sprint 1-5 implementation guide for iChart account/profile and single-user chart backup/sync.

## Local Setup

1. Install the Supabase CLI:
   - Homebrew: `brew install supabase/tap/supabase`
   - Or use the official package manager instructions from Supabase.
2. Copy `.env.example` to `.env` and fill in local or project keys.
3. Confirm `supabase/config.toml` exists. It defines the local API/database ports and allows `ichart://auth-callback`.
4. Start local services: `supabase start`
5. Reset local database from migrations: `supabase db reset`
6. Run database tests when the CLI is available: `supabase test db`
7. Run the local QA harness: `scripts/run_supabase_local_qa.sh`

## App Configuration

The app reads these values from the Xcode scheme environment or generated Info.plist build settings:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_ANON_KEY` as a temporary legacy fallback

Do not commit `.env`, service-role keys, JWT secrets, Stripe secrets, or dashboard export files.

## Dashboard Settings

- Enable email/password auth.
- Keep email verification enabled for production.
- Add `ichart://auth-callback` to Supabase Auth redirect URLs.
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

- Unconfigured build launches and edits charts locally.
- Create account, resend verification, sign in, refresh session, and sign out.
- Request password reset and return to the app through `ichart://auth-callback`.
- Save profile fields to `profiles`.
- Create, edit, delete, relaunch, sync, and restore charts after reinstall/sign-in.
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
