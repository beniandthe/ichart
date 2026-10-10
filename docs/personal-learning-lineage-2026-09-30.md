# Local learning lineage — 2026-09-30

## Purpose and boundary

Optional personalization needs an inspectable account of its support examples before a paired comparison can be interpreted. This pass adds that account to the existing teaching paths. It changes neither generic recognition, model weights, ranking thresholds, ink normalization, nor the learning opt-in rules. It is not an accuracy-improvement result.

The identifiers represent **observed local intake sessions**, not authenticated writers or original physical acquisition sessions. Chart review can reuse older ink. Exact hashes cannot establish freshness of translated, scaled, reordered, or otherwise reused handwriting. No new remote collection or training consent is implied.

## App wiring

- Setup and practice lessons share the model instance's local intake session; separate lessons get separate capture IDs. Standalone canvases do not acquire a guessed chart style.
- Practice comparison captures its context before prediction. Only explicit teaching of the user's reviewed label records it; prediction and scoring do not teach.
- Chart review carries an editor-instance intake session and the known Simple/Rhythm chart style through the existing background learning queue. Review opt-out and active-evaluation guards remain in force.
- Saved evaluation teaching uses the saved run ID, record ID, and capture time only when exact recognition input exists. Thumbnail-only legacy records remain untracked.
- Individually labeled pieces from a saved chord inherit the validated parent's session/capture/time/style. The origin records that this is a selected saved symbol, not a fresh acquisition. A changed parent commitment rejects the atomic teaching edit.

Newly appended lessons bind the exact passed strokes and actual normalized stored strokes separately using SHA-256 over existing canonical trajectory packets. Packet commitments preserve stroke/point order, bounds, IEEE-754 signed zero, and timing availability. Metadata construction and validation happen before correction removal or capacity edits. Duplicate lessons and source upgrades retain the original provenance, including missing legacy provenance.

## Frozen comparison support

New saved chart evaluations freeze a `PersonalInkProfileLineageSummary` alongside the frozen profile. It records tracked, missing, mismatched and overlapping example IDs, observed support-session IDs, and the query session ID. Missing or mismatched metadata prevents a complete/disjoint claim. Empty support is vacuously complete/disjoint, not evidence of quality or transfer.

The frozen summary is not recomputed when later corrections are taught. Older journal/profile files retain absent optional fields without migration or invented history. Stored summaries and identifiers are local metadata, not authenticated provenance, consent, chronology, or recognition accuracy.

## Verification scope

Focused SwiftPM checks cover legacy JSON compatibility, source/stored commitments, duplicate behavior, atomic invalid-context rejection, summary boundaries, derived-symbol lineage, saved-run teaching in both styles, and unchanged mock-model recognition rankings. iOS checks separately exercise PencilKit setup/practice/review intake and opt-out behavior, along with project configuration.

No existing user profile, journal, chart ink, label, model artifact, reserved writer data, or prior evaluation receipt was changed by this development pass. No fresh writer was evaluated. No iPad installation, physical-device acceptance, training, release, commit or push was performed. Independent fresh handwriting in both styles remains necessary before quality or ship-readiness claims.
