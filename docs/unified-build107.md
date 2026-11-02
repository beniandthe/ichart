# Unified regular-app build 107

Version 1.2.4 (107) combines the accepted automatic-render recovery from
[PR #92](https://github.com/beniandthe/ichart/pull/92) with the Free Ink engraving
alignment work already merged through [PR #93](https://github.com/beniandthe/ichart/pull/93)
and its manual-measure-width correction.

The no-read recovery keeps completed recognition, technical failure and
cancellation separate; retries a current technical failure once; and retains
the source-bound retry budget across unchanged input. Supported candidate
feedback, structural review precedence, source ownership, geometry protection
and diagnostic authorization remain as described in the
[build 104 validation record](automatic-no-read-recovery-2026-11-01.md).

Free Ink follows authored staff geometry across engraving changes while
retaining its original source archive. A common row transform is now used only
when it maps every measure's boundaries to that measure's target boundaries.
Rows containing both manual and default widths otherwise use the existing
connected-group owning-measure projection. This prevents internal barline
alignment errors without splitting connected handwriting.

The manual-width correction includes a regression spanning all twelve directed
preset transitions, with notes on both sides of internal barlines and source,
metadata and connected-component checks. It failed against the earlier policy
and passed with the correction. The combined candidate additionally retains
the automatic-render, live-source, fallback, keyboard, rotation, persistence
and export regression coverage.

Build 104's physical workflow acceptance applies to that installed build.
Build 107 has its own exact-source validation and delivery record in PR #92;
component results do not substitute for combined-build acceptance. Private
device data and raw handwriting remain outside the public repository.

The new optional staff/preset metadata reads older archives. Forward updates
must retain that metadata; an older binary that drops the keys is unsuitable
as a rollback after the newer format has been saved. Existing signed artifacts
and backups are retained as provenance, never restored automatically.

This work does not change backend schemas or deployments and does not resume
Graph/MyScript, model training or handwriting collection.
