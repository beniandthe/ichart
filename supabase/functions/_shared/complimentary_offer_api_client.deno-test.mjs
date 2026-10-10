import { generateKeyPairSync } from "node:crypto";
import { Buffer } from "node:buffer";
import assert from "node:assert/strict";
import { AppStoreServerAPIClient } from "npm:@apple/app-store-server-library@3.1.0";
import { createFreshComplimentaryAppleDependencies } from "./complimentary_offer_apple_client.mjs";

// Deno-only composition regression; no real keys, owner, transaction or network.
// The real pinned SDK builds the request. Only its transport is intercepted in
// this test process, and the original prototype is restored even on failure.
Deno.test("default complimentary client builds verified ES256 Sandbox status and history requests in Deno", async () => {
  const pair = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const privateKeyPEM = pair.privateKey.export({ format: "pem", type: "pkcs8" }).toString();
  const publicKey = await crypto.subtle.importKey("spki", pair.publicKey.export({ format: "der", type: "spki" }),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const owner = "00000000-0000-4000-8000-000000000001";
  const originalFetch = AppStoreServerAPIClient.prototype.makeFetchRequest;
  let interceptedRequests = 0;
  let validatedRequests = 0;
  AppStoreServerAPIClient.prototype.makeFetchRequest = async function (path, parameters, method, body, headers) {
    interceptedRequests++;
    assert.equal(this.urlBase, AppStoreServerAPIClient.SANDBOX_URL);
    assert.equal(path, interceptedRequests === 1 ? "/inApps/v1/subscriptions/100" : "/inApps/v2/history/100");
    assert.equal(method, "GET");
    const parts = headers.Authorization.replace(/^Bearer /, "").split(".");
    assert.equal(parts.length, 3);
    const header = JSON.parse(Buffer.from(parts[0], "base64url").toString());
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString());
    assert.deepEqual(header, { alg: "ES256", kid: "ABCDEFGHIJ", typ: "JWT" });
    assert.equal(payload.bid, "com.ichart.app");
    assert.equal(payload.iss, owner);
    assert.equal(payload.aud, "appstoreconnect-v1");
    assert.equal(Number.isSafeInteger(payload.iat), true);
    assert.equal(Math.abs(payload.iat - Math.floor(Date.now() / 1000)) < 30, true);
    assert.equal(payload.exp - payload.iat, 300);
    assert.equal(Buffer.from(parts[2], "base64url").length, 64);
    assert.equal(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey,
      Buffer.from(parts[2], "base64url"), Buffer.from(parts[0] + "." + parts[1])), true);
    validatedRequests++;
    const response = interceptedRequests === 1
      ? { environment: "Sandbox", bundleId: "com.ichart.app", appAppleId: 123456789, data: [] }
      : { environment: "Sandbox", bundleId: "com.ichart.app", appAppleId: 123456789,
        revision: "synthetic-revision", hasMore: false, signedTransactions: [] };
    return new Response(JSON.stringify(response), { status: 200 });
  };
  try {
    const dependencies = createFreshComplimentaryAppleDependencies({
      APP_STORE_BUNDLE_ID: "com.ichart.app", APP_STORE_ENVIRONMENT: "Sandbox",
      APP_STORE_SUBSCRIPTION_KEY_P8: privateKeyPEM, APP_STORE_SUBSCRIPTION_KEY_ID: "ABCDEFGHIJ", APP_STORE_ISSUER_ID: owner,
    }, { verifiers: { verifyAndDecodeTransaction: async () => ({}), verifyAndDecodeRenewalInfo: async () => ({}) } });
    await assert.rejects(() => dependencies.fetchFreshAppleSnapshot({
      ownerID: owner, originalTransactionID: "100", environment: "sandbox",
    }));
    // Empty mocked history is deliberately rejected, not treated as eligibility.
    assert.equal(interceptedRequests, 2);
    assert.equal(validatedRequests, 2);
  } finally {
    AppStoreServerAPIClient.prototype.makeFetchRequest = originalFetch;
  }
});
