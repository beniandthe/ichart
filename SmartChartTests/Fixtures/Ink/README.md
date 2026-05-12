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

When real iPad handwriting fails, export the strokes as a new fixture, add a
failing test, fix the deterministic recognition layer, and keep the fixture.

During app testing, the chord confirmation sheet can copy fixture JSON for the
current chord ink. The importer names the file after the fixture `name` and
adds a captured suffix when that seed already exists.

All `.json` files in this directory are automatically loaded by the recognition,
cluster, and glyph tests, so adding a captured fixture is enough to put it under
the full pure Swift regression harness.

## Live Capture Protocol

Use this exact loop when collecting data:

1. Select the chord tab and write exactly one chord symbol.
2. In the confirmation sheet, set `Intended chord` to the exact target text.
3. Tap `Copy Test Fixture`.
4. Wait for the watcher to print `Imported ...`.
5. Tap `Clear & Next Sample`.
6. Repeat with the next chord.

During a data pass, do not tap `Use Chord` unless you are testing normal chart
entry. The fixture label is the source of truth, so correct the text before
copying even when the app suggestion is wrong.

Recommended first targets:

- `C`, `D`, `E`, `F`, `G`, `A`, `B`
- `Bb`, `F#`, `Db`
- `C-`, `Bb-`, `F#-`
- `C△7`, `C-7`, `Db7(b9)`, `G/B`

To watch a booted simulator pasteboard and import copied samples automatically:

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
