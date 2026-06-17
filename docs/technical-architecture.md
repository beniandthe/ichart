# Smart Chart — Technical Architecture and Initial Build Plan

Status: historical architecture and initial build plan, useful for v1 context
Product source of truth: `docs/core-design-document.md`
Current implementation source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

This document translates the product spec into the first implementation shape for the iPad app.

It is optimized for one thing: proving the editor loop quickly without backing into a brittle architecture.

For current sprint movement, recognition authority, real Pencil validation, and writing-to-render readiness, use `docs/smart-chart-sprint-source-of-truth.md` and `docs/smart-chart-real-life-testing-readiness-2026-05-25.md`. This older plan must not override the recovered pipeline or the writer-agnostic recognition policy.

## Recommended V1 stack

- **Platform:** iPadOS first
- **Language:** Swift
- **UI:** SwiftUI with UIKit bridges where the editor surface needs lower-level control
- **Ink capture:** PencilKit
- **Persistence:** SwiftData first, with a clean persistence boundary so Core Data can replace it later if needed
- **Export:** native PDF generation
- **App model:** local-first, document-like editing experience
- **Backend:** none required for v1

## Core architectural rule

The app must never treat the chart as just ink or just plain text.

Every meaningful item becomes a structured object:
- measures
- meter
- timed chord events
- section labels
- cue text
- roadmap objects
- barlines

Raw Pencil strokes are still preserved so the app can support reinterpretation and future recognition improvements.

## Architectural boundaries

### 1. App
Owns launch, scene setup, persistence container, and shared app state.

### 2. Domain Models
Defines chart objects, meter, chord timing semantics, and lightweight editor state.

### 3. Editor Feature
Owns the main chart authoring flow:
- chart canvas
- top toolbar menus
- object selection
- editing
- inspector popovers
- mode switching

### 4. Ink + Recognition
Owns PencilKit integration and conversion from raw strokes to structured candidates.

### 5. Layout
Owns measure and system layout plus predictable reflow behavior, including beat-aware placement inside measures.

### 6. Export
Owns PDF rendering and share/export flows.

### 7. Library
Owns chart browser, recent charts, duplicate/rename/delete, and opening documents.

### 8. Monetization and Entitlements
Owns product-tier state and feature gating without infecting the core chart model:
- local entitlement state
- chart-count limits
- Pro feature checks for export and advanced local tools
- StoreKit boundary and purchase restoration later

The editor and library should depend on lightweight entitlement queries, not on StoreKit directly.

## First implementation slice

The first slice should prove this scenario end-to-end:
1. Create a new chart.
2. Display a clean measure/system canvas with a default meter.
3. Add a chord event manually.
4. Set its beat position and duration manually.
5. Add a section label.
6. Select and edit an object.
7. Render a PDF preview/export.

Only after that should freehand recognition become a top implementation priority.

## Why this order is correct

If the object model, timing model, layout engine, and edit loop do not feel good, better recognition will not save the product.

Recognition is the multiplier, not the foundation.

Monetization should attach to the proven editor loop, not drive it.

## Suggested milestones

### Milestone 0 — bootstrap
- app target created
- persistence bootstrapped
- chart library placeholder
- new chart flow placeholder

### Milestone 1 — static editor shell
- chart canvas with systems and measures
- default meter visible
- sample chart data renders
- zoom and pan behavior decided

### Milestone 2 — manual chart editing
- create and edit chord events
- set beat position and duration manually
- change measure meter
- set document key and transposition view
- change document font preset
- create special notation items from toolbar actions
- select object
- move object
- delete object
- inspector editing
- autosave

### Milestone 3 — export
- PDF render pipeline
- preview/share

### Milestone 3.5 — entitlement foundation
- local entitlement model
- Basic 3-chart cap logic
- Pro feature gating hooks for cloud sync and Forums
- StoreKit boundary isolated behind a protocol or service wrapper

Keep this slice small. It should formalize the business model without delaying the core editor.

### Milestone 4 — ink capture
- PencilKit canvas overlay
- stroke grouping
- ink-to-candidate pipeline

### Milestone 5 — recognition v1
- chord recognition
- time signature recognition
- limited rhythm-value recognition
- section label recognition
- cue text recognition
- barline recognition

### Milestone 6 — roadmap recognition
- repeat span
- ending 1 / ending 2
- coda / To Coda
- Segno
- D.S. / D.C.
- Fine
- vamp count
- N.C.

## Recognition guidance

Keep recognition constrained and context-aware.

Use soft zone logic:
- at the beginning of the chart or a meter change position = likely time signature
- inside a measure main writing zone = likely chord
- directly above or below a chord = likely rhythm attachment
- above a system = likely section label
- spanning across measures = likely roadmap object
- below or near a measure = likely cue text

That will outperform a naive free-for-all recognizer in early versions.

## Persistence guidance

Persist at least these entities early:
- Chart
- Measure
- ChordEvent
- SectionLabel
- CueText
- RoadmapObject
- Barline
- InkStrokeGroup

Do not tightly couple persistence types to view types.

## Export guidance

Export should render from structured chart objects, not screenshot the editor.

That keeps output clean and lets export evolve independently of the editor UI.

## Build risks to watch

- layout instability after edits
- ambiguity between chord writing and rhythm attachment gestures
- mode confusion between write/select/erase
- rhythm support drifting into full notation scope
- recognition ambiguity without fast reinterpretation
- overfitting too early to one chart dialect

## Recommended development posture

- Keep the app local-first.
- Keep the object model explicit.
- Keep meter and timing first-class.
- Keep correction fast.
- Delay clever recognition until the chart editor itself feels trustworthy.
- Treat strong one-page charts as the release-critical layout target.
