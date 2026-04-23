# Smart Chart — Basic Chart Creation Flow

Status: Active behavior spec for the most basic authoring flow
Date: 2026-04-23
Source of truth for this flow: `docs/core-design-document.md`

## Purpose

This document defines the exact first-use interaction flow for creating the simplest possible Smart Chart.

This is the minimum flow the app must handle well before more advanced recognition, rhythm entry, roadmap symbols, or polish work matter.

## Scope of this flow

This document covers one simple case:
- open app
- create a new chart
- set time signature and key
- render the first chart line
- write one chord
- explicitly ingest that chord
- draw a closing barline
- commit the measure as a structured object

This flow is intentionally narrow. It should work reliably even before broader recognition features are added.

## Terminology

For clarity, this document uses these terms:

- `landing page`: the app's main home screen
- `project`: a saved chart document
- `chart page`: the white authoring surface
- `chart line`: the first horizontal chart row at the top of the page
- `stanza`: shorthand for the first chart line; this is not a full notation staff
- `open measure`: a measure that has started but is not yet closed by a barline
- `committed measure`: a measure closed by a recognized barline and stored as structured chart data
- `ingest tap`: a user tap above a handwritten chord that tells the app to convert it into a structured chord object

## High-level flow

1. User opens the app.
2. User lands on the home screen.
3. User taps `New Chart`.
4. App opens a blank white chart page.
5. App prompts for time signature and key.
6. User confirms time signature and key.
7. App renders the first chart line at the top of the page with the time signature and an opening barline.
8. User handwrites a chord next to the opening barline.
9. User taps above the handwritten chord to mark it ready for ingestion.
10. App converts the handwriting into the best matching structured chord symbol and snaps it into place.
11. User draws a barline to close the measure.
12. App recognizes the barline, closes the measure, and commits that measure plus its contents as structured chart data.

## Detailed screen-by-screen flow

### Screen 1 — Landing page

When the app opens, it should land on a main home screen with clear top-level navigation.

Minimum top-level tabs or destinations:
- `Projects`
- `Settings`
- `Account`

Minimum primary action:
- `New Chart`

The landing page should also allow:
- opening an existing chart from `Projects`
- starting a new blank chart immediately

For this basic flow, the primary path is:
- user taps `New Chart`

## Screen 2 — New chart entry state

After tapping `New Chart`, the app opens a new blank chart document.

The visible result should be:
- an entirely blank white page space
- no existing chart content
- no pre-filled measures beyond the initial document scaffolding needed for the flow

Immediately after opening the blank page, the app should prompt for:
- `Time Signature`
- `Key`

This prompt can appear as:
- a modal sheet
- a compact setup panel
- a floating setup card

For this flow, the prompt must appear before the first committed chart line is finalized.

## Required user inputs before the first line is generated

### Time signature

The user must be able to choose or enter a time signature such as:
- `4/4`
- `3/4`
- `6/8`

### Key

The user must be able to choose or enter a key such as:
- `C`
- `Bb`
- `Eb`
- `G minor`

For the basic flow, key entry exists so the document has transposition context from the beginning.

## Screen 3 — First chart line generated

Once the user confirms time signature and key, the blank page transitions into the first editable chart state.

The app must generate:
- one chart line at the top of the white page
- the selected time signature at the far left of that chart line
- the opening barline immediately to the right of the time signature
- an open measure area to the right of the opening barline

Important clarification:
- this is a chart line or stanza, not a five-line notation staff
- the page should still feel mostly blank and open after this first line appears

## Initial structured state after generation

At this point, the app should internally create:
- a new `Chart`
- the chart's default key
- the chart's default time signature
- the first `System` or chart line
- the first `Measure` in an `open` state
- an opening barline anchoring the start of that measure

At this stage, the measure is not yet committed for export/transposition workflows as a finished measure. It exists as the active editable measure being authored.

## Screen 4 — User writes a chord

The user now writes a chord by hand to the right of the opening barline inside the open measure.

Examples:
- `C`
- `Bb min`
- `F#7`
- `Ebmaj7`

For this basic flow:
- the app should capture the handwriting as raw ink first
- the app should not immediately force final recognition while the user is still writing
- the chord remains in a pending handwritten state until the user explicitly confirms it

## Pending handwritten chord state

While the chord is still just handwritten ink:
- it should remain visually close to what the user wrote
- it should be associated with the current open measure
- it should be treated as `pending ingestion`
- no final structured chord object should replace it yet

This explicit pause is important because the user is signaling when recognition should happen.

## Screen 5 — User signals ingestion

When the user finishes writing the chord, the user taps the screen above the handwritten chord to indicate that the chord is ready to be ingested.

This tap is part of the core interaction model for the basic flow.

### Meaning of the ingest tap

The tap above the chord means:
- "I am done writing this chord"
- "Interpret this ink now"
- "Convert it into a structured chord object"

### Ingest tap behavior

The app should:
1. identify the nearest pending handwritten chord ink group below the tap
2. freeze that ink group as the recognition target
3. match the handwritten shape against supported chord patterns
4. choose the best chord-symbol candidate
5. replace or overlay the handwriting with a snapped structured chord symbol
6. keep the raw ink linked to the structured object for later reinterpretation if needed

## Chord recognition expectations

For this basic flow, recognition only needs to handle common chord symbol cases well enough to support quick charting.

Examples of supported recognition targets:
- `C`
- `Cm`
- `C-`
- `Bb min`
- `Bb-`
- `F7`
- `Ebmaj7`
- `D/F#`

### After ingestion, the result must become a structured chord object

Once the chord is ingested, the app should create a structured chord event with at least:
- the recognized chord symbol
- the raw original input
- the active measure reference
- the document key context
- a default beat position
- a default duration value appropriate for an unfinished open measure

Visually, the chord should:
- snap into a clean chart-symbol style
- align to the measure space
- look clearly different from raw handwriting

## Screen 6 — User draws a closing barline

After the chord has been ingested, the user can draw a vertical barline to the right of the chord.

This barline means:
- the current measure is complete
- everything inside that measure should now be finalized as one structured measure

### Closing barline behavior

When the user draws the barline, the app should:
1. detect a vertical stroke in the expected measure-boundary zone
2. interpret it as a closing barline
3. snap it to the chart line and measure boundary
4. close the current open measure

## Measure commit behavior

Once the closing barline is recognized, the app must commit the measure and all of its current elements.

That means the measure becomes an official structured unit that can support later features such as:
- transposition
- time signature changes for following measures
- layout reflow
- export
- editing and reinterpretation

### Minimum objects that should be committed

The committed measure should contain:
- start boundary
- end boundary
- time signature context
- any ingested chord events inside the measure
- any future rhythm placement metadata associated with those chord events

## Resulting post-commit state

After the first measure is committed, the page should now show:
- the first chart line at the top of the page
- the time signature at the left
- the opening barline
- the snapped chord symbol
- the closing barline
- one fully committed measure

The app should then be ready for the next action, such as:
- opening a new measure to the right
- allowing another chord to be written
- accepting a meter change for the next measure if the user initiates one later

## State-machine summary

### State 1 — Landing
- user sees home screen
- `New Chart` is available

### State 2 — Blank chart page
- white empty page is visible
- time signature and key prompt is active

### State 3 — Primed chart page
- first chart line exists
- time signature is visible
- opening barline is visible
- first measure is open

### State 4 — Pending ink
- handwritten chord exists in the open measure
- no final structured chord yet

### State 5 — Ingested chord
- chord has been matched and snapped
- raw ink remains linked for reinterpretation

### State 6 — Committed measure
- closing barline has been recognized
- measure and its contents are now structured document data

## Explicit acceptance criteria

This flow is successful only if all of the following are true:

- the app opens to a landing page with clear top-level destinations such as `Projects`, `Settings`, and `Account`
- `New Chart` is an obvious primary action
- tapping `New Chart` opens a blank white chart page
- the app prompts for both time signature and key before the first chart line is finalized
- confirming those values generates one chart line at the top of the page
- that chart line includes the time signature and an opening barline
- the user can handwrite a chord into the open measure
- the user can tap above the chord to explicitly trigger ingestion
- the app converts the handwritten chord into a snapped structured chord symbol
- the user can draw a closing barline
- that barline commits the measure and its elements as structured chart data

## Explicit non-goals for this flow

This first flow does not need to prove:
- advanced rhythm recognition
- multiple chord events in one measure
- roadmap symbols
- section labels
- PDF export
- cloud sync
- advanced AI interpretation

Those can come later. This basic flow must work first.

## Product rule enforced by this document

If Smart Chart cannot do this basic flow smoothly, the product is not yet ready to expand into more advanced recognition or editing complexity.
