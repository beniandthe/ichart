import { authenticatedUserIDFromBearer } from "./supabase_subscription_authority_store.mjs";
import { RecognitionStudyConsentStoreError } from "./recognition_study_consent.mjs";

export function createRecognitionStudyConsentDependencies(
  env = globalThis.Deno?.env,
  options = {},
) {
  const configuration = recognitionStudyConsentStoreConfigurationFromEnv(env);
  if (configuration === null) {
    return {};
  }
  const fetcher = options.fetch ?? fetch;
  return {
    authenticatedUserID: (request) => authenticatedUserIDFromBearer(
      request,
      { supabaseURL: configuration.supabaseURL, secretKey: configuration.publicKey },
      fetcher,
    ),
    acceptConsent: (request, value) => callAuthenticatedRPC(
      configuration,
      request,
      "accept_recognition_study_consent",
      {
        target_client_request_id: value.clientRequestID,
        target_explicit_raw_stroke_authorization:
          value.explicitRawStrokeDonationAuthorization,
        target_presentation_id: value.presentationID,
        target_presentation_sha256: value.presentationSHA256,
      },
      fetcher,
    ),
    readConsentStatus: (request) => callAuthenticatedRPC(
      configuration,
      request,
      "recognition_study_consent_status",
      {},
      fetcher,
    ),
    withdrawConsent: (request, value) => callAuthenticatedRPC(
      configuration,
      request,
      "withdraw_recognition_study_consent_v2",
      {
        target_client_request_id: value.clientRequestID,
        target_consent_record_id: value.consentRecordID,
      },
      fetcher,
    ),
  };
}

export function recognitionStudyConsentStoreConfigurationFromEnv(env) {
  const supabaseURL = normalizedString(envValue(env, "SUPABASE_URL"));
  const publicKey = normalizedString(
    envValue(env, "SUPABASE_PUBLISHABLE_KEY")
      ?? envValue(env, "SUPABASE_ANON_KEY"),
  );
  if (supabaseURL.length === 0 || publicKey.length === 0) {
    return null;
  }
  return { publicKey, supabaseURL: supabaseURL.replace(/\/+$/, "") };
}

async function callAuthenticatedRPC(configuration, request, functionName, body, fetcher) {
  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer [^\s]+$/.test(authorization)) {
    throw new RecognitionStudyConsentStoreError("unauthorized");
  }
  const url = new URL(`/rest/v1/rpc/${functionName}`, `${configuration.supabaseURL}/`);
  const response = await fetcher(url, {
    method: "POST",
    headers: {
      accept: "application/json",
      apikey: configuration.publicKey,
      authorization,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  let value;
  try {
    value = await response.json();
  } catch {
    throw new RecognitionStudyConsentStoreError("unavailable");
  }
  if (!response.ok) {
    const message = typeof value?.message === "string" ? value.message : "";
    if (message.includes("reviewed consent presentation is unavailable")) {
      throw new RecognitionStudyConsentStoreError("policy_unavailable");
    }
    if (message.includes("request id was already used")
        || message.includes("active consent record already exists")) {
      throw new RecognitionStudyConsentStoreError("conflict");
    }
    if (message.includes("consent record was not found")) {
      throw new RecognitionStudyConsentStoreError("not_found");
    }
    throw new RecognitionStudyConsentStoreError("unavailable");
  }
  return value;
}

function normalizedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function envValue(env, key) {
  if (env === undefined || env === null) {
    return undefined;
  }
  return typeof env.get === "function" ? env.get(key) : env[key];
}
