import {
  authenticatedUserIDFromBearer,
  supabaseAuthorityStoreConfigurationFromEnv,
} from "./supabase_subscription_authority_store.mjs";

const deleteAccountConfirmation = "DELETE_MY_ICHART_ACCOUNT";
const forumPDFBucketID = "forum_chart_pdfs";
const maximumRequestBytes = 4 * 1024;

export function createAccountDeletionDependencies(env = globalThis.Deno?.env, options = {}) {
  const configuration = supabaseAuthorityStoreConfigurationFromEnv(env);
  const fetcher = options.fetch ?? fetch;

  if (configuration === null) {
    return {};
  }

  return {
    authenticatedUserID: (request) => authenticatedUserIDFromBearer(request, configuration, fetcher),
    listForumPDFStoragePaths: (ownerID) => listForumPDFStoragePaths(configuration, ownerID, fetcher),
    prepareAccountDeletion: (ownerID) => prepareAccountDeletion(configuration, ownerID, fetcher),
    deleteForumPDFStoragePaths: (paths) => deleteForumPDFStoragePaths(configuration, paths, fetcher),
    deleteAuthUser: (ownerID) => deleteAuthUser(configuration, ownerID, fetcher),
  };
}

export async function handleAccountDeletionRequest(request, dependencies = {}) {
  if (request.method !== "POST") {
    return jsonResponse(405, {
      accepted: false,
      error: "Use POST to delete an iChart account.",
    });
  }

  if (typeof dependencies.authenticatedUserID !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "Account deletion is not configured.",
    });
  }

  const body = await boundedJSON(request, maximumRequestBytes);
  if (!body.ok) {
    return jsonResponse(body.tooLarge ? 413 : 400, {
      accepted: false,
      error: body.tooLarge
        ? "Account deletion request is too large."
        : "Account deletion request must be valid JSON.",
    });
  }

  if (normalizedString(body.value?.confirmation) !== deleteAccountConfirmation) {
    return jsonResponse(400, {
      accepted: false,
      error: "Account deletion confirmation is required.",
    });
  }

  const ownerID = await dependencies.authenticatedUserID(request);
  if (ownerID === null) {
    return jsonResponse(401, {
      accepted: false,
      error: "A signed-in iChart account is required.",
    });
  }

  if (typeof dependencies.deleteAuthUser !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "Account deletion authority is not configured.",
    });
  }

  if (typeof dependencies.prepareAccountDeletion !== "function") {
    return jsonResponse(501, {
      accepted: false,
      error: "Account deletion database preparation is not configured.",
    });
  }

  try {
    let storagePaths = [];
    if (typeof dependencies.listForumPDFStoragePaths === "function") {
      storagePaths = await dependencies.listForumPDFStoragePaths(ownerID);
    }

    await dependencies.prepareAccountDeletion(ownerID);

    if (storagePaths.length > 0 && typeof dependencies.deleteForumPDFStoragePaths === "function") {
      await dependencies.deleteForumPDFStoragePaths(storagePaths);
    }

    await dependencies.deleteAuthUser(ownerID);

    return jsonResponse(202, {
      accepted: true,
      account_deleted: true,
      forum_pdf_storage_paths_deleted: storagePaths.length,
    });
  } catch {
    return jsonResponse(502, {
      accepted: false,
      error: "Account deletion could not be completed. Try again or contact support.",
    });
  }
}

async function listForumPDFStoragePaths(configuration, ownerID, fetcher) {
  const normalizedOwnerID = normalizedString(ownerID).toLowerCase();
  const paths = new Set(await forumPostPDFPathsForOwner(configuration, normalizedOwnerID, fetcher));
  const listedStoragePaths = await storageFolderPathsForOwner(configuration, normalizedOwnerID, fetcher);
  for (const path of listedStoragePaths) {
    paths.add(path);
  }

  return Array.from(paths).filter((path) => path.startsWith(`${normalizedOwnerID}/`));
}

async function prepareAccountDeletion(configuration, ownerID, fetcher) {
  const response = await fetcher(
    supabaseURL(configuration, "/rest/v1/rpc/prepare_account_deletion"),
    {
      method: "POST",
      headers: supabaseJSONHeaders(configuration),
      body: JSON.stringify({ target_owner_id: normalizedString(ownerID).toLowerCase() }),
    }
  );

  await parseSupabaseJSONResponse(response);
}

async function forumPostPDFPathsForOwner(configuration, ownerID, fetcher) {
  const url = supabaseURL(configuration, "/rest/v1/forum_chart_posts");
  url.searchParams.set("owner_id", `eq.${ownerID}`);
  url.searchParams.set("select", "pdf_storage_path");

  const response = await fetcher(url, {
    method: "GET",
    headers: supabaseJSONHeaders(configuration),
  });
  const rows = responseRows(await parseSupabaseJSONResponse(response));
  return rows
    .map((row) => normalizedString(row?.pdf_storage_path).toLowerCase())
    .filter((path) => path.length > 0);
}

async function storageFolderPathsForOwner(configuration, ownerID, fetcher) {
  const response = await fetcher(
    supabaseURL(configuration, `/storage/v1/object/list/${forumPDFBucketID}`),
    {
      method: "POST",
      headers: supabaseJSONHeaders(configuration),
      body: JSON.stringify({
        prefix: `${ownerID}/`,
        limit: 1000,
        offset: 0,
      }),
    }
  );

  if (!response.ok) {
    return [];
  }

  const rows = responseRows(await parseSupabaseJSONResponse(response));
  return rows
    .map((row) => normalizedString(row?.name).toLowerCase())
    .filter((name) => name.length > 0)
    .map((name) => name.startsWith(`${ownerID}/`) ? name : `${ownerID}/${name}`);
}

async function deleteForumPDFStoragePaths(configuration, paths, fetcher) {
  for (const path of paths) {
    const response = await fetcher(
      supabaseURL(
        configuration,
        `/storage/v1/object/${forumPDFBucketID}/${path.split("/").map(encodeURIComponent).join("/")}`
      ),
      {
        method: "DELETE",
        headers: supabaseJSONHeaders(configuration),
      }
    );

    if (!response.ok && response.status !== 404) {
      throw new Error("Forum PDF storage deletion failed.");
    }
  }
}

async function deleteAuthUser(configuration, ownerID, fetcher) {
  const response = await fetcher(
    supabaseURL(configuration, `/auth/v1/admin/users/${encodeURIComponent(ownerID)}`),
    {
      method: "DELETE",
      headers: supabaseJSONHeaders(configuration),
    }
  );

  if (!response.ok) {
    throw new Error("Supabase Auth user deletion failed.");
  }
}

async function boundedJSON(request, maxBytes) {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    return { ok: false, tooLarge: true };
  }

  try {
    const readResult = await readBoundedText(request, maxBytes);
    if (!readResult.ok) {
      return { ok: false, tooLarge: true };
    }

    const text = readResult.text;
    return { ok: true, value: text.trim().length === 0 ? {} : JSON.parse(text) };
  } catch {
    return { ok: false, tooLarge: false };
  }
}

async function readBoundedText(request, maxBytes) {
  if (request.body === null) {
    return { ok: true, text: "" };
  }

  const reader = request.body.getReader();
  const chunks = [];
  let totalBytes = 0;

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    if (value === undefined) {
      continue;
    }

    const chunk = value instanceof Uint8Array ? value : new Uint8Array(value);
    totalBytes += chunk.byteLength;
    if (totalBytes > maxBytes) {
      try {
        await reader.cancel();
      } catch {
        // The response is already decided; stream cancellation is best effort.
      }
      return { ok: false, text: "" };
    }

    chunks.push(chunk);
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return {
    ok: true,
    text: new TextDecoder().decode(body),
  };
}

function supabaseURL(configuration, path) {
  return new URL(path, `${configuration.supabaseURL.replace(/\/+$/, "")}/`);
}

function supabaseJSONHeaders(configuration) {
  return {
    apikey: configuration.secretKey,
    authorization: `Bearer ${configuration.secretKey}`,
    accept: "application/json",
    "content-type": "application/json",
  };
}

async function parseSupabaseJSONResponse(response) {
  const text = await response.text();

  if (!response.ok) {
    throw new Error(`Supabase account deletion request failed with status ${response.status}.`);
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

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function normalizedString(value) {
  return `${value ?? ""}`.replace(/\s+/gu, " ").trim();
}
