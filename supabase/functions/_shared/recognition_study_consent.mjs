export const recognitionStudyConsentContract = Object.freeze({
  acceptRequestSchemaVersion: "recognition-study-consent-accept-request-v1",
  statusRequestSchemaVersion: "recognition-study-consent-status-request-v1",
  withdrawRequestSchemaVersion: "recognition-study-consent-withdraw-request-v1",
  responseSchemaVersion: "recognition-study-consent-response-v1",
  policySchemaVersion: "recognition-study-consent-policy-v1",
  consentSchemaVersion: "recognition-study-consent-record-summary-v1",
  maximumRequestBytes: 4 * 1_024,
});

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const sha256Pattern = /^[0-9a-f]{64}$/;
const presentationIDPattern = /^[a-z0-9][a-z0-9._-]{0,127}$/;
const acceptFields = new Set([
  "clientRequestID",
  "explicitRawStrokeDonationAuthorization",
  "presentationID",
  "presentationSHA256",
  "schemaVersion",
]);
const statusFields = new Set(["schemaVersion"]);
const withdrawFields = new Set(["clientRequestID", "consentRecordID", "schemaVersion"]);
const policyFields = new Set([
  "consentDocumentURL",
  "consentLedgerVersion",
  "consentTextVersion",
  "dataUsePolicyVersion",
  "presentationID",
  "presentationSHA256",
  "privacyNoticeVersion",
  "rawStrokeDonationRequired",
  "retentionPolicyVersion",
  "schemaVersion",
  "scope",
]);
const consentFields = new Set([
  "acceptedAtUnixMilliseconds",
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
  "status",
  "withdrawnAtUnixMilliseconds",
]);

export class RecognitionStudyConsentError extends Error {
  constructor(code, path) {
    super(`${code}:${path}`);
    this.name = "RecognitionStudyConsentError";
    this.code = code;
    this.path = path;
  }
}

export class RecognitionStudyConsentStoreError extends Error {
  constructor(disposition) {
    super(`recognition_study_consent_store_${disposition}`);
    this.name = "RecognitionStudyConsentStoreError";
    this.disposition = disposition;
  }
}

export async function handleRecognitionStudyConsentRequest(request, dependencies = {}) {
  if (request.method !== "POST") {
    return errorResponse(405, "Recognition Study consent requires POST.");
  }
  if (
    typeof dependencies.authenticatedUserID !== "function"
    || typeof dependencies.acceptConsent !== "function"
    || typeof dependencies.readConsentStatus !== "function"
    || typeof dependencies.withdrawConsent !== "function"
  ) {
    return errorResponse(501, "Recognition Study consent is not configured.");
  }

  let body;
  try {
    body = await readCanonicalJSON(request);
  } catch (error) {
    return errorResponse(
      error instanceof RecognitionStudyConsentError && error.code === "request_too_large"
        ? 413
        : 400,
      error instanceof RecognitionStudyConsentError && error.code === "request_too_large"
        ? "Consent request is too large."
        : "Consent request has an invalid contract.",
    );
  }

  let ownerID;
  try {
    ownerID = await dependencies.authenticatedUserID(request);
  } catch {
    return errorResponse(503, "Account verification is temporarily unavailable.");
  }
  if (typeof ownerID !== "string" || !uuidPattern.test(ownerID)) {
    return errorResponse(401, "A signed-in account is required.");
  }

  try {
    if (body.schemaVersion === recognitionStudyConsentContract.statusRequestSchemaVersion) {
      requireExactFields(body, statusFields, "request");
      const result = await dependencies.readConsentStatus(request);
      return publicConsentResponse(result, false);
    }
    if (body.schemaVersion === recognitionStudyConsentContract.acceptRequestSchemaVersion) {
      validateAcceptRequest(body);
      const result = await dependencies.acceptConsent(request, body);
      return publicConsentResponse(result, result?.replayed === true ? false : true);
    }
    if (body.schemaVersion === recognitionStudyConsentContract.withdrawRequestSchemaVersion) {
      validateWithdrawRequest(body);
      const result = await dependencies.withdrawConsent(request, body);
      return publicConsentResponse(result, false);
    }
    throw new RecognitionStudyConsentError("unknown_schema_version", "request.schemaVersion");
  } catch (error) {
    if (error instanceof RecognitionStudyConsentError) {
      return errorResponse(400, "Consent request has an invalid contract.");
    }
    if (error instanceof RecognitionStudyConsentStoreError) {
      if (error.disposition === "conflict") {
        return errorResponse(409, "Consent request conflicts with an existing record.");
      }
      if (error.disposition === "policy_unavailable") {
        return errorResponse(503, "No reviewed consent presentation is currently available.");
      }
      if (error.disposition === "not_found") {
        return errorResponse(404, "Consent record was not found.");
      }
    }
    return errorResponse(503, "Consent authority is temporarily unavailable.");
  }
}

function publicConsentResponse(value, created) {
  const normalized = validateStoreResponse(value);
  return canonicalResponse(created ? 201 : 200, {
    consent: normalized.consent,
    currentPolicy: normalized.currentPolicy,
    replayed: normalized.replayed,
    schemaVersion: recognitionStudyConsentContract.responseSchemaVersion,
    status: normalized.status,
  });
}

export function validateStoreResponse(value) {
  requireObject(value, "storeResponse");
  requireExactFields(
    value,
    new Set(["consent", "currentPolicy", "replayed", "schemaVersion", "status"]),
    "storeResponse",
  );
  if (value.schemaVersion !== "recognition-study-consent-store-response-v1") {
    throw new RecognitionStudyConsentError("fixed_value_mismatch", "storeResponse.schemaVersion");
  }
  if (!["not-accepted", "active", "withdrawn"].includes(value.status)) {
    throw new RecognitionStudyConsentError("invalid_status", "storeResponse.status");
  }
  if (typeof value.replayed !== "boolean") {
    throw new RecognitionStudyConsentError("invalid_boolean", "storeResponse.replayed");
  }
  if (value.currentPolicy !== null) {
    validatePolicy(value.currentPolicy);
  }
  if (value.consent !== null) {
    validateConsentSummary(value.consent);
    if (value.consent.status !== value.status) {
      throw new RecognitionStudyConsentError("status_mismatch", "storeResponse");
    }
  } else if (value.status !== "not-accepted") {
    throw new RecognitionStudyConsentError("missing_consent", "storeResponse.consent");
  }
  return value;
}

function validateAcceptRequest(value) {
  requireExactFields(value, acceptFields, "request");
  requireUUID(value.clientRequestID, "request.clientRequestID");
  requirePresentationID(value.presentationID, "request.presentationID");
  requireSHA256(value.presentationSHA256, "request.presentationSHA256");
  if (value.explicitRawStrokeDonationAuthorization !== true) {
    throw new RecognitionStudyConsentError(
      "raw_stroke_donation_not_authorized",
      "request.explicitRawStrokeDonationAuthorization",
    );
  }
}

function validateWithdrawRequest(value) {
  requireExactFields(value, withdrawFields, "request");
  requireUUID(value.clientRequestID, "request.clientRequestID");
  requireUUID(value.consentRecordID, "request.consentRecordID");
}

function validatePolicy(value) {
  requireObject(value, "policy");
  requireExactFields(value, policyFields, "policy");
  if (value.schemaVersion !== recognitionStudyConsentContract.policySchemaVersion) {
    throw new RecognitionStudyConsentError("fixed_value_mismatch", "policy.schemaVersion");
  }
  requirePresentationID(value.presentationID, "policy.presentationID");
  requireSHA256(value.presentationSHA256, "policy.presentationSHA256");
  requireHTTPSURL(value.consentDocumentURL, "policy.consentDocumentURL");
  for (const field of [
    "consentLedgerVersion",
    "consentTextVersion",
    "dataUsePolicyVersion",
    "privacyNoticeVersion",
    "retentionPolicyVersion",
    "scope",
  ]) {
    requirePresentationID(value[field], `policy.${field}`);
  }
  if (value.rawStrokeDonationRequired !== true) {
    throw new RecognitionStudyConsentError("fixed_value_mismatch", "policy.rawStrokeDonationRequired");
  }
}

function validateConsentSummary(value) {
  requireObject(value, "consent");
  requireExactFields(value, consentFields, "consent");
  if (value.schemaVersion !== recognitionStudyConsentContract.consentSchemaVersion) {
    throw new RecognitionStudyConsentError("fixed_value_mismatch", "consent.schemaVersion");
  }
  requireUUID(value.consentRecordID, "consent.consentRecordID");
  requireSHA256(value.consentRecordSHA256, "consent.consentRecordSHA256");
  requireNonnegativeInteger(value.acceptedAtUnixMilliseconds, "consent.acceptedAtUnixMilliseconds");
  requirePositiveInteger(value.consentLedgerEpoch, "consent.consentLedgerEpoch");
  for (const field of [
    "consentLedgerVersion",
    "consentTextVersion",
    "dataUsePolicyVersion",
    "privacyNoticeVersion",
    "retentionPolicyVersion",
    "scope",
  ]) {
    requirePresentationID(value[field], `consent.${field}`);
  }
  if (value.rawStrokeDonationAuthorized !== true) {
    throw new RecognitionStudyConsentError("invalid_boolean", "consent.rawStrokeDonationAuthorized");
  }
  if (!["active", "withdrawn"].includes(value.status)) {
    throw new RecognitionStudyConsentError("invalid_status", "consent.status");
  }
  if (value.status === "active" && value.withdrawnAtUnixMilliseconds !== null) {
    throw new RecognitionStudyConsentError("invalid_withdrawal_time", "consent.withdrawnAtUnixMilliseconds");
  }
  if (value.status === "withdrawn") {
    requireNonnegativeInteger(value.withdrawnAtUnixMilliseconds, "consent.withdrawnAtUnixMilliseconds");
  }
}

async function readCanonicalJSON(request) {
  const length = request.headers.get("content-length");
  if (length !== null && Number(length) > recognitionStudyConsentContract.maximumRequestBytes) {
    throw new RecognitionStudyConsentError("request_too_large", "request");
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > recognitionStudyConsentContract.maximumRequestBytes) {
    throw new RecognitionStudyConsentError("request_too_large", "request");
  }
  let text;
  let value;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    value = JSON.parse(text);
  } catch {
    throw new RecognitionStudyConsentError("invalid_json", "request");
  }
  requireObject(value, "request");
  if (consentCanonicalJSONString(value) !== text) {
    throw new RecognitionStudyConsentError("noncanonical_json", "request");
  }
  return value;
}

function canonicalResponse(status, value) {
  return new Response(consentCanonicalJSONBytes(value), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/vnd.ichart.recognition-study-consent+json",
    },
  });
}

function errorResponse(status, message) {
  return new Response(consentCanonicalJSONBytes({ error: message }), {
    status,
    headers: { "cache-control": "no-store", "content-type": "application/json" },
  });
}

function requireObject(value, path) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new RecognitionStudyConsentError("invalid_object", path);
  }
}

function requireExactFields(value, fields, path) {
  const actual = Object.keys(value).sort();
  const expected = [...fields].sort();
  if (actual.length !== expected.length
      || actual.some((field, index) => field !== expected[index])) {
    throw new RecognitionStudyConsentError("invalid_fields", path);
  }
}

function requireUUID(value, path) {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new RecognitionStudyConsentError("invalid_uuid", path);
  }
}

function requireSHA256(value, path) {
  if (typeof value !== "string" || !sha256Pattern.test(value)) {
    throw new RecognitionStudyConsentError("invalid_sha256", path);
  }
}

function requirePresentationID(value, path) {
  if (typeof value !== "string" || !presentationIDPattern.test(value)) {
    throw new RecognitionStudyConsentError("invalid_identifier", path);
  }
}

function requireHTTPSURL(value, path) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password || url.hash) {
      throw new Error("unsafe");
    }
  } catch {
    throw new RecognitionStudyConsentError("invalid_url", path);
  }
}

function requirePositiveInteger(value, path) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new RecognitionStudyConsentError("invalid_integer", path);
  }
}

function requireNonnegativeInteger(value, path) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RecognitionStudyConsentError("invalid_integer", path);
  }
}

export function consentCanonicalJSONString(value) {
  return consentCanonicalValue(value, "$", new Set());
}

export function consentCanonicalJSONBytes(value) {
  return new TextEncoder().encode(consentCanonicalJSONString(value));
}

function consentCanonicalValue(value, path, ancestors) {
  if (value === null) {
    return "null";
  }
  if (typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) {
      throw new RecognitionStudyConsentError("invalid_integer", path);
    }
    return String(value);
  }
  if (Array.isArray(value)) {
    if (ancestors.has(value)) {
      throw new RecognitionStudyConsentError("cyclic_json", path);
    }
    ancestors.add(value);
    const result = `[${value.map((item, index) =>
      consentCanonicalValue(item, `${path}[${index}]`, ancestors)).join(",")}]`;
    ancestors.delete(value);
    return result;
  }
  if (typeof value === "object") {
    if (ancestors.has(value)) {
      throw new RecognitionStudyConsentError("cyclic_json", path);
    }
    ancestors.add(value);
    const result = `{${Object.keys(value).sort().map((key) => {
      if (value[key] === undefined) {
        throw new RecognitionStudyConsentError("unsupported_json_value", `${path}.${key}`);
      }
      return `${JSON.stringify(key)}:${consentCanonicalValue(value[key], `${path}.${key}`, ancestors)}`;
    }).join(",")}}`;
    ancestors.delete(value);
    return result;
  }
  throw new RecognitionStudyConsentError("unsupported_json_value", path);
}
