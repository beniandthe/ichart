import test from "node:test";
import assert from "node:assert/strict";
import { createSupabaseComplimentaryOfferDependencies } from "./supabase_complimentary_offer_store.mjs";
import { createSupabaseSubscriptionAuthorityDependencies } from "./supabase_subscription_authority_store.mjs";
import { handleStoreKitSubscriptionClaimRequest } from "./app_store_subscription_authority.mjs";
import { handleComplimentaryOfferRequest, complimentaryCampaignID, complimentaryOfferIDs } from "./complimentary_offer_campaign.mjs";

const ownerID = "11111111-1111-4111-8111-111111111111";
const attemptID = "22222222-2222-4222-8222-222222222222";
const monthly = "com.ichart.app.pro.monthly";
const annual = "com.ichart.app.pro.annual";
const now = Date.parse("2026-10-08T12:00:00Z");
const configuration = { campaignID: complimentaryCampaignID, enabled: true, startsAt: now - 86400000,
  endsAt: now + 86400000, bundleID: "com.ichart.app", environment: "production" };
const baseTransaction = { bundleId: "com.ichart.app", productId: monthly, environment: "Production", appAccountToken: ownerID,
  type: "Auto-Renewable Subscription", inAppOwnershipType: "PURCHASED", originalTransactionId: "1000", transactionId: "1001",
  purchaseDate: now - 10000, expiresDate: now + 100000, signedDate: now };

// Real REST adapters and both actual request handlers. Only auth/REST/Apple I/O
// are mocked; this intentionally checks the cross-module JSON seam.
function fixture({ existingTransaction, decision = "introductory" } = {}) {
  let subscription = existingTransaction ? { owner_id: ownerID, provider: "storekit", storekit_original_transaction_id: "1000",
    storekit_app_account_token: ownerID, storekit_environment: existingTransaction.environment.toLowerCase() } : null;
  const accounts = new Map();
  const attempts = new Map();
  let time = now;
  let fresh = existingTransaction ? { history: [existingTransaction], statuses: [{ status: 2, transaction: existingTransaction,
    renewal: { productId: monthly, autoRenewProductId: monthly, autoRenewStatus: 0, renewalDate: now - 1 } }] } : { history: [], statuses: [] };
  let verified = { ...baseTransaction, offerType: decision === "introductory" ? 1 : 2,
    ...(decision === "introductory" ? {} : { offerIdentifier: complimentaryOfferIDs[monthly] }),
    offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 };
  const requests = [];
  const appleRequests = [];
  const benefitWrites = [];
  const signatureRequests = [];
  const fetcher = async (input, options = {}) => {
    const url = new URL(input);
    requests.push({ path: url.pathname, query: url.searchParams, method: options.method ?? "GET" });
    const json = (value) => new Response(JSON.stringify(value), { status: 200 });
    if (url.pathname === "/auth/v1/user") return json({ id: ownerID, is_anonymous: false });
    if (url.pathname === "/rest/v1/subscriptions") {
      if (options.method === "POST") { subscription = JSON.parse(options.body); return json([subscription]); }
      if (url.searchParams.has("storekit_environment")
          && subscription?.storekit_environment !== url.searchParams.get("storekit_environment").slice(3)) return json([]);
      return json(subscription ? [subscription] : []);
    }
    const environment = url.searchParams.get("environment")?.slice(3);
    if (url.pathname === "/rest/v1/storekit_complimentary_campaign_accounts") {
      const account = accounts.get(environment);
      return json(account ? [account] : []);
    }
    if (url.pathname === "/rest/v1/storekit_complimentary_campaign_attempts") {
      const attempt = attempts.get(`${environment}:${url.searchParams.get("attempt_id")?.slice(3)}`);
      return json(attempt ? [attempt] : []);
    }
    const body = JSON.parse(options.body);
    if (url.pathname === "/rest/v1/rpc/reserve_storekit_complimentary_campaign_attempt") {
      const key = `${body.p_environment}:${body.p_attempt_id}`;
      const attempt = attempts.get(key) ?? { attempt_id: body.p_attempt_id, product_id: body.p_product_id, environment: body.p_environment,
        offer_id: body.p_offer_id, decision: body.p_decision, nonce: body.p_nonce, signature_timestamp: body.p_timestamp };
      attempts.set(key, attempt);
      accounts.set(body.p_environment, { state: "prepared", product_id: body.p_product_id, current_attempt_id: body.p_attempt_id, environment: body.p_environment });
      return json({ ok: true, attempt: { attemptID: attempt.attempt_id, productID: attempt.product_id, offerID: attempt.offer_id,
        decision: attempt.decision, nonce: attempt.nonce, timestamp: attempt.signature_timestamp } });
    }
    if (url.pathname === "/rest/v1/rpc/record_storekit_complimentary_campaign_benefit") {
      benefitWrites.push(body);
      accounts.set(body.p_environment, { ...accounts.get(body.p_environment), state: body.p_state, product_id: body.p_product_id,
        original_transaction_id: body.p_original_transaction_id, transaction_id: body.p_transaction_id, environment: body.p_environment,
        access_starts_at: body.p_access_starts_at, access_ends_at: body.p_access_ends_at });
      return json({ ok: true });
    }
    throw new Error("Unexpected fixture I/O");
  };
  const env = { SUPABASE_URL: "https://example.test", SUPABASE_SERVICE_ROLE_KEY: "synthetic-server-key" };
  const verification = { verifyAndDecodeTransaction: async () => verified };
  const dependencies = { ...createSupabaseComplimentaryOfferDependencies(env, { fetch: fetcher }), ...verification,
    fetchFreshAppleSnapshot: async (input) => { appleRequests.push(input); return fresh; },
    signPromotionalOffer: async (input) => {
      signatureRequests.push(input);
      return { keyID: "ABCDEFGHIJ", signature: "synthetic", ...input };
    } };
  const requestFor = (body) => new Request("https://example.test", { method: "POST", headers: { authorization: "Bearer synthetic-user-session" },
    body: JSON.stringify(body) });
  return {
    requests,
    appleRequests,
    benefitWrites,
    signatureRequests,
    account: (environment) => accounts.get(environment),
    setTime: (timestamp) => { time = timestamp; },
    setSubscription: (row) => { subscription = row; },
    setAccount: (environment, account) => { accounts.set(environment, account); },
    setFresh: (snapshot) => { fresh = snapshot; },
    setVerified: (transaction) => { verified = transaction; },
    currentGift: () => verified,
    campaign: async (action, extra = {}, campaignConfiguration = configuration) => {
      const response = await handleComplimentaryOfferRequest(requestFor({ schemaVersion: 1, action, productID: monthly, ...extra }), dependencies, campaignConfiguration, () => time);
      return { status: response.status, body: await response.json() };
    },
    claim: async () => {
      const response = await handleStoreKitSubscriptionClaimRequest(requestFor({ signedTransactionInfo: "verified-gift" }),
        { ...createSupabaseSubscriptionAuthorityDependencies(env, { fetch: fetcher }), ...verification, now: new Date(time) });
      return { status: response.status, body: await response.json() };
    },
  };
}

test("new intro purchase must pass existing verified claim before campaign confirm", async () => {
  const state = fixture();
  const prepared = await state.campaign("prepare", { attemptID });
  assert.equal(prepared.body.decision, "introductory");
  assert.equal(prepared.body.state, "prepared");
  assert.equal((await state.campaign("confirm", { attemptID, signedTransactionInfo: "verified-gift" })).body.reason,
    "verified_subscription_claim_required");
  const claim = await state.claim();
  assert.equal(claim.status, 202);
  assert.equal(claim.body.stored, true);
  state.setFresh({ history: [state.currentGift()], statuses: [{ status: 1, transaction: state.currentGift(), renewal: {} }] });
  const confirmed = await state.campaign("confirm", { attemptID, signedTransactionInfo: "verified-gift" });
  assert.equal(confirmed.status, 200);
  assert.equal(confirmed.body.state, "redeemed");
  assert.equal(confirmed.body.attemptID, attemptID);
  assert.equal(confirmed.body.signature, undefined);
});

test("real owned seed object + current attempt decision permits lapsed promotional confirmation", async () => {
  const state = fixture({ existingTransaction: { ...baseTransaction, expiresDate: now - 1 }, decision: "promotional" });
  const available = await state.campaign("status");
  assert.equal(available.body.decision, "promotional");
  const prepared = await state.campaign("prepare", { attemptID });
  assert.equal(prepared.body.state, "prepared");
  assert.equal(prepared.body.signature.appAccountToken, ownerID);
  const recovery = await state.campaign("status");
  assert.equal(recovery.body.state, "prepared");
  assert.equal(recovery.body.attemptID, attemptID);
  assert.equal(recovery.body.signature, undefined);
  assert.equal((await state.claim()).body.stored, true);
  state.setFresh({ history: [state.currentGift()], statuses: [{ status: 1, transaction: state.currentGift(), renewal: {} }] });
  const confirmed = await state.campaign("confirm", { attemptID, signedTransactionInfo: "verified-gift" });
  assert.equal(confirmed.status, 200);
  assert.equal(confirmed.body.decision, "promotional");
  assert.equal(confirmed.body.attemptID, attemptID);
  assert.ok(state.requests.some((entry) => entry.path.endsWith("campaign_attempts")));
});

for (const productID of [monthly, annual]) {
  for (const offerDiscountType of ["FREE_TRIAL", "PAY_UP_FRONT"]) {
    test(`${productID} ${offerDiscountType} scheduled benefit becomes redeemed and recovery repeats original transaction`, async () => {
      const paid = { ...baseTransaction, productId: productID };
      const state = fixture({ existingTransaction: paid, decision: "scheduledPromotional" });
      const paidRenewal = { productId: productID, autoRenewProductId: productID, autoRenewStatus: 1,
        renewalDate: paid.expiresDate };
      state.setVerified(paid);
      state.setFresh({ history: [paid], statuses: [{ status: 1, transaction: paid, renewal: paidRenewal }] });
      const prepared = await state.campaign("prepare", { productID, attemptID });
      assert.equal(prepared.body.state, "prepared");
      assert.equal(prepared.body.decision, "scheduledPromotional");
      state.setFresh({ history: [paid], statuses: [{ status: 1, transaction: paid, renewal: { ...paidRenewal,
        offerType: 2, offerIdentifier: complimentaryOfferIDs[productID], offerDiscountType, offerPeriod: "P1M", renewalPrice: 0 } }] });
      const scheduled = await state.campaign("confirm", { productID, attemptID, signedTransactionInfo: "verified-current-paid-term" });
      assert.equal(scheduled.status, 200);
      assert.equal(scheduled.body.state, "scheduled");
      assert.equal(state.account("production").state, "scheduled");
      assert.equal(state.account("production").transaction_id, paid.transactionId);
      assert.equal(state.account("production").access_ends_at, null);

      const gift = { ...paid, transactionId: "1002", purchaseDate: paid.expiresDate,
        expiresDate: paid.expiresDate + 200000, signedDate: paid.expiresDate,
        offerType: 2, offerIdentifier: complimentaryOfferIDs[productID], offerDiscountType, offerPeriod: "P1M", price: 0 };
      state.setTime(gift.purchaseDate + 1);
      state.setVerified(gift);
      assert.equal((await state.claim()).body.stored, true);
      state.setFresh({ history: [paid, gift], statuses: [{ status: 1, transaction: gift, renewal: {} }] });
      const redeemed = await state.campaign("confirm", { productID, attemptID, signedTransactionInfo: "verified-actual-gift" });
      assert.equal(redeemed.status, 200);
      assert.equal(redeemed.body.state, "redeemed");
      assert.equal(redeemed.body.decision, "scheduledPromotional");
      assert.equal(redeemed.body.activation, "nextBillingEvent");
      assert.equal(redeemed.body.accessStartsAt, new Date(gift.purchaseDate).toISOString());
      assert.equal(redeemed.body.accessEndsAt, new Date(gift.expiresDate).toISOString());
      assert.equal(redeemed.body.estimatedAccessEndsAt, undefined);
      assert.equal(redeemed.body.accessEndsAtIsEstimated, undefined);
      const recorded = state.account("production");
      assert.equal(recorded.state, "redeemed");
      assert.equal(recorded.current_attempt_id, attemptID);
      assert.equal(recorded.transaction_id, gift.transactionId);
      assert.equal(recorded.access_starts_at, redeemed.body.accessStartsAt);
      assert.equal(recorded.access_ends_at, redeemed.body.accessEndsAt);

      const duplicate = { ...gift, transactionId: "1003", purchaseDate: gift.purchaseDate + 100000,
        expiresDate: gift.expiresDate + 100000 };
      state.setFresh({ history: [duplicate, gift, paid], statuses: [{ status: 1, transaction: duplicate, renewal: {} }] });
      const repeat = await state.campaign("confirm", { productID, attemptID, signedTransactionInfo: "verified-actual-gift" });
      assert.equal(repeat.status, 200);
      assert.equal(repeat.body.state, "redeemed");
      assert.equal(repeat.body.accessStartsAt, redeemed.body.accessStartsAt);
      assert.equal(repeat.body.accessEndsAt, redeemed.body.accessEndsAt);
      assert.deepEqual(state.account("production"), recorded);
      const actualWrites = state.benefitWrites.slice(1);
      assert.equal(actualWrites.length, 2);
      assert.ok(actualWrites.every(write => write.p_state === "redeemed" && write.p_transaction_id === gift.transactionId
        && write.p_access_starts_at === redeemed.body.accessStartsAt && write.p_access_ends_at === redeemed.body.accessEndsAt));
      assert.equal(state.signatureRequests.length, 1);
      assert.equal(state.requests.filter(request => request.path.endsWith("reserve_storekit_complimentary_campaign_attempt")).length, 1);
    });
  }
}

test("another requested product never exposes scheduled or available crossgrade", async () => {
  const state = fixture({ existingTransaction: { ...baseTransaction, productId: annual } });
  const current = { ...baseTransaction, productId: annual };
  state.setFresh({ history: [current], statuses: [{ status: 1, transaction: current, renewal: { productId: annual, autoRenewProductId: annual,
    offerType: 2, offerIdentifier: complimentaryOfferIDs[annual], offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", renewalPrice: 0,
    autoRenewStatus: 1, renewalDate: current.expiresDate } }] });
  const result = await state.campaign("status");
  assert.equal(result.body.productID, monthly);
  assert.equal(result.body.state, "unavailable");
  assert.equal(result.body.signature, undefined);
});

test("predeadline introductory authorization survives pending approval after cutoff through actual adapters", async () => {
  const state = fixture();
  assert.equal((await state.campaign("prepare", { attemptID })).body.state, "prepared");
  const approvedAt = configuration.endsAt + 14 * 86400000;
  state.setTime(approvedAt + 1);
  const recovering = await state.campaign("status");
  assert.equal(recovering.body.state, "prepared");
  assert.equal(recovering.body.canPrepare, false);
  assert.equal(recovering.body.attemptID, attemptID);
  assert.equal(recovering.body.signature, undefined);
  const writesBefore = state.requests.filter((request) => request.path.includes("/rpc/")).length;
  const denied = await state.campaign("prepare", { attemptID: ownerID, previousAttemptID: attemptID });
  assert.equal(denied.body.reason, "campaign_ended");
  assert.equal(state.requests.filter((request) => request.path.includes("/rpc/")).length, writesBefore);
  const gift = { ...state.currentGift(), purchaseDate: approvedAt, signedDate: approvedAt, expiresDate: approvedAt + 30 * 86400000 };
  state.setVerified(gift);
  assert.equal((await state.claim()).body.stored, true);
  state.setFresh({ history: [gift], statuses: [{ status: 1, transaction: gift, renewal: {} }] });
  const confirmed = await state.campaign("confirm", { attemptID, signedTransactionInfo: "verified-late-gift" });
  assert.equal(confirmed.status, 200);
  assert.equal(confirmed.body.state, "redeemed");
  assert.equal(confirmed.body.accessStartsAt, new Date(approvedAt).toISOString());
});

test("same-owner Sandbox consumption cannot block or reserve Production campaign", async () => {
  const state = fixture();
  const sandbox = { ...configuration, environment: "sandbox", sandboxQAOwnerIDs: [ownerID] };
  const sandboxGift = { ...state.currentGift(), environment: "Sandbox" };
  assert.equal((await state.campaign("prepare", { attemptID }, sandbox)).body.state, "prepared");
  state.setFresh({ history: [sandboxGift], statuses: [{ status: 1, transaction: sandboxGift, renewal: {} }] });
  state.setVerified(sandboxGift);
  assert.equal((await state.campaign("status", { signedTransactionInfo: "verified-sandbox-gift" }, sandbox)).body.state, "redeemed");
  state.setFresh({ history: [], statuses: [] });
  const production = await state.campaign("status");
  assert.equal(production.body.state, "available");
  assert.equal(production.body.attemptID, undefined);
  assert.equal((await state.campaign("prepare", { attemptID })).body.state, "prepared");
  assert.ok(state.requests.filter((request) => request.path.endsWith("campaign_accounts"))
    .every((request) => ["eq.production", "eq.sandbox"].includes(request.query.get("environment"))));
});

test("wrong-environment subscription seed is excluded instead of sent to campaign Apple API", async () => {
  const state = fixture({ existingTransaction: { ...baseTransaction, environment: "Sandbox" } });
  state.setFresh({ history: [], statuses: [] });
  const result = await state.campaign("status");
  assert.equal(result.body.decision, "introductory");
  assert.equal(state.appleRequests.length, 0);
  assert.ok(state.requests.some((request) => request.path.endsWith("subscriptions")
    && request.query.get("storekit_environment") === "eq.production"));
});
