# Forum browsing follow-up: Build 137

Updated November 4, 2026. This tested follow-up is included in PR #95 after
the user approved public inclusion. Build 137, source `71491e50`, is now
installed with saved-state preservation verified. Build 136 receipts below
remain historical. The separate Build 138 repeat-repair candidate has passing
local native validation; exact-head CI/review is tracked in PR #95 and physical
repeat acceptance remains open. See the
[Fix Docket](ichart-fix-docket.md).

## Observed problems and repair

The actual forum walkthrough exposed three related browsing defects:

- Four fixed leaderboard columns squeezed badge names into individual letters
  in the iPad's narrow content pane. The board now uses its measured inner
  width for one to four flexible columns, with one column at accessibility
  text sizes. Badge identities retain their full names and preferred text size.
- Search appeared below the leaderboard and disappeared during loading or
  failure. The field and Search action now appear at the top and remain mounted
  through those states. Existing account and configuration gates still apply.
- Returning from Charts retained a submitted query but lost its Search Results
  presentation. The actual app reproduced this failure before the state repair.
  The library now retains the submitted query and updates it from the query
  requested by Search, Retry, tab return and visible account refreshes. Editing
  a submitted query keeps the original single default-catalog refresh; later
  keystrokes add no requests.

The visible entry helper, accessibility labels/hints and How To instructions
change with the controls. The original browsing-only runtime patch is confined
to LibraryView.swift. Its project build default and expectation advanced to 137.

## Verification

| Evidence lane | Result |
| --- | --- |
| Focused native selection | 50 passed, no skips or failures. Includes mounted production forum views, both chart styles, narrow/available widths, accessibility text, whole badge names, stable focused field/frame through loading/failure/retry, account gates, submitted-state recreation, participation, publishing guidance and project configuration. |
| Actual app search return | Failed before the submitted-state repair; passed afterward through normal Search, Charts and Forums controls. Query and Search Results presentation both survive return. |
| Actual app publication | Passed for newly created Simple and Rhythm charts, including normal rename and submission, author PDF preview, normal sign-out/sign-in and second-account downloads. Both native publications use their default Concert view. |
| Actual app participation | Passed with two normal verified-account sign-ins. Both styles retain peer votes and comments, earlier paging grows 80 to 160 loaded comments and posting retains 161, badges remain readable, and B-flat/legacy-unknown PDF labels are correct. |

All three final app walkthrough methods passed with zero failures. Durable
readback after app termination confirms both new publications have validated
provenance; each seeded style retains one peer upvote and 168 comments. The
last comment belongs to the expected peer account. Screenshots were visually
checked for the narrow forum layout and both native publication PDFs.

The app walkthrough uses a unique proof bundle, fresh Simulator and isolated
local Auth, PostgREST, Storage and Edge handlers with two synthetic verified
accounts. A pre-run guard verifies the local endpoint, client configuration and
candidate build. It uses the normal account and forum UI, with sample-data
substitution disabled. Credentials, test logs, recordings and saved-state
artifacts stay outside source control.

Native Concert publication and seeded B-flat/legacy download checks are distinct
lanes. This does not establish fresh Pencil gestures or physical iPad acceptance.
No production test content was created and no production badges were awarded.
The original isolated walkthrough did not install the physical app. Build 137
was installed later through a separate authorized backup/preservation flow.
The two disposable accounts and their posts, songs, badges and stored PDFs were
removed with zero remaining fixture records. Only
the isolated test server was stopped; the proof Simulator is shut down.

## Integration boundary

The historical Build 136 installation checkpoint remains `6ffeb144`. The
original tested forum follow-up is checkpointed separately at `8c79e13a` and
was included in PR #95 after explicit user approval. Installed Build 137 now
uses `71491e50`, including the subsequent reviewed corrections. The user's
keyboard checks passed in both chart styles; the later Simple/Automatic repeat
failure is a separate open acceptance issue tracked by the Build 138 candidate.

At the earlier Build 136 PR head `2607d8ed`, hosted backend contracts and
Dependency Review passed. Hosted iOS, SwiftPM and CodeQL jobs were cancelled
before execution because GitHub did not acquire macOS runners. Checks for the
Build 138 repair head are separate; the earlier results do not establish that
hosted gate. Build 138 local native validation passes; the exact-head hosted
CI/review and physical repeat acceptance are separate gates. Issue #96 remains open with no identified historical mechanism or
production repair claim. Promotion to main, app release and any further device
installation remain separate actions.
