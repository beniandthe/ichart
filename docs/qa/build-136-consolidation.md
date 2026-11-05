# Build 136 source consolidation

Updated November 4, 2026.

The historical iChart 1.2.4 (136) installation is checkpointed at
`6ffeb1442a04ec020a036c7da653ff2051e70363`. This preserves the tested application,
regressions, tool guidance, forum test utility and publication-boundary migration.
Build 137, source `71491e50`, is now installed with saved-state preservation
verified. Its keyboard review passed the user's checks in both chart styles,
but physical Simple/Automatic repeat writing failed. Build 138 is the repair
candidate. Its local native suite passes 3,373 / 0 failed / 119 skipped;
current-head hosted CI/review is tracked in PR #95 and physical repeat acceptance
remains pending.
See the [Fix Docket](ichart-fix-docket.md) for current status.

## Integration and scope

The GitHub `main` tip checked for this consolidation was
`4fb03664670f90ed477fdebfc8fbf181f7b2a1a2`. It is an ancestor of the checkpoint:
the range contains 23 commits and changes 126 text files. The checkpoint was
imported through fast-forward ancestry on the isolated
`codex/build136-integration` branch. Unrelated edits in the original working
checkout remain unchanged.

The checkpoint covers Write & Render routing, partial structural rendering,
review-source ownership, F and major-triangle recognition, Free Ink articulations,
chart-ID persistence, measure/engraving geometry, PDF metadata and forum
participation. Existing marcato compatibility is retained; further mark-input
work remains parked. Separate Graph, MyScript and ML research branches were not
incorporated.

No application-runtime code changed during the initial Build 136 consolidation.
That integration step sets the
authoritative `project.yml` build default from 108 to 136 and updates its test
expectation. The installed binary had already used an explicit build-136
override; the new default makes ordinary builds use the same number.

## Verification evidence

These evidence lanes are separate; historical local results are not hosted CI.

| Lane | Result and boundary |
| --- | --- |
| Installed-source native regressions | 1,526 final passing cases; no remaining failures. Seven optional captured/full-archive replay checks were explicitly excluded. |
| Portable recognition | 256 passed, two optional skips, no failures. Includes retained genuine half-diminished controls. |
| Local forum HTTP gateway | 25 passed with two real test accounts, JWT verification, the actual Edge handler, PostgREST and Storage. Both chart styles exercised. |
| Local database policies | 170 assertions passed. |
| Edge handler unit tests | 56 passed. |
| Integration configuration | 34 native project-configuration tests passed without a build-number override; no skips or failures. |
| Physical iPad, historical Build 136 | Build 136 installed and relaunched after an authorized backup. Independent reads verified saved charts, original ink, PDFs, setlists and the rendering preference. User reported improved recognition; this was not an exhaustive physical style/mode matrix. |

The approved service-only forum publication repair is already deployed as
`20261104151103_repair_forum_publication_gateway_boundary`. Readback verified its
restricted caller boundary and empty search path without granting general
private-schema access. Local gateway fixtures were removed; production
verification created no public test content.

Device snapshots, handwriting archives and detailed local execution artifacts
remain outside this source consolidation. See the [Fix Docket](ichart-fix-docket.md)
for current ticket status and remaining checks.

## Remaining closeout

The actual forum app walkthrough in an isolated local environment is complete.
It exposed browsing defects addressed by the separate
[Build 137 follow-up](forum-browse-followup-137.md), included in the same
PR after explicit user approval. That follow-up passed 50 focused native checks
and three actual app walkthrough methods, with durable server readback and
fixture cleanup. Build 137 was subsequently installed from `71491e50`; its
separate preservation receipt does not replace this historical Build 136 record.

At the earlier Build 136 PR head, hosted backend contracts and Dependency Review
passed. Hosted iOS, SwiftPM and
CodeQL jobs were cancelled before execution because macOS runners were not
acquired. These earlier results do not describe the later Build 137 gates or
the pending Build 138 repair gates.

Fresh physical checks of the latest divider, engraving-preview and PDF-label
changes remain open. The historical ink-integrity investigation still requires
affected-chart evidence; successful installation preservation does not settle it.

Issue #96 remains open with its historical mechanism unidentified. Build 138
local source verification is complete; current-head hosted CI/review and fresh
physical repeat acceptance are separate gates. No physical repeat repair is
claimed complete here. Promotion to `main`, any further device
installation and App Store release are separate from these historical receipts.
