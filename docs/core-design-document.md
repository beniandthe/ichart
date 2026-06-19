# iChart — Core Design Document

Status: Active for prototype and v1

## Purpose

This document defines the product boundary for iChart.

If another planning document conflicts with this document, this document wins.

## Product thesis

iChart should let a working musician create a clean, trustworthy chart at roughly the speed of handwriting on paper, while preserving the advantages of structured digital editing.

The app is chord-first, but not rhythm-blind.

Users must be able to show:
- where chords land inside a measure
- how long they last
- simple implied hits or syncopations
- roadmap flow that other players can follow quickly

## Core workflow

The target workflow is:

**open -> write -> recognize -> snap -> fix -> export**

In practical use, that means:
1. open a blank chart page
2. accept a default meter or write a time signature
3. create measures with barlines
4. write chord symbols naturally
5. add simple rhythmic values when placement matters
6. let the app snap the result into structured chart objects
7. correct any wrong interpretation quickly
8. export a readable chart for rehearsal, teaching, or gig use

## Product boundary

iChart is:
- an iPad-first chart editor for working musicians
- a stylus-first, local-first authoring tool
- an account-backed product with recoverable identity, profile, and subscription state
- a structured chord and roadmap chart builder
- a rhythm-aware chart tool that can show chord placement and implied hits
- a fast rehearsal and gig-prep utility with clean PDF export

iChart is not:
- full staff notation software
- melody or pitched note-entry software
- a general-purpose rhythm engraving tool
- a DAW companion or playback-first product
- a PDF annotation app first
- a cross-platform-first product at launch

## Core design rules

### 1. Chord-first, not notation-first

The main object in the app is the chord event inside a measure.

Rhythm support exists to clarify chord placement, duration, and hits. It must not pull the app into full notation editing.

### 2. Time-aware, not full engraving

Measures need real meter and beat awareness.

The app must support time signatures and limited rhythmic values well enough to show:
- two or more chord changes inside a measure
- syncopated entries
- held chords
- simple anticipations
- implied hits

But it does not need staff lines, noteheads tied to pitch, stems for melody, or multi-voice engraving.

### 3. Structured objects over raw ink

The chart must never exist as ink alone.

Every meaningful item becomes a structured object so the app can:
- transpose reliably
- edit quickly
- reflow layout
- export clean PDFs
- reinterpret recognition mistakes without losing context

### 4. Correction speed matters more than perfect recognition

Recognition can be imperfect if correction is fast and obvious.

The user should feel that the app helps them finish quickly, not that it forces them to fight the UI.

### 5. One-page readability is release-critical

The first version should optimize hard for readable one-page charts.

Multi-page sophistication is less important than getting the common rehearsal-chart case right.

### 6. Apple Pencil first, finger not blocked

Apple Pencil is the primary authoring tool.

Finger input should still support navigation, selection, editing, and simple fallback entry where it does not compromise clarity or reliability.

### 7. Ownership should feel fair

The pricing model must respect that musicians expect to own their local charts.

That means:
- the Basic account tier should let users feel the product before paying
- Basic should include the complete local chart-writing tool, PDF/export, and local autosave with a 3-chart cap
- account/auth/profile/subscription identity should be a base trust layer, not a paid feature
- Pro subscription should fund unlimited chart capacity, cloud chart backup/sync/restore, Forums, and other ongoing-service features
- local chart ownership should not disappear when Pro expires

## Primary users

- working bandleaders
- gigging rhythm section players
- session players needing readable roadmaps fast
- teachers creating simplified charts or handouts
- horn players and arrangers who need quick transposed chord charts

## V1 scope

Included in v1:
- iPad-first editor
- Apple Pencil input
- blank chart creation
- document key chosen at chart creation
- systems and measures
- time signatures
- barline creation
- recognition for common chord symbols
- beat-aware placement of chord events inside a measure
- limited rhythmic values attached to chords and hits
- document-wide font presets
- section labels
- cue text
- simple roadmap objects: repeat span, 1st/2nd endings, coda/To Coda, Segno, D.S./D.C., Fine, N.C., vamp count
- a top toolbar with fast access to font, transposition, notation, and text tools
- edit, reinterpret, move, and delete created objects
- concert / Bb / Eb views
- auto-layout for strong one-page charts
- PDF export and sharing

Explicitly out of scope for v1:
- full notation
- melody entry
- pitched note entry
- open-ended rhythm engraving unrelated to chord placement
- multi-voice notation
- playback engine or backing tracks
- collaboration
- desktop app
- iPhone-first authoring
- cloud-dependent chart authoring
- required chart cloud sync for local editing

## Monetization principles

Recommended launch business model:
- mandatory account for both Basic and Pro users
- Basic account tier for local-first chart authoring and local persistence
- Pro subscription for cloud chart backup/sync/restore and other service-backed features

The product should treat these as launch truths unless later user testing proves they are wrong:
- account/auth/profile/subscription identity is the base trust layer, not the paywall
- local chart authoring and local save should remain usable without chart cloud sync
- Basic should include all essential chart tools plus PDF/export, limited by a 3-chart local library cap
- subscriptions should fund unlimited chart capacity, cloud chart services, Forums, cross-device organization, shared libraries, setlists, version history, and AI-assisted cleanup if those features are built
- Pro expiration should pause cloud backup/sync and Forums clearly
- downgraded accounts with more than 3 local charts should choose which local charts to remove until only 3 remain
- downgrade pruning should delete user-selected overflow charts locally without creating cloud deletion tombstones; cloud backups remain recoverable until the grace period ends
- the app should remain useful offline after account/session state has been established

## Release-critical success criteria

The first meaningful prototype succeeds if a musician can:
- create a short chart with Pencil input
- set or change meter when needed
- place two or more chords inside a measure with simple rhythmic clarity
- correct one or two recognition mistakes quickly
- export a readable PDF
- conclude that the app is faster than their current rough-chart workflow

## Implementation consequences

The implementation must preserve separate structured concepts for:
- chart metadata
- systems and measures
- meter
- timed chord events
- section labels
- cue text
- roadmap objects
- raw ink groups and recognition candidates

The app should treat recognition as a translation layer into those objects, not as the source of truth.
