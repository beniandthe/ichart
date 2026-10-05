import assert from "node:assert/strict";
import test from "node:test";

import {
  createRecognitionStudyConsentDependencies,
  recognitionStudyConsentStoreConfigurationFromEnv,
} from "./recognition_study_consent_store.mjs";

const baseEnv = {
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_example",
  SUPABASE_URL: "https://example.supabase.co",
};
const bearerRequest = new Request("https://example.test/consent", {
  headers: { authorization: "Bearer user-session" },
});

test("store requires only public Supabase client configuration", () => {
  assert.equal(recognitionStudyConsentStoreConfigurationFromEnv({}), null);
  assert.equal(
    recognitionStudyConsentStoreConfigurationFromEnv({
      SUPABASE_URL: baseEnv.SUPABASE_URL,
    }),
    null,
  );
  assert.deepEqual(recognitionStudyConsentStoreConfigurationFromEnv(baseEnv), {
    publicKey: "sb_publishable_example",
    supabaseURL: "https://example.supabase.co",
  });
  assert.deepEqual(
    recognitionStudyConsentStoreConfigurationFromEnv({
      SUPABASE_ANON_KEY: "legacy-public-key",
      SUPABASE_URL: "https://example.supabase.co/",
    }),
    { publicKey: "legacy-public-key", supabaseURL: "https://example.supabase.co" },
  );
});

test("every RPC forwards the user bearer token instead of a service credential", async () => {
  const calls = [];
  const ownerID = "10000000-0000-4000-8000-000000000001";
  const fetcher = async (url, init) => {
    calls.push({ init, url: String(url) });
    if (String(url).endsWith("/auth/v1/user")) {
      return Response.json({ id: ownerID });
    }
    return Response.json({
      consent: null,
      currentPolicy: null,
      replayed: false,
      schemaVersion: "recognition-study-consent-store-response-v1",
      status: "not-accepted",
    });
  };
  const dependencies = createRecognitionStudyConsentDependencies(baseEnv, { fetch: fetcher });
  assert.equal(await dependencies.authenticatedUserID(bearerRequest), ownerID);
  await dependencies.readConsentStatus(bearerRequest);
  await dependencies.acceptConsent(bearerRequest, {
    clientRequestID: "10000000-0000-4000-8000-000000000002",
    explicitRawStrokeDonationAuthorization: true,
    presentationID: "pilot-v1",
    presentationSHA256: "ab".repeat(32),
  });
  await dependencies.withdrawConsent(bearerRequest, {
    clientRequestID: "10000000-0000-4000-8000-000000000003",
    consentRecordID: "10000000-0000-4000-8000-000000000004",
  });

  const rpcCalls = calls.filter((call) => call.url.includes("/rpc/"));
  assert.equal(rpcCalls.length, 3);
  assert.deepEqual(
    rpcCalls.map((call) => call.url.split("/rpc/")[1]),
    [
      "recognition_study_consent_status",
      "accept_recognition_study_consent",
      "withdraw_recognition_study_consent_v2",
    ],
  );
  for (const call of rpcCalls) {
    assert.equal(call.init.headers.apikey, "sb_publishable_example");
    assert.equal(call.init.headers.authorization, "Bearer user-session");
    assert.equal(JSON.stringify(call.init).includes("service"), false);
  }
});

test("store stays disabled without configuration or a bearer request", async () => {
  assert.deepEqual(createRecognitionStudyConsentDependencies({}), {});
  const dependencies = createRecognitionStudyConsentDependencies(baseEnv, {
    fetch: async () => Response.json({}),
  });
  await assert.rejects(
    dependencies.readConsentStatus(new Request("https://example.test/consent")),
    /unauthorized/,
  );
});

test("database errors map to narrow consent dispositions", async () => {
  for (const [message, disposition] of [
    ["reviewed consent presentation is unavailable", "policy_unavailable"],
    ["consent request id was already used with different bytes", "conflict"],
    ["consent record was not found", "not_found"],
  ]) {
    const dependencies = createRecognitionStudyConsentDependencies(baseEnv, {
      fetch: async () => Response.json({ message }, { status: 400 }),
    });
    await assert.rejects(
      dependencies.readConsentStatus(bearerRequest),
      new RegExp(disposition),
    );
  }
});
