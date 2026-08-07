# iChart V1.1 Release Plan

Status: active planning source of truth
Created: 2026-08-03
Current scope: key signatures, key-aware enharmonic chord spelling, and
additional chord coverage

This document turns `docs/ichart-v1-1-roadmap.md` into an execution plan. If a
V1.1 implementation decision conflicts with the roadmap, update the roadmap
first, then reflect the execution change here.

## Release Call

V1.1 is a narrow musical-control release. It should feel like one connected
upgrade:

- Charts know their keys.
- Key signatures render where chart readers expect them.
- Modulations change the active key at the right spot in the chart.
- Chords spell themselves according to the active key unless the user has chosen
  a specific enharmonic spelling.
- The chord system covers more obscure and complex chord types, with an internal
  coverage printout that keeps parser, renderer, and QA expectations visible.

Rhythm notation input is not part of V1.1. It is parked for V1.2 so V1.1 can be
debugged and released around one musical model: key context and chord spelling.

## Scope

### 1. Official Key Signature Incorporation

- Add chart-start key selection to new-chart setup.
- Persist chart key in saved chart data with backward-compatible defaults for
  existing V1.0 charts.
- Render key signatures at the front of stanzas in the editor.
- Render the same key signatures in PDF export.
- Support chart key changes after creation.
- Add modulation points so the active key can change mid-chart.
- Make active key available to chord spelling and transposition code.

### 2. Enharmonic Chord Spelling

- Resolve chord spelling from the active key by default.
- Preserve the user's explicit chord spelling when the input or later edit makes
  that spelling intentional.
- Let users tap a rendered chord and choose an enharmonic spelling.
- Keep chart-wide transposition and modulation spelling coherent in the
  destination key.
- Save, reopen, and export chord-spelling overrides without silent rewriting.

### 3. Additional Chord Coverage

- Produce an internal printout of all currently supported chord types before
  expanding coverage.
- Use `docs/ichart-v1-1-chord-coverage-baseline.md` as the starting V1.1
  coverage printout, then refresh it as chord families are added.
- Use that printout as the QA checklist for newly added chord families.
- Add obscure and complex chord symbols through the parser and compendium before
  treating them as supported recognition output.
- Verify every newly supported family through render, persistence, and export.
- Keep ambiguous handwriting routed through confirmation instead of pretending
  every spelling can be inferred automatically.

## V1.2 Parking Lot

Select-input rhythm notation moves to V1.2:

- rhythm values
- rests
- dots
- ties
- grouped beaming
- deterministic rhythm-map creation without handwriting recognition

The V1.1 app keeps Free-Write as the rhythm notation path for personal marks,
cues, articulations, and working-musician shorthand.

## Implementation Order

1. Inventory current chord coverage.
2. Add the internal chord-coverage printout command or test artifact.
3. Design the key-signature data model: chart key, modulation points, and
   compatibility defaults.
4. Thread active-key resolution through layout, editor rendering, PDF export,
   and chord display.
5. Add the chord enharmonic spelling model and tap-to-change interaction.
6. Add new chord families with parser, compendium, renderer, persistence, and
   export coverage.
7. Run simulator and physical-iPad QA across new-chart setup, key changes,
   modulation, chord edits, save/reopen, and PDF export.
8. Package V1.1 only after the release gate proves the three scoped pillars
   together.
9. Create the next App Store version metadata update with the canonical search
   package from `docs/app-store-testflight-metadata-draft.md`.

## Version Discipline

Keep release versions tight and focused:

- Each PR should name the slice it proves.
- Avoid unrelated UI redesign, marketing copy, Supabase changes, and App Store
  metadata changes during implementation PRs unless the slice explicitly
  requires them.
- Treat the App Store search metadata update as a final V1.1 release-packaging
  step, after the binary scope is proven.
- Include a build-specific App Store/TestFlight update note for every submitted
  build so users and testers can see the fixes, patches, and active update
  focus represented by that build.
- Do not mix V1.2 rhythm-input work into V1.1 branches.
- If a release problem appears, the V1.1 history should make it clear whether
  the likely source is key data, modulation, chord spelling, or chord coverage.

## App Store Metadata Handoff

When V1.1 is ready for App Store submission, update the product page metadata
with this canonical discoverability package:

- App name: `iChart: Music Notation`
- Subtitle: `Handwritten charts for iPad`
- Keywords: `chord,lead sheet,pdf,band,setlist,gig,musician,pencil,teacher,horn,wedding,transpose,rehearsal`

Keep the live Promotional Text aligned with the same positioning:

> Handwrite reusable music charts on iPad, then transpose, organize, and export when the gig changes.

This metadata change belongs with the next app version because the released
V1.0 product-page name, subtitle, description, and keywords are locked in App
Store Connect.

Before sending a build to App Store Connect, also update the per-build release
notes in `docs/app-store-testflight-metadata-draft.md`. Build 37 / V1.1 should
ship with its public "What's New" text plus TestFlight/review-facing notes for
the key-signature, modulation, chord editing, tutorial, and home-stamp updates.

## Release Gates

V1.1 cannot be called ready until these gates pass:

- The internal chord-coverage printout exists and is reviewed.
- Key signatures render consistently in editor and PDF export.
- Modulations update active key and chord spelling at the expected chart
  locations.
- User-selected enharmonic spelling survives save, reopen, transpose, and export.
- Newly added chord families parse, render, persist, reopen, transpose where
  applicable, and export.
- Existing V1.0 charts open without requiring a key choice or corrupting stored
  chord symbols.
- SwiftPM tests pass.
- Focused simulator QA passes on Simple Chord Sheet and Rhythm Section Sheet.
- Physical-iPad Pencil QA passes for chord entry, chord tapping/editing, key
  setup, modulation controls, and PDF export.
