# Offline local-learner connection — verified result

## Outcome

The approved separate offline path is implemented and executed with the retained
real app encoder. It connects the fixed local anchored residual and unchanged
linear anchored control to identical explicitly saved symbol lessons. No live
recognition, rendering, profile, or installed-iPad behavior was changed.

Branch: `codex/recognition-generalization-reset`; base HEAD:
`160aa31594903508e241802e21ca83ec447de849`. Existing unrelated work remains
uncommitted and preserved. No commit, push, release, or production write occurred.

## Executed verification

- Xcode 26.6, Swift 6.3.3; arm64 iPad Simulator
  `0D3454BE-1A21-4910-8FD6-FFD3EB43E908`, iOS 26.5.
- Regenerated from `project.yml`; static diff check passed.
- **51 tests passed, zero failed, zero skipped**: 7 new engine tests, 5 new freeze
  tests, 1 real-runtime export, 8 local-head tests, 1 operational-scale numerical
  test, and 29 project-configuration tests. The successful gate uses normal
  Debug settings. A prior global-optimization run crashed the compiler in
  third-party `IssueReporting` before executing any test; that result is retained
  and is not validation.
- Actual support: **16 glyph examples across 13 labels**; all **18 whole-chord
  examples excluded** from fitting and encoding. Complete vocabulary: 100 labels
  (97 shared, 3 explicitly taught novel symbols).
- Both captures processed with the unchanged observed target partition: **9
  Simple and 8 Rhythm attempts**. No target was merged/dropped to match the
  writer's eight written chords. All 17 attempts retained; 79 automatic glyph
  queries; zero invalid-geometry targets. Parser no-reads remain explicit.
- Unchanged Python references refitted on the exact frozen app embeddings,
  padded generic scores, lessons and pinned public anchors. All **23,700 score
  cells** and complete rank orders agree across shared, linear, and local arms.
  Maximum absolute error: shared `0`, linear `6.106226635438361e-16`, local
  `6.161737786669619e-15`, below the fixed `1e-4` tolerance.
- Before/after source, profile, code and runtime checks passed. Live reader and
  grouper hashes remain identical to frozen v31. No production caller invokes
  this new path; executable callers are test-only.

## Evidence

Private evidence root:
`/Users/benirossman/.local/share/ichart/recognition-development/offline-local-comparison-20261001.xcnD2M`.
Private-derived labels, embeddings, UUIDs and intake metadata remain local,
outside the repository and telemetry.

Runtime export SHA-256:
`69c6b62bb18fd47730da3900f6f62f8040e2b297ca8ccea54c7966f947febb4c`.
Source-code map binds 78 files; digest:
`92e38470f8225f3f0e7df5ef3aadac6c9139c777c028c8ec44a772624127c43a`.
Runtime map binds 5 files; digest:
`31fdfad29ec20b50b180bd94b59b530268238f6cb93919828f463f0495d6a0df`.

## Not established

This is a verified offline connection and numerical/preservation gate, not a
recognition-accuracy result. It does not establish correct automatic glyph
ownership, independent blind annotation, fresh/writer-independent transfer,
encoder-conversion parity with the missing historical checkpoint, physical-iPad
latency/energy/memory, or shipping readiness. No learner promotion is authorized.

The supplied-owner route carries only an opaque receipt digest; a future
conditional accuracy arm must validate the parent receipt's source/group binding.
The structural reading validator is not a standalone numerical verifier for
untrusted decoded artifacts. The current numerical evidence instead uses a
separate complete Python recomputation of freshly generated outputs.
