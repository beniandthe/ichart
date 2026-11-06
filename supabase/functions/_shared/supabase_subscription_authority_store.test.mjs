import assert from "node:assert/strict";
import test from "node:test";

import {
  authenticatedUserIDFromBearer,
  supabaseAuthorityStoreConfigurationFromEnv,
  supabaseSecretKeyFromEnv,
  updateMappedSubscriptionAuthority,
  upsertSubscriptionAuthorityClaim,
} from "./supabase_subscription_authority_store.mjs";

function env(values) {
  return {
    get(key) {
      return values[key];
    },
  };
}

test("store configuration stays disabled without server-only Supabase credentials", () => {
  assert.equal(supabaseAuthorityStoreConfigurationFromEnv(env({})), null);
  assert.equal(
    supabaseAuthorityStoreConfigurationFromEnv(env({ SUPABASE_URL: "https://project.supabase.co" })),
    null
  );
});

test("store configuration reads default Supabase secret key dictionary", () => {
  const configuration = supabaseAuthorityStoreConfigurationFromEnv(
    env({
      SUPABASE_URL: "https://project.supabase.co/",
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: "server-only-key" }),
    })
  );

  assert.equal(configuration.supabaseURL, "https://project.supabase.co");
  assert.equal(configuration.secretKey, "server-only-key");
});

test("store configuration falls back to legacy service role env name", () => {
  assert.equal(
    supabaseSecretKeyFromEnv(
      env({
        SUPABASE_SERVICE_ROLE_KEY: "legacy-server-only-key",
      })
    ),
    "legacy-server-only-key"
  );
});

test("authenticated user resolver validates bearer token against Supabase Auth", async () => {
  let requestedURL = null;
  let requestedHeaders = null;
  const userID = await authenticatedUserIDFromBearer(
    new Request("https://example.test/functions/v1/storekit-subscription-claims", {
      headers: { authorization: "Bearer user-session-token" },
    }),
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    async (url, init) => {
      requestedURL = String(url);
      requestedHeaders = init.headers;
      return Response.json({ id: "00000000-0000-4000-8000-000000000001" });
    }
  );

  assert.equal(requestedURL, "https://project.supabase.co/auth/v1/user");
  assert.equal(requestedHeaders.apikey, "server-only-key");
  assert.equal(requestedHeaders.authorization, "Bearer user-session-token");
  assert.equal(userID, "00000000-0000-4000-8000-000000000001");
});

test("authenticated user resolver treats denied sessions as signed out", async () => {
  const userID = await authenticatedUserIDFromBearer(
    new Request("https://example.test/functions/v1/storekit-subscription-claims", {
      headers: { authorization: "Bearer user-session-token" },
    }),
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    async () => new Response("{}", { status: 401 })
  );

  assert.equal(userID, null);
});

const configuration = {
  supabaseURL: "https://project.supabase.co",
  secretKey: "server-only-key",
};
const ownerID = "00000000-0000-4000-8000-000000000001";
const rpcURL = "https://project.supabase.co/rest/v1/rpc/apply_storekit_subscription_authority";
const notification = {
  provider: "storekit",
  plan: "free",
  status: "inactive",
  storekit_original_transaction_id: "1000000000000100",
  app_store_notification_uuid: "notification-0001",
  app_store_signed_at: "2026-06-12T21:29:00.000Z",
  app_store_status: "expired",
};

function captureRPC(requests, response) {
  return async (url, init) => {
    assert.equal(String(url), rpcURL);
    assert.equal(init.method, "POST");
    assert.equal(init.headers.apikey, "server-only-key");
    assert.equal(init.headers.authorization, "Bearer server-only-key");
    assert.equal(init.headers.prefer, undefined);
    requests.push(JSON.parse(init.body));
    return Response.json(response);
  };
}

test("claim writer sends exactly one atomic RPC with owner and unchanged field-presence semantics", async () => {
  const authorityUpdate = {
    provider: "storekit", plan: "studioSubscription", status: "active",
    storekit_original_transaction_id: "1000000000000100",
    app_store_signed_at: null,
    cloud_retention_deleted_at: null,
  };
  const requests = [];
  const subscription = { owner_id: ownerID, ...authorityUpdate };
  const result = await upsertSubscriptionAuthorityClaim(configuration, ` ${ownerID} `, authorityUpdate,
    captureRPC(requests, { stored: true, mapping_status: "claimed", subscription }));

  assert.deepEqual(requests, [{ authority_update: authorityUpdate, claim_owner_id: ownerID }]);
  assert.equal(Object.hasOwn(requests[0].authority_update, "app_store_auto_renew_status"), false);
  assert.equal(requests[0].authority_update.cloud_retention_deleted_at, null);
  assert.deepEqual(result, { stored: true, mapping_status: "claimed", subscription });
});

test("claim writer passes owner-conflict and stale-claim transaction outcomes through without a REST fallback", async () => {
  for (const status of ["original_transaction_owner_conflict", "stale_transaction_claim"]) {
    const requests = [];
    const expected = { stored: false, mapping_status: status, subscription: { owner_id: ownerID } };
    const result = await upsertSubscriptionAuthorityClaim(configuration, ownerID, notification,
      captureRPC(requests, expected));
    assert.deepEqual(result, expected);
    assert.equal(requests.length, 1);
  }
});

test("notification writer sends ledger and authority fields to one atomic transaction", async () => {
  const requests = [];
  const expected = { stored: true, mapping_status: "updated", subscription: { owner_id: ownerID } };
  const result = await updateMappedSubscriptionAuthority(configuration, notification,
    captureRPC(requests, expected));
  assert.deepEqual(requests, [{ authority_update: notification, claim_owner_id: null }]);
  assert.deepEqual(result, expected);
});

test("notification writer returns unmapped, duplicate and stale outcomes from the same RPC", async () => {
  for (const status of ["unmapped_original_transaction", "duplicate_notification", "stale_notification"]) {
    const requests = [];
    const expected = { stored: false, mapping_status: status };
    const result = await updateMappedSubscriptionAuthority(configuration, notification,
      captureRPC(requests, expected));
    assert.deepEqual(result, expected);
    assert.equal(requests.length, 1);
  }
});

test("missing original transaction never sends a claim or notification mutation", async () => {
  const fetcher = async () => { assert.fail("Missing originals must not invoke the RPC."); };
  const expected = { stored: false, mapping_status: "missing_original_transaction" };
  assert.deepEqual(await updateMappedSubscriptionAuthority(configuration, {}, fetcher), expected);
  assert.deepEqual(await upsertSubscriptionAuthorityClaim(configuration, ownerID,
    { storekit_original_transaction_id: "  " }, fetcher), expected);
});

test("failed atomic RPC stays retryable with the same notification UUID and never falls back to split writes", async () => {
  for (const failureStatus of [404, 503]) {
    const requests = [];
    const fetcher = async (url, init) => {
      assert.equal(String(url), rpcURL);
      assert.equal(init.method, "POST");
      requests.push(JSON.parse(init.body));
      return requests.length === 1
        ? new Response("transaction unavailable", { status: failureStatus })
        : Response.json({ stored: true, mapping_status: "updated", subscription: { owner_id: ownerID } });
    };
    await assert.rejects(updateMappedSubscriptionAuthority(configuration, notification, fetcher),
      new RegExp(`status ${failureStatus}`));
    const retried = await updateMappedSubscriptionAuthority(configuration, notification, fetcher);
    assert.equal(retried.stored, true);
    assert.deepEqual(requests, [
      { authority_update: notification, claim_owner_id: null },
      { authority_update: notification, claim_owner_id: null },
    ]);
  }
});

test("parallel claim and notification requests have no client-side authority-read race", async () => {
  const requests = [];
  let release;
  const barrier = new Promise((resolve) => { release = resolve; });
  const fetcher = async (url, init) => {
    assert.equal(String(url), rpcURL);
    assert.equal(init.method, "POST");
    const payload = JSON.parse(init.body);
    requests.push(payload);
    if (requests.length === 2) release();
    await barrier;
    return Response.json({ stored: true,
      mapping_status: payload.claim_owner_id === null ? "updated" : "claimed",
      subscription: { owner_id: ownerID } });
  };
  const claimUpdate = { ...notification, app_store_notification_uuid: null };
  const results = await Promise.all([
    upsertSubscriptionAuthorityClaim(configuration, ownerID, claimUpdate, fetcher),
    updateMappedSubscriptionAuthority(configuration, notification, fetcher),
  ]);
  assert.deepEqual(results.map((result) => result.mapping_status), ["claimed", "updated"]);
  assert.equal(requests.length, 2);
  assert.deepEqual(requests.find((request) => request.claim_owner_id !== null).authority_update, claimUpdate);
  assert.deepEqual(requests.find((request) => request.claim_owner_id === null).authority_update, notification);
});

test("atomic RPC transport failures do not create a local replay acknowledgment", async () => {
  let calls = 0;
  const fetcher = async (url, init) => {
    assert.equal(String(url), rpcURL);
    assert.equal(JSON.parse(init.body).authority_update.app_store_notification_uuid, notification.app_store_notification_uuid);
    if (++calls === 1) throw new Error("connection interrupted");
    return Response.json({ stored: false, mapping_status: "duplicate_notification" });
  };
  await assert.rejects(updateMappedSubscriptionAuthority(configuration, notification, fetcher), /connection interrupted/);
  assert.equal((await updateMappedSubscriptionAuthority(configuration, notification, fetcher)).mapping_status,
    "duplicate_notification");
  assert.equal(calls, 2);
});

test("invalid or contradictory atomic RPC results fail closed", async () => {
  for (const response of [null, [], {}, { stored: true, mapping_status: "stale_notification" },
    { stored: false, mapping_status: "updated" }, { stored: true, mapping_status: "claimed" }]) {
    await assert.rejects(updateMappedSubscriptionAuthority(configuration, notification,
      async () => Response.json(response)), /invalid transaction result/);
  }
  await assert.rejects(upsertSubscriptionAuthorityClaim(configuration, ownerID, notification,
    async () => Response.json({ stored: true, mapping_status: "updated" })), /invalid transaction result/);
});
