# Final candidate review October 9 2026

The local final candidate gates passed after two App-target test guards and one
privacy-copy assertion were repaired. The backend CI job now includes the offer,
subscription-authority and account-deletion contracts. App behavior, installed
build, saved data, reader policy and public offer configuration were not changed
by this pass. Signing for distribution, publication and the timed live checks
remain open.

## Candidate and source review

Active branch: `codex/app-release-normalization`; base HEAD:
`3062164007ae5b13ad100bd71a96857ffce989a9`. The review below covered the
uncommitted working candidate. After separate user approval, that exact candidate
was committed locally as `8296848` with a clean working tree and unchanged source
fingerprints. No push or distribution action followed that checkpoint.

The final inventory accounts for **58 tracked changes and 58 untracked files**
before adding this receipt. New application and regression files are included
in the regenerated Xcode Sources. Nothing was discarded or automatically staged.
The scoped manifest fingerprints **1,283 source/test/configuration inputs** in
`iChart`, `iChartTests`, `ThirdParty`, `scripts`, `StoreKit`, `.github`, `supabase`,
and root package/project settings. Its digest remained unchanged across the
verified native tests and final checks:
`5b0ca3dff76f94d2fe95053dc0ff9b220f0c661e18fd3651f2e3a9ae2a871287`.
Generated project, iChart scheme and resolved-package hashes also stayed equal.
This scoped manifest does not fingerprint external fixtures or every document.
The tested local policy draft's final SHA-256 is separately recorded as
`66659e99268abf1a79c0fea3f8f61306e943597e5972651897f7464f920b5daa`.

Bounded static review covered editor review/input, source-ink ownership,
rotation, chord geometry, PDF/setlist/deletion recovery, and offer/telemetry
integration. No newly reproduced app release blocker was established. A minor
static feedback inconsistency remains parked: near a measure's right edge,
the temporary chord move-selection frame can be narrower than its glyph; the
committed frame returns to the chosen width. No content or sizing mutation was
identified, and this was not independently reproduced through touch interaction.
Destructive library entrypoints retain source-wiring/store tests, not a new
per-touch deletion acceptance record.

## Repairs and failed receipts

- The first full SwiftPM command failed compilation because the native Debug QA
  test imported Supabase, absent from the Foundation package. After its guard was
  corrected, the next attempt exposed purchase-feedback tests referring to
  App-target-only types. Both files now use the appropriate native platform
  guards. Their assertions remain intact; the native result tree proves all
  **30 QA diagnostic and eight purchase-feedback tests executed and passed**.
- The first native gate recorded **2,373 passed, one failed, 103 skipped**. Its
  single failure required the old phrase “random installation identifier.” The
  approved disclosure explicitly names “random installation and diagnostic-session
  identifiers.” The assertion now checks that complete wording; the full native
  selection was rerun rather than treating the failed receipt as green.
- CI preserves the existing telemetry job/name and adds one local-fixture Node
  step. It needs no credentials, package installation or live service. Existing
  telemetry contracts plus the new 502-test command select **518 contracts**.
  Remote GitHub execution has not occurred. The PGlite retention fixture and
  Deno SDK-composition fixture are not silently represented as CI coverage.

## Fresh verification

| Gate | Passed | Failed | Skipped | Evidence |
| --- | ---: | ---: | ---: | --- |
| Full iChart native suite | 2,374 | 0 | 103 | `AppVerifiedCandidate.xcresult`, summary and actual test tree |
| Full SwiftPM XCTest suite | 1,677 | 0 | 89 | `swiftpm-final-verified.log`, nonzero XCTest summary |
| Offer plus transaction-authority contracts | 487 | 0 | 0 | `complimentary-offer-complete.log` |
| Telemetry/account contracts | 31 | 0 | 0 | `telemetry-account-contracts.log` |
| Retention PostgreSQL fixtures | 11 | 0 | 0 | `privacy-retention.log`, unchanged SQL in PGlite 0.5.8 |
| New CI offer/authority/account command | 502 | 0 | 0 | `ci-offer-account-contracts.log`; overlaps rows above |

Do not add overlapping suites into an accuracy or unique-test claim. The backend
supplemental selection also passed 60 tests; 43 overlap the offer row and 17
environment/verifier tests are additional. The Deno composition fixture was
inspected, not executed in this pass. PostgreSQL fixtures use synthetic Auth rows
and a registration-only Cron adapter, not a real Auth deletion or Cron daemon.

The native 103 skips comprise 48 opt-in historical ink fixtures, 16 provided
saved-state/trace replays, 37 personalization/research runtime replays and two
live backend tests. SwiftPM's 89 comprise 48 historical fixtures, five provided
replays, 34 research/runtime checks and two live backend tests. Rotation, cue
export, clear-draft, privacy, input/review, deletion and setlist regressions
executed. No fresh-writer accuracy study or dense-page latency claim follows.
SwiftPM's separate Swift Testing footer ran zero tests; it is not the XCTest
evidence used for the passing count.

## Unsigned Release artifact

A fresh `xcodebuild build -configuration Release`, with pinned cached packages
and no comparison opt-in, succeeded: **zero errors, 13 compiler warnings**.
Warnings comprise six actor-isolation diagnostics, four unused responder results,
two deprecations and one unreachable branch. They remain warning debt; the build
is not described as warning-free.

The actual `Release-iphoneos/iChart.app` is `com.ichart.app`, **1.2.1 (75)**.
Its privacy manifest byte-matches source, declares ten linked nontracking types
including functionality-only Customer Support, and declares no tracking domains.
All 24 font files are present. There is no comparison model/package, Study app,
`.storekit` file, saved profile/evaluation/correction data, library state or
performance trace in the inspected resource inventory. The artifact is unsigned
as requested, with no signature directory or embedded provisioning profile.

- Executable SHA-256:
  `aebf742c8dcf46613b3d03357a8eb6e54859dd646cde5cd6c1db578c14e1c895`.
- Privacy manifest SHA-256:
  `ab3d5b9ae5283d14ec0a00e70881ea36808eb4c2e29d3e0af3803cad459a480a`.

During the review, no archive/export, physical-iPad operation, user account change,
deployment, purchase, campaign activation, commit, push or upload was performed. The earlier
user-reported physical checklist still binds the installed privacy revision;
these additional changes affect tests/CI only.

## Repository alignment before push

The follow-up audit of checkpoint `8296848` found no source/resource, version,
signing-configuration, telemetry-allowlist or backend-import mismatch. The release
path still parks handwriting setup and runtime personalization. Historical ink
fixtures and research refs remain preserved; the bounded file scan found no
unexpected generated/cache/signing assets or live credential evidence.

The native `Package.resolved` was previously ignored. It is now retained at the
conventional Xcode workspace path, byte-matching the tested graph: Supabase
`2.55.3` and six transitive packages. Other generated project files remain
ignored. Native CI and CodeQL require the lock; lock changes trigger their
appropriate checks. CodeQL now specifies the project explicitly. The ordinary
app CI job also selects the existing experimental-resource packaging guards;
this does not run ML training or promote a model.

- Focused native configuration tests: **32 passed, zero failed, zero skipped**,
  independently verified in `Configuration.xcresult`.
- Focused SwiftPM configuration tests: **32 passed, zero failed, zero skipped**.
- Dependency-free packaging guards: **seven passed**.
- Workflow YAML parses and tracked shell scripts pass syntax checks.
- A fresh source-tree export regenerates a byte-identical project, app scheme
  and dependency lock. Xcode lists both retained schemes using strict locked
  dependency resolution with the tested cached packages. This is not an
  independent package download, fresh full-suite rerun or new device acceptance.
- Fresh `origin/main` is `90fd4b0d0c575c9254b6fb490fe0f0f1f03274fd`, an ancestor
  of the release branch; no incoming main commits need reconciliation.

No application/runtime source, package version, public policy draft, campaign,
backend migration or user data was changed by this cleanup. The original full
app/Release receipts remain attached to their tested snapshot; the focused
checks above cover the new repository/test wiring. Push, remote CI and public
release remain separate outcomes.

Private follow-up receipts:
`/private/tmp/iChartPushReadiness-20261009.rkXtTQ/`.

## Remaining release decisions and timed checks

1. Observe job 3's first real retention result after **October 9, 8:15 PM PDT**;
   actual Auth-service deletion remains unexercised. Do not delete the user's
   account or force cleanup to manufacture a receipt.
2. Observe the already accepted monthly offer's actual signed zero-charge term
   after **October 10, 8:42:40 AM PDT**, without another purchase. Paid renewal,
   fresh/lapsed cohorts, active-annual scheduling and revoked/upgraded terminal
   finishing remain separate, unclosed offer gates.
3. Coordinate public policy/App Privacy with the consent-enabled release.
   Current store metadata/build-number availability needs live refresh before
   distribution packaging; the unsigned local build does not reserve build 75.
4. The local checkpoint commit is complete. Obtain the appropriate authority for
   push and distribution signing/archive/export/upload. Keep the public campaign
   off until its remaining customer cases and publication gates are resolved.

Private native/SwiftPM/Release receipts:
`/private/tmp/iChartFinalCandidate-20261009.E6ZZvp/`.
Private backend receipts:
`/private/tmp/iChartFinalBackendGate-20261009.cnvIhy/`.
