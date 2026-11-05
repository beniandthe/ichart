// Real Auth + PostgREST + Storage integration against an isolated local stack.
// Never accepts a hosted URL, the normal development ports, or a linked project.
// Creates only synthetic accounts/content and removes them in finally.
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";

const program = promisify(execFile);
const project = process.env.ICHART_FORUM_LOCAL_PROJECT;
assert.ok(project && isAbsolute(project), "Set absolute ICHART_FORUM_LOCAL_PROJECT to an isolated test project.");
const config = await readFile(join(project, "supabase/config.toml"), "utf8");
const projectID = config.match(/^project_id\s*=\s*"([^"]+)"/m)?.[1];
assert.match(projectID ?? "", /^ichart-forum-docket[0-9]+$/, "Use an isolated docket project, not the developer's ordinary stack.");
try {
  await readFile(join(project, "supabase/.temp/project-ref"));
  assert.fail("A linked project is forbidden for this local-only fixture.");
} catch (error) { if (error.code !== "ENOENT") throw error; }

const cliVersion = (await program("supabase", ["--version"], { timeout: 15_000 })).stdout.trim();
const status = JSON.parse((await program("supabase", ["--workdir", project, "status", "-o", "json"],
  { timeout: 20_000, maxBuffer: 2 * 1024 * 1024 })).stdout);
const url = new URL(status.API_URL ?? status.api_url);
assert.equal(url.protocol, "http:");
assert.equal(url.hostname, "127.0.0.1");
assert.ok(Number(url.port) >= 55000 && Number(url.port) <= 55999,
  "The fixture must use dedicated 55xxx test ports, never the ordinary local stack.");
assert.equal(url.pathname, "/");
const apiKey = status.PUBLISHABLE_KEY ?? status.publishable_key ?? status.ANON_KEY ?? status.anon_key;
const admin = status.SERVICE_ROLE_KEY ?? status.service_role_key;
assert.ok(apiKey && admin, "The isolated stack must expose local test credentials.");
const database = new URL(status.DB_URL ?? status.db_url);
assert.equal(database.hostname, "127.0.0.1");
assert.ok(Number(database.port) >= 55000 && Number(database.port) <= 55999);
assert.notEqual(database.port, url.port);
const results = [], users = [], posts = [], songs = [], storagePaths = [];
const useEdgeHTTP = process.env.ICHART_FORUM_EDGE_HTTP === "1";
let cleanupPassed = false;

class RequestFailure extends Error {
  constructor(path, statusCode, body) {
    super(`${path} returned HTTP ${statusCode}: ${body.slice(0, 500)}`);
    this.statusCode = statusCode;
  }
}

async function request(path, { token = admin, method = "GET", body, query, prefer, binary = false } = {}) {
  const target = new URL(path, url);
  if (query) for (const [key, value] of Object.entries(query)) target.searchParams.set(key, value);
  const headers = { apikey: apiKey, Authorization: `Bearer ${token}` };
  if (prefer) headers.Prefer = prefer;
  if (body !== undefined) headers["Content-Type"] = Buffer.isBuffer(body) ? "application/pdf" : "application/json";
  const response = await fetch(target, { method, headers,
    body: body === undefined ? undefined : Buffer.isBuffer(body) ? body : JSON.stringify(body),
    signal: AbortSignal.timeout(20_000) });
  if (!response.ok) throw new RequestFailure(path, response.status, await response.text());
  if (binary) return Buffer.from(await response.arrayBuffer());
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

async function check(name, action) {
  await action();
  results.push({ name, status: "passed" });
  console.log(`PASS ${name}`);
}

async function denied(action, allowedCodes = [401, 403]) {
  await assert.rejects(action, error => error instanceof RequestFailure && allowedCodes.includes(error.statusCode));
}

const select = (table, token, query) => request(`rest/v1/${table}`, { token, query });
const insert = (table, token, body, query) => request(`rest/v1/${table}`,
  { token, method: "POST", body, query, prefer: "return=representation" });

async function operatorSQL(sql) {
  // Badge awards are deliberately database-operator actions, not service API
  // writes. Match that contract without granting any new table privilege.
  const env = Object.fromEntries(Object.entries(process.env)
    .filter(([key]) => !key.startsWith("PG") && key !== "PSQLRC"));
  Object.assign(env, { PGHOST: database.hostname, PGPORT: database.port,
    PGUSER: decodeURIComponent(database.username), PGPASSWORD: decodeURIComponent(database.password),
    PGDATABASE: database.pathname.slice(1), PGCONNECT_TIMEOUT: "5" });
  const value = (await program("psql", ["-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
    { env, timeout: 15_000, maxBuffer: 1024 * 1024 })).stdout.trim();
  return value ? JSON.parse(value) : null;
}

async function account(label) {
  const email = `forum-${label}-${randomUUID()}@example.test`;
  const password = `Forum-local-${randomUUID()}-A1!`;
  const user = await request("auth/v1/admin/users", { method: "POST", body: {
    email, password, email_confirm: true, user_metadata: { first_name: "Local", last_name: label }
  } });
  users.push(user.id);
  await request("rest/v1/subscriptions", { method: "POST", query: { on_conflict: "owner_id" },
    prefer: "resolution=merge-duplicates,return=representation", body: { owner_id: user.id, plan: "studioSubscription", status: "active",
    provider: "manual", entitlement_expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    revoked_at: null, last_verified_at: new Date().toISOString() } });
  const session = await request("auth/v1/token", { method: "POST", query: { grant_type: "password" }, body: { email, password } });
  assert.equal(session.user.id, user.id);
  return { id: user.id, token: session.access_token };
}

function pdfFixture(style) {
  // A complete one-page PDF with real xref offsets, rather than header-only
  // bytes. Its content is synthetic text; it contains no handwriting or chart.
  const stream = `BT /F1 18 Tf 50 720 Td (Synthetic ${style} forum fixture) Tj ET\n`;
  const objects = ["<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
    `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}endstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"];
  let text = "%PDF-1.4\n% Synthetic local forum fixture\n";
  const offsets = [0];
  for (const [index, object] of objects.entries()) {
    offsets.push(Buffer.byteLength(text)); text += `${index + 1} 0 obj\n${object}\nendobj\n`;
  }
  const xref = Buffer.byteLength(text);
  text += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  text += offsets.slice(1).map(offset => `${String(offset).padStart(10, "0")} 00000 n \n`).join("");
  text += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(text);
}

async function page(postID, token, cursor) {
  const query = { post_id: `eq.${postID}`, select: "id,body,owner_id,creator_display_name,created_at",
    order: "created_at.desc,id.desc", limit: "81" };
  if (cursor) query.or = `(created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id}))`;
  const rows = await select("forum_comments", token, query);
  const visible = rows.slice(0, 80);
  return { rows: visible, cursor: rows.length > 80 ? visible.at(-1) : null };
}

async function cleanup() {
  // Delete only IDs created by this process. Never truncate/reset a database.
  for (const id of posts) await operatorSQL(`with deleted as (delete from public.forum_chart_posts where id='${id}'::uuid returning id)
    select count(*)::int from deleted`);
  if (storagePaths.length) await request("storage/v1/object/forum_chart_pdfs", { method: "DELETE", body: { prefixes: storagePaths } });
  for (const id of songs) await operatorSQL(`with deleted as (delete from public.forum_songs where id='${id}'::uuid returning id)
    select count(*)::int from deleted`);
  for (const id of users) await request(`auth/v1/admin/users/${id}`, { method: "DELETE" });
  for (const id of posts) assert.deepEqual(await select("forum_chart_posts", admin, { id: `eq.${id}`, select: "id" }), []);
  for (const id of users) assert.equal(await operatorSQL(`select count(*)::int from public.forum_author_badges where owner_id='${id}'::uuid`), 0);
  cleanupPassed = true;
}

let failure, cleanupFailure;
try {
  assert.deepEqual(await select("forum_chart_posts", admin, { select: "id", limit: "1" }), [],
    "The isolated test catalog must start empty.");
  await check("publication boundary keeps private schema closed and grants only the service entry point", async () => {
    const shape = await operatorSQL(`select jsonb_build_object(
      'privateUsage',has_schema_privilege('service_role','private','USAGE'),
      'anonExecute',has_function_privilege('anon','public.publish_forum_chart_post(uuid,uuid,bigint,text)','EXECUTE'),
      'memberExecute',has_function_privilege('authenticated','public.publish_forum_chart_post(uuid,uuid,bigint,text)','EXECUTE'),
      'serviceExecute',has_function_privilege('service_role','public.publish_forum_chart_post(uuid,uuid,bigint,text)','EXECUTE'),
      'definer',prosecdef,'fixedPath',proconfig=array['search_path=""'])
      from pg_proc where oid='public.publish_forum_chart_post(uuid,uuid,bigint,text)'::regprocedure`);
    assert.deepEqual(shape, { privateUsage: false, anonExecute: false, memberExecute: false,
      serviceExecute: true, definer: true, fixedPath: true });
    await operatorSQL(`do $$ begin
      perform public.publish_forum_chart_post('${randomUUID()}'::uuid,'${randomUUID()}'::uuid,20,'${"a".repeat(64)}');
      raise exception 'Expected privileged caller guard';
      exception when insufficient_privilege then null; end $$; select to_jsonb(true)`);
  });
  const a = await account("Author"), b = await account("Viewer");
  await check("two independent real Auth sessions", async () => {
    assert.notEqual(a.id, b.id); assert.notEqual(a.token, b.token);
    assert.equal((await request("auth/v1/user", { token: a.token })).id, a.id);
    assert.equal((await request("auth/v1/user", { token: b.token })).id, b.id);
  });

  const awards = await operatorSQL(`with inserted as (
    insert into public.forum_author_badges(owner_id,badge_type) values
      ('${a.id}'::uuid,'verifiedContributor'),('${a.id}'::uuid,'trustedArranger')
    returning id,badge_type) select jsonb_agg(to_jsonb(inserted)) from inserted`);
  await check("badges visible to both eligible accounts with an empty catalog", async () => {
    for (const viewer of [a, b]) {
      const badges = await select("forum_author_badges", viewer.token, { owner_id: `eq.${a.id}`, select: "badge_type", order: "badge_type" });
      assert.deepEqual(badges.map(row => row.badge_type), ["trustedArranger", "verifiedContributor"]);
    }
    assert.deepEqual(await select("forum_author_badges", b.token, { owner_id: `eq.${b.id}`, select: "id" }), []);
  });
  await check("members cannot award, alter, or revoke badges", async () => {
    for (const viewer of [a, b]) {
      await denied(() => insert("forum_author_badges", viewer.token, { owner_id: viewer.id, badge_type: "communityExpert" }));
      await denied(() => request("rest/v1/forum_author_badges", { token: viewer.token, method: "PATCH",
        query: { id: `eq.${awards[0].id}` }, body: { badge_type: "communityExpert" } }));
      await denied(() => request("rest/v1/forum_author_badges", { token: viewer.token, method: "DELETE", query: { id: `eq.${awards[0].id}` } }));
    }
    assert.equal(await operatorSQL(`select count(*)::int from public.forum_author_badges where owner_id='${a.id}'::uuid`), 2);
  });

  for (const [index, style] of ["simpleChordSheet", "rhythmSectionSheet"].entries()) {
    const author = index === 0 ? a : b, viewer = index === 0 ? b : a;
    const songID = randomUUID(), postID = randomUUID(), voteID = randomUUID();
    const storagePath = `${author.id}/${postID}.pdf`;
    const pdf = pdfFixture(style);
    if (useEdgeHTTP && process.env.ICHART_FORUM_GATEWAY_RECEIPT) {
      await writeFile(join(dirname(process.env.ICHART_FORUM_GATEWAY_RECEIPT), `edge-fixture-${style}.pdf`), pdf);
    }
    songs.push(songID); posts.push(postID); storagePaths.push(storagePath);
    await insert("forum_songs", author.token, { id: songID, song_title: `Local ${songID}`, artist_name: "Synthetic Artist",
      normalized_song_title: `local ${songID}`, normalized_artist_name: "synthetic artist", created_by: author.id });
    await request(`storage/v1/object/forum_chart_pdfs/${storagePath}`, { token: author.token, method: "POST", body: pdf });
    await insert("forum_chart_posts", author.token, { id: postID, song_id: songID, owner_id: author.id,
      chart_title: `Local ${style}`, arranger_credit: "Synthetic", creator_display_name: "Ignored client value",
      tags: ["local-test"], layout_style: style, pdf_storage_path: storagePath });
    await check(`${style}: private pending submission and inaccessible PDF`, async () => {
      const own = await select("forum_chart_posts", author.token, { id: `eq.${postID}`, select: "id,status,layout_style" });
      assert.equal(own[0].status, "pending"); assert.equal(own[0].layout_style, style);
      assert.deepEqual(await select("forum_chart_posts", viewer.token, { id: `eq.${postID}`, select: "id" }), []);
      await denied(() => request(`storage/v1/object/authenticated/forum_chart_pdfs/${storagePath}`,
        { token: viewer.token, binary: true }), [400, 401, 403, 404]);
    });
    const proof = { target_post_id: postID, target_owner_id: author.id, target_byte_size: pdf.length,
      target_sha256: createHash("sha256").update(pdf).digest("hex") };
    await check(`${style}: clients cannot finalize publication`, async () => {
      await denied(() => request("rest/v1/rpc/publish_forum_chart_post", { token: author.token, method: "POST", body: proof }));
      await denied(() => request("rest/v1/rpc/publish_forum_chart_post", {
        token: status.ANON_KEY ?? status.anon_key ?? apiKey, method: "POST", body: proof }));
    });
    await check(`${style}: service publication still rejects wrong owner, bad proof and a banned account`, async () => {
      await denied(() => request("rest/v1/rpc/publish_forum_chart_post", { method: "POST",
        body: { ...proof, target_owner_id: viewer.id } }));
      await denied(() => request("rest/v1/rpc/publish_forum_chart_post", { method: "POST",
        body: { ...proof, target_sha256: "not-a-sha256" } }), [400]);
      await operatorSQL(`update auth.users set banned_until=now()+interval '1 hour' where id='${author.id}'::uuid; select to_jsonb(true)`);
      try {
        await denied(() => request("rest/v1/rpc/publish_forum_chart_post", { method: "POST", body: proof }));
      } finally {
        await operatorSQL(`update auth.users set banned_until=null where id='${author.id}'::uuid; select to_jsonb(true)`);
      }
      const row = (await select("forum_chart_posts", author.token,
        { id: `eq.${postID}`, select: "status,pdf_provenance_status" }))[0];
      assert.deepEqual(row, { status: "pending", pdf_provenance_status: "pending" });
    });
    if (useEdgeHTTP) {
      const payload = { action: "publish", post_id: postID, byte_size: pdf.length, sha256: proof.target_sha256 };
      await check(`${style}: actual Edge HTTP rejects wrong account and malformed proof`, async () => {
        await denied(() => request("functions/v1/forum-post-actions", { token: viewer.token, method: "POST", body: payload }));
        await denied(() => request("functions/v1/forum-post-actions", { token: author.token, method: "POST",
          body: { ...payload, sha256: "not-a-sha256" } }), [422]);
      });
      const published = await request("functions/v1/forum-post-actions", { token: author.token, method: "POST",
        body: { ...payload, owner_id: viewer.id } });
      assert.equal(published.accepted, true); assert.equal(published.state, "published");
      assert.equal(published.post.id, postID); assert.equal(published.post.owner_id, author.id);
      await check(`${style}: actual Edge HTTP repeat is idempotent and preserves provenance`, async () => {
        const repeated = await request("functions/v1/forum-post-actions", { token: author.token, method: "POST", body: payload });
        assert.equal(repeated.accepted, true); assert.equal(repeated.state, "already_published");
        assert.equal(repeated.post.published_at, published.post.published_at);
        assert.equal(await operatorSQL(`select count(*)::int from private.forum_chart_pdf_provenance where post_id='${postID}'::uuid`), 1);
      });
    } else {
      // The local operator supplies a published fixture through the service-only
      // atomic RPC; Edge admission can be checked separately or enabled above.
      await request("rest/v1/rpc/publish_forum_chart_post", { method: "POST", body: proof });
    }
    await check(`${style}: published catalog and exact stored PDF reach both accounts`, async () => {
      const storedProof = await operatorSQL(`select jsonb_build_object('byteSize',byte_size,'sha256',sha256,
        'ownerID',owner_id,'storagePath',storage_path) from private.forum_chart_pdf_provenance where post_id='${postID}'::uuid`);
      assert.deepEqual(storedProof, { byteSize: pdf.length, sha256: proof.target_sha256,
        ownerID: author.id, storagePath });
      for (const reader of [author, viewer]) {
        const rows = await select("forum_chart_posts", reader.token, { id: `eq.${postID}`, select: "id,status,layout_style,pdf_provenance_status" });
        assert.equal(rows.length, 1); assert.equal(rows[0].status, "published");
        assert.equal(rows[0].layout_style, style); assert.equal(rows[0].pdf_provenance_status, "validated");
        assert.deepEqual(await request(`storage/v1/object/authenticated/forum_chart_pdfs/${storagePath}`,
          { token: reader.token, binary: true }), pdf);
      }
    });
    await check(`${style}: vote, change, duplicate rejection and aggregate readback`, async () => {
      await insert("forum_votes", viewer.token, { id: voteID, post_id: postID, owner_id: viewer.id, vote_value: 1 });
      assert.equal((await select("forum_chart_posts", viewer.token, { id: `eq.${postID}`, select: "vote_up_count" }))[0].vote_up_count, 1);
      await denied(() => insert("forum_votes", viewer.token,
        { id: randomUUID(), post_id: postID, owner_id: viewer.id, vote_value: 1 }), [409]);
      await request("rest/v1/forum_votes", { token: viewer.token, method: "PATCH", query: { id: `eq.${voteID}` }, body: { vote_value: -1 } });
      const rows = await select("forum_chart_posts", author.token, { id: `eq.${postID}`, select: "vote_up_count,vote_down_count" });
      assert.deepEqual(rows[0], { vote_up_count: 0, vote_down_count: 1 });
    });

    const history = Array.from({ length: 166 }, (_, i) => ({
      id: `${index === 0 ? "90000000" : "91000000"}-0000-4000-8000-${String(i + 1).padStart(12, "0")}`,
      post_id: postID, owner_id: author.id, body: `Synthetic history ${i}`,
      created_at: `2026-11-04T00:00:00.${String(123456 + Math.floor(i / 4)).padStart(6, "0")}+00:00`
    }));
    await insert("forum_comments", author.token, history);
    const replyID = randomUUID();
    await check(`${style}: comment rejection retains history, retry posts once`, async () => {
      await denied(() => insert("forum_comments", viewer.token,
        { id: replyID, post_id: postID, owner_id: viewer.id, body: " " }), [400]);
      assert.equal((await select("forum_comments", viewer.token, { post_id: `eq.${postID}`, select: "id" })).length, 166);
      await insert("forum_comments", viewer.token, { id: replyID, post_id: postID, owner_id: viewer.id, body: "Synthetic newest reply" });
      await denied(() => insert("forum_comments", viewer.token,
        { id: replyID, post_id: postID, owner_id: viewer.id, body: "Synthetic newest reply" }), [409]);
      const rows = await select("forum_comments", author.token, { id: `eq.${replyID}`, select: "id,owner_id,creator_display_name" });
      assert.equal(rows.length, 1); assert.equal(rows[0].owner_id, viewer.id);
      assert.ok(rows[0].creator_display_name.startsWith("Local "));
    });
    await check(`${style}: three pages preserve timestamp ties, newest reply and every ID`, async () => {
      const expected = await select("forum_comments", author.token, { post_id: `eq.${postID}`, select: "id", order: "created_at.desc,id.desc" });
      const accumulated = []; let cursor, pageCount = 0;
      do {
        const current = await page(postID, viewer.token, cursor);
        accumulated.push(...current.rows); cursor = current.cursor; pageCount += 1;
        assert.ok(pageCount <= 4);
      } while (cursor);
      assert.equal(pageCount, 3); assert.equal(accumulated.length, 167);
      assert.equal(accumulated[0].id, replyID);
      assert.equal(new Set(accumulated.map(row => row.id)).size, 167);
      assert.deepEqual(accumulated.map(row => row.id), expected.map(row => row.id));
      assert.ok(accumulated.some(row => row.created_at.includes("123456")), "Microseconds survive the gateway unchanged.");
    });
    await check(`${style}: another account cannot spoof the commenter`, async () => {
      await denied(() => insert("forum_comments", viewer.token,
        { id: randomUUID(), post_id: postID, owner_id: author.id, body: "Synthetic spoof denied" }));
    });
  }

  await check("revoking one badge preserves the other badge and unbadged author", async () => {
    const revoke = awards.find(row => row.badge_type === "verifiedContributor");
    await operatorSQL(`with deleted as (delete from public.forum_author_badges where id='${revoke.id}'::uuid returning id)
      select count(*)::int from deleted`);
    for (const reader of [a, b]) {
      const current = await select("forum_author_badges", reader.token, { owner_id: `eq.${a.id}`, select: "badge_type" });
      assert.deepEqual(current.map(row => row.badge_type), ["trustedArranger"]);
      assert.deepEqual(await select("forum_author_badges", reader.token, { owner_id: `eq.${b.id}`, select: "id" }), []);
    }
  });
} catch (error) { failure = error; }
finally {
  try { await cleanup(); } catch (error) { cleanupFailure = error; failure ??= error; }
}

const migrationNames = (await readdir(join(project, "supabase/migrations"))).filter(name => name.endsWith(".sql")).sort();
const migrationHash = createHash("sha256");
for (const name of migrationNames) migrationHash.update(name).update(await readFile(join(project, "supabase/migrations", name)));
const receipt = { passed: !failure, projectID, apiHost: url.hostname, apiPort: Number(url.port), cliVersion,
  realAuth: true, realPostgREST: true, realStorage: true, chartStyles: ["simpleChordSheet", "rhythmSectionSheet"],
  realEdgeRuntime: useEdgeHTTP,
  caseCount: results.length, results, cleanupPassed, productionAccessed: false,
  cleanupError: cleanupFailure?.message,
  publicationFixture: useEdgeHTTP ? "actual local Edge HTTP bearer/access/owner/metadata admission and atomic service RPC"
    : "service-only atomic publication RPC; Edge bearer/access/owner/metadata admission is separate",
  badgeFixture: "database-operator award/revoke; real authenticated clients have SELECT only",
  coverageBoundary: "Gateway data/authorization flow, not a physical iPad or app-screen walkthrough",
  migrations: { count: migrationNames.length, sha256: migrationHash.digest("hex"), last: migrationNames.at(-1) } };
if (process.env.ICHART_FORUM_GATEWAY_RECEIPT) {
  assert.ok(isAbsolute(process.env.ICHART_FORUM_GATEWAY_RECEIPT));
  await writeFile(process.env.ICHART_FORUM_GATEWAY_RECEIPT, JSON.stringify(receipt, null, 2) + "\n");
}
if (failure) throw failure;
console.log(JSON.stringify({ passed: true, caseCount: results.length, cleanupPassed, realAuth: true, realPostgREST: true, realStorage: true }));
