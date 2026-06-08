# iChart Brand System

Status: B4.8A-H1 is canon for the current app-surface trial as of June 6, 2026.

## Logo

- Primary logo: B4.8A-H1, the baseline-aligned italic `i` variant.
- Reference alternate: B4.7B.
- Stored studies: B4.8A current adjusted, B4.8A-H2 top italic `i`, and B4.8A-H3 C-top italic `i`.
- Structure: wordmark-first `iChart`, with the blue `C` as the music symbol.
- Staff treatment: five horizontal staff lines run from the left edge of `C` through `hart`, extend just past the `t`, and close with two light regular barlines.
- B4.8A-H1: Finale Maestro Text Italic `i`, slightly more motion, still family-matched. In app use, the italic `i` is nudged left while its bottom aligns with `hart`, keeping the wordmark connected to the `C` without floating above the word.
- B4.7B: Finale Maestro Text `i`, tighter spacing, steadier reference alternate.
- Home-screen default: B4.8A-H1.

## Color

- Night: `#10161c`, primary app-brand field.
- Stage: `#0f151b`, logo and dark-panel surface.
- Ink: `#151a1f`, primary text on light surfaces.
- Paper: `#f7f3ea`, primary content surface.
- Paper 2: `#eee6d9`, secondary warm surface.
- iChart Blue: `#226c8a`, primary accent and `C` on light surfaces.
- Light Blue: `#8fd3e6`, logo `C` on dark surfaces.
- Blue Soft: `#dcecf1`, quiet selected/active surface.
- Brass is no longer part of the logo system; reserve warm notes for subtle page atmosphere only.

## Type

- Logo font: Finale Maestro Text.
- Logo alternate: Finale Maestro Text Italic for the `i` only in B4.8A-H1 and the stored B4.8A studies.
- App UI: SF Pro/system UI for operational text, labels, lists, and controls.
- Chart/music surfaces: keep the existing notation-family choices and chart-style-specific typography.

## Feel

iChart should feel like a focused music workstation: dark stage framing, warm paper content, precise notation cues, and a confident blue `C` focal point. Avoid decorative gradients, gold logo accents, and generic icon-plus-name branding.

## Home-Page Shell

Locked direction: adaptive sidebar shell.

- Light mode: Paper Workbench, using warm paper as the dominant workspace.
- Dark mode: Stage Workbench, using dark frame/header/sidebar while keeping chart pages paper-first.
- Sidebar: app-level navigation structure is locked; top-left logo is the full B4.8A-H1 canon wordmark.
- Logo placement: the sidebar owns the universal logo; individual home tabs do not repeat the logo in their content headers.
- Sidebar tabs: `Charts`, `Forums`, `Settings`.
- `Charts` owns all saved charts plus the `New Chart` action.
- `Forums` and `Settings` are home-level destinations, not editor-tool tabs.
- Header: keep the A/B-style header with wordmark, section/project context, status, and primary action.
- Chart surfaces: remain paper-first in both modes.

## Supporting Docs

- `color-analysis.md`: color psychology, rendered-image analysis, contrast, and audience fit.
- `color-usage-rules.md`: role-based usage rules for applying the palette across app surfaces.
- `adaptive-sidebar-concepts.md`: locked home-page shell direction with light/dark modes and sidebar structure.
