# Supabase Production Readiness Checklist

Status: Sprint 5 checklist for iChart account verification, profile sync, and single-user chart backup/sync.

## Non-Secret Project Facts

- Product: iChart / Smart Chart.
- Supabase project ref: `pausvvwoazbvmzyrebwl`.
- Remote URL shape: `https://pausvvwoazbvmzyrebwl.supabase.co`.
- The iOS app may receive only the project URL and publishable/anon client key.
- Database passwords, JWT secrets, service-role keys, SMTP credentials, Stripe secrets, and webhook signing secrets stay out of the app and out of git.

## Dashboard Configuration

Supabase Auth references:

- [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- [Native mobile deep linking](https://supabase.com/docs/guides/auth/native-mobile-deep-linking)
- [General Auth configuration](https://supabase.com/docs/guides/auth/general-configuration)
- [Email templates](https://supabase.com/docs/guides/auth/auth-email-templates)

Required production settings:

- Auth email/password provider is enabled.
- New user signup is enabled for QA builds.
- Confirm Email is enabled.
- Secure password changes are enabled.
- URL Configuration allows `ichart://auth-callback`.
- Password reset and signup confirmation redirects use `ichart://auth-callback`.
- Email templates keep a confirmation link flow unless the app adds a deliberate OTP/code-entry screen.
- Custom SMTP is configured before relying on branded production emails or high-volume QA.
- No service-role key, database password, JWT secret, or Stripe secret is copied into Xcode settings, `.env.example`, docs, or app code.

## Automated Local Gate

Run the secret-free production readiness wrapper:

```sh
scripts/run_supabase_production_readiness.sh
```

That wrapper runs whitespace hygiene, ignored-path checks, key-shaped secret scanning, focused Supabase/chart tests, and full SwiftPM unless `SMART_CHART_SKIP_FULL_SWIFTPM=1` is set.

When a local Supabase stack is available, include SQL/RLS and live local integration coverage:

```sh
SMART_CHART_RUN_LOCAL_SUPABASE_QA=1 scripts/run_supabase_production_readiness.sh
```

The local QA path resets the local database, runs `supabase test db`, derives local URL/key values from `supabase status -o env`, and runs `SupabaseIntegrationTests` with a throwaway local Auth account.

## Manual Simulator Gate

Use the iPad simulator because the runtime app target owns the Settings/account/sync UI.

1. Launch without Supabase env.
2. Confirm Settings shows account services unavailable and chart sync unavailable.
3. Confirm charts can still be created, edited, deleted, relaunched, and saved locally.
4. Relaunch the same installed build with `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
5. Create a new account with email/password.
6. Open the verification email. If the browser ends on a blank deep-link page, return to the app and sign in with the same email/password.
7. Confirm Settings shows `Verified`.
8. Request a password reset from the signed-out Account panel.
9. Open the reset email through a path that can hand `ichart://auth-callback` to the simulator/app.
10. Confirm Settings shows `Set new password`, enter a new password, save, sign out, and sign back in with the new password.
11. Save email, phone, address, and payment summary profile fields. Payment summary must remain text/customer-reference only.
12. Tap `Sync Now` and confirm Chart Sync returns to `Synced` with an updated Last Backup time.
13. Create a Simple Chord Sheet, edit at least one chord, and wait for sync to return to `Synced`.
14. Create a Rhythm Section chart, add visible chart content, and wait for sync to return to `Synced`.
15. Delete one disposable QA chart and confirm it does not return after relaunch.
16. Sign out, relaunch, sign back in, and confirm the expected charts restore.

## Restore/Reinstall Gate

Use only disposable QA charts for this pass.

1. Record the visible chart IDs or titles and the remote document count.
2. Stop the app.
3. Remove local app data or reinstall the simulator app.
4. Relaunch with Supabase env and sign in.
5. Confirm remote active charts restore locally.
6. Confirm remote tombstones remain deleted and do not resurrect older local copies.
7. Confirm Settings reports `Synced` and Last Backup.

## Offline/Failure Gate

1. Sign in and reach a known `Synced` state.
2. Disable network or launch against a deliberately unreachable Supabase URL.
3. Make a local chart edit.
4. Confirm local editing and local save continue.
5. Confirm Chart Sync reports an offline/failed state with a retry action, not raw backend errors.
6. Restore network or the correct Supabase URL.
7. Tap `Retry Sync` or `Sync Now`.
8. Confirm Chart Sync returns to `Synced` and the remote backup time updates.

## Data And RLS Gate

- Anonymous reads/writes to owner-scoped tables are denied.
- A signed-in user can read and write only their own `profiles`, `chart_documents`, `chart_snapshots`, and `devices` rows.
- The app can read but not write subscription rows.
- `chart_documents.latest_snapshot_id` cannot point to another user's snapshot or a missing snapshot.
- Chart deletes create tombstones instead of hard-deleting the sync marker.
- `profiles.stripe_customer_id`, raw card numbers, CVC values, and payment tokens are not app-writable profile fields.

## Evidence To Keep With The Release Candidate

- Commit hash.
- Supabase project ref.
- `scripts/run_supabase_production_readiness.sh` result.
- Local Supabase QA result, when run.
- iPad simulator build/run result.
- Screenshot or UI snapshot of unconfigured Settings.
- Screenshot or UI snapshot of configured `Verified` and `Synced` Settings.
- Notes for account creation, verification, profile save, chart upload, restore-after-reinstall, offline retry, and delete propagation.
