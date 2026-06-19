# Supabase Remote Simulator QA - 2026-06-10

Status: completed on `codex/user-authentication-db`.

Simulator:

- Device: iPad Pro 13-inch (M5), iOS Simulator.
- Bundle ID: `com.ichart.app`.
- Supabase project ref: `pausvvwoazbvmzyrebwl`.
- Remote URL: `https://pausvvwoazbvmzyrebwl.supabase.co`.
- Account: existing verified QA session. New-account email verification was not re-run in this pass.

## Automated Gate

- `scripts/run_supabase_production_readiness.sh` focused mode passed with 45 selected tests, 1 expected live-integration skip, and 0 failures.
- Full SwiftPM passed with 517 tests, 37 skipped, and 0 failures.
- `ICHART_RUN_LOCAL_SUPABASE_QA=1 scripts/run_supabase_production_readiness.sh` passed:
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
- Backed up local `library-state.json` to `/tmp/ichart-library-state-before-remote-restore-20260610104236.json`.
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
- Library moved through the active Basic chart counter during the disposable chart create flow.
- Deleted the top newly-created disposable chart through `Chart actions > Delete`.
- Library returned to the prior Basic chart counter after the disposable delete.
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
- Follow-up fix: the app now has an explicit `passwordRecovery` account state. Valid `ichart://auth-callback` recovery links show a compact new-password panel in Settings and save with Supabase `auth.update(user: UserAttributes(password: ...))`.
- Follow-up hardening: recovery callbacks now accept either `token_hash` or Supabase's default hosted-link `token` value when that token is delivered directly to `ichart://auth-callback`, so simulator QA can bypass Safari consuming the one-time `/verify` URL.
- Hosted project requirement after domain/custom SMTP setup: set the Reset password email template to `ichart://auth-callback?token_hash={{ .TokenHash }}&type=recovery` before production QA. Supabase blocks hosted template edits on the current free/default email-provider path, so this remains parked until SMTP unlocks template customization. This avoids email-provider or browser prefetch of the default `{{ .ConfirmationURL }}` link.
- Verified recovery QA: opened the direct `ichart://auth-callback` recovery link in the iPad simulator, confirmed Settings showed `Set new password`, saved a replacement password, signed out, and signed back in with the replacement password. The app returned to `Verified`, `Signed in.`, and `Synced`, and Supabase auth logs showed `/verify`, `/user`, `/logout`, and `/token` success responses for the flow.

## Notes

- Product direction after this QA: account/auth/profile remain mandatory for Basic and Pro users. Basic includes the complete local chart-writing tool, PDF/export, local autosave, and a 3-chart local cap. Chart cloud backup/sync/restore and Forums become Pro entitlements before production cloud rollout. The signed-in sync path exercised here is interim QA coverage until StoreKit/subscription gating is wired.
- Endpoint/auth-restore connectivity failures are now treated as temporary offline state rather than signed-out state.
- No service-role key, database password, JWT secret, SMTP credential, or Stripe secret was used in the app or committed.
