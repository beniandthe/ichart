# Smart Chart

Smart Chart is an iPad-first chart builder for working musicians. It sits between paper charts, iReal Pro, and full notation software: fast enough for rehearsal prep, clean enough to hand to other players, and structured enough to transpose, edit, and export reliably.

## Core idea

**Write naturally with Apple Pencil, and Smart Chart snaps your input into clean, editable chart objects.**

## Product boundaries

Smart Chart is:
- a stylus-first chart editor for iPad
- a structured tool for chord and roadmap charts
- a rehearsal and gig-prep utility
- a clean PDF export workflow for working players and teachers

Smart Chart is not:
- full engraving or staff-based notation software
- a DAW companion or playback-first app
- a lyric prompter first
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
2. correct mistakes faster than rigid typed-entry tools,
3. export a chart they would trust at rehearsal or on a gig.

## V1 scope

Included in v1:
- iPad-first editor
- Apple Pencil input
- chart canvas with systems and measures
- recognition for common chord symbols
- section labels
- cue text
- simple roadmap objects: repeat span, 1st/2nd endings, coda/To Coda, Segno, D.S./D.C., Fine, N.C., vamp count
- edit, reinterpret, move, and delete created objects
- auto-layout for strong one-page charts
- concert / Bb / Eb views
- PDF export and sharing

Explicitly out of scope for v1:
- full rhythmic notation
- melody entry
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
- clean output over decorative styling
- simple obvious modes over dense tool palettes

## Source-of-truth docs

- [`docs/core-design-document.md`](docs/core-design-document.md) — enforced product and design rules
- [`docs/developer-mvp-spec.md`](docs/developer-mvp-spec.md) — buildable MVP scope and behaviors
- [`docs/technical-architecture.md`](docs/technical-architecture.md) — architecture and first implementation order
- [`docs/v1-production-deployment.md`](docs/v1-production-deployment.md) — release and launch plan
- [`docs/github-bootstrap.md`](docs/github-bootstrap.md) — local repo and GitHub bootstrap steps

## Prototype success criteria

The first meaningful prototype succeeds if a musician can:
- create a short chart with Pencil input,
- correct one or two recognition mistakes quickly,
- export a readable PDF,
- and conclude that the app is faster than their current rough-chart workflow.

## Status

Planning, specification, and initial scaffold stage.
