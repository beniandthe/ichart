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
  const row = {
    owner_id: normalizedString(ownerID),
    ...authorityUpdate,
  };
  const url = supabaseURL(configuration, "/rest/v1/subscriptions");
  url.searchParams.set("on_conflict", "owner_id");

  const response = await fetcher(url, {
    method: "POST",
    headers: supabaseRESTHeaders(configuration, "resolution=merge-duplicates,return=representation"),
    body: JSON.stringify(row),
  });
  const rows = responseRows(await parseSupabaseJSONResponse(response));

  return {
    stored: true,
    mapping_status: "claimed",
    subscription: rows[0] ?? row,
  };
}

export async function updateMappedSubscriptionAuthority(configuration, authorityUpdate, fetcher = fetch) {
  const originalTransactionID = normalizedString(authorityUpdate?.storekit_original_transaction_id);
  if (originalTransactionID.length === 0) {
    return {
      stored: false,
      mapping_status: "missing_original_transaction",
    };
  }

  const url = supabaseURL(configuration, "/rest/v1/subscriptions");
  url.searchParams.set("storekit_original_transaction_id", `eq.${originalTransactionID}`);

  const response = await fetcher(url, {
    method: "PATCH",
    headers: supabaseRESTHeaders(configuration, "return=representation"),
    body: JSON.stringify(authorityUpdate),
  });
  const rows = responseRows(await parseSupabaseJSONResponse(response));

  if (rows.length === 0) {
    return {
      stored: false,
      mapping_status: "unmapped_original_transaction",
    };
  }

  return {
    stored: true,
    mapping_status: "updated",
    subscription: rows[0],
  };
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
  return {
    apikey: configuration.secretKey,
    authorization: `Bearer ${configuration.secretKey}`,
    "content-type": "application/json",
    accept: "application/json",
    prefer,
  };
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

function responseRows(value) {
  if (Array.isArray(value)) {
    return value;
  }

  if (value === null || value === undefined) {
    return [];
  }

  return [value];
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
