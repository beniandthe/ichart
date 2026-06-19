# iChart — Architecture Reset Proposal

Status: Proposal only
Date: 2026-04-23
This document does not replace `docs/core-design-document.md` or the current source-of-truth architecture docs yet.

## Purpose

This document compares the current iChart implementation direction with a proposed architecture reset.

The goal is not to throw away the product direction. The goal is to adjust the technical path so the app is easier to build, easier to test, and less likely to collapse under editor complexity.

## Why consider a reset

The current approach is showing strain in three hard areas at the same time:
- freehand recognition
- editable page/canvas behavior
- music-chart layout

Those are each difficult systems. Trying to solve them simultaneously inside a high-level prototype shell is likely to produce friction even if the product direction is correct.

## Executive recommendation

Keep:
- Swift as the main language
- native Apple frameworks
- the structured chart domain model
- local-first architecture
- deterministic layout and export

Change:
- stop treating the editor surface as primarily a SwiftUI-composed screen
- move the actual page canvas to UIKit + PencilKit
- treat recognition as an assistive subsystem, not the foundation of the editor
- make layout deterministic before handwriting interpretation
- reserve OpenAI for optional reinterpretation/cleanup later, not live primary recognition

Do not adopt as the main architecture:
- a C++-first app shell
- a cloud-dependent recognition loop
- an OpenAI-dependent real-time editing path

## Current vs proposed

### 1. App shell

Current:
- SwiftUI-first shell
- SwiftUI renders the editor screen, canvas area, measure cards, and many editing surfaces

Proposed:
- SwiftUI remains the app shell for library, settings, paywall, document list, and inspector containers
- UIKit owns the actual editor canvas and direct manipulation surface
- SwiftUI hosts UIKit where needed

Why:
- the canvas needs precise gesture handling, hit-testing, selection, drag behavior, zooming, and Pencil interaction
- UIKit is a better fit for a custom editor surface than trying to compose everything from SwiftUI layout primitives

### 2. Editor surface

Current:
- `EditorView.swift` renders a vertically stacked prototype screen with cards and horizontally scrolling measure views
- the chart canvas is effectively a composed preview, not a true document editor

Proposed:
- replace the main canvas area with a custom `ChartCanvasView` backed by UIKit
- one page/document surface should own:
  - coordinate space
  - hit testing
  - selection
  - drag/move/snap
  - zoom/pan
  - overlay layers for ink, guides, and structured objects

Why:
- page structure and object interaction need a single geometry system, not nested SwiftUI stacks and scroll views

### 3. Layout engine

Current:
- layout is implicit in SwiftUI composition and per-view rendering
- measure presentation is distributed through UI views

Proposed:
- create a deterministic layout engine that produces page/system/measure/object frames from the chart model
- views render the layout result instead of inventing layout themselves

Why:
- PDF export, on-screen display, and hit-testing should all come from the same layout truth
- this reduces “looks different on screen vs export” problems

### 4. Recognition

Current:
- recognition is described as arriving relatively soon after shell/manual editing
- chart authoring and recognition are still conceptually close together

Proposed:
- demote recognition to a later layer after:
  - canvas
  - deterministic layout
  - manual editing
  - selection/repositioning
  - export
  feel trustworthy
- start with constrained interpretation rules, not open-ended handwriting intelligence

Why:
- if the document editor is weak, better recognition does not save the experience
- musicians will forgive imperfect recognition faster than unstable editing

### 5. AI / OpenAI role

Current:
- not deeply integrated yet

Proposed:
- no OpenAI dependency in the core editing loop
- optional future use cases:
  - reinterpret ambiguous handwritten measure input
  - suggest likely chord spellings
  - help convert messy ink into structured candidates after capture
  - offer cleanup suggestions on demand

Why:
- live beat-accurate placement and page interaction should stay deterministic and local
- AI can help with ambiguity, but should not own geometry or document state

### 6. C++ role

Current:
- no C++ dependency

Proposed:
- still no C++ requirement for the app architecture
- only introduce C++ if later profiling shows one narrow subsystem needs it, such as:
  - geometry-heavy layout
  - stroke clustering
  - recognition heuristics

Why:
- a C++-first rewrite adds complexity before it solves the real bottleneck
- Apple-native UI, Pencil, persistence, and export still want Swift/UIKit on top

### 7. Persistence

Current:
- in-memory prototype repository
- future SwiftData plan

Proposed:
- keep the plan to use SwiftData or another native local persistence layer
- persist structured document state first
- persist ink groups as linked auxiliary data

Why:
- structured objects remain the source of truth
- raw ink supports reinterpretation without owning the document model

## What in the current repo is still good

Keep these ideas and artifacts:
- `iChart/Models/Chart.swift`
- `iChart/Models/Measure.swift`
- `iChart/Models/ChordEvent.swift`
- `iChart/Models/ChartAnnotations.swift`
- `iChart/Models/MusicTheory.swift`
- `iChart/Services/ChartParsers.swift`
- `iChart/Services/MeasureTimingValidator.swift`
- `docs/core-design-document.md`
- `docs/developer-mvp-spec.md`
- `docs/monetization-strategy.md`

Why they survive:
- they describe the product and structured domain well
- they are compatible with the reset

## What should be treated as prototype-only

These are useful for exploration, but should not define the long-term editor:
- `iChart/Features/Editor/EditorView.swift`
- `iChart/Features/Editor/Components/MeasureCardView.swift`
- the current horizontally scrolling measure-card canvas approach
- the assumption that the editor can be mostly composed from stacked SwiftUI cards

Why:
- they are good as shell scaffolding, but weak as the basis for a professional drawing/editor surface

## Proposed architecture after reset

### Layer 1 — App shell

Responsibilities:
- app lifecycle
- library and navigation
- settings
- monetization UI
- document open/create flow

Suggested tech:
- SwiftUI

### Layer 2 — Editor container

Responsibilities:
- bridge app state into the editor
- coordinate inspector/toolbars with the canvas
- host UIKit canvas inside SwiftUI

Suggested tech:
- SwiftUI + `UIViewRepresentable` / `UIViewControllerRepresentable`

### Layer 3 — Canvas/editor engine

Responsibilities:
- single document coordinate space
- gesture handling
- Pencil input routing
- object selection
- drag/move/snap
- zoom/pan
- overlay composition

Suggested tech:
- UIKit
- PencilKit
- custom `UIView` or `UIViewController`

### Layer 4 — Layout engine

Responsibilities:
- system breaking
- measure widths
- beat-grid placement
- section-label placement
- roadmap badge placement
- collision avoidance rules
- export-ready frame generation

Suggested tech:
- pure Swift

### Layer 5 — Domain engine

Responsibilities:
- chart model
- transposition
- validation
- timing semantics
- editing commands

Suggested tech:
- pure Swift

### Layer 6 — Recognition pipeline

Responsibilities:
- stroke grouping
- region inference
- candidate generation
- confidence scoring
- reinterpretation options

Suggested tech:
- pure Swift first
- Apple Vision where useful for constrained OCR-like cases
- optional future AI helper on demand, never required for core editing

### Layer 7 — Export pipeline

Responsibilities:
- render from layout engine output
- produce PDF from structured objects
- preview/share

Suggested tech:
- Core Graphics
- PDFKit for preview if helpful

## Current repo vs proposed module map

Current rough shape:
- `App`
- `Features/Library`
- `Features/Editor`
- `Models`
- `Services`
- `Persistence`

Proposed rough shape:
- `App`
- `Features/Library`
- `Features/Monetization`
- `Features/EditorShell`
- `EditorCore/Canvas`
- `EditorCore/Layout`
- `EditorCore/Commands`
- `Recognition`
- `Models`
- `Services`
- `Persistence`
- `Export`

## Milestone diff

### Current milestone emphasis

Current plan:
1. shell
2. manual editing
3. export
4. ink capture
5. recognition

### Proposed milestone emphasis

Reset plan:
1. get project compiling and running on Mac/iPad
2. replace prototype canvas with UIKit-based document canvas
3. build deterministic layout engine
4. wire manual object selection/edit/move on the real canvas
5. make export render from the same layout engine
6. add PencilKit stroke capture overlays
7. add constrained recognition passes
8. add optional AI reinterpretation later, only if needed

## Explicit diffs from the current architecture doc

Current:
- “SwiftUI with UIKit bridges where the editor surface needs lower-level control”

Reset:
- SwiftUI remains the shell, but the editor surface itself should be assumed to be UIKit-first from the beginning

Current:
- Milestone 1 and 2 implicitly allow the prototype canvas to stand in for the real editor

Reset:
- the prototype canvas should be considered a temporary shell only; a real canvas becomes the first major Mac build milestone

Current:
- recognition follows relatively soon after shell/manual editing

Reset:
- recognition moves later; layout and interaction become the real foundation

Current:
- no explicit separation between visual layout generation and view composition

Reset:
- layout engine becomes a first-class subsystem and the single geometry source for screen, hit-testing, and export

## Suggested first Mac milestone after reset

The first Mac-only milestone should be:

1. generate the Xcode project
2. make the app compile
3. replace the current measure-card canvas area with a placeholder UIKit canvas host
4. prove one page can render a deterministic 4-bar system from the chart model
5. support tap selection on a rendered chord event
6. support one drag-to-move interaction

If those steps feel good, the reset is working.

## Recommendation summary

The product direction still looks strong.

The likely problem is not that Swift is wrong. The likely problem is that the current implementation path lets the prototype shell masquerade as the editor architecture.

The reset recommendation is:
- stay native
- keep Swift
- keep Apple frameworks
- move the editor surface to UIKit + PencilKit
- make layout deterministic
- postpone complex recognition
- use AI only as an optional assistive layer later
