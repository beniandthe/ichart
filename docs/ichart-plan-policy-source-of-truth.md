# iChart Plan Policy Source Of Truth

Status: Active product policy for v1 implementation
Last updated: 2026-06-12

This document is the hard source of truth for iChart account, Basic, Pro, cloud sync, Forums, downgrade, and subscription policy. If another planning document conflicts with this file, this file wins for plan and entitlement behavior.

## 1. Product Principle

iChart should feel like a complete, trustworthy chart-writing app before a user pays.

The paid plan should not unlock the basic ability to write, edit, save, or export charts. Pro exists because some features create ongoing service cost, security responsibility, storage cost, moderation cost, support burden, or multi-device value.

## 2. Account Policy

- Account creation/sign-in is mandatory for production Basic and Pro users.
- In-app account creation requires first name, last name, email, and password before entering the chart library.
- Name and email are locked account identity fields after signup so forum attribution, support identity, recovery, and subscription ownership stay stable.
- Users cannot edit account identity from Settings. Identity changes are customer-support operations.
- Phone setup and verification are legacy/post-v1. Existing phone values remain support-controlled data, but new users are not asked to set up or verify a phone number in V1.
- Existing payment or customer-reference metadata is backend/support controlled and must not be writable from the app.
- First launch shows account signup before the iChart launch animation; after verified automatic sign-in, the onboarding gate shows `Verified`, the user taps `Continue`, and the canonical iChart launch animation opens into the app.
- Signing out returns immediately to the account creation/sign-in gate.
- Account/auth is not the paywall.
- Email verification, password recovery, profile, subscription identity, and support identity are part of the base trust layer.
- Production auth starts with email/password plus email verification.
- Magic links, Apple Sign-In, social login, and other auth methods are post-v1 unless explicitly reprioritized.
- Domain/custom SMTP setup is still parked. Until that is complete, hosted Auth email-template changes remain a dashboard follow-up rather than an app-code dependency.

## 3. Plan Structure

### Basic

Basic is the default mandatory-account tier.

Basic includes:

- complete local chart-writing tool access
- all essential Simple Chord Sheet and Rhythm Section authoring tools
- local autosave
- local library access
- PDF export and sharing
- local PDF Library for app-generated exports
- account/profile/password recovery
- 3 local charts

Basic excludes:

- Projects for grouping multiple charts under one song
- cloud chart backup
- chart restore after reinstall from cloud
- cross-device chart sync
- Forums
- future service-heavy features such as version history, shared libraries, setlists, cloud organization, or AI-assisted cleanup

### Pro

Pro is an auto-renewing subscription surface, offered as monthly and annual plans.

Pro includes:

- Projects for keeping every chart for the same song together
- Project chart variants for Concert, Bb Horn, Eb Horn, F Horn, and other interval-based instrument views as added
- unlimited local chart creation
- cloud chart backup
- chart restore after reinstall or new iPad sign-in
- future cross-device chart sync
- Forums access
- future cloud-backed organization
- future service-heavy features if built

No one-time Pro purchase is planned for launch. A one-time purchase can be reconsidered later only for permanent local features with no ongoing service cost.

## 4. Paywall Policy

Do not gate core local authoring behind Pro.

Core local authoring includes:

- creating charts within the current plan limit
- editing existing charts
- local autosave
- chord writing and correction
- rhythm chart authoring
- measure/repeat/page tools required for normal chart work
- typography and appearance controls required for readable charts
- PDF export and sharing
- local PDF Library access for exports and forum downloads

Pro gates ongoing-service and community surfaces:

- unlimited chart capacity
- Projects
- Project-level instrument variants
- cloud backup/sync/restore
- Forums
- future service-backed features

## 5. Chart Limit Policy

- Basic users can create up to 3 local charts.
- Pro users can create unlimited local charts.
- The chart cap applies to active local chart documents in the local library.
- Creating and duplicating charts must respect the cap.
- After the Basic library is at or below the cap, editing, opening, renaming, deleting, and exporting those local charts must not be blocked by the cap.
- If an inactive Pro account is over the Basic cap, chart opening/editing stays locked until the user removes local charts back to the cap or restores Pro.

## 6. Downgrade And Expiration Policy

When Pro expires, is canceled, or cannot be verified:

- users must resolve the local Basic cap if the library has more than 3 charts
- Forums lock
- cloud backup/sync/restore pauses
- Settings should clearly explain that cloud backup and Forums require Pro, and that the local library must be reduced to 3 charts for Basic

If a downgraded Basic account has more than 3 local charts:

- the app must prompt the user to choose which local charts to keep or remove until only 3 local charts remain
- charts removed during this downgrade flow are deleted from the local library
- downgrade pruning is local-only and must not create cloud deletion tombstones
- downgrade pruning must not delete remote chart documents or snapshots while the cloud grace period is active
- chart opening/editing is locked while the downgraded local library is above the Basic cap
- local chart editing/export continues for the remaining 3 Basic charts
- new chart creation and duplication stay blocked until the local library is reduced to 3 charts or Pro is restored

This policy gives Pro clear value while preserving recoverability through the cloud grace window.

## 7. Cloud Backup Retention Policy

Pro expiration should hard-stop cloud service access, not local user work.

Recommended v1 retention behavior:

- Cloud backup/sync pauses immediately when Pro is inactive.
- The app reminds users before cancellation/expiration, where possible, to export critical charts.
- Remote chart backups receive a clear grace period after Pro expiration.
- Recommended default grace period: 30 days.
- After the grace period, remote backups may be deleted or archived according to the published retention policy.
- Charts removed locally during downgrade pruning remain in cloud backup until the grace period ends.
- If Pro is restored before the grace period ends, cloud-backed charts can be restored from the remote snapshots.
- Local device charts are not affected by remote backup retention cleanup beyond the user's explicit downgrade-pruning choices.

The app must explain this plainly in Settings or the subscription management surface before production launch.

## 8. Cloud Sync Policy

The editor remains local-first.

- `FileChartRepository` remains the runtime source of truth for local editing.
- Cloud sync must never block launch, chart editing, local save, or export.
- `ChartCloudSyncService` is gated behind active Pro entitlement before production cloud rollout.
- Supabase RLS must also require active Pro for `chart_documents` and `chart_snapshots`, so Cloud Backup is server-enforced and not only hidden by client UI.
- Sync uses whole-chart snapshots and last-writer-wins current state for this phase.
- Operation-level collaboration and merge logic are out of scope.
- Delete propagation uses tombstones so older devices do not resurrect deleted charts.

Chart sync states should communicate the user's real situation:

- unconfigured build
- signed out
- Basic cloud backup requires Pro
- offline
- syncing
- synced at time
- failed with retry

## 9. Forums Policy

- Forums are Pro-only.
- Forums may remain visible in the sidebar for Basic users, but the content should be locked with clear upgrade copy.
- Forums should not block access to Charts, Help, or Settings.
- Forums access should be controlled by the same active Pro entitlement boundary as cloud services.
- Forums are a community chart library, not an anonymous social feed.
- Forum publishing submits a fixed PDF snapshot with creator credit and source metadata; editable chart JSON, source ink, and local authoring state are not shared in V1.
- Forum publishing only accepts charts created or stored inside the local iChart library. Users cannot upload arbitrary PDFs or files from device storage to Forums.
- Forum downloads save into the local in-app PDF Library as non-editable PDFs before preview/share actions.
- Every post, comment, vote, report, and badge must be tied to a verified account identity. Forum creator credit uses the account's locked first name plus last initial, never an email fallback or editable alias.
- Forum chart posts require song title, artist, arranger credit, account-owned creator credit, layout style, and optional tags/version notes.
- New forum chart posts start as `pending` and must pass an authenticity review before they appear in the public community library.
- Community quality uses votes, report thresholds, ranking scores, and moderation states such as `pending`, `published`, `flagged`, `hidden`, and `removed`.
- Users may vote, comment, report, download PDFs, and submit chart posts when active Pro is verified; public visibility is server/moderation-owned, and users cannot self-award badges or directly mutate moderation status, aggregate counters, subscription state, or another user's content.
- Forum charts should remain chords/rhythm-chart focused in V1 and avoid lyrics/melody-sharing features.

## 10. Subscription And Payment Policy

- Pro should launch as monthly and annual auto-renewing subscriptions.
- Current target launch pricing is $7.99 monthly and $64.99 annual.
- Annual should be positioned as the best value at roughly 32% savings against twelve monthly payments.
- No raw card data is collected or stored by iChart.
- Settings should not expose user-editable payment fields.
- Billing UI should route through StoreKit/provider-managed purchase and restore flows; any customer references remain backend metadata only and are not client-writable profile fields.
- StoreKit owns Apple subscription purchase/restore.
- First App Store product IDs are `com.ichart.app.pro.monthly` and `com.ichart.app.pro.annual`.
- StoreKit purchase/restore state feeds `IChartSubscriptionEntitlement`; the rest of the app must continue reading capability from `AppEntitlements` rather than from StoreKit UI directly.
- Local simulator purchase QA uses `StoreKit/iChartProSubscriptions.storekit` through the generated `iChart` scheme. Command-line/MCP simulator launches use a Debug simulator-only fallback that reads the bundled StoreKit file for product button metadata and treats fallback button taps as a local Pro entitlement preview. Prices in that file should mirror the current target launch pricing until App Store Connect becomes the production pricing authority.
- Supabase subscription rows are read-only from the app and are updated only by trusted server-side purchase verification, StoreKit transaction claims, and App Store Server Notification handling.
- Future service-role updates, Stripe webhooks, or StoreKit server notification handlers must run server-side only.
- App Store Server Notification handling is a Supabase Edge Function that uses Apple's signed-data verifier and an Edge-only Supabase writer when secrets are configured, rejects oversized or missing/invalid `signedPayload` input, records notification UUIDs for idempotency, rejects stale signed-date replay, and updates only previously claimed StoreKit original-transaction mappings.
- StoreKit transaction claiming is the authenticated path that maps an Apple original transaction to an iChart account after Apple signed-transaction verification succeeds, the signed transaction includes the expected `appAccountToken`, and stale/cross-owner replay checks pass.
- Service-role keys, Stripe secrets, SMTP credentials, database passwords, and JWT secrets must never be bundled into the app or committed.

## 11. Security And Database Policy

- Owner-scoped data must be protected by RLS.
- The iOS app embeds only the Supabase project URL and publishable client key; service-role and secret keys stay server-side only.
- The app must never authorize privileged behavior from user-editable metadata.
- Subscription or entitlement authority should come from trusted purchase/subscription state, not client-editable profile fields.
- `profiles`, `chart_documents`, `chart_snapshots`, `subscriptions`, and `devices` must keep RLS coverage.
- `subscriptions` remains client read-only.
- App auth callbacks must have a local pending flow with the expected callback type and nonce; unsolicited, expired, or incompatible callbacks are rejected before Supabase session handling.
- Forum creator attribution must be derived server-side from locked profile names, and published forum PDFs must be tied to validated post-owned storage paths.
- Account deletion must be user-initiated and handled separately from Pro expiration.

## 12. Implementation Policy

Before production cloud rollout:

- Rename user-facing `Free` wording to `Basic`.
- Keep legacy enum names only where needed for backward compatibility.
- Set Basic local chart cap to 3.
- Treat subscription authority as a first-class state separate from legacy plan names: Basic, active Pro, grace, expired, and unavailable.
- Map only active Pro to cloud-service entitlement. Grace, expired, and unavailable states use Basic local limits while preserving cloud-retention messaging.
- Wire StoreKit as an entitlement source, not a feature gate scattered through UI surfaces.
- Keep PDF/export available in Basic.
- Keep local authoring tools available in Basic.
- Add a cloud-sync state for inactive Pro, such as `requiresPro`.
- Gate `ChartCloudSyncStore` / `ChartCloudSyncService` by active Pro.
- Gate Forums by active Pro.
- Add an explicit downgrade-pruning flow for users over the 3-chart Basic cap.
- Lock chart opening/editing while the local library remains above the Basic cap.
- Keep downgrade pruning separate from normal chart delete so it does not enqueue remote tombstones.
- Add tests for Basic cap, Pro unlimited charts, Basic export availability, Pro sync access, Basic sync lock, Forums lock, downgrade-pruning behavior, and cloud grace preservation.

## 13. QA Acceptance Policy

Minimum acceptance before calling the plan implementation ready:

- Basic account can create exactly 3 local charts.
- Basic account cannot create a 4th chart.
- Basic account can edit, rename, delete, and export its charts.
- Basic account can use all essential local chart tools.
- Basic account sees cloud backup/sync as Pro-required.
- Basic account sees Forums as Pro-required.
- Pro account can create more than 3 charts.
- Pro account can sync/backup/restore charts.
- Pro account can access Forums.
- Expired/downgraded Pro with more than 3 local charts is prompted to choose local charts to remove until 3 remain.
- Expired/downgraded Pro with more than 3 local charts cannot open charts for editing until local pruning is complete or Pro is restored.
- Downgrade-pruned charts are removed locally but remain in cloud backup until the grace period ends.
- Downgrade pruning does not create remote tombstones.
- The remaining 3 local Basic charts can open/edit/export.
- Remote backup grace-period messaging is visible before cloud retention cleanup ships.

## 14. Parked Follow-Ups

These are intentionally not blockers for the immediate entitlement pass:

- domain setup
- custom SMTP setup
- hosted Auth email-template customization
- final monthly/annual price points
- StoreKit production products
- App Store subscription metadata
- Apple verifier Edge Function secrets and subscription webhook writer deployment
- real Forums backend implementation
- final remote backup retention automation

## 15. Short Rule

Basic is the real local app with 3 charts.

Pro is unlimited capacity plus cloud, restore, sync, Forums, and future services.

Downgrade removes user-selected local overflow charts, but cloud backups remain recoverable until the grace period ends.
