# iChart V1.1 Roadmap

Status: active post-V1 product promise
Created: 2026-07-22

## Purpose

This document defines the V1.1 goal and public/internal statement after the
V1.0 release shape was narrowed to a more reliable promise.

If older docs imply handwritten rhythm recognition, full notation engraving, or
key-signature support in V1.0, this document supersedes that language for the
V1.1 roadmap.

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

> Add key signatures, deterministic rhythm-notation input, and stronger
> transposition preferences, while expanding chord coverage so iChart charts
> feel more complete, predictable, and player-ready.

## V1.1 Goals

### Key Signatures

- Add key-signature support to chart setup and editing.
- Render key signatures on supported chart styles where they make musical sense.
- Keep Rhythm Section chart behavior deliberate: key signatures should not be
  forced into layouts where the product has chosen keyless chart identity.
- Keep chord-symbol transposition separate from visual key-signature rendering.

### Select Input For Rhythm Notation

- Replace the retired handwritten rhythm recognizer with a literal/select input
  system.
- Input should be deterministic: users choose rhythm values, rests, dots, ties,
  and beamed groupings instead of relying on ink shape recognition.
- Preserve the existing rhythm-map model, renderer, export path, and saved-data
  compatibility for charts that already contain rendered rhythm maps.
- Free-Write remains available for personal rhythm ink, cues, articulations, and
  markings.

### Enharmonic Transposition And Preferences

- Add enharmonic spelling controls for transposed chord symbols.
- Add user/chart preferences for sharp/flat spelling and common instrument
  transposition defaults.
- Keep transposition predictable and reversible where possible.
- Avoid implying automatic arranging or generated horn parts; V1.1 improves chart
  spelling/control, not full part generation.

### Additional Chord Coverage

- Expand supported chord recognition for obscure and less-common chord symbols
  that were not part of the V1.0 coverage pass.
- Keep new chord families validated through the chord compendium and parser
  before they can render as structured `ChordEvent`s.
- Prefer transferable chord-family coverage over one-off handwriting fixtures.
- Preserve the correction/confirmation loop for ambiguous complex chords rather
  than promising automatic recognition for every handwritten variant.

## Non-Goals

- No return to handwriting-based rhythm recognition as a V1.1 requirement.
- No melody/lyric lead-sheet engraving promise.
- No automatic horn-part generation.
- No automatic cleanup of messy paper charts.
- No promise that every obscure chord spelling will auto-render from handwriting
  without confirmation.

## Acceptance Shape

V1.1 is ready when a tester can:

1. Create or edit a chart with a visible key signature where supported.
2. Enter basic rhythm notation through a select-input flow without handwriting
   recognition.
3. Transpose chord symbols with enharmonic spelling that matches the user's
   selected preference.
4. Write, confirm, and render a broader set of supported uncommon chord symbols.
5. Export a PDF whose key signatures, rhythms, chord spellings, and visible
   chart metadata match the in-app chart.
