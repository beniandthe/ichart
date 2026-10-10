# iChart App Store and TestFlight Metadata Draft

Status: Local App Store/TestFlight metadata draft; build 75 privacy publication hold
Last updated: 2026-10-09

## Build 75 Privacy Publication Hold — 2026-10-09

The current native QA candidate is `1.2.1 (75)`. Signed installation and QA
receipts do not establish App Store/TestFlight publication or privacy-label
approval. App Store Connect's existing App Privacy entries and live version
state were **not refreshed here following the earlier browser-access restriction**;
current access has not been retried in this physical-acceptance update. The
App Privacy entries below are local submission proposals, not live store writes.
The updated public privacy policy has not been published. The telemetry-only
database deployment described below does not establish either publication.

The Customer Support manifest entry and corrected support-report help copy are
now Development-signed, installed and normally launched as `1.2.1 (75)`.
Signature/profile and saved-content checks pass. On October 9 the user reported
**“Both passed”** for the short privacy/legal, keyboard/Scribble review,
render/save/reopen/PDF and Free Ink rotation checklist in Simple and Rhythm.
That is user-reported acceptance, not measured performance or general recognition
accuracy. The delivery and acceptance receipt is in
`docs/privacy-telemetry-release-closeout-2026-10-09.md`.

The final native privacy gate executed 38 tests with zero failures or skips,
verified through `xcresulttool`. The initial run's 37 passes and one obsolete
wording failure are retained separately; that wording/test mismatch is now
fixed. The separate signed delivery above, not the test count, establishes
installation of the new native copy and manifest.

The later final candidate review also passes the full native and SwiftPM gates
and a fresh **unsigned Release** build, retaining `1.2.1 (75)` and the same
privacy manifest. This is not a distribution archive, upload, or live build-number
reservation. Remaining compiler warnings and actual coverage are in
`docs/final-candidate-review-2026-10-09.md`.

Coordinate the updated privacy policy, App Privacy entries, and distribution of
the updated default-off app before publication. Do not describe the older
distributed app as having the updated consent controls without version-specific
evidence. Real scheduler execution and end-to-end Auth account deletion remain
unobserved. Public policy/store writes and distribution remain separate gates;
the short physical acceptance does not close them.

### Proposed App Privacy Matrix

This matrix transcribes the ten data types and purposes currently declared in
`iChart/Resources/PrivacyInfo.xcprivacy`. Every declared type is linked to the
user and not used for tracking; the manifest also declares no tracking domains.
It is the starting point for App Privacy review, not proof that the live store
entries match or that every collection channel has been assessed.

| Data type | Linked to user | Tracking | Purposes |
| --- | --- | --- | --- |
| Name | Yes | No | App Functionality |
| Email Address | Yes | No | App Functionality |
| User ID | Yes | No | App Functionality; Analytics |
| Device ID | Yes | No | App Functionality; Analytics |
| Purchase History | Yes | No | App Functionality; Analytics |
| Other User Content | Yes | No | App Functionality |
| Customer Support | Yes | No | App Functionality |
| Product Interaction | Yes | No | App Functionality; Analytics |
| Performance Data | Yes | No | App Functionality; Analytics |
| Other Diagnostic Data | Yes | No | App Functionality; Analytics |

**Customer Support scope:** user-initiated support emails and explicitly shared
diagnostic reports are a collection channel even when automatic telemetry is
off. The local manifest now declares this type as linked to the user, not used
for tracking, and used only for App Functionality. This does not establish a
live App Privacy update.

**Approved manual support-data policy:** retain manually submitted support
messages and reports only as needed to resolve the issue and follow up. Honor
verified deletion requests, except for records required for legal or security
purposes. This policy is separate from the database's 180-day telemetry cleanup;
it does not establish an automated email/report purge or a blanket deletion
guarantee. The updated public policy and store labels have not been published.

### Automatic Diagnostics Versus Explicitly Shared Reports

- In the updated app, automatic usage/reliability telemetry is off until the
  user opts in through Settings > Privacy > Share App Diagnostics. Opting out
  stops new automatic collection/sending, clears unsent queued telemetry, and
  removes its installation identifier. Requests already sent may finish;
  opting out does not erase records already received by the server. App
  features and subscription access do not require this consent.
- Opted-in events include random installation/session identifiers, technical
  app/device context, workflow counts, timings, and bounded error/aggregate ink
  diagnostics. Signed-in events may be linked to the iChart account. The
  automatic telemetry allowlist excludes chart titles, email/name fields, raw
  chord text, drawings, PDFs, screenshots, and chart documents; this is not a
  claim about data the user separately sends to support, cloud backup, or Forums.
- Local performance traces are separate from automatic telemetry consent and
  are not automatically uploaded by the trace recorder. A user may explicitly
  share an exported support report. Its export removes raw uptime fields, but
  that does not establish that every retained metadata value is content-free.
  Do not apply the automatic telemetry exclusions to every manual report.
  Unshared local traces are not manually submitted support data and are not
  automatically removed by telemetry opt-out or database cleanup.

### Deployed Telemetry Configuration And Remaining Evidence

- **DEPLOYED CONFIGURATION, telemetry only:** the user-approved migration was
  applied successfully at remote version `20261009230003`. The local migration
  filename is aligned to that version; its unchanged SHA-256 is
  `1d0f2095dc04f898f670f85955dc73c79e30f3b9398be9228d00ad5ecae0117d`.
- Read-only verification at **2026-10-09 23:00:51 UTC** confirmed the validated
  account-linked telemetry `CASCADE`, retained RLS, no table/helper privileges
  for `anon` or `authenticated`, and retained service-role execution privilege.
  A real end-to-end Auth account deletion has **not** been observed.
- Exactly one active job was verified: ID `3`,
  `ichart-telemetry-retention-180d`, schedule `15 3 * * *` in GMT (03:15 UTC
  daily), with the purge helper configured for 180 days. It removes telemetry
  events older than 180 days at execution time. This is a daily cutoff, not an
  exact 180-day maximum: records can remain between runs or if the job fails.
- At that check, expired-event count was `0` and real job-run count was `0`.
  Scheduler configuration is verified; a real cron execution/purge receipt is
  **not** yet observed. Do not turn the zero expired count into purge evidence.
- Local synthetic verification passed 11 PostgreSQL tests and 31 ingest/account
  regression tests. Those results support the local implementation but do not
  establish a real scheduler run or end-to-end Auth account-service deletion.
- Account-delete `CASCADE` does not remove anonymous installation-linked
  telemetry records; those still need the applicable retention/data-request
  policy. Telemetry-event retention does not purge local performance traces or
  manually supplied support reports; submitted support data follows the separate
  approved policy above. Withdrawal, account deletion, and a verified support
  data-deletion request remain distinct actions; the final disclosure must state
  the approved boundaries.

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

Historical App Store Connect snapshot — checked 2026-08-06, not refreshed here:

- At that check, live version 1.0 remained the public App Store version pending
  V1.1 review and release.
- At that check, V1.1 existed as `1.1 Prepare for Submission`.
- The V1.1 draft then had the canonical app name, subtitle, promotional text,
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

## Historical Apple Product Page Requirements — Checked 2026-07-20

Retained for submission preparation. These requirements and source pages were
not rechecked in this update; refresh them through an authorized Apple access
path before relying on them for a new submission.

- App name and subtitle are each limited to 30 characters. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/
- Promotional text appears above the description and is limited to 170 characters. Source: https://developer.apple.com/app-store/product-page/
- Screenshots can be `.jpeg`, `.jpg`, or `.png`; upload 1 to 10 screenshots; images cannot include alpha channels. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- For an iPad app, 13-inch iPad screenshots are required. Accepted 13-inch sizes include `2064 x 2752`, `2752 x 2064`, `2048 x 2732`, and `2732 x 2048`. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- App previews are optional; up to three can be uploaded per supported device size and language. Source: https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- A Privacy Policy URL is required for all apps. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/
- The Support URL is required and must lead to actual contact information. Source: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
- If using an App Store badge in marketing, use Apple-provided badge artwork and do not modify it. Source: https://developer.apple.com/app-store/marketing/guidelines/

## What's New / Release Notes Template

Historical V1.1 template; select build-specific copy for the actual submission.

> iChart V1.1 adds official key signatures, chart modulations, key-aware enharmonic chord spelling, expanded chord-symbol coverage, a refreshed first-run tour, and chord editing polish.

## Per-Build App Store Update Notes

Every App Store Connect submission should include a concise user-facing update
note for that specific build. Use this section to track the public "What's New"
copy plus any TestFlight-facing fix/patch notes so users and testers can see
what changed and what is being actively tightened.

The build 38/42/51 entries below are retained historical release notes, not
evidence of the current public version, current consent rollout, or deployed
retention/deletion guarantees. In particular, build 42's telemetry introduction
does not establish the updated default-off behavior described for build 75 above.

Rules:

- Keep each build entry factual and scoped to shipped or testable changes.
- Separate public App Store "What's New" copy from TestFlight fix/patch notes
  when the patch detail is useful for testers but too granular for the public
  product page.
- Do not list future roadmap work as shipped. Planned work belongs in roadmap
  docs unless the build actually includes it.
- For patch-only builds, name the user-visible fix, crash fix, performance fix,
  or review-facing correction that changed.

### Build 51 / V1.2.1

Public App Store "What's New":

> iChart 1.2.1 improves the chart-writing workflow with clearer chord-tool guidance, Help and Settings updates, true multi-page Add Page export behavior, and more predictable Simple Chord Sheet chord placement.

TestFlight / review-facing update notes:

- Includes the current UI/UX pass for first-use guidance, Help, Settings,
  chord-tool labeling, and chart setup copy.
- Adds true Add Page behavior so later pages are separate chart pages, inherit
  chart settings, and export as multi-page PDFs.
- Updates Simple Chord Sheet chord rendering to use deterministic placement
  slots for more predictable chord positioning.
- Keeps chord recognition in the explicit draft workflow until the user chooses
  `Render Chords`.
- Maintains the existing account, local library, PDF export, Pro subscription,
  and Forums boundaries.

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

> This update tightens account verification recovery, Simple Chord Sheet chord spacing, and support diagnostics. Replacement verification emails now only show as sent after iChart confirms the request, password-reset links stay intact across app relaunch, Simple Chord Sheet chords use clearer beat lanes, and privacy-limited diagnostics help us investigate reliability issues without collecting chart content.

TestFlight / review-facing update notes:

- Includes the PR #44 auth recovery follow-up on top of the V1.1.1 trust patch.
- Preserves pending password-reset recovery flows during app restoration instead
  of clearing them while checking for a restorable signup-verification email.
- Shows "Replacement Email Sent" only after the resend request succeeds, and
  keeps the replacement-email button in a sending state while the request is in
  flight.
- Updates Simple Chord Sheet chord layout so chords anchor to their beat lanes
  and use the available measure space more predictably.
- Adds privacy-limited telemetry for launch/auth/library/editor/export/cloud/
  subscription/forum outcomes, plus aggregate ink visibility diagnostics for
  support cases. Telemetry does not collect chart titles, emails, raw chord
  text, drawings, PDFs, screenshots, or chart documents.
- Adds Supabase `telemetry_events` storage, `app-telemetry-ingest`, protected
  rollup views, retention helper, and client/server allowlist sanitizers.
- Updates hosted and in-app privacy copy for the new diagnostics boundary.
- Adds `ProjectConfigurationTests` coverage for the pending-flow preservation
  and resend-success UI contract, telemetry backend wiring, and telemetry
  privacy guardrails.
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

Historical V1.1 boundaries (refresh for the actual submission):

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
- Historical review setup recorded Paid Apps Agreement, banking, and U.S. tax setup as active, with the subscription group and both products included. This account/submission state is not freshly verified here; confirm it before using that assertion in new App Review notes.
- If StoreKit shows a sandbox account availability alert before the Apple purchase confirmation completes, no transaction has reached iChart yet. Please retry the sandbox purchase or use Restore Purchases after the sandbox account is available.
- The app does not include service-role keys, App Store Connect keys, or webhook secrets.
- Account deletion is initiated in-app at Settings > Account > Delete Account. Use a disposable review account before completing the deletion flow. The account-linked telemetry `CASCADE` configuration above is deployed and validated, but real end-to-end Auth deletion and sign-out behavior still need submission-specific evidence; do not imply deletion erases every anonymous diagnostic/support record.
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
- Terms / EULA URL: https://useichart.com/terms.html
- Proposed Privacy Choices URL: https://useichart.com/privacy.html#data-requests
- Support URL: https://useichart.com/support.html
- Marketing URL: https://useichart.com
- Support email: support@useichart.com
- Beta feedback email: support@useichart.com

These must be real, monitored, public-facing destinations before App Review and public submission.

The Privacy Choices anchor is a local coordination proposal to be added to the
privacy page; its published availability was not verified in this update. The
Terms / EULA URL matches the app's configured legal link, not a newly selected
destination.

## Historical Deferred Operations — Not A Current Release-Gate List

Retained from the earlier draft. Reconcile these items with the current project
state/runbook before taking action; this update does not verify their live state.

- Supabase Pro upgrade is deferred until a supported payment method is available.
- After upgrade, enable leaked-password protection and revisit MFA advisor settings.
- Universal links remain a production follow-up once a stable associated domain is selected.
- Historical, superseded server-status deferral: current-status checks were then described as a follow-up after basic TestFlight purchase/restore validation, with signed StoreKit claims, App Store Server Notifications V2, app-account token binding, and replay/idempotency guards as the candidate server gate. Do not reuse this as the current runtime description: the later complimentary-offer status/history work and its remaining Apple acceptance/renewal gates are tracked in the current subscription runbook and project state. Ordinary entitlement claims and gift confirmation remain separate.
