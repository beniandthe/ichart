import { Buffer } from "node:buffer";
import {
  constants as cryptoConstants,
  X509Certificate,
  verify as verifySignature,
} from "node:crypto";
import { KJUR, X509 } from "npm:jsrsasign@11.1.0";
import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";

import {
  appStoreVerifierConfigurationFromEnv,
  appStoreVerifierEnvironmentProduction,
} from "./app_store_verifier_config.mjs";

export function createAppStoreSignedDataVerifiers(env = Deno.env) {
  const config = appStoreVerifierConfigurationFromEnv(env);
  if (!config.ok) {
    return {};
  }

  try {
    const rootCertificateBuffers = config.value.rootCertificateBase64Bodies
      .map((body) => Buffer.from(body, "base64"));
    const verifier = new SignedDataVerifier(
      rootCertificateBuffers,
      config.value.enableOnlineChecks,
      appStoreLibraryEnvironment(config.value.environment),
      config.value.bundleID,
      config.value.appAppleID ?? undefined
    );

    return {
      verifyAndDecodeNotification: (signedPayload) => verifyWithSandboxFallback(
        () => verifier.verifyAndDecodeNotification(signedPayload),
        () => verifyCompactAppStoreJWS(signedPayload, rootCertificateBuffers, config.value, "notification")
      ),
      verifyAndDecodeTransaction: (signedTransactionInfo) => verifyWithSandboxFallback(
        () => verifier.verifyAndDecodeTransaction(signedTransactionInfo),
        () => verifyCompactAppStoreJWS(signedTransactionInfo, rootCertificateBuffers, config.value, "transaction")
      ),
      verifyAndDecodeRenewalInfo: (signedRenewalInfo) => verifyWithSandboxFallback(
        () => verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo),
        () => verifyCompactAppStoreJWS(signedRenewalInfo, rootCertificateBuffers, config.value, "renewalInfo")
      ),
    };
  } catch {
    return {};
  }
}

function appStoreLibraryEnvironment(environment) {
  if (environment === appStoreVerifierEnvironmentProduction) {
    return Environment.PRODUCTION;
  }

  return Environment.SANDBOX;
}

async function verifyWithSandboxFallback(appleVerification, fallbackVerification) {
  try {
    return await appleVerification();
  } catch (error) {
    if (Number(error?.status) !== 1) {
      throw error;
    }

    return fallbackVerification();
  }
}

async function verifyCompactAppStoreJWS(signedPayload, rootCertificateBuffers, config, payloadKind) {
  if (config.environment === appStoreVerifierEnvironmentProduction || config.enableOnlineChecks) {
    throw new AppStoreJWSVerificationError(11);
  }

  const decoded = decodeCompactJWS(signedPayload);
  const publicKey = await verifyCertificateChain(
    decoded.header.x5c,
    rootCertificateBuffers,
    signedDateForPayload(decoded.payload)
  );

  if (!await verifyJWSSignature(decoded, publicKey)) {
    throw new AppStoreJWSVerificationError(24);
  }

  verifyDecodedPayloadScope(decoded.payload, config, payloadKind);
  return decoded.payload;
}

function decodeCompactJWS(signedPayload) {
  if (typeof signedPayload !== "string") {
    throw new AppStoreJWSVerificationError(12);
  }

  const parts = signedPayload.split(".");
  if (parts.length !== 3) {
    throw new AppStoreJWSVerificationError(13);
  }

  try {
    return {
      encodedHeader: parts[0],
      encodedPayload: parts[1],
      encodedSignature: parts[2],
      header: JSON.parse(base64URLDecode(parts[0]).toString("utf8")),
      payload: JSON.parse(base64URLDecode(parts[1]).toString("utf8")),
    };
  } catch (error) {
    throw new AppStoreJWSVerificationError(14, error);
  }
}

async function verifyCertificateChain(x5c, rootCertificateBuffers, effectiveDate) {
  if (!Array.isArray(x5c) || x5c.length !== 3) {
    throw new AppStoreJWSVerificationError(15);
  }

  let leaf;
  let leafBuffer;
  let intermediate;
  let intermediateBuffer;
  let rootCertificates;
  try {
    leafBuffer = Buffer.from(x5c[0], "base64");
    intermediateBuffer = Buffer.from(x5c[1], "base64");
    leaf = new X509Certificate(leafBuffer);
    intermediate = new X509Certificate(intermediateBuffer);
    rootCertificates = rootCertificateBuffers.map((buffer) => ({
      certificate: new X509Certificate(buffer),
      rawBuffer: Buffer.from(buffer),
    }));
  } catch (error) {
    throw new AppStoreJWSVerificationError(16, error);
  }

  let root;
  for (const candidate of rootCertificates) {
    try {
      if (await verifyCertificateSignature(
        intermediate,
        candidate.certificate,
        intermediateBuffer,
        candidate.rawBuffer
      )) {
        root = candidate;
        break;
      }
    } catch {
      continue;
    }
  }

  if (root === undefined) {
    throw new AppStoreJWSVerificationError(
      await unmatchedRootDiagnosticStatus(x5c[2], intermediate, intermediateBuffer)
    );
  }

  try {
    if (!await verifyCertificateSignature(leaf, intermediate, leafBuffer, intermediateBuffer)) {
      throw new AppStoreJWSVerificationError(18);
    }
  } catch (error) {
    if (error instanceof AppStoreJWSVerificationError) {
      throw error;
    }

    throw new AppStoreJWSVerificationError(28, error);
  }

  if (!intermediate.ca) {
    throw new AppStoreJWSVerificationError(19);
  }

  if (!certificateHasExtension(leaf, "1.2.840.113635.100.6.11.1", leafBuffer)) {
    throw new AppStoreJWSVerificationError(20);
  }

  if (!certificateHasExtension(intermediate, "1.2.840.113635.100.6.2.1", intermediateBuffer)) {
    throw new AppStoreJWSVerificationError(21);
  }

  if (
    !certificateIsValidAt(leaf, effectiveDate)
    || !certificateIsValidAt(intermediate, effectiveDate)
    || !certificateIsValidAt(root.certificate, effectiveDate)
  ) {
    throw new AppStoreJWSVerificationError(22);
  }

  return leaf.publicKey;
}

async function verifyJWSSignature(decoded, publicKey) {
  const algorithm = signatureAlgorithm(decoded.header.alg);
  if (algorithm === null) {
    throw new AppStoreJWSVerificationError(23);
  }

  try {
    const verified = verifySignature(
      algorithm,
      Buffer.from(`${decoded.encodedHeader}.${decoded.encodedPayload}`),
      { key: publicKey, dsaEncoding: "ieee-p1363" },
      base64URLDecode(decoded.encodedSignature)
    );
    if (verified) {
      return true;
    }
  } catch (error) {
    // Supabase Edge may expose node:crypto without honoring dsaEncoding for
    // raw ECDSA JWS signatures. Fall through to WebCrypto, which uses raw
    // ECDSA signatures for P-256/P-384/P-521.
  }

  return verifyJWSSignatureWithWebCrypto(decoded, publicKey);
}

function verifyDecodedPayloadScope(payload, config, payloadKind) {
  if (payloadKind === "transaction") {
    if (payload?.bundleId !== config.bundleID) {
      throw new AppStoreJWSVerificationError(25);
    }

    if (payload?.environment !== config.environment) {
      throw new AppStoreJWSVerificationError(26);
    }

    return;
  }

  if (payloadKind === "renewalInfo") {
    if (payload?.environment !== config.environment) {
      throw new AppStoreJWSVerificationError(26);
    }

    return;
  }

  const notificationScope = notificationPayloadScope(payload);
  if (
    notificationScope.bundleID !== config.bundleID
    || (config.environment === appStoreVerifierEnvironmentProduction
      && config.appAppleID !== notificationScope.appAppleID)
  ) {
    throw new AppStoreJWSVerificationError(25);
  }

  if (notificationScope.environment !== config.environment) {
    throw new AppStoreJWSVerificationError(26);
  }
}

function notificationPayloadScope(payload) {
  if (payload?.data) {
    return {
      appAppleID: payload.data.appAppleId,
      bundleID: payload.data.bundleId,
      environment: payload.data.environment,
    };
  }

  if (payload?.summary) {
    return {
      appAppleID: payload.summary.appAppleId,
      bundleID: payload.summary.bundleId,
      environment: payload.summary.environment,
    };
  }

  if (payload?.externalPurchaseToken) {
    return {
      appAppleID: payload.externalPurchaseToken.appAppleId,
      bundleID: payload.externalPurchaseToken.bundleId,
      environment: String(payload.externalPurchaseToken.externalPurchaseId ?? "").startsWith("SANDBOX")
        ? "Sandbox"
        : "Production",
    };
  }

  if (payload?.appData) {
    return {
      appAppleID: payload.appData.appAppleId,
      bundleID: payload.appData.bundleId,
      environment: payload.appData.environment,
    };
  }

  return {};
}

function certificateHasExtension(certificate, oid, rawBuffer) {
  try {
    const parsedCertificate = new X509();
    parsedCertificate.readCertHex(certificateRawHex(certificate, rawBuffer));
    return parsedCertificate.getExtInfo(oid) !== undefined;
  } catch {
    return false;
  }
}

async function verifyCertificateSignature(certificate, issuerCertificate, certificateRawBuffer, issuerRawBuffer) {
  if (typeof certificate.verify === "function") {
    try {
      return certificate.verify(issuerCertificate.publicKey);
    } catch {
      // Supabase Edge's Node compatibility can expose X509Certificate.verify
      // but throw for Apple's EC certificate chain; fall through to explicit
      // ECDSA verification.
    }
  }

  let parsedCertificate;
  let params;
  try {
    parsedCertificate = new X509();
    parsedCertificate.readCertHex(certificateRawHex(certificate, certificateRawBuffer));
    params = parsedCertificate.getParam({ tbshex: true });
  } catch (error) {
    throw new AppStoreJWSVerificationError(42, error);
  }

  try {
    return verifyCertificateSignatureWithNodeCrypto(params, issuerCertificate.publicKey);
  } catch {
    try {
      return await verifyCertificateSignatureWithWebCrypto(params, issuerCertificate.publicKey);
    } catch {
      const webCryptoError = await webCryptoVerificationError(params, issuerCertificate.publicKey);
      const parsedIssuerCertificate = new X509();
      try {
        parsedIssuerCertificate.readCertHex(certificateRawHex(issuerCertificate, issuerRawBuffer));
        return verifyCertificateSignatureWithJSRsaSign(
          parsedCertificate,
          parsedIssuerCertificate.getPublicKey()
        );
      } catch (error) {
        if (webCryptoError instanceof AppStoreJWSVerificationError) {
          throw webCryptoError;
        }

        throw new AppStoreJWSVerificationError(48, error);
      }
    }
  }
}

function certificateRawHex(certificate, rawBuffer) {
  return Buffer.from(rawBuffer ?? certificate.raw).toString("hex");
}

function verifyCertificateSignatureWithJSRsaSign(parsedCertificate, issuerPublicKey) {
  const params = parsedCertificate.getParam({ tbshex: true });
  const signature = new KJUR.crypto.Signature(signatureOptionsForJSRsaSign(params.sigalg));
  signature.init(issuerPublicKey);
  signature.updateHex(params.tbshex);
  return signature.verify(params.sighex);
}

function signatureOptionsForJSRsaSign(signatureAlgorithmName) {
  const normalizedName = signatureAlgorithmName.toLowerCase();
  const options = { alg: signatureAlgorithmName };
  if (normalizedName.includes("rsaandmgf1")) {
    const saltLength = signatureHashByteLength(normalizedName);
    if (saltLength === null) {
      throw new AppStoreJWSVerificationError(27);
    }

    options.psssaltlen = saltLength;
  }

  return options;
}

function verifyCertificateSignatureWithNodeCrypto(params, issuerPublicKey) {
  const signatureOptions = nodeCryptoSignatureOptions(params.sigalg, issuerPublicKey);

  return verifySignature(
    signatureOptions.algorithm,
    Buffer.from(params.tbshex, "hex"),
    signatureOptions.key,
    Buffer.from(params.sighex, "hex")
  );
}

function nodeCryptoSignatureOptions(signatureAlgorithmName, publicKey) {
  const normalizedName = signatureAlgorithmName.toLowerCase();
  const algorithm = signatureHashAlgorithm(normalizedName);
  if (algorithm === null) {
    throw new AppStoreJWSVerificationError(27);
  }

  if (normalizedName.includes("rsaandmgf1")) {
    return {
      algorithm,
      key: {
        key: publicKey,
        padding: cryptoConstants.RSA_PKCS1_PSS_PADDING,
        saltLength: cryptoConstants.RSA_PSS_SALTLEN_DIGEST,
      },
    };
  }

  if (normalizedName.includes("rsa")) {
    return {
      algorithm,
      key: {
        key: publicKey,
        padding: cryptoConstants.RSA_PKCS1_PADDING,
      },
    };
  }

  return {
    algorithm,
    key: publicKey,
  };
}

async function verifyCertificateSignatureWithWebCrypto(params, issuerPublicKey) {
  const subtle = globalThis.crypto?.subtle;
  if (subtle === undefined || typeof issuerPublicKey?.export !== "function") {
    throw new AppStoreJWSVerificationError(43);
  }

  const algorithm = webCryptoECDSAAlgorithm(params.sigalg, issuerPublicKey);
  if (algorithm === null) {
    throw new AppStoreJWSVerificationError(44);
  }

  let key;
  try {
    key = await subtle.importKey(
      "spki",
      issuerPublicKey.export({ format: "der", type: "spki" }),
      {
        name: "ECDSA",
        namedCurve: algorithm.namedCurve,
      },
      false,
      ["verify"]
    );
  } catch (error) {
    throw new AppStoreJWSVerificationError(45, error);
  }

  let signature;
  try {
    signature = ecdsaDERSignatureToRaw(Buffer.from(params.sighex, "hex"), algorithm.coordinateLength);
  } catch (error) {
    throw new AppStoreJWSVerificationError(46, error);
  }

  try {
    return await subtle.verify(
      {
        name: "ECDSA",
        hash: algorithm.hash,
      },
      key,
      signature,
      Buffer.from(params.tbshex, "hex")
    );
  } catch (error) {
    throw new AppStoreJWSVerificationError(47, error);
  }
}

async function verifyJWSSignatureWithWebCrypto(decoded, publicKey) {
  const subtle = globalThis.crypto?.subtle;
  const algorithm = webCryptoJWSAlgorithm(decoded.header.alg);
  if (subtle === undefined || typeof publicKey?.export !== "function" || algorithm === null) {
    throw new AppStoreJWSVerificationError(24);
  }

  let key;
  try {
    key = await subtle.importKey(
      "spki",
      publicKey.export({ format: "der", type: "spki" }),
      {
        name: "ECDSA",
        namedCurve: algorithm.namedCurve,
      },
      false,
      ["verify"]
    );
  } catch (error) {
    throw new AppStoreJWSVerificationError(24, error);
  }

  try {
    return await subtle.verify(
      {
        name: "ECDSA",
        hash: algorithm.hash,
      },
      key,
      base64URLDecode(decoded.encodedSignature),
      Buffer.from(`${decoded.encodedHeader}.${decoded.encodedPayload}`)
    );
  } catch (error) {
    throw new AppStoreJWSVerificationError(24, error);
  }
}

function webCryptoJWSAlgorithm(algorithm) {
  switch (algorithm) {
    case "ES256":
      return { hash: "SHA-256", namedCurve: "P-256" };
    case "ES384":
      return { hash: "SHA-384", namedCurve: "P-384" };
    case "ES512":
      return { hash: "SHA-512", namedCurve: "P-521" };
    default:
      return null;
  }
}

async function webCryptoVerificationError(params, issuerPublicKey) {
  try {
    await verifyCertificateSignatureWithWebCrypto(params, issuerPublicKey);
    return null;
  } catch (error) {
    return error;
  }
}

function webCryptoECDSAAlgorithm(signatureAlgorithmName, issuerPublicKey) {
  const hash = webCryptoHashAlgorithm(signatureAlgorithmName);
  const curveName = normalizedNamedCurve(issuerPublicKey.asymmetricKeyDetails?.namedCurve);
  if (hash === undefined || curveName === null) {
    return null;
  }

  return {
    hash,
    namedCurve: curveName.name,
    coordinateLength: curveName.coordinateLength,
  };
}

function webCryptoHashAlgorithm(signatureAlgorithmName) {
  switch (signatureHashAlgorithm(signatureAlgorithmName.toLowerCase())) {
    case "sha512":
      return "SHA-512";
    case "sha384":
      return "SHA-384";
    case "sha256":
      return "SHA-256";
    case "sha1":
      return "SHA-1";
    default:
      return undefined;
  }
}

function normalizedNamedCurve(namedCurve) {
  switch (String(namedCurve ?? "").toLowerCase()) {
    case "prime256v1":
    case "secp256r1":
    case "p-256":
      return { name: "P-256", coordinateLength: 32 };
    case "secp384r1":
    case "p-384":
      return { name: "P-384", coordinateLength: 48 };
    case "secp521r1":
    case "p-521":
      return { name: "P-521", coordinateLength: 66 };
    default:
      return null;
  }
}

function ecdsaDERSignatureToRaw(signature, coordinateLength) {
  let offset = 0;
  if (signature[offset] !== 0x30) {
    throw new AppStoreJWSVerificationError(27);
  }
  offset += 1;

  const sequenceLength = readASN1Length(signature, offset);
  offset = sequenceLength.offset;
  if (sequenceLength.length !== signature.length - offset) {
    throw new AppStoreJWSVerificationError(27);
  }

  const r = readASN1Integer(signature, offset);
  offset = r.offset;
  const s = readASN1Integer(signature, offset);
  offset = s.offset;
  if (offset !== signature.length) {
    throw new AppStoreJWSVerificationError(27);
  }

  return Buffer.concat([
    integerToFixedWidth(r.value, coordinateLength),
    integerToFixedWidth(s.value, coordinateLength),
  ]);
}

function readASN1Integer(bytes, offset) {
  if (bytes[offset] !== 0x02) {
    throw new AppStoreJWSVerificationError(27);
  }

  const length = readASN1Length(bytes, offset + 1);
  const start = length.offset;
  const end = start + length.length;
  if (end > bytes.length) {
    throw new AppStoreJWSVerificationError(27);
  }

  return {
    value: bytes.subarray(start, end),
    offset: end,
  };
}

function readASN1Length(bytes, offset) {
  const first = bytes[offset];
  if (first === undefined) {
    throw new AppStoreJWSVerificationError(27);
  }

  if ((first & 0x80) === 0) {
    return {
      length: first,
      offset: offset + 1,
    };
  }

  const byteCount = first & 0x7f;
  if (byteCount === 0 || byteCount > 4 || offset + byteCount >= bytes.length) {
    throw new AppStoreJWSVerificationError(27);
  }

  let length = 0;
  for (let index = 0; index < byteCount; index += 1) {
    length = (length << 8) | bytes[offset + 1 + index];
  }

  return {
    length,
    offset: offset + 1 + byteCount,
  };
}

function integerToFixedWidth(value, width) {
  let bytes = Buffer.from(value);
  while (bytes.length > 0 && bytes[0] === 0) {
    bytes = bytes.subarray(1);
  }

  if (bytes.length > width) {
    throw new AppStoreJWSVerificationError(27);
  }

  return Buffer.concat([Buffer.alloc(width - bytes.length), bytes]);
}

function signatureHashAlgorithm(normalizedSignatureAlgorithmName) {
  if (normalizedSignatureAlgorithmName.includes("sha512")) {
    return "sha512";
  }

  if (normalizedSignatureAlgorithmName.includes("sha384")) {
    return "sha384";
  }

  if (normalizedSignatureAlgorithmName.includes("sha256")) {
    return "sha256";
  }

  if (normalizedSignatureAlgorithmName.includes("sha224")) {
    return "sha224";
  }

  if (normalizedSignatureAlgorithmName.includes("sha1")) {
    return "sha1";
  }

  return null;
}

function signatureHashByteLength(normalizedSignatureAlgorithmName) {
  if (normalizedSignatureAlgorithmName.includes("sha512")) {
    return 64;
  }

  if (normalizedSignatureAlgorithmName.includes("sha384")) {
    return 48;
  }

  if (normalizedSignatureAlgorithmName.includes("sha256")) {
    return 32;
  }

  if (normalizedSignatureAlgorithmName.includes("sha224")) {
    return 28;
  }

  if (normalizedSignatureAlgorithmName.includes("sha1")) {
    return 20;
  }

  return null;
}

async function unmatchedRootDiagnosticStatus(encodedRoot, intermediate, intermediateBuffer) {
  let headerRoot;
  let headerRootBuffer;
  try {
    headerRootBuffer = Buffer.from(encodedRoot, "base64");
    headerRoot = new X509Certificate(headerRootBuffer);
  } catch {
    return 38;
  }

  const subjectStatus = rootSubjectDiagnosticStatus(headerRoot.subject);
  try {
    return await verifyCertificateSignature(
      intermediate,
      headerRoot,
      intermediateBuffer,
      headerRootBuffer
    )
      ? subjectStatus
      : subjectStatus + 20;
  } catch (error) {
    if (
      error instanceof AppStoreJWSVerificationError
      && error.status >= 42
      && error.status <= 48
    ) {
      return error.status;
    }

    return subjectStatus + 10;
  }
}

function rootSubjectDiagnosticStatus(subject) {
  if (subject.includes("Apple Root CA - G3")) {
    return 31;
  }

  if (subject.includes("Apple Root CA - G2")) {
    return 32;
  }

  if (subject.includes("Apple Inc. Root Certificate")) {
    return 33;
  }

  if (subject.includes("Apple Root")) {
    return 34;
  }

  if (subject.includes("Apple Application Integration")) {
    return 35;
  }

  if (subject.includes("Apple Worldwide Developer Relations")) {
    return 36;
  }

  return 37;
}

function certificateIsValidAt(certificate, date) {
  return new Date(certificate.validFrom).getTime() <= date.getTime() + 60_000
    && new Date(certificate.validTo).getTime() >= date.getTime() - 60_000;
}

function signatureAlgorithm(algorithm) {
  switch (algorithm) {
    case "ES256":
      return "sha256";
    case "ES384":
      return "sha384";
    case "ES512":
      return "sha512";
    default:
      return null;
  }
}

function signedDateForPayload(payload) {
  if (Number.isFinite(payload?.signedDate)) {
    return new Date(payload.signedDate);
  }

  return new Date();
}

function base64URLDecode(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - normalized.length % 4) % 4), "=");
  return Buffer.from(padded, "base64");
}

class AppStoreJWSVerificationError extends Error {
  constructor(status, cause) {
    super();
    this.status = status;
    this.cause = cause;
  }
}
