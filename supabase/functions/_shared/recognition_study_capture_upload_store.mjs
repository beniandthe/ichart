import {
  authenticatedUserIDFromBearer,
  supabaseAuthorityStoreConfigurationFromEnv,
} from "./supabase_subscription_authority_store.mjs";
import {
  RecognitionStudyCaptureConsumeError,
} from "./recognition_study_capture_upload.mjs";

export function createRecognitionStudyCaptureUploadDependencies(
  env = globalThis.Deno?.env,
  options = {},
) {
  const configuration = supabaseAuthorityStoreConfigurationFromEnv(env);
  if (configuration === null) {
    return {};
  }
  const fetcher = options.fetch ?? fetch;
  return {
    authenticatedUserID: (request) => authenticatedUserIDFromBearer(
      request,
      configuration,
      fetcher,
    ),
    consumeCapture: (value) => consumeRecognitionStudyCapture(
      configuration,
      value,
      fetcher,
    ),
    nowUnixSeconds: options.nowUnixSeconds
      ?? (() => Math.floor(Date.now() / 1_000)),
    subtle: options.subtle ?? globalThis.crypto?.subtle,
  };
}

export async function consumeRecognitionStudyCapture(
  configuration,
  {
    ownerID,
    captureAuthorizationID,
    signedGrantSHA256,
    envelope,
    envelopeSHA256,
    canonicalPacketBase64,
    canonicalPacketSHA256,
    canonicalPacketByteCount,
  },
  fetcher = fetch,
) {
  const value = await callSupabaseRPC(
    configuration,
    "consume_recognition_study_capture",
    {
      target_owner_id: ownerID,
      target_capture_authorization_id: captureAuthorizationID,
      target_signed_grant_sha256: signedGrantSHA256,
      target_envelope: envelope,
      target_envelope_sha256: envelopeSHA256,
      target_packet_base64: canonicalPacketBase64,
      target_packet_sha256: canonicalPacketSHA256,
      target_packet_byte_count: canonicalPacketByteCount,
    },
    fetcher,
  );
  return {
    accepted: value?.accepted,
    canonicalPacketByteCount: value?.canonicalPacketByteCount,
    canonicalPacketSHA256: value?.canonicalPacketSHA256,
    captureAuthorizationID: value?.captureAuthorizationID,
    envelopeSHA256: value?.envelopeSHA256,
    grantCompleted: value?.grantCompleted,
    receiptID: value?.receiptID,
    receivedAtUnixMilliseconds: value?.receivedAtUnixMilliseconds,
    replayed: value?.replayed,
    schemaVersion: value?.schemaVersion,
  };
}

async function callSupabaseRPC(configuration, functionName, body, fetcher) {
  const url = new URL(
    `/rest/v1/rpc/${functionName}`,
    `${configuration.supabaseURL}/`,
  );
  const response = await fetcher(url, {
    method: "POST",
    headers: {
      accept: "application/json",
      apikey: configuration.secretKey,
      "content-type": "application/json",
      ...(isLegacyJWT(configuration.secretKey)
        ? { authorization: `Bearer ${configuration.secretKey}` }
        : {}),
    },
    body: JSON.stringify(body),
  });
  let value;
  try {
    value = await response.json();
  } catch {
    throw new RecognitionStudyCaptureConsumeError("unavailable");
  }
  if (!response.ok) {
    const message = typeof value?.message === "string" ? value.message : "";
    if (
      message.includes("active raw-stroke research consent is required")
      || message.includes("capture authorization is not active")
      || message.includes("capture authorization was not found")
      || message.includes("capture authorization changed")
    ) {
      throw new RecognitionStudyCaptureConsumeError("inactive");
    }
    if (
      message.includes("already used with different bytes")
      || message.includes("digest does not match authorization")
      || message.includes("envelope does not match")
    ) {
      throw new RecognitionStudyCaptureConsumeError("conflict");
    }
    throw new RecognitionStudyCaptureConsumeError("unavailable");
  }
  return value;
}

function isLegacyJWT(value) {
  return typeof value === "string"
    && value.split(".").length === 3
    && !value.startsWith("sb_secret_");
}
