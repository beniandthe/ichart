import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { gzipSync, gunzipSync } from "node:zlib";
import { createOwnerSnapshotRetentionDependencies, handleOwnerSnapshotRetentionRequest,
  ownerSnapshotArchiveBucket, verifyRestoredArchive } from "./owner_snapshot_retention.mjs";

const owner = "00000000-0000-4000-8000-000000000001";
const other = "00000000-0000-4000-8000-000000000002";
const batchID = "00000000-0000-4000-8000-000000000003";
const secret = "synthetic-owner-retention-capability-" + "a".repeat(40);
const encoder = new TextEncoder();
const digest = value => createHash("sha256").update(value).digest("hex");
const rawRow = (id, rowOwner = owner) => `{"id": "${id}", "owner_id": "${rowOwner}", "revision": 9007199254740993, "snapshot_json": {"chord": "E∆7", "ink": [{"x": 0.123456789012345678901234567890, "y": 17, "pressure": 0.75}]}, "created_at": "2026-01-01T00:00:00+00:00"}`;

function planned(options = {}) {
  const rows = (options.rows ?? [
    rawRow("10000000-0000-4000-8000-000000000001", options.owner ?? owner),
    rawRow("10000000-0000-4000-8000-000000000002", options.owner ?? owner),
  ]).map(row_text => ({ snapshot_id: JSON.parse(row_text).id, row_text, row_sha256: digest(row_text) }));
  return { status: "planned", owner_id: options.owner ?? owner, batch_id: batchID,
    bucket: ownerSnapshotArchiveBucket, object_key: `${options.owner ?? owner}/${batchID}.jsonl.gz`,
    row_count: rows.length, rows, manifest_sha256: digest(rows.map(row => `${row.snapshot_id}:${row.row_sha256}`).join("\n")),
    uncompressed_bytes: Buffer.byteLength(rows.map(row => row.row_text).join("\n") + "\n"),
    initial_restore_verified: false, expires_at: "2099-01-01T00:00:00Z" };
}

function request(body = {}, headers = {}, method = "POST") {
  return new Request("https://synthetic.invalid/owner-snapshot-retention", {
    method, headers: { "x-ichart-retention-job-secret": secret, ...headers },
    ...(method === "POST" ? { body: typeof body === "string" ? body : JSON.stringify(body) } : {}),
  });
}

function harness(plan = planned()) {
  const calls = [], store = new Map();
  let next = plan;
  const dependencies = {
    configured: true, jobSecret: secret,
    readPolicy: async () => { calls.push("policy"); return { enabled: true, owner_id: owner, bucket: ownerSnapshotArchiveBucket }; },
    ensureArchiveBucket: async () => { calls.push("bucket"); },
    planBatch: async () => { calls.push("plan"); const value = next; next = { status: "empty" }; return value; },
    uploadArchive: async (batch, bytes) => {
      calls.push("upload"); store.set(batch.batch_id, new Uint8Array(bytes)); return { alreadyExists: false };
    },
    downloadArchive: async batch => { calls.push("get"); return new Uint8Array(store.get(batch.batch_id)); },
    finalizeArchive: async (batch, proof) => {
      calls.push("finalize"); dependencies.proof = proof;
      return { status: "verified_waiting_initial_restore", owner_id: owner, batch_id: batch.batch_id,
        deleted_count: 0, protected_count: batch.row_count };
    },
    listArchives: async () => ({ owner_id: owner, batches: [], next_cursor: null }),
    signArchive: async () => "https://synthetic.invalid/unused",
  };
  return { dependencies, calls, store };
}

test("method/auth/forged-role failures perform no policy, database or Storage work", async () => {
  for (const input of [request({}, {}, "GET"), request({}, { "x-ichart-retention-job-secret": "wrong" }),
    request({}, { "x-ichart-retention-job-secret": "", authorization: "Bearer forged-role-service-role" })]) {
    const h = harness(); const response = await handleOwnerSnapshotRetentionRequest(input, h.dependencies);
    assert.equal([401, 405].includes(response.status), true); assert.deepEqual(h.calls, []);
  }
});

test("caller cannot select owner, object, URL, batch size or unsupported mode", async () => {
  for (const body of [{ owner_id: other }, { object_key: "other/archive.gz" }, { url: "https://outside.invalid" },
    { limit: 500 }, { mode: "prune" }, { mode: "archive", after: batchID }, [], "not-json"]) {
    const h = harness(); const response = await handleOwnerSnapshotRetentionRequest(request(body), h.dependencies);
    assert.equal(response.status, 400); assert.deepEqual(h.calls, []);
  }
  const h = harness();
  assert.equal((await handleOwnerSnapshotRetentionRequest(request(" ".repeat(4097)), h.dependencies)).status, 413);
  assert.deepEqual(h.calls, []);
});

test("disabled policy does no archive/bucket work", async () => {
  const h = harness(); h.dependencies.readPolicy = async () => ({ enabled: false, owner_id: owner, bucket: ownerSnapshotArchiveBucket });
  const response = await handleOwnerSnapshotRetentionRequest(request(), h.dependencies);
  assert.equal((await response.json()).status, "disabled"); assert.deepEqual(h.calls, []);
});

test("bootstrap preserves exact opaque PG text, large numbers and ink before receipt; deletes zero", async () => {
  const plan = planned(), h = harness(plan);
  const response = await handleOwnerSnapshotRetentionRequest(request(), h.dependencies);
  assert.equal(response.status, 202);
  assert.deepEqual(h.calls, ["policy", "bucket", "plan", "upload", "get", "finalize"]);
  const result = await response.json(); assert.equal(result.batches[0].deleted_count, 0);
  const raw = gunzipSync(h.store.get(batchID)).toString("utf8");
  assert.equal(raw, plan.rows.map(row => row.row_text).join("\n") + "\n");
  assert.equal(raw.includes("9007199254740993"), true);
  assert.equal(raw.includes("0.123456789012345678901234567890"), true);
  assert.equal(h.dependencies.proof.manifestSHA256, plan.manifest_sha256);
  assert.equal(h.dependencies.proof.archiveSHA256, digest(h.store.get(batchID)));
});

test("upload failure cannot download, attest or prune and never exposes upstream text", async () => {
  const h = harness(); h.dependencies.uploadArchive = async () => { h.calls.push("upload"); throw new Error("private-row-and-key"); };
  const response = await handleOwnerSnapshotRetentionRequest(request(), h.dependencies);
  assert.equal(response.status, 502); assert.deepEqual(h.calls, ["policy", "bucket", "plan", "upload"]);
  assert.equal((await response.text()).includes("private-row-and-key"), false);
});

test("successful upload followed by corrupted Storage bytes cannot attest or prune", async () => {
  const h = harness(); h.dependencies.downloadArchive = async () => { h.calls.push("get"); return new Uint8Array([1, 2, 3]); };
  assert.equal((await handleOwnerSnapshotRetentionRequest(request(), h.dependencies)).status, 502);
  assert.equal(h.calls.includes("finalize"), false);
});

test("duplicate object must independently match exact rows even if it is valid gzip", async () => {
  const plan = planned(), h = harness(plan);
  h.dependencies.uploadArchive = async () => ({ alreadyExists: true });
  h.dependencies.downloadArchive = async () => new Uint8Array(gzipSync(Buffer.from(
    plan.rows.map(row => row.row_text.replace('"y": 17', '"y": 18')).join("\n") + "\n")));
  assert.equal((await handleOwnerSnapshotRetentionRequest(request(), h.dependencies)).status, 502);
  assert.equal(h.calls.includes("finalize"), false);
});

test("valid immutable duplicate can be recovered without overwriting", async () => {
  const plan = planned(), h = harness(plan);
  h.dependencies.uploadArchive = async () => ({ alreadyExists: true });
  h.dependencies.downloadArchive = async () => new Uint8Array(gzipSync(Buffer.from(plan.rows.map(row => row.row_text).join("\n") + "\n")));
  assert.equal((await handleOwnerSnapshotRetentionRequest(request(), h.dependencies)).status, 202);
  assert.equal(h.calls.includes("finalize"), true);
});

test("policy owner binding rejects consistent other-owner plan before Storage", async () => {
  const h = harness(planned({ owner: other }));
  assert.equal((await handleOwnerSnapshotRetentionRequest(request(), h.dependencies)).status, 502);
  assert.equal(h.calls.includes("upload"), false); assert.equal(h.calls.includes("finalize"), false);
});

test("foreign row, object path, row hash, manifest, size and expired lease are rejected", async () => {
  const cases = [
    planned({ rows: [rawRow("10000000-0000-4000-8000-000000000001", other)] }),
    { ...planned(), object_key: `${other}/${batchID}.jsonl.gz` },
    { ...planned(), manifest_sha256: "0".repeat(64) },
    { ...planned(), uncompressed_bytes: 1 },
    { ...planned(), expires_at: "2000-01-01T00:00:00Z" },
  ];
  const wrongHash = planned(); wrongHash.rows[0].row_sha256 = "0".repeat(64); cases.push(wrongHash);
  for (const plan of cases) {
    const h = harness(plan);
    assert.equal((await handleOwnerSnapshotRetentionRequest(request(), h.dependencies)).status, 502);
    assert.equal(h.calls.includes("upload"), false); assert.equal(h.calls.includes("finalize"), false);
  }
});

test("verified replay GET-checks the original archive before bounded refinalization", async () => {
  const original = planned(), bytes = new Uint8Array(gzipSync(Buffer.from(original.rows.map(row => row.row_text).join("\n") + "\n")));
  const plan = { ...original, status: "verified", archive_sha256: digest(bytes), archive_bytes: bytes.length,
    rows: original.rows.map(row => ({ ...row, row_text: null })), initial_restore_verified: true };
  const h = harness(plan); h.store.set(batchID, bytes);
  h.dependencies.finalizeArchive = async () => { h.calls.push("finalize"); return { owner_id: owner, batch_id: batchID,
    status: "pruned", deleted_count: 1, protected_count: 1 }; };
  const response = await handleOwnerSnapshotRetentionRequest(request(), h.dependencies);
  assert.equal(response.status, 202); assert.equal(h.calls.includes("upload"), false);
  assert.deepEqual(h.calls, ["policy", "bucket", "plan", "get", "finalize"]);
  const changed = harness({ ...plan, archive_sha256: "0".repeat(64) }); changed.store.set(batchID, bytes);
  assert.equal((await handleOwnerSnapshotRetentionRequest(request(), changed.dependencies)).status, 502);
  assert.equal(changed.calls.includes("finalize"), false);
});

test("SQL stale-reference refusal retains the uploaded archive and exposes no direct-delete path", async () => {
  const h = harness(); h.dependencies.finalizeArchive = async () => { h.calls.push("finalize"); throw new Error("stale-reference"); };
  assert.equal((await handleOwnerSnapshotRetentionRequest(request(), h.dependencies)).status, 502);
  assert.equal(h.store.has(batchID), true); assert.equal("deleteSnapshots" in h.dependencies, false);
});

test("account-deletion fence acknowledges verified archive with zero prune and stops planning", async () => {
  const h = harness();
  h.dependencies.finalizeArchive = async () => { h.calls.push("finalize"); return {
    status: "verified_waiting_account_deletion", owner_id: owner, batch_id: batchID,
    deleted_count: 0, protected_count: 2,
  }; };
  const response = await handleOwnerSnapshotRetentionRequest(request(), h.dependencies);
  const result = await response.json(); assert.equal(response.status, 202);
  assert.equal(result.status, "verified_waiting_account_deletion");
  assert.equal(h.calls.filter(call => call === "plan").length, 1); assert.equal(h.store.has(batchID), true);
});

test("single-batch invocation performs exactly one plan, upload, readback and finalize", async () => {
  const plan = planned(), h = harness(plan); h.dependencies.planBatch = async () => { h.calls.push("plan"); return plan; };
  const response = await handleOwnerSnapshotRetentionRequest(request(), h.dependencies);
  assert.equal((await response.json()).batches.length, 1);
  for (const stage of ["plan", "upload", "get", "finalize"]) {
    assert.equal(h.calls.filter(call => call === stage).length, 1);
  }
});

test("signed-link export binds every receipt to policy owner and does no archival/finalization", async () => {
  const plan = planned(), h = harness(plan);
  const receipt = { ...plan, archive_sha256: "a".repeat(64), archive_bytes: 10 };
  h.dependencies.listArchives = async after => { assert.equal(after, null); return { owner_id: owner, batches: [receipt], next_cursor: null }; };
  const response = await handleOwnerSnapshotRetentionRequest(request({ mode: "download-links" }), h.dependencies);
  const value = await response.json(); assert.equal(response.status, 200); assert.equal(value.archives.length, 1);
  assert.equal(value.owner_id, owner); assert.equal(value.archives[0].object_key, plan.object_key);
  assert.equal(response.headers.get("cache-control"), "no-store"); assert.deepEqual(h.calls, ["policy", "bucket"]);
  const foreign = harness(); foreign.dependencies.listArchives = async () => ({ owner_id: other, batches: [], next_cursor: null });
  assert.equal((await handleOwnerSnapshotRetentionRequest(request({ mode: "download-links" }), foreign.dependencies)).status, 502);
});

const bucket = () => ({ id: ownerSnapshotArchiveBucket, name: ownerSnapshotArchiveBucket, public: false,
  file_size_limit: 9 * 1024 * 1024, allowed_mime_types: ["application/gzip"], versioning_status: "DISABLED" });
const apiKey = ["sb", "secret", "synthetic"].join("_");
function factory(fetcher) {
  return createOwnerSnapshotRetentionDependencies({ SUPABASE_URL: "https://project.supabase.co",
    ICHART_RETENTION_JOB_SECRET: secret, SUPABASE_SECRET_KEYS: JSON.stringify({ default: apiKey }) }, { fetch: fetcher });
}

test("private fixed bucket read/create/re-read never updates an existing bucket", async () => {
  const calls = []; let exists = false;
  const dependencies = factory(async (url, options) => {
    calls.push([url.pathname, options.method]); assert.equal(options.redirect, "error");
    assert.equal(options.headers.apikey, apiKey); assert.equal(options.headers.authorization, undefined);
    if (options.method === "POST") {
      const body = JSON.parse(options.body); assert.deepEqual(body, { id: ownerSnapshotArchiveBucket,
        name: ownerSnapshotArchiveBucket, public: false, file_size_limit: 9 * 1024 * 1024,
        allowed_mime_types: ["application/gzip"], versioning_status: "DISABLED" });
      exists = true; return Response.json({ name: ownerSnapshotArchiveBucket });
    }
    return exists ? Response.json(bucket()) : new Response("", { status: 404 });
  });
  await dependencies.ensureArchiveBucket(true);
  assert.deepEqual(calls.map(call => call[1]), ["GET", "POST", "GET"]);
  calls.length = 0; await dependencies.ensureArchiveBucket(true);
  assert.deepEqual(calls.map(call => call[1]), ["GET"]);
});

test("structured HTTP400 NoSuchBucket compatibility response creates then rechecks fixed bucket", async () => {
  for (const missing of [
    { statusCode: "404", code: "NoSuchBucket", error: "Bucket not found", message: "Bucket not found" },
    { statusCode: 404, error: "Bucket not found", message: "Bucket not found" },
  ]) {
    let exists = false; const calls = [];
    const dependencies = factory(async (_, options) => {
      calls.push(options.method);
      if (options.method === "POST") { exists = true; return Response.json({ name: ownerSnapshotArchiveBucket }); }
      return exists ? Response.json(bucket()) : Response.json(missing, { status: 400 });
    });
    await dependencies.ensureArchiveBucket(true);
    assert.deepEqual(calls, ["GET", "POST", "GET"]);
  }
});

test("unrelated/malformed HTTP400 errors never authorize bucket creation", async () => {
  for (const response of [
    Response.json({ statusCode: "403", code: "AccessDenied", error: "AccessDenied" }, { status: 400 }),
    Response.json({ statusCode: "401", code: "InvalidJWT" }, { status: 400 }),
    Response.json({ statusCode: "404", code: "NoSuchKey", error: "not_found", message: "Object not found" }, { status: 400 }),
    new Response("not JSON", { status: 400 }),
  ]) {
    const calls = []; const dependencies = factory(async (_, options) => { calls.push(options.method); return response; });
    await assert.rejects(() => dependencies.ensureArchiveBucket(true)); assert.deepEqual(calls, ["GET"]);
  }
});

test("authorized failures report only static stage and optional HTTP status", async () => {
  for (const [name, stage, body] of [
    ["readPolicy", "read_policy", {}], ["ensureArchiveBucket", "check_bucket", {}],
    ["planBatch", "plan", {}], ["uploadArchive", "upload", {}], ["downloadArchive", "get", {}],
    ["finalizeArchive", "finalize", {}], ["listArchives", "sign_links", { mode: "download-links" }],
  ]) {
    const h = harness(); h.dependencies[name] = async () => { throw new Error("private-credential-and-row"); };
    const response = await handleOwnerSnapshotRetentionRequest(request(body), h.dependencies);
    assert.equal(response.status, 502); const result = await response.json(); assert.equal(result.stage, stage);
    assert.equal(JSON.stringify(result).includes("private-credential-and-row"), false);
  }
  const bad = planned(); bad.rows[0].row_sha256 = "0".repeat(64);
  assert.equal((await (await handleOwnerSnapshotRetentionRequest(request(), harness(bad).dependencies)).json()).stage, "verify");
  const dependencies = factory(async () => new Response("private upstream body", { status: 403 }));
  const response = await handleOwnerSnapshotRetentionRequest(request(), dependencies);
  const result = await response.json(); assert.equal(result.stage, "read_policy"); assert.equal(result.upstream_http_status, 403);
  assert.equal(JSON.stringify(result).includes("private upstream body"), false);
  const unauthorized = await handleOwnerSnapshotRetentionRequest(request({}, { "x-ichart-retention-job-secret": "wrong" }), dependencies);
  assert.equal((await unauthorized.json()).stage, undefined);
});

test("public, versioned, unknown-versioning, unlimited or broad-MIME bucket fails closed without repair", async () => {
  for (const value of [{ ...bucket(), public: true }, { ...bucket(), versioning_status: "ENABLED" },
    { ...bucket(), versioning_status: "SUSPENDED" }, { ...bucket(), versioning_status: undefined },
    { ...bucket(), file_size_limit: null }, { ...bucket(), allowed_mime_types: ["*"] }]) {
    const calls = []; const dependencies = factory(async (_, options) => { calls.push(options.method); return Response.json(value); });
    await assert.rejects(() => dependencies.ensureArchiveBucket(true)); assert.deepEqual(calls, ["GET"]);
  }
});

test("transport uses immutable upload, authenticated GET and exact signed path; never caller credentials", async () => {
  const plan = planned(), calls = [];
  const dependencies = factory(async (url, options) => {
    calls.push([url, options]); assert.equal(options.redirect, "error");
    assert.equal(options.headers["x-ichart-retention-job-secret"], undefined);
    assert.equal(options.headers.authorization, undefined); assert.equal(options.headers.apikey, apiKey);
    if (url.pathname.includes("/object/sign/")) return Response.json({ signedURL: `/object/sign/${plan.bucket}/${plan.object_key}?token=synthetic` });
    if (options.method === "POST") {
      assert.equal(options.headers["x-upsert"], "false"); assert.equal(options.headers["content-encoding"], undefined);
      return new Response("", { status: 409 });
    }
    return new Response(new Uint8Array([1, 2, 3]));
  });
  assert.deepEqual(await dependencies.uploadArchive(plan, new Uint8Array([1, 2, 3])), { alreadyExists: true });
  assert.deepEqual(await dependencies.downloadArchive(plan), new Uint8Array([1, 2, 3]));
  const signed = await dependencies.signArchive(plan);
  assert.equal(new URL(signed).origin, "https://project.supabase.co");
  assert.equal(calls[1][0].pathname.includes("/object/authenticated/"), true);
  const malicious = factory(async () => Response.json({ signedURL: "https://outside.invalid/object" }));
  await assert.rejects(() => malicious.signArchive(plan));
});

test("oversized chunked RPC and archive streams fail closed", async () => {
  const dependencies = factory(async () => new Response(new Uint8Array(9 * 1024 * 1024 + 1)));
  await assert.rejects(() => dependencies.downloadArchive(planned()));
  const hugeRPC = factory(async () => new Response(new Uint8Array(17 * 1024 * 1024)));
  await assert.rejects(() => hugeRPC.planBatch());
});

test("Storage stream failure prevents any SQL receipt and redacts its error", async () => {
  const h = harness();
  const transport = factory(async () => new Response(new ReadableStream({
    start(controller) { controller.error(new Error("private-stream-content")); },
  })));
  h.dependencies.downloadArchive = transport.downloadArchive;
  const response = await handleOwnerSnapshotRetentionRequest(request(), h.dependencies);
  assert.equal(response.status, 502); assert.equal(h.calls.includes("finalize"), false);
  assert.equal((await response.text()).includes("private-stream-content"), false);
});

test("request abort cancels a pending archive stream and cannot attest or prune", async () => {
  const controller = new AbortController(); let cancelled = false;
  const transport = factory(async () => new Response(new ReadableStream({
    start(stream) { stream.enqueue(new Uint8Array([1, 2, 3])); },
    cancel() { cancelled = true; },
  })));
  const h = harness(), upload = h.dependencies.uploadArchive;
  h.dependencies.uploadArchive = async (...args) => { const result = await upload(...args); controller.abort(); return result; };
  h.dependencies.downloadArchive = transport.downloadArchive;
  const input = new Request("https://synthetic.invalid/archive", { method: "POST", body: "{}",
    signal: controller.signal, headers: { "x-ichart-retention-job-secret": secret } });
  assert.equal((await handleOwnerSnapshotRetentionRequest(input, h.dependencies)).status, 502);
  assert.equal(cancelled, true); assert.equal(h.calls.includes("finalize"), false); assert.equal(h.store.has(batchID), true);
});

test("gzip expansion beyond the raw budget never reaches SQL attestation", async () => {
  const h = harness(); h.dependencies.uploadArchive = async () => ({ alreadyExists: true });
  h.dependencies.downloadArchive = async () => new Uint8Array(gzipSync(Buffer.alloc(8 * 1024 * 1024 + 1, 65)));
  assert.equal((await handleOwnerSnapshotRetentionRequest(request(), h.dependencies)).status, 502);
  assert.equal(h.calls.includes("finalize"), false);
});

test("restored archive requires exact trailing LF, row ownership and byte count", async () => {
  const plan = planned(), raw = plan.rows.map(row => row.row_text).join("\n") + "\n";
  assert.equal((await verifyRestoredArchive(encoder.encode(raw), plan)).rowCount, plan.row_count);
  await assert.rejects(() => verifyRestoredArchive(encoder.encode(raw.slice(0, -1)), plan));
  await assert.rejects(() => verifyRestoredArchive(encoder.encode(raw.replace(owner, other)), plan));
});
