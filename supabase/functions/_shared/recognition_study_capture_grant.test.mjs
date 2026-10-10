import assert from "node:assert/strict";
import test from "node:test";

import {
  RecognitionStudyCaptureGrantError,
  canonicalJSONBytes,
  canonicalJSONString,
  createSignedCaptureGrant,
  decodeCanonicalSignedCaptureGrant,
  signedCaptureGrantSHA256,
  validateCaptureGrantPayload,
  validateSignedCaptureGrant,
  verifySignedCaptureGrant,
} from "./recognition_study_capture_grant.mjs";

function samplePayload(overrides = {}) {
  return {
    artifactKind: "externally-authorized-session-grant-v1",
    authorizationEpoch: 7,
    authorizationID: "00000000-0000-4000-8000-000000000101",
    captureTickets: [
      {
        captureAuthorizationID: "00000000-0000-4000-8000-000000000201",
        displayText: "Cmaj7  Dm7  G7  Cmaj7",
        ordinal: 0,
        presentedChartStyle: "simple-chord-sheet",
        presentedConstruction: "root-first",
        presentedPace: "natural",
        presentedSize: "normal",
        promptID: "major-two-five-one",
        promptKind: "realistic-row",
        requestedOrientation: "portrait",
      },
      {
        captureAuthorizationID: "00000000-0000-4000-8000-000000000202",
        displayText: "not a chord",
        ordinal: 1,
        presentedChartStyle: "rhythm-section-sheet",
        presentedConstruction: "mixed-or-retraced",
        presentedPace: "fast",
        presentedSize: "small",
        promptID: "open-set-negative-one",
        promptKind: "open-set-negative",
        requestedOrientation: "landscape",
      },
    ],
    clientRequirements: {
      captureContractVersion: "recognition-study-authorized-capture-v1",
      expectedBundleIdentifier: "com.ichart.recognitionstudy",
      minimumBuildNumber: 101,
    },
    collectionProtocolVersion: "writer-independent-capture-v2",
    consentBinding: {
      consentLedgerEpoch: 4,
      consentLedgerVersion: "consent-ledger-v1",
      consentRecordID: "00000000-0000-4000-8000-000000000301",
      consentRecordSHA256: "ab".repeat(32),
      consentTextVersion: "recognition-consent-v1",
      dataUsePolicyVersion: "recognition-data-use-v1",
      privacyNoticeVersion: "recognition-privacy-v1",
      rawStrokeDonationAuthorized: true,
      retentionPolicyVersion: "recognition-retention-v1",
      schemaVersion: "recognition-study-consent-binding-v1",
      scope: "chord-recognition-research-v1",
    },
    datasetVersion: "independent-writer-pilot-v1",
    expectedCaptureCount: 2,
    expiresAtUnixSeconds: 2_000,
    issuedAtUnixSeconds: 1_000,
    notBeforeUnixSeconds: 1_010,
    promptPlanVersion: "balanced-pilot-v1",
    schemaVersion: "recognition-study-capture-grant-v1",
    serviceSessionID: "00000000-0000-4000-8000-000000000102",
    ...overrides,
  };
}

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

function expectCode(expected, operation) {
  assert.throws(operation, (error) => {
    assert.ok(error instanceof RecognitionStudyCaptureGrantError);
    assert.equal(error.code, expected);
    return true;
  });
}

const swiftGoldenPayload = "{\"artifactKind\":\"externally-authorized-session-grant-v1\",\"authorizationEpoch\":9,\"authorizationID\":\"11111111-1111-4111-8111-111111111111\",\"captureTickets\":[{\"captureAuthorizationID\":\"44444444-4444-4444-8444-444444444444\",\"displayText\":\"C7\",\"ordinal\":0,\"presentedChartStyle\":\"simple-chord-sheet\",\"presentedConstruction\":\"root-first\",\"presentedPace\":\"natural\",\"presentedSize\":\"normal\",\"promptID\":\"isolated-c-seven\",\"promptKind\":\"isolated-chord\",\"requestedOrientation\":\"portrait\"},{\"captureAuthorizationID\":\"55555555-5555-4555-8555-555555555555\",\"displayText\":\"Bb7 | Eb7\",\"ordinal\":1,\"presentedChartStyle\":\"rhythm-section-sheet\",\"presentedConstruction\":\"mixed-or-retraced\",\"presentedPace\":\"fast\",\"presentedSize\":\"small\",\"promptID\":\"row-b-flat-seven-e-flat-seven\",\"promptKind\":\"realistic-row\",\"requestedOrientation\":\"landscape\"}],\"clientRequirements\":{\"captureContractVersion\":\"recognition-study-authorized-capture-v1\",\"expectedBundleIdentifier\":\"com.ichart.recognitionstudy\",\"minimumBuildNumber\":51},\"collectionProtocolVersion\":\"writer-independent-capture-v2\",\"consentBinding\":{\"consentLedgerEpoch\":7,\"consentLedgerVersion\":\"consent-ledger-v1\",\"consentRecordID\":\"33333333-3333-4333-8333-333333333333\",\"consentRecordSHA256\":\"abababababababababababababababababababababababababababababababab\",\"consentTextVersion\":\"consent-text-v1\",\"dataUsePolicyVersion\":\"raw-stroke-research-v1\",\"privacyNoticeVersion\":\"privacy-notice-v1\",\"rawStrokeDonationAuthorized\":true,\"retentionPolicyVersion\":\"retention-12-months-v1\",\"schemaVersion\":\"recognition-study-consent-binding-v1\",\"scope\":\"chord-recognition-research-v1\"},\"datasetVersion\":\"writer-pilot-2026-01\",\"expectedCaptureCount\":2,\"expiresAtUnixSeconds\":1800003600,\"issuedAtUnixSeconds\":1800000000,\"notBeforeUnixSeconds\":1800000100,\"promptPlanVersion\":\"pilot-prompts-v1\",\"schemaVersion\":\"recognition-study-capture-grant-v1\",\"serviceSessionID\":\"22222222-2222-4222-8222-222222222222\"}";
const swiftGoldenSignature = "Su0SaxTyWXz0O7bsxux5GkrKu9aBwJMg6I+GriIRHha7fuACjMzRq/e72QLlubuKqCTqzaQ1XuAq1K7XnuZDCA==";
const swiftGoldenPublicKey = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=";
const swiftGoldenDigest = "0adad335a1454c11f0b0c98951461f4c8bb71ea3fc6f0d68f1675a201a66e0e1";

test("Deno authority verifies the exact Swift CryptoKit golden artifact", async () => {
  const payload = JSON.parse(swiftGoldenPayload);
  assert.equal(canonicalJSONString(payload), swiftGoldenPayload);
  const wrapper = canonicalJSONString({
    payload,
    schemaVersion: "recognition-study-signed-capture-grant-v1",
    signatureBase64: swiftGoldenSignature,
    signingKeyID: "study-authority-test-v1",
  });
  const grant = decodeCanonicalSignedCaptureGrant(wrapper);
  const rawPublicKey = Uint8Array.from(
    atob(swiftGoldenPublicKey),
    (character) => character.charCodeAt(0),
  );

  await verifySignedCaptureGrant({
    grant,
    trustedRawPublicKeysByID: new Map([["study-authority-test-v1", rawPublicKey]]),
    validationUnixSeconds: 1_800_000_100,
  });
  assert.equal(await signedCaptureGrantSHA256(grant), swiftGoldenDigest);
});

test("canonical payload bytes match Swift sorted-key and slash behavior", () => {
  const payload = samplePayload();
  validateCaptureGrantPayload(payload);
  const text = canonicalJSONString(payload);

  assert.ok(text.startsWith(
    "{\"artifactKind\":\"externally-authorized-session-grant-v1\",\"authorizationEpoch\":7,\"authorizationID\":"
  ));
  assert.ok(text.includes("Cmaj7  Dm7  G7  Cmaj7"));
  assert.equal(text.includes("\\/"), false);
  assert.deepEqual(canonicalJSONBytes(payload), new TextEncoder().encode(text));
});

test("signed grants verify exact payload bytes and bind the full wrapper digest", async () => {
  const fixture = await signingFixture();
  const grant = await createSignedCaptureGrant({
    payload: samplePayload(),
    signingKeyID: "pilot-ed25519-1",
    signPayload: fixture.signPayload,
  });
  const canonical = canonicalJSONString(grant);
  const decoded = decodeCanonicalSignedCaptureGrant(canonical);
  const verified = await verifySignedCaptureGrant({
    grant: decoded,
    trustedRawPublicKeysByID: new Map([["pilot-ed25519-1", fixture.rawPublicKey]]),
    validationUnixSeconds: 1_100,
  });

  assert.deepEqual(verified, grant.payload);
  assert.match(await signedCaptureGrantSHA256(grant), /^[0-9a-f]{64}$/);
  assert.ok(canonical.startsWith("{\"payload\":"));
  assert.ok(canonical.includes(
    "\"schemaVersion\":\"recognition-study-signed-capture-grant-v1\",\"signatureBase64\":"
  ));
});

test("signature verification rejects payload tampering and an untrusted key", async () => {
  const fixture = await signingFixture();
  const grant = await createSignedCaptureGrant({
    payload: samplePayload(),
    signingKeyID: "pilot-ed25519-1",
    signPayload: fixture.signPayload,
  });
  const tampered = {
    ...grant,
    payload: {
      ...grant.payload,
      datasetVersion: "independent-writer-pilot-v2",
    },
  };

  await assert.rejects(
    verifySignedCaptureGrant({
      grant: tampered,
      trustedRawPublicKeysByID: new Map([["pilot-ed25519-1", fixture.rawPublicKey]]),
      validationUnixSeconds: 1_100,
    }),
    (error) => error.code === "signature_verification_failed",
  );
  await assert.rejects(
    verifySignedCaptureGrant({
      grant,
      trustedRawPublicKeysByID: new Map(),
      validationUnixSeconds: 1_100,
    }),
    (error) => error.code === "untrusted_signing_key",
  );
});

test("validity windows are half-open and fail closed", async () => {
  const fixture = await signingFixture();
  const grant = await createSignedCaptureGrant({
    payload: samplePayload(),
    signingKeyID: "pilot-ed25519-1",
    signPayload: fixture.signPayload,
  });
  const keyring = new Map([["pilot-ed25519-1", fixture.rawPublicKey]]);

  await assert.rejects(
    verifySignedCaptureGrant({ grant, trustedRawPublicKeysByID: keyring, validationUnixSeconds: 1_009 }),
    (error) => error.code === "authorization_not_yet_valid",
  );
  await verifySignedCaptureGrant({
    grant,
    trustedRawPublicKeysByID: keyring,
    validationUnixSeconds: 1_010,
  });
  await assert.rejects(
    verifySignedCaptureGrant({ grant, trustedRawPublicKeysByID: keyring, validationUnixSeconds: 2_000 }),
    (error) => error.code === "authorization_expired",
  );
});

test("strict decoding rejects alternate JSON and unknown fields", async () => {
  const fixture = await signingFixture();
  const grant = await createSignedCaptureGrant({
    payload: samplePayload(),
    signingKeyID: "pilot-ed25519-1",
    signPayload: fixture.signPayload,
  });
  const canonical = canonicalJSONString(grant);

  expectCode("noncanonical_json", () => decodeCanonicalSignedCaptureGrant(` ${canonical}`));
  expectCode("unknown_field", () => validateSignedCaptureGrant({ ...grant, trusted: true }));
  expectCode("unknown_field", () => validateCaptureGrantPayload({ ...grant.payload, split: "development" }));
});

test("payload validation refuses identity, supervision, and malformed prompt plans", () => {
  expectCode("unknown_field", () => validateCaptureGrantPayload({
    ...samplePayload(),
    writerIDHash: "cd".repeat(32),
  }));
  expectCode("unknown_field", () => validateCaptureGrantPayload({
    ...samplePayload(),
    groundTruth: "Cmaj7",
  }));
  expectCode("noncontiguous_prompt_ordinals", () => validateCaptureGrantPayload({
    ...samplePayload(),
    captureTickets: samplePayload().captureTickets.map((ticket, index) => ({
      ...ticket,
      ordinal: index + 1,
    })),
  }));
  expectCode("duplicate_prompt_id", () => validateCaptureGrantPayload({
    ...samplePayload(),
    captureTickets: samplePayload().captureTickets.map((ticket) => ({
      ...ticket,
      promptID: "same-prompt",
    })),
  }));
  expectCode("raw_stroke_donation_not_authorized", () => validateCaptureGrantPayload({
    ...samplePayload(),
    consentBinding: {
      ...samplePayload().consentBinding,
      rawStrokeDonationAuthorized: false,
    },
  }));
});

test("display text accepts canonical Unicode but rejects alternate or unsafe text", () => {
  const canonical = samplePayload();
  canonical.captureTickets[0] = {
    ...canonical.captureTickets[0],
    displayText: "Dø7  B♭Δ7",
  };
  validateCaptureGrantPayload(canonical);

  for (const displayText of [
    "Cafe\u0301",
    "C7\nG7",
    "\u{105C0}",
    "\u{10FFFF}",
    "🙂",
    "x".repeat(257),
  ]) {
    const payload = samplePayload();
    payload.captureTickets[0] = {
      ...payload.captureTickets[0],
      displayText,
    };
    expectCode("invalid_display_text", () => validateCaptureGrantPayload(payload));
  }
});

test("integer domains match Swift through the maximum exact JSON integer", () => {
  const maximum = Number.MAX_SAFE_INTEGER;
  validateCaptureGrantPayload({
    ...samplePayload(),
    authorizationEpoch: maximum,
    expiresAtUnixSeconds: maximum,
  });

  for (const [field, value, code] of [
    ["authorizationEpoch", maximum + 1, "invalid_positive_integer"],
    ["expiresAtUnixSeconds", maximum + 1, "invalid_nonnegative_integer"],
  ]) {
    expectCode(code, () => validateCaptureGrantPayload({
      ...samplePayload(),
      [field]: value,
    }));
  }
});
