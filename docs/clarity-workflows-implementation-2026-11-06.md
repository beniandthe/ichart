# Clarity and workflow implementation

Date: November 6, 2026
Initial base: GitHub main `00f7901538074670251cd6626c1efa88a3bd1aec`
Integrated main: `fd7e4bbb3f898dbf806d85afaee43ea8c7ef58c3` (#103)
Branch: `codex/clarity-workflows-20261106`
Status: implementation under verification

## Result

The editor now teaches its immediate action through a short purpose, numbered steps and current context. Longer instructions live in a local Guide sheet. The same patch updates the related review sheets, accessibility hints, Quick Start and How To.

The editing flows now identify their target, group repeat and ending tasks, and explain unavailable layout operations. Library work adds cancellable staged chart creation, retrieval controls, direct PDF/setlist handoffs and specific recovery actions. Existing editing algorithms, recognition thresholds, source-ink ownership, PDF files, saved repeat notation and feature gates are retained.

## Changes in the recommended order

### Explainers and accurate scope

- `EditorToolGuidance` separates purpose, next steps, context and detailed help. Both supported chart layouts and Automatic/Manual use the same structure with their actual differences.
- Apple Pencil is named in writing guidance. Free Ink starts with page handwriting; staff notes remain handwritten and supported articulation conversions are explained separately.
- Guide opens outside the writing canvas. Its presentation suspends ink interaction and automatic commits. Returning to unchanged source refreshes ownership before restoring the original pending timing; changed source does not resume that episode.
- Recovery text uses a reserved instruction area, keeping the writing canvas in place when feedback changes.
- The editor paper ignores keyboard safe-area changes underneath sheets. The inline cue editor retains keyboard-aware layout; review sheets own their text-field scrolling. This addresses the observed Guide-close viewport resize rather than changing paper coordinates or ink.
- Rendering: Automatic/Manual is reachable directly in Write & Render and explicitly selectable in Settings, preserving the existing stored preference.
- The automatic status is the single review action. Clear Draft Ink remains separate and destructive.
- Both chord review flows now describe clearing the entire unrendered Write & Render layer. Rewrite This Chord is recommended only when present.
- Ending review describes whether Use Ending continues rendering or leaves an approved draft ready. Back to Writing preserves source ink.
- Header, ending, appearance, font and setup sheets have short visible task instructions with their actual Apply/immediate-save semantics.
- Primary editor tools expose active accessibility state. Their labels can wrap.

### Editing workflows

- Measure/range context is visible in the helper.
- Form Markers opens a staged measure/marker sheet with all nine existing point-marker choices, meanings and explicit destination. Add validates the exact target; it never falls back to another measure after confirmation.
- Repeats separates Repeat Measures, Add Ending and Manage. Repeat This Measure retains the former One Bar behavior. Standard/custom endings use the same label/range editor. The original page-selected first/second ending-range workflows remain available inside Add Ending.
- Layout provides separate Start New Row and Join Row Above actions, plus precise unavailable reasons for joining, moving, merging and evening widths. Availability calls the existing owning predicates.
- The document menu groups Chart Details, Key & Transposition, and Appearance & Layout without removing commands.
- Fonts starts with matched sets and a real renderer-backed preview. Customize reveals all existing individual font and notation choices; changes still apply immediately to the chart and PDF.

### Library and PDF workflows

- New Chart stages layout and setup locally. Back to Layouts and Cancel do not create a library item. Returning to the same layout retains draft setup choices. Final creation rechecks chart/project access and adds the completed chart, selection and project membership in one persisted batch.
- Layout choice shows real chart examples and plain descriptions.
- Charts, Projects, PDFs, Setlists and Add PDFs support title search and Recent/Name ordering where applicable.
- Search result selection has one visible scope for count and Delete. Hidden selections are counted separately and cannot be deleted by the visible-results action.
- PDF rows open from their main content, wrap metadata/title and group secondary actions under Actions.
- Saved PDF previews and library items offer Add to Setlist, including an existing-setlist chooser and atomic new-setlist-with-PDFs action.
- Missing references, plan access, missing files, locked PDFs and unreadable PDFs have distinct recovery text. Replacement retains setlist entry identity/order and leaves PDF files untouched. Existing Previous/Next Song navigation remains available.
- Forum Save PDF & Open states its persistent effect, then becomes Open Saved PDF during the session. Editing a submitted query retains its results until submission; explicitly clearing returns to browsing.
- Account/plan gates offer a direct next action. Verification failure has a reachable Contact Support link; authentication service behavior is unchanged.
- How To groups Start here, Common actions and Fix a problem while retaining the detailed restrictions. PDF import, setlist creation, offline reading and unavailable-song recovery have task entries.

## Audit coverage

| Audit items | Implementation |
| --- | --- |
| C01–C03 | Structured short helpers, local Guide, accurate clearing scope, Pencil requirement and Free Ink's general purpose. |
| C04–C08 | Explicit target/range, reachable verification support, direct rendering choice, single recovery action and accurate ending-approval effect. |
| C09–C13 | Repeat/ending task groups, grouped document menu, unavailable-action reasons, Fonts preview/customization and sheet instructions. |
| C14–C18 | Staged cancellable creation, real layout examples, search/sort, PDF-to-setlist handoff and adaptive PDF rows. |
| C19–C22 | Specific unavailable-PDF recovery, accurate forum save label, submitted-search continuity and direct account/plan actions. |
| C23 | Corrected after owning-source review: transposition is an immediate cumulative action, so selected-interval checkmarks were removed. |
| C24–C25 | Semantic active-tool state and task-organized How To, including PDF/setlist/offline recovery. |

Layout and Fonts examples use the app's renderer. The writing Guide includes a chord-spacing/chord-repeat example and layout-specific gesture rules. This patch does not claim a complete visual tutorial library or first-time-user acceptance study.

## Correction to the audit

The original audit's C23 described Transpose as a persistent selected interval. Implementation review of `ChartEditing.setChordTranspositionSemitones` showed that each nonzero choice immediately changes chord pitches and resets the display offset. The menu is an action menu. This patch removes misleading selection checkmarks and explains cumulative pitch changes; it does not introduce a retained interval or change pitch behavior. Reset Display Offset retains the existing reset operation and does not promise to undo previous transpositions.

Chart Key also transposes chart chords and key changes. Instrument changes the display view. The current guidance preserves these distinctions.

## Preserved boundaries

- Handwritten chord-repeat `%` / dot-slash-dot remains supported.
- Handwritten bar-and-dot measure/range repeat ingestion remains retired; those operations use Tools > Repeats.
- Ordinary barlines and ending brackets remain supported with their current layout-specific constraints.
- Dedicated rhythm recognition and personalization/ML work remain gated/parked.
- Existing chart, import manifest and setlist formats remain unchanged. PDF replacement changes a reference, not the underlying file.
- Main advanced during implementation. The branch incorporates merged #103 hardening, including unread-library quarantine, paginated Forum search, saved-ink indexing and PDF manifest/export consistency. Backend changes are inherited from main; no deployment was performed here.
- No physical-device install, production-service change, publishing or release is part of this implementation.

## Verification

The app and test target compile with the generated Xcode project. A test-only accessibility identifier cast was corrected after the first test build.

The regression matrix and runtime observations will be recorded here after verification completes. Simulator/replayed/injected evidence remains separate from physical Pencil acceptance, saved-state readback and production behavior.

Frozen-result UI fixtures now disable their reader once through an internal dependency that defaults to enabled in the app. Repeated layout-time toggles had cancelled fixture serialization work. Manual fixture readiness is bound to actual visible source and represented claims; the production source-consumption checks remain in use. Delayed-review coverage returns to writing before adding source ink and distinguishes injected callbacks from physical Pencil input.
