# Chord-repeat scope correction — November 5, 2026

## User clarification and current contract

The user clarified: “i didnt say to get rid of chord repeat symbols... just
measure repeats”. The corrected candidate supports handwritten chord-repeat
symbols (`%` / dot-slash-dot) in **Write & Render**, including Automatic and
Manual Render with Preview on Simple Chord Sheet and Rhythm Section Sheet.

Handwritten bar-and-dot opening, closing and combined measure/range repeat signs
(`||:`, `:||`, `:||:`) stay retired. Use **Tools > Repeats** with selected measures
for measure repeats/ranges. Ordinary barlines and handwritten ending brackets
remain supported. Typed/manual chord repeats, existing saved repeat notation,
source ink, PDFs and setlists must remain compatible.

This corrects the overly broad removal in local commit `936aa2ab4eb6448baea3f047d5ec5f1170f901de`.
It does not reopen Graph/MyScript, ML-core, expanded telemetry or personal
handwriting training. All basic telemetry reduction, consent and anonymous
transport behavior remain in place.

## Guidance updated with the source correction

The Write & Render helper and How To distinguish chord-repeat symbols from
measure/range repeat signs. Current repository policy, project state, recognition
notes, metadata/marketing drafts and historical scope banners use the same
boundary. The homepage source draft mentions chord-repeat symbols and directs
measure/range entry to the Repeats tool.

Earlier sealed packets, replay/device captures and test receipts remain intact.
The prior combined-candidate handoff is marked historical with its original
results retained. Those results do not validate this corrected source.

## Required evidence and delivery boundary

The corrected candidate needs its own recognition, Automatic/Manual rendering
and save/reopen checks for chord-repeat symbols in both chart styles. Preserve
negative coverage for bar-and-dot measure/range ingestion, ordinary barline and
ending controls, source ownership and saved-repeat compatibility. Retain the
telemetry/privacy/storage/network isolation checks.

The source/copy review preceded the executed validation below. No fresh physical Pencil result is claimed.
Source review, automated tests, Simulator behavior and physical iPad results
must be reported separately for the exact corrected revision. Physical device
work still requires its own authorization and preservation backup.

This is a local source/copy correction. It does not publish the homepage draft,
change external Apple fields or posts, push/merge a PR, deploy a backend, install
an app or release to the App Store. The basic telemetry privacy-policy source
changes and any external copy updates retain their separate publication gate.


## Final corrected-candidate validation

| Local check | Total | Passed | Skipped | Failed |
| --- | ---: | ---: | ---: | ---: |
| Full native target | 3,273 | 3,153 | 120 | 0 |
| Full portable suite | 2,010 | 1,918 | 92 | 0 |
| Focused workflow, targeting, guidance and UI checks | 78 | 78 | 0 | 0 |

The native workflow test uses the existing `ChordRepeatCaptured01` fixture through production preparation and recognition. It covers both chart styles, both preparation flows and Manual/Automatic commits, requiring a chord-repeat event, no measure-repeat span, retained source ink and exact serialization/reopen. Bar-and-dot retirement and manual/saved repeat compatibility checks remain. UI tests retain every viewport, control-reachability and canvas-stability assertion while requiring the exact current chord/measure distinction.

All 1,258 app/test/project inputs and the frozen native product bytes were verified unchanged after the final runs. The native payload came from `build-for-testing` and an explicit full-target descriptor on the configured iPad (A16), iOS 26.5 Simulator. All three task-owned Simulators were shut down and temporary accessibility/keyboard preferences were restored. Independent runtime review passed eleven checks: nine restored recognition/fallback files match the pre-removal base exactly; the session retains only the structural-context rename; the measure-repeat reader remains absent; telemetry and core data/source guards remain intact.

Earlier failures were test-contract corrections: separate the stored PencilKit buffer from a decoded/re-encoded buffer when asserting byte preservation, and update old generic repeat-helper text assertions. No runtime code changed for those test fixes, and all layout/preservation assertions remain. Three UIKit-only test-file corrections were inactive on macOS; their guards/hashes and unchanged active portable inputs are recorded. A payload preflight also switched from raw Swift mangled names to canonical demangled names; native compilation itself passed.

The corrected local commit/tree, exact source and product manifests, all logs/result bundles, patches and publication drafts are recorded in the sealed handoff at `/Users/benirossman/.local/share/ichart/repository-archives/2026-11-05-chord-repeat-scope-correction/`. The prior `936aa2ab` packet is unchanged and superseded for scope, not rewritten. PR #102 remains unmerged; this correction is not pushed, installed or released.
