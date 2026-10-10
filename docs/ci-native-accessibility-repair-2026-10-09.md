# Native CI accessibility repair — October 9, 2026

This follow-up repairs test discovery and simulator test-service setup. It does
not change application behavior, fonts, recognition, subscriptions, telemetry,
backend code, dependency versions, or saved user data. No physical-iPad install,
archive, upload, merge, purchase, or public campaign action is part of this pass.

## Failure and diagnosis

The original branch push, commit
`9c4639a757176fac971e07818ca1a3f1812bced1`, succeeded. Its
[CI run](https://github.com/beniandthe/ichart/actions/runs/38020044700)
failed three native tests: two Clear Draft availability tests and the mounted
Setlist PDF appearance test. Their lookup failed before the enabled-state or
dark PDF/file-preservation assertions. CI executed 2,374 passing tests, three
failures and 103 skips; its SwiftPM and telemetry jobs passed separately.

Failure screenshots showed Clear Draft Ink and Done visibly present. Native
enumeration omitted the horizontal editor strip's entire accessibility content,
not only Clear. With Xcode 26.6 (17F113), the CI-matching simulator was iPad Air
13-inch (M4), iOS 26.4.1 (23E254a). A controlled test on that exact runtime
passed all three Clear Draft cases when the simulator accessibility service was
initialized, then restored and verified its prior setting.

This isolates a hosted-test accessibility preparation/discovery defect; visible
buttons alone did not prove their state or tap behavior. No production toolbar
mutation or assertion removal was justified.

## Scoped repair

- A test-only native lookup recursively enumerates UIKit subviews, static
  accessibility children, automation children, and dynamic count/index
  providers. Identity deduplication and bounded traversal prevent cycles and
  oversized container enumeration. Invalid negative dynamic counts must not
  reach UIKit's internally enumerating automation getter.
- Clear Draft assertions still require a rendered, on-window button with
  enabled semantics. The no-ink negative control first requires a discoverable
  real editor button, so an empty tree cannot produce a false pass.
- Setlist tests retain light/dark pixel and trait checks, document identity, and
  source/saved PDF byte-preservation assertions. Only title discovery and the
  hosted accessibility environment change.
- CI temporarily initializes `ApplicationAccessibilityEnabled` on its exact
  selected simulator UUID, verifies initialization, and restores the key's
  original boolean/integer value or absence. This is an explicitly documented
  **undocumented Simulator test-service workaround**, not an app API or a
  customer-device configuration. No host or physical-device defaults are used.
- Xcode's test destination remains the selected simulator; parallel clones are
  disabled. Existing nonzero/zero-failure result checks remain mandatory, and
  actual executed result rows must match that selected UUID.

## Executed evidence

| Gate | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Focused configuration, lookup, Clear Draft and Setlist tests, iOS 26.4.1 with service initialization | 45 | 0 | 0 |
| Same focused selection, canonical iOS 26.5 simulator with its existing setting | 45 | 0 | 0 |
| Full native suite through the CI wrapper, iOS 26.4.1 | 2,383 | 0 | 103 |
| Focused native selection through the final cancellation-hardened wrapper, iOS 26.4.1 | 45 | 0 | 0 |
| Mocked wrapper and actual CI summary-verifier regressions | 15 | 0 | 0 |

The full native result contains 2,486 total tests and identifies the exact
configured UUID `2E627DBC-EC0B-4D6C-82C8-B7CDDE07A171`. Both the wrapper and an
independent read verified restoration to boolean false afterward. The canonical
26.5 simulator already had accessibility enabled; that run is not evidence for
a fresh/default-off simulator. The 103 skips remain the existing historical,
research/replay and live-backend opt-in tests, not the three formerly failing
cases.

The final wrapper adds cancellation/PID-capture protection without changing the
normal test command or native test sources from the full passing run. Mocked
regressions cover original boolean/integer 0/1/absence, preparation/enable/test
failures, restoration errors, INT/TERM, a child ignoring cancellation, and the
launch/PID race. Restoration is verified on normal exit and handled INT/TERM;
SIGKILL or runner/host loss cannot be trapped. Workflow YAML parsing, shell
syntax and whitespace checks also passed.

Earlier diagnostic runs are not silently counted as passing evidence. Several
had compile errors and zero executed tests. One focused run was terminated after
a process sample identified UIKit endlessly enumerating a synthetic negative
container count inside the new helper regression; the helper's preflight budget
guard fixed that test-harness defect before the passing runs above. Public SDK
block-provider getters were also unsuitable on the tested runtime and are not
included in the repair.

Native source/test receipts are retained locally under
`/private/tmp/iChartCIDiscoveryRepair-20261009.l61Hyc/`, including
`FocusedAXBounded2641.xcresult`, `FocusedDefault265.xcresult`, and
`FullWrapper2641.xcresult`, plus `FinalWrapperFocused2641.xcresult` and
`final-wrapper-mocks.log`. Native package lock SHA-256 is unchanged:
`a3b3da28d71e407f388f992f4a929b8ce7f8d7d56c63f803ba974d9193da456b`.

The passing local suite is not a fresh remote CI result or new physical product
acceptance. A follow-up push must receive its own remote checks. PR-only CodeQL
and Dependency Review, distribution and the previously parked release/offer
gates remain separate.
