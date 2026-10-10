// Run with node --test scripts/test_telemetry_privacy_retention.mjs and an
// absolute ICHART_PGLITE_MODULE_PATH pointing to pinned PGlite 0.5.8's ESM entry.
// All records and roles below are synthetic, in a fresh in-memory database.
// The actual repository foundation and closeout migrations execute unchanged.
// cron.schedule is a REGISTRATION-ONLY adapter: no daemon, timer, real job run,
// Supabase Auth service, customer database, credentials or network is involved.

import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";

const modulePath = process.env.ICHART_PGLITE_MODULE_PATH;
assert.ok(typeof modulePath === "string" && isAbsolute(modulePath),
  "Set ICHART_PGLITE_MODULE_PATH to the absolute pinned PGlite 0.5.8 ESM entry path.");
const { PGlite } = await import(pathToFileURL(modulePath).href);
const foundationSQL = await readFile(new URL(
  "../supabase/migrations/20260813192919_telemetry_foundation.sql", import.meta.url), "utf8");
const closeoutSQL = await readFile(new URL(
  "../supabase/migrations/20261009230003_telemetry_privacy_retention_closeout.sql", import.meta.url), "utf8");

const ownerA = "11000000-0000-4000-8000-000000000001";
const ownerB = "11000000-0000-4000-8000-000000000002";
const sharedInstallation = "22000000-0000-4000-8000-000000000001";
const sharedSession = "33000000-0000-4000-8000-000000000001";
const retentionJobName = "ichart-telemetry-retention-180d";
const retentionCommand = "select private.purge_old_telemetry_events(180);";

// This adapter models named registration/upsert only. It deliberately never
// evaluates the supplied command; genuine pg_cron scheduling remains a live gate.
const syntheticPrerequisitesSQL = `
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;
  create schema auth;
  create table auth.users (id uuid primary key);
  insert into auth.users(id) values ('${ownerA}'), ('${ownerB}');
  create schema cron;
  create table cron.job (
    jobid bigint generated always as identity primary key,
    jobname text not null unique,
    schedule text not null,
    command text not null,
    active boolean not null default true
  );
  create function cron.schedule(job_name text, job_schedule text, job_command text)
  returns bigint language plpgsql as $$
  declare registered_job_id bigint;
  begin
    insert into cron.job(jobname, schedule, command)
    values (job_name, job_schedule, job_command)
    on conflict (jobname) do update
      set schedule = excluded.schedule, command = excluded.command, active = true
    returning jobid into registered_job_id;
    return registered_job_id;
  end;
  $$;
  select cron.schedule('unrelated-maintenance', '0 1 * * *', 'select 1;');
  create table public.retention_fixture_unrelated (id integer primary key, marker text not null);
  insert into public.retention_fixture_unrelated values (1, 'synthetic-preserve');
`;

async function fixture(t, { applyCloseout = true } = {}) {
  const db = await PGlite.create();
  t.after(() => db.close());
  await db.exec(syntheticPrerequisitesSQL);
  await db.exec(foundationSQL);
  if (applyCloseout) await db.exec(closeoutSQL);
  return db;
}

async function insertEvent(db, {
  label, ownerID = null, receivedSQL = "now()", occurredSQL = "now()",
} = {}) {
  // SQL expressions are hard-coded fixture timestamps, never external input.
  await db.query(`
    insert into public.telemetry_events (
      client_event_id, owner_id, installation_id, session_id, event_name,
      occurred_at, received_at, app_version, build_number, platform, os_version,
      device_model, locale_language, time_zone_offset_minutes, properties
    ) values ($1, $2, $3, $4, 'app.launched', ${occurredSQL}, ${receivedSQL},
      $5, '1', 'ios', 'synthetic', 'synthetic', 'en', 0, '{}')
  `, [randomUUID(), ownerID, sharedInstallation, sharedSession, label]);
}

async function labels(db) {
  return (await db.query("select app_version from public.telemetry_events order by app_version"))
    .rows.map(row => row.app_version);
}

async function purge(db, days) {
  const result = days === undefined
    ? await db.query("select private.purge_old_telemetry_events() as deleted")
    : await db.query("select private.purge_old_telemetry_events($1::integer) as deleted", [days]);
  return result.rows[0].deleted;
}

async function ownerForeignKey(db) {
  return (await db.query(`
    select conname, confdeltype, convalidated
    from pg_catalog.pg_constraint
    where conrelid = 'public.telemetry_events'::regclass
      and conname = 'telemetry_events_owner_id_fkey'
  `)).rows;
}

async function asRole(db, role, operation) {
  assert.ok(["anon", "authenticated", "service_role"].includes(role));
  await db.exec(`set role ${role}`);
  try { return await operation(); }
  finally { await db.exec("reset role"); }
}

test("default 180-day purge uses received_at, keeps the exact boundary, and includes signed-out rows", async (t) => {
  const db = await fixture(t);
  await db.exec("begin");
  try {
    await insertEvent(db, { label: "older-linked", ownerID: ownerA,
      receivedSQL: "now() - interval '180 days' - interval '1 microsecond'",
      occurredSQL: "now() + interval '1 day'" });
    await insertEvent(db, { label: "older-signedout",
      receivedSQL: "now() - interval '181 days'", occurredSQL: "now()" });
    await insertEvent(db, { label: "exact-boundary", ownerID: ownerA,
      receivedSQL: "now() - interval '180 days'", occurredSQL: "now() - interval '365 days'" });
    await insertEvent(db, { label: "newer-signedout",
      receivedSQL: "now() - interval '180 days' + interval '1 microsecond'",
      occurredSQL: "now() - interval '365 days'" });
    await insertEvent(db, { label: "new-received-old-client", ownerID: ownerB,
      receivedSQL: "now()", occurredSQL: "now() - interval '365 days'" });
    assert.equal(await purge(db), 2);
    assert.deepEqual(await labels(db), ["exact-boundary", "new-received-old-client", "newer-signedout"]);
    assert.equal(await purge(db, 180), 0);
    const rollup = await db.query("select sum(event_count)::integer as count from private.telemetry_daily_event_counts");
    assert.equal(rollup.rows[0].count, 3);
  } finally { await db.exec("rollback"); }
});

test("NULL and retention below 30 days reject without deleting records", async (t) => {
  const db = await fixture(t);
  await insertEvent(db, { label: "old-preserve", receivedSQL: "now() - interval '366 days'" });
  for (const days of [null, -1, 0, 29]) {
    const expectedMessage = days === null
      ? "retain_days must not be null"
      : "retain_days must be at least 30";
    await assert.rejects(purge(db, days), error => error.code === "P0001" && error.message === expectedMessage);
    assert.deepEqual(await labels(db), ["old-preserve"]);
  }
});

test("explicit 30-day minimum and longer retention preserve the helper's existing parameter behavior", async (t) => {
  const db = await fixture(t);
  await insertEvent(db, { label: "older-than-30", receivedSQL: "now() - interval '31 days'" });
  await insertEvent(db, { label: "newer-than-30", receivedSQL: "now() - interval '29 days'" });
  assert.equal(await purge(db, 30), 1);
  assert.deepEqual(await labels(db), ["newer-than-30"]);
  await insertEvent(db, { label: "older-than-365", receivedSQL: "now() - interval '366 days'" });
  await insertEvent(db, { label: "within-365", receivedSQL: "now() - interval '181 days'" });
  assert.equal(await purge(db, 365), 1);
  assert.deepEqual(await labels(db), ["newer-than-30", "within-365"]);
});

for (const role of ["anon", "authenticated"]) {
  test(`${role} cannot invoke the private purge or read/delete raw telemetry`, async (t) => {
    const db = await fixture(t);
    const grants = await db.query(`
      select has_function_privilege($1, 'private.purge_old_telemetry_events(integer)', 'execute') as execute,
        has_table_privilege($1, 'public.telemetry_events', 'select') as read,
        has_table_privilege($1, 'public.telemetry_events', 'insert') as insert,
        has_table_privilege($1, 'public.telemetry_events', 'delete') as delete
    `, [role]);
    assert.deepEqual(grants.rows[0], { execute: false, read: false, insert: false, delete: false });
    await asRole(db, role, async () => {
      await assert.rejects(purge(db, 180), error => error.code === "42501");
      await assert.rejects(db.query("select count(*) from public.telemetry_events"), error => error.code === "42501");
      await assert.rejects(db.query("delete from public.telemetry_events"), error => error.code === "42501");
    });
  });
}

test("service_role retains purge/table grants and can execute the real SECURITY DEFINER helper", async (t) => {
  const db = await fixture(t);
  const result = await db.query(`
    select has_schema_privilege('service_role', 'private', 'usage') as usage,
      has_function_privilege('service_role', 'private.purge_old_telemetry_events(integer)', 'execute') as execute,
      has_table_privilege('service_role', 'public.telemetry_events', 'select') as read,
      has_table_privilege('service_role', 'public.telemetry_events', 'insert') as insert,
      has_table_privilege('service_role', 'public.telemetry_events', 'delete') as delete
  `);
  assert.deepEqual(result.rows[0], { usage: true, execute: true, read: true, insert: true, delete: true });
  const definition = (await db.query(`
    select prosecdef, proconfig, pg_get_expr(proargdefaults, 0) as defaults
    from pg_catalog.pg_proc where oid = 'private.purge_old_telemetry_events(integer)'::regprocedure
  `)).rows[0];
  assert.equal(definition.prosecdef, true);
  assert.equal(definition.defaults, "180");
  assert.deepEqual(definition.proconfig, ["search_path=private"]);
  const table = (await db.query(`
    select relrowsecurity from pg_catalog.pg_class where oid = 'public.telemetry_events'::regclass
  `)).rows[0];
  assert.equal(table.relrowsecurity, true);
  await insertEvent(db, { label: "old-service", receivedSQL: "now() - interval '181 days'" });
  assert.equal(await asRole(db, "service_role", () => purge(db, 180)), 1);
  assert.deepEqual(await labels(db), []);
});

test("validated same-name owner FK cascades only linked telemetry, preserving shared-installation anonymous/other-owner rows", async (t) => {
  const db = await fixture(t);
  assert.deepEqual(await ownerForeignKey(db), [{ conname: "telemetry_events_owner_id_fkey", confdeltype: "c", convalidated: true }]);
  await insertEvent(db, { label: "owner-a", ownerID: ownerA });
  await insertEvent(db, { label: "owner-b", ownerID: ownerB });
  await insertEvent(db, { label: "anonymous" });
  await db.query("delete from auth.users where id = $1", [ownerA]);
  assert.deepEqual(await labels(db), ["anonymous", "owner-b"]);
  const preserved = (await db.query(`
    select app_version, owner_id, installation_id, session_id
    from public.telemetry_events order by app_version
  `)).rows;
  assert.deepEqual(preserved, [
    { app_version: "anonymous", owner_id: null, installation_id: sharedInstallation, session_id: sharedSession },
    { app_version: "owner-b", owner_id: ownerB, installation_id: sharedInstallation, session_id: sharedSession },
  ]);
  assert.equal((await db.query("select count(*)::integer as count from auth.users where id = $1", [ownerB])).rows[0].count, 1);
});

test("rolling back Auth deletion also restores its cascaded telemetry", async (t) => {
  const db = await fixture(t);
  await insertEvent(db, { label: "rollback-linked", ownerID: ownerA });
  await insertEvent(db, { label: "rollback-anonymous" });
  await db.exec("begin");
  try {
    await db.query("delete from auth.users where id = $1", [ownerA]);
    assert.deepEqual(await labels(db), ["rollback-anonymous"]);
  } finally { await db.exec("rollback"); }
  assert.deepEqual(await labels(db), ["rollback-anonymous", "rollback-linked"]);
  assert.equal((await db.query("select count(*)::integer as count from auth.users where id = $1", [ownerA])).rows[0].count, 1);
});

test("exact migration registers one proposed job, invokes no purge, and preserves unrelated jobs/table on replay", async (t) => {
  const db = await fixture(t, { applyCloseout: false });
  await insertEvent(db, { label: "migration-must-not-purge", ownerID: ownerA,
    receivedSQL: "now() - interval '366 days'" });
  assert.deepEqual(await ownerForeignKey(db), [{ conname: "telemetry_events_owner_id_fkey", confdeltype: "n", convalidated: true }]);
  const unrelatedJob = (await db.query("select * from cron.job where jobname = 'unrelated-maintenance'")).rows[0];
  await db.exec(closeoutSQL);
  const job = (await db.query("select * from cron.job where jobname = $1", [retentionJobName])).rows;
  assert.equal(job.length, 1);
  assert.equal(job[0].schedule, "15 3 * * *");
  assert.equal(job[0].command, retentionCommand);
  assert.equal(job[0].active, true);
  assert.deepEqual(await labels(db), ["migration-must-not-purge"]);
  await db.exec(closeoutSQL);
  assert.deepEqual((await db.query("select * from cron.job where jobname = $1", [retentionJobName])).rows, job);
  assert.equal((await db.query("select count(*)::integer as count from cron.job")).rows[0].count, 2);
  assert.deepEqual((await db.query("select * from cron.job where jobname = 'unrelated-maintenance'")).rows[0], unrelatedJob);
  assert.deepEqual((await db.query("select * from public.retention_fixture_unrelated")).rows,
    [{ id: 1, marker: "synthetic-preserve" }]);
  assert.deepEqual(await labels(db), ["migration-must-not-purge"]);
  assert.deepEqual(await ownerForeignKey(db), [{ conname: "telemetry_events_owner_id_fkey", confdeltype: "c", convalidated: true }]);
});

test("failed registration rolls back the exact migration's FK/helper changes atomically", async (t) => {
  const db = await fixture(t, { applyCloseout: false });
  await insertEvent(db, { label: "atomic-preserve", ownerID: ownerA,
    receivedSQL: "now() - interval '366 days'" });
  await db.exec(`
    create or replace function cron.schedule(job_name text, job_schedule text, job_command text)
    returns bigint language plpgsql as $$
    begin raise exception 'synthetic registration-only adapter failure'; end;
    $$;
  `);
  await assert.rejects(db.exec(closeoutSQL), /synthetic registration-only adapter failure/);
  await db.exec("rollback");
  assert.deepEqual(await ownerForeignKey(db), [{ conname: "telemetry_events_owner_id_fkey", confdeltype: "n", convalidated: true }]);
  assert.equal(await purge(db, null), 0, "foundation helper remains unchanged after failed migration");
  assert.deepEqual(await labels(db), ["atomic-preserve"]);
  assert.equal((await db.query("select count(*)::integer as count from cron.job where jobname = $1", [retentionJobName])).rows[0].count, 0);
});

test("missing cron.schedule rejects the exact migration without persisting any changes", async (t) => {
  const db = await fixture(t, { applyCloseout: false });
  await insertEvent(db, { label: "missing-cron-preserve", ownerID: ownerA,
    receivedSQL: "now() - interval '366 days'" });
  const unrelatedJob = (await db.query("select * from cron.job where jobname = 'unrelated-maintenance'")).rows[0];
  await db.exec("drop function cron.schedule(text, text, text)");
  await assert.rejects(db.exec(closeoutSQL), error => error.code === "P0001"
    && error.message === "pg_cron must be available before telemetry retention is configured");
  await db.exec("rollback");
  assert.deepEqual(await ownerForeignKey(db), [{ conname: "telemetry_events_owner_id_fkey", confdeltype: "n", convalidated: true }]);
  assert.equal(await purge(db, null), 0, "foundation helper remains unchanged when cron.schedule is unavailable");
  assert.deepEqual(await labels(db), ["missing-cron-preserve"]);
  assert.equal((await db.query("select count(*)::integer as count from cron.job where jobname = $1", [retentionJobName])).rows[0].count, 0);
  assert.deepEqual((await db.query("select * from cron.job where jobname = 'unrelated-maintenance'")).rows[0], unrelatedJob);
  assert.deepEqual((await db.query("select * from public.retention_fixture_unrelated")).rows,
    [{ id: 1, marker: "synthetic-preserve" }]);
});
