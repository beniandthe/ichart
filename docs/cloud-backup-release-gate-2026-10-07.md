# Cloud backup/restore release gate — 2026-10-07

Candidate: **1.2.1/74**, the user-accepted Development Debug app. Active worktree:
`codex/app-release-normalization`. Scope: prove backup/restore through the real
app and legitimate account entitlement. This is not authorization to change
billing, fabricate subscription rows, weaken RLS, delete existing charts, reset
the populated iPad, deploy functions, commit, push or upload.

## Current evidence

- Fresh read-only physical-device captures of Application Support and Documents
  are retained in `/private/tmp/iChartCloudReleaseGate-20261007.caXaDh/`.
  The current library has **4 charts, 49 deletion records, 11 PDFs and 70
  handwriting examples**. Documents is empty; the successful second copy used
  an explicitly created destination directory. The original unsuccessful copy
  receipt is retained. No local restore or file replacement was performed.
- The device's telemetry installation ID was read from its preference file;
  account lookup was scoped to that installation and build **74**, not an
  arbitrary user or a project-wide customer cohort. No session token, password,
  signed StoreKit transaction or service key was retrieved.
- Read-only production SQL matched the account from the latest authenticated
  build-74 event (**2026-10-07 07:48:17 PDT**). Its subscription is **free /
  inactive / production StoreKit expired**, with expiry **2026-09-03
  14:55:14 PDT**, no grace deadline, and no revocation. The live cloud-access
  predicate evaluates false from these fields. The account has **0 active
  remote chart documents and 0 snapshots**.
- That installation/build has **6 cloud.push_started** and **6
  cloud.push_failed** events, last failure **2026-10-07 07:48:02 PDT**,
  classified only as `sync_error`. There is no recorded successful push or
  restore for this candidate. Aggregate failure telemetry alone does not
  identify the HTTP response; the inactive server entitlement is a verified
  prerequisite blocker, not a reconstructed network error message.
- The saved local library reports Pro Active. The Debug Plan Preview can set
  local entitlement without changing server authorization, so local Pro or
  enabled controls cannot certify cloud eligibility. The actual cause of the
  current local override was not inferred from the status alone.
- The live `current_user_has_active_pro()` definition and chart document/
  snapshot policies were inspected read-only. They require authenticated owner
  equality plus server plan `studioSubscription`, status `active`, no revocation,
  and an absent/future entitlement expiry. No function, policy, permission,
  subscription or stored chart row was modified.

## Restore Purchases result — prerequisite remains blocked

The user tapped **Settings → Plan → Restore Purchases**, approved Apple's
prompt, and supplied a screenshot timestamped **2026-10-07 08:00:30 PDT**.
It shows local Pro Active, Pro selected in Plan Preview, and Cloud Backup
reporting permissions blocked. No subscription purchase was requested.

The matched real-device telemetry records `subscription.restore_started` at
**07:59:33 PDT** and `subscription.restore_succeeded` at **08:00:01 PDT**, with
the actual result **plan free / subscription_status proExpired**. The event
means the StoreKit sync/refresh request completed; it does not mean an active
purchase was recovered. Read-only server recheck still reports the same
September-3 expiry, free/inactive status and false cloud eligibility.

The current `.ready` subscription state has no visible result text, so an
expired restore returns to the same panel without explaining the outcome.
Likewise the generic cloud permissions message recommends signing in again
without identifying the expired entitlement. These are evidenced UX follow-ups,
not implemented repairs or reasons to repeat sign-out/retry on this account.
Local Debug preview remains distinct from server authorization. Apple sign-in
and any future sandbox credentials stay with the user, never in chat.

If no active purchase is restored, use a legitimate Apple Sandbox test account
and sandbox transaction, after agreeing the setup and checking that the purchase
sheet explicitly identifies the test environment. Do not replace this with
Xcode-only StoreKit simulation or a manually fabricated production entitlement:
neither proves Apple's server-verified claim path. Apple documents sandbox
transactions as noncharging testing:
[Overview of testing in sandbox](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox).
No sandbox account, purchase or transaction was created in this pass.

## Existing Sandbox tester verified

After the user completed App Store Connect developer-account sign-in, its
Sandbox page showed one existing **iChart Sandbox** test account. Read-only
inspection confirmed United States storefront, the existing five-minute
monthly-renewal setting, and interrupted purchases disabled. The dialog was
cancelled without saving; no tester settings, credentials or purchase history
were changed. No tester password was retrieved or displayed.

The next prerequisite is user sign-in on the iPad under **Settings → Developer
→ Sandbox Apple Account**, followed by a separately verified Sandbox purchase
through the development-signed app. Do not sign out of the main Apple account.
Apple's current documentation notes that the Sandbox account control can appear
only after the first purchase attempt in a development-signed app. If absent,
stop at the Apple purchase/sign-in sheet and verify its Sandbox environment
before completing anything.

Source inspection confirms that the verifier supports Sandbox fallback even
when the preferred App Store environment is Production. This is code-path
evidence, not proof of the deployed claim succeeding. An accepted expired
transaction can still leave the subscription inactive; check active Sandbox
authority, future expiry and the matched account's cloud-access predicate
before proceeding. Tester existence and developer sign-in do not pass the gate.

## Real purchase result — entitlement prerequisite passed, backup still open

The user supplied the Apple purchase sheet timestamped **08:32:12 PDT**. It
explicitly stated testing-only and no charge, using the device's current Apple
account rather than the dedicated tester. After the user confirmed the test
purchase, installation-scoped telemetry recorded monthly purchase success at
**08:42:46 PDT** and Pro Active at **08:42:47 PDT**.

Read-only server verification at **08:44:39 PDT** confirmed the matched
account's `provider=storekit`, `storekit_environment=sandbox`,
`plan=studioSubscription`, `status=active`, `app_store_status=active`, expiry
**2026-10-08 08:42:40 PDT**, no grace/revocation, and true cloud-access
predicate. This proves the genuine signed Sandbox claim prerequisite; it does
not prove backup/restore. The sanitized receipt is retained as
`post-purchase-server-check.json` in the capture directory.

The same device recorded two automatic push failures at **08:42:46–47 PDT**,
with durations about **24 ms** and **16 ms**, both generic `sync_error`.
The matched account still had **0 active remote charts and 0 snapshots**.
Read-only unified logs for **08:42:40–50 PDT** showed successful claim,
subscription and auth requests, but no chart document/snapshot endpoint entries
in that queried window. This is not proof of complete log coverage or a
specific exception. A new content-free device trace was copied read-only to
`post-purchase-performance-trace.jsonl`; it confirms automatic failure backoff
around the purchase but does not record the underlying error type.

Source review found duplicate entitlement-triggered pushes can cancel an
in-flight task, and cancellation currently becomes a generic failure/backoff.
The session refresher also performs a throwing Keychain persistence operation
before chart networking. These are diagnostic candidates, not established
causes of this device failure. No app fix, weakened RLS, fabricated entitlement,
cloud mutation or retry was performed by the agent. The next bounded check is
one user-triggered manual backup with stable entitlement; manual backup enrolls
the current local library, so preserve the pre-purchase capture and do not
delete any chart for the later restore test.

## Manual backup — verified successful

The user tapped Cloud Backup retry and reported green status. Installation-scoped
build-74 telemetry records `cloud.push_succeeded` at **08:52:27 PDT** and
**08:52:44 PDT**, each with four charts and `cloud_backed_up_count=4` (about
3.75 and 2.09 seconds). Read-only server inspection at **08:54:23 PDT** confirms
four active chart documents and eight stored snapshots. All four latest
snapshot pointers resolve to an object payload with matching chart and owner.
Active genuine Sandbox entitlement remains valid.

The saved iPad library was copied read-only to
`after-manual-backup-library-state.json`. Each of the four charts was compared
with its account-scoped, pointed latest cloud snapshot using parsed JSON:
**4/4 content matches**, including the saved modern page Free Ink in one chart.
Only `cloudBackupStatus` was omitted because backup stamps it; unordered
`keyChangeSystemBreakMeasureIDs` and `tieOutSlotIndices` arrays were normalized.
Other field values and array order were preserved. No titles, chord text or ink
bytes were printed in the comparison result. Receipts are
`manual-backup-server-check.json` and `manual-backup-content-comparison.json`.

All four current charts are **Simple Chord Sheet**. This proves this candidate's
physical iPad chart backup and stored-content integrity, not Rhythm cloud
round-trip coverage, restored decoding/rendering, reinstall recovery, or complete
app-data backup. PDFs, PDF setlists, handwriting profiles and library folders
are outside the per-chart cloud payload; no claim that they were backed up is
made. No existing iPad charts were deleted or replaced.

## Clean restore client prepared — waiting for same-account sign-in

A new Simulator, **iChart Cloud Restore 74 - 20261007**, was created without
cloning or resetting any existing device. ID:
`A7BBACC9-FA55-47DB-9124-9C2B360D7258`; iPad A16 / iOS 26.5. The already-built
candidate at `/private/tmp/iChartFinalIntegrationAudit-20261006.IMApTd/SimulatorDerivedData/Build/Products/Debug-iphonesimulator/iChart.app`
was verified as `com.ichart.app` build 74, installed and launched normally through
simctl with no account/chart fixtures or Xcode StoreKit launch configuration.
Its saved library check reports zero charts and zero deletion records.

The Mac Simulator window visibly shows the signed-out account landing, now
switched from Create Account to **Sign In**. It needs the same iChart account as
the backed-up iPad, not the Apple Sandbox tester. No password, token, account or
entitlement was injected. No restore request or cloud write was initiated by
the agent. Opening the native control surface was unexpectedly slow; subsequent
inspection was bounded to ten seconds. Setup receipt:
`clean-restore-client-setup.json`. This preparation is not successful recovery.

## Safe end-to-end procedure after access is valid

1. Preserve fresh local backups. Use a QA-only client/library for two disposable
   charts, one Simple and one Rhythm, with identifiable content.
2. Back up through the app. `Back Up Now` enrolls **all** local charts; a test
   chart in a populated library does not isolate that operation. Confirm stored
   remote snapshots and expected content, not merely the green status label.
3. Restore onto a separate clean client where the test charts have never existed,
   signed into the same entitled account. A fresh Simulator can provide this
   without erasing the iPad; that proves Simulator restoration, not physical
   reinstall recovery.
4. Open, compare, relaunch and reopen the restored charts. Compare saved draft/
   free ink and musical/layout content where included in the fixture; confirm
   tombstoned fixtures do not resurrect.
5. Record exact client, input, remote receipt and persistence outcomes before
   closing the gate. Physical reinstall recovery needs a clean physical client
   or a separately authorized disposable-data reinstall pass.

Never use ordinary **Delete → Restore** as the recovery test: deleting a
cloud-backed chart creates a cloud tombstone. Restore pulls **and pushes** the
merged library, so it is a cloud write, not a read-only preview. Sign-in can
start an automatic backup but does not itself restore missing charts. Do not
delete the user's current charts or claim that unit tests prove live restoration.

Status: **the bounded chart backup/restore gate passed**: legitimate Sandbox
entitlement, physical Simple-chart backup, clean Simulator Simple restore/restart,
and first-time physical iPad Rhythm-fixture restore/persistence are verified.
Initial post-purchase automatic failures remain a recorded diagnostic follow-up;
their cause was not established or fixed by the successful manual retry. No
billing or policy mutation was performed by the agent. Recognition and learning
remain parked.

## Clean-client restore and restart — passed for four Simple charts

The user completed normal sign-in on the dedicated empty Simulator. Before
restore, its saved library still had zero charts and zero tombstones, and its
account owner matched the captured iPad owner. The agent then used the real
app's Restore Charts from Cloud control. Installation-scoped telemetry records
`cloud.restore_started` at **09:55:57 PDT** and `cloud.restore_succeeded` at
**09:56:07 PDT**, with four charts and approximately 10.53 seconds duration.
The same-owner relationship was independently confirmed through scoped server
events. Restore also pushes the merged library; this was an authorized recovery
test, not a read-only operation.

All four restored chart IDs were present. Immediate parsed per-chart comparison
against the captured iPad library returned **4/4 exact content matches**, omitting
only `cloudBackupStatus` and normalizing the two previously identified unordered
arrays. Created/updated dates, all persisted coordinates and the modern saved
Free Ink were retained in the comparison. Backup inclusion, owner, schema version
and original first-backup timestamp were validated separately.

All four charts opened into the editor without a load error. Screenshots of two
restored first pages showed rendered content; this does not certify every page's
visual geometry or every ink stroke. The app was relaunched normally via simctl.
All four chart objects still matched the iPad capture, and the chart containing
Free Ink reopened. No restored chart content, ink or coordinates were changed by
the no-edit opens. Receipts: `clean-restore-server-check.json`,
`clean-restore-content-comparison.json`, and
`clean-restore-restart-comparison.json`. No iPad charts were deleted, replaced or
edited. This is clean Simulator recovery, not physical uninstall/reinstall proof.

## Rhythm fixture — backup passed, receiving-client restore pending

Through the normal app UI on the dedicated QA Simulator, the agent created
**QA Cloud Rhythm 74 Oct 7**: Rhythm Section Sheet, eight measures, distinct typed
title/credit/style, one structured repeat span, and a small synthetic Free Ink
mark. This mark is cloud preservation input, not the user's handwriting or
recognition-accuracy evidence. The fixture was not inserted through a database
or local-library replacement.

The app uploaded the fixture normally. At **10:12:07 PDT**, its pointed latest
cloud snapshot matched the full saved chart content (same narrowly defined
comparison), including repeat and saved Free Ink. Pointer/chart/owner agreement
passed. The server now contains five active charts. Receipt:
`rhythm-fixture-cloud-comparison.json`; fixture setup state is retained separately.

The Mac locked during further native navigation; no lock or authentication
protection was bypassed. No second Mac sign-in is needed for the next check:
the already authenticated iPad can receive the QA Rhythm chart that has never
existed in its library. A fresh read-only pre-restore iPad capture is saved as
`before-rhythm-restore-ipad-library-state.json`. It still contains four charts,
all matching the earlier captured chart content; no QA Rhythm fixture is local.
The next user step is Settings -> Cloud Backup -> Restore Charts from Cloud,
then open the distinctly named QA Rhythm chart. Afterward compare the new chart
and verify the original four remain unchanged. Do not delete an existing chart,
purchase again, reset the iPad, or call the gate passed before that check.

## Physical iPad Rhythm restore — passed for the defined fixture

The user restored the QA chart, opened it, checked the staff/repeat/ink, and
reported **“done all green.”** Installation-scoped build-74 telemetry records
`cloud.restore_started` at **12:14:46 PDT** with four local charts and
`cloud.restore_succeeded` at **12:14:51 PDT** with five (approximately 5.88 s).
A subsequent push succeeded at **12:15:08 PDT**, with all five backed up. At
12:16:55 PDT, the account had five active cloud documents and five valid latest
snapshot pointers. These reads were scoped to the tested iPad installation.

Fresh saved iPad content is retained in
`after-rhythm-restore-ipad-library-state.json`. Direct comparison of the actual
before/after files proves **4/4 original chart objects unchanged**, excluding
only backup stamps and normalizing the same two unordered arrays. All **49
deletion tombstones** and projects are unchanged; no unexpected chart was added
and no deleted chart resurrected. Included backup intent, owner, schema and
original first-backup date are preserved for all five charts.

The restored Rhythm fixture matches its QA source in every field except the
Free Ink archive encoding: **598 -> 620 decoded bytes**. The actual PencilKit
drawings were decoded using a read-only Swift helper, not judged by archive
length alone. Both contain **3 strokes / 5 path points**. Exact comparison passed
for point positions, times, dimensions, opacity, force, azimuth, altitude,
transforms, masks, random seeds, creation dates, render bounds, drawing bounds,
ink type and RGB/alpha. Persisted coordinate space is also exact. This supports
safe PencilKit reserialization, not ink movement or loss. The app decoder
reserializes valid nonempty ink through its existing normalization path.

The existing app was normally relaunched on the iPad (no build, reinstall,
fixture/auth injection or deletion). All **5/5 saved chart objects** then matched
the immediate post-restore capture, including encoded ink; tombstones and
projects remain unchanged. This verifies saved persistence after restart, not
a second human visual reopening of every chart. The QA chart remains in place.

Receipts: `rhythm-restore-ipad-server-check.json`,
`rhythm-restore-ipad-content-comparison.json`,
`rhythm-restored-ink-geometry-comparison.json`, `rhythm-ipad-relaunch.json`, and
`rhythm-ipad-relaunch-content-comparison.json`. The first transient cached-value
comparison was replaced by the authoritative direct-file comparison;
an independent direct-file check also found all four originals unchanged.

Coverage boundary: this Rhythm fixture has a header, eight measures, one repeat
span and saved Free Ink, but **no chord events, pitched notes, rhythm maps or
pending chord draft**. It proves the defined basic Rhythm-chart recovery, not
all possible musical-content combinations or handwriting recognition accuracy.
Simple charts provide the populated chord/layout recovery evidence. Physical
uninstall/reinstall recovery, PDFs, PDF setlists, handwriting profiles and
library-folder cloud backup remain outside this gate. The earlier automatic
post-purchase push failures and misleading restore/permission messages remain
recorded follow-ups; this pass did not establish or fix their causes.

No app code, billing, RLS, function deployment, commit, push, distribution archive
or upload occurred in this confirmation pass. Recognition research remains parked.
