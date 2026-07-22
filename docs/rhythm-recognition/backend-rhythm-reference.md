# Backend Rhythm Recognition Reference

Date: 2026-06-22
Branch: `codex/rhythm-recognition-overhaul`

## Purpose

This is the parked backend rhythm-recognition reference surface. It is not user-facing Help content and is not part of the shipping V1 rhythm-entry flow. It remains only as archived context in case handwritten recognition is revisited after literal rhythm input exists.

## Local Visual Sources

- [simple-rest-and-rhythm.jpg](references/simple-rest-and-rhythm.jpg): single note/rest visual chart.
- [rhythm-combinations.pdf](references/rhythm-combinations.pdf): 5-page rhythm combination visual reference.
- [visual-ink-reference-bridge.md](visual-ink-reference-bridge.md): connector between raw ink tokens, handwritten variants, local visual references, and meter/grouping rules.
- [recognizer-decision-contract.md](recognizer-decision-contract.md): required recognizer output surface for commit, keep-writing, and review decisions.
- [golden-fixture-matrix.md](golden-fixture-matrix.md): must-pass and must-not-autocommit examples for the recognizer overhaul.

The single-symbol image includes values beyond current V1 engine support: dotted whole, dotted eighth, and sixteenth note/rest forms. Store them as recognition-context references, but do not claim current render/recognition support until the model and renderer support those values.

## External Rule Sources

- LilyPond Notation Reference, Beams: automatic beaming is controlled by `baseMoment`, `beatStructure`, and `beamExceptions`; common time signatures can have exceptions beyond simple beat endings. https://lilypond.org/doc/v2.23/Documentation/notation/beams
- LilyPond Notation Reference, Displaying rhythms: time-signature settings define `baseMomentFraction`, `beatStructure`, and optional `beamExceptions`. https://lilypond.org/doc/v2.23/Documentation/notation/displaying-rhythms
- LilyPond Notation Reference, Writing rhythms: durations use reciprocal note values and dots extend duration. https://lilypond.org/doc/v2.23/Documentation/notation/writing-rhythms
- MuseScore Studio Handbook, Beams: beams connect consecutive eighth-or-shorter notes for rhythmic grouping; default beaming comes from the time signature, and per-note overrides can split/join beams. https://handbook.musescore.org/notation/rhythm-meter-and-measures/beams
- Steinberg Dorico Help, Changing beam grouping: Dorico beams according to the prevailing meter, can split/unbeam selected notes, and can encode consistent groupings such as `[2+3+2]/8`. https://www.steinberg.help/r/dorico/doricofirststeps/6.1/en/dorico_first_steps/topics/first_steps_layout_formatting/first_steps_beam_grouping_changing_t.html
- Steinberg Dorico Help, Rests within beams: conventions differ for beams interacting with rests, including splitting beams, extending beams, and stemlets. https://www.steinberg.help/r/dorico-pro/6.1/en/dorico/topics/notation_reference/notation_reference_beaming/notation_reference_beaming_rests_c.html

## Canonical Single-Value Durations

Durations below are expressed in quarter-note beats for ordinary quarter-note meters.

| Name | Note context | Rest context | Beats | Current V1 support |
| --- | --- | --- | ---: | --- |
| Whole | Whole note | Whole rest | 4 | Yes |
| Dotted whole | Dotted whole note | Dotted whole rest | 6 | Reference only |
| Half | Half note | Half rest | 2 | Yes |
| Dotted half | Dotted half note | Dotted half rest | 3 | Note yes, rest reference only |
| Quarter | Quarter note | Quarter rest | 1 | Yes |
| Dotted quarter | Dotted quarter note | Dotted quarter rest | 1.5 | Note yes, rest bounded-dot backed |
| Eighth | Eighth note | Eighth rest | 0.5 | Yes |
| Dotted eighth | Dotted eighth note | Dotted eighth rest | 0.75 | Reference only |
| Sixteenth | Sixteenth note | Sixteenth rest | 0.25 | Reference only |

## Recognition Context Rules

1. Symbol classification is not enough. A beam, flag, rest mark, or dot must be validated against meter position and surrounding rhythm.
2. Beaming is contextual evidence. Adjacent eighth notes may be beamed, but only if the beam does not hide a protected beat or grouping boundary.
3. The measure grid owns final validity. Candidate values must fit the meter exactly before any rendered rhythm map can commit.
4. Rests break beams by default in V2. Beams over rests are a deliberate engraving convention and should require explicit support, not accidental recognition.
5. Dots change duration and grouping. A dotted note can push the following short value to a protected beat boundary, so the recognizer must calculate onset/offset positions before trusting beam evidence.
6. Compound meters group by dotted beats. In 6/8, six eighth notes should naturally form two groups of three, not one group of six and not three groups of two unless the style explicitly asks for it.
7. Irregular meters need explicit grouping profiles. A 7/8 grouping like 2+3+2 is a meter context, not a visual guess from the noteheads alone.
8. Dotted rests require a main rest glyph plus a bounded trailing dot. After glyph segmentation, a compact lower-lane dot may modify the previous glyph only when it sits to the right within the allowed x/y attachment window; do not promote plain rests into dotted rests with a generic nearest-dot rule.

## Critical Example

In 4/4:

`dotted quarter - eighth - eighth - dotted quarter`

Offsets in quarter-note beats:

| Value | Start | End |
| --- | ---: | ---: |
| Dotted quarter | 1.0 | 2.5 |
| Eighth | 2.5 | 3.0 |
| Eighth | 3.0 | 3.5 |
| Dotted quarter | 3.5 | 5.0 |

The boundary between the two eighth notes is beat 3, the center of the 4/4 measure. The recognizer must not treat those two eighths as one beamed group. The correct context is two separate eighth values on opposite sides of the protected midpoint.

This is now covered by `RhythmRecognitionContextRules`: the boundary before the second eighth in `[.dottedQuarter, .eighth, .eighth, .dottedQuarter]` is marked as a protected meter boundary in 4/4.

## V2 Implication

If handwritten recognition is revisited, it should use a layered pipeline:

1. Neutral ink morphology: compact dot, vertical stroke, horizontal stroke, diagonal stroke, curve hook, zig-zag body, and loop evidence.
2. Visual symbol candidates: notehead/rest/dot/stem/flag/beam interpretations built from morphology.
3. Duration candidates: value proposals per symbol.
4. Meter positions: start/end offsets for each proposal.
5. Grouping validation: beaming/rest/dot context checked against meter grouping rules.
6. Commit gate: only high-confidence exact fits commit; conflicting visual/meter context stays in review.
