# iChart Sprint 62 Chord First Release Candidate Pass

Status: complete
Date: 2026-05-27
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Goal

Close the chord-first side-sprint lane with one bounded product pass that validates the main chord loop end to end:

```text
write -> recognize -> auto-render or confirm -> clear ink -> edit if needed -> export
```

This is a release-candidate validation pass, not a new recognition-training loop.

## Guardrails

- No personal handwriting fixture expansion.
- No recognition score retuning from one writer's pass.
- No default OCR expansion.
- No symbol-ledger diagnostics cost.
- No renderer/raster rewrite unless new timing evidence proves render handoff is the blocker.
- No accepted-chord ink-clearing change.
- Capture summary evidence unless a concrete bug needs diagnostics.

## Pass Checklist

Use one clean chart and complete the following bounded cases:

| Case | Expected route | What to verify |
| --- | --- | --- |
| `C` | auto-render | Basic chord renders promptly, ink clears, placement feels right |
| `G/B` | auto-render | Slash chord candidate availability and placement remain stable |
| `Absus` | auto-render or clean confirmation if close | Suspended chord remains available without handwriting-specific tuning |
| `Db7(b9)` | auto-render or clean confirmation/direct input depending on confidence race | Altered-extension suggestions stay compendium-approved and candidate availability is present |
| one intentional correction/rewrite | confirmation, manual entry, delete, or rewrite path | Wrong-render recovery does not create a write/delete/rewrite loop |
| export | PDF/share/Preview | Export produces the full chart page, not old card blocks |

## Simulator Setup

The current app was rebuilt and launched for this pass with:

```bash
xcodebuildmcp build_run_sim CODE_SIGNING_ALLOWED=NO
```

Build/run result:

- scheme: `iChart`
- simulator: `iPad Pro 13-inch (M5)` / `42254D11-2E65-4586-AEBE-C6317AF2DD10`
- bundle id: `com.ichart.app`
- result: succeeded
- runtime log: `/Users/benirossman/Library/Developer/XcodeBuildMCP/workspaces/iChart-f58ea80f996f/logs/com.ichart.app_2026-05-27T18-46-23-458Z_helperpid39027_ownerpid1549_c72d9062.log`
- OS log: `/Users/benirossman/Library/Developer/XcodeBuildMCP/workspaces/iChart-f58ea80f996f/logs/com.ichart.app_oslog_2026-05-27T18-46-24-491Z_helperpid39101_ownerpid1549_5e66a38e.log`
- screenshot: `/var/folders/8g/kslp9zm178l_8pmjnh37lsnc0000gn/T/screenshot_optimized_fa673185-d25d-4d6c-ba22-e1a4d4f9850e.jpg`

After the pass, inspect the selected chart:

```bash
APP_DATA="$(xcrun simctl get_app_container booted com.ichart.app data)"
python3 scripts/audit_chord_entry_diagnostics.py --app-data "$APP_DATA" --details --scores 8
python3 scripts/analyze_chord_timing_logs.py "/Users/benirossman/Library/Developer/XcodeBuildMCP/workspaces/iChart-f58ea80f996f/logs/com.ichart.app_2026-05-27T18-46-23-458Z_helperpid39027_ownerpid1549_c72d9062.log"
```

## Evidence Routing

If the pass finds an issue, assign it to one lane:

| Symptom | Route |
| --- | --- |
| Wrong or missing suggestions | recognition/candidate availability |
| Good suggestions but wrong automatic behavior | confidence/trust |
| Confirmation feels heavy or confusing | confirmation/direct input UX |
| Chord lands in the wrong beat/measure | placement/snapping |
| Render appears late despite low scheduler/recognition/commit times | render handoff |
| Export/share fails or output is incomplete | export |
| Ink does not clear after accepted chord | chord ink lifecycle |
| Rewrite/delete repeats the same wrong answer | local correction memory |

## Current Evidence Inputs

- Sprint 60: supported candidate backfill prevents compendium-approved candidates from being hidden behind unsupported raw noise.
- Sprint 61: render handoff stayed small at `15-28ms`; do not rewrite renderer/raster behavior from current evidence.
- Sprint 61: one `Db7(b9)` placement evidence mismatch was observed after a user-rule-applied commit. Watch whether placement mismatch reproduces in this release-candidate pass.

## Pass Evidence: 2026-05-27

Simulator app data:

- container: `/Users/benirossman/Library/Developer/CoreSimulator/Devices/42254D11-2E65-4586-AEBE-C6317AF2DD10/data/Containers/Data/Application/E00D3EF2-C51E-40D8-AED4-F887C6EBA6A5`
- active chart: `9F9DD955-91BF-4361-9B02-177B49C48A0C`
- active chart events: `C`, `G/B`, `Db7(b9)`, `Absus`

Recognition and render evidence:

| Chord | Result | Timing | Placement |
| --- | --- | --- | --- |
| `C` | auto-rendered | total `420ms`, recognition `1ms`, commit `8ms`, render `40ms` | matched |
| `G/B` | auto-rendered | total `791ms`, recognition `2ms`, commit `3ms`, render `16ms` | matched |
| `Db7(b9)` | user rule applied from close race | total `856ms`, recognition `64ms`, OCR `40ms`, commit `3ms`, render `16ms` | matched |
| `Absus` | auto-rendered | total `432ms`, recognition `19ms`, commit `3ms`, render `15ms` | matched |

Findings:

- Basic, slash, suspended, and altered-extension chord commits are present as structured `ChordEvent`s.
- `Db7(b9)` remained compendium-approved and was recovered through the local correction rule rather than score retuning.
- Placement evidence was complete and matched for all four active chord events.
- Render handoff stayed small at `15-40ms`; renderer/raster is not the current blocker.
- The initial simulator PDF cache was stale: `Library/Caches/iChartExports/untitled-chart-concert.pdf` was last modified on `2026-05-26 09:31:58 -0700`, before the current `2026-05-27 11:52:45 -0700` pass. This was resolved by the fresh export evidence below.

## Export Evidence: 2026-05-27

Fresh export evidence:

- iChart export cache: `Library/Caches/iChartExports/untitled-chart-concert.pdf`
- Preview document copy: `Documents/untitled-chart-concert-4.pdf`
- modified: `2026-05-27 12:23:13 -0700`
- size: `45024`
- type: PDF 1.3, `1` page

Visual verification:

- QuickLook rendered the fresh PDF successfully.
- The rendered page showed `C`, `G/B`, `Db7(b9)`, and `Absus`.
- Export now matches the active chart state for the bounded Sprint 62 pass.

## Acceptance Criteria

- Basic, slash, suspended, and altered-extension chords complete the write-to-render loop.
- Accepted chord ink clears.
- Close races route to clean confirmation/direct input.
- Wrong-render recovery avoids repeated wrong auto-renders.
- Export produces the full chart.
- Any remaining issue is routed to the correct next lane instead of reopening the full audit plan.
