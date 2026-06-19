# iChart Sprint 67 Rhythm Section Current Workflow Lock

Status: complete behavior-lock checkpoint; superseded by active Rhythm Section side sprint
Date: 2026-05-27
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Purpose

Sprint 67 keeps momentum after Sprint 66 without widening the renderer surface. The goal is to make `Rhythm Section Sheet` explicitly mean the current basic iChart workflow: staff-line measures, rhythm writing between barlines, chords above the staff, rhythm-aware chord placement when rhythm exists, and beat-grid fallback when it does not.

This sprint is a behavior lock first, not a redesign. Do not add a new rhythm-section renderer, do not bring key setup back, and do not start new rhythm-recognition behavior unless the user explicitly scopes that slice.

## Rhythm Section Contract

- Setup omits key and clef for now.
- Setup keeps starting time and starting measures.
- Measures are real measures with staff lines.
- Rhythms are written between barlines and snap to the measure.
- Chords are written above the staff in the chord writing lane.
- Chords snap to written rhythms and can be moved to other rhythms.
- If a measure has no written rhythm yet, chord placement uses the existing beat-grid fallback behavior.
- Simple Chord Sheet above-measure free-hand lanes do not appear on Rhythm Section sheets.
- The follow-on Rhythm Section side sprint owns below-staff free-hand articulation lanes.

## Implemented Slice

- Added a focused layout regression that pins `Rhythm Section Sheet` to the existing staff/rhythm/chord workflow.
- The test verifies key header suppression, meter/header retention, staff lines, leading notation, no Simple free-hand lanes, rhythm-map note layouts, chord lane above staff, and chord alignment to rhythm attack centers.

## Step-By-Step Plan

0. Close Sprint 66 locally. Status: complete.
   - Sprint 66 remains pending final commit in the current local change set.
   - Preserve its verified Simple Chord Sheet capture/render/select/move/delete behavior.

1. Add Rhythm Section workflow lock coverage. Status: complete.
   - Pin the current workflow designation with a focused layout test.
   - Avoid production behavior changes unless a test exposes a real drift.

2. Verify proportionally. Status: complete.
   - Run focused `LeadSheetPageLayoutTests` for the new guard.
   - Run the full SwiftPM suite after the doc update lands.
   - Run simulator compile only if app-target behavior changes.

3. Pause before new Rhythm Section systems. Status: complete.
   - New rhythm-section layout/system changes are now scoped in `docs/ichart-rhythm-section-side-sprint-plan-2026-05-27.md`.
   - Candidate future slices include rhythm cue editing polish, move-to-rhythm-slot UX, measure grouping, and section/cue surfaces.

## Guardrails

- No recognition, parser, compendium, OCR, symbol-ledger, or fixture changes.
- No key setup reintroduction for Rhythm Section Sheet.
- No Simple Chord Sheet above-measure free-hand lane leakage into Rhythm Section Sheet.
- No Lead Sheet pitched-note work.
- No broad renderer/export rewrite.

## Acceptance Criteria

- `Rhythm Section Sheet` remains keyless at setup and in the header.
- It still renders the current staff system with clef/time-signature leading notation.
- Rhythms render between barlines when a rhythm map exists.
- Chords render above the staff and align to written rhythm attack centers.
- Above-measure free-hand lanes stay Simple-only; below-measure Rhythm Section articulation lanes are owned by the active side sprint.

## Verification Log

- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter LeadSheetPageLayoutTests/testRhythmSectionSheetPreservesCurrentRhythmAndChordWorkflow` passed with `1` test, `0` failures after adding the Rhythm Section workflow lock guard.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `348` tests, `36` skipped, `0` failures after opening Sprint 67 and adding the Rhythm Section workflow guard.
