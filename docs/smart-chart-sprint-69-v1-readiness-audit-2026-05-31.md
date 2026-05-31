# Smart Chart Sprint 69 V1 Readiness Audit

Status: active audit sprint
Date: 2026-05-31
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`
Milestone checkpoint: `4dff695 Finalize Simple chart core authoring loop`

## Purpose

Sprint 69 is a short recursive closeout and V1 readiness audit after the Simple Chord Sheet core authoring loop became product-credible in live simulator use.

The goal is not to reopen old sprints by default. The goal is to classify all remaining known work into clear buckets, prove the current V1 loop from the app surface, and choose the next polish lane from evidence.

## Classification Buckets

- `Done`: implemented, covered by tests or live pass evidence, and not currently blocking V1.
- `V1 blocker`: must be fixed before a credible V1 release.
- `V1 polish`: improves the release feel but should be ranked against other polish work.
- `Post-V1`: intentionally after the first release.
- `Intentionally deferred`: valid idea, but not active until the user reopens it or new evidence makes it necessary.

## Initial Read

Done or currently product-proven:

- New Chart layout-style setup for Simple Chord Sheet, Rhythm Section Sheet, and Lead Sheet compatibility.
- One-measure minimum across chart creation and editing paths.
- Simple Chord Sheet core loop: create, write chords, auto-render, place on beat grid, move/delete/select, fit chords like a handwritten/iReal-style grid, and preserve writable space.
- Simple manual row flow: menu-owned row breaks, equal default row measures, proportional manual width weighting, row cap, and selected row-group guide.
- Simple chart-area freehand ink as movable measure-attached handwriting.
- Role-based typography with matched sets and per-role overrides.
- MuseJazz bundled from official MuseScore sources with license and SMuFL metadata.
- V1 structured roadmap/cue systems already implemented for active styles: repeat spans, first/second endings, point navigation markers, optional model-only links, cue text, and export/readability coverage.
- Rhythm Section core authoring and V4 rhythm-recognition gate: rhythm lane, chord lane, below-staff freehand articulations, exact-fit commit authority, and fail-closed local ink behavior.
- Lead Sheet planning and current baseline archived under `docs/post-v1/lead-sheet/`.

Likely Sprint 69 audit checks:

- Fresh app install flow: Projects -> New Chart -> Simple Chord Sheet and Rhythm Section Sheet.
- Save/reopen persistence for Simple chord layouts, typography choices, freehand, measure row breaks, roadmap objects, cue text, and exported layout.
- Export proof from real app state, not only layout fixtures.
- Toolstrip consistency after current Page/Measures/Roadmap/Text/Time/Chord/Free-Hand cleanup.
- Rhythm Section visual cohesion and whether it now lags Simple in professional polish.
- Any stale docs that still imply the old Simple above/below freehand lane, Lead Sheet as a V1 target, or generic shared layout behavior.

## Scope

This sprint may update docs, add audit checklists, run tests, run fresh simulator passes, and make tiny fixes only when they are clearly audit-found regressions.

Larger implementation should wait until the audit says which lane is next.

## Non-Goals

- No chord-recognition score retuning.
- No OCR expansion.
- No personal handwriting fixture expansion.
- No default diagnostics stream.
- No Rhythm Section manual row/system breaks unless the audit upgrades them to V1 blockers.
- No rhythm-object editing.
- No vamp count.
- No handwritten recognition for section labels, cue text, or articulations.
- No Lead Sheet feature expansion before V1.

## Step-by-Step Plan

1. Preserve the Simple core-loop milestone remotely. Status: pushed at `4dff695`.
2. Audit current sprint docs and active code surfaces against the V1 classification buckets.
3. Run baseline verification:
   - `git status --short --branch`
   - `git diff --check`
   - focused tests for chart editing, layout, typography, interaction policy, rhythm quantizer, and PDF export
   - full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`
4. Run a fresh simulator pass for Simple Chord Sheet:
   - create a new Simple chart
   - write one-chord, two-chord, and three-or-more-chord measures
   - move chords beat-to-beat
   - change chord font role
   - add row break, cue text, repeat/ending/point marker, and freehand object
   - save/reopen and export
5. Run a fresh simulator pass for Rhythm Section Sheet:
   - create a new Rhythm Section chart
   - write slashes, quarter-note rhythm phrases, and beamed eighths
   - add chords with no-rhythm beat fallback and rhythm-slot snapping
   - add below-staff freehand articulation, cue text, and roadmap objects
   - save/reopen and export
6. Produce a V1 readiness matrix with recommendations for the next implementation sprint.

## Acceptance Criteria

- The milestone commit is pushed.
- Source-of-truth docs name Sprint 69 as the active audit sprint.
- Old Sprint 68 work is marked as complete enough for the current milestone, with remaining items intentionally classified.
- The next work lane is chosen from evidence, not from stale backlog momentum.
