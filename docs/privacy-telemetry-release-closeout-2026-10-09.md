# Privacy and telemetry closeout — October 9, 2026

Status: approved telemetry configuration deployed; native delivery and the user's
short physical checklist passed. Publication and timed server/Apple checks
remain open. This is a bounded release closeout, not a recognition iteration or
a full security/compliance certification.

## What changed

- The user explicitly approved the telemetry-only retention/deletion migration.
  It is deployed in project `pausvvwoazbvmzyrebwl`, recorded as version
  `20261009230003`, name `telemetry_privacy_retention_closeout`.
- Daily cleanup is configured to delete events whose **server `received_at`** is
  more than 180 days old. A daily job is not an exact maximum age: a record can
  remain until the next successful run. Client `occurred_at` does not decide age.
- Deleting an Auth account now cascades to telemetry **still linked to that
  account**. Another account's events and anonymous events on the same
  installation are preserved. Records already unlinked by the historical
  `SET NULL` rule cannot be reconstructed or automatically attributed.
- No purge or account deletion was invoked during deployment. Charts, PDFs,
  subscriptions, authentication handlers and the offer campaign were not edited.

The local migration filename was aligned to the version assigned by the
deployment tool, without changing the tested SQL. SHA-256:
`1d0f2095dc04f898f670f85955dc73c79e30f3b9398be9228d00ad5ecae0117d`.

## Live configuration evidence

The read-only preflight at **22:59:23 UTC** showed the old validated `SET NULL`
foreign key, no job with the proposed name, pg_cron 1.6.4, GMT timezone, and
**zero events older than 180 days**. The earlier bounded catalog search found no
job whose command named the telemetry table or helper; it cannot exclude an
external scheduler or an indirect wrapper.

Read-only verification at **23:00:51 UTC**, after successful application:

| Check | Observed result |
| --- | --- |
| Owner foreign key | `ON DELETE CASCADE`, validated |
| Raw-table RLS | Enabled; anonymous/authenticated SELECT, INSERT and DELETE denied |
| Purge helper | SECURITY DEFINER, `search_path=private`, NULL guard present |
| Helper execution | Anonymous/authenticated denied; service role allowed |
| Retention job | Exactly one named `ichart-telemetry-retention-180d`, job ID 3, active |
| Schedule/command | `15 3 * * *` in GMT; `select private.purge_old_telemetry_events(180);` |
| Expired events | Zero |
| Actual job runs | Zero observed; scheduler execution is not yet proven |

The first scheduled boundary after deployment is **October 10, 03:15 UTC /
October 9, 8:15 PM PDT**. Check this job's `cron.job_run_details` after that
boundary. Inspect status/message before calling cleanup operational; do not
force deletion or change a schedule just to obtain a passing receipt.

Before/after Supabase advisory results are unchanged. The no-RLS-policy INFO
for the server-only telemetry table is paired with denied client privileges,
not repaired by exposing client access. The existing MFA-options WARN remains
outside this patch. No full security sweep is claimed.
[RLS advisory reference](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[MFA reference](https://supabase.com/docs/guides/auth/auth-mfa).

## Local verification

- **11 synthetic PostgreSQL tests passed**, zero failures/skips, executing the
  unchanged foundation and closeout SQL in pinned PGlite 0.5.8. Covered exact
  cutoff, signed-out retention, NULL/minimum guards, permissions, linked-only
  cascade, deletion rollback, replay, and atomic failure with unavailable Cron
  registration. The Cron adapter registers jobs only; it is not a live daemon.
  Synthetic Auth rows are not the Supabase Auth service.
- **31 ingest/account regressions passed**, zero failures/skips. These are
  sanitizer/handler tests, not live account deletion or actual job execution.
- **38 focused native tests passed**, zero failures/skips, verified through
  `xcresulttool`. They include report sanitization/runtime checks and source/UI
  wiring checks, not physical Pencil acceptance. The initial run had 37 passes
  and one obsolete assertion requiring the old help wording; its failed receipt
  is retained separately. The assertion was updated and the full selection rerun.
- Privacy manifest lint, XcodeGen generation and diff whitespace checks pass.
  Existing CoreText/accessibility/toolchain warnings are not called resolved.

Private logs and xcresults: `/private/tmp/iChartPrivacyCloseout-20261009.MmulkZ/`.
Reproduce the SQL tests using `scripts/test_telemetry_privacy_retention.mjs` and
`ICHART_PGLITE_MODULE_PATH` pointing to the pinned PGlite 0.5.8 ESM entry. No repo
or global dependency was added. The native selection is
`PrivacyControlsIntegrationTests`, `PerformanceTracePrivacyTests` and
`ProjectConfigurationTests`.

## Disclosure boundaries and remaining decisions

The user approved the manual support-data policy after reviewing this closeout:
keep manually submitted messages/reports only as needed for resolution and
follow-up, and honor verified deletion requests except required legal/security
records. The local policy draft now includes it. This is a support-operation
policy, not a new automated email purge or a claim that local unshared reports
are erased by the telemetry job. No mailbox was inspected or changed.

Automatic telemetry in the updated app is default-off and opt-in. Withdrawal
stops new collection/sending, starts unsent-queue cleanup and resets identifiers;
already-sent requests may finish. Received records are not erased by the switch.
Older distributed versions lacked this switch. The local policy draft now
distinguishes those versions rather than promising retroactive consent controls.

Local support reports are separate: the recorder does not automatically upload
them, and the user explicitly chooses to share. Their export removes raw uptime
but retains diagnostic context, potentially including identifiers/error details.
It is not universally content-free. The help copy now says **“Timing and
diagnostic context”**, and the local manifest declares Customer Support, linked,
nontracking, for App Functionality. The proposed matrix contains ten types.
This declaration changes no collection behavior. The native edits have now been
signed, installed and normally launched. The user subsequently reported both
short physical passes successful, within the scope recorded below.

Apple's [App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/)
requires reviewing the actual collection channels; optional consent alone does
not exempt ongoing account-linked telemetry. The local policy includes the
approved daily-retention and linked-account-deletion scope, and a Privacy Choices
anchor. Its publication remains on hold. App Store Connect labels were not
refreshed because of the saved browser-access restriction; the local matrix is
not a live store update.

Before privacy publication:

1. Confirm the first real cleanup result; preserve any failure evidence. Actual
   account-service deletion has not been exercised by this pass, and the user's
   account must not be deleted to manufacture evidence.
2. Refresh App Privacy and coordinate the public policy with the consent-enabled
   app; the small native disclosure delivery and short physical acceptance are
   now recorded below. Policy publication,
   store writes and upload need their own recorded authorization/outcome.

Then continue final candidate checks and the existing October 10 Apple purchase
boundary. The complimentary campaign remains inactive. No new
purchase, recognition/profile change, GitHub push, archive or upload occurred.

## Native privacy delivery

The focused privacy source was built with cached pinned packages and the
existing Development identity, without a version bump or store upload.

- `1.2.1 (75)` device build succeeded. Strict signature verification passes;
  the valid Development profile binds the expected team, app and connected iPad.
  Existing deprecation/AppIntents warnings remain.
- Install and normal-launch JSON receipts both report success. The launch
  executable matches the installed bundle; no diagnostic/purchase arguments or
  environment flags were supplied. The initial CLI launch rejected an empty
  environment argument before launching; omitting that parameter fixed the
  invocation, without an app change or reinstall.
- The bundled Customer Support declaration and complete privacy manifest match
  the tested local source. Manifest SHA-256:
  `ab3d5b9ae5283d14ec0a00e70881ea36808eb4c2e29d3e0af3803cad459a480a`.
  New signed executable SHA-256:
  `034f0007814bce0040f6d945211f24f57e13df059682b664eb6e118590779192`.
- Initial and settled-startup snapshots retain the 19-file inventory and preserve
  five charts/source ink, 11 PDFs, setlists and parked profile/evaluation/correction
  data. Selected chart and core access fields remain unchanged, with saved Pro
  active. Diagnostic trace and sync/verification metadata changed during normal
  startup; strict full-entitlement/full-state identity is not claimed. This is
  not a new Apple/server entitlement verification or physical UI pass.
- The prior signed app bundle was copied intact before reusing its build cache;
  its original executable hash still matches the previous delivery receipt.
  No uninstall, data reset, account change, purchase or profile teaching occurred.

Private delivery receipts: `/private/tmp/iChartPrivacyDelivery-20261009.qDJFmt/`.
They include `PrivacySignedDeviceBuild.xcresult`, `install.json`,
`normal-launch.json`, before/initial/settled app-data snapshots,
`settled-content-comparison.json`, `settled-delivery-verification.json`, the prior
bundle, and public provisioning metadata.
Public policy/store labels remain unchanged.

## User-reported physical acceptance — October 9

After this exact privacy delivery, the user replied **“Both passed”** to the
short checklist for Simple Chord Sheet and Rhythm Section Sheet:

- Settings → Privacy: diagnostics control and Terms/Privacy links accessible;
  sharing left at the user's preference.
- Write chords, review/correct using keyboard and Scribble, and scroll review
  where it overflows without drawing ink.
- Render, save, reopen and export a PDF.
- Make a small Free Ink mark, rotate, and check its position.

This closes the requested short physical acceptance gate for `1.2.1 (75)`.
It is the user's report, not an independently instrumented interaction or
performance measurement. It does not establish dense-page responsiveness,
general handwriting accuracy, a live retention-job run, end-to-end account
deletion, Apple offer fulfillment, public policy/store updates or distribution.
No additional handwriting study, teaching or purchase was requested.
