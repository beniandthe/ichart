import assert from "node:assert/strict";
import test from "node:test";

import {
  createEd25519Signer,
  createRecognitionStudyCollectionDependencies,
  recognitionStudyPromptPlanForID,
} from "./recognition_study_collection_store.mjs";

function bytesToBase64(bytes) {
  let value = "";
  for (const byte of bytes) {
    value += String.fromCharCode(byte);
  }
  return btoa(value);
}

async function keyFixture() {
  const keyPair = await globalThis.crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  return {
    keyPair,
    pkcs8Base64: bytesToBase64(new Uint8Array(
      await globalThis.crypto.subtle.exportKey("pkcs8", keyPair.privateKey),
    )),
  };
}

const promptPlan = recognitionStudyPromptPlanForID("coverage-pilot-v2");

test("dependency factory stays disabled without every server-only input", async () => {
  const key = await keyFixture();
  const base = {
    RECOGNITION_STUDY_ED25519_PRIVATE_KEY_PKCS8_BASE64: key.pkcs8Base64,
    RECOGNITION_STUDY_PROMPT_PLAN_ID: "coverage-pilot-v2",
    RECOGNITION_STUDY_SIGNING_KEY_ID: "pilot-key-1",
    SUPABASE_SERVICE_ROLE_KEY: "service-secret",
    SUPABASE_URL: "https://example.supabase.co",
  };

  for (const missing of Object.keys(base)) {
    const env = { ...base };
    delete env[missing];
    assert.deepEqual(createRecognitionStudyCollectionDependencies(env), {});
  }
  assert.deepEqual(createRecognitionStudyCollectionDependencies({
    ...base,
    RECOGNITION_STUDY_PROMPT_PLAN_ID: "unreviewed-plan-v1",
  }), {});
  assert.deepEqual(createRecognitionStudyCollectionDependencies({
    ...base,
    RECOGNITION_STUDY_ED25519_PRIVATE_KEY_PKCS8_BASE64: "not-base64",
  }), {});
});

test("configured dependencies authenticate, prepare, commit, and sign", async () => {
  const key = await keyFixture();
  const calls = [];
  const ownerID = "00000000-0000-4000-8000-000000000001";
  const signedGrant = { schemaVersion: "placeholder" };
  const fetcher = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) {
      return Response.json({ id: ownerID });
    }
    if (String(url).endsWith("/rpc/prepare_recognition_study_capture_grant")) {
      return Response.json({
        authorizationEpoch: 9,
        consentBinding: { schemaVersion: "recognition-study-consent-binding-v1" },
      });
    }
    if (String(url).endsWith("/rpc/commit_recognition_study_capture_grant")) {
      const body = JSON.parse(init.body);
      return Response.json({
        signedGrant: body.target_signed_grant,
        signedGrantSHA256: body.target_signed_grant_sha256,
        status: "issued",
        stored: true,
      });
    }
    throw new Error("unexpected URL");
  };
  const dependencies = createRecognitionStudyCollectionDependencies(
    {
      RECOGNITION_STUDY_ED25519_PRIVATE_KEY_PKCS8_BASE64: key.pkcs8Base64,
      RECOGNITION_STUDY_PROMPT_PLAN_ID: "coverage-pilot-v2",
      RECOGNITION_STUDY_SIGNING_KEY_ID: "pilot-key-1",
      SUPABASE_SERVICE_ROLE_KEY: "service-secret",
      SUPABASE_URL: "https://example.supabase.co",
    },
    {
      fetch: fetcher,
      nowUnixSeconds: () => 123,
      randomUUID: () => "00000000-0000-4000-8000-000000000099",
    },
  );

  assert.equal(
    await dependencies.authenticatedUserID(new Request("https://example.test", {
      headers: { authorization: "Bearer user-session" },
    })),
    ownerID,
  );
  assert.equal((await dependencies.prepareGrant(ownerID)).authorizationEpoch, 9);
  assert.deepEqual(
    await dependencies.commitGrant({
      clientRequestID: "00000000-0000-4000-8000-000000000002",
      grant: signedGrant,
      ownerID,
      signedGrantSHA256: "ab".repeat(32),
    }),
    {
      signedGrant,
      signedGrantSHA256: "ab".repeat(32),
      status: "issued",
      stored: true,
    },
  );

  const payload = new TextEncoder().encode("exact-payload");
  const signature = await dependencies.signPayload(payload);
  assert.equal(
    await globalThis.crypto.subtle.verify(
      { name: "Ed25519" },
      key.keyPair.publicKey,
      signature,
      payload,
    ),
    true,
  );
  assert.equal(dependencies.signingKeyID, "pilot-key-1");
  assert.deepEqual(dependencies.promptPlan, promptPlan);
  assert.equal(dependencies.nowUnixSeconds(), 123);
  assert.equal(dependencies.randomUUID(), "00000000-0000-4000-8000-000000000099");

  const prepareCall = calls.find((call) => call.url.includes("/rpc/prepare_"));
  assert.deepEqual(JSON.parse(prepareCall.init.body), { target_owner_id: ownerID });
  assert.equal(prepareCall.init.headers.apikey, "service-secret");
  assert.equal(prepareCall.init.headers.authorization, undefined);
  const commitCall = calls.find((call) => call.url.includes("/rpc/commit_"));
  assert.deepEqual(JSON.parse(commitCall.init.body), {
    target_client_request_id: "00000000-0000-4000-8000-000000000002",
    target_owner_id: ownerID,
    target_signed_grant: signedGrant,
    target_signed_grant_sha256: "ab".repeat(32),
  });
});

test("prompt plans are frozen reviewed artifacts without cohort authority", () => {
  assert.equal(recognitionStudyPromptPlanForID("missing-plan"), null);
  assert.equal(recognitionStudyPromptPlanForID("coverage-pilot-v1"), null);
  assert.equal(Object.isFrozen(promptPlan), true);
  assert.equal(Object.isFrozen(promptPlan.captureTickets), true);
  assert.equal(promptPlan.captureTickets.length, 17);
  assert.equal(promptPlan.datasetVersion, "capture-pilot-v2");
  assert.equal(promptPlan.promptPlanVersion, "coverage-pilot-v2");

  const negativePrompts = promptPlan.captureTickets.filter(
    (ticket) => ticket.promptKind === "open-set-negative",
  );
  assert.equal(negativePrompts.length, 3);
  assert.equal(
    negativePrompts.every((ticket) => ticket.displayText.includes("not a chord symbol")),
    true,
  );
  assert.equal(
    negativePrompts.some((ticket) => ticket.displayText === "Write any chord you choose"),
    false,
  );
  assert.equal(
    new Set(promptPlan.captureTickets.map((ticket) => ticket.promptID)).size,
    promptPlan.captureTickets.length,
  );

  const encoded = JSON.stringify(promptPlan).toLowerCase();
  for (const forbidden of [
    "groundtruth",
    "corpuseligible",
    "sealed-holdout",
    "training-split",
    "evaluation-split",
    "writerid",
    "personid",
  ]) {
    assert.equal(encoded.includes(forbidden), false);
  }
});

test("legacy service-role JWT fallback remains bearer compatible", async () => {
  const key = await keyFixture();
  const calls = [];
  const legacyJWT = "header.payload.signature";
  const dependencies = createRecognitionStudyCollectionDependencies(
    {
      RECOGNITION_STUDY_ED25519_PRIVATE_KEY_PKCS8_BASE64: key.pkcs8Base64,
      RECOGNITION_STUDY_PROMPT_PLAN_ID: "coverage-pilot-v2",
      RECOGNITION_STUDY_SIGNING_KEY_ID: "pilot-key-1",
      SUPABASE_SERVICE_ROLE_KEY: legacyJWT,
      SUPABASE_URL: "https://example.supabase.co",
    },
    {
      fetch: async (url, init) => {
        calls.push({ url: String(url), init });
        return Response.json({ authorizationEpoch: 1, consentBinding: {} });
      },
    },
  );

  await dependencies.prepareGrant("00000000-0000-4000-8000-000000000001");
  assert.equal(calls[0].init.headers.apikey, legacyJWT);
  assert.equal(calls[0].init.headers.authorization, `Bearer ${legacyJWT}`);
});

test("PKCS8 signer rejects noncanonical key material and verifies exact bytes", async () => {
  assert.equal(createEd25519Signer("%%%"), null);
  const key = await keyFixture();
  const signer = createEd25519Signer(key.pkcs8Base64);
  const payload = new TextEncoder().encode("signed-exactly-once");
  const signature = await signer(payload);
  assert.equal(
    await globalThis.crypto.subtle.verify(
      { name: "Ed25519" },
      key.keyPair.publicKey,
      signature,
      payload,
    ),
    true,
  );
});
