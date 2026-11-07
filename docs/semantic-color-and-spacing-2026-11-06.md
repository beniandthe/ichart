# Color roles and fewer containers — November 6, 2026

This pass follows the user's clarification after Build 148: intersperse the existing blue, gold/orange, black, and white to make the interface easier to understand, and reduce the number of boxes. The previous warm-panel treatment is superseded by the following roles.

## Visual structure

- Blue filled buttons with white labels identify primary actions. Blue text and selection marks use a lighter foreground in dark appearance.
- The editor's persistent explainer is one flat navy band with a gold heading and white instructions. Its Guide button remains blue and keeps its balanced position and accessibility-size layout.
- Sheet introductions are open text with a short gold rule. Repeated choices use rows, spacing, and native separators instead of an outlined card for each choice.
- Library, PDF, setlist, creation, Help, Quick Start, and Forum sections lose ornamental outer and nested containers. Actual handwriting previews, chart previews, and editable inputs retain their useful bounds.
- Measure Layout uses separated action rows. Explanations and unavailable-action reasons remain outside the buttons, wrap fully, and can scroll. Essential explanations use primary text after visual review found the former secondary text too pale. PDF metadata is plain text with one existing boundary above the document.

Shared colors live in `IChartInterfaceStyle`. The Library also resolves action foregrounds through its explicit home appearance setting, so its dark mode does not depend on the system's appearance. Filled actions keep a darker blue for readable white labels. Shared chart/PDF/project search explicitly colors its placeholder, typed text, and cursor; chart-action menu icons use the readable action foreground rather than a dimmed secondary tint.

## Behavior and guidance review

The change does not alter tools, gestures, recognition, layout availability predicates, button handlers, feature gates, or source-ink ownership. Existing quick explainers, Guide content, and How To instructions still describe the same controls and actions. In particular, Free Ink's two shared symbol instructions, Automatic/Manual guidance, the five Measure Layout actions, and the absence of file-size labels remain intact.

The previous Write & Render entry-crash repair retains its concrete toolbar type boundaries. Recognition feedback retains its reserved instruction height. Reading the Guide or Measure Layout does not edit the chart.

## Verification

The final focused Simulator regression run passed **99 tests with no failures** after the Library link/search and shared foreground-color corrections. It covered both chart layouts and render modes, hosted editor/review input, source-ink preservation, large-text helper and Measure Layout wrapping, appearance/font controls, PDF handoff, library retrieval, creation, setlist appearance, and Forum layout. An earlier 99-test run also passed; these are the same selected tests, not 198 unique tests.

Three external Simulator UI tests passed with no failures: cold Write & Render entry/reentry across both layouts and both render modes, the explainer/Guide flow in those four combinations, and all five Measure Layout explanations and availability reasons in both layouts. These screenshots/tests precede the last Library tint/search corrections and the final text-only contrast corrections; editor handlers, controls, selection rules, and layout geometry were unchanged by those corrections.

After darkening the Measure Layout explanation paragraphs, **six focused Measure Layout and sheet checks passed**, including the narrow, largest-accessibility-text dark-mode layout and the centered Guide at large text. These six repeat tests already in the 99-test set. The final one-line chart-action icon color correction then compiled successfully in the Simulator and was visually checked.

Simulator screenshots were inspected for the Simple Automatic and Rhythm Manual helpers, the open Measure Layout rows, and the final Library in light and dark appearance. The Library screenshots also exercise an iPad window with synthetic charts and confirm readable search text, collapsed rows without individual boxes, and a distinct selected row. This is visual review of those surfaces, not exhaustive pixel/accessibility certification of every app screen.

Source-color calculations use WCAG relative luminance, not sampled screenshots. White on the filled action blue is 6.81:1; the lighter action foreground on a dark native row is 7.22:1; the gold guidance heading on navy is 11.18:1. These calculations do not establish contrast for every possible composited surface.

Evidence is stored separately under `.build/semantic-clarity-20261106/` and `.build/clarity-verification/semantic-colors-149.*`. Source snapshots distinguish the external UI, final regression, and last visual-build revisions. Simulator build number 149 is a command-line override; the project default is unchanged. No physical iPad installation or fresh Pencil-input acceptance occurred in this pass. No push, merge, or public release was performed.
