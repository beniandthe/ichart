# iChart App Store and TestFlight Metadata Draft

Status: Draft for internal/external TestFlight setup
Last updated: 2026-06-21

## App Identity

- App name: iChart: Quick-Notation Charts
- Bundle ID: com.ichart.app
- SKU: ichart-ios
- Primary category: Music
- Secondary category: Productivity
- Copyright: 2026 iChart

## Subtitle Options

Preferred:

> Pencil-first chord charts for iPad

Alternates:

- Fast chord charts for working musicians
- Write clean rehearsal charts on iPad
- Pencil to polished chord charts

## Short Description

> iChart helps musicians turn quick iPad handwriting into clean, readable chord and rhythm charts. Create charts locally, export PDFs, transpose chord symbols, and use Pro for cloud backup, restore, projects, and community chart PDFs.

## Full Description Draft

iChart is an iPad chart-writing app for musicians who need rough ideas to become clean rehearsal-ready charts quickly.

Write with Apple Pencil, shape simple chord sheets or rhythm section charts, edit recognized chord objects, adjust meter and layout, transpose chord symbols, and export polished PDFs for rehearsal, teaching, or performance prep.

Basic accounts include local chart writing, a 3-chart local library, PDF export, account recovery, and subscription identity.

iChart Pro adds unlimited local charts, Projects, cloud backup and restore, and Forums access for reviewed community chart PDFs.

iChart is not full notation software. It is built for practical chord charts, rhythm-aware placement, quick correction, and readable output.

## Keywords Draft

chord chart,lead sheet,music chart,jazz chart,rehearsal chart,rhythm chart,sheet music,transpose,Apple Pencil,musician

## Promotional Text Draft

> Turn quick handwritten chord ideas into clean iPad charts for rehearsal, teaching, and performance prep.

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

- iChart is focused on chord/rhythm charts, not full notation engraving.
- Recognition will still need correction on some handwriting styles.
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

## Screenshot Checklist

Required iPad screenshots:

- Charts library with New Chart available.
- Apple Pencil chart editor with handwritten/recognized chord content.
- Simple Chord Sheet PDF/export preview.
- Rhythm Section Sheet with beat-aware chord placement.
- Settings showing account and Pro subscription state.
- Forums/Community Library surface for Pro users.

Optional:

- Projects surface for Pro users.
- Help/FAQ or Contact Us surface.

## URLs And Contact Placeholders

- Privacy Policy URL: https://useichart.com/privacy
- Support URL: https://useichart.com/support
- Marketing URL: https://useichart.com
- Support email: support@useichart.com
- Beta feedback email: support@useichart.com

These must be real, monitored, public-facing destinations before external TestFlight or App Review.

## Deferred Operations

- Supabase Pro upgrade is deferred until a supported payment method is available.
- After upgrade, enable leaked-password protection and revisit MFA advisor settings.
- Universal links remain a production follow-up once a stable associated domain is selected.
