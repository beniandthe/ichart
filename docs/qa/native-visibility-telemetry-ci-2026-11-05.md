# Native visibility telemetry fixture — November 5, 2026

The final `d840620d` consolidation's hosted native run completed 3,526 tests:
3,404 passed, 121 skipped and one failed. The failure was
`LeadSheetInkTelemetryHostLifecycleTests.testRepeatedIdenticalHostLayoutsDoNotStarveStableCanvasVisibility`,
whose one-shot disk-queue read did not find its expected event. See the
[original native job](https://github.com/beniandthe/ichart/actions/runs/42075481371/job/127417327575).
The original run has no producer/recorder phase trace, so its exact failure
mechanism remains unidentified. The historical issue #96 remains open.

## Fixture correction

The test retains all ten 100 ms layout requests and requires its sole deferred
producer to hand off before that loop ends. It then awaits actual asynchronous
queue append using the existing bounded two-second helper. Correlated call IDs,
an empty loop-start baseline, a fixture-chart reference and final exclusivity
checks prevent an ambient or post-loop event from satisfying the producer gate.
A bounded in-memory technical trace reports stages on failure.

The existing outcome, scope, source/count, duration and duplicate assertions
remain. Duration assertions accept both valid JSON numeric representations:
an integral measured Double can decode as Int without changing its value.
Both still require finite values and retain their original lower bounds.

This patch changes the native fixture and its assertions. The host retains its
600 ms stable observation, consent-generation binding and admission behavior.

## Controlled verification

- With the real deferred recorder held at the queue-read boundary, the original
  assertion fails despite a valid producer handoff. The corrected fixture passes
  after that same held recorder resumes and actually appends its event.
- A temporary reset-on-identical-layout mutation is rejected at the original
  producer boundary. A later queued event does not turn that result into a pass.
- All five native host lifecycle methods passed 20 repetitions each: **100 test
  executions, zero failures and zero skips** on an isolated iPad Simulator.
- The temporary recorder gate and production mutation are removed before final
  verification and publication. Production source is byte-identical to `d840620d`.

These controls establish the assertion gap and preserve starvation detection.
They do not establish the original hosted failure's exact mechanism or a new
physical-device acceptance result. Final revision-specific test and merge
results are recorded in the PRs. Private execution artifacts remain local.
