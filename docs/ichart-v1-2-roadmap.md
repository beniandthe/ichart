# iChart V1.2 Feature Roadmap

Status: active feature roadmap
Created: 2026-08-09
Rescoped: 2026-08-11

## Purpose

V1.2 is now the next feature update after the V1.1.1 bugfix patch.

The former V1.2 parking lot mixed true bugs with new capabilities. The bugs
have been moved to [docs/ichart-v1-1-1-bugfix-plan.md](ichart-v1-1-1-bugfix-plan.md).
This roadmap should now focus on user-facing improvements that add capability,
polish, or recovery workflows without pretending they are urgent patch fixes.

## V1.2 Split Decisions

| Item | Destination | Reason |
| --- | --- | --- |
| Pending verification reminder | V1.2 | New recovery workflow; not a bug squash. |
| Tactile button tapping | V1.2 | App-wide interaction polish. |
| Beat/subdivision placement visual cue | V1.2 | New assistive feedback after V1.1.1 placement correctness. |
| Free-Write ink color choice | V1.2 | New user-facing writing feature. |
| Select-input rhythm notation | V1.2 | New structured rhythm-input feature. |
| Manual chord alias coverage | V1.1.1 | High-priority trust issue in existing manual correction flows. |
| Beat/subdivision placement correctness | V1.1.1 | Existing control appears broken. |
| Time Signature selected-measure targeting and collisions | V1.1.1 | Existing Time tool targets/collides incorrectly. |
| Subsequent-stanza rhythm-chart left barline spacing | V1.1.1 | Existing layout produces a false mini-measure. |
| First/second ending and coda clipping | V1.1.1 | Existing notation renders clipped. |

## Auth Trust And Recovery

### Pending Verification Reminder

Add a reminder path for users who created an account but have not completed
email verification.

The reminder must respect the current app-owned verification architecture:

- The app stores a pending auth flow before sending signup or resend email.
- The pending flow includes expected email, flow type, `flow_nonce`, and local
  lifetime.
- The email template sends `token_hash={{ .TokenHash }}` to
  `https://useichart.com/verify.html`; it must not use Supabase's
  `{{ .ConfirmationURL }}` for signup verification.
- The hosted page is only a handoff page. It forwards allowed exchange values
  back to `ichart://auth-callback` and must not claim verification complete
  before the app consumes the token.
- The app validates the pending flow and calls `verifyOTP`.

#### V1.2 Decision

Use a reminder email, but do not include a standalone verification link.

The reminder call to action should send users back into iChart:

> Open iChart on the iPad where you created your account. If you are still on
> the verification screen, tap Email Didn't Arrive?, then tap Send Replacement
> Email. Then open Mail and tap Verify iChart Account. If you already verified,
> return to iChart and sign in.

#### Reasoning

A server-generated reminder link can be valid from Supabase's perspective while
still failing the app-owned callback contract:

- The original device may no longer have the matching pending flow.
- The pending flow may have expired.
- A new reminder link may not include the same `flow_nonce`.
- Opening the link on another device can create a browser-success impression
  while the original iPad remains unverified.
- Multiple account emails can make the next action ambiguous unless the app
  gives users one clear recovery action.

Routing users back to iChart's Email Didn't Arrive? recovery keeps the
replacement-email action inside the app and prevents the recovery path from
competing with the normal verification steps.

#### Requirements

- Identify unconfirmed signup accounts without exposing private email addresses
  in logs, dashboards, or support summaries.
- Send at most one plain reminder per unconfirmed signup window unless the user
  requests a new account email from inside the app.
- Reminder email body must not include a verification, recovery, magic-link, or
  direct `ichart://auth-callback` URL.
- Reminder copy must say to open iChart on the iPad where the account was
  created.
- Reminder copy must say to tap Email Didn't Arrive?, then Send Replacement
  Email if the user is still pending, or sign in if the user already verified.
- Reminder and support copy must not include stale-link warnings; expired,
  already-used, or mismatched links should direct users back to iChart for the
  app-owned recovery action.
- The in-app pending verification screen should continue to be the only place
  that generates a new verification email for that pending flow.
- Rate-limit and support-copy behavior must handle Supabase email send limits.

#### Non-Goals

- No automated standalone verification links.
- No Supabase `ConfirmationURL` restoration.
- No browser page that says verification is complete before app-side `verifyOTP`
  succeeds.
- No off-device verification success claim.
- No broad email campaign to already confirmed users.

#### Acceptance Criteria

1. A pending unconfirmed signup can receive reminder copy that contains no auth
   token, verification link, recovery link, or callback URL.
2. The user can follow the reminder by opening iChart, tapping Email Didn't
   Arrive?, tapping Send Replacement Email, opening Mail, tapping Verify
   iChart Account, and
   returning to a signed-in app session.
3. An expired, already-used, or mismatched email link produces clear error copy
   and does not advance the app state.
4. Opening the reminder on a phone or computer cannot imply verification
   success.
5. Support and health checks can distinguish reminder-sent accounts from
   verified, signed-in, confirmed-without-login, and unconfirmed accounts.

## Interaction Feedback

### Tactile Button Tapping

Improve the feel and clarity of button taps across the app.

Current concern: many tap interactions feel sterile because the user receives
little or no immediate visual confirmation that the button was actually pressed.
This weakens trust, especially in account, save, export, editor, and toolbar
workflows where users need to know the app heard them.

#### Requirements

- Buttons should show immediate pressed-state feedback on tap or Pencil contact.
- Pressed feedback should be visible before the action finishes, including for
  actions that trigger async work.
- Loading, disabled, selected, destructive, and normal button states should be
  visually distinct.
- Feedback should be consistent across account screens, library actions, editor
  tools, export/share actions, forum actions, and modal buttons.
- Feedback should not shift layout, resize labels, or make compact toolbars
  harder to scan.
- Button feedback should remain visible in light/dark appearances and on
  high-brightness gig-stage iPad use.
- Critical actions should pair pressed feedback with an explicit result state:
  saved, sent, exported, signed in, verification email sent, deleted, or failed.

#### Non-Goals

- No broad redesign of the app chrome just to add tap feedback.
- No decorative animation that slows down chart-writing workflows.
- No feedback that makes disabled controls look tappable.
- No hidden reliance on sound or hardware haptics as the only confirmation.

#### Acceptance Criteria

1. A tester can tap common buttons and immediately see the control enter a
   pressed state.
2. Async actions show both immediate press feedback and a clear in-progress or
   completed result state.
3. Editor toolbar buttons, account-flow buttons, library row actions, export
   buttons, and destructive buttons all use a coherent feedback language.
4. Visual feedback does not introduce layout jumps or text clipping on iPad
   portrait or landscape.
5. Disabled controls remain visually unavailable and do not use pressed-state
   styling.

## Chord Placement Feedback

### Beat And Subdivision Placement Feedback

Add a lightweight visual cue for chord beat/subdivision placement after V1.1.1
fixes the underlying placement correctness bug.

Current concern: even when placement is correct, users need confidence that they
are choosing the intended beat or subdivision. V1.1.1 should make the chord
actually move correctly; V1.2 can add a clearer assistive display on top.

#### Requirements

- Show a transient beat/subdivision cue while moving or stepping a chord.
- The cue may be a label, guide tick, ghost position, or similar non-permanent
  placement aid.
- The cue must not become chart content or appear in exported PDFs.
- The cue must not hide the chord, barlines, time signature, repeat markings, or
  nearby notation.
- The cue must follow the same placement grid fixed in V1.1.1.

#### Acceptance Criteria

1. A user moving a chord can tell which beat/subdivision is being selected.
2. The cue disappears when placement is complete.
3. The cue does not affect saved chart data or PDF export.
4. The cue agrees with the final saved `ChordEvent` placement.

## Free-Write Ink

### User-Selectable Ink Color

Add color choice for Free-Write ink.

Current concern: Free-Write is the reliable path for personal rhythm notation,
cues, articulations, and chart markings, but users cannot choose ink color for
their own markup. Color choice would make Free-Write more useful for rehearsal
notes, section cues, corrections, emphasis, and personal chart organization.

This work must not regress the V1.1 visible-ink fix. Black or dark ink should
remain the default, and white or very light ink must never appear by accident.

#### Requirements

- Provide a simple color picker or swatch set for Free-Write ink.
- Preserve black/dark ink as the default for new users and existing charts.
- Persist the selected Free-Write color across strokes, save/reopen, and app
  relaunch.
- Export selected Free-Write colors to PDF consistently with the editor.
- Keep existing handwritten chord-recognition ink policy separate from
  decorative Free-Write color choice.
- White or very light ink may be allowed only as an explicit user-selected
  color, with clear contrast expectations; it must never be a fallback,
  migration default, or accidental persisted state.
- Color controls should be quick to access while writing and should not crowd
  the editor toolbar.
- Eraser, undo/redo, selection, move, and delete behavior should work the same
  regardless of ink color.

#### Non-Goals

- No automatic color interpretation as semantic music data.
- No change to chord parser, chord recognition, or rhythm-input authority.
- No broad redesign of the drawing toolbar.
- No defaulting existing documents to colored or white ink.

#### Acceptance Criteria

1. A tester can choose at least black plus several high-contrast colors and see
   new Free-Write strokes use the selected color immediately.
2. Selected Free-Write colors persist after save, reopen, app relaunch, and PDF
   export.
3. Existing charts continue to open with visible dark Free-Write ink unless the
   user explicitly changes color.
4. White or light ink cannot appear from migration, default state, failed color
   decoding, or platform-version differences.
5. Chord-recognition ink and Free-Write color choice remain separate behaviors.

## Rhythm Input

### Select-Input Rhythm Notation

Add deterministic select-input rhythm notation as a V1.2 feature candidate.

This remains separate from Free-Write. Free-Write is still the reliable path for
personal rhythm ink, cues, articulations, and working-musician shorthand.

#### Candidate Scope

- rhythm values
- rests
- dots
- ties
- grouped beaming
- deterministic rhythm-map creation without handwriting recognition

#### Requirements

- Use explicit user selection, not automatic handwriting recognition, as the
  authority for structured rhythm data.
- Keep Free-Write rhythm ink available and visually reliable.
- Any structured rhythm value must save, reopen, render, transpose where
  applicable, and export consistently.
- Ambiguous or unsupported rhythm entry should fail with clear feedback instead
  of producing incorrect notation.

#### Non-Goals

- No claim that handwritten Free-Write rhythm ink becomes structured notation.
- No full engraving engine.
- No rhythm-recognition rewrite.

## V1.2 Release Gates

V1.2 should not ship until:

1. V1.1.1 patch bugs are either shipped or explicitly not blocking V1.2.
2. Feature scope is kept to the items in this document unless a new item is
   deliberately added.
3. Feature tests include save/reopen and PDF export where the feature affects
   chart content.
4. Existing V1.1.1 bugfix regressions remain green.
5. App Store release notes clearly distinguish new features from prior bug
   fixes.
