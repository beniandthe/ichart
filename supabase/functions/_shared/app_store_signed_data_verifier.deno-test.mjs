import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { sign, X509Certificate } from "node:crypto";
import { KJUR } from "npm:jsrsasign@11.1.5";
import { createAppStoreSignedDataVerifiers, verifyCompactAppStoreJWS } from "./app_store_signed_data_verifier.mjs";
import fixture from "./testdata/app_store_signed_data_verifier.synthetic.json" with { type: "json" };

// These public test keys and certificates were independently encoded by OpenSSL.
// They are trusted only by the local configuration below, never by production.
const roots = [Buffer.from(fixture.certificates.root, "base64")];
const config = {
  bundleID: "com.ichart.synthetic-offline-test",
  environment: "Sandbox",
  appAppleID: 123456789,
  enableOnlineChecks: false,
};

function signedTransaction(overrides = {}, { leaf = "leaf", intermediate = "intermediate" } = {}) {
  const header = { alg: "ES256", x5c: [fixture.certificates[leaf],
    fixture.certificates[intermediate], fixture.certificates.root] };
  const payload = { bundleId: config.bundleID, environment: config.environment,
    signedDate: fixture.signedDate, transactionId: "synthetic-transaction", ...overrides };
  const encoded = [header, payload].map(value => Buffer.from(JSON.stringify(value)).toString("base64url"));
  const signature = sign("sha256", Buffer.from(encoded.join(".")),
    { key: fixture.leafPrivateKeyPEM, dsaEncoding: "ieee-p1363" });
  return [...encoded, signature.toString("base64url")].join(".");
}

function replaceHeader(token, edit) {
  const parts = token.split(".");
  const header = JSON.parse(Buffer.from(parts[0], "base64url"));
  edit(header);
  parts[0] = Buffer.from(JSON.stringify(header)).toString("base64url");
  return parts.join(".");
}

function tamperedCertificateToken() {
  return replaceHeader(signedTransaction(), header => {
    const der = Buffer.from(header.x5c[0], "base64");
    der[der.length - 1] ^= 1;
    header.x5c[0] = der.toString("base64");
  });
}

Deno.test("real patched verifier accepts an independently signed trusted synthetic chain", async () => {
  const payload = await verifyCompactAppStoreJWS(signedTransaction(), roots, config, "transaction");
  assert.equal(payload.transactionId, "synthetic-transaction");
  assert.equal(payload.bundleId, config.bundleID);
});

Deno.test("public transaction entry composes the real pinned Apple SDK and patched verifier offline", async () => {
  const verifier = createAppStoreSignedDataVerifiers({
    APP_STORE_BUNDLE_ID: config.bundleID,
    APP_STORE_ENVIRONMENT: config.environment,
    APP_STORE_ROOT_CERTIFICATES_PEM: fixture.rootPEM,
    APP_STORE_ENABLE_ONLINE_CHECKS: "false",
  });
  const payload = await verifier.verifyAndDecodeTransaction(signedTransaction());
  assert.equal(payload.transactionId, "synthetic-transaction");
  await assert.rejects(() => verifier.verifyAndDecodeTransaction(signedTransaction({ bundleId: "wrong.bundle" })));
});

Deno.test("patched X509 and KJUR fallback verifies chains when platform certificate key support throws", async () => {
  const descriptor = Object.getOwnPropertyDescriptor(X509Certificate.prototype, "publicKey");
  assert.equal(typeof descriptor?.get, "function");
  const OriginalSignature = KJUR.crypto.Signature;
  let fallbackVerifications = 0;
  // Emulate the unsupported issuer-key path handled by the shipped Edge fallback.
  // Leaf keys remain native so the independent JWS signature is still verified.
  Object.defineProperty(X509Certificate.prototype, "publicKey", {
    ...descriptor,
    get() { return this.ca ? {} : descriptor.get.call(this); },
  });
  KJUR.crypto.Signature = function (...args) {
    const signature = new OriginalSignature(...args);
    const verify = signature.verify;
    signature.verify = function (...values) {
      fallbackVerifications++;
      return verify.apply(this, values);
    };
    return signature;
  };
  try {
    const payload = await verifyCompactAppStoreJWS(signedTransaction(), roots, config, "transaction");
    assert.equal(payload.transactionId, "synthetic-transaction");
    assert.equal(fallbackVerifications >= 2, true);
    await assert.rejects(() => verifyCompactAppStoreJWS(tamperedCertificateToken(),
      roots, config, "transaction"), { status: 18 });
    await assert.rejects(() => verifyCompactAppStoreJWS(signedTransaction(),
      [Buffer.from(fixture.otherRootPEM)], config, "transaction"), { status: 37 });
  } finally {
    KJUR.crypto.Signature = OriginalSignature;
    Object.defineProperty(X509Certificate.prototype, "publicKey", descriptor);
  }
});

for (const [name, token, status] of [
  ["wrong bundle", () => signedTransaction({ bundleId: "wrong.bundle" }), 25],
  ["wrong environment", () => signedTransaction({ environment: "Production" }), 26],
  ["certificate date outside validity", () => signedTransaction({ signedDate: fixture.expiredSignedDate }), 22],
  ["leaf without the Apple-specific certificate OID", () => signedTransaction({}, { leaf: "leaf-no-oid" }), 20],
  ["intermediate without CA authority", () => signedTransaction({}, { intermediate: "intermediate-no-ca" }), 19],
  ["malformed DER", () => replaceHeader(signedTransaction(), header => { header.x5c[0] = "YmFk"; }), 16],
  ["incomplete certificate chain", () => replaceHeader(signedTransaction(), header => { header.x5c.pop(); }), 15],
  ["unsupported JWS algorithm", () => replaceHeader(signedTransaction(), header => { header.alg = "RS256"; }), 23],
]) {
  Deno.test(`patched verifier rejects ${name}`, async () => {
    await assert.rejects(() => verifyCompactAppStoreJWS(token(), roots, config, "transaction"), { status });
  });
}

Deno.test("patched verifier rejects a valid chain rooted outside its configured trust store", async () => {
  await assert.rejects(() => verifyCompactAppStoreJWS(signedTransaction(),
    [Buffer.from(fixture.otherRootPEM)], config, "transaction"), { status: 37 });
});

Deno.test("patched verifier rejects a tampered certificate signature", async () => {
  await assert.rejects(() => verifyCompactAppStoreJWS(tamperedCertificateToken(), roots, config, "transaction"),
    { status: 18 });
});

Deno.test("patched verifier rejects a tampered JWS signature", async () => {
  const parts = signedTransaction().split(".");
  const signature = Buffer.from(parts[2], "base64url");
  signature[0] ^= 1;
  parts[2] = signature.toString("base64url");
  await assert.rejects(() => verifyCompactAppStoreJWS(parts.join("."), roots, config, "transaction"), { status: 24 });
});
