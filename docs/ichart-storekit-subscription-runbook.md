# iChart StoreKit Subscription Runbook

Status: StoreKit/Supabase authority loop wired; App Store Connect sandbox gate pending
Created: 2026-06-12
Last updated: 2026-06-13

Resume trigger: when the user says "Apple developer account is setup", run `scripts/resume_apple_developer_gate.sh` before continuing sandbox purchase QA.

## Product IDs

The first Pro subscription products are:

- `com.smartchart.app.pro.monthly`: $7.99/month
- `com.smartchart.app.pro.annual`: $64.99/year

These IDs must match:

- `SmartChart/Models/IChartStoreKitProductCatalog.swift`
- `StoreKit/iChartProSubscriptions.storekit`
- App Store Connect subscription products when they are created

## Local StoreKit QA

Local simulator purchase testing uses:

- StoreKit file: `StoreKit/iChartProSubscriptions.storekit`
- XcodeGen hook: `project.yml` > `schemes` > `SmartChart` > `run` > `storeKitConfiguration`
- Debug simulator fallback: command-line/MCP launches read the bundled StoreKit file for product button metadata and use a local Pro entitlement preview when those fallback buttons are tapped
- Debug build setting: `SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG`

Run `xcodegen generate` after changing the StoreKit file or project spec. The generated `SmartChart` scheme should include a `StoreKitConfigurationFileReference` for `StoreKit/iChartProSubscriptions.storekit`.

Local prices in the `.storekit` file should mirror the current target launch pricing until App Store Connect becomes the production pricing authority. At $7.99 monthly and $64.99 annual, the annual plan is roughly 32% less than twelve monthly payments.

Xcode's normal Run action reads the scheme StoreKit configuration and should exercise real local StoreKit purchase dialogs. Command-line/MCP simulator launches build and launch the app outside that Run action, so the Debug simulator app also bundles the `.storekit` file, reads it for product button metadata, and treats fallback button taps as a local Pro entitlement preview. That fallback is compile-gated to Debug simulator builds and is not a production entitlement source.

Do not initialize `StoreKitTest.SKTestSession` inside the app process. It expects an XCTest configuration and aborts the app when launched normally.

## App Store Connect Production Gate

Before App Store/TestFlight subscription QA, configure the Apple-side products:

- Create one subscription group for iChart Pro.
- Create the monthly auto-renewable subscription with product ID `com.smartchart.app.pro.monthly`.
- Create the annual auto-renewable subscription with product ID `com.smartchart.app.pro.annual`.
- Use app bundle ID `com.smartchart.app`.
- Set App Store Server Notifications Version 2 sandbox URL to `https://pausvvwoazbvmzyrebwl.supabase.co/functions/v1/app-store-server-notifications`.
- Add product display names, descriptions, durations, review metadata, screenshots if required by App Review, and localization records.
- Set the monthly starting price to $7.99 and the annual starting price to $64.99 in the United States storefront, then review the App Store Connect comparable prices for other countries and regions.
- Leave both products in a state where StoreKit can fetch them in sandbox/TestFlight before removing the local StoreKit configuration from the run scheme.
- Allow for App Store Connect metadata propagation; Apple notes product metadata changes can take up to 1 hour to appear in the sandbox environment.

Production entitlement authority should not stop at the iOS client:

- Keep `Product.products(for:)`, `Product.purchase()`, `Transaction.currentEntitlements`, `Transaction.updates`, and `AppStore.sync()` as the in-app StoreKit surface.
- Add a server-owned subscription pipeline before trusting Supabase `subscriptions` rows as production authority.
- Use App Store Server Notifications for real-time lifecycle changes such as renewals, failed renewals, refunds, grace/billing retry changes, and churn.
- Use the App Store Server API from a server/Edge Function only; never bundle App Store Connect API keys, signing keys, webhook secrets, or service-role keys in the app.
- Keep `subscriptions` read-only from the app and update provider, StoreKit product, original transaction, App Store status, expiration, grace, revocation, and last-verification metadata only from trusted server-side purchase verification/notification handling.
- Settings and the upgrade sheet expose Manage Subscription through Apple's system subscription management UI.

Primary Apple references:

- [Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/)
- [Manage pricing for auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/)
- [Enter server URLs for App Store Server Notifications](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications)
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications)

## App Store Server Notification Function

The server-side subscription authority path is wired at:

- `supabase/functions/app-store-server-notifications/index.mjs`
- `supabase/functions/storekit-subscription-claims/index.mjs`
- `supabase/functions/_shared/app_store_subscription_authority.mjs`
- `supabase/functions/_shared/app_store_subscription_authority.test.mjs`
- `supabase/functions/_shared/app_store_signed_data_verifier.mjs`
- `supabase/functions/_shared/supabase_subscription_authority_store.mjs`
- `supabase/functions/_shared/supabase_subscription_authority_store.test.mjs`
- `supabase/functions/_shared/app_store_verifier_config.mjs`
- `supabase/functions/_shared/app_store_verifier_config.test.mjs`

`supabase/config.toml` sets `[functions.app-store-server-notifications]` with `verify_jwt = false` because Apple webhook delivery will not include a Supabase user JWT. That makes Apple signed-payload verification mandatory before any database write.

`supabase/config.toml` also sets `[functions.storekit-subscription-claims]` with `verify_jwt = true` because this endpoint is for signed-in iChart users after purchase/restore. The authenticated claim endpoint creates the trusted account-to-original-transaction mapping before later App Store Server Notifications arrive.

Both Edge Function entrypoints create verifier dependencies through Apple's official `@apple/app-store-server-library` `SignedDataVerifier`. The dependency factory reads only Edge Function environment secrets and returns no verifier functions when required Apple configuration is missing or malformed, so both endpoints fail closed with the existing not-configured responses.

Both entrypoints also create the Supabase subscription authority store from Edge-only secrets. The writer uses `SUPABASE_SECRET_KEYS` when available, or the legacy Supabase service-role secret name as a fallback, and never runs inside the iOS app. The iOS app reads `subscriptions`; it does not write them directly.

Required Edge Function verifier secrets:

- `APP_STORE_BUNDLE_ID`: `com.smartchart.app`.
- `APP_STORE_ENVIRONMENT`: `Sandbox` for sandbox/TestFlight verification, `Production` for production App Store traffic.
- `APP_STORE_ROOT_CERTIFICATES_PEM`: Apple Root Certificate PEM blocks from the Apple PKI site, stored as an Edge Function secret.
- `APP_STORE_APP_APPLE_ID`: App Store app identifier. Required for `Production`; omitted for `Sandbox`.

Prepare the public Apple root certificate bundle locally:

```sh
scripts/prepare_apple_root_certificates.sh /tmp/ichart-apple-root-certificates.pem
```

Set secrets from the operator machine or Supabase Dashboard, never in git:

```sh
supabase secrets set APP_STORE_BUNDLE_ID=com.smartchart.app
supabase secrets set APP_STORE_ENVIRONMENT=Sandbox
supabase secrets set APP_STORE_ROOT_CERTIFICATES_PEM="$(cat /tmp/ichart-apple-root-certificates.pem)"
# Production only:
# supabase secrets set APP_STORE_APP_APPLE_ID=<numeric-app-apple-id>
```

Supabase hosted Edge Functions expose `SUPABASE_URL` and `SUPABASE_SECRET_KEYS` by default. The secret key is server-only and must never be copied into the iOS app, docs, `.env.example`, or chat.

Current behavior is intentionally locked:

- non-POST requests are rejected
- missing `signedPayload` is rejected
- unconfigured verifier secrets return a not-configured response
- invalid Apple signatures are rejected before mapping or writing
- nested signed transaction/renewal payloads must be verified before write attempts
- verified notifications missing StoreKit product/original-transaction identity are rejected
- transaction claims require a signed-in account bearer token
- transaction claims require `signedTransactionInfo`
- transaction claims reject non-Pro products and missing original transaction identity
- transaction claims resolve the signed-in Supabase user before writing owner mapping
- transaction claims upsert `subscriptions` by `owner_id` after Apple verification succeeds
- verified notifications update only previously claimed `storekit_original_transaction_id` rows
- unmapped notifications are accepted without assigning ownership
- no subscription row is mutated from unverified input

The shared authority reducer and Supabase writer are testable with Node so the mapping rules can be verified before Deno is installed locally:

```sh
node --test \
  supabase/functions/_shared/app_store_subscription_authority.test.mjs \
  supabase/functions/_shared/app_store_verifier_config.test.mjs \
  supabase/functions/_shared/supabase_subscription_authority_store.test.mjs
```

Before this endpoint becomes production authority:

- configure Apple verifier Edge Function secrets for the target environment
- deploy both functions after secrets are configured and smoke-test missing/invalid signed payload behavior
- map only `com.smartchart.app.pro.monthly` and `com.smartchart.app.pro.annual` to active Pro
- store service-role/admin keys, App Store Connect API keys, webhook secrets, and Apple signing material only as Supabase Edge Function secrets
- deploy with the linked project after verification is complete:
  ```sh
  supabase functions deploy app-store-server-notifications
  supabase functions deploy storekit-subscription-claims
  ```

## App Flow

StoreKit is an entitlement source, not a scattered feature gate.

The flow is:

```text
StoreKit transaction/current entitlement
-> IChartStoreKitSubscriptionStore
-> authenticated StoreKit transaction claim function
-> Supabase subscription owner/original-transaction mapping
-> IChartSubscriptionEntitlement
-> AppEntitlements
-> Library, Projects, cloud sync, Forums, chart-cap behavior
```

Only `proActive` unlocks cloud backup, Projects, Forums, and unlimited local charts. Basic, grace, expired, and unavailable states keep Basic local limits.

## Production Follow-Up

Before production launch:

- Create monthly and annual auto-renewing subscription products in App Store Connect.
- Confirm App Store Connect product IDs match the code and local StoreKit file.
- Configure App Store Connect pricing to the current target: $7.99 monthly and $64.99 annual, unless launch pricing changes before release.
- Replace or sync the local StoreKit configuration if App Store Connect product metadata becomes the source.
- Configure and validate Apple signed-payload verification plus server-only App Store Server Notification handling before trusting Supabase subscription rows as production authority.
- Have the verified server path write the subscription authority metadata in `subscriptions`; the iOS app remains select-only.
- Keep service-role keys, webhook secrets, App Store Connect API keys, and signing keys out of the iOS app and out of git.
