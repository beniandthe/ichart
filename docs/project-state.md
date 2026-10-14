# Project state and next Apple build

Updated: 2026-10-14. This is the current release handoff. Historical reports are
evidence for their recorded revisions, not an automatically expanding backlog.

## Shipping baseline

- Repository: `beniandthe/ichart`; shipping branch: `main`.
- Clean release checkout:
  `/Users/benirossman/.codex/worktrees/app-release-normalization/Smart Chart`.
- Audited starting main: `b98267639fd8df69a246722e1c8f96d3e7060a24`.
- `project.yml` is authoritative: iChart `1.2.1 (75)`, bundle `com.ichart.app`,
  team `N6G8X4K46U`, iPad, minimum iOS 17. Regenerate with `xcodegen generate`;
  preserve the tracked native `Package.resolved`.
- Ordinary entry uses the existing Write & Render / review / repair workflow.
  Handwriting setup, teaching, and runtime personalization remain parked.
  Graph/MyScript MVPs are separate research lanes, not this shipping binary.
- This cleanup does not change app features, accounts, billing, the public
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

October 14 configuration gate at audited starting main: **32 native tests
passed / 0 failed / 0 skipped**, verified by `xcresulttool` on the isolated
`DB02387F-6B8E-43DE-9BE5-58E4FC15B411` Simulator. No generated-project drift.
Release archive/export and final merge-head CI are separate gates below.

Maintenance PR #81 changes CodeQL and Python actions; its ordinary green checks
did not execute the changed analyzer or optional Python action. Actual dispatched
compatibility runs are `38597125017` (CodeQL) and `38597132705` (opt-in research).
PR #80 changes optional Torch training/export pins; its ordinary green checks
did not exercise Torch. Its opt-in compatibility run is `38597918073`. Inspect
executed tests and processed analysis before merging; keep an unsupported or
failed research-toolchain update parked rather than redefining it as an app gate.

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
3. **Apple upload:** verify the highest already-uploaded build for `1.2.1` in
   App Store Connect before reusing `75` or selecting the next build number.
   No build-75 upload receipt was found locally. Organizer history does not
   establish the store's highest build. Upload/processing is not authorized by
   this repository cleanup and must be recorded separately.
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
