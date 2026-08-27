# Chord Recognition Music-Theory Context Evidence

Date: 2026-08-25
Branch: `codex/chord-recognition-accuracy`
Status: research and architecture guidance only

## Scope

This document extracts music-theory context that should guide handwritten chord recognition without changing the current product boundary:

- no OCR, Vision text recognition, or Scribble lane recognition
- no `PKStrokeRecognizer` or iOS 27 dependency
- no chord-lane UI, rendered-edit, terminal barline, ink persistence, sync, measure-resize, or layout-guide changes
- no implicit rendered chart mutation before explicit `Render Chords` / `Auto Render`

The target is not broader syntax. The target is stronger trust: use theory to support or negate glyph roles before the recognizer turns ambiguous strokes into a confident wrong chord.

## Local Source Of Truth

Observed repo evidence:

- `docs/chord-recognition-trust-protocol-2026-08-25.md` defines the active branch authority. It requires root-led grouping, draft-only recognition output, no OCR, no `PKStrokeRecognizer`, no lane UI churn, and physical iPad validation before final accuracy claims.
- `docs/chord-recognition-accuracy-course-correction-2026-08-21.md` defines the recognition contract: a base `A-G` root starts a chord, suffix glyphs stay with the active root until the next base root, a solo vertical stroke is a barline, and no-read/confirmation is better than a confident wrong read.
- `docs/chord-lane-auto-render-course-correction-2026-08-21.md` defines the product flow: the user writes a base letter, suffixes/extensions, then the next base letter; previous group boundaries should not be retroactively reinterpreted.
- `docs/ichart-v1-1-chord-coverage-baseline.md` is the current in-repo chord-family printout. It is grounded in `ChordRecognitionCompendium`, `ChordSymbolParser`, and parser tests.
- `iChart/Models/MusicTheory.swift` supports pitch spelling as root `A-G` with optional `#` or `b`.
- `iChart/Models/ChordEvent.swift` stores structured `ChordSymbol` values as root, accidental, quality, extensions, alterations, optional slash bass, or the special chord-repeat kind.
- `iChart/Services/ChartParsers.swift` parses a leading pitch first, then descriptor, then optional final slash bass. It accepts the current supported grammar and rejects unsupported/ambiguous forms such as bare major suffixes, duplicate alterations, unsupported degrees, and invalid slash-bass text.
- `iChart/Services/ChordRecognitionCompendium.swift` exposes the supported families: major, minor, minor sixth, minor-major, major triangle, dominant extensions, add, sus, 7sus, dim, half-dim, aug, altered dominant, slash bass, and chord repeat.
- `iChart/Recognition/ChordInkSequentialGrouper.swift` already implements the first recognition-stage theory rule: probable `A-G` root starts open new groups, slash-bass roots stay inside the active group after `/`, and gap grouping is fallback only.
- `iChart/Recognition/ChordInkSemanticGlyphContextualizer.swift`, `ChordInkSemanticCandidateComposer.swift`, and `ChordInkCandidateScoringPolicy.swift` contain multiple family-specific theory patches for `sus`, altered dominants, half-diminished, sharp-eleven, slash bass, sixth, flat/root collisions, diminished, and chord repeat.

Architecture implication: the next theory pass should consolidate those repeated family facts into shared role evidence. It should not add another isolated boost for each failing fixture.

## External Source Summary

The external sources agree on a structural model that matches iChart's current parser more than generic OCR:

- Open Music Theory describes chord symbols as containing root, triad quality, extensions, and any non-root bass note. It also states the useful defaults: bare triads imply major, unqualified sevenths imply minor seventh over a major triad, and higher extensions are major/perfect unless altered.
- MusicXML represents popular chord symbols as `harmony` data with root, kind, optional bass, and degree additions/alterations. Root and bass are both split into pitch step plus optional alter value. This is strong evidence that slash bass and altered degrees are separate roles, not generic trailing characters.
- MuseScore's chord-symbol syntax also starts from alphabetical root names `a-g`, then accepts quality abbreviations, extensions/alterations, `sus`, `alt`, slash chords, commas, and parentheses. This supports using parser-like role context before scoring.
- Puget Sound's lead-sheet-symbol reference reinforces that major is the default root-only triad; minor is root plus `m`; diminished and augmented signs occur after the root.
- music21's `ChordSymbol` model treats lead-sheet symbols as root/kind/bass objects, with diverse accepted syntax but not unlimited expressions.

Sources:

- [Open Music Theory, Chord Symbols](https://viva.pressbooks.pub/openmusictheory/chapter/chord-symbols/)
- [MusicXML 4.0, Chord Symbols and Diagrams](https://www.w3.org/2021/06/musicxml40/tutorial/chord-symbols-and-diagrams/)
- [MusicXML 4.0, harmony element reference](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/harmony/)
- [MuseScore Studio Handbook, Chord symbols](https://musescore.org/en/handbook/4/chord-symbols)
- [Music Theory for the 21st-Century Classroom, Lead-Sheet Symbols](https://musictheory.pugetsound.edu/mt21c/LeadSheetSymbols.html)
- [music21 harmony module, ChordSymbol](https://music21.org/music21docs/moduleReference/moduleHarmony.html)

## Evidence Matrix

### Root Bases

Supports:

- first glyph is a body-sized `A`, `B`, `C`, `D`, `E`, `F`, or `G`
- glyph appears at group start or immediately after a previous group has been closed
- glyph has root-body geometry rather than suffix-sized geometry
- parser can produce a rooted `ChordSymbol`
- compendium/parser support the resulting display text

Negates:

- candidate is not `A-G`
- candidate is a suffix/modifier glyph with stronger evidence than the root
- glyph is small, high, punctuation-like, or part of an extension/alteration tail
- glyph occurs immediately after a slash separator and therefore is bass role, not a new chord root
- candidate only becomes valid by inventing unsupported syntax

Recognizer use:

- Root-base evidence should be the only strong reason to open a new sequential group.
- A root-like candidate inside a suffix position should confirm unless slash-bass context explains it.

### Root Accidentals

Supports:

- `#` or `b` immediately follows an `A-G` root
- accidental sits near the root and before any quality/extension descriptor
- parser normalizes root plus accidental into a supported pitch spelling
- following descriptor makes musical sense, such as `Db-`, `F#7`, or `Bb-7`

Negates:

- accidental occurs after `7`, `9`, `11`, or `13`, where it is more likely an altered degree
- accidental is inside parentheses after a dominant extension
- accidental appears without a root or without a later supported descriptor
- `b` competes with strong `6`, degree-dot, or diminished/half-diminished circle evidence outside root-adjacent position

Recognizer use:

- The same flat/sharp shape has different roles by position. Root accidental and alteration accidental should be scored differently.
- The `Db` flat-loop fix should remain position-aware; it must not broadly demote `6`, `°`, `ø`, `△`, or `•`.

### Quality Prefix/Descriptor

The word "prefix" is potentially misleading for iChart recognition. In lead-sheet chord symbols, the root comes first. Most quality evidence is a descriptor after the root, not a prefix before the root.

Supports:

- minor: `-`, `m`, `min`, or `minor` after root/accidental
- major quality: `△`, `maj`, `major`, or uppercase `M` only when paired with a supported extension
- diminished: `°`, `º`, or `dim` after root/accidental
- half-diminished: `ø`, `Ø`, `⌀`, or normalized `m7b5` / `-7b5`
- augmented: `+` or `aug` after root/accidental
- suspended: `sus`, `sus2`, `sus4`, `7sus`, `9sus`, `13sus`
- altered dominant: `alt`, `altered`, or `7alt`

Negates:

- a quality marker before any root
- bare major suffix text such as `CM`, `Cmaj`, or `Cmajor`, which iChart intentionally rejects today
- incompatible repeated qualities, such as dim plus unrelated major-triangle evidence
- dim or half-dim with unsupported higher extensions
- augmented with alterations, which the current parser rejects

Recognizer use:

- Quality roles should support candidates only after a root role is already present.
- Composer-generated quality candidates are useful but should remain confirmation-routed when explicit glyph coverage is incomplete.

### Extensions

Supports:

- supported numeric degrees `6`, `7`, `9`, `11`, `13` after root/quality
- dominant defaults when an unqualified `7`, `9`, `11`, or `13` follows a major/default root
- lower-extension implication for unqualified `9`, `11`, and `13`, consistent with Open Music Theory
- `6/9` as a special extension sequence where the slash is not a slash-bass separator

Negates:

- numeric glyph as the first/root glyph
- unsupported degrees such as `2`, `3`, `4`, `5`, `8`, or `10`, except when accepted under `add` or `sus`
- extension without root support
- `7`, `9`, or `11` being used to start a new chord group

Recognizer use:

- Numbers should generally be suffix evidence, not group-opening evidence.
- `6` needs extra care because it can collide with flat-loop shapes and degree dots.

### Alterations

Supports:

- dominant extension context before an alteration, usually `7`
- accidental plus supported altered degree: `b5`, `#5`, `b9`, `#9`, `#11`, `b13`
- optional parentheses around altered degrees
- the accidental is after the extension context, not immediately after root

Negates:

- alteration without a supported extension, such as `C(b9)`
- duplicate alterations
- accidental/number tail that lacks an explicit or strongly inferred dominant context
- generated altered candidate that outruns weak raw glyph evidence

Recognizer use:

- Altered dominants are high-risk for confident wrong reads. They should confirm unless root, dominant, accidental, and degree-tail roles are all supported.
- Key/progression assumptions should not override stroke evidence for altered dominants.

### Suspensions

Supports:

- `sus` after root/accidental
- `7sus` and `9sus` where an extension precedes the suspension descriptor
- `sus4` and `sus2` as accepted suspended forms
- suffix glyphs are compact and sequence-like, not root-sized letters

Negates:

- isolated `s`, `u`, or `s` without root evidence
- slash-like `s` evidence when the group also has strong slash-bass separator evidence
- strong minor/dominant/dim/major-triangle conflicts unless the `7sus` context explains the dominant `7`

Recognizer use:

- Suspended recognition should be sequence-aware and confirm on close races with slash bass.
- Prior `Absus` work supports this: slash lookalikes can steal suspended chords if role context is not explicit.

### Slash Bass

Supports:

- slash follows a complete or nearly complete rooted chord
- glyph after slash is an `A-G` bass pitch with optional `#` or `b`
- parser accepts a final slash bass on a supported rooted chord
- root after slash stays inside the same group

Negates:

- slash appears before a rooted chord
- slash is part of `6/9`, which is an extension, not bass
- text after slash is not a pitch
- slash-like glyph is actually part of `sus` or chord-repeat layout

Recognizer use:

- Slash should suppress new root grouping for the next `A-G` glyph.
- Slash-bass candidates should be penalized when suspended context is stronger.

### Chord Repeat

Supports:

- compact dot-slash-dot or supported `%` / `./.` alias
- layout matches repeat mark rather than slash-bass or rhythm slash
- special `ChordSymbol.Kind.chordRepeat`, not rooted grammar

Negates:

- missing dot/slash/dot layout
- dots are really diminished/degree marks attached to a rooted symbol
- slash is clearly a slash-bass separator after a rooted chord

Recognizer use:

- Chord repeat is a special complete symbol and should not require root evidence.
- It should not teach the system that punctuation-like marks are valid rooted chord starts.

## Context Priors That Are Useful

These priors are safe because they describe chord-symbol grammar and layout roles:

- Root-start prior: new group starts require `A-G` root-body evidence.
- Role-position prior: the same glyph can mean different things by position, especially `b`, `#`, `/`, and dots.
- Descriptor-order prior: root/accidental comes before quality, quality before extension/alteration, slash bass last.
- Supported-grammar prior: compendium/parser support is required before any trusted read.
- Closed-group prior: once a later root starts a new group, the previous group boundary stays fixed.
- Shape-scale prior: roots are usually body-sized; suffixes and alterations are usually compact and right-side.
- Ambiguity prior: close supported interpretations route to confirm/no-read, not trusted render.

## Context Priors That Are Dangerous

These priors should not be used as trust authority:

- Key-signature or diatonic-progression bias. Jazz/pop charts intentionally use chromatic roots, secondary dominants, substitutions, slash basses, and altered chords. Key context can be a weak diagnostic note later, not a trust override.
- Common-chord popularity as a strong override. `Db7sus`, `B#`, `E#`, and `Fb` are valid in the current supported root spelling model even if uncommon. Uncommon spelling can require confirmation when close, but should not be auto-corrected to a more common spelling.
- Previous-chord smoothing. A repeated root or nearby diatonic progression may be common, but using it strongly can cause exactly the wrong-read behavior this branch is trying to prevent.
- User-specific fixture frequency. The fixture policy says captured handwriting is regression evidence, not training data.
- Generic language/OCR confidence. Chord symbols are short, spatial, punctuation-heavy, and music-specific; OCR was already removed from the authority path.

## Proposed Architecture Use

Add a shared recognition-stage theory context, but only after tests describe its contract.

1. Introduce a pure `ChordInkTheoryRoleContext` helper.
   - Inputs: ordered glyph candidate columns, cluster bounds, optional parser/compendium callback.
   - Outputs: role evidence per cluster, such as `rootBase`, `rootAccidental`, `quality`, `extension`, `alterationAccidental`, `alterationDegree`, `slashSeparator`, `slashBassRoot`, `repeatDot`, and `unknown`.
   - It should not mutate UI state or rendered chart content.

2. Use role evidence in grouping first.
   - Open groups only on strong `rootBase` roles.
   - Keep `rootAccidental`, descriptor, alteration, and slash-bass roles with the active group.
   - Keep the current gap fallback for weak/no-root cases.

3. Use role evidence in candidate composition second.
   - Replace family-specific duplicated checks with shared role predicates where feasible.
   - Let semantic composers propose candidates only when their roles are present in the expected order.
   - Keep generated candidates below trust unless explicit glyph coverage is adequate.

4. Use role evidence in scoring/trust third.
   - Promote candidates that explain every cluster with a supported role.
   - Demote candidates with unexplained root-like, accidental-like, or suffix-like pressure.
   - Confirm close races when the losing candidate has a plausible supported role sequence.

5. Keep parser/compendium as final syntax authority.
   - Theory context should guide role confidence, not expand supported syntax silently.
   - Any new grammar support needs a separate parser/coverage decision.

## Tests To Add Before Implementation

Pure theory-role tests:

- `Db-`: `D` root, `b` root accidental, `-` minor descriptor.
- `D-7 E-7`: second `E` opens a new group; `7` never opens a group.
- `Cmaj7 Dmin7 Emin9`: `m/a/j` and `m/i/n` are descriptors after roots, not independent chords.
- `Db7sus`: flat is root accidental, `7` is extension, `sus` is descriptor.
- `C7(b9)`: `b` is alteration accidental only after dominant context.
- `G/B`: slash suppresses group split at bass `B`.
- `C6/9`: slash is extension separator, not slash bass.
- `•/•`: repeat mark is complete special symbol with no root.

Negative/confirm tests:

- suffix-only `7`, `9`, `sus`, `b9`, or `#11` does not become a trusted rooted chord.
- root-like `B` after `/` stays bass, not new group.
- `C(b9)` remains unsupported.
- duplicate alteration remains unsupported.
- bare major `Cmaj` remains unsupported under current parser policy.
- uncommon spelling close races, such as `B#` versus `B`, confirm rather than silently normalize.

Fixture-family audit targets:

- root body evidence: `D`, `E`, `F`
- flats/sharps: `Db-`, `DFlatMinorCaptured01`, `DFlat7susCaptured03`, `F#7`, `Bb-7`
- dominant alterations: `C7(b9)`, `C7(#11)`, `C7alt`
- suspended: `Csus`, `C7sus`, `Db7sus`
- slash bass: `G/B`, `C/E`, `F#/A#`
- chord repeat: `ChordRepeatCaptured01`

## Decision

Music-theory context is worth adding, but only as a shared role-evidence layer. It should support trustworthy grouping and candidate ranking; it should not become a hidden auto-correction engine.

The strongest next step is:

1. write pure role-context tests around the cases above;
2. implement shared role labeling without changing parser coverage or UI behavior;
3. route current semantic composer/scoring checks through role predicates gradually;
4. rerun the trust acceptance fixture set and full archive;
5. validate on physical iPad before any final accuracy claim.
