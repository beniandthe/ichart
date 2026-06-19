# iChart V1 Readiness Matrix

Date: 2026-05-31
Sprint: 69 V1 readiness / recursive closeout audit
Branch: `codex/rhythm-section-core-authoring`
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Summary

The current V1 product should focus on two active chart styles:

- Simple Chord Sheet: handwritten/iReal-style chord-grid authoring.
- Rhythm Section Sheet: structured staff-based hit/rhythm chart authoring.

Lead Sheet is preserved as a post-V1 archive and compatibility surface, not an active V1 release target.

The code/doc audit and final Sprint 69 app-surface pass do not expose a hidden V1 implementation blocker. The next lane can move from audit into app functionality and UX/UI polish, especially project/library UX, export/share confidence, and tool/menu coherence.

## Matrix

| Area | Status | Evidence | V1 Decision |
| --- | --- | --- | --- |
| New Chart layout picker | Done | `ChartLayoutStyle.v1NewChartOptions` exposes Simple Chord Sheet and Rhythm Section Sheet for V1 creation while preserving Lead Sheet compatibility in the model | Keep |
| One-measure minimum | Done | Model guards and tests for zero-measure sanitization and delete minimum | Keep |
| Simple chord authoring loop | Done | Live milestone at `4dff695`; tests for beat-1/beat-3 append, move-to-beat, later-beat append order, adaptive chord layout, semantic typography | Keep as V1 core |
| Simple manual rows | Done | Menu-owned row breaks, row cap, equal default rows, proportional manual width weighting, layout tests | Keep as V1 core |
| Simple floating freehand | Done | `FreehandSymbolLane.chartArea`, move/delete model tests, layout tests, active-tool scroll protection tests | Keep as V1 core |
| Role-based typography | Done | `ChartTypographySettings`, resolver tests, MuseJazz bundled from official source, semantic chord token tests | Keep as V1 core |
| Section labels | Done | Measure-attached model, layout/export coverage, delete-with-measure behavior | Keep as structured objects |
| Roadmap repeats/endings/markers | Done | Repeat spans, first/second endings, coda/segno/D.S./D.C./Fine/N.C. point markers, layout/export coverage | Keep; vamp count stays out |
| Cue text | Done | Measure-attached typed text, above/below positions, layout/export coverage, delete-with-measure behavior | Keep as typed/manual-first |
| Persistence | Done for V1 audit | Added V1-shaped Simple/Rhythm snapshot tests plus a mixed-library regression gate covering pending chord ink, committed chord source evidence, rhythm maps with drawing data, unresolved rhythm ink, typography, manual Simple row/width state, roadmap, cue, freehand, selected chart, and entitlements; final Rhythm Section app-surface pass save/reopen was green | Keep; carry save-status clarity into Sprint 70 UX |
| PDF/export | Done for structured proof | Simple and Rhythm Section export-proof tests cover structured objects and reject editor placeholders | Keep; make export/share UX a Sprint 70 polish lane |
| Rhythm Section core authoring | Done | V4 rhythm-recognition gate, exact-fit map authority, chord snap tests, below-staff freehand lane, direct whole-note circle rule, two-half-note phrase routing, layout/export coverage, and final green app-surface pass | Keep as V1 core |
| Rhythm Section visual cohesion | Done for V1 audit | Section-label rehearsal-mark reserve, boxed Rhythm Section rehearsal marks, darker staff lines, stronger cue/roadmap/ending rendering, header meter suppression, and final green app-surface pass | Keep; continue visual refinement only as Sprint 70 polish |
| Native iPad screen and orientation | Implemented and app-surface checked | Full-screen iPad metadata, all iPad orientations, viewport-sized editor canvas, Simple/Rhythm native paper widths, Rhythm Section full-row staff stretching, and final green native-surface pass | Keep |
| Toolstrip semantics | Done enough for V1 audit | Page/Export/fonts/engraving grouping, Roadmap coda icon, Text, Chord pencil label, Simple hides Rhythmic Notation, legacy tabs hidden, Library summaries hide key for styles whose setup hides key, and final green app-surface pass | Polish in Sprint 70 |
| Save/reopen app flow | Passed audit gate | Repository/store regression gate protects the data contract; final Rhythm Section app-surface save/reopen pass was green | Keep; improve user confidence in Sprint 70 |
| Fresh simulator install flow | Passed audit gate | Fresh uninstall/reinstall build/run succeeded; final app-surface pass reported green | Keep |
| Lead Sheet | Post-V1 | Archived under `docs/post-v1/lead-sheet/` | Preserve compatibility only |
| Rhythm-object editing | Post-V1 | Explicitly deferred in Rhythm Section plan | Do not block V1 |
| Handwritten section/cue/articulation recognition | Intentionally deferred | Structured typed/manual paths exist | Do not block V1 |
| Vamp count | Intentionally deferred | Explicitly skipped by user | Do not block V1 |
| OCR expansion, score retuning, personal handwriting training, default diagnostics | Intentionally deferred / prohibited | Recognition guardrails | Do not do |

## V1 Blockers

No code/doc-audit blocker is currently confirmed.

Sprint 69 release gates are complete enough to leave the audit lane:

- Simple Chord Sheet core app flow is product-proven through the Sprint 68 live milestone plus Sprint 69 persistence/export regression gates.
- Rhythm Section Sheet final app-surface pass was green for layout, core rhythm recognition, chord snapping, below-staff freehand articulation, structured chart objects, and save/reopen behavior.
- Native iPad full-screen surface is implemented and app-surface checked.
- Fresh simulator uninstall/reinstall build/run succeeded.

## V1 Polish Queue

1. Project/library UX: rename, duplicate, delete, clearer metadata, and less developer-facing library behavior.
2. Export/share UX: obvious export flow, PDF preview confidence, file naming, and app-created export proof.
3. Toolstrip and menu affordance pass: clean remaining naming, hit-target, and menu-state contradictions found in live passes.
4. App-level save/reopen confidence: make persistence feel visible and trustworthy without adding noise.

## Post-V1 Queue

- Lead Sheet pitched-note authoring, ledger lines, key-aware note spelling, and full lead-sheet export polish.
- Rhythm-object editing after recognition commit.
- Rhythm Section manual row/system controls if real chart layout pressure proves automatic wrapping insufficient.
- Handwritten recognition for section labels, cue text, and freehand articulations.
- Vamp count and deeper playback/navigation roadmap semantics.

## Audit Notes

- Sprint 68 is complete enough for the current V1 direction; remaining ideas are now classified rather than recursively reopened.
- The next implementation lane can proceed from audit into Sprint 70 App Functionality and UX/UI.
- Personal live passes remain validation evidence only. They are not recognizer training data.
