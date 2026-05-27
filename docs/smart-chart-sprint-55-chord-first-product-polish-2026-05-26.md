# Smart Chart Sprint 55: Chord-First Product Polish

Status: implemented locally; placement/snapping, placement-evidence diagnostics, and audit-tooling slices ready for CI
Date: 2026-05-26
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Goal

Keep the product roadmap centered on chord work: write, recognize, snap, fix, render, and export chord symbols cleanly.

## Product Direction

The next sequence should prioritize chord-related features over general app-shell work:

- Placement and snapping: chords should land where the writer expects.
- Raster/render time: recognized chords should appear quickly after the commit decision.
- Accuracy and confidence: trust decisions should stay writer-agnostic and evidence-based.
- Confirmation and correction: wrong or ambiguous reads should recover without trapping the user.
- Export fidelity: exported charts should preserve structured chord placement, not card-like blocks.

## Sprint 55 Slice

Start with placement/snapping.

Reason: if a chord lands in the wrong rhythmic location, it feels wrong even when recognition is correct. Placement is also easier to improve with general geometry/rhythm evidence than handwriting-specific score tuning.

## Implementation

- Change rhythm-map placement snapping to choose the nearest playable rhythm-slot attack/start position, not the slot midpoint.
- This improves long-slot cases such as quarter, quarter, half where a chord written near beat 3 should snap to the half-note slot at beat 3 instead of the previous quarter slot.
- Record chord placement evidence in chord-entry diagnostics: start position, duration, rhythm placement, and mapped rhythm-slot index when available.
- Placement evidence lets the next real pass audit where a chord actually landed without expanding the handwriting fixture corpus or retuning recognition scores.
- Surface placement evidence in `scripts/audit_chord_entry_diagnostics.py --details` so pass review can see each rendered chord's final start, duration, rhythm placement, and one-based rhythm slot.
- Report missing or mismatched placement evidence by comparing active diagnostics against the current rendered chart state.
- Summarize available timing evidence by slowest delay, idle, recognition total, proposal, commit, and render handoff so render/performance review starts from metadata instead of impressions.
- Tighten compact suspended-chord candidate availability from transferable field evidence: `Absus` failures were missing `Absus` from suggestions or losing to slash-bass lookalikes, so semantic suspended candidates now consider nearby plausible root letters and add cautious `sus` candidates without raising them into auto-render.
- Soften slash-bass candidates when the slash column also carries suspended-`s` evidence, allowing `Absus`/neighboring suspended candidates to compete instead of letting a slash lookalike silently steal the result.
- Improve chord-entry live ink persistence by letting `PKCanvasView` own active strokes while the Pencil is moving, blocking stale chart-data reloads during unpersisted chord ink, and syncing the chart's chord-ink snapshot at the idle recognition boundary. The original chord-entry pen tool and weight are preserved.
- Keep chord entry Pencil-only on real iPad/device builds so trackpad, mouse, or cursor input cannot enter the chord ink stream during field testing. Simulator builds keep pointer input enabled for automation and smoke tests.
- Preserve recognition, trust, parser, correction-memory, PencilKit, fixture corpus, OCR, export, and chart mutation authority.

## Verification Plan

- Focused SwiftPM test: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint55-placement --filter MeasureRhythmMappingTests`.
- Focused diagnostics test: `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint55-diagnostics --filter ChordEntryDiagnosticsTests`.
- Python compile check for `scripts/audit_chord_entry_diagnostics.py`.
- `git diff --check`.
- App-target compile only if the touched model path triggers a SwiftUI/app compile risk.
- Required GitHub Actions after push.

## Verification Evidence

- Focused `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint55-placement --filter MeasureRhythmMappingTests` passed with `15` tests and `0` failures.
- XcodeBuildMCP iOS simulator compile-only build passed for the `SmartChart` scheme with `CODE_SIGNING_ALLOWED=NO`.
- `git diff --check` passed.
- GitHub Actions for `7740a3f Start sprint 55 chord placement polish` passed `SwiftPM tests`, `iOS simulator tests`, and `Analyze Swift` on 2026-05-26.
- Focused `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint55-diagnostics --filter ChordEntryDiagnosticsTests` passed with `8` tests and `0` failures.
- XcodeBuildMCP iOS simulator compile-only build passed for the `SmartChart` scheme with `CODE_SIGNING_ALLOWED=NO` after the editor diagnostics wiring.
- `git diff --check` passed after the placement-evidence diagnostics update.
- GitHub Actions for `28fc6f6 Record chord placement evidence in diagnostics` passed `SwiftPM tests`, `iOS simulator tests`, and `Analyze Swift` on 2026-05-26.
- `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py` passed after the audit-tooling update.
- `git diff --check` passed after the audit-tooling update.
- GitHub Actions for `3329731 Surface chord placement in diagnostic audit` passed `SwiftPM tests`, `iOS simulator tests`, and `Analyze Swift` on 2026-05-26.
- `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py` passed after the placement-drift audit update.
- `git diff --check` passed after the placement-drift audit update.
- Simulator sample `python3 scripts/audit_chord_entry_diagnostics.py --simulator 42254D11-2E65-4586-AEBE-C6317AF2DD10 --details --scores 3` completed; it reported `missing=6, mismatched=0` placement evidence for the current pre-placement-evidence diagnostic rows.
- GitHub Actions for `3b23fd7 Flag chord placement drift in diagnostics audit` passed `SwiftPM tests`, `iOS simulator tests`, and `Analyze Swift` on 2026-05-26.
- `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py` passed after the timing-summary audit update.
- `git diff --check` passed after the timing-summary audit update.
- Simulator sample `python3 scripts/audit_chord_entry_diagnostics.py --simulator 42254D11-2E65-4586-AEBE-C6317AF2DD10 --details --scores 3` completed after the timing-summary update; it reported `Timing evidence: available=0` for the current older rows.
- Focused `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint55-absus --filter ChordInkCandidateComposerTests` passed with `51` tests and `0` failures.
- Focused `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint55-absus-recognizer --filter ChordInkRecognizerTests` passed with `40` tests, `1` skipped, and `0` failures.
- Saved-state replay `SMART_CHART_REPLAY_CHART_ID=17D5CFA4-1267-4914-B800-63100FC13C78 SMART_CHART_REPLAY_GLYPHS=1 swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint55-absus-replay-after --filter ChordEntryPassReplayTests/testReplayChordWritingTestChartFromSavedState` passed; the three `Absus` rows now match `Absus` and remain confirmation-routed when root/suffix evidence is ambiguous.
- XcodeBuildMCP `build_run_sim` passed for the `SmartChart` scheme with `CODE_SIGNING_ALLOWED=NO`.
- `git diff --check` passed after the compact suspended-chord update.
- Reverted the attempted suspended continuation-delay change after the user clarified that the problem was visual ink persistence, not early render timing.
- `xcodegen generate` passed after adding the chord-entry ink tool policy test.
- XcodeBuildMCP focused iOS simulator `test_sim -only-testing:SmartChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `1` test and `0` failures after restoring the original chord-entry pen tool and weight.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed and launched `com.smartchart.app` on the iPad simulator for the next manual pass.
- XcodeBuildMCP focused iOS simulator `test_sim -only-testing:SmartChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `1` test and `0` failures after the fast-writing ownership change.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed and launched `com.smartchart.app` on the iPad simulator after the fast-writing ownership change.
- `xcodegen generate` passed after the fast-writing ownership change.
- XcodeBuildMCP focused iOS simulator `test_sim -only-testing:SmartChartTests/LeadSheetInteractionModeStatePolicyTests CODE_SIGNING_ALLOWED=NO` passed with `2` tests and `0` failures after adding the real-device Pencil-only chord input policy.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed and launched `com.smartchart.app` on the iPad simulator after the Pencil-only device policy; simulator chord input remains `.anyInput` for automation.

## Acceptance Criteria

- Rhythm-aware chord insertion snaps to the nearest playable slot attack/start position.
- Long-duration rhythm slots no longer lose near-start chord writes to earlier short slots.
- Existing next-open-slot and explicit move/replace behaviors remain covered.
- Chord-entry diagnostics include placement evidence for committed, corrected, and reconciled rendered chords.
- The diagnostic audit script prints placement evidence during metadata review.
- The diagnostic audit script reports whether active diagnostic placement evidence is missing or no longer matches the rendered chart.
- The diagnostic audit script summarizes available timing evidence for render/performance triage.
- Compact `Absus` evidence stays in the supported candidate set, with ambiguous cases routed to confirmation instead of new global score tuning or handwriting-specific fixtures.
- Chord-entry live ink is not pushed through SwiftUI on every point update; active strokes remain owned by `PKCanvasView`, and the chart snapshot catches up at the idle recognition boundary.
- Active chord ink with unpersisted changes is not overwritten by stale model ink during SwiftUI refreshes.
- Chord-entry keeps the original `.pen` tool at `2.5` points; ink persistence must not be faked by making strokes thicker.
- Chord-entry on real iPad/device builds accepts Apple Pencil input only; simulator builds keep `.anyInput` for automation.
- No personal handwriting fixture expansion or score retuning.
