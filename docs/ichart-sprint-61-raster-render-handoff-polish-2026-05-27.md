# iChart Sprint 61 Raster Render Handoff Polish

Status: complete locally; awaiting GitHub verification after push
Date: 2026-05-27
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Goal

Keep the writing-to-render handoff feeling immediate without premature rendering, unnecessary raster work, or a speculative renderer rewrite.

## Evidence Gathered

Sprint 61 started by checking the current timing and render-handoff surfaces before changing behavior:

- `LeadSheetChordInkRecognitionScheduling` owns the idle/continuation wait policy.
- `ChordInkRecognitionTiming` captures requested delay, idle time, recognition time, and total scheduled-to-recognition-finished time.
- `EditorView.commitChordInkCandidate` measures structured chart commit mutation time.
- `EditorView.recordPendingChordRenderHandoff` measures the time from commit observation to SwiftUI chart-change/render handoff and replaces the latest matching diagnostic row.
- `Chart.commitRecognizedChordInk` remains the model-level commit contract: append structured `ChordEvent`, store source ink evidence, and clear active chord ink only after a successful append.
- `scripts/audit_chord_entry_diagnostics.py` can print persisted timing evidence.
- `scripts/analyze_chord_timing_logs.py` can classify console timing logs by scheduler, recognition, proposal, commit, render handoff, OCR, and trust route.

## Current Finding

The strongest existing timing evidence still comes from Sprint 50:

| Case | Scheduled-to-finished | Recognition | Render handoff | Classification |
| --- | ---: | ---: | ---: | --- |
| `C` | `405ms` | `0ms` | `7ms` | root-continuation scheduler wait dominated |
| `G/B` | `782ms` | `2ms` | `13ms` | idle scheduler wait dominated |
| `Db7(b9)` | `813ms` | `28ms` | `6ms` | trust/candidate route dominated, not render |

Current booted simulator app data was also inspected with:

```bash
python3 scripts/audit_chord_entry_diagnostics.py --app-data "$APP_DATA" --details --scores 5
```

The active simulator chart had six rendered auto-render diagnostics but no timing evidence on those rows, so it is not enough to justify a render-path change.

## Decision

Do not rewrite renderer/raster behavior from current evidence. The existing data says render handoff is small compared with scheduler/idle and recognition/trust routing. Sprint 61 should either:

- run one clean timing capture on the current app build, or
- make only a tiny measurement/tooling improvement if current timing evidence is missing when it should be present.

## Clean Current Timing Capture Setup

Commit `5ae51d2` passed required GitHub Actions. The app was then rebuilt and launched on the configured iPad simulator with:

```bash
xcodebuildmcp build_run_sim CODE_SIGNING_ALLOWED=NO
```

Build/run result:

- scheme: `iChart`
- simulator: `iPad Pro 13-inch (M5)` / `42254D11-2E65-4586-AEBE-C6317AF2DD10`
- bundle id: `com.ichart.app`
- result: succeeded
- runtime log: `/Users/benirossman/Library/Developer/XcodeBuildMCP/workspaces/iChart-f58ea80f996f/logs/com.ichart.app_2026-05-27T18-00-37-067Z_helperpid35175_ownerpid1549_ce5f8613.log`
- OS log: `/Users/benirossman/Library/Developer/XcodeBuildMCP/workspaces/iChart-f58ea80f996f/logs/com.ichart.app_oslog_2026-05-27T18-00-38-081Z_helperpid35249_ownerpid1549_2e153308.log`

Run one bounded simulator/iPad pass:

| Case | Expected route | Timing question |
| --- | --- | --- |
| `C` | auto-render if clear | Is final-stroke delay still scheduler/continuation wait, or does render handoff grow? |
| `G/B` | auto-render if clear | Does slash placement stay fast after Sprint 60 candidate backfill? |
| `Db7(b9)` | auto-render or confirm depending on confidence race | Does candidate availability stay present, and is any delay trust/confirmation rather than render? |

After the pass, inspect persisted diagnostics:

```bash
APP_DATA="$(xcrun simctl get_app_container booted com.ichart.app data)"
python3 scripts/audit_chord_entry_diagnostics.py --app-data "$APP_DATA" --details --scores 8
```

If console logs are needed, parse the runtime log:

```bash
python3 scripts/analyze_chord_timing_logs.py "/Users/benirossman/Library/Developer/XcodeBuildMCP/workspaces/iChart-f58ea80f996f/logs/com.ichart.app_2026-05-27T18-00-37-067Z_helperpid35175_ownerpid1549_ce5f8613.log"
```

Route the next move from evidence:

- high `delay`/`idle`, low recognition/proposal/commit/render: scheduling or continuation policy
- high `recognition`: recognizer/candidate conflict
- high `proposal` or `commit`: editor proposal or chart mutation
- high `render`: SwiftUI/render handoff
- low timing but wrong/ambiguous result: confidence/candidate/trust route

## Timing Capture Result

Fresh simulator pass source:

- app data: CoreSimulator app container `Library/Application Support/iChart`
- chart: `Untitled Chart`
- chart ID: `57C55F1B-3860-43D1-9622-5FCF7D9EC403`
- diagnostics: `chord-entry-diagnostics.jsonl`
- console runtime log: `/Users/benirossman/Library/Developer/XcodeBuildMCP/workspaces/iChart-f58ea80f996f/logs/com.ichart.app_2026-05-27T18-00-37-067Z_helperpid35175_ownerpid1549_ce5f8613.log`

Observed result:

| Case | Route | Scheduled-to-finished | Recognition | Commit | Render handoff | Classification |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `C` | auto-render | `419ms` | `0ms` | `5ms` | `19ms` | root-continuation scheduler wait dominated |
| `Absus` | auto-render | `432ms` | `18ms` | `4ms` | `17ms` | scheduler plus modest candidate composition |
| `Db7(b9)` | user-rule applied after close-route evidence | `863ms` | `63ms` including `41ms` OCR | `3ms` | `19ms` | trust/OCR/candidate race, not render |
| `G#+` | auto-render | `420ms` | `3ms` | `7ms` | `28ms` | scheduler dominated; highest render sample still small |
| `B°7` | auto-render | `1265ms` | `1ms` | `3ms` | `15ms` | continuation scheduler wait dominated |

The active chart had `7` rendered chord events and `7` matching diagnostics with timing evidence. `6` were `autoRendered`; `1` was `userRuleApplied`. The pass also produced one placement evidence mismatch for `Db7(b9)`: the diagnostic row captured start `3`, while the current chart state reports start `1`. That belongs to placement/edit evidence, not raster/render handoff.

## Closeout Decision

Sprint 61 does not justify renderer or raster code changes. The measured render handoff stayed in a small `15-28ms` band. Perceived delay is still dominated by scheduler/continuation policy, recognition/trust work on complex chords, or user-rule/confirmation routing.

Do not change `PKCanvasView`, export rasterization, or rendered chord drawing from this sprint. Move to the chord-first release-candidate pass with this evidence preserved.

## Guardrails

- No personal handwriting fixture expansion.
- No recognition score retuning.
- No default OCR expansion.
- No symbol-ledger diagnostics cost.
- No export behavior change unless a measured export/raster issue is found.
- No change to accepted-chord ink clearing.
