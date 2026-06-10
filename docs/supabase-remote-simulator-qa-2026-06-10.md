# Supabase Remote Simulator QA - 2026-06-10

Status: completed on `codex/user-authentication-db`.

Simulator:

- Device: iPad Pro 13-inch (M5), iOS Simulator.
- Bundle ID: `com.smartchart.app`.
- Supabase project ref: `pausvvwoazbvmzyrebwl`.
- Remote URL: `https://pausvvwoazbvmzyrebwl.supabase.co`.
- Account: existing verified QA session. New-account email verification was not re-run in this pass.

## Automated Gate

- `scripts/run_supabase_production_readiness.sh` focused mode passed with 45 selected tests, 1 expected live-integration skip, and 0 failures.
- Full SwiftPM passed with 517 tests, 37 skipped, and 0 failures.
- `SMART_CHART_RUN_LOCAL_SUPABASE_QA=1 scripts/run_supabase_production_readiness.sh` passed:
  - local database reset from migrations succeeded.
  - `supabase/tests/rls_smoke.sql` passed with 16 tests.
  - `SupabaseIntegrationTests` passed against local Supabase with 1 test and 0 failures.

## Remote App QA

Unconfigured launch:

- `build_run_sim CODE_SIGNING_ALLOWED=NO` succeeded.
- Settings showed `Account services offline`.
- Chart Sync showed `Cloud backup unavailable`.
- Manual sync action showed `Unavailable`.
- Local library remained usable with 4 charts.

Configured remote launch:

- Relaunched the installed app with remote `SUPABASE_URL` and publishable-key environment.
- Settings showed `Verified`.
- Chart Sync showed `Synced 10:41 AM`, then manual `Sync Now` entered `Syncing` and returned to `Synced`.
- Last Backup showed `Jun 10, 2026 at 10:41 AM`.

Restore from cloud:

- Stopped the app.
- Backed up local `library-state.json` to `/tmp/smart-chart-library-state-before-remote-restore-20260610104236.json`.
- Removed only the local chart library snapshot.
- Relaunched with remote Supabase configuration.
- Library restored to the same 4 remote charts.
- Settings showed `Verified`, `4 charts`, and `Synced 10:42 AM`.

Failure/recovery smoke:

- Relaunched with a deliberately unreachable Supabase URL.
- Local chart library remained available with 4 charts.
- Settings stayed readable and did not expose raw backend errors.
- Initial bug-chase result: because auth restore could not reach the endpoint, the account state showed `Signed out` and Chart Sync showed `Sign in to back up`, not the sync-specific `Offline` state.
- Relaunched with the correct remote URL and the app recovered to `Verified` and `Synced 10:44 AM`.
- Follow-up fix: endpoint/auth-restore connectivity failures now keep the stored session as `Temporarily offline` and allow Chart Sync to report `Offline` instead of implying an intentional sign-out.
- Verified follow-up: bad endpoint showed `Temporarily offline`, `Reconnect`, and Chart Sync `Offline`; correct endpoint recovered to `Verified` and `Synced 2:00 PM`.

Disposable create/delete propagation:

- Created a disposable Simple Chord Sheet through the real `New Chart` flow.
- Library moved from `4 of 5 free charts used` to `5 of 5 free charts used`.
- Deleted the top newly-created disposable chart through `Chart actions > Delete`.
- Library returned to `4 of 5 free charts used`.
- Settings showed `Verified`, `4 charts`, and `Synced 10:45 AM`.

## Notes

- Endpoint/auth-restore connectivity failures are now treated as temporary offline state rather than signed-out state.
- No service-role key, database password, JWT secret, SMTP credential, or Stripe secret was used in the app or committed.
