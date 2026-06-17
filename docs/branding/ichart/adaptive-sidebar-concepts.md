# iChart Adaptive Sidebar Concept

Date: June 6, 2026

Status: locked as the home-page appearance direction.

Purpose: define the locked home-page appearance direction around a hybrid idea: A/B become light and dark modes, while C contributes the sidebar navigation.

## Core Idea

Use one stable home-page app shell:

- Sidebar for app-level destinations, with the full B4.8A-H1 canon wordmark in the top-left.
- A/B-style content treatment for section context, status, and primary action.
- Light and dark modes that change the surrounding workspace mood without changing the core navigation model.
- Chart pages stay paper-first in both modes.

## Light Mode: Paper Workbench

Light mode should inherit the Paper Studio feel:

- warm paper workspace
- light header with wordmark and current section
- iChart Blue for primary action
- Blue Soft for selection
- sidebar remains dark so navigation has weight and consistency

Best for:

- writing
- teaching
- arranging
- daytime library/project management

## Dark Mode: Stage Workbench

Dark mode should inherit the Stage Workbench feel:

- dark header and surrounding workspace
- same sidebar layout
- B4.8A-H1 logo colors on dark
- paper chart previews/pages remain warm and readable
- dark mode frames the music; it does not invert the chart page by default

Best for:

- low-light work
- rehearsal/performance-adjacent use
- users who prefer a darker app shell

## Sidebar Role

The sidebar should be app-level, not editor-tool-level.

The top-left sidebar logo is locked as the full B4.8A-H1 canon wordmark: baseline-aligned italic `i`, blue `C`, staff-line `hart`, and the closing double barline. Individual home tabs should not repeat the logo in their content headers.

Locked tabs:

- Charts
- Forums
- Help
- Settings

`Charts` owns all saved charts and the `New Chart` action. `Forums`, `Help`, and `Settings` are app-level home destinations, separate from editor tools. `Help` owns FAQ, user-policy, legal, and contact placeholders until the release hygiene sprint turns those into fuller documents.

Sidebar behavior:

- The sidebar can collapse to an icon-forward rail and reopen to the full wordmark/tab state.
- Collapse state should preserve the selected home destination.
- The bottom of the sidebar owns the Light/Dark mode switch.
- Support/legal/contact links should live inside the Help surface instead of duplicating in the sidebar footer.

Potential later additions:

- Search
- Recent
- Account / Upgrade

## Header Role

The header should stay closer to A/B:

- wordmark
- current section/project name
- saved/account status
- primary action

Avoid making the top header feel like dense console chrome. The sidebar can carry the operational structure.

## Locked Home-Page Direction

This is now the locked direction for the home page:

- A and B become mode personalities.
- C becomes navigation architecture.
- The top-left sidebar logo becomes the full B4.8A-H1 canon wordmark.
- The bottom of the sidebar owns the Light/Dark mode switch.
- The sidebar can collapse/open while Help remains the all-in-one support surface.
- The Charts tab stays work-first: the sidebar owns the wordmark, while the content surface centers the primary `New Chart` action without a redundant tab header.
- App opening motion should build the same mark instead of introducing a separate splash identity: canonical italic `i` and staff lines fade in, the active captured PencilKit `Chart` handwriting sample replays in stroke order, then the resolved mark snaps into the exact B4.8A-H1 sidebar-logo geometry.
- The bundled fresh-install handwriting fallback must come from an exported active capture row, not a generated or manually drawn approximation.
- The handwritten-to-resolved-logo transition should stay gentle: preserve the feeling of ink becoming the app identity rather than adding a splash-screen effect.
- The first transition direction is the staff-line lock: once handwriting completes, staff and measure lines lightly brighten for one beat, then the clean logo resolves onto that same staff.
- The sidebar is stable across light and dark modes.
- The chart surface remains governed by the usage rule: paper holds the music.
