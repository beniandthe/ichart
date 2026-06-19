# Ink Fixtures

Ink fixtures are stable JSON snapshots for recognition tests. They intentionally
store pure `InkStroke` data instead of PencilKit data so grouping, glyph
classification, and chord composition can be tested without UIKit or simulator
state.

Each fixture should include:

- `name`: short fixture name.
- `expectedDisplayText`: final chord display text expected after full recognition.
- `strokes`: ordered `InkStroke` values.
- `expectedClusterCount`: optional grouping expectation.
- `expectedTopGlyphs`: optional first-choice glyphs once glyph recognition exists.

Ink fixtures are regression evidence, not training data. They should prove that
known recognition paths stay stable, but they must not become a continuous
sample collection loop for one writer's hand.

iChart recognition must stay writer-agnostic by default. Do not design,
tune, or expand the recognizer around one person's repeated chord-writing
passes. Any future user-specific personalization must be an explicit product
feature with a separate opt-in data boundary, not a hidden fixture habit.

When real iPad handwriting exposes a transferable product regression, export the
strokes as a new fixture, add or update a failing test, fix the deterministic
recognition layer, and keep the fixture. Do not add captured samples simply to
increase corpus size.

During app testing, the chord confirmation sheet can copy fixture JSON for the
current chord ink. The importer names the file after the fixture `name` and
adds a captured suffix when that seed already exists.

All `.json` files in this directory remain available to the full pure Swift
archive harness, but default recognition, cluster, and glyph tests now use a
compact regression suite selected by `InkFixtureLoader.defaultRegressionFixtureNames`.

## Test Policy

Default SwiftPM and CI tests use a compact, transferable regression suite. The
full captured handwriting archive is opt-in and should be run deliberately when
auditing recognition drift, preparing recognition changes, or reviewing fixture
coverage:

```bash
ICHART_FULL_INK_FIXTURES=1 swift test --scratch-path /tmp/iChartSwiftBuild-full-ink
```

The full archive still loads through the cached test loader, so archive audits
do not re-read every fixture file repeatedly inside one process. Captured
handwriting count is not a product authority; compendium/parser validation and
structured `ChordEvent` output remain the runtime authority.

## Regression Capture Protocol

Use this loop only when a real iPad writing pass exposes a transferable product
regression or a general chord/glyph shape that should be protected for all
users:

1. Select the chord tab and write exactly one chord symbol.
2. In the confirmation sheet, set `Intended chord` to the exact target text.
3. Tap `Copy Regression Fixture`.
4. Wait for the watcher to print `Imported ...`.
5. Tap `Clear Ink`.
6. Stop unless there is another distinct, transferable regression to protect.

During validation, do not turn the test chart into an ongoing personal corpus.
The fixture label is the source of truth, so correct the text before copying
even when the app suggestion is wrong.

Useful regression seed targets, when they expose a real issue:

- `C`, `D`, `E`, `F`, `G`, `A`, `B`
- `Bb`, `F#`, `Db`
- `C-`, `Bb-`, `F#-`
- `C△7`, `C-7`, `Db7(b9)`, `G/B`

To watch a booted simulator pasteboard and import copied regression fixtures
automatically:

```bash
scripts/watch_simulator_chord_fixtures.py --clear-on-start
```

To import the JSON copied from the macOS clipboard:

```bash
scripts/import_chord_fixture.py --clipboard
```

You can also pipe JSON through stdin or pass a file path:

```bash
scripts/import_chord_fixture.py /tmp/CapturedChord.json
```
