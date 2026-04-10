# Smart Chart — Developer-Facing MVP Spec

Status: Active for Prototype and V1  
Source of truth: `docs/core-design-document.md`

## 1. Purpose

This document turns the core design document into a buildable MVP specification.

If this document conflicts with the core design document, the core design document wins.

The MVP succeeds if it proves the core workflow:

**write -> recognize -> snap -> fix -> export**

## 2. Product goals

### Primary goals
- Make chart creation faster than paper cleanup and less tedious than rigid typed entry.
- Preserve the feel of handwriting while producing structured editable output.
- Keep correction fast enough that imperfect recognition is acceptable.
- Generate charts that look trustworthy and readable.

### Non-goals
- Full staff notation
- Melody or rhythm engraving
- Playback or backing tracks
- Realtime collaboration
- Desktop parity
- Required cloud sync for launch

## 3. Platform target

### V1 target
- iPadOS only for primary authoring
- Apple Pencil is first-class input
- Finger input is primarily for navigation, selection, editing, and mode changes

### Later platforms
- iPhone companion later
- macOS later only if it becomes useful for library/export workflows

## 4. Recommended technical stack

### App shell
- Swift
- SwiftUI
- UIKit bridge where the editor surface needs lower-level control

### Ink capture
- PencilKit for raw stroke capture and rendering

### Local persistence
- SwiftData preferred for speed of iteration
- Core Data acceptable if SwiftData limitations become painful

### Export
- Native PDF generation using Core Graphics / PDF rendering primitives
- PDFKit optional for preview if useful

### Backend
- No required backend for v1
- Local-first architecture
- Optional analytics and crash tooling only if lightweight and privacy-appropriate

## 5. MVP scope

### Included
- Blank chart creation
- Strong one-page chart layout
- Systems and measures
- Apple Pencil input on chart canvas
- Recognition of common chord symbols
- Recognition of section labels
- Recognition of cue text
- Recognition of simple roadmap objects
- Object selection, edit, delete, move, and reinterpretation
- Concert / Bb / Eb display
- PDF export

### Excluded
- Full notation
- Beat-level rhythmic spacing
- Audio playback
- Realtime collaboration
- OCR or photo import
- Required cloud sync
- Desktop app
- Marketplace or social features

## 6. MVP user stories

- As a bandleader, I want to write a quick chart naturally so I can hand a readable version to my players.
- As a gigging musician, I want to clean up a rough chart fast so I can use it at rehearsal.
- As a teacher, I want to create simplified readable chart handouts.
- As a horn player or bandleader, I want to generate Bb and Eb versions without rewriting the chart by hand.

## 7. Core object model

The chart must be represented as structured data, not just raw ink.

### 7.1 Chart
- id
- title
- chartType
- pageSize
- orientation
- defaultTranspositionView
- createdAt
- updatedAt
- stylePreset

### 7.2 System
- id
- index
- measureIDs
- spacingMode
- lineBreakRule

### 7.3 Measure
- id
- index
- barlineAfter
- chordIDs
- cueIDs
- roadmapIDs
- layoutMetadata

### 7.4 Chord
- id
- measureID
- root
- accidental
- quality
- extensions
- alterations
- slashBass
- displayStyle
- positionInMeasure
- rawInput

### 7.5 SectionLabel
- id
- text
- type (`sectionName` or `rehearsalMark`)
- anchorMeasureID
- anchorSystemID
- rawInput

### 7.6 CueText
- id
- text
- anchorMeasureID
- position
- emphasis
- rawInput

### 7.7 RoadmapObject
Supported subtypes:
- repeatSpan
- ending1
- ending2
- codaMarker
- toCoda
- segno
- ds
- dc
- fine
- noChord
- vampCount

Common fields:
- id
- type
- startMeasureID
- endMeasureID (optional)
- count (optional)
- linkedTargetID (optional)
- rawInput

### 7.8 Barline
Supported types:
- single
- double
- final

### 7.9 InkStrokeGroup
- id
- strokeData
- boundingBox
- candidateType
- recognizedText
- confidence
- linkedObjectID (optional)

## 8. Recognition model

Recognition does not need to be universal handwriting recognition. It only needs to work well for constrained chart vocabulary.

### Input categories
#### Chords
Examples:
- C
- Cm
- C-
- Cmaj7
- CΔ7
- C7
- C9
- C13
- C7b9
- F#-
- Bb7
- D/F#

#### Section labels
Examples:
- Intro
- Verse
- Chorus
- Bridge
- Outro
- Solo
- A
- B

#### Roadmap text or symbols
Examples:
- D.S.
- D.C.
- Fine
- al Fine
- Coda
- To Coda
- Segno
- 1.
- 2.
- x2
- x4
- Vamp
- N.C.

#### Cue text
Examples:
- drums in
- bass only
- tacet
- stop time
- hits
- rubato

#### Structural strokes
- vertical line => barline candidate
- bracket across measures => repeat / ending / vamp candidate
- scribble => delete gesture

### Context rules
- inside a measure => chord first
- above a system => section label first
- below or near a measure => cue text first
- text paired with a bracket => roadmap intent first
- vertical line near measure boundary => barline

### Confidence behavior
#### High confidence
- snap immediately

#### Medium confidence
- snap, but expose alternatives on tap or long press

#### Low confidence
- keep suggestion state or require reinterpretation with minimal friction

## 9. Interaction model

### Modes
#### Write mode
- default creation mode
- Pencil input creates recognition candidates

#### Select mode
- tap, select, and edit existing objects
- drag and reposition objects
- open inspector

#### Erase mode
- direct object removal
- supplemental to scribble delete

### Gesture-to-action map
#### Pencil write
- create chord / section / cue / roadmap candidate

#### Pencil vertical stroke
- create barline

#### Pencil bracket over span
- create repeat / ending / vamp candidate

#### Pencil scribble over object
- delete object

#### Finger tap object
- select object

#### Finger drag selected object
- reposition or re-anchor object

#### Long press object
- open reinterpretation menu

#### Pinch
- zoom canvas

#### Two-finger drag
- pan canvas

#### Two-finger tap
- undo if reliable

#### Apple Pencil double tap
- configurable toggle between Write and Erase or Write and Select

## 10. Editor UI

### Top bar
Left:
- back
- chart title

Center:
- undo
- redo

Right:
- concert / Bb / Eb toggle
- transpose
- export/share
- overflow menu

### Main canvas
- chart rendered in clean systems
- section labels above systems or measure groups
- chords inside measures
- roadmap objects attached cleanly
- cue text visually secondary but readable

### Bottom toolbar
- Select
- Write
- Erase
- Roadmap
- Text
- Layout

### Context inspector
#### Chord
- root
- quality
- extension
- alterations
- slash bass
- display style

#### RoadmapObject
- type
- span start/end
- repeat count
- convert subtype

#### SectionLabel
- text
- style
- anchor behavior

#### CueText
- text
- emphasis
- position

## 11. Layout requirements

The output must prioritize readability over decorative style.

### Requirements
- clean measure spacing
- consistent chord alignment
- section labels clearly separated from chords
- roadmap objects visually unambiguous
- cue text readable but secondary
- layout should avoid object collisions
- support one-page charts very well

### User controls
- auto-fit page
- force line break here
- keep section together (nice-to-have)
- loosen/tighten spacing (nice-to-have)

## 12. Transposition requirements

### MVP transposition
- concert
- Bb
- Eb

### Notes
- transposition must operate on structured chord data, not string replacement
- roadmap and section objects remain unchanged
- cue text remains unchanged unless explicitly edited by the user

## 13. Export requirements

### Export target
- PDF

### MVP expectations
- clean title/header
- readable systems and spacing
- stable PDF layout
- printable/sharable output
- share sheet integration

## 14. Persistence requirements

### MVP persistence
- local save of charts
- autosave behavior
- recent chart list
- no user account required

### Nice-to-have if low cost
- Files export/import support

## 15. Validation plan

### Prototype test scenario
User creates a chart that includes:
- Intro
- 4 bars of chords
- Verse
- 4 more bars
- repeat bracket with x4
- one cue text item
- one corrected recognition error
- PDF export

### Key evaluation questions
- Was it faster than the user’s current method?
- What did the app misread most often?
- Was correcting mistakes fast enough?
- Would the user trust the exported chart on a rehearsal or gig?

## 16. Enforcement notes

Do not expand the MVP into:
- full notation
- playback
- collaboration
- required backend services
- broad multi-platform scope

Do iterate within the MVP on:
- recognition thresholds
- correction UX
- layout tuning
- visual styling inside the clean professional direction
