# Telemetry release candidate — iChart 1.2.4 (92)

Date: October 30, 2026. Working branch: `codex/telemetry-feature-contracts`.
**Status: release held for an unresolved physical ink-disappearance report;
build-92 packaging and validation are also pending.**

`project.yml` now declares ordinary bundle `com.ichart.app`, version **1.2.4**,
build **92**. Its Release archive has started; no completed build-92 archive,
export, signature verification, installation or physical acceptance result is
established by this receipt. The runtime source is frozen pending physical
retesting. Its final commit must be recorded before an artifact can be
associated with that exact source.

## Why build 92 is required

[Build 91 is held](telemetry-release-candidate-1.2.4-91-2026-10-30.md): its actual
device sent `chart.save_readback` / `readback_mismatch` with expected and actual
chart counts both 17 and `content_matches=false`, despite independent material
preservation of the existing charts and ink. Its signed packages, successful
installation, baseline and readbacks remain historical evidence. They do not
validate the build-92 correction.

The whole-snapshot comparison defect has now been reproduced with a real
`FileChartRepository`: persisted billing fields round-trip exactly while the
intentionally nonpersisted runtime `AppEntitlements.accessPolicy` differs. The
regression failed on three assertions before the correction. After the narrow
helper was implemented, all **23 diagnostic XCTest cases passed, zero failed**;
an independent source review also passed. The final XCTest suite is nonzero;
the separate Swift Testing footer with zero tests is not the validation result.

Passing run: `/private/tmp/ichart-checkpoint-readback-after-fix.log`.

This establishes the local comparison defect and its regression fix. The actual
runtime access-policy value on build 91 was not captured, so it is still an
unproven explanation of that device's mismatch event. No corrected-device
observation exists yet.

The implemented correction compares the encoded, persisted entitlement fields
before ignoring **only** the nonpersisted runtime access policy in the otherwise
strict snapshot comparison. Chart data/order, source bytes, project data/order,
selection, cloud metadata, billing evidence and tombstone records/order remain
strict. It must continue detecting older, missing, reordered or corrupt durable
readbacks. No tombstone sorting, whole-snapshot decoder normalization or broad
mismatch suppression is part of the intended exception.

## Physical ink disappearance — release blocker

The user reported that, "as writing went on, ink got worse" and was "popping
in/out," then clarified that it "just disappeared as writing" and described
the "writing too fast issue again." The confirmed mode was **Write & Render**
on the installed build-91 app. This remains a physical release blocker,
regardless of the passing local diagnostic tests or the earlier
material-preservation comparison. A targeted telemetry scheduling correction is
implemented below, but physical acceptance with diagnostics enabled is not
established.

A complete live app-container capture was copied to ignored local storage:

`.build/release-1.2.4-91/device-backups/ink-pop-in-out-live-capture/`

The captured trace shows serialized source counts progressing **3 → 7 → 13 →
24**, no synchronous library loads after the initial load, and **six committed
source attachments** by capture time. Those facts establish what reached the
captured persistence trace. They do not prove continuous visibility of the ink,
establish a cause, or invalidate the user's observed disappearance. Preserve the
capture without adding its private contents to Git.

For the controlled diagnostics-off comparison, the user reported **"Stable with
diagnostics off."** This associates the observed behavior with the diagnostics
setting in that physical comparison; it does not by itself identify the exact
stall or prove the correction below fixes enabled writing. The corrected
candidate must remain stable during rapid writing with diagnostics **enabled**
before this blocker can close.

## Telemetry scheduling correction and local evidence

The static telemetry entry points previously read the authoritative consent
snapshot through the same lock that orders queue/checkpoint disk I/O with
withdrawal. Caller-side admission could therefore wait for that I/O-bearing
lock. `record`, `isRecordingEnabled`, `flush` and pending-flush scheduling now
read a separate cached consent/generation token under a short lock that performs
no I/O and never acquires the authoritative lock.

The cache is advisory for scheduling only. The telemetry actor still validates
the authoritative consent generation before persisting or sending, and the
existing atomic withdrawal/checkpoint protocol remains intact. An independent
review of this separation passed. The legacy `recordPersistedInkTelemetry`
caller also now checks consent before decoding or inspecting source ink, so
that diagnostic content capture is skipped while diagnostics are off.

Six new `TelemetrySchedulingConsentTests` cover actual blocked queue append and
checkpoint I/O, off-state visibility while withdrawal cleanup is blocked,
generation transitions/stale work and authoritative validation of direct
preference withdrawal. The final native run including these six tests and the
progressive-ink boundary case completed with **196 passed, zero failed, zero
skipped**, as verified from the result bundle and summary:

- `/private/tmp/ichart-telemetry-validation/Build92FinalFocused.xcresult`
- `/private/tmp/ichart-telemetry-validation/build92-final-focused-summary.json`

The prior full SwiftPM run for the narrow persisted-comparison correction
completed with **1,881 executed: 1,790 passed, 91 skipped, zero failures**. It
does not cover the subsequent UIKit scheduling/guard changes or the six new
native tests; the inspected 196-case native run supplies that separate
validation. Log:

`/private/tmp/ichart-telemetry-validation/build92-swiftpm.log`

`ProgressiveInkVisibilityBoundaryTests` separately passed **one simulator case**,
covering light and dark appearances and progression from 3 to 24 source strokes,
with source preserved and 44 records of actual ancestor state. This checks the
boundary represented by that test; it contains no explicit raster-continuity
proof and is **not proof that physical flicker is fixed**. It also passed as
part of the final 196-case native run.

- `/private/tmp/ichart-progressive-visibility-boundary.xcresult`
- `/private/tmp/ichart-progressive-visibility-boundary-summary.json`

The build-92 Release archive is in progress; its result is not yet recorded:

`/private/tmp/ichart-telemetry-validation/ReleaseArchive92.xcresult`

No build-92 installation has occurred. Physical enabled-writing acceptance
remains required after verified packaging, a fresh complete backup and the
corrected candidate's verified in-place installation.

## Evidence that remains applicable

The deployed backend, disclosure review and operational monitor have separate
receipts and do not need a new deployment merely because this local comparison
changes:

- [Backend deployment and verification](telemetry-backend-deployment-2026-10-30.md).
- [Published October 30 policy and App Store Connect disclosure review](telemetry-privacy-disclosure-review-2026-10-30.md).
- [Verified monitor configuration and historical build-91 gates](telemetry-release-candidate-1.2.4-91-2026-10-30.md#external-action-and-access-gates).

Graph/MyScript remain paused. Raw handwriting contributions remain plan-only.
These prerequisites do not establish build-92 event correctness, physical
behavior or delivery through the existing backend.

## Source and review identity

[PR #90](https://github.com/beniandthe/ichart/pull/90) remains open at
`9431062aa4836b1a3a8b6a396de640bba04053da`, the build-91 source, while the correction
and new push are pending. Required remote checks against that old head cannot
certify the build-92 working tree. Record the new exact commit, PR head and
required CI outcomes after the corrected source is committed and pushed.

No build-91 test total or signed package is relabeled as a build-92 result.

## Fresh device baseline required

The ordinary app currently has the build-91 installation and subsequent user
activity may have changed its library. Before any in-place build-92 installation,
take a **new complete, unlocked app-container backup** and read-only inventory,
verify the live library against that complete copy, and record the current
bundle/version/build and mode. Preserve all charts, ink, PDFs, setlists and
other content added or changed since the build-91 baseline.

Keep the build-91 baseline/readbacks immutable and recoverable. Do not reuse
its older baseline as the new current-data backup, restore it over newer edits,
or delete/reinstall the app. Keep private container data and hash manifests in
ignored local evidence storage.

The user has confirmed switching diagnostics off and on and stable writing in
the controlled diagnostics-off comparison. These are the confirmed physical
observations; full withdrawal/cleanup, offline/retry and relaunch acceptance
have not been established. Physical build-91 feedback must retain its actual
build identity. Physical chart/ink and consent acceptance of the corrected
candidate requires build-92 observations after its own verified install, and
the reported ink disappearance must be resolved first.

## Gates and current state

| Gate | Required evidence | Current state |
| --- | --- | --- |
| Reproduction and diagnosis | Real file-repository regression fails before the narrow correction; source tracing explains what differs. Distinguish that reproduction from device proof. | Local defect reproduced with three failing assertions before fix; actual build-91 runtime value/cause remains unproven. |
| Corrected comparison | Persisted entitlement equality permits only the runtime access-policy difference; genuine source/order/billing/metadata/tombstone differences remain violations. | Implemented; 23 diagnostic XCTest cases passed, zero failed, and independent source review passed. |
| Telemetry scheduling and off-state capture | Caller scheduling avoids the I/O-bearing consent lock; authoritative actor validation and atomic withdrawal stay intact; opted-out legacy ink capture is skipped. | Implemented and independently reviewed; six new native scheduling/consent tests passed in the final native run. Physical enabled-writing verification remains pending. |
| Final local checks | Relevant diagnostic and consent tests, final nonzero inspected native results and appropriate broader regression after the correction. Retain failures/skips separately. | Passed: final native 196/zero failed/zero skipped. Narrow-comparison SwiftPM run: 1,881 executed, 1,790 passed/91 skipped/zero failed. Independent one-case progressive-boundary simulator run also passed; none is physical flicker proof. |
| Final source and remote review | Exact committed/pushed source and PR head with required remote checks. | PR #90 still has build-91 head `9431062a`; corrected source/push/CI pending. |
| Fresh complete backup | New current-data baseline, inventory and matching live-library read; immutable older backups preserved. | Required before build-92 installation; not yet recorded. |
| Signed Release archive | Ordinary Release archive from the corrected source, bundle/version/build/team/profile verified, strict signature check and experimental-resource audit. | Build-92 archive in progress; result and signing evidence pending. |
| Distribution and cable-QA exports | Separate App Store and same-archive device-QA exports, verified entitlements/profile, artifact hashes and shared binary identity. | Pending; build-91 exports remain build-91 evidence. |
| In-place install and preservation | Correct candidate identity; complete prelaunch/postlaunch readbacks compared against the fresh baseline; material preservation and strict-container outcomes reported separately. | Pending. |
| Real-device diagnostic correctness | Correct durable readback yields the expected passing event; genuine regression cases remain detected by validated tests. Confirm delivery and classification against the existing ingest. | Pending; no corrected-device result yet. |
| Physical ink continuity | Diagnose and fix the user's Write & Render ink popping/disappearance; obtain controlled rapid-writing and persistence observations on the corrected candidate. | **Blocked:** build-91 writing was stable with diagnostics off. Targeted scheduling correction implemented; no corrected enabled-device result yet. Trace and simulator boundary checks do not prove visual continuity. |
| Physical consent and chart/ink acceptance | Opt-out, opt-in, withdrawal, offline/retry; chart render, rotation, save, force-close/reopen and interaction/performance observations on build 92. | Diagnostics off/on and diagnostics-off writing stability confirmed on build 91. Full acceptance remains pending; enabled-writing stability is required. |
| Existing backend, disclosure and monitoring | Preserve the verified prerequisites above; refresh live health as needed and record any material change. | Existing receipts apply; they do not replace candidate validation. |

Before reporting readiness, replace pending entries with exact source/artifact
identities and inspectable results, account for every preservation difference,
and record the actual physical acceptance boundaries. A successful archive or
launch alone is insufficient. No TestFlight upload, App Review submission or
public release is established by this receipt.
