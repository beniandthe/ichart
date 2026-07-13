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

test("claim writer upserts subscription authority by owner", async () => {
  let requestedURL = null;
  let requestedInit = null;
  const requestedMethods = [];
  const result = await upsertSubscriptionAuthorityClaim(
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    "00000000-0000-4000-8000-000000000001",
    {
      provider: "storekit",
      plan: "studioSubscription",
      status: "active",
      storekit_original_transaction_id: "1000000000000100",
      storekit_app_account_token: "00000000-0000-4000-8000-000000000001",
      app_store_signed_at: "2026-06-12T21:29:00.000Z",
    },
    async (url, init) => {
      requestedMethods.push(init.method);
      if (init.method === "GET") {
        return Response.json([]);
      }

      requestedURL = String(url);
      requestedInit = init;
      return Response.json([
        {
          owner_id: "00000000-0000-4000-8000-000000000001",
          provider: "storekit",
        },
      ]);
    }
  );

  assert.equal(
    requestedURL,
    "https://project.supabase.co/rest/v1/subscriptions?on_conflict=owner_id"
  );
  assert.deepEqual(requestedMethods, ["GET", "GET", "POST"]);
  assert.equal(requestedInit.method, "POST");
  assert.equal(requestedInit.headers.authorization, "Bearer server-only-key");
  assert.equal(requestedInit.headers.prefer, "resolution=merge-duplicates,return=representation");
  const body = JSON.parse(requestedInit.body);
  assert.equal(body.owner_id, "00000000-0000-4000-8000-000000000001");
  assert.equal(body.storekit_original_transaction_id, "1000000000000100");
  assert.equal(Object.hasOwn(body, "app_store_auto_renew_status"), false);
  assert.equal(result.stored, true);
  assert.equal(result.mapping_status, "claimed");
});

test("claim writer clears stale renewal state when an owner claims a new active original transaction", async () => {
  let requestedInit = null;
  const requestedMethods = [];
  const result = await upsertSubscriptionAuthorityClaim(
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    "00000000-0000-4000-8000-000000000001",
    {
      provider: "storekit",
      plan: "studioSubscription",
      status: "active",
      storekit_original_transaction_id: "1000000000000200",
      storekit_app_account_token: "00000000-0000-4000-8000-000000000001",
      app_store_signed_at: "2026-06-12T21:29:00.000Z",
    },
    async (url, init) => {
      requestedMethods.push(init.method);
      const requestedURL = String(url);
      if (init.method === "GET" && requestedURL.includes("storekit_original_transaction_id=eq.1000000000000200")) {
        return Response.json([]);
      }
      if (init.method === "GET" && requestedURL.includes("owner_id=eq.00000000-0000-4000-8000-000000000001")) {
        return Response.json([
          {
            owner_id: "00000000-0000-4000-8000-000000000001",
            provider: "storekit",
            status: "active",
            storekit_original_transaction_id: "1000000000000100",
            app_store_auto_renew_status: false,
          },
        ]);
      }

      requestedInit = init;
      return Response.json([
        {
          owner_id: "00000000-0000-4000-8000-000000000001",
          provider: "storekit",
        },
      ]);
    }
  );

  assert.deepEqual(requestedMethods, ["GET", "GET", "POST"]);
  const body = JSON.parse(requestedInit.body);
  assert.equal(body.storekit_original_transaction_id, "1000000000000200");
  assert.equal(body.app_store_auto_renew_status, null);
  assert.equal(result.stored, true);
  assert.equal(result.mapping_status, "claimed");
});

test("claim writer rejects original transactions already mapped to another owner", async () => {
  const result = await upsertSubscriptionAuthorityClaim(
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    "00000000-0000-4000-8000-000000000001",
    {
      provider: "storekit",
      plan: "studioSubscription",
      status: "active",
      storekit_original_transaction_id: "1000000000000100",
      app_store_signed_at: "2026-06-12T21:29:00.000Z",
    },
    async (url, init) => {
      assert.equal(init.method, "GET");
      return Response.json([
        {
          owner_id: "00000000-0000-4000-8000-000000000002",
          provider: "storekit",
        },
      ]);
    }
  );

  assert.equal(result.stored, false);
  assert.equal(result.mapping_status, "original_transaction_owner_conflict");
});

test("claim writer rejects stale transaction claims for the same owner", async () => {
  const result = await upsertSubscriptionAuthorityClaim(
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    "00000000-0000-4000-8000-000000000001",
    {
      provider: "storekit",
      plan: "studioSubscription",
      status: "active",
      storekit_original_transaction_id: "1000000000000100",
      app_store_last_transaction_id: "1000000000000101",
      app_store_signed_at: "2026-06-12T21:29:00.000Z",
    },
    async (url, init) => {
      assert.equal(init.method, "GET");
      return Response.json([
        {
          owner_id: "00000000-0000-4000-8000-000000000001",
          app_store_last_transaction_id: "1000000000000102",
          app_store_signed_at: "2026-06-12T21:30:00.000Z",
        },
      ]);
    }
  );

  assert.equal(result.stored, false);
  assert.equal(result.mapping_status, "stale_transaction_claim");
});

test("notification writer patches only previously claimed original transactions", async () => {
  let requestedURL = null;
  let requestedInit = null;
  const requestedMethods = [];
  const result = await updateMappedSubscriptionAuthority(
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    {
      provider: "storekit",
      plan: "free",
      status: "inactive",
      storekit_original_transaction_id: "1000000000000100",
      app_store_notification_uuid: "notification-0001",
      app_store_signed_at: "2026-06-12T21:29:00.000Z",
      app_store_status: "expired",
    },
    async (url, init) => {
      requestedMethods.push(init.method);
      if (init.method === "GET") {
        return Response.json([
          {
            owner_id: "00000000-0000-4000-8000-000000000001",
            app_store_signed_at: "2026-06-12T21:28:00.000Z",
          },
        ]);
      }
      if (String(url).includes("/rest/v1/app_store_notification_events")) {
        return Response.json([
          {
            notification_uuid: "notification-0001",
          },
        ]);
      }

      requestedURL = String(url);
      requestedInit = init;
      return Response.json([
        {
          owner_id: "00000000-0000-4000-8000-000000000001",
          app_store_status: "expired",
        },
      ]);
    }
  );

  assert.equal(
    requestedURL,
    "https://project.supabase.co/rest/v1/subscriptions?storekit_original_transaction_id=eq.1000000000000100"
  );
  assert.deepEqual(requestedMethods, ["GET", "POST", "PATCH"]);
  assert.equal(requestedInit.method, "PATCH");
  assert.equal(requestedInit.headers.prefer, "return=representation");
  assert.equal(JSON.parse(requestedInit.body).app_store_status, "expired");
  assert.equal(result.stored, true);
  assert.equal(result.mapping_status, "updated");
});

test("notification writer accepts unmapped original transactions without assigning an owner", async () => {
  const result = await updateMappedSubscriptionAuthority(
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    {
      provider: "storekit",
      plan: "studioSubscription",
      status: "active",
      storekit_original_transaction_id: "1000000000009999",
    },
    async () => Response.json([])
  );

  assert.equal(result.stored, false);
  assert.equal(result.mapping_status, "unmapped_original_transaction");
});

test("notification writer ignores duplicate notification UUIDs", async () => {
  const result = await updateMappedSubscriptionAuthority(
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    {
      provider: "storekit",
      plan: "free",
      status: "inactive",
      storekit_original_transaction_id: "1000000000000100",
      app_store_notification_uuid: "notification-0001",
      app_store_signed_at: "2026-06-12T21:29:00.000Z",
      app_store_status: "expired",
    },
    async (url, init) => {
      if (init.method === "GET") {
        return Response.json([
          {
            owner_id: "00000000-0000-4000-8000-000000000001",
            app_store_signed_at: "2026-06-12T21:28:00.000Z",
          },
        ]);
      }
      if (String(url).includes("/rest/v1/app_store_notification_events")) {
        return Response.json([]);
      }

      throw new Error("duplicate notification should not patch subscription authority");
    }
  );

  assert.equal(result.stored, false);
  assert.equal(result.mapping_status, "duplicate_notification");
});

test("notification writer rejects stale notifications", async () => {
  const result = await updateMappedSubscriptionAuthority(
    {
      supabaseURL: "https://project.supabase.co",
      secretKey: "server-only-key",
    },
    {
      provider: "storekit",
      plan: "studioSubscription",
      status: "active",
      storekit_original_transaction_id: "1000000000000100",
      app_store_last_transaction_id: "1000000000000101",
      app_store_notification_uuid: "notification-0002",
      app_store_signed_at: "2026-06-12T21:29:00.000Z",
      app_store_status: "active",
    },
    async (url, init) => {
      if (init.method === "GET") {
        return Response.json([
          {
            owner_id: "00000000-0000-4000-8000-000000000001",
            app_store_last_transaction_id: "1000000000000102",
            app_store_signed_at: "2026-06-12T21:30:00.000Z",
          },
        ]);
      }
      if (String(url).includes("/rest/v1/app_store_notification_events")) {
        return Response.json([
          {
            notification_uuid: "notification-0002",
          },
        ]);
      }

      throw new Error("stale notification should not patch subscription authority");
    }
  );

  assert.equal(result.stored, false);
  assert.equal(result.mapping_status, "stale_notification");
});
