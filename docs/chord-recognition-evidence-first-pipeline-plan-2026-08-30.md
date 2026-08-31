# Chord Recognition Evidence-First Pipeline Plan

Date: 2026-08-30
Branch: `codex/chord-evidence-first-pipeline`
Status: active experiment

## Purpose

This branch tests whether the current deterministic recognizer can become more trustworthy by adding evidence ownership before candidate trust. The failed strict role-parser pass showed that replacing the recognizer with a new parser is too brittle for live handwriting. This plan keeps the existing recognizer, parser, compendium, root-led grouping, trace layer, and explicit Render Chords flow, then adds a narrower evidence gate that can reject impossible ink stories before they become trusted previews.

The primary product target is wrong-read prevention. A no-read or confirmation is acceptable. A confident wrong preview is not.

## Current Authority

This document extends, but does not replace, the active recognition authority in:

- `docs/chord-recognition-trust-protocol-2026-08-25.md`
- `docs/chord-recognition-accuracy-branch-plan-2026-08-25.md`
- `docs/chord-recognition-music-theory-context-evidence-2026-08-25.md`
- `docs/chord-lane-auto-render-course-correction-2026-08-21.md`

Historical OCR/Scribble/trust-arbiter notes remain history only.

## Hard Boundaries

- No OCR, Vision text recognition, or `VNRecognizeTextRequest`.
- No `PKStrokeRecognizer` or iOS 27 dependency in this branch.
- No lane-level Scribble recognition.
- No chord lane UI churn.
- No implicit rendered chart mutation. Draft recognition remains preview-only until explicit Render Chords / Auto Render.
- No edit-mode, terminal barline, ink persistence, sync, measure resize, or layout-guide changes unless a direct recognition-validation blocker is documented first.

## Decision

Do not rebuild the recognizer as a strict parser. Add an evidence-first veto layer after glyph/context generation and before final candidate matching/trust.

The layer may:

- Require a candidate to be explainable by the role evidence already visible in the ink.
- Reject impossible reuse of one cluster as multiple incompatible roles.
- Keep ambiguous candidates available for diagnostics and confirmation where useful.
- Force confirmation/no-read rather than trust when the evidence story is incomplete.

The layer must not:

- Invent a candidate that glyph/context/composer evidence did not support.
- Remove valid typed/imported chord spellings from `ChordSymbolParser` or `ChordRecognitionCompendium`.
- Penalize all uncommon spellings globally. A handwritten `Cb` is valid only when there is lowercase-flat evidence in the root accidental role.

## Pipeline Target

The intended live flow is:

1. `PKDrawing`
2. recognition frame identity and stale-result rejection
3. visible-stroke filtering
4. draft-barline detection/removal
5. target routing and root-led grouping
6. stroke clustering
7. glyph candidate ranking
8. semantic glyph context
9. role evidence ledger
10. role-constrained candidate selection/composition
11. evidence vetoes for impossible role reuse
12. parser/compendium validation
13. trust policy
14. draft-preview reducer
15. explicit Render Chords / Auto Render commit

## Evidence Rules For This Slice

- A handwritten uppercase `B` candidate is never flat evidence after a root. Lowercase `b` remains valid flat evidence.
- A slash-bass chord requires explicit slash separator evidence followed by a separate `A-G` bass-root role. A root-sized `7` or triangle fragment cannot become `/C`.
- A `7` role cannot also prove a slash separator or bass root.
- A triangle-owned quality cluster cannot also prove diminished, half-diminished, slash separator, or bass-root evidence.
- Diminished and half-diminished quality require round-quality evidence, not only a triangle or digit tail.
- Detached root-sized `A-G` pressure after an active chord is not allowed to become a suffix/accidental for the previous chord unless an explicit attached suffix role protects it.
- Preview publication should expose a proposal only when the recognizer has a supported match or a clear confirmation candidate. Raw unsupported candidate strings are diagnostics, not display authority.

## Implementation Steps

1. Add this source-of-truth document and link it from the trust protocol.
2. Add pure tests for evidence vetoes around `C D -> Cb`, `Eb△7 -> Eb°/C`, `Bb△7 -> half-dim/slash`, `D/F#` versus `B/F#`, uppercase `B` as flat, and slash-bass ownership.
3. Add a lightweight `ChordInkCandidateEvidencePolicy` that consumes candidate text, selected glyphs, all glyph columns, clusters, and `ChordInkTheoryRoleContext`.
4. Wire the policy into `ChordInkRecognitionCandidateComposer` after semantic candidates are merged and before final sorting.
5. Tighten preview publication so draft preview payloads require a supported match or ranked supported confirmation candidate, not just non-empty raw candidates.
6. Run focused recognition tests, full archive gate, trace replay if a trace file is present, `xcodegen generate`, `git diff --check`, and a simulator `xcodebuild` with `xcresulttool` proof.
7. Build/install/launch Debug on the attached iPad for live validation before making any accuracy claim.

## Drift Checklist

- [x] Branch created from clean post-revert state.
- [x] No OCR/Vision lane recognizer added.
- [x] No `PKStrokeRecognizer` dependency added.
- [x] Role grammar experiment remains reverted.
- [x] Evidence-veto tests added before behavior changes.
- [x] Evidence policy wired without UI/render/persistence churn.
- [x] Focused Swift tests pass with nonzero selected cases.
- [x] Full fixture archive pass recorded.
- [x] `xcodegen generate` and `git diff --check` pass.
- [x] Simulator XCTest pass recorded with `xcresulttool` nonzero/zero-failure proof.
- [x] Physical iPad Debug build/install/launch recorded.
- [ ] Current C7(b9) followed by next-chord no-read pass records stable preview preservation.
- [ ] Current major-triangle pass records angular `△` evidence not being reused as diminished/half-dim/slash evidence.

## Implementation Log

### 2026-08-30 Evidence-First Experiment

Observed facts:

- Added `ChordInkCandidateEvidencePolicy` as a veto-only stage after candidate composition and before final candidate sorting.
- Tightened draft-preview publication so unsupported raw strings cannot create visible preview payloads.
- The first full-archive run failed because the evidence policy was too broad: it overprotected triangle candidates, blocked valid alteration-flat evidence after `7`, and blocked known slash-bass fixtures when the slash column also ranked as `7`.
- The policy was narrowed to preserve known archive behavior: alteration accidentals after extensions are protected, actual slash-shaped strokes can own slash-bass despite `7` lookalikes, and same-column circle/triangle/sixth conflicts only veto when the competing evidence is stronger enough for that role.

Verification:

- Focused recognition/provider gate: `swift test --scratch-path /tmp/iChartSwiftBuild-evidence-first-focused --filter 'ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'` passed with 136 selected tests, 1 expected full-archive skip, and 0 failures.
- Opt-in full archive gate: `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-evidence-first-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'` passed with 84 selected tests and 0 failures.
- Forbidden-path grep found no live production OCR, Vision text-recognition, `PKStrokeRecognizer`, or lane-level Scribble recognizer path. Scribble references remain manual text/account surfaces and tests.
- `xcodegen generate` passed.
- `git diff --check` passed.
- Generated Xcode project build for Simulator passed with signing disabled: `xcodebuild -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartEvidenceFirstSimulatorDerivedData CODE_SIGNING_ALLOWED=NO build`.
- Physical-device Debug build compiled through the device target, then stalled at local `codesign` using `Apple Development: Benjamin Rossman (8BHT3N56XX)` and `iOS Team Provisioning Profile: com.ichart.app`. Direct `codesign` of the built app also stalled. This is signing/keychain evidence, not recognizer-source failure.

Open:

- Run simulator XCTest with `xcresulttool` proof if this branch proceeds past exploratory live testing.
- Complete a signed Debug install/launch on the physical iPad, then collect trace evidence from live handwriting before making any accuracy claim.

### 2026-08-30 Live Trace Follow-Up: No-Read Preservation And Triangle Ownership

Observed facts:

- The pulled physical-iPad trace for the reported `Ebmaj7` failure showed a real distinction between the failed and successful attempts. The failed target ended as `Eb°7` with weak triangle evidence in the quality column, while the successful rewrite preserved a strong `△` column and ended as `Eb△7`.
- The same trace showed `C7(b9)` was initially recognized and trusted, then later right-side ink for the next intended chord was absorbed into the existing target. Once the expanded target became unsupported/no-read, preview replacement output omitted the previous `C7(b9)`.
- That disappearing-preview behavior was not purely a recognizer issue. The branch had changed draft-preview publication to filter out unsupported/no-read payloads before they reached `ChordPreviewState.replaceDraftChords(with:)`, preventing the existing stale-read preservation path from running.

Implementation direction:

- Draft-preview callbacks should pass any non-empty recognizer payload through to the reducer. Unsupported candidate strings remain non-display diagnostics because `EditorView` builds draft inputs through `ChordInkRenderResolutionPolicy`; no supported match means the input is unresolved, not a visible wrong chord.
- The preview reducer must preserve a previously readable draft when a later absorbed target becomes no-read, matching the existing preservation rule for absorbed targets that change to a different visible chord.
- Major-triangle protection should be geometry-owned, not globally score-owned. If a quality cluster has angular triangle construction, `△` remains valid even when round-quality candidates score higher, and `°/ø` candidates cannot reuse those strokes. If the cluster is round, diminished and half-diminished protections still apply.

Risks:

- This does not by itself prove the next `Cdim7` root boundary. It prevents the prior `C7(b9)` from disappearing when the next target is unresolved, while later grouping work must still decide whether the new root should split earlier.
- Overprotecting triangle globally would damage valid diminished/half-diminished reads. The implementation must require actual angular geometry before overriding stronger round-quality candidates.

Validation required:

- Focused draft-preview and candidate-composer tests for no-read preservation and angular triangle ownership.
- Full recognition/archive gates to ensure diminished and half-diminished fixtures do not regress.
- Fresh physical-iPad trace using `Eb△7`, `Bb△7`, `C°7`, `Cø7`, and `C7(b9)` followed by a separate next chord before claiming the slice works on real handwriting.

Implementation:

- Restored draft-preview callbacks to pass any non-empty recognition payload into `ChordPreviewState` instead of filtering out unsupported/no-read payloads in `LeadSheetCanvasHostView`.
- Added no-read-only preview preservation in `ChordPreviewState`: a previous readable draft is preserved when a later unresolved target absorbs its strokes at a detached right-side gap. Visible wrong-read changes still use the stricter existing detachment threshold.
- Added angular triangle ownership evidence in `ChordInkCandidateEvidencePolicy`. A quality cluster with two opposing diagonal sides plus a base/corner coverage, or a single-stroke closed/open triangle gesture, can keep `△` valid even when round-quality candidates score higher. The same angular ownership blocks `°/ø` candidates from reusing those strokes.

Verification:

- `swift test --scratch-path /tmp/iChartSwiftBuild-evidence-first-focused3 --filter 'ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkRecognizerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordInkSequentialGrouperTests|ChordInkRecognitionTraceTests'`
  - Result: pass, 175 selected tests, 4 expected opt-in trace/archive skips, 0 failures.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-evidence-first-full2 --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkCandidateComposerTests|ChordInkTheoryRoleContextTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests|ChordInkRecognitionTraceTests'`
  - Result: pass, 100 selected tests, 3 expected trace-env skips, 0 failures.
- `xcodegen generate`
  - Result: pass; regenerated `iChart.xcodeproj` from `project.yml`.
- `git diff --check`
  - Result: pass, no whitespace errors.
- Physical-device build/install/launch after lane-identity fix:
  - Build: `xcodebuild -quiet -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartEvidenceFirstDevice-20260830-laneid -allowProvisioningUpdates build`
  - Result: pass, with existing unrelated LibraryView and telemetry warnings.
  - Code signing: `codesign --verify --deep --strict --verbose=2 /tmp/iChartEvidenceFirstDevice-20260830-laneid/Build/Products/Debug-iphoneos/iChart.app`
  - Result: valid on disk and satisfies its Designated Requirement.
  - App identity: `com.ichart.app`, version `1.2`, bundle version `50`.
  - Binary proof: `strings .../iChart | rg 'ChordInkCandidateEvidencePolicy|lane_root_sequence|minimumUnresolvedAddedStrokeGap'` found `ChordInkCandidateEvidencePolicy`, `measure_lane_root_sequence`, and `lane_root_sequence`.
  - Install: `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartEvidenceFirstDevice-20260830-laneid/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, installed `com.ichart.app`.
  - Launch: `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB --terminate-existing com.ichart.app`
  - Result: pass, launched `com.ichart.app`.
- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartDerived-evidence-first-triangle-20260830-1613 -resultBundlePath /tmp/iChartEvidenceFirstTriangle-20260830-1613.xcresult -only-testing:iChartTests/ChordInkDraftPreviewTests/testDraftStatePreservesReadableDraftWhenExpandedInkBecomesNoRead -only-testing:iChartTests/ChordInkDraftPreviewTests/testDraftStatePreservesReadableDraftWhenDetachedInkAbsorbsAndChangesRead -only-testing:iChartTests/ChordInkCandidateComposerTests/testRecognitionComposerProtectsAngularTriangleWhenRoundQualityCandidateScoresHigher -only-testing:iChartTests/ChordInkCandidateComposerTests/testRecognitionComposerRejectsHalfDiminishedWhenTriangleOwnsQualityCluster -only-testing:iChartTests/ChordInkCandidateComposerTests/testRecognitionComposerStillAllowsOwnedHalfDiminishedQuality test`
  - Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartEvidenceFirstTriangle-20260830-1613.xcresult --format json`
  - Result: `totalTestCount = 5`, `passedTests = 5`, `failedTests = 0`, `skippedTests = 0`.
- Physical-device build/install/launch:
  - Device: Ben's iPad `376D59F8-92F2-5260-B10E-BA0BEAF941AB`, available and paired.
  - Build: `xcodebuild -quiet -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartEvidenceFirstDevice-20260830-1616 -allowProvisioningUpdates build`
  - Result: pass, with existing unrelated LibraryView and telemetry warnings.
  - Code signing: `codesign --verify --deep --strict --verbose=2 /tmp/iChartEvidenceFirstDevice-20260830-1616/Build/Products/Debug-iphoneos/iChart.app`
  - Result: valid on disk and satisfies its Designated Requirement.
  - App identity: `com.ichart.app`, version `1.2`, bundle version `50`.
  - Binary proof: `strings .../iChart | rg 'ChordInkCandidateEvidencePolicy|lane_root_sequence|root-construction-targeting'` found `ChordInkCandidateEvidencePolicy`, `measure_lane_root_sequence`, and `lane_root_sequence`.
  - Install: `xcrun devicectl device install app --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB /tmp/iChartEvidenceFirstDevice-20260830-1616/Build/Products/Debug-iphoneos/iChart.app`
  - Result: pass, installed `com.ichart.app`.
  - Launch: `xcrun devicectl device process launch --device 376D59F8-92F2-5260-B10E-BA0BEAF941AB --terminate-existing com.ichart.app`
  - Result: pass, launched `com.ichart.app`.

### 2026-08-30 Device Pass: C Preview Stability And Lane Identity

Observed facts:

- Pulled the current physical-iPad diagnostics from `com.ichart.app` into `/tmp/ichart-device-pass-20260830-1622`.
- The trace file was current for the user pass: `Library/Application Support/iChart/chord-draft-preview-debug.jsonl`, 102 events, last modified at 2026-08-30 16:22 local time.
- Replaying the pulled trace with `ICHART_CHORD_DRAFT_TRACE_FILE=/tmp/ichart-device-pass-20260830-1622/chord-draft-preview-debug.jsonl swift test --scratch-path /tmp/iChartSwiftBuild-current-device-trace-20260830-1622 --filter 'ChordInkRecognitionTraceTests'` failed the stability gate:
  - `previewDroppedRenderableRead`: pass 19 target 2 changed from `C°` to no preview.
  - `targetAbsorbedPreviouslyReadableRead`: pass 8 target 1 changed from `Bb△7` to `Bb△11`.
  - `targetAbsorbedPreviouslyReadableRead`: pass 11 target 1 changed from `Bb△7` to `Bb△13`.
- The C concern is real in the trace. A second-lane one-stroke target first published as `C` with confidence 3.965, then the same local target became `C°` and finally `C°7` as additional close strokes were added.
- The final preview replacement for that second-lane target reused the first-lane `Eb△7` draft id because `ChordInkDraftAnchor` only included `measureID` and fraction bucket. Lane/system index was not part of draft identity, so same-measure same-fraction targets on different rows could collide.
- Raw glyph evidence for the second-lane target was not a missing-C failure: column one had `C:0.96` heuristic evidence. The instability came from later close columns scoring as `°`/`•` and `7`, allowing a legal-looking `C°7` suffix sequence to dominate.
- Telemetry for the final preview update marked all six targets as trusted with zero no-read, confirm, generated-sequence-limit, or close-race counts. That means current trust policy did not catch the C/dim ambiguity.

Implementation:

- Added lane/system index to `ChordInkDraftAnchor`, using explicit `laneLocation.systemIndex` when available and falling back to the integer part of `visualOrder`.
- Updated anchor bucketing to use lane-local fraction when available, preventing first-lane and later-lane draft ids from colliding at the same horizontal fraction.
- Tightened draft-continuity scope so two drafts with different known lane indices cannot absorb/preserve across rows.

### 2026-08-30 C Root-Position Evidence Slice

Observed facts:

- The current post-lane-identity iPad trace still showed the intended second-lane `C°7` beginning with unstable root-column evidence. The first one-stroke target was accepted as `C`, but the raw glyph column ranked heuristic `b:0.98` over heuristic `C:0.95`.
- That means the C issue was not caused by draft-lane identity, render state, or downstream preview replacement. It was a first/root glyph evidence ordering problem that later suffix evidence happened to recover in some cases.
- The same trace still had one separate non-C stability failure: a previous `Eb△7` target could be absorbed into `Eb△13`. That remains a triangle/extension continuity issue, not solved by this C-root slice.

Implementation:

- Added first-column-only contextualization in `ChordInkSemanticGlyphContextualizer`: when strong heuristic `C` root evidence is narrowly losing to a strong heuristic `b` lookalike, promote `C` just above `b`.
- Kept real flats protected by limiting the promotion to root position only. A second-column `b` after an owned root remains flat accidental evidence.
- Tightened `ChordInkCandidateSelectionPolicy` so a strong first-column root candidate is moved to the front even when it was already inside the selected prefix. Previously the policy removed `b/#` lookalikes but could leave `C` behind a higher-scored non-root lookalike.
- Removed dead contextualizer state that produced a repeated compiler warning.

Verification:

- `swift test --scratch-path /tmp/iChartSwiftBuild-c-root-evidence --filter 'ChordInkSemanticGlyphContextualizerTests|ChordInkCandidateComposerTests|ChordInkRecognizerTests|ChordInkSequentialGrouperTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
  - Result: pass, 155 selected tests, 1 expected full-archive skip, 0 failures.
- `ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-c-root-evidence-full --filter 'ChordInkRecognizerTests/testRecognizesFullInkFixtureArchiveWhenEnabled|GestureTemplateRecognizerTests/testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled|StrokeClustererTests/testClustersFullInkFixtureArchiveWhenEnabled|ChordInkSemanticGlyphContextualizerTests|ChordInkCandidateComposerTests|ChordInkTrustAcceptanceTests|ChordRecognitionProviderBoundaryTests'`
  - Result: pass, 80 selected tests, 0 failures.
- `xcodegen generate`
  - Result: pass; regenerated `iChart.xcodeproj` from `project.yml`.
- `git diff --check`
  - Result: pass, no whitespace errors.
- Simulator XCTest:
  - Command: `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartDerived-c-root-evidence -resultBundlePath /tmp/iChartCRootEvidence.xcresult -only-testing:iChartTests/ChordInkSemanticGlyphContextualizerTests -only-testing:iChartTests/ChordInkCandidateComposerTests/testRootSelectionMovesStrongCBeforeFlatLookalikeInFirstColumn -only-testing:iChartTests/ChordInkCandidateComposerTests/testRootSelectionDoesNotMoveSecondColumnFlatAccidental test`
  - `xcresulttool` summary: `totalTestCount = 7`, `passedTests = 7`, `failedTests = 0`, `skippedTests = 0`.
- Physical iPad Debug build/install/launch:
  - Device: Ben's iPad `376D59F8-92F2-5260-B10E-BA0BEAF941AB`, available and paired.
  - Build: `xcodebuild -quiet -project iChart.xcodeproj -scheme iChart -configuration Debug -destination 'platform=iOS,id=376D59F8-92F2-5260-B10E-BA0BEAF941AB' -derivedDataPath /tmp/iChartEvidenceFirstDevice-20260830-croot -allowProvisioningUpdates build`
  - Result: pass, with existing unrelated `LibraryView` and telemetry warnings.
  - Code signing: app bundle is valid on disk and satisfies its Designated Requirement.
  - App identity: `com.ichart.app`, version `1.2`, build `50`.
  - Binary proof: `strings .../iChart | rg 'ChordInkCandidateEvidencePolicy|lane_root_sequence|minimumUnresolvedAddedStrokeGap|ChordInkSemanticGlyphContextualizer'` found `ChordInkCandidateEvidencePolicy`, `ChordInkSemanticGlyphContextualizer`, `measure_lane_root_sequence`, and `lane_root_sequence`.
  - Install: pass, installed `com.ichart.app`.
  - Launch: pass, launched `com.ichart.app`.

Open:

- Physical iPad acceptance is still required for this slice. Test plain `C`, repeated `C D`, `C°7`, `Cø7`, real flats such as `Cb`/`Bb`, and `C7(b9)` followed by a separate next chord.
- The prior `Eb△7 -> Eb△13` absorption issue remains outside this C-root fix and should be checked separately after the C behavior is confirmed.
- Added `testDraftStateKeepsLaneSpecificDraftIdentityWhenFractionsOverlap` to prove same-measure same-fraction targets on different lanes keep distinct draft ids.

Verification:

- `xcodebuild -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=0D3454BE-1A21-4910-8FD6-FFD3EB43E908' -derivedDataPath /tmp/iChartDerived-preview-lane-identity-20260830 -resultBundlePath /tmp/iChartPreviewLaneIdentity-20260830.xcresult -only-testing:iChartTests/ChordInkDraftPreviewTests/testDraftStateKeepsLaneSpecificDraftIdentityWhenFractionsOverlap -only-testing:iChartTests/ChordInkDraftPreviewTests/testDraftStatePreservesReadableDraftWhenExpandedInkBecomesNoRead -only-testing:iChartTests/ChordInkDraftPreviewTests/testDraftStatePreservesReadableDraftWhenDetachedInkAbsorbsAndChangesRead -only-testing:iChartTests/ChordInkDraftPreviewTests/testDraftStateReplacesBatchAndPreservesEditedTextByAnchor test`
  - Result: pass.
- `xcrun xcresulttool get test-results summary --path /tmp/iChartPreviewLaneIdentity-20260830.xcresult --format json`
  - Result: `totalTestCount = 4`, `passedTests = 4`, `failedTests = 0`, `skippedTests = 0`.
- `git diff --check`
  - Result: pass, no whitespace errors.

User intent update:

- The user confirmed the second-lane target was intended to be `Cdim7`. The recognizer's final `C°7` display for that target was therefore semantically correct.
- The actionable bug from that part of the pass is the stale cross-lane preview identity reuse, not a missing plain-`C` recognition failure.

Remaining:

- This lane-identity fix is now installed on the physical iPad, but needs a fresh handwriting pass to prove the stale cross-lane draft-id reuse is gone in live behavior.
- Do not export the second-lane `C°7` as a plain-`C` fixture; it was an intended diminished-seventh chord.
- Continue investigating the remaining trace stability issues where `Bb△7` was absorbed into `Bb△11`/`Bb△13`.

### 2026-08-30 Device Pass: C Root Evidence Classification

Observed facts:

- Pulled the post-lane-identity physical-iPad trace into `/tmp/ichart-device-pass-20260830-c-current`.
- The trace file was current for the follow-up pass: 100 events, last modified at 2026-08-30 16:49 local time.
- Replay gate failed with one remaining stability issue, unrelated to C: `Eb△7` was absorbed into `Eb△13` at pass 21 target 3.
- The Cdim7 target sequence was semantically correct:
  - One-stroke target accepted and previewed `C` with confidence 3.95.
  - Two-stroke target accepted and previewed `C°` with confidence 5.18.
  - Three-stroke target accepted and previewed `C°7` with confidence 4.90.
- The C root glyph evidence is still weak internally. The first/root glyph column ranked `b` at 0.98 above `C` at 0.95, even though the selected chord result recovered `C` because root position cannot legally be a flat symbol.

Classification:

- This is not a target-routing or preview-reducer failure in the current trace. The target was created, recognized, and previewed.
- This is a root-column glyph evidence issue: C-shaped root strokes are still allowed to score as flat above C before role-aware selection rescues the output.
- The next C-specific fix should be root-role evidence, not a global flat demotion. In root position, a root-sized C-shaped stroke should own the root role and should not carry strong flat accidental evidence. Flat evidence must remain strong immediately after a real root.
