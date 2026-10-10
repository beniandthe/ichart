import test from "node:test";
import assert from "node:assert/strict";
import { createSupabaseComplimentaryOfferDependencies } from "./supabase_complimentary_offer_store.mjs";

const ownerID = "A8CE4681-7733-4CF2-8413-12EC9331B6B2";
const owner = ownerID.toLowerCase();
const attemptID = "cb40f913-f81e-4b66-8dc9-d0211d094ad3";
const previousAttemptID = "a3e0b50d-df9c-4dd5-bfab-f1d34db5b3ad";
const nonce = "ee5293bd-6ebc-4350-b6c0-eb8f809c34cd";
const campaignID = "ichart-complimentary-pro-1m-v1";
const productID = "com.ichart.app.pro.annual";
const offerID = "ichart_complimentary_annual_1m_v1";
const now = "2026-10-08T12:00:00.000Z";
const appleEnvironment = "production";
const environment = { SUPABASE_URL: "https://example.supabase.co/", SUPABASE_SERVICE_ROLE_KEY: "server-secret" };

function adapter(responses) {
  const calls = [];
  const dependencies = createSupabaseComplimentaryOfferDependencies(environment, {
    fetch: async (url, options) => {
      calls.push({ url: new URL(url), ...options });
      const response = responses.shift();
      if (response instanceof Error) throw response;
      if (response instanceof Response) return response;
      assert.notEqual(response, undefined, "Unexpected request");
      return Response.json(response);
    },
  });
  return { dependencies, calls };
}

test("missing server configuration exposes no persistence dependencies", () => {
  assert.deepEqual(createSupabaseComplimentaryOfferDependencies({}), {});
});

test("auth resolves a canonical owner only through the user endpoint", async () => {
  const { dependencies, calls } = adapter([{ id: ownerID, is_anonymous: false,
    user_metadata: { owner_id: "forged-owner" } }]);
  assert.equal(await dependencies.authenticatedUserID(new Request("https://example.test", {
    headers: { authorization: "Bearer app-jwt" },
  })), owner);
  assert.equal(calls[0].url.pathname, "/auth/v1/user");
  assert.equal(calls[0].headers.authorization, "Bearer app-jwt");
  assert.equal(calls[0].headers.apikey, "server-secret");
});

test("missing, rejected, anonymous, indeterminate, and non-UUID auth fail closed", async () => {
  const absent = adapter([]);
  assert.equal(await absent.dependencies.authenticatedUserID(new Request("https://example.test")), null);
  assert.equal(absent.calls.length, 0);
  for (const response of [new Response(null, { status: 401 }), new Response(null, { status: 403 }),
    { id: owner, is_anonymous: true }, { id: owner }, { id: "not-a-uuid", is_anonymous: false }]) {
    const { dependencies } = adapter([response]);
    assert.equal(await dependencies.authenticatedUserID(new Request("https://example.test", {
      headers: { authorization: "Bearer app-jwt" },
    })), null);
  }
});

test("auth failures disclose only status, not bearer or server key", async () => {
  const { dependencies } = adapter([new Response("app-jwt server-secret", { status: 500 })]);
  await assert.rejects(dependencies.authenticatedUserID(new Request("https://example.test", {
    headers: { authorization: "Bearer app-jwt" },
  })), { message: "Campaign persistence request failed with status 500." });
});

test("owned StoreKit seed binds the original chain and stored token to the server owner", async () => {
  const { dependencies, calls } = adapter([{ owner_id: owner, storekit_original_transaction_id: "2000000123",
    storekit_app_account_token: ownerID, storekit_environment: appleEnvironment }].map((row) => [row]));
  assert.deepEqual(await dependencies.readSubscriptionSeed(ownerID, appleEnvironment), { originalTransactionID: "2000000123" });
  assert.equal(calls[0].url.searchParams.get("owner_id"), `eq.${owner}`);
  assert.equal(calls[0].url.searchParams.get("provider"), "eq.storekit");
  assert.equal(calls[0].url.searchParams.get("storekit_environment"), `eq.${appleEnvironment}`);
  assert.ok(calls[0].url.searchParams.get("select").split(",").includes("storekit_environment"));
  assert.equal(calls[0].headers.authorization, "Bearer server-secret");
});

test("unmapped chain is null but conflicting chain/token cannot seed Apple history", async () => {
  assert.equal(await adapter([[]]).dependencies.readSubscriptionSeed(owner, appleEnvironment), null);
  for (const rows of [[{ owner_id: owner, storekit_original_transaction_id: "123", storekit_app_account_token: null, storekit_environment: appleEnvironment }],
    [{ owner_id: nonce, storekit_original_transaction_id: "123", storekit_app_account_token: owner, storekit_environment: appleEnvironment }],
    [{ owner_id: owner, storekit_original_transaction_id: "123", storekit_app_account_token: nonce, storekit_environment: appleEnvironment }]]) {
    await assert.rejects(adapter([rows]).dependencies.readSubscriptionSeed(owner, appleEnvironment), /ownership is unavailable/);
  }
});

test("ledger returns current owned attempt metadata without a signature", async () => {
  const { dependencies, calls } = adapter([[
    { state: "prepared", product_id: productID, current_attempt_id: attemptID, original_transaction_id: null,
      environment: appleEnvironment, access_starts_at: null, access_ends_at: null },
  ], [{ decision: "scheduledPromotional", offer_id: offerID, product_id: productID,
    environment: appleEnvironment, signature_timestamp: Date.parse(now) }]]);
  assert.deepEqual(await dependencies.readCampaignLedger({ ownerID, campaignID, environment: appleEnvironment }), {
    state: "prepared", productID, attemptID, decision: "scheduledPromotional", offerID,
    authorizedAt: Date.parse(now), originalTransactionID: null, environment: appleEnvironment, accessStartsAt: null, accessEndsAt: null,
  });
  assert.equal(calls[1].url.searchParams.get("attempt_id"), `eq.${attemptID}`);
  for (const call of calls) {
    assert.equal(call.url.searchParams.get("owner_id"), `eq.${owner}`);
    assert.equal(call.url.searchParams.get("campaign_id"), `eq.${campaignID}`);
    assert.equal(call.url.searchParams.get("environment"), `eq.${appleEnvironment}`);
    assert.ok(!call.url.searchParams.get("select").split(",").includes("signature"));
  }
});

test("unmapped ledger is null and corrupt attempt metadata fails closed", async () => {
  assert.equal(await adapter([[]]).dependencies.readCampaignLedger({ ownerID, campaignID, environment: appleEnvironment }), null);
  await assert.rejects(adapter([[{ state: "prepared", product_id: productID, current_attempt_id: attemptID,
    environment: appleEnvironment }], []])
    .dependencies.readCampaignLedger({ ownerID, campaignID, environment: appleEnvironment }), /attempt is unavailable/);
});

test("reservation uses a single RPC with owner, attempt CAS, product and nonce; no secrets in body", async () => {
  const result = { ok: true, attempt: { attemptID, productID, offerID, decision: "scheduledPromotional",
    nonce, timestamp: Date.parse(now) } };
  const { dependencies, calls } = adapter([result]);
  assert.deepEqual(await dependencies.reserveCampaignAttempt({ ownerID, campaignID, environment: appleEnvironment, attemptID, previousAttemptID,
    productID, offerID, decision: "scheduledPromotional", nonce, timestamp: Date.parse(now), now }), result);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url.pathname, "/rest/v1/rpc/reserve_storekit_complimentary_campaign_attempt");
  const payload = JSON.parse(calls[0].body);
  assert.equal(payload.p_owner_id, owner);
  assert.equal(payload.p_environment, appleEnvironment);
  assert.equal(payload.p_previous_attempt_id, previousAttemptID);
  assert.equal(payload.p_nonce, nonce);
  assert.ok(!calls[0].body.includes("server-secret"));
  assert.ok(!Object.keys(payload).some((key) => key.includes("signature")));
});

test("reservation conflict reasons are preserved without local optimistic success", async () => {
  for (const reason of ["attempt_conflict", "another_product_reserved", "attempt_retired", "campaign_already_consumed"]) {
    const result = { ok: false, reason };
    const { dependencies } = adapter([result]);
    assert.deepEqual(await dependencies.reserveCampaignAttempt({ ownerID, campaignID, environment: appleEnvironment, attemptID, productID, offerID,
      decision: "promotional", nonce, timestamp: Date.parse(now), now }), result);
  }
});

test("confirmed benefit is a separate RPC and requires a verified transaction identity shape", async () => {
  const { dependencies, calls } = adapter([{ ok: true }]);
  assert.deepEqual(await dependencies.recordCampaignBenefit({ ownerID, campaignID, attemptID, productID,
    originalTransactionID: "123", transactionID: "124", environment: "production", state: "scheduled", now }), { ok: true });
  assert.equal(calls[0].url.pathname, "/rest/v1/rpc/record_storekit_complimentary_campaign_benefit");
  const payload = JSON.parse(calls[0].body);
  assert.equal(payload.p_attempt_id, attemptID);
  assert.equal(payload.p_original_transaction_id, "123");
  assert.equal(payload.p_state, "scheduled");
  assert.equal(payload.p_environment, "production");
  assert.equal(payload.p_access_starts_at, null);
  assert.equal(payload.p_access_ends_at, null);
});

test("fresh server-observed history can record without an app attempt", async () => {
  const { dependencies, calls } = adapter([{ ok: true }]);
  await dependencies.recordCampaignBenefit({ ownerID, campaignID, productID, originalTransactionID: "123",
    environment: "sandbox", state: "redeemed", accessStartsAt: now,
    accessEndsAt: "2026-11-08T12:00:00.000Z", now });
  assert.equal(JSON.parse(calls[0].body).p_attempt_id, null);
});

test("numeric server-clock milliseconds normalize to an ISO timestamp", async () => {
  const { dependencies, calls } = adapter([{ ok: true }]);
  await dependencies.recordCampaignBenefit({ ownerID, campaignID, productID, originalTransactionID: "123",
    environment: "production", state: "redeemed", now: Date.parse(now) });
  assert.equal(JSON.parse(calls[0].body).p_now, now);
});

test("superseded attempt confirmation failure is returned without changing the benefit", async () => {
  const { dependencies } = adapter([{ ok: false, reason: "attempt_retired" }]);
  assert.deepEqual(await dependencies.recordCampaignBenefit({ ownerID, campaignID, attemptID, productID,
    originalTransactionID: "123", environment: "production", state: "redeemed", now }), {
    ok: false, reason: "attempt_retired",
  });
});

test("invalid values never reach privileged RPCs", async () => {
  const { dependencies, calls } = adapter([]);
  const preparation = { ownerID, campaignID, environment: appleEnvironment, attemptID, productID, offerID,
    decision: "promotional", nonce, timestamp: Date.parse(now), now };
  for (const change of [{ ownerID: "client-selected" }, { productID: "unlisted" }, { offerID: null },
    { decision: "redeemed" }, { timestamp: NaN }, { previousAttemptID: "invalid" }, { environment: "other" }, { environment: undefined }]) {
    await assert.rejects(dependencies.reserveCampaignAttempt({ ...preparation, ...change }));
  }
  const benefit = { ownerID, campaignID, productID, originalTransactionID: "123", environment: "production", state: "redeemed", now };
  for (const change of [{ environment: "other" }, { environment: undefined }, { state: "prepared" }, { originalTransactionID: "abc" },
    { transactionID: "abc" }, { now: "not-a-date" }]) {
    await assert.rejects(dependencies.recordCampaignBenefit({ ...benefit, ...change }));
  }
  assert.equal(calls.length, 0);
});

test("malformed RPC responses and REST errors do not become successful writes", async () => {
  const input = { ownerID, campaignID, productID, originalTransactionID: "123", environment: "production", state: "redeemed", now };
  for (const response of [{}, [], null, { ok: "yes" }, new Response("secret error payload", { status: 409 })]) {
    await assert.rejects(adapter([response]).dependencies.recordCampaignBenefit(input));
  }
});

test("all environment-scoped reads reject a missing or unexpected environment before making a request", async () => {
  const { dependencies, calls } = adapter([]);
  for (const environment of [undefined, null, "Sandbox", "unknown"]) {
    await assert.rejects(dependencies.readSubscriptionSeed(owner, environment), /Invalid campaign environment/);
    await assert.rejects(dependencies.readCampaignLedger({ ownerID, campaignID, environment }), /Invalid campaign environment/);
  }
  assert.equal(calls.length, 0);
});

test("wrong-environment subscription rows fail closed instead of seeding Apple history", async () => {
  for (const storekit_environment of [undefined, null, "sandbox", "Production"]) {
    const { dependencies } = adapter([[{ owner_id: owner, storekit_original_transaction_id: "123",
      storekit_app_account_token: owner, storekit_environment }]]);
    await assert.rejects(dependencies.readSubscriptionSeed(owner, "production"), /ownership is unavailable/);
  }
});

test("wrong-environment account or attempt rows cannot become a campaign status", async () => {
  const account = { state: "prepared", product_id: productID, current_attempt_id: attemptID, environment: "production" };
  const attempt = { decision: "promotional", offer_id: offerID, product_id: productID, environment: "production",
    signature_timestamp: Date.parse(now) };
  for (const environment of [undefined, null, "sandbox"]) {
    await assert.rejects(adapter([[{ ...account, environment }]])
      .dependencies.readCampaignLedger({ ownerID, campaignID, environment: "production" }), /ledger is unavailable/);
    await assert.rejects(adapter([[account], [{ ...attempt, environment }]])
      .dependencies.readCampaignLedger({ ownerID, campaignID, environment: "production" }), /attempt is unavailable/);
  }
});

test("authorization timestamp normalizes safe integer bigint JSON representations", async () => {
  for (const signature_timestamp of [Date.parse(now), String(Date.parse(now))]) {
    const { dependencies } = adapter([[{ state: "prepared", product_id: productID,
      current_attempt_id: attemptID, environment: appleEnvironment }], [{ decision: "promotional",
      offer_id: offerID, product_id: productID, environment: appleEnvironment, signature_timestamp }]]);
    const ledger = await dependencies.readCampaignLedger({ ownerID, campaignID, environment: appleEnvironment });
    assert.equal(ledger.authorizedAt, Date.parse(now));
    assert.equal(typeof ledger.authorizedAt, "number");
  }
});

test("absent, invalid, or unsafe authorization timestamps fail closed", async () => {
  for (const signature_timestamp of [undefined, null, 0, -1, 1.5, Infinity, Number.MAX_SAFE_INTEGER + 1,
    "not-a-time", "1e3", "9007199254740992"]) {
    const { dependencies } = adapter([[{ state: "prepared", product_id: productID,
      current_attempt_id: attemptID, environment: appleEnvironment }], [{ decision: "promotional",
      offer_id: offerID, product_id: productID, environment: appleEnvironment, signature_timestamp }]]);
    await assert.rejects(dependencies.readCampaignLedger({ ownerID, campaignID, environment: appleEnvironment }),
      /authorization time is unavailable/);
  }
});

test("a server-observed benefit without a current attempt returns no authorization timestamp", async () => {
  const { dependencies, calls } = adapter([[{ state: "redeemed", product_id: productID,
    current_attempt_id: null, environment: "sandbox", original_transaction_id: "123",
    access_starts_at: now, access_ends_at: "2026-11-08T12:00:00.000Z" }]]);
  const ledger = await dependencies.readCampaignLedger({ ownerID, campaignID, environment: "sandbox" });
  assert.equal(ledger.authorizedAt, null);
  assert.equal(ledger.environment, "sandbox");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url.searchParams.get("environment"), "eq.sandbox");
});
