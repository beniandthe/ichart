# Telemetry release candidate — iChart 1.2.4 (91)

Date: October 30, 2026. Working branch: `codex/telemetry-feature-contracts`.
Starting implementation/deployment checkpoint: `f56c5293` on main base `2dab8316`.
Candidate runtime, tests, disclosure copy and version/build are committed as
`9431062aa4836b1a3a8b6a396de640bba04053da` and are now pushed in
[PR #90](https://github.com/beniandthe/ichart/pull/90). **Build 91 is held from
release readiness:** the real device emitted a readback-mismatch diagnostic
that contradicts the independently exact material-preservation comparison.
The diagnostic discrepancy is under investigation. This document is an evidence
receipt, not a statement that an upload or public release occurred.

## Candidate identity and scope

- Intended bundle: `com.ichart.app`, version **1.2.4**, build **91**.
- `project.yml` is authoritative and has been updated to this candidate identity.
  The generated settings, successful Release archive and App Store export agree
  on this candidate identity.
- App Store Connect preflight reported the latest uploaded version/build as
  **1.2.3 (78)**. The connected ordinary iChart app was **1.2.3 (90)**.
- Scope: consent-safe local diagnostic checkpoint cleanup, aggregate telemetry
  and incident pipeline integration, disclosure alignment, and release checks.
- Graph/MyScript remain paused. No recognition experiments, model/SDK runs,
  raw handwriting contribution activation or App Store public release is part
  of this candidate validation.
- Runtime source commit: `9431062aa4836b1a3a8b6a396de640bba04053da`.
  [PR #90](https://github.com/beniandthe/ichart/pull/90) is open at that head.
  Final required remote CI/merge results remain to be recorded. Do not substitute
  an older tested binary or infer its source identity from version/build alone.

## Backend prerequisite — complete

The aggregate diagnostics backend is already deployed and independently
verified. Migration `20261030151740_telemetry_feature_contract_pipeline` and
`app-telemetry-ingest` version 43 are live. The actual five-minute worker ran,
synthetic failure/control cases were classified correctly, and delivery retry
and malformed-input controls passed. See the
[live backend receipt](telemetry-backend-deployment-2026-10-30.md).

That backend proof does not establish that this new device binary sends the
expected events, preserves existing content or has acceptable interaction cost.

Final independent backend checks at **16:29:46 UTC / 9:29 a.m. Pacific** passed
all **56 checks**: 25 ingest/schema, 14 task-consumer, 13 native PostgreSQL and
four workflow-scope checks. All four deployed version-43 files matched local
source. Worker health had no pending, rejected or dead-letter records, and the
ten noncritical historical tasks remained open. Device delivery counters still
had no reporting installation; that is unknown coverage, not zero loss.

Local receipts:

- `.build/telemetry-backend-final-gates-2026-10-30.json`
- `.build/telemetry-final-edge-file-comparison.json`

## Fresh physical-device baseline — complete

The full unlocked ordinary-app data-container copy completed at approximately
**16:24 UTC / 9:24 a.m. Pacific** on October 30, before installation of this
candidate. Only the confirmed main-app process, PID **2889**, was stopped.
No lab/recognizer app was stopped, installed or modified by this baseline step.

- Device: paired wired iPad13,2, CoreDevice
  `376D59F8-92F2-5260-B10E-BA0BEAF941AB`, iPadOS **26.6.2 (23G90)**.
- Installed ordinary app at baseline: `com.ichart.app`, **1.2.3 (90)**.
- Complete baseline: **62 files / 63,178,559 bytes**.
- Live-before and complete-copy library snapshots were each **1,661,027 bytes**
  and matched byte for byte.
- Baseline data remains under ignored `.build` storage; private charts, PDFs,
  ink, provisioning data and raw app metadata must not be added to Git.
- The complete baseline is a preservation reference, not authorization to
  restore it over later edits or to delete/reinstall the app.

Local evidence paths, relative to this checkout:

- `.build/release-1.2.4-91/device-backups/before-install-complete/`
- `.build/release-1.2.4-91/device-backups/before-install-inventory.json`
- `.build/release-1.2.4-91/device-backups/live-library-before.json`

The read-only inventory records the old app identity, all file counts/bytes and
the full hash manifest. Keep it alongside the untouched complete copy and
recheck it after the release validation. Do not normalize or exclude cache,
telemetry or bookkeeping changes to manufacture an exact comparison.

## Checkpoint cleanup and local checks — passed

The cleanup implementation has been independently reviewed without a
supported-path blocker. The new UI-hosted consent tests (**9**) and pure
diagnostic tests (**19**) passed in their focused runs.

The first broad SwiftPM run (**1,877 tests**) and selected simulator run
(**185 tests**) both failed on the same stale source-code assertion. Those
attempts remain failed evidence; they are not relabeled by the focused results.
The source assertion was corrected. The final selected simulator result is
**185 passed / zero failed / zero skipped**, and the final full SwiftPM log
reports **1,877 executed: 1,786 passed / 91 skipped / zero failed**. The latter
completed at 9:32:43 a.m. Pacific. Skips are retained as skips; this is not a claim
of 1,877 passing tests. These results are separate from the failed first attempts.

Final local result paths:

- `/private/tmp/ichart-telemetry-validation/PreshipFocusedFinal.xcresult`
- `/private/tmp/ichart-telemetry-validation/preship-focused-final-summary.json`
- `/private/tmp/ichart-telemetry-validation/preship-focused-final.log`
- `/private/tmp/ichart-telemetry-validation/preship-swiftpm-final.log`

The required cleanup checks include existing-checkpoint removal on opt-out,
withdrawal during background publication, stale-generation exclusion after
withdrawal/re-opt-in, launch while opted out, and retry after a cleanup failure.
The user's chart/library data must remain untouched by diagnostic cleanup.

## Signed Release archive and App Store export — complete

The Release archive completed successfully from the candidate source, and
`codesign --verify --deep --strict` passed for its ordinary app. Bundle, version,
build and expected distribution profile were verified. The packaging check found
no experimental resources. Archive success does not establish device behavior.

- Archive: `.build/release-1.2.4-91/iChart-1.2.4-91.xcarchive`
- Archive result: `/private/tmp/ichart-telemetry-validation/ReleaseArchive.xcresult`
- Archive log: `/private/tmp/ichart-telemetry-validation/release-archive.log`
- App Store IPA: `.build/release-1.2.4-91/app-store/iChart.ipa`
- App Store export log:
  `/private/tmp/ichart-telemetry-validation/release-export-appstore.log`
- IPA SHA-256:
  `77f185d3f69f567327c2fe82ef22f0241657b4c33abbd9ac1ffefb7dd01bfef1`

The first cable-QA export used `method=debugging` with manual signing and the
existing Xcode-managed development profile. Xcode rejected that combination.
Its failed log is retained at
`/private/tmp/ichart-telemetry-validation/release-export-deviceqa.log`.
It does not invalidate the successful archive or App Store export.

A distinct same-archive QA export **succeeded** with automatic signing, without
`-allowProvisioningUpdates` and without manual-only certificate/profile options.
The development profile includes the paired iPad, has `get-task-allow=true`, and
matches `N6G8X4K46U.com.ichart.app`. Archive and cable-QA binaries share UUID
`FB6B27C7-400C-301D-85BF-8170B2F53316`. They have different distribution signatures
and entitlements; binary-UUID agreement is not a claim that their signed bytes
are identical. The App Store archive/IPA remain separate and unchanged.

- Signing receipt:
  `.build/release-1.2.4-91/candidate-signing-verification.json`
- Cable-QA IPA SHA-256:
  `55192484a708e2397fbfd0467c33140afc900883b0b4541fd0ad68bc8b41fb1d`

## Physical installation and preservation — material data preserved

The cable-QA export installed in place and launched successfully as ordinary
`com.ichart.app` **1.2.4 (91)**. Complete copies were obtained before install,
after install/before first launch, and after launch. No delete/reinstall or old
backup restore was used.

Both preservation audits retain the baseline's **62 files** unchanged and report:

- **17 chart objects and their order exactly preserved**, including full chart
  fields and rendered source-ink provenance.
- The separate handwritten-ink summary is exact: **20 fields**, ten nonempty
  binary fields totaling **300,984 bytes**. This number is that summary's byte
  count; the full chart comparison independently covers `sourceInkData` fields.
- **19 PDF documents and their metadata/bytes** exactly preserved.
- **One setlist / 15 entries** exactly preserved, with valid PDF references.
- **Three profile/correction/evaluation files** exactly preserved.
- Post-launch app metadata confirms all **53 other app records** remain exact.

Strict container comparisons remain **false** and must not be reported as exact:
the prelaunch difference consists of four SplashBoard snapshot renames. The
post-launch differences include deletion-tombstone ordering, trace/preferences,
caches and snapshot renames. Tombstone records remain exact as a multiset and
all other library fields are exact. No exclusions were added to force a green
strict comparison.

Audits:

- `.build/release-1.2.4-91/prelaunch-preservation-audit.json`
- `.build/release-1.2.4-91/postlaunch-preservation-audit.json`

These preservation results do not establish interactive chart/ink behavior or
acceptable physical-device latency. The user-facing UI/consent checks are still
pending direct observations.

## Build 91 diagnostic discrepancy — release hold

The actual build-91 device sent `chart.save_readback` / `readback_mismatch` with
expected and actual chart counts both **17**, and `content_matches=false`.
Independent post-launch preservation shows the material content above remains
exact. This is a diagnostic-comparison discrepancy, not evidence that 17 charts
or their ink were lost.

The current investigation is whether whole runtime snapshot equality includes
the nonpersisted runtime access policy while the loaded snapshot reconstructs
its default. That explanation is a hypothesis until the source-level diagnosis
and regression pass are complete. The fix must preserve real older/missing/
corrupt readback detection rather than suppressing mismatches indiscriminately.

Do not certify build 91 or reuse its successful archive as proof of a corrected
detector. A source correction will require a new verified source/build, likely
build 92, with new signing and device acceptance evidence. Keep this build-91
archive, failed diagnostic observation and preservation artifacts recoverable.

## External-action and access gates

Automatic approval review initially rejected the Git push because transmitting
private repository source was not explicitly authorized. The user subsequently
approved the push; it completed normally and PR #90 is open at head `9431062a`.
The initial rejection was not bypassed. Final remote CI/merge evidence still
needs to be recorded separately from local tests.

The updated October 30 policy is now **published and read back exactly**, and
the App Store Connect privacy-answer review is complete. This publication is
separate from the candidate app and does not activate raw handwriting
contributions. The earlier IONOS sign-in gate is no longer pending.

The quiet operational monitor is active on a 15-minute cadence. Its configured
baseline contains the ten existing noncritical tasks, with healthy worker state
and unknown delivery-counter coverage kept distinct. Graph/MyScript remain
paused. The verified active monitor identity is
`monitor-ichart-telemetry-health`; its cadence is fifteen minutes.

## Release gates still pending

| Gate | Required evidence | Current state |
| --- | --- | --- |
| Integrated source and remote CI | Exact PR/head and required passing checks for the final source; no Graph/MyScript changes. | Push approved/completed; PR #90 open at `9431062a`. Final required CI/merge evidence pending. |
| Final local regression | Nonzero inspected SwiftPM/Xcode results after the stale assertion correction. Preserve failed attempts separately. | Passed: 185 simulator cases; SwiftPM 1,786 passed, 91 skipped, zero failed. |
| Release archive | Signed ordinary `iChart` Release archive from the final source with the intended bundle/version/build/team. | Complete; archive and strict signature check succeeded. |
| App Store candidate export | Verified distribution signature/profile, archive/export identity and hashes. Export is not upload. | Complete; IPA hash recorded above, no upload claimed. |
| Physical Release QA package | A separately exported development-signed package from the same Release archive, suitable for an in-place cable install. | Complete; signing/profile verified, same binary UUID, QA IPA hash recorded. |
| Install and preservation readback | In-place install; complete prelaunch/postlaunch readbacks; old chart/order/source ink, PDF/setlist and profile preservation; explicit accounting for diagnostic/cache changes. | Install/launch and material preservation passed; strict comparisons remain false as documented. |
| Device consent and delivery | Opt-out, opt-in, withdrawal, offline/retry and real release-build contract-event evidence against ingest version 43. | Device contract events arrive, but the readback detector discrepancy blocks acceptance. UI/consent/offline observations remain pending. |
| Physical chart/ink acceptance | Render, rotation, save, force-close/reopen and large-chart interaction/performance observations on the actual candidate. | Pending. |
| Disclosure publication and Apple answers | Published policy/in-app wording match aggregate collection and opaque chart correlation; App Store privacy answers checked against the implementation. | October 30 policy published with exact readback; ASC answer review completed. Raw contributions remain deferred. |
| Operational consumption | Quiet critical-finding/worker-failure monitoring and regular task review actually configured, with unchanged states kept quiet. | `monitor-ichart-telemetry-health` active/verified every fifteen minutes; Graph/MyScript paused. |
| Diagnostic correctness on device | A real persisted snapshot must compare using its durable semantics while genuine source loss remains detectable. | **Blocked:** build 91 reports a readback mismatch despite exact material preservation; investigation/fix pending. |

No TestFlight upload, App Review submission or public release is established by
this receipt. A physical launch alone is not a visual or performance acceptance
result. If any required gate cannot be completed, leave the candidate state
explicitly pending and name the precise action or evidence needed.

## Ready-state handoff requirements

Before declaring the release candidate ready, record the final source commit,
CI result, app/archive/export identities and hashes, backup immutability,
preservation results, actual device behavior/consent evidence, disclosure state
and operational monitor identity. Keep the signed App Store export separate
from its cable-QA export. Preserve any failed or incomplete attempts and the
remaining manual acceptance boundaries.
