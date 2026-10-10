import { supabaseAuthorityStoreConfigurationFromEnv } from "./supabase_subscription_authority_store.mjs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const productIDs = new Set(["com.ichart.app.pro.monthly", "com.ichart.app.pro.annual"]);
const decisions = new Set(["introductory", "promotional", "scheduledPromotional"]);

// This adapter only persists campaign bookkeeping. Existing subscription claims
// remain the sole writer of entitlement authority.
export function createSupabaseComplimentaryOfferDependencies(env = globalThis.Deno?.env, options = {}) {
  const configuration = supabaseAuthorityStoreConfigurationFromEnv(env);
  const fetcher = options.fetch ?? fetch;
  if (configuration === null) return {};

  return {
    authenticatedUserID: (request) => authenticatedCampaignUserID(request, configuration, fetcher),
    readSubscriptionSeed: (ownerID, environment) => subscriptionSeed(configuration, ownerID, environment, fetcher),
    readCampaignLedger: (input) => campaignLedger(configuration, input, fetcher),
    reserveCampaignAttempt: (input) => reserveCampaignAttempt(configuration, input, fetcher),
    recordCampaignBenefit: (input) => recordCampaignBenefit(configuration, input, fetcher),
  };
}

async function authenticatedCampaignUserID(request, configuration, fetcher) {
  const match = (request.headers.get("authorization") ?? "").match(/^Bearer\s+(\S+)$/i);
  if (match === null) return null;
  const response = await fetcher(urlFor(configuration, "/auth/v1/user"), {
    method: "GET",
    headers: { apikey: configuration.secretKey, authorization: `Bearer ${match[1]}`, accept: "application/json" },
  });
  if (response.status === 401 || response.status === 403) return null;
  const user = await parseResponse(response);
  // Only the auth server response authorizes ownership. Neither metadata nor
  // a UUID supplied by an app can authorize a campaign.
  if (user?.is_anonymous !== false) return null;
  return canonicalUUID(user?.id);
}

async function subscriptionSeed(configuration, ownerID, environment, fetcher) {
  const owner = requiredUUID(ownerID);
  const appleEnvironment = requiredEnvironment(environment);
  const url = urlFor(configuration, "/rest/v1/subscriptions");
  url.searchParams.set("owner_id", `eq.${owner}`);
  url.searchParams.set("provider", "eq.storekit");
  url.searchParams.set("storekit_environment", `eq.${appleEnvironment}`);
  url.searchParams.set("select", "owner_id,storekit_original_transaction_id,storekit_app_account_token,storekit_environment");
  url.searchParams.set("limit", "2");
  const rows = await readRows(configuration, url, fetcher);
  if (rows.length === 0) return null;
  if (rows.length !== 1 || canonicalUUID(rows[0]?.owner_id) !== owner
    || canonicalUUID(rows[0]?.storekit_app_account_token) !== owner
    || rows[0]?.storekit_environment !== appleEnvironment) {
    throw new Error("Campaign subscription ownership is unavailable.");
  }
  const originalTransactionID = rows[0]?.storekit_original_transaction_id;
  return typeof originalTransactionID === "string" && /^\d+$/.test(originalTransactionID)
    ? { originalTransactionID } : null;
}

async function campaignLedger(configuration, { ownerID, campaignID, environment }, fetcher) {
  const owner = requiredUUID(ownerID);
  const campaign = requiredCampaignID(campaignID);
  const appleEnvironment = requiredEnvironment(environment);
  const url = urlFor(configuration, "/rest/v1/storekit_complimentary_campaign_accounts");
  url.searchParams.set("owner_id", `eq.${owner}`);
  url.searchParams.set("campaign_id", `eq.${campaign}`);
  url.searchParams.set("environment", `eq.${appleEnvironment}`);
  url.searchParams.set("select", "state,product_id,current_attempt_id,original_transaction_id,environment,access_starts_at,access_ends_at");
  url.searchParams.set("limit", "2");
  const rows = await readRows(configuration, url, fetcher);
  if (rows.length === 0) return null;
  const row = rows[0];
  if (rows.length !== 1 || !["prepared", "scheduled", "redeemed"].includes(row?.state)
    || !productIDs.has(row?.product_id) || row?.environment !== appleEnvironment) {
    throw new Error("Campaign ledger is unavailable.");
  }
  let decision = null;
  let offerID = null;
  let authorizedAt = null;
  if (row.current_attempt_id != null) {
    const attemptID = requiredUUID(row.current_attempt_id);
    const attemptURL = urlFor(configuration, "/rest/v1/storekit_complimentary_campaign_attempts");
    attemptURL.searchParams.set("owner_id", `eq.${owner}`);
    attemptURL.searchParams.set("campaign_id", `eq.${campaign}`);
    attemptURL.searchParams.set("environment", `eq.${appleEnvironment}`);
    attemptURL.searchParams.set("attempt_id", `eq.${attemptID}`);
    attemptURL.searchParams.set("select", "decision,offer_id,product_id,environment,signature_timestamp");
    attemptURL.searchParams.set("limit", "2");
    const attempts = await readRows(configuration, attemptURL, fetcher);
    if (attempts.length !== 1 || !decisions.has(attempts[0]?.decision)
      || attempts[0]?.product_id !== row.product_id
      || attempts[0]?.environment !== appleEnvironment
      || (attempts[0]?.decision !== "introductory" && attempts[0]?.offer_id == null)) {
      throw new Error("Campaign attempt is unavailable.");
    }
    decision = attempts[0].decision;
    offerID = attempts[0].offer_id ?? null;
    authorizedAt = requiredTimestamp(attempts[0].signature_timestamp);
  }
  return {
    state: row.state,
    productID: row.product_id,
    attemptID: row.current_attempt_id ?? null,
    decision,
    offerID,
    authorizedAt,
    originalTransactionID: row.original_transaction_id ?? null,
    environment: row.environment,
    accessStartsAt: row.access_starts_at ?? null,
    accessEndsAt: row.access_ends_at ?? null,
  };
}

async function reserveCampaignAttempt(configuration, input, fetcher) {
  const payload = {
    p_owner_id: requiredUUID(input.ownerID),
    p_campaign_id: requiredCampaignID(input.campaignID),
    p_environment: requiredEnvironment(input.environment),
    p_attempt_id: requiredUUID(input.attemptID),
    p_previous_attempt_id: input.previousAttemptID == null ? null : requiredUUID(input.previousAttemptID),
    p_product_id: requiredProductID(input.productID),
    p_offer_id: input.offerID == null ? null : requiredOfferID(input.offerID),
    p_decision: input.decision,
    p_nonce: requiredUUID(input.nonce),
    p_timestamp: input.timestamp,
    p_now: requiredDate(input.now),
  };
  if (!decisions.has(payload.p_decision) || !Number.isSafeInteger(payload.p_timestamp)
    || payload.p_timestamp <= 0 || (payload.p_decision !== "introductory" && payload.p_offer_id === null)) {
    throw new Error("Invalid campaign preparation.");
  }
  const result = await rpc(configuration, "reserve_storekit_complimentary_campaign_attempt", payload, fetcher);
  if (result.ok && (!result.attempt || canonicalUUID(result.attempt.attemptID) !== payload.p_attempt_id
    || canonicalUUID(result.attempt.nonce) === null || !productIDs.has(result.attempt.productID)
    || result.attempt.productID !== payload.p_product_id || result.attempt.offerID !== payload.p_offer_id
    || result.attempt.decision !== payload.p_decision || !Number.isSafeInteger(result.attempt.timestamp)
    || result.attempt.timestamp <= 0)) {
    throw new Error("Campaign preparation response is unavailable.");
  }
  return result;
}

async function recordCampaignBenefit(configuration, input, fetcher) {
  if (!["scheduled", "redeemed"].includes(input.state)
    || typeof input.originalTransactionID !== "string" || !/^\d+$/.test(input.originalTransactionID)
    || (input.transactionID != null && (typeof input.transactionID !== "string" || !/^\d+$/.test(input.transactionID)))) {
    throw new Error("Invalid verified campaign benefit.");
  }
  return rpc(configuration, "record_storekit_complimentary_campaign_benefit", {
    p_owner_id: requiredUUID(input.ownerID),
    p_campaign_id: requiredCampaignID(input.campaignID),
    p_attempt_id: input.attemptID == null ? null : requiredUUID(input.attemptID),
    p_product_id: requiredProductID(input.productID),
    p_original_transaction_id: input.originalTransactionID,
    p_transaction_id: input.transactionID ?? null,
    p_environment: requiredEnvironment(input.environment),
    p_state: input.state,
    p_access_starts_at: input.accessStartsAt == null ? null : requiredDate(input.accessStartsAt),
    p_access_ends_at: input.accessEndsAt == null ? null : requiredDate(input.accessEndsAt),
    p_now: requiredDate(input.now),
  }, fetcher);
}

async function rpc(configuration, name, payload, fetcher) {
  const response = await fetcher(urlFor(configuration, `/rest/v1/rpc/${name}`), {
    method: "POST", headers: serverHeaders(configuration), body: JSON.stringify(payload),
  });
  const result = await parseResponse(response);
  if (typeof result?.ok !== "boolean" || (result.reason != null && typeof result.reason !== "string")) {
    throw new Error("Campaign persistence response is unavailable.");
  }
  return result;
}

async function readRows(configuration, url, fetcher) {
  const value = await parseResponse(await fetcher(url, { method: "GET", headers: serverHeaders(configuration) }));
  if (!Array.isArray(value)) throw new Error("Campaign persistence response is unavailable.");
  return value;
}

function serverHeaders(configuration) {
  return { apikey: configuration.secretKey, authorization: `Bearer ${configuration.secretKey}`,
    "content-type": "application/json", accept: "application/json" };
}

function urlFor(configuration, path) { return new URL(path, `${configuration.supabaseURL}/`); }

async function parseResponse(response) {
  if (!response.ok) throw new Error(`Campaign persistence request failed with status ${response.status}.`);
  try { return await response.json(); } catch { throw new Error("Campaign persistence response is unavailable."); }
}

function canonicalUUID(value) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : null;
}

function requiredUUID(value) {
  const uuid = canonicalUUID(value);
  if (uuid === null) throw new Error("Invalid campaign account or attempt.");
  return uuid;
}

function requiredCampaignID(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9._-]{1,128}$/.test(value)) throw new Error("Invalid campaign identifier.");
  return value;
}

function requiredOfferID(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9._-]{1,128}$/.test(value)) throw new Error("Invalid campaign offer.");
  return value;
}

function requiredProductID(value) {
  if (!productIDs.has(value)) throw new Error("Invalid campaign product.");
  return value;
}

function requiredEnvironment(value) {
  if (!["sandbox", "production"].includes(value)) throw new Error("Invalid campaign environment.");
  return value;
}

function requiredTimestamp(value) {
  const timestamp = typeof value === "number" || (typeof value === "string" && /^\d+$/.test(value))
    ? Number(value) : NaN;
  if (!Number.isSafeInteger(timestamp) || timestamp <= 0) throw new Error("Campaign authorization time is unavailable.");
  return timestamp;
}

function requiredDate(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (!(typeof value === "string" || value instanceof Date || (typeof value === "number" && Number.isFinite(value) && value > 0))
    || !Number.isFinite(date.getTime())) {
    throw new Error("Invalid campaign date.");
  }
  return date.toISOString();
}
