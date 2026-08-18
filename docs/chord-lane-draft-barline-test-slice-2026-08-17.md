# Chord Lane Draft Barline Test Slice

Created: 2026-08-17 PDT / 2026-08-18 UTC

## Implemented In This Slice

- Chord mode now schedules a debounced, non-mutating draft preview read after chord-lane ink stabilizes.
- Draft chord previews render as small anchored labels in the blue chord writing lane.
- Tall straight vertical lane strokes are detected as draft barlines and drawn as dashed non-destructive boundaries.
- Draft barline strokes are filtered out of chord recognition input so they do not become chord candidates.
- `Render Chords` commits renderable draft chords and currently-supported draft open-measure boundaries in one explicit action.
- `Discard` clears draft preview state plus the raw chord-lane ink.
- Draft preview telemetry is aggregate-only and allowlisted.
- Focused simulator tests cover draft grouping/edit preservation, barline gesture detection, explicit render transaction, telemetry allowlist, and legacy chord commit/session paths.

## Current-System Fit Notes

- Current chord-lane ink is stored as one page-level chord drawing (`pageHandwrittenChordData`). The draft model is therefore in-memory for this slice, with source ink still persisted as raw chord ink until render/discard.
- The existing chart model supports committing an open measure with `commitOpenMeasure(barlineAfter:)`, but it does not yet support arbitrary measure splitting from several draft barlines inside one authored open lane span. This slice commits draft barlines only where they map cleanly onto the current open-measure workflow.
- The legacy tap-to-confirm chord path still exists for comparison and fallback. That means the new explicit `Render Chords` workflow is testable, but it has not fully replaced the old confirmation/auto-render path yet.
- Preview labels are currently display-only. Candidate picking/manual correction still uses the existing confirmation sheets rather than direct preview tapping.
- Undo restoration of draft ink state is not implemented in this slice. The committed chord events retain source ink data as before, and discard clears the draft ink.
- This does not prove the chord-trust problem is solved. It creates a testable non-mutating preview/explicit render path that still needs Simulator handwriting QA.
