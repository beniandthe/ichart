import {
  RecognitionStudyCaptureGrantError,
  canonicalJSONBytes,
  canonicalJSONString,
  createSignedCaptureGrant,
  signedCaptureGrantSHA256,
  validateSignedCaptureGrant,
} from "./recognition_study_capture_grant.mjs";

const requestSchemaVersion = "recognition-study-capture-grant-request-v1";
const grantMediaType = "application/vnd.ichart.recognition-study-capture-grant+json";
const maximumRequestBytes = 1_024;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export async function handleRecognitionStudyCaptureGrantRequest(
  request,
  dependencies = {},
) {
  if (request.method !== "POST") {
    return errorResponse(405, "Capture-grant issuance requires POST.");
  }
  const missing = [
    "authenticatedUserID",
    "prepareGrant",
    "commitGrant",
    "signPayload",
    "randomUUID",
    "nowUnixSeconds",
  ].filter((name) => typeof dependencies[name] !== "function");
  if (
    missing.length > 0
    || typeof dependencies.signingKeyID !== "string"
    || dependencies.promptPlan === undefined
  ) {
    return errorResponse(501, "Recognition Study authority is not configured.");
  }

  const body = await readJSON(request, maximumRequestBytes);
  if (!body.ok) {
    return errorResponse(
      body.tooLarge ? 413 : 400,
      body.tooLarge ? "Capture-grant request is too large." : "Request body must be valid JSON.",
    );
  }
  if (!isExactGrantRequest(body.value)) {
    return errorResponse(400, "Capture-grant request has an invalid contract.");
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

  let prepared;
  try {
    prepared = await dependencies.prepareGrant(ownerID);
  } catch {
    return errorResponse(503, "Capture authorization is temporarily unavailable.");
  }
  if (prepared === null || prepared === undefined) {
    return errorResponse(403, "Active raw-stroke research consent is required.");
  }

  try {
    const now = dependencies.nowUnixSeconds();
    const lifetime = normalizedGrantLifetime(dependencies.grantLifetimeSeconds);
    const payload = captureGrantPayload({
      prepared,
      promptPlan: dependencies.promptPlan,
      now,
      expiresAt: now + lifetime,
      randomUUID: dependencies.randomUUID,
    });
    const grant = await createSignedCaptureGrant({
      payload,
      signingKeyID: dependencies.signingKeyID,
      signPayload: dependencies.signPayload,
    });
    const digest = await signedCaptureGrantSHA256(grant);
    const stored = await dependencies.commitGrant({
      clientRequestID: body.value.clientRequestID,
      grant,
      ownerID,
      signedGrantSHA256: digest,
    });
    const servedGrant = stored?.signedGrant ?? grant;
    const servedDigest = await signedCaptureGrantSHA256(servedGrant);
    if (
      stored?.status !== "issued"
      || servedGrant?.payload?.notBeforeUnixSeconds > now
      || servedGrant?.payload?.expiresAtUnixSeconds <= now
      || typeof stored?.signedGrantSHA256 !== "string"
      || stored.signedGrantSHA256 !== servedDigest
    ) {
      return errorResponse(503, "Capture authorization could not be committed.");
    }
    validateSignedCaptureGrant(servedGrant);
    return new Response(canonicalJSONBytes(servedGrant), {
      status: stored?.stored === false ? 200 : 201,
      headers: {
        "cache-control": "no-store",
        "content-type": grantMediaType,
        "x-ichart-authority-artifact-sha256": servedDigest,
      },
    });
  } catch (error) {
    if (error instanceof RecognitionStudyCaptureGrantError) {
      return errorResponse(500, "Capture authority contract is invalid.");
    }
    return errorResponse(503, "Capture authorization is temporarily unavailable.");
  }
}

export function captureGrantPayload({
  prepared,
  promptPlan,
  now,
  expiresAt,
  randomUUID,
}) {
  if (!Number.isSafeInteger(now) || now < 0) {
    throw new RecognitionStudyCaptureGrantError("invalid_timestamp", "now");
  }
  if (!Number.isSafeInteger(expiresAt) || expiresAt <= now) {
    throw new RecognitionStudyCaptureGrantError("invalid_timestamp", "expiresAt");
  }
  if (
    prepared === null
    || typeof prepared !== "object"
    || !Number.isSafeInteger(prepared.authorizationEpoch)
    || prepared.authorizationEpoch <= 0
    || prepared.consentBinding === null
    || typeof prepared.consentBinding !== "object"
  ) {
    throw new RecognitionStudyCaptureGrantError("invalid_prepared_grant", "prepared");
  }
  if (
    promptPlan === null
    || typeof promptPlan !== "object"
    || !Array.isArray(promptPlan.captureTickets)
  ) {
    throw new RecognitionStudyCaptureGrantError("invalid_prompt_plan", "promptPlan");
  }
  requireExactKeys(
    promptPlan,
    ["captureTickets", "datasetVersion", "minimumBuildNumber", "promptPlanVersion"],
    "promptPlan",
  );

  const tickets = promptPlan.captureTickets.map((ticket, ordinal) => {
    requireExactKeys(
      ticket,
      [
        "displayText",
        "presentedChartStyle",
        "presentedConstruction",
        "presentedPace",
        "presentedSize",
        "promptID",
        "promptKind",
        "requestedOrientation",
      ],
      `promptPlan.captureTickets[${ordinal}]`,
    );
    return {
      captureAuthorizationID: randomUUID(),
      displayText: ticket.displayText,
      ordinal,
      presentedChartStyle: ticket.presentedChartStyle,
      presentedConstruction: ticket.presentedConstruction,
      presentedPace: ticket.presentedPace,
      presentedSize: ticket.presentedSize,
      promptID: ticket.promptID,
      promptKind: ticket.promptKind,
      requestedOrientation: ticket.requestedOrientation,
    };
  });
  return {
    artifactKind: "externally-authorized-session-grant-v1",
    authorizationEpoch: prepared.authorizationEpoch,
    authorizationID: randomUUID(),
    captureTickets: tickets,
    clientRequirements: {
      captureContractVersion: "recognition-study-authorized-capture-v1",
      expectedBundleIdentifier: "com.ichart.recognitionstudy",
      minimumBuildNumber: promptPlan.minimumBuildNumber,
    },
    collectionProtocolVersion: "writer-independent-capture-v2",
    consentBinding: prepared.consentBinding,
    datasetVersion: promptPlan.datasetVersion,
    expectedCaptureCount: tickets.length,
    expiresAtUnixSeconds: expiresAt,
    issuedAtUnixSeconds: now,
    notBeforeUnixSeconds: now,
    promptPlanVersion: promptPlan.promptPlanVersion,
    schemaVersion: "recognition-study-capture-grant-v1",
    serviceSessionID: randomUUID(),
  };
}

function isExactGrantRequest(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const keys = Object.keys(value).sort();
  return keys.length === 2
    && keys[0] === "clientRequestID"
    && keys[1] === "schemaVersion"
    && value.schemaVersion === requestSchemaVersion
    && typeof value.clientRequestID === "string"
    && uuidPattern.test(value.clientRequestID);
}

function normalizedGrantLifetime(value) {
  if (value === undefined) {
    return 3_600;
  }
  if (!Number.isSafeInteger(value) || value < 60 || value > 86_400) {
    throw new RecognitionStudyCaptureGrantError("invalid_grant_lifetime", "grantLifetimeSeconds");
  }
  return value;
}

function requireExactKeys(value, expectedKeys, path) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new RecognitionStudyCaptureGrantError("invalid_object", path);
  }
  const actual = Object.keys(value).sort();
  const expected = [...expectedKeys].sort();
  if (
    actual.length !== expected.length
    || actual.some((key, index) => key !== expected[index])
  ) {
    throw new RecognitionStudyCaptureGrantError("invalid_fields", path);
  }
}

async function readJSON(request, maximumBytes) {
  const contentLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > maximumBytes) {
    return { ok: false, tooLarge: true };
  }
  let bytes;
  try {
    bytes = new Uint8Array(await request.arrayBuffer());
  } catch {
    return { ok: false, tooLarge: false };
  }
  if (bytes.byteLength > maximumBytes) {
    return { ok: false, tooLarge: true };
  }
  try {
    return { ok: true, value: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) };
  } catch {
    return { ok: false, tooLarge: false };
  }
}

function errorResponse(status, error) {
  return new Response(canonicalJSONString({ accepted: false, error }), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}
