# Natural writer capture — current readiness boundary

Read-only source audit against branch `codex/recognition-generalization-reset`,
HEAD `160aa31594903508e241802e21ca83ec447de849`, with the current dirty worktree
included. This is source-level capability evidence, not a test/build/install,
physical-device acceptance, acquired corpus, recognition accuracy or learning
benefit. Two focused agents inspected the local flows; the root checked the
shared-store, run-metadata, freeze/label, trajectory and eligibility boundaries.
No private ink/profile, device or backend was queried or changed. No code,
model, collection authority, commit, push or deployment changed.

## Saved Chart Test on the existing installation

The route `Editor → My Handwriting → Saved Chart Test` supports fresh
whole-chart source capture, labels after stopping, written-count/grouping
reports and a frozen profile snapshot. Starting/scoring a run does not teach.

A second writer may use a blank chart in **Before corrections** for a limited
Standard-result/source-ink diagnostic without changing the profile, provided
they do not render/confirm chart predictions, press Teach, reset or change
profile settings. This is the current installed baseline, not a newly validated
universal or clean independent-writer benchmark. Preserve the writer association
separately; the run's chart/run UUID does not establish writer identity.

Do **not** run a second writer's Before → Teach → After sequence through the
existing shared profile. The UI and recognizer use `PersonalInkProfileStore.shared`
at `PersonalHandwriting/profile-v1.json`; the shared journal is
`PersonalHandwriting/evaluation-v1.json`. Teaching would mix their examples into
the current user's profile. Injectable store constructors exist, but the normal
UI/recognition route does not expose a writer-isolated context. A separate
installation/container or explicitly isolated test context is needed before
claiming second-writer personalized benefit; this does not by itself require
multi-profile functionality in the production product.

Source anchors:

- `iChart/Features/Editor/Components/PersonalHandwritingEvaluationView.swift:62`
  creates the model with shared defaults; `:188` describes capture/label
  separation and `:211` freezes the current shared profile.
- `iChart/Recognition/ChordInkPersonalization.swift:325` binds the one profile
  path; `iChart/Recognition/PersonalInkEvaluation.swift:78` has run/chart/style
  identity, not writer identity, and `:244` binds the one journal path.
- `iChart/Features/Editor/Components/LeadSheetCanvasHostView.swift:1591`
  creates the recognition session with the shared profile.
- `iChart/Recognition/PersonalInkLearningLineage.swift:4` explicitly says local
  intake lineage does not verify independent handwriting, writer identity or
  consent.

## Recognition Study local engineering capture

The separate study app is a reusable single-complete-chord capture scaffold,
not a ready multiwriter training or personalization experiment:

- It commits complete prepared visible x/y geometry and available point/stroke
  timing before calling the packet-only recognizer. That boundary does not
  preserve the original PKDrawing archive, pressure/tilt, erased geometry or
  edit history, and timing presence does not prove chronology quality.
- Its local session UUID/app context has no participant or support/query role.
  The generic envelope intentionally excludes identity and eligibility.
- Recognition does not receive the prompt/expected answer. However, the
  prediction remains pending in memory until writer confirmation, rather than
  being a durable full raw-output freeze. Interruption safely records a
  technical failure; it does not invent missing predictions.
- The engineering importer requires the fixed ten-prompt single-chord plan.
  Simple/Rhythm backdrops are not natural full-row editor-context evidence.
- Outcomes and mechanical import receipts explicitly remain local engineering
  only, with corpus/model-supervision/evaluation eligibility false. Capture or
  an intended label does not establish consent, adjudication or dataset role.
  A separately authorized envelope is not authority for local dry-run data.

Source anchors:
`RecognitionStudyCaptureView.swift:274`, `:540`, `:586`, `:650`;
`RecognitionStudyCaptureModels.swift:207`, `:685`;
`RecognitionStudyOutcomeModels.swift:19`;
`recognition_ml/ichart_recognition_ml/study_session.py:391`, `:497`.
Swift file anchors above are under `iChart/Features/RecognitionStudy/`.

## Next decision, not an implemented expansion

The natural-data dependency remains unresolved. A writer pilot can start with
non-teaching baseline diagnostics, but training and personalized comparisons
need explicit writer/session association, support/query separation, a suitable
natural-writing protocol, durable answer-blind predictions and separate data-use
and adjudication eligibility. These cannot be inferred from six labels, chart
names, local UUIDs or engineering receipts.

The user has been offered an independent-writer capture pilot or drafted
data-access inquiries for approval. Neither choice has been received at this
checkpoint. No person was contacted, participant identity invented, access gate
accepted, local capture promoted to a corpus, or original/private answers used
to select another model recipe. Do not restart a rejected synthetic recipe as
substitute evidence while this decision is pending.

## Subsequent direct user constraint

The user permits additional fresh tests of their own handwriting but does not
want other people involved for evidence. Do not recruit writers, contact source
authors or make an external participant a prerequisite for continued personal
learning/app work. The earlier pending-choice paragraph is historical, not the
current instruction. Across-writer claims remain unsupported; fresh same-writer
tests can still assess local learning transfer and regressions.

A read-only device refresh confirms iChart 1.2.1 build 55, the unchanged enabled
37-example profile, and 18 saved runs (14 complete, four cancelled, none active
or awaiting labels). The journal is 3,959,630 bytes, below the 24 MB budget and
32-run limit. Profile and journal hashes exactly match the completed prior
checkpoint. No app/profile/journal mutation or build occurred.

The next bounded step is the separately frozen
[same-writer replication protocol](personal-same-writer-replication-protocol-2026-10-02.md),
not another model recipe or automatic teaching cycle. Private current copies are
retained outside Git in
`/Users/benirossman/.local/share/ichart/recognition-development/same-writer-readiness-20261002.FajmvR`.
