# iChart Sprint 63 Chart Layout Goals

Status: complete planning handoff
Date: 2026-05-27
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Purpose

Sprint 63 defines the next product architecture layer after the chord-first release-candidate pass: separate chart layout choices at new-chart creation.

This sprint is the planning and product-contract handoff into Sprint 64. Do not start by changing recognition, chord confidence, handwriting fixtures, or renderer internals.

## Product Decision

When the user taps `New Chart`, iChart should present three layout choices:

1. `Simple Chord Sheet`
2. `Rhythm Section Sheet`
3. `Lead Sheet`

The choice should happen before the blank editor opens. The selected layout becomes a durable chart attribute that influences setup defaults, page layout, notation lanes, toolbar emphasis, export rendering, and future feature availability.

Implementation name selected for Sprint 64: `ChartLayoutStyle`.

This is intentionally separate from the older `ChartType`, which remains a legacy/product-category field. Missing layout style data from older saved charts should decode as `Lead Sheet`, because the current app renderer is lead-sheet-like.

## Layout 1: Simple Chord Sheet

Working name: `Simple Chord Sheet`

Reference feel: iReal Pro-style fast chord grid, but local-first, editable, exportable, and iChart-native.

Primary user intent:

- Create a clean harmonic roadmap quickly.
- Prioritize chords, sections, repeats, endings, and transposition.
- Keep the page dense and readable.
- Avoid full staff notation and detailed rhythmic engraving.

Core systems:

- Chord-entry lane: primary surface.
- Measure grid: compact, repeat-friendly, optimized for many bars per page.
- Section labels: high priority.
- Roadmap symbols: high priority.
- Beat placement: available, but visually lightweight.
- Rhythmic hits: limited or secondary.
- Export: dense one-page chord sheet.

Default behavior:

- Start with chord-chart presentation, not staff-heavy lead-sheet presentation.
- Favor compact systems and clear measure boxes.
- Keep the toolbar focused on chords, sections, repeats, endings, and transposition.

## Layout 2: Rhythm Section Sheet

Working name: `Rhythm Section Sheet`

Reference feel: working rhythm chart for a bandstand or rehearsal.

Primary user intent:

- Show harmonic form plus important rhythmic information.
- Communicate hits, pushes, holds, stops, groove notes, and slash/rhythm notation.
- Give rhythm section players enough timing clarity without becoming full notation software.

Core systems:

- Chord-entry lane: primary surface.
- Rhythm/hit lane: first-class.
- Slash/rhythmic notation: first-class, but still chord-attached and measure-aware.
- Cue text: high priority for groove and hits.
- Section labels and roadmap symbols: high priority.
- Beat placement and duration: visually explicit.
- Export: readable rhythm-section handout with chords and rhythmic clarity.

Default behavior:

- Start with staff or rhythm-line presentation where rhythmic slashes and hits have room.
- Toolbar should make rhythm values, hits, and cue text easy to reach.
- Recognition remains chord-first, but rhythmic notation entry has an obvious lane.

## Layout 3: Lead Sheet

Working name: `Lead Sheet`

Reference feel: clean lead-sheet page structure.

Primary user intent:

- Build the most notation-like chart iChart supports.
- Present chords with a more formal staff/page layout.
- Support section labels, cue text, roadmap objects, and rhythm-aware chord placement.

V1 boundary:

- This is not full melody or pitched-note notation yet.
- Do not pull Sprint 63 into full notation, lyrics, multi-voice engraving, playback, or DAW-style workflows.
- The lead-sheet layout can reserve space and model boundaries for future melody, but current iChart authority remains chord-first and rhythm-aware.

Core systems:

- Staff/page presentation: primary surface.
- Chord-entry lane: first-class above the staff.
- Rhythm placement: visible and beat-aware.
- Cue text and section labels: first-class.
- Roadmap symbols: supported, but not allowed to break page readability.
- Export: polished lead-sheet style page.

Default behavior:

- Start with the current lead-sheet-like page renderer as the closest existing implementation.
- Preserve the write -> recognize -> snap -> fix -> export loop.
- Keep full notation out of scope until a future product decision explicitly expands the boundary.

## Shared Chart-Structure Systems

All three layouts need shared structured systems:

- chart metadata: title, composer/credit, key, meter, transposition view, layout selection
- systems and measures: deterministic page/system/measure model
- chord events: structured, transposable, editable
- beat placement: editor/layout-owned, not recognition-owned
- section labels: form anchors
- roadmap objects: repeats, endings, coda/segno, D.S./D.C., Fine, N.C., vamp count
- cue text: musician-facing notes
- export: one renderer path per layout family, sharing model truth
- raw ink evidence: linked to structured objects when useful, not runtime authority

## Sprint 64 Implementation Handoff

The first thin Sprint 64 implementation slice should:

- Add a `New Chart` layout chooser with the three options.
- Persist the chosen layout as `ChartLayoutStyle` on the chart.
- Map each option to safe setup defaults.
- Keep existing charts backward-compatible by decoding missing layout data as `Lead Sheet`.
- Keep the current renderer behavior for the lead-sheet-like default until layout-specific rendering is implemented.

Potential model direction:

- Prefer a dedicated chart-layout concept over overloading recognition or editor mode.
- Use `ChartLayoutStyle` beside `ChartType`; do not turn recognition or editor mode into layout authority.
- Preserve old `ChartType` decoding for existing saved charts.

## Non-Goals

- No recognition behavior change.
- No personal handwriting fixture expansion.
- No score retuning.
- No default OCR expansion.
- No symbol-ledger diagnostics cost.
- No full notation/melody expansion.
- No broad renderer rewrite until layout contracts are explicit.

## Acceptance Criteria

- The three new-chart layout choices are named and defined.
- Each layout has a clear user intent and system emphasis.
- Shared chart-structure systems are identified.
- Sprint 64 can build the chooser without debating product taxonomy again.
- Existing saved charts remain compatible when Sprint 64 adds durable layout data.
