# Automatic no-read recovery follow-up

This follows the regular-app consolidation on main and targets 1.2.4 (104).
Graph/MyScript, model training and recognition research remain parked. No
backend schema, deployment, new telemetry properties or raw-ink collection is
part of this change.

The existing automatic fallback chain uses three native scale reads followed
by Apple Vision. Previously a thrown Vision error became the same optional
empty result as successful recognition with no supported candidate. The session
could cache that result without knowing whether the engine had completed.
The new typed result distinguishes completion, cancellation and technical
failure. A technical failure gets one delayed retry against the same current
prepared source. Genuine completed empty reads remain cached; cancellation
cannot publish an obsolete answer. Technical retry state stays separate from
semantic empty-result caching and remains bounded across unchanged input.

Automatic feedback now uses the same supported-candidate policy as automatic
rendering, including score and raw-candidate evidence. An explicit global
ending/repeat review blocker takes precedence over per-chord completion
friction. These changes do not promote confidence to trust, invent a chord or
relax source ownership, timing, placement or collision checks. A genuine
unsupported current input still produces no-read feedback and retains its ink.

A separate in-memory operation context links completion, preservation and
geometry checks for one chart/source revision under the current diagnostic
authorization. New source or authorization starts a new context. Successful
partial consumption is progress, not proof that all remaining ink rendered.
Physical acceptance requires visible editable output, complete source
accounting and save/reopen preservation as well as telemetry delivery.

These repairs address source-proven failure and classification paths. The
retained aggregate events and local traces do not establish which engine path
caused the historical device incidents. Passing regressions or fewer incident
events alone do not establish that those incidents are resolved. Fresh device
testing remains a separate acceptance step.

Validation and device acceptance are pending for this candidate.
