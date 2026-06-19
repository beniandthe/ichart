# iChart — Implementation Milestones

Status: historical prototype kickoff sequence
Product source of truth: `docs/core-design-document.md`
Current implementation source of truth: `docs/ichart-sprint-source-of-truth.md`

## Purpose

This document turns the design and MVP docs into the first execution sequence.

Current sprint execution has moved beyond this initial milestone list. Use the living sprint source of truth for the active architecture, validation state, and next-sprint decisions.

## Milestone 0 — Repository and project bootstrap

Deliverables:
- real GitHub repository created
- Xcode iPad app project or checked-in project generation spec created
- base folder structure mapped to the planned module layout
- README and docs committed
- `.gitignore` added for Xcode/Swift projects

Exit criteria:
- project definition is ready for Mac-side generation/build, and the blank app shell runs once opened in Xcode
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
- default time signature displayed
- sample chart data displayed cleanly
- zoom and pan behavior working

Exit criteria:
- sample one-page charts render reliably

## Milestone 3 — Manual object editing

Deliverables:
- chord event rendering
- section label rendering
- cue text rendering
- roadmap object rendering
- top toolbar menus for fonts, transpose, notation, and text
- manual beat placement and duration editing for chord events
- document key and font controls
- meter editing
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
- rhythm-aware chord placement preserved in export

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
- time signature recognition
- limited rhythm-value recognition for chord timing
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

## Milestone 8 — Monetization foundation

Deliverables:
- mandatory account/auth/profile foundation for Basic and Pro users
- local entitlement state
- Basic 3-chart cap messaging in the library
- Pro gating hooks for cloud chart backup/sync/restore
- Pro gating hooks for Forums
- Basic 3-chart cap with complete local tool and PDF/export access
- downgrade flow that lets users prune selected local charts down to the 3-chart Basic cap
- local-only downgrade pruning that does not create cloud deletion tombstones
- purchase/subscription restoration path planned behind a StoreKit boundary
- chart cloud services reserved for active Pro entitlement

Exit criteria:
- the app can express Basic account and Pro subscription rules cleanly without making local chart editing, local save, or export depend on cloud chart sync

## Release-critical guardrails

Do not block the prototype or v1 on:
- multi-page perfection
- collaboration
- full cloud chart sync if the account/auth foundation is in place and chart sync can stay Pro-gated
- playback
- full notation
- non-iPad platforms
- cloud chart dependency in the editor

## Current recommended next step

Start Milestone 0 immediately:
1. generate or open the Xcode project from the checked-in scaffold on a Mac
2. verify the blank app shell launches and the sample library/editor views render
3. begin manual chart editing on top of the current domain models
