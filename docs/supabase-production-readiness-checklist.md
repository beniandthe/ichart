# Supabase Production Readiness Checklist

Status: Sprint 5 checklist for iChart account verification, profile sync, and Pro cloud chart backup/sync.

## Non-Secret Project Facts

- Product: iChart / iChart.
- Supabase project ref: `pausvvwoazbvmzyrebwl`.
- Remote URL shape: `https://pausvvwoazbvmzyrebwl.supabase.co`.
- The iOS app embeds only the project URL and publishable client key.
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
- After custom SMTP unlocks hosted template editing, Reset password template uses a direct app recovery link, not the default prefetch-prone hosted verify link:
  ```html
  <a href="ichart://auth-callback?token_hash={{ .TokenHash }}&type=recovery">Reset password in iChart</a>
  ```
- Custom SMTP is configured before relying on branded production emails, custom hosted Auth templates, or high-volume QA.
- No service-role key, database password, JWT secret, or Stripe secret is copied into Xcode settings, `.env.example`, docs, or app code.

## Edge Function Configuration

- App Store Server Notifications are received by `app-store-server-notifications`.
- `supabase/config.toml` sets `verify_jwt = false` for that function because Apple does not send a Supabase user JWT.
- Public webhook access does not imply trust: the function must reject missing or unverified `signedPayload` input.
- StoreKit transaction claims are received by `storekit-subscription-claims`.
- `supabase/config.toml` sets `verify_jwt = true` for the claim function because it is invoked by signed-in app users.
- The claim function must reject missing user bearer auth, missing `signedTransactionInfo`, unverified StoreKit transactions, non-Pro products, and missing original transaction identity.
- The server-only subscription writer reads Edge Function secrets and never runs in the iOS app.
- Nested App Store transaction/renewal payloads must also be verified before any write path is enabled.
- Verified webhook events still need StoreKit product and original transaction identity before they can touch subscription authority.
- Verified webhook events update only existing original-transaction mappings; unmapped notifications are accepted without assigning account ownership.
- Verified transaction claims must resolve the signed-in Supabase user before writing owner mapping.
- Apple JWS verification is wired through Apple's `SignedDataVerifier`; missing or malformed verifier secrets must keep the functions in a fail-closed not-configured state.
- Required verifier secrets are `APP_STORE_BUNDLE_ID`, `APP_STORE_ENVIRONMENT`, `APP_STORE_ROOT_CERTIFICATES_PEM`, and production-only `APP_STORE_APP_APPLE_ID`.
- Server-only Supabase credentials and App Store Connect secrets must be set as Edge Function secrets, never committed and never bundled into the iOS app.
- Local mapping coverage can run without Deno:
  ```sh
  node --test \
    supabase/functions/_shared/app_store_subscription_authority.test.mjs \
    supabase/functions/_shared/app_store_verifier_config.test.mjs \
    supabase/functions/_shared/supabase_subscription_authority_store.test.mjs
  ```

## Product Entitlement Configuration

- Account/auth/profile is mandatory for Basic and Pro users.
- Basic includes the complete local chart-writing tool, PDF/export, local chart save, and a 3-chart local library cap.
- Chart cloud backup/sync/restore is available only with active Pro entitlement.
- Forums are available only with active Pro entitlement.
- Current signed-in chart sync behavior is an interim QA path until StoreKit/subscription entitlement wiring is implemented.
- Before production cloud rollout, `ChartCloudSyncService` and Forums must be blocked when Pro is inactive and Settings must explain that cloud backup requires Pro.
- Expired Pro pauses paid cloud/service features and requires the user to reduce the local library to the 3-chart Basic cap when needed.
- Downgraded Basic accounts over the 3-chart cap must choose which local charts to remove until only 3 remain.
- Downgrade pruning is local-only and must not create cloud deletion tombstones.
- Remote chart backups use a published grace period, recommended default 30 days, before cloud retention cleanup. Charts removed locally during downgrade pruning remain in cloud backup until the grace period ends.

## Automated Local Gate

Run the secret-free production readiness wrapper:

```sh
scripts/run_supabase_production_readiness.sh
```

That wrapper runs whitespace hygiene, ignored-path checks, key-shaped secret scanning, focused Supabase/chart tests, and full SwiftPM unless `ICHART_SKIP_FULL_SWIFTPM=1` is set.

When a local Supabase stack is available, include SQL/RLS and live local integration coverage:

```sh
ICHART_RUN_LOCAL_SUPABASE_QA=1 scripts/run_supabase_production_readiness.sh
```

The local QA path resets the local database, runs `supabase test db`, derives local URL/key values from `supabase status -o env`, and runs `SupabaseIntegrationTests` with a throwaway local Auth account.

## Manual Simulator Gate

Use the iPad simulator because the runtime app target owns the Settings/account/sync UI.

1. Launch without Supabase env.
2. Confirm Settings shows account services unavailable and cloud backup unavailable.
3. Confirm charts can still be created, edited, deleted, relaunched, and kept on the device.
4. Relaunch the same installed build with runtime `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, not only xcodebuild build-setting values. With XcodeBuildMCP, use `launch_app_sim` env after `build_run_sim`.
5. Create a new account with email/password.
6. Open the verification email. If the browser ends on a blank deep-link page, return to the app and sign in with the same email/password.
7. Confirm Settings shows `Verified`.
8. Request a password reset from the signed-out Account panel.
9. Open the reset email's direct app recovery link in the simulator/app. Temporary hosted-link fallback: if the email still contains Supabase's default hosted `/verify?token=...` link while the dashboard template is being updated, extract the `token` value and open `ichart://auth-callback?token=<token>&type=recovery` in the simulator instead of letting Safari consume the hosted link.
10. Confirm Settings shows `Set new password`, enter a new password, save, sign out, and sign back in with the new password.
11. Save email, phone, and address profile fields. Confirm Settings does not expose user-editable payment fields.
12. With Basic entitlement, confirm PDF/export remains available, Cloud Backup explains that cloud backup requires Pro, Forums are locked, and creating a 4th chart is blocked.
13. With active Pro entitlement, tap `Back Up Now` and confirm Cloud Backup returns to `Cloud backup active`.
14. With active Pro entitlement, create a Simple Chord Sheet, edit at least one chord, and wait for Cloud Backup to return to `Cloud backup active`.
15. With active Pro entitlement, create a Rhythm Section chart, add visible chart content, and wait for Cloud Backup to return to `Cloud backup active`.
16. Delete one disposable QA chart and confirm it does not return after relaunch.
17. Sign out, relaunch, sign back in, and confirm the expected charts restore.
18. Simulate downgrade/expired Pro with more than 3 local charts and confirm the app requires user-selected local pruning down to 3 charts.
19. Confirm downgrade-pruned local charts do not create remote deletion tombstones and remain restorable from cloud snapshots until the grace period ends.

## Restore/Reinstall Gate

Use only disposable QA charts for this pass.

This gate requires active Pro entitlement because chart cloud backup/sync/restore is a paid cloud service.

1. Record the visible chart IDs or titles and the remote document count.
2. Stop the app.
3. Remove local app data or reinstall the simulator app.
4. Relaunch with Supabase env and sign in.
5. Confirm remote active charts restore locally.
6. Confirm remote tombstones remain deleted and do not resurrect older local copies.
7. Confirm Settings reports `Cloud backup active`.

## Offline/Failure Gate

This gate verifies local-first resilience for both Basic and Pro. Cloud retry/sync assertions require active Pro entitlement.

1. Sign in and reach a known `Cloud backup active` state.
2. Disable network or launch against a deliberately unreachable Supabase URL.
3. Make a local chart edit.
4. Confirm local editing and local save continue.
5. Confirm Cloud Backup reports an offline/failed state with a retry action, not raw backend errors.
6. Restore network or the correct Supabase URL.
7. Tap `Try Again` or `Back Up Now`.
8. Confirm Cloud Backup returns to `Cloud backup active`.

## Data And RLS Gate

- Anonymous reads/writes to owner-scoped tables are denied.
- A signed-in user can read and write only their own `profiles`, `chart_documents`, `chart_snapshots`, and `devices` rows.
- The app can read but not write subscription rows.
- Subscription rows include server-owned provider, StoreKit product, original transaction, App Store status, expiration, grace, revocation, and last-verification metadata.
- `chart_documents.latest_snapshot_id` cannot point to another user's snapshot or a missing snapshot.
- Chart deletes create tombstones instead of hard-deleting the sync marker.
- `profiles.stripe_customer_id`, raw card numbers, CVC values, and payment tokens are not app-writable profile fields.
- App Store webhook events cannot update `subscriptions` unless the server first verifies Apple signed data and maps the transaction to the trusted owner/subscription record.
- StoreKit transaction-claim events cannot update `subscriptions` unless the server first verifies the Apple signed transaction and resolves the authenticated account owner.

## Evidence To Keep With The Release Candidate

- Commit hash.
- Supabase project ref.
- `scripts/run_supabase_production_readiness.sh` result.
- Local Supabase QA result, when run.
- App Store Server Notification function test result.
- iPad simulator build/run result.
- Screenshot or UI snapshot of unconfigured Settings.
- Screenshot or UI snapshot of configured `Verified` and `Cloud backup active` Settings.
- Notes for account creation, verification, profile save, chart upload, restore-after-reinstall, offline retry, and delete propagation.
