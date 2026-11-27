# December 1 production-paid release preparation

This is a preparation record, not production activation approval or a delivery
receipt. The target is **December 1, 2026 at 09:00 America/Los_Angeles (PST),
17:00 UTC**, selected by the owner on November 27. Keep public free Pro ON until
the final reviewed cutover. Reaching that time does not activate anything.

## Source and package

The accepted feature source is `04ccbbeb8fe3749725c3910d9a6c8c7b98514db9`,
with all eight commits after `d44b02e6cc16586880d72e9ea2c8188a97a263ee`.
It includes the Build 200–205 PDF import/review, paper measure placement and
movement, gap selection and drag/resize, contextual spelling, rapid mixed
writing, and partial-height barline fixes, with their guidance and tests.
The final release head will also include the reviewed pricing, packaging and
production-backend routing changes. Feature receipts do not certify that later
combined head; execute its hosted checks and paid validation separately.

The selected production identity is **1.9.4 (208)**. A separate, internal-only
isolated billing-QA artifact uses **1.9.4 (207)** through its reviewed build
override. Apple’s TestFlight upload history on November 27 showed 199 as the
newest uploaded build, with no newer or pending
upload visible. The current App Store version remained 1.9.3 (161), Ready for
Distribution. Build 206 belongs to retained prior held attempts; development
Build 205 was an override. These source allocations are not Apple reservations.
Recheck upload reservations before delivery.

`project.yml` keeps the normal free-beta defaults. A separately generated and
verified production-paid Release project enables `ICHART_PAID_SUBSCRIPTION`
only for the iChart target. No staging or local-QA conditions, personal models,
private fixtures, credentials or debug payloads belong in the distribution app.
Keep the existing strict public-beta verifier intact; its Build 199 procedure
is historical and does not certify this paid candidate. Use the separate paid
validation and packaging procedures for this artifact.

**Hold paid distribution pending coordinated validation.** The earlier static
paid candidate selected paid gates immediately and skipped beta reconciliation;
its retained signed archives are prior attempts, not final artifacts. The
coordinated production client uses the authenticated runtime phase described in
[the coordination procedure](paid-rollout-coordination.md). Its library gates,
Plan, Upgrade, How To and fresh checkout admission must agree on the phase.
Missing or unsupported status blocks checkout without deleting saved work.
Only same-head native evidence and the separately verified installed backend can
establish preactivation safety. Do not assign an unverified candidate to an
automatic TestFlight group, install or publish it. Artifact integrity and
delivery authorization remain separate.

## Live readback on November 27

These observations expire; repeat them before the final decision.

| Surface | Observed state | Required before cutover |
| --- | --- | --- |
| Supabase free access | Free Pro enabled; deferred paid migrations absent | Preserve free access until final reviewed sequence |
| GitHub integration | Deploy to production OFF; automatic branching OFF | Keep both OFF; deploy reviewed backend changes explicitly |
| Temporary backend | Owner approved a new data-less QA branch and teardown; `yiuxduqhhbucsmooevxz` was created November 27 at 19:52 UTC | Verify its schema, disable inherited scheduled jobs, and use only synthetic QA data; restore any separately approved Sandbox routing before teardown |
| App Store products | Both production products Approved | Recheck availability, metadata and fetched prices |
| US monthly | $7.99; no upcoming change | Reviewed $6.99 schedule |
| US annual | $64.99; no upcoming change | Reviewed exactly $60.00 schedule; no $59.99 substitution |
| Production service levels | Monthly level 1; annual level 2 | Review putting both at the same Pro level before changing crossgrade behavior |
| Billing Grace Period | UI offers Set Up Billing Grace Period | Preserve unconfigured; inspect any existing grace entitlements |
| Agreements | Free and Paid Apps Agreements Active; payment/tax status Active | Recheck without changing legal or payment details |
| Notifications | Production and Sandbox URLs both point to production notification handler | Preserve routing; verify deployed code, permissions and Apple-verified processing |
| Advance pricing notice | Initially NULL; owner-approved notice `paid-plans-2026-12-01-v1` published November 27 and verified at 10:06 a.m. PST | Verify notice availability; do not claim every user has seen or acknowledged it |

Existing production grace entitlement counts were zero. The absence of current
grace does not authorize enabling grace with a partial-service policy. The beta
notice acknowledgement is stored locally per account/iPad; there is no server
acknowledgement count proving that every user has read a notice.

The approved 752-character notice distinguishes future iChart 2.0/offline
recognition plans from the 1.9.4 release preparation. The alert publication
preceded the later coordinated candidate and build-number allocation. Its publication changed
only the four notice fields. Live readback confirmed the exact body, free Pro
still enabled, paid policy still absent, and the beta RPC returning notice fields.
The ending timestamp remains informational. No prices, billing, build delivery or
paid activation changed. Installed clients append their existing fixed footer;
changing that footer in a draft does not change those installed clients.

The production product IDs remain `com.ichart.app.pro.monthly` and
`com.ichart.app.pro.annual`. Source targets are 699 and 6000 US cents. Product
labels use Apple's fetched localized prices. The source change does not
change Apple's catalog, existing customers' bills, or foreign storefronts.
Price decreases on existing subscriptions affect renewal pricing; review that
effect before scheduling changes. See [Apple's subscription pricing guide](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions).

A later November 27 read-only preview confirmed that **$60.00** is an available
US price point for the actual production annual product under **See Additional
Prices**. The preview was cancelled without choosing a price or date and without
saving a schedule. This proves availability of the exact target, not live pricing.

## Review-access clarification and isolated QA

The owner approved sending the exact prepared review-access question. Apple
Developer Support accepted it under **case 103026634749** on November 27 through
App Review → Other App Review questions. It explains that ordinary production
review access remains in the free phase, with purchase controls and PDF/setlist
cloud unavailable, and asks whether clearly labeled isolated evidence is
sufficient or direct access in the submitted binary is required. No answer or
App Store submission is claimed. Do not create a hidden reviewer override or
activate customers to resolve this question.

The new QA branch is authorized at $0.01344/hour plus normal storage/usage charges,
with teardown after verification. The coordinated QA capability, separate
namespace, exact endpoint and Sandbox product routing require their own reviewed
source and artifact checks. Historical static staging evidence does not certify
this lane. Public free Pro, production pricing, production notification routing
and automatic production-deployment settings stay unchanged. App-wide temporary
Sandbox routing and a tester purchase-history reset require separate explicit
approval before those actions.

## Access and saved-content requirements

Both chart styles and core writing/editing/export remain Free. Basic's
three-chart cap applies to new creation and duplication. It must not delete
existing charts, lock editing above the cap, or require selecting three charts
before saved content opens. Existing Projects remain visible and read-only;
their charts remain editable and exportable. Preserve original ink, applied
Pro fonts, converted charts, downloaded/original PDFs and local setlists after
downgrade, expiry, unavailable billing, restore, relaunch and reopening.

Phase caching and paid billing verification are separate. The coordinated client
retains the existing strict billing-unavailable policy: an ownerless paid value
from archived chart JSON is not current-account proof after restart. New Pro
creation/tools can require renewed owner-bound verification, while the saved-work
rights above remain intact. This preparation does not add an offline paid
billing-authority cache. Unknown phase uses a nonmodal checking state.

No billing change creates an iPad data migration. Do not re-enable the older
destructive retention/pruning workflow as part of this rollout. Keep the
historical retention worker paused while its obsolete locking/deletion behavior
is separately reviewed. Explicit account deletion is a separate user action.

The current grace policy pauses cloud and some Forum/PDF-setlist services.
Do not enable Apple's Billing Grace Period with this policy. Apple requires
continued service during enabled billing grace; if existing customers are
already in grace, resolve full-service handling before launch even when new
grace is disabled. See [Apple's billing grace guide](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions).

## Required verification

1. Review the combined source and keep all eight accepted commits represented.
   Pass exact-head PR SwiftPM, Simulator, CodeQL analysis/upload, dependency
   review and backend contract checks. Do not count skipped or zero-selected
   test jobs as execution.
2. Run the dedicated production-paid Release tests with paid conditions on the
   app and test targets only. Exercise real paid `.current`, catalog, public
   namespace, backend routing, Basic/active/expired/unavailable behavior and
   existing chart/ink/Project/font/PDF/setlist persistence tests. Normal free CI
   must retain its strict free-beta assertions.
3. Archive/export the exact committed source using Apple Distribution and the
   current App Store profile. Verify optimized native compiler evidence, source
   and project pins, normal production backend/public auth namespace, no local
   QA/staging/Debug conditions, signatures, active entitlements, profile expiry,
   arm64/dSYM agreement, export changes and final IPA hash. Retain the held
   release-policy receipt; this is not a TestFlight processing receipt.
4. Audit each pending migration, worker and claim/notification handler together.
   Do not blanket-push migrations. Validate owner isolation, account deletion,
   verified Apple authority, notification idempotence and current access rules
   in an isolated local database before proposing explicit production changes.
5. Complete monthly and annual purchase, restore, renewal cancellation through
   paid-through, expiry and re-upgrade evidence for the final policy. Historical
   staging success is separate evidence; annual expiry was not established.
   Sandbox does not prove that a production customer has been billed correctly.
6. Verify the user-approved bounded legacy compatibility: strictly verified
   paid owners retain old local Pro gates without rewriting beta membership or
   billing; expired or unverified owners do not. New clients consume truthful
   phase status, and server service authority must never consume compatibility
   JSON. Older free builds retain **Pro — Free** labels and lack modern paid
   controls until updated. Include these limits and the update path in final
   approval; the bridge does not make old binaries complete paid clients.
7. Review the actual Apple price schedules, equal service levels, metadata,
   review notes and manual release controls before any Apple changes/submission.
   State explicitly which customers and renewals change. A desired date is not
   a guarantee of Apple's review or propagation time.

## Cutover review and rollback

Prepare a private packet containing the immutable source/CI receipts, separate
paid test and packaging receipts, live aggregate backend readbacks, exact
ordered migration/function changes and rollback SQL, Apple catalog changes and
renewal effects, reviewer instructions, and unresolved gates. Obtain final
production approval on that concrete packet. No automatic activation task is
created by this preparation.

Use the reviewed paid-feature policy control; do not infer that the legacy free
flag is the paid activation switch. Read its deployed definition and effective
access result before changing anything. Retention suppression and old clients
can depend on the legacy flag staying true. Verify the current production
policy, routing and access after each separately authorized change.

If access, billing or preservation checks fail, stop distribution and restore
the reviewed free-access policy. Leave source work recoverable, retain paid
transaction/notification records, and leave destructive retention paused. Do
not cancel customers' Apple subscriptions, refund, delete content, reverse
schema blindly, restore an old iPad writer or change live prices as an implicit
rollback. Each affected surface needs its own verified rollback action.

Coordinated rollback must advance the protected policy revision and return the
compatible client to the real beta policy, preserving voluntary Basic choices
and billing truth. Verify it in an existing Plan/Upgrade view and before a new
checkout; a database readback alone is not client proof. Disconnected clients
converge on their next successful refresh. Earlier static-paid binaries require
an update and remain outside the remote rollback guarantee. Restore, Manage and
accepted transaction verification continue through rollback; already opened
Apple sheets and completed charges cannot be undone by an access flag.

No new physical iPad install or restart is authorized here. The current device
is development Build 205 with newer saved data. A later direct or automatic
TestFlight update requires fresh saved-work confirmation, two stopped-app
backups, saved-format compatibility and post-install/relaunch preservation
checks. Do not complete the superseded Build 199 installation request.
