# Coordinated paid access rollout

This is preparation for the December 1, 2026, 09:00 Pacific (17:00 UTC) target. The target does not activate anything. Public free Pro remains enabled, Supabase automatic production deployment remains disabled, and paid delivery and cutover require their own reviewed approval.

The release contains the complete accepted Builds 200–205 writing and PDF changes. The coordinated follow-on replaces the static paid candidate with a server-directed access phase. Never use a previous static-paid archive or its test receipt to certify this implementation.

## Access and billing

Build capability, access phase, voluntary beta participation and verified Apple billing are independent. A paid-capable production client asks the authenticated `product_access_status()` RPC for the current phase. A server phase is not an entitlement or proof of purchase. The same resolved runtime policy must drive local access, Plan, Upgrade, How To and checkout admission. Normal free-beta and isolated staging build scopes retain their existing semantics.

During `free_beta`, recorded participants retain free Pro and voluntary Basic users can rejoin. New paid checkout is unavailable. During `paid`, current owner-bound Apple subscription truth determines Pro access. Saved charts, ink, fonts, converted charts, PDFs and setlists remain available under the existing downgrade guarantees; creation limits cannot delete saved work. Projects retain their documented read-only downgrade behavior.

Unknown, missing or unsupported server status blocks new checkout. It does not invent a purchase or treat a network failure as an account downgrade. Cached status is scoped to its project and account, stale until refreshed, and can preserve previously confirmed local access only. Server services continue to enforce their own verified access. Offline devices learn a transition on their next successful refresh; this is not a universal wall-clock switch.

The phase cache is not a paid billing cache. The existing independent billing-unavailable policy remains in force: after a process restart, an ownerless archived paid entitlement cannot prove that the current account owns Pro. New paid creation/tools may therefore use Basic limits until owner-bound billing is verified. All saved editing, export, PDFs, applied fonts and local setlists remain available, and the existing device-local legacy floor is preserved. This change does not add a new offline paid-authority cache. An unavailable phase is still presented as **Checking Plan Access** rather than silently calling the account Basic.

Before opening a new Apple purchase, verify the current account and a fresh recognized paid phase after all other preparation awaits. A rollback observed in an already open Plan or Upgrade view must remove checkout immediately. Restore, Manage Subscription, accepted transaction verification and finishing remain independent of phase. A previously opened Apple confirmation sheet may still complete after rollback; do not discard the real transaction.

## Older installed apps

The user approved bounded legacy compatibility on November 27. In paid phase, the old `free_pro_beta_status()` response may project its legacy formula fields to retain local Pro tools for strictly verified, unexpired and unrevoked paid owners. It must not rewrite enrollment, subscriptions, expiry or billing records. The truthful new RPC does not use this projection, and server RLS and paid feature authority never derive access from compatibility JSON. Both legacy participation mutations reject without changes during paid phase.

This protects old local access but cannot replace compiled UI. Older free builds continue to show their existing **Pro — Free** labels and lack the new paid checkout and newer compile-gated features until updated. Unpaid or expired owners do not receive the paid compatibility projection. A client version header or user-editable metadata never authorizes paid service.

## Deployment sequence for final review

1. Review the exact combined source, additive migration, matching worker closures, source-bound native validation, hosted CI and signed distribution artifact. Keep automatic production deployment off.
2. Obtain approval for the exact backend deployment packet. Apply only its listed prerequisites and additive coordination migration with paid access disabled. Verify free Pro, real beta membership, owner restrictions, strict paid predicates, notification handling and paused destructive retention. Installing additive support is separate from activation.
3. Review the Apple changes separately: US monthly target **$6.99**, annual target **exactly $60.00**, and equal subscription service levels. Current schedules, existing subscribers and renewal effects must be shown in the approval packet. An available Apple price point is not a saved schedule. Do not substitute $59.99. App Store agreements, review status and notification routing require a fresh readback.
4. Deliver the exact coordinated binary only after the installed backend and same-head preactivation tests demonstrate free Pro with paid checkout blocked. TestFlight processing, group distribution, installation and saved-data preservation are separate gates. Protect the iPad with a fresh saved-work confirmation and two stopped-app backups before any install or potentially automatic update.
5. Complete genuine Sandbox purchase, restore, cancellation paid-through, annual expiration/re-upgrade, verified notifications and owner-bound Free/Pro service checks on the compatible client in the approved isolated environment. Historical Build 173 staging results are useful history, not current production verification. A billable staging branch requires a concrete approved need and teardown after verification.
6. Reconcile billing grace with Apple's full subscribed-service requirement if grace is configured or any current entitlement is in grace. Do not enable grace while the client or backend withholds that service.
7. Present the final exact cutover and rollback packet for explicit approval. Refresh the UTC time, production free flag, policy revision, Apple price schedule, compatible client availability and retention state immediately before any approved transition. A date in a notice cannot activate paid access.

## Rollback

Use a reviewed compare-and-swap on the same protected phase policy with a newer revision, returning to `free_beta` while leaving the legacy free-policy row enabled. Preserve recorded participation, subscriptions, receipt processing, data and paused destructive retention. Do not drop schema, restore old chart JSON or require an app reinstall. Verify the server readback and the compatible client in an already open Plan/Upgrade view; a database flag alone does not prove client rollback.

An access rollback does not cancel subscriptions, refund charges or reverse Apple price schedules. Those are separate customer and Apple actions. Disconnected clients converge on reconnect. Previously distributed static paid binaries require an update and cannot be included in a universal remote rollback claim.

## Evidence boundaries

Keep source review, unit tests, Simulator observations, hosted CI, archive verification, live backend readbacks, genuine Apple Sandbox events and physical iPad preservation evidence separate. Publish only reviewed source and operational documentation. Private ink, customer readbacks, credentials, local QA receipts and device backups remain outside GitHub.
