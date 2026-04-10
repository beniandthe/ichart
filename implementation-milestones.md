# Smart Chart — Implementation Milestones

Status: Active for prototype kickoff  
Source of truth: `docs/core-design-document.md`

## Purpose

This document turns the design and MVP docs into the first execution sequence.

## Milestone 0 — Repository and project bootstrap

Deliverables:
- real GitHub repository created
- Xcode iPad app project created
- base folder structure mapped to the planned module layout
- README and docs committed
- `.gitignore` added for Xcode/Swift projects

Exit criteria:
- project builds and runs a blank app shell
- repository has `main` branch and first docs commit

## Milestone 1 — Library and new chart shell

Deliverables:
- chart library placeholder screen
- new chart creation flow
- chart model persisted locally
- recent charts list wired to persistence

Exit criteria:
- user can create a new chart and reopen it after relaunch

## Milestone 2 — Static editor shell

Deliverables:
- editor screen with top bar, toolbar, and canvas
- systems and measures rendered from structured chart data
- sample chart data displayed cleanly
- zoom and pan behavior working

Exit criteria:
- sample one-page charts render reliably

## Milestone 3 — Object editing

Deliverables:
- chord object rendering
- section label rendering
- cue text rendering
- roadmap object rendering
- select, move, edit, delete, and reinterpret interactions
- inspector panel or popover

Exit criteria:
- a chart can be built and modified manually without Pencil recognition

## Milestone 4 — PDF export

Deliverables:
- structured-chart PDF renderer
- preview and share flow
- stable title/header layout
- readable one-page export output

Exit criteria:
- a manually built chart exports as a trustworthy PDF

## Milestone 5 — Pencil capture and candidate pipeline

Deliverables:
- PencilKit overlay integrated
- stroke grouping
- candidate extraction pipeline
- raw strokes linked to chart regions

Exit criteria:
- Pencil input is captured cleanly and attached to chart context

## Milestone 6 — Recognition v1

Deliverables:
- chord recognition
- section label recognition
- cue text recognition
- barline recognition
- confidence-based snapping and reinterpretation

Exit criteria:
- prototype scenario works end-to-end for common cases

## Milestone 7 — Roadmap recognition v1

Deliverables:
- repeat span
- ending 1 / ending 2
- coda / To Coda
- Segno
- D.S. / D.C.
- Fine
- vamp count
- N.C.

Exit criteria:
- working-musician beta users can create a short roadmap chart without unacceptable friction

## Release-critical guardrails

Do not block the prototype or v1 on:
- multi-page perfection
- collaboration
- accounts/backend
- playback
- full notation
- non-iPad platforms

## Current recommended next step

Start Milestone 0 immediately:
1. create the real GitHub repository
2. create the Xcode iPad project shell
3. commit the aligned docs
