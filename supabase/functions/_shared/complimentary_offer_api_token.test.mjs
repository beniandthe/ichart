import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, sign, verify } from "node:crypto";
import { Buffer } from "node:buffer";
import { createComplimentaryAppStoreAPITokenSigner, p256DERSignatureToP1363 } from "./complimentary_offer_api_token.mjs";

const p256 = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const privateKeyPEM = p256.privateKey.export({ format: "pem", type: "pkcs8" });
const timestamp = 1_791_542_400_999;
const configuration = {
  bundleID: "com.ichart.app", keyID: "ABCDEFGHIJ",
  issuerID: "12345678-1234-4234-8234-123456789ABC",
  privateKeyPEM, clock: () => timestamp,
};

function decodedToken(token) {
  const parts = token.split(".");
  assert.equal(parts.length, 3);
  for (const part of parts) assert.match(part, /^[A-Za-z0-9_-]+$/);
  return {
    header: JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8")),
    payload: JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")),
    signingInput: `${parts[0]}.${parts[1]}`,
    signature: Buffer.from(parts[2], "base64url"),
  };
}

async function nativePublicKey(publicKey) {
  return globalThis.crypto.subtle.importKey("spki", publicKey.export({ format: "der", type: "spki" }),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
}

function nativeVerify(publicKey, input, signature) {
  return globalThis.crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, signature, input);
}

function derSignature(r, s) {
  return Buffer.from([0x30, r.length + s.length + 4, 0x02, r.length, ...r, 0x02, s.length, ...s]);
}

test("DER conversion left-pads minimally encoded small positive scalars to fixed-width JOSE", () => {
  const der = derSignature([1], [0x7f]);
  const signature = p256DERSignatureToP1363(der);
  assert.equal(signature.length, 64);
  assert.deepEqual(signature.subarray(0, 32), Buffer.from([...Array(31).fill(0), 1]));
  assert.deepEqual(signature.subarray(32), Buffer.from([...Array(31).fill(0), 0x7f]));
  assert.deepEqual(p256DERSignatureToP1363(new Uint8Array(der)), signature);
  assert.deepEqual(der, derSignature([1], [0x7f]));
});

test("DER conversion accepts full-width unpadded scalars and removes only required sign padding", () => {
  const unpadded = [0x7f, ...Array(31).fill(0xff)];
  const padded = [0, 0x80, ...Array(31).fill(0xff)];
  assert.deepEqual(p256DERSignatureToP1363(derSignature(unpadded, padded)),
    Buffer.from([...unpadded, ...padded.slice(1)]));
  assert.deepEqual(p256DERSignatureToP1363(derSignature(padded, padded)),
    Buffer.from([...padded.slice(1), ...padded.slice(1)]));
  const shorterPadded = [0, 0x80, ...Array(30).fill(0)];
  assert.deepEqual(p256DERSignatureToP1363(derSignature(shorterPadded, [1])).subarray(0, 32),
    Buffer.from([0, ...shorterPadded.slice(1)]));
});

test("DER conversion rejects nonbyte inputs and malformed sequence lengths or tags", () => {
  const valid = derSignature([1], [2]);
  for (const malformed of [undefined, null, "synthetic-sensitive-signature", [], 1, {}, new ArrayBuffer(8),
    new Uint8Array(0), valid.subarray(0, 7), Buffer.from([0x31, ...valid.subarray(1)]),
    Buffer.from([0x30, 5, ...valid.subarray(2)]), Buffer.from([0x30, 7, ...valid.subarray(2)]),
    Buffer.from([0x30, 0x81, 6, ...valid.subarray(2)]), Buffer.from([0x30, 0x80, ...valid.subarray(2), 0, 0]),
    Buffer.concat([valid, valid]), Buffer.alloc(73)]) {
    assert.throws(() => p256DERSignatureToP1363(malformed),
      { message: "App Store API token signature format is unavailable" });
  }
});

test("DER conversion rejects zero, negative, nonminimal and over-width INTEGERs in either position", () => {
  const invalidScalars = [[], [0], [0x80], [0xff], [0, 1], [0, 0x7f], [0, 0, 0x80],
    [0x7f, ...Array(32).fill(1)], [0, 0x80, ...Array(32).fill(1)]];
  for (const scalar of invalidScalars) {
    for (const signature of [derSignature(scalar, [1]), derSignature([1], scalar)]) {
      assert.throws(() => p256DERSignatureToP1363(signature),
        { message: "App Store API token signature format is unavailable" });
    }
  }
});

test("DER conversion rejects wrong INTEGER tags, truncation, extra components and trailing bytes", () => {
  const valid = derSignature([1], [2]);
  for (const malformed of [Buffer.from([0x30, 6, 0x03, 1, 1, 0x02, 1, 2]),
    Buffer.from([0x30, 6, 0x02, 1, 1, 0x03, 1, 2]),
    Buffer.from([0x30, 6, 0x02, 0x81, 1, 0x02, 1, 2]),
    Buffer.from([0x30, 6, 0x02, 1, 1, 0x02, 0x80, 2]),
    Buffer.from([0x30, 6, 0x02, 4, 1, 0x02, 1, 2]),
    Buffer.from([0x30, 6, 0x02, 1, 1, 0x02, 2, 2]),
    Buffer.from([0x30, 7, ...valid.subarray(2), 0]),
    Buffer.from([0x30, 9, ...valid.subarray(2), 0x02, 1, 3])]) {
    assert.throws(() => p256DERSignatureToP1363(malformed),
      { message: "App Store API token signature format is unavailable" });
  }
});

test("server API token has the exact Apple ES256 header and five-minute claims", () => {
  const token = createComplimentaryAppStoreAPITokenSigner(configuration)();
  const decoded = decodedToken(token);
  assert.deepEqual(decoded.header, { alg: "ES256", kid: configuration.keyID, typ: "JWT" });
  assert.deepEqual(decoded.payload, {
    bid: "com.ichart.app", iss: configuration.issuerID, aud: "appstoreconnect-v1",
    iat: 1_791_542_400, exp: 1_791_542_700,
  });
  assert.equal(decoded.payload.exp - decoded.payload.iat, 300);
});

test("actual P-256 token uses a 64-byte JOSE signature that verifies and rejects tampering", async () => {
  const decoded = decodedToken(createComplimentaryAppStoreAPITokenSigner(configuration)());
  assert.equal(decoded.signature.length, 64);
  const publicKey = await nativePublicKey(p256.publicKey);
  const input = Buffer.from(decoded.signingInput, "utf8");
  assert.equal(await nativeVerify(publicKey, input, decoded.signature), true);
  assert.equal(await nativeVerify(publicKey, Buffer.from(`${decoded.signingInput}tampered`, "utf8"), decoded.signature), false);
  const tamperedSignature = Buffer.from(decoded.signature);
  tamperedSignature[0] ^= 1;
  assert.equal(await nativeVerify(publicKey, input, tamperedSignature), false);
  const otherKey = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  assert.equal(await nativeVerify(await nativePublicKey(otherKey.publicKey), input, decoded.signature), false);
  // Retain the direct Node check, without depending on Deno's P1363-ignoring shim.
  if (globalThis.Deno === undefined) {
    assert.equal(verify("sha256", input, { key: p256.publicKey, dsaEncoding: "ieee-p1363" }, decoded.signature), true);
  }
});

test("server API JOSE encoding remains distinct from legacy promotional DER", async () => {
  const decoded = decodedToken(createComplimentaryAppStoreAPITokenSigner(configuration)());
  const input = Buffer.from(decoded.signingInput, "utf8");
  const derSignature = sign("sha256", input, { key: p256.privateKey, dsaEncoding: "der" });
  assert.equal(derSignature[0], 0x30);
  assert.equal(verify("sha256", input, { key: p256.publicKey, dsaEncoding: "der" }, derSignature), true);
  const publicKey = await nativePublicKey(p256.publicKey);
  assert.equal(await nativeVerify(publicKey, input, p256DERSignatureToP1363(derSignature)), true);
  assert.equal(await nativeVerify(publicKey, input, derSignature), false);
  let acceptedAsDER = false;
  try { acceptedAsDER = verify("sha256", input, { key: p256.publicKey, dsaEncoding: "der" }, decoded.signature); } catch {}
  assert.equal(acceptedAsDER, false);
});

test("the signer samples the injected clock for every token and floors milliseconds", () => {
  let now = timestamp;
  let calls = 0;
  const signer = createComplimentaryAppStoreAPITokenSigner({ ...configuration, clock: () => { calls += 1; return now; } });
  assert.equal(calls, 0);
  const first = decodedToken(signer()).payload;
  now += 1_001;
  const second = decodedToken(signer()).payload;
  assert.equal(calls, 2);
  assert.equal(first.iat, Math.floor(timestamp / 1000));
  assert.equal(second.iat, Math.floor(now / 1000));
  assert.equal(second.exp, second.iat + 300);
});

test("valid clock bounds retain positive safe whole-second claims", () => {
  for (const now of [1_000, Number.MAX_SAFE_INTEGER]) {
    const payload = decodedToken(createComplimentaryAppStoreAPITokenSigner({ ...configuration, clock: () => now })()).payload;
    assert.equal(payload.iat, Math.floor(now / 1000));
    assert.equal(payload.exp, payload.iat + 300);
    assert.equal(Number.isSafeInteger(payload.iat), true);
    assert.equal(Number.isSafeInteger(payload.exp), true);
    assert.equal(payload.iat > 0, true);
  }
});

test("invalid clocks cannot issue tokens", () => {
  for (const now of [undefined, null, "123", 0, -1, 999, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, 1n]) {
    const signer = createComplimentaryAppStoreAPITokenSigner({ ...configuration, clock: () => now });
    assert.throws(() => signer(), /Invalid App Store API token clock/);
  }
  for (const clock of [null, 1, "clock", {}]) {
    assert.throws(() => createComplimentaryAppStoreAPITokenSigner({ ...configuration, clock }),
      /Invalid App Store API token configuration/);
  }
});

test("an injected clock error does not disclose its arbitrary error text", () => {
  const signer = createComplimentaryAppStoreAPITokenSigner({ ...configuration,
    clock: () => { throw new Error("synthetic-sensitive-clock-error"); } });
  assert.throws(() => signer(), { message: "Invalid App Store API token clock" });
});

test("missing, unknown and noncanonical public configuration is rejected", () => {
  const invalidValues = {
    bundleID: [undefined, null, "", "other.app", " com.ichart.app", "com.ichart.app "],
    keyID: [undefined, null, "", "abcdef1234", "ABCDEFGHI", "ABCDEFGHIJK", "ABCDEFGHI!", "ABCDEFGHIJ ", "ABCDEFGHIJ\n"],
    issuerID: [undefined, null, "", "not-a-uuid", configuration.issuerID.replaceAll("-", ""),
      `{${configuration.issuerID}}`, ` ${configuration.issuerID}`, `${configuration.issuerID} `, `${configuration.issuerID}\n`],
  };
  for (const [field, values] of Object.entries(invalidValues)) {
    for (const value of values) {
      assert.throws(() => createComplimentaryAppStoreAPITokenSigner({ ...configuration, [field]: value }),
        /Invalid App Store API token configuration/);
    }
  }
});

test("missing or malformed private keys fail closed with a fixed error", () => {
  for (const privateKeyPEM of [undefined, null, "", "synthetic-sensitive-invalid-private-key",
    "-----BEGIN PRIVATE KEY-----\ninvalid\n-----END PRIVATE KEY-----"]) {
    assert.throws(() => createComplimentaryAppStoreAPITokenSigner({ ...configuration, privateKeyPEM }),
      { message: "App Store API token signing requires a P-256 private key" });
  }
});

for (const { name, type, options } of [
  { name: "P-384", type: "ec", options: { namedCurve: "secp384r1" } },
  { name: "RSA", type: "rsa", options: { modulusLength: 2048 } },
  { name: "Ed25519", type: "ed25519", options: {} },
]) {
  test(`an actual synthetic ${name} key cannot issue an ES256 server API token`, () => {
    const { privateKey } = generateKeyPairSync(type, options);
    const privateKeyPEM = privateKey.export({ format: "pem", type: "pkcs8" });
    assert.throws(() => createComplimentaryAppStoreAPITokenSigner({ ...configuration, privateKeyPEM }),
      /App Store API token signing requires a P-256 private key/);
  });
}
