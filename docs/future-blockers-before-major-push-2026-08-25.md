# Future Blockers Before The Next Major Push

Date: 2026-08-25
Pre-parking baseline: `main` at `22baf1b` (`Merge pull request #56 from beniandthe/dependabot/github_actions/github-actions-ebe228fd2f`)
Status: parked until after the next chord-recognition accuracy branch

## Purpose

This document records non-recognition follow-up work that should be revisited before another major release, large merge stack, or heavy editor expansion.

These items are not current blockers for starting chord-recognition accuracy work. They are future blockers for the next larger push because they affect sync reliability, editor architecture, validation confidence, code health, or future chord-lane depth.

## Scope Boundary

The next active branch is expected to focus on chord-recognition accuracy. That work should not expand into these items unless a failure directly blocks recognition validation.

Do not use this document to justify:

- OCR revival
- broad editor rewrites during recognition work
- chord-lane product additions before the basic recognition pass is stable
- cloud-sync changes mixed into recognition fixes

## Future Blockers

### 1. Cloud Sync Push Failure Audit

Known state:

- Local ink persistence and erase/reopen behavior were validated on the physical iPad.
- Automatic cloud uploads now back off briefly after failed pushes so failing remote sync does not pressure local authoring after every save.
- The underlying `cloud.push_failed` cause was not fixed.

Why it matters:

- Local authoring can be healthy while remote backup/sync is still unreliable.
- Before another major push, cloud failures need to be separated into expected offline/auth behavior versus real production sync failures.

Recommended future branch:

- `codex/cloud-sync-push-failure-audit`

Minimum acceptance:

- Identify the failing request path and error class.
- Verify manual `Back Up Now` behavior separately from automatic queue behavior.
- Confirm successful push clears backoff.
- Confirm local-only chart editing remains unaffected by cloud failure.

### 2. Editor Architecture Extraction

Known state:

- `LeadSheetCanvasHostView.swift` remains the central coordinator for mode transitions, PencilKit state, renderer invalidation, gestures, edit overlays, ink persistence, chord preview scheduling, and chart write-back.
- Several helper boundaries now exist, including ink session, scoped ink canvas, ink scheduling, ink persistence, performance metrics, and parent scroll lock.
- More extraction is useful, but only if behavior-preserving and validated in small slices.

Why it matters:

- The app is functional, but host centralization remains the largest source of regression risk.
- More editor features will increase the chance that a fix for one layer affects another.

Recommended future slices:

- `ChordDraftPreviewCoordinator`
- `RenderedEditInteractionController`
- edit command-executor consolidation

Minimum acceptance:

- No behavior change per extraction slice.
- Focused tests around the moved policy.
- Physical iPad validation for any slice that affects Pencil feel, drag behavior, or chord-lane preview timing.

### 3. Remaining Editor Validation Gaps

Known state:

- Free-Write page ink write, erase, `Done`, close, reopen, and heavy-chart partial erase/rewrite were validated on the physical iPad.
- Mixed chord ink, Free-Write ink, deletion, rendered edit movement/resizing, and close/reopen also held in the observed pass.
- Some workflows were not fully exercised.

Validation still needed:

- Long-session chord-lane erase and preview persistence.
- Rapid switching across page, header, chord, and rhythm ink scopes.
- Cue text movement.
- Roadmap marker movement.
- Canceled drag paths.

Why it matters:

- These are the remaining places where state ownership, dirty ink preservation, and transient edit state could drift.
- They should be validated before another large editor branch or release gate.

Minimum acceptance:

- Physical iPad pass for the workflows above.
- Local trace review separating ink persistence, layout invalidation, chart write-back, and cloud sync events.
- No repeated dirty-scope model reloads during active writing or erasing.

### 4. Non-Blocking Warning Cleanup

Known state:

- Local gates still report known non-blocking warnings.

Known warning classes:

- Deprecated `onChange(of:perform:)` usage in `LibraryView.swift`.
- `UIDevice.current` main-actor warnings in `IChartTelemetry.swift`.
- AppIntents metadata warnings for missing shortcuts/framework metadata.

Why it matters:

- These are not current product blockers, but warnings make future build logs noisier and can hide new warnings.

Minimum acceptance:

- Remove or intentionally document each warning class.
- Confirm `xcodebuild build-for-testing` still succeeds.
- Confirm warning count does not increase.

### 5. Optional Chord-Lane Product Additions

Known state:

- The basic chord-lane flow is stable enough to keep as a baseline.
- The course-correction doc intentionally deferred deeper product features until the core preview/render/edit loop was stable.

Deferred additions:

- candidate picker
- manual text correction panel
- recognition confidence overlays
- chord copy/paste
- multi-select rendered chord movement
- per-system lane spacing controls

Why it matters:

- These can improve depth, but they also add UI and state complexity.
- They should not be mixed into the next chord-recognition accuracy branch unless explicitly scoped and validated.

Minimum acceptance:

- Pick one addition at a time.
- Define the exact owning mode and state layer before implementation.
- Preserve the rule that draft chord ink commits only through explicit `Render Chords`.

## Return Protocol

After chord-recognition accuracy work is complete:

1. Rebase or branch from the then-current clean `main`.
2. Re-run source-control health checks before choosing the next blocker.
3. Start with cloud sync if production reliability is the priority.
4. Start with validation gaps if release readiness is the priority.
5. Start with editor extraction only if the next feature set will touch the canvas host again.
