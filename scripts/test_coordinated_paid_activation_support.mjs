// Explicit local synthetic PostgreSQL fixture. Never resets the app database and
// never consumes Supabase URLs, credentials, service files or a hosted project.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID, randomInt, createHash } from 'node:crypto';
import { readFile, readdir, mkdtemp, chmod, rm } from 'node:fs/promises';
import { join, isAbsolute } from 'node:path';
import { tmpdir } from 'node:os';

const migrations = new URL('../supabase/migrations/', import.meta.url);
const tail = [
  '20261015203728_free_pro_access.sql', '20261015232153_voluntary_free_pro_beta.sql',
  '20261016022548_atomic_forum_publication.sql', '20261104151103_repair_forum_publication_gateway_boundary.sql',
  '20261106045008_atomic_storekit_subscription_authority.sql', '20261106045138_search_forum_home_pagination.sql',
  '20261121051720_owner_private_pdf_setlist_backups.sql',
  '20261121051725_verified_free_forum_browse_and_paid_feature_rollout.sql',
  '20261121065253_pdf_setlist_nonretryable_conflict.sql',
  '20261122163736_grant_service_role_notification_ledger_access.sql',
  '20261127184805_coordinated_paid_activation_compat.sql',
];
const childEnv = Object.fromEntries(Object.entries(process.env)
  .filter(([key]) => !key.startsWith('PG') && key !== 'PSQLRC'));
const prerequisites = `
create extension if not exists pgcrypto;
create schema auth;
create table auth.users(id uuid primary key,email text,phone text,raw_user_meta_data jsonb default '{}',
 email_confirmed_at timestamptz,phone_confirmed_at timestamptz,deleted_at timestamptz,
 banned_until timestamptz,is_anonymous boolean default false);
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
grant usage on schema auth to anon,authenticated,service_role;
create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),
 name text,owner uuid,owner_id text,metadata jsonb default '{}',created_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema storage to anon,authenticated,service_role;
grant select,insert,update,delete on storage.objects to authenticated,service_role;
create function storage.foldername(path text) returns text[] language sql immutable as $$
 select string_to_array(regexp_replace(path,'/[^/]*$',''),'/'); $$;
create function storage.extension(path text) returns text language sql immutable as $$
 select regexp_replace(path,'^.*\\.',''); $$;
`;

function args(container, database, name) {
  if (typeof container === 'object') return ['-h', container.root, '-p', String(container.port),
    '-U', 'postgres', '-d', database, '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'];
  return ['exec', '-i', '-e', `PGAPPNAME=${name}`, container, 'psql', '-X', '-q', '-A', '-t',
    '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate', '-U', 'postgres', '-d', database];
}
function program(binary, arguments_) {
  return new Promise((resolve,reject) => {
    const child=spawn(binary,arguments_,{env:childEnv,stdio:['ignore','pipe','pipe']});let output='';
    const timer=setTimeout(()=>child.kill('SIGKILL'),30000);
    child.stdout.on('data',x=>{output+=x;});child.stderr.on('data',x=>{output+=x;});
    child.on('error',error=>{clearTimeout(timer);reject(error);});
    child.on('close',(code,signal)=>{clearTimeout(timer);if(code===0)resolve(output.trim());else reject(new Error(`Private PostgreSQL command failed (${signal??code}): ${output}`));});
  });
}
function execute(container, database, sql) {
  return new Promise((resolve, reject) => {
    const child = spawn(typeof container === 'object' ? join(container.bin,'psql') : 'docker', args(container, database, 'ichart-coordinated-control'),
      { env: childEnv, stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '', error = '';
    const timer = setTimeout(() => child.kill('SIGKILL'), 30_000);
    child.stdout.on('data', x => { out += x; }); child.stderr.on('data', x => { error += x; });
    child.stdin.on('error', () => {});
    child.on('error', e => { clearTimeout(timer); reject(e); });
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      if (code === 0) resolve(out.trim());
      else reject(new Error(`Owned synthetic database SQL failed (${signal ?? code}): ${error}`));
    });
    child.stdin.end(sql);
  });
}
class Session {
  constructor(container, database, name) {
    this.name = name; this.sequence = 0; this.buffer = ''; this.stderr = '';
    this.child = spawn(typeof container === 'object' ? join(container.bin,'psql') : 'docker', args(container, database, name),
      { env: childEnv, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stdout.on('data', data => {
      this.buffer += data;
      let end;
      while ((end = this.buffer.indexOf('\n')) >= 0) {
        const line = this.buffer.slice(0, end).replace(/\r$/, '');
        this.buffer = this.buffer.slice(end + 1);
        if (line === this.pending?.marker) {
          const p = this.pending; this.pending = undefined; clearTimeout(p.timer);
          p.resolve(p.lines.filter(Boolean).join('\n'));
        } else if (this.pending) this.pending.lines.push(line);
      }
    });
    this.child.stderr.on('data', data => { this.stderr = (this.stderr + data).slice(-16000); });
    this.child.stdin.on('error', error => this.fail(error));
    this.child.on('error', error => this.fail(error));
    this.closed = new Promise(resolve => this.child.on('close', (code, signal) => {
      this.ended = true; this.fail(new Error(`Local SQL session ${name} exited (${signal ?? code}): ${this.stderr}`)); resolve();
    }));
  }
  fail(error) {
    if (!this.pending) return;
    const p = this.pending; this.pending = undefined; clearTimeout(p.timer); p.reject(error);
  }
  command(sql) {
    assert.ok(!this.pending && !this.ended, 'One command per live owned SQL session');
    const result = new Promise((resolve, reject) => {
      const marker = `COORDINATED_${++this.sequence}_${randomUUID()}`;
      const timer = setTimeout(() => { this.fail(new Error(`Local SQL session timed out: ${this.name}`)); this.child.kill('SIGKILL'); }, 20000);
      this.pending = { resolve, reject, marker, timer, lines: [] };
      this.child.stdin.write(`${sql}\n\\echo ${marker}\n`);
    });
    result.catch(() => {}); return result;
  }
  async close() {
    if (!this.ended) this.child.stdin.end();
    const timer = setTimeout(() => this.child.kill('SIGKILL'), 2000);
    try { await this.closed; } finally { clearTimeout(timer); }
  }
}
export async function createFixture() {
  let container = process.env.ICHART_COORDINATED_TEST_CONTAINER;
  const bin = process.env.ICHART_POSTGRES_BIN;
  assert.ok(container || bin, 'Set explicit local ICHART_COORDINATED_TEST_CONTAINER or ICHART_POSTGRES_BIN; no hosted connection is accepted');
  if (container) assert.match(container, /^[A-Za-z0-9][A-Za-z0-9_.-]*$/);
  else {
    assert.ok(isAbsolute(bin), 'PostgreSQL binaries require an absolute local directory');
    const version = await program(join(bin,'postgres'), ['--version']);
    assert.ok(Number(version.match(/PostgreSQL\) (\d+)/)?.[1]) >= 16, 'Private native PostgreSQL16+ is required');
    const root = await mkdtemp(join(tmpdir(), 'ichart-activation-')); await chmod(root, 0o700);
    container = { bin, root, port: randomInt(55000, 64000), data: join(root, 'data') };
    try {
      await program(join(bin,'initdb'), ['-D',container.data,'-U','postgres','--auth-local=trust','--auth-host=reject','--no-locale','--encoding=UTF8']);
      await program(join(bin,'pg_ctl'), ['-D',container.data,'-l',join(root,'postgres.log'),'-t','15','-w','-o',
        `-c listen_addresses='' -c unix_socket_directories='${root}' -c unix_socket_permissions=0700 -p ${container.port}`,'start']);
    } catch (error) {
      let started=false;try { await readFile(join(container.data,'postmaster.pid'));started=true; } catch {}
      if (started) await program(join(bin,'pg_ctl'),['-D',container.data,'-m','immediate','-t','15','-w','stop']);
      console.error(`Private startup fixture retained: ${root}`);throw error;
    }
  }
  const database = `ichart_activation_${randomUUID().replaceAll('-', '')}`;
  const sessions = new Set(); const applied = [];
  let created=false;
  const db = {
    container: typeof container === 'object' ? 'private-native-postgres' : container, database, applied,
    query: sql => execute(container, database, sql),
    async session(name) {
      const s = new Session(container, database, `ichart-activation-${database.slice(-8)}-${name}`); sessions.add(s);
      s.pid = Number(await s.command("set statement_timeout='15s'; set idle_in_transaction_session_timeout='30s'; select pg_backend_pid();"));
      assert.ok(Number.isSafeInteger(s.pid) && s.pid > 0); return s;
    },
    async close(success = true) {
      await Promise.all([...sessions].map(s => s.close()));
      assert.match(database, /^ichart_activation_[a-f0-9]{32}$/);
      try {
        if (success && created) await execute(container, 'postgres', `drop database ${database} with (force);`);
        else console.error(`Failed synthetic fixture retained for diagnosis: ${database}`);
      } finally {
        if (typeof container === 'object') {
          await program(join(container.bin,'pg_ctl'), ['-D',container.data,'-m','immediate','-t','15','-w','stop']);
          if (success) { assert.ok(container.root.startsWith(join(tmpdir(),'ichart-activation-'))); await rm(container.root,{recursive:true}); }
          else console.error(`Stopped private PostgreSQL cluster retained: ${container.root}`);
        }
      }
    },
  };
  try {
    await execute(container, 'postgres', `create database ${database};`);created=true;
    assert.equal(await db.query('select current_database();'), database);
    if (typeof container === 'object') {
      await db.query('create role anon nologin;create role authenticated nologin;create role service_role nologin bypassrls;');
      assert.equal(await db.query('show listen_addresses;'), '', 'Private native cluster must not listen on TCP');
    }
    assert.equal(await db.query("select count(*) from pg_roles where rolname in ('anon','authenticated','service_role');"), '3');
    await db.query(prerequisites);
    const baseline = (await readdir(migrations)).filter(n => /^20260[67].*\.sql$/.test(n)).sort();
    for (const name of [...baseline, ...tail]) {
      const bytes = await readFile(new URL(name, migrations));
      await db.query(bytes.toString()); applied.push({ name, sha256: createHash('sha256').update(bytes).digest('hex') });
    }
    return db;
  } catch (error) { await db.close(false); throw error; }
}
export const owner = 'c1210000-0000-4000-8000-000000000001';
export const other = 'c1210000-0000-4000-8000-000000000002';
export const seed = `
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 ('${owner}','activation-owner@example.test',now(),'{"first_name":"Synthetic","last_name":"Owner"}'),
 ('${other}','activation-other@example.test',now(),'{"first_name":"Synthetic","last_name":"Other"}');
insert into public.chart_documents(id,owner_id,title,layout_style) values
 ('c1210000-0000-4000-8000-000000000003','${owner}','Retained synthetic chart','simpleChordSheet');
insert into public.chart_snapshots(id,chart_id,owner_id,version,chart_json) values
 ('c1210000-0000-4000-8000-000000000004','c1210000-0000-4000-8000-000000000003','${owner}',1,'{"syntheticOpaqueInk":"must remain byte-equivalent JSON"}');
`;
export const auth = (id = owner) => `set local role authenticated;set local request.jwt.claim.sub='${id}';`;
export const strictPaid = `update public.subscriptions set provider='storekit',plan='studioSubscription',status='active',
 app_store_status='active',entitlement_expires_at=now()+interval '1 day',last_verified_at=now(),revoked_at=null
 where owner_id='${owner}';`;
export const assertHelpers = `
create function pg_temp.check_true(value boolean,label text) returns void language plpgsql as $$
 begin if value is distinct from true then raise exception 'Contract check failed: %',label;end if;end$$;
create function pg_temp.expect_error(statement text,expected text) returns void language plpgsql as $$
 begin begin execute statement;exception when others then
 if sqlstate=expected then return;end if;raise exception 'Wrong SQLSTATE %, expected %',sqlstate,expected;
 end;raise exception 'Expected rejection % did not occur',expected;end$$;
`;
