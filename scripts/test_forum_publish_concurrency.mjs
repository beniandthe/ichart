// Real, independent PostgreSQL sessions against a private synthetic cluster.
// Requires PostgreSQL 16+ server binaries, optionally at ICHART_POSTGRES_BIN.
// No Supabase/customer connection settings, credentials, or TCP listener are used.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomInt, randomUUID } from "node:crypto";
import { access, chmod, mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { constants } from "node:fs";
import { isAbsolute, join } from "node:path";
import { tmpdir } from "node:os";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";

const migrations = new URL("../supabase/migrations/", import.meta.url);
const migrationTail = [
  "20261015203728_free_pro_access.sql",
  "20261015232153_voluntary_free_pro_beta.sql",
  "20261016022548_atomic_forum_publication.sql",
];
const digest = "a".repeat(64);
const byteSize = 128;
// Ignore inherited libpq defaults, including service files, hosts and passwords.
const childEnv = Object.fromEntries(Object.entries(process.env)
  .filter(([key]) => !key.startsWith("PG") && key !== "PSQLRC"));
Object.assign(childEnv, { PGCONNECT_TIMEOUT: "5", LC_ALL: "C", TZ: "UTC" });

async function program(binary, args, timeout = 30_000) {
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, { env: childEnv, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", data => { output += data; });
    child.stderr.on("data", data => { output += data; });
    const timer = setTimeout(() => { child.kill("SIGKILL"); }, timeout);
    child.on("error", error => { clearTimeout(timer); reject(error); });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      if (code === 0) resolve(output.trim());
      else reject(new Error(`${binary} failed (${signal ?? code}):\n${output}`));
    });
  });
}

class Session {
  constructor(binary, args, name) {
    this.name = name;
    this.sequence = 0;
    this.buffer = "";
    this.stderr = "";
    this.child = spawn(binary, args, {
      env: { ...childEnv, PGAPPNAME: `ichart-forum-test-${name}` },
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.child.stdout.on("data", data => {
      this.buffer += data;
      let end;
      while ((end = this.buffer.indexOf("\n")) !== -1) {
        const line = this.buffer.slice(0, end).replace(/\r$/, "");
        this.buffer = this.buffer.slice(end + 1);
        if (line === this.pending?.marker) {
          const pending = this.pending;
          this.pending = undefined;
          clearTimeout(pending.timer);
          pending.resolve(pending.lines.filter(Boolean).join("\n"));
        } else if (this.pending) this.pending.lines.push(line);
      }
    });
    this.child.stderr.on("data", data => { this.stderr = (this.stderr + data).slice(-16_000); });
    this.child.on("error", error => this.fail(error));
    this.closed = new Promise(resolve => this.child.on("close", (code, signal) => {
      this.ended = true;
      this.fail(new Error(`${name}: psql exited (${signal ?? code})\n${this.stderr}`));
      resolve();
    }));
    // A failed backend can close stdin before the outstanding query settles.
    this.child.stdin.on("error", error => this.fail(error));
  }
  fail(error) {
    if (!this.pending) return;
    clearTimeout(this.pending.timer);
    this.pending.reject(error);
    this.pending = undefined;
  }
  command(sql) {
    assert.ok(!this.pending, `${this.name}: only one in-flight command per SQL session`);
    assert.ok(!this.ended, `${this.name}: SQL session already exited`);
    const marker = `ICHART_SQL_DONE_${this.sequence++}_${randomUUID().replaceAll("-", "")}`;
    const promise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.fail(new Error(`${this.name}: SQL command exceeded 25 seconds\n${this.stderr}`));
        this.child.kill("SIGKILL");
      }, 25_000);
      this.pending = { resolve, reject, marker, timer, lines: [] };
      this.child.stdin.write(`${sql}\n\\echo ${marker}\n`);
    });
    // Blocked operations are deliberately awaited after an observer query.
    promise.catch(() => {});
    return promise;
  }
  async close() {
    if (this.ended) return;
    this.child.kill("SIGTERM");
    const timer = setTimeout(() => this.child.kill("SIGKILL"), 2_000);
    try { await this.closed; } finally { clearTimeout(timer); }
  }
}

async function cluster() {
  const bin = process.env.ICHART_POSTGRES_BIN || await program("pg_config", ["--bindir"])
    .catch(error => { throw new Error(`PostgreSQL server binaries are required. Set absolute ICHART_POSTGRES_BIN. ${error.message}`); });
  assert.ok(isAbsolute(bin), "ICHART_POSTGRES_BIN / pg_config --bindir must be an absolute directory");
  for (const name of ["initdb", "pg_ctl", "psql"]) {
    await access(join(bin, name), constants.X_OK)
      .catch(() => { throw new Error(`Required PostgreSQL binary is missing or not executable: ${join(bin, name)}`); });
  }
  const version = await program(join(bin, "psql"), ["--version"]);
  assert.ok(Number(version.match(/PostgreSQL\) (\d+)/)?.[1]) >= 16, `PostgreSQL 16+ is required; found ${version}`);
  // /private/tmp keeps macOS Unix socket paths below the platform length limit.
  const temporaryParent = process.platform === "darwin" ? "/private/tmp" : tmpdir();
  const root = await mkdtemp(join(temporaryParent, "ichart-forum-"));
  await chmod(root, 0o700);
  const data = join(root, "data");
  const log = join(root, "postgres.log");
  const port = String(randomInt(20_000, 60_000));
  const sessions = new Set();
  let stopped = false;
  async function stop(success) {
    await Promise.all([...sessions].map(session => session.close()));
    try {
      await program(join(bin, "pg_ctl"), ["-D", data, "-m", "fast", "-t", "15", "-w", "stop"], 20_000);
      stopped = true;
    } catch (error) {
      // initdb/startup can fail before a postmaster exists; distinguish that case.
      try { await access(join(data, "postmaster.pid")); } catch { stopped = true; }
      if (!stopped) throw new Error(`Cluster shutdown failed; retained ${root}: ${error.message}`);
    }
    if (success) {
      assert.ok(root.startsWith(join(temporaryParent, "ichart-forum-")) && root !== temporaryParent);
      await rm(root, { recursive: true });
      console.log(`Isolated PostgreSQL cluster stopped and removed: ${root}`);
    } else console.error(`Failed fixture retained for diagnosis (server stopped): ${root}; log: ${log}`);
  }
  try {
    await program(join(bin, "initdb"), ["-D", data, "-U", "ichart_test_owner", "--auth-local=trust", "--auth-host=reject", "--no-locale", "--encoding=UTF8"]);
    await program(join(bin, "pg_ctl"), ["-D", data, "-l", log, "-t", "15", "-w", "-o",
      `-c listen_addresses='' -c unix_socket_directories='${root}' -c unix_socket_permissions=0700 -p ${port}`, "start"], 20_000);
  } catch (error) {
    await stop(false);
    throw error;
  }
  return {
    version, stop,
    async session(name) {
      const session = new Session(join(bin, "psql"), ["-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
        "-h", root, "-p", port, "-U", "ichart_test_owner", "-d", "postgres"], name);
      sessions.add(session);
      session.pid = Number(await session.command("set statement_timeout='15s'; set idle_in_transaction_session_timeout='30s'; select pg_backend_pid();"));
      assert.ok(Number.isInteger(session.pid) && session.pid > 0);
      return session;
    },
  };
}

async function fixture(observer) {
  // The same external Auth/Storage prerequisites as test_beta_pro_participation;
  // all app schema/functions/policies come from the unchanged real migrations.
  await observer.command(`
    create role anon nologin; create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create table auth.users(id uuid primary key, email text, phone text,
      raw_user_meta_data jsonb default '{}', email_confirmed_at timestamptz,
      phone_confirmed_at timestamptz, deleted_at timestamptz,
      banned_until timestamptz, is_anonymous boolean default false);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
    grant usage on schema auth to authenticated,anon,service_role;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),
      name text,owner uuid,owner_id text,metadata jsonb default '{}',created_at timestamptz default now());
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated,service_role;
    grant select,insert,update,delete on storage.objects to authenticated,service_role;
    create function storage.foldername(path text) returns text[] language sql immutable
      as $$ select string_to_array(regexp_replace(path,'/[^/]*$',''),'/'); $$;
    create function storage.extension(path text) returns text language sql immutable
      as $$ select regexp_replace(path,'^.*\\.',''); $$;
  `);
  const names = (await readdir(migrations)).filter(name => /^20260[67].*\.sql$/.test(name)).sort();
  for (const name of [...names, ...migrationTail]) {
    await observer.command(await readFile(new URL(name, migrations), "utf8"));
  }
}

async function seed(observer, existingMembership = false) {
  const owner = randomUUID(), song = randomUUID(), post = randomUUID();
  await observer.command(`
    insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
      values ('${owner}','${owner}@example.test',now(),'{"first_name":"Synthetic","last_name":"Tester"}');
    insert into public.forum_songs(id,song_title,artist_name,normalized_song_title,normalized_artist_name,created_by)
      values ('${song}','Synthetic Song ${song}','Synthetic Artist','synthetic song ${song}','synthetic artist','${owner}');
    insert into public.forum_chart_posts(id,song_id,owner_id,chart_title,arranger_credit,creator_display_name,layout_style,pdf_storage_path,status)
      values ('${post}','${song}','${owner}','Synthetic Chart','Synthetic Tester','Synthetic T.','simpleChordSheet','${owner}/${post}.pdf','pending');
    insert into storage.objects(bucket_id,name,owner,owner_id)
      values ('forum_chart_pdfs','${owner}/${post}.pdf','${owner}','${owner}');
    ${existingMembership ? `insert into private.free_pro_beta_memberships(owner_id,participating) values ('${owner}',true);` : ""}
  `);
  return { owner, post };
}

const publish = ({ owner, post }) => `public.publish_forum_chart_post('${post}'::uuid,'${owner}'::uuid,${byteSize},'${digest}')`;
const authenticate = owner => `set local role authenticated; set local request.jwt.claim.sub='${owner}';`;
const optOut = owner => `select public.set_free_pro_beta_participation(false,'${owner}'::uuid)->>'participating';`;
const ban = owner => `update auth.users set banned_until=now()+interval '1 day' where id='${owner}';`;
function denied(sql, code) {
  // Any unexpected success or other SQLSTATE still stops psql via ON_ERROR_STOP.
  return `do $$ begin perform ${sql}; raise exception 'Expected SQLSTATE ${code}';
    exception when sqlstate '${code}' then null; end $$; select 'denied-${code}';`;
}
async function postState(observer, post) {
  return JSON.parse(await observer.command(`select jsonb_build_object(
    'status',p.status,'provenance',p.pdf_provenance_status,'validated_at',p.pdf_validated_at,
    'proof_count',(select count(*) from private.forum_chart_pdf_provenance where post_id=p.id))
    from public.forum_chart_posts p where p.id='${post}';`));
}
async function blockedBy(observer, waiting, holding) {
  assert.notEqual(waiting.pid, holding.pid, "Concurrency requires distinct PostgreSQL backends");
  const deadline = Date.now() + 6_000;
  let activity;
  do {
    activity = JSON.parse(await observer.command(`select coalesce((select jsonb_build_object(
      'state',state,'wait_type',wait_event_type,'blockers',pg_blocking_pids(pid))
      from pg_stat_activity where pid=${waiting.pid}),'{}'::jsonb);`));
    if (activity.state === "active" && activity.wait_type === "Lock" && activity.blockers.includes(holding.pid)) return;
    if (!waiting.pending) assert.fail(`Session ${waiting.pid} completed before acquiring the required owner lock: ${JSON.stringify(activity)}`);
    await delay(20);
  } while (Date.now() < deadline);
  assert.fail(`No PostgreSQL blocking relationship ${waiting.pid} -> ${holding.pid}: ${JSON.stringify(activity)}`);
}

test("atomic Forum publication serializes with real competing PostgreSQL transactions", { timeout: 120_000 }, async t => {
  const db = await cluster();
  let success = false;
  let failed = false;
  async function scenario(name, body) {
    await t.test(name, async () => {
      try { await body(); } catch (error) { failed = true; throw error; }
    });
  }
  try {
    const observer = await db.session("observer");
    assert.equal(await observer.command("show listen_addresses;"), "", "Private cluster must not listen on TCP");
    await fixture(observer);
    t.diagnostic(`Database engine: ${db.version}; real migrations applied to synthetic Auth/Storage fixture`);
    for (const existing of [true, false]) {
      await scenario(`completed opt-out with ${existing ? "existing" : "initially missing"} membership denies waiting publication`, async () => {
        const row = await seed(observer, existing);
        const setter = await db.session(`setter-${existing}`), publisher = await db.session(`publisher-${existing}`);
        await setter.command(`begin; ${authenticate(row.owner)}`);
        assert.equal(await setter.command(optOut(row.owner)), "false");
        const publishing = publisher.command(`begin; set local role service_role; ${denied(publish(row), "42501")} commit;`);
        await blockedBy(observer, publisher, setter);
        assert.equal((await postState(observer, row.post)).status, "pending");
        await setter.command("commit;");
        assert.equal(await publishing, "denied-42501");
        assert.deepEqual(await postState(observer, row.post), { status: "pending", provenance: "pending", validated_at: null, proof_count: 0 });
        assert.equal(await observer.command(`select participating from private.free_pro_beta_memberships where owner_id='${row.owner}';`), "f");
        await Promise.all([setter.close(), publisher.close()]);
      });
    }
    await scenario("completed Auth ban denies publication that was waiting on the account row", async () => {
      const row = await seed(observer);
      const admin = await db.session("ban-first"), publisher = await db.session("publish-after-ban");
      await admin.command(`begin; ${ban(row.owner)}`);
      const publishing = publisher.command(`begin; set local role service_role; ${denied(publish(row), "42501")} commit;`);
      await blockedBy(observer, publisher, admin);
      await admin.command("commit;");
      assert.equal(await publishing, "denied-42501");
      assert.deepEqual(await postState(observer, row.post), { status: "pending", provenance: "pending", validated_at: null, proof_count: 0 });
      await Promise.all([admin.close(), publisher.close()]);
    });
    for (const change of ["opt-out", "Auth ban"]) {
      await scenario(`publisher holding owner lock prevents ${change} completion until publication commits`, async () => {
        const row = await seed(observer);
        const publisher = await db.session(`publish-first-${change}`), modifier = await db.session(`change-after-${change}`);
        await publisher.command("begin; set local role service_role;");
        assert.equal(await publisher.command(`select ${publish(row)}->>'status';`), "published");
        const changing = modifier.command(change === "opt-out"
          ? `begin; ${authenticate(row.owner)} ${optOut(row.owner)} commit;`
          : `begin; ${ban(row.owner)} commit; select 'banned';`);
        await blockedBy(observer, modifier, publisher);
        assert.deepEqual(await postState(observer, row.post), { status: "pending", provenance: "pending", validated_at: null, proof_count: 0 }, "Uncommitted publication and provenance must remain invisible");
        await publisher.command("commit;");
        assert.equal(await changing, change === "opt-out" ? "false" : "banned");
        const state = await postState(observer, row.post);
        assert.equal(state.status, "published");
        assert.equal(state.provenance, "validated");
        assert.ok(state.validated_at);
        assert.equal(state.proof_count, 1);
        assert.equal(await observer.command(change === "opt-out"
          ? `select participating is false from private.free_pro_beta_memberships where owner_id='${row.owner}';`
          : `select banned_until > now() from auth.users where id='${row.owner}';`), "t");
        await Promise.all([publisher.close(), modifier.close()]);
      });
    }
    await scenario("withdrawal committed before publication preserves removed status with no provenance", async () => {
      const row = await seed(observer);
      const withdrawal = await db.session("withdraw-first"), publisher = await db.session("publish-after-withdraw");
      await withdrawal.command(`begin; set local role service_role;
        update public.forum_chart_posts set status='removed' where id='${row.post}' and owner_id='${row.owner}' and status='pending'; commit;`);
      assert.equal(await publisher.command(`begin; set local role service_role; ${denied(publish(row), "55000")} commit;`), "denied-55000");
      assert.deepEqual(await postState(observer, row.post), { status: "removed", provenance: "pending", validated_at: null, proof_count: 0 });
      await Promise.all([withdrawal.close(), publisher.close()]);
    });
    success = !failed && !t.signal.aborted;
  } finally {
    await db.stop(success);
  }
});
