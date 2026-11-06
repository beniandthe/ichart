export function createSupabaseSubscriptionAuthorityDependencies(env = globalThis.Deno?.env, options = {}) {
  const configuration = supabaseAuthorityStoreConfigurationFromEnv(env);
  const fetcher = options.fetch ?? fetch;

  if (configuration === null) {
    return {};
  }

  return {
    authenticatedUserID: (request) => authenticatedUserIDFromBearer(request, configuration, fetcher),
    writeSubscriptionAuthority: (authorityUpdate) => updateMappedSubscriptionAuthority(
      configuration,
      authorityUpdate,
      fetcher
    ),
    writeSubscriptionAuthorityClaim: ({ ownerID, authorityUpdate }) => upsertSubscriptionAuthorityClaim(
      configuration,
      ownerID,
      authorityUpdate,
      fetcher
    ),
  };
}

export function supabaseAuthorityStoreConfigurationFromEnv(env) {
  const supabaseURL = normalizedString(envValue(env, "SUPABASE_URL"));
  const secretKey = supabaseSecretKeyFromEnv(env);

  if (supabaseURL.length === 0 || secretKey.length === 0) {
    return null;
  }

  return {
    supabaseURL: supabaseURL.replace(/\/+$/, ""),
    secretKey,
  };
}

export function supabaseSecretKeyFromEnv(env) {
  const secretKeysJSON = normalizedString(envValue(env, "SUPABASE_SECRET_KEYS"));
  if (secretKeysJSON.length > 0) {
    try {
      const secretKeys = JSON.parse(secretKeysJSON);
      const defaultKey = normalizedString(secretKeys?.default);
      if (defaultKey.length > 0) {
        return defaultKey;
      }

      const firstKey = Object.values(secretKeys ?? {})
        .map(normalizedString)
        .find((value) => value.length > 0);
      if (firstKey !== undefined) {
        return firstKey;
      }
    } catch {
      return "";
    }
  }

  return normalizedString(envValue(env, "SUPABASE_SERVICE_ROLE_KEY"));
}

export async function authenticatedUserIDFromBearer(request, configuration, fetcher = fetch) {
  const bearerToken = bearerTokenFromRequest(request);
  if (bearerToken === null) {
    return null;
  }

  const response = await fetcher(supabaseURL(configuration, "/auth/v1/user"), {
    method: "GET",
    headers: {
      apikey: configuration.secretKey,
      authorization: `Bearer ${bearerToken}`,
      accept: "application/json",
    },
  });

  if (response.status === 401 || response.status === 403) {
    return null;
  }

  const user = await parseSupabaseJSONResponse(response);
  const userID = normalizedString(user?.id);
  return userID.length > 0 ? userID : null;
}

export async function upsertSubscriptionAuthorityClaim(
  configuration,
  ownerID,
  authorityUpdate,
  fetcher = fetch
) {
  const normalizedOwnerID = normalizedString(ownerID);
  const originalTransactionID = normalizedString(authorityUpdate?.storekit_original_transaction_id);
  if (originalTransactionID.length === 0) {
    return {
      stored: false,
      mapping_status: "missing_original_transaction",
    };
  }

  return applySubscriptionAuthorityRPC(configuration, authorityUpdate, normalizedOwnerID, fetcher);
}

export async function updateMappedSubscriptionAuthority(configuration, authorityUpdate, fetcher = fetch) {
  const originalTransactionID = normalizedString(authorityUpdate?.storekit_original_transaction_id);
  if (originalTransactionID.length === 0) {
    return {
      stored: false,
      mapping_status: "missing_original_transaction",
    };
  }

  return applySubscriptionAuthorityRPC(configuration, authorityUpdate, null, fetcher);
}

async function applySubscriptionAuthorityRPC(configuration, authorityUpdate, claimOwnerID, fetcher) {
  // The transaction locks and rechecks ownership/order, acknowledges the
  // notification UUID, and changes authority together. Never fall back to
  // separate REST writes: a failed authority update must remain retryable.
  const response = await fetcher(supabaseURL(configuration, "/rest/v1/rpc/apply_storekit_subscription_authority"), {
    method: "POST",
    headers: supabaseRESTHeaders(configuration),
    body: JSON.stringify({ authority_update: authorityUpdate, claim_owner_id: claimOwnerID }),
  });
  const result = await parseSupabaseJSONResponse(response);
  const allowedStatuses = claimOwnerID === null
    ? new Set(["missing_original_transaction", "unmapped_original_transaction", "duplicate_notification", "stale_notification", "updated"])
    : new Set(["missing_original_transaction", "original_transaction_owner_conflict", "stale_transaction_claim", "claimed"]);
  if (
    result === null
    || typeof result !== "object"
    || Array.isArray(result)
    || typeof result.stored !== "boolean"
    || !allowedStatuses.has(result.mapping_status)
    || result.stored !== ["updated", "claimed"].includes(result.mapping_status)
  ) {
    throw new Error("Supabase subscription authority returned an invalid transaction result.");
  }
  return result;
}

function envValue(env, key) {
  if (env && typeof env.get === "function") {
    return env.get(key);
  }

  return env?.[key];
}

function supabaseURL(configuration, path) {
  return new URL(path, `${configuration.supabaseURL}/`);
}

function supabaseRESTHeaders(configuration, prefer) {
  const headers = {
    apikey: configuration.secretKey,
    authorization: `Bearer ${configuration.secretKey}`,
    "content-type": "application/json",
    accept: "application/json",
  };
  if (prefer !== undefined) {
    headers.prefer = prefer;
  }

  return headers;
}

async function parseSupabaseJSONResponse(response) {
  const text = await response.text();

  if (!response.ok) {
    throw new Error(`Supabase subscription authority request failed with status ${response.status}.`);
  }

  if (text.trim().length === 0) {
    return null;
  }

  return JSON.parse(text);
}

function bearerTokenFromRequest(request) {
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(\S+)$/i);
  return match?.[1] ?? null;
}

function normalizedString(value) {
  if (value === null || value === undefined) {
    return "";
  }

  return String(value).trim();
}
