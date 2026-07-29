# iChart Apple App Review Submission Checklist

Status: V1.0 App Review checklist for build `1.0 (33)`
Last updated: 2026-07-29

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

## Current Resubmission Blocker

Build `1.0 (32)` was rejected on 2026-07-29 for Guideline `5.1.1 Legal:
Privacy - Data Collection and Storage` because iChart supports account creation
but did not include an in-app account deletion option.

Build `1.0 (33)` is the repair target.

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
  `https://useichart.com`.
- [x] Verify live `https://useichart.com/privacy` includes Settings > Account >
  Delete Account.
- [ ] Attach the physical-device screen recording Apple requested in App Review
  Notes.
- [ ] Upload/attach build `1.0 (33)`.
- [ ] Resubmit app version plus subscription group/monthly/annual items.

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

- [ ] Privacy Policy URL is present in App Store Connect.
- [ ] Privacy Policy URL is accessible in-app and on the product page.
- [ ] Privacy policy identifies data collected, how it is collected, why it is
  used, data retention/deletion behavior, and support contact.
- [ ] App Store privacy questionnaire matches actual V1 data practices.
- [ ] No third-party analytics/ads SDKs are present or claimed.
- [ ] Account creation collects only directly relevant information.
- [ ] App Review has a working demo/review account.
- [ ] Account deletion is easy to find in account settings.
- [ ] Account deletion removes the account record and associated iChart data not
  legally required to retain.
- [ ] If subscription is active, the deletion flow or review notes explain that
  Apple manages subscription billing/cancellation.
- [ ] User-generated public forum content associated with the account is removed
  or hidden as part of account deletion, except legally required retained
  records.

## Subscriptions And IAP

- [ ] Subscription group is submitted with the app version.
- [ ] Monthly product ID is `com.ichart.app.pro.monthly`.
- [ ] Annual product ID is `com.ichart.app.pro.annual`.
- [ ] Product names, prices, duration, description, and screenshots/metadata are
  complete.
- [ ] In-app subscription screen clearly shows name, duration, services, renewal
  price, restore purchases, and manage subscription path.
- [ ] Terms of Use and Privacy Policy are available from metadata and in app.
- [ ] Restore purchase works in sandbox/TestFlight.
- [ ] Pro entitlement server verification is alive.
- [ ] Review Notes explain StoreKit sandbox purchase/restore path.

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

- [ ] `scripts/run_supabase_production_readiness.sh` passes.
- [ ] GitHub CI and CodeQL pass on the release PR.
- [ ] Supabase Edge Functions list shows expected `verify_jwt` boundaries:
  `app-store-server-notifications=false`, `storekit-subscription-claims=true`,
  `forum-post-actions=true`, `account-deletion=true`,
  `subscription-retention-jobs=false`.
- [ ] Hosted Edge Function smokes fail closed:
  App Store notification bad payload `400`, StoreKit claim unauth `401`, forum
  action unauth `401`, account deletion unauth `401`, retention unauth `401`.
- [ ] RLS remains enabled on app-facing tables.
- [ ] Private schema remains unavailable to `anon` and `authenticated`.
- [ ] No service-role keys, JWT secrets, App Store keys, database URLs, `.p8`,
  provisioning profiles, or `.env` files are tracked or non-ignored.
- [ ] Supabase warnings are accepted or tracked with rationale. Current known
  caveat: MFA advisor warning remains a post-V1 account UX/security follow-up
  unless a complete MFA/passkey flow is added.

## Resubmission Packet

- [ ] PR merged to `main`.
- [ ] Build `1.0 (33)` archived from `main`, not only the repair branch.
- [ ] Build `1.0 (33)` uploaded and processed in App Store Connect.
- [ ] App Review Notes include:
  - Review account email and password, entered only in App Store Connect.
  - Settings > Account > Delete Account deletion path.
  - Attached physical-device deletion-flow recording.
  - StoreKit sandbox subscription path.
  - Support/privacy URLs.
  - Any special notes for Forums/cloud backup/reviewed chart PDFs.
- [ ] App version, subscription group, monthly product, and annual product are
  included in the same submission.
- [ ] Manual release remains selected unless a deliberate public-release
  decision changes it.
