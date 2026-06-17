# Smart Chart — Jazz Lead-Sheet Build Plan

Status: historical post-V1 Lead Sheet reference
Date: 2026-04-24

Archive note: this is preserved as historical Lead Sheet concept work only. It is not active for V1 and should not make the post-V1 Lead Sheet direction jazz-only.

This is the working plan for the app as it exists now.

We are no longer building multiple notation paths or a recognition-heavy prototype first.
We are building one product path:

- projects landing page
- new chart setup
- jazz lead-sheet page
- top tool tabs
- page-wide free-hand writing
- measure growth on the page
- interpretation later, on top of a stable authoring surface

## Build tracks

Every new feature should fit into one of these tracks.

### 1. Editor shell

Purpose:
- keep the top-level UI simple
- make tool state explicit
- avoid hidden interaction modes

Includes:
- top tabs
- page setup and header editing
- view/transposition controls
- authoring mode state

Rule:
- if a feature changes what the user can do at the page level, it belongs here first

### 2. Lead-sheet page

Purpose:
- make the page look and behave like a real lead sheet
- keep systems, measures, and spacing deterministic

Includes:
- paper frame
- header
- system layout
- measure sizing
- writable regions
- measure growth and wrapping

Rule:
- geometry should come from the layout engine, not from ad hoc view math

### 3. Authoring overlays

Purpose:
- let the user write naturally on the page
- keep raw input stable before interpretation

Includes:
- free-hand writing
- future localized writing regions
- future selection and revision overlays
- later snapping/recognition layers

Rule:
- capture first, interpret second

## Stage sequence

### Stage A — Foundation

Status: done

Delivered:
- jazz-only setup path
- one medium opening measure
- page-wide free-hand mode
- simplified top tabs

### Stage B — Mode architecture

Status: current

Goal:
- move the editor onto an explicit mode model so future tools do not become one-off booleans

Delivered in this stage:
- explicit editor canvas mode
- shared shell/canvas behavior for browse vs free-hand

### Stage C — Measure and system growth

Status: next

Goal:
- make measure creation and continuation feel intentional on the jazz page

Focus:
- clearer active-measure targeting
- better open-measure continuation
- stable wrapping when measures expand across systems

### Stage D — Localized writing regions

Status: upcoming

Goal:
- move from one page-wide raw-ink layer toward deliberate authored regions

Focus:
- chord-band region
- staff writing region
- measure-local revision behavior

### Stage E — Structured interpretation

Status: later

Goal:
- convert writing into structured chart objects only after the writing experience feels correct

Focus:
- chord ingestion
- barline interpretation
- rhythm interpretation
- reinterpret/edit loops

## Working rules

- stay on the jazz lead-sheet path only
- do not add alternate notation formats yet
- do not add recognition-driven behavior before the writing surface feels right
- prefer one stable system over multiple half-working paths
- when adding a feature, decide first which track it belongs to
