# Lesson matching core and source plan results

The new joint match-or-defer core, training-role source parser, and source-only
planner are implemented and independently reviewed. On 2026-10-03, all 24
focused engineering tests passed with warnings treated as errors and zero skips.
The actual public metadata schedule was frozen successfully. No real-source
coordinates, rasters, or embeddings were processed. Synthetic tensors did run
through the core for forward/gradient tests; no model was fitted and no
recognition accuracy was measured in this pass.

This advances the customizable ML implementation without promoting another
unproven learner. The live app, installed iPad build, profiles, chart ink, and
historical prediction/score artifacts were not changed. The separate chord-only
reader boundary remains covered by the existing local app/Study gates; its
23-file source map was reverified unchanged in this pass.

## Engineering checks

| Gate | Passed | Failed | Skipped | Scope |
| --- | ---: | ---: | ---: | --- |
| Match-or-defer core | 7 | 0 | 0 | Synthetic tensors and gradients |
| Filtered source parser | 7 | 0 | 0 | Synthetic source text and provenance |
| Source planner | 10 | 0 | 0 | Synthetic metadata, scheduling, artifact separation |

The core has a tensor-only learned forward, differentiable support pooling,
exact candidate-own generic fallback, strict tie deferral, allowed-label
revalidation, paired targets from one truth sequence, and a false-match
counterexample. The revised gradient check uses matcher loss alone and proves
gradients on both retained support/query embeddings, not merely through batch
normalization. These are implementation properties, not empirical safety.

The official source reader hard-requires the fixed parent receipt and metadata
hashes, authenticates the complete source bytes, and validates its metadata grid.
Excluded writers' coordinate tokens are syntax-checked but never converted into
numeric points, strokes, or samples. Geometry equivalence and this role boundary
were tested on synthetic source text only; the real source has not been opened.

The planner preserves requested catalog order but derives target indexes from
the core's sorted prototype labels. It fixes identical candidate/control episode
and augmentation-draw schedules. Targets, copy exclusions, and query-derived
cohort diagnostics are saved separately from forward inputs. Unavailable or
duplicate supports cannot silently become valid profiles.

## Actual metadata freeze

The planner read only the pinned parent receipt, fit plan, metadata, external
Swift-domain export, and bound code/documentation. It did not open cached
features, checkpoints, source coordinates, private queries, or excluded writers'
geometry. It generated random-draw commitments for future augmentation, not
images or model outputs.

| Metadata count | A16 to B16 | B16 to A16 |
| --- | ---: | ---: |
| Fit writers and held-out writers | 16 and 16 | 16 and 16 |
| Distinct fit query sources | 3,104 | 3,104 |
| Distinct held-out query sources | 3,104 | 3,104 |
| Held-out catalog query exposures | 6,208 | 6,208 |
| Copy-excluded exposures | 22 | 24 |
| Copy-eligible exposures | 6,186 | 6,184 |
| Requested support exposures per epoch | 992 | 992 |
| Available support exposures per epoch | 992 | 992 |
| Unusable training profiles | 0 | 0 |
| True and wrong support coverage mismatches | 0 | 0 |
| Held-out episodes without usable cohorts | 0 | 0 |
| Planned optimizer updates per arm | 1,920 | 1,920 |

Both source-only `numericalFitAllowed` flags are true. This means the metadata
has usable training profiles; it does not mean a numerical trainer has passed,
a model exists, or the recognition gates have passed. The two catalog exposures
reuse the same queries. The combined distinct query source count is 6,208, not
12,416 independent writings. Raster/trajectory copies and literal corpus-glyph
limitations remain explicit in the fixed protocol.

An independent standard-library-only check rehashed all six artifacts, the
17 current bindings, and 13 preserved parent source bindings. It reconstructed
the schedules, prototype targets, copy ledgers, and every count exactly. The
forward plan contains no query targets, cohorts, copy reasons, or evidence
diagnostics. The raw coordinate file was not reopened; its source identity is
bound transitively through the exact parent receipt and metadata.

## Frozen identities

Worktree: `recognition-generalization-reset/Smart Chart`.
Branch: `codex/recognition-generalization-reset`.
HEAD: `160aa31594903508e241802e21ca83ec447de849`, with existing work preserved.
Runtime: Python 3.12.14, Torch 2.7.0, NumPy 2.0.2.

| File | SHA-256 |
| --- | --- |
| Fixed protocol | b8bc1c371f3e5cfd60c8f8867e8380148d93d7105ff62289c4ff1b02484d5c33 |
| Core module | a1a6679737631ab87f022679075a08cbddae387a077041a748e8e5722449ab41 |
| Core tests | e5977663d88ddc12a2ad4c33e5da83a43c9424d2e7386d1645c7aad00a9948e4 |
| Source parser | 1c7506fcda0371d00cd686d29f27282ba56025efd4d5f275a02fc1d8310bd589 |
| Source parser tests | 66093659ee51d5ee54894f2c6bab5ce1dda248bd3166685ed41665732c2f7d79 |
| Planner | 92df1e72a3d204f54a4e289fcdca97d9ca94442c7ad668771f1261d6a5a6044d |
| Planner tests | 4b14eb527a9d2ee98f76ba1254375ebfff5c501cde66482ae2a15e4c5dfcaed4 |
| Actual plan receipt | db84ea5c90d7844ae6a4691eac1e62847c5667a5913b086e6400c9a4c4969291 |
| Actual forward plan | c6fa6c953a87c471c18316cfa39f818869a9b50ac8327363e921486ed9988995 |

Local evidence is under
`/private/tmp/iChartSupportMatchDeferCore-20261003.8GUyVr`:
`core-tests.log`, `source-tests.log`, `plan-tests.log`, `source-plan.log`, and
the six frozen files in `source-plan`. Temporary artifacts may expire.
The plan receipt binds all artifact hashes and 17 executed/dependency source
files, including the actual Swift setup catalog and chord domain.

## Next gate

Implement and verify the matched numerical trainer against this exact schedule.
It must prove complete initial-state equality, single concatenated augmentation
and encoder batches, identical transformed bytes/order between arms, role-bound
raster/hash parity, final-epoch-only selection, and training-only targets. Only
then may fitting begin. Freeze all query predictions before a separate scorer
opens labels and applies every stop rule, including no-read-to-wrong regressions.

No model promotion, physical-device install, fresh-writing score, commit, push,
release, or deployment is claimed. A passing public experiment would still need
separate application-runtime parity and genuinely fresh reviewed writing in
both chart styles before an app recognition or ship-readiness claim.
