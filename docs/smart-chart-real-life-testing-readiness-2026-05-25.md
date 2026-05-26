# Smart Chart Real-Life Testing Readiness

Status: Sprint 42 readiness artifact
Date: 2026-05-25
Primary authority: `docs/smart-chart-sprint-source-of-truth.md`
Product authority: `docs/core-design-document.md`

## Purpose

This document defines the handoff from repo-local writing-to-render QA into real Apple Pencil product testing.

The goal is to prove the recovered product loop:

```text
open -> write -> recognize -> snap -> fix -> export
```

This is product validation, not a handwriting training pass. New real Pencil observations should measure writing feel, trust, correction friction, and export quality. They should not become a standing loop of repeatedly capturing one writer's chord samples.

## Current Pipeline

The current source-of-truth pipeline is:

```text
native PKCanvasView ink
-> PencilKitInkAdapter
-> StrokeClusterer
-> GestureTemplateRecognizer
-> ChordInkCandidateComposer
-> ChordRecognitionCompendium / ChordSymbolParser
-> ChordInkRecognitionPolicy plus optional trust sidecar
-> Chart.commitRecognizedChordInk
-> structured ChordEvent
-> PDFChartExporter
```

Runtime authority boundaries:

- `PKCanvasView` remains the native writing surface.
- The recognizer proposes compendium-backed candidates.
- `ChordRecognitionTrustArbiter` decides whether the primary read is trusted enough to render or needs confirmation.
- `Chart.commitRecognizedChordInk` owns the successful structured commit and live chord-ink clear rule.
- OCR remains optional, compendium-gated, and ambiguity-only.
- Symbol ledger diagnostics remain off by default on the live path.

## Automated Readiness Gates

Sprint 42 adds a bounded writing-to-render readiness harness that must stay capped at three product-proof fixtures:

- `C`: clear primary read, expected auto-render.
- `Db7(b9)`: supported altered chord, expected confirmation because the current policy treats it as an ambiguous close race.
- `G/B`: clear slash-chord read, expected auto-render.

The harness checks:

- each fixture recognizes to the expected compendium-backed display text
- default live recognition does not pay symbol-ledger diagnostics cost
- trust decisions match the live editor policy
- OCR sidecar is requested only when the primary decision needs ambiguity evidence
- per-fixture recognition latency remains below the bounded product-loop budget
- the product-proof renderer path commits through `Chart.commitRecognizedChordInk`
- committed chords clear the active chord ink pass
- exported PDFs contain the structured chord text and no editor placeholder copy

These fixtures are regression/product evidence only. Do not expand this set to improve one writer's pass rate.

## Real Pencil Validation Protocol

Run this manually on a real iPad with Apple Pencil after Sprint 42 is green:

1. Open Smart Chart to the Projects library.
2. Create or open a clean local chart.
3. Enter chord-writing mode.
4. Write `C` in the first measure and pause naturally.
5. Confirm that the writing feels native and does not lag, fragment, or fight Pencil input.
6. Confirm that `C` renders as a structured chord or reaches a clear correction path.
7. Write `G/B` in another measure and confirm the slash chord snaps correctly.
8. Write `Db7(b9)` and confirm the app asks for confirmation instead of blindly rendering the ambiguous altered chord.
9. Accept the supported candidate and confirm the active chord ink pass clears after render.
10. Export the chart to PDF and visually inspect that the rendered chords are readable.

Record the pass in `docs/smart-chart-real-pencil-field-test-log-2026-05-26.md` so the next sprint can be chosen from product evidence instead of memory.

Evidence to record:

- device model and iPadOS version
- whether Pencil feel is acceptable
- whether recognition routed to auto-render or confirmation as expected
- correction friction notes
- export readability notes
- screenshots or short recordings only when they explain a product issue

## Fixture And Training Boundary

Do not add captured ink just because a real-life pass is imperfect. A new fixture is appropriate only when it protects a transferable regression that should generalize beyond one writer, such as:

- a supported chord family consistently fails across realistic writing styles
- a parser/compendium-backed chord renders incorrectly after recognition
- trust routing auto-renders an ambiguous chord that should require confirmation
- export loses a structured chord that was already committed

Do not add fixtures for count goals, personal handwriting coverage, or repeated attempts at the same writer-specific shape.

## Ready-For-Testing Criteria

Before real-life testing starts:

- required GitHub Actions must be green on the Sprint 42 commit
- full SwiftPM tests must pass
- iOS simulator `SmartChart` scheme tests must pass
- renderer product proof must pass through the live trust and commit contract
- visual renderer QA artifacts must remain inspectable when generated
- source-of-truth and supporting docs must agree that recognition is writer-agnostic by default

The next product decision after the real Pencil pass should be based on observed friction: writing feel, recognition trust, correction speed, or export readability. It should not be based on building another personal sample corpus.
