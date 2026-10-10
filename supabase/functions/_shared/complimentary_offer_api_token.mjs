import { createPrivateKey, sign } from "node:crypto";
import { Buffer } from "node:buffer";
import { isP256PrivateKey } from "./complimentary_offer_signature.mjs";

const issuerUUIDPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const tokenLifetimeSeconds = 300;

// P-256 DER signatures fit short-form lengths (at most 72 bytes total).
// Accept exactly two minimally encoded positive INTEGERs, never raw JOSE input.
export function p256DERSignatureToP1363(signatureDER) {
  const invalidSignature = () => { throw new Error("App Store API token signature format is unavailable"); };
  if (!(signatureDER instanceof Uint8Array) || signatureDER.length < 8 || signatureDER.length > 72
      || signatureDER[0] !== 0x30 || signatureDER[1] !== signatureDER.length - 2) {
    invalidSignature();
  }

  const signature = Buffer.alloc(64);
  let offset = 2;
  for (let component = 0; component < 2; component += 1) {
    if (signatureDER[offset] !== 0x02) invalidSignature();
    const length = signatureDER[offset + 1];
    offset += 2;
    if (!Number.isInteger(length) || length < 1 || length > 33 || offset + length > signatureDER.length) {
      invalidSignature();
    }
    let value = signatureDER.subarray(offset, offset + length);
    offset += length;
    if ((value[0] & 0x80) !== 0) invalidSignature();
    if (value[0] === 0) {
      if (value.length === 1 || (value[1] & 0x80) === 0) invalidSignature();
      value = value.subarray(1);
    }
    if (value.length > 32) invalidSignature();
    signature.set(value, (component + 1) * 32 - value.length);
  }
  if (offset !== signatureDER.length) invalidSignature();
  return signature;
}

// Apple server API JWTs use JOSE/P1363 ES256, unlike legacy offer signatures' DER.
// The injected clock follows Date.now(): positive safe-integer epoch milliseconds.
export function createComplimentaryAppStoreAPITokenSigner({
  bundleID, keyID, issuerID, privateKeyPEM, clock = Date.now,
}) {
  if (bundleID !== "com.ichart.app"
      || typeof keyID !== "string" || keyID.length !== 10 || !/^[A-Z0-9]{10}$/.test(keyID)
      || typeof issuerID !== "string" || issuerID.length !== 36 || !issuerUUIDPattern.test(issuerID)
      || typeof clock !== "function") {
    throw new Error("Invalid App Store API token configuration");
  }

  let privateKey;
  try {
    if (typeof privateKeyPEM !== "string" || privateKeyPEM.length === 0) throw new Error();
    privateKey = createPrivateKey({ key: privateKeyPEM, format: "pem", type: "pkcs8" });
  } catch {
    throw new Error("App Store API token signing requires a P-256 private key");
  }
  if (!isP256PrivateKey(privateKey)) {
    throw new Error("App Store API token signing requires a P-256 private key");
  }

  const encodedHeader = encodeJSON({ alg: "ES256", kid: keyID, typ: "JWT" });
  return () => {
    let now;
    try { now = clock(); } catch { throw new Error("Invalid App Store API token clock"); }
    if (!Number.isSafeInteger(now) || now <= 0) throw new Error("Invalid App Store API token clock");
    const iat = Math.floor(now / 1000);
    const exp = iat + tokenLifetimeSeconds;
    if (!Number.isSafeInteger(iat) || iat <= 0 || !Number.isSafeInteger(exp)) {
      throw new Error("Invalid App Store API token clock");
    }
    const encodedPayload = encodeJSON({ bid: bundleID, iss: issuerID, aud: "appstoreconnect-v1", iat, exp });
    const signingInput = `${encodedHeader}.${encodedPayload}`;
    let signatureDER;
    try {
      // Deno 2.1.14 ignores node:crypto's ieee-p1363 option; DER works in both runtimes.
      signatureDER = sign("sha256", Buffer.from(signingInput, "utf8"), { key: privateKey, dsaEncoding: "der" });
    } catch {
      throw new Error("App Store API token signing is unavailable");
    }
    const signature = p256DERSignatureToP1363(signatureDER);
    return `${signingInput}.${signature.toString("base64url")}`;
  };
}

function encodeJSON(value) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}
