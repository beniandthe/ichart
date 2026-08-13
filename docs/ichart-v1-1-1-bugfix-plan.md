# iChart V1.1.1 Bugfix Patch Plan

Status: active patch candidate
Created: 2026-08-11

## Purpose

V1.1.1 is a narrow bug-squash release pulled out of the former V1.2 parking
lot.

The goal is to fix visible broken behavior in existing shipped tools without
adding new product surface area. This patch should be easier to verify, easier
to explain, and safer to ship quickly than a full V1.2 feature release.

## Release Boundary

V1.1.1 may include:

- fixes for incorrect behavior in existing chart-writing tools
- layout/rendering fixes where existing notation is clipped, misplaced, or
  colliding
- bounded trust fixes for existing manual chord confirmation/correction flows
- copy changes only when required to make an existing flow truthful
- regression tests and visual/PDF parity checks

V1.1.1 should not include:

- new user-facing tools
- new feature workflows
- broad redesigns
- new analytics/telemetry systems
- new reminder email workflows
- unbounded chord compendium expansion beyond alias coverage needed for
  existing manual correction/entry trust

## Split From Former V1.2

| Former V1.2 Item | Decision | Reason |
| --- | --- | --- |
| Manual chord alias coverage | V1.1.1 | High-priority trust issue in existing manual correction flows. |
| Beat and subdivision placement correctness | V1.1.1 | Existing chord placement control appears ineffective on later beats. |
| Time Signature selected-measure targeting and chord-safe layout | V1.1.1 | Existing Time tool changes the wrong measure and causes collisions. |
| Subsequent-stanza rhythm-chart left barline spacing | V1.1.1 | Existing rhythm-chart layout creates a fake mini-measure after setup. |
| First/second ending and coda clipping | V1.1.1 | Existing repeat/roadmap symbols are visibly clipped. |
| Pending verification reminder | V1.2 | New recovery workflow, not a bug squash. |
| Tactile button tapping | V1.2 | UX improvement across the app, not a defect fix. |
| Beat/subdivision placement visual cue | V1.2 | New assistive feedback after placement is correct. |
| Free-Write ink color choice | V1.2 | New user-facing feature. |
| Select-input rhythm notation | V1.2 | New structured rhythm-input feature. |

## Chord Entry Trust

### Manual Chord Alias Coverage

Broaden typed chord support in every existing manual chord-entry path.

Current concern: when handwriting recognition misses or misreads a chord, the
manual confirmation/editing flow must feel more reliable than the recognizer.
If the user reaches for manual correction and common spellings are rejected, the
fallback feels broken even if recognition is behaving reasonably.

This belongs in V1.1.1 because manual confirmation/correction is already part
of the shipped recovery path. The patch should make that existing path accept
common musician spellings; it should not become an unbounded chord-theory or
handwriting-recognition expansion.

If a user writes `C∆7` and needs to confirm or correct it manually, they should
be able to type the chord in the notation language they naturally use, such as
`C∆7`, `C△7`, `CMaj7`, `Cmaj7`, `CM7`, or `C major 7`. The same trust rule
applies to minor seventh chords and other common families: `C-7`, `Cmin7`,
`Cm7`, and `C minor 7` should resolve to the intended chord instead of forcing
the user to learn iChart's preferred spelling.

#### Requirements

- Every manual chord flow should use the same alias-capable parser:
  confirmation, correction, rendered-chord editing, and keyboard/manual entry.
- Alias matching should be case-insensitive where music meaning is unchanged:
  `CMaj7`, `Cmaj7`, and `CM7` should all be accepted for major seventh.
- Common quality aliases should be accepted for every supported root and
  accidental spelling.
- Minor aliases should include at least `m`, `min`, `minor`, and `-` forms,
  including seventh and extended variants where supported.
- Major seventh aliases should include triangle forms, `maj`, `Maj`, `M`, and
  written `major` forms where supported.
- Spacing should be forgiving for common typed forms: `Cmaj7`, `C maj7`,
  `C maj 7`, and equivalent supported spellings should not become separate
  failure modes.
- Accepted aliases should normalize to a structured chord symbol that saves,
  reopens, transposes, renders, and exports correctly.
- Unsupported chord qualities should fail with clear manual-entry feedback
  rather than silently rendering the wrong chord.
- The internal chord coverage artifact should include alias examples for each
  supported chord family, not only one canonical spelling.

#### V1.1.1 Non-Goals

- No claim that every handwritten visual variant will be auto-recognized.
- No free-text chord rendering that bypasses parser, compendium, persistence,
  transposition, or export validation.
- No accepting ambiguous text by guessing a different chord quality.
- No weakening of the confirmation loop for uncertain handwriting.
- No broad compendium expansion unrelated to existing manual-entry trust.

#### Acceptance Criteria

1. Major seventh examples such as `C∆7`, `C△7`, `CMaj7`, `Cmaj7`, `CM7`, and
   `C major 7` resolve to the intended structured chord in every manual-entry
   flow.
2. Minor seventh examples such as `C-7`, `Cmin7`, `Cm7`, and `C minor 7`
   resolve to the intended structured chord in every manual-entry flow.
3. Alias coverage is tested across all root letters and accidentals, including
   sharp and flat roots.
4. Accepted aliases render, save, reopen, transpose, and export as valid
   structured chord symbols.
5. Unsupported or ambiguous manual input shows a clear correction message and
   does not create an invalid chord event.
6. The chord coverage printout includes representative aliases for each
   supported chord family so QA can see what users are allowed to type.

## Chord Placement

### Beat And Subdivision Placement Correctness

Make chord placement visibly respond to every beat and subdivision choice inside
the measure, starting with Simple Chord Sheet.

Current concern: in Simple sheets, beat 1 feels like it lands in the right
place, but moving a chord through later beat/subdivision positions does not
visibly move the chord enough. The last few beat positions can appear stuck, and
the chord remains too far from the right barline. That makes the control feel
fake: the model may say the chord is on a later beat, but the page does not
convince the user that the chord actually moved there.

This is an editor/layout bug, not a recognition bug. Recognition may help create
a chord, but the editor and layout layers own where that structured `ChordEvent`
appears in the measure.

#### Requirements

- Audit the mapping from `BeatPosition`, subdivision, `targetFraction`, and
  rendered chord frame to the visible x-position inside a measure.
- Use the real barline-to-barline measure body as the placement authority for
  Simple Chord Sheet chord positions.
- Preserve the current good beat-1 placement while making later beats and
  subdivisions visibly distinct.
- Ensure each supported beat/subdivision step produces a meaningful visual
  movement unless two positions truly resolve to the same musical location.
- Make late-measure positions move progressively closer to the right barline
  while preserving readable padding and avoiding chord clipping.
- Keep the visible chord body, tap target, drag/edit affordance, saved
  `ChordEvent`, and exported PDF in agreement.
- Verify the same placement contract after save/reopen, transpose, duplicate,
  and PDF export.

#### V1.1.1 Non-Goals

- No broad rhythm-recognition rewrite.
- No letting handwriting recognition decide beat placement authority.
- No fix that only changes the saved beat value while leaving the visible chord
  position almost unchanged.
- No new placement-guide feature beyond what is required to verify the bug fix.
- No late-beat placement that clips into the right barline or spills into the
  next measure.

#### Acceptance Criteria

1. In a Simple Chord Sheet measure, moving a chord through each supported beat
   and subdivision produces visibly distinct left-to-right positions.
2. Late-measure positions move close enough to the right barline to read as
   late beats while retaining professional padding.
3. The final supported beat/subdivision position does not appear stuck with the
   previous few positions.
4. Editor rendering, hit testing, saved `ChordEvent` data, and PDF export agree
   on the chord's placement.
5. Regression coverage protects beat 1, mid-measure, and late-measure positions
   across the supported Simple Chord Sheet subdivision grid.

## Time Signature Tool

### Selected-Measure Targeting And Chord-Safe Layout

Make time-signature changes apply to the selected measure from its left barline,
and make local time changes reserve enough left-side space that chords never
collide with the time signature.

Current concern: when the user taps a measure and changes the time signature,
the app appears to change the measure after the one selected. The musical and
visual expectation is different: the selected measure is the measure whose time
signature changes, starting at that measure's left barline.

There is a second layout concern: when a local time change appears inside a
measure, it collides with chords placed in the first few beat/subdivision
positions. The collision can happen whether the chord already existed before
the time change or is placed afterward. That means the time-change symbol and
the chord-placement grid are not sharing the same measure-body contract.

#### Requirements

- Tapping a measure in the Time tool and choosing a meter must change the
  selected measure, not the following measure.
- The visible time signature should appear at the selected measure's left
  barline, compactly inside the left side of that measure.
- Existing UI copy must stop saying or implying that the new time signature
  starts after the selected measure or on the next measure.
- Scope actions must be implemented around the selected measure: selected
  measure plus added measures, selected measure to next time change, and
  selected measure to end of piece.
- If the model continues to store time changes as boundary records, the Time
  tool must map the selected measure to the correct boundary deliberately and
  test that mapping.
- A local time signature must reserve a compact, symbol-aware left-side lane
  before the chord-placement body begins.
- Chords on beat 1 and early subdivisions must be pushed or constrained into
  the remaining chord body so they do not overlap the time signature.
- Adding a chord after a time change must use the same collision-safe chord body
  as relayouting a chord that existed before the time change.
- Time-signature glyph sizing should be compact enough for repeated local
  changes but legible on stage.
- Editor rendering, hit testing, saved chart data, save/reopen, duplicate,
  transpose, and PDF export must agree.

#### V1.1.1 Non-Goals

- No fix that only changes button copy while the next measure still receives
  the meter change.
- No fix that changes the stored meter but leaves the visible time signature in
  the wrong measure.
- No visual-only fix that keeps chord hit testing or PDF export colliding with
  the time signature.
- No oversized time signature that consumes the first beat or makes the measure
  feel cramped.
- No broad rewrite of meter, rhythm, or chord recognition systems unless the
  selected-measure contract requires a narrow model adapter.

#### Acceptance Criteria

1. Selecting measure N and applying a time signature makes measure N the first
   visible and musical measure in that meter.
2. The following measure no longer receives the change accidentally.
3. The visible time signature sits at the selected measure's left barline in a
   compact lane.
4. Chords on beat 1 and early subdivisions do not collide with the local time
   signature, whether they were placed before or after the time change.
5. The chord-placement grid uses the time-signature-reserved body when a local
   time change exists.
6. Time-change behavior is verified for first, middle, last, and system-start
   measures where applicable.
7. Editor rendering, saved chart data, reopened chart data, hit testing, and
   PDF export agree.
8. Tests cover both the selected-measure targeting contract and local
   time-signature/chord collision avoidance.

## Rhythm Chart Layout

### Subsequent-Stanza Left Barline Spacing

Tighten the left barline placement at the start of rhythm-chart stanzas after
the first stanza.

Current concern: after the first stanza, the first left barline sits too far to
the right of the clef/setup area. Visually, this can read like a small false
measure before the first real measure of the stanza.

This is a continuation of the rhythm first-measure layout contract: the
clef/key/time setup can occupy a left setup area, but the visible leading
barline and the beat/chord body must read as one coherent first measure.

#### Requirements

- Move the leading barline for each non-first rhythm-chart stanza closer to the
  clef/setup area.
- Preserve enough spacing for clef, key signature, and time signature so the
  barline does not collide with setup notation.
- Keep editor canvas and PDF/export geometry aligned.
- Preserve beat targeting, chord placement, and first-measure body width.
- Do not create a different beat grid for first stanzas versus later stanzas.
- Keep the existing first-stanza layout correct while fixing subsequent
  stanzas.
- Add regression coverage for first stanza and subsequent-stanza geometry.

#### Acceptance Criteria

1. Subsequent rhythm-chart stanzas no longer show a fake mini-measure between
   the clef/setup area and the first real measure.
2. The leading barline sits close enough to the clef/setup area to read as the
   start of the stanza's first real measure.
3. Clef, key signature, and time signature remain legible and do not collide
   with the leading barline.
4. Editor rendering and PDF export match for first and subsequent stanzas.
5. Existing first-measure beat/chord targeting tests remain green.

## Repeat And Roadmap Layout

### First And Second Ending And Coda Symbol Clipping

Fix first- and second-ending brackets/text and coda-related roadmap symbols
being visibly cut off by what looks like an invisible clipping line.

Current concern: first and second endings in repeat structures appear clipped.
The coda symbols are showing the same kind of clipping. This may look
font-specific at first, but the more likely product risk is that the ending or
roadmap marker frame, text/glyph drawing rect, renderer clip, system top
reserve, or PDF/editor drawing boundary is too tight. A font can expose the
defect, but the root cause may be a shared geometry or clipping contract.

#### Investigation Areas

- Ending layout frame height and vertical placement above the measure body.
- Text rect padding for ending labels such as `1.`, `2.`, `1st`, or custom
  ending text.
- Roadmap marker frame height, label frame, and movement frame for coda-related
  symbols and labels.
- Standalone coda glyphs, `To Coda`, and `D.S. al Coda` labels that include the
  coda glyph.
- Font ascender/descender metrics across the app's supported chart fonts.
- Any canvas, paper, measure, system, or PDF clip applied before ending
  brackets/text or coda/roadmap markers are drawn.
- Whether the bracket line, hook lines, text, coda glyph, roadmap text, or all
  roadmap elements are clipped.
- Whether the issue reproduces in editor only, PDF export only, or both.
- Whether the issue changes between Simple Chord Sheet and Rhythm Section
  Sheet.

#### Requirements

- Treat endings and coda/roadmap symbols as shared notation objects with enough
  vertical and horizontal breathing room for all supported chart fonts.
- Ensure ending brackets, hooks, labels, coda glyphs, and coda-related labels
  render fully inside both editor and PDF export.
- Preserve ending attachment to the selected start/end measures.
- Support both first and second endings, including spans across multiple
  measures and spans that cross a system boundary.
- Preserve coda/roadmap marker attachment, movement, resizing, and hit testing.
- Verify that ending text and coda/roadmap symbols do not collide with chords,
  chord lanes, staff lines, clefs, roadmap markers, or section labels.
- Add visual/layout regression coverage that would fail if ending or coda drawn
  content is clipped by its own frame or by a parent drawing boundary.

#### V1.1.1 Non-Goals

- No font-only fix unless the layout and clipping boundaries are proven safe.
- No hiding the issue by moving endings so far upward that they collide with
  prior systems or page margins.
- No editor-only correction that leaves PDF export clipped.
- No PDF-only correction that leaves the live chart clipped.
- No repeat-structure model change unless the clipping investigation proves the
  model is storing the wrong span.
- No coda marker model change unless the clipping investigation proves marker
  attachment, movement, or scale is being stored incorrectly.

#### Acceptance Criteria

1. First- and second-ending brackets, hooks, and labels render without visible
   clipping in the editor.
2. Standalone coda symbols and coda-related labels render without visible
   clipping in the editor.
3. The same endings and coda/roadmap symbols export to PDF without clipping.
4. The fix is verified across supported chart fonts that previously made the
   problem visible.
5. Simple Chord Sheet and Rhythm Section Sheet ending/roadmap layouts both pass.
6. Single-measure, multi-measure, and system-crossing endings retain correct
   attachment and visual span.
7. Coda markers retain correct attachment, movement, resize behavior, hit
   testing, and visual span.
8. Regression tests protect the ending frame, coda marker frame, text/glyph
   rects, and editor/PDF parity.

## Release Gates

V1.1.1 should not ship until:

1. The five patch areas above are either fixed and verified or explicitly
   deferred out of V1.1.1.
2. Focused parser/layout/model tests pass for manual chord aliases, chord
   placement, Time tool behavior, rhythm stanza geometry, and repeat/roadmap
   clipping.
3. Editor and PDF export are checked for every changed layout path.
4. Existing V1.1 visible-ink and account-flow tests remain green.
5. No new feature UI is introduced beyond truthful copy and necessary bug-fix
   affordances.
