# Smart Chart

[![CI](https://github.com/beniandthe/smart-chart/actions/workflows/ci.yml/badge.svg)](https://github.com/beniandthe/smart-chart/actions/workflows/ci.yml)
[![CodeQL](https://github.com/beniandthe/smart-chart/actions/workflows/codeql.yml/badge.svg)](https://github.com/beniandthe/smart-chart/actions/workflows/codeql.yml)

Smart Chart is an iPad-first, rhythm-aware chord chart builder for working musicians. It sits between paper charts, iReal Pro, and full notation software: fast enough for rehearsal prep, clean enough to hand to other players, and structured enough to transpose, edit, and export reliably.

## Core idea

**Write naturally with Apple Pencil, and Smart Chart snaps your input into clean, editable chart objects.**

Chords stay central, but measures are time-aware: users can add time signatures and simple rhythmic values to show where chords land and where the hits are, without turning the app into full notation software.

## Product boundaries

Smart Chart is:
- a stylus-first chart editor for iPad
- a structured tool for chord, roadmap, and rhythm-aware chart building
- a rehearsal and gig-prep utility
- a clean PDF export workflow for working players and teachers

Smart Chart is not:
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

Smart Chart should let a musician:
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

Smart Chart should optimize for:
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

Active authority:

- [`docs/smart-chart-sprint-source-of-truth.md`](docs/smart-chart-sprint-source-of-truth.md) — active living sprint plan, recovery baseline, and current implementation authority
- [`docs/core-design-document.md`](docs/core-design-document.md) — enforced product and design rules
- [`docs/developer-mvp-spec.md`](docs/developer-mvp-spec.md) — buildable MVP scope and behaviors
- [`docs/monetization-strategy.md`](docs/monetization-strategy.md) — launch tiering, feature gating, and entitlement rules
- [`docs/technical-architecture.md`](docs/technical-architecture.md) — architecture and first implementation order
- [`docs/implementation-milestones.md`](docs/implementation-milestones.md) — execution sequence for the prototype
- [`docs/repo-github-recognition-audit-2026-05-20.md`](docs/repo-github-recognition-audit-2026-05-20.md) — current recognition architecture and GitHub audit evidence for the recovery plan
- [`docs/v1-production-deployment.md`](docs/v1-production-deployment.md) — release and launch plan
- [`docs/github-bootstrap.md`](docs/github-bootstrap.md) — local repo and GitHub bootstrap steps
- [`docs/macos-handoff.md`](docs/macos-handoff.md) — Mac-side startup checklist, current scaffold state, and first validation steps
- [`docs/basic-chart-creation-flow.md`](docs/basic-chart-creation-flow.md) — explicit step-by-step behavior for the most basic chart authoring flow

Historical context:

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

Planning, specification, and initial scaffold stage.
