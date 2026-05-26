# Smart Chart Sprint 52 Chord Confirmation User Loop

Status: implementation green; manual UX validation gate
Date: 2026-05-26
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`
Prior evidence: `docs/smart-chart-sprint-51-real-life-polish-2026-05-26.md`
Manual validation log: `docs/smart-chart-sprint-52-manual-ux-validation-log-2026-05-26.md`

## Purpose

Sprint 52 begins the product UX layer for chord confirmation and user correction.

The goal is to keep the primary lane fast and automatic while making misses feel recoverable:

```text
write -> auto-render when trusted -> confirm when close -> direct input when failed -> remember local user choices safely
```

## Product Rules

- Auto-render remains the preferred lane whenever trust is clear.
- Complete recognition failure clears the live chord ink automatically so the user can rewrite immediately.
- Automatic complete-failure clearing is capped at two consecutive failures for the same measure/target slot; the third consecutive complete failure opens direct input.
- Close-race confirmation shows the top three supported suggestions.
- A selected suggestion may create a local user correction rule only when the race is close but not extremely tight.
- Extremely tight races do not create user rules because the competing chords are too close to safely bias later behavior.
- Manual entry after wrong suggestions creates a local exclusion for that top-three suggestion signature.

## Architecture Boundary

This is product personalization, not recognizer training.

- The core recognition pipeline remains writer-agnostic.
- No fixture corpus expansion is allowed for this work.
- No global score retuning is allowed from one user's handwriting.
- OCR remains ambiguity-only and compendium-gated.
- Symbol-ledger diagnostics remain off the live path by default.
- User correction memory is local app support data, separate from chart snapshots and diagnostics.

## Implementation Plan

- Add a local `ChordInkUserCorrectionMemory` service for candidate-signature rules, suggestion exclusions, automatic rewrite failure tracking, and JSON persistence.
- Wire `EditorView` so complete failures clear ink for the first two consecutive attempts, then route to direct input on the third.
- Keep close-race confirmation to top-three suggestions.
- Persist a local user rule when a confirmed suggestion came from a non-extremely-tight close race.
- Persist a local exclusion when the user manually enters a supported chord that was not among the suggestions.
- Apply a learned local rule only when the current race has the same top-three supported candidate signature, is not extremely tight, and has no exclusion.

## Acceptance Criteria

- Complete fail attempts one and two clear live chord ink without blocking the user.
- Complete fail attempt three opens direct chord input.
- Close-race confirmation presents only the top three supported candidates.
- Confirming a non-extremely-tight close-race suggestion creates a local user correction rule.
- Confirming an extremely tight race does not create a local user correction rule.
- Manual entry outside the suggestions records an exclusion and prevents local auto-rule application for that signature.
- Existing compendium/parser validation still gates every accepted chord.

## Verification Plan

- `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint52 --filter ChordInkUserCorrectionMemoryTests`
- XcodeBuildMCP iOS simulator focused test:
  `-only-testing:SmartChartTests/ChordInkUserCorrectionMemoryTests`
- `git diff --check`
- Run a short manual UI pass only after the implementation is green: one complete miss loop, one close-race confirmation, and one manual-entry correction.

## Verification Evidence

- local `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint52 --filter ChordInkUserCorrectionMemoryTests`: passed with `5` tests, `0` failures
- local `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint52 --filter ChordEntryDiagnosticsTests`: passed with `7` tests, `0` failures
- XcodeBuildMCP iOS simulator focused test `-only-testing:SmartChartTests/ChordInkUserCorrectionMemoryTests`: passed with `5` tests, `0` failures
- `git diff --check`: passed
- GitHub Actions on `0a59588 Add sprint 52 chord confirmation user loop`: SwiftPM tests, iOS simulator tests, and Analyze Swift passed

## Current Gate

Run only the bounded manual UX validation pass in `docs/smart-chart-sprint-52-manual-ux-validation-log-2026-05-26.md`.

Do not add fixtures, retune scores, expand OCR, or run a long chord loop from this gate. The only question is whether the new confirmation UX rules feel right in the app.
