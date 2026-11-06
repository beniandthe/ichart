import {
  authenticatedUserIDFromBearer,
  supabaseAuthorityStoreConfigurationFromEnv,
} from "./supabase_subscription_authority_store.mjs";

const deleteAccountConfirmation = "DELETE_MY_ICHART_ACCOUNT";
const forumPDFBucketID = "forum_chart_pdfs";
const maximumRequestBytes = 4 * 1024;
const cleanupPageSize = 1000;
const maximumCleanupListingPages = 1000;
const cleanupDeleteConcurrency = 10;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

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
  if (typeof ownerID !== "string" || !uuidPattern.test(ownerID.toLowerCase())) {
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
      const listed = await dependencies.listForumPDFStoragePaths(ownerID);
      if (!Array.isArray(listed)) throw new Error("Account storage inventory is invalid.");
      storagePaths = Array.from(new Set(listed.map((path) => ownedForumPDFPath(path, ownerID))));
    }
    if (storagePaths.length > 0 && typeof dependencies.deleteForumPDFStoragePaths !== "function") {
      throw new Error("Account storage cleanup is not configured.");
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
  const normalizedOwnerID = canonicalOwnerID(ownerID);
  const paths = new Set(await forumPostPDFPathsForOwner(configuration, normalizedOwnerID, fetcher));
  const listedStoragePaths = await storageFolderPathsForOwner(configuration, normalizedOwnerID, fetcher);
  for (const path of listedStoragePaths) {
    paths.add(path);
  }

  return Array.from(paths);
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
  const paths = [];
  let cursor = null;
  for (let page = 0; page < maximumCleanupListingPages; page += 1) {
    const url = supabaseURL(configuration, "/rest/v1/forum_chart_posts");
    url.searchParams.set("owner_id", `eq.${ownerID}`);
    url.searchParams.set("select", "id,pdf_storage_path");
    url.searchParams.set("order", "id.asc");
    url.searchParams.set("limit", String(cleanupPageSize));
    if (cursor !== null) url.searchParams.set("id", `gt.${cursor}`);

    const response = await fetcher(url, { method: "GET", headers: supabaseJSONHeaders(configuration) });
    const rows = cleanupRows(await parseSupabaseJSONResponse(response));
    if (rows.length === 0) return paths;
    for (const row of rows) {
      const id = typeof row?.id === "string" ? row.id.toLowerCase() : "";
      if (!uuidPattern.test(id) || (cursor !== null && id <= cursor)) {
        throw new Error("Account post inventory did not advance.");
      }
      paths.push(ownedForumPDFPath(row.pdf_storage_path, ownerID));
      cursor = id;
    }
  }
  throw new Error("Account post inventory exceeded its safe listing bound.");
}

async function storageFolderPathsForOwner(configuration, ownerID, fetcher) {
  const paths = [];
  const seen = new Set();
  let offset = 0;
  for (let page = 0; page < maximumCleanupListingPages; page += 1) {
    const response = await fetcher(
      supabaseURL(configuration, `/storage/v1/object/list/${forumPDFBucketID}`),
      {
        method: "POST",
        headers: supabaseJSONHeaders(configuration),
        body: JSON.stringify({ prefix: `${ownerID}/`, limit: cleanupPageSize, offset,
          sortBy: { column: "name", order: "asc" } }),
      }
    );
    // An unavailable listing is unknown, never evidence that storage is empty.
    const rows = cleanupRows(await parseSupabaseJSONResponse(response));
    if (rows.length === 0) return paths;
    for (const row of rows) {
      const name = row?.name;
      if (typeof name !== "string") throw new Error("Account storage inventory is invalid.");
      const path = ownedForumPDFPath(name.startsWith(`${ownerID}/`) ? name : `${ownerID}/${name}`, ownerID);
      if (seen.has(path)) throw new Error("Account storage inventory did not advance.");
      seen.add(path);
      paths.push(path);
    }
    // Advance by the actual page, including a lower server-side row cap.
    offset += rows.length;
  }
  throw new Error("Account storage inventory exceeded its safe listing bound.");
}

async function deleteForumPDFStoragePaths(configuration, paths, fetcher) {
  for (let start = 0; start < paths.length; start += cleanupDeleteConcurrency) {
    const results = await Promise.allSettled(paths.slice(start, start + cleanupDeleteConcurrency).map(async (path) => {
      const response = await fetcher(
        supabaseURL(configuration, `/storage/v1/object/${forumPDFBucketID}/${path.split("/").map(encodeURIComponent).join("/")}`),
        { method: "DELETE", headers: supabaseJSONHeaders(configuration) }
      );
      if (!response.ok && response.status !== 404) throw new Error("Forum PDF storage deletion failed.");
    }));
    if (results.some((result) => result.status === "rejected")) throw new Error("Forum PDF storage deletion failed.");
  }
}

function cleanupRows(value) {
  if (!Array.isArray(value) || value.length > cleanupPageSize
      || value.some((row) => row === null || typeof row !== "object" || Array.isArray(row))) {
    throw new Error("Account cleanup inventory is invalid.");
  }
  return value;
}

function canonicalOwnerID(value) {
  if (typeof value !== "string" || !uuidPattern.test(value.toLowerCase())) throw new Error("Account owner is invalid.");
  return value.toLowerCase();
}

function ownedForumPDFPath(value, ownerID) {
  const prefix = `${canonicalOwnerID(ownerID)}/`;
  if (typeof value !== "string" || value.length > 1024 || !value.startsWith(prefix)) {
    throw new Error("Account storage path is outside its owner scope.");
  }
  const name = value.slice(prefix.length);
  // Current uploads use UUID.pdf; keep ordinary legacy PDF names and their
  // case intact, but never traverse a nested folder or encoded path segment.
  if (!/^[^/\\%?#\u0000-\u001f\u007f]+\.pdf$/i.test(name) || name === ".pdf" || name.includes("..")) {
    throw new Error("Account storage path is invalid.");
  }
  return value;
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
