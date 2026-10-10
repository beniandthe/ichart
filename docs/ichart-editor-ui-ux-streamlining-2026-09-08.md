# iChart Editor UI/UX Streamlining Pass

Date: 2026-09-08

Status: active implementation and physical-iPad acceptance

## Goal

Make both Simple Chord Sheet and Rhythm Section Sheet faster to understand and operate without removing, weakening, or changing the meaning of any editor function. The page remains the primary surface. Controls appear because they are frequent, because the current selection needs them, or because the user explicitly opens a clearly labeled secondary group.

## Evidence

### Current product surface

The current editor can stack four command layers above the page:

1. A permanent nine-item strip: Settings, Edit, Measures, Repeats, Form Markers, Text, Time, Chord, and Free-Write.
2. A persistent workflow explainer in Chord mode.
3. An active-tool strip that can contain up to ten actions plus Done.
4. A separate selected-object action strip.

This makes primary modes, document settings, object creation, and contextual correction look equally important. Several controls also describe implementation modes rather than the musician's immediate task.

### Aggregate telemetry

Read-only production telemetry was inspected on 2026-09-08. Since `editor.mode_changed` began on 2026-08-14, it recorded 1,638 transitions across 31 installations and 223 sessions. Entries into the two shipped chart editors were:

| Mode | Recorded entries |
| --- | ---: |
| Chord entry | 386 |
| Free-Write | 185 |
| Measure edit | 178 |
| Header handwriting | 75 |
| Repeats | 26 |
| Text | 14 |
| Time signature | 9 |

This is a ranking signal, not a complete usage census. Form-marker menu actions are not instrumented as mode changes, text can be edited through object selection, older builds did not emit every current event, and development-device activity can be present. Separate event totals—3,495 ink persistence events and 1,681 chord-preview updates—reinforce that direct writing is the central editor behavior.

### External guidance

- Apple says a toolbar should prioritize the commands people most often need, minimize groups, and move lower-priority commands into an overflow or More menu: <https://developer.apple.com/design/human-interface-guidelines/toolbars>
- Apple recommends contextual controls for modal editing states and at least 44-by-44-point hit regions: <https://developer.apple.com/design/human-interface-guidelines/buttons>
- Apple Pencil guidance says a mark should appear when Pencil touches the screen and controls must remain operable with Pencil: <https://developer.apple.com/design/human-interface-guidelines/apple-pencil-and-scribble>
- Apple's iPad SwiftUI guidance recommends primary and secondary toolbar actions instead of rendering every command at equal priority: <https://developer.apple.com/videos/play/wwdc2022/110343/>
- Nielsen Norman Group's progressive-disclosure guidance says frequent actions belong in the first layer, specialized actions belong in one obvious secondary layer, and deeper nesting should be avoided: <https://www.nngroup.com/articles/progressive-disclosure/>
- forScore's current iPad annotation model keeps score content primary, replaces controls contextually during annotation, and adapts lower-priority controls at narrower widths: <https://forscore.co/documentation/annotation/>
- Dorico for iPad separates stable mode access from mode-dependent secondary controls: <https://www.steinberg.help/r/A4_2Z~ZdAgq~gL1GCE2z_w/MmFU_8V7u0uxvo8oqEWXmw>

## Information Architecture

### Document bar

The navigation bar remains one row:

- Back
- Chart title as a labeled document menu
- Export PDF

The chart-title menu contains the document-wide setup actions formerly under Settings: initial setup, Add Page, typed or handwritten header, chart key and selected-measure key change, instrument, transposition, style, fonts, and engraving. Export remains visible as the primary document action instead of being duplicated inside the menu.

### Primary editor tools

The always-visible editor row contains five controls:

- Select
- Chords
- Ink
- Measures
- Tools

Select, Chords, Ink, and Measures are direct actions. Tools is a labeled menu, not an unlabeled mystery icon. It contains the lower-frequency systems in two sections:

- Structure: Repeats, Time Signature, and Rhythm when the dedicated Rhythm tool ships for the chart style.
- Annotate: Text and Form Markers.

### Context row

Only one contextual row can appear under the primary row:

- In an active tool, it contains the tool identity/instruction, state-relevant actions, and one trailing Done action.
- In Select, it contains actions for only the selected Chord, Barline, Text, Marker, or Measure.
- The permanent four-line Chord Workflow card is removed from ordinary editing. The guided walkthrough continues to provide full first-use instruction.

## Capability Preservation Matrix

| Existing capability | Streamlined location |
| --- | --- |
| Select and move rendered objects | Select; selected-object context row |
| Correct/delete chord | Chord selection context row |
| Delete committed chord barline | Barline selection context row |
| Add, stack, prepend, double-bar, merge, delete, range-delete measures | Measures contextual Add/Layout/Delete groups |
| New Row, Join Row Above, Move to Row Below, Even Row | Measures contextual Layout group; select a row's first measure to move it up or its last measure to move it down |
| One-bar repeat, repeat span, first/second endings, removal | Tools > Repeats; state-relevant repeat context row |
| Coda, To Coda, Segno, D.S., D.S. al Coda, D.C., D.C. al Fine, Fine, N.C. | Tools > Form Markers; selected-marker context row |
| Add/edit/resize/delete text | Tools > Text; Text context row; selected-text context row |
| Time-signature changes and scope | Tools > Time Signature; existing target and scope flow |
| Structured Rhythm tool, when enabled | Tools > Rhythm; existing Rhythm context row |
| Chord handwriting, preview, correction, Render, Discard | Chords; Chord context row |
| Persistent page handwriting and erasing | Ink; Ink context row |
| Typed/handwritten header | Chart-title document menu and header selection |
| Setup, key, key change, instrument, transpose, style, fonts, engraving | Chart-title document menu |
| Add Page | Chart-title document menu |
| Export PDF | Visible navigation action |

## Interaction Rules

1. Switching among Select, Chords, Ink, and Measures remains a single tap.
   Switching directly from one active tool to another is also allowed once setup is complete; Done remains a clear return to Select, not a required intermediate tap.
2. Selecting an object never requires entering an edit mode first.
3. Lower-frequency tools are no more than one labeled Tools menu away; Form Markers may use one named submenu because it contains nine peer symbols.
4. Text mode allows measure targeting, then exposes Above, Below, and Remove in the same contextual row.
5. Multi-step operations show only the next valid actions. A pending repeat span shows End Repeat and Cancel instead of every repeat command; a pending delete range shows Delete To and Cancel.
   Chord and Rhythm preview status appears only after ink creates something to review; an empty "waiting" panel does not occupy the command row.
6. Destructive commands remain red, last in their group, and disabled when invalid.
7. Every visible control has at least a 44-point hit target, a text accessibility label, and a stable portrait/landscape location.
8. No chart mutation, renderer coordinate, PencilKit persistence path, recognition rule, or PDF output contract changes solely to support this UI pass.

## Verification Gates

### Automated

- A command-placement policy test proves every editor system remains reachable and the primary row never exceeds five controls.
- Mode-state tests prove Text can select measures, ready charts allow direct tool-to-tool switching, and document-wide mutations remain locked during ink-critical modes.
- Guided-tour source-contract tests reflect the new labels and paths.
- Focused editor tests pass with a nonzero selected-test count.
- The complete test suite passes with explicit skips separated from failures.
- Portrait and landscape screenshots are inspected at current iPad dimensions.

### Physical iPad

Use both Simple Chord Sheet and Rhythm Section Sheet. For each:

1. Switch Select -> Chords -> Ink -> Measures directly.
2. Open Tools and enter Repeats, Time Signature, and Text.
3. Select measures and complete Join Row Above, Move to Row Below, and Even Row Widths, plus one Add and one Delete workflow.
4. Add, move, resize, and delete Text and a Form Marker.
5. Write and erase chord ink; Render and Discard remain visible and responsive.
6. Write and erase persistent ink.
7. Open the chart-title menu and verify every former Settings command.
8. Rotate portrait -> landscape -> portrait during Select, Chords, Ink, and Measures.
9. Export and confirm page count/layout are unchanged.

Acceptance requires the user to confirm that common work is materially simpler on the installed build. A green test suite or screenshot alone is not physical usability acceptance.

### Typed-header and alignment follow-up

The first physical pass confirmed that the simplified editor flow was materially better, then exposed two shared-chrome defects:

- The per-field keyboard affordance only reassigned SwiftUI focus. When iPadOS retained first-responder focus while hiding the software keyboard, tapping the same button could be a no-op.
- The chart title was laid out between a 44-point Back control and a much wider Export PDF control. It was therefore centered only in the leftover space, while the five-command system row was centered on the screen.

The first follow-up combined forced first-responder focus with a custom Apple input-assistant strip. Physical-iPad review showed that this still produced overlapping entry paths: row tapping, automatic keyboard presentation, and a second tool strip. The final typed header uses standard SwiftUI `TextField` controls only. It has no automatic focus, no custom input assistant, and no row-level keyboard controls. The sheet opens quietly; tapping Title, Composer / Credit, or Style Note opens the standard Apple keyboard, where iPadOS owns Dictation and Return. Return advances Title -> Composer / Credit -> Style Note, and the last field uses Done. The three fields remain one explicit stack with two full-width dividers. Typed versus Handwritten is selected once in the chart-title Header menu; the Typed sheet no longer repeats that choice with a nested Header Mode picker.

The document bar now uses three equal-width columns for Back, chart title, and Export PDF. This gives the title the same exact horizontal center axis as the five-command system row in portrait and landscape.

The Header editor now uses a single 330-point presentation detent. This removes the empty lower half of the default iPad form sheet and keeps Cancel, Header, Apply, and all three fields together in one compact centered surface. The standard Apple keyboard, Dictation, Return, and hardware-keyboard assistant remain the only text-input path. Their exact shortcut-pill position is owned by iPadOS and is not repositioned or duplicated by iChart.

### Symmetric row-boundary follow-up

Measures > Layout now supports the missing reverse of Join Row Above. Select the last measure of an upper system and choose Move to Row Below; iChart shifts the system boundary backward by one measure and automatically evens both affected rows. The same action is available in Simple Chord Sheet and Rhythm Section Sheet without adding another primary tool or another context row.

The move preserves the selected measure's identity and attached chart content. It remains disabled when the selection is not the last measure in its row, no lower row exists, the source row would become empty, the move would cross a page or key-change boundary, the Simple-sheet destination would exceed its measure cap, or a Rhythm-sheet row would have to shrink below the minimum editable width.

## Current Verification

- Final post-cleanup complete simulator suite: 1,230 tests selected; 1,186 passed, 44 intentional environment or fixture skips, and 0 failed. The result was confirmed from `/tmp/ichart-uiux-full-DJJwnY/iChartFull.xcresult`, not inferred from console text.
- Focused editor/state/help gate before the typed-header follow-up: 207 tests executed, 2 intentionally skipped, 0 failures.
- Final single-flow typed-header/alignment focused gate: 10 tests executed, 0 skipped, 0 failures. This includes Return sequencing, symmetric navigation geometry, the three-field/two-divider structure, and source contracts proving there is no forced focus, custom UIKit field, input assistant, redundant row control, or nested Header Mode selector.
- Complete simulator suite after the compact Header follow-up: 1,221 tests selected; 1,177 passed, 44 intentionally skipped, and 0 failed.
- Move-to-row-below focused gate: 8 tests selected; 8 passed, 0 skipped, and 0 failed. The tests cover Simple and Rhythm row movement, identity/content preservation, equalization of both rows, atomic failure, and page/key-boundary guards.
- Complete simulator suite after adding Move to Row Below: 1,228 tests selected; 1,184 passed, 44 intentionally skipped, and 0 failed.
- Simple Chord Sheet and Rhythm Section Sheet were visually inspected in portrait and landscape with the same five-command primary row.
- In the live Simple-sheet simulator fixture, Move to Row Below was disabled for an ineligible selection, enabled for the last measure of the upper row, and visibly changed an even 4+4 layout into an even 3+5 layout while retaining the moved-measure selection. In the live Rhythm fixture, the same flow visibly rebalanced 5+3 into 4+4 with full staff lines and signature context intact.
- Direct switching was exercised across Ink, Measures, Repeats, and Text; the chart-title document menu and compact Add Text presentation were also inspected.
- The first hands-on pass reported that the simplified flow was "really good" and identified the typed-header and centering follow-ups above.
- The final single-flow build signed successfully with the Apple Development identity, passed strict code-signature verification, and installed in place on Ben's iPad as iChart 1.2.1 (51).
- Immediately before and after the compact-Header installation, `Library/Application Support/iChart/library-state.json` was copied from the device and matched byte-for-byte (SHA-256 `f6fab2933c7540388941bcdae15c4ff8368c55781d7ed57fab9b264311a07783`; 365,309 bytes; 3 charts). The app launched successfully after installation.
- The Move-to-Row-Below build signed with the Apple Development identity, passed strict code-signature verification, installed in place on Ben's iPad, and launched successfully. The current three-chart device library matched byte-for-byte immediately before and after installation (SHA-256 `97429e71b33f69975303ef8cb6df1c18416ed918e0787d26fe4a9f6b9c5899a2`; 297,551 bytes).
- Final hands-on acceptance of the tap-to-open keyboard flow, restored separators, title/system-row alignment, removal of the nested Typed/Handwritten control, and compact Header height remains pending. Treat that as a separate gate from simulator, unit-test, signing, installation, launch, and persisted-data proof.
- Final hands-on acceptance of Move to Row Below in both Simple and Rhythm charts remains pending. Select the last measure in an upper row, then use Measures > Layout > Move to Row Below and confirm that the measure moves with its contents while both rows remain readable.

## Quick Start Audit

The editor simplification exposed the tutorial as a second, older information architecture layered on top of the new one. Before this audit, starting the guide meant navigating 18 live walkthrough stops, a separate four-item Chord Workflow card, and 15 written tutorial substeps grouped into four disclosure sections. The live enum still contained dozens of inactive microsteps for individual buttons. The result taught the control surface one command at a time instead of teaching the musician's chart-making loop.

The revised learning system has two deliberately different layers:

- **Quick Start** is optional, short, and interactive. It teaches one usable chart through eight live milestones: create a page, write four chords, render them, shape the form, add a cue, review, export, and finish.
- **How To** is the complete reference. It retains Select, chord previews and corrections, Ink, all Measure and Layout actions, Repeats, Time Signature, Text, Form Markers, Simple and Rhythm sheet differences, document settings, and export.

The Help version of Quick Start is now a flat five-move preview rather than another accordion-based manual. The editor rail is one compact surface with the current outcome, one target, one forward action, and one close control. It no longer displays a guardrail card, a large target panel, an additional Chord Workflow lesson, or a second labeled Skip Tour button. Advanced commands stay discoverable in contextual controls and How To instead of being compulsory tutorial stops.

The live path remains Simple Chord Sheet-specific because chord handwriting and Render Chords form its core task loop. Shared editor concepts and the Rhythm Section Sheet's distinct capabilities remain fully covered in How To; the guide does not pretend the two sheet types have identical workflows.

### Pen responsiveness cleanup

The Page Settings pen-responsiveness slider was removed after physical-iPad review showed no perceptible change across its range. Source tracing confirmed that it adjusted only a 4-to-30-millisecond debounce before post-stroke persistence or recognition timers; it never altered PencilKit's live mark rendering. The editor now uses one internal 17-millisecond coalescing cadence, preserving the former balanced scheduling behavior without exposing a misleading user preference or retaining chart-style-specific behavior.

- The focused interaction-policy gate selected 196 tests: 194 passed, 2 intentional fixture skips, and 0 failed.
- The Help/source contract selected and passed 1 test, including absence checks for the removed setting, storage key, and canvas parameter.
- The final signed device build, including the settings removal and Help wording cleanup, passed strict code-signature verification, installed in place on Ben's iPad, and launched successfully as iChart 1.2.1 (51).
- The device chart library matched byte-for-byte before and after that final installation (SHA-256 `c26811533348bb563a478994caffa477fd046de395f4f1910f8c0d70368d7d69`; 311,217 bytes).

Apple's current onboarding guidance supports a fast, optional, interactive introduction and recommends teaching features in context rather than explaining too much up front. TipKit likewise positions tips as sparse, contextual assistance rather than a replacement for a whole guided tour. The revised split follows that model: Quick Start gets a first chart made, while How To answers specific later questions.

### Quick Start interaction contract

1. Setup cannot advance until Create Blank Page succeeds.
   Guided Simple-sheet setup prepares four starting measures automatically so the following four-chord exercise is immediately possible; ordinary setup keeps its normal default.
2. Chord preview success advances writing to review-and-render; a musician can also continue manually if recognition is not the lesson they need.
3. Rendering, a successful Measure mutation, adding Text, returning to Select, and a successful export each advance their matching milestone.
4. Every non-setup milestone has a predictable forward action so the guide never traps the musician inside an optional lesson.
5. The close control is always available and labeled End Quick Start for accessibility.
6. Completing or closing the guide changes no chart capability and does not remove the full reference from Help.
7. At the Basic chart limit, Help explains that Quick Start needs one free chart slot and does not launch a guide that points at a disabled New Chart action.

### Quick Start verification

- The final focused source and behavior gate selected 13 tests: 13 passed, 0 skipped, and 0 failed.
- The behavior tests prove the exact eight-step order, progress labels, terminal state, core targets, optional exit, and Export skip behavior.
- The setup-policy test proves guided Simple creation supplies at least four measures without changing the ordinary one-measure default.
- The Help source contract proves the five-move summary exists, the old tutorial disclosures and guardrails are gone, and the complete How To reference still names every shipped editor system and the four row-layout actions.
- The complete simulator suite selected 1,231 tests: 1,187 passed, 44 intentional environment or fixture skips, and 0 failed.
- The Help overview, chart-type picker, setup banner, and in-editor rail were visually inspected in portrait and landscape. The rail remained one compact row in both orientations, and the visible guided setup stepper opened at four measures.
- The final Debug device build signed with the Apple Development identity, passed strict code-signature verification, installed in place on Ben's iPad, and launched successfully.
- Immediately before and after installation, `Library/Application Support/iChart/library-state.json` was copied from the device and matched byte-for-byte (SHA-256 `9e78c335dd5c4d8f971e3053abbc810a7ae9648bc384b34896cfd5471529049a`; 297,111 bytes).
- Physical-iPad usability remains a separate gate; simulator, installation, launch, and automated results are not final hands-on acceptance.

## Completion Audit

As of September 9, 2026, source implementation is complete for the five-control hierarchy, direct mode switching, contextual actions, complete secondary Tools menu, compact single-flow typed Header editor, symmetric navigation alignment, Move to Row Below, simplified Quick Start and complete How To reference, and removal of the misleading pen-responsiveness preference. The capability-placement policy covers every shipped editor system, the source contracts cover every documented command family, the focused behavior gates are green, the final complete suite is green, and the exact source installed and launched on the physical iPad without changing its chart library.

The full goal is not yet closed because physical usability acceptance cannot be inferred from tests or installation. The user has accepted the overall first-pass direction and the simplified tutorial on-device, but the final compact Header flow and Move to Row Below still need explicit hands-on confirmation in both chart styles. An export/layout spot check after rotating both styles also remains part of the requested physical acceptance pass.
