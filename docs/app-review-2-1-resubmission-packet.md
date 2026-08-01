# iChart App Review 2.1(b) Resubmission Packet

Status: Submitted repair packet for the 2026-07-31 rejection
Build rejected: `1.0 (35)`
Target repair build: `1.0 (36)`
Submission ID: `06b203db-9cdf-401b-bf58-78066c20ad0b`
Current submitted state: build `1.0 (36)`, app version, subscription group,
monthly subscription, and annual subscription are `Waiting for Review`

## Rejection Summary

Apple rejected build `1.0 (35)` on 2026-07-31 under Guideline `2.1(b)
Performance: App Completeness`.

Apple's message says the In-App Purchase products exhibited a bug. The attached
reviewer screenshot shows the Settings subscription area and StoreKit's sandbox
alert:

`Your account is temporarily unavailable. Try again later. [Environment: Sandbox]`

The `iChart Pro` subscription group, `iChart Pro Monthly`, and `iChart Pro
Annual` were returned because the associated app version was rejected.

## Verified External State

- App Store Connect submission: build `1.0 (36)` is attached to app version
  `1.0` with the subscription group, monthly product, and annual product in
  the same review submission.
- Paid Apps Agreement: active.
- Bank account: active.
- U.S. Form W-9: active.
- Subscription group: `iChart Pro`, ID `22169564`, rejected only because the app
  version was rejected.
- Monthly product ID: `com.ichart.app.pro.monthly`.
- Annual product ID: `com.ichart.app.pro.annual`.
- Monthly and annual availability: all countries or regions selected.
- Monthly and annual localizations: English (U.S.) present.
- Monthly and annual review screenshots: present.
- Public support URL: `https://useichart.com/support.html`.
- Public privacy URL: `https://useichart.com/privacy.html`.
- Public terms URL: `https://useichart.com/terms.html`.

## App-Side Repair

The reviewer screenshot shows `Pro Expired` before the purchase attempt. That
can happen when local StoreKit history contains stale expired sandbox
transactions even though the signed-in iChart review account has no server-owned
subscription authority row.

The build `1.0 (36)` repair keeps production signed-in accounts server-backed:

- Local StoreKit history may still provide an active signed transaction for a
  server claim.
- A signed-in account only shows active or expired Pro when Supabase subscription
  authority returns a row for that account.
- If Supabase has no subscription row for the signed-in account, the account
  displays Basic rather than inheriting stale local sandbox transaction history.
- If a local active transaction cannot be verified by the server, the app stays
  unavailable/locked rather than granting local-only Pro in Release.

## Resubmission Notes To Paste

iChart is a chart-writing app for musicians.

Test account:

- Username/email: `appreview-v1-20260731@useichart.com`
- Password: provided only in App Store Connect App Review Information.

Subscription products:

- Monthly: `com.ichart.app.pro.monthly`
- Annual: `com.ichart.app.pro.annual`

Suggested review path:

1. Sign in with the provided test account.
2. Open Settings and confirm the account is signed in.
3. Open Settings > Pro Subscription.
4. Tap iChart Pro Monthly or iChart Pro Annual to start StoreKit sandbox
   purchase.
5. Complete Apple sandbox purchase if prompted.
6. If StoreKit returns a temporary sandbox account availability alert before
   purchase confirmation, no transaction has reached iChart yet; please retry
   the sandbox purchase or use Restore Purchases after the sandbox account is
   available.
7. Confirm Pro unlocks unlimited charts, Projects, cloud backup, and Forums.
8. Account deletion is available from Settings > Account > Delete Account.

Additional notes:

- Paid Apps Agreement, bank account, and U.S. tax form are active.
- The subscription group and both products are submitted with this app version.
- iChart uses StoreKit and sends signed transactions to a Supabase Edge Function
  for server-side verification.
- Account deletion removes iChart server account data and signs the app out.
  App Store subscriptions and billing remain managed by Apple.
- Public links:
  - Support: `https://useichart.com/support.html`
  - Privacy: `https://useichart.com/privacy.html`
  - Terms: `https://useichart.com/terms.html`

## Final Gate Evidence

- [x] PR with the server-backed entitlement repair is merged to `main`.
- [x] Build `1.0 (36)` is archived from `main`.
- [x] Build `1.0 (36)` is uploaded and processed.
- [x] The fresh review account shows Basic before purchase/restore.
- [ ] Purchase or restore is tested on physical device/TestFlight when possible.
- [x] App version, subscription group, monthly, and annual products are included
  in the same resubmission.
- [x] App Review notes include the resubmission notes above.
- [x] Manual release remains selected.
