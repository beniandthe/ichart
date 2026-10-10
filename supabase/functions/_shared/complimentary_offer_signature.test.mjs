import test from "node:test";
import assert from "node:assert/strict";
import { createPrivateKey, generateKeyPairSync, verify } from "node:crypto";
import { Buffer } from "node:buffer";
import {
  createLegacyPromotionalOfferSigner,
  isP256PrivateKey,
  promotionalOfferSignaturePayload,
} from "./complimentary_offer_signature.mjs";

const bundleID = "com.ichart.app";
const keyID = "ABCDEFGHIJ";
const fields = {
  productID: "com.ichart.app.pro.monthly",
  offerID: "ichart_complimentary_monthly_1m_v1",
  appAccountToken: "ABCDEF12-3456-4789-8ABC-DEF123456789",
  nonce: "FEDCBA98-7654-4321-8FED-CBA987654321",
  timestamp: 1_791_542_400_000,
};

const p256 = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const p256PEM = p256.privateKey.export({ format: "pem", type: "pkcs8" });
const signer = () => createLegacyPromotionalOfferSigner({ bundleID, keyID, privateKeyPEM: p256PEM });

// Generated and verified as P-521 with Node solely for this test. Never used by a service.
// Deno 2.1.14 cannot generate this curve and may also reject it while importing PKCS#8.
const syntheticP521PEM = `-----BEGIN PRIVATE KEY-----
MIHuAgEAMBAGByqGSM49AgEGBSuBBAAjBIHWMIHTAgEBBEIAxj6+ueBY8iD958bh
qo4EYKE9o3ItwSY5iKdUzATJKot7XkA5w/Az2QxYqcjovosy1j63Ycb/rWu1BL3r
IbpKRuuhgYkDgYYABAEwfc9iU7aGeIyY87mPYF3OIZJzw+tUgVElWfZ2bQIGoLXW
AeHgAL1MerL2ubcjrUZh5C8y+fam+P9p4vHMyrjzxgBgc6s+ZChyfJbOrPpwvjWL
6zKNr6WBGRjoqkH2zRHmW61OGs3lEGbLUvPbEIRfZfEHfHBgFPIOl7MBPEr+D/VN
/A==
-----END PRIVATE KEY-----
`;

for (const namedCurve of ["prime256v1", "secp256r1", "p-256", "p256", "P-256"]) {
  test(`accepts the explicit P-256 metadata alias ${namedCurve}`, () => {
    assert.equal(isP256PrivateKey({ asymmetricKeyType: "ec", asymmetricKeyDetails: { namedCurve } }), true);
  });
}

test("missing, unknown and other-curve metadata cannot qualify as P-256", () => {
  for (const namedCurve of [undefined, null, 256, {}, [], "", "unknown", " prime256v1", "p256 ", "secp384r1", "P-384", "secp521r1", "P-521", "p521"]) {
    assert.equal(isP256PrivateKey({ asymmetricKeyType: "ec", asymmetricKeyDetails: { namedCurve } }), false);
  }
  for (const key of [undefined, null, {}, { asymmetricKeyType: "ec" }, { asymmetricKeyType: "ec", asymmetricKeyDetails: null }]) {
    assert.equal(isP256PrivateKey(key), false);
  }
});

test("a P-256 curve label does not allow a different key type", () => {
  for (const asymmetricKeyType of [undefined, "rsa", "rsa-pss", "ed25519", "ed448", "dh", "unknown"]) {
    assert.equal(isP256PrivateKey({ asymmetricKeyType, asymmetricKeyDetails: { namedCurve: "p256" } }), false);
  }
});

test("an actual synthetic P-256 key signs the exact Apple payload as verifiable DER SHA-256", () => {
  const signOffer = signer();
  const signed = signOffer(fields);
  const payload = promotionalOfferSignaturePayload({ bundleID, keyID, ...fields });
  const expectedPayload = [
    bundleID, keyID, fields.productID, fields.offerID,
    fields.appAccountToken.toLowerCase(), fields.nonce.toLowerCase(), String(fields.timestamp),
  ].join("\u2063");

  assert.equal(payload, expectedPayload);
  assert.equal(signed.keyID, keyID);
  assert.equal(signed.nonce, fields.nonce.toLowerCase());
  assert.equal(signed.timestamp, fields.timestamp);
  const signature = Buffer.from(signed.signature, "base64");
  assert.equal(signature[0], 0x30);
  assert.equal(verify("sha256", Buffer.from(expectedPayload, "utf8"),
    { key: p256.publicKey, dsaEncoding: "der" }, signature), true);
  assert.equal(verify("sha256", Buffer.from(`${expectedPayload}tampered`, "utf8"),
    { key: p256.publicKey, dsaEncoding: "der" }, signature), false);
});

for (const { name, type, options } of [
  { name: "P-384", type: "ec", options: { namedCurve: "secp384r1" } },
  { name: "RSA", type: "rsa", options: { modulusLength: 2048 } },
  { name: "Ed25519", type: "ed25519", options: {} },
]) {
  test(`rejects an actual synthetic ${name} private key`, () => {
    const { privateKey } = generateKeyPairSync(type, options);
    const privateKeyPEM = privateKey.export({ format: "pem", type: "pkcs8" });
    assert.throws(() => createLegacyPromotionalOfferSigner({ bundleID, keyID, privateKeyPEM }),
      /Promotional offer signing requires a P-256 private key/);
  });
}

test("actual synthetic P-521 keys fail closed even when the runtime cannot import the curve", () => {
  const importFixtureSigner = () => createLegacyPromotionalOfferSigner({
    bundleID, keyID, privateKeyPEM: syntheticP521PEM,
  });
  if (globalThis.Deno) {
    // Rejection during PKCS#8 import is proper fail-closed behavior; it does not prove the curve guard ran.
    assert.throws(importFixtureSigner);
    return;
  }

  const fixtureKey = createPrivateKey({ key: syntheticP521PEM, format: "pem", type: "pkcs8" });
  assert.equal(fixtureKey.asymmetricKeyType, "ec");
  assert.equal(fixtureKey.asymmetricKeyDetails?.namedCurve, "secp521r1");
  assert.equal(isP256PrivateKey(fixtureKey), false);
  assert.throws(importFixtureSigner, /Promotional offer signing requires a P-256 private key/);

  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "secp521r1" });
  assert.equal(privateKey.asymmetricKeyDetails?.namedCurve, "secp521r1");
  assert.equal(isP256PrivateKey(privateKey), false);
  const privateKeyPEM = privateKey.export({ format: "pem", type: "pkcs8" });
  assert.throws(() => createLegacyPromotionalOfferSigner({ bundleID, keyID, privateKeyPEM }),
    /Promotional offer signing requires a P-256 private key/);
});

test("missing and malformed private-key input is rejected", () => {
  for (const privateKeyPEM of [undefined, null, "", "not-a-private-key",
    "-----BEGIN PRIVATE KEY-----\ninvalid\n-----END PRIVATE KEY-----"]) {
    assert.throws(() => createLegacyPromotionalOfferSigner({ bundleID, keyID, privateKeyPEM }));
  }
});

test("malformed signature fields and separator injection are rejected", () => {
  const valid = { bundleID, keyID, ...fields };
  for (const key of ["bundleID", "keyID", "productID", "offerID"]) {
    for (const value of [undefined, null, "", 1, "injected\u2063field"]) {
      assert.throws(() => promotionalOfferSignaturePayload({ ...valid, [key]: value }),
        /Invalid promotional offer signature fields/);
    }
  }
  for (const key of ["appAccountToken", "nonce"]) {
    for (const value of [undefined, null, "", "not-a-uuid", `${fields[key]}extra`]) {
      assert.throws(() => promotionalOfferSignaturePayload({ ...valid, [key]: value }),
        /Invalid promotional offer signature fields/);
    }
  }
  for (const timestamp of [undefined, null, "123", 0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => promotionalOfferSignaturePayload({ ...valid, timestamp }),
      /Invalid promotional offer signature fields/);
  }
});

test("the real signer rejects malformed purchase fields before signing", () => {
  const signOffer = signer();
  for (const invalidFields of [
    { ...fields, productID: "" }, { ...fields, offerID: "invalid\u2063offer" },
    { ...fields, appAccountToken: "not-a-uuid" }, { ...fields, nonce: "not-a-uuid" },
    { ...fields, timestamp: 0 },
  ]) {
    assert.throws(() => signOffer(invalidFields), /Invalid promotional offer signature fields/);
  }
});
