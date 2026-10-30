# Telemetry privacy disclosure alignment

Date: October 30, 2026. Scope: the ordinary aggregate diagnostics release on
`codex/telemetry-feature-contracts`. Graph/MyScript and raw handwriting
contributions remain paused/plan-only. This review changes disclosure text,
not collection consent, backend permissions, retention policy or research use.

## Source and publication state

Read live on October 30:

- [Current iChart privacy policy](https://useichart.com/privacy.html), showing
  an October 15, 2026 update and the current free-Pro/Basic-preservation terms.
- [Apple App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/),
  including collection, identity linkage, optional-disclosure conditions,
  Product Improvement Programs and the data-type/purpose definitions.

The local `public-site/useichart/privacy.html` was still an October 9 draft
with superseded paid-Pro wording. Its unrelated account/access/billing text
was reconciled to the observed live policy before adding the narrow diagnostics
clarification. The reviewed file is dated October 30 and was published through
IONOS's existing file editor on October 30. Only `privacy.html` was saved; no
other site files from this older checkout were published. The existing
`/privacy` route was verified in Chrome to redirect to `/privacy.html` and show
the October 30 policy. The `/privacy/` fallback does not need a separate body.

The parent inspected the signed-in App Store Connect App Privacy page on
October 30. It showed answers published thirteen days earlier with eleven
collected types, including Other Usage Data in addition to the ten types in
the local manifest. User ID, Device ID, Product Interaction, Performance Data
and Other Diagnostic Data are linked to the user and used for App Functionality
and Analytics. Other Usage Data is linked and used for App Functionality only.
Name, Email Address, Customer Support and Other User Content are linked and
used for App Functionality; Purchase History is linked and used for App
Functionality and Analytics. No tracking label was shown. The existing policy
URL is `https://useichart.com/privacy`; no separate Privacy Choices URL was
shown. No App Store Connect answer was changed by this work. The new aggregate
counts/check outcomes fit the existing identifier, interaction and diagnostic
disclosures; no new answer change was identified for this release. This is an
observed disclosure comparison, not a legal-compliance certification.

## Text updated

- In-app diagnostic explanation names chart references that connect technical
  checks for the same chart on the installation, ink counts/data sizes, and
  save/reopen/render/rotation check outcomes. It retains account linkage,
  opt-in and the exclusion of musical content and source-content hashes.
- The public-policy draft explains the opaque per-installation chart reference,
  operation/batch linkage, measured counts/sizes and local comparison outcomes.
  It does not describe pseudonymous identifiers as anonymous.
- The draft distinguishes local diagnostic checkpoints from uploaded reports.
  Local chart identifiers and source fingerprints stay on the iPad; only
  permitted aggregate observations leave it. The withdrawal paragraph includes
  checkpoint cleanup. The parent subsequently reported the coordinated cleanup
  gate passed: nineteen persistence-diagnostic tests and nine checkpoint-consent
  tests, including withdrawal during a write and preservation of library bytes.
- The service can retain technical issue status/fix summaries after their raw
  evidence is deleted. The draft discloses that distinction while retaining the
  daily 180-day raw-event cutoff, linked-account deletion scope and deletion
  request route. It does not promise an exact maximum age or deletion of
  already received records merely by turning the switch off.
- Version-specific legacy telemetry and manually shared performance/support
  report boundaries remain explicit. Ordinary diagnostics and backup permission
  do not authorize recognition research or training with saved handwriting.

## App Store privacy review target

Apple treats off-device retained data as collected and asks whether it is linked
via an account, device or other details. Optional opt-in alone does not establish
the Product Improvement Program disclosure exception: the program must also
meet its no-identity-linkage and other conditions. These diagnostics can be
linked to an account and installation, so review them as linked collection.

| Implemented diagnostic information | Existing manifest data type/purpose to confirm in App Store Connect | Interpretation |
| --- | --- | --- |
| Signed-in account identity and random installation/session identifiers | User ID and Device ID; linked, nontracking; App Functionality and Analytics | These types were already declared. Confirm the actual account/device linkage answers instead of describing the identifiers as anonymous. |
| Opaque chart reference, operation/batch reference, failure category, local-comparison outcome, source attachment/stroke/point counts and byte sizes | Other Diagnostic Data; linked, nontracking; App Functionality and Analytics | Technical chart correlation does not send the chart's title, chord text, original chart UUID or raw ink. It is part of the diagnostic payload, not a new raw-content contribution channel. |
| Save/readback/recognition/review timings and diagnostic performance context | Performance Data; linked, nontracking; App Functionality and Analytics | Confirm against all automatic and explicitly shared reporting paths; a timing field does not make the rest of a support report timing-only. |
| Tool/mode use, review/render results and correction categories | Product Interaction; linked, nontracking; App Functionality and Analytics | Workflow outcomes are not independent labels of what a user intended to write. |
| Local checkpoint chart IDs, source fingerprints and comparison baseline | Not themselves off-device collection in this implementation | They remain local. Uploaded derived counts/outcomes are covered above. Opt-out cleanup and generation-safe writes must pass the client gate. |

The existing privacy manifest declares ten types; the live store also has an
Other Usage Data entry as described above. No new raw handwriting data
type was added by this aggregate diagnostics change. The complete existing
manifest remains the full-app review baseline, including collection outside
automatic diagnostics:

| Existing declared type | Linked | Tracking | Existing declared purposes |
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

Do not remove the existing Other User Content or Customer Support declarations
because automatic telemetry excludes raw content: cloud/forum features and
explicit support sharing are separate collection channels. Do not treat those
existing declarations as contribution consent or as permission to repurpose
backups for recognition work. Actual store-answer changes depend on the live
answers and the final release implementation.

## Release checks and evidence

1. Run `PrivacyControlsIntegrationTests` on the final source, alongside the
   behavioral consent/transport/checkpoint tests. The source checks cover the
   disclosure connection; they do not replace consent-race or device evidence.
2. Verify the final in-app privacy description is readable in the Release app
   and links to the published policy. Sharing starts off on a new installation
   and refusal/withdrawal does not remove normal app features.
3. Confirm checkpoint removal after withdrawal, including an in-flight write,
   process restart and opt-out/opt-in generation changes. Chart/ink data must
   remain intact. The checkpoint cleanup agent owns these runtime checks.
4. The parent reviewed live App Store Connect privacy answers as recorded above.
   Retain its observed-answer evidence with the exact candidate receipt. No
   store-answer update was required by this aggregate diagnostic change, and
   this work performed no App Store Connect write.
5. Publish the reviewed policy through the authorized hosting workflow and
   verify the live October 30 text. A local HTML edit or policy publication
   does not itself establish collection consent or matching store answers.

Static validation: Swift syntax parsing, HTML structural parsing, manifest plist
lint and diff whitespace checks are recorded by this task. The initial sandboxed
SwiftPM test attempt could not compile its manifest because the user-level
Clang module cache was not writable; no tests executed in that attempt. The
parent is coordinating the final native/Release test run.

## Single-file publication preparation

Existing release records identify IONOS Webspace Explorer as the legitimate
hosting workflow. No CLI/SFTP credentials were found or substituted. A fresh,
cache-busted public HTML fetch on October 30 captured an exact rollback file:
8,650 bytes, SHA-256
`a2dbb9af2e4c951b0a00ce809522f98b826fa072c29768b2122365a93105cb85`,
dated October 15. This matches the preserved prior approved publication.

The reviewed candidate is 10,362 bytes, SHA-256
`16f3fa2e00d7e809160c5bc1a83b384d0e9990975675b24e6bf976de49771079`,
dated October 30. Both are named `privacy.html` in separate before/candidate
directories so a rollback cannot accidentally upload under a different name.
Preparation artifacts and the exact publication/rollback checklist are under:

`/Users/benirossman/.codex/visualizations/2026/10/30/01a18d3a-4ef7-70f1-865b-2968d97b4810/privacy-publication/`.

The initial IONOS login required user handoff after automatic approval review
rejected a password-page interaction as potentially submitting a sign-in
without explicit authentication approval or supplied credentials. No password
was submitted by this work and no alternate credential route was attempted.
The user subsequently signed in, and the correct IONOS Web Hosting Plus
Webspace Explorer root was verified. Its existing `privacy.html` was 8.45 KB,
dated October 17, with permissions `604`. A fresh public fetch reconfirmed the
exact rollback hash above. Baseline hashes for the other five public root files
were saved before upload.

The documented file chooser flow rejected the selected local candidate because
the ChatGPT browser extension did not have "Allow access to file URLs" enabled.
No file was transferred and no extension permission was changed. The upload
overlay was closed. The existing `privacy.html` action menu provided a normal
Edit action, so the approved policy was pasted into that built-in IONOS editor.
Copying the complete editor selection back before Save matched the candidate
exactly, including all 10,362 characters. Only that file's Save was invoked.

Fresh public readback at 16:37:20 UTC on October 30 matched the candidate
byte-for-byte and had SHA-256
`16f3fa2e00d7e809160c5bc1a83b384d0e9990975675b24e6bf976de49771079`.
The public page showed "Last updated: October 30, 2026" and the new technical
diagnostics text. Comparison against the pre-publication baseline found only
`privacy.html` changed among the six public root files: `index.html`,
`styles.css`, `support.html`, `terms.html` and `verify.html` retained their exact
hashes. The hosting directory showed `privacy.html` at 10.12 KB, updated October
30 at 09:36:38 AM local time, with its existing `604` permissions. No route,
asset, other file or permission was edited.

The rollback file above remains available. If rollback is required, open only
the root `privacy.html` Edit action, replace its complete contents with
`before/privacy.html`, verify the editor copy, Save, and freshly read back the
old exact hash. The upload route is unnecessary while its Chrome permission is
disabled.

Publication artifacts include `after/privacy.html`,
`before/public-file-hashes.json`, `after/public-file-hashes.json`, the
before/after hosting-directory screenshots, and `after/public-policy.jpg`.
The latter is browser proof of the publicly displayed October 30 date. The
public policy tab was retained as a deliverable; the hosting session was left
open for the user.
