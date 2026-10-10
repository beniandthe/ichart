# iChart StoreKit Subscription Runbook

Status: StoreKit/Supabase authority loop wired; App Store Connect products configured; TestFlight sandbox QA active
Created: 2026-06-12
Last updated: 2026-10-09

## Current resume point — October 9, 2026

The bounded build-74 Sandbox entitlement/cloud recovery gate and local
distribution archive/export have passed, with the coverage and receipts in
[project state](project-state.md) and the
[cloud gate record](cloud-backup-release-gate-2026-10-07.md). The sections below
remain configuration/reference guidance, not instructions to recreate the
already configured products or repeat a purchase.

**Build 75 is installed and launched under build/install-only authorization.**
Fresh focused tests, signature/provisioning checks and saved-content preservation
passed. The latest privacy revision is installed as the same `1.2.1 (75)`; on
October 9 the user reported **“Both passed”** for its short privacy/legal,
keyboard/Scribble review, render/save/reopen/PDF and Free Ink rotation checklist
in Simple and Rhythm. This is not a full stress/recognition assessment or an
Apple offer-fulfillment pass. See the
[current privacy delivery and physical receipt](privacy-telemetry-release-closeout-2026-10-09.md).
No upload, public
release or public campaign activation is authorized. App privacy repairs and the objective
pre-build cleanup are locally implemented and tested. The annual savings badge
now uses comparable fetched StoreKit prices, rounding down or omitting an
invalid comparison; target prices are used only by the separate Debug local
preview. The user has now approved parking all handwriting setup, teaching,
evaluation and runtime personalization for the next build, retaining saved data.
The complimentary-Pro audience is **new, returning/expired and existing users**.
The user selected **one calendar month free, followed by automatic paid renewal**
unless the customer cancels. Apple purchase acceptance is still required; this
does not authorize silently restarting canceled subscriptions. One recorded
active annual subscription is the known existing-subscriber case. The app flow,
authenticated signer and campaign ledger are implemented locally. The delegated
claim-window decision is 90 days beginning with the actual public release.
Matching monthly/annual promotional definitions are saved in App Store Connect;
the approved signing key is protected in iChart's server secrets and verified.
The ledger and authenticated offer endpoint are deployed; public activation
remains off, separate from the restricted temporary Sandbox QA window below.
The Sandbox QA-owner guard is implemented, tested and deployed. Its later
same-owner history/status gate passed, and the user has approved a temporary
Sandbox-only monthly acceptance setup: 18:09–18:45 UTC on October 9
(11:09–11:45 AM Pacific), restricted to the verified QA owner. Monthly is
available for next-billing promotional scheduling; annual crossgrade was refused.
The user's tap later failed at the status-request stage without an Apple sheet;
that first test was closed/disabled and its dates removed, with ledger 0/0/0.
The user then approved focused visible feedback and fixed-category QA diagnostics.
That revised build 75 is installed/launched after **85 native tests passed, zero
failures/skips** and saved-content preservation. The controlled same-owner
Sandbox retry presented one month free at the next monthly billing event, then
the user approved it. Apple's verified `OFFER_REDEEMED` notification arrived at
18:45:40.873 UTC; the QA server subscription remains active and auto-renewing.
**Initial confirmation/recovery failed:** the ledger was prepared with two attempts
and no benefit. A normal relaunch returned
`pending_campaign_offer_not_verifiable` and persisted unavailable client access
despite the active server subscription. A subsequent focused repair restored
Pro on the installed iPad without granting access from the gift. Read-only,
fixed-category checks identified the pending renewal as `PAY_UP_FRONT` + full
`P1M` + numeric zero, while the old validator required `FREE_TRIAL`. This isolates
the scheduled-term mismatch; actual redemption/renewal is still open. Saved chart/
ink, PDF, setlist and profile/evaluation content is separately unchanged, but
full-state preservation failed because client access/selection changed.
The authorization cutoff was shortened to **18:50 UTC**, then the campaign was
fully disabled and temporary dates removed after capturing the recovery failure.
The QA-owner guard and ordinary billing/signing configuration are unchanged.
Full disablement suspends campaign recovery; pending purchase context and ledger
remain preserved. **Do not repeat a purchase or switch accounts.** The separately
authorized existing-purchase-only private QA recovery now passes: ledger state
is scheduled, its first benefit is recorded with the verified next-billing start,
the same two attempts remain, Pro access stays active and the matching local
pending marker cleared naturally. Final tests pass **113 native / 469 server**,
zero failures/skips, and the revised **1.2.1 (75)** is installed/launched. Both
temporary QA cutoffs are removed, purchase dates absent, campaign still disabled
and ordinary billing/signing unchanged. This is not actual free-period redemption
or paid renewal, nor new/returning/annual customer validation. Apple acceptance is
established, but benefit fulfillment, free-period/renewal and device failure-
feedback acceptance remain open. See the
[current access and pending-term receipt](project-state.md#access-recovery-and-pending-term-diagnosis--october-9)
and historical
[guard receipt](project-state.md#sandbox-qa-owner-guard-inactive-deployment-receipt--october-8).
Introductory dates and verified Apple fulfillment remain open.

**Latest continuation:** the completed promotional predicate now accepts
only the exact configured product/offer, `P1M`, numeric actual transaction price
zero and `FREE_TRIAL` or `PAY_UP_FRONT`. Introductory validation is unchanged.
The native prepared-next-billing recovery accepts an actually completed matching
confirmation while preserving the still-scheduled branch. Actual dates, not
estimates, are required. **115 native / 487 server tests pass**, zero failures/
skips. Under separately approved focused scope, the endpoint is now **version
38**, JWT enabled, with every deployed file matching tested source and the other
six services unchanged. The new native revision is now Development-signed,
installed and normally launched as **1.2.1 (75)**, replacing the preceding
113-native installed baseline. Signature/profile checks pass; the running
executable matches the newly installed bundle and launch uses no diagnostic or
purchase flags. Fresh native-delivery snapshots preserve all 19 saved files'
chart/ink/PDF/setlist/profile/evaluation content, selection and current Pro
plan/status/expiry/auto-renew fields. Backup/sync/verification timestamps changed;
this is not strict full-state identity or fresh Pencil/visual acceptance. See the
[native delivery receipt](project-state.md#completed-offer-native-delivery--october-9).
Four authenticated monthly/annual status responses pass disabled/no-attempt/
no-signature checks. Normal launch restores diagnostic-free operation; all
19 saved files' chart/ink/PDF/setlist/profile/evaluation content is preserved.
In the earlier backend smoke, Pro plan/status stayed active; verified refresh
filled previously missing expiry/
auto-renew metadata, so strict entitlement/full-state identity is not claimed.
Campaign remains off, all temporary dates absent and ordinary signing/billing
configuration unchanged. Disabled QA recovery is still scheduled-only; no window
was opened. See the
[deployment receipt](project-state.md#completed-offer-focused-inactive-deployment--october-9).

The next no-new-purchase Apple gate is the existing monthly schedule's start,
**October 10 at 8:42:40 AM PDT**. Current database rows still report scheduled,
actual end null, active/auto-renewing ordinary Pro and two attempts. Require a
fresh verified completed transaction, original actual dates, exact product/offer,
zero-charge terms and later paid renewal before calling fulfillment complete.
Do not infer completed payment mode from the prior signed pending renewal.
New/returning/annual cases remain separate, with legitimate isolated QA histories
and purchase-specific approval. See the
[completion repair receipt](project-state.md#completed-offer-and-billing-boundary-local-repair--october-9).

Production/public offers are not activated. The offer-specific continuation
changed no base product/price, entitlement, notification setting, server retention
or store policy. The later, separately approved telemetry-only retention
deployment and unpublished policy draft are recorded in the
[privacy closeout](privacy-telemetry-release-closeout-2026-10-09.md); its first
real scheduled run remains open. See the
[current cleanup decisions](project-state.md#pre-build-75-cleanup-and-decisions--2026-10-07).

Resume trigger: after Apple product, Supabase secret, or Edge Function changes,
repeat the applicable bounded smoke checks before continuing Sandbox purchase QA.
Do not run `scripts/resume_apple_developer_gate.sh` blindly: its legacy global
Sandbox-environment setup is not authorized by the isolated campaign plan.
Keep the ordinary claim verifier's environment unchanged.

## Complimentary Pro campaign — design, not an activated offer

The October 8 decision is **one calendar month of Pro free, then automatic paid
renewal at the selected plan's standard Apple price unless canceled**. This
supersedes the earlier proposed nonrenewing gift. Each new or returning customer
must accept the offer in Apple's purchase flow before paid renewal is enabled.
Show the selected monthly or annual plan, actual localized renewal price,
billing interval and cancellation terms before acceptance. Do not describe
annual renewal as a monthly charge or silently resubscribe an expired customer.

The user delegated claim timing. Allow **90 days from actual public release**
for new authorizations so returning users have time to install the update.
No absolute start/end dates or customer's free-month clock have been started.
Set exact server UTC timestamps at release, then align introductory offer dates
per Apple storefront (its date boundaries follow the storefront's time zone).
Do not activate introductory offers during cleanup: Apple can show them on the
App Store product page independently of this new client or campaign switch.
At cutoff, reject new preparation but keep authenticated recovery available for
previously accepted/pending benefits. This is an **authorization deadline**, not
a guarantee that Apple stops accepting every outstanding offer at that instant;
already-issued promotional signatures retain Apple's 24-hour validity, and
pending introductory approval may complete later.

Operational basis: the October 8 read-only backend lookup found one current
production annual entitlement, one active Sandbox entitlement and no other
current production rows. Use the annual subscriber as the known compensation
case; do not hardcode that person's identity or assume the database is a complete
Apple buyer ledger. Unlinked purchases may be absent, and the production row's
last verification was September 16. Actual billing state, not an email/account
allowlist, must choose the offer path. No customer contact identifiers belong in
source, ordinary telemetry or this runbook.

### Implemented mechanism and known limits

Use the normal, account-token-bearing StoreKit purchase path:

- **New or lapsed, introductory-eligible:** configure a Free one-month
  introductory offer on the selected monthly/annual product. Apple eligibility
  is per subscription group, not per iChart login or device reinstall.
  [Apple introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions).
- **Previously subscribed, introductory-ineligible:** configure a Free
  one-month promotional offer and provide an authenticated, server-signed
  purchase option. Prior use of an introductory offer does not exclude this
  cohort. Keep `appAccountToken` in the same purchase and signature binding.
  [Apple promotional offer setup](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions),
  [implementation](https://developer.apple.com/documentation/storekit/implementing-promotional-offers-in-your-app).
- **Known active annual subscriber:** use a separate same-product promotional
  offer. Its period starts at the next billing event, not immediately during
  an already-paid year. Verify scheduled benefit and subsequent annual renewal;
  do not refund, crossgrade or shorten the paid term as part of this plan.

Both monthly and annual base products support a Free one-month offer. The app
now validates fetched free-trial, zero-price, one-calendar-month metadata and
Apple introductory eligibility; promotional purchases use the authenticated
server signer. The local StoreKit configuration's introductory offers remain
null and its promotional inventory remains empty: no fictional configured offer
was added to the baseline. October 8 live App Store Connect inspection found no
introductory/promotional offers on either product. The two matching Free/1 Month
promotional definitions were then saved and visibly verified in 175 countries
or regions each. Both introductory pages remain empty; dates/activation are
deferred until release. The server campaign remains off.

Both current base products have Family Sharing off. Monthly and annual remain
at their existing subscription-group levels (1 and 2 respectively); do not
reorder them or change a base plan to deliver this gift. The public 1.2.1 listing
referenced build 51 at the October 8 inspection; locally tested/installed build 75 is not evidence
that this offer flow is in the App Store version.

For active customers, match the offer to the current monthly or annual product.
Do not crossgrade an annual subscriber into monthly just to supply the gift.
Apple distinguishes a current offer from an offer scheduled for a later renewal.
Therefore offer acceptance alone does not prove an immediate extra month or a
particular future charge date. Confirm the scheduled benefit and subsequent
renewal in Sandbox on the existing annual product, including cancellation.
[Apple current/pending offer handling](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app),
[subscription lifecycle guidance](https://developer.apple.com/app-store/subscriptions/).

Do not use a local Pro override: it does not change Apple billing and cannot
authorize server-owned cloud/Forums access. The selected introductory plus
promotional approach now matches the approved automatic-renewal terms and
avoids introducing tokenless code redemption as the main entry path.

Renewal-date extensions are a conditional compensation alternative for eligible
paid subscribers affected by service problems, not a general free-trial API.
Eligibility, purpose and limits must be checked; extension writes cannot be
reversed. Do not mass-extend or claim eligibility based only on this design.
[Apple renewal extensions](https://developer.apple.com/documentation/appstoreserverapi/extending-the-renewal-date-for-auto-renewable-subscriptions).

### Required outcome by customer state

The expected outcomes below are our acceptance requirements, **not recorded
Sandbox results**. A cohort is not covered merely because Apple allows a code.

| Customer state | Required outcome / handling |
| --- | --- |
| New, never subscribed | One-month introductory trial on the customer's selected plan, then paid auto-renewal unless canceled. Require Apple acceptance and verified access. Display actual trial end date and renewal price/interval. |
| Returning after expiration, including prior trial/code use | Introductory trial if eligible; otherwise the signed one-month promotional offer. Require explicit Apple acceptance before restarting renewal. Restore charts, preserve identity and prevent a second campaign benefit. |
| Active monthly, auto-renew on | Preserve the monthly plan and paid term. Confirm an actual free additional period/charge-date benefit and what renewal follows it before offering a success message. |
| Active annual, auto-renew on | Same requirement on the annual product; do not replace an annual paid term with monthly access. If deferred, show the signed scheduled start and explicitly distinguish an estimated end from the actual redeemed end; do not call it active now. |
| Canceled but not expired, monthly or annual | Treat as currently entitled, not lapsed. Preserve the paid term until the customer accepts a clearly disclosed offer. Acceptance may enable renewal; verify its free-period scheduling and post-offer billing state. Never restart renewal silently. |
| Grace or billing retry | Do not equate offer eligibility with recovered billing or full Pro. Establish whether the gift is active, scheduled or rejected. Do not double-charge outstanding billing or falsely report cloud access while the current grace policy pauses it. |
| Current free introductory/promotional/code offer or pending offer | Inspect current and pending terms. Preserve the existing benefit; do not replace/stack offers without verified behavior and clear consent. A scheduled gift is not an active entitlement. |
| Family recipient | Confirm whether Family Sharing is actually enabled for these products. If included, verify the recipient's full cloud/Forums entitlement, not just local StoreKit access. The current account-binding path does not support this case; do not omit it silently or claim coverage. |
| Signed out, different iChart account, or changed Apple Account | Authenticate the correct iChart account before account-linked fulfillment. Never move another account's subscription automatically. Keep an explicit recover/retry path that preserves charts and explains which verification is pending. |
| Offline, redemption canceled, pending or verification failed | No false success and no paid fallback. Preserve current valid access and retry state. Do not start a local gift clock that will expire before server verification. |
| Reinstall, second device or repeated request | Recover the original verified benefit and dates. Do not reset the clock. Concurrent claim, notification and redemption processing must be idempotent. |
| Refund, revocation or expired benefit | Apply verified lifecycle state. Do not let a stale cache or replayed transaction revive revoked access. Do not erase charts, PDFs or free ink when access changes. |
| Unsupported storefront, unavailable offer or ineligible redemption | Preserve current access and explain unavailability without silently invoking a paid purchase. Resolve any uncovered cohort before advertising universal coverage. Code exhaustion is relevant only to the parked alternative. |

### Local implementation — October 8

`IChartComplimentaryOffer.swift` owns the strict request/response and offer policy;
the StoreKit store implements status, prepare, Apple purchase, normal verified
subscription claim, campaign confirmation and unfinished-transaction recovery.
Both purchase surfaces display fetched renewal terms and keep standard paid
plans visibly separate. Cancellation/pending/failure is not success, and the free
action never falls through to the normal paid purchase or Simulator preview.
Ordinary paid transactions must remain independent of the optional campaign
endpoint; known campaign transactions must stay recoverable if it is unavailable.

The new `storekit-complimentary-offers` function authenticates the owner with
Supabase Auth, reads fresh signature-verified Apple history/status and preserves
the existing claim/token-binding authority. The signer uses server-only P-256
key material and a fresh single-use nonce/signature per explicit buy request.
Retrying the same preparation request is distinct from making another Apple
purchase request. The CLI-created migration
`20261008173453_storekit_complimentary_campaign.sql` adds client-inaccessible,
RLS-enabled bookkeeping and restricted row-locked RPCs. Preparation does not
grant access or consume the benefit; the first verified benefit is immutable.
This ledger cannot make database writes and Apple processing globally atomic.
Delayed signatures and Apple's eventual consistency still require live tests.

Campaign accounts, attempts, locks, CAS, confirmation and original-chain
uniqueness are scoped by **campaign + Apple environment + owner**. Sandbox
testing cannot consume the same owner's Production campaign benefit. Cached
subscription seeds also have to match the campaign environment. The existing
normal subscription authority still stores one row per owner and is unchanged:
use a separate QA iChart account for Sandbox purchases, not the known paid
Production owner's account.

The persisted authorization timestamp is the server reservation timestamp,
not proof of when an Apple buy was launched or a signature returned. Fresh
preparation checks the clock before lookup, after fresh Apple verification,
after DB reservation and after asynchronous signing. If cutoff is crossed,
no signature/new authorization is returned. Post-cutoff status can return a
matching prepared attempt with `canPrepare:false` and no signature for recovery
only; the client rejects it at both fresh-offer and purchase-authorization
boundaries. A late introductory completion requires a same-owner/product/
environment predeadline introductory authorization plus the existing verified
claim and fresh Apple-verified exact Free/P1M/zero-price transaction purchased
no earlier than that authorization. It does not manufacture a grace period or
grant an entitlement from the campaign ledger.

An expired, unrevoked, non-upgraded exact verified gift stays `redeemed` with
its original immutable Apple dates, allowing recovery to finish and the client
to show **ended**, not renewed access. Revoked/upgraded/invalid-term evidence
remains unavailable. Terminal revoked/upgraded transaction finishing is not
established by this pass and remains a focused lifecycle QA case; do not call
all recovery states covered based on the ended-gift check.

Fixed campaign ID: `ichart-complimentary-pro-1m-v1`. Promotional offer IDs are
`ichart_complimentary_monthly_1m_v1` and `ichart_complimentary_annual_1m_v1` on
their matching products. Server configuration requires:

- `ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED=true` only for explicit activation.
- `ICHART_COMPLIMENTARY_CAMPAIGN_STARTS_AT` and
  `ICHART_COMPLIMENTARY_CAMPAIGN_ENDS_AT`: 90-day public-release claim window, not a locally
  calculated customer's access period.
- `APP_STORE_SUBSCRIPTION_KEY_ID`, `APP_STORE_SUBSCRIPTION_KEY_P8` and
  `APP_STORE_ISSUER_ID`, plus the existing bundle/verifier configuration.
- `ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT`: optional explicit `Sandbox` or
  `Production`, defaulting to `APP_STORE_ENVIRONMENT`. An invalid override
  disables the campaign. It does not change the existing global claim verifier.

Two separately approved QA controls are **absent by default**, require explicit
Sandbox plus the exact singleton QA owner, and reject a cutoff more than one
hour away. They do not configure a public claim window:

- `ICHART_COMPLIMENTARY_SANDBOX_DIAGNOSTIC_ENDS_AT`: disabled-campaign,
  status-only read of fresh matching Apple evidence, with fixed boolean/category
  output. No benefit recording, reservation, confirmation or signing.
- `ICHART_COMPLIMENTARY_SANDBOX_RECOVERY_ENDS_AT`: disabled-campaign status/confirm
  recovery of the existing current scheduled-promotional attempt. Requires the
  trusted same-owner chain and fresh verified scheduled terms; confirm also
  requires matching verified supplied JWS. It may record only that existing
  scheduled campaign benefit through the attempt-matching recorder. Response
  remains `enabled:false`, with `recoveryOnly:true`, `canPrepare:false`, no
  signature and the saved attempt. Preparation/signing and ordinary entitlement
  grants are unavailable. Native acknowledgement requires the matching account,
  product and unchanged local attempt; it is not an Apple transaction finish.

Remove these QA cutoffs when their separately authorized checks end. Runtime
configuration is constructed at isolate initialization: secret deletion alone
is not proof that every warm isolate changed. Redeploy/restart and verify a
fresh disabled response; the fixed deadline also expires fail-closed throughout
each request.

Missing/invalid configuration fails closed. Following explicit approval, the
`iChart Server Offers v1` In-App Purchase key was created and its three signing
settings stored in iChart's protected Supabase Edge Function secrets. Remote
digests match the approved download; all preexisting secret digests are unchanged.
`ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED=false` was set and verified before storing
the credentials. No campaign timestamps are set. The ledger and endpoint are
now deployed; the live handler reports disabled. Client roles cannot read/write
the ledger or execute its RPCs. Temporary plaintext download/staging files were removed after
verification; Apple's one-time download cannot be repeated, but the protected
server copy remains. Only the new migration and named campaign function were
deployed; existing function code/versions/JWT settings are unchanged from the
post-key-staging baseline. No introductory configuration or live activation has
occurred. Keep `ENABLED=true` after the
normal deadline for accepted-benefit
recovery; **`ENDS_AT` closes new authorizations**, whereas disabling the function
would also prevent normal recovery. The explicit, short-lived private Sandbox
exception above is not a production recovery policy. Emergency disable remains a separate safety action,
not the ordinary campaign sunset procedure.

### Parked alternative: offer-code account association

The selected ordinary iChart purchase path attaches the authenticated account UUID using
`appAccountToken`. The current claim authority rejects tokenless transactions
with **422** and mismatched ownership with **403**. The installed SDK's existing
offer-code sheet has no app-account-token option. A new customer's external
redemption can therefore succeed at Apple and still fail full iChart Pro
verification. This blocker applies to the parked offer-code alternative, not
to a correctly token-bound introductory/promotional purchase. Do not distribute
external codes or relax existing ownership checks as a shortcut.

Relevant source: `iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift`
(`storeKitPurchaseOptions` and the authenticated claim service), and
`supabase/functions/_shared/app_store_subscription_authority.mjs`
(`appAccountToken` checks). No account-binding checks were relaxed in this pass.

Apple's Set App Account Token endpoint supports external code purchases but
can overwrite a token, affects current/future subscription renewals rather than
past transactions, and does not support `FAMILY_SHARED`. It is not permission
to assign an arbitrary tokenless receipt to its first claimant. A recovery
implementation must establish ownership, refuse reassignment, handle concurrent
requests and re-verify fresh Apple data before changing authority.
[Apple token association API](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token).

Apple also describes newer redemption options and a returned verification result
for Xcode 27. The installed Xcode 26.6 StoreKit interface contains only the older
UIKit sheet signature. This pass did not install a new toolchain or assume the
new API can be deployed to all supported iPads. A future SDK path still needs
OS availability and external-redemption recovery.
[WWDC26 redemption changes](https://developer.apple.com/videos/play/wwdc2026/210/).

### Bounded implementation sequence

1. Duration/renewal and window are decided: one calendar month, then paid
   auto-renewal unless canceled; new authorizations available for 90 days after
   public release. No absolute clock or campaign has been activated.
2. Matching monthly/annual promotional definitions are saved and verified.
   Configure introductory dates at release without overwriting another offer.
   Verify the known active annual case separately using a QA account/Apple state;
   do not purchase or mutate the real customer's paid subscription for testing.
3. The authenticated signer and offer selection are locally implemented using
   verified Apple history/eligibility, not mutable profile data. Keep the existing
   owner-token claim contract and one-benefit-per-campaign rule. Do not expose
   signing keys or issue unsigned/client-authorized promotional grants. The
   signing credentials are staged and verified; the migration/function inactive
   deployment gate has passed. The campaign is still off.
4. The free-month action/status is locally implemented. Validate available,
   awaiting Apple, awaiting iChart verification, scheduled, active and ended.
   Display dates from verified authority and the actual fetched offer terms.
   Do not advertise a free month or silently fall back to a paid-only purchase
   if eligibility/signing/offer metadata fails. Consume transaction updates,
   unfinished transactions and current entitlements through the existing
   verification pipeline.
5. Verify the focused release cases: new monthly/annual, lapsed with/without
   prior introductory use, one active annual scheduled offer, cancellation,
   accepted/pending/canceled purchase, account mismatch, duplicate/reinstall
   and server/full-Pro delivery. Unexpected subscription states still need a
   safe outcome, but do not build a new billing system for hypothetical cohorts.
6. Only then set the release-aligned introductory dates and activate the
   Production campaign with the agreed terms. Record activation separately from
   saved promotional definitions and app tests/build/install.

For the parked code alternative, Apple limits redemption **per offer**, not per app campaign. Separate monthly
and annual offers therefore do not automatically give one gift total per
customer. Campaign deduplication, account recreation and outside-app redemption
must be handled explicitly. The new ledger covers token-bound app purchases,
not arbitrary external-code ownership association or account recreation. The
campaign must not depend on optional telemetry consent, and codes, receipts,
raw account identifiers or handwriting must not enter ordinary diagnostics.
At expiry, the normal entitlement policy applies without deleting stored work.

**Current result:** audience, one-month duration, automatic paid renewal and
90-day release claim window are agreed; handwriting flows parked;
introductory/promotional app flow, signer and environment-scoped ledger are
implemented locally. Monthly/annual promotional definitions are visibly saved.
Backend, synthetic SQL and native test receipts are recorded in
[project state](project-state.md#complimentary-pro-windowconfiguration-follow-up--october-8).
Approved key staging, offline legacy promotional DER verification and read-only
Apple Production/Sandbox authentication probes passed; the synthetic transaction
returned the expected `4040010` in both environments. This is not a real offer
purchase or scheduling test. The six existing deployed function code hashes and
JWT settings stayed unchanged; secret updates increased their platform revision
numbers by three. Evidence is recorded in the
[signing receipt](project-state.md#complimentary-pro-signing-key-staging-receipt--october-8).
The [inactive deployment receipt](project-state.md#complimentary-pro-inactive-deployment-receipt--october-8)
records live access/boot checks and the exact deployed migration version.
Introductory dates, actual Apple redemption/scheduling and
deployed full-Pro delivery remain open. No live commercial activation, renewal
extension or distribution action occurred. Build 75 now has a
[fresh test/build/install receipt](project-state.md#build-75-test-build-and-install-receipt--october-8):
147 native tests passed, 0 failed and 2 opt-in live tests were skipped. The
Development-signed app installed/launched and retained chart content/ink, PDFs,
setlist and handwriting examples. Startup-window logs show authenticated HTTP
200 calls to the disabled endpoint; response bodies and fulfillment were not
queried. This is not a live Apple offer or distribution gate.

### Next gate: isolated Sandbox purchase QA

Inactive deployment does not validate authenticated status/prepare/confirm,
Apple offer purchase terms, annual scheduling, transaction recovery or full Pro.
Build 75 now includes the new offer UI and is installed/launched with the
campaign disabled. The user has confirmed an existing chart opens normally. The user's
build/install approval does not authorize Sandbox campaign activation, offer
purchases, upload, public release, a Production claim window or commercial
activation. Obtain separate approval for the isolated Sandbox test setup and
purchase cases before changing its server window or starting a purchase.

Use a separate iChart QA account and legitimate Apple Sandbox tester, preserving
the existing populated iPad/account and the real active annual subscription.
Before enabling Sandbox QA, verify its Apple environment, the corresponding
test-only server window and isolation from Production. Never change the global
claim verifier environment, create synthetic production entitlement rows or
test by purchasing against the real paid customer's subscription.

#### Isolation prerequisite — fixed and deployed inactive

The planning check reproduced a non-QA owner reaching available Sandbox status
and campaign reads. The user subsequently approved a narrow server guard with
the campaign still off. The deployed version-2 handler now requires the
authenticated owner's membership in a valid server-only
`ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS` JSON array for every effective Sandbox
request, including the global-environment fallback. The array must contain
1–32 unique UUIDs; missing, malformed, empty, duplicate or oversized lists fail
closed. Status, prepare, confirm and recovery are guarded before campaign/seed
reads, transaction verification, Apple calls, reservation, recording or signing.
Non-QA status reports `enabled: false`. No client input or user-editable metadata
can grant access. Production does not read the QA setting.

Sources: `_shared/complimentary_offer_campaign.mjs` configuration and
`handleComplimentaryOfferRequest`; `_shared/complimentary_offer_runtime.mjs`;
`IChartStoreKitSubscriptionStore.swift`'s `complimentaryOffer(request:)`.
The ordinary claim adapter in `_shared/supabase_subscription_authority_store.mjs`
upserts with `on_conflict=owner_id`. Its production/Sandbox verification fallback
is unchanged; never claim Sandbox purchases on the real paid iChart account.

Validation: **237 backend tests passed, 0 failed, 0 skipped**; Node syntax and
cached Deno endpoint checks passed; independent review found no concrete
remaining bypass/regression. All 11 deployed source files byte-match the tested
deployment, JWT verification remains enabled, and **10/10 live inactive checks**
passed. Other deployed functions and all secret digests remain unchanged.
The campaign is off, dates and the QA-owner list remain unconfigured, and ledger
account/attempt counts remain **0/0**. Active live-QA requests, actual Apple
purchases, annual scheduling and full-Pro delivery remain unverified.
A test-isolated owner and genuine Apple Sandbox login are required. An empty
iChart QA account must not be paired blindly with an Apple history already bound
to another iChart owner. See the October 9 same-owner setup below.

#### October 9 realignment — inactive same-owner staging verified

The current iPad Apple login is shown in Developer → Sandbox Apple Account.
Fresh server evidence identifies its current iChart owner as Sandbox monthly,
with a matching purchase token, distinct from the Production annual owner.
Preserve this same-owner binding; no separate tester password or iChart account
switch is needed merely to stage its isolated campaign configuration.

The campaign is still disabled. An explicit Sandbox override and one-owner QA
allowlist are now staged; start/end dates are absent. Normal Apple claim settings,
signing-key digest and subscription authority are unchanged. Campaign accounts
and attempts remain zero. At this staging checkpoint, live signed-in status,
accepted purchases and fulfillment were not yet verified; see the later status
receipt below. This supersedes the requirement to switch to
the unverified empty candidate in the earlier preflight below, not the later
fresh-customer, lapsed-plan, annual, lifecycle or release gates.

Use only the authenticated same-owner app session for the next live lookup.
Do not mint a substitute session, reset credentials, clear purchase history,
crossgrade, or change a production subscription to establish a test state.
An active monthly subscription can qualify only for a same-monthly-product
next-billing promotional offer with verified consistent Apple renewal data.
Status may record a previously accepted benefit from Apple history even though
it cannot prepare a new purchase or issue a signature. Disable first before
removing a Sandbox override. The public campaign remains off.

#### October 9 live status gate — passed; campaign closed

After explicit user approval, a focused signer/runtime compatibility patch was
deployed only to the complimentary-offer service. All deployed source bytes
match the tested revision, JWT enforcement remains enabled, and other services'
code hashes/JWT flags are unchanged. Final local gates are 203 Node tests and
150 Deno tests plus 54 nested steps, all passing; native diagnostics passed
48 tests with no failures/skips. The portable JWT encoding was independently
verified with native WebCrypto, including the pinned Apple SDK/default client.

A genuine same-owner future-start status run returned monthly and annual
`campaign_not_started` responses at 18:01:50–18:01:53 UTC. Owner/schema/product/
campaign all match, the campaign was enabled for that isolated lookup, and the
valid nonempty owned Sandbox seed required fresh verified Apple status/history.
No signature or attempt was returned. This proves the live history/status path,
not promotional eligibility, purchase acceptance, annual scheduling or renewal.

The campaign was disabled and verified before removing temporary dates. Final
state is disabled, dates absent, explicit Sandbox/single-owner restriction
retained, normal Apple environment/signing-key digests unchanged, and ledger
accounts/attempts 0/0. The iPad is back in a normal launch with diagnostics off;
chart/ink, PDFs, setlist and saved handwriting data passed the final comparison.
An earlier post-deploy startup stall remains an unlocalized observation, not a
verified root cause or failed Apple result. Do not alter accounts to explain it.

Next: obtain separate approval for explicit Sandbox offer acceptance and a
bounded real claim window, then verify same-product Apple scheduling and the
later benefit/renewal/recovery. Do not enable a public campaign, configure
introductory dates or change a real subscription to make this test pass.
Full receipts are in [project state](project-state.md#same-owner-live-status-and-signer-compatibility-receipt--october-9).

#### Earlier staged execution plan — October 8 preflight (not executed)

The user has now approved isolated account/tester/window setup, not purchases or
public introductory dates. Read-only preflight found an empty iChart QA-account
candidate and the existing **iChart Sandbox** Apple tester. Further App Store
Connect access was denied by the browser permission control, so candidate logins
remain unverified and no test clock or server configuration has been started.
Resume account verification before staging or activation; do not infer lifetime
purchase history from Apple's blank last-purchase column.

1. **Isolation:** the code guard, local denied/approved controls, protected
   configuration baseline, rollback source and live inactive checks are complete.
   Live approved-cohort requests still need verified access to the now-authorized
   QA account and test window. Keep `APP_STORE_ENVIRONMENT` unchanged. Stage while
   disabled, enable last, and close the purchase-free setup with disabled status
   verified. Never remove the Sandbox override while enabled, because it falls
   back to the global Apple environment. Purchases require separate approval.
2. **Promotional path first:** on the separate QA account/tester, establish an
   Apple-verified Sandbox expired plan and test its matching promotional offer.
   Then test a Sandbox active annual plan's same-product next-renewal scheduling.
   Record the displayed terms, verified transactions, account binding, server
   access and the later free-period/paid-renewal events. Do not use a real paid
   subscription to establish either state.
3. **Introductory path separately:** the monthly/annual introductory offers
   remain unconfigured. Do not set dates just to make the first test pass:
   Apple states that configured introductory offers appear on the App Store
   product page for eligible customers, and product metadata may take up to an
   hour to reach Sandbox. The app's disabled campaign switch does not hide
   Apple's product-page offer. Actual-product fresh-user testing therefore needs
   a separately approved introductory-date/commercial configuration decision;
   local StoreKit simulation is only preflight, not proof of real fulfillment.
4. **Recovery and lifecycle:** test cancellation, pending/interrupted purchases,
   duplicate/relaunch/account mismatch, cutoff and already-accepted benefit
   recovery. Do not uninstall the populated iPad app for a recovery test without
   separate approval and verified backups. Keep ordinary chart/PDF/ink work intact.

Apple reference: [Sandbox testing overview](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox/),
[introductory-offer setup and visibility](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/),
and [Sandbox renewal/interrupted-purchase controls](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/).
These sources were rechecked on October 8; no Apple/Supabase settings or purchases
were changed by this plan.

For each case record Apple's displayed **one-month free** terms and subsequent
localized monthly/annual renewal, explicit acceptance, verified environment/
account binding, campaign state, ordinary server entitlement and cloud access:

1. Fresh monthly and annual introductory eligibility, including cancel/pending.
2. Lapsed monthly/annual with and without prior introductory use.
3. Active annual same-product promotional scheduling at the next billing event,
   followed by actual redemption and the unchanged paid annual cadence.
4. Retry, duplicate/relaunch/reinstall, account mismatch, window cutoff and
   accepted-benefit recovery. Revoked/upgraded terminal finishing stays open
   until separately demonstrated.

StoreKit configuration simulation, local tests and generic subscription restore
are not substitutes for Apple Sandbox evidence. Leave Production off and its
introductory dates unset until these gates and release approval are complete.

## Product IDs

The first Pro subscription products are:

- `com.ichart.app.pro.monthly`: $7.99/month
- `com.ichart.app.pro.annual`: $64.99/year

These IDs must match:

- `iChart/Models/IChartStoreKitProductCatalog.swift`
- `StoreKit/iChartProSubscriptions.storekit`
- App Store Connect subscription products when they are created

## Local StoreKit QA

Local simulator purchase testing uses:

- StoreKit file: `StoreKit/iChartProSubscriptions.storekit`
- XcodeGen hook: `project.yml` > `schemes` > `iChart` > `run` > `storeKitConfiguration`
- Debug simulator fallback: command-line/MCP launches read the bundled StoreKit file for product button metadata and use a local Pro entitlement preview when those fallback buttons are tapped
- Debug build setting: `SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG`

Run `xcodegen generate` after changing the StoreKit file or project spec. The generated `iChart` scheme should include a `StoreKitConfigurationFileReference` for `StoreKit/iChartProSubscriptions.storekit`.

Local prices in the `.storekit` file should mirror the current target launch pricing until App Store Connect becomes the production pricing authority. At $7.99 monthly and $64.99 annual, the annual plan is roughly 32% less than twelve monthly payments.

Xcode's normal Run action reads the scheme StoreKit configuration and should exercise real local StoreKit purchase dialogs. Command-line/MCP simulator launches build and launch the app outside that Run action, so the Debug simulator app also bundles the `.storekit` file, reads it for product button metadata, and treats fallback button taps as a local Pro entitlement preview. That fallback is compile-gated to Debug simulator builds and is not a production entitlement source.

Do not initialize `StoreKitTest.SKTestSession` inside the app process. It expects an XCTest configuration and aborts the app when launched normally.

## App Store Connect Production Gate

Apple-side products must remain configured as follows before App Store/TestFlight subscription QA:

- Create one subscription group for iChart Pro.
- Create the monthly auto-renewable subscription with product ID `com.ichart.app.pro.monthly`.
- Create the annual auto-renewable subscription with product ID `com.ichart.app.pro.annual`.
- Use app bundle ID `com.ichart.app`.
- Set App Store Server Notifications Version 2 sandbox URL to `https://pausvvwoazbvmzyrebwl.supabase.co/functions/v1/app-store-server-notifications`.
- Add product display names, descriptions, durations, review metadata, screenshots if required by App Review, and localization records.
- Set the monthly starting price to $7.99 and the annual starting price to $64.99 in the United States storefront, then review the App Store Connect comparable prices for other countries and regions.
- Leave both products in a state where StoreKit can fetch them in sandbox/TestFlight. Keep the local StoreKit configuration only for local Debug simulator QA; Release/TestFlight entitlement authority must come from Apple StoreKit plus the server-side claim path.
- Allow for App Store Connect metadata propagation; Apple notes product metadata changes can take up to 1 hour to appear in the sandbox environment.

Production entitlement authority should not stop at the iOS client:

- Keep `Product.products(for:)`, `Product.purchase()`, `Transaction.currentEntitlements`, `Transaction.updates`, and `AppStore.sync()` as the in-app StoreKit surface.
- Purchases call StoreKit with a stable per-account `appAccountToken`; the server rejects missing or mismatched app-account tokens before writing subscription authority.
- Add a server-owned subscription pipeline before trusting Supabase `subscriptions` rows as production authority.
- Use App Store Server Notifications for real-time lifecycle changes such as renewals, failed renewals, refunds, grace/billing retry changes, and churn.
- Use the App Store Server API from a server/Edge Function only; never bundle App Store Connect API keys, signing keys, webhook secrets, or service-role keys in the app.
- Keep `subscriptions` read-only from the app and update provider, StoreKit product, original transaction, app-account token, App Store status, expiration, grace, revocation, signed-date, notification UUID, and last-verification metadata only from trusted server-side purchase verification/notification handling.
- Settings and the upgrade sheet expose Manage Subscription through Apple's system subscription management UI.

Primary Apple references:

- [Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/)
- [Manage pricing for auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/)
- [Enter server URLs for App Store Server Notifications](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications)
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications)
- [StoreKit appAccountToken](https://developer.apple.com/documentation/storekit/transaction/appaccounttoken)
- [App Store Server Notifications notificationUUID](https://developer.apple.com/documentation/appstoreservernotifications/notificationuuid)

## App Store Server Notification Function

The server-side subscription authority path is wired at:

- `supabase/functions/app-store-server-notifications/index.mjs`
- `supabase/functions/storekit-subscription-claims/index.mjs`
- `supabase/functions/_shared/app_store_subscription_authority.mjs`
- `supabase/functions/_shared/app_store_subscription_authority.test.mjs`
- `supabase/functions/_shared/app_store_signed_data_verifier.mjs`
- `supabase/functions/_shared/supabase_subscription_authority_store.mjs`
- `supabase/functions/_shared/supabase_subscription_authority_store.test.mjs`
- `supabase/functions/_shared/app_store_verifier_config.mjs`
- `supabase/functions/_shared/app_store_verifier_config.test.mjs`
- `supabase/functions/subscription-retention-jobs/index.mjs`
- `supabase/functions/_shared/subscription_retention_jobs.mjs`
- `supabase/functions/_shared/subscription_retention_jobs.test.mjs`

`supabase/config.toml` sets `[functions.app-store-server-notifications]` with `verify_jwt = false` because Apple webhook delivery will not include a Supabase user JWT. That makes Apple signed-payload verification mandatory before any database write.

`supabase/config.toml` also sets `[functions.storekit-subscription-claims]` with `verify_jwt = true` because this endpoint is for signed-in iChart users after purchase/restore. The authenticated claim endpoint creates the trusted account-to-original-transaction mapping before later App Store Server Notifications arrive.

`supabase/config.toml` sets `[functions.subscription-retention-jobs]` with `verify_jwt = false` because it is invoked by a trusted scheduler, not a user JWT. It must be protected by `ICHART_RETENTION_JOB_SECRET`, and email dispatch additionally requires `RESEND_API_KEY` plus `ICHART_RETENTION_EMAIL_FROM`.

Both Edge Function entrypoints create verifier dependencies through Apple's official `@apple/app-store-server-library` `SignedDataVerifier`. The dependency factory reads only Edge Function environment secrets and returns no verifier functions when required Apple configuration is missing or malformed, so both endpoints fail closed with the existing not-configured responses.

Both entrypoints also create the Supabase subscription authority store from Edge-only secrets. The writer uses `SUPABASE_SECRET_KEYS` when available, or the legacy Supabase service-role secret name as a fallback, and never runs inside the iOS app. The iOS app reads `subscriptions`; it does not write them directly.

Required Edge Function verifier secrets:

- `APP_STORE_BUNDLE_ID`: `com.ichart.app`.
- `APP_STORE_ENVIRONMENT`: `Sandbox` for sandbox/TestFlight verification, `Production` for production App Store traffic.
- `APP_STORE_ROOT_CERTIFICATES_PEM`: Apple Root Certificate PEM blocks from the Apple PKI site, stored as an Edge Function secret.
- `APP_STORE_APP_APPLE_ID`: App Store app identifier. Required for `Production`; omitted for `Sandbox`.
- `ICHART_RETENTION_JOB_SECRET`: random secret for scheduled retention job calls.
- `RESEND_API_KEY`: email provider secret for subscription-retention warning/deletion messages.
- `ICHART_RETENTION_EMAIL_FROM`: verified sender, for example `iChart <support@useichart.com>`.

Prepare the public Apple root certificate bundle locally:

```sh
scripts/prepare_apple_root_certificates.sh /tmp/ichart-apple-root-certificates.pem
```

Set secrets from the operator machine or Supabase Dashboard, never in git:

```sh
supabase secrets set APP_STORE_BUNDLE_ID=com.ichart.app
supabase secrets set APP_STORE_ENVIRONMENT=Sandbox
supabase secrets set APP_STORE_ROOT_CERTIFICATES_PEM="$(cat /tmp/ichart-apple-root-certificates.pem)"
supabase secrets set ICHART_RETENTION_JOB_SECRET=<random-job-secret>
supabase secrets set RESEND_API_KEY=<resend-api-key>
supabase secrets set ICHART_RETENTION_EMAIL_FROM='iChart <support@useichart.com>'
# Production only:
# supabase secrets set APP_STORE_APP_APPLE_ID=<numeric-app-apple-id>
```

Production deployments verify App Store signed data against Apple's Production environment first. If Apple's verifier returns the generic JWS verification failure that can occur when a TestFlight/App Review/sandbox transaction reaches the production backend, the verifier retries with a Sandbox verifier and still requires the signed payload to match the iChart bundle, product ids, and app-account-token owner before writing any entitlement. The stored `storekit_environment` records which Apple environment signed the accepted transaction.

Supabase hosted Edge Functions expose `SUPABASE_URL` and `SUPABASE_SECRET_KEYS` by default. The secret key is server-only and must never be copied into the iOS app, docs, `.env.example`, or chat.

Current behavior is intentionally locked:

- non-POST requests are rejected
- webhook and claim request bodies are parsed with bounded streaming size limits before JSON/JWS verification
- missing `signedPayload` is rejected
- unconfigured verifier secrets return a not-configured response
- invalid Apple signatures are rejected before mapping or writing
- nested signed transaction/renewal payloads must be verified before write attempts
- verified notifications missing StoreKit product/original-transaction identity are rejected
- duplicate notification UUIDs are idempotent no-ops
- stale notification payloads are rejected before they can rewind authority fields
- transaction claims require a signed-in account bearer token
- transaction claims require `signedTransactionInfo`
- transaction claims reject non-Pro products, missing original transaction identity, and missing/mismatched `appAccountToken`
- transaction claims resolve the signed-in Supabase user before writing owner mapping
- transaction claims upsert `subscriptions` by `owner_id` after Apple verification succeeds
- transaction claims reject original transactions already mapped to another owner
- transaction claims reject stale signed transactions for an existing owner mapping
- verified notifications update only previously claimed `storekit_original_transaction_id` rows
- unmapped notifications are accepted without assigning ownership
- duplicate/stale writer rejections do not echo subscription rows back to public webhook or claim callers
- no subscription row is mutated from unverified input

The shared authority reducer and Supabase writer are testable with Node so the mapping rules can be verified before Deno is installed locally:

```sh
node --test \
  supabase/functions/_shared/app_store_environment_fallback.test.mjs \
  supabase/functions/_shared/app_store_subscription_authority.test.mjs \
  supabase/functions/_shared/app_store_verifier_config.test.mjs \
  supabase/functions/_shared/supabase_subscription_authority_store.test.mjs
```

Current release-candidate smoke gate:

- remote migration `20260707164637_harden_forum_pdf_provenance.sql` is applied to project `pausvvwoazbvmzyrebwl`
- `app-store-server-notifications` is deployed with `verify_jwt = false`
- `storekit-subscription-claims` is deployed with `verify_jwt = true`
- missing notification payload returns `400`
- invalid opaque notification payload returns verifier rejection `401`
- non-POST notification requests return `405`
- oversized notification bodies return `413`
- unauthenticated transaction claims return `401`

Before this endpoint is treated as public-production authority:

- configure Apple verifier Edge Function secrets for the target environment
- deploy both functions after secrets are configured and smoke-test missing/invalid signed payload behavior
- map only `com.ichart.app.pro.monthly` and `com.ichart.app.pro.annual` to active Pro
- keep app-account token binding, original-transaction owner conflicts, notification UUID replay, stale signed-date replay, and oversized request tests green
- store service-role/admin keys, App Store Connect API keys, webhook secrets, and Apple signing material only as Supabase Edge Function secrets
- after the basic TestFlight purchase/restore path is green, add App Store Server API current-status checks as the next production-hardening layer
- deploy with the linked project after verification is complete:
  ```sh
  supabase functions deploy app-store-server-notifications
  supabase functions deploy storekit-subscription-claims
  ```

## App Flow

StoreKit is an entitlement source, not a scattered feature gate.

The flow is:

```text
StoreKit transaction/current entitlement
-> IChartStoreKitSubscriptionStore
-> StoreKit purchase option appAccountToken
-> authenticated StoreKit transaction claim function
-> Supabase subscription owner/original-transaction mapping
-> IChartSubscriptionEntitlement
-> AppEntitlements
-> Library, Projects, cloud sync, Forums, chart-cap behavior
```

`proActive` unlocks cloud backup, Projects, Forums, and unlimited local charts. Apple billing grace keeps local chart access and Projects available while cloud backup and Forums pause. Basic, expired, and unavailable states use Basic local limits.

## Production Follow-Up

Before production launch:

- Create monthly and annual auto-renewing subscription products in App Store Connect.
- Confirm App Store Connect product IDs match the code and local StoreKit file.
- Configure App Store Connect pricing to the current target: $7.99 monthly and $64.99 annual, unless launch pricing changes before release.
- Replace or sync the local StoreKit configuration if App Store Connect product metadata becomes the source.
- Configure and validate Apple signed-payload verification plus server-only App Store Server Notification handling before trusting Supabase subscription rows as production authority.
- Have the verified server path write the subscription authority metadata in `subscriptions`; the iOS app remains select-only.
- Keep service-role keys, webhook secrets, App Store Connect API keys, and signing keys out of the iOS app and out of git.
