# iChart V1.1 Roadmap

Status: active post-V1.0 product promise
Created: 2026-07-22
Revised: 2026-08-03

## Purpose

This document defines the V1.1 goal and public/internal statement after the
V1.0 release shape was narrowed to a more reliable promise.

If older docs imply handwritten rhythm recognition, full notation engraving,
key-signature support in V1.0, or select-input rhythm notation in V1.1, this
document supersedes that language for the current V1.1 roadmap.

## V1.0 Boundary

V1.0 ships as a trustworthy chart-writing app for working musicians:

- Simple Chord Sheet and Rhythm Section Sheet chart creation.
- Apple Pencil-first chord/chart authoring.
- Structured chords, repeats, form markings, text, meter, layout tools, PDF
  export, Projects, account identity, Pro entitlements, cloud backup, and
  Forums.
- Rhythm Section charts support staff layout and Free-Write rhythm notation, but
  the dedicated handwritten rhythm recognizer is retired from the shipping
  toolbar.
- Chord transposition is available as structured chord-symbol transposition. It
  is not key-signature engraving.

## V1.1 Statement

V1.1 will focus on chart-musician control rather than handwriting guesses:

> Add official key signatures, key-aware enharmonic chord spelling, and broader
> complex-chord coverage so iChart charts feel more complete, predictable, and
> player-ready without widening the release into a notation-input rebuild.

## V1.1 Goals

### Key Signatures

- Users can choose a concert key when starting a chart.
- Users can edit the chart key after creation without recreating the chart.
- Key signatures populate at the front of stanzas like an actual chart, in both
  the editor and PDF export.
- Chart modulations can change the active key at the correct musical location.
- Key changes and modulations provide the spelling context for rendered chord
  symbols.
- Keep chord-symbol transposition separate from visual key-signature rendering,
  but make both flows agree on the active musical key.

### Enharmonic Chord Spelling

- Chords enharmonically respond to their active key unless the chord was entered
  or manually corrected with a specific spelling.
- Users can tap a rendered chord and choose an alternate enharmonic spelling.
- Modulating the chart updates new-key chord spellings while preserving explicit
  user overrides.
- Chart-wide transposition and per-section modulation must maintain coherent
  chord spelling in the destination key.
- Avoid implying automatic arranging or generated horn parts; V1.1 improves chart
  spelling and key control, not full part generation.

### Additional Chord Coverage

- Produce a full internal printout of all covered chord types. This is not
  user-facing; it is a development and QA artifact for spotting coverage gaps.
- Expand supported chord recognition for obscure, complex, and less-common chord
  symbols that were not part of the V1.0 coverage pass.
- Add every newly supported chord family to the internal coverage printout.
- Keep new chord families validated through the chord compendium, parser, render
  path, and export path before they can ship as structured `ChordEvent`s.
- Prefer transferable chord-family coverage over one-off handwriting fixtures.
- Preserve the correction/confirmation loop for ambiguous complex chords rather
  than promising automatic recognition for every handwritten variant.

## Non-Goals

- No select-input rhythm notation in V1.1; that moves to V1.2.
- No return to handwriting-based rhythm recognition as a V1.1 requirement.
- No melody/lyric lead-sheet engraving promise.
- No automatic horn-part generation.
- No automatic cleanup of messy paper charts.
- No promise that every obscure chord spelling will auto-render from handwriting
  without confirmation.

## Acceptance Shape

V1.1 is ready when a tester can:

1. Create a chart with a chosen key and see the key signature at the front of
   chart stanzas in the editor and exported PDF.
2. Change the chart key and add a modulation that changes the active key at the
   intended musical location.
3. See chord spellings respond to the active key while preserving explicit
   chord-spelling overrides.
4. Tap a rendered chord and choose an alternate enharmonic spelling.
5. Transpose or modulate a chart and see new-key chord spellings remain coherent.
6. Generate the internal chord-coverage printout and confirm every newly
   supported chord family appears in it.
7. Write, confirm, render, save, reopen, and export a broader set of supported
   uncommon chord symbols.

## V1.2 Parking Lot

Select-input rhythm notation is now planned for V1.2. The V1.2 rhythm work
should remain deterministic: users choose rhythm values, rests, dots, ties, and
beamed groupings instead of relying on ink shape recognition.

Free-Write remains the reliable V1.1 path for personal rhythm ink, cues,
articulations, and markings.
