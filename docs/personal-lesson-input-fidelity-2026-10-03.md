# Personal lesson input fidelity

This pass fixes a reproduced storage defect in optional handwriting learning. New lessons retain the full input used by recognition instead of training and matching from a reduced thumbnail. It does not establish a handwriting accuracy improvement, explain the earlier residual model regressions, or promote an experimental learner.

## Reproduced failure

The existing profile writer stored `PersonalInkShape.normalizedStrokes`, which thins a dense stroke to roughly 128 points. The descriptor for a fresh query used every incoming point. Reloading a lesson reconstructed its descriptor from the reduced path and normalized that path again. Dropping an interior extremum could therefore change the learned shape enough that an exact replay did not match itself.

Three synthetic tests reproduced this with 129-point, 257-point, and multistroke inputs: three tests executed with six failed assertions. All three now pass immediately after learning and after JSON reload. Their arbitrary valid chord label exercises storage, not musical recognition.

## Implementation

- New `PersonalInkExample.recognitionStrokes` retains all points, order, relative timing, and declared bounds. `strokes` remains the normalized bounded thumbnail. `recognitionInput` selects the full input when present and otherwise uses a legacy lesson's existing stored path.
- Template snapshots, adaptive and visual comparison readers, support hashes, correction identity, and symbol teaching use the same recognition input. The dense encoder test checks the exact 257-point input delivered to the encoder.
- Deduplication and explicit cross-label correction compare full normalized trajectories, not thumbnails. Different dense paths with identical thumbnails remain separate lessons. Affine copies of the same complete trajectory remain idempotent.
- New contextualized lessons use provenance version 2 with `storedInputRole: recognitionInput`. Both original and stored hashes bind the retained input. Version 1 remains the old stored-input contract. V2 records with missing or null full input fail validation rather than downgrade to thumbnails.
- Selected symbol lessons retain the exact parent stroke subset and ownership indexes. The teaching preview uses full normalized geometry; selection and hit testing operate on unchanged source ink. Legacy selected-symbol records retain their earlier validation contract.
- The existing 64-stroke and 32,768-point lesson bounds remain unchanged. Invalid geometry, empty strokes, invalid timing, or a mismatched thumbnail cannot become a new valid lesson. The 8,000,000-byte profile limit is now checked before writing or publishing an edited profile; an oversized edit preserves the prior file and snapshot.
- Future captures identify the pipeline as `maximum-trust-v33-lossless-personal-lessons-2026-10-03`. The chord-only domain policy, model weights, confidence thresholds, and automatic acceptance rules are unchanged.

## Compatibility and limits

Valid legacy profiles are not migrated or backfilled. An old thumbnail cannot recover discarded points. A new dense example is not deleted or deduplicated merely because its thumbnail matches a legacy lesson. Normal existing per-label and total-example capacity policies still apply.

Lossless teaching retains more local data, including relative timing. It remains in the existing protected, backup-excluded local storage; this pass adds no upload or telemetry payload. Dense lessons can reach storage limits sooner. Model input budgets remain separately versioned: the learned feature schema's 8,192-point limit is not the lesson store's 32,768-point limit. An encoder must reject unsupported input rather than silently thin the saved lesson.

Declared bounds must be finite and ordered. This pass preserves them exactly but does not add a new requirement that they enclose every point; that would change the existing feature contract. The evaluation journal retains its existing 24,000,000-byte limit and storage-error behavior. No journal eviction or limit increase was added.

The local support receipt's `storedInkSHA256` binds the input actually encoded: legacy stored paths for old lessons and full recognition input for new ones. The frozen profile hash and versioned learning provenance distinguish these cases. Historical artifacts and score reports were not rewritten.

## Verification

The focused macOS Swift gate passed **178 tests, zero failures, zero skips**. It includes the original three regressions, nine adversarial storage tests, learning and correction safety, legacy persistence, symbol selection, learned-reader input, provenance, evaluation persistence, and chord-domain checks. Canonical packet equality verifies signed zero, fractional coordinates, timing, bounds, and every retained point through JSON and file reload.

The gate exposed and repaired two issues before the final rerun: a storage validator incorrectly inherited a model encoder's input limits, and a V2 record could fall back to a thumbnail if its optional full-input field was removed. A stale-review test was adjusted to open the review before corrupting its source; invalid profiles are now refused at opening.

The separate iPad Simulator gate passed **50 tests, zero failures, zero skips**, verified from both `xcresulttool` summary and individual test-tree entries. It exercised setup/review learning, stale and opted-out teaching, both chart-style capture adapters, lossless persistence, actual teaching views in portrait and landscape, and the pinned Core ML comparison runtime connection. The runtime integration case executed rather than skipping. The two teaching-view images were visually inspected: source ink and both symbol previews fit their frames in both orientations.

Environment: Xcode 26.6 build 17F113; iOS Simulator 26.5 on the iPad A16 simulator `0D3454BE-1A21-4910-8FD6-FFD3EB43E908`; Debug app version 1.2.1 build 51 from `project.yml`. The comparison package was explicitly opted in from the existing frozen runtime; its weights were not changed. This is an app build and Simulator test result, not a new physical-device build number or a model promotion.

Physical-device installation, Pencil interaction, and fresh handwriting accuracy are not established by this pass. No inference from the failed historical model experiments has been revised based on these synthetic checks.

## Evidence location

Worktree: `/Users/benirossman/.codex/worktrees/recognition-generalization-reset/Smart Chart`.
Branch: `codex/recognition-generalization-reset` at base commit `160aa31594903508e241802e21ca83ec447de849`, with existing uncommitted work preserved.

Local artifacts: `/private/tmp/iChartPersonalLessonFidelity-20261003.IKjgCD`.
`red.log` records the reproduced failure; `initial-green.log` and `core-gate.log` record early checks; `integration-gate.log` records a fixture compilation failure; `integration-gate2.log` records the intermediate failing gate; `integration-gate3.log` is the passing 178-test gate. Temporary artifacts may expire.

`iPad.xcresult`, `iPad.log`, `iPad-summary.json`, `iPad-tests.json`, and `attachments/` contain the 50-test Simulator evidence. The XCTest summary and test tree independently count 50 passed test cases; attachment-export messages about cases with no attachments are not skipped tests.

No physical-device data, profile, chart, prior evaluation journal, model artifact, historical experiment, or production service was changed. No commit or push was performed.

## Learning test eligibility follow up

A further flow check reproduced a mismatch between symbol teaching and evaluation. A newly taught setup glyph or explicitly selected saved symbol could not unlock an After test; only whole-chord corrections qualified. Conversely, changing an existing whole-chord lesson's source from setup to explicit correction could unlock it without adding new labeled ink. Five focused tests executed with three failed assertions before the repair.

The eligibility check now accepts a new setup glyph, explicitly taught selected glyph, or whole-chord explicit correction relative to a completed baseline from the same profile generation. It validates the input and supported label, then compares the complete normalized trajectory, label, and kind against the frozen baseline. Merely toggling settings, changing revision or source, reordering or deleting examples, and resaving identical labeled ink do not qualify. Automatic review confirmations and unused practice sources do not qualify either. Disabled or reset profiles still cannot use the old baseline.

The interface now says Before learning and After learning and describes symbol teaching as well as whole-chord correction. Stored phase values remain `beforeCorrections` and `afterCorrections`; this change does not rewrite historical runs or their frozen profiles. Eligibility means explicit learning exists, not that learning was useful or that two runs constitute a controlled accuracy comparison.

The initial repaired gate passed 64 Swift tests with zero failures, including the five new cases, evaluation persistence, exact lesson storage, and the chord-only domain policy. Separately, a read-only compatibility test loaded all 68 examples from the preserved build 57 profile with no changes to its bytes or lesson inputs. All 68 are legacy lessons; this check cannot restore points discarded before the storage fix and does not establish the current iPad's state.

The expanded app-level follow-up passed 142 iPad Simulator tests with no failures or skips, verified through both the result summary and test tree. Eight eligibility tests now cover actual selected-symbol teaching, saved setup learning and journal reload, duplicates and affine copies, source-only upgrades versus real relabeling, invalid input and labels, opt-out, administrative changes, and profile reset. Old serialized phase names are preserved. A subsequent chord-only scored-candidate repair passed a separate overlapping 331-test Simulator gate; see `chord-reader-domain-boundary-2026-10-03.md` for that change and its evidence limits.

Development build 58 compiled and passed signature verification before the eligibility change. Build 59 supersedes it with that change and the updated interface text; it also compiled and passed signature verification. Both used version 1.2.1. The build 59 comparison resources are byte-identical to the existing frozen runtime. The Mac reports the physical iPad as unavailable, so neither build was installed or launched there and no device data was changed.

Current local artifacts are under `/private/tmp/iChartLessonFidelityDevice-20261003.zI1r7N`: `after-learning-red.log`, `after-learning-green.log`, `profile-compatibility.log`, `AfterLearning-iPad.xcresult`, `AfterLearning-summary.json`, `AfterLearning-tests.json`, and the build logs. After the final scored-candidate repair, the signed app at `DerivedData/Build/Products/Debug-iphoneos/iChart.app` is build 60, which supersedes the uninstalled builds 58 and 59. Build 60 compiled and passed signature verification; its model resources remain unchanged. The final iPad availability check still failed, so the new app has not been installed or launched on the physical device.
