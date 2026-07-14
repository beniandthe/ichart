import {
  authenticatedUserIDFromBearer,
  supabaseAuthorityStoreConfigurationFromEnv,
} from "./supabase_subscription_authority_store.mjs";

const maximumForumPDFBytes = 10 * 1024 * 1024;
const validForumPostStatuses = new Set(["pending", "published", "flagged", "hidden", "removed"]);

export function createForumPostActionDependencies(env = globalThis.Deno?.env, options = {}) {
  const configuration = supabaseAuthorityStoreConfigurationFromEnv(env);
  const fetcher = options.fetch ?? fetch;

  if (configuration === null) {
    return {};
  }

  return {
    authenticatedUserID: (request) => authenticatedUserIDFromBearer(request, configuration, fetcher),
    fetchPost: (postID) => fetchForumPost(configuration, postID, fetcher),
    fetchSong: (songID) => fetchForumSong(configuration, songID, fetcher),
    finalizePostPDF: (payload) => finalizeForumPostPDF(configuration, payload, fetcher),
    updatePostStatus: (payload) => updateForumPostStatus(configuration, payload, fetcher),
  };
}

export async function handleForumPostActionRequest(request, dependencies = {}) {
  if (request.method !== "POST") {
    return jsonResponse(405, { accepted: false, error: "Forum post actions require POST." });
  }

  const authenticatedUserID = dependencies.authenticatedUserID;
  if (typeof authenticatedUserID !== "function") {
    return jsonResponse(501, { accepted: false, error: "Authenticated user resolver is not configured." });
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { accepted: false, error: "Invalid forum post action JSON." });
  }

  const action = normalizedString(body?.action);
  const postID = normalizedString(body?.post_id);
  if (postID.length === 0) {
    return jsonResponse(400, { accepted: false, error: "Missing forum post id." });
  }

  const ownerID = await authenticatedUserID(request);
  if (ownerID === null) {
    return jsonResponse(401, { accepted: false, error: "A signed-in iChart account is required." });
  }

  const fetchPost = dependencies.fetchPost;
  if (typeof fetchPost !== "function") {
    return jsonResponse(501, { accepted: false, error: "Forum post store is not configured." });
  }

  const post = await fetchPost(postID);
  if (post === null) {
    return jsonResponse(404, { accepted: false, error: "Forum post was not found." });
  }

  if (normalizedString(post.owner_id) !== ownerID) {
    return jsonResponse(403, { accepted: false, error: "Forum post belongs to a different iChart account." });
  }

  if (!validForumPostStatuses.has(normalizedString(post.status))) {
    return jsonResponse(422, { accepted: false, error: "Forum post status is invalid." });
  }

  switch (action) {
  case "publish":
    return await handlePublishAction({ post, ownerID, body, dependencies });
  case "withdraw":
    return await handleWithdrawAction({ post, dependencies });
  case "remove":
    return await handleRemoveAction({ post, dependencies });
  default:
    return jsonResponse(400, { accepted: false, error: "Unsupported forum post action." });
  }
}

async function handlePublishAction({ post, ownerID, body, dependencies }) {
  const status = normalizedString(post.status);
  if (status === "published" || status === "flagged") {
    return jsonResponse(202, {
      accepted: true,
      action: "publish",
      state: "already_published",
      post,
    });
  }

  if (status !== "pending") {
    return jsonResponse(409, {
      accepted: false,
      error: "Only pending forum posts can be published.",
    });
  }

  const expectedStoragePath = `${ownerID.toLowerCase()}/${normalizedString(post.id).toLowerCase()}.pdf`;
  if (normalizedString(post.pdf_storage_path) !== expectedStoragePath) {
    return jsonResponse(422, {
      accepted: false,
      error: "Forum PDF storage path does not match the authenticated post owner.",
    });
  }

  const byteSize = Number(body?.byte_size);
  if (!Number.isSafeInteger(byteSize) || byteSize <= 0 || byteSize > maximumForumPDFBytes) {
    return jsonResponse(422, {
      accepted: false,
      error: "Forum PDF size is invalid.",
    });
  }

  const sha256 = normalizedString(body?.sha256).toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(sha256)) {
    return jsonResponse(422, {
      accepted: false,
      error: "Forum PDF checksum is invalid.",
    });
  }

  const fetchSong = dependencies.fetchSong;
  if (typeof fetchSong !== "function") {
    return jsonResponse(501, { accepted: false, error: "Forum song store is not configured." });
  }

  const song = await fetchSong(post.song_id);
  if (song === null) {
    return jsonResponse(422, {
      accepted: false,
      error: "Forum post song metadata is missing.",
    });
  }

  const metadataErrors = forumPostMetadataErrors({ post, song });
  if (metadataErrors.length > 0) {
    return jsonResponse(422, {
      accepted: false,
      error: "Forum post metadata is not ready to publish.",
      metadata_errors: metadataErrors,
    });
  }

  const finalizePostPDF = dependencies.finalizePostPDF;
  const updatePostStatus = dependencies.updatePostStatus;
  if (typeof finalizePostPDF !== "function" || typeof updatePostStatus !== "function") {
    return jsonResponse(501, { accepted: false, error: "Forum post publisher is not configured." });
  }

  await finalizePostPDF({
    postID: post.id,
    byteSize,
    sha256,
  });
  const publishedPost = await updatePostStatus({
    postID: post.id,
    status: "published",
    publishedAt: new Date().toISOString(),
  });

  return jsonResponse(202, {
    accepted: true,
    action: "publish",
    state: "published",
    post: publishedPost ?? { ...post, status: "published" },
  });
}

async function handleWithdrawAction({ post, dependencies }) {
  const status = normalizedString(post.status);
  if (status === "removed") {
    return jsonResponse(202, {
      accepted: true,
      action: "withdraw",
      state: "already_removed",
      post,
    });
  }

  if (status !== "pending") {
    return jsonResponse(409, {
      accepted: false,
      error: "Only pending forum submissions can be withdrawn.",
    });
  }

  const updatePostStatus = dependencies.updatePostStatus;
  if (typeof updatePostStatus !== "function") {
    return jsonResponse(501, { accepted: false, error: "Forum post remover is not configured." });
  }

  const removedPost = await updatePostStatus({
    postID: post.id,
    status: "removed",
  });
  return jsonResponse(202, {
    accepted: true,
    action: "withdraw",
    state: "removed",
    post: removedPost ?? { ...post, status: "removed" },
  });
}

async function handleRemoveAction({ post, dependencies }) {
  const status = normalizedString(post.status);
  if (status === "removed") {
    return jsonResponse(202, {
      accepted: true,
      action: "remove",
      state: "already_removed",
      post,
    });
  }

  if (status !== "published" && status !== "flagged") {
    return jsonResponse(409, {
      accepted: false,
      error: "Only published forum posts can be removed from Forums.",
    });
  }

  const updatePostStatus = dependencies.updatePostStatus;
  if (typeof updatePostStatus !== "function") {
    return jsonResponse(501, { accepted: false, error: "Forum post remover is not configured." });
  }

  const removedPost = await updatePostStatus({
    postID: post.id,
    status: "removed",
  });
  return jsonResponse(202, {
    accepted: true,
    action: "remove",
    state: "removed",
    post: removedPost ?? { ...post, status: "removed" },
  });
}

export function forumPostMetadataErrors({ post, song }) {
  const errors = [];
  const fields = [
    ["song_title", song?.song_title, { min: 1, max: 120 }],
    ["artist_name", song?.artist_name, { min: 1, max: 120 }],
    ["chart_title", post?.chart_title, { min: 1, max: 120 }],
    ["arranger_credit", post?.arranger_credit, { min: 1, max: 120 }],
    ["creator_display_name", post?.creator_display_name, { min: 1, max: 80 }],
  ];

  for (const [field, value, limits] of fields) {
    if (!isUsefulForumText(value, limits)) {
      errors.push(field);
    }
  }

  const versionNote = normalizedString(post?.version_note);
  if (versionNote.length > 500 || (versionNote.length > 0 && !isUsefulForumText(versionNote, { min: 1, max: 500 }))) {
    errors.push("version_note");
  }

  const tags = Array.isArray(post?.tags) ? post.tags : [];
  if (tags.length > 8 || tags.some((tag) => !isUsefulForumText(tag, { min: 1, max: 40 }))) {
    errors.push("tags");
  }

  return errors;
}

function isUsefulForumText(value, { min, max }) {
  const text = normalizedString(value);
  if (text.length < min || text.length > max) {
    return false;
  }

  const compact = text.replace(/\s+/gu, "");
  if (compact.length === 0 || /^(.)\1{4,}$/u.test(compact)) {
    return false;
  }

  const usefulCharacters = [...compact].filter((character) => /[\p{L}\p{N}]/u.test(character)).length;
  return usefulCharacters > 0;
}

async function fetchForumPost(configuration, postID, fetcher) {
  const rows = await supabaseGET(
    configuration,
    `/rest/v1/forum_chart_posts?id=eq.${encodeURIComponent(postID)}&select=*`,
    fetcher
  );
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

async function fetchForumSong(configuration, songID, fetcher) {
  const rows = await supabaseGET(
    configuration,
    `/rest/v1/forum_songs?id=eq.${encodeURIComponent(normalizedString(songID))}&select=*`,
    fetcher
  );
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

async function finalizeForumPostPDF(configuration, { postID, byteSize, sha256 }, fetcher) {
  await supabaseJSON(
    configuration,
    "/rest/v1/rpc/finalize_forum_chart_post_pdf",
    {
      method: "POST",
      body: {
        target_post_id: postID,
        target_byte_size: byteSize,
        target_sha256: sha256,
      },
    },
    fetcher
  );
}

async function updateForumPostStatus(configuration, { postID, status, publishedAt }, fetcher) {
  const update = { status };
  if (publishedAt !== undefined) {
    update.published_at = publishedAt;
  }

  const rows = await supabaseJSON(
    configuration,
    `/rest/v1/forum_chart_posts?id=eq.${encodeURIComponent(postID)}&select=*`,
    {
      method: "PATCH",
      body: update,
      prefer: "return=representation",
    },
    fetcher
  );
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

async function supabaseGET(configuration, path, fetcher) {
  return await supabaseJSON(configuration, path, { method: "GET" }, fetcher);
}

async function supabaseJSON(configuration, path, options, fetcher) {
  const headers = {
    apikey: configuration.secretKey,
    authorization: `Bearer ${configuration.secretKey}`,
    accept: "application/json",
  };

  if (options.body !== undefined) {
    headers["content-type"] = "application/json";
  }

  if (options.prefer !== undefined) {
    headers.prefer = options.prefer;
  }

  const response = await fetcher(`${configuration.supabaseURL.replace(/\/+$/, "")}${path}`, {
    method: options.method,
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message.length > 0 ? message : `Supabase request failed with ${response.status}.`);
  }

  if (response.status === 204) {
    return null;
  }

  const text = await response.text();
  return text.length > 0 ? JSON.parse(text) : null;
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
