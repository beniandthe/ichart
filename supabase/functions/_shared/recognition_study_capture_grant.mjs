const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder("utf-8", { fatal: true });

export const captureGrantContract = Object.freeze({
  signedSchemaVersion: "recognition-study-signed-capture-grant-v1",
  payloadSchemaVersion: "recognition-study-capture-grant-v1",
  artifactKind: "externally-authorized-session-grant-v1",
  collectionProtocolVersion: "writer-independent-capture-v2",
  consentSchemaVersion: "recognition-study-consent-binding-v1",
  consentScope: "chord-recognition-research-v1",
  captureContractVersion: "recognition-study-authorized-capture-v1",
  studyBundleIdentifier: "com.ichart.recognitionstudy",
  maximumPromptCount: 256,
  maximumPayloadBytes: 256 * 1024,
  maximumSignedGrantBytes: 272 * 1024,
});

const wrapperFields = new Set([
  "payload",
  "schemaVersion",
  "signatureBase64",
  "signingKeyID",
]);
const payloadFields = new Set([
  "artifactKind",
  "authorizationEpoch",
  "authorizationID",
  "captureTickets",
  "clientRequirements",
  "collectionProtocolVersion",
  "consentBinding",
  "datasetVersion",
  "expectedCaptureCount",
  "expiresAtUnixSeconds",
  "issuedAtUnixSeconds",
  "notBeforeUnixSeconds",
  "promptPlanVersion",
  "schemaVersion",
  "serviceSessionID",
]);
const consentFields = new Set([
  "consentLedgerEpoch",
  "consentLedgerVersion",
  "consentRecordID",
  "consentRecordSHA256",
  "consentTextVersion",
  "dataUsePolicyVersion",
  "privacyNoticeVersion",
  "rawStrokeDonationAuthorized",
  "retentionPolicyVersion",
  "schemaVersion",
  "scope",
]);
const clientRequirementFields = new Set([
  "captureContractVersion",
  "expectedBundleIdentifier",
  "minimumBuildNumber",
]);
const ticketFields = new Set([
  "captureAuthorizationID",
  "displayText",
  "ordinal",
  "presentedChartStyle",
  "presentedConstruction",
  "presentedPace",
  "presentedSize",
  "promptID",
  "promptKind",
  "requestedOrientation",
]);

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const sha256Pattern = /^[0-9a-f]{64}$/;
const versionPattern = /^[a-z0-9][a-z0-9._-]*$/;
const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const allowedDisplayTextNonASCIIScalars = new Set([
  0x00B0,
  0x00D8,
  0x00F8,
  0x0394,
  0x25B3,
  0x266D,
  0x266E,
  0x266F,
]);

export class RecognitionStudyCaptureGrantError extends Error {
  constructor(code, path, detail = "") {
    super(`${code}:${path}${detail.length > 0 ? `:${detail}` : ""}`);
    this.name = "RecognitionStudyCaptureGrantError";
    this.code = code;
    this.path = path;
    this.detail = detail;
  }
}

export function validateCaptureGrantPayload(value) {
  requireObject(value, "payload");
  requireExactFields(value, payloadFields, "payload");
  requireFixed(value.schemaVersion, captureGrantContract.payloadSchemaVersion, "payload.schemaVersion");
  requireFixed(value.artifactKind, captureGrantContract.artifactKind, "payload.artifactKind");
  requireUUID(value.authorizationID, "payload.authorizationID");
  requireUUID(value.serviceSessionID, "payload.serviceSessionID");
  requireVersion(value.datasetVersion, "payload.datasetVersion");
  requireFixed(
    value.collectionProtocolVersion,
    captureGrantContract.collectionProtocolVersion,
    "payload.collectionProtocolVersion",
  );
  requireVersion(value.promptPlanVersion, "payload.promptPlanVersion");
  requirePositiveSafeInteger(value.expectedCaptureCount, "payload.expectedCaptureCount");
  requirePositiveSafeInteger(value.authorizationEpoch, "payload.authorizationEpoch");
  requireNonnegativeSafeInteger(value.issuedAtUnixSeconds, "payload.issuedAtUnixSeconds");
  requireNonnegativeSafeInteger(value.notBeforeUnixSeconds, "payload.notBeforeUnixSeconds");
  requireNonnegativeSafeInteger(value.expiresAtUnixSeconds, "payload.expiresAtUnixSeconds");
  if (
    value.issuedAtUnixSeconds > value.notBeforeUnixSeconds
    || value.notBeforeUnixSeconds >= value.expiresAtUnixSeconds
  ) {
    fail("invalid_timestamp_order", "payload");
  }

  validateConsentBinding(value.consentBinding);
  validateClientRequirements(value.clientRequirements);
  if (!Array.isArray(value.captureTickets)) {
    fail("invalid_array", "payload.captureTickets");
  }
  if (
    value.captureTickets.length === 0
    || value.captureTickets.length > captureGrantContract.maximumPromptCount
  ) {
    fail(
      "invalid_prompt_count",
      "payload.captureTickets",
      `expected 1...${captureGrantContract.maximumPromptCount}`,
    );
  }
  if (value.expectedCaptureCount !== value.captureTickets.length) {
    fail("prompt_count_mismatch", "payload.expectedCaptureCount");
  }

  const captureAuthorizationIDs = new Set();
  const promptIDs = new Set();
  const allIDs = new Set([value.authorizationID, value.serviceSessionID]);
  for (const [index, ticket] of value.captureTickets.entries()) {
    validatePromptTicket(ticket, index);
    if (ticket.ordinal !== index) {
      fail("noncontiguous_prompt_ordinals", `payload.captureTickets[${index}].ordinal`);
    }
    if (captureAuthorizationIDs.has(ticket.captureAuthorizationID)) {
      fail("duplicate_capture_authorization_id", `payload.captureTickets[${index}]`);
    }
    if (promptIDs.has(ticket.promptID)) {
      fail("duplicate_prompt_id", `payload.captureTickets[${index}]`);
    }
    if (allIDs.has(ticket.captureAuthorizationID)) {
      fail("identifier_collision", `payload.captureTickets[${index}].captureAuthorizationID`);
    }
    captureAuthorizationIDs.add(ticket.captureAuthorizationID);
    promptIDs.add(ticket.promptID);
    allIDs.add(ticket.captureAuthorizationID);
  }

  const canonical = canonicalJSONBytes(value);
  if (canonical.byteLength > captureGrantContract.maximumPayloadBytes) {
    fail("payload_too_large", "payload", String(canonical.byteLength));
  }
  return value;
}

export function validateSignedCaptureGrant(value) {
  requireObject(value, "grant");
  requireExactFields(value, wrapperFields, "grant");
  requireFixed(value.schemaVersion, captureGrantContract.signedSchemaVersion, "grant.schemaVersion");
  requirePrintableASCII(value.signingKeyID, "grant.signingKeyID", 64);
  validateCaptureGrantPayload(value.payload);
  const signature = canonicalBase64Bytes(value.signatureBase64, "grant.signatureBase64");
  if (signature.byteLength !== 64) {
    fail("invalid_signature_length", "grant.signatureBase64");
  }
  const canonical = canonicalJSONBytes(value);
  if (canonical.byteLength > captureGrantContract.maximumSignedGrantBytes) {
    fail("signed_grant_too_large", "grant", String(canonical.byteLength));
  }
  return value;
}

export function canonicalJSONString(value) {
  return JSON.stringify(canonicalValue(value, "$"));
}

export function canonicalJSONBytes(value) {
  return textEncoder.encode(canonicalJSONString(value));
}

export function decodeCanonicalSignedCaptureGrant(input) {
  const bytes = typeof input === "string" ? textEncoder.encode(input) : asUint8Array(input);
  if (bytes.byteLength > captureGrantContract.maximumSignedGrantBytes) {
    fail("signed_grant_too_large", "grant", String(bytes.byteLength));
  }
  let text;
  let value;
  try {
    text = textDecoder.decode(bytes);
    value = JSON.parse(text);
  } catch {
    fail("invalid_json", "grant");
  }
  validateSignedCaptureGrant(value);
  if (canonicalJSONString(value) !== text) {
    fail("noncanonical_json", "grant");
  }
  return value;
}

export async function createSignedCaptureGrant({
  payload,
  signingKeyID,
  signPayload,
}) {
  validateCaptureGrantPayload(payload);
  requirePrintableASCII(signingKeyID, "signingKeyID", 64);
  if (typeof signPayload !== "function") {
    fail("missing_signer", "signPayload");
  }
  const signature = asUint8Array(await signPayload(canonicalJSONBytes(payload)));
  if (signature.byteLength !== 64) {
    fail("invalid_signature_length", "signature");
  }
  const grant = {
    payload,
    schemaVersion: captureGrantContract.signedSchemaVersion,
    signatureBase64: bytesToBase64(signature),
    signingKeyID,
  };
  validateSignedCaptureGrant(grant);
  return Object.freeze(grant);
}

export async function verifySignedCaptureGrant({
  grant,
  trustedRawPublicKeysByID,
  validationUnixSeconds,
  subtle = globalThis.crypto?.subtle,
}) {
  validateSignedCaptureGrant(grant);
  requireNonnegativeSafeInteger(validationUnixSeconds, "validationUnixSeconds");
  if (!(trustedRawPublicKeysByID instanceof Map)) {
    fail("invalid_keyring", "trustedRawPublicKeysByID");
  }
  const rawPublicKey = trustedRawPublicKeysByID.get(grant.signingKeyID);
  if (rawPublicKey === undefined) {
    fail("untrusted_signing_key", "grant.signingKeyID", grant.signingKeyID);
  }
  if (subtle === undefined) {
    fail("missing_crypto_runtime", "crypto.subtle");
  }

  let key;
  let verified = false;
  try {
    key = await subtle.importKey(
      "raw",
      asUint8Array(rawPublicKey),
      { name: "Ed25519" },
      false,
      ["verify"],
    );
    verified = await subtle.verify(
      { name: "Ed25519" },
      key,
      canonicalBase64Bytes(grant.signatureBase64, "grant.signatureBase64"),
      canonicalJSONBytes(grant.payload),
    );
  } catch {
    fail("invalid_signing_public_key", "grant.signingKeyID");
  }
  if (!verified) {
    fail("signature_verification_failed", "grant.signatureBase64");
  }
  if (validationUnixSeconds < grant.payload.notBeforeUnixSeconds) {
    fail("authorization_not_yet_valid", "validationUnixSeconds");
  }
  if (validationUnixSeconds >= grant.payload.expiresAtUnixSeconds) {
    fail("authorization_expired", "validationUnixSeconds");
  }
  return grant.payload;
}

export async function signedCaptureGrantSHA256(
  grant,
  subtle = globalThis.crypto?.subtle,
) {
  validateSignedCaptureGrant(grant);
  if (subtle === undefined) {
    fail("missing_crypto_runtime", "crypto.subtle");
  }
  const digest = new Uint8Array(
    await subtle.digest("SHA-256", canonicalJSONBytes(grant)),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function validateConsentBinding(value) {
  requireObject(value, "payload.consentBinding");
  requireExactFields(value, consentFields, "payload.consentBinding");
  requireFixed(
    value.schemaVersion,
    captureGrantContract.consentSchemaVersion,
    "payload.consentBinding.schemaVersion",
  );
  requireUUID(value.consentRecordID, "payload.consentBinding.consentRecordID");
  requireSHA256(value.consentRecordSHA256, "payload.consentBinding.consentRecordSHA256");
  requireFixed(value.scope, captureGrantContract.consentScope, "payload.consentBinding.scope");
  requireVersion(value.consentLedgerVersion, "payload.consentBinding.consentLedgerVersion");
  requirePositiveSafeInteger(value.consentLedgerEpoch, "payload.consentBinding.consentLedgerEpoch");
  requireVersion(value.consentTextVersion, "payload.consentBinding.consentTextVersion");
  requireVersion(value.privacyNoticeVersion, "payload.consentBinding.privacyNoticeVersion");
  requireVersion(value.dataUsePolicyVersion, "payload.consentBinding.dataUsePolicyVersion");
  requireVersion(value.retentionPolicyVersion, "payload.consentBinding.retentionPolicyVersion");
  if (value.rawStrokeDonationAuthorized !== true) {
    fail("raw_stroke_donation_not_authorized", "payload.consentBinding.rawStrokeDonationAuthorized");
  }
}

function validateClientRequirements(value) {
  requireObject(value, "payload.clientRequirements");
  requireExactFields(value, clientRequirementFields, "payload.clientRequirements");
  requireFixed(
    value.captureContractVersion,
    captureGrantContract.captureContractVersion,
    "payload.clientRequirements.captureContractVersion",
  );
  requireFixed(
    value.expectedBundleIdentifier,
    captureGrantContract.studyBundleIdentifier,
    "payload.clientRequirements.expectedBundleIdentifier",
  );
  requirePositiveSafeInteger(value.minimumBuildNumber, "payload.clientRequirements.minimumBuildNumber");
}

function validatePromptTicket(value, index) {
  const path = `payload.captureTickets[${index}]`;
  requireObject(value, path);
  requireExactFields(value, ticketFields, path);
  requireUUID(value.captureAuthorizationID, `${path}.captureAuthorizationID`);
  requireDisplayText(value.displayText, `${path}.displayText`);
  requireNonnegativeSafeInteger(value.ordinal, `${path}.ordinal`);
  requireOneOf(value.promptKind, ["isolated-chord", "realistic-row", "open-set-negative"], `${path}.promptKind`);
  requireSlug(value.promptID, `${path}.promptID`, 64);
  requireOneOf(value.presentedChartStyle, ["simple-chord-sheet", "rhythm-section-sheet"], `${path}.presentedChartStyle`);
  requireOneOf(value.requestedOrientation, ["portrait", "landscape"], `${path}.requestedOrientation`);
  requireOneOf(value.presentedPace, ["natural", "fast", "careful"], `${path}.presentedPace`);
  requireOneOf(value.presentedSize, ["small", "normal", "large"], `${path}.presentedSize`);
  requireOneOf(value.presentedConstruction, ["root-first", "modifier-first", "mixed-or-retraced"], `${path}.presentedConstruction`);
}

function canonicalValue(value, path) {
  if (value === null || value === undefined) {
    fail("unsupported_json_value", path);
  }
  if (typeof value === "string" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) {
      fail("noncanonical_json_number", path);
    }
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((entry, index) => canonicalValue(entry, `${path}[${index}]`));
  }
  if (typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalValue(value[key], `${path}.${key}`)]),
    );
  }
  fail("unsupported_json_value", path);
}

function requireObject(value, path) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail("invalid_object", path);
  }
}

function requireExactFields(value, expected, path) {
  const actual = Object.keys(value);
  const missing = Array.from(expected).filter((key) => !actual.includes(key));
  const unknown = actual.filter((key) => !expected.has(key));
  if (missing.length > 0) {
    fail("missing_field", path, missing.sort().join(","));
  }
  if (unknown.length > 0) {
    fail("unknown_field", path, unknown.sort().join(","));
  }
}

function requireFixed(value, expected, path) {
  if (value !== expected) {
    fail("fixed_value_mismatch", path, `expected ${expected}`);
  }
}

function requirePrintableASCII(value, path, maximumBytes) {
  if (
    typeof value !== "string"
    || value.length === 0
    || textEncoder.encode(value).byteLength > maximumBytes
    || Array.from(value).some((character) => {
      const value = character.codePointAt(0);
      return value < 32 || value > 126;
    })
  ) {
    fail("invalid_printable_ascii", path);
  }
  return value;
}

function requireDisplayText(value, path) {
  if (
    typeof value !== "string"
    || value.length === 0
    || textEncoder.encode(value).byteLength > 256
    || value.normalize("NFC") !== value
    || Array.from(value).some((character) => {
      const scalar = character.codePointAt(0);
      return !(
        (scalar >= 0x20 && scalar <= 0x7E)
        || allowedDisplayTextNonASCIIScalars.has(scalar)
      );
    })
  ) {
    fail("invalid_display_text", path);
  }
}

function requireVersion(value, path) {
  requirePrintableASCII(value, path, 128);
  if (!versionPattern.test(value)) {
    fail("invalid_version", path);
  }
}

function requireSlug(value, path, maximumBytes) {
  requirePrintableASCII(value, path, maximumBytes);
  if (!slugPattern.test(value)) {
    fail("invalid_slug", path);
  }
}

function requireUUID(value, path) {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    fail("invalid_uuid", path);
  }
}

function requireSHA256(value, path) {
  if (typeof value !== "string" || !sha256Pattern.test(value)) {
    fail("invalid_sha256", path);
  }
}

function requireOneOf(value, choices, path) {
  if (!choices.includes(value)) {
    fail("invalid_enum", path, choices.join("|"));
  }
}

function requirePositiveSafeInteger(value, path) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    fail("invalid_positive_integer", path);
  }
}

function requireNonnegativeSafeInteger(value, path) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail("invalid_nonnegative_integer", path);
  }
}

function asUint8Array(value) {
  if (value instanceof Uint8Array) {
    return value;
  }
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  fail("invalid_binary_value", "binary");
}

function bytesToBase64(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function canonicalBase64Bytes(value, path) {
  if (typeof value !== "string" || value.length === 0) {
    fail("invalid_base64", path);
  }
  let bytes;
  try {
    const binary = atob(value);
    bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    fail("invalid_base64", path);
  }
  if (bytesToBase64(bytes) !== value) {
    fail("noncanonical_base64", path);
  }
  return bytes;
}

function fail(code, path, detail = "") {
  throw new RecognitionStudyCaptureGrantError(code, path, detail);
}
