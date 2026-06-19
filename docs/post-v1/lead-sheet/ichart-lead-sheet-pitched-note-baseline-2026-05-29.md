# iChart Lead Sheet Pitched-Note Baseline

Status: implemented locally; richer Lead Sheet systems deferred until after V1
Date: 2026-05-29
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `../../ichart-sprint-source-of-truth.md`

## Purpose

This slice resumes the main chart-style plan after the Rhythm Section/V4 rhythm-recognition detour. It adds the smallest Lead Sheet note-entry proof without expanding into full notation engraving.

The baseline goal is narrow: a recognized note rhythm in a Lead Sheet measure can become a structured pitched note event snapped to an in-staff position. Ledger lines, named-pitch spelling, note editing, and full melody systems stay out of scope.

## Implemented Slice

- `Measure` now persists `LeadSheetPitchedNoteEvent` objects with rhythm-slot indices and clamped in-staff positions.
- `LeadSheetStaffPosition` clamps note placement to staff steps `0...8`, preserving the no-ledger-lines rule.
- `Chart.setLeadSheetPitchedNotes` commits exact-fit pitched-note rhythm values only for `Lead Sheet` charts and clears the consumed handwritten rhythm ink.
- `Chart.setLeadSheetRhythmMap` now accepts mixed Lead Sheet note/rest phrases while storing pitched-note events only on note-capable rhythm slots, and rejects partial or duplicate pitch coverage.
- `Measure.clearInvalidRhythmSlotAssignments` prunes pitched-note events when the rhythm map changes or no longer supports pitched notes.
- `LeadSheetPageLayoutEngine` renders Lead Sheet pitched notes on staff positions while keeping Rhythm Section rhythm maps as slash/rest notation.
- `RhythmicNotationQuantizer` exposes deterministic visual note anchors from the V4 crop pipeline so Lead Sheet finalization can map accepted note rhythms to staff steps.
- `LeadSheetRhythmicNotationFinalization` converts Lead Sheet rhythm commits into pitched-note events when visual note anchors match every note-capable slot in the accepted values.
- Stem-down staff notes are protected from being read as single eighths solely because the notehead sits above the stem.
- Beamed eighth groups can supply multiple Lead Sheet pitch anchors from one V4 crop, so accepted beamed-eighth rhythm values can map each eighth note to its own staff position.

## Current Contract

- Lead Sheet setup still asks for key, time signature, starting measures, and treble/bass clef.
- Chords remain in the existing chord lane above the measure.
- Note entry uses the same rhythm auto-render confidence gate as Rhythm Section, then adds staff-position snapping for Lead Sheet charts.
- Rhythmic-notation ink remains enabled for Lead Sheet through `ChartLayoutProfile`; this is separate from the user-facing note/rhythm edit surface.
- Rhythm Section and Simple Chord Sheet behavior do not receive pitched-note events.
- If Lead Sheet note ink cannot provide exactly one matching visual note anchor for every note-capable slot, the ink stays local instead of committing a misleading pitched-note map.
- Lead Sheet has no freehand symbol ink lanes for now; profile-owned freehand availability resolves no freehand page-ink scope until that slice is explicitly designed.

## Deferred

- Ledger lines.
- Clef-specific named pitch spelling.
- Key-aware accidentals on notes.
- Individual note editing/moving.
- Beam engraving for pitched eighths. The current baseline stores the beamed-eighth pitch anchors and renders accepted eighths with the existing individual eighth-note layout.
- Any ML, OCR, personal handwriting training, fixture expansion, or global recognizer retuning.

## Verification Log

- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests --filter LeadSheetPageLayoutTests` passed with `86` tests and `0` failures after the mixed note/rest model and layout baseline.
- XcodeBuildMCP focused `test_sim` for the Lead Sheet pitched-note finalization cases passed with `2` tests and `0` failures.
- XcodeBuildMCP focused `test_sim` for mixed Lead Sheet note/rest finalization passed with `1` test and `0` failures.
- XcodeBuildMCP focused `test_sim` for beamed-eighth Lead Sheet pitch-anchor finalization passed with `1` test and `0` failures.
- XcodeBuildMCP `test_sim` for `RhythmicNotationQuantizerTests` passed with `78` tests and `0` failures after adding mixed note/rest and beamed-eighth pitch-anchor finalization.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `186` tests and `0` failures.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the mixed note/rest slice and again after the pitch-coverage guard.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `48` tests and `0` failures after tightening Lead Sheet pitch coverage to require every note-capable slot.
- XcodeBuildMCP focused `test_sim` for `LeadSheetInteractionModeStatePolicyTests` and `ChartEditingTests` passed with `67` tests and `0` failures after the profile-owned rhythmic-notation availability guard.
- XcodeBuildMCP grouped `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests` passed with `188` tests and `0` failures after the profile-owned rhythmic-notation availability guard.
- Full `swift test --scratch-path /tmp/iChartSwiftBuild-layoutprofile` passed with `362` tests, `36` skipped, and `0` failures after the profile-owned rhythmic-notation availability guard.
- `git diff --check` passed after the pitch-coverage guard and doc audit.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` plus screenshot capture succeeded with the existing headermap warning only after the pitch-coverage guard.
