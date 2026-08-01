# iChart Apple App Review Submission Checklist

Status: V1.0 App Review checklist for submitted build `1.0 (36)` repair
Last updated: 2026-07-31

Use this checklist before every App Review submission or resubmission. It is
based on Apple's App Review Guidelines, account-deletion guidance,
auto-renewable subscription guidance, App Review preparation guidance, and App
Store Connect privacy guidance.

Official Apple references:

- App Review Guidelines: `https://developer.apple.com/app-store/review/guidelines/`
- Offering account deletion in your app: `https://developer.apple.com/support/offering-account-deletion-in-your-app/`
- App Review preparation/common issues: `https://developer.apple.com/distribute/app-review/`
- Auto-renewable subscriptions: `https://developer.apple.com/app-store/subscriptions/`
- App privacy in App Store Connect: `https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/`

## Current App Review State

Build `1.0 (32)` was rejected on 2026-07-29 for Guideline `5.1.1 Legal:
Privacy - Data Collection and Storage` because iChart supports account creation
but did not include an in-app account deletion option.

Build `1.0 (35)` was the submitted account-deletion repair build. It includes
the build `1.0 (33)` account-deletion repair, the build `1.0 (34)`
account-entry Scribble scope repair, and the follow-up account-field UI
rollback/narrow ink suppression needed for the physical-device deletion-flow
recording.

App Store Connect submission `06b203db-9cdf-401b-bf58-78066c20ad0b` was
rejected again on 2026-07-31 for Guideline `2.1(b) Performance: App
Completeness`. Apple's attached screenshot shows the Settings subscription
section with the StoreKit sandbox alert: `Your account is temporarily
unavailable. Try again later. [Environment: Sandbox]`. The `iChart Pro`
subscription group, `iChart Pro Monthly`, and `iChart Pro Annual` were returned
because the associated app version was rejected.

The 2026-07-31 dashboard check found the Paid Apps Agreement active, the bank
account active, the U.S. Form W-9 active, the subscription group present, both
subscription products available in all countries or regions, expected product
IDs, English localizations, and review screenshots. The remaining repair is to
submit a new binary that prevents stale local StoreKit history from making a
fresh server-backed review account appear `Pro Expired`, plus clearer review
notes for sandbox purchase/restore.

Required before resubmission:

- [x] Add in-app deletion initiation at Settings > Account > Delete Account.
- [x] Require destructive user confirmation before deletion.
- [x] Delete the authenticated user's iChart server account/data through a
  server-owned path.
- [x] Sign the app out after deletion is accepted.
- [x] Deploy `account-deletion` Edge Function with `verify_jwt = true`.
- [x] Smoke unauthenticated function request returns `401`.
- [x] Update local privacy/support page source to describe in-app deletion.
- [x] Add App Store subscription/billing warning to the in-app account deletion
  copy.
- [x] Add forum contributor blocking so Forums cover App Review Guideline 1.2
  UGC safety expectations alongside reporting and support contact.
- [x] Deploy updated `index.html`, `privacy.html`, and `support.html` to live
  `https://useichart.com` via IONOS on 2026-07-29.
- [x] Verify live `https://useichart.com/privacy.html` includes Settings > Account >
  Delete Account; cache-busted live/local SHA-256 evidence is recorded in
  `docs/ichart-v1-final-release-gate.md`.
- [x] Replace the email verification placeholder source with a branded
  `https://useichart.com/verify.html` browser fallback that never displays token
  values and can pass callback parameters into iChart.
- [x] Deploy and cache-bust verify `https://useichart.com/verify.html` after this
  branch merges.
  - 2026-07-30: live route returned `200`, preserved the `Open iChart`
    handoff, and served the refreshed public-site support/privacy/home links.
- [x] Deploy and cache-bust verify the 2026-07-31 public-site repair before
  resubmission.
  - 2026-07-31: `https://useichart.com/support.html`,
    `https://useichart.com/privacy.html`, `https://useichart.com/verify.html`,
    and `https://useichart.com/terms.html` returned usable pages after the
    accidental physical route folders were removed. App Store Connect metadata
    should use the explicit URLs `support.html`, `privacy.html`, and
    `terms.html` to avoid IONOS directory-routing drift.
- [x] Attach the physical-device screen recording Apple requested in App Review
  Notes.
  - 2026-07-30: attached as `ichart-app-review-deletion-flow.mp4`.
- [x] Upload/attach build `1.0 (35)`.
  - 2026-07-30: App Store Connect build table showed only build `35` attached
    to the app version before resubmission.
- [x] App Privacy answers match V1 data collection.
  - 2026-07-31: removed Phone Number and Physical Address from App Store
    Connect App Privacy; published summary now lists 8 linked data types.
- [x] App Review sign-in account is fresh and clean.
  - 2026-07-31: created `appreview-v1-20260731@useichart.com`, auto-confirmed
    it in Supabase, added the `App Reviewer` profile row, verified zero
    chart/forum rows and only an inactive/free subscription row, and saved the
    generated password in App Store Connect only.
- [x] App Review sign-in account remains stored only in App Store Connect.
- [x] Submit a new repair build after the server-backed StoreKit entitlement
  display patch merges.
- [x] Resubmit app version plus subscription group/monthly/annual items with
  updated review notes.

2026-07-31 post-repair check: App Store Connect submission
`06b203db-9cdf-401b-bf58-78066c20ad0b` shows iOS App `1.0 (36)`, the
`iChart Pro` subscription group, `iChart Pro Monthly`, and `iChart Pro Annual`
all `Waiting for Review`.

## Binary And App Completeness

- [ ] Build number has not been used in App Store Connect.
- [ ] Bundle ID is `com.ichart.app`.
- [ ] Version is `1.0`.
- [ ] Release build launches on a physical iPad.
- [ ] Release build does not expose developer-only diagnostics, fixture
  capture, sample switches, local Pro preview, or debug-only controls.
- [ ] Core flow tested on device: sign in, create chart, edit chord/text/repeats,
  export PDF, close/reopen, restore purchase, Pro gates, forums, cloud restore,
  offline reopen.
- [ ] Backend services needed for review are live: Supabase Auth, database/RLS,
  Edge Functions, StoreKit verification, support site, privacy/support URLs.
- [ ] App Review Notes describe non-obvious features and IAP/subscription
  behavior.

## Account, Privacy, And Data Deletion

- [x] Privacy Policy URL is present in App Store Connect.
- [x] Privacy Policy URL is accessible in-app and on the product page.
- [x] Privacy policy identifies data collected, how it is collected, why it is
  used, data retention/deletion behavior, and support contact.
- [x] App Store privacy questionnaire matches actual V1 data practices.
- [x] No third-party analytics/ads SDKs are present or claimed.
- [x] Account creation collects only directly relevant information.
- [x] App Review has a working demo/review account.
- [ ] Account deletion is easy to find in account settings.
- [ ] Account deletion removes the account record and associated iChart data not
  legally required to retain.
- [ ] If subscription is active, the deletion flow or review notes explain that
  Apple manages subscription billing/cancellation.
- [ ] User-generated public forum content associated with the account is removed
  or hidden as part of account deletion, except legally required retained
  records.

## Subscriptions And IAP

- [x] Paid Apps Agreement is active.
  - 2026-07-31: Business > Agreements showed Paid Apps Agreement active through
    Jun 16, 2027.
- [x] Banking and U.S. tax setup are active.
- [x] Subscription group is submitted with the app version.
- [x] Monthly product ID is `com.ichart.app.pro.monthly`.
- [x] Annual product ID is `com.ichart.app.pro.annual`.
- [x] Product names, duration, description, availability, and screenshots/metadata are
  complete.
- [x] Product review notes explain the sandbox purchase path and that Apple may
  retry if their sandbox account is temporarily unavailable before iChart
  receives a transaction.
- [ ] In-app subscription screen clearly shows name, duration, services, renewal
  price, restore purchases, and manage subscription path.
- [ ] Terms of Use and Privacy Policy are available from metadata and in app.
- [ ] Restore purchase works in sandbox/TestFlight.
- [x] Pro entitlement server verification is alive.
- [x] Review Notes explain StoreKit sandbox purchase/restore path.
- [x] Fresh server-backed review account shows Basic, not `Pro Expired`, when no
  server subscription authority row exists.

## Metadata, Screenshots, Media, And Age Rating

- [ ] App name, subtitle, promotional text, description, keywords, support URL,
  privacy URL, marketing URL, copyright, category, and review contact are
  complete.
- [ ] Metadata does not use Apple product terms in a misleading or disallowed
  way.
- [ ] Metadata does not promise unsupported V1.1 features such as full notation
  engraving, automatic rhythm recognition, horn-part generation, or messy
  paper cleanup.
- [ ] Screenshots show actual app use, not only splash/login/title art.
- [ ] Screenshots match the iPad device family and accepted sizes.
- [ ] Screenshots, preview text, and captions are accurate for V1.
- [ ] Product page images do not show private real-user data.
- [ ] Age rating answers are current, including social/forum/community features.
- [ ] Any App Store Connect warning about social-media/UGC age-rating responses
  is resolved before public release if it becomes blocking.

## Legal, Rights, And User-Generated Content

- [ ] Terms of Use/EULA link is present in metadata and in app.
- [ ] User Policy and Legal Policy are accessible in Help.
- [ ] Forum/upload flow states that users may upload only content they have the
  right to share.
- [ ] Forum detail surfaces include report and block controls for non-owned
  contributors.
- [ ] Forum PDF validation/provenance remains server-owned.
- [ ] User attribution is server-owned from immutable account names.
- [ ] User can withdraw pending forum submissions and remove published forum
  posts.
- [ ] App and metadata do not imply Apple endorsement.
- [ ] No copyrighted third-party music content, lyrics, recordings, or protected
  material is bundled without rights.

## Backend, Security, And Operations

- [x] `scripts/run_supabase_production_readiness.sh` passes.
  - 2026-07-31: passed after the StoreKit-completeness repair; Node shared
    backend tests `79/79`, full SwiftPM `657` tests, `38` skipped, `0`
    failures.
- [x] GitHub CI and CodeQL pass on the release PR.
- [x] Supabase Edge Functions list shows expected `verify_jwt` boundaries:
  `app-store-server-notifications=false`, `storekit-subscription-claims=true`,
  `forum-post-actions=true`, `account-deletion=true`,
  `subscription-retention-jobs=false`.
- [x] Hosted Edge Function smokes fail closed:
  App Store notification bad payload `400`, StoreKit claim unauth `401`, forum
  action unauth `401`, account deletion unauth `401`, retention unauth `401`.
- [x] RLS remains enabled on app-facing tables.
- [x] Private schema remains unavailable to `anon` and `authenticated`.
- [x] No service-role keys, JWT secrets, App Store keys, database URLs, `.p8`,
  provisioning profiles, or `.env` files are tracked or non-ignored.
- [x] Supabase warnings are accepted or tracked with rationale. Current known
  caveat: MFA advisor warning remains a post-V1 account UX/security follow-up
  unless a complete MFA/passkey flow is added.

## Resubmission Packet

- [x] PR merged to `main`.
- [x] Build `1.0 (36)` archived from the accepted app source, not only the
  repair branch.
- [x] Build `1.0 (36)` uploaded, processed, and attached in App Store Connect.
- [x] App Review Notes include:
  - Review account email and password, entered only in App Store Connect.
  - Settings > Account > Delete Account deletion path.
  - Attached physical-device deletion-flow recording.
  - StoreKit sandbox subscription path.
  - Support/privacy URLs.
  - Any special notes for Forums/cloud backup/reviewed chart PDFs.
- [x] App version, subscription group, monthly product, and annual product are
  included in the same submission.
- [x] Manual release remains selected unless a deliberate public-release
  decision changes it.
