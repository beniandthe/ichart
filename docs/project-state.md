# Project state and next Apple build

Updated: 2026-10-15. This is the current release handoff. Historical reports are
evidence for their recorded revisions, not an automatically expanding backlog.

## Current change: free Pro while the app is stabilized

- User decision: every legitimate account receives all shipped Pro features free,
  with no checkout, trial deadline or automatic conversion to paid. Normal account
  confirmation and account-safety requirements remain. Returning to paid access
  requires advance customer notice and an explicitly confirmed paid subscription;
  this is not a date-based trial or the previous complimentary-month campaign.
- Implementation branch: `codex/free-pro-access-2026-10-15`, based on verified
  `main` at `025d2ce50489215cfd4baa5de341ff99b02623fa`. Current source candidate is
  **1.2.3 (77)**, as explicitly requested on October 15. Build 76 was reported
  ready in TestFlight; preserve that artifact,
  but it does not contain this free-access change. Build 77's new version metadata
  passed all 2,403 native tests / 0 failures / 103 existing skips; 36 focused
  configuration/copy tests passed without failures or skips. The intended
  Simulator bundle reports 1.2.3 (77) and visibly launches to the account screen.
  The development-signed build was installed over 76 and launched on the wired
  iPad, with its new version/build read back from the device. A signed Release
  archive and local App Store IPA export also succeeded. Archive and exported-app
  strict signatures and exact version/build metadata were verified; this is not
  an upload. Physical user acceptance and Apple build-number availability/upload
  remain unverified. No existing charts, accounts or subscriptions were deleted.
  Before/after iPad snapshots verify exact chart, PDF, setlist and parked-profile
  preservation; only the append-only performance log grew. The private archive,
  export and preservation receipts are retained under
  `/Users/benirossman/.local/share/ichart/release-candidates/2026-10-15-free-pro-1.2.3-77`.
  IPA SHA-256: `eb8905ac4818d9f3be7ca952cafc7cad809d6239cfb3c6464d0326a9c4abcd39`.
  Exported Release entitlements have the expected team/bundle and
  `get-task-allow=false`; compiler warnings remain in the archive log.
- Runtime feature access is separate from truthful subscription state. Existing
  billing records and Apple receipt/notification verification are not rewritten.
  Local chart limits are removed; cloud, Forums and Projects are included; local
  forum PDFs and their setlist links survive refund, expiry and unavailable billing.
  Experimental handwriting setup/personalization remains independently parked.
- Free Plan and fallback Upgrade UI replace purchase/offer controls with free
  access information. Ordinary and complimentary purchase entry points also
  return before checkout. Management/restore of existing Apple purchase history
  and Apple's refund-request link remain available in Settings.
- Backend migration **20261015203728_free_pro_access** was applied through the
  connected Supabase migration tool on October 15. The deployed policy has no
  automatic end. It grants access only to live, confirmed, non-anonymous,
  non-banned accounts; existing chart ownership, Forum moderation, provenance
  and quota predicates stay in place. Live sequential role-bound checks verified
  eligible grants and no cross-owner chart/snapshot visibility.
- Subscription-based backup deletion and access-loss notices are paused. Original
  paid retention/claim functions are parked privately and not API-callable;
  removing the free policy fails closed rather than deleting overdue backups.
  Account-requested deletion and telemetry privacy retention are unchanged.
  Retention Edge version 41 and offer Edge version 42 are active. The old offer
  runtime is explicitly disabled with `free_access_active`, without constructing
  Apple signer/verifier dependencies for that request path.
- Existing installed apps still enforce their old local paywalls until updated.
  Server deployment is not app distribution.
- Local final verification: **2,403 native passed / 0 failed / 103 existing skips**
  (2,506 total), on exact Simulator `BA44A6B3-E630-42C2-B627-2A7995C63C4E` using
  the existing accessibility wrapper; **1,693 SwiftPM passed / 0 failed / 89
  existing skips** (1,782 total); **618 backend passed / 0 failed / 0 skipped**,
  including 26 PGlite PostgreSQL/policy contracts. The three mounted free fallback
  cases and both stale-checkout guards actually executed. The private Plan view
  is source-contract checked, not mounted or physically device-verified.
  The first native run omitted the required Simulator wrapper and failed two
  existing Clear Draft Ink accessibility lookups even though the screenshots
  showed enabled buttons. The final correctly configured run passed unchanged
  assertions; no production Editor code was changed to address that test setup.
  Full local Supabase/Docker pgTAP was unavailable and is not counted as a pass.
  Live retention/offer endpoints still reject requests without authorization;
  this is an authentication smoke check, not an actual customer purchase/login.
- **Apple billing is not cancelled or refunded by this access grant.** Removing
  subscriptions from sale, stopping renewals and refund handling remain separate
  Apple actions. No such action has occurred. Do not claim that existing subscribers
  cannot be charged. The saved Apple-access restriction remains in force.
- Previously approved App Store/public wording still describes Basic/paid Pro.
  Preserve those exact approved payloads as history; prepare the changed free
  policy wording for fresh exact approval before metadata/public-policy submission.
  Do not silently reuse the old approval or publish revised copy as housekeeping.
- Future paid rollout must review existing Apple auto-renew status, customer notice,
  explicit opt-in, fresh retention/grace periods and suppressed mail. Never blindly
  restore parked paid deletion functions or old elapsed deadlines.

The sections below preserve the October 14 build-76 cleanup receipts. They do not
establish signing, upload or release of the current free-access candidate.

## Shipping baseline

- Repository: `beniandthe/ichart`; shipping branch: `main`.
- Clean release checkout:
  `/Users/benirossman/.codex/worktrees/app-release-normalization/Smart Chart`.
- Audited starting main: `b98267639fd8df69a246722e1c8f96d3e7060a24`.
- `project.yml` is authoritative: iChart `1.2.2 (76)`, bundle `com.ichart.app`,
  team `N6G8X4K46U`, iPad, minimum iOS 17. Regenerate with `xcodegen generate`;
  preserve the tracked native `Package.resolved`.
- Ordinary entry uses the existing Write & Render / review / repair workflow.
  Handwriting setup, teaching, and runtime personalization remain parked.
  Graph/MyScript MVPs are separate research lanes, not this shipping binary.
- The user selected `1.2.2 (76)` for the next upload; the only production build
  input change is that version/build metadata. This cleanup does not change app
  features, accounts, billing, the public
  complimentary-offer campaign, live services, or saved chart/ink data.

## GitHub and verification checkpoint

PR #78 is merged at `6a39868391ca159e75e796890819daaf0eee0f60`. Its squash tree
matches reviewed head `d836afdb15c31c17c769d78b859ab6dc5052a168`. PR #79's Pillow
maintenance update is already on the audited starting main; it affects the
optional research toolchain, not ordinary app resources.

The user explicitly changed the solo-maintainer rule: **zero required approving
reviews**, while retaining strict current SwiftPM, iOS Simulator, CodeQL and
Dependency Review checks, resolved conversations, linear history, and the
prohibitions on force-pushing or deleting `main`. Use normal exact-head-guarded
squash merges; the absence of a required human approval is not permission to
ignore failed checks or real findings.

The completed October 10 post-merge CI at `6a39868` executed 2,386 native tests
passed / 0 failed / 103 skipped; 1,683 SwiftPM passed / 0 failed / 89 skipped;
518 backend contracts passed / 0 failed / 0 skipped. Its native validator proved
nonzero execution. Direct-main CodeQL was deferred, not a new scan; actual
pre-merge analysis and Dependency Review are separate receipts.

October 14 configuration checks executed **33 native tests passed / 0 failed /
0 skipped**, verified by `xcresulttool` on the isolated
`DB02387F-6B8E-43DE-9BE5-58E4FC15B411` Simulator. No generated-project drift.

[Cleanup PR #82](https://github.com/beniandthe/ichart/pull/82) integrates the
exact maintenance heads from PR #81 (`452a659`, CodeQL/Python actions) and
PR #80 (`4e0fcf9`, optional Torch pins). Retire those PRs as superseded only after
the verified cleanup merge; preserve their heads under archive tags first.

The audit reproduced a CI routing defect: `grep -q` could exit early on a large
file list, causing its upstream `printf` to fail under `pipefail` and falsely
skip matching tests. All three predicates now use here-strings; four executable
Bash regression tests cover their actual workflow expressions, including large
inputs. CodeQL scope also includes analyzer workflow and shared build tooling.
Green scope-only jobs before this repair are not execution evidence.

The optional Python gate previously errored on a developer-local retained golden
fixture path. Missing, undeclared external fixtures now produce an explicit skip;
an explicitly configured missing, incomplete or corrupt fixture still fails.
The local crossfit test module executed **12 passed / 0 failed / 0 skipped**,
including the retained 248-case fixture on this Mac. This does not establish
Torch 2.13 compatibility. Require fresh, actual PR checks, processed CodeQL, and
the opt-in Python/Core ML compatibility gate at the final cleanup head before
merging; neither skipped goldens nor export tests establish handwriting accuracy.

## Signed local package

Distribution archive and local App Store Connect IPA export succeeded at
`/Users/benirossman/.local/share/ichart/release-candidates/2026-10-14-repo-cleanup`.
The candidate archive is `iChart-1.2.2-76.xcarchive`; the IPA is
`export-1.2.2-76/iChart.ipa`.
IPA SHA-256: `af6bff8bc6c3fb8c87446b43533ef194268e380578575e0c3b0a6d72a4464f88`.
Strict deep signature verification passed; the matching App Store profile and
Apple Distribution identity expire June 20, 2027. No experimental model or SDK
was present. These are local package facts, not an upload or device test.

The archived app runtime inputs match audited starting main; only the requested
version/build lines in `project.yml` changed. Documentation, tests, CI and
optional research dependencies are not app runtime changes. Verify the archived
build inputs against final merged main before reusing the IPA. The archive log
contains 133 warning occurrences across nine distinct warning messages; this is
not a warning-free build. The earlier `1.2.1 (75)` archive and `export/` IPA are
preserved in the same directory, but are not the next upload candidate.
Apple-side build availability and editable version status remain unverified.

## Preserved work

| Lane | Disposition |
| --- | --- |
| `codex/recognizer-graph-mvp`, `codex/recognizer-myscript-mvp` | Active research with current dirty source/evidence; leave intact. No automatic merge or model promotion. |
| `codex/recognizer-main-baseline` | Clean comparison lane at the audited starting main. Keep its identity fixed until the research coordinator deliberately refreshes it. |
| `codex/park/recognition-research-2026-10-05` at `417113a` | Retained research-source snapshot. |
| `codex/park/stroke-direction-2026-10-05` at `f4b4ffe` | Retained source snapshot; all 11 current dirty source/test files in `717e` match it. |
| Locked generalization-reset and prior Core ML / hybrid lanes | Archived reference, not release candidates. Do not unlock, reset, or restart them as cleanup. |
| Primary Documents checkout | Contains marketing edits and active coordinator/reference files; preserve it, not a clean release checkout. |

The existing archive is
`/Users/benirossman/.local/share/ichart/recognition-archives/2026-10-11-replacement-verified`.
Its verification receipt is a point-in-time archive check, not a fresh full
restore or a backup of current Graph/MyScript changes. Superseded remote branches
may be retired only after their exact commits are retained under archive tags.
Keep local parking refs and active worktrees; do not stage private handwriting,
credentials, large models, or unrelated marketing material into this release.

## Release gates

1. **Repository:** complete verified maintenance disposition, merge this scoped
   cleanup through ordinary protected PR checks, then verify final `main`, clean
   release checkout, and post-merge results. Record actual execution, not routing.
2. **Package:** regenerate; run nonzero configuration tests; archive/export with
   locked native dependencies and project-scoped manual distribution signing.
   Inspect archive/IPA identity, signatures/profile, and absence of experimental
   models/SDKs. A valid local identity/profile is not itself a successful archive.
3. **Apple upload:** the user selected `1.2.2 (76)`. Verify that build `76` is
   available and the intended App Store version is editable before upload.
   Organizer history and local artifacts do not establish the store's highest
   build. No authenticated catalog read was available through a permitted path;
   do not bypass the saved browser restriction. Upload/processing is not
   authorized by this repository cleanup and must be recorded separately.
4. **Public-release privacy/business gates:** live privacy-policy and App Privacy
   alignment, actual retention execution, and remaining complimentary-offer
   cohort/free-period/renewal observations remain explicit. Keep the campaign
   disabled and its claim clock unstarted; do not start purchases or publish
   policy/campaign changes as repository housekeeping. See the dated
   [privacy closeout](privacy-telemetry-release-closeout-2026-10-09.md).

TestFlight upload, physical device acceptance, App Review, and public release
are distinct outcomes. Compiler warnings and skipped research checks must be
reported honestly; package/CI evidence is not general handwriting accuracy.

## History and build workflow

- [Complete retained normalization history](project-state-history-through-2026-10-10.md)
- [PR #78 scoped repair](pr78-scoped-repair-2026-10-10.md)
- [Local build hard-truth runbook](local-build-environment-hard-truth-2026-08-21.md)
- [Parked recognition inventory](parked-recognition/README.md)

The V1.0 final gate and old Apple submission checklist are historical references,
not current version/build or release authority. Update this document with the
actual results before declaring any pending gate complete.
