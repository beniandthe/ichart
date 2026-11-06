# Combined telemetry reduction and repeat retirement candidate

This is local release preparation. The user requested one candidate combining the basic telemetry reduction with handwritten repeat-ingestion retirement, and explicitly held the repeat-only merge. Push, merge, production/backend operations, releases and physical iPad installs are outside this handoff. Automations remain paused.

## Inputs

- Canonical base: `4971b3ed82b7afc0239330df9bfdfb1f9ff5d88a`.
- Repeat-retirement input: `88bb2730cc383bc2ffeeeed8e3fdc75de7851e97`, PR [#102](https://github.com/beniandthe/ichart/pull/102), unmerged at the integration handoff.
- Telemetry input: the frozen uncommitted patch from `codex/basic-telemetry-20261105`, SHA-256 `53d15a308080f99b06c8edc6918a136d6f02652867e16261f8a395f88e80df64`, based on the same canonical commit.
- Local combined branch: `codex/telemetry-repeat-retirement`.

Both source inputs and their evidence remain recoverable. The telemetry source checkout was not modified. Existing dirty notation/Build 142 worktrees and parked ML work were not changed.

## Integrated behavior

Handwritten bar-and-dot repeat recognition and handwritten percent/measure-repeat recognition are retired, including their draft pairing/commit, confirmation and recovery UI. Current guidance directs repeat entry through Tools > Repeats. Manual/typed repeats, saved repeat spans and source ink, ordinary barlines and handwritten ending brackets remain supported.

Optional diagnostics retain fixed basic errors/counts and completed-operation timings. Producer admission is bounded and uses try-lock buffers. Diagnostic disk/network work runs separately from launch, writing, rendering and saving. Consent epochs, withdrawal and anonymous transport remain supported. Geometry, visibility, keyboard, live ink probes, diagnostic persistence rereads/hashes/checkpoints and their observer-only suites are removed.

The actual chart/source validation, synchronous source-consumption safeguards, persistence errors/retries and serialization remain authoritative. No chart, source-ink, PDF or setlist migration is introduced. No recognition algorithm is reopened or trained.

## Overlap resolution

The inputs overlap in eleven paths. Git's three-way merge preserved the independent changes in the canvas host, library UI and mixed functional tests. EditorView conflicts retained the retirement's removal of repeat-review state while accepting telemetry observer removal.

The optional automatic-render telemetry and ink feature-contract implementations were modified by repeat retirement but deleted by telemetry reduction; their deletion is retained. The corresponding observer suites are retired after reviewing their assertions for functional coverage elsewhere. Repeat/ending source safeguards remain in functional workflow and compatibility suites.

Local ingest contract tests must validate the smaller client's exact vocabulary and compatibility with the existing server, while keeping legacy server vocabulary/tests for older installed apps. No ingest implementation or deployed schema is changed.

Combined verification found that the existing ingest service reserves the `operation` wire key for legacy feature-contract events and drops it on basic events. The client now maps its fixed operation category to the existing generic `source` wire key. Filtering accepts only the fixed operation vocabulary and remains idempotent when queued events are sanitized again. Mocked ingest tests verify that this category and the basic error/timing/count fields survive; arbitrary source strings remain forbidden by the client.

The first full portable attempt also exposed an obsolete expectation that the removed diagnostic persistence callback should fire on a save failure. The test now requires no legacy callback and no diagnostic reread, while retaining exact chart preservation and the actual failed-save status. Initial logs are retained; the corrected full runs use a newly recorded frozen input manifest.

The first completed full native run passed 3,148 tests, skipped 120 and failed two test methods: an old account-linked privacy-copy expectation and a cold-start fixture that required a single best-effort observation before establishing an installation identity. The exact original drop gate was not observed. Independent source analysis identified an unstable identity/preference-projection precondition; the fixture now uses a stable synthetic identity and records bounded stage/denial names on failure. The two-second limit and all payload/privacy/persistence assertions remain. Current and historical privacy disclosures are tested separately. All seven focused cold-start/privacy tests then passed, with no runtime change for these corrections. A native-only enum mismatch in a new test fixture was also corrected before that run; its compile failure is retained.

A subsequent full attempt executed the obsolete privacy-test method even though the focused run passed its renamed replacement. Both the build product and installed Simulator test binary had identical hashes and contained only the new method; the exact loading/selection mismatch remained unresolved. That result is retained and rejected as final acceptance. Final native validation uses an explicit full-target `.xctestrun` generated by `build-for-testing`, a hashed snapshot of its products and a fresh configured iPad (A16) Simulator. The final log must execute the new method, contain no obsolete method, and pass all tests. Product and source hashes are checked again afterward.

## Evidence boundaries

Individual input evidence is not combined-candidate evidence:

- Repeat-only local full runs: native 3,302 passed / 120 skipped / zero failures; SwiftPM 1,895 passed / 92 skipped / zero failures.
- Telemetry-only local selection: native 437 passed / two optional archive skips / zero failures; portable persistence/configuration/privacy 115 passed and timing/privacy 25 passed.
- Repeat-only hosted receipts at the hold showed passing portable/backend/dependency lanes and no automated-review findings, but native and CodeQL were still running. Those receipts are explicitly superseded for the combined candidate. No completed hosted native or CodeQL result is inferred.

Final combined validation is complete:

| Lane | Total | Passed | Skipped | Failed |
| --- | ---: | ---: | ---: | ---: |
| Full native Xcode target | 3,270 | 3,150 | 120 | 0 |
| Full portable XCTest suite | 2,008 | 1,916 | 92 | 0 |
| Local mocked ingest contracts | 28 | 28 | 0 | 0 |
| Ordinary packaging contracts | 7 | 7 | 0 | 0 |
| Focused cold-start/privacy rerun | 7 | 7 | 0 | 0 |

The final full native run executed the new privacy method and no obsolete method. All sixteen focused retirement, ending/source, held-network/storage, fixed-wire and privacy cases passed within that full run. All 1,258 app/test/project inputs and the 44-file reviewed runtime snapshot match their final manifests. Frozen test-product hashes also remained unchanged after execution. Temporary preferences were restored and all four task-owned Simulators were verified shut down.

The portable suite finished before corrections to three UIKit-only test files; those files have no active macOS code. Exact before/after hashes and their entire-file `canImport(UIKit)` guards are recorded, and every other portable input remained byte-identical. No common runtime code changed during these fixture corrections.

The exact final local commit/tree, complete logs/result bundles, source/product manifests, original input patch and prepared PR description are recorded in the sealed local handoff at `/Users/benirossman/.local/share/ichart/repository-archives/2026-11-05-telemetry-repeat-candidate/`. Final source evidence is separate from every superseded or interrupted run.

## Publication and device boundary

Before this combined-preparation handoff, the repeat-retirement website correction was published and verified, and issue #99 was retired as not planned. This integration does not publish the additional telemetry privacy-policy source changes, alter issues, merge PR #102, or release an app.

The last read-only device query confirmed iChart 1.2.4 (143). No physical iPad action is part of the combined candidate. A future installation still requires its own saved-edit confirmation, fresh stopped-app backup and preservation verification.

Remaining release steps are publication of the combined branch/PR update, hosted checks and review of that combined head, approval/publication of the additional privacy-policy source changes, and a separately authorized signed build/install or App Store submission. Paused monitoring/checkpoints are unchanged; monitoring must account for intentionally absent expanded diagnostics before it is resumed. This preparation makes no hosted-combined, physical Pencil, installed-device preservation or production-deployment claim.

The candidate descends directly from PR #102's existing head, so publication can fast-forward that PR's source branch and update its title/body with the prepared combined description. A new PR or a force push is unnecessary. No such publication is authorized or performed by this local handoff.
