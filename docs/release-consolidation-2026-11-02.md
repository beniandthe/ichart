# iChart release consolidation — November 2, 2026

Candidate: **1.2.4 (108)** on `codex/next-app-store-20261102`.
Source baseline: `31e16ea5deac4621dea10ddd3a0d1f9c59a3f3f5` (`main`, PR #92).
Status: **source coverage complete; corrected fixture focus passed; final checks tracked separately**.

The sweep found that the regular app's functional work was already consolidated
on main. It did not find another omitted production implementation to merge.
Older donor branches remain ahead in Git because of squash merges and selective
ports; that graph shape does not establish missing functionality. Content,
source/test paths, historical checkpoints and PR dispositions were compared
before deciding whether to copy anything.

The [sanitized JSON inventory](release-consolidation-2026-11-02.json) records
individual branch/tracking-ref, worktree, tag, PR and reflog dispositions. Private
raw ink, device-library data, complete research filenames and QA dumps remain
outside this report.

## Candidate changes beyond the consolidated baseline

- Include PR #84's CodeQL `init` and `analyze` update from `v4.39.0` to
  `v4.39.1`, retained in commit `fcea7299`. The PR was open at the initial sweep;
  including its patch is not a claim that the original PR was merged or closed.
- Set `project.yml` to **1.2.4 (108)** and update the matching configuration-test
  expectation. Generated Xcode project state remains derived from `project.yml`.
- Restore the PDF binary rule in `.gitattributes` and the reusable synthetic
  `scripts/create_pdf_import_proof.py` generator from the PDF-import donor.
- Restore the historical [offline PDF proof runbook](ichart-pdf-import-offline-proof-2026-10-23.md)
  and [production review runbook](ichart-pdf-import-production-review-2026-10-23.md),
  with historical banners and frozen evidence links. Their old results do not
  validate build 108, and generated proof PDFs/screenshots are not copied into
  the app candidate.
- Isolate the basic telemetry consent-value test on `MainActor`. The first
  hosted PR run exposed a startup-projection wait race in this non-concurrency
  fixture; every assertion is retained and dedicated concurrency tests remain.
- Add this release inventory and update the current project-state header.

There is no new application runtime change in this candidate beyond the
already combined main implementation. The source sweep is not a new security
scan, handwriting evaluation or backend deployment.

## Functional coverage

| Lane | Source coverage |
| --- | --- |
| Release normalization and existing production repairs | Covered by main normalization and later fixes; historical ahead counts are not missing work. PRs #76, #77, #78, #81, #82. |
| Free Pro, account recovery, cloud access and Forum publication | Covered in main; existing billing and customer obligations remain separate. PRs #83. |
| Notation readability and staff density | Covered in main, including all19 prototype test methods plus four later preservation/density tests. PRs #86. |
| Repeat signs and custom/direct endings | Covered in main; dedicated ending review confirms no missing implementation. Donor integration files are older than current host/editor. PRs #87, #88, #91. |
| Personal PDF import and offline setlists | Runtime already covered. Restore proof generator, PDF binary rule and two historical runbooks; retain historical generated evidence separately. PRs #85, #91. |
| Free Ink rotation, viewport, engraving and manual widths | Covered in main, including all12 directed engraving-preset pairs and the mixed-width projection correction. PRs #89, #93, #92. |
| Automatic rendering, fallback recovery and diagnostic contracts | Covered in main. Keep source ownership, consent generations, structural/repeat/ending coverage and bounded technical-failure retry. PRs #90, #91, #92. |
| Integration checkpoints | Covered by baseline31e16ea5. PR92 donor whole tree matches main; current local main was one commit behind and left untouched. PRs #91, #92. |
| Remaining workflow maintenance | Included in candidatefcea7299: CodeQL init/analyze v4.39.0 to v4.39.1 only. PRs #84. |

Repeat-ending review found **36 changed app/test paths**, **25 byte-identical**
to main and **zero missing**. The remaining files contain later main integration
work: automatic rendering, consent/keyboard reachability, PDF intake, Free Ink
and build configuration. The dedicated ending implementation and tests are
retained. Copying the old donor editor/host files would remove those later fixes.

The production automatic reader recovery, grammar/parser, source ownership,
rendering and privacy fixes stay in scope. The user's ML exclusion applies to
parked study/lab work rather than deleting existing production error handling.

## GitHub coverage

The initial connected-GitHub sweep fetched all **93 PR records**, retained **18**
October/November or open records, inspected all **five live remote branches**,
and inspected the latest **30 workflow runs**. There were no standalone open
issues; PR #84 was the only open PR at that checkpoint. The JSON records this as
a timestamped initial snapshot, not a promise that later GitHub activity is
already covered.

| PR | Recorded disposition |
| --- | --- |
| [#76](https://github.com/beniandthe/ichart/pull/76) | Superseded by release normalization; source commits retained through PR78. |
| [#77](https://github.com/beniandthe/ichart/pull/77) | Merged CodeQL maintenance. |
| [#78](https://github.com/beniandthe/ichart/pull/78) | Merged release normalization, editor/ink/telemetry and CI maintenance. |
| [#79](https://github.com/beniandthe/ichart/pull/79) | Merged historical training dependency maintenance; no parked model/runtime promotion. |
| [#80](https://github.com/beniandthe/ichart/pull/80) | Closed unmerged; optional training dependency maintenance carried by PR82, outside app bundle. |
| [#81](https://github.com/beniandthe/ichart/pull/81) | Closed unmerged; Actions maintenance carried by PR82. |
| [#82](https://github.com/beniandthe/ichart/pull/82) | Merged repository/release handoff and maintenance changes. |
| [#83](https://github.com/beniandthe/ichart/pull/83) | Merged voluntary free Pro access, recovery/account controls and atomic Forum publication. |
| [#84](https://github.com/beniandthe/ichart/pull/84) | Only open PR at the initial GitHub sweep; its two CodeQL action changes are included in candidate commit fcea7299. This does not claim PR84 was merged or closed. |
| [#85](https://github.com/beniandthe/ichart/pull/85) | Closed unmerged as superseded; personal PDF import and offline setlist feature selectively integrated by PR91. |
| [#86](https://github.com/beniandthe/ichart/pull/86) | Merged repeat/navigation readability with density and preservation coverage. |
| [#87](https://github.com/beniandthe/ichart/pull/87) | Merged flexible custom endings and direct bracket editing. |
| [#88](https://github.com/beniandthe/ichart/pull/88) | Merged production repeat-sign recognition in Write & Render. |
| [#89](https://github.com/beniandthe/ichart/pull/89) | Merged Free Ink rotation/viewport stability. |
| [#90](https://github.com/beniandthe/ichart/pull/90) | Closed unmerged as superseded; diagnostics/task pipeline selectively integrated by PR91. |
| [#91](https://github.com/beniandthe/ichart/pull/91) | Merged the regular-app consolidation: PDF import, ending recognition/review, automatic rendering and telemetry integration. |
| [#92](https://github.com/beniandthe/ichart/pull/92) | Merged bounded technical-failure recovery and mixed manual/default-width Free Ink correction; main tree exactly matches tested donor head. |
| [#93](https://github.com/beniandthe/ichart/pull/93) | Merged engraving-aligned Free Ink; later mixed-width correction retained through PR92. |

The five live remote heads were `main`, the free-Pro donor, PDF-import donor,
telemetry-feature donor and the CodeQL Dependabot branch. Cached tracking refs
for older deleted remote branches were retained and classified separately.
Closed-unmerged PRs #76, #80, #81, #85 and #90 were checked against their actual
superseding integrations; their closure alone was not used as proof of coverage.

## Local refs, worktrees and preservation

The initial audit covered **41 branch/tracking refs**: **33 local heads** and
**eight remote-tracking refs**, including `origin/HEAD`. It covered **18 registered
worktrees**, **12 present** and **six missing**. Creating this isolated candidate
adds one local head and one present worktree: the candidate-inclusive count is
**34 heads + eight tracking refs**, **19 registered worktrees**, **13 present**
and **six missing**.

The extended inventory also reviewed **14 tags**, **five Codex snapshot refs**,
**eight turn-diff tree refs**, **zero stashes** and **five recent reflog-only
variants**. Together with the candidate head, those are **69 refs**. The reflog
variants were patch-equivalent, tree-equivalent, or superseded by retained
production changes. Recovery/agent metadata was not merged over current source.
No extra Git checkout was found in the checked standard worktree/temporary
checkout locations; arbitrary filesystem locations were not exhaustively scanned.

The six missing worktree registrations retain their refs. Five are stale
prunable temporary-checkout registrations; one is a missing locked research
snapshot. Nothing was pruned, deleted, reset or recreated merely to make this
inventory appear clean. Existing donor worktrees remain available for recovery.

The primary dirty checkout contains **11 modified tracked files** and **35,095
untracked files**. Their complete local manifest remains private. Its disposition
is:

| Paths | Disposition |
| --- | --- |
| 13 runtime/test paths | Earlier readability prototype already integrated or superseded in main. All 19 local readability test methods exist upstream; main adds four more preservation/density tests. No source copy required. |
| 4 marketing documents | Byte-identical to main. |
| 3 historical/planning documents | Old App Store draft, import plan and superseded intake retained. They are not newly approved public text or missing runtime implementation. |
| 33 readability QA artifacts | Historical evidence preserved locally; no current candidate pass inferred. |
| 35,053 research files | Parked ML/research preserved and excluded from integration. |

An additional tracked-path absence check across **33 non-ML refs** found **57
paths absent from baseline main** and no missing Swift, SQL, backend or CI runtime
file. The four nonruntime controls/runbooks listed above are now selected for
this candidate. The other **53 historical/generated paths** remain donor
artifacts, accounted for without copying old receipts or generated proof assets
into the release tree.

## Parked ML and retained boundaries

Graph/MyScript replacement labs, Core ML/hybrid/stroke-direction research,
function/Fourier experiments, personalized-handwriting studies and the
generalization/reset lane remain parked. This consolidation does not train,
promote a model, resume vendor work or activate raw-ink collection. The ordinary
pitch-alias changes visible in lab working copies already match main byte for
byte; a replacement-lab-specific test remains with that lab.

The research paths, signed lab products and historical datasets remain in their
existing preservation locations. Diagnostic consent does not become training
consent. The PDF/Pro Scan plan remains a plan where implementation has not been
completed; preserving the plan does not ship an online conversion feature.

## Validation and delivery gates

The first candidate's complete local native gate passed **3,112 / 0 failed / 114 skipped** (**3,226 total**)
on the fresh iPad A16 / iOS 26.5 Simulator. `xcresulttool` verified nonzero
execution, zero failures and that exact destination. All **1,286 app/test/build
input hashes** remained unchanged throughout validation. The portable SwiftPM
suite passed **1,820 / 0 / 91 skipped** (**1,911 total**). Backend/workflow groups
passed **822 / 0 / 0**, and the restored PDF generator produced the expected
two-page US Letter fixture.

The original QA Simulator run is preserved as **3,109 passed / three failed
tests / 114 skipped**, with six failure events at software-keyboard preconditions.
A cold three-test rerun on that existing Simulator repeated those precondition
failures. The same three tests then passed unchanged on the fresh same-model,
same-runtime Simulator with software-keyboard configuration set before its first
boot. The entire suite subsequently passed there, including all three keyboard
tests. No app source or test assertions were changed to obtain that result;
temporary host-preference restoration was verified.

The first hosted PR native run separately recorded **3,111 passed / one failed
/ 114 skipped**: the basic consent-value test read its seeded installation UUID
before deferred startup projection finished. The same-head branch-push run
passed **3,112 / 0 / 114**, including its nonzero/destination validator. This was
not one of the earlier keyboard failures.

The value test now runs on `MainActor`, serializing initialization and its first
snapshot with the queued preference projection. Its default-off, nil-identity,
legacy/unknown-version and explicit-grant assertions are unchanged. Background,
blocked-cleanup, reentry and stale-generation tests retain concurrency coverage.
No production consent code changed; the test-only queue sentinel is not claimed
to drain arbitrary deferred retries. The corrected test passed **50 repetitions
/ 0 failures**. Full local native/portable reruns and fresh exact-head hosted
checks are tracked separately after this fixture revision.

This is the source-preparation checkpoint. Hosted checks, signed archive/IPA,
physical-device acceptance and Apple delivery are recorded separately in the
review PR and release owner's private artifact receipt as they actually finish.
Earlier failed/preflight receipts remain retained alongside the passing results.

Historical baseline evidence is separate: PR #92's final donor head
`f7c6128120d4e781dacbfa3ba4d9c9bc123c1b38` has the same full tree as baseline
main, and its [CI](https://github.com/beniandthe/ichart/actions/runs/41479185644)
and [CodeQL](https://github.com/beniandthe/ichart/actions/runs/41479185642) ran
actual validation successfully. The subsequent main-push iOS/SwiftPM and CodeQL
jobs were cancelled before runner assignment or test steps. Their annotations identify hosted macOS arm64 capacity/acquisition failure
("The job was not acquired by Runner of type hosted even after multiple attempts").
This is not a fresh application test failure or a current candidate success.

For **1.2.4 (108)**, Apple upload, processing, Distribution attachment, App Review
submission, Apple approval and public release are **not established** by this
source consolidation. No new listing, review-note, privacy or marketing copy has
been approved by this report. Physical acceptance of earlier component builds
does not establish combined build 108 acceptance. Earlier **1.2.3** Apple release
records remain historical and do not satisfy any 108 delivery gate.

Keep the separate acceptance boundaries for editing/rendering/export, imported
PDF/setlist behavior, Free Ink transformations and save/reopen. Cloud backup does
not acquire PDF/setlist/source-document coverage merely because native-chart
backup exists. Customer billing/goodwill obligations and future paid-transition
work remain separately recorded; no customer message is replayed by this sweep.

The current privacy source is dated October 30 and describes diagnostic
checkpoints and technical task history. Source alone does not establish approval
or live publication of that text. Before any needed external publication, check
for newer human approval and public readback evidence; this consolidation does
not publish a policy or change the existing Apple privacy label.
