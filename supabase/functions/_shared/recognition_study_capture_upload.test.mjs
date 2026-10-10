import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  canonicalJSONString,
  signedCaptureGrantSHA256,
} from "./recognition_study_capture_grant.mjs";
import {
  RecognitionStudyCaptureConsumeError,
  RecognitionStudyCaptureUploadError,
  decodeCanonicalTrajectoryPacket,
  decodeCanonicalCaptureUploadRequest,
  deriveTrajectoryDescriptor,
  handleRecognitionStudyCaptureUploadRequest,
  prepareRecognitionStudyCaptureUpload,
  recognitionStudyCaptureUploadContract,
  sha256Hex,
  validateAuthorizedCaptureEnvelope,
} from "./recognition_study_capture_upload.mjs";

const ownerID = "00000000-0000-4000-8000-000000000001";
const authorizationID = "00000000-0000-4000-8000-000000000101";
const serviceSessionID = "00000000-0000-4000-8000-000000000102";
const captureAuthorizationID = "00000000-0000-4000-8000-000000000201";

function base64(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function sampleGrant() {
  return {
    payload: {
      artifactKind: "externally-authorized-session-grant-v1",
      authorizationEpoch: 7,
      authorizationID,
      captureTickets: [{
        captureAuthorizationID,
        displayText: "C7",
        ordinal: 0,
        presentedChartStyle: "simple-chord-sheet",
        presentedConstruction: "root-first",
        presentedPace: "natural",
        presentedSize: "normal",
        promptID: "isolated-c-seven",
        promptKind: "isolated-chord",
        requestedOrientation: "portrait",
      }],
      clientRequirements: {
        captureContractVersion: "recognition-study-authorized-capture-v1",
        expectedBundleIdentifier: "com.ichart.recognitionstudy",
        minimumBuildNumber: 51,
      },
      collectionProtocolVersion: "writer-independent-capture-v2",
      consentBinding: {
        consentLedgerEpoch: 4,
        consentLedgerVersion: "consent-ledger-v1",
        consentRecordID: "00000000-0000-4000-8000-000000000301",
        consentRecordSHA256: "ab".repeat(32),
        consentTextVersion: "consent-text-v1",
        dataUsePolicyVersion: "raw-stroke-research-v1",
        privacyNoticeVersion: "privacy-notice-v1",
        rawStrokeDonationAuthorized: true,
        retentionPolicyVersion: "retention-12-months-v1",
        schemaVersion: "recognition-study-consent-binding-v1",
        scope: "chord-recognition-research-v1",
      },
      datasetVersion: "capture-pilot-v1",
      expectedCaptureCount: 1,
      expiresAtUnixSeconds: 2_000,
      issuedAtUnixSeconds: 1_000,
      notBeforeUnixSeconds: 1_010,
      promptPlanVersion: "coverage-pilot-v1",
      schemaVersion: "recognition-study-capture-grant-v1",
      serviceSessionID,
    },
    schemaVersion: "recognition-study-signed-capture-grant-v1",
    signatureBase64: base64(new Uint8Array(64)),
    signingKeyID: "study-authority-test-v1",
  };
}

function samplePacket() {
  return {
    coordinateSpace: "transformed-prepared-drawing",
    formatVersion: "ink-trajectory-packet-v1",
    strokes: [{
      bounds: {
        maxX: "3ff0000000000000",
        maxY: "4000000000000000",
        minX: "3ff0000000000000",
        minY: "4000000000000000",
      },
      creationTimeOffset: {
        bitPattern: "0000000000000000",
        state: "finite",
      },
      points: [{
        timeOffset: {
          bitPattern: "3fd0000000000000",
          state: "finite",
        },
        x: "3ff0000000000000",
        y: "4000000000000000",
      }],
    }],
  };
}

async function fixture() {
  const signedGrant = sampleGrant();
  const packet = samplePacket();
  const packetBytes = new TextEncoder().encode(canonicalJSONString(packet));
  const packetSHA256 = await sha256Hex(packetBytes);
  const signedGrantSHA256 = await signedCaptureGrantSHA256(signedGrant);
  const envelope = {
    artifactKind: "externally-authorized-trajectory-v1",
    captureAuthorizationID,
    clientAppContext: {
      appVersion: "1.0",
      buildNumber: "51",
      bundleIdentifier: "com.ichart.recognitionstudy",
      operatingSystemMajorVersion: 26,
      operatingSystemMinorVersion: 5,
    },
    clientCapturedAtUnixMilliseconds: 1_100_000,
    clientObservedSurface: {
      canvasHeight: "4090000000000000",
      canvasWidth: "4088000000000000",
      clientObservedOrientation: "portrait",
      presentedChartStyle: "simple-chord-sheet",
      presentedConstructionInstruction: "root-first",
      presentedPaceInstruction: "natural",
      presentedSizeInstruction: "normal",
      surfaceVersion: "recognition-study-presented-surface-v1",
    },
    grantAuthorizationID: authorizationID,
    schemaVersion: "recognition-study-authorized-capture-envelope-v1",
    serviceSessionID,
    signedGrantSHA256,
    ticketOrdinal: 0,
    trajectoryDescriptor: deriveTrajectoryDescriptor(
      packet,
      packetSHA256,
      packetBytes.byteLength,
    ),
  };
  const requestValue = {
    canonicalPacketBase64: base64(packetBytes),
    envelope,
    schemaVersion: "recognition-study-capture-upload-request-v1",
    signedGrant,
  };
  return { envelope, packet, packetBytes, requestValue, signedGrant };
}

function requestFor(value) {
  return new Request("https://example.test/capture", {
    method: "POST",
    headers: { authorization: "Bearer user-session" },
    body: canonicalJSONString(value),
  });
}

function canonicalFixtureBytes(name) {
  const stored = readFileSync(
    new URL(`../../../recognition_contract_fixtures/${name}`, import.meta.url),
  );
  assert.equal(stored.at(-1), 0x0a, "fixture carries exactly one file terminator");
  const canonical = stored.subarray(0, stored.length - 1);
  assert.equal(canonical.includes(0x0a), false, "canonical fixture is one JSON line");
  return canonical;
}

test("JavaScript validates the shared Swift canonical packet and envelope golden", async () => {
  const packetBytes = canonicalFixtureBytes("ink_trajectory_packet_v1.json");
  const envelopeBytes = canonicalFixtureBytes("authorized_capture_envelope_v1.json");
  const packet = decodeCanonicalTrajectoryPacket(packetBytes);
  const envelope = JSON.parse(new TextDecoder().decode(envelopeBytes));

  validateAuthorizedCaptureEnvelope(envelope);
  assert.equal(canonicalJSONString(packet), new TextDecoder().decode(packetBytes));
  assert.equal(canonicalJSONString(envelope), new TextDecoder().decode(envelopeBytes));
  assert.equal(
    await sha256Hex(packetBytes),
    envelope.trajectoryDescriptor.canonicalPacketSHA256,
  );
  assert.deepEqual(
    deriveTrajectoryDescriptor(
      packet,
      envelope.trajectoryDescriptor.canonicalPacketSHA256,
      packetBytes.byteLength,
    ),
    envelope.trajectoryDescriptor,
  );
});

test("JavaScript accepts the exact shared Swift canonical upload request", async () => {
  const requestBytes = canonicalFixtureBytes(
    "authorized_capture_upload_request_v1.json",
  );
  const requestValue = await decodeCanonicalCaptureUploadRequest(requestBytes);
  const prepared = await prepareRecognitionStudyCaptureUpload({
    requestValue,
    nowUnixSeconds: 1_800_000_200,
  });

  assert.equal(requestBytes.byteLength, 4_288);
  assert.equal(
    prepared.envelopeSHA256,
    await sha256Hex(canonicalFixtureBytes("authorized_capture_envelope_v1.json")),
  );
  assert.equal(
    prepared.canonicalPacketSHA256,
    requestValue.envelope.trajectoryDescriptor.canonicalPacketSHA256,
  );
});

test("valid capture is bound, consumed once, and returns a digest receipt", async () => {
  const value = await fixture();
  let consumed;
  const response = await handleRecognitionStudyCaptureUploadRequest(
    requestFor(value.requestValue),
    {
      authenticatedUserID: async () => ownerID,
      consumeCapture: async (prepared) => {
        consumed = prepared;
        return {
          accepted: true,
          canonicalPacketByteCount: prepared.canonicalPacketByteCount,
          canonicalPacketSHA256: prepared.canonicalPacketSHA256,
          captureAuthorizationID: prepared.captureAuthorizationID,
          envelopeSHA256: prepared.envelopeSHA256,
          grantCompleted: true,
          receiptID: "00000000-0000-4000-8000-000000000401",
          receivedAtUnixMilliseconds: 1_100_100,
          replayed: false,
          schemaVersion: "recognition-study-capture-receipt-v1",
        };
      },
      nowUnixSeconds: () => 1_100,
    },
  );

  assert.equal(response.status, 201);
  assert.equal(consumed.ownerID, ownerID);
  assert.equal(consumed.captureAuthorizationID, captureAuthorizationID);
  assert.equal(consumed.canonicalPacketByteCount, value.packetBytes.byteLength);
  assert.equal(consumed.canonicalPacketBase64, value.requestValue.canonicalPacketBase64);
  assert.equal((await response.json()).grantCompleted, true);
});

test("an exact server replay returns 200 without changing receipt bindings", async () => {
  const value = await fixture();
  const prepared = await prepareRecognitionStudyCaptureUpload({
    requestValue: value.requestValue,
    nowUnixSeconds: 1_100,
  });
  const response = await handleRecognitionStudyCaptureUploadRequest(
    requestFor(value.requestValue),
    {
      authenticatedUserID: async () => ownerID,
      consumeCapture: async () => ({
        accepted: true,
        canonicalPacketByteCount: prepared.canonicalPacketBytes.byteLength,
        canonicalPacketSHA256: prepared.canonicalPacketSHA256,
        captureAuthorizationID,
        envelopeSHA256: prepared.envelopeSHA256,
        grantCompleted: true,
        receiptID: "00000000-0000-4000-8000-000000000401",
        receivedAtUnixMilliseconds: 1_100_100,
        replayed: true,
        schemaVersion: "recognition-study-capture-receipt-v1",
      }),
      nowUnixSeconds: () => 1_100,
    },
  );
  assert.equal(response.status, 200);
  assert.equal((await response.json()).replayed, true);
});

test("canonical decoding rejects unknown fields, pretty JSON, and malformed base64", async () => {
  const value = await fixture();
  const unknown = { ...value.requestValue, unexpected: true };
  await assert.rejects(
    decodeCanonicalCaptureUploadRequest(
      new TextEncoder().encode(canonicalJSONString(unknown)),
    ),
    (error) => error instanceof RecognitionStudyCaptureUploadError
      && error.code === "invalid_fields",
  );
  await assert.rejects(
    decodeCanonicalCaptureUploadRequest(
      new TextEncoder().encode(JSON.stringify(value.requestValue, null, 2)),
    ),
    (error) => error.code === "noncanonical_json",
  );
  const badBase64 = { ...value.requestValue, canonicalPacketBase64: "A" };
  await assert.rejects(
    decodeCanonicalCaptureUploadRequest(
      new TextEncoder().encode(canonicalJSONString(badBase64)),
    ),
    (error) => error.code === "invalid_base64",
  );
});

test("grant, ticket, surface, and packet descriptor mismatches fail closed", async () => {
  const value = await fixture();
  const wrongSurface = structuredClone(value.requestValue);
  wrongSurface.envelope.clientObservedSurface.presentedSizeInstruction = "large";
  await assert.rejects(
    prepareRecognitionStudyCaptureUpload({
      requestValue: wrongSurface,
      nowUnixSeconds: 1_100,
    }),
    (error) => error.code === "surface_ticket_mismatch",
  );

  const wrongDigest = structuredClone(value.requestValue);
  wrongDigest.envelope.signedGrantSHA256 = "ef".repeat(32);
  await assert.rejects(
    prepareRecognitionStudyCaptureUpload({
      requestValue: wrongDigest,
      nowUnixSeconds: 1_100,
    }),
    (error) => error.code === "signed_grant_digest_mismatch",
  );

  const differentPacket = structuredClone(value.requestValue);
  differentPacket.canonicalPacketBase64 = base64(new TextEncoder().encode(
    canonicalJSONString({
      ...value.packet,
      strokes: [],
    }),
  ));
  await assert.rejects(
    prepareRecognitionStudyCaptureUpload({
      requestValue: differentPacket,
      nowUnixSeconds: 1_100,
    }),
    (error) => error.code === "trajectory_descriptor_mismatch",
  );

  for (const invalidCaptureTime of [999_999, 2_000_000]) {
    const outsideWindow = structuredClone(value.requestValue);
    outsideWindow.envelope.clientCapturedAtUnixMilliseconds = invalidCaptureTime;
    await assert.rejects(
      prepareRecognitionStudyCaptureUpload({
        requestValue: outsideWindow,
        nowUnixSeconds: 1_100,
      }),
      (error) => error.code === "capture_outside_grant_validity_window",
    );
  }
});

test("trajectory parser rejects non-finite geometry and unsafe timing claims", async () => {
  const value = await fixture();
  for (const mutate of [
    (packet) => { packet.strokes[0].points[0].x = "7ff0000000000000"; },
    (packet) => {
      packet.strokes[0].points[0].timeOffset = {
        bitPattern: "7ff0000000000000",
        state: "finite",
      };
    },
  ]) {
    const packet = structuredClone(value.packet);
    mutate(packet);
    const changed = structuredClone(value.requestValue);
    changed.canonicalPacketBase64 = base64(
      new TextEncoder().encode(canonicalJSONString(packet)),
    );
    await assert.rejects(
      prepareRecognitionStudyCaptureUpload({
        requestValue: changed,
        nowUnixSeconds: 1_100,
      }),
      (error) => ["nonfinite_geometry", "timing_state_mismatch"].includes(error.code),
    );
  }
});

test("handler refuses unauthenticated, inactive, oversized, and conflicting uploads", async () => {
  const value = await fixture();
  const unauthenticated = await handleRecognitionStudyCaptureUploadRequest(
    requestFor(value.requestValue),
    {
      authenticatedUserID: async () => null,
      consumeCapture: async () => assert.fail("must not consume"),
      nowUnixSeconds: () => 1_100,
    },
  );
  assert.equal(unauthenticated.status, 401);

  let expiredReachedConsume = false;
  const expired = await handleRecognitionStudyCaptureUploadRequest(
    requestFor(value.requestValue),
    {
      authenticatedUserID: async () => ownerID,
      consumeCapture: async () => {
        expiredReachedConsume = true;
        throw new RecognitionStudyCaptureConsumeError("inactive");
      },
      nowUnixSeconds: () => 2_000,
    },
  );
  assert.equal(expired.status, 410);
  assert.equal(expiredReachedConsume, true);

  const oversized = await handleRecognitionStudyCaptureUploadRequest(
    new Request("https://example.test/capture", {
      method: "POST",
      body: "x".repeat(
        recognitionStudyCaptureUploadContract.maximumRequestBytes + 1,
      ),
    }),
    {
      authenticatedUserID: async () => ownerID,
      consumeCapture: async () => assert.fail("must not consume"),
      nowUnixSeconds: () => 1_100,
    },
  );
  assert.equal(oversized.status, 413);

  const conflict = await handleRecognitionStudyCaptureUploadRequest(
    requestFor(value.requestValue),
    {
      authenticatedUserID: async () => ownerID,
      consumeCapture: async () => {
        throw new RecognitionStudyCaptureConsumeError("conflict");
      },
      nowUnixSeconds: () => 1_100,
    },
  );
  assert.equal(conflict.status, 409);

  const inactive = await handleRecognitionStudyCaptureUploadRequest(
    requestFor(value.requestValue),
    {
      authenticatedUserID: async () => ownerID,
      consumeCapture: async () => {
        throw new RecognitionStudyCaptureConsumeError("inactive");
      },
      nowUnixSeconds: () => 1_100,
    },
  );
  assert.equal(inactive.status, 410);

  const unavailable = await handleRecognitionStudyCaptureUploadRequest(
    requestFor(value.requestValue),
    {
      authenticatedUserID: async () => ownerID,
      consumeCapture: async () => { throw new Error("network"); },
      nowUnixSeconds: () => 1_100,
    },
  );
  assert.equal(unavailable.status, 503);
});

test("an expired exact retry can recover its immutable server receipt", async () => {
  const value = await fixture();
  const response = await handleRecognitionStudyCaptureUploadRequest(
    requestFor(value.requestValue),
    {
      authenticatedUserID: async () => ownerID,
      consumeCapture: async (prepared) => ({
        accepted: true,
        canonicalPacketByteCount: prepared.canonicalPacketByteCount,
        canonicalPacketSHA256: prepared.canonicalPacketSHA256,
        captureAuthorizationID: prepared.captureAuthorizationID,
        envelopeSHA256: prepared.envelopeSHA256,
        grantCompleted: false,
        receiptID: "00000000-0000-4000-8000-000000000401",
        receivedAtUnixMilliseconds: 1_999_999,
        replayed: true,
        schemaVersion: "recognition-study-capture-receipt-v1",
      }),
      nowUnixSeconds: () => 2_000,
    },
  );

  assert.equal(response.status, 200);
  assert.equal((await response.json()).replayed, true);
});
