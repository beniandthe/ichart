import test from "node:test";
import assert from "node:assert/strict";
import { complimentaryCampaignConfigurationFromEnv, complimentaryCampaignID, complimentaryOfferIDs,
  handleComplimentaryOfferRequest } from "./complimentary_offer_campaign.mjs";
import { createSupabaseComplimentaryOfferDependencies } from "./supabase_complimentary_offer_store.mjs";

const qaOwner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ordinaryOwner = "11111111-1111-4111-8111-111111111111";
const attemptID = "22222222-2222-4222-8222-222222222222";
const monthly = "com.ichart.app.pro.monthly";
const now = Date.parse("2026-10-08T12:00:00Z");
const sandbox = { campaignID: complimentaryCampaignID, enabled: true, startsAt: now - 100000,
  endsAt: now + 100000, bundleID: "com.ichart.app", environment: "sandbox", sandboxQAOwnerIDs: [qaOwner] };
const completeEnv = { APP_STORE_ENVIRONMENT: "Production", ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT: "Sandbox",
  ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED: "true", ICHART_COMPLIMENTARY_CAMPAIGN_STARTS_AT: "2026-10-01T00:00:00Z",
  ICHART_COMPLIMENTARY_CAMPAIGN_ENDS_AT: "2026-11-01T00:00:00Z", APP_STORE_BUNDLE_ID: "com.ichart.app",
  APP_STORE_SUBSCRIPTION_KEY_ID: "ABCDEFGHIJ", APP_STORE_SUBSCRIPTION_KEY_P8: "-----BEGIN PRIVATE KEY-----",
  APP_STORE_ISSUER_ID: ordinaryOwner };
const invalidLists = [undefined, null, [], {}, ["*"], [""], [1], [null], [qaOwner + " "], [qaOwner + "\n"],
  [qaOwner, qaOwner.toUpperCase()], Array.from({ length: 33 }, (_, i) => `${i.toString(16).padStart(8, "0")}-aaaa-4aaa-8aaa-aaaaaaaaaaaa`)];

function fixture({ configuration = sandbox, owner = qaOwner, overrides = {} } = {}) {
  const calls = [];
  const methods = { authenticatedUserID: async () => owner, readCampaignLedger: async () => null,
    readSubscriptionSeed: async () => null, verifyAndDecodeTransaction: async () => { throw new Error("unexpected verification"); },
    fetchFreshAppleSnapshot: async () => ({ history: [], statuses: [] }),
    reserveCampaignAttempt: async (input) => ({ ok: true, attempt: input }),
    recordCampaignBenefit: async () => ({ ok: true }),
    signPromotionalOffer: async (input) => ({ keyID: "ABCDEFGHIJ", signature: "synthetic-signature", ...input }), ...overrides };
  const dependencies = Object.fromEntries(Object.entries(methods).map(([name, method]) => [name, async (...args) => {
    calls.push(name); return method(...args);
  }]));
  return { calls, request: async (action, extra = {}, time = now) => {
    const body = { schemaVersion: 1, action, productID: monthly, ...(action === "status" ? {} : { attemptID }), ...extra };
    const response = await handleComplimentaryOfferRequest(new Request("https://example.test", { method: "POST",
      headers: { "x-qa-owner": qaOwner }, body: JSON.stringify(body) }), dependencies, configuration, () => time);
    return { status: response.status, body: await response.json() };
  } };
}

test("Sandbox env configuration requires a strict bounded QA list, including global fallback", () => {
  for (const list of invalidLists) {
    for (const useOverride of [true, false]) {
      const env = { ...completeEnv, ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS: JSON.stringify(list) };
      if (!useOverride) { delete env.ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT; env.APP_STORE_ENVIRONMENT = "Sandbox"; }
      const config = complimentaryCampaignConfigurationFromEnv(env);
      assert.equal(config.enabled, false);
      assert.equal(config.reason, "sandbox_qa_not_configured");
      assert.equal(config.sandboxQAOwnerIDs, null);
    }
  }
  for (const raw of ["", "{", qaOwner, "[]" + " ".repeat(8192)]) {
    assert.equal(complimentaryCampaignConfigurationFromEnv({ ...completeEnv,
      ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS: raw }).enabled, false);
  }
});
test("valid object/get configuration canonicalizes QA UUID case without changing global environment", () => {
  const env = { ...completeEnv, ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS: JSON.stringify([qaOwner.toUpperCase(), ordinaryOwner]) };
  for (const input of [env, { get: (key) => env[key] }]) {
    const config = complimentaryCampaignConfigurationFromEnv(input);
    assert.equal(config.enabled, true);
    assert.equal(config.environment, "sandbox");
    assert.deepEqual(config.sandboxQAOwnerIDs, [qaOwner, ordinaryOwner]);
    assert.ok(Object.isFrozen(config.sandboxQAOwnerIDs));
  }
  assert.equal(env.APP_STORE_ENVIRONMENT, "Production");
});
test("exactly 32 QA owners are accepted without truncation", () => {
  const owners = Array.from({ length: 32 }, (_, i) => `${i.toString(16).padStart(8, "0")}-aaaa-4aaa-8aaa-aaaaaaaaaaaa`);
  const config = complimentaryCampaignConfigurationFromEnv({ ...completeEnv,
    ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS: JSON.stringify(owners) });
  assert.equal(config.enabled, true);
  assert.deepEqual(config.sandboxQAOwnerIDs, owners);
});
test("Production ignores malformed Sandbox QA settings and does not fetch them", () => {
  const env = { ...completeEnv, ICHART_COMPLIMENTARY_CAMPAIGN_ENVIRONMENT: "Production" };
  const input = { get: (key) => { assert.notEqual(key, "ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS"); return env[key]; } };
  const config = complimentaryCampaignConfigurationFromEnv(input);
  assert.equal(config.enabled, true);
  assert.equal(config.environment, "production");
  assert.equal(config.sandboxQAOwnerIDs, null);
});

for (const action of ["status", "prepare", "confirm"]) {
  for (const environment of ["sandbox", "Sandbox", " Sandbox "]) {
    test(`non-QA ${action} is denied before every sink with environment ${JSON.stringify(environment)}`, async () => {
      const state = fixture({ owner: ordinaryOwner, configuration: { ...sandbox, environment } });
      const result = await state.request(action, { signedTransactionInfo: "synthetic-recovery-JWS", previousAttemptID: attemptID });
      assert.equal(result.status, 200);
      assert.equal(result.body.enabled, false);
      assert.equal(result.body.reason, "campaign_not_available");
      assert.equal(result.body.state, "unavailable");
      assert.equal(result.body.signature, undefined);
      assert.equal(result.body.attemptID, undefined);
      assert.equal(result.body.sandboxQAOwnerIDs, undefined);
      assert.deepEqual(state.calls, ["authenticatedUserID"]);
    });
  }
  test(`direct enabled ${action} configurations cannot omit or corrupt QA authorization`, async () => {
    for (const list of invalidLists) {
      const state = fixture({ configuration: { ...sandbox, sandboxQAOwnerIDs: list } });
      const result = await state.request(action, { signedTransactionInfo: "synthetic-recovery-JWS" });
      assert.equal(result.body.enabled, false);
      assert.equal(result.body.reason, "campaign_not_available");
      assert.deepEqual(state.calls, ["authenticatedUserID"]);
    }
  });
  test(`disabled ${action} retains the authenticated disabled short-circuit`, async () => {
    const state = fixture({ configuration: { ...sandbox, enabled: false, sandboxQAOwnerIDs: null }, owner: ordinaryOwner });
    assert.equal((await state.request(action)).body.reason, "campaign_disabled");
    assert.deepEqual(state.calls, ["authenticatedUserID"]);
  });
}
test("invalid effective environments and non-string aliases cannot become Production bypasses", async () => {
  for (const environment of [undefined, null, "unexpected", {}, ["Production"], 1]) {
    const state = fixture({ configuration: { ...sandbox, environment }, owner: ordinaryOwner });
    const result = await state.request("status");
    assert.equal(result.body.enabled, false);
    assert.equal(result.body.reason, "campaign_not_configured");
    assert.deepEqual(state.calls, ["authenticatedUserID"]);
  }
});
test("direct sparse QA arrays cannot authorize an account", async () => {
  const owners = [qaOwner];
  owners.length = 2;
  const state = fixture({ configuration: { ...sandbox, sandboxQAOwnerIDs: owners } });
  assert.equal((await state.request("status")).body.enabled, false);
  assert.deepEqual(state.calls, ["authenticatedUserID"]);
});
test("denial does not mutate shared configuration or block a later approved QA request", async () => {
  assert.equal((await fixture({ owner: ordinaryOwner }).request("status")).body.enabled, false);
  assert.equal(sandbox.enabled, true);
  assert.equal((await fixture({ owner: qaOwner.toUpperCase() }).request("status")).body.state, "available");
});
test("Production ordinary owner remains available regardless of QA config", async () => {
  for (const sandboxQAOwnerIDs of invalidLists) {
    const state = fixture({ owner: ordinaryOwner, configuration: { ...sandbox, environment: "production", sandboxQAOwnerIDs } });
    const result = await state.request("status");
    assert.equal(result.body.enabled, true);
    assert.equal(result.body.state, "available");
    assert.deepEqual(state.calls, ["authenticatedUserID", "readCampaignLedger", "readSubscriptionSeed"]);
  }
});
test("approved QA can prepare introductory purchase without a promotional signer", async () => {
  const state = fixture();
  const result = await state.request("prepare");
  assert.equal(result.status, 200);
  assert.equal(result.body.enabled, true);
  assert.equal(result.body.state, "prepared");
  assert.equal(result.body.decision, "introductory");
  assert.ok(state.calls.includes("reserveCampaignAttempt"));
  assert.ok(!state.calls.includes("signPromotionalOffer"));
});

const transaction = { bundleId: "com.ichart.app", productId: monthly, environment: "Sandbox", appAccountToken: qaOwner,
  type: "Auto-Renewable Subscription", inAppOwnershipType: "PURCHASED", originalTransactionId: "1000", transactionId: "1001",
  purchaseDate: now - 10000, expiresDate: now + 50000 };
test("approved lapsed QA can fetch verified history and sign its promotional preparation", async () => {
  const expired = { ...transaction, purchaseDate: now - 200000, expiresDate: now - 1 };
  const state = fixture({ overrides: { readSubscriptionSeed: async () => ({ originalTransactionID: "1000" }),
    fetchFreshAppleSnapshot: async () => ({ history: [expired], statuses: [{ status: 2, transaction: expired,
      renewal: { autoRenewStatus: 0 } }] }) } });
  const result = await state.request("prepare");
  assert.equal(result.body.state, "prepared");
  assert.equal(result.body.decision, "promotional");
  assert.ok(result.body.signature);
  assert.ok(state.calls.includes("fetchFreshAppleSnapshot"));
  assert.ok(state.calls.includes("signPromotionalOffer"));
});
for (const action of ["status", "confirm"]) {
  test(`approved QA ${action} preserves verified benefit recovery`, async () => {
    const gift = { ...transaction, offerType: 2, offerIdentifier: complimentaryOfferIDs[monthly],
      offerDiscountType: "FREE_TRIAL", offerPeriod: "P1M", price: 0 };
    const state = fixture({ overrides: { readCampaignLedger: async () => ({ state: "prepared", environment: "sandbox",
      attemptID, productID: monthly, decision: "promotional", offerID: complimentaryOfferIDs[monthly] }),
    readSubscriptionSeed: async () => ({ originalTransactionID: "1000" }), verifyAndDecodeTransaction: async () => gift,
    fetchFreshAppleSnapshot: async () => ({ history: [gift], statuses: [] }) } });
    const result = await state.request(action, { signedTransactionInfo: "synthetic-gift" }, sandbox.endsAt + 1);
    assert.equal(result.status, 200);
    assert.equal(result.body.state, "redeemed");
    assert.equal(result.body.enabled, true);
    assert.ok(state.calls.includes("recordCampaignBenefit"));
    assert.ok(!state.calls.includes("reserveCampaignAttempt"));
    assert.ok(!state.calls.includes("signPromotionalOffer"));
  });
}
test("approved QA retains post-cutoff prepared recovery without new signing", async () => {
  const state = fixture({ overrides: { readCampaignLedger: async () => ({ state: "prepared", environment: "sandbox",
    attemptID, authorizedAt: now, productID: monthly, decision: "introductory", offerID: null }) } });
  const result = await state.request("status", {}, sandbox.endsAt + 1);
  assert.equal(result.body.state, "prepared");
  assert.equal(result.body.canPrepare, false);
  assert.equal(result.body.reason, "prepared_recovery_only");
  assert.ok(!state.calls.includes("reserveCampaignAttempt"));
});
test("server auth identity defeats QA-looking user metadata, headers and request identity", async () => {
  const paths = [];
  const dependencies = createSupabaseComplimentaryOfferDependencies({ SUPABASE_URL: "https://example.test",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-server-key" }, { fetch: async (url) => {
    paths.push(new URL(url).pathname);
    assert.equal(new URL(url).pathname, "/auth/v1/user");
    return new Response(JSON.stringify({ id: ordinaryOwner, is_anonymous: false,
      user_metadata: { qa: true, owner_id: qaOwner } }));
  } });
  const request = (body) => new Request("https://example.test", { method: "POST", headers: {
    authorization: "Bearer synthetic-user-token", "x-qa-owner": qaOwner }, body: JSON.stringify(body) });
  const base = { schemaVersion: 1, action: "status", productID: monthly };
  const response = await handleComplimentaryOfferRequest(request(base), dependencies, sandbox, () => now);
  assert.equal((await response.json()).reason, "campaign_not_available");
  assert.deepEqual(paths, ["/auth/v1/user"]);
  const forged = await handleComplimentaryOfferRequest(request({ ...base, ownerID: qaOwner }), dependencies, sandbox, () => now);
  assert.equal(forged.status, 400);
  assert.deepEqual(paths, ["/auth/v1/user"]);
});
