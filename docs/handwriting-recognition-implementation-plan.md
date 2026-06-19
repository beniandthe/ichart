# Handwriting Recognition Implementation Plan

Status: historical architecture context, not active sprint authority
Date: 2026-05-06
Target repo: `beniandthe/ichart`

## Historical Notice

This document preserves the original handwriting-recognition architecture, pass notes, and recovery context. It is not the active sprint plan.

For current execution, start with `docs/ichart-sprint-source-of-truth.md`. For the May 2026 repo, GitHub, and recognition audit evidence, use `docs/repo-github-recognition-audit-2026-05-20.md`.

When this document conflicts with the living sprint source of truth, the living sprint source of truth wins.

Important current override: do not use this historical plan as a mandate to
keep expanding one writer's captured chord samples or to build recognition
around repeated personal test passes. Current recognition work must stay
writer-agnostic by default. Fixtures are regression evidence only unless a
future sprint explicitly designs opt-in user-specific personalization.

## Purpose

iChart should convert Apple Pencil input into clean, editable chord-chart objects without making handwriting recognition the fragile center of the app.

The goal is not full OCR. The goal is a constrained, testable recognition pipeline for common chord-chart tokens: chord roots, accidentals, minor marks, extensions, alterations, slash bass, and a small set of notation marks.

Historically, this plan assumed the GitHub `main` branch was the source of truth. That assumption is stale for the Sprint 2 recovery work; the active recovery baseline is recorded in `docs/ichart-sprint-source-of-truth.md`.

## Current Repo Starting Point

Relevant existing files:

- `iChart/Services/ChordRecognitionCompendium.swift`
- `iChart/Services/ChartParsers.swift`
- `iChart/Models/MusicTheory.swift`
- `iChart/Models/ChordEvent.swift`
- `iChart/Models/Chart.swift`
- `iChartTests/ChordSymbolParserTests.swift`
- `docs/architecture-reset-proposal.md`

The current `ChordRecognitionCompendium` already handles symbolic/OCR-like chord strings such as:

- `F sharp` -> `F#`
- `D flat` -> `Db`
- Unicode accidentals such as `B♭`
- minor aliases such as `Cm`, `Cmin`, `C minor`, and `C-`
- rejection of unsupported major suffix aliases such as `Cmaj`, `CM`, and `C major`

That means the missing layer is not primarily the chord parser. The missing layer is the ink-to-candidate pipeline that turns PencilKit strokes into ranked candidate strings before calling `ChordRecognitionCompendium.match(candidates:)`.

## Core Principle

Recognize small musical glyphs, compose those glyphs into candidate chord strings, then let the existing chord compendium validate the final result.

Do not try to recognize a complete handwritten chord symbol as arbitrary text in one step.

Preferred flow:

```text
PKDrawing
-> raw strokes
-> stroke groups / clusters
-> per-cluster glyph candidates
-> composed chord-string candidates
-> ChordRecognitionCompendium.match(candidates:)
-> ChordSymbol / ChordEvent suggestion
```

Recognition should propose. The structured chart model should decide.

## Pipeline 1 Trust Sidecar

The first OCR integration should be a compendium-gated sidecar, not a replacement for the
glyph/template recognizer.

Preferred live flow:

```text
PKDrawing
-> stroke groups / glyph candidates / chord-string candidates
-> ChordRecognitionCompendium.match(candidates:)
-> primary recognizer decision

only for primary reads that would already require confirmation:
ink crop
-> OCR text candidates
-> ChordRecognitionCompendium.match(candidates:)
-> trust arbiter

trust arbiter
-> auto-render when primary is clear or primary and OCR agree
-> confirmation when OCR supports a ranked runner-up or is the only valid source
```

Raw OCR text should never be rendered or shown as a candidate unless it normalizes through
`ChordRecognitionCompendium`. Invalid OCR strings, partial reads such as a bare root letter,
and OCR strings that do not match a ranked recognizer candidate are diagnostic-only evidence.

## Third-Party References

### Primary candidate: DollarGestureRecognizer

Repository: https://github.com/DanielCardonaRojas/DollarGestureRecognizer

Why it fits:

- Swift/iOS implementation.
- MIT licensed.
- Exposes dollar-family recognizers through UIKit gesture recognizers.
- Includes single-stroke and multi-stroke recognizer approaches (`$1`, `$Q`, `$P`, `$N`).
- Multi-stroke matching is useful for accidentals such as `#`, flat-like marks, natural signs, slashes, and compound glyphs.

Recommended use:

- Treat this as either a vendored dependency under `ThirdParty/` or a porting reference.
- For product stability, prefer copying/porting only the small recognizer core we need into `iChart/Recognition` with license attribution, instead of making the editor depend directly on a large external UI surface.

### Useful reference: DollarP-ObjC

Repository/page: https://fe9lix.github.io/DollarP_ObjC/

Why it matters:

- Clear Objective-C reference for `$P` point-cloud matching.
- Useful if we want to implement a minimal Swift point-cloud recognizer ourselves.

### Music-symbol data: HOMUS

Dataset page: https://grfia.dlsi.ua.es/homus/

Why it matters:

- Handwritten online music-symbol dataset.
- 15,200 samples from 100 musicians.
- Includes accidentals, notes, rests, time signatures, clefs, dots, and barlines.
- Stores strokes as 2D point sequences, which maps well to PencilKit-style input.

Recommended use:

- Do not depend on HOMUS in the app bundle initially.
- Use it later for evaluation, tests, and optional model/template expansion.
- Start with iChart-specific user samples first because chord-chart handwriting differs from formal staff notation.

### CoreML reference: DeTeXt

Repository: https://github.com/venkatasg/DeTeXt

Why it matters:

- iOS app using PencilKit, SwiftUI, Combine, and CoreML for drawn-symbol classification.
- Good architecture reference if template matching hits a ceiling.

Recommended use:

- Phase-two reference only.
- Do not start with CoreML unless template recognition cannot get reliable enough.

## Proposed Module Map

Add:

```text
iChart/Recognition/
  InkPoint.swift
  InkStroke.swift
  InkCluster.swift
  InkStrokeExtractor.swift
  StrokeClusterer.swift
  GestureTemplate.swift
  GestureTemplateRecognizer.swift
  GlyphCandidate.swift
  ChordInkCandidateComposer.swift
  ChordInkRecognizer.swift
  RecognitionVocabulary.swift
  RecognitionDebugFormatter.swift

iChartTests/Recognition/
  InkStrokeExtractorTests.swift
  StrokeClustererTests.swift
  GestureTemplateRecognizerTests.swift
  ChordInkCandidateComposerTests.swift
  ChordInkRecognizerTests.swift

iChartTests/Fixtures/Ink/
  README.md
  C.json
  Bb.json
  FSharp.json
  CMinor.json
  Db7b9.json
```

Optional later:

```text
ThirdParty/DollarGestureRecognizer/
  LICENSE
  Sources/...
```

or:

```text
iChart/Recognition/Dollar/
  DollarPointCloudRecognizer.swift
  DollarRecognizerLicense.md
```

## Data Types

Start with pure Swift structs so the recognition layer can be tested without UIKit/PencilKit.

```swift
struct InkPoint: Codable, Hashable {
    var x: Double
    var y: Double
    var timeOffset: TimeInterval?
}

struct InkStroke: Codable, Hashable {
    var points: [InkPoint]
    var bounds: InkBounds
}

struct InkCluster: Codable, Hashable {
    var strokes: [InkStroke]
    var bounds: InkBounds
    var startTimeOffset: TimeInterval?
    var endTimeOffset: TimeInterval?
}

struct GlyphCandidate: Hashable {
    var text: String
    var confidence: Double
    var source: RecognitionSource
}

struct ChordInkRecognitionResult: Hashable {
    var rawCandidates: [String]
    var glyphCandidates: [[GlyphCandidate]]
    var match: ChordRecognitionMatch?
    var confidence: Double
}
```

Keep these independent from `PKStroke` and `PKDrawing`. UIKit/PencilKit adapters should sit at the edge.

## Layer 1: Parser And Compendium Lockdown

Before adding ink recognition, make the existing symbolic layer harder to regress.

Expand `iChartTests/ChordSymbolParserTests.swift` with tests for:

- every root plus accidental spelling: `C`, `C#`, `Cb`, `D`, `D#`, `Db`, etc.
- enharmonic spellings that should be preserved on zero transposition: `Cb`, `E#`, `Fb`, `B#`
- OCR-like variants: `F sharp`, `D flat`, `B♭`
- minor aliases: `Cm`, `Cmin`, `C minor`, `C-`
- rejected major aliases: `Cmaj`, `CM`, `C major`
- candidate ordering: if candidates are `['8b', 'Bb']`, the compendium should eventually choose `Bb`

Acceptance criteria:

- The existing compendium remains the only authority for accepted chord tokens.
- Recognition code never bypasses `ChordRecognitionCompendium.match(candidates:)` when creating a chord symbol.

## Layer 2: Stroke Extraction

Add a small adapter to convert PencilKit data to recognition-native strokes.

Responsibilities:

- Convert each PencilKit stroke into `InkStroke`.
- Preserve point order.
- Preserve timing if available.
- Normalize coordinates only inside the recognizer, not at extraction time.
- Keep the original `PKDrawing.dataRepresentation()` persisted in the chart model.

Integration point:

- `Chart.pageHandwrittenChordData`
- `Chart.pageHandwrittenNotationData`

Acceptance criteria:

- Unit tests can load JSON fixtures into `InkStroke` without PencilKit.
- UI integration can convert a fresh `PKDrawing` into the same `InkStroke` representation.

## Layer 3: Stroke Grouping

Most recognition regressions will come from grouping, not glyph classification.

Implement `StrokeClusterer` before doing anything clever.

Grouping heuristics:

- group strokes by short time gaps
- group strokes whose bounding boxes overlap or nearly touch
- group small modifiers with nearby roots when they are spatially close
- split left-to-right when there is a clear horizontal gap
- treat slash-bass regions separately after a slash-like stroke

Inputs:

```swift
struct StrokeClustererConfiguration {
    var maxTimeGap: TimeInterval
    var maxHorizontalGapRatio: Double
    var maxVerticalOverlapMissRatio: Double
    var smallModifierSizeRatio: Double
}
```

Important cases:

- `Bb` should group as `B` + flat modifier.
- `F#` should group as `F` + sharp modifier.
- `C-` should group as root + minor mark.
- `Db7(b9)` should split into usable glyph clusters but compose into one chord candidate.
- Slash bass such as `G/B` should preserve the slash as a separator.

Acceptance criteria:

- Fixture tests prove grouping for `Bb`, `F#`, `C-`, and `Db7(b9)`.
- Clusterer output is deterministic.
- Clusterer has no knowledge of `ChordSymbol`; it only returns geometry/time clusters.

## Layer 4: Gesture/Glyph Recognition

Implement `GestureTemplateRecognizer` as a constrained recognizer for a small vocabulary.

Initial glyph vocabulary:

- roots: `A`, `B`, `C`, `D`, `E`, `F`, `G`
- accidentals: `#`, `b`
- optional later accidental: natural
- qualities: `m`, `-`
- digits: `7`, `9`, `1`, `3`
- separators: `/`

Template matching approach:

- resample points to a fixed count
- scale to a normalized bounding box while preserving useful aspect-ratio features
- translate to origin/centroid
- compare to templates with a point-cloud or path-distance metric
- return ranked `GlyphCandidate` values, not just one answer

Important detail:

- Keep aspect ratio, width, height, and stroke count as features. A flat, lowercase `b`, and uppercase `B` can look dangerously similar if normalized too aggressively.

Acceptance criteria:

- For every glyph fixture, the expected glyph appears in the top 3.
- Confidence values are stable enough to sort alternatives, but not treated as absolute truth.
- The recognizer can return ambiguity instead of forcing a bad answer.

## Layer 5: Chord Candidate Composition

Add `ChordInkCandidateComposer` to combine glyph candidates into valid chord-string candidates.

Responsibilities:

- Compose root + accidental + quality + extensions + alterations + slash bass.
- Generate multiple candidate strings from ambiguous glyphs.
- Prefer valid chord grammar over raw glyph confidence when appropriate.
- Defer final validation to `ChordRecognitionCompendium` and `ChordSymbolParser`.

Example:

```text
Glyph candidates:
  [B, 8]
  [b, 6]

Composed candidates:
  Bb
  B6
  8b

Compendium result:
  Bb
```

Ranking rules:

- root letters must start a chord candidate
- accidental directly after root is preferred over accidental later
- slash must introduce a bass pitch candidate
- unsupported major suffixes stay rejected by the existing parser/compendium
- candidate strings that parse successfully outrank non-parsing strings

Acceptance criteria:

- `Bb` beats `8b` when both are plausible.
- `F#` beats `F` when a nearby sharp cluster is present with reasonable confidence.
- `C-` and `Cm` normalize to the same minor symbol.
- `Db7(b9)` can be composed and parsed.

## Layer 6: ChordInkRecognizer Facade

Add `ChordInkRecognizer` as the main API used by the editor.

```swift
protocol ChordInkRecognizing {
    func recognize(strokes: [InkStroke]) -> ChordInkRecognitionResult
}
```

Responsibilities:

- run clustering
- run glyph recognition
- compose chord candidates
- call `ChordRecognitionCompendium.match(candidates:)`
- return best match plus alternatives/debug data

Acceptance criteria:

- Editor code calls one facade.
- Tests can run recognition from JSON fixtures without UI.
- Debug output can explain why a candidate won.

## Layer 7: PencilKit UI Integration

Integrate recognition only after pure Swift tests are useful.

Recommended editor behavior:

- Use `PKCanvasView` for chord-entry overlay.
- Persist raw `PKDrawing.dataRepresentation()` into chart data.
- On stroke completion or short idle timeout, recognize the newest stroke group.
- Show a lightweight candidate popover near the ink.
- Do not immediately mutate the chart model unless confidence is very high and the user has enabled fast entry.

Candidate UI actions:

- accept best candidate
- choose alternate
- edit text manually
- keep as raw ink
- delete/retry

Acceptance criteria:

- A wrong recognition is cheap to correct.
- Raw ink remains available for reinterpretation.
- Committed output is always a structured `ChordEvent` or explicit annotation, not untracked text.

## Layer 8: Committing To The Chart Model

When the user accepts a candidate:

- create or update a `ChordEvent`
- set `rawInput` to the original recognized string or the user-edited text
- preserve the raw PencilKit data separately
- use current measure/beat hit-testing to assign `startPosition`
- use existing measure timing suggestions when available

Do not let recognition own beat placement. Recognition produces musical tokens; layout/editor logic decides where they belong.

Acceptance criteria:

- Accepted chord appears in the chart as structured data.
- Transposition and export use the existing domain model.
- Undo/redo can eventually treat acceptance as a normal editing command.

## Testing Strategy

### Unit tests

Add tests for:

- point normalization
- stroke bounds
- cluster splitting/grouping
- glyph candidate ranking
- chord candidate composition
- final compendium matching

### Fixture tests

Use JSON fixtures under `iChartTests/Fixtures/Ink/`.

Each fixture should include:

- name
- strokes
- expected clusters
- expected top glyphs
- expected final display text

Example fixture metadata:

```json
{
  "name": "Bb",
  "expectedDisplayText": "Bb",
  "strokes": []
}
```

### Regression tests

Whenever recognition fails on real iPad input:

1. export the strokes as a fixture
2. add a failing test
3. fix grouping/composition/template logic
4. keep the fixture forever

This is the main guardrail against recurring regressions.

### Historical live fixture capture loop

This loop is historical. Do not use it as an ongoing data collection or
training habit. Current fixture capture is only for transferable regressions,
and the active button labels now refer to regression fixtures:

1. write exactly one chord symbol in chord mode
2. correct `Intended chord` to the exact target spelling
3. tap `Copy Regression Fixture`
4. let `scripts/watch_simulator_chord_fixtures.py` import the copied fixture
5. tap `Clear Ink`
6. stop unless another distinct transferable regression needs protection

The corrected `Intended chord` label is the source of truth for the captured
fixture. Do not tap `Use Chord` during a fixture capture unless the goal is to
test normal chart entry instead of regression fixture export.

### Current captured fixture coverage

The first real handwriting fixture set is now committed and covered by
`InkFixtureCoverageTests`:

### Consolidated chord-recognition v1 boundary

Recognition v1 is now scoped to a constrained chord-chart vocabulary, validated
through the parser/compendium instead of arbitrary OCR. The fixture corpus has
been deduplicated so exact name-only duplicates do not inflate confidence:

- fixture corpus: 645 distinct ink fixture payloads across 209 canonical
  display texts
- duplicate policy: exact duplicate payloads are rejected by coverage tests and
  skipped by the fixture importer
- source of truth: the compendium and parser remain the only authority for
  accepted chord tokens; ink recognition only proposes ranked candidates

Supported in v1:

- roots and accidentals: natural roots plus `#` and `b`, including spellings
  such as `Cb`, `E#`, and `B#` without enharmonic rewriting
- major triads: root letter only, with unsupported written major aliases still
  rejected for now
- minor forms: written `-`, `m`, `min`, and `minor`, rendered through the
  standardized jazz minor notation where appropriate
- dominant extensions: `7`, `9`, `11`, and `13`
- sixth chords: major `6` and minor `m6`
- major-triangle extensions: `△7`, `△9`, and `△13`
- minor extensions: `-7`, `-9`, `-11`, and `-13`
- minor-major seventh: `-△7`
- suspended forms: `sus`, `sus4`, and `7sus`
- diminished forms: `°`, `°7`, and `ø7`, with parser aliases such as `dim`,
  `dim7`, `m7b5`, and `-7b5`
- augmented triads: `+`
- altered dominants: `7(b9)`, `7(#9)`, `7(b5)`, `7(#5)`, `7(b13)`,
  `7(#11)`, and shorthand `7alt`
- slash chords: root plus slash bass such as `F/A`, `D/F#`, and `F#/A#`

Deferred beyond v1:

- full handwriting-to-text OCR
- natural signs and broader accidental systems
- major-eleventh symbols outside the suspended-chord path
- compound/multiple simultaneous altered extensions beyond the current
  one-alteration fixture families
- add chords, `6/9`, polychords, cluster notation, and advanced voicing syntax
- CoreML/HOMUS expansion unless the constrained template pipeline hits a clear
  ceiling

The next product step is not full end-to-end app validation yet. It is a
focused chord-writing loop on a disposable test chart: create/open a clean test
chart, write chord symbols above measures, show concise alternatives, accept or
correct them, commit structured `ChordEvent` values to the chart, preserve raw
ink for the confirmation cycle, and keep fixture copy tooling behind a
debug/data-collection path.

After each normal chart-entry pass, run
`scripts/audit_chord_entry_diagnostics.py --strict` before tuning recognition.
The audit compares rendered `ChordEvent` IDs in the disposable test chart with
`chord-entry-diagnostics.jsonl` so stale simulator logs or missing auto-render
events do not get mistaken for recognizer evidence. When several disposable
charts share the same title, the audit should prefer the selected matching
chart, then the newest matching chart; pass `--chart-id` only when replaying a
specific historical chart.
Use `scripts/audit_chord_entry_diagnostics.py --strict --details --scores 3`
when deciding what to tune next. The detail view is the canonical quick read
for a pass: it shows each accepted/rendered chord, whether it auto-rendered or
needed confirmation, the winning confidence, the close-race gap, and the top
candidate scores without treating confirmed close races as failures.
If a pass rendered before live diagnostics were complete, use
`scripts/audit_chord_entry_diagnostics.py --reconcile-missing --strict` once to
backfill explicitly labeled `reconciledRenderedChord` rows from rendered chart
state. These rows prove coverage but must not be treated as recognizer
confidence wins.

Current checkpoint expectation for the chord-writing loop is a mixed but
intentional result: obvious roots and clean root/accidental forms should
auto-render, while compact suffix collisions such as minor sevenths, altered
dominants, and suspended forms may still request confirmation if the candidate
gap is genuinely tight. The next tuning target should be visible in the
diagnostic detail output before recognition heuristics are changed.
Chord-entry latency should be tuned separately from recognition confidence:
simple settled ink can use a shorter idle delay, complex/wide multi-stroke
symbols should keep the longer delay, and debug timing should show the idle,
recognition, and total milliseconds before further responsiveness changes.

### Symbol-ledger checkpoint

The symbol-ledger sprint is a diagnostics checkpoint, not a new authority layer.
It records stable left-to-right symbol evidence, running-prefix candidates, final
candidate support, and primary-candidate agreement so live passes can be audited
without adding another opaque scoring stack.

Keep these boundaries in place:

- ledger evidence may explain a recognition result, but it should not auto-render
  a different answer on its own
- raster/cache experiments remain deferred unless the diagnostic ledger proves a
  specific, repeated gap that the current template pipeline cannot explain
- pass-visible fixes should stay narrow and replayable; avoid broad scoring
  rewrites from a single frustrating live pass
- if the loop starts requiring repeated manual passes without clear diagnostic
  signal, stop tuning and return to product/editor work

Current checkpoint evidence:

- full Swift suite is green with the symbol-ledger diagnostics in place
- replay can validate archived chord-writing passes from `library-state.json`
- `Db7(b9)` stays a flat-ninth case instead of inventing an unwritten `b13`
- the known remaining hard cases are confirmation/backlog items, not blockers
  for continuing app design

- natural roots: at least 4 captured samples each for `A`, `B`, `C`, `D`, `E`,
  `F`, and `G`
- common accidentals: at least 3 captured samples each for `A#`, `Ab`, `Bb`,
  `C#`, `D#`, `Db`, `Eb`, `F#`, `G#`, and `Gb`
- success-criteria forms: fixtures remain present for `C`, `Bb`, `F#`, `C-`,
  `C-7`, `Db7(b9)`, and `G/B`
- alias behavior: written `Cm7` remains supported as input, but exported
  fixtures and rendered chord events canonicalize it to `C-7`
- minor-form pass: captured samples now cover both written dash minor
  (`C-`, `C-7`) and written lowercase-m minor (`Cm`, `Cm7`) while rendering
  both paths through the standard dash-minor chord model
- flat-minor stress pass: captured samples now cover `Bb-`, `Bbm`, `Bb-7`,
  and `Bbm7`; the exporter preserves the written `m` glyphs for fixture
  truth while the chart model still renders canonical `Bb-` / `Bb-7`
- G-flat minor stress pass: captured samples now cover `Gb-`, `Gbm`,
  `Gb-7`, and `Gbm7`; compact trailing sevens now split from handwritten `m`
  suffixes so `Gbm7` does not collapse into `Gb7`
- C-flat minor stress pass: captured samples now cover `Cb-`, `Cbm`,
  `Cb-7`, and `Cbm7`; the existing flat pipeline preserves the written
  C-flat spelling without enharmonic conversion
- A-sharp minor stress pass: captured samples now cover `A#-`, `A#m`,
  `A#-7`, and `A#m7`; embedded root-plus-sharp clusters are now split back
  into the largest root prefix plus complete sharp suffix, so an `A` crossbar
  does not make `A#m` collapse into `F-`
- E-sharp minor stress pass: captured samples now cover `E#-`, `E#m`,
  `E#-7`, and `E#m7`; the existing sharp pipeline preserves the written
  E-sharp spelling without enharmonic conversion
- B-sharp minor stress pass: captured samples now cover `B#-`, `B#m`,
  `B#-7`, and `B#m7`; compact two-bowl B roots now use their whole-symbol
  horizontal direction changes so they do not lose close races to D-sharp
  candidates
- sharp-minor stress pass: captured samples now cover `F#-`, `F#m`, `F#-7`,
  and `F#m7`; slash detection was tightened so slanted `F` bars do not split
  from the root as false slash separators
- C-sharp minor stress pass: captured samples now cover `C#-`, `C#m`,
  `C#-7`, and `C#m7`; compact sharp construction now merges thin upright
  strokes without letting the sharp absorb the following minor dash
- G-sharp minor stress pass: captured samples now cover `G#-`, `G#m`,
  `G#-7`, and `G#m7`; completed sharp glyphs now stay separate from following
  quality marks, including overlapping dash-plus-7 handwriting
- G-sharp sanity pass: preserved a valid `G#m7` sample where the sharp's
  cross-strokes slightly overlap the `G` root edge; sharp construction strokes
  may now cross into the root edge without being absorbed into the root cluster
- D-sharp minor stress pass: captured samples now cover `D#-`, `D#m`,
  `D#-7`, and `D#m7`; tiny hand-drawn minor dashes now stay separate from a
  following `7` instead of collapsing the suffix into a false minor-like glyph
- D-flat minor stress pass: captured samples now cover `Db-`, `Dbm`, `Db-7`,
  and `Dbm7`; compact two-stroke D roots now receive a root-level D heuristic
  so they do not lose close races to B-flat candidates
- E-flat minor stress pass: captured samples now cover `Eb-`, `Ebm`, `Eb-7`,
  and `Ebm7`; multi-stroke E roots now merge their staff-like bars before
  glyph recognition, flat marks are read more by whole-symbol shape than stroke
  direction, and the confirmation UI filters raw glyph noise out of suggestions
- A-flat minor stress pass: captured samples now cover `Ab-`, `Abm`, `Ab-7`,
  and `Abm7`; root-construction merging now requires true same-glyph horizontal
  overlap so an A crossbar does not swallow a flat mark, while flat modifier
  overlap at the root edge remains supported
- dominant-seventh stress pass: captured samples now cover `C7`, `Bb7`,
  `F#7`, `Db7`, `G#7`, and `B#7`; the first extension-only pass tightened
  compact seven-vs-minor matching, compact flat ranking, one-stroke-root sharp
  splitting, and compact B roots before moving into larger extensions
- sixth-chord stress pass: captured samples now cover `C6`, `Bb6`, `F#6`,
  `Db6`, `G#6`, and `B#6`; wide looped `6` glyphs now resolve against flat,
  minor, and `9` lookalikes, leaned D/B stems merge back into their root body,
  and rough E/F root ordering uses stroke order instead of only geometry
- dominant-ninth stress pass: captured samples now cover `C9`, `Bb9`,
  `F#9`, `Db9`, `G#9`, and `B#9`; open-loop handwritten 9s are accepted as a
  whole-symbol shape, compact D roots are protected from B-like collisions, and
  sharp fragments can be rejoined after a right-edge stem is split away from a
  root
- dominant-eleventh stress pass: captured samples now cover `C11`, `Bb11`,
  `F#11`, `Db11`, `G#11`, and `B#11`; adjacent handwritten `1` glyphs stay
  sequential instead of merging into a double-stem cluster, and narrow `1`
  strokes receive a high-confidence glyph heuristic even with a small top hook
- dominant-thirteenth stress pass: captured samples now cover `C13`, `Bb13`,
  `F#13`, `Db13`, `G#13`, and `B#13`; compact suffix `1` strokes and curled
  whole-symbol `3` strokes now resolve before weak flat/seven alternates, while
  accidental bonus scoring only applies when the accidental glyph itself is
  strong enough to earn it
- major-seventh triangle stress pass: captured samples now cover `C△7`,
  `Bb△7`, `F#△7`, `Db△7`, `G#△7`, and `B#△7`; triangle quality glyphs now use
  a dedicated lower-body-to-upper-peak return cue, and the parser rejects
  reordered noise such as `B6△7` so the written `Bb△7` candidate can win
- major-ninth triangle stress pass: captured samples now cover `C△9`, `Bb△9`,
  `F#△9`, `Db△9`, `G#△9`, and `B#△9`; open handwritten `9` glyphs now require
  a true upper-loop return and tail-side closure so they do not steal already
  locked `6`, flat, or compact C shapes
- major-thirteenth triangle stress pass: captured samples now cover `C△13`,
  `Bb△13`, `F#△13`, `Db△13`, `G#△13`, and `B#△13`; adjacent suffix `1` and
  `3` glyphs stay split even when handwritten tightly, while major-eleventh
  support remains intentionally deferred for the later sus/sus4 pass
- minor ninth/thirteenth stress pass: captured samples now cover `C-9`,
  `Bb-9`, `F#-9`, `Db-9`, `G#-9`, `B#-9`, `C-13`, `Bb-13`, `F#-13`,
  `Db-13`, `G#-13`, and `B#-13`; a relaxed top-shelf cue is available only
  for suffix `3` glyphs so tight minor-thirteenth handwriting does not lose to
  `6`/flat/C lookalikes
- minor eleventh stress pass: captured samples now cover `C-11`, `Bb-11`,
  `F#-11`, `Db-11`, `G#-11`, and `B#-11`; parser, compendium fallback,
  candidate composer, and fixture exporter preserve written `m`/`min`/`-`
  aliases while rendering standardized jazz `-11` symbols, and ultra-compact
  two-point minor dashes are accepted as intentional dash-minor glyphs
- minor-major-seventh prep: symbolic parsing, compendium matching, candidate
  composition, and fixture export now support written dash-triangle forms such
  as `C-△7` while preserving the canonical rendered chord as `C-△7`
- diminished family prep: parser, compendium fallback, candidate composer,
  glyph templates, and fixture exporter now support diminished triads (`C°`),
  diminished sevenths (`C°7`), and half-diminished sevenths (`Cø7`) while
  accepting aliases such as `Cdim`, `Cdim7`, `Cø`, `Cm7b5`, and `C-7b5`
- dominant flat-ninth stress pass: captured samples now cover `C7(b9)`,
  `Bb7(b9)`, `F#7(b9)`, `Db7(b9)`, `G#7(b9)`, and `B#7(b9)`; the suffix
  repair is deliberately constrained to a `7` followed by split `b9`
  fragments, so it does not globally merge adjacent major, diminished, sixth,
  or extension glyphs
- dominant sharp-ninth prep: symbolic parsing, candidate composition, glyph
  templates, and fixture export now accept literal handwritten parentheses for
  `7(#9)` while keeping the semantic glyph target as `7#9`; parenthesis wrapper
  strokes are stripped before chord matching so tight handwritten `(#9)` groups
  do not depend on punctuation spacing
- pure altered prep: symbolic parsing, compendium matching, candidate
  composition, fixture export, and glyph templates now support written
  root-plus-`alt` forms such as `Calt`, `C alt`, and `C7alt`, while
  standardizing all accepted shorthand to dominant altered display text such as
  `C7alt`; the lowercase `a/l/t` templates are geometry-gated so they do not
  steal already stable `9`, `1`, `+`, or altered-dominant glyphs

## Milestones

### Milestone 1: Stabilize symbolic recognition

- Expand compendium/parser tests.
- Confirm existing chord spellings and aliases are stable.
- No UI changes.

### Milestone 2: Add pure Swift ink model

- Add `InkPoint`, `InkStroke`, `InkCluster`, and bounds utilities.
- Add JSON fixture loading.
- Add basic tests.

### Milestone 3: Add stroke clustering

- Implement deterministic grouping heuristics.
- Prove grouping with synthetic and captured fixtures.

### Milestone 4: Add glyph templates

- Add minimal glyph recognizer.
- Add templates for roots, accidentals, minor marks, digits, and slash.
- Return ranked candidates.

### Milestone 5: Compose chord candidates

- Convert glyph sequences into chord-string candidates.
- Validate through `ChordRecognitionCompendium.match(candidates:)`.
- Add tests for ambiguous cases.

### Milestone 6: Add PencilKit capture

- Add a chord-entry overlay.
- Persist raw drawing data.
- Recognize new stroke groups after idle timeout.

### Milestone 7: Add candidate UI

- Show best match and alternates.
- Allow accept, alternate selection, manual edit, keep ink, and retry.

### Milestone 8: Commit accepted candidates

- Create/update `ChordEvent` from accepted candidates.
- Preserve raw input and raw ink.
- Use existing transposition/export paths.

### Milestone 9: Expand from real samples

- Record real writing samples from iPad.
- Add fixtures for every failure.
- Add HOMUS-derived accidental tests if useful.

### Milestone 10: Evaluate CoreML only if needed

- If templates cannot handle real-world variation, prototype image/glyph classification.
- Use DeTeXt-style PencilKit -> image -> CoreML flow as a reference.
- Keep the compendium as the final validator even if CoreML is added.

## Non-Goals For The First Pass

Do not implement these initially:

- full handwriting-to-text OCR
- full staff-based music notation recognition
- melody or pitched-note entry
- automatic correction that mutates chart data without user visibility
- cloud-dependent recognition
- OpenAI-dependent live editing
- CoreML training pipeline before simple templates are evaluated

## Risk Areas

### Root vs accidental confusion

`B`, `b`, flat marks, and handwritten `6` can collide. Preserve aspect ratio, relative size, and context.

### Over-normalization

If every glyph is forced into the same square without extra features, musically different marks can become identical. Keep width, height, stroke count, and relative placement.

### Bad grouping

A good glyph recognizer will still fail if the wrong strokes are grouped. Invest in cluster fixtures early.

### Premature auto-commit

Auto-committing wrong symbols makes the app feel untrustworthy. Start with candidate confirmation and add fast entry later.

### Mixing recognition with layout

Recognition should identify tokens. Beat placement, snapping, and page layout should remain deterministic editor responsibilities.

## First Implementation Checklist

- [x] Add this plan to the repo.
- [x] Expand `ChordSymbolParserTests` around compendium behavior.
- [x] Add `iChart/Recognition` folder.
- [x] Add pure Swift ink data types.
- [x] Add fixture loader for recognition tests.
- [x] Add `StrokeClusterer` with deterministic heuristics.
- [x] Add a minimal point-cloud glyph recognizer.
- [x] Add initial glyph templates.
- [x] Add `ChordInkCandidateComposer`.
- [x] Add `ChordInkRecognizer` facade.
- [x] Wire final matching through `ChordRecognitionCompendium.match(candidates:)`.
- [x] Add PencilKit capture overlay.
- [x] Add candidate UI.
- [x] Commit accepted candidates into `ChordEvent`.
- [x] Add fixture export path for real iPad handwriting samples.
- [x] Add fixture import path for real iPad handwriting samples.
- [x] Add real iPad handwriting samples as fixtures.
- [x] Keep fixture capture as a dev-only path and make normal chord confirmation render to the chart first.

## Success Criteria

The first successful implementation should let a user write simple chord symbols such as:

- `C`
- `Bb`
- `F#`
- `C-`
- `Cm7`
- `Db7(b9)`
- `G/B`

and receive a structured candidate that can be accepted, corrected, transposed, saved, and exported through the existing iChart model.

The app does not need perfect recognition to feel good. It needs stable recognition, clear alternatives, and fast correction.
