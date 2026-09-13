# Chord-recognition trial readiness — 2026-09-12

## Decision

The user reopened the deeper recognition iteration on September 12 and deferred the near-term trial cutoff. V16 remains the validated, installed physical baseline. V19 is the current local follow-up. It closes the four sharp/minor construction-order failures, but expanded stroke-direction evidence remains unresolved. This is not shipping acceptance, perfect recognition or an uploaded release.

Final R04 telemetry-boundary, native, Release, SwiftPM and concurrency checks pass. The exact V16 Release candidate is now development-signed, installed and launched on the physical iPad. Fresh handwriting acceptance and distribution remain separate gates.

## Reopened iteration: retained V16 correction (V17 checkpoint)

The fresh saved library contains an explicit `Bbmaj7` correction with a V16
source candidate signature of `Gb13`. Rendering and replaying its exact source
drawing exposes a stemless two-lobe root (also visually a 3), a flat, a wide
retraced major triangle, and a seven. The local raw debug trace is older than
V16 startup, so it is not used as evidence of V16 preview decisions.

At original size, V16 replays `Gb13` requiring confirmation with no useful B
alternative. At 110% size, the same geometry can become a trusted `Gb13`.
This is a deterministic stress failure, not proof that this exact size change
occurred on the iPad. Explicit stored correction establishes intent; the
missing B stem still does not support an automatic B accept.

V17 adds a bounded stemless-root ambiguity guard, review-only B alternatives,
and an explicit visible review slot. It also checks all three sides of a broad
major triangle geometrically, rather than relying on aspect ratio, pen start
or direction. The native primary and recognition scores remain intact; B
recovery is never automatic. Both chart styles share these policies.

The new ambiguous capture lives in `Fixtures/InkReview` with an explicit
confirmation/visible-recovery contract, not in the accepted 660-fixture
correct-primary archive. It is repair-guiding, single-writer evidence. Its
triangle passes 32 direction/start/scale variations, and the complete capture
passes eight scale/direction variations without replacing the native primary.

V17 validation: native full suite 1,410 selected / 1,351 passed / 59
explicit opt-in skips / zero failures; SwiftPM 990 selected / 937 passed / 53
opt-in skips / zero failures; exact-source native replay and focused policies
109 selected / 108 passed / one optional archive skip / zero failures; Release
transport/privacy/configuration and new recognition regressions 22/22.
The separate full nine-condition archive, identity and glyph-rank audit passes
all three selected tests. All 660 identity primaries remain correct (383 trusted,
277 requiring confirmation). Across 5,940 deterministic recognition attempts,
there are zero trusted-wrong results and zero hidden correct recoveries;
transformed inputs still include manual-only confirmations and no-reads.
The unchanged final source manifest contains 873 files with SHA-256
`71f3511f7d7765fd2fe95b2314c1976f7642d3d1f9cd5b55124ca6d9d0146982`.
V17 is not installed, signed for distribution, uploaded or pushed. V16's
physical startup/preservation and production transport proofs do not become
V17 hardware acceptance.

Further audits must address within-glyph stroke order/direction and candidate
role leakage. In the retained example, a root-position `7` lookalike can supply
dominant-seventh context to later numeric fallback rules; that path remains a
separate follow-up rather than being claimed fixed by the V17 review guard.
The current archive transformations preserve articulation. The
[$P research](https://depts.washington.edu/acelab/proj/dollar/pdollar.html)
motivates articulation-invariant matching experiments, not an unmeasured claim
that a replacement matcher improves iChart. MathWriting's
[dataset license](https://arxiv.org/html/2404.10690v2) is CC-BY-NC-SA 4.0; no
dataset, model or code from it has been incorporated into the shipping app.

## V18: root-role repair and expanded articulation evidence

V18 excludes the leading root column from dominant-seventh evidence in all
five affected candidate-selection fallback rules. A root-position `7`
lookalike cannot inject `1` at a major triangle, promote a later seven to `3`,
or supply context for unrelated numeric/accidental fallbacks. Actual
post-root sevens retain the existing confidence threshold, including strong
C lookalikes. No trust threshold or candidate-search budget was relaxed.

The new regressions first failed in four of five selected baseline tests
(14 assertions); the real-seventh control passed. After repair, all five pass.
The exact native saved-source replay retains `Gb△7` as a confirmation primary,
shows `Bb△7` among the first three choices, and no longer offers the manufactured
`Gb13`. The complete ambiguous capture also excludes that candidate across
the eight scale/root-direction variants. Missing B-stem evidence still does
not justify automatic B recognition.

V18 normal validation: native 1,415 selected / 1,356 passed / 59 explicit
opt-in skips / zero failures; SwiftPM 995 selected / 942 passed / 53 opt-in
skips / zero failures; initial exact-source/focused native 165 selected /
164 passed / one optional archive skip / zero failures; Release
transport/privacy/configuration and new regressions 27/27. The separate
three-test archive audit passes: all 660 identity primaries remain correct
(382 trusted / 278 confirmation), and 5,940 usual deterministic attempts
have zero trusted-wrong reads or hidden correct recoveries. Final source
equality is verified across 873 files, SHA-256
`efb7d9a621a9b44f1bc0212fa73d2902703d7599fb272261459af25d1edea433`.

The usual archive transformations preserve stroke articulation. Additional
private diagnostics link directly to this frozen V18 core and change only
point direction or stroke order inside an already-owned chord. Drawn
geometry and ascending point timing are preserved; the reordered case
reassigns the original creation cadence to the new construction order.
Both diagnostics first verify 660 correct original primaries. These are
curated repair-guiding stress variants, not independent writers, physical
Pencil latency measurements or selected XCTest acceptance gates.

| Additional diagnostic | Samples | Correct primary | Trusted wrong | No-read |
| --- | ---: | ---: | ---: | ---: |
| Reverse each stroke's point direction | 660 | 78 | 20 | 504 |
| Reverse stroke construction order | 660 | 573 | 4 | 70 |

The four order-related trusted failures lose a minor suffix inside the sharp
cluster (`CSharpMinorCaptured03`, `CSharpmCaptured03`, `ESharpmCaptured03`,
`FSharpMinorCaptured02`). Direction failures include 6/9, minor/augmented,
suspended/slash, and sharp/major-quality confusion. These failures remain
open; the older green archive cannot overrule this expanded evidence.

A private, non-shipping experiment reorients sufficiently straight,
elongated strokes to a consistent line direction. It preserves all 660
original primaries, but reversed-input trusted-wrong reads rise from 20 to
27 despite correct primaries increasing from 78 to 229 and no-reads falling
from 504 to 335. It is rejected as an unconditional pipeline change; better
coverage does not justify more confident wrong reads. No experimental input
normalizer or external point-cloud implementation has been incorporated
into V18. V18 is not installed or pushed, and V16 remains on the iPad.

## V19: detached minor suffixes and sharp construction order

The four V18 trusted-wrong order failures shared one upstream cause: greedy
sharp construction could absorb a visibly detached minor stroke when that
stroke arrived before the sharp's crossbars. V19 partitions it only when
there is a unique geometrically valid split: the remaining strokes must
form a complete two-stem/two-crossbar sharp, and the single minor-shaped
stroke must be visibly detached near its lower/right edge. It preserves
every original stroke/index and does not inject a glyph or choose a chord.
Overlapping repeated crossbars and ambiguous competing partitions stay fused.
The leading root's geometric seven lookalike is not a dominant-seven anchor.

The new original/reversed-order regression first failed with 12 assertions
on V18; the overlapping repeated-crossbar control passed. Both now pass.
Native focused validation selects 51 tests / 49 passed / two explicit
opt-in skips / zero failures. The full native suite selects 1,417 tests /
1,358 passed / 59 opt-in skips / zero failures. Release transport/privacy,
configuration and the seven prior plus two new recognition regressions pass
all 29 selected tests.

The full SwiftPM suite selects 997 tests / 944 passed / 53 explicit opt-in
skips / zero failures. The final source manifest remains byte-identical
across these gates: 873 files, SHA-256
`782ee8d41885b8914eec50b721ff3ce5b171d282f9659bcc86ffd3ba561f3590`.

The separate full archive selects all four requested tests, including glyph
rank and full-corpus clustering. All 660 identity primaries remain correct
(382 trusted / 278 requiring confirmation). Across the usual nine conditions,
5,940 attempts have zero trusted-wrong reads and zero hidden correct
recoveries. These conditions still preserve stroke articulation.

The expanded private order audit now reports 579 correct primaries, 343
trusted correct, 236 confirmation-primary correct, zero trusted-wrong reads,
three visible recoveries, eight manual-only results and 70 no-reads across
660 cases (649 changed inputs). All four reproduced sharp/minor failures
are corrected. This is a curated diagnostic, not a population accuracy or
hardware acceptance measurement; missed order-dependent reads remain.

V19's separate private reverse-each-stroke diagnostic still has 20
trusted-wrong reads, 78 correct primaries and 504 no-reads across all 660
samples. A narrower control reverses only sufficiently straight horizontal
segments (width at least four points, width/height at least 1.8, straightness
at least 0.55). It changes 430 inputs and produces 15 trusted-wrong reads,
407 correct primaries and 139 no-reads. Both preserve the underlying geometry.
This isolates a line-direction dependency worth testing separately; it is
not evidence that the earlier rejected input normalizer is safe to ship.

### Point-cloud comparison: not incorporated

A private comparison uses the unmodified, New-BSD-licensed official
[$P implementation](https://depts.washington.edu/acelab/proj/dollar/pdollar.html)
against the app's existing 33 templates, without added training data or
confidence tuning. It examines 2,228 aligned glyphs and skips 24 fixtures
without a one-to-one label/cluster mapping. Original cluster membership is
held fixed for the reversed variant, so this is not a full-pipeline test.
The native classifier includes its existing heuristics; pure $P does not.

| Matcher / input | Correct top one | Expected glyph in top three |
| --- | ---: | ---: |
| Native / original | 1,759 | 2,141 |
| Native / reversed paths | 826 | 1,265 |
| Pure $P / original | 1,278 | 1,738 |
| Pure $P / reversed paths | 1,230 | 1,720 |

Point-cloud matching is more tolerant of this direction change but materially
worse on the original captures. It is not an accepted replacement. No
external matcher or unconditional line-direction normalizer is in V19;
hardware latency and trust effects cannot be inferred from these glyph ranks.
V19 remains local, not installed, pushed or uploaded. V16 remains on the iPad.

## What this candidate fixes

Both Rhythm Section and Simple Chord Sheet use the same maximum-trust recognizer, production preparation and explicit review/render contract.

- Native-size geometry remains the primary read; transformed recovery suggestions cannot become automatic accepts.
- A supported primary read needs independent symbol evidence and all required robustness checks before trusted rendering. Ambiguous evidence remains in review.
- Original stroke chronology determines chord ownership, not glyph meaning. Completed chords must keep their exact source strokes as later entries arrive.
- Exact retained fourth/fifth-system ink was replayed through production preparation, not only isolated glyph tests. The new narrow convex D and inset-return D now produce the expected D primary.
- Broader interleaving coverage exposed three pre-existing F#/slash-bass, Gb-minor and G#-altered ownership families. The same new regressions failed on the installed baseline. V16 repairs bounded unfinished-stem construction and unequal-height neighbor ownership without relaxing trust thresholds.
- Preview choices retain trust/review state through atomic rendering. Correction memory requires explicit correction and exact geometry; deleting a chord is not recognition feedback.
- Recognition-result caching and stale-work cancellation preserve ink persistence and avoid using serialized PencilKit metadata as semantic identity.

The two new fifth-line D intents are visually inferred from retained handwriting and the preceding D-writing exercise; they are not independently user-labeled evaluation data.

## Recognition evidence and its limits

The full native ten-test archive passes on the V16 recognition core. Later finalization changes telemetry and platform compilation boundaries only; source manifests verify that the recognition, chord-service and model code are unchanged.

- 660 original curated fixtures: correct primary for all 660; 383 trusted-correct and 277 correct-primary requiring confirmation. No native identity no-reads or trusted-wrong reads.
- Nine deterministic conditions: 5,940 recognition attempts with no trusted-wrong results or hidden correct recoveries. These are repeated transformations of the same fixtures, not 5,940 independent users or writings. Transformed inputs can still need manual entry or produce no read.
- Completed ownership: 7,178 prefixes and 22,178 completed-chord checks across 110 rows at both 0.80- and 2.75-second cadences; zero ownership changes.
- Seven exact retained/fresh production-prefix row gates pass, spanning both chart styles, plus the 13-chord committed-source replay.
- Simulator identity timing: median 7.171 ms, p95 80.003 ms, maximum 323.021 ms in the archive trust audit. These are XCTest measurements, not physical Pencil latency or a promise about every device.
- Deliberately lossy thinning still produced 74/660 no-reads and 82 manual-only confirmations. Missing geometric evidence cannot safely be recovered by inventing a confident chord.

These fixtures were used to guide repairs. They are not a held-out, multi-writer accuracy study. The confirmation frequency is part of the conservative trust contract, not a 100% automatic-recognition claim.

## Final validation

The final frozen R04 candidate passes:

| Gate | Selected | Passed | Skipped | Failed |
| --- | ---: | ---: | ---: | ---: |
| Native full application suite | 1,405 | 1,346 | 59 | 0 |
| Release telemetry/privacy/configuration | 20 | 20 | 0 | 0 |
| Release 660-fixture identity archive | 1 | 1 | 0 | 0 |
| Thread Sanitizer, including retained fifth line and transport | 129 | 129 | 0 | 0 |
| SwiftPM XCTest suite | 985 | 932 | 53 | 0 |
| Telemetry ingest Node contract | 12 | 12 | 0 | 0 |

Skips are explicit opt-in live-service, fixture/replay and specialized test gates, not failures counted as passes. The secondary Swift Testing runner's zero-test line is not used as XCTest proof.

Release static analysis succeeds with zero errors and zero analyzer findings. Nine compiler warnings remain: six existing UIDevice actor-isolation annotations, two existing SDK deprecations, and the unreachable Simulator-preview branch outside Debug Simulator builds. This is not a warning-free build or proof of all production races.

The command-line build boundary was repaired without removing native iPad tests: app-only preview helpers are unavailable to SwiftPM, and UIKit-only tests now use appropriate platform guards.

## Physical QA delivery checkpoint

After the user returned and confirmed readiness for native signing approval, a separate copy of the exact tested unsigned Release app was development-signed. Strict deep signature verification, the expected certificate/profile and exact QA entitlements all pass. All 44 executable sections retain identical bytes and geometry, and every original resource remains byte-identical. The pipeline is V16; no rebuild, recognition edit, credential-document access or keychain-permission change was needed.

The app installed and launched on the physical iPad at 20:53 PDT on September 12. Native process inspection matches the newly installed V16 bundle. This is a development-signed Release QA build, not an App Store distribution artifact.

The fresh preinstall library is 230,144 bytes; it is the preservation baseline for this installation, not the older 269,115-byte snapshot. All 10 backed-up files are byte-identical before and after installation/prelaunch. All eight existing non-diagnostic files, including the library, correction memory and PDFs, remain byte-identical after startup. Only the local performance trace and telemetry queue changed.

Fresh natural-size writing, later-system behavior, dense-page Pencil feel, review/render, correction, erasure and post-writing cold-relaunch persistence still require user-observed acceptance in both styles. Install/launch and unchanged pre-existing documents do not prove those behaviors.

## Telemetry for the trial

Normal Release telemetry is enabled outside XCTest. Both signed-out and signed-in clients use the configured production endpoint; signed-out requests use the public `apikey` without a fabricated bearer session. Signed-in requests use the actual user-session JWT.

Production ingest v9 is already deployed under the user's explicit diagnostic-field approval. Real pre-V13 preview events demonstrate retention and scalar types for pipeline/trust/review/root-issue fields; this is transport/storage proof, not handwriting accuracy or V16 hardware acceptance. No synthetic recognition events were injected to manufacture that proof.

The new physical Release startup also reached production. A read-only query matched this exact installation: one real signed-out `app.launched` event with V16, `release_build`, iPadOS and the physical iPad model; both version/source retain JSON string types. It occurred at 03:53:07 UTC and was received at 03:53:08.551 UTC on September 13. There were no V16 startup rows in the preceding prelaunch query. This proves the ordinary signed-out Release transport/storage path on hardware, not external-user collection, recognition accuracy or a new live signed-in acceptance gate.

The final client adds:

- An `app.launched` pipeline version and `source` of `debug_build` or `release_build`, joinable to the same installation/session.
- Content-free preparation failures, excluding cancellation, erased/empty ink and barline-only ink. No target means an unknown intended-chord denominator; no invented no-read count.
- Version/style context on preview, review, render/discard and commit events.
- Rendered correction categories attributed to the original stored read version when known. Legacy and manual entries remain unattributed. Imported metadata must match a bounded pipeline-version format, so arbitrary chart content cannot cross this field.
- Persistent best-effort retries after offline/failing requests and on foreground activity, using original event IDs. Successful batches remove acknowledged events without losing concurrent appends.
- Bounded requests: up to 40 events and 120,000 bytes per batch, up to four batches per flush, 15-second request timeout and a 1,000-event persisted queue. This is not a guarantee that every event is delivered under indefinite offline use or app termination.

Diagnostics do not upload chord strings, chart titles, artist names, raw strokes/drawings, screenshots, PDFs or editable chart documents. Raw local glyph/stroke diagnostic recording remains Debug-only and is not enabled for customers.

`release_build` identifies a build configuration, not an external person. Exclude known internal installations—including development-signed Release QA—from user-cohort reporting. Use the exact pipeline and session build source, split chart styles, and keep attempt/batch/snapshot metrics distinct. Cache hits, repeated previews and retries are not new writings.

Review/no-read/correction/render rates and recognition timings are useful trial signals. They are not measured recognition accuracy without independently labeled intended chords. A correction can also be editorial; its category must be retained rather than treating every edit as a misread.

## Privacy and backend checks

The actual app-owned `PrivacyInfo.xcprivacy` is packaged at the Release app root. It declares non-tracking linked first-party data collection and required reasons for own-container file metadata, elapsed timing and own-app UserDefaults. Dependency manifests remain present separately.

The local privacy notice now discloses installation/session identifiers, signed-in account linkage and recognition diagnostics. The hosted policy is still the August 13 version; this local change has not been deployed. Verify hosted notice and App Store Connect privacy answers before distributing to new users.

Production telemetry is RLS-enabled and server-only: anon/authenticated clients have no direct SELECT/INSERT grants; service role ingests events. The existing security advisory for RLS without client policies is intentional for this server-only table. No auth, billing or table-grant changes were made.

The private 180-day cleanup helper exists, but there is no matching scheduled cleanup job. Approval to enable a daily telemetry-only retention job is outstanding; no purge or schedule was run. Do not claim automatic 180-day retention.

## Remaining release gates

1. Fresh V16 physical acceptance in both styles: write B/C/D/G and modifiers at natural size and pace, continue through later systems, check incomplete previews versus completed reads, Review & Render, correction, erasure, dense-page Pencil feel and cold-relaunch persistence. Use a throwaway chart for destructive layout tests; keep the evidence charts intact.
2. Confirm TestFlight beta versus App Store free-trial distribution. TestFlight is useful for real handwriting feedback, but purchases use sandbox and do not measure normal trial conversion or revenue.
3. Verify the current App Store Connect build number and assign a unique upload build before the signed distribution archive/export. The local engineering archive remains 1.2.1 (51); it is not upload-ready.
4. Publish/verify the privacy notice and review store privacy metadata, then authorize upload/distribution. The existing subscription/free-trial system was not changed, and no new live purchase or sandbox transaction was exercised in this pass.

The currently installed physical candidate is V16. The original unsigned Release archive remains preserved separately, and App Store Release signing settings were not changed. The earlier canceled signing attempts are historical delivery failures, not failures of this now-signed QA artifact. Fresh V16 recognition acceptance and distribution remain unproven.

## Source and GitHub handoff

Final R04 source manifest: 871 app/test/configuration/contract/privacy files; SHA-256 `b1b570d6c8671172c2104d227de09c458a8cf661c981b2ab29f399e7c8396ad9`. Documentation is excluded. Before/after source equality is verified across all final gates. A fresh postchecks device copy also remains byte-identical to the preflight library.

The V16 full archive, final test summaries, source manifests, unsigned Release archive and private device evidence are retained outside the repository in local QA. Do not add chart-library snapshots, diagnostic JSONL, PDFs, screenshots, signing material or real installation identifiers to this public repository. Newly added fixtures contain only deidentified chord geometry, expected labels and rebased relative timing.

At the initial pre-push inspection, remote main matched local main and the branch had no remote head. The engineering checkpoint is committed locally as `05a4d95`; the physical delivery report follows without application-source changes. Older PR/Actions results are not this candidate's CI. GitHub push, pull request, hosted privacy deployment, upload, distribution and App Store submission have not been performed.

## Primary references

- [Apple app privacy details](https://developer.apple.com/app-store/app-privacy-details/).
- [Apple required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
- [Supabase publishable API keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys).
- [Supabase Edge Function authentication headers](https://supabase.com/docs/guides/functions/auth-headers).
- [TestFlight subscription testing uses sandbox](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight).
