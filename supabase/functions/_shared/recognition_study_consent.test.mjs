import assert from "node:assert/strict";
import test from "node:test";

import {
  RecognitionStudyConsentStoreError,
  consentCanonicalJSONString,
  handleRecognitionStudyConsentRequest,
  recognitionStudyConsentContract,
} from "./recognition_study_consent.mjs";

const ownerID = "10000000-0000-4000-8000-000000000001";
const clientRequestID = "10000000-0000-4000-8000-000000000002";
const consentRecordID = "10000000-0000-4000-8000-000000000003";
const policy = {
  consentDocumentURL: "https://useichart.com/legal/recognition-study-v1.json",
  consentLedgerVersion: "consent-ledger-v1",
  consentTextVersion: "consent-text-v1",
  dataUsePolicyVersion: "raw-stroke-research-v1",
  presentationID: "raw-stroke-research-pilot-v1",
  presentationSHA256: "ab".repeat(32),
  privacyNoticeVersion: "privacy-notice-v1",
  rawStrokeDonationRequired: true,
  retentionPolicyVersion: "retention-12-months-v1",
  schemaVersion: recognitionStudyConsentContract.policySchemaVersion,
  scope: "chord-recognition-research-v1",
};
const consent = {
  acceptedAtUnixMilliseconds: 1_800_000_000_000,
  consentLedgerEpoch: 8,
  consentLedgerVersion: "consent-ledger-v1",
  consentRecordID,
  consentRecordSHA256: "cd".repeat(32),
  consentTextVersion: "consent-text-v1",
  dataUsePolicyVersion: "raw-stroke-research-v1",
  privacyNoticeVersion: "privacy-notice-v1",
  rawStrokeDonationAuthorized: true,
  retentionPolicyVersion: "retention-12-months-v1",
  schemaVersion: recognitionStudyConsentContract.consentSchemaVersion,
  scope: "chord-recognition-research-v1",
  status: "active",
  withdrawnAtUnixMilliseconds: null,
};

function storeResponse(overrides = {}) {
  return {
    consent,
    currentPolicy: policy,
    replayed: false,
    schemaVersion: "recognition-study-consent-store-response-v1",
    status: "active",
    ...overrides,
  };
}

function dependencies(overrides = {}) {
  return {
    acceptConsent: async () => storeResponse(),
    authenticatedUserID: async () => ownerID,
    readConsentStatus: async () => storeResponse({
      consent: null,
      replayed: false,
      status: "not-accepted",
    }),
    withdrawConsent: async () => storeResponse({
      consent: {
        ...consent,
        consentLedgerEpoch: 9,
        status: "withdrawn",
        withdrawnAtUnixMilliseconds: 1_800_000_100_000,
      },
      replayed: false,
      status: "withdrawn",
    }),
    ...overrides,
  };
}

function request(value, headers = {}) {
  return new Request("https://example.test/consent", {
    method: "POST",
    headers: { authorization: "Bearer user-session", ...headers },
    body: consentCanonicalJSONString(value),
  });
}

test("endpoint is POST-only and fail-closed without every authority", async () => {
  assert.equal(
    (await handleRecognitionStudyConsentRequest(
      new Request("https://example.test/consent"),
      dependencies(),
    )).status,
    405,
  );
  assert.equal(
    (await handleRecognitionStudyConsentRequest(
      request({ schemaVersion: recognitionStudyConsentContract.statusRequestSchemaVersion }),
      {},
    )).status,
    501,
  );
});

test("status request is canonical, authenticated, and returns minimal policy state", async () => {
  const body = { schemaVersion: recognitionStudyConsentContract.statusRequestSchemaVersion };
  const response = await handleRecognitionStudyConsentRequest(request(body), dependencies());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    consent: null,
    currentPolicy: policy,
    replayed: false,
    schemaVersion: recognitionStudyConsentContract.responseSchemaVersion,
    status: "not-accepted",
  });
  assert.equal(response.headers.get("cache-control"), "no-store");

  const unauthorized = await handleRecognitionStudyConsentRequest(
    request(body),
    dependencies({ authenticatedUserID: async () => null }),
  );
  assert.equal(unauthorized.status, 401);
});

test("accept sends only explicit acknowledgement of one reviewed presentation", async () => {
  const value = {
    clientRequestID,
    explicitRawStrokeDonationAuthorization: true,
    presentationID: policy.presentationID,
    presentationSHA256: policy.presentationSHA256,
    schemaVersion: recognitionStudyConsentContract.acceptRequestSchemaVersion,
  };
  let received;
  const sourceRequest = request(value);
  const response = await handleRecognitionStudyConsentRequest(
    sourceRequest,
    dependencies({
      acceptConsent: async (incomingRequest, incomingValue) => {
        received = { incomingRequest, incomingValue };
        return storeResponse();
      },
    }),
  );
  assert.equal(response.status, 201);
  assert.deepEqual(received.incomingValue, value);
  assert.equal(received.incomingRequest, sourceRequest);
  assert.equal((await response.json()).status, "active");

  const replay = await handleRecognitionStudyConsentRequest(
    request(value),
    dependencies({ acceptConsent: async () => storeResponse({ replayed: true }) }),
  );
  assert.equal(replay.status, 200);
  assert.equal((await replay.json()).replayed, true);
});

test("accept rejects false authorization, unknown fields, and noncanonical JSON", async () => {
  const value = {
    clientRequestID,
    explicitRawStrokeDonationAuthorization: false,
    presentationID: policy.presentationID,
    presentationSHA256: policy.presentationSHA256,
    schemaVersion: recognitionStudyConsentContract.acceptRequestSchemaVersion,
  };
  assert.equal(
    (await handleRecognitionStudyConsentRequest(request(value), dependencies())).status,
    400,
  );
  value.explicitRawStrokeDonationAuthorization = true;
  value.groundTruth = "C7";
  assert.equal(
    (await handleRecognitionStudyConsentRequest(request(value), dependencies())).status,
    400,
  );
  const noncanonical = new Request("https://example.test/consent", {
    method: "POST",
    body: JSON.stringify({
      schemaVersion: recognitionStudyConsentContract.statusRequestSchemaVersion,
    }, null, 2),
  });
  assert.equal(
    (await handleRecognitionStudyConsentRequest(noncanonical, dependencies())).status,
    400,
  );
});

test("withdraw identifies one opaque record without exposing upload counts", async () => {
  const value = {
    clientRequestID,
    consentRecordID,
    schemaVersion: recognitionStudyConsentContract.withdrawRequestSchemaVersion,
  };
  const response = await handleRecognitionStudyConsentRequest(request(value), dependencies());
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.status, "withdrawn");
  assert.equal(result.consent.consentRecordID, consentRecordID);
  assert.equal("deletedCaptureCount" in result, false);
  assert.equal("revokedGrantCount" in result, false);
});

test("store conflicts and unavailable policy have stable public dispositions", async () => {
  const value = {
    clientRequestID,
    explicitRawStrokeDonationAuthorization: true,
    presentationID: policy.presentationID,
    presentationSHA256: policy.presentationSHA256,
    schemaVersion: recognitionStudyConsentContract.acceptRequestSchemaVersion,
  };
  for (const [disposition, status] of [["conflict", 409], ["policy_unavailable", 503]]) {
    const response = await handleRecognitionStudyConsentRequest(
      request(value),
      dependencies({
        acceptConsent: async () => {
          throw new RecognitionStudyConsentStoreError(disposition);
        },
      }),
    );
    assert.equal(response.status, status);
  }
});

test("oversized requests and forged store responses fail closed", async () => {
  const oversized = await handleRecognitionStudyConsentRequest(
    new Request("https://example.test/consent", {
      method: "POST",
      body: "x".repeat(recognitionStudyConsentContract.maximumRequestBytes + 1),
    }),
    dependencies(),
  );
  assert.equal(oversized.status, 413);

  const forged = await handleRecognitionStudyConsentRequest(
    request({ schemaVersion: recognitionStudyConsentContract.statusRequestSchemaVersion }),
    dependencies({
      readConsentStatus: async () => ({
        ...storeResponse(),
        groundTruth: "C7",
      }),
    }),
  );
  assert.equal(forged.status, 400);
});
