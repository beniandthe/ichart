# iChart V1.3 Roadmap

Status: active parking lot
Created: 2026-08-09

## Purpose

V1.3 is a focused trust patch for Apple Pencil ink behavior.

The release thesis: when a musician writes into iChart, the app must either
understand the ink, ask a clear confirmation question, or preserve the ink
exactly and visibly. The user should never wonder whether the app lost,
miscolored, misread, or silently changed what they wrote.

This roadmap is mostly about chord ink and rhythm ink trust. It should build on
the V1.1 visible-ink repair and the V1.2 trust work without expanding into a
large notation-engine release.

## Scope Boundary

V1.3 should stay tight and diagnosable:

- Chord ink trust: handwritten chord capture, recognition, confirmation,
  correction, persistence, rendering, transposition, and export.
- Rhythm ink trust: Free-Write rhythm markings, cues, rehearsal shorthand,
  visibility, editing, persistence, and export.
- Shared ink reliability: Apple Pencil tool state, dark/light appearance,
  platform-version differences, save/reopen, undo/redo, and PDF parity.
- Clear user recovery: when recognition is uncertain, the app asks; when ink is
  decorative, the app preserves it; when a tool changes mode, the app makes the
  mode obvious.

V1.3 should not become a full rhythm-recognition or engraving release. If a
feature changes musical authority, parsing, or layout contracts, it needs its
own explicit acceptance criteria.

## Chord Ink Trust

### Recognition And Confirmation Confidence

Improve trust in handwritten chord capture from first stroke through final
rendered chord.

Current concern: chord ink is high-trust input. If the recognizer is uncertain,
the confirmation loop must feel safer than guessing. If the user corrects the
result, the corrected chord must become the durable authority across save,
reopen, transpose, and export.

#### Requirements

- Preserve raw chord ink long enough to support clear confirmation and recovery.
- Show uncertain recognition results as questions, not confident facts.
- Use the same manual chord parser and alias coverage planned in V1.2 wherever
  a user corrects handwritten chord recognition.
- Keep recognition output, confirmation choice, rendered chord symbol,
  persistence, transposition, and PDF export in sync.
- Never silently replace a corrected chord with a later recognizer guess.
- Make failed or unsupported recognition explicit and recoverable through manual
  entry.
- Ensure chord ink remains visible in all supported appearances and iPadOS
  versions.

#### Non-Goals

- No promise that every handwritten chord style will be recognized.
- No bypass around structured chord storage, transposition, or export.
- No silent correction of ambiguous chords.
- No broad compendium expansion without tests and representative fixtures.

#### Acceptance Criteria

V1.3 can ship this chord-ink trust pass only when:

1. A handwritten chord can be recognized, confirmed, saved, reopened,
   transposed, and exported without changing musical meaning.
2. An uncertain handwritten chord produces a clear confirmation or correction
   step instead of an unverified final chord.
3. A manually corrected chord remains authoritative and is not overwritten by
   later recognition state.
4. Unsupported or ambiguous recognition never creates an invalid chord event.
5. Chord ink visibility is verified across light/dark appearance and relevant
   iPadOS versions.

### Chord Ink Regression Fixtures

Create a repeatable chord-ink regression set.

#### Requirements

- Maintain fixture examples for common chord families, common handwriting
  variation, and known problematic cases.
- Include major seventh, minor seventh, dominant, diminished, half-diminished,
  altered dominant, slash chord, and accidental-root examples.
- Include corrected-result fixtures, not only recognizer-success fixtures.
- Verify fixture results through editor rendering, save/reopen, transposition,
  and PDF export.
- Keep the fixture set small enough to run during release hardening.

## Rhythm Ink Trust

### Free-Write Rhythm Ink Reliability

Improve confidence in handwritten rhythm markings, cues, and rehearsal notes.

Current concern: Free-Write is the user's reliable fallback for rhythm ideas,
personal notation, articulations, and bandleader shorthand. It must feel like
paper: visible immediately, stable after tool changes, editable, saved, and
exported exactly where the user placed it.

#### Requirements

- New rhythm ink should appear immediately under Pencil input with no delayed
  or invisible stroke state.
- Persist rhythm ink position, color, stroke width, and eraser behavior across
  save, reopen, app relaunch, and PDF export.
- Keep rhythm ink visually aligned with the chart after transpose, layout,
  clef, stanza, or page changes.
- Make mode ownership clear: rhythm ink, chord recognition, selection, eraser,
  lasso, and move tools should not leak state into each other.
- Protect against accidental white or invisible rhythm ink from platform
  appearance, PencilKit state, migration, or failed color decoding.
- Preserve undo/redo expectations for rhythm ink separately from structured
  chord events.

#### Non-Goals

- No automatic claim that Free-Write rhythm ink has become structured rhythm
  notation.
- No rhythm-recognition promise without a separate recognition contract.
- No color or brush feature that weakens default black/dark visible ink.
- No layout change that makes existing rhythm ink drift silently.

#### Acceptance Criteria

V1.3 can ship this rhythm-ink trust pass only when:

1. A tester can write rhythm markings, switch tools, return, and continue
   writing without unexpected color, width, or mode changes.
2. Rhythm ink saves, reopens, exports to PDF, and remains visually aligned with
   the same chart location.
3. Existing charts with Free-Write rhythm ink remain visible after migration.
4. Erase, undo, redo, select, move, and delete behavior are predictable and do
   not affect structured chord events unless explicitly intended.
5. Light/dark appearance and supported iPadOS versions cannot produce accidental
   invisible or white rhythm ink.

### Rhythm Ink Versus Structured Rhythm

Keep the product boundary clear.

V1.3 may improve the trustworthiness of rhythm ink, but structured rhythm input
remains separate from handwritten Free-Write ink unless explicitly promoted by a
future spec.

#### Requirements

- UI copy and tool states should distinguish Free-Write rhythm ink from
  structured rhythm notation.
- Export should preserve Free-Write as visual ink unless the user explicitly
  creates structured rhythm data.
- Tests should confirm that Free-Write rhythm ink does not accidentally become
  parsed rhythm events.
- Any future rhythm-recognition work should require an explicit confirmation
  loop before changing musical authority.

## Shared Ink Reliability

### Tool-State Isolation

Prevent PencilKit or app tool state from leaking between ink systems.

#### Requirements

- Chord-recognition ink, Free-Write ink, selection/lasso UI, eraser, and move
  tools should have explicit state boundaries.
- Persistent ink color should be derived from app-owned policy, not incidental
  system or PencilKit tool state.
- Temporary UI ink or selection color should never become saved musical ink.
- Failed decoding, unknown version data, or migration paths should fail toward
  visible dark ink unless the user explicitly selected another visible color.
- Tests should cover platform appearance, stored-document migration, and tool
  switching.

### Export And Reopen Parity

The editor, saved document, reopened document, and exported PDF should agree.

#### Requirements

- Chord ink decisions and rhythm ink strokes should be visually checked in the
  editor and PDF export.
- Save/reopen should not change color, position, scale, or musical meaning.
- Layout changes should keep ink anchored to the intended musical region.
- Regression tests should include editor/PDF parity for both chord and rhythm
  ink.

## Release Gates

V1.3 should not ship until:

1. Chord ink and rhythm ink pass focused regression fixtures.
2. Existing V1.1 visible-ink tests remain green.
3. Existing V1.1.1 manual chord alias and V1.2 Free-Write color decisions are
   not contradicted.
4. Editor/PDF parity is verified for representative chord and rhythm ink.
5. Migration from existing user charts preserves visible dark ink by default.
6. QA includes at least one fresh-install path and one existing-document path.
