import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";

// Explicit opt-in to the NEW disposable container prepared by the audit runner.
// No automatic connection to the developer's existing Supabase stack.
const container = process.env.ICHART_AUTHORITY_TEST_CONTAINER;
const database = "ichart_authority_audit";
if (container) assert.match(container, /^[A-Za-z0-9][A-Za-z0-9_.-]*$/);
const literal = (value) => `'${String(value).replaceAll("'", "''")}'`;
const owner = (number) => `00000000-0000-4000-8000-${String(number).padStart(12, "0")}`;
const update = (original, signedAt, transaction, notificationID = null) => ({
  provider: "storekit", plan: "studioSubscription", status: "active",
  storekit_original_transaction_id: original, app_store_signed_at: signedAt,
  app_store_last_transaction_id: transaction, app_store_notification_uuid: notificationID,
});
const rpc = (authority, claimOwner = null) =>
  `public.apply_storekit_subscription_authority(${literal(JSON.stringify(authority))}::jsonb, ${claimOwner === null ? "null" : `${literal(claimOwner)}::uuid`})`;

function runSQL(sql, applicationName = "ichart-authority-audit-control", keepOpen = false) {
  const child = spawn("docker", ["exec", "-i", "-e", `PGAPPNAME=${applicationName}`, container,
    "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", database],
  { stdio: ["pipe", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.stdin.on("error", () => {}); // The process result retains an early SQL/transport failure.
  const result = new Promise((resolve, reject) => {
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve(stdout.trim());
      else reject(new Error(`Isolated authority SQL failed (${code}): ${stderr}`));
    });
  });
  // Attach a rejection observer immediately; polling readiness must not turn
  // an early SQL error into an unrelated unhandled-rejection failure.
  result.catch(() => {});
  if (keepOpen) child.stdin.write(sql);
  else child.stdin.end(sql);
  return { child, result };
}

async function sql(query) { return runSQL(query).result; }
function parsedResult(output) {
  const rows = output.split("\n").filter((line) => line.startsWith("{"));
  assert.equal(rows.length, 1, output);
  return JSON.parse(rows[0]);
}

async function assertIsolatedFixture() {
  assert.equal(await sql("select current_database();"), database);
  assert.equal(await sql("select to_regprocedure('public.audit_authority_update_failure()') is not null;"), "t");
}

async function seed(ownerID, original, signedAt = "2026-11-01T00:00:00Z") {
  await sql(`insert into auth.users(id) values (${literal(ownerID)}::uuid) on conflict do nothing;
    insert into public.subscriptions(owner_id, provider, plan, status, storekit_original_transaction_id,
      app_store_signed_at, app_store_last_transaction_id)
    values (${literal(ownerID)}::uuid, 'storekit', 'studioSubscription', 'active', ${literal(original)},
      ${literal(signedAt)}::timestamptz, '100');`);
}

async function waitForHeldTransaction(applicationName, job) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const ready = await sql(`select exists(select 1 from pg_stat_activity
      where application_name=${literal(applicationName)} and state='idle in transaction'
      and (select count(*) from pg_locks where pid=pg_stat_activity.pid
        and locktype='advisory' and granted) >= 2);`);
    if (ready === "t") return;
    if (job.child.exitCode !== null) await job.result;
    await delay(25);
  }
  assert.fail("First transaction did not reach its controlled hold after the RPC.");
}

async function waitForAdvisoryBlock(applicationName, job) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const blocked = await sql(`select exists(select 1 from pg_locks locks join pg_stat_activity activity
      on activity.pid=locks.pid where activity.application_name=${literal(applicationName)}
      and locks.locktype='advisory' and not locks.granted);`);
    if (blocked === "t") return;
    if (job.child.exitCode !== null) await job.result;
    await delay(25);
  }
  assert.fail("Second writer did not wait for the first transaction's advisory lock.");
}

async function interleave(label, firstExpression, secondExpression) {
  const firstName = `ichart-authority-audit-${label}-first`;
  const secondName = `ichart-authority-audit-${label}-second`;
  const first = runSQL(`begin; set local statement_timeout='10s'; set local role service_role;
    select ${firstExpression};\n`, firstName, true);
  try {
    await waitForHeldTransaction(firstName, first);
    const second = runSQL(`set statement_timeout='10s'; set role service_role; select ${secondExpression};`, secondName);
    await waitForAdvisoryBlock(secondName, second);
    // Release only after the second real database session is observably
    // blocked. No scheduler-dependent sleep decides transaction ordering.
    first.child.stdin.end("commit;\n");
    const results = await Promise.all([first.result, second.result]);
    return results.map(parsedResult);
  } finally {
    if (!first.child.stdin.destroyed && !first.child.stdin.writableEnded) first.child.stdin.end("rollback;\n");
  }
}

test("newer notification serializes against an older claim and cannot be overwritten", { skip: !container, timeout: 30_000 }, async () => {
  await assertIsolatedFixture();
  const id = owner(100001), original = "audit-notification-before-claim";
  await seed(id, original);
  const [first, second] = await interleave("notification-claim",
    rpc(update(original, "2026-11-04T00:00:00Z", "400", "audit-newest-notification")),
    rpc(update(original, "2026-11-03T00:00:00Z", "300"), id));
  assert.equal(first.mapping_status, "updated");
  assert.equal(second.mapping_status, "stale_transaction_claim");
  assert.equal(await sql(`select app_store_signed_at='2026-11-04T00:00:00Z'::timestamptz
    from public.subscriptions where owner_id=${literal(id)};`), "t");
});

test("newer claim serializes against an older notification and stale UUID remains acknowledged", { skip: !container, timeout: 30_000 }, async () => {
  await assertIsolatedFixture();
  const id = owner(100002), original = "audit-claim-before-notification";
  await seed(id, original);
  const [first, second] = await interleave("claim-notification",
    rpc(update(original, "2026-11-05T00:00:00Z", "500"), id),
    rpc(update(original, "2026-11-04T00:00:00Z", "400", "audit-stale-notification")));
  assert.equal(first.mapping_status, "claimed");
  assert.equal(second.mapping_status, "stale_notification");
  assert.equal(await sql("select count(*) from public.app_store_notification_events where notification_uuid='audit-stale-notification';"), "1");
  assert.equal(await sql(`select app_store_signed_at='2026-11-05T00:00:00Z'::timestamptz
    from public.subscriptions where owner_id=${literal(id)};`), "t");
});

test("concurrent first claims for one original cannot bind it to different owners", { skip: !container, timeout: 30_000 }, async () => {
  await assertIsolatedFixture();
  const firstID = owner(100003), secondID = owner(100004), original = "audit-competing-first-claim";
  await sql(`insert into auth.users(id) values (${literal(firstID)}::uuid),(${literal(secondID)}::uuid);`);
  const [first, second] = await interleave("first-claims",
    rpc(update(original, "2026-11-04T00:00:00Z", "400"), firstID),
    rpc(update(original, "2026-11-05T00:00:00Z", "500"), secondID));
  assert.equal(first.mapping_status, "claimed");
  assert.equal(second.mapping_status, "original_transaction_owner_conflict");
  assert.equal(await sql(`select owner_id::text from public.subscriptions
    where storekit_original_transaction_id=${literal(original)};`), firstID);
  assert.equal(await sql(`select count(*) from public.subscriptions where owner_id=${literal(secondID)};`), "0");
});

test("concurrent duplicate notification UUID commits one ledger row and one authority result", { skip: !container, timeout: 30_000 }, async () => {
  await assertIsolatedFixture();
  const id = owner(100005), original = "audit-duplicate-uuid";
  await seed(id, original);
  const expression = rpc(update(original, "2026-11-04T00:00:00Z", "400", "audit-duplicate-notification"));
  const [first, second] = await interleave("duplicate", expression, expression);
  assert.equal(first.mapping_status, "updated");
  assert.equal(second.mapping_status, "duplicate_notification");
  assert.equal(await sql("select count(*) from public.app_store_notification_events where notification_uuid='audit-duplicate-notification';"), "1");
});

test("notification rechecks mapping after a new-original claim moves the owner row", { skip: !container, timeout: 30_000 }, async () => {
  await assertIsolatedFixture();
  const id = owner(100006), original = "audit-moved-old-original", replacement = "audit-moved-new-original";
  await seed(id, original);
  const [first, second] = await interleave("owner-move",
    rpc(update(replacement, "2026-11-04T00:00:00Z", "400"), id),
    rpc(update(original, "2026-11-05T00:00:00Z", "500", "audit-now-unmapped-notification")));
  assert.equal(first.mapping_status, "claimed");
  assert.equal(second.mapping_status, "unmapped_original_transaction");
  assert.equal(await sql(`select storekit_original_transaction_id from public.subscriptions
    where owner_id=${literal(id)};`), replacement);
  assert.equal(await sql("select count(*) from public.app_store_notification_events where notification_uuid='audit-now-unmapped-notification';"), "0");
});

test("cross-owner claim swaps reject conflicts without taking two subscription rows", { skip: !container, timeout: 30_000 }, async () => {
  await assertIsolatedFixture();
  const firstID = owner(100007), secondID = owner(100008);
  const firstOriginal = "audit-swap-first", secondOriginal = "audit-swap-second";
  await seed(firstID, firstOriginal); await seed(secondID, secondOriginal);
  const results = await Promise.all([
    sql(`set role service_role; select ${rpc(update(secondOriginal, "2026-11-05T00:00:00Z", "500"), firstID)};`),
    sql(`set role service_role; select ${rpc(update(firstOriginal, "2026-11-05T00:00:00Z", "500"), secondID)};`),
  ]);
  assert.deepEqual(results.map((output) => parsedResult(output).mapping_status),
    ["original_transaction_owner_conflict", "original_transaction_owner_conflict"]);
  assert.equal(await sql(`select storekit_original_transaction_id from public.subscriptions where owner_id=${literal(firstID)};`), firstOriginal);
  assert.equal(await sql(`select storekit_original_transaction_id from public.subscriptions where owner_id=${literal(secondID)};`), secondOriginal);
});
