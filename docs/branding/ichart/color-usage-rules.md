# iChart Color Usage Rules

Date: June 6, 2026

Status: working rules for extending the B4.8A-H1 brand system beyond the home screen.

## Core Principle

iChart colors should be assigned by job, not by decoration.

The product should feel like a serious musician's workstation: dark brand framing, warm paper work surfaces, strong ink for music and text, restrained blue for action, and pale blue reserved for the logo's `C` on dark.

## Non-Negotiable Rules

1. Dark navy frames the workspace.
   Use Night and Stage for app identity, major headers, toolbars, brand moments, export/share moments, and high-emphasis modal framing. Do not turn chart-writing surfaces dark by default.

2. Paper is where music work happens.
   Chart canvases, library rows, forms, sheet bodies, and repeated reading surfaces should remain warm, paper-forward, and high contrast.

3. Light Blue is sacred.
   `#8fd3e6` belongs to the logo `C` on dark surfaces. Do not use it for text, controls, icons, data states, badges, links, or selected states on Paper.

4. iChart Blue is the action color.
   `#226c8a` is for primary actions, active controls, selected outlines, links, and the `C` when the mark appears on light surfaces.

5. Staff gray is symbolic.
   Low-contrast staff lines are appropriate in the logo and brand texture. Do not use low-contrast staff-like lines for functional UI or chart information.

6. Color is never the only signal.
   Recognition, saved state, errors, destructive actions, and selected states need text, icon, shape, or position in addition to color.

## Palette Roles

| Token | Hex | Use | Avoid |
| --- | --- | --- | --- |
| Night | `#10161c` | Primary brand field, deep app chrome, dark overlays | Large reading/editing surfaces |
| Stage | `#0f151b` | Logo stage, hero panels, focused modal headers, export/share brand frames | Dense list backgrounds and chart canvas |
| Ink | `#151a1f` | Text, notation, labels, chart content on Paper | Low-emphasis disabled text without opacity adjustment |
| Paper | `#f7f3ea` | Main content surface, chart canvas warmth, logo letters on dark | Primary button fills |
| Paper 2 | `#eee6d9` | Secondary surfaces, grouped panels, quiet card alternates | Text and icon color |
| iChart Blue | `#226c8a` | Primary actions, active controls, focus rings, links, selected outlines | Large decorative floods |
| Light Blue | `#8fd3e6` | Logo `C` on dark, rare dark-surface brand glint | Light-surface text, icons, controls, badges |
| Blue Soft | `#dcecf1` | Selected list rows, quiet active surfaces, subtle focus fill | Logo `C`, primary buttons |
| Staff Gray | approx `#484d51` | Decorative staff/barline texture on Stage | Functional lines, form borders, chart staff lines |

## Surface Rules

### Home / Library

- Use the locked adaptive sidebar shell for the home page.
- Support light and dark modes: Paper Workbench for light, Stage Workbench for dark.
- Keep the sidebar stable across modes as app-level navigation with locked `Charts`, `Forums`, `Help`, and `Settings` tabs.
- Use the full B4.8A-H1 canon wordmark as the top-left sidebar logo.
- Put the Light/Dark mode switch at the bottom of the sidebar.
- Keep FAQ, User Policy, Legal, and Contact Us inside the Help surface instead of duplicating them under the mode switch.
- Keep the Charts tab work-first: the universal logo stays in the sidebar, the redundant tab header is removed, and `New Chart` is centered as the primary action.
- Show free-tier chart usage near `New Chart` only when a chart cap applies.
- Keep chart rows simple by default, with user-selectable `Collapsed`, `Quick`, and `Large` preview density.
- Use iChart Blue for `New Chart` and other primary library actions.
- Use Paper or Paper 2 for chart rows.
- Use Blue Soft for selected chart rows, with iChart Blue border/indicator.
- Keep metadata in Ink with opacity or system secondary styling.
- Saved status can use green, but should remain quieter than the primary action.

Verdict: the current home screen is directionally correct.

### Editor Canvas

- Use Paper as the default canvas/page environment.
- Use Ink for written/recognized chart content.
- Preserve chart-style-specific paper tones where they support readability.
- Use iChart Blue for active selection outlines, edit targets, focus rings, and accepted recognition highlights.
- Use Blue Soft for non-destructive selected fills.
- Use red only for destructive/removal/error feedback.
- Use green/teal only for confirmed success or safe move/commit states.
- Avoid Light Blue on the canvas except inside the actual logo or a dark brand frame.

The editor should feel like writing on an excellent chart surface, not like operating inside a dark dashboard.

### Toolbars and Mode Controls

- Toolbars may use Paper/Paper 2 when embedded in the work surface.
- Top-level or global toolbars may use Stage/Night if they frame the editor without swallowing it.
- Selected mode: iChart Blue fill with Paper text, or Blue Soft fill with iChart Blue icon/text.
- Unselected mode: Paper/Paper 2 fill with Ink text/icons.
- Disabled: Ink at reduced opacity, never pale blue.
- Avoid default system `.blue` once the brand rollout reaches the editor.

### Menus, Sheets, and Popovers

- Default body: Paper.
- Grouped sections: Paper 2 or white over Paper if system clarity requires it.
- Primary action: iChart Blue.
- Secondary action: Ink on Paper/Paper 2.
- Destructive action: red, separated by label/icon/placement.
- Brand-heavy modal headers may use Stage, but ordinary editing sheets should stay paper-forward.
- Do not put Light Blue in sheet icons or labels unless the sheet header is dark.

### Chart Content and Notation

- Music content wins over brand color.
- Notation, chord symbols, barlines, rhythm markings, and handwritten ink should remain Ink/near-black unless a state requires feedback.
- Chart staff/grid lines should prioritize readability over logo-style subtlety.
- Do not turn notation blue for brand consistency.
- Use color overlays sparingly and temporarily for editing feedback.

### Recognition and Feedback States

- Candidate / pending: Blue Soft fill with iChart Blue outline.
- Accepted / saved: quiet green with text/icon.
- Warning / unsure recognition: warm amber only if necessary, never logo brass/gold.
- Error / failed / destructive: red with icon/text.
- Moving/reordering: teal/green-blue is acceptable, but keep it visually distinct from iChart Blue actions.

### Export / Share / Print

- Print/PDF chart content should remain Paper/Ink and avoid brand-heavy colors.
- Export preview chrome can use Stage or iChart Blue, but exported chart pages should prioritize musical readability.
- Share sheets and success states can include the logo mark or dark brand strip, but not on the chart page itself unless explicitly creating branded output.

### App Icon and Small Logo

- The full B4.8A-H1 mark is a medium/large mark.
- At small sizes, staff lines and double barlines will fade first.
- A future small-size variant should preserve the blue `C` and the wordmark relationship, but can simplify or strengthen the staff geometry.
- Do not judge the full logo at app-icon scale without making a dedicated small-size study.

## Proportions

Use this as a starting ratio for app screens:

- 60-75% Paper / Paper 2 for work and reading surfaces.
- 10-20% Stage / Night for framing and brand moments.
- 5-10% Blue Soft for selected and active areas.
- 2-5% iChart Blue for action and emphasis.
- Light Blue only inside the dark-surface logo mark.

The isolated logo is intentionally 96% Stage, but the app should not be.

## Migration Notes

The current home screen already follows the emerging system. The editor still contains older generic system blues and system backgrounds. When the brand rollout reaches the editor, migrate these by role:

- Replace generic `.blue` control accents with iChart Blue.
- Replace pale generic blue selected fills with Blue Soft where the state is non-destructive.
- Keep existing recognition/error colors where they have learned functional meaning, then tune them only if they conflict with the new role system.
- Keep chart rendering readability above brand consistency.

## Quick Decisions

| Question | Answer |
| --- | --- |
| Should the editor become dark? | No, not by default. Use dark for framing. |
| Can Light Blue be used for links? | No. Use iChart Blue. |
| Should staff lines be a UI pattern? | Only as brand texture, not functional UI. |
| Can chart notation use brand blue? | Generally no. Music content should stay Ink. |
| Should the home hero stay dark? | Yes. That is where the brand has its moment. |
| Is gold/brass part of the system? | No. Avoid logo gold and reserve warm tones for atmosphere only. |

## Working Summary

Dark frames the instrument. Paper holds the music. Ink carries information. iChart Blue means action. Light Blue belongs to the logo. Blue Soft means quiet selection. Feedback colors stay functional and never become decoration.
