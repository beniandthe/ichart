# iChart StoreKit Subscription Runbook

Status: local StoreKit QA baseline
Created: 2026-06-12

## Product IDs

The first Pro subscription products are:

- `com.smartchart.app.pro.monthly`
- `com.smartchart.app.pro.annual`

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

Local prices in the `.storekit` file are placeholders for simulator testing only. Final launch pricing lives in App Store Connect and should be documented separately before release.

Xcode's normal Run action reads the scheme StoreKit configuration and should exercise real local StoreKit purchase dialogs. Command-line/MCP simulator launches build and launch the app outside that Run action, so the Debug simulator app also bundles the `.storekit` file, reads it for product button metadata, and treats fallback button taps as a local Pro entitlement preview. That fallback is compile-gated to Debug simulator builds and is not a production entitlement source.

Do not initialize `StoreKitTest.SKTestSession` inside the app process. It expects an XCTest configuration and aborts the app when launched normally.

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
- Decide final monthly and annual pricing.
- Replace or sync the local StoreKit configuration if App Store Connect product metadata becomes the source.
- Add server-side receipt/subscription verification or App Store Server Notification handling before trusting Supabase subscription rows as production authority.
- Keep service-role keys, webhook secrets, App Store Connect API keys, and signing keys out of the iOS app and out of git.
