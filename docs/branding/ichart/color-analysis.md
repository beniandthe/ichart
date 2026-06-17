# iChart Color Analysis

Date: June 6, 2026

Subject: B4.8A-H1 canon logo export and current Library home-screen application.

## Executive Verdict

The current iChart palette is functional and appropriate for the app and likely audience. It reads as a focused music workstation: serious, precise, calm, and notation-aware without becoming academic or nostalgic.

The strongest decision is the dark stage plus warm paper relationship. The dark navy gives the logo a performance/workbench frame, while the warm paper keeps the product connected to charts, lead sheets, and printed music. The pale blue `C` is distinctive enough to be remembered and calm enough to avoid feeling like a generic tech app.

Keep the palette. The main rule is usage discipline: the pale logo blue belongs on dark stage surfaces, while the darker iChart Blue belongs on warm paper/light UI surfaces.

## Actual Rendered Image

Sampled from `exports/ichart-b48a-h1-canon-logo.png` at 4800 x 2400:

| Rendered class | Approx share | Notes |
| --- | ---: | --- |
| Stage/night | 96.01% | Dominant dark field. Creates focus and premium calm. |
| Paper letters | 1.91% | High-contrast readable wordmark. |
| Light blue `C` | 1.07% | Small but highly salient because it is the only saturated color in the mark. |
| Staff/barline gray | 0.94% | Musical signal, intentionally quiet. |
| Antialias/shadow pixels | 0.07% | Normal edge rendering. |

Exact dominant colors from the isolated logo:

| Role | Rendered color |
| --- | --- |
| Stage | `#0f151b` |
| Paper | `#f7f3ea` |
| Light blue `C` | `#8fd3e6` |
| Staff/barline on stage | approximately `#484d51` |

This is a restrained mark. The palette relies on contrast and symbol placement, not color volume. That is good for a professional tool, but the mark should not be reduced too far without a small-size variant because the staff lines will disappear first.

## Brand Tokens

| Token | Hex | Hue | Lightness | Psychological read | Functional role |
| --- | --- | ---: | ---: | --- | --- |
| Night | `#10161c` | 210 | 8.6% | Depth, trust, concentration, backstage/stage-light mood | Primary brand field |
| Stage | `#0f151b` | 210 | 8.2% | Serious, quiet, premium, low-glare | Logo and dark-panel surface |
| Ink | `#151a1f` | 210 | 10.2% | Practical, readable, editorial | Main text on light surfaces |
| Paper | `#f7f3ea` | 42 | 94.3% | Lead sheet, paper score, warmth, craft | Main content surface and logo letters |
| Paper 2 | `#eee6d9` | 37 | 89.2% | Aged paper, secondary warmth | Secondary surfaces |
| iChart Blue | `#226c8a` | 197 | 33.7% | Competent, modern, calm, musical-tech | Accent, controls, `C` on light surfaces |
| Light Blue | `#8fd3e6` | 193 | 73.1% | Clear, bright, airy, memorable | `C` on dark logo surfaces only |
| Blue Soft | `#dcecf1` | 194 | 90.4% | Quiet selection, low-friction UI | Selected/active surface |
| Staff approx | `#484d51` | 207 | 30.0% | Subtle notation texture | Decorative staff/barlines |

## Contrast and Accessibility

| Pair | Contrast | Read |
| --- | ---: | --- |
| Paper on Stage | 16.58:1 | Excellent. Logo letters are highly readable. |
| Light Blue on Stage | 11.04:1 | Excellent. The `C` remains strong on dark. |
| Paper on Night | 16.44:1 | Excellent. |
| Light Blue on Night | 10.95:1 | Excellent. |
| Ink on Paper | 15.81:1 | Excellent for app body text. |
| iChart Blue on Paper | 5.30:1 | Good. Passes normal-text contrast. |
| iChart Blue on Paper 2 | 4.74:1 | Acceptable, close enough to protect. |
| Paper on iChart Blue | 5.30:1 | Good for primary buttons. |
| Saved green text on saved green bg | 6.68:1 | Good. |
| Staff approx on Stage | 2.14:1 | Low, but acceptable because staff lines are decorative and symbolic, not body text. |

Important caveat: Light Blue should not be used for meaningful text or controls on Paper. It is a logo-on-dark color. On light UI surfaces, use iChart Blue.

## Color-Vision Resilience

The logo survives common color-vision shifts because the important separation is luminance first and hue second.

Approximate simulated contrast:

| Pair | Protanopia | Deuteranopia | Tritanopia | Read |
| --- | ---: | ---: | ---: | --- |
| Light Blue vs Stage | 8.71:1 | 8.03:1 | 11.78:1 | Strong. The `C` remains visible. |
| Paper vs Stage | 16.99:1 | 17.25:1 | 15.82:1 | Excellent. |
| iChart Blue vs Paper | 8.11:1 | 9.24:1 | 4.28:1 | Mostly strong. Tritanopia is the weakest case, so avoid making this smaller/lighter. |
| Light Blue vs Paper | 1.95:1 | 2.15:1 | 1.34:1 | Poor. Reinforces the rule: Light Blue is not a light-surface accent. |

## Psychology and Audience Fit

### Musicians and chart writers

This audience needs a tool that feels reliable during repeated use, not a playful novelty. The dark navy and restrained accents suggest concentration, rehearsal rooms, music stands, pits, and stage environments. The palette supports the idea that iChart is where serious musical work happens.

### Educators and students

The warm paper keeps the experience approachable. Pure white plus saturated blue could feel like a school productivity app or generic cloud software. The paper tone adds craft and makes the interface feel closer to chart work.

### Professional users

The palette has enough restraint to feel credible in a pro setting. The blue `C` gives the mark a memorable hook without over-branding the workspace. This is important because a chart editor should get out of the way once the user is actually writing music.

### Emotional posture

The current colors say:

- calm, not sleepy
- focused, not sterile
- musical, not decorative
- premium, not luxurious
- modern, not trendy
- trustworthy, not corporate

That is the right lane for iChart.

## Functional App Fit

### Home screen

The current home-screen treatment works. The dark hero panel gives the logo a deliberate brand moment, and the warm/pale list area keeps the library readable. The `New Chart` button in iChart Blue has enough contrast and does not compete with the logo `C`.

### Editor and chart surfaces

Do not let the dark stage take over the editor. The editor should remain mostly paper-forward because users will read, write, and inspect notation there. Use Night/Stage for framing, headers, toolbars, modal emphasis, and brand moments. Use Paper for work surfaces.

### Controls and states

Use iChart Blue for primary action and active controls. Use Blue Soft for selected rows, active list states, and quiet focus surfaces. Keep green for saved/success, red for destructive/error, and avoid introducing gold back into the logo system.

## Risks

1. Small-size logo loss
   The staff and double barline are intentionally low contrast. At small sizes they will fade before the `iChart` word or blue `C`. This is acceptable for large/medium lockups, but small icons may need a simplified mark.

2. Over-coolness
   The palette is mostly blue/navy. The warm paper is what prevents it from feeling clinical. Preserve the paper warmth in app surfaces.

3. Pale blue misuse
   `#8fd3e6` is excellent on dark but weak on light. Do not use it for text, icons, controls, or data states on Paper.

4. Generic blue-product drift
   If every active state becomes blue and every background becomes pale blue, the app could drift toward generic productivity/dashboard language. Use the musical staff, paper, ink, and restrained navy to keep the identity specific.

5. Brand-field dominance
   The isolated logo export is 96% dark field. That is elegant, but marketing placements and app icons may need tighter cropping or a different composition so the mark does not feel too small.

## Recommendations

- Keep the current color scheme as the canonical app-brand palette.
- Keep B4.8A-H1 on the dark stage with Paper letters and Light Blue `C`.
- Use iChart Blue, not Light Blue, for controls and text on light surfaces.
- Treat staff lines as symbolic texture, not information-bearing UI.
- Preserve warm Paper as the main reading and chart-writing surface.
- Consider a small-size logo variant later: likely the blue `C` plus reduced/stronger staff geometry, or a tighter wordmark crop.
- When extending beyond the home screen, apply the palette by role rather than by decoration: dark for framing, paper for work, blue for action, soft blue for selection.

## Final Assessment

The current image is not just aesthetically pleasing; it is strategically coherent. It supports the product promise: a serious, musician-native chart workspace that feels calm enough for long sessions and distinctive enough to be remembered.

No immediate color overhaul is recommended. The next design work should focus on usage rules and small-size adaptations, not changing the palette.
