# Smart Chart — Current Architecture Audit

Status: historical audit, stale for current recognition path
Date: 2026-04-23

Execution sequence reference: `docs/post-v1/lead-sheet/jazz-lead-sheet-build-plan.md`

## Historical Notice

This audit reflects an older editor-cleanup checkpoint before live chord-entry recognition returned to the app. It is useful as historical context for the jazz-page reset, but it is not the active sprint or recognition architecture authority.

For current sprint execution, use `docs/smart-chart-sprint-source-of-truth.md`. For the May 2026 repo, GitHub, and recognition audit evidence, use `docs/repo-github-recognition-audit-2026-05-20.md`.

When this document conflicts with the living sprint source of truth, the living sprint source of truth wins.

This audit reflects the repo after the jazz-page cleanup pass. It is meant to answer one practical question:

What is still part of the real product path, and what has been intentionally removed?

## Active product path

The current app is now intentionally centered on one workflow:

- library/projects landing page
- new chart setup
- jazz lead-sheet page
- one medium open measure to start
- top tool tabs for page actions
- page-wide free-hand writing mode
- measure growth through the `Measures` tab

This is the only path the app should be treated as supporting right now.

## Keep

These systems are on the correct path and should stay:

- app shell and project/library flow
  - `SmartChart/App/AppRootView.swift`
  - `SmartChart/Features/Library/LibraryView.swift`
  - `SmartChart/Features/Library/ChartLibraryStore.swift`
- jazz-only setup and editor shell
  - `SmartChart/Features/Editor/EditorView.swift`
  - `SmartChart/Features/Editor/Components/ChartSetupSheetView.swift`
  - `SmartChart/Features/Editor/Components/ChartHeaderSheetView.swift`
- lead-sheet renderer and layout engine
  - `SmartChart/Features/Editor/Components/LeadSheetCanvasHostView.swift`
  - `SmartChart/Services/LeadSheetPageLayout.swift`
- structured chart domain
  - `SmartChart/Models/Chart.swift`
  - `SmartChart/Models/Measure.swift`
  - `SmartChart/Models/ChordEvent.swift`
  - `SmartChart/Models/MeasureRhythmMapping.swift`
  - `SmartChart/Models/ChartEditing.swift`
- support layers that still serve the jazz page
  - parsing and non-destructive transposition views
  - persistence
  - PDF export
  - timing validation

## Removed or retired

These paths are no longer part of the live implementation direction:

- alternate notation/page-style flows
  - the app is locked to `StaffStyle.fiveLine`
- old SwiftUI prototype editor surfaces
  - `ChartCanvasHostView`
  - `PenChartPageView`
  - `PenMeasureSurfaceView`
  - `MeasureCardView`
  - old inline chord/rhythm composer views
- recognition-driven draft state that was not on the live path
  - pending chord ink model state
  - pending rhythm-map draft model state
  - pending measure-closure model state
  - old recognizer plumbing tied to those flows
- dormant editing commands that no active UI calls
  - starter-chord shortcuts
  - reopen/recommit prototype commands
  - old chord move / clear-rhythm convenience actions

## What the codebase now means

The repository is simpler now:

- the renderer owns the jazz page look
- the editor owns a small set of deliberate top-level actions
- free-hand mode is page-wide raw ink only
- structured measure growth still exists through `commitOpenMeasure()` and `positionOpenMeasure(after:)`
- rhythm interpretation now runs through a confirmation-first handwritten quantizer
- at this historical checkpoint, chord interpretation was outside the live path; that is no longer true for the current recovery branch

That makes the codebase much closer to the actual product goal: build the page authoring experience first, then add interpretation back on top of a stable surface.

## Current risks

The main remaining architectural risk is not bloat anymore. It is that the renderer and authoring layer still need to converge further.

The biggest gaps now are:

- turning raw page ink into deliberate, localized authored objects
- adding measure- and notation-specific tools on top of the lead-sheet page without reintroducing prototype sprawl
- eventually sharing more geometry rules between screen rendering and PDF export

## Recommendation for the next implementation stages

Stay on the jazz page only.

Build forward in this order:

1. stronger page-local authoring tools on top of the existing free-hand layer
2. clearer per-measure interaction on the lead-sheet surface
3. controlled interpretation of written content only after the writing experience feels correct
4. export/layout unification once the page authoring model stabilizes

That is the cleanest continuation from the current state.
