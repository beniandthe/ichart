# Project state and next Apple build

Updated: 2026-10-15. This is the current release handoff. Historical reports are
evidence for their recorded revisions, not an automatically expanding backlog.

## Current repair checkpoint: public free Pro and atomic Forum publication

The approved public-facing title is **Pro — Free**. The app now says Pro is
currently free with an iChart account, allows leaving/rejoining in Settings, and
requires advance pricing notice plus Apple confirmation for any new paid
subscription. Existing Apple billing remains separate. These are display-string
changes, not a billing, recognition, chart-format or access-policy transition.
Internal beta identifiers and persisted membership/RPC keys remain compatible.

The admitted-publish race found on PR #83 is repaired in source. Publication now
uses one service-only database operation that locks the account and stored post,
checks current eligibility/access/ownership/status, and finalizes provenance plus
visibility in the same transaction. The participation setter takes the same
account lock, covering both existing and initially absent membership. Auth bans
and deletion also conflict with that row lock. A completed opt-out/ban denies a
waiting publisher; an already-committing publisher finishes before the access
change can complete. Withdrawal/removal is not resurrected. There is no fallback
to the old finalizer-plus-publication PATCH and no new authenticated moderation
or provenance-finalization grant.

- The original wired race was reproduced, and both added revocation regressions
  failed against the old handler before passing against the repair.
- Final focused handler/PostgreSQL tests: **141 passed / 0 failed / 0 skipped**,
  including 56 handler cases and 85 single-session PostgreSQL cases. The full
  shared backend suite separately passed **641 / 0 / 0**; these overlap, not add.
- Real PostgreSQL **17.11**, with independent sessions, passed all **six** lock
  ordering scenarios (**7** Node tests including the parent). Observed blocking
  comes from `pg_blocking_pids`, not timing assumptions. Each run owns and stops
  a private synthetic Unix-socket-only cluster. CI now runs this regression using
  the runner's PostgreSQL server binaries; remote execution is still a fresh gate.
- Full native tests passed **2,446 / 0 / 103 existing skips** (2,549 total), with
  the exact configured Simulator verified from `xcresulttool`. Full SwiftPM
  passed **1,724 / 0 / 89 existing skips** (1,813 total). Four workflow-scope
  regressions passed. An independent read-only bypass/regression review found no
  concrete surviving defect in the focused backend candidate. This is not a
  repository-wide security scan or handwriting-accuracy evidence.
- Production migration **20261016022548_atomic_forum_publication** is applied.
  Its exact SQL digest matches the repository; the initial uncommitted CLI
  filename was aligned to the version actually recorded by Supabase, without
  changing SQL or rewriting migration history. Service-only grants/empty search
  paths and the absence of authenticated status UPDATE privileges are verified.
  Existing advisor notices remain unchanged. The live Forum endpoint is still
  **version 42**: the human separately approved replacing only that endpoint
  **after fresh PR checks pass and the repair is merged**. Do not claim the live
  admitted-publish path has changed before that deployment/readback.
- Version/build remains **1.2.3 (78)**. A new signed local archive/export succeeded
  in the private `2026-10-15-free-pro-1.2.3-78-public-wording-atomic-publish`
  candidate directory. IPA SHA-256:
  `10677b28a289da6b938eda3e4886d6b3e6a29e0bbbdb289edb5ad07577305ee4`.
  Prior packages are preserved. The previously installed account-loop acceptance
  passed at the preceding `e854bf0` candidate; it is not a claim of a new physical
  test of this wording-only app follow-up.
- Fresh exact-head PR CI, actual CodeQL analysis/processing and Dependency Review
  must pass before a normal guarded squash merge. Earlier `e854bf0` green results
  do not validate this repair. Apple build availability, private editable version,
  configured locales, listing/privacy alignment, upload and submission remain
  separate. New English listing/privacy/terms drafts are private and **unapproved**;
  public UI wording approval does not authorize publishing those documents.

## Previous pre-push checkpoint: free-beta account-loop audit (`e854bf0`)

Version/build remains **1.2.3 (78)** on
`codex/free-pro-access-2026-10-15`. This follow-up preserves the voluntary free-Pro
policy below and closes concrete recovery/access/queue gaps; it does not resume
recognition research, start billing, or publish an Apple release.

- **Recovery:** Try Again reconnects the actual offline session before reading
  membership. Store-owned/coalesced reads survive a cancelled foreground waiter;
  a same-owner offline transition invalidates obsolete recovery work. Account
  and generation guards reject stale responses. An uncertain write acknowledgement
  preserves the last confirmed local choice and reconciles with a read, never an
  automatic replay of the possibly committed choice.
- **Basic access:** stale project-variant sheets cannot create or duplicate into
  Projects after leaving Pro. Existing over-cap charts remain editable. Locked
  feature/capacity messages point to the free Rejoin action, not paid checkout.
- **Forum queues:** Basic/account changes pause publishing without discarding
  drafts. Rejoin resumes only the matching owner's pending items without concurrent
  duplicate sends. Withdrawal, removal and queue dismissal cannot be resurrected
  by late progress, success or cancellation callbacks. Failed cleanup stays
  actionable rather than automatically publishing. Basic cleanup no longer fails
  merely because its subsequent Pro-only home-feed refresh is forbidden.
- **Server authority:** `forum-post-actions` now checks the authenticated user's
  current access before service-role publishing, using the original user bearer
  and a public/anon API key. It supports Supabase's publishable-key dictionary
  as well as the prior key forms, rejects secret/service-role keys for that check,
  and fails closed on invalid access responses/configuration. Publishing atomically
  requires the post still be `pending`; a concurrent withdrawal/removal wins and
  the late publish returns 409 instead of fabricating success. Owned cleanup,
  provenance, quotas and existing authentication remain enforced. Focused Edge
  **version 42** is active with JWT verification enabled; all three deployed
  files were read back and match the tested bundle. No new migration or permission
  broadening was needed. The Forum regression suite is now included explicitly
  in ordinary CI.
- **Live role-bound audit:** all **86** existing accounts were checked in a
  read-only rolled-back transaction: **65 eligible / 65 granted**, with zero
  owner/status-helper mismatches, foreign-owner chart/snapshot visibility, or
  rows visible without the access grant. No customer choice was changed. Local
  PostgreSQL cases additionally cover verified email/phone, anonymous, unverified,
  banned/past-ban, deleted/missing accounts, account-scoped participation, protected
  table ownership and paused retention. These are role-bound policy checks, not
  86 physical logins or a live customer publishing exercise.
- **Final local execution:** native **2,445 passed / 0 failed / 103 existing
  skips** (2,548 total), verified with `xcresulttool` and nonzero execution on
  Simulator `BA44A6B3-E630-42C2-B627-2A7995C63C4E`; complete SwiftPM **1,723
  passed / 0 failed / 89 existing skips** (1,812 total); shared backend **625
  passed / 0 failed / 0 skipped** plus PostgreSQL **54 / 0 / 0**; four Bash scope
  regressions passed. The final native receipt is
  `/private/tmp/iChartBetaFinalFullNative-20261015-003.xcresult`. The immediately
  preceding run had one outdated test expectation after a remove action; it is
  preserved, and the replacement asserts Withdrawn after withdrawal and Removed
  after removal. No production change was made to conceal that failure. Parked
  research/integration skips are not passes or recognition-accuracy evidence.
- **Device/package:** the final development app passed strict signing,
  replacement installation, normal launch and exact **1.2.3 (78)** readback.
  Before/after snapshots preserve all eleven chart objects, Projects, 49
  tombstones, cloud metadata and selection; 15 PDF files and the one six-entry
  setlist remain intact. All 22 pre-existing files other than the performance log
  are byte-identical; that log changed and a diagnostic queue was added. Final Release
  archive/export and both strict signatures passed, with expected team/bundle and
  `get-task-allow=false`. Current private candidate:
  `/Users/benirossman/.local/share/ichart/release-candidates/2026-10-15-free-pro-1.2.3-78-final-audit/export-final/iChart.ipa`.
  IPA SHA-256: `b37a63faa3da68d35409f7058d2a9f109276b644ae84cc038b8e3dd4d0cfa463`.
  Earlier packages and the interim audit archive/export are preserved.
- **Remaining boundaries:** the new physical Leave Pro → reopen existing work →
  Rejoin flow still needs a short user acceptance check. Local verification and
  packaging do not establish a GitHub push, remote CI, Apple upload, listing
  approval, submission or public availability. Compiler/advisor warnings remain;
  this is not a repository-wide clean security bill. No beta-ending notice/date,
  paid conversion or customer campaign is active. Future paid-return notice,
  explicit Apple consent and the promised private goodwill fulfilment remain
  separately parked; the approved goodwill email has been sent, not a refund or
  subscription cancellation. Customer identifiers/message payloads stay private.

## Previous voluntary-beta checkpoint: `f8fece4`

- Version/build stays **1.2.3 (78)**. Every verified account starts with free
  Pro. Settings offers **Leave Pro — Use Basic** and **Rejoin Pro — Free During
  Beta**, without checkout. Both choices are saved against the authenticated
  account, not Apple receipts or shared chart files. Delayed requests and UI
  actions cannot apply one account's choice to a different account.
- Basic limits new-chart creation to three charts and disables Pro-only
  services. Existing charts remain editable even above that limit. Existing
  Projects data, PDFs and setlist links are retained; cloud backups are not
  deleted. Rejoining restores feature access without changing billing history.
- **Manage My Subscription** and purchase-history restore remain. The public
  refund-request button is removed. Changing beta membership does **not** cancel
  existing Apple billing or issue a refund. The private goodwill email was later
  sent after exact-message approval; no customer identifiers or private message
  payload belong in this repository.
- An account-scoped, acknowledged in-app notice can warn before beta ends.
  **No notice, deadline, paid conversion, email campaign or purchase is active.**
  A future paid transition still requires reviewed implementation and explicit
  Apple purchase confirmation; this feature does not create an auto-renewal.
- Production migration `20261015232153_voluntary_free_pro_beta` adds private
  participation records and bounded own-account RPCs. The setter also requires
  an expected-owner rejection guard, while `auth.uid()` remains authoritative.
  Global backup-retention protection is independent of individual participation.
  Live role-bound QA Leave/Rejoin assertions passed inside a rolled-back
  transaction; zero choices remained saved. All 86 original subscription rows
  matched their before/after digest. Notice/deadline fields remain null.
- That revision's native validation: **2,431 passed / 0 failed / 103 existing
  skips**, 2,534 total, including five mounted beta-control cases, fourteen store
  cases and nine access/data-preservation cases. The configured Simulator and
  accessibility wrapper were used. Backend validation: **592 shared contracts
  plus 47 PostgreSQL contracts passed / 0 failed / 0 skipped**. Complete SwiftPM
  execution before the final extra expected-owner overload passed **1,715 / 0 /
  89 skips**; the final store/core/copy subset then passed **26 / 0 / 0**.
- The revised development app was signed, replacement-installed and normally
  launched on the iPad; installed identity reads **1.2.3 (78)**. Hands-on testing
  of the new Leave/Rejoin flow remains pending. A new local Release archive and
  IPA were signed/exported and passed strict signature checks, with version/build
  1.2.3 (78) and `get-task-allow=false`. They are retained separately under
  `/Users/benirossman/.local/share/ichart/release-candidates/2026-10-15-free-pro-1.2.3-78-beta-controls`.
  That revision's IPA SHA-256:
  `981d40a50e80d54b65fecf1a1c278d08374f8c9b674c915087249f84fa7399cd`.
  Fresh device snapshots preserve all eleven chart objects, Projects,
  tombstones and cloud metadata, plus all 21 other non-log files byte-for-byte
  (PDFs, setlist index and parked profiles included). The library file changed
  only for selection and a refresh of genuine subscription verification/expiry/
  renewal metadata; the performance log also changed. Do not call every file
  byte-identical or imply that beta membership created a paid entitlement.
  Earlier build-78/77 packages below are preserved, not silently overwritten.
  No upload, submission, push or merge is established by this revision.
- The new private membership table intentionally has deny-all RLS; the two new
  authenticated SECURITY DEFINER RPCs intentionally expose only bounded
  own-account operations with empty search paths. Their advisor notices are not
  a reason to broaden direct table permissions. See the advisor explanations for
  [deny-all private RLS](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
  and [bounded definer RPCs](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
  Existing MFA warning and compiler warnings remain; this is not a clean
  repository-wide security audit.

## Earlier free-Pro baseline and retained packages

- User decision: every legitimate account receives all shipped Pro features free,
  with no checkout, trial deadline or automatic conversion to paid. Normal account
  confirmation and account-safety requirements remain. Returning to paid access
  requires advance customer notice and an explicitly confirmed paid subscription;
  this is not a date-based trial or the previous complimentary-month campaign.
- Implementation branch: `codex/free-pro-access-2026-10-15`, based on verified
  `main` at `025d2ce50489215cfd4baa5de341ff99b02623fa`. Current source candidate is
  **1.2.3 (78)**, corrected explicitly on October 15. The signed build-77 package
  and its verification receipts below are preserved; a build-number change does
  not carry their package identity forward. Build 76 was reported
  ready in TestFlight; preserve that artifact,
  but it does not contain this free-access change. Build 77's previous version metadata
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
- Build **1.2.3 (78)** now replaces 77 as the current candidate. This is a
  build-number-only correction: **41 focused native tests / 0 failures / 0 skips**
  and **36 configuration/copy tests / 0 failures / 0 skips** passed. Development
  signing, replacement iPad installation, normal launch and installed-version
  readback succeeded. The signed Release archive/export and strict signatures
  also passed, with exported `get-task-allow=false`. Fresh before/after snapshots
  preserve all existing chart/PDF/setlist/profile files exactly; diagnostic log
  rotation and a new telemetry queue are not chart-data changes.
  Current private package directory:
  `/Users/benirossman/.local/share/ichart/release-candidates/2026-10-15-free-pro-1.2.3-78`.
  Current IPA SHA-256:
  `4d0764d3375f8cea569812b549f7b7eb2595fd38a5341d7ceb13f27867fa686d`.
  Build 77's retained IPA hash is unchanged. Physical user acceptance, Apple-side
  build availability, upload and review/submission remain separate pending gates.
- Runtime feature access is separate from truthful subscription state. Existing
  billing records and Apple receipt/notification verification are not rewritten.
  Local chart limits are removed; cloud, Forums and Projects are included; local
  forum PDFs and their setlist links survive refund, expiry and unavailable billing.
  Experimental handwriting setup/personalization remains independently parked.
- Free Plan and fallback Upgrade UI replace purchase/offer controls with free
  access information. Ordinary and complimentary purchase entry points also
  return before checkout. Management/restore of existing Apple purchase history
  remain available in Settings. The latest revision above removes the public
  refund-request link and adds voluntary beta participation.
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
