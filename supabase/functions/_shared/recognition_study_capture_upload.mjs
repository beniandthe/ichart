import {
  RecognitionStudyCaptureGrantError,
  canonicalJSONBytes,
  canonicalJSONString,
  signedCaptureGrantSHA256,
  validateSignedCaptureGrant,
} from "./recognition_study_capture_grant.mjs";

const textDecoder = new TextDecoder("utf-8", { fatal: true });
const textEncoder = new TextEncoder();

export const recognitionStudyCaptureUploadContract = Object.freeze({
  requestSchemaVersion: "recognition-study-capture-upload-request-v1",
  envelopeSchemaVersion: "recognition-study-authorized-capture-envelope-v1",
  envelopeArtifactKind: "externally-authorized-trajectory-v1",
  receiptSchemaVersion: "recognition-study-capture-receipt-v1",
  surfaceVersion: "recognition-study-presented-surface-v1",
  trajectoryDescriptorSchemaVersion: "recognition-study-trajectory-descriptor-v1",
  packetFormatVersion: "ink-trajectory-packet-v1",
  coordinateSpace: "transformed-prepared-drawing",
  maximumRequestBytes: 6 * 1024 * 1024,
  maximumEnvelopeBytes: 64 * 1024,
  maximumPacketBytes: 4 * 1024 * 1024,
  maximumStrokeCount: 256,
  maximumPointsPerStroke: 8_192,
  maximumPointCount: 32_768,
});

const requestFields = new Set([
  "canonicalPacketBase64",
  "envelope",
  "schemaVersion",
  "signedGrant",
]);
const envelopeFields = new Set([
  "artifactKind",
  "captureAuthorizationID",
  "clientAppContext",
  "clientCapturedAtUnixMilliseconds",
  "clientObservedSurface",
  "grantAuthorizationID",
  "schemaVersion",
  "serviceSessionID",
  "signedGrantSHA256",
  "ticketOrdinal",
  "trajectoryDescriptor",
]);
const clientContextFields = new Set([
  "appVersion",
  "buildNumber",
  "bundleIdentifier",
  "operatingSystemMajorVersion",
  "operatingSystemMinorVersion",
]);
const surfaceFields = new Set([
  "canvasHeight",
  "canvasWidth",
  "clientObservedOrientation",
  "presentedChartStyle",
  "presentedConstructionInstruction",
  "presentedPaceInstruction",
  "presentedSizeInstruction",
  "surfaceVersion",
]);
const descriptorFields = new Set([
  "canonicalPacketByteCount",
  "canonicalPacketSHA256",
  "containsNonFiniteTiming",
  "coordinateSpace",
  "creationTimingCoverage",
  "emptyStrokeCount",
  "overallTimingCoverage",
  "packetFormatVersion",
  "pointCount",
  "pointTimingCoverage",
  "schemaVersion",
  "strokeCount",
]);
const packetFields = new Set(["coordinateSpace", "formatVersion", "strokes"]);
const strokeFields = new Set(["bounds", "creationTimeOffset", "points"]);
const boundsFields = new Set(["maxX", "maxY", "minX", "minY"]);
const pointFields = new Set(["timeOffset", "x", "y"]);
const missingTimingFields = new Set(["state"]);
const presentTimingFields = new Set(["bitPattern", "state"]);

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const sha256Pattern = /^[0-9a-f]{64}$/;
const bitPattern = /^[0-9a-f]{16}$/;
const decimalBuildPattern = /^(?:0|[1-9][0-9]*)$/;
const canonicalBase64Pattern = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

export class RecognitionStudyCaptureUploadError extends Error {
  constructor(code, path, detail = "") {
    super(`${code}:${path}${detail.length > 0 ? `:${detail}` : ""}`);
    this.name = "RecognitionStudyCaptureUploadError";
    this.code = code;
    this.path = path;
    this.detail = detail;
  }
}

export class RecognitionStudyCaptureConsumeError extends Error {
  constructor(disposition) {
    super(`capture_consume_${disposition}`);
    this.name = "RecognitionStudyCaptureConsumeError";
    this.disposition = disposition;
  }
}

export async function handleRecognitionStudyCaptureUploadRequest(
  request,
  dependencies = {},
) {
  if (request.method !== "POST") {
    return errorResponse(405, "Capture upload requires POST.");
  }
  const missing = ["authenticatedUserID", "consumeCapture", "nowUnixSeconds"]
    .filter((name) => typeof dependencies[name] !== "function");
  if (missing.length > 0) {
    return errorResponse(501, "Recognition Study capture upload is not configured.");
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
    const requestValue = await decodeCanonicalCaptureUploadRequest(request);
    prepared = await prepareRecognitionStudyCaptureUpload({
      requestValue,
      nowUnixSeconds: dependencies.nowUnixSeconds(),
      subtle: dependencies.subtle ?? globalThis.crypto?.subtle,
    });
  } catch (error) {
    if (error instanceof RecognitionStudyCaptureUploadError
        || error instanceof RecognitionStudyCaptureGrantError) {
      const tooLarge = error.code === "request_too_large";
      return errorResponse(
        tooLarge ? 413 : 400,
        tooLarge
          ? "Capture upload is too large."
          : "Capture upload has an invalid contract.",
      );
    }
    return errorResponse(400, "Capture upload has an invalid contract.");
  }

  let receipt;
  try {
    receipt = await dependencies.consumeCapture({
      ownerID,
      captureAuthorizationID: prepared.envelope.captureAuthorizationID,
      signedGrantSHA256: prepared.signedGrantSHA256,
      envelope: prepared.envelope,
      envelopeSHA256: prepared.envelopeSHA256,
      canonicalPacketBase64: prepared.canonicalPacketBase64,
      canonicalPacketSHA256: prepared.canonicalPacketSHA256,
      canonicalPacketByteCount: prepared.canonicalPacketBytes.byteLength,
    });
    validateCaptureReceipt(receipt, prepared);
  } catch (error) {
    if (error instanceof RecognitionStudyCaptureConsumeError) {
      if (error.disposition === "inactive") {
        return errorResponse(410, "Capture authorization is no longer active.");
      }
      if (error.disposition === "conflict") {
        return errorResponse(409, "Capture ticket was already used.");
      }
    }
    return errorResponse(503, "Capture upload is temporarily unavailable.");
  }

  return new Response(canonicalJSONBytes(receipt), {
    status: receipt.replayed ? 200 : 201,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/vnd.ichart.recognition-study-capture-receipt+json",
      "x-ichart-capture-receipt-id": receipt.receiptID,
    },
  });
}

export async function decodeCanonicalCaptureUploadRequest(requestOrBytes) {
  const bytes = requestOrBytes instanceof Request
    ? await readRequestBytes(
      requestOrBytes,
      recognitionStudyCaptureUploadContract.maximumRequestBytes,
    )
    : asUint8Array(requestOrBytes);
  if (bytes.byteLength > recognitionStudyCaptureUploadContract.maximumRequestBytes) {
    fail("request_too_large", "request", String(bytes.byteLength));
  }
  let text;
  let value;
  try {
    text = textDecoder.decode(bytes);
    value = JSON.parse(text);
  } catch {
    fail("invalid_json", "request");
  }
  requireObject(value, "request");
  requireExactFields(value, requestFields, "request");
  requireFixed(
    value.schemaVersion,
    recognitionStudyCaptureUploadContract.requestSchemaVersion,
    "request.schemaVersion",
  );
  validateSignedCaptureGrant(value.signedGrant);
  validateAuthorizedCaptureEnvelope(value.envelope);
  requireCanonicalBase64(value.canonicalPacketBase64, "request.canonicalPacketBase64");
  if (canonicalJSONString(value) !== text) {
    fail("noncanonical_json", "request");
  }
  return value;
}

export async function prepareRecognitionStudyCaptureUpload({
  requestValue,
  nowUnixSeconds,
  subtle = globalThis.crypto?.subtle,
}) {
  requireNonnegativeSafeInteger(nowUnixSeconds, "nowUnixSeconds");
  if (subtle === undefined) {
    fail("missing_crypto_runtime", "crypto.subtle");
  }
  validateSignedCaptureGrant(requestValue.signedGrant);
  validateAuthorizedCaptureEnvelope(requestValue.envelope);

  const grant = requestValue.signedGrant;
  const envelope = requestValue.envelope;
  // Expiry is enforced atomically by the consume RPC. Let an expired exact
  // retry reach that RPC so a client that lost the original response can
  // recover its immutable receipt; new or conflicting bytes still fail there.
  if (nowUnixSeconds < grant.payload.notBeforeUnixSeconds) {
    fail("authorization_not_active", "signedGrant.payload");
  }
  const signedGrantSHA256 = await signedCaptureGrantSHA256(grant);
  if (envelope.signedGrantSHA256 !== signedGrantSHA256) {
    fail("signed_grant_digest_mismatch", "envelope.signedGrantSHA256");
  }
  if (
    envelope.grantAuthorizationID !== grant.payload.authorizationID
    || envelope.serviceSessionID !== grant.payload.serviceSessionID
  ) {
    fail("grant_binding_mismatch", "envelope");
  }

  const ticket = grant.payload.captureTickets[envelope.ticketOrdinal];
  if (
    ticket === undefined
    || ticket.captureAuthorizationID !== envelope.captureAuthorizationID
    || ticket.ordinal !== envelope.ticketOrdinal
  ) {
    fail("ticket_binding_mismatch", "envelope.captureAuthorizationID");
  }
  const clientCapturedAtUnixSeconds = Math.floor(
    envelope.clientCapturedAtUnixMilliseconds / 1_000,
  );
  if (
    clientCapturedAtUnixSeconds < grant.payload.notBeforeUnixSeconds
    || clientCapturedAtUnixSeconds >= grant.payload.expiresAtUnixSeconds
  ) {
    fail(
      "capture_outside_grant_validity_window",
      "envelope.clientCapturedAtUnixMilliseconds",
    );
  }
  validateClientBinding(envelope.clientAppContext, grant.payload.clientRequirements);
  validateSurfaceBinding(envelope.clientObservedSurface, ticket);

  const canonicalPacketBytes = canonicalBase64Bytes(
    requestValue.canonicalPacketBase64,
    "request.canonicalPacketBase64",
  );
  if (
    canonicalPacketBytes.byteLength === 0
    || canonicalPacketBytes.byteLength
      > recognitionStudyCaptureUploadContract.maximumPacketBytes
  ) {
    fail(
      "packet_too_large",
      "request.canonicalPacketBase64",
      String(canonicalPacketBytes.byteLength),
    );
  }
  const packet = decodeCanonicalTrajectoryPacket(canonicalPacketBytes);
  const canonicalPacketSHA256 = await sha256Hex(canonicalPacketBytes, subtle);
  const derivedDescriptor = deriveTrajectoryDescriptor(
    packet,
    canonicalPacketSHA256,
    canonicalPacketBytes.byteLength,
  );
  if (canonicalJSONString(derivedDescriptor)
      !== canonicalJSONString(envelope.trajectoryDescriptor)) {
    fail("trajectory_descriptor_mismatch", "envelope.trajectoryDescriptor");
  }

  const envelopeBytes = canonicalJSONBytes(envelope);
  if (envelopeBytes.byteLength
      > recognitionStudyCaptureUploadContract.maximumEnvelopeBytes) {
    fail("envelope_too_large", "envelope", String(envelopeBytes.byteLength));
  }
  return Object.freeze({
    canonicalPacketBase64: requestValue.canonicalPacketBase64,
    canonicalPacketBytes,
    canonicalPacketSHA256,
    envelope,
    envelopeSHA256: await sha256Hex(envelopeBytes, subtle),
    signedGrantSHA256,
  });
}

export function validateAuthorizedCaptureEnvelope(value) {
  requireObject(value, "envelope");
  requireExactFields(value, envelopeFields, "envelope");
  requireFixed(
    value.schemaVersion,
    recognitionStudyCaptureUploadContract.envelopeSchemaVersion,
    "envelope.schemaVersion",
  );
  requireFixed(
    value.artifactKind,
    recognitionStudyCaptureUploadContract.envelopeArtifactKind,
    "envelope.artifactKind",
  );
  requireUUID(value.grantAuthorizationID, "envelope.grantAuthorizationID");
  requireUUID(value.serviceSessionID, "envelope.serviceSessionID");
  requireUUID(value.captureAuthorizationID, "envelope.captureAuthorizationID");
  requireNonnegativeSafeInteger(value.ticketOrdinal, "envelope.ticketOrdinal");
  requireSHA256(value.signedGrantSHA256, "envelope.signedGrantSHA256");
  requireNonnegativeSafeInteger(
    value.clientCapturedAtUnixMilliseconds,
    "envelope.clientCapturedAtUnixMilliseconds",
  );
  validateClientAppContext(value.clientAppContext);
  validatePresentedSurface(value.clientObservedSurface);
  validateTrajectoryDescriptor(value.trajectoryDescriptor);
  if (canonicalJSONBytes(value).byteLength
      > recognitionStudyCaptureUploadContract.maximumEnvelopeBytes) {
    fail("envelope_too_large", "envelope");
  }
  return value;
}

export function decodeCanonicalTrajectoryPacket(bytesValue) {
  const bytes = asUint8Array(bytesValue);
  if (
    bytes.byteLength === 0
    || bytes.byteLength > recognitionStudyCaptureUploadContract.maximumPacketBytes
  ) {
    fail("packet_too_large", "packet", String(bytes.byteLength));
  }
  let text;
  let packet;
  try {
    text = textDecoder.decode(bytes);
    packet = JSON.parse(text);
  } catch {
    fail("invalid_json", "packet");
  }
  requireObject(packet, "packet");
  requireExactFields(packet, packetFields, "packet");
  requireFixed(
    packet.formatVersion,
    recognitionStudyCaptureUploadContract.packetFormatVersion,
    "packet.formatVersion",
  );
  requireFixed(
    packet.coordinateSpace,
    recognitionStudyCaptureUploadContract.coordinateSpace,
    "packet.coordinateSpace",
  );
  if (!Array.isArray(packet.strokes)) {
    fail("invalid_array", "packet.strokes");
  }
  if (packet.strokes.length
      > recognitionStudyCaptureUploadContract.maximumStrokeCount) {
    fail("too_many_strokes", "packet.strokes");
  }
  let pointCount = 0;
  for (const [strokeIndex, stroke] of packet.strokes.entries()) {
    const path = `packet.strokes[${strokeIndex}]`;
    requireObject(stroke, path);
    requireExactFields(stroke, strokeFields, path);
    validateBounds(stroke.bounds, `${path}.bounds`);
    validateTimingValue(stroke.creationTimeOffset, `${path}.creationTimeOffset`);
    if (!Array.isArray(stroke.points)) {
      fail("invalid_array", `${path}.points`);
    }
    if (stroke.points.length
        > recognitionStudyCaptureUploadContract.maximumPointsPerStroke) {
      fail("too_many_points", `${path}.points`);
    }
    pointCount += stroke.points.length;
    if (pointCount > recognitionStudyCaptureUploadContract.maximumPointCount) {
      fail("too_many_points", "packet.strokes");
    }
    for (const [pointIndex, point] of stroke.points.entries()) {
      validatePoint(point, `${path}.points[${pointIndex}]`);
    }
  }
  if (canonicalJSONString(packet) !== text) {
    fail("noncanonical_json", "packet");
  }
  return packet;
}

export function deriveTrajectoryDescriptor(packet, packetSHA256, packetByteCount) {
  requireSHA256(packetSHA256, "packetSHA256");
  requirePositiveSafeInteger(packetByteCount, "packetByteCount");
  let emptyStrokeCount = 0;
  let pointCount = 0;
  const pointTimings = [];
  const creationTimings = [];
  let containsNonFiniteTiming = false;
  for (const stroke of packet.strokes) {
    if (stroke.points.length === 0) {
      emptyStrokeCount += 1;
    }
    pointCount += stroke.points.length;
    creationTimings.push(stroke.creationTimeOffset);
    if (stroke.creationTimeOffset.state === "nonFinite") {
      containsNonFiniteTiming = true;
    }
    for (const point of stroke.points) {
      pointTimings.push(point.timeOffset);
      if (point.timeOffset.state === "nonFinite") {
        containsNonFiniteTiming = true;
      }
    }
  }
  return {
    canonicalPacketByteCount: packetByteCount,
    canonicalPacketSHA256: packetSHA256,
    containsNonFiniteTiming,
    coordinateSpace: recognitionStudyCaptureUploadContract.coordinateSpace,
    creationTimingCoverage: timingCoverage(creationTimings),
    emptyStrokeCount,
    overallTimingCoverage: timingCoverage([...creationTimings, ...pointTimings]),
    packetFormatVersion: recognitionStudyCaptureUploadContract.packetFormatVersion,
    pointCount,
    pointTimingCoverage: timingCoverage(pointTimings),
    schemaVersion:
      recognitionStudyCaptureUploadContract.trajectoryDescriptorSchemaVersion,
    strokeCount: packet.strokes.length,
  };
}

export async function sha256Hex(bytesValue, subtle = globalThis.crypto?.subtle) {
  if (subtle === undefined) {
    fail("missing_crypto_runtime", "crypto.subtle");
  }
  const bytes = asUint8Array(bytesValue);
  const digest = new Uint8Array(await subtle.digest("SHA-256", bytes));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function validateClientAppContext(value) {
  requireObject(value, "envelope.clientAppContext");
  requireExactFields(value, clientContextFields, "envelope.clientAppContext");
  requirePrintableASCII(
    value.bundleIdentifier,
    "envelope.clientAppContext.bundleIdentifier",
    64,
  );
  requirePrintableASCII(value.appVersion, "envelope.clientAppContext.appVersion", 32);
  requirePrintableASCII(value.buildNumber, "envelope.clientAppContext.buildNumber", 32);
  requireCanonicalBuild(value.buildNumber, "envelope.clientAppContext.buildNumber");
  requireIntegerRange(
    value.operatingSystemMajorVersion,
    1,
    65_535,
    "envelope.clientAppContext.operatingSystemMajorVersion",
  );
  requireIntegerRange(
    value.operatingSystemMinorVersion,
    0,
    65_535,
    "envelope.clientAppContext.operatingSystemMinorVersion",
  );
}

function validatePresentedSurface(value) {
  const path = "envelope.clientObservedSurface";
  requireObject(value, path);
  requireExactFields(value, surfaceFields, path);
  requireFixed(
    value.surfaceVersion,
    recognitionStudyCaptureUploadContract.surfaceVersion,
    `${path}.surfaceVersion`,
  );
  requireOneOf(
    value.presentedChartStyle,
    ["simple-chord-sheet", "rhythm-section-sheet"],
    `${path}.presentedChartStyle`,
  );
  requireOneOf(
    value.clientObservedOrientation,
    ["portrait", "landscape"],
    `${path}.clientObservedOrientation`,
  );
  validatePositiveFiniteBitPattern(value.canvasWidth, `${path}.canvasWidth`);
  validatePositiveFiniteBitPattern(value.canvasHeight, `${path}.canvasHeight`);
  requireOneOf(
    value.presentedPaceInstruction,
    ["natural", "fast", "careful"],
    `${path}.presentedPaceInstruction`,
  );
  requireOneOf(
    value.presentedSizeInstruction,
    ["small", "normal", "large"],
    `${path}.presentedSizeInstruction`,
  );
  requireOneOf(
    value.presentedConstructionInstruction,
    ["root-first", "modifier-first", "mixed-or-retraced"],
    `${path}.presentedConstructionInstruction`,
  );
}

function validateTrajectoryDescriptor(value) {
  const path = "envelope.trajectoryDescriptor";
  requireObject(value, path);
  requireExactFields(value, descriptorFields, path);
  requireFixed(
    value.schemaVersion,
    recognitionStudyCaptureUploadContract.trajectoryDescriptorSchemaVersion,
    `${path}.schemaVersion`,
  );
  requireFixed(
    value.packetFormatVersion,
    recognitionStudyCaptureUploadContract.packetFormatVersion,
    `${path}.packetFormatVersion`,
  );
  requireFixed(
    value.coordinateSpace,
    recognitionStudyCaptureUploadContract.coordinateSpace,
    `${path}.coordinateSpace`,
  );
  requireSHA256(value.canonicalPacketSHA256, `${path}.canonicalPacketSHA256`);
  requireIntegerRange(
    value.canonicalPacketByteCount,
    1,
    recognitionStudyCaptureUploadContract.maximumPacketBytes,
    `${path}.canonicalPacketByteCount`,
  );
  requireIntegerRange(
    value.strokeCount,
    0,
    recognitionStudyCaptureUploadContract.maximumStrokeCount,
    `${path}.strokeCount`,
  );
  requireIntegerRange(
    value.emptyStrokeCount,
    0,
    value.strokeCount,
    `${path}.emptyStrokeCount`,
  );
  requireIntegerRange(
    value.pointCount,
    0,
    recognitionStudyCaptureUploadContract.maximumPointCount,
    `${path}.pointCount`,
  );
  for (const key of [
    "pointTimingCoverage",
    "creationTimingCoverage",
    "overallTimingCoverage",
  ]) {
    requireOneOf(value[key], ["unavailable", "partial", "complete"], `${path}.${key}`);
  }
  if (typeof value.containsNonFiniteTiming !== "boolean") {
    fail("invalid_boolean", `${path}.containsNonFiniteTiming`);
  }
}

function validateClientBinding(clientContext, requirements) {
  if (clientContext.bundleIdentifier !== requirements.expectedBundleIdentifier) {
    fail("bundle_identifier_mismatch", "envelope.clientAppContext.bundleIdentifier");
  }
  const build = requireCanonicalBuild(
    clientContext.buildNumber,
    "envelope.clientAppContext.buildNumber",
  );
  if (build < requirements.minimumBuildNumber) {
    fail("build_below_minimum", "envelope.clientAppContext.buildNumber");
  }
}

function validateSurfaceBinding(surface, ticket) {
  const comparisons = [
    [surface.presentedChartStyle, ticket.presentedChartStyle],
    [surface.clientObservedOrientation, ticket.requestedOrientation],
    [surface.presentedPaceInstruction, ticket.presentedPace],
    [surface.presentedSizeInstruction, ticket.presentedSize],
    [surface.presentedConstructionInstruction, ticket.presentedConstruction],
  ];
  if (comparisons.some(([actual, expected]) => actual !== expected)) {
    fail("surface_ticket_mismatch", "envelope.clientObservedSurface");
  }
}

function validateBounds(value, path) {
  requireObject(value, path);
  requireExactFields(value, boundsFields, path);
  for (const key of boundsFields) {
    validateGeometryValue(value[key], `${path}.${key}`);
  }
}

function validatePoint(value, path) {
  requireObject(value, path);
  requireExactFields(value, pointFields, path);
  validateGeometryValue(value.x, `${path}.x`);
  validateGeometryValue(value.y, `${path}.y`);
  validateTimingValue(value.timeOffset, `${path}.timeOffset`);
}

function validateGeometryValue(value, path) {
  if (typeof value !== "string" || !bitPattern.test(value)) {
    fail("invalid_bit_pattern", path);
  }
  if (!hexDouble(value).finite) {
    fail("nonfinite_geometry", path);
  }
}

function validatePositiveFiniteBitPattern(value, path) {
  validateGeometryValue(value, path);
  if (hexDouble(value).value <= 0) {
    fail("invalid_positive_number", path);
  }
}

function validateTimingValue(value, path) {
  requireObject(value, path);
  if (value.state === "missing") {
    requireExactFields(value, missingTimingFields, path);
    return;
  }
  if (value.state !== "finite" && value.state !== "nonFinite") {
    fail("invalid_timing_state", `${path}.state`);
  }
  requireExactFields(value, presentTimingFields, path);
  if (typeof value.bitPattern !== "string" || !bitPattern.test(value.bitPattern)) {
    fail("invalid_bit_pattern", `${path}.bitPattern`);
  }
  const isFinite = hexDouble(value.bitPattern).finite;
  if (isFinite !== (value.state === "finite")) {
    fail("timing_state_mismatch", path);
  }
}

function hexDouble(value) {
  const buffer = new ArrayBuffer(8);
  const view = new DataView(buffer);
  view.setBigUint64(0, BigInt(`0x${value}`), false);
  const decoded = view.getFloat64(0, false);
  return { finite: Number.isFinite(decoded), value: decoded };
}

function timingCoverage(values) {
  if (values.length === 0) {
    return "unavailable";
  }
  const available = values.filter((value) => value.state !== "missing").length;
  if (available === 0) {
    return "unavailable";
  }
  return available === values.length ? "complete" : "partial";
}

function validateCaptureReceipt(value, prepared) {
  requireObject(value, "receipt");
  requireExactFields(value, new Set([
    "accepted",
    "canonicalPacketByteCount",
    "canonicalPacketSHA256",
    "captureAuthorizationID",
    "envelopeSHA256",
    "grantCompleted",
    "receiptID",
    "receivedAtUnixMilliseconds",
    "replayed",
    "schemaVersion",
  ]), "receipt");
  requireFixed(
    value.schemaVersion,
    recognitionStudyCaptureUploadContract.receiptSchemaVersion,
    "receipt.schemaVersion",
  );
  if (value.accepted !== true
      || typeof value.replayed !== "boolean"
      || typeof value.grantCompleted !== "boolean") {
    fail("invalid_receipt_state", "receipt");
  }
  requireUUID(value.receiptID, "receipt.receiptID");
  requireUUID(value.captureAuthorizationID, "receipt.captureAuthorizationID");
  requireNonnegativeSafeInteger(
    value.receivedAtUnixMilliseconds,
    "receipt.receivedAtUnixMilliseconds",
  );
  if (
    value.captureAuthorizationID !== prepared.envelope.captureAuthorizationID
    || value.envelopeSHA256 !== prepared.envelopeSHA256
    || value.canonicalPacketSHA256 !== prepared.canonicalPacketSHA256
    || value.canonicalPacketByteCount !== prepared.canonicalPacketBytes.byteLength
  ) {
    fail("receipt_binding_mismatch", "receipt");
  }
}

async function readRequestBytes(request, maximumBytes) {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    fail("request_too_large", "request", String(declaredLength));
  }
  if (request.body === null) {
    fail("missing_body", "request");
  }
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      const chunk = asUint8Array(value);
      total += chunk.byteLength;
      if (total > maximumBytes) {
        await reader.cancel("request too large");
        fail("request_too_large", "request", String(total));
      }
      chunks.push(chunk);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function canonicalBase64Bytes(value, path) {
  requireCanonicalBase64(value, path);
  let binary;
  try {
    binary = atob(value);
  } catch {
    fail("invalid_base64", path);
  }
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  if (bytesToBase64(bytes) !== value) {
    fail("noncanonical_base64", path);
  }
  return bytes;
}

function requireCanonicalBase64(value, path) {
  if (typeof value !== "string" || !canonicalBase64Pattern.test(value)) {
    fail("invalid_base64", path);
  }
}

function bytesToBase64(bytes) {
  const chunks = [];
  const chunkSize = 32_768;
  for (let offset = 0; offset < bytes.byteLength; offset += chunkSize) {
    chunks.push(String.fromCharCode(...bytes.subarray(offset, offset + chunkSize)));
  }
  return btoa(chunks.join(""));
}

function requireCanonicalBuild(value, path) {
  if (typeof value !== "string" || !decimalBuildPattern.test(value)) {
    fail("invalid_build_number", path);
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    fail("invalid_build_number", path);
  }
  return parsed;
}

function requireObject(value, path) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail("invalid_object", path);
  }
}

function requireExactFields(value, expected, path) {
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (
    actual.length !== wanted.length
    || actual.some((field, index) => field !== wanted[index])
  ) {
    fail("invalid_fields", path);
  }
}

function requireFixed(value, expected, path) {
  if (value !== expected) {
    fail("fixed_value_mismatch", path, String(value));
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

function requirePrintableASCII(value, path, maximumBytes) {
  if (
    typeof value !== "string"
    || value.length === 0
    || textEncoder.encode(value).byteLength > maximumBytes
    || Array.from(value).some((character) => {
      const scalar = character.codePointAt(0);
      return scalar < 0x20 || scalar > 0x7e;
    })
  ) {
    fail("invalid_printable_ascii", path);
  }
}

function requireOneOf(value, choices, path) {
  if (!choices.includes(value)) {
    fail("invalid_enum", path);
  }
}

function requireNonnegativeSafeInteger(value, path) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail("invalid_nonnegative_integer", path);
  }
}

function requirePositiveSafeInteger(value, path) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    fail("invalid_positive_integer", path);
  }
}

function requireIntegerRange(value, minimum, maximum, path) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    fail("integer_out_of_range", path);
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

function errorResponse(status, error) {
  return new Response(canonicalJSONString({ accepted: false, error }), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function fail(code, path, detail = "") {
  throw new RecognitionStudyCaptureUploadError(code, path, detail);
}
