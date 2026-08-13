# iChart App Store and TestFlight Metadata Draft

Status: Public App Store metadata draft, aligned with current V1 launch positioning
Last updated: 2026-08-06

## App Identity

- App name: iChart: Music Notation
- Bundle ID: com.ichart.app
- SKU: ichart-ios
- Primary category: Music
- Secondary category: Productivity
- Copyright: 2026 iChart

## Canonical App Store Search Package

- App name: `iChart: Music Notation` (22 characters)
- Subtitle: `Handwritten charts for iPad` (27 characters)
- Keywords: `chord,lead sheet,pdf,band,setlist,gig,musician,pencil,teacher,horn,wedding,transpose,rehearsal` (94 characters)

Intent:

- Put `music` and `notation` in the highest-weight visible name field so iChart
  stops reading like a medical, data, or business charting app.
- Use the subtitle to clarify that the product is still the musician workflow:
  handwritten charts on iPad.
- Use the keyword field for adjacent working-musician searches that are not
  already covered by the app name, subtitle, or Music category.

App Store Connect status checked 2026-08-06:

- Live version 1.0 remains the public App Store version until V1.1 is reviewed
  and released.
- V1.1 exists in App Store Connect as `1.1 Prepare for Submission`.
- The V1.1 draft has the canonical app name, subtitle, promotional text,
  description, keywords, What's New text, App Review notes, and iPad screenshot
  package applied.

## Subtitle Options

Preferred:

> Handwritten charts for iPad

Alternates:

- Handwrite, transpose, export
- Music charts on iPad
- Chord charts on iPad
- Apple Pencil chart writing

## Short Description

> iChart helps musicians handwrite clean, reusable music charts on iPad, then transpose, organize, and export them as PDFs.

## Full Description Draft

iChart helps musicians handwrite clean, reusable music charts on iPad, then transpose, organize, and export them as PDFs.

Write practical charts by hand. Add chords, repeats, form markings, rhythm cues, and notes directly on the page, then keep the chart editable for the next rehearsal, singer, horn player, lesson, or gig.

Use iChart when paper is fast but not reusable, when quick chord-chart apps feel limiting, and when full notation software is more tool than the moment needs.

Core chart tools:

- Create Simple Chord Sheet and Rhythm Section Sheet charts.
- Write and edit recognized chord symbols.
- Add repeats, text notes, meter, rhythm cues, and layout changes.
- Duplicate charts and transpose chord symbols for new keys or instruments.
- Export readable PDFs for rehearsal, teaching, and performance prep.

Basic accounts include local chart writing, a 3-chart local library, PDF export, account recovery, and subscription identity.

iChart Pro adds unlimited local charts, Projects, cloud backup and restore, and Forums access for reviewed community chart PDFs.

iChart is not full notation engraving software. It is built for musicians who need paper-speed chart creation with the practical power of editable, transposable digital charts.

## Keywords Draft

chord,lead sheet,pdf,band,setlist,gig,musician,pencil,teacher,horn,wedding,transpose,rehearsal

## Promotional Text Draft

> Handwrite reusable music charts on iPad, then transpose, organize, and export when the gig changes.

## Public Product Page Guardrails

- Do not claim automatic cleanup of messy paper charts.
- Do not imply full notation engraving, automatic horn arranging, or automatic part generation.
- Use "handwrite clean charts at paper speed" as the core promise.
- Use "Available on the App Store" and the official App Store badge only after the public product page or pre-order page is live.
- Do not use public V1 copy to promise dedicated rhythm notation tools, rhythm recognition, or rhythm rendering.
- If rhythm notation comes up, frame it only as a planned V1.2 lane for select-input notation and future workflow expansion.

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

> iChart V1.1 adds official key signatures, chart modulations, key-aware enharmonic chord spelling, expanded chord-symbol coverage, a refreshed first-run tour, and chord editing polish.

## Per-Build App Store Update Notes

Every App Store Connect submission should include a concise user-facing update
note for that specific build. Use this section to track the public "What's New"
copy plus any TestFlight-facing fix/patch notes so users and testers can see
what changed and what is being actively tightened.

Rules:

- Keep each build entry factual and scoped to shipped or testable changes.
- Separate public App Store "What's New" copy from TestFlight fix/patch notes
  when the patch detail is useful for testers but too granular for the public
  product page.
- Do not list future roadmap work as shipped. Planned work belongs in roadmap
  docs unless the build actually includes it.
- For patch-only builds, name the user-visible fix, crash fix, performance fix,
  or review-facing correction that changed.

### Build 38 / V1.1

Public App Store "What's New":

> iChart V1.1 adds official key signatures, chart modulations, key-aware enharmonic chord spelling, expanded chord-symbol coverage, a refreshed first-run tour, and chord editing polish.

TestFlight / review-facing update notes:

- Adds V1.1 key-signature and modulation support across chart setup, rendering,
  chord spelling, and export.
- Tightens chord editing by aligning the update-chord flow with the confirm-chord
  flow.
- Refreshes the first-run tutorial so tool guidance is clearer and less likely
  to cover the controls being taught.
- Adds the home-screen V1.1/date stamp so testers can confirm they are on the
  active update build.

App Store screenshot package:

- Use `docs/app-store/media/v1-1-build-38-key-signatures/ipad-13-portrait/`
  for the three V1.1 key-signature screenshots.
- App Store Connect iPad 13-inch display order keeps the inherited V1 first
  seven screenshots, then uses these V1.1 shots in slots 8-10: new chart
  key/clef setup, rendered rhythm chart key signatures, and page key-change
  menu.
- Social-safe originals are preserved in
  `docs/app-store/media/v1-1-build-38-key-signatures/originals/`; the social
  handoff note is `docs/marketing/social-media/v1-1-key-signature-screenshot-handoff.md`.

### Build 42 / V1.1.2

Public App Store "What's New":

> This update tightens account verification recovery and Simple Chord Sheet chord spacing. Replacement verification emails now only show as sent after iChart confirms the request, password-reset links stay intact across app relaunch, and Simple Chord Sheet chords use clearer beat lanes.

TestFlight / review-facing update notes:

- Includes the PR #44 auth recovery follow-up on top of the V1.1.1 trust patch.
- Preserves pending password-reset recovery flows during app restoration instead
  of clearing them while checking for a restorable signup-verification email.
- Shows "Replacement Email Sent" only after the resend request succeeds, and
  keeps the replacement-email button in a sending state while the request is in
  flight.
- Updates Simple Chord Sheet chord layout so chords anchor to their beat lanes
  and use the available measure space more predictably.
- Adds `ProjectConfigurationTests` coverage for the pending-flow preservation
  and resend-success UI contract.
- Adds `LeadSheetPageLayoutTests` coverage for the Simple Chord Sheet spacing
  contract.

## TestFlight Beta Description

Please test the core iChart loop:

- Create a new chart.
- Add and edit chord symbols.
- Try Simple Chord Sheet and Rhythm Section Sheet workflows.
- Export and share a PDF.
- Close and reopen the app to confirm charts persist.
- If you have Pro enabled, test restore purchases, cloud backup, Projects, and Forums.

Known V1.1 boundaries:

- iChart is focused on reusable chord charts and practical gig charts, not full notation engraving.
- Chord recognition will still need correction on some handwriting styles.
- V1.2 roadmap note: dedicated rhythm notation input is planned as a select-input workflow. Do not describe V1.0 or V1.1 as shipping handwritten rhythm recognition or rendered rhythm notation.
- Forums publish reviewed PDF snapshots, not editable chart source files.
- Cloud backup and Forums require active Pro.

Please send TestFlight feedback with your iPad model, iPadOS version, chart type, and the shortest steps that reproduce any issue.

## App Review Notes Draft

iChart is a chart-writing app for musicians.

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
8. Account deletion is available from Settings > Account > Delete Account.

Notes:

- Apple handles purchase, restore, cancellation, and subscription management.
- iChart sends StoreKit transactions to a Supabase Edge Function for server-side verification.
- Paid Apps Agreement, banking, and U.S. tax setup are active in App Store Connect. The subscription group and both products are included in this submission with the app version.
- If StoreKit shows a sandbox account availability alert before the Apple purchase confirmation completes, no transaction has reached iChart yet. Please retry the sandbox purchase or use Restore Purchases after the sandbox account is available.
- The app does not include service-role keys, App Store Connect keys, or webhook secrets.
- Account deletion is initiated in-app at Settings > Account > Delete Account. Use a disposable review account before completing the deletion flow; deletion removes the iChart account/server data and signs the app out.
- Attach the physical-device account deletion screen recording requested by App Review to the Notes field for this submission and future submissions until the review history is stable.
- Forum publishing creates reviewed PDF snapshots; editable source chart data is not published in V1.

## Screenshot Plan

Required iPad product-page set:

1. Charts library with a real gig-oriented chart list and New Chart available.
   - Caption direction: "Start a clean chart fast."
2. Handwritten chart editor showing handwritten and recognized chord content.
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

- Privacy Policy URL: https://useichart.com/privacy.html
- Support URL: https://useichart.com/support.html
- Marketing URL: https://useichart.com
- Support email: support@useichart.com
- Beta feedback email: support@useichart.com

These must be real, monitored, public-facing destinations before App Review and public submission.

## Deferred Operations

- Supabase Pro upgrade is deferred until a supported payment method is available.
- After upgrade, enable leaked-password protection and revisit MFA advisor settings.
- Universal links remain a production follow-up once a stable associated domain is selected.
- App Store Server API current-status checks are a follow-up after the basic TestFlight purchase/restore path is green; the current release-candidate server gate relies on signed StoreKit transaction claims, App Store Server Notifications V2, app-account token binding, and replay/idempotency guards.
