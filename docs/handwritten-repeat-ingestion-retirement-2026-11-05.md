# Handwritten measure-repeat ingestion retired — November 5, 2026

## Corrected scope

The user clarified: “i didnt say to get rid of chord repeat symbols... just
measure repeats”. The retirement applies to handwritten bar-and-dot measure/range
repeat signs (`||:`, `:||`, `:||:`). It does not apply to the chord-repeat symbol
(`%` / dot-slash-dot), which remains part of **Write & Render**.

Earlier wording and the sealed `936aa2ab` candidate removed both paths. That
blanket scope is superseded by this clarification. Its source and test receipts
remain historical evidence; they do not validate the corrected chord-repeat
candidate. See the [scope-correction handoff](qa/chord-repeat-scope-correction-2026-11-05.md).

## Supported workflows

Write chords, chord-repeat symbols and ending brackets in **Write & Render**.
The chord-repeat symbol follows the chord recognition/review workflow in
Automatic and Manual Render with Preview. Keep separate symbols apart and use
the offered review path when a read is uncertain.

Use **Tools > Repeats** and select the intended measures to add measure repeats
or repeat ranges. Write & Render does not convert drawn opening, closing or
combined bar-and-dot repeat barlines. These are not promised future handwriting
repairs. **Free Ink** can retain those signs as ordinary ink.

Existing saved repeat spans, their retained source ink, repeat editing,
rendering, and PDF export remain supported. Typed/manual chord-repeat symbols,
ordinary barline entry and handwritten ending-bracket review remain supported.

## Source and evidence boundaries

Historical repeat recognizers, drawing limits, earlier local test results,
replay receipts and installation records remain recoverable in Git history and
the existing source archives. They describe their recorded revisions. Private
chart and PencilKit captures stay local.

Retiring bar-and-dot ingestion does not authorize deleting or rewriting existing
chart objects or pending ink. Preserve saved repeat/source data, the manual
measure-based tools and the restored chord-repeat recognition path. The basic
telemetry reduction remains in place; this correction does not reopen expanded
telemetry, Graph/MyScript or parked ML work.

## Delivery status

This records the corrected source/copy contract. Validation of the corrected
candidate, GitHub publication, merge, signing and installation require their own
receipts. Prior tests and the installed Build 143 do not establish fresh physical
Pencil acceptance of this correction.

Repository listing drafts and marketing guidance distinguish chord repeats from
measure/range repeats. External App Store fields, the public website and
already-published social posts require separate publication/readback. This
source correction does not change those external surfaces or the sealed local
candidate packet.
