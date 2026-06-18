# iChart

[![CI](https://github.com/beniandthe/smart-chart/actions/workflows/ci.yml/badge.svg)](https://github.com/beniandthe/smart-chart/actions/workflows/ci.yml)
[![CodeQL](https://github.com/beniandthe/smart-chart/actions/workflows/codeql.yml/badge.svg)](https://github.com/beniandthe/smart-chart/actions/workflows/codeql.yml)

iChart is an iPad-first, rhythm-aware chord chart builder for working musicians. It sits between paper charts, iReal Pro, and full notation software: fast enough for rehearsal prep, clean enough to hand to other players, and structured enough to transpose, edit, and export reliably.

## Core idea

**Write naturally with Apple Pencil, and iChart snaps your input into clean, editable chart objects.**

Chords stay central, but measures are time-aware: users can add time signatures and simple rhythmic values to show where chords land and where the hits are, without turning the app into full notation software.

## Product boundaries

iChart is:
- a stylus-first chart editor for iPad
- a structured tool for chord, roadmap, and rhythm-aware chart building
- a rehearsal and gig-prep utility
- a clean PDF export workflow for working players and teachers

iChart is not:
- full engraving or staff-based notation software
- melody or pitched note-entry software
- a DAW companion or playback-first app
- a PDF annotation app first
- a cross-platform-first product at launch

## Primary users

- working bandleaders
- gigging rhythm section players
- teachers creating simplified charts
- session players who need quick readable roadmaps

## Core promise

iChart should let a musician:
1. create a usable chart faster than paper cleanup,
2. show beat placement and implied hits when needed,
3. correct mistakes faster than rigid typed-entry tools,
4. export a chart they would trust at rehearsal or on a gig.

## V1 scope

Included in v1:
- iPad-first editor
- Apple Pencil input
- document key chosen at chart creation
- chart canvas with systems and measures
- time signatures
- beat-aware chord placement inside a measure
- limited rhythmic values tied to chord placement and hits
- document-wide font presets, with item-level font overrides later
- recognition for common chord symbols
- section labels
- cue text
- simple roadmap objects: repeat span, 1st/2nd endings, coda/To Coda, Segno, D.S./D.C., Fine, N.C., vamp count
- top-toolbar menus for fonts, transpose, notation, and text tools
- edit, reinterpret, move, and delete created objects
- auto-layout for strong one-page charts
- concert / Bb / Eb views
- PDF export and sharing

Explicitly out of scope for v1:
- full notation
- melody entry
- pitched note entry
- open-ended rhythm engraving unrelated to chord placement
- playback engine or backing tracks
- collaboration
- desktop app
- iPhone-first authoring
- required cloud backend

## Technical direction

Recommended v1 stack:
- **Platform:** iPadOS first
- **Language:** Swift
- **UI:** SwiftUI with UIKit bridges where the editor surface needs lower-level control
- **Ink capture:** PencilKit
- **Persistence:** SwiftData first, with a clean boundary so Core Data can replace it later if needed
- **Export:** native PDF generation and preview
- **Backend:** none required for v1; keep the app local-first

## Build philosophy

iChart should optimize for:
- speed over feature count
- structured chart logic over raw ink alone
- forgiving correction over perfect recognition
- rhythm support that clarifies chord placement without becoming full notation
- obvious top-level tools instead of buried controls
- clean output over decorative styling
- simple obvious modes over dense tool palettes

## Business model

Recommended product structure:
- free download with a limited local chart library
- one-time Pro unlock for ownership features: unlimited local charts, PDF export, transposition, font tools, special notation tools, and advanced rhythm-aware editing
- optional later subscription only for ongoing-service value such as cloud sync, cross-device organization, shared band libraries, setlists, version history, and AI-assisted cleanup

Business-model rules:
- users should be able to feel the product before paying
- local chart ownership should not feel rented
- recurring billing should fund real ongoing services, not basic save access
- v1 can launch with free + Pro even if no subscription ships yet

## Source-of-truth docs

Current implementation authority:

- [`docs/smart-chart-sprint-source-of-truth.md`](docs/smart-chart-sprint-source-of-truth.md) — active living sprint plan, recovery baseline, and current implementation authority
- [`docs/smart-chart-post-merge-app-audit-2026-05-23.md`](docs/smart-chart-post-merge-app-audit-2026-05-23.md) — post-merge written/visual app audit and Sprint 13-15 planning evidence
- [`docs/smart-chart-real-life-testing-readiness-2026-05-25.md`](docs/smart-chart-real-life-testing-readiness-2026-05-25.md) — Sprint 42 writing-to-render readiness handoff for real Pencil validation
- [`docs/smart-chart-real-pencil-field-test-log-2026-05-26.md`](docs/smart-chart-real-pencil-field-test-log-2026-05-26.md) — Sprint 43 real Pencil field-test evidence log
- [`docs/smart-chart-post-export-field-test-log-2026-05-26.md`](docs/smart-chart-post-export-field-test-log-2026-05-26.md) — Sprint 45 post-export real Pencil validation evidence log
- [`docs/smart-chart-recognition-latency-triage-2026-05-26.md`](docs/smart-chart-recognition-latency-triage-2026-05-26.md) — Sprint 46 recognition latency evidence
- [`docs/smart-chart-sprint-52-chord-confirmation-user-loop-2026-05-26.md`](docs/smart-chart-sprint-52-chord-confirmation-user-loop-2026-05-26.md) — Sprint 52 chord confirmation and local user correction loop
- [`docs/smart-chart-sprint-53-validation-speed-2026-05-26.md`](docs/smart-chart-sprint-53-validation-speed-2026-05-26.md) — Sprint 53 validation-speed policy and workflow cleanup
- [`docs/smart-chart-sprint-54-confirmation-ux-polish-2026-05-26.md`](docs/smart-chart-sprint-54-confirmation-ux-polish-2026-05-26.md) — Sprint 54 confirmation and correction sheet UX polish
- [`docs/smart-chart-sprint-55-chord-first-product-polish-2026-05-26.md`](docs/smart-chart-sprint-55-chord-first-product-polish-2026-05-26.md) — Sprint 55 chord-first product polish
- [`docs/smart-chart-sprint-56-chord-field-validation-2026-05-27.md`](docs/smart-chart-sprint-56-chord-field-validation-2026-05-27.md) — Sprint 56 bounded real-device chord validation
- [`docs/smart-chart-sprint-56-repeat-validation-log-2026-05-27.md`](docs/smart-chart-sprint-56-repeat-validation-log-2026-05-27.md) — Sprint 56 repeat validation gate
- [`docs/smart-chart-chord-first-side-sprints-2026-05-27.md`](docs/smart-chart-chord-first-side-sprints-2026-05-27.md) — active chord-first side-sprint route map
- [`docs/smart-chart-sprint-57-chord-placement-edit-loop-2026-05-27.md`](docs/smart-chart-sprint-57-chord-placement-edit-loop-2026-05-27.md) — Sprint 57 chord placement/edit loop
- [`docs/smart-chart-sprint-58-wrong-render-recovery-2026-05-27.md`](docs/smart-chart-sprint-58-wrong-render-recovery-2026-05-27.md) — Sprint 58 wrong render recovery and replace UX
- [`docs/smart-chart-sprint-59-confirmation-direct-input-polish-2026-05-27.md`](docs/smart-chart-sprint-59-confirmation-direct-input-polish-2026-05-27.md) — Sprint 59 confirmation and direct-input polish
- [`docs/smart-chart-sprint-60-general-candidate-availability-hardening-2026-05-27.md`](docs/smart-chart-sprint-60-general-candidate-availability-hardening-2026-05-27.md) — Sprint 60 general candidate availability hardening
- [`docs/smart-chart-sprint-61-raster-render-handoff-polish-2026-05-27.md`](docs/smart-chart-sprint-61-raster-render-handoff-polish-2026-05-27.md) — Sprint 61 raster/render handoff evidence
- [`docs/smart-chart-sprint-62-chord-first-release-candidate-pass-2026-05-27.md`](docs/smart-chart-sprint-62-chord-first-release-candidate-pass-2026-05-27.md) — Sprint 62 chord-first release-candidate pass
- [`docs/smart-chart-sprint-63-chart-layout-goals-2026-05-27.md`](docs/smart-chart-sprint-63-chart-layout-goals-2026-05-27.md) — Sprint 63 chart layout goals
- [`docs/smart-chart-sprint-64-new-chart-layout-style-chooser-2026-05-27.md`](docs/smart-chart-sprint-64-new-chart-layout-style-chooser-2026-05-27.md) — Sprint 64 New Chart layout-style chooser
- [`docs/smart-chart-sprint-65-layout-profile-contracts-2026-05-27.md`](docs/smart-chart-sprint-65-layout-profile-contracts-2026-05-27.md) — Sprint 65 layout-profile contracts
- [`docs/smart-chart-sprint-66-profile-driven-structure-defaults-2026-05-27.md`](docs/smart-chart-sprint-66-profile-driven-structure-defaults-2026-05-27.md) — Sprint 66 profile-driven structure defaults
- [`docs/core-design-document.md`](docs/core-design-document.md) — enforced product and design rules
- [`docs/developer-mvp-spec.md`](docs/developer-mvp-spec.md) — buildable MVP scope and behaviors
- [`docs/repo-github-recognition-audit-2026-05-20.md`](docs/repo-github-recognition-audit-2026-05-20.md) — current recognition architecture and GitHub audit evidence for the recovery plan

Supporting product and launch context:

- [`docs/monetization-strategy.md`](docs/monetization-strategy.md) — launch tiering, feature gating, and entitlement rules
- [`docs/v1-production-deployment.md`](docs/v1-production-deployment.md) — release and launch plan
- [`docs/basic-chart-creation-flow.md`](docs/basic-chart-creation-flow.md) — explicit step-by-step behavior for the most basic chart authoring flow

Historical or setup context:

- [`docs/technical-architecture.md`](docs/technical-architecture.md) — early architecture and first implementation order; subordinate to the living sprint doc when details conflict
- [`docs/implementation-milestones.md`](docs/implementation-milestones.md) — older prototype execution sequence; subordinate to the living sprint doc
- [`docs/github-bootstrap.md`](docs/github-bootstrap.md) — local repo and GitHub bootstrap steps
- [`docs/macos-handoff.md`](docs/macos-handoff.md) — Mac-side startup checklist, current scaffold state, and first validation steps
- [`docs/handwriting-recognition-implementation-plan.md`](docs/handwriting-recognition-implementation-plan.md) — historical recognition architecture and pass notes, subordinate to the living sprint doc
- [`docs/current-architecture-audit.md`](docs/current-architecture-audit.md) — historical editor-cleanup audit, stale for the current live recognition path
- [`docs/architecture-reset-proposal.md`](docs/architecture-reset-proposal.md) — historical proposal for the editor architecture reset

## Local validation

If full Xcode is not installed yet, the shared chart logic can still be compiled on macOS with Swift Package Manager:

```sh
swift build
```

This validates the non-UI parsing, transposition, timing, entitlement, and library-store layer. The iPad app target and XCTest suite still require Xcode plus XcodeGen.

## Prototype success criteria

The first meaningful prototype succeeds if a musician can:
- create a short chart with Pencil input
- show a split or syncopated chord measure clearly
- correct one or two recognition mistakes quickly
- export a readable PDF
- conclude that the app is faster than their current rough-chart workflow

## Status

Post-merge recovery/audit stage: the recognition recovery branch is merged into `main`; Sprints 12-62 restored the streamlined writer-agnostic recognition/editor pipeline, validated the writing-to-render loop with real app passes, added local chord-correction UX, shortened routine sprint validation, closed the first chord field-validation loop, and completed the chord-first release-candidate pass. Sprint 63 defined the three new-chart layout styles: Simple Chord Sheet, Rhythm Section Sheet, and Lead Sheet. Sprint 64 implemented the first `ChartLayoutStyle` New Chart chooser slice. Sprint 65 defined the layout-profile contracts for toolbar emphasis, measure defaults, notation-lane intent, and future renderer routing. Sprint 68 focuses V1 chart-structure systems on Simple Chord Sheet and Rhythm Section Sheet; Lead Sheet implementation notes are archived under `docs/post-v1/lead-sheet/` until after V1. Current sprint status lives in the source-of-truth doc.
