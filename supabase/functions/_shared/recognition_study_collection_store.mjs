import {
  authenticatedUserIDFromBearer,
  supabaseAuthorityStoreConfigurationFromEnv,
} from "./supabase_subscription_authority_store.mjs";

export function createRecognitionStudyCollectionDependencies(
  env = globalThis.Deno?.env,
  options = {},
) {
  const configuration = supabaseAuthorityStoreConfigurationFromEnv(env);
  const signingKeyID = normalizedString(envValue(env, "RECOGNITION_STUDY_SIGNING_KEY_ID"));
  const signingPrivateKey = normalizedString(
    envValue(env, "RECOGNITION_STUDY_ED25519_PRIVATE_KEY_PKCS8_BASE64"),
  );
  const promptPlan = recognitionStudyPromptPlanForID(
    normalizedString(envValue(env, "RECOGNITION_STUDY_PROMPT_PLAN_ID")),
  );
  const fetcher = options.fetch ?? fetch;
  const subtle = options.subtle ?? globalThis.crypto?.subtle;
  const randomUUID = options.randomUUID ?? (() => globalThis.crypto.randomUUID());
  const nowUnixSeconds = options.nowUnixSeconds
    ?? (() => Math.floor(Date.now() / 1_000));

  if (
    configuration === null
    || signingKeyID.length === 0
    || signingPrivateKey.length === 0
    || promptPlan === null
    || subtle === undefined
  ) {
    return {};
  }
  const signer = createEd25519Signer(signingPrivateKey, subtle);
  if (signer === null) {
    return {};
  }

  return {
    authenticatedUserID: (request) => authenticatedUserIDFromBearer(
      request,
      configuration,
      fetcher,
    ),
    commitGrant: (value) => commitRecognitionStudyCaptureGrant(
      configuration,
      value,
      fetcher,
    ),
    nowUnixSeconds,
    prepareGrant: (ownerID) => prepareRecognitionStudyCaptureGrant(
      configuration,
      ownerID,
      fetcher,
    ),
    promptPlan,
    randomUUID,
    signPayload: signer,
    signingKeyID,
  };
}

export function recognitionStudyPromptPlanForID(promptPlanID) {
  return collectionSafePromptPlansByID[promptPlanID] ?? null;
}

export async function prepareRecognitionStudyCaptureGrant(
  configuration,
  ownerID,
  fetcher = fetch,
) {
  return callSupabaseRPC(
    configuration,
    "prepare_recognition_study_capture_grant",
    { target_owner_id: ownerID },
    fetcher,
  );
}

export async function commitRecognitionStudyCaptureGrant(
  configuration,
  {
    clientRequestID,
    grant,
    ownerID,
    signedGrantSHA256,
  },
  fetcher = fetch,
) {
  const value = await callSupabaseRPC(
    configuration,
    "commit_recognition_study_capture_grant",
    {
      target_client_request_id: clientRequestID,
      target_owner_id: ownerID,
      target_signed_grant: grant,
      target_signed_grant_sha256: signedGrantSHA256,
    },
    fetcher,
  );
  return {
    signedGrant: value?.signedGrant,
    signedGrantSHA256: value?.signedGrantSHA256,
    status: value?.status,
    stored: value?.stored,
  };
}

export function createEd25519Signer(privateKeyPKCS8Base64, subtle = globalThis.crypto?.subtle) {
  if (subtle === undefined) {
    return null;
  }
  const privateKeyBytes = canonicalBase64Bytes(privateKeyPKCS8Base64);
  if (privateKeyBytes === null) {
    return null;
  }
  let keyPromise;
  return async (payload) => {
    if (keyPromise === undefined) {
      keyPromise = subtle.importKey(
        "pkcs8",
        privateKeyBytes,
        { name: "Ed25519" },
        false,
        ["sign"],
      );
    }
    const key = await keyPromise;
    return subtle.sign({ name: "Ed25519" }, key, payload);
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
    throw new Error(`Supabase RPC ${functionName} returned invalid JSON.`);
  }
  if (!response.ok) {
    throw new Error(`Supabase RPC ${functionName} failed with ${response.status}.`);
  }
  return value;
}

function isLegacyJWT(value) {
  return typeof value === "string"
    && value.split(".").length === 3
    && !value.startsWith("sb_secret_");
}

function canonicalBase64Bytes(value) {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  try {
    const binary = atob(value);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    let encoded = "";
    for (const byte of bytes) {
      encoded += String.fromCharCode(byte);
    }
    if (btoa(encoded) !== value) {
      return null;
    }
    return bytes;
  } catch {
    return null;
  }
}

function normalizedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function envValue(env, key) {
  if (env === undefined || env === null) {
    return undefined;
  }
  if (typeof env.get === "function") {
    return env.get(key);
  }
  return env[key];
}

function frozenPrompt({
  displayText,
  presentedChartStyle = "simple-chord-sheet",
  presentedConstruction = "root-first",
  presentedPace = "natural",
  presentedSize = "normal",
  promptID,
  promptKind = "isolated-chord",
  requestedOrientation = "portrait",
}) {
  return Object.freeze({
    displayText,
    presentedChartStyle,
    presentedConstruction,
    presentedPace,
    presentedSize,
    promptID,
    promptKind,
    requestedOrientation,
  });
}

const collectionSafePromptPlansByID = Object.freeze({
  "coverage-pilot-v2": Object.freeze({
    captureTickets: Object.freeze([
      frozenPrompt({ displayText: "C", promptID: "isolated-c-major" }),
      frozenPrompt({ displayText: "Bb", promptID: "isolated-b-flat-major" }),
      frozenPrompt({ displayText: "F#-7", promptID: "isolated-f-sharp-minor-seven" }),
      frozenPrompt({ displayText: "Eb△7", promptID: "isolated-e-flat-major-seven" }),
      frozenPrompt({ displayText: "Dø7", promptID: "isolated-d-half-diminished-seven" }),
      frozenPrompt({ displayText: "G7(b9)", promptID: "isolated-g-seven-flat-nine" }),
      frozenPrompt({ displayText: "A13", promptID: "isolated-a-thirteen" }),
      frozenPrompt({ displayText: "C/E", promptID: "isolated-c-over-e" }),
      frozenPrompt({ displayText: "Db△9", promptID: "isolated-d-flat-major-nine" }),
      frozenPrompt({ displayText: "B7sus", promptID: "isolated-b-seven-sus" }),
      frozenPrompt({
        displayText: "C-7 | F7 | Bb△7 | Eb△7",
        presentedChartStyle: "rhythm-section-sheet",
        presentedConstruction: "mixed-or-retraced",
        promptID: "row-c-minor-seven-to-e-flat-major-seven",
        promptKind: "realistic-row",
        requestedOrientation: "landscape",
      }),
      frozenPrompt({
        displayText: "F#ø7 | B7(b9) | E-7 | A7",
        presentedConstruction: "modifier-first",
        presentedPace: "careful",
        presentedSize: "large",
        promptID: "row-f-sharp-half-diminished-to-a-seven",
        promptKind: "realistic-row",
        requestedOrientation: "landscape",
      }),
      frozenPrompt({
        displayText: "Db△9 | G7(#11) | C-7 | F7",
        presentedChartStyle: "rhythm-section-sheet",
        presentedConstruction: "mixed-or-retraced",
        presentedPace: "fast",
        presentedSize: "small",
        promptID: "row-d-flat-major-nine-to-f-seven",
        promptKind: "realistic-row",
        requestedOrientation: "landscape",
      }),
      frozenPrompt({
        displayText: "A-7 | D7 | G△7",
        presentedConstruction: "mixed-or-retraced",
        presentedPace: "careful",
        promptID: "row-a-minor-seven-to-g-major-seven",
        promptKind: "realistic-row",
      }),
      frozenPrompt({
        displayText: "Write a short rehearsal note (not a chord symbol)",
        presentedConstruction: "mixed-or-retraced",
        promptID: "negative-rehearsal-note",
        promptKind: "open-set-negative",
      }),
      frozenPrompt({
        displayText: "Draw a single rhythmic slash (not a chord symbol)",
        presentedChartStyle: "rhythm-section-sheet",
        presentedConstruction: "mixed-or-retraced",
        promptID: "negative-rhythmic-slash",
        promptKind: "open-set-negative",
        requestedOrientation: "landscape",
      }),
      frozenPrompt({
        displayText: "Write a section marker such as V2 (not a chord symbol)",
        presentedConstruction: "mixed-or-retraced",
        promptID: "negative-section-marker",
        promptKind: "open-set-negative",
      }),
    ]),
    datasetVersion: "capture-pilot-v2",
    minimumBuildNumber: 51,
    promptPlanVersion: "coverage-pilot-v2",
  }),
});
