import assert from "node:assert/strict";
import test from "node:test";

import {
  decodeCanonicalSignedCaptureGrant,
  signedCaptureGrantSHA256,
  verifySignedCaptureGrant,
} from "./recognition_study_capture_grant.mjs";
import {
  captureGrantPayload,
  handleRecognitionStudyCaptureGrantRequest,
} from "./recognition_study_collection_authority.mjs";

const ownerID = "00000000-0000-4000-8000-000000000001";
const clientRequestID = "00000000-0000-4000-8000-000000000002";

const prepared = {
  authorizationEpoch: 12,
  consentBinding: {
    consentLedgerEpoch: 3,
    consentLedgerVersion: "consent-ledger-v1",
    consentRecordID: "00000000-0000-4000-8000-000000000003",
    consentRecordSHA256: "ab".repeat(32),
    consentTextVersion: "consent-text-v1",
    dataUsePolicyVersion: "raw-stroke-research-v1",
    privacyNoticeVersion: "privacy-notice-v1",
    rawStrokeDonationAuthorized: true,
    retentionPolicyVersion: "retention-12-months-v1",
    schemaVersion: "recognition-study-consent-binding-v1",
    scope: "chord-recognition-research-v1",
  },
};

const promptPlan = {
  captureTickets: [
    {
      displayText: "Dø7",
      presentedChartStyle: "simple-chord-sheet",
      presentedConstruction: "root-first",
      presentedPace: "natural",
      presentedSize: "normal",
      promptID: "isolated-d-half-diminished-seven",
      promptKind: "isolated-chord",
      requestedOrientation: "portrait",
    },
    {
      displayText: "Bb7 | Eb7",
      presentedChartStyle: "rhythm-section-sheet",
      presentedConstruction: "mixed-or-retraced",
      presentedPace: "fast",
      presentedSize: "small",
      promptID: "row-b-flat-seven-e-flat-seven",
      promptKind: "realistic-row",
      requestedOrientation: "landscape",
    },
  ],
  datasetVersion: "independent-writer-pilot-v1",
  minimumBuildNumber: 51,
  promptPlanVersion: "balanced-pilot-v1",
};

async function signingFixture() {
  const keyPair = await globalThis.crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const rawPublicKey = new Uint8Array(
    await globalThis.crypto.subtle.exportKey("raw", keyPair.publicKey),
  );
  return {
    rawPublicKey,
    signPayload: (payload) => globalThis.crypto.subtle.sign(
      { name: "Ed25519" },
      keyPair.privateKey,
      payload,
    ),
  };
}

function uuidGenerator(start = 100) {
  let value = start;
  return () => {
    const suffix = String(value).padStart(12, "0");
    value += 1;
    return `00000000-0000-4000-8000-${suffix}`;
  };
}

function grantRequest(body = {}) {
  return new Request("https://example.test/recognition-study-capture-grant", {
    method: "POST",
    headers: {
      authorization: "Bearer test-session",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      clientRequestID,
      schemaVersion: "recognition-study-capture-grant-request-v1",
      ...body,
    }),
  });
}

async function configuredDependencies(overrides = {}) {
  const fixture = await signingFixture();
  return {
    authenticatedUserID: async () => ownerID,
    commitGrant: async ({ grant, signedGrantSHA256 }) => ({
      signedGrant: grant,
      signedGrantSHA256,
      status: "issued",
      stored: true,
    }),
    grantLifetimeSeconds: 900,
    nowUnixSeconds: () => 1_800_000_000,
    prepareGrant: async () => prepared,
    promptPlan,
    randomUUID: uuidGenerator(),
    signingKeyID: "pilot-ed25519-1",
    signPayload: fixture.signPayload,
    fixture,
    ...overrides,
  };
}

test("issue endpoint returns a canonical signed grant without identity or labels", async () => {
  const dependencies = await configuredDependencies();
  let committed;
  dependencies.commitGrant = async (value) => {
    committed = value;
    return {
      signedGrant: value.grant,
      signedGrantSHA256: value.signedGrantSHA256,
      status: "issued",
      stored: true,
    };
  };

  const response = await handleRecognitionStudyCaptureGrantRequest(
    grantRequest(),
    dependencies,
  );
  const text = await response.text();
  const grant = decodeCanonicalSignedCaptureGrant(text);
  const digest = await signedCaptureGrantSHA256(grant);

  assert.equal(response.status, 201);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(response.headers.get("x-ichart-authority-artifact-sha256"), digest);
  assert.equal(committed.ownerID, ownerID);
  assert.equal(committed.clientRequestID, clientRequestID);
  assert.equal(committed.signedGrantSHA256, digest);
  assert.equal(grant.payload.captureTickets[0].displayText, "Dø7");
  assert.equal(grant.payload.expectedCaptureCount, 2);
  assert.equal(grant.payload.notBeforeUnixSeconds, 1_800_000_000);
  assert.equal(grant.payload.expiresAtUnixSeconds, 1_800_000_900);
  assert.equal(text.includes(ownerID), false);
  assert.equal(text.includes("writer"), true); // protocol version only
  for (const forbidden of ["writerID", "writer_id", "groundTruth", "split", "corpusEligible"] ) {
    assert.equal(text.includes(forbidden), false);
  }
  await verifySignedCaptureGrant({
    grant,
    trustedRawPublicKeysByID: new Map([["pilot-ed25519-1", dependencies.fixture.rawPublicKey]]),
    validationUnixSeconds: 1_800_000_100,
  });
});

test("same client request returns the first immutable artifact", async () => {
  let stored;
  const dependencies = await configuredDependencies({
    commitGrant: async ({ grant, signedGrantSHA256 }) => {
      if (stored === undefined) {
        stored = { grant, signedGrantSHA256 };
        return { signedGrant: grant, signedGrantSHA256, status: "issued", stored: true };
      }
      return {
        signedGrant: stored.grant,
        signedGrantSHA256: stored.signedGrantSHA256,
        status: "issued",
        stored: false,
      };
    },
  });

  const first = await handleRecognitionStudyCaptureGrantRequest(grantRequest(), dependencies);
  const second = await handleRecognitionStudyCaptureGrantRequest(grantRequest(), dependencies);
  assert.equal(first.status, 201);
  assert.equal(second.status, 200);
  assert.equal(await second.text(), await first.text());
});

test("endpoint never serves a revoked or expired idempotent artifact", async () => {
  const revoked = await configuredDependencies({
    commitGrant: async ({ grant, signedGrantSHA256 }) => ({
      signedGrant: grant,
      signedGrantSHA256,
      status: "revoked",
      stored: false,
    }),
  });
  assert.equal(
    (await handleRecognitionStudyCaptureGrantRequest(grantRequest(), revoked)).status,
    503,
  );

  const expired = await configuredDependencies({
    commitGrant: async ({ grant }) => {
      const signedGrant = {
        ...grant,
        payload: {
          ...grant.payload,
          issuedAtUnixSeconds: 1_799_999_000,
          notBeforeUnixSeconds: 1_799_999_000,
          expiresAtUnixSeconds: 1_799_999_900,
        },
      };
      return {
        signedGrant,
        signedGrantSHA256: await signedCaptureGrantSHA256(signedGrant),
        status: "issued",
        stored: false,
      };
    },
  });
  assert.equal(
    (await handleRecognitionStudyCaptureGrantRequest(grantRequest(), expired)).status,
    503,
  );
});

test("endpoint rejects unsigned callers, malformed requests, and missing consent", async () => {
  const unsigned = await configuredDependencies({ authenticatedUserID: async () => null });
  assert.equal(
    (await handleRecognitionStudyCaptureGrantRequest(grantRequest(), unsigned)).status,
    401,
  );

  const malformed = await configuredDependencies();
  assert.equal(
    (await handleRecognitionStudyCaptureGrantRequest(
      grantRequest({ requestedSplit: "sealed-evaluation" }),
      malformed,
    )).status,
    400,
  );

  const noConsent = await configuredDependencies({ prepareGrant: async () => null });
  assert.equal(
    (await handleRecognitionStudyCaptureGrantRequest(grantRequest(), noConsent)).status,
    403,
  );
});

test("server prompt plan cannot smuggle supervision or unsupported display text", async () => {
  const withGroundTruth = await configuredDependencies({
    promptPlan: {
      ...promptPlan,
      captureTickets: promptPlan.captureTickets.map((ticket) => ({
        ...ticket,
        groundTruth: ticket.displayText,
      })),
    },
  });
  assert.equal(
    (await handleRecognitionStudyCaptureGrantRequest(grantRequest(), withGroundTruth)).status,
    500,
  );

  const newline = await configuredDependencies({
    promptPlan: {
      ...promptPlan,
      captureTickets: [{ ...promptPlan.captureTickets[0], displayText: "C7\nG7" }],
    },
  });
  assert.equal(
    (await handleRecognitionStudyCaptureGrantRequest(grantRequest(), newline)).status,
    500,
  );
});

test("payload builder assigns one ticket per ordinal and fresh identifiers", () => {
  const payload = captureGrantPayload({
    prepared,
    promptPlan,
    now: 100,
    expiresAt: 200,
    randomUUID: uuidGenerator(500),
  });
  assert.deepEqual(payload.captureTickets.map((ticket) => ticket.ordinal), [0, 1]);
  assert.equal(new Set([
    payload.authorizationID,
    payload.serviceSessionID,
    ...payload.captureTickets.map((ticket) => ticket.captureAuthorizationID),
  ]).size, 4);
});
