# Smart Chart — Technical Architecture and Initial Build Plan

Status: Active for Prototype and V1  
Source of truth: `docs/core-design-document.md`

## Purpose

This document translates the product spec into the first implementation shape for the iPad app.

It is optimized for one thing: proving the editor loop quickly without backing into a brittle architecture.

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

The app must never treat the chart as just ink.

Every meaningful item becomes a structured object:
- measures
- chords
- section labels
- cue text
- roadmap objects
- barlines

Raw Pencil strokes are still preserved so the app can support reinterpretation and future recognition improvements.

## Architectural boundaries

### 1. App
Owns launch, scene setup, persistence container, and shared app state.

### 2. Domain Models
Defines chart objects and lightweight editor state.

### 3. Editor Feature
Owns the main chart authoring flow:
- chart canvas
- object selection
- editing
- inspector popovers
- mode switching

### 4. Ink + Recognition
Owns PencilKit integration and conversion from raw strokes to structured candidates.

### 5. Layout
Owns measure and system layout plus predictable reflow behavior.

### 6. Export
Owns PDF rendering and share/export flows.

### 7. Library
Owns chart browser, recent charts, duplicate/rename/delete, and opening documents.

## First implementation slice

The first slice should prove this scenario end-to-end:
1. Create a new chart.
2. Display a clean measure/system canvas.
3. Add a chord object manually or from a mocked recognition event.
4. Add a section label.
5. Select and edit an object.
6. Render a PDF preview/export.

Only after that should freehand recognition become a top implementation priority.

## Why this order is correct

If the object model, layout engine, and edit loop do not feel good, better recognition will not save the product.

Recognition is the multiplier, not the foundation.

## Suggested milestones

### Milestone 0 — bootstrap
- app target created
- persistence bootstrapped
- chart library placeholder
- new chart flow placeholder

### Milestone 1 — static editor shell
- chart canvas with systems and measures
- sample chart data renders
- zoom and pan behavior decided

### Milestone 2 — object editing
- select object
- move object
- delete object
- inspector editing
- autosave

### Milestone 3 — export
- PDF render pipeline
- preview/share

### Milestone 4 — ink capture
- PencilKit canvas overlay
- stroke grouping
- ink-to-candidate pipeline

### Milestone 5 — recognition v1
- chord recognition
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
- inside a measure = likely chord
- above a system = likely section label
- spanning across measures = likely roadmap object
- below or near a measure = likely cue text

That will outperform a naive free-for-all recognizer in early versions.

## Persistence guidance

Persist at least these entities early:
- Chart
- Measure
- Chord
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
- mode confusion between write/select/erase
- recognition ambiguity without fast reinterpretation
- overfitting too early to one chart dialect
- overbuilding beyond the enforced v1 object set

## Recommended development posture

- Keep the app local-first.
- Keep the object model explicit.
- Keep correction fast.
- Delay clever recognition until the chart editor itself feels trustworthy.
- Treat strong one-page charts as the release-critical layout target.
