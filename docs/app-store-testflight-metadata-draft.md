# iChart App Store and TestFlight Metadata Draft

Status: Public App Store metadata draft, aligned with current V1 launch positioning
Last updated: 2026-07-22

## App Identity

- App name: iChart: Quick-Notation Charts
- Bundle ID: com.ichart.app
- SKU: ichart-ios
- Primary category: Music
- Secondary category: Productivity
- Copyright: 2026 iChart

## Subtitle Options

Preferred:

> Pencil-first charts for iPad

Alternates:

- Pencil-first chord charts
- Fast chord charts for working musicians
- Write clean rehearsal charts on iPad
- Pencil to polished chord charts

## Short Description

> iChart helps musicians handwrite clean, reusable chord charts on iPad. Write with Apple Pencil, transpose chord symbols, organize charts into projects, and export PDFs for rehearsal or performance prep.

## Full Description Draft

iChart is an iPad chart-writing app for musicians who need practical charts without slowing down into full notation software.

Write clean chord charts by hand with Apple Pencil. Add chords, repeats, form markings, and notes directly on the page, then keep the chart editable for the next rehearsal, singer, horn player, or gig.

Use iChart when paper is fast but not reusable, when quick chord-chart apps feel limiting, and when full notation software is more tool than the moment needs.

Core chart tools:

- Create Simple Chord Sheet and Rhythm Section Sheet charts.
- Write and edit recognized chord symbols.
- Add repeats, text notes, meter, and layout changes.
- Duplicate charts and transpose chord symbols for new keys or instruments.
- Export readable PDFs for rehearsal, teaching, and performance prep.

Basic accounts include local chart writing, a 3-chart local library, PDF export, account recovery, and subscription identity.

iChart Pro adds unlimited local charts, Projects, cloud backup and restore, and Forums access for reviewed community chart PDFs.

iChart is not full notation engraving software. It is built for musicians who need paper-speed chart creation with the practical power of editable, transposable digital charts.

## Keywords Draft

chord chart,lead sheet,music chart,jazz chart,rehearsal,transpose,Apple Pencil,musician

## Promotional Text Draft

> Handwrite reusable chord charts on iPad, then transpose, organize, and export when the gig changes.

## Public Product Page Guardrails

- Do not claim automatic cleanup of messy paper charts.
- Do not imply full notation engraving, automatic horn arranging, or automatic part generation.
- Use "handwrite clean charts at paper speed" as the core promise.
- Use "Available on the App Store" and the official App Store badge only after the public product page or pre-order page is live.
- Do not use public V1 copy to promise dedicated rhythm notation tools, rhythm recognition, or rhythm rendering.
- If rhythm notation comes up, frame it only as a planned V1.1 lane for select-input notation and future workflow expansion.

## Current Apple Product Page Requirements Checked 2026-07-20

- App name and subtitle are each limited to 30 characters. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/
- Promotional text appears above the description and is limited to 170 characters. Source: https://developer.apple.com/app-store/product-page/
- Screenshots can be `.jpeg`, `.jpg`, or `.png`; upload 1 to 10 screenshots; images cannot include alpha channels. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- For an iPad app, 13-inch iPad screenshots are required. Accepted 13-inch sizes include `2064 x 2752`, `2752 x 2064`, `2048 x 2732`, and `2732 x 2048`. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- App previews are optional; up to three can be uploaded per supported device size and language. Source: https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- A Privacy Policy URL is required for all apps. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/
- The Support URL is required and must lead to actual contact information. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
- If using an App Store badge in marketing, use Apple-provided badge artwork and do not modify it. Source: https://developer.apple.com/app-store/marketing/guidelines/

## What's New / Release Notes Template

> Initial TestFlight build for iChart V1: local chart creation, Apple Pencil editing, PDF export, account sign-in, Pro subscription restore, cloud backup, Projects, and Forums access.

## TestFlight Beta Description

Please test the core iChart loop:

- Create a new chart.
- Add and edit chord symbols.
- Try Simple Chord Sheet and Rhythm Section Sheet workflows.
- Export and share a PDF.
- Close and reopen the app to confirm charts persist.
- If you have Pro enabled, test restore purchases, cloud backup, Projects, and Forums.

Known V1 boundaries:

- iChart is focused on reusable chord charts and practical gig charts, not full notation engraving.
- Chord recognition will still need correction on some handwriting styles.
- V1.1 roadmap note: dedicated rhythm notation input is planned as a select-input workflow. Do not describe V1.0 as shipping handwritten rhythm recognition or rendered rhythm notation.
- Key signatures and enharmonic transposition preferences are V1.1 roadmap
  items, not V1.0 launch promises.
- Forums publish reviewed PDF snapshots, not editable chart source files.
- Cloud backup and Forums require active Pro.

Please send TestFlight feedback with your iPad model, iPadOS version, chart type, and the shortest steps that reproduce any issue.

## App Review Notes Draft

iChart is an iPad-only music chart-writing app.

Test account:

- Username/email: [APP_REVIEW_TEST_ACCOUNT_EMAIL]
- Password: [PROVIDE IN APP STORE CONNECT ONLY]

Subscription products:

- Monthly: com.ichart.app.pro.monthly
- Annual: com.ichart.app.pro.annual

Suggested review path:

1. Sign in with the provided test account.
2. Open Settings and confirm account status.
3. Open Charts and create a new chart.
4. Add or edit chord content.
5. Export/share a PDF.
6. Open Settings > Pro Subscription and use restore/purchase flow in sandbox.
7. Confirm Pro unlocks unlimited charts, Projects, cloud backup, and Forums.

Notes:

- Apple handles purchase, restore, cancellation, and subscription management.
- iChart sends StoreKit transactions to a Supabase Edge Function for server-side verification.
- The app does not include service-role keys, App Store Connect keys, or webhook secrets.
- Forum publishing creates reviewed PDF snapshots; editable source chart data is not published in V1.

## Screenshot Plan

Required iPad product-page set:

1. Charts library with a real gig-oriented chart list and New Chart available.
   - Caption direction: "Start a clean chart fast."
2. Apple Pencil chart editor showing handwritten and recognized chord content.
   - Caption direction: "Handwrite chords directly on the page."
3. Chord, repeat, text, and form-marking workflow on a simple chart.
   - Caption direction: "Build the chart musicians actually need."
4. Transpose flow using the wedding-key-change example.
   - Caption direction: "Duplicate and transpose for the new key."
5. Projects surface showing a set folder or band book.
   - Caption direction: "Keep the gig together."
6. PDF export or preview screen showing a readable chart output.
   - Caption direction: "Export a chart players can use."
7. Settings/account state with Basic/Pro wording exactly matching the app.
   - Caption direction: "Local writing first. Pro adds backup and projects."
8. Forums/Community Library surface for Pro users, only if review state is clean.
   - Caption direction: "Share reviewed PDF chart snapshots."

Optional:

- App preview video adapted from SM-001 after removing hard-launch wording until the App Store page is live.
- Help/FAQ or Contact Us surface if Apple review needs support discoverability proof.

Capture notes:

- Use the current release build UI only.
- Avoid raw iPad status bars, recording indicators, test emails, personal names, private account identifiers, or placeholder chart titles.
- Export final screenshots without alpha channels.
- Prepare both landscape and portrait only if the product story benefits from both; otherwise keep the set visually consistent.
- Use a real, rights-safe chart example from the social demo set: `Funk Groove`, `Funk Groove Bb Horn`, `First Dance In C`, and `First Dance In F`.

## URLs And Contact Placeholders

- Privacy Policy URL: https://useichart.com/privacy
- Support URL: https://useichart.com/support
- Marketing URL: https://useichart.com
- Support email: support@useichart.com
- Beta feedback email: support@useichart.com

These must be real, monitored, public-facing destinations before App Review and public submission.

## Deferred Operations

- Supabase Pro upgrade is deferred until a supported payment method is available.
- After upgrade, enable leaked-password protection and revisit MFA advisor settings.
- Universal links remain a production follow-up once a stable associated domain is selected.
- App Store Server API current-status checks are a follow-up after the basic TestFlight purchase/restore path is green; the current release-candidate server gate relies on signed StoreKit transaction claims, App Store Server Notifications V2, app-account token binding, and replay/idempotency guards.
