# Clarity and visual refinements — November 6, 2026

This pass refines the clarity build after the Build 147 Write & Render entry repair. It addresses the user's requests for more centering, readable Measure Layout explanations, visible Free Ink symbol guidance, removal of file-size labels, and wider use of the existing orange/gold accent.

## Centering and visual hierarchy

Short tool explainers now center their purpose, context, and next steps. The Guide affordance is balanced so the title remains centered on the page. At accessibility text sizes, purpose and context use the full width and Guide moves to its own centered row with a natural size and a minimum 44-point target. The existing reserved instruction area remains independent of recognition feedback; the writing canvas should not move when feedback changes.

Shared sheet introductions, chart setup headings and layout summaries, appearance/font choices, Form Marker choices and placement summaries, and ending preset controls are centered where this improves scanning. Library, PDF, setlist, and chart-creation introductions and empty states receive the same treatment. Editable data fields, navigation controls, longer reference paragraphs, and content that benefits from a leading alignment retain it.

The existing `IChartTourStyle.orange` and `orangeSoft` colors now appear in warm instruction panels, section accents, icons, borders, and choice cards. Shared warm panels adjust their intensity for dark appearance. Final visual review also gives the disabled New Chart label an explicit theme-aware foreground, keeping its name readable without changing creation availability. This final Library-only color correction is separate from the physical editor/tool test source snapshot and is checked in Simulator. Body copy retains semantic primary/secondary colors; existing selection checks, destructive actions, and warning meanings are preserved.

## Measure Layout

**Measures > Layout** now opens a scrollable **Measure Layout** sheet instead of placing long explanations in a native dropdown. The sheet shows the selected measure, a short introduction, and separate cards for all five existing actions:

- **Start New Row**
- **Join Row Above**
- **Move to Row Below**
- **Even Row Widths**, or **Fill Row** for an eligible single-measure row
- **Merge with Next Measure**

Each card has a short action title and a wrapping explanation. Unavailable actions retain their complete reason below the explanation, where it can wrap and scroll. Opening the sheet or choosing Done does not alter the chart. Tapping an available action invokes its existing editing handler.

The sheet request captures the chart and selected measure. Applying an action revalidates that captured target and its current availability rather than silently switching to another measure. The existing chart/layout predicates remain authoritative, including the original Start New Row predicate.

The Measures Guide, accessibility hint on Layout, and in-app How To describe the new sheet path and explain that users can compare actions and read why an option is unavailable.

## Free Ink guidance

The visible Free Ink helper now names the two symbols shared by **Simple Chord Sheet** and **Rhythm Section Sheet**: a **fermata** (arch over a dot) and an **accent** (`>`). It tells the user to lift the Pencil and pause to render. Ordinary staff notes remain handwritten.

The longer Guide retains the existing Rhythm-only **marcato** (`^`) support near a chord, note, or staff-ink anchor. It also retains placement/editing instructions, spacing advice, and the explanation that converted marks retain their original strokes. Restore Ink is taught only when converted marks make the action available. Legacy Lead Sheet guidance does not promise symbol conversion.

The quick helper, local Guide, Free Ink accessibility hint, and in-app How To are aligned with the existing conversion and restoration paths. Recognition, conversion eligibility, source-ink ownership, and recovery behavior are unchanged by this copy update.

## File-size presentation

PDF file-size labels are removed from Library metadata and the PDF preview. Import failure copy no longer displays a numeric byte limit; it suggests saving a reduced copy or splitting the PDF and trying again.

Internal byte counts, stored manifests, size validation, and technical diagnostics remain intact. Page counts and other useful document information remain visible. No library migration or PDF-content change is part of this presentation pass.

## Validation and acceptance

Validation for this candidate is recorded separately from the prior Build 147 results. The prior physical entry-crash acceptance does not establish this pass's visual or workflow acceptance.

| Evidence category | Status for this candidate |
| --- | --- |
| Source review: controls, guidance, availability, and recovery agree | PASSED — owning handlers, modal/input guards, full guidance and source-ink paths reviewed |
| Whitespace/diff checks | PASSED — git diff --check |
| Automated editor, routing, library, PDF, and workflow tests | 390 passed, 2 optional saved-device replays skipped, 0 unresolved failures across 392 unique selected tests; latest results consolidated after focused expectation/readiness corrections |
| Simulator: both chart layouts and Automatic/Manual modes | PASSED — hosted editor workflow and feedback checks across both layouts and render settings |
| Simulator: Measure Layout wrapping, scrolling, disabled reasons, and target behavior | PASSED — 400-point viewport at accessibility5 in dark mode; full reasons, five reachable actions and one real action callback |
| Simulator: narrow/larger-text layout and light/dark readability | PASSED — 400-point Guide header at standard/light and accessibility5/dark; physical default-size tool screenshots and Simulator light/dark Library screenshots reviewed |
| Physical iPad: candidate installation and saved-data readback | NOT PERFORMED — personal Build 147 retained while latest saved-work confirmation is pending; separate synthetic QA chart readback passed |
| Physical iPad: native tool-entry and new sheet acceptance | PASSED — 3 native UI tests with two blank synthetic charts in a separate QA app; eight Write & Render entries across both layouts and both render modes, Free Ink symbols/Guide in both layouts, all five Layout explanations and availability reasons in both layouts |
| Fresh physical Pencil input and symbol recognition | NOT ESTABLISHED by source review or automated UI tests |

Candidate: iChart 1.2.4, Build 148. Local evidence is under `.build/clarity-polish-20261106/`: `signed-build148-manifest.json`, `regression-acceptance.json`, `physical-polish-summary.json`, `physical-attachments/`, and `qa-saved-readback.json`, `marker-polish-simulator-summary.json`, `library-light-settled.png`, and `library-dark-final.png`. The centered Form Marker Cancel/Add workflow passed in both layouts in a separate native Simulator test. The physical QA readback preserves both synthetic chart payloads and deletion records exactly after reading/dismissing the tools. The disposable QA app and runner have been removed.

The initial test build had one test-only identifier lookup corrected to use the existing native provider. Changed wording/source locations required expectation updates. The first hosted fixture could lose key-window ownership during app startup; the harness now maintains its real key window while waiting for UIKit’s actual appearance callback. Assertions still require appearance, focus, control reachability, stable canvas geometry, and exact saved chart data. This is documented in the consolidated result rather than presented as a single clean broad run.

Final handoff should identify the committed candidate source and its installation/readback evidence if installed. Physical checks must identify whether they used synthetic QA charts or the user's saved library. No fresh Pencil recognition or full-container byte-identity claim follows from a successful UI construction test.

Final packaging: device compile/link passed. Xcode signing encountered existing File Provider FinderInfo metadata; a clean copied artifact was signed with the existing development identity and generated entitlements and passed deep/strict verification. The verified Build 148 artifact is recorded in the local manifest. Personal ML comparison resources are absent.
