import { randomUUID } from "node:crypto";
import { iChartProProductIDs, normalizeStoreKitEnvironment } from "./app_store_subscription_authority.mjs";

export const complimentaryCampaignID = "ichart-complimentary-pro-1m-v1";
export const complimentaryOfferIDs = Object.freeze({
  "com.ichart.app.pro.monthly": "ichart_complimentary_monthly_1m_v1",
  "com.ichart.app.pro.annual": "ichart_complimentary_annual_1m_v1",
});
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isCampaignUUID = (value) => typeof value === "string" && uuidPattern.test(value);
const valueFromEnv = (env, key) => (typeof env?.get === "function" ? env.get(key) : env?.[key]);
const iso = (value) => Number.isFinite(value) && value > 0 && Number.isFinite(new Date(value).getTime())
  ? new Date(value).toISOString() : null;
const isPro = (product) => iChartProProductIDs.includes(product);

function canonicalSandboxQAOwners(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 32
      || !Array.from(value).every((owner) => typeof owner === "string" && owner.length === 36
        && isCampaignUUID(owner))) return null;
  const owners = value.map((owner) => owner.toLowerCase());
  if (new Set(owners).size !== owners.length) return null;
  return Object.freeze(owners);
}

function sandboxQAOwnersFromEnv(env) {
  const raw = valueFromEnv(env, "ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS");
  if (typeof raw !== "string" || raw.length > 8192) return null;
  try { return canonicalSandboxQAOwners(JSON.parse(raw)); } catch { return null; }
}

export function complimentaryCampaignConfigurationFromEnv(env = globalThis.Deno?.env) {
  const requested = valueFromEnv(env, "ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED") === "true";
  const startsAt = Date.parse(valueFromEnv(env, "ICHART_COMPLIMENTARY_CAMPAIGN_STARTS_AT") ?? "");
  const endsAt = Date.parse(valueFromEnv(env, "ICHART_COMPLIMENTARY_CAMPAIGN_ENDS_AT") ?? "");
  const bundleID = valueFromEnv(env, "APP_STORE_BUNDLE_ID");
  const explicitEnvironment = valueFromEnv(env, "ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT");
  const environment = normalizeStoreKitEnvironment(explicitEnvironment === undefined
    ? valueFromEnv(env, "APP_STORE_ENVIRONMENT") : explicitEnvironment);
  const keyID = valueFromEnv(env, "APP_STORE_SUBSCRIPTION_KEY_ID");
  const privateKeyPEM = valueFromEnv(env, "APP_STORE_SUBSCRIPTION_KEY_P8");
  const issuerID = valueFromEnv(env, "APP_STORE_ISSUER_ID");
  // Sandbox is a private test cohort, not a public alternative Apple environment.
  // Production deliberately does not read this test-only setting.
  const sandboxQAOwnerIDs = environment === "sandbox" ? sandboxQAOwnersFromEnv(env) : null;
  const configured = Number.isFinite(startsAt) && Number.isFinite(endsAt) && endsAt > startsAt
    && bundleID === "com.ichart.app" && environment !== null
    && typeof keyID === "string" && /^[A-Z0-9]{10}$/.test(keyID)
    && typeof privateKeyPEM === "string" && privateKeyPEM.includes("-----BEGIN PRIVATE KEY-----")
    && isCampaignUUID(issuerID);
  const sandboxQAConfigured = environment !== "sandbox" || sandboxQAOwnerIDs !== null;
  const sandboxDiagnosticEndsAt = environment === "sandbox" && normalizeStoreKitEnvironment(explicitEnvironment) === "sandbox"
    ? Date.parse(valueFromEnv(env, "ICHART_COMPLIMENTARY_SANDBOX_DIAGNOSTIC_ENDS_AT") ?? "") : NaN;
  const sandboxRecoveryEndsAt = environment === "sandbox" && normalizeStoreKitEnvironment(explicitEnvironment) === "sandbox"
    ? Date.parse(valueFromEnv(env, "ICHART_COMPLIMENTARY_SANDBOX_RECOVERY_ENDS_AT") ?? "") : NaN;
  return { campaignID: complimentaryCampaignID, enabled: requested && configured && sandboxQAConfigured,
    reason: !requested ? "campaign_disabled" : !configured ? "campaign_not_configured"
      : !sandboxQAConfigured ? "sandbox_qa_not_configured" : null,
    startsAt, endsAt, bundleID, environment, keyID, privateKeyPEM, issuerID, sandboxQAOwnerIDs,
    sandboxDiagnosticEndsAt, sandboxRecoveryEndsAt };
}

// These checks operate ONLY on signature-verified, freshly fetched Apple payloads.
export function validateCampaignTransaction(transaction, ownerID, configuration) {
  if (!transaction || transaction.bundleId !== configuration.bundleID || !isPro(transaction.productId)
      || normalizeStoreKitEnvironment(transaction.environment) !== configuration.environment
      || !isCampaignUUID(transaction.appAccountToken)
      || transaction.appAccountToken.toLowerCase() !== ownerID.toLowerCase()
      || transaction.inAppOwnershipType === "FAMILY_SHARED"
      || transaction.type !== "Auto-Renewable Subscription"
      || !transaction.originalTransactionId || !transaction.transactionId) {
    throw new Error("transaction_ownership_or_scope_mismatch");
  }
}

function freeMonth(payload, priceField) {
  return payload?.offerDiscountType === "FREE_TRIAL" && payload.offerPeriod === "P1M"
    && payload[priceField] === 0;
}

function completedPromotionalZeroChargeMonth(transaction) {
  // Actual transaction evidence is independent of a prospective renewal quote.
  // A configured one-month promotional offer at numeric zero can be fulfilled
  // with either payment mode; introductory eligibility remains FREE_TRIAL only.
  return transaction?.offerType === 2
    && isPro(transaction.productId)
    && transaction.offerIdentifier === complimentaryOfferIDs[transaction.productId]
    && transaction.offerPeriod === "P1M" && transaction.price === 0
    && ["FREE_TRIAL", "PAY_UP_FRONT"].includes(transaction.offerDiscountType);
}

function pendingZeroChargeMonth(renewal) {
  // Apple renewalPrice includes the pending offer discount. PAY_UP_FRONT covers
  // the entire stated offerPeriod: an exact P1M offer quoted at numeric zero
  // therefore schedules one month without a charge, not a multi-period prepaid
  // plan. Keep its actual payment mode; do not rewrite it as FREE_TRIAL or use
  // this prospective quote as evidence of a redeemed transaction/access period.
  return renewal?.offerPeriod === "P1M" && renewal.renewalPrice === 0
    && ["FREE_TRIAL", "PAY_UP_FRONT"].includes(renewal.offerDiscountType);
}

// Fixed booleans only: no Apple values, identifiers, signed data or errors.
// Missing terms remain different from verified zero-price/free-month terms.
export function pendingCampaignVerificationChecks(entry, now) {
  const transaction = entry?.transaction ?? {};
  const renewal = entry?.renewal ?? {};
  return {
    status_active: entry?.status === 1,
    unrevoked: !transaction.revocationDate,
    unexpired: Number.isFinite(transaction.expiresDate) && transaction.expiresDate > now,
    current_product_match: renewal.productId === transaction.productId,
    renewal_product_match: renewal.autoRenewProductId === transaction.productId,
    configured_offer_match: renewal.offerIdentifier === complimentaryOfferIDs[transaction.productId],
    free_trial: renewal.offerDiscountType === "FREE_TRIAL",
    one_month: renewal.offerPeriod === "P1M",
    zero_price: renewal.renewalPrice === 0,
    auto_renew_on: renewal.autoRenewStatus === 1,
    renewal_date_valid: Number.isFinite(renewal.renewalDate) && renewal.renewalDate >= now,
    discount_present: renewal.offerDiscountType != null,
    period_present: renewal.offerPeriod != null,
    price_present: renewal.renewalPrice != null,
    price_positive: typeof renewal.renewalPrice === "number" && renewal.renewalPrice > 0,
    renewal_date_present: renewal.renewalDate != null,
  };
}

// Classify the signed field without emitting it or treating an unfamiliar value
// as a free trial. This is diagnostic evidence, never an eligibility decision.
export function pendingCampaignDiscountCategory(value) {
  if (value === undefined) return "missing";
  if (value === null) return "null_value";
  if (typeof value !== "string") return "invalid_type";
  switch (value) {
    case "FREE_TRIAL": return "free_trial";
    case "PAY_AS_YOU_GO": return "pay_as_you_go";
    case "PAY_UP_FRONT": return "pay_up_front";
    case "ONE_TIME": return "one_time";
    default: return "other_string";
  }
}

async function collectDisabledSandboxPendingDiagnostic(body, ownerID, dependencies, configuration, clock) {
  const qaOwners = canonicalSandboxQAOwners(configuration.sandboxQAOwnerIDs);
  // This opt-in read-only hook cannot recover, prepare, confirm or grant access.
  // A single exact QA owner and future cutoff are mandatory even for direct config.
  if (body.action !== "status" || configuration.environment !== "sandbox"
      || configuration.bundleID !== "com.ichart.app" || qaOwners?.length !== 1
      || qaOwners[0] !== ownerID.toLowerCase()
      || !Number.isFinite(configuration.sandboxDiagnosticEndsAt)
      || clock() >= configuration.sandboxDiagnosticEndsAt
      || configuration.sandboxDiagnosticEndsAt - clock() > 3600000
      || typeof dependencies.recordPendingVerificationDiagnostic !== "function") return;
  try {
    const ledger = await dependencies.readCampaignLedger({ ownerID, campaignID: configuration.campaignID, environment: "sandbox" });
    if (!["prepared", "scheduled"].includes(ledger?.state) || !isCampaignUUID(ledger.attemptID)
        || ledger.environment !== "sandbox" || ledger.productID !== body.productID
        || ledger.decision !== "scheduledPromotional" || ledger.offerID !== complimentaryOfferIDs[body.productID]
        || !Number.isSafeInteger(ledger.authorizedAt) || ledger.authorizedAt <= 0 || ledger.authorizedAt > clock()
        || clock() >= configuration.sandboxDiagnosticEndsAt) return;
    const seed = await dependencies.readSubscriptionSeed(ownerID, "sandbox");
    if (!seed?.originalTransactionID || (ledger.originalTransactionID != null
        && ledger.originalTransactionID !== seed.originalTransactionID)
        || clock() >= configuration.sandboxDiagnosticEndsAt) return;
    const snapshot = await dependencies.fetchFreshAppleSnapshot({ ownerID,
      originalTransactionID: seed.originalTransactionID, environment: "sandbox" });
    for (const entry of snapshot.statuses ?? []) validateCampaignTransaction(entry.transaction, ownerID, configuration);
    const matching = (snapshot.statuses ?? []).filter(entry => entry.transaction.originalTransactionId === seed.originalTransactionID
      && entry.transaction.productId === ledger.productID && entry.renewal?.offerType === 2
      && entry.renewal.offerIdentifier === ledger.offerID);
    if (matching.length !== 1 || clock() >= configuration.sandboxDiagnosticEndsAt) return;
    const checks = pendingCampaignVerificationChecks(matching[0], clock());
    const pendingDiscountCategory = pendingCampaignDiscountCategory(matching[0].renewal?.offerDiscountType);
    dependencies.recordPendingVerificationDiagnostic(checks, pendingDiscountCategory);
    return { pendingVerificationChecks: checks, pendingDiscountCategory };
  } catch {
    // Diagnostics must not change the disabled response or serialize upstream errors.
  }
}

// A separate, short-lived opt-in can only recognize the already authorized
// Sandbox QA attempt. It cannot create an attempt, sign an offer or grant access.
// Undefined means inactive; null means an admitted check failed closed, so the
// disabled handler must not fall through to another Apple diagnostic request.
async function recoverDisabledSandboxScheduledAttempt(body, ownerID, dependencies, configuration, clock) {
  const qaOwners = canonicalSandboxQAOwners(configuration.sandboxQAOwnerIDs);
  const withinWindow = (now = clock()) => {
    return Number.isFinite(now) && Number.isFinite(configuration.sandboxRecoveryEndsAt)
      && configuration.sandboxRecoveryEndsAt > now
      && configuration.sandboxRecoveryEndsAt - now <= 3600000;
  };
  if (!["status", "confirm"].includes(body.action) || configuration.enabled !== false
      || configuration.campaignID !== complimentaryCampaignID
      || configuration.environment !== "sandbox" || configuration.bundleID !== "com.ichart.app"
      || qaOwners?.length !== 1 || qaOwners[0] !== ownerID.toLowerCase() || !withinWindow()) return;
  try {
    if (typeof dependencies.readCampaignLedger !== "function"
        || typeof dependencies.readSubscriptionSeed !== "function"
        || typeof dependencies.fetchFreshAppleSnapshot !== "function"
        || typeof dependencies.recordCampaignBenefit !== "function"
        || (body.action === "confirm" && (typeof body.signedTransactionInfo !== "string"
          || typeof dependencies.verifyAndDecodeTransaction !== "function"))) return null;
    if (!withinWindow()) return null;
    const ledger = await dependencies.readCampaignLedger({ ownerID,
      campaignID: configuration.campaignID, environment: "sandbox" });
    if (!["prepared", "scheduled"].includes(ledger?.state) || !isCampaignUUID(ledger.attemptID)
        || ledger.environment !== "sandbox" || ledger.productID !== body.productID
        || ledger.decision !== "scheduledPromotional" || ledger.offerID !== complimentaryOfferIDs[body.productID]
        || !Number.isSafeInteger(ledger.authorizedAt) || ledger.authorizedAt <= 0 || ledger.authorizedAt > clock()
        || !withinWindow()) return null;
    const attemptID = ledger.attemptID.toLowerCase();
    if (body.action === "confirm" && body.attemptID.toLowerCase() !== attemptID) return null;
    const seed = await dependencies.readSubscriptionSeed(ownerID, "sandbox");
    if (typeof seed?.originalTransactionID !== "string" || !/^\d+$/.test(seed.originalTransactionID)
        || (ledger.originalTransactionID != null && ledger.originalTransactionID !== seed.originalTransactionID)
        || !withinWindow()) return null;
    if (body.action === "confirm") {
      const providedTransaction = await dependencies.verifyAndDecodeTransaction(body.signedTransactionInfo);
      validateCampaignTransaction(providedTransaction, ownerID, configuration);
      if (providedTransaction.originalTransactionId !== seed.originalTransactionID
          || providedTransaction.productId !== ledger.productID || !withinWindow()) return null;
    }
    if (!withinWindow()) return null;
    const snapshot = await dependencies.fetchFreshAppleSnapshot({ ownerID,
      originalTransactionID: seed.originalTransactionID, environment: "sandbox" });
    if (!withinWindow()) return null;
    const matchingStatuses = (snapshot?.statuses ?? []).filter(entry =>
      entry.transaction?.originalTransactionId === seed.originalTransactionID
      && entry.transaction?.productId === ledger.productID);
    if (matchingStatuses.length !== 1) return null;
    const verifiedAt = clock();
    const result = evaluateComplimentaryCampaign({ ownerID, productID: body.productID,
      configuration, snapshot, ledger, now: verifiedAt });
    if (result.state !== "scheduled" || result.decision !== ledger.decision
        || result.productID !== ledger.productID || result.offerID !== ledger.offerID
        || result.benefit?.state !== "scheduled" || result.benefit.productID !== ledger.productID
        || result.benefit.environment !== "sandbox"
        || result.benefit.originalTransactionID !== seed.originalTransactionID || !withinWindow()) return null;
    const recordedAt = clock();
    if (!withinWindow(recordedAt)) return null;
    // Supplying the saved current attempt for STATUS too makes retirement races
    // fail inside the existing transactional benefit recorder.
    const stored = await dependencies.recordCampaignBenefit({ ownerID, campaignID: configuration.campaignID,
      attemptID, ...result.benefit, now: recordedAt });
    const completedAt = clock();
    if (!stored?.ok || !withinWindow(completedAt)) return null;
    const { benefit: _benefit, ...publicResult } = result;
    return { ...publicResult, enabled: false, recoveryOnly: true, canPrepare: false, attemptID,
      serverTime: new Date(completedAt).toISOString() };
  } catch {
    // No upstream errors or partial verification may change the disabled policy.
    return null;
  }
}

function matchingAuthorization(ledger, configuration, productID) {
  return isCampaignUUID(ledger?.attemptID) && ledger.productID === productID
    && ledger.environment === configuration.environment && Number.isSafeInteger(ledger.authorizedAt)
    && ledger.authorizedAt >= configuration.startsAt && ledger.authorizedAt < configuration.endsAt
    && ["introductory", "promotional", "scheduledPromotional"].includes(ledger.decision)
    && (ledger.decision === "introductory" ? ledger.offerID == null : ledger.offerID === complimentaryOfferIDs[productID]);
}

function campaignTransaction(transaction, configuration, ledger) {
  if (transaction.offerType === 2 && Object.values(complimentaryOfferIDs).includes(transaction.offerIdentifier)) return true;
  if (transaction.offerType !== 1 || !freeMonth(transaction, "price")) return false;
  const completedDuringWindow = transaction.purchaseDate >= configuration.startsAt && transaction.purchaseDate < configuration.endsAt;
  const authorizedBeforeDeadline = matchingAuthorization(ledger, configuration, transaction.productId)
    && ledger.decision === "introductory" && transaction.purchaseDate >= ledger.authorizedAt;
  // Apple pending approval may complete after the authorization window. There
  // is no new completion grace period, nor any new right to prepare a purchase.
  return completedDuringWindow || authorizedBeforeDeadline;
}

function addCalendarMonth(timestamp) {
  const result = new Date(timestamp);
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + 1);
  const lastDay = new Date(Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result.toISOString();
}

function unavailable(reason, extra = {}) {
  return { decision: "ineligible", activation: null, state: "unavailable", reason, ...extra };
}

export function evaluateComplimentaryCampaign({ ownerID, productID, configuration, snapshot, ledger, now }) {
  const history = snapshot?.history ?? [];
  const statuses = snapshot?.statuses ?? [];
  for (const transaction of [...history, ...statuses.map((entry) => entry.transaction)]) {
    validateCampaignTransaction(transaction, ownerID, configuration);
  }
  const benefits = history.filter((transaction) => campaignTransaction(transaction, configuration, ledger))
    // The first accepted gift consumes the campaign, even if later refunded.
    // Never present a later duplicate as a fresh or extended complimentary term.
    .sort((left, right) => left.purchaseDate - right.purchaseDate);
  if (benefits.length > 0) {
    const transaction = benefits[0];
    const matchingTerms = transaction.offerType === 1
      ? freeMonth(transaction, "price") : completedPromotionalZeroChargeMonth(transaction);
    const accessStartsAt = iso(transaction.purchaseDate);
    const accessEndsAt = transaction.expiresDate > transaction.purchaseDate ? iso(transaction.expiresDate) : null;
    const benefit = { productID: transaction.productId, originalTransactionID: transaction.originalTransactionId,
      transactionID: transaction.transactionId, environment: configuration.environment, state: "redeemed", accessStartsAt, accessEndsAt };
    if (!matchingTerms || !accessStartsAt || !accessEndsAt) return unavailable("verified_offer_terms_mismatch", { benefit });
    if (transaction.revocationDate || transaction.isUpgraded) {
      return unavailable("campaign_already_used", { benefit });
    }
    if (transaction.productId !== productID) return unavailable("campaign_already_used_on_other_product", { benefit });
    const originallyScheduled = transaction.offerType === 2 && ledger?.productID === transaction.productId
      && ledger?.decision === "scheduledPromotional" && ledger?.offerID === transaction.offerIdentifier;
    // Redeemed also describes an ended, unrevoked gift. Its original Apple dates
    // permit transaction recovery; normal subscription authority alone grants access.
    return { decision: transaction.offerType === 1 ? "introductory" : originallyScheduled ? "scheduledPromotional" : "promotional",
      activation: originallyScheduled ? "nextBillingEvent" : "immediate",
      state: "redeemed", productID: transaction.productId,
      ...(transaction.offerType === 2 ? { offerID: transaction.offerIdentifier } : {}), accessStartsAt, accessEndsAt, benefit };
  }
  for (const entry of statuses) {
    const transaction = entry.transaction;
    const renewal = entry.renewal;
    if (renewal?.offerType === 2 && Object.values(complimentaryOfferIDs).includes(renewal.offerIdentifier)) {
      const sameProduct = renewal.productId === transaction.productId && renewal.autoRenewProductId === transaction.productId;
      if (entry.status !== 1 || transaction.revocationDate || !Number.isFinite(transaction.expiresDate)
          || transaction.expiresDate <= now || !sameProduct
          || renewal.offerIdentifier !== complimentaryOfferIDs[transaction.productId]
          || !pendingZeroChargeMonth(renewal) || renewal.autoRenewStatus !== 1
          || !Number.isFinite(renewal.renewalDate) || renewal.renewalDate < now) {
        return unavailable("pending_campaign_offer_not_verifiable");
      }
      const accessStartsAt = iso(renewal.renewalDate);
      // Pending Apple renewal verifies P1M and its start; no future transaction exists yet.
      const accessEndsAt = null;
      const estimatedAccessEndsAt = addCalendarMonth(renewal.renewalDate);
      const benefit = { productID: transaction.productId, originalTransactionID: transaction.originalTransactionId,
        transactionID: transaction.transactionId, environment: configuration.environment, state: "scheduled", accessStartsAt, accessEndsAt };
      if (transaction.productId !== productID) return unavailable("campaign_already_used_on_other_product", { benefit });
      return { decision: "scheduledPromotional", activation: "nextBillingEvent", state: "scheduled",
        productID: transaction.productId, offerID: renewal.offerIdentifier, accessStartsAt, accessEndsAt,
        estimatedAccessEndsAt, accessEndsAtIsEstimated: true, benefit };
    }
  }
  if (ledger?.state === "redeemed" || ledger?.state === "scheduled") return unavailable("campaign_already_used");
  if (!configuration.enabled) return unavailable(configuration.reason ?? "campaign_disabled");
  if (now < configuration.startsAt) return unavailable("campaign_not_started");
  if (now >= configuration.endsAt) return unavailable("campaign_ended");
  if (statuses.some((entry) => ![1, 2].includes(entry.status) || entry.renewal?.isInBillingRetryPeriod
      || Number(entry.renewal?.gracePeriodExpiresDate) > now)) return unavailable("subscription_state_requires_resolution");
  const active = statuses.filter((entry) => entry.status === 1 && entry.transaction.expiresDate > now
    && !entry.transaction.revocationDate && !entry.transaction.isUpgraded);
  if (active.length > 1) return unavailable("ambiguous_active_subscription");
  if (active.length === 1) {
    const { transaction, renewal } = active[0];
    if (transaction.productId !== productID) return unavailable("active_subscription_same_product_required");
    if (!renewal || renewal.productId !== productID || renewal.autoRenewProductId !== productID
        || renewal.offerIdentifier || renewal.offerType || transaction.offerType || transaction.offerIdentifier
        || renewal.renewalDate !== transaction.expiresDate) return unavailable("conflicting_or_unknown_renewal_offer");
    return { decision: "scheduledPromotional", activation: "nextBillingEvent", state: "available",
      offerID: complimentaryOfferIDs[productID] };
  }
  if (statuses.some((entry) => entry.status === 1)) return unavailable("subscription_state_inconsistent");
  if (history.length === 0 && statuses.length === 0) {
    // Absence of an iChart mapping is NOT proof of Apple introductory eligibility.
    return { decision: "introductory", activation: "immediate", state: "available" };
  }
  if (statuses.length === 0 || !statuses.every((entry) => entry.status === 2)) return unavailable("subscription_state_inconsistent");
  if (statuses.some((entry) => entry.renewal?.autoRenewStatus === 1 && entry.renewal?.renewalDate >= now
      && (entry.renewal?.offerIdentifier || entry.renewal?.offerType))) return unavailable("conflicting_renewal_offer");
  return { decision: "promotional", activation: "immediate", state: "available", offerID: complimentaryOfferIDs[productID] };
}

async function boundedRequestText(request) {
  const maximumBytes = 65536;
  if (Number(request.headers.get("content-length")) > maximumBytes) return null;
  if (request.body === null) return "";
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0;
  let text = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) return text + decoder.decode();
    bytes += value.byteLength;
    if (bytes > maximumBytes) {
      try { await reader.cancel(); } catch { /* Best-effort cancellation only. */ }
      return null;
    }
    text += decoder.decode(value, { stream: true });
  }
}

export async function handleComplimentaryOfferRequest(request, dependencies, configuration, clock = Date.now) {
  const now = clock();
  let productID = "";
  const respond = (status, result, attemptID) => new Response(JSON.stringify({ schemaVersion: 1,
    campaignID: configuration.campaignID, enabled: configuration.enabled, productID,
    serverTime: new Date(now).toISOString(), ...result, ...(attemptID ? { attemptID } : {}) }),
  { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  try {
    if (request.method !== "POST") return respond(405, unavailable("method_not_allowed"));
    const bodyText = await boundedRequestText(request);
    if (bodyText === null) return respond(413, unavailable("request_too_large"));
    let body;
    try { body = JSON.parse(bodyText); } catch { return respond(400, unavailable("invalid_request")); }
    if (!body || typeof body !== "object" || Array.isArray(body)) return respond(400, unavailable("invalid_request"));
    productID = body.productID;
    if (body.schemaVersion !== 1 || !["status", "prepare", "confirm"].includes(body.action) || !isPro(productID)
        || Object.keys(body).some((key) => !["schemaVersion", "action", "productID", "signedTransactionInfo", "attemptID", "previousAttemptID"].includes(key))
        || (body.action !== "status" && !isCampaignUUID(body.attemptID))
        || (body.previousAttemptID != null && !isCampaignUUID(body.previousAttemptID))
        || (body.signedTransactionInfo != null && (typeof body.signedTransactionInfo !== "string" || body.signedTransactionInfo.length > 32768))) {
      return respond(400, unavailable("invalid_request"));
    }
    const ownerID = await dependencies.authenticatedUserID?.(request);
    if (!isCampaignUUID(ownerID)) return respond(401, unavailable("signed_in_account_required"));
    const attemptID = body.attemptID?.toLowerCase();
    // Disabled campaigns cannot issue signatures. Explicit QA-only exceptions
    // are independent, bounded recognition/diagnostic paths, never activation.
    if (!configuration.enabled) {
      const recovered = await recoverDisabledSandboxScheduledAttempt(body, ownerID, dependencies, configuration, clock);
      if (recovered) return respond(200, recovered);
      if (recovered === null) return respond(200, unavailable(configuration.reason ?? "campaign_disabled"));
      const pendingDiagnostic = await collectDisabledSandboxPendingDiagnostic(body, ownerID, dependencies, configuration, clock);
      return respond(200, unavailable(configuration.reason ?? "campaign_disabled",
        pendingDiagnostic ?? {}));
    }
    // Recheck at the shared request boundary, including directly constructed config.
    // Every action and recovery path is gated before campaign/Apple/signing I/O.
    const environment = typeof configuration.environment === "string"
      ? normalizeStoreKitEnvironment(configuration.environment) : null;
    if (environment === null) return respond(200, unavailable("campaign_not_configured", { enabled: false }));
    if (environment === "sandbox") {
      const qaOwners = canonicalSandboxQAOwners(configuration.sandboxQAOwnerIDs);
      if (qaOwners === null || !qaOwners.includes(ownerID.toLowerCase())) {
        return respond(200, unavailable("campaign_not_available", { enabled: false }));
      }
    }
    // New authorization closes independently of all recovery/benefit paths.
    if (body.action === "prepare" && (now < configuration.startsAt || now >= configuration.endsAt)) {
      return respond(200, unavailable(now < configuration.startsAt ? "campaign_not_started" : "campaign_ended"), attemptID);
    }
    const ledger = await dependencies.readCampaignLedger({ ownerID, campaignID: configuration.campaignID, environment: configuration.environment });
    const ownedSeed = await dependencies.readSubscriptionSeed(ownerID, configuration.environment);
    if (ledger && ledger.environment !== configuration.environment) throw new Error("campaign_environment_mismatch");
    const seeds = new Set(ownedSeed?.originalTransactionID ? [ownedSeed.originalTransactionID] : []);
    let providedTransaction;
    if (body.signedTransactionInfo) {
      providedTransaction = await dependencies.verifyAndDecodeTransaction(body.signedTransactionInfo);
      validateCampaignTransaction(providedTransaction, ownerID, configuration);
      seeds.add(providedTransaction.originalTransactionId);
    }
    if (body.action === "confirm" && (!providedTransaction || ownedSeed?.originalTransactionID !== providedTransaction.originalTransactionId)) {
      return respond(409, unavailable("verified_subscription_claim_required"), attemptID);
    }
    const snapshots = [];
    for (const originalTransactionID of seeds) snapshots.push(await dependencies.fetchFreshAppleSnapshot({ ownerID, originalTransactionID, environment: configuration.environment }));
    const snapshot = { history: snapshots.flatMap((item) => item.history), statuses: snapshots.flatMap((item) => item.statuses) };
    // Avoid duplicate active rows when DB and local JWS seed different IDs in the same Apple history.
    snapshot.history = [...new Map(snapshot.history.map((item) => [item.transactionId, item])).values()];
    snapshot.statuses = [...new Map(snapshot.statuses.map((item) => [item.transaction.originalTransactionId, item])).values()];
    const result = evaluateComplimentaryCampaign({ ownerID, productID, configuration, snapshot, ledger, now });
    if (body.action === "confirm" && ledger?.attemptID !== attemptID) return respond(409, unavailable("purchase_attempt_not_current"), attemptID);
    if (result.benefit) {
      const stored = await dependencies.recordCampaignBenefit({ ownerID, campaignID: configuration.campaignID,
        ...(body.action === "confirm" ? { attemptID } : {}), ...result.benefit, now });
      if (!stored.ok) return respond(409, unavailable(stored.reason ?? "campaign_benefit_conflict"), attemptID);
    }
    const { benefit: _benefit, ...publicResult } = result;
    if (body.action === "confirm") {
      if (!["scheduled", "redeemed"].includes(result.state) || result.productID !== productID
          || ledger?.decision !== result.decision) return respond(409, unavailable(result.reason ?? "apple_offer_not_yet_confirmed"), attemptID);
      return respond(200, publicResult, attemptID);
    }
    if (body.action === "status") {
      if (result.reason === "campaign_ended" && ledger?.state === "prepared" && matchingAuthorization(ledger, configuration, productID)) {
        return respond(200, { decision: ledger.decision, state: "prepared", canPrepare: false,
          activation: ledger.decision === "scheduledPromotional" ? "nextBillingEvent" : "immediate",
          ...(ledger.offerID ? { offerID: ledger.offerID } : {}), reason: "prepared_recovery_only" }, ledger.attemptID);
      }
      const recoverable = result.state === "available" && ledger?.state === "prepared"
        && ledger.productID === productID && ledger.decision === result.decision
        && ledger.offerID === (result.offerID ?? null) && isCampaignUUID(ledger.attemptID);
      return respond(200, { ...publicResult, ...(recoverable ? { state: "prepared" } : {}) }, ledger?.attemptID);
    }
    if (result.state !== "available") return respond(200, publicResult, ledger?.attemptID);
    // Apple checks can take time. Check before reservation and again after each
    // asynchronous issuance step; request arrival is not purchase authorization.
    const preparedAt = clock();
    if (preparedAt < configuration.startsAt || preparedAt >= configuration.endsAt) {
      return respond(200, unavailable(preparedAt < configuration.startsAt ? "campaign_not_started" : "campaign_ended"), attemptID);
    }
    const currentResult = evaluateComplimentaryCampaign({ ownerID, productID, configuration, snapshot, ledger, now: preparedAt });
    if (currentResult.state !== "available" || currentResult.decision !== result.decision) {
      return respond(409, unavailable("subscription_state_changed_before_preparation"), attemptID);
    }
    const reservation = await dependencies.reserveCampaignAttempt({ ownerID, campaignID: configuration.campaignID,
      attemptID, previousAttemptID: body.previousAttemptID?.toLowerCase(), productID,
      environment: configuration.environment, offerID: result.offerID ?? null, decision: result.decision,
      nonce: randomUUID().toLowerCase(), timestamp: preparedAt, now: preparedAt });
    if (!reservation.ok) return respond(409, unavailable(reservation.reason ?? "purchase_attempt_conflict"), ledger?.attemptID);
    const reservedAt = clock();
    if (reservedAt < configuration.startsAt || reservedAt >= configuration.endsAt) {
      // Keep the persisted attempt for verified-purchase recovery, but do not
      // return a fresh authorization or invoke the signer after the cutoff.
      return respond(200, unavailable(reservedAt < configuration.startsAt ? "campaign_not_started" : "campaign_ended",
        { canPrepare: false, serverTime: new Date(reservedAt).toISOString() }), attemptID);
    }
    const attempt = reservation.attempt;
    if (attempt.decision !== result.decision || attempt.productID !== productID || attempt.offerID !== (result.offerID ?? null)
        || reservedAt - attempt.timestamp >= 86400000 || attempt.timestamp > reservedAt) return respond(409, unavailable("purchase_attempt_stale"), attemptID);
    const signature = result.decision === "introductory" ? undefined : await dependencies.signPromotionalOffer({ productID,
      offerID: result.offerID, appAccountToken: ownerID.toLowerCase(), nonce: attempt.nonce, timestamp: attempt.timestamp });
    const issuedAt = clock();
    if (issuedAt < configuration.startsAt || issuedAt >= configuration.endsAt) {
      // Even a completed signature is withheld if asynchronous signing crossed
      // the authorization deadline. Status may still expose recovery metadata.
      return respond(200, unavailable(issuedAt < configuration.startsAt ? "campaign_not_started" : "campaign_ended",
        { canPrepare: false, serverTime: new Date(issuedAt).toISOString() }), attemptID);
    }
    if (issuedAt - attempt.timestamp >= 86400000 || attempt.timestamp > issuedAt) {
      return respond(409, unavailable("purchase_attempt_stale"), attemptID);
    }
    return respond(200, { ...publicResult, state: "prepared", ...(signature ? { signature } : {}) }, attemptID);
  } catch (error) {
    // Never serialize upstream errors: they can contain credentials, JWS, or signatures.
    const reason = ["transaction_ownership_or_scope_mismatch"].includes(error?.message) ? error.message : "campaign_verification_unavailable";
    return respond(503, unavailable(reason));
  }
}
