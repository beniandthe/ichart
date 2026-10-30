# Free Ink integration into main — October 29, 2026

The user accepted the physical behavior of build 90 on Becoming: smoother zoom/pan with handwriting retaining its position. The user then authorized merging the Free Ink fix into main.

## Scope

The accepted device branch is retained as `codex/free-ink-rotation` at `bb37365919b5bc031d417058361e2b0b02eabe13`. That branch descends from eight repeat-ending commits absent from main. To avoid publishing unrelated work, `codex/free-ink-main` starts at main `061e9a35` and applies only the final Free Ink delta from `45b8e4b2` to `bb373659`.

Four overlapping-file conflicts were resolved selectively: retain Free Ink source invalidation and document-width handling, retain main's existing ending behavior, and set the project and configuration assertion to build 90. The narrow inherited ink-normalization guard and its regression are included as a preservation prerequisite: already-normalized archives retain their original bytes instead of being decoded and re-encoded. No other repeat-ending implementation is included.

The first full SwiftPM attempt exposed two geometry tests referencing a UIKit-only helper from macOS. Only those two tests are conditionally compiled for UIKit; they continue to run in the native iPad simulator. Other portable layout-policy tests remain in SwiftPM. Production behavior was not changed to repair this test-target issue.

The Free Ink changes retain exact paper coordinates, one logical document width, native fit-width pinch/pan with focal-point preservation, unchanged ink serialization on geometry-only updates, authored-width PDF export and deferred raster refresh after navigation. Graph/MyScript, recognition providers/models, resources, schemas, backend and CI configuration are unchanged.

## Evidence boundaries

- The accepted installed build is from the preserved device branch. It has 944 passing editor tests, 10 optional replay skips, seven separate appearance passes and four fresh-library passes, plus the user's physical confirmation. Its existing data readback matched the fresh backup.
- The main integration is a separate source revision. Its fresh local tests and protected GitHub PR checks must pass before merge. The PR records those final results; device-branch results are not relabeled as main-integration results.
- The older combined-process PDFKit accessibility teardown failure remains unresolved. Local editor and appearance runs were isolated. The protected iOS CI result is a separate gate and any failure must be assessed before merging.
- Private backups, ink, provisioning material and diagnostics remain ignored under `.build`. No device data is changed by the source integration. Existing dirty checkouts and research branches are retained.

The main branch protections require current SwiftPM, iOS simulator, Swift CodeQL and dependency-review checks, resolved conversations and linear history. Use a normal squash merge guarded by the final PR head. A repository merge does not establish an App Store upload or public release.
