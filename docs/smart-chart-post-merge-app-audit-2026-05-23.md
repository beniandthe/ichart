# Smart Chart Post-Merge App Audit

Status: draft in progress
Date: 2026-05-23
Branch: `main`
Baseline: `1e4ef82 Open sprint twelve post merge audit`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

This Sprint 12 audit captures the merged Smart Chart app architecture after PR
[#4](https://github.com/beniandthe/smart-chart/pull/4). It is meant to align
the product workflow, live code paths, diagnostic sidecars, local drift, and the
next few sprints before more implementation work begins.

The north-star workflow remains:

```text
open -> write -> recognize -> snap -> fix -> export
```

## Current Verdict

Smart Chart is now back on one recognizable path: local-first chart library,
SwiftUI editor shell, native `PKCanvasView` ink capture, recovered chord
recognition pipeline, compendium/parser validation, structured `ChordEvent`
commit, fast correction, and native PDF export.

The tracked app is aligned enough to move forward, but Sprint 12 should not be
treated as done until the local duplicate test files are either intentionally
cleaned or explicitly ignored and a live app smoke pass is completed from
`main`. The largest risks are now maintenance and clarity risks, not obvious
runtime detours:

- Recognition is source-of-truth aligned, but several files are still large and
  carry family-specific repairs that are hard to audit quickly.
- The editor is correctly the owner of chord ink lifecycle and placement, but
  `EditorView.swift` and `LeadSheetCanvasHostView.swift` remain broad
  orchestration surfaces.
- Debug/audit tooling is mostly separated from live behavior, but the project
  still needs a clean "what runs by default" map for future work.
- The local worktree has untracked duplicate test files named `* 2.swift`.
  They are byte-identical to tracked files but still break local SwiftPM test
  discovery because SwiftPM compiles them as extra sources. They should be
  cleaned later only with explicit approval.
- Documentation authority is much better than before, but `README.md` still
  lists some older docs under active authority that the sprint source of truth
  treats as subordinate or historical.

## Evidence Snapshot

- PR #4 merged into `main` as `1b792df`.
- Sprint 12 kickoff commit is `1e4ef82`.
- GitHub checks on `1e4ef82`: SwiftPM tests, iOS simulator tests, and Analyze
  Swift all completed successfully.
- Local `git status --short --branch` is on `main...origin/main` with only
  untracked duplicate `SmartChartTests/Recognition/* 2.swift` files.
- Duplicate local test files inspected so far are byte-identical to their
  tracked counterparts.
- Local `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint12` currently
  fails because those untracked duplicate files redeclare test types such as
  `InkFixture`, `InkFixtureLoader`, and multiple `XCTestCase` classes.
- `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py
  scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py`
  passed locally.
- Fixture corpus count: `645` JSON files under `SmartChartTests/Fixtures/Ink`,
  about `6.7M`.

## Whole-App Architecture

```mermaid
flowchart TD
    App["SmartChartApp"]
    Store["ChartLibraryStore"]
    Repo["FileChartRepository<br/>Application Support JSON"]
    Root["AppRootView<br/>Tabs + NavigationStack"]
    Library["LibraryView<br/>Projects"]
    Editor["EditorView<br/>mode + sheet orchestration"]
    Canvas["LeadSheetCanvasHostView<br/>SwiftUI -> UIKit bridge"]
    UIKitCanvas["LeadSheetCanvasUIKitView<br/>PKCanvasView + rendering"]
    Model["Chart model<br/>systems, measures, chord events, rhythm maps"]
    Recognition["Chord recognition pipeline"]
    Parser["ChordRecognitionCompendium<br/>ChordSymbolParser"]
    Export["PDFChartExporter<br/>PDF preview/share"]
    Diagnostics["ChordEntryDiagnostics<br/>audit scripts"]

    App --> Store
    Store <--> Repo
    App --> Root
    Root --> Library
    Root --> Editor
    Editor <--> Model
    Editor --> Canvas
    Canvas --> UIKitCanvas
    UIKitCanvas --> Recognition
    Recognition --> Parser
    Parser --> Editor
    Editor --> Model
    Editor --> Export
    Editor -. debug/simulator .-> Diagnostics
```

### Architecture Feedback

What is aligned:

- The app is local-first and does not depend on a backend for v1 behavior.
- SwiftPM and iOS/Xcode targets have a useful split: pure domain/recognition
  code is testable through SwiftPM, while editor/PencilKit coverage is protected
  by the iOS simulator scheme.
- The model layer is structured around charts, systems, measures, chord events,
  rhythm maps, and raw ink storage. That matches the core design rule:
  structured objects over raw ink alone.
- Export is a service (`PDFChartExporter`) rather than a direct editor concern.

What needs continued attention:

- `ChartLibraryStore` persists on every published change. That is simple and
  probably fine for prototype scale, but a future persistence sprint should
  consider debounce/error surfacing before large libraries.
- `AppRootView` already has placeholder Workspace and Settings tabs. They are
  harmless, but future app shell work should decide whether they are true v1
  navigation or placeholder surface area.
- `LibraryView` is functional but still reads like a prototype surface: it
  mixes a large hero, project list, free-tier capacity text, and debug-only
  chord test entry. That is acceptable now, but v1 should converge on a tighter
  project-first library.
- The active document authority is split between the living sprint doc, core
  design doc, README, and older planning docs. The living sprint doc should
  remain the first stop for implementation decisions.

## App Shell, Persistence, And Entitlements

```mermaid
flowchart TD
    Launch["SmartChartApp"]
    Fonts["NotationFontRegistrar"]
    Store["ChartLibraryStore"]
    Snapshot["ChartLibrarySnapshot"]
    Repo["FileChartRepository"]
    JSON["Application Support<br/>SmartChart/library-state.json"]
    Entitlements["AppEntitlements"]
    Library["LibraryView"]
    Upgrade["UpgradeSheetView"]

    Launch --> Fonts
    Launch --> Store
    Store <--> Snapshot
    Store <--> Repo
    Repo <--> JSON
    Store --> Entitlements
    Store --> Library
    Library --> Upgrade
    Upgrade --> Store
```

Feedback:

- The local JSON repository is a good v1 boundary because it keeps persistence
  simple and testable.
- The store owns both chart library state and entitlement state. That is fine
  for prototype speed, but StoreKit wiring should probably introduce a clearer
  purchase/entitlement adapter rather than letting the library store become a
  commerce hub.
- Free vs Pro gating already exists for chart count and PDF export. The current
  "Use Pro Preview" flow is explicitly a prototype local entitlement switch.
- Persistence errors are printed, not surfaced. That is tolerable during
  prototype work, but it is not enough for production chart ownership.

## User Workflow And State

```mermaid
stateDiagram-v2
    [*] --> Library
    Library --> Editor: open chart
    Editor --> ChordEntry: choose Chord mode
    ChordEntry --> InkCapture: write in native PKCanvasView
    InkCapture --> Recognition: idle delay
    Recognition --> AutoRender: high trust
    Recognition --> ConfirmChord: needs user confirmation
    ConfirmChord --> Commit: accept or type correction
    AutoRender --> Commit
    Commit --> StructuredChart: append ChordEvent
    Commit --> ClearChordInk: clear chord ink pass
    StructuredChart --> Correction: tap existing chord
    Correction --> StructuredChart: replace ChordEvent
    StructuredChart --> Export: preview/share PDF
    Export --> [*]
```

### Workflow Feedback

What is aligned:

- Chord entry stays in the product flow: write naturally, recognize, snap to a
  structured event, correct quickly, export cleanly.
- The current product decision is explicit: accepting/rendering a chord consumes
  the current chord-writing pass and clears the live chord ink layer.
- Correction remains a first-class escape hatch, which is right because
  correction speed matters more than perfect recognition.

What still needs live validation:

- A fresh simulator run from `main` should verify library open, chart creation,
  chord mode, correction, export reachability, and PDF preview after the PR
  merge.
- Handwriting quality should not be retuned from synthetic simulator strokes.
  Future quality work should use real Pencil/user input or fixture replay.

## Chord Recognition Pipeline

```mermaid
flowchart LR
    PK["native PKCanvasView ink"]
    Adapter["PencilKitInkAdapter"]
    Cluster["StrokeClusterer"]
    Glyph["GestureTemplateRecognizer"]
    Context["ChordInkSemanticGlyphContextualizer"]
    Compose["ChordInkCandidateComposer"]
    Semantic["ChordInkSemanticCandidateComposer"]
    Compendium["ChordRecognitionCompendium<br/>ChordSymbolParser"]
    Policy["ChordInkRecognitionPolicy<br/>ChordRecognitionTrustArbiter"]
    Event["structured ChordEvent"]

    PK --> Adapter --> Cluster --> Glyph --> Context --> Compose
    Semantic --> Compose
    Compose --> Compendium --> Policy --> Event
```

### Recognition Feedback

What is aligned:

- `ChordInkRecognizer` is again a facade/orchestrator instead of the owner of
  every semantic repair.
- `ChordInkSymbolLedger` is gated behind recognition options and does not run by
  default on the live path.
- OCR remains ambiguity-only and compendium-gated.
- The compendium/parser layer is still the final chord authority.

Maintenance risks:

- `StrokeClusterer.swift` and `StrokeClustererSupport.swift` together are nearly
  3k lines. They contain real recovered behavior, but should eventually become
  named deterministic passes.
- `GestureTemplateRecognizer.swift` is still large and mixes template matching
  with shape gates.
- `ChordInkSemanticCandidateComposer.swift` remains the largest semantic recipe
  file at about 1.6k lines.
- `ChordInkCandidateScoringPolicy.swift` is useful as a boundary, but it is
  still a dense cluster of scoring knobs. Threshold changes should stay tied to
  fixture evidence.
- `BasicMajorChordCompendium` remains as a compatibility wrapper around
  `ChordRecognitionCompendium` and is still referenced by tests. It is not a
  live runtime fork, but the old name is stale and should eventually disappear.

## Editor And Export System

```mermaid
flowchart TD
    Editor["EditorView"]
    Modes["EditorCanvasMode"]
    Canvas["LeadSheetCanvasHostView"]
    UIKit["LeadSheetCanvasUIKitView"]
    Layout["LeadSheetPageLayout"]
    ChordCommit["appendRecognizedChordEvent"]
    InkClear["setPageHandwrittenChordDrawing(nil)"]
    ExportButton["Export PDF button"]
    Entitlement["AppEntitlements.pdfExport"]
    Exporter["PDFChartExporter"]
    PDF["PDFExportPreviewView + Share"]

    Editor --> Modes
    Editor --> Canvas
    Canvas --> UIKit
    UIKit --> Layout
    Editor --> ChordCommit
    ChordCommit --> InkClear
    Editor --> ExportButton
    ExportButton --> Entitlement
    Entitlement --> Exporter
    Exporter --> PDF
```

Feedback:

- `EditorCanvasMode` is a useful authority surface. It centralizes which modes
  lock document actions, allow export, allow selection, and own ink capture.
- `LeadSheetCanvasUIKitView` correctly keeps native `PKCanvasView` as the ink
  renderer. That remains the right boundary for Apple Pencil feel.
- `EditorView` owns proposal confirmation, correction, entitlement-gated export,
  and diagnostic recording. It works, but it is a broad coordination surface and
  should be split only where a behavior-preserving seam is obvious.
- PDF export uses a service and PDF preview/share view, which is the right shape.
  The renderer is separate from editor UI and now avoids editor-only placeholder
  text in exports.
- Current export rendering is a clean prototype renderer, not yet a full shared
  geometry renderer with the on-screen page. Future layout/export unification is
  still a valid product polish target once authoring behavior stabilizes.

## Authority Boundaries

```mermaid
flowchart TD
    Ink["Ink capture<br/>may observe strokes"]
    Recognizer["Recognizer<br/>may propose candidates"]
    OCR["OCR sidecar<br/>may propose gated text"]
    Ledger["Symbol ledger<br/>may explain diagnostics"]
    Compendium["Compendium + parser<br/>may validate chord tokens"]
    Trust["Trust policy<br/>may choose action"]
    Editor["Editor/layout<br/>may place and commit"]
    Model["Chart model<br/>stores structured truth"]
    Export["Exporter<br/>renders structured truth"]

    Ink --> Recognizer
    Recognizer --> Compendium
    OCR -. ambiguity only .-> Compendium
    Ledger -. diagnostics only .-> Recognizer
    Compendium --> Trust
    Trust --> Editor
    Editor --> Model
    Model --> Export
```

Hard rules to preserve:

- Parser/compendium validate chord tokens.
- Recognition proposes, but does not own beat placement.
- Editor/layout decides target measure and fraction.
- Diagnostics may explain; they do not render a different answer.
- Export renders structured chart state, not editor-only placeholder text.

## Live Runtime vs Debug And Tooling

Live runtime:

- `ChartLibraryStore.live()` loads/saves a local JSON snapshot.
- `AppRootView` routes Projects to `EditorView`.
- `LeadSheetCanvasUIKitView` hosts `PKCanvasView` and routes mode-specific ink.
- Chord mode schedules recognition after idle delay.
- Accepted chord candidates append `ChordEvent` objects and clear chord ink.
- PDF export uses structured chart data.
- Pro gating decides whether export opens the upgrade sheet or generates a PDF.

Debug/simulator/tooling:

- Chord writing test chart creation exists only in debug/simulator contexts.
- Chord entry diagnostics record simulator/debug evidence.
- Symbol ledger diagnostics are opt-in through recognition options.
- Fixture import/watch/audit scripts support development and regression loops.
- `SmartChartTests/Fixtures/Ink` is test corpus, not app runtime data.
- `LibraryView` exposes the disposable Chord Writing Test Chart only in debug or
  simulator builds.

## Local Drift And Bloat Watchlist

Immediate local drift:

- The worktree contains untracked duplicate files under
  `SmartChartTests/Recognition` with names ending in ` 2.swift`.
- There are `14` duplicate files.
- All inspected duplicates are byte-identical to tracked files.
- Local SwiftPM verification fails until these duplicates are removed, moved, or
  excluded because they redeclare test helpers and test classes.
- Do not clean these in Sprint 12 without explicit approval; record them as
  local workspace drift first.

Tracked bloat/complexity:

- Recognition fixture corpus is valuable but large.
- Large recognition files are now organized better than before, but still need
  future behavior-preserving splits.
- `EditorView.swift` and `LeadSheetCanvasHostView.swift` remain broad
  coordination surfaces.
- README source-of-truth wording should be reconciled with the living sprint doc
  after this audit, because README still lists several older docs as active.

## Verification Status

Tracked GitHub state:

- `1e4ef82` passed SwiftPM tests, iOS simulator tests, and Analyze Swift on
  GitHub.

Local workspace state:

- `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py
  scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py`
  passed.
- `git diff --check -- docs/smart-chart-post-merge-app-audit-2026-05-23.md`
  passed.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint12` failed because
  untracked duplicate `* 2.swift` files under `SmartChartTests/Recognition` are
  compiled by SwiftPM and redeclare existing symbols.

Implication:

- The remote tracked project is green.
- The local workspace is not verification-clean until the duplicate files are
  handled.
- XcodeGen/iOS local verification should wait until the duplicate-file decision
  is made, because `project.yml` includes `SmartChartTests` by directory.

## Recommended Next Sprints

### Sprint 13 Candidate: Local Hygiene And Product Smoke

Goal: prove the merged `main` app path live and decide what to do with local
duplicate files.

Acceptance criteria:

- Fresh simulator smoke covers open, create/open chart, chord mode, recognition
  proposal or correction fallback, correction, export, and PDF preview.
- Local duplicate `* 2.swift` files are either explicitly removed or explicitly
  ignored with a documented reason.
- Local SwiftPM verification passes again after the duplicate-file decision.
- No recognition retuning.

### Sprint 14 Candidate: Editor Surface Boundary Cleanup

Goal: reduce editor coordination risk without changing behavior.

Acceptance criteria:

- Identify one small behavior-preserving extraction from `EditorView.swift` or
  `LeadSheetCanvasHostView.swift`.
- Preserve native `PKCanvasView` feel and chord ink lifecycle.
- Run iOS simulator tests.

### Sprint 15 Candidate: Recognition Maintenance Split

Goal: split one remaining large recognition area with fixture evidence.

Acceptance criteria:

- Choose one target: semantic candidate recipes, stroke clustering passes, or
  glyph-shape gates.
- Move code without score retuning.
- Run focused recognition tests, full SwiftPM tests, scripts py-compile, and
  iOS simulator tests if any editor-facing API changes.

## Remaining Sprint 12 Work

- Get explicit cleanup/ignore direction for the local duplicate test files, or
  leave Sprint 12 marked with local verification blocked by workspace drift.
- Run the Sprint 12 verification commands from the source-of-truth document.
- Run or explicitly defer a live simulator smoke pass from `main`.
- Link this audit from `docs/smart-chart-sprint-source-of-truth.md`.
- Close Sprint 12 with final evidence and next-sprint selection.
