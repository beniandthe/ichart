# iChart - Monetization Strategy

Status: Active for prototype and v1
Source of truth: `docs/core-design-document.md`
Plan policy authority: `docs/ichart-plan-policy-source-of-truth.md`

## 1. Purpose

This document makes the recommended iChart pricing, account, and entitlement model explicit.

The product model should build trust from the first launch, keep local chart ownership fair, and reserve recurring billing for features that create real ongoing infrastructure, storage, security, support, or service cost.

## 2. Launch recommendation

Recommended launch structure:

- account required for all users
- Basic account tier for local chart authoring and local persistence
- Pro subscription for cloud chart services and other service-heavy features

Account/auth is not the paywall. Account identity, email verification, password recovery, profile, and subscription state are part of the base trust layer.

The paywall starts where ongoing cloud/service cost starts: chart backup, restore, cross-device sync, and related cloud chart services.

## 3. Pricing principles

- Every user should have a recoverable iChart account with verified email and password recovery.
- The editor should remain local-first: chart writing, local save, and export should not depend on chart cloud sync.
- Recurring billing should pay for ongoing infrastructure and support burden, not for the mere ability to write charts.
- Monetization must not make musicians feel that their local charts are being held hostage.
- If renewal is canceled, Pro access continues through the paid-through date. If Pro actually expires, cloud chart backup/sync and Forums access pause until Pro is active again, and over-cap users must choose 3 local Basic charts before editing continues.

## 4. Recommended tier structure

### Basic account

Recommended v1 access:

- account creation and sign-in required
- verified email and password recovery
- profile and subscription identity
- create and edit a limited number of local charts
- all essential chart-writing tools
- PDF export and sharing
- local autosave
- recent chart library on the device
- basic rhythm-aware chord chart workflow
- enough functionality to understand the editor loop before paying

Recommended initial limit:

- 3 local charts

Recommended exclusions:

- cloud chart backup/sync/restore
- Forums access
- future service-heavy features such as shared libraries, version history, setlists, or AI-assisted cleanup if built

### Pro subscription

Recommended Pro access:

- cloud chart backup
- chart restore after reinstall or new iPad sign-in
- future cross-device chart sync
- Forums access as a Pro-only community chart library for PDF chart snapshots, voting, comments, reports, and trusted contributor badges
- future cloud-backed chart organization
- unlimited local charts if the subscription is active
- future service-heavy features such as sharing, version history, setlists, or AI-assisted cleanup if built

Pro should feel like the professional iChart account: unlimited chart capacity plus protected cloud chart services and community access.

## 5. Entitlement rules

- Account/auth/profile is mandatory base infrastructure, not a paid feature.
- Basic users can keep and reopen their 3 local Basic charts.
- Pro gates cloud chart services because they carry storage, security, email, recovery, support, and operational cost.
- Cloud chart sync must never block local authoring, local save, app launch, or export.
- If Pro renewal is canceled, keep full Pro access until the paid-through date and clearly show when access ends.
- If Pro expires, pause future cloud backup/sync and Forums access, and make the status clear.
- If an expired Basic account has more than 3 local charts, lock chart opening/editing until the user chooses which local charts to remove from the device so only 3 Basic charts remain.
- Downgrade pruning is local-only. It must not create remote deletion tombstones.
- Remote chart backups remain available through the paid-through date and any Apple billing grace period. After that retention deadline, cloud chart documents/snapshots are deleted by server-side retention cleanup.
- If Pro renews or payment recovers before the retention deadline, clear the pending cleanup state.
- Before Pro ends, warn the user in-app and by scheduled email that cloud backup will be removed and local chart access will lock until they choose 3 Basic charts.
- Restore purchases/subscription status must be supported from day one of monetization.

## 6. V1 implementation guidance

For v1, keep the implementation honest and local-first:

- require account creation/sign-in in the production onboarding flow
- keep local chart files as the editor source of truth
- keep account/profile/subscription state cloud-backed and recoverable
- gate `ChartCloudSyncService` behind a Pro entitlement before production cloud sync rollout
- gate Forums behind the same active Pro entitlement
- treat current signed-in chart sync behavior as an interim QA path until entitlement gating is wired
- keep StoreKit/subscription logic isolated behind a small boundary
- keep service-role keys, SMTP credentials, webhook secrets, and payment secrets out of the app

## 7. Open tuning knobs

These values can be adjusted after early beta feedback:

- Pro monthly and annual pricing, currently targeted at $7.99/month and $64.99/year
- exact timing for the day-before expiration email and any operational safety buffer for refunds/revocations
- whether unlimited local charts belongs only to active Pro or later gets a permanent local unlock
- which future service-heavy Pro features join cloud chart services and Forums after launch

## 8. Current recommendation summary

iChart should launch with mandatory recoverable accounts for both Basic and Pro users. Basic includes the complete local chart-writing tool, PDF/export, local autosave, and a 3-chart local cap. Pro gates unlimited chart capacity, cloud chart backup/sync/restore, Forums, and other service-heavy features. The account system is a trust foundation; chart cloud services and community/service surfaces are the paid operational layer.
