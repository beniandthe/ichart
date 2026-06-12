# iChart StoreKit Subscription Runbook

Status: local StoreKit QA baseline
Created: 2026-06-12

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
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications)

## App Flow

StoreKit is an entitlement source, not a scattered feature gate.

The flow is:

```text
StoreKit transaction/current entitlement
-> IChartStoreKitSubscriptionStore
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
- Add server-side receipt/subscription verification or App Store Server Notification handling before trusting Supabase subscription rows as production authority.
- Have the server write the subscription authority metadata in `subscriptions`; the iOS app remains select-only.
- Keep service-role keys, webhook secrets, App Store Connect API keys, and signing keys out of the iOS app and out of git.
