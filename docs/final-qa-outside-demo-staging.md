# iChart Final QA Outside-Demo Staging

Status: Active outside-demo staging record
Last updated: 2026-07-07

This document keeps the final QA lane aligned while iChart moves from internal polish into outside demo/TestFlight readiness. It records the order of gates, the current branch/PR, and the evidence that should be kept with the release candidate.

## Current Release Lane

- Branch: `codex/final-qa-stage`
- Base: `main`
- Draft PR: `#15` — `[codex] Final QA stage hardening`
- Current head: `b3dc35b Harden server subscription and forum gates`
- Target distribution: outside-demo/TestFlight candidate after docs alignment and final performance/optimization pass

## Completed Gates

1. Create a QA branch from `main`.
   - Done: `codex/final-qa-stage`.

2. Add/verify real contact routing through `useichart.com`.
   - Done: `4ade59e Guard hosted support contact route`.
   - Public URLs: `https://useichart.com`, `https://useichart.com/support`, `https://useichart.com/privacy`.
   - Support email: `support@useichart.com`.

3. Remove or hide dev-facing/test-only tools from Release surfaces.
   - Done: `43218cb Harden release developer surface gates`.
   - Release-gated surfaces include forum QA samples, local Pro preview hooks, chord/rhythm diagnostics, fixture capture paths, and simulator-only Supabase auth fallback.

4. Run the full security sweep and apply required hardening.
   - Done: `b3dc35b Harden server subscription and forum gates`.
   - Remote Supabase migration applied: `20260707164637_harden_forum_pdf_provenance.sql`.
   - Edge Functions deployed for App Store Server Notifications and StoreKit transaction claims.
   - Remote smoke expectations: missing notification payload returns `400`; fake opaque payload returns verifier rejection `401`; unauthenticated transaction claim returns `401`; oversized webhook body returns `413`.
   - PR checks passed: SwiftPM, iOS simulator tests, Dependency Review, and CodeQL. Supabase Preview is skipped by project integration settings and is not a release failure by itself.

## Active Gate

5. Audit docs for iChart/App Store/Supabase alignment.

Scope:
- Active release docs only, not historical sprint logs unless a current release doc points to them as authority.
- App identity: `iChart: Quick-Notation Charts`, bundle `com.ichart.app`, SKU `ichart-ios`.
- Product IDs: `com.ichart.app.pro.monthly` and `com.ichart.app.pro.annual`.
- Supabase project: `pausvvwoazbvmzyrebwl`.
- Public URLs: `https://useichart.com`, `https://useichart.com/support`, `https://useichart.com/privacy`.
- TestFlight callback: `ichart://auth-callback`; universal links remain a production follow-up after associated-domain setup.
- Secrets must remain out of git, chat, Xcode settings, app bundles, docs, and screenshots.

Completion evidence:
- No active release doc still describes legacy branding, legacy bundle identifiers, optional launch subscriptions, or no-backend V1 architecture as current truth.
- StoreKit and Supabase runbooks describe server-owned subscription authority, app-account token binding, replay/idempotency guards, Cloud Backup RLS, forum attribution/provenance, and remaining dashboard follow-ups.
- App Store/TestFlight metadata points to the live support/privacy URLs and monitored support email.

## Remaining Gates

6. Final performance/optimization pass.
   - Keep this evidence-driven. Do not revive the rejected renderer/font simplification experiment.
   - Focus on first-open/new-chart/editor responsiveness, cloud/offline behavior, and obvious repeated work found by profiling or source review.

7. Package the next outside-demo/TestFlight build.
   - Package only after docs alignment and performance/optimization gates are clean.
   - Build from the release-candidate branch or merged `main`, then record build number, commit hash, CI URL, remote Supabase evidence, and manual QA notes.

## Known Deferred Follow-Ups

- Supabase Auth leaked-password protection should be enabled when available on the current plan.
- MFA/passkeys remain post-V1 unless a complete account UX is added.
- Universal links remain post-TestFlight until the associated domain path is selected and verified.
- App Store Server API current-status checks are a post-basic-TestFlight hardening layer.
