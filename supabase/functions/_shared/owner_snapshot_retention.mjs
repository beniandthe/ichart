import { supabaseSecretKeyFromEnv } from "./supabase_subscription_authority_store.mjs";
import { timingSafeEqual } from "node:crypto";

export const ownerSnapshotArchiveBucket = "ichart-owner-snapshot-archives";
const maximumRows = 100;
const maximumRawBytes = 8 * 1024 * 1024;
const maximumArchiveBytes = maximumRawBytes + 1024 * 1024;
const maximumPlanResponseBytes = 16 * 1024 * 1024 + 256 * 1024;
const maximumBatches = 1;
const deadlineMilliseconds = 50_000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const sha256 = /^[0-9a-f]{64}$/;
const encoder = new TextEncoder();

class ArchiveFailure extends Error {
  constructor(httpStatus) { super(); this.httpStatus = httpStatus; }
}
class BoundsFailure extends ArchiveFailure {}
const require = (condition) => { if (!condition) throw new ArchiveFailure(); };
const requireHTTP = response => { if (!response.ok) throw new ArchiveFailure(response.status); };
const environmentValue = (env, key) => typeof env?.get === "function" ? env.get(key) : env?.[key];

export function createOwnerSnapshotRetentionDependencies(env = globalThis.Deno?.env, options = {}) {
  const jobSecret = String(environmentValue(env, "ICHART_RETENTION_JOB_SECRET") ?? "").trim();
  const secretKey = supabaseSecretKeyFromEnv(env);
  const fetcher = options.fetch ?? fetch;
  let base;
  try {
    base = new URL(String(environmentValue(env, "SUPABASE_URL") ?? ""));
    require(base.protocol === "https:" && !base.username && !base.password
      && base.pathname === "/" && !base.search && !base.hash);
  } catch { return { jobSecret, configured: false }; }
  if (!secretKey) return { jobSecret, configured: false };

  function headers(json = true) {
    const result = { apikey: secretKey };
    // Opaque secret keys go on apikey, never in a JWT bearer slot.
    if (!secretKey.startsWith("sb_secret_")) result.authorization = `Bearer ${secretKey}`;
    if (json) result["content-type"] = "application/json";
    return result;
  }
  async function rpc(name, body, signal, limit = 64 * 1024) {
    const response = await fetcher(new URL(`/rest/v1/rpc/${name}`, base), {
      method: "POST", headers: { ...headers(), accept: "application/json" },
      body: JSON.stringify(body), redirect: "error", signal,
    });
    requireHTTP(response);
    return JSON.parse(decode(await readBounded(response.body, limit, signal)));
  }
  function objectURL(kind, receipt) {
    validateObject(receipt);
    const path = [receipt.bucket, ...receipt.object_key.split("/")].map(encodeURIComponent).join("/");
    return new URL(`/storage/v1/object/${kind}${path}`, base);
  }
  async function readBucket(signal) {
    const response = await fetcher(new URL(`/storage/v1/bucket/${ownerSnapshotArchiveBucket}`, base), {
      method: "GET", headers: headers(false), redirect: "error", signal,
    });
    if (response.status === 404) return null;
    if (!response.ok && response.status !== 400) throw new ArchiveFailure(response.status);
    let value;
    try { value = JSON.parse(decode(await readBounded(response.body, 16 * 1024, signal))); }
    catch { throw new ArchiveFailure(response.status); }
    if (response.status === 400 && String(value?.statusCode) === "404"
      && (value.code === "NoSuchBucket" || (value.code === undefined
        && value.error === "Bucket not found" && value.message === "Bucket not found"))) {
      return null;
    }
    requireHTTP(response);
    return value;
  }
  return {
    jobSecret, configured: true,
    readPolicy: (signal) => rpc("owner_snapshot_retention_status", {}, signal),
    ensureArchiveBucket: async (allowCreate, signal) => {
      let value = await readBucket(signal);
      if (value === null && allowCreate) {
        const response = await fetcher(new URL("/storage/v1/bucket", base), {
          method: "POST", headers: headers(), redirect: "error", signal,
          body: JSON.stringify({ id: ownerSnapshotArchiveBucket, name: ownerSnapshotArchiveBucket,
            public: false, file_size_limit: maximumArchiveBytes, allowed_mime_types: ["application/gzip"],
            versioning_status: "DISABLED" }),
        });
        if (!response.ok && response.status !== 400 && response.status !== 409) throw new ArchiveFailure(response.status);
        value = await readBucket(signal);
      }
      require(value?.id === ownerSnapshotArchiveBucket && value.name === ownerSnapshotArchiveBucket
        && value.public === false && Number(value.file_size_limit) === maximumArchiveBytes
        && Array.isArray(value.allowed_mime_types) && value.allowed_mime_types.length === 1
        && value.allowed_mime_types[0] === "application/gzip"
        && (value.type === undefined || value.type === "STANDARD")
        && value.versioning_status === "DISABLED"
        && [undefined, false, "Disabled"].includes(value.versioning)
        && [undefined, false].includes(value.is_versioned)
        && [undefined, false].includes(value.versioning_enabled));
    },
    planBatch: (signal) => rpc("plan_owner_snapshot_retention", { p_limit: maximumRows }, signal,
      maximumPlanResponseBytes),
    uploadArchive: async (batch, bytes, signal) => {
      const response = await fetcher(objectURL("", batch), {
        method: "POST", headers: { ...headers(false), "content-type": "application/gzip", "x-upsert": "false" },
        body: bytes, redirect: "error", signal,
      });
      // Duplicate objects are never overwritten. Their complete bytes/rows must
      // still pass independent readback validation before an attestation.
      if (!response.ok && response.status !== 400 && response.status !== 409) throw new ArchiveFailure(response.status);
      return { alreadyExists: !response.ok };
    },
    downloadArchive: async (batch, signal) => {
      const response = await fetcher(objectURL("authenticated/", batch), {
        method: "GET", headers: headers(false), redirect: "error", signal,
      });
      requireHTTP(response);
      const length = Number(response.headers.get("content-length"));
      require(!Number.isFinite(length) || length <= maximumArchiveBytes);
      return readBounded(response.body, maximumArchiveBytes, signal);
    },
    finalizeArchive: (batch, proof, signal) => rpc("finalize_owner_snapshot_archive", {
      p_batch_id: batch.batch_id, p_archive_sha256: proof.archiveSHA256,
      p_archive_bytes: proof.archiveBytes, p_restored_manifest_sha256: proof.manifestSHA256,
      p_restored_row_count: proof.rowCount,
    }, signal),
    listArchives: (after, signal) => rpc("list_owner_snapshot_archives", { p_after: after, p_limit: 100 }, signal,
      256 * 1024),
    signArchive: async (receipt, signal) => {
      const response = await fetcher(objectURL("sign/", receipt), {
        method: "POST", headers: headers(), body: JSON.stringify({ expiresIn: 3600 }),
        redirect: "error", signal,
      });
      requireHTTP(response);
      const value = JSON.parse(decode(await readBounded(response.body, 16 * 1024, signal)));
      require(typeof value.signedURL === "string" && value.signedURL.startsWith("/object/sign/"));
      const url = new URL(`/storage/v1${value.signedURL}`, base);
      require(url.origin === base.origin && url.pathname === objectURL("sign/", receipt).pathname
        && !url.hash && url.searchParams.has("token") && url.searchParams.get("token").length > 0);
      return url.href;
    },
  };
}

export async function handleOwnerSnapshotRetentionRequest(request, dependencies = {}) {
  if (request.method !== "POST") return json(405, { accepted: false, error: "Use POST." });
  if (!await authorized(request, dependencies.jobSecret)) {
    return json(401, { accepted: false, error: "Archive job authorization failed." });
  }
  if (!dependencies.configured) return json(503, { accepted: false, error: "Archive job is not configured." });
  const controller = new AbortController();
  const abort = () => controller.abort();
  request.signal.addEventListener("abort", abort, { once: true });
  if (request.signal.aborted) controller.abort();
  const timer = setTimeout(abort, deadlineMilliseconds);
  const signal = controller.signal;
  let stage = "read_policy";
  try {
    let mode, after;
    try {
      const raw = await readBounded(request.body, 4096, signal);
      const body = raw.length === 0 ? {} : JSON.parse(decode(raw));
      require(body !== null && typeof body === "object" && !Array.isArray(body));
      mode = body.mode ?? "archive";
      require(mode === "archive" || mode === "download-links");
      require(Object.keys(body).every(key => key === "mode" || (mode === "download-links" && key === "after")));
      after = body.after ?? null;
      require(after === null || (typeof after === "string" && uuid.test(after)));
    } catch (error) {
      return json(error instanceof BoundsFailure ? 413 : 400, { accepted: false,
        error: "Use archive or download-links mode with only an optional after cursor." });
    }
    const policy = await dependencies.readPolicy(signal);
    if (!policy?.owner_id) {
      return json(202, { accepted: true, status: "unconfigured", batches: [], next_cursor: null });
    }
    require(uuid.test(policy.owner_id) && policy.bucket === ownerSnapshotArchiveBucket);
    if (mode === "download-links") {
      stage = "check_bucket";
      await dependencies.ensureArchiveBucket(false, signal);
      stage = "sign_links";
      const page = await dependencies.listArchives(after, signal);
      require(page.owner_id === policy.owner_id && Array.isArray(page.batches) && page.batches.length <= 100);
      require(page.next_cursor === null || (typeof page.next_cursor === "string" && uuid.test(page.next_cursor)));
      const results = [];
      for (const receipt of page.batches) {
        validateReceipt(receipt, policy.owner_id);
        results.push({ batch_id: receipt.batch_id, bucket: receipt.bucket, object_key: receipt.object_key,
          archive_sha256: receipt.archive_sha256,
          archive_bytes: receipt.archive_bytes, manifest_sha256: receipt.manifest_sha256,
          row_count: receipt.row_count, uncompressed_bytes: receipt.uncompressed_bytes,
          download_url: await dependencies.signArchive({ ...receipt, owner_id: policy.owner_id }, signal),
          expires_in: 3600 });
      }
      // This capability-bearing response is for the privileged backup operator.
      // Never log it or store signed URLs in the durable archive receipt.
      return json(200, { accepted: true, status: "download_links", owner_id: policy.owner_id, archives: results,
        next_cursor: page.next_cursor });
    }
    if (policy.enabled !== true) return json(202, { accepted: true, status: "disabled", batches: [] });
    stage = "check_bucket";
    await dependencies.ensureArchiveBucket(true, signal);
    const results = [];
    let status = "batch_limit";
    for (let index = 0; index < maximumBatches; index++) {
      require(!signal.aborted);
      stage = "plan";
      const plan = await dependencies.planBatch(signal);
      if (["disabled", "busy", "empty", "daily_limit"].includes(plan?.status)) {
        status = plan.status;
        break;
      }
      stage = "verify";
      await validateBatch(plan, policy.owner_id);
      let expectedUpload = null;
      if (plan.status === "planned") {
        stage = "upload";
        const bytes = encoder.encode(plan.rows.map(row => row.row_text).join("\n") + "\n");
        const archive = await compress(bytes, signal);
        require(!signal.aborted && Date.parse(plan.expires_at) > Date.now());
        const result = await dependencies.uploadArchive(plan, archive, signal);
        require(typeof result?.alreadyExists === "boolean");
        if (!result.alreadyExists) expectedUpload = { bytes: archive.length, hash: await hash(archive) };
      }
      stage = "get";
      const downloaded = await dependencies.downloadArchive(plan, signal);
      stage = "verify";
      require(downloaded instanceof Uint8Array && downloaded.length > 0 && downloaded.length <= maximumArchiveBytes);
      const archiveHash = await hash(downloaded);
      if (expectedUpload) require(downloaded.length === expectedUpload.bytes && archiveHash === expectedUpload.hash);
      if (plan.status === "verified") {
        require(downloaded.length === plan.archive_bytes && archiveHash === plan.archive_sha256);
      }
      const restored = await decompress(downloaded, signal);
      const proof = await verifyRestoredArchive(restored, plan);
      require(!signal.aborted);
      stage = "finalize";
      const finalized = await dependencies.finalizeArchive(plan,
        { archiveSHA256: archiveHash, archiveBytes: downloaded.length, ...proof }, signal);
      require(finalized?.owner_id === policy.owner_id && finalized.batch_id === plan.batch_id
        && ["verified_waiting_initial_restore", "verified_waiting_account_deletion", "pruned"].includes(finalized.status)
        && integer(finalized.deleted_count, 0, plan.row_count)
        && integer(finalized.protected_count, 0, plan.row_count)
        && (finalized.status === "pruned" || finalized.deleted_count === 0));
      results.push({ batch_id: plan.batch_id, status: finalized.status, row_count: plan.row_count,
        archive_bytes: downloaded.length, deleted_count: finalized.deleted_count,
        protected_count: finalized.protected_count });
      if (finalized.status === "verified_waiting_account_deletion") {
        status = finalized.status;
        break;
      }
    }
    return json(202, { accepted: true, status, batches: results });
  } catch (error) {
    // Do not expose row data, object URLs, service keys or upstream error bodies.
    return json(502, { accepted: false, stage,
      ...(integer(error?.httpStatus, 100, 599) ? { upstream_http_status: error.httpStatus } : {}),
      error: "Archive job did not complete; no unverified archive is attested." });
  } finally {
    clearTimeout(timer);
    request.signal.removeEventListener("abort", abort);
  }
}

function validateObject(value) {
  require(value && uuid.test(value.owner_id) && uuid.test(value.batch_id)
    && value.bucket === ownerSnapshotArchiveBucket
    && value.object_key === `${value.owner_id}/${value.batch_id}.jsonl.gz`);
}

function validateReceipt(value, ownerID) {
  validateObject({ ...value, owner_id: ownerID });
  require(sha256.test(value.archive_sha256) && integer(value.archive_bytes, 1, maximumArchiveBytes)
    && sha256.test(value.manifest_sha256) && integer(value.row_count, 1, maximumRows)
    && integer(value.uncompressed_bytes, 1, maximumRawBytes));
}

async function validateBatch(batch, ownerID) {
  validateObject(batch);
  require(batch.owner_id === ownerID && ["planned", "verified"].includes(batch.status)
    && integer(batch.row_count, 1, maximumRows) && integer(batch.uncompressed_bytes, 1, maximumRawBytes)
    && sha256.test(batch.manifest_sha256) && Array.isArray(batch.rows) && batch.rows.length === batch.row_count
    && Number.isFinite(Date.parse(batch.expires_at)) && Date.parse(batch.expires_at) > Date.now());
  let previous = "";
  let bytes = 0;
  for (const row of batch.rows) {
    require(uuid.test(row.snapshot_id) && row.snapshot_id > previous && sha256.test(row.row_sha256));
    previous = row.snapshot_id;
    if (batch.status === "planned") {
      require(typeof row.row_text === "string" && row.row_text.length > 0 && !/[\r\n]/.test(row.row_text));
      const encoded = encoder.encode(row.row_text);
      bytes += encoded.length + 1;
      require(bytes <= maximumRawBytes && await hash(encoded) === row.row_sha256);
      validateRow(row.row_text, row.snapshot_id, ownerID);
    } else require(row.row_text === null);
  }
  require(await manifest(batch.rows) === batch.manifest_sha256);
  if (batch.status === "planned") require(bytes === batch.uncompressed_bytes);
  else validateReceipt(batch, ownerID);
}

export async function verifyRestoredArchive(bytes, batch) {
  require(bytes.length === batch.uncompressed_bytes && bytes.length <= maximumRawBytes);
  const text = decode(bytes);
  require(text.endsWith("\n"));
  const lines = text.slice(0, -1).split("\n");
  require(lines.length === batch.row_count);
  for (let index = 0; index < lines.length; index++) {
    const row = batch.rows[index];
    require(!lines[index].includes("\r") && await hash(encoder.encode(lines[index])) === row.row_sha256);
    if (row.row_text !== null) require(lines[index] === row.row_text);
    validateRow(lines[index], row.snapshot_id, batch.owner_id);
  }
  const digest = await manifest(batch.rows);
  require(digest === batch.manifest_sha256);
  return { manifestSHA256: digest, rowCount: lines.length };
}

function validateRow(text, snapshotID, ownerID) {
  const row = JSON.parse(text);
  require(row !== null && !Array.isArray(row) && typeof row === "object"
    && row.id === snapshotID && row.owner_id === ownerID);
}

async function manifest(rows) {
  return hash(encoder.encode(rows.map(row => `${row.snapshot_id}:${row.row_sha256}`).join("\n")));
}

async function hash(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, value => value.toString(16).padStart(2, "0")).join("");
}

async function authorized(request, secret) {
  const supplied = request.headers.get("x-ichart-retention-job-secret") ?? "";
  if (typeof secret !== "string" || secret.length < 32 || secret.length > 8192 || supplied.length > 8192) return false;
  const [left, right] = await Promise.all([crypto.subtle.digest("SHA-256", encoder.encode(secret)),
    crypto.subtle.digest("SHA-256", encoder.encode(supplied))]);
  return timingSafeEqual(new Uint8Array(left), new Uint8Array(right));
}

async function compress(bytes, signal) {
  return readBounded(new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip")),
    maximumArchiveBytes, signal);
}

async function decompress(bytes, signal) {
  return readBounded(new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip")),
    maximumRawBytes, signal);
}

async function readBounded(stream, maximum, signal) {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks = [];
  let length = 0;
  let complete = false;
  const abort = () => { reader.cancel().catch(() => {}); };
  signal?.addEventListener("abort", abort, { once: true });
  try {
    require(!signal?.aborted);
    while (true) {
      const { value, done } = await reader.read();
      require(!signal?.aborted);
      if (done) break;
      require(value instanceof Uint8Array);
      if (length + value.length > maximum) throw new BoundsFailure();
      chunks.push(value);
      length += value.length;
    }
    const result = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
    complete = true;
    return result;
  } finally {
    signal?.removeEventListener("abort", abort);
    if (!complete) await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

const decode = bytes => new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
const integer = (value, minimum, maximum) => Number.isSafeInteger(value) && value >= minimum && value <= maximum;
function json(status, value) {
  return new Response(JSON.stringify(value), { status,
    headers: { "content-type": "application/json", "cache-control": "no-store" } });
}
