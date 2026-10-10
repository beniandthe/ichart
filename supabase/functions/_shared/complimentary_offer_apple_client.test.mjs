import assert from "node:assert/strict";
import test from "node:test";
import { verifyWithAppStoreEnvironmentFallback } from "./app_store_environment_fallback.mjs";
import {
  ComplimentaryAppleSnapshotError,
  createFreshComplimentaryAppleDependencies,
  fetchAndVerifyFreshComplimentaryAppleSnapshot,
} from "./complimentary_offer_apple_client.mjs";

const ownerID = "735087db-a170-4d36-8ce0-239eb12a1bd9";
const otherOwnerID = "71e63d85-08b7-491e-946a-74ea37cdb1fa";
const bundleID = "com.ichart.app";
const monthlyID = "com.ichart.app.pro.monthly";
const annualID = "com.ichart.app.pro.annual";

function fixture() {
  const payloads = {
    current: {
      bundleId: bundleID,
      environment: "Production",
      productId: annualID,
      appAccountToken: ownerID,
      inAppOwnershipType: "PURCHASED",
      originalTransactionId: "100",
      transactionId: "102",
      subscriptionGroupIdentifier: "200",
      purchaseDate: 1_790_000_000_000,
      expiresDate: 1_820_000_000_000,
    },
    historical: {
      bundleId: bundleID,
      environment: "Production",
      productId: monthlyID,
      appAccountToken: ownerID,
      inAppOwnershipType: "PURCHASED",
      originalTransactionId: "100",
      transactionId: "101",
      purchaseDate: 1_788_000_000_000,
      expiresDate: 1_789_000_000_000,
      revocationDate: 1_788_500_000_000,
    },
    renewal: {
      environment: "Production",
      productId: annualID,
      autoRenewProductId: annualID,
      originalTransactionId: "100",
      appAccountToken: ownerID,
    },
  };
  const statusResponse = {
    bundleId: bundleID,
    environment: "Production",
    data: [{ subscriptionGroupIdentifier: "200", lastTransactions: [{
      status: 1,
      originalTransactionId: "100",
      signedTransactionInfo: "current",
      signedRenewalInfo: "renewal",
    }] }],
  };
  const pages = [{
    bundleId: bundleID,
    environment: "Production",
    hasMore: false,
    revision: "revision-1",
    signedTransactions: ["historical", "current"],
  }];
  const calls = [];
  const verifications = [];
  const verifiers = {
    async verifyAndDecodeTransaction(jws) {
      verifications.push(["transaction", jws]);
      assert.ok(payloads[jws], "unknown mock transaction");
      return structuredClone(payloads[jws]);
    },
    async verifyAndDecodeRenewalInfo(jws) {
      verifications.push(["renewal", jws]);
      assert.ok(payloads[jws], "unknown mock renewal");
      return structuredClone(payloads[jws]);
    },
  };
  const client = {
    async getAllSubscriptionStatuses(id) {
      calls.push(["status", id]);
      return structuredClone(statusResponse);
    },
    async getTransactionHistory(id, revision, request, version) {
      calls.push(["history", id, revision, request, version]);
      const index = calls.filter((call) => call[0] === "history").length - 1;
      return structuredClone(pages[index] ?? pages.at(-1));
    },
  };
  const input = { ownerID, originalTransactionID: "100", environment: "production" };
  const options = { bundleID, environment: "production", client, verifiers };
  return { payloads, statusResponse, pages, calls, verifications, client, verifiers, input, options };
}

async function rejectsSnapshot(f) {
  await assert.rejects(
    fetchAndVerifyFreshComplimentaryAppleSnapshot(f.input, f.options),
    (error) => error instanceof ComplimentaryAppleSnapshotError
      && error.message === "apple_snapshot_unavailable"
      && error.cause === undefined,
  );
}

test("fresh snapshot paginates unfiltered V2 history, including revoked records", async () => {
  const f = fixture();
  f.pages[0].hasMore = true;
  f.pages[0].signedTransactions = ["historical"];
  f.pages.push({ ...f.pages[0], hasMore: false, revision: "revision-2", signedTransactions: ["current"] });
  const result = await fetchAndVerifyFreshComplimentaryAppleSnapshot(f.input, f.options);
  assert.equal(result.environment, "production");
  assert.deepEqual(result.history.map((item) => item.transactionId), ["101", "102"]);
  assert.equal(result.history[0].revocationDate, f.payloads.historical.revocationDate);
  assert.deepEqual(result.statuses, [{ status: 1, transaction: f.payloads.current, renewal: f.payloads.renewal }]);
  assert.deepEqual(f.calls, [
    ["status", "100"],
    ["history", "100", null, {}, "v2"],
    ["history", "100", "revision-1", {}, "v2"],
  ]);
  assert.deepEqual(f.verifications, [
    ["transaction", "current"], ["renewal", "renewal"],
    ["transaction", "historical"], ["transaction", "current"],
  ]);
});

test("every unrelated product payload is verified before being omitted", async () => {
  const f = fixture();
  f.payloads.unrelated = {
    bundleId: bundleID, environment: "Production", productId: "com.ichart.app.oldtip",
    transactionId: "901", originalTransactionId: "900",
  };
  f.payloads.unrelatedRenewal = {
    environment: "Production", productId: "com.ichart.app.oldtip", originalTransactionId: "900",
  };
  f.pages[0].signedTransactions.push("unrelated");
  f.statusResponse.data.push({ lastTransactions: [{ status: 2, originalTransactionId: "900",
    signedTransactionInfo: "unrelated", signedRenewalInfo: "unrelatedRenewal" }] });
  const result = await fetchAndVerifyFreshComplimentaryAppleSnapshot(f.input, f.options);
  assert.equal(result.history.length, 2);
  assert.equal(result.statuses.length, 1);
  assert.equal(f.verifications.filter((call) => call[1] === "unrelated").length, 2);
  assert.ok(f.verifications.some((call) => call[1] === "unrelatedRenewal"));
});

test("UUID comparison is case-insensitive without rebinding ownership", async () => {
  const f = fixture();
  f.input.ownerID = ownerID.toUpperCase();
  f.payloads.current.appAccountToken = ownerID.toUpperCase();
  f.payloads.renewal.appAccountToken = ownerID.toUpperCase();
  const result = await fetchAndVerifyFreshComplimentaryAppleSnapshot(f.input, f.options);
  assert.equal(result.history.length, 2);
});

test("invalid identity, transaction seed, environment, and dependencies fail before Apple calls", async (t) => {
  const mutations = {
    "non UUID owner": (f) => { f.input.ownerID = "owner-from-client"; },
    "missing owner": (f) => { delete f.input.ownerID; },
    "path instead of transaction ID": (f) => { f.input.originalTransactionID = "100/elsewhere"; },
    "missing seed": (f) => { delete f.input.originalTransactionID; },
    "cross environment": (f) => { f.input.environment = "sandbox"; },
    "unknown environment": (f) => { f.input.environment = "Xcode"; },
    "missing verifier": (f) => { delete f.options.verifiers; },
    "invalid page limit": (f) => { f.options.maxPages = 51; },
  };
  for (const [name, mutate] of Object.entries(mutations)) {
    await t.test(name, async () => {
      const f = fixture();
      mutate(f);
      await rejectsSnapshot(f);
      assert.equal(f.calls.length, 0);
    });
  }
});

test("status and history envelopes must match the configured bundle and environment", async (t) => {
  for (const location of ["status", "history"]) {
    for (const field of ["bundleId", "environment"]) {
      await t.test(`${location} ${field}`, async () => {
        const f = fixture();
        (location === "status" ? f.statusResponse : f.pages[0])[field] = "unrelated";
        await rejectsSnapshot(f);
      });
    }
  }
});

test("every related Pro transaction must be in scope and purchased by this account", async (t) => {
  const mutations = {
    "other bundle": (payload) => { payload.bundleId = "com.other.app"; },
    "other environment": (payload) => { payload.environment = "Sandbox"; },
    "missing token": (payload) => { delete payload.appAccountToken; },
    "other owner's token": (payload) => { payload.appAccountToken = otherOwnerID; },
    "non UUID token": (payload) => { payload.appAccountToken = "owner"; },
    "family shared": (payload) => { payload.inAppOwnershipType = "FAMILY_SHARED"; },
    "unknown ownership": (payload) => { delete payload.inAppOwnershipType; },
    "malformed transaction": (payload) => { payload.transactionId = 101; },
  };
  for (const location of ["current", "historical"]) {
    for (const [name, mutate] of Object.entries(mutations)) {
      await t.test(`${location} ${name}`, async () => {
        const f = fixture();
        mutate(f.payloads[location]);
        await rejectsSnapshot(f);
      });
    }
  }
});

test("renewal payload must pair with the same original transaction, product, scope, and owner", async (t) => {
  const mutations = {
    "other original": (payload) => { payload.originalTransactionId = "999"; },
    "other product": (payload) => { payload.productId = monthlyID; },
    "other environment": (payload) => { payload.environment = "Sandbox"; },
    "other owner": (payload) => { payload.appAccountToken = otherOwnerID; },
    "other bundle if present": (payload) => { payload.bundleId = "com.other.app"; },
  };
  for (const [name, mutate] of Object.entries(mutations)) {
    await t.test(name, async () => {
      const f = fixture();
      mutate(f.payloads.renewal);
      await rejectsSnapshot(f);
    });
  }
  const f = fixture();
  delete f.payloads.renewal.appAccountToken;
  assert.equal((await fetchAndVerifyFreshComplimentaryAppleSnapshot(f.input, f.options)).statuses.length, 1);
});

test("outer status original transaction and subscription group cannot contradict signed payload", async (t) => {
  await t.test("outer original", async () => {
    const f = fixture();
    f.statusResponse.data[0].lastTransactions[0].originalTransactionId = "999";
    await rejectsSnapshot(f);
  });
  await t.test("group", async () => {
    const f = fixture();
    f.statusResponse.data[0].subscriptionGroupIdentifier = "999";
    await rejectsSnapshot(f);
  });
});

test("unknown or incomplete status structures fail closed", async (t) => {
  for (const mutation of [
    (f) => { delete f.statusResponse.data; },
    (f) => { delete f.statusResponse.data[0].lastTransactions; },
    (f) => { f.statusResponse.data[0].lastTransactions[0].status = 6; },
    (f) => { f.statusResponse.data[0].lastTransactions[0].status = "1"; },
    (f) => { delete f.statusResponse.data[0].lastTransactions[0].signedRenewalInfo; },
    (f) => { f.statusResponse.data = []; },
  ]) {
    await t.test(async () => { const f = fixture(); mutation(f); await rejectsSnapshot(f); });
  }
});

test("incomplete, looping, oversized, or malformed history fails closed", async (t) => {
  const mutations = {
    "page cap": (f) => { f.options.maxPages = 1; f.pages[0].hasMore = true; },
    "repeated revision": (f) => { f.pages[0].hasMore = true; },
    "missing revision": (f) => { f.pages[0].hasMore = true; delete f.pages[0].revision; },
    "empty unfinished page": (f) => { f.pages[0].hasMore = true; f.pages[0].signedTransactions = []; },
    "missing hasMore": (f) => { delete f.pages[0].hasMore; },
    "missing transactions": (f) => { delete f.pages[0].signedTransactions; },
    "oversized page": (f) => { f.pages[0].signedTransactions = Array(21).fill("current"); },
    "unsigned item": (f) => { f.pages[0].signedTransactions.push(42); },
    "empty history": (f) => { f.pages[0].signedTransactions = []; },
  };
  for (const [name, mutate] of Object.entries(mutations)) {
    await t.test(name, async () => { const f = fixture(); mutate(f); await rejectsSnapshot(f); });
  }
});

test("fresh responses must contain the requested owned original transaction", async () => {
  const f = fixture();
  f.input.originalTransactionID = "999";
  await rejectsSnapshot(f);
});

test("SDK and signature failures expose no underlying body, credential, or JWS", async (t) => {
  const sensitiveError = new Error("private-key-and-signed-transaction-contents");
  for (const location of ["status", "history", "transaction", "renewal"]) {
    await t.test(location, async () => {
      const f = fixture();
      const failure = async () => { throw sensitiveError; };
      if (location === "status") f.client.getAllSubscriptionStatuses = failure;
      if (location === "history") f.client.getTransactionHistory = failure;
      if (location === "transaction") f.verifiers.verifyAndDecodeTransaction = failure;
      if (location === "renewal") f.verifiers.verifyAndDecodeRenewalInfo = failure;
      await rejectsSnapshot(f);
    });
  }
});

test("runtime factory disables itself without every required server-only configuration value", () => {
  const complete = {
    APP_STORE_BUNDLE_ID: bundleID,
    APP_STORE_ENVIRONMENT: "Production",
    APP_STORE_SUBSCRIPTION_KEY_P8: "test-only-placeholder",
    APP_STORE_SUBSCRIPTION_KEY_ID: "TESTKEYID",
    APP_STORE_ISSUER_ID: ownerID,
  };
  for (const key of Object.keys(complete)) {
    const env = { ...complete };
    delete env[key];
    assert.deepEqual(createFreshComplimentaryAppleDependencies(env), {});
  }
  assert.deepEqual(createFreshComplimentaryAppleDependencies({ ...complete, APP_STORE_ENVIRONMENT: "Xcode" }), {});
});

test("runtime factory supports env.get, dependency injection, and fresh calls on every refresh", async () => {
  const f = fixture();
  const envValues = {
    APP_STORE_BUNDLE_ID: bundleID,
    APP_STORE_ENVIRONMENT: "Production",
    APP_STORE_SUBSCRIPTION_KEY_P8: "test-only-placeholder",
    APP_STORE_SUBSCRIPTION_KEY_ID: "TESTKEYID",
    APP_STORE_ISSUER_ID: ownerID,
  };
  const deps = createFreshComplimentaryAppleDependencies({ get: (key) => envValues[key] }, {
    client: f.client,
    verifiers: f.verifiers,
  });
  assert.deepEqual(Object.keys(deps), ["fetchFreshAppleSnapshot"]);
  await deps.fetchFreshAppleSnapshot(f.input);
  await deps.fetchFreshAppleSnapshot(f.input);
  assert.equal(f.calls.filter((call) => call[0] === "status").length, 2);
  assert.equal(f.calls.filter((call) => call[0] === "history").length, 2);
});

test("Sandbox requests stay in Sandbox rather than falling back to Production", async () => {
  const f = fixture();
  f.input.environment = "sandbox";
  f.options.environment = "Sandbox";
  f.statusResponse.environment = "Sandbox";
  f.pages[0].environment = "Sandbox";
  for (const payload of Object.values(f.payloads)) payload.environment = "Sandbox";
  assert.equal((await fetchAndVerifyFreshComplimentaryAppleSnapshot(f.input, f.options)).environment, "sandbox");
  f.payloads.historical.environment = "Production";
  await rejectsSnapshot(f);
});

test("production global verifier with Sandbox campaign override targets only Sandbox API evidence", async () => {
  const f = fixture();
  f.input.environment = "sandbox";
  f.statusResponse.environment = "Sandbox";
  f.pages[0].environment = "Sandbox";
  for (const payload of Object.values(f.payloads)) payload.environment = "Sandbox";
  const env = { APP_STORE_BUNDLE_ID: bundleID, APP_STORE_ENVIRONMENT: "Production",
    APP_STORE_SUBSCRIPTION_KEY_P8: "synthetic", APP_STORE_SUBSCRIPTION_KEY_ID: "TESTKEYID", APP_STORE_ISSUER_ID: ownerID };
  let fallbackCalls = 0;
  const withExistingFallback = (method) => (jws) => verifyWithAppStoreEnvironmentFallback({
    primaryVerification: async () => { throw { status: 4 }; },
    sandboxVerification: async () => { fallbackCalls += 1; return f.verifiers[method](jws); },
  });
  const deps = createFreshComplimentaryAppleDependencies(env, { client: f.client, environment: "sandbox", verifiers: {
    verifyAndDecodeTransaction: withExistingFallback("verifyAndDecodeTransaction"),
    verifyAndDecodeRenewalInfo: withExistingFallback("verifyAndDecodeRenewalInfo"),
  } });
  assert.equal((await deps.fetchFreshAppleSnapshot(f.input)).environment, "sandbox");
  assert.equal(fallbackCalls, 4);
  assert.equal(env.APP_STORE_ENVIRONMENT, "Production");
  f.statusResponse.environment = "Production";
  await assert.rejects(() => deps.fetchFreshAppleSnapshot(f.input), /apple_snapshot_unavailable/);
  assert.deepEqual(createFreshComplimentaryAppleDependencies(env, { environment: "invalid" }), {});
});
