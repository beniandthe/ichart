# iChart Plan Policy Source Of Truth

Status: Approved paid-launch policy for FIX-036 implementation
Last updated: 2026-11-20

This document is the hard source of truth for iChart account, Basic, Pro, cloud sync, Forums, downgrade, and subscription policy. If another planning document conflicts with this file, this file wins for plan and entitlement behavior.

The current release operates under the free beta policy. `IChartProductAccessPolicy.current`
is `.freeAllFeatures`, with all shipped features available without a purchase,
trial, expiry, or automatic conversion to a paid subscription. Users can choose
Beta Basic and rejoin free Pro without changing their Apple billing history.
Account authentication, ownership, and moderation checks continue to apply.
The paid-launch rules below are the approved implementation target. Enabling
paid access gates, hosted service policy, and an App Store release remain
separate rollout steps.

## 1. Product Principle

iChart should feel like a complete, trustworthy chart-writing app before a user pays.

Basic includes local writing, editing, saving, and exporting in both chart styles. Pro adds unlimited creation, PDF conversion, song Projects, expressive font choices, community participation, and service-backed features.

## 2. Account Policy

- Account creation/sign-in is mandatory for production Basic and Pro users.
- In-app account creation requires first name, last name, email, and password before entering the chart library.
- Name and email are locked account identity fields after signup so forum attribution, support identity, recovery, and subscription ownership stay stable.
- Users cannot edit completed account identity from Settings. Identity changes are customer-support operations.
- Legacy QA accounts missing first or last name may complete the blank fields once from Settings > Account, then those fields lock under the same account-identity policy.
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

Basic includes

- complete local chart-writing tool access
- all essential Simple Chord Sheet and Rhythm Section authoring tools
- local autosave
- local library access
- PDF export and sharing
- importing, reading, and sharing original PDFs in the local PDF Library
- unlimited local PDF setlists and offline access to saved PDFs
- individual instrument views and transposition
- standard fonts and readability controls in both chart styles
- signed-in Forum browsing, search, chart details, discussion reading, contributor badges, reporting, and blocking
- account/profile/password recovery
- creation of up to 3 active local chart documents
- opening, editing, renaming, deleting, and exporting all saved charts, including converted charts and charts above the creation cap after downgrade

At paid rollout, new Basic chart PDFs include a small **Made with iChart** credit
on the first page. PDF exports remain unlimited. A PDF already in the library
keeps the file originally saved there, including across plan changes.

### Pro

Pro is an auto-renewing subscription surface, offered as monthly and annual plans.

Pro includes

- Projects for keeping every chart for the same song together
- Project chart variants for Concert, Bb Horn, Eb Horn, F Horn, and other interval-based instrument views as added
- unlimited local chart creation
- PDF-to-editable-chart conversion, including the current on-device converter
- the Petaluma, MuseJazz, and Finale Jazz font choices in both chart styles
- cloud chart backup
- chart restore after reinstall or new iPad sign-in
- cross-device chart sync when available
- backup, restore, and cross-device sync for PDF setlists and their PDFs
- new full Forum PDF downloads, chart submission, voting, and commenting
- future cloud-backed organization
- future service-heavy features if built

Basic retains individual instrument views. Saving another chart from a view is
new chart creation and uses a Basic chart slot. Project creation, membership
organization, and duplication inside a Project require Pro. After downgrade,
existing Projects remain visible as read-only groups. Each member chart stays
openable, editable, and exportable from its Project and the Charts library.

Basic includes Finale Broadway, the new-chart default, and standard engraved
choices. Petaluma, MuseJazz, and Finale Jazz are the approved initial Pro font
collection. More fonts may join that collection later. A chart's already applied
font survives downgrade and remains available for that chart's editing and PDF
export. Selecting a new Pro font requires Pro.

Original PDFs and local PDF setlists do not consume chart slots. Converting a
PDF creates a new editable chart and requires Pro. Existing converted charts
remain editable and exportable after downgrade. If cloud-assisted conversion
ships, its Pro page allowance must be based on observed processing costs.

After downgrade, downloaded PDFs remain readable and playable, and local
setlists remain editable and playable. Their backup, restore, and cross-device
sync pause. Live band sharing is a later Pro feature.

No one-time Pro purchase is planned for launch. A one-time purchase can be reconsidered later only for permanent local features with no ongoing service cost.

## 4. Paywall Policy

Do not gate core local authoring behind Pro.

Core local authoring includes

- creating charts within the current plan limit
- editing existing charts
- local autosave
- chord writing and correction
- rhythm chart authoring
- measure/repeat/page tools required for normal chart work
- typography and appearance controls required for readable charts
- PDF export and sharing
- local PDF Library access for exports and forum downloads
- importing, reading, and sharing original PDFs
- unlimited local PDF setlists and offline use
- continued editing and export of saved converted charts and charts using an applied Pro font

Pro gates

- unlimited chart capacity
- Projects
- Project-level instrument variants
- PDF-to-editable-chart conversion
- selecting a new font from the Pro collection
- cloud backup/sync/restore
- setlist and PDF backup/sync/restore
- new full Forum PDF downloads, chart submission, voting, and commenting
- future service-backed features

## 5. Chart Limit Policy

- Basic users can create a new chart while fewer than 3 active local chart documents are saved.
- Pro users can create unlimited local charts.
- The chart cap applies to active local chart documents in the local library.
- Creating and duplicating charts must respect the cap. Opening, editing, renaming, deleting, saving, and exporting existing local charts stay available at every library size.
- A downgraded account keeps every saved chart. New creation and duplication resume after Pro is restored or the library contains fewer than 3 active chart documents.
- Original PDFs, saved Forum PDFs, and local setlists do not consume editable chart slots.

## 6. Downgrade And Expiration Policy

When Pro expires or cannot be verified

- all saved charts remain openable, editable, and exportable, including converted charts and charts above the Basic cap
- new chart creation and duplication use the Basic creation cap
- existing Projects remain visible as read-only groups, with member charts editable from the group and Charts library
- new Project creation, organization, and Project variant duplication pause
- new PDF conversion and selection of a new Pro font require restored Pro
- applied chart fonts remain intact through editing and export
- Forum browsing, search, details, discussion reading, badges, reporting, and blocking remain available to signed-in Basic users
- new full Forum PDF downloads, chart submission, voting, and commenting require restored Pro
- previously saved Forum PDFs remain available offline in the PDF Library and setlists
- cloud backup/sync/restore pauses
- local PDF setlists remain editable and playable, while setlist and PDF backup/sync/restore pause
- Settings explains the creation cap and which Pro actions are paused while preserving access to saved local work

Canceled-but-paid-through Pro is not a downgrade state. It remains full Pro until Apple reports the paid-through entitlement has ended.

Downgrade preserves the whole local library, downloaded PDFs, setlist references,
and existing deletion records. Chart and PDF deletion remains an explicit user
action through the usual deletion controls.

## 7. Cloud Backup Retention Policy

Pro cancellation should keep paid access through the current paid-through date. Pro expiration should hard-stop cloud service access, not silently delete local user work.

Recommended v1 retention behavior:

- If renewal is canceled but the paid-through period is still active, Pro features remain available.
- The app warns that Pro access ends on the paid-through date when Apple reports renewal is off.
- Cloud backup/sync pauses when Pro is inactive.
- Apple billing grace keeps local chart access available and prevents cloud deletion while payment recovery is still possible.
- Remote chart backups are deleted after the paid-through date or Apple billing grace deadline, whichever applies, unless Pro renews first.
- If Pro renews before that deadline, pending cloud cleanup is cleared.
- Remote retention cleanup preserves all local charts, downloaded PDFs, and setlists. Chart opening, editing, and export remain available above the Basic creation cap.

The app must explain this plainly in Settings or the subscription management surface before production launch.

## 8. Cloud Sync Policy

The editor remains local-first.

- `FileChartRepository` remains the runtime source of truth for local editing.
- Cloud sync must never block launch, chart editing, local save, or export.
- `ChartCloudSyncService` is gated behind active Pro entitlement before production cloud rollout.
- Supabase RLS must also require active Pro for `chart_documents` and `chart_snapshots`, so Cloud Backup is server-enforced and not only hidden by client UI.
- Routine cloud backup is local-to-cloud. Creating, editing, and deleting local
  charts must not implicitly pull older cloud charts back into the local library.
- Automatic background backup only uploads charts with chart-level cloud backup
  intent/provenance. Legacy local charts with no cloud tag stay local-only until
  the user explicitly taps `Back Up Now`; that action enrolls current local
  charts for backup.
- Deleting a chart only creates a cloud-sync tombstone after that chart has a
  confirmed cloud backup record. Never-backed local chart deletes stay local.
- Remote-to-local cloud restore is explicit from Settings through `Restore Charts
  from Cloud`.
- Sync uses whole-chart snapshots and last-writer-wins current state for this phase.
- Operation-level collaboration and merge logic are out of scope.
- Delete propagation uses tombstones so older devices do not resurrect deleted charts.

PDF setlist sync uses a separate owner-private backup. **Back Up Setlists**
enrolls local setlists and their linked PDFs for that account. **Restore
Setlists** merges its backup into the local library. Revisions guard against
concurrent changes. When the same setlist changes on two devices, the user
chooses which versions to keep. A pause on downgrade affects service access.
Local copies stay usable, and the setlist backup remains available to the
same account if paid Pro returns. The existing chart-backup retention policy
applies to chart backups.

Chart sync states should communicate the user's real situation:

- unconfigured build
- signed out
- Basic cloud backup requires Pro
- offline
- syncing
- synced at time
- failed with retry

## 9. Forums Policy

- Signed-in Basic users can browse and search published charts, open chart details, read discussion, and see contributor badges.
- Reporting and blocking remain available wherever people can browse.
- New full PDF downloads, chart submission, voting, and commenting require active paid Pro.
- Previously saved Forum PDFs remain readable and playable offline from the PDF Library and setlists after downgrade. Downgrade preserves their files and setlist references.
- Forum read access and Pro actions have distinct client and server authorization boundaries. Community actions retain account, ownership, and moderation checks.
- Forums should keep Charts, Help, and Settings reachable.
- Forums are a community chart library, not an anonymous social feed.
- Forum publishing submits a fixed PDF snapshot with creator credit and source metadata; editable chart JSON, source ink, and local authoring state are not shared in V1.
- Forum publishing only accepts charts created or stored inside the local iChart library. Users cannot upload arbitrary PDFs or files from device storage to Forums.
- Forum downloads save into the local in-app PDF Library as non-editable PDFs before preview/share actions.
- Every post, comment, vote, report, and badge must be tied to a verified account identity. Forum creator credit uses the account's locked first name plus last initial, never an email fallback or editable alias.
- Forum chart posts require song title, artist, arranger credit, account-owned creator credit, layout style, and optional tags/version notes.
- New forum chart posts start as `pending` and must pass an authenticity review before they appear in the public community library.
- Community quality uses votes, report thresholds, ranking scores, and moderation states such as `pending`, `published`, `flagged`, `hidden`, and `removed`.
- Users may vote, comment, download new full PDFs, and submit chart posts when active Pro is verified. Signed-in Basic users retain reporting and blocking. Public visibility is server/moderation-owned, and users cannot self-award badges or directly mutate moderation status, aggregate counters, subscription state, or another user's content.
- Forum charts should remain chords/rhythm-chart focused in V1 and avoid lyrics/melody-sharing features.

## 10. Subscription And Payment Policy

- Pro should launch as monthly and annual auto-renewing subscriptions.
- Current target launch pricing is $6.99 monthly and $60.00 annual.
- Annual should be positioned as the best value at 28% savings against twelve monthly payments.
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
- Map active Pro to full cloud-service entitlement. Apple billing grace keeps local chart capacity available while cloud backup and Pro Forum actions pause. Basic Forum read access, reporting, and blocking remain available. Expired and unavailable states use the Basic creation cap while preserving saved-content access and retention messaging.
- Wire StoreKit as an entitlement source, not a feature gate scattered through UI surfaces.
- Keep PDF/export available in Basic.
- Keep local authoring tools available in Basic.
- Include both chart styles, individual instrument views, standard fonts, and readability controls in Basic.
- Keep Petaluma, MuseJazz, and Finale Jazz selection in Pro while retaining already applied fonts through downgrade, editing, and export.
- Gate creation of editable charts from PDFs behind Pro. Preserve saved converted charts after downgrade.
- Include original PDF import, reading, and sharing and unlimited local PDF setlists in Basic without using chart slots.
- Gate setlist and PDF backup/sync/restore behind Pro. Preserve downloaded content and local setlist editing after downgrade.
- Gate Project creation, organization, and duplication inside Projects behind Pro. Keep downgraded groups visible and read-only, with every member chart editable and exportable.
- Add a cloud-sync state for inactive Pro, such as `requiresPro`.
- Gate `ChartCloudSyncStore` / `ChartCloudSyncService` by active Pro.
- Allow signed-in Basic Forum reading and safety actions. Gate new full PDF downloads and community participation by active Pro.
- Apply the Basic chart cap only to creation and duplication. Preserve opening, editing, saving, renaming, and exporting at every library size.
- Replace the older mandatory downgrade-pruning, over-cap editing lock, and Forum download cleanup rules wherever implemented.
- Verify upgrade, downgrade, purchase restore, and existing saved-content access for each capability and each chart style.

The December 1, 2026 production targets are $6.99/month and exactly $60.00/year
in the United States. These source targets do not change live Apple prices or
any existing subscription renewal. App Store Connect remains the authority for
localized product prices. The exact activation time and production changes
require release review; keep public free Pro on until that cutover.

Prepare the production-paid artifact separately and hold its distribution until
the cutover is authorized. Its paid compilation condition applies client gates
immediately; the server flag alone does not coordinate that client activation.
Keep the normal free-beta package and its strict verifier unchanged.

Keep Apple Billing Grace Period disabled while the implemented grace policy
pauses cloud and Forum services. Enabling Apple's billing grace requires a
separately verified full-service client and server policy throughout grace.

The current free beta continues until a separately validated paid rollout.
Client gates, service authorization, hosted rollout, billing configuration, and
release activation each require validation before paid operation is enabled.
The app build selects the paid policy with the `ICHART_PAID_SUBSCRIPTION` Swift
compilation condition. The server migration installs its protected paid feature
switch with the default set to the existing beta phase. The paid build and
server switch are release inputs. Setlist cloud backup always requires a
verified current paid entitlement on the server.

## 13. QA Acceptance Policy

Minimum acceptance before calling the plan implementation ready:

- Basic account can create exactly 3 local charts.
- Basic account cannot create a 4th chart.
- Basic account can edit, rename, delete, and export its charts.
- Basic account can use all essential local chart tools.
- Basic account sees cloud backup/sync as Pro-required.
- Basic account can import, read, and share original PDFs without consuming chart slots.
- Basic account can create unlimited local PDF setlists and use saved PDFs offline.
- Basic account can use either chart style, individual instrument views, standard fonts, and readability controls.
- Basic account can browse and search Forums, read details and discussion, see badges, report, and block.
- Basic account needs Pro for a new full Forum PDF download, chart submission, voting, or commenting.
- Basic account needs Pro for new PDF-to-editable conversion, including the on-device converter.
- Basic account needs Pro to select Petaluma, MuseJazz, or Finale Jazz for a chart. Existing applied fonts survive downgrade, editing, and export.
- Pro account can create more than 3 charts.
- Pro account can sync/backup/restore charts.
- Pro account can use new full Forum PDF downloads, chart submission, voting, and commenting.
- Pro account can convert PDFs into editable charts and select the Pro font collection in both styles.
- Pro account can create and organize Projects and duplicate instrument variants within them.
- Pro account can back up, restore, and sync PDF setlists and their PDFs when those services are available.
- Expired/downgraded Pro with more than 3 local charts can open, edit, save, rename, delete, and export every saved chart. New creation and duplication use the Basic creation cap.
- Saved converted charts remain editable and exportable after downgrade.
- Existing Projects remain read-only groups after downgrade, with member charts editable and exportable from both the group and the Charts library.
- Downloaded Forum PDFs remain playable offline from the PDF Library and local setlists after downgrade.
- Local setlists remain editable and playable after downgrade while sync pauses.
- Downgrade preserves local chart/PDF/setlist files and does not enqueue deletion tombstones.
- Remote cloud backups are deleted after the paid-through date or Apple billing grace deadline unless Pro renews first.
- Remote backup grace-period messaging is visible before cloud retention cleanup ships.
- Upgrade, downgrade, purchase restore, and reopening saved content retain the agreed access and content for every capability.
- The current free beta still exposes its shipped features and offers no automatic conversion to paid Pro until paid operation is separately enabled.

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
- cloud-assisted PDF conversion and its measured Pro page allowance
- live band sharing as a later Pro feature

## 15. Short Rule

Basic includes both chart styles, saved-chart editing and export, standard fonts,
individual instrument views, original PDFs, unlimited local PDF setlists, and
signed-in Forum reading. Its three-chart limit applies to new creation.

Pro adds unlimited chart creation, PDF conversion, Project organization and
variants, the expressive font collection, cloud backup/restore/sync, and new
Forum downloads and participation.

Downgrade preserves every saved chart, applied font, downloaded PDF, and local
setlist. Project groups become read-only, member charts stay editable, and Pro
services pause. Remote backup retention follows the paid-through date or Apple
billing grace deadline under the separately validated service policy.
