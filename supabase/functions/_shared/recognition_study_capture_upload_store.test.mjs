import assert from "node:assert/strict";
import test from "node:test";

import {
  consumeRecognitionStudyCapture,
  createRecognitionStudyCaptureUploadDependencies,
} from "./recognition_study_capture_upload_store.mjs";
import {
  RecognitionStudyCaptureConsumeError,
} from "./recognition_study_capture_upload.mjs";

const ownerID = "00000000-0000-4000-8000-000000000001";
const captureAuthorizationID = "00000000-0000-4000-8000-000000000201";

function captureValue() {
  return {
    ownerID,
    captureAuthorizationID,
    signedGrantSHA256: "ab".repeat(32),
    envelope: { schemaVersion: "envelope" },
    envelopeSHA256: "cd".repeat(32),
    canonicalPacketBase64: "e30=",
    canonicalPacketSHA256: "ef".repeat(32),
    canonicalPacketByteCount: 2,
  };
}

function receipt() {
  return {
    accepted: true,
    canonicalPacketByteCount: 2,
    canonicalPacketSHA256: "ef".repeat(32),
    captureAuthorizationID,
    envelopeSHA256: "cd".repeat(32),
    grantCompleted: false,
    receiptID: "00000000-0000-4000-8000-000000000401",
    receivedAtUnixMilliseconds: 1_100_100,
    replayed: false,
    schemaVersion: "recognition-study-capture-receipt-v1",
  };
}

test("dependency factory stays disabled without Supabase server authority", () => {
  assert.deepEqual(createRecognitionStudyCaptureUploadDependencies({}), {});
  assert.deepEqual(createRecognitionStudyCaptureUploadDependencies({
    SUPABASE_URL: "https://example.supabase.co",
  }), {});
});

test("configured dependency authenticates and sends exact consume RPC fields", async () => {
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) {
      return Response.json({ id: ownerID });
    }
    if (String(url).endsWith("/rpc/consume_recognition_study_capture")) {
      return Response.json(receipt());
    }
    throw new Error("unexpected URL");
  };
  const dependencies = createRecognitionStudyCaptureUploadDependencies(
    {
      SUPABASE_SERVICE_ROLE_KEY: "service-secret",
      SUPABASE_URL: "https://example.supabase.co",
    },
    { fetch: fetcher, nowUnixSeconds: () => 1_100 },
  );

  assert.equal(
    await dependencies.authenticatedUserID(new Request("https://example.test", {
      headers: { authorization: "Bearer user-session" },
    })),
    ownerID,
  );
  assert.deepEqual(await dependencies.consumeCapture(captureValue()), receipt());
  assert.equal(dependencies.nowUnixSeconds(), 1_100);

  const rpc = calls.find((call) => call.url.endsWith(
    "/rpc/consume_recognition_study_capture",
  ));
  assert.deepEqual(JSON.parse(rpc.init.body), {
    target_owner_id: ownerID,
    target_capture_authorization_id: captureAuthorizationID,
    target_signed_grant_sha256: "ab".repeat(32),
    target_envelope: { schemaVersion: "envelope" },
    target_envelope_sha256: "cd".repeat(32),
    target_packet_base64: "e30=",
    target_packet_sha256: "ef".repeat(32),
    target_packet_byte_count: 2,
  });
  assert.equal(rpc.init.headers.apikey, "service-secret");
  assert.equal(rpc.init.headers.authorization, undefined);
});

test("legacy service-role JWT is used only for compatibility bearer auth", async () => {
  const calls = [];
  await consumeRecognitionStudyCapture(
    {
      secretKey: "header.payload.signature",
      supabaseURL: "https://example.supabase.co",
    },
    captureValue(),
    async (url, init) => {
      calls.push({ url: String(url), init });
      return Response.json(receipt());
    },
  );
  assert.equal(calls[0].init.headers.apikey, "header.payload.signature");
  assert.equal(
    calls[0].init.headers.authorization,
    "Bearer header.payload.signature",
  );
});

test("RPC failures distinguish terminal authorization from retryable service failure", async () => {
  for (const [message, expected] of [
    ["active raw-stroke research consent is required", "inactive"],
    ["capture ticket was already used with different bytes", "conflict"],
    ["database unavailable", "unavailable"],
  ]) {
    await assert.rejects(
      consumeRecognitionStudyCapture(
        {
          secretKey: "service-secret",
          supabaseURL: "https://example.supabase.co",
        },
        captureValue(),
        async () => Response.json({ message }, { status: 400 }),
      ),
      (error) => error instanceof RecognitionStudyCaptureConsumeError
        && error.disposition === expected,
    );
  }
});
