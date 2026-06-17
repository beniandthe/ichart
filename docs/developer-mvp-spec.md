# Smart Chart — Developer-Facing MVP Spec

Status: Active for prototype and v1
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
- Support meter and simple rhythm well enough to show where chords land in a measure.
- Keep correction fast enough that imperfect recognition is acceptable.
- Generate charts that look trustworthy and readable.

### Non-goals
- Full staff notation
- Melody or pitched note entry
- General-purpose rhythm engraving
- Playback or backing tracks
- Realtime collaboration
- Desktop parity
- Required cloud sync for launch

## 3. Platform target

### V1 target
- iPadOS only for primary authoring
- Apple Pencil is first-class input
- Finger input supports navigation, selection, editing, and simple fallback authoring where it remains reliable

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
- Supabase-backed account identity, email verification, password recovery, profile, and subscription state are required for production
- Local-first architecture
- No required chart cloud sync for local authoring
- Optional analytics and crash tooling only if lightweight and privacy-appropriate

## 5. MVP scope

### Included
- Blank chart creation
- Document key input at chart creation
- Strong one-page chart layout
- Systems and measures
- Time signatures
- Apple Pencil input on chart canvas
- Document-wide font preset selection
- Recognition of common chord symbols
- Recognition of time signatures
- Recognition of limited rhythmic values tied to chord placement and hits
- Recognition of section labels
- Recognition of cue text
- Recognition of simple roadmap objects
- Object selection, edit, delete, move, and reinterpretation
- Concert / Bb / Eb display
- PDF export

### Excluded
- Full notation
- Melody entry
- Staff lines and pitched noteheads
- Open-ended note and rest entry unrelated to chord timing
- Tuplets and advanced engraving rules
- Audio playback
- Realtime collaboration
- OCR or photo import
- Required cloud sync
- Desktop app
- Marketplace or social features

## 6. MVP user stories

- As a bandleader, I want to write a quick chart naturally so I can hand a readable version to my players.
- As a gigging musician, I want to clean up a rough chart fast so I can use it at rehearsal.
- As a player, I want to show syncopated chord entries or implied hits without opening full notation software.
- As a teacher, I want to create simplified readable chart handouts.
- As a horn player or bandleader, I want to generate Bb and Eb versions without rewriting the chart by hand.

## 7. Core object model

The chart must be represented as structured data, not just raw ink.

### 7.1 Chart
- id
- title
- chartType
- documentKey
- documentFont
- pageSize
- orientation
- defaultTranspositionView
- defaultMeterNumerator
- defaultMeterDenominator
- stylePreset
- createdAt
- updatedAt

### 7.2 System
- id
- index
- measureIDs
- spacingMode
- lineBreakRule

### 7.3 Measure
- id
- index
- meterOverrideNumerator (optional)
- meterOverrideDenominator (optional)
- beatGridPreset
- barlineAfter
- chordEventIDs
- cueIDs
- roadmapIDs
- layoutMetadata

### 7.4 ChordEvent
- id
- measureID
- root
- accidental
- quality
- extensions
- alterations
- slashBass
- startBeatPosition
- durationValue
- rhythmPlacement
- tieOut (optional)
- hitStyle (optional)
- displayStyle
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
- anchorSystemID (optional)
- placement
- displayText (optional)
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

#### Time signatures
Examples:
- 4/4
- 3/4
- 6/8
- 12/8

#### Rhythmic values for chord timing
Examples:
- quarter
- eighth
- half
- dotted quarter
- dotted half
- tied continuation
- simple hit marks if low-cost and readable

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
- at the beginning of a chart or meter change zone => time signature first
- inside a measure main writing zone => chord first
- directly above or below a chord event => rhythm attachment first
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
#### Pencil write in measure
- create chord candidate

#### Pencil rhythm value near an existing chord
- attach or update chord timing

#### Pencil time signature near the chart start or meter change position
- set or update meter

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

### Top tool strip
- Fonts menu
- Transpose menu
- Notation menu
- Text menu

Notes:
- Fonts menu should support document-wide font changes first
- selection-aware font overrides can come after core editing is stable
- Transpose menu should expose document key and concert / Bb / Eb views
- Notation menu should create movable roadmap symbols such as Coda, Segno, D.S. al Coda, and Fine
- Text menu should create section labels and cue text quickly

### Main canvas
- chart rendered in clean systems
- section labels above systems or measure groups
- chords inside measures
- rhythmic values aligned clearly with the chord events they explain
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
#### ChordEvent
- root
- quality
- extension
- alterations
- slash bass
- start beat position
- duration value
- rhythm placement
- tie out
- display style

#### Measure
- meter
- beat grid preset
- barline type

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
- beat-aware placement of chords inside measures
- consistent chord alignment
- rhythmic values visually tied to the chord they clarify
- section labels clearly separated from chords
- roadmap objects visually unambiguous
- cue text readable but secondary
- layout should avoid object collisions
- support one-page charts very well

### User controls
- auto-fit page
- force line break here
- show or hide beat guides if helpful
- keep section together (nice-to-have)
- loosen/tighten spacing (nice-to-have)

## 12. Transposition requirements

### MVP transposition
- concert
- Bb
- Eb

### Notes
- transposition must operate on structured chord data, not string replacement
- chord timing and rhythmic placement remain unchanged
- roadmap and section objects remain unchanged
- cue text remains unchanged unless explicitly edited by the user

## 13. Export requirements

### Export target
- PDF

### MVP expectations
- clean title/header
- readable systems and spacing
- stable PDF layout
- rhythmic placement preserved in export
- printable/sharable output
- share sheet integration

## 14. Persistence requirements

### MVP persistence
- local save of charts
- autosave behavior
- recent chart list
- account required for production identity, password recovery, profile, and subscription state
- chart files remain local-first; chart cloud backup/sync is not required for local editing

### Nice-to-have if low cost
- Files export/import support

## 15. Monetization requirements

### Launch recommendation
- mandatory Basic account for local-first chart authoring
- Pro subscription for cloud chart services and other ongoing-service value

### Basic account tier
- 3-chart local library cap
- complete local chart creation and editing tools
- PDF export and sharing
- local autosave
- recent chart library
- verified email, password recovery, profile, and subscription identity

Recommended initial chart cap:
- 3 local charts

### Pro subscription tier
- cloud chart backup
- chart restore after reinstall or new iPad sign-in
- future cross-device chart sync
- unlimited local charts
- Forums access

### Later Pro expansion candidates
Only expand recurring service scope after the core cloud chart service is stable:
- cross-device chart organization beyond backup/restore
- shared band libraries
- setlists
- version history
- AI-assisted cleanup or recognition upgrades

### Entitlement behavior
- Basic users must be able to reopen their existing local charts
- account/auth/profile is mandatory base infrastructure, not a paid feature
- Pro gates cloud chart services because they create ongoing operational cost
- expired Pro should remove or pause only paid cloud/service-backed features such as cloud backup/sync and Forums
- downgraded Basic accounts over the 3-chart cap must choose which local charts to remove until only 3 remain
- downgrade pruning deletes user-selected charts locally but does not create remote deletion tombstones
- remote chart backups should receive a clear grace period, recommended default 30 days, before cloud retention cleanup
- charts removed locally during downgrade pruning remain in cloud backup until the grace period ends
- restore purchases must be supported when monetization ships

## 16. Validation plan

### Prototype test scenario
User creates a chart that includes:
- a 4/4 time signature
- Intro
- one measure with two chord events and a visible rhythmic difference between them
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
- Did the limited rhythm support feel sufficient without becoming cumbersome?
- Would the user trust the exported chart on a rehearsal or gig?

## 17. Enforcement notes

Do not expand the MVP into:
- full notation
- melody entry
- pitched note entry
- playback
- collaboration
- required backend services
- broad multi-platform scope

Do iterate within the MVP on:
- time signature handling
- chord timing representation
- recognition thresholds
- correction UX
- layout tuning
- visual styling inside the clean professional direction
