import { createPrivateKey, sign } from "node:crypto";
import { Buffer } from "node:buffer";

const separator = "\u2063";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const p256NamedCurves = new Set(["prime256v1", "secp256r1", "p-256", "p256"]);

// Node/OpenSSL and Deno report equivalent P-256 keys with different curve names.
export function isP256PrivateKey(privateKey) {
  const namedCurve = privateKey?.asymmetricKeyDetails?.namedCurve;
  return privateKey?.asymmetricKeyType === "ec"
    && typeof namedCurve === "string" && p256NamedCurves.has(namedCurve.toLowerCase());
}

// Apple's legacy iOS 17+ promotional-offer API requires ASN.1 DER, not JOSE/P1363.
export function promotionalOfferSignaturePayload({ bundleID, keyID, productID, offerID, appAccountToken, nonce, timestamp }) {
  const fields = [bundleID, keyID, productID, offerID];
  if (fields.some((value) => typeof value !== "string" || value.length === 0 || value.includes(separator))
      || !uuidPattern.test(appAccountToken ?? "") || !uuidPattern.test(nonce ?? "")
      || !Number.isSafeInteger(timestamp) || timestamp <= 0) {
    throw new Error("Invalid promotional offer signature fields");
  }
  return [...fields, appAccountToken.toLowerCase(), nonce.toLowerCase(), String(timestamp)].join(separator);
}

export function createLegacyPromotionalOfferSigner({ bundleID, keyID, privateKeyPEM }) {
  const privateKey = createPrivateKey({ key: privateKeyPEM, format: "pem", type: "pkcs8" });
  if (!isP256PrivateKey(privateKey)) {
    throw new Error("Promotional offer signing requires a P-256 private key");
  }
  return ({ productID, offerID, appAccountToken, nonce, timestamp }) => {
    const payload = promotionalOfferSignaturePayload({ bundleID, keyID, productID, offerID, appAccountToken, nonce, timestamp });
    const signature = sign("sha256", Buffer.from(payload, "utf8"), { key: privateKey, dsaEncoding: "der" }).toString("base64");
    return { keyID, nonce: nonce.toLowerCase(), signature, timestamp };
  };
}
