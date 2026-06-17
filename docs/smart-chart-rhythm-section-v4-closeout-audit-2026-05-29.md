# Smart Chart Rhythm Section V4 Closeout Audit

Status: local implementation audit
Date: 2026-05-29
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

This audit records the current end state of the Rhythm Section side sprint, Rhythm Recognition V3/V4 rebuild, and the resumed Lead Sheet baseline. It separates implemented core authoring systems from product-definition-gated follow-up work.

## Implemented Core

- New Chart layout styles are wired through `ChartLayoutStyle` and `ChartLayoutProfile`.
- All chart creation paths preserve the one-measure minimum.
- Rhythm Section setup remains keyless and clefless while preserving time signature and starting measures.
- Rhythm Section keeps staff-line measures, rhythm notation inside the measure lane, chords above staff, rhythm-slot chord snapping, and beat-grid fallback when no rhythm exists.
- Measure insertion at the beginning is supported through chart editing, preserving existing measure IDs and anchors while reindexing order.
- Free-hand symbol policy is profile-owned: Simple now uses measure-attached chart-area freehand objects, Rhythm Section supports below-staff only, and Lead Sheet has no free-hand symbol lane for now.
- Rhythmic-notation ink availability is profile-owned: Simple has no rhythm-notation ink scope, Rhythm Section and Lead Sheet keep that scope.
- User-facing rhythm-note editing availability is profile-owned: Simple and Rhythm Section remain disabled, Lead Sheet keeps the existing note/rhythm edit surface.
- Ink tools expose write/erase modes for active canvas ink, and erase mode only affects live ink strokes.

## Rhythm Recognition

- V3 remains a fail-closed bridge with explicit `commit`, `keepWriting`, and `needsReview` decisions.
- V4 is implemented as a deterministic raster/template phrase gate before V3.
- V4 normalizes live measure ink into left-to-right symbol crops, matches a writer-agnostic visual compendium, validates values through `RhythmicNotationCompendium` and `MeasureRhythmMap`, and requires render alignment before commit.
- V4 covers slashes, quarters, halves, wholes, single eighths, beamed eighth pairs, dotted quarters, dotted halves, eighth rests, quarter rests, half rests, and whole-rest review behavior.
- V4 rejects tiny isolated noise before crop grouping while preserving meaningful unsupported marks as local unread crop feedback.
- Unsupported, underfilled, overflow, ambiguous, uncovered-stroke, non-natural exact-fit, and fallback-only paths preserve ink instead of clearing live rhythm strokes.
- Red unread feedback waits for completed-looking decisions and localizes to unread crop/stroke bounds when possible.
- Runtime trace helpers and one-off replay helpers are removed from the default product path.

## Architecture

- `RhythmicNotationQuantizer` remains the public recognizer/proposal entrypoint and the V3/visual/fallback bridge.
- `RhythmicNotationRasterTemplateRecognizer` owns V4 raster input, symbol crops, visual template matches, phrase decisions, render comparison, and visual note anchors.
- `RhythmicNotationRecognitionTypes` owns shared quantization errors, proposal safety, primitives, phrase hypotheses, decisions, reasons, candidates, and candidate paths.
- `MeasureRhythmMap`, resolved slots, and `RhythmicNotationCompendium` remain the structured chart authority after a phrase commits.

## Lead Sheet Baseline

- Lead Sheet setup stores key, time signature, starting measures, and treble/bass clef.
- Lead Sheet layout renders the selected clef and first-system key signature before the time signature.
- Accepted Lead Sheet rhythm ink can create clamped in-staff pitched-note events when V4 visual note anchors cover every note-capable slot exactly once.
- Mixed note/rest phrases preserve rest glyphs while storing pitched events only on note-capable rhythm slots.
- Beamed-eighth V4 crops can provide separate pitch anchors for each accepted eighth value.

## Verification Snapshot

- XcodeBuildMCP focused `test_sim` for `RhythmicNotationQuantizerTests`: `78` passed, `0` failed.
- XcodeBuildMCP grouped simulator `test_sim` for `RhythmicNotationQuantizerTests`, `LeadSheetInteractionModeStatePolicyTests`, `ChartEditingTests`, `LeadSheetPageLayoutTests`, and `SmuflFontMetadataTests`: `188` passed, `0` failed.
- Full `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile`: `362` tests, `36` skipped, `0` failures.
- `git diff --check`: passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO`: passed with the existing headermap warning only.
- Screenshot captured after launch: `/var/folders/8g/kslp9zm178l_8pmjnh37lsnc0000gn/T/screenshot_optimized_6a7c6ac4-4f00-4647-92e7-e9a5b01fbf13.jpg`.

## Deferred By Design

- Rhythm Section section/system layout and grouping.
- Rhythm Section individual rhythm object editing.
- Rhythm Section articulation recognition.
- Simple Chord Sheet free-hand resizing, semantic classification, or rhythm snapping.
- Lead Sheet ledger lines, named pitch spelling, key-aware accidental mutation, richer melody editing, and beam engraving beyond the current baseline.
- Any chord-recognition score retuning, OCR expansion, personal handwriting fixture expansion, ML training, or default diagnostic stream.

## Routing Note

The next implementation should not start the deferred layout systems until the user defines the target behavior. Safe work before that point is limited to behavior-preserving architecture cleanup, documentation closure, verification, or bug fixes found by current tests/simulator evidence.
