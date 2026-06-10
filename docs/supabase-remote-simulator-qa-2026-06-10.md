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

Fresh-account cloud gate:

- Created a new disposable plus-address QA account through the app.
- Verification email delivery recovered after recreating the hosted Supabase Auth user, and the verification link completed account verification.
- Signed in from the simulator and confirmed Settings showed `Verified`.
- Initial sync for the fresh account hit `Cloud permissions blocked backup` because the simulator still had a local library snapshot from a different authenticated owner. This confirmed RLS was blocking cross-user chart ownership as intended, but exposed an account-switch UX edge.
- Backed up and removed the stale local `library-state.json`, then relaunched with the same verified fresh account.
- Settings showed `Verified`, `0 charts`, and `Synced 2:11 PM`.
- Saved profile fields for email, phone, address, and a text-only payment/customer reference. The app showed `Profile saved.`
- Created a Simple Chord Sheet and a Rhythm Section Sheet through the real `New Chart` flows.
- Settings showed `2 charts` and `Synced 2:13 PM`.
- Relaunched against an intentionally bad endpoint, confirmed the account state showed `Temporarily offline`, Chart Sync showed `Offline`, and local chart creation still worked.
- Relaunched against the correct remote endpoint and confirmed the offline-created chart uploaded; Settings showed `3 charts` and `Synced 2:14 PM`.
- Signed out, relaunched, signed back in, and confirmed the same `3 charts` returned.
- Backed up and removed local chart state, relaunched, and confirmed all `3 charts` restored from cloud.
- Deleted one disposable chart, confirmed Settings showed `2 charts`, backed up and removed local state again, relaunched, and confirmed the deleted chart did not resurrect.
- Follow-up fix: local chart snapshots now stamp the authenticated Supabase owner after sync. If a different owner signs in later, owner-scoped local sync starts from that user's remote state instead of trying to upload another user's chart IDs. Legacy ownerless cloud snapshots that hit RLS during upload fall back to the signed-in user's remote library.

Password reset recovery:

- Requested password reset from the signed-out Account panel. The app showed `Password reset email sent.`
- Clicking the hosted reset link from the desktop browser opened a blank page and did not produce a visible simulator callback.
- Follow-up fix: the app now has an explicit `passwordRecovery` account state. Valid `ichart://auth-callback` recovery links show a compact new-password panel in Settings and save with Supabase `auth.update(user: UserAttributes(password: ...))`.
- Remaining manual QA: open the reset link inside the simulator/app deep-link path, confirm the new-password panel appears, save a new password, sign out, and sign back in with the new password.

## Notes

- Endpoint/auth-restore connectivity failures are now treated as temporary offline state rather than signed-out state.
- Opening a custom-scheme callback from the desktop browser can appear as a blank page if it is not routed into the iOS simulator. This is a simulator-link routing issue, not proof that the app handled the callback.
- No service-role key, database password, JWT secret, SMTP credential, or Stripe secret was used in the app or committed.
