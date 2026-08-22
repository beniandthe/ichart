# Chord Lane Auto-Render Course Correction

Date: 2026-08-21
Base branch: `codex/1.1.7-build49-testflight`
Clean base commit: `885355e` (`Record corrected TestFlight branch cleanup`)
Implementation fallback commit: `697c2a5` (`Establish chord lane draft render baseline`)

This document captures the intended chord-lane implementation after the August 2026 recovery reset. It is a product and engineering contract, not proof that the implementation is complete.

## Fallback Checkpoint

Commit `697c2a5` on branch `codex/chord-lane-auto-render` is the first committed baseline for the course-corrected chord-lane system.

Use this as the fallback point if later work destabilizes the chord tool workflow. This checkpoint includes:

- explicit draft preview before render
- `Render Chords` as the only chord-lane commit action
- draft/user barline recognition and preview ordering
- restored preview bootstrap for saved chord ink
- erased/invisible stroke filtering to prevent preview ghosts
- select-mode chord-lane hiding
- Pencil-enabled preview strip scrolling
- committed chord movement, resizing, deletion, and barline deletion safeguards
- deprecated OCR path removal from live app code, tests, diagnostics, and scripts

Verification recorded at the checkpoint:

- `git diff --check` passed
- focused simulator gate passed with `173` tests, `173` passed, `0` failed, `0` skipped
- targeted OCR search across `iChart`, `iChartTests`, `project.yml`, and `scripts` found no live OCR references

If recovery is needed, prefer branching from the checkpoint instead of destroying active work:

```bash
git switch -c codex/chord-lane-recovery 697c2a5
```

Only reset an active branch to this checkpoint after saving or intentionally discarding later work:

```bash
git switch codex/chord-lane-auto-render
git reset --hard 697c2a5
```

Future chord-lane changes should preserve this baseline contract unless a newer checkpoint explicitly supersedes it.

## Product Goal

The chord tool should feel like writing on a paper lead sheet with a blue chord lane:

- The user writes naturally from the beginning of a staff/system.
- The blue chord lane is open from the left guide to the right edge/end barline.
- The user writes a base chord letter.
- The user writes any suffix/extensions after that base letter.
- The user moves to the next base letter.
- The next base letter starts a new chord.
- Starting a new chord means the previous chord is accepted for preview grouping and must not be retroactively reinterpreted.
- A vertical or near-vertical line drawn by itself in the lane is a barline.
- The same flow repeats across every staff/system on the page.

## Non-Negotiable Contracts

- Ink remains the source of truth until `Render Chords`.
- Live preview must not mutate committed chord symbols, committed barlines, or real measure widths.
- Draft barlines are non-destructive until they are auto-created or explicitly rendered according to the active branch contract.
- Rendered chords must be editable after render.
- Rendered chords must move freely left/right in the chord lane without beat snapping.
- Rendered chords must be able to move tightly near barlines when space demands it.
- Dense chord glyphs should stay uniform and readable. Solve density with layout/span/width, not by shrinking text unpredictably.
- Existing page/layout behavior and current release branch must stay testable.

## Intended User Flow

1. User selects the chord tool.
2. The page shows one open blue chord lane per system/stanza.
3. Each lane has the first left boundary and the final right/end barline.
4. User writes chord ink anywhere in the lane.
5. Recognition updates after stroke completion/debounce, not during every Pencil movement.
6. Preview panel updates dynamically, like the rhythm preview pattern.
7. User keeps writing across the lane and across systems.
8. When the user writes the next base root, the previous chord group is closed for preview purposes.
9. A solo vertical/near-vertical stroke in the lane becomes a barline.
10. User can delete user-created barlines.
11. User taps `Render Chords`.
12. Render commits all renderable draft chords and barlines as one model operation.
13. The blue ink clears only when rendered chords are visibly present or otherwise acknowledged in chord-tool mode.
14. Leaving chord-tool mode should not be required to prove render success.

## UI Scope

Keep the UI basic:

- Chord tool button.
- Blue chord lane.
- Dynamic preview panel.
- `Render Chords`.
- No separate `Read` button.
- No manual correction UI in the first course-corrected lane branch.
- No candidate picker in the first course-corrected lane branch.
- No extra debug controls in production UI.

## Core Systems

### Chord Lane Geometry

Relevant areas:

- `LeadSheetPageLayout`
- `LeadSheetPageLayoutEngine`
- `LeadSheetActiveInkScope`
- `LeadSheetCanvasHostView`
- `LeadSheetChordInkRecognitionTargeting`
- `ChordInkDraftPreview`
- `EditorView`

The chord lane should be generated from current engraving, not from recognition state. The lane is the writing surface; committed model changes are applied only after render or barline auto-create, depending on the branch phase.

### Draft Preview State

The draft state should track:

- draft chord IDs
- source drawing data or stroke references
- authored lane/system/page anchor
- bounds
- visual order
- recognition payload
- preview text or unread state
- dirty/stale state
- draft barlines
- unresolved counts
- render readiness

Preview order must be placement-aware across systems and left-to-right within each system.

### Batch Render

Batch render should:

- commit draft barlines and draft chords together where applicable
- preserve authored system/lane placement
- place chords between existing rendered chords when their x-position is between them
- preserve visual order
- clear draft ink only after a successful render path
- create undo that restores the prior model and draft ink state

### Rendered Chord Editing

Rendered chord editing should include:

- free horizontal drag in the chord lane
- cross-measure movement within the same system
- cross-system movement when the user drags into another lane
- no beat-grid snapping during drag
- side handles to widen/narrow the rendered chord box
- deletion of ink-origin rendered chords
- deletion of user-created barlines

## Barlines

A draft/user barline is recognized from a solo vertical or near-vertical lane stroke. It should not require chord context.

Recognition cues:

- sufficient lane-height coverage
- strong vertical angle
- straight enough path
- narrow enough width
- centered inside or near the chord lane

Rejection cues:

- slash chord separator shape
- diagonal rhythmic slash
- short vertical stem inside a chord glyph
- out-of-lane stroke
- near-duplicate barline too close to an existing one

Behavior:

- user-created barline can be deleted
- end-of-system lane has a final barline by default
- final barline geometry must line up with measure selection and page layout
- drawn barline placement is preserved when spacing mode is `drawn`
- optional exact/even spacing mode may transform spans into preprogrammed measure widths

## Breaking Points To Watch

- Preview order reversing because payloads are sorted by recognition completion instead of lane x-position.
- Chords rendering to the first system because lane anchors are dropped.
- Chords moving across systems but not across measures because committed placement still uses measure-local constraints.
- Rendered chord drag bouncing away from barlines because layout clamps or beat snapping remain active.
- Ink disappearing after `Render Chords` while committed chords are only visible after leaving chord-tool mode.
- Draft barlines rendering far from where they were drawn because target measure/span calculation uses stale measure geometry.
- Multiple systems sharing one open measure ID and losing authored system index.
- Live recognition updating persisted drawing on every stroke and making ink slow.
- Simulator failures being mistaken for product failures.
- Recognition fixes modifying chord-lane architecture.

## Potential Additions

Do not add these until the basic flow is stable:

- candidate picker
- manual text correction panel
- recognition confidence overlays
- per-chord lock/unlock controls
- chord copy/paste
- multi-select rendered chord movement
- per-system lane spacing controls
- training/fixture capture UI
- telemetry dashboards

## Tests And Gates

Required unit/focused tests:

- chord lane frame extends to right page edge/end barline
- one lane per system/stanza
- final end barline aligns with selection and measure boundary
- draft barline recognizer accepts solo vertical lane stroke
- draft barline recognizer rejects slash/chord-stem strokes
- batch targeting preserves system/lane anchors
- render commits chords on the authored system
- render preserves left-to-right visual order
- rendered chord drag crosses measures in the same system
- rendered chord drag crosses systems
- rendered chord drag allows tight placement near barlines
- rendered chord resize changes manual layout width without beat snapping
- deleting user-created barline updates model/layout
- undo restores model and draft ink after batch render

Simulator/device gates:

- simulator can boot and run the app before UI testing
- iPad is connected and visible to CoreDevice before physical QA
- direct screen evidence or user-observed iPad evidence is required for visual acceptance
- no claim that recognition trust improved without physical writing evidence

Comparison gates:

- compare against the current merged chord-lane flow at `origin/main`
- compare against build-49 cleanup base `885355e`
- compare simple chord spacing after 1.1.6 dense spacing fixes
- ensure all filtered test commands execute nonzero tests

## Branch Policy

Dedicated chord-lane branch:

- branch name: `codex/chord-lane-auto-render`
- base: `885355e`
- scope: lane UI, draft preview, draft barlines, render batch, rendered chord movement/editing
- out of scope: recognizer accuracy experiments

Dedicated recognition branch:

- branch name: `codex/chord-correction-accuracy`
- base: `885355e`
- scope: chord grouping/recognition/correction accuracy
- out of scope: lane UI redesign and render-flow refactors

## Recovery Rule

If a fix requires touching both the chord-lane render workflow and the recognizer in the same commit, stop and split the problem first. The last failure mode came from letting those systems collapse into one patch stream.
