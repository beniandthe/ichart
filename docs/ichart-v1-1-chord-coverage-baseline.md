# iChart V1.1 Chord Coverage Printout

Status: internal V1.1 development printout
Created: 2026-08-03
Updated: 2026-08-03
Audience: development and QA only; not user-facing

This document is the current internal printout of chord types covered by the
V1.1 additional-chord pass. It is grounded in:

- `iChart/Services/ChordRecognitionCompendium.swift`
- `iChart/Services/ChartParsers.swift`
- `iChartTests/ChordSymbolParserTests.swift`

The current chord system has two coverage layers:

- Explicit compendium coverage: finite entries exposed through
  `ChordRecognitionCompendium.supportedMatches`.
- Parser fallback coverage: additional typed/candidate strings that can parse
  into structured `ChordSymbol` values even when they are not in the finite
  compendium printout.

## Generated V1.1 Family Printout

This section mirrors `ChordRecognitionCompendium.supportedChordTypePrintout`.

| Family | Examples |
| --- | --- |
| major triads | C, F#, Bb |
| minor triads | C-, Cmin, Cm |
| major seventh and extended major | C△7, Cmaj7, Cmajor9 |
| dominant sixth/seventh/ninth/eleventh/thirteenth | C6, C7, C9, C11, C13 |
| six-nine | C6/9, C-6/9 |
| add chords | Cadd2, Cadd9, Cadd11 |
| altered dominants | C7(b9), C7(#9), C7(#11), C7(b13), C7alt |
| suspended chords | Csus, Csus2, Csus4, C7sus, C9sus |
| diminished and half-diminished | C°, C°7, Cø7, Cm7b5 |
| minor sixth and minor-major | Cm6, C-△7, C-△9 |
| slash bass | C/E, Db7(b9)/F, C6/9/E |
| chord repeat | •/•, %, ./. |

## Root Spellings

The compendium covers these root spellings for every explicit chord family:

| Natural | Sharp | Flat |
| --- | --- | --- |
| C | C# | Cb |
| D | D# | Db |
| E | E# | Eb |
| F | F# | Fb |
| G | G# | Gb |
| A | A# | Ab |
| B | B# | Bb |

The parser also accepts slash-bass pitches using the same root spelling shape:
natural, sharp, or flat A through G.

## Explicit Compendium Families

These families are enumerated for every root spelling above unless noted.

| Family | Display Example | Common Accepted Aliases |
| --- | --- | --- |
| Chord repeat | •/• | `•/•`, `%`, `./.` |
| Major triad | C | root only |
| Minor triad | C- | `C-`, `Cm`, `Cmin`, `C minor` |
| Minor sixth | Cm6 | `C-6`, `Cm6`, `Cmin6`, `C minor 6` |
| Minor-major seventh | C-△7 | `C-△7`, `Cm△7`, `Cmin△7`, triangle variants |
| Suspended | Csus | `Csus`, `C suspended` |
| Suspended fourth | Csus4 | `Csus4`, `C sus 4`, `C suspended 4` |
| Dominant suspended | C7sus | `C7sus`, `C 7 sus`, `C7 suspended` |
| Augmented | C+ | `C+`, `Caug`, `C augmented` |
| Altered dominant | C7alt | `Calt`, `C7alt`, `C7 altered` |
| Diminished | C° | `C°`, `Cdim`, `C diminished` |
| Diminished seventh | C°7 | `C°7`, `Cdim7`, `C diminished7` |
| Half-diminished seventh | Cø7 | `Cø`, `Cø7`, `Chalf-dim7`, `Cm7b5`, `C-7b5` |

Current explicit compendium count: 253 displayed matches.

- 21 root spellings times 12 rooted families.
- 1 chord-repeat family.

## Parser Fallback Families

The parser supports additional structured chord symbols beyond the explicit
compendium entries.

| Family | Display Examples | Notes |
| --- | --- | --- |
| Dominant and unqualified extensions | C6, C7, C9, C11, C13 | Accepted extensions: `6`, `7`, `9`, `11`, `13`. |
| Six-nine chords | C6/9, C-6/9 | The slash is treated as part of the extension only for `6/9`; later slashes remain bass notes. |
| Added-tone chords | Cadd2, Cadd4, Cadd9, Cadd11 | Added-tone forms are major-rooted in V1.1. |
| Dominant alterations | C7(b5), C7(#5), C7(b9), C7(#9), C7(#11), C7(b13) | Alterations can be written directly or in parentheses. |
| Multiple dominant alterations | C7(b9)(#5) | Duplicate alterations are rejected. |
| Minor extensions | Cm6, C-7, C-9, C-11, C-13 | `m6` displays as `Cm6`; other minor extensions display with `-`. |
| Minor seventh flat five | Cø7 | `Cm7b5`, `Cmin7b5`, and `C-7b5` normalize to half-diminished. |
| Major triangle and major aliases | C△, C△7, C△9, C△13, Cmaj7, Cmajor9 | `△`, `Δ`, `∆`, `maj`, and `major` display as `△` when followed by a supported extension. Bare `maj`/`major` remains unsupported. |
| Minor-major forms | C-△7, C-△9, C-△11, C-△13 | The minor-major quality supports the common seventh and extended forms. |
| Suspended forms | Csus, Csus2, Csus4, C7sus, C9sus, C13sus | `Csus7` and `C7sus4` normalize to `C7sus`; extended suspended chords display as `Csus9` and `Csus13`. |
| Altered suspended dominants | C7sus(b9), C9sus(#11) | Suspended alterations require a supported extension. |
| Altered dominant | C7alt | `Calt`, `Caltered`, `C7alt`, and `C7 altered` normalize to `C7alt`. |
| Augmented | C+ | Augmented alterations are rejected. |
| Diminished forms | C°, C°7 | Diminished extensions beyond seventh are rejected. |
| Half-diminished seventh | Cø7 | Half-diminished extensions beyond seventh are rejected. |
| Slash bass | G/B, Db7(b9)/D, C6/9/E | Any supported rooted chord can include one final slash bass with a valid pitch only. |

## Accepted Normalizations

- Unicode sharp and flat signs normalize to `#` and `b`.
- Full-width sharp normalizes to `#`.
- `flat` and `sharp` word forms are accepted through compendium aliases.
- `º` normalizes to `°`.
- `Ø` and `⌀` normalize to `ø`.
- `Δ` and `∆` normalize to `△`.
- Dash/minus variants normalize for compendium matching.

## Explicitly Unsupported Today

These are current boundaries, not necessarily permanent product decisions:

- Bare major suffix aliases: `CM`, `Cmaj`, `Cmajor`, `C major`.
- Uppercase `M` major aliases such as `CM7`; V1.1 keeps this unsupported to
  avoid OCR confusion with minor `m`.
- Diminished ninth and half-diminished ninth forms such as `C°9` and `Cø9`.
- Half-diminished with extra flat-five text after normalization, such as
  `Cø7b5`.
- Numeric noise or unsupported extensions such as `C2`, `C3`, `C4`, `C5`,
  `C8`, and `C10`.
- Alterations without an extension, such as `C(b9)`.
- Duplicate alterations such as `C7(b9)(b9)`.
- Slash bass with non-pitch suffix text, such as `D/F5`.

## Deferred Candidates

These remain outside the current V1.1 coverage boundary.

- Minor added-tone chords such as `Cmadd9`.
- Minor seventh alterations beyond the half-diminished normalization.
- Altered dominant shorthand variants beyond `7alt` if they can be displayed
  predictably.
- Omitted-tone symbols only if there is a clear display convention and real user
  need.
- Polychord or upper-structure notation only if scoped separately; these are not
  safe to treat as simple slash-bass chords.
