// Synthetic integration tests only. Every invocation initializes a new private
// PostgreSQL cluster; no existing database, Supabase stack or TCP endpoint is used.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { gzipSync, gunzipSync } from 'node:zlib';
import { readFile, mkdtemp, chmod, realpath, stat } from 'node:fs/promises';
import { isAbsolute, dirname, join, extname, relative, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { before, after, test } from 'node:test';

const root = dirname(fileURLToPath(import.meta.url));
const bin = process.env.ICHART_RETENTION_TEST_PG_BIN;
const migration = process.env.ICHART_RETENTION_MIGRATION_SQL
  ?? join(root, '../../migrations/20261106170932_owner_scoped_chart_snapshot_retention.sql');
const frozenMigrationSHA = 'b3147d4aab4e4ebfdb4e112c4ec0ad49241d7fd502e2db1df59ac25600084f1a';
assert.ok(typeof bin === 'string' && isAbsolute(bin),
  'Set ICHART_RETENTION_TEST_PG_BIN to an absolute native PostgreSQL 17.11 binary directory.');
assert.ok(isAbsolute(migration) && extname(migration) === '.sql',
  'Use the repository migration or an absolute path to the same frozen SQL bytes.');
assert.notEqual(process.getuid?.(), 0, 'Run the private PostgreSQL fixture as an unprivileged user.');
const admin = 'ichart_retention_fixture';
const port = '5432';
let clusterRoot, dataRoot, migrationSQL, migrationSHA, fixtureSQL, fixtureSHA;
let initialized = false, started = false;
const cleanEnv = Object.fromEntries(Object.entries(process.env)
  .filter(([key]) => !key.startsWith('PG') && key !== 'PSQLRC'));
Object.assign(cleanEnv, { LC_ALL: 'C', TZ: 'UTC', PGCONNECT_TIMEOUT: '5',
  PGPASSFILE: '/dev/null', PSQL_HISTORY: '/dev/null' });
const ownerA = '10000000-0000-4000-8000-000000000001';
const ownerB = '10000000-0000-4000-8000-000000000002';
const chartA = '20000000-0000-4000-8000-000000000001';
const chartB = '20000000-0000-4000-8000-000000000002';
const chartC = '20000000-0000-4000-8000-000000000003';
const id = n => `30000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const lit = value => value == null ? 'null' : `'${String(value).replaceAll("'", "''")}'`;
const sha = value => createHash('sha256').update(value).digest('hex');
const parseJSON = output => {
  const lines = output.trim().split('\n').filter(x => x.startsWith('{') || x.startsWith('['));
  assert.equal(lines.length, 1, `Expected one synthetic JSON result: ${output}`);
  return JSON.parse(lines[0]);
};

function program(binary, args, input = '', timeout = 30_000) {
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, { stdio: ['pipe', 'pipe', 'pipe'], env: cleanEnv });
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data; });
    child.stderr.on('data', data => { stderr += data; });
    const timer = setTimeout(() => child.kill('SIGKILL'), timeout);
    child.on('error', error => { clearTimeout(timer); reject(error); });
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      if (code === 0) resolve(stdout);
      else {
        const error = new Error(`${binary} (${signal ?? code}): ${stderr}\n${stdout}`);
        error.exitCode = code;
        reject(error);
      }
    });
    child.stdin.end(input);
  });
}
const connectionArgs = db => ['-h', clusterRoot, '-p', port, '-U', admin, '-d', db];
const psqlArgs = db => ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', ...connectionArgs(db)];
const psql = (db, text) => program(join(bin, 'psql'), psqlArgs(db), text);

before(async () => {
  const version = await program(join(bin, 'postgres'), ['--version']);
  assert.match(version, /PostgreSQL\) 17\.11(?:\s|$)/);
  assert.ok((await stat(await realpath(migration))).isFile(), 'Migration must be a regular SQL file.');
  migrationSQL = await readFile(migration, 'utf8');
  migrationSHA = sha(Buffer.from(migrationSQL));
  assert.equal(migrationSHA, frozenMigrationSHA, 'Migration differs from the frozen integration-test revision.');
  fixtureSQL = await readFile(join(root, 'fixture.sql'), 'utf8');
  fixtureSHA = sha(Buffer.from(fixtureSQL));
  console.log(`Frozen migration SHA256: ${migrationSHA}`);
  assert.ok(isAbsolute(tmpdir()), 'TMPDIR must be an absolute path outside the repository.');
  const parent = await realpath(tmpdir());
  const repository = await realpath(join(root, '../../..'));
  const parentFromRepository = relative(repository, parent);
  assert.ok(parentFromRepository === '..' || parentFromRepository.startsWith(`..${sep}`)
    || isAbsolute(parentFromRepository), 'TMPDIR must not create a cluster inside the repository.');
  clusterRoot = await mkdtemp(join(parent, 'ichart-retention-'));
  await chmod(clusterRoot, 0o700);
  // pg_ctl parses its -o argument; reject ambiguous paths instead of allowing
  // environment-selected temporary directories to alter PostgreSQL options.
  assert.match(clusterRoot, /^[A-Za-z0-9_./-]+$/, 'TMPDIR must use a simple absolute Unix path.');
  assert.ok(Buffer.byteLength(join(clusterRoot, `.s.PGSQL.${port}`)) < 104,
    'TMPDIR is too long for a portable PostgreSQL Unix socket.');
  dataRoot = join(clusterRoot, 'data');
  await program(join(bin, 'initdb'), ['-D', dataRoot, '-U', admin, '--auth-local=trust',
    '--auth-host=reject', '--no-locale', '--encoding=UTF8']);
  initialized = true;
  await program(join(bin, 'pg_ctl'), ['-D', dataRoot, '-l', join(clusterRoot, 'postgres.log'),
    '-t', '15', '-w', '-o', `-c listen_addresses='' -c unix_socket_directories='${clusterRoot}' -c unix_socket_permissions=0700 -p ${port}`, 'start']);
  started = true;
  const settings = parseJSON(await psql('postgres', "select jsonb_build_object('version',current_setting('server_version_num'), 'listen',current_setting('listen_addresses'), 'socket',current_setting('unix_socket_directories'))"));
  assert.equal(Number(settings.version), 170011);
  assert.equal(settings.listen, ''); assert.equal(settings.socket, clusterRoot);
  console.log('Private PostgreSQL 17.11 cluster verified: TCP disabled, Unix socket only.');
});
after(async () => {
  // A failed startup waiter can leave its postmaster alive. Inspect only the
  // private data directory created above and stop it even when start rejected.
  if (initialized && !started) {
    try {
      await program(join(bin, 'pg_ctl'), ['-D', dataRoot, 'status']);
      started = true;
    } catch (error) {
      // pg_ctl status uses exit 3 when this data directory has no running server.
      if (error.exitCode !== 3) throw error;
    }
  }
  if (started) await program(join(bin, 'pg_ctl'), ['-D', dataRoot, '-m', 'fast', '-t', '15', '-w', 'stop']);
  if (migrationSHA) assert.equal(sha(await readFile(migration)), migrationSHA,
    'SQL source changed during validation; rerun the frozen revision.');
  if (fixtureSHA) assert.equal(sha(await readFile(join(root, 'fixture.sql'))), fixtureSHA,
    'Synthetic fixture changed during validation.');
});

class Session {
  constructor(db, name) {
    this.child = spawn(join(bin, 'psql'), psqlArgs(db), { stdio: ['pipe', 'pipe', 'pipe'], env: cleanEnv });
    this.child.stdin.on('error', () => {}); // SQL/process failures propagate via close, including expected FK errors.
    this.buffer = ''; this.stderr = ''; this.pending = null;
    this.child.stdout.on('data', data => { this.buffer += data; this.consume(); });
    this.child.stderr.on('data', data => { this.stderr += data; });
    this.child.on('close', (code, signal) => {
      if (this.pending) {
        clearTimeout(this.pending.timer);
        this.pending.reject(new Error(`Session ${name} closed (${signal ?? code}): ${this.stderr}`));
        this.pending = null;
      }
    });
    this.name = name;
  }
  consume() {
    if (!this.pending) return;
    const position = this.buffer.indexOf(this.pending.marker + '\n');
    if (position < 0) return;
    const output = this.buffer.slice(0, position);
    this.buffer = this.buffer.slice(position + this.pending.marker.length + 1);
    const pending = this.pending; this.pending = null;
    clearTimeout(pending.timer); pending.resolve(output);
  }
  sql(sql, timeout = 15_000) {
    assert.equal(this.pending, null, 'Only one command may be pending per interactive session.');
    const marker = `END_${randomUUID().replaceAll('-', '')}`;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending = null; this.child.kill('SIGKILL');
        reject(new Error(`Session ${this.name} timeout: ${this.stderr}`));
      }, timeout);
      this.pending = { marker, resolve, reject, timer };
      this.child.stdin.write(`${sql}\n\\echo ${marker}\n`);
    });
  }
  async pid() {
    return Number((await this.sql(`set application_name=${lit(this.name)};select pg_backend_pid();`)).trim());
  }
  stop() {
    if (this.child.exitCode != null || this.child.signalCode != null) return;
    this.child.stdin.end('rollback;\n\\q\n'); this.child.kill('SIGTERM');
  }
}

async function fixture(t, body) {
  const db = `ichart_retention_test_${randomUUID().replaceAll('-', '').slice(0, 16)}`;
  const sessions = [];
  const archives = new Map();
  await program(join(bin, 'createdb'), ['-h', clusterRoot, '-p', port, '-U', admin, db]);
  const sql = text => psql(db, text);
  const json = async text => parseJSON(await sql(text));
  const service = async text => json(`set role service_role;${text};reset role;`);
  const session = name => { const s = new Session(db, name); sessions.push(s); return s; };
  try {
    await sql(fixtureSQL);
    await sql(migrationSQL);
    const api = {
      db, sql, json, service, session,
      async configure({ enabled = true, initialVerified = false } = {}) {
        await sql(`insert into ichart_snapshot_retention.policy(singleton,owner_id,enabled,bucket,
          max_batch_rows,max_batch_bytes,daily_max_rows,initial_archive_cutoff_at,
          initial_restore_verified_at,initial_restore_manifest_sha256)
          values(true,${lit(ownerA)},${enabled},'ichart-owner-snapshot-archives',100,4194304,1000,
            clock_timestamp(),${initialVerified ? 'clock_timestamp()' : 'null'},
            ${initialVerified ? lit('1'.repeat(64)) : 'null'})
          on conflict(singleton) do update set owner_id=excluded.owner_id,enabled=excluded.enabled,
            bucket=excluded.bucket,max_batch_rows=excluded.max_batch_rows,
            max_batch_bytes=excluded.max_batch_bytes,daily_max_rows=excluded.daily_max_rows,
            initial_archive_cutoff_at=excluded.initial_archive_cutoff_at,
            initial_restore_verified_at=excluded.initial_restore_verified_at,
            initial_restore_manifest_sha256=excluded.initial_restore_manifest_sha256;`);
      },
      seed(owner, chart, base, count = 40) {
        return sql(`select fixture.seed_history(${lit(owner)},${lit(chart)},${base},${count});`);
      },
      plan(limit = 100, timezone = 'UTC') {
        return service(`set timezone=${lit(timezone)};select public.plan_owner_snapshot_retention(${limit})`);
      },
      finalize(batch, overrides = {}) {
        const bytes = archives.get(batch.batch_id)
          ?? gzipSync(Buffer.from(batch.rows.map(row => row.row_text + '\n').join('')));
        return service(`set timezone=${lit(overrides.timezone ?? 'UTC')};select public.finalize_owner_snapshot_archive(${lit(batch.batch_id)},
          ${lit(overrides.archiveSHA ?? sha(bytes))},${overrides.archiveBytes ?? bytes.length},
          ${lit(overrides.manifestSHA ?? batch.manifest_sha256)},${overrides.rowCount ?? batch.row_count})`);
      },
      status() { return service('select public.owner_snapshot_retention_status()'); },
      async markInitialVerified(manifest = '1'.repeat(64)) {
        const status = await api.status();
        assert.equal(status.initial_remaining_rows, 0, 'Never bypass initial full-archive verification.');
        await sql(`update ichart_snapshot_retention.policy set initial_restore_verified_at=clock_timestamp(),
          initial_restore_manifest_sha256=${lit(manifest)} where singleton;`);
      },
      async archiveAndRestore(batch) {
        assert.ok(['planned', 'verified'].includes(batch.status));
        assert.equal(batch.rows.length, batch.row_count);
        assert.ok(batch.rows.length > 0);
        let rows = batch.rows;
        if (batch.status === 'verified') {
          const stored = archives.get(batch.batch_id);
          assert.ok(stored, 'Must re-read an existing immutable archive, never invent missing row text.');
          assert.equal(sha(stored), batch.archive_sha256);
          assert.equal(stored.length, batch.archive_bytes);
          const lines = gunzipSync(stored).toString('utf8');
          assert.ok(lines.endsWith('\n'));
          rows = lines.slice(0, -1).split('\n').map(row_text => ({
            snapshot_id: JSON.parse(row_text).id, row_text, row_sha256: sha(Buffer.from(row_text))
          }));
          assert.deepEqual(rows.map(({ snapshot_id, row_sha256 }) => ({ snapshot_id, row_sha256 })),
            batch.rows.map(({ snapshot_id, row_sha256 }) => ({ snapshot_id, row_sha256 })));
        }
        const ordered = [...rows].sort((a, b) => a.snapshot_id.localeCompare(b.snapshot_id));
        assert.deepEqual(rows.map(x => x.snapshot_id), ordered.map(x => x.snapshot_id));
        for (const row of rows) assert.equal(sha(Buffer.from(row.row_text)), row.row_sha256);
        const manifest = ordered.map(row => row.snapshot_id.toLowerCase() + ':' + row.row_sha256).join('\n');
        assert.equal(sha(Buffer.from(manifest)), batch.manifest_sha256);
        const jsonl = Buffer.from(rows.map(row => row.row_text + '\n').join(''));
        assert.equal(jsonl.length, batch.uncompressed_bytes);
        const compressed = gzipSync(jsonl);
        assert.deepEqual(gunzipSync(compressed), jsonl);
        if (archives.has(batch.batch_id)) assert.deepEqual(archives.get(batch.batch_id), compressed);
        else archives.set(batch.batch_id, compressed);
        // Reconstruct PostgreSQL rows from the original opaque JSON strings.
        // Node never parses/reserializes chart_json numbers or source bytes.
        await sql('create table if not exists fixture.restored_snapshots (like public.chart_snapshots including all);truncate fixture.restored_snapshots;');
        for (const row of rows) {
          await sql(`insert into fixture.restored_snapshots select (jsonb_populate_record(
            null::public.chart_snapshots,${lit(row.row_text)}::jsonb)).*;`);
        }
        const restored = await json(`set timezone='UTC';select coalesce(jsonb_agg(jsonb_build_object(
          'snapshot_id',id,'row_text',to_jsonb(r)::text,
          'row_sha256',encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex'))
          order by id),'[]'::jsonb) from fixture.restored_snapshots r;`);
        assert.deepEqual(restored, rows.map(row => ({ snapshot_id: row.snapshot_id,
          row_text: row.row_text, row_sha256: row.row_sha256 })));
        return { jsonl, compressed, manifestSHA: sha(Buffer.from(manifest)) };
      },
      async bootstrap() {
        const batch = await api.plan();
        await api.archiveAndRestore(batch);
        const before = await json("select jsonb_build_object('rows',count(*)) from public.chart_snapshots;");
        const result = await api.finalize(batch);
        assert.equal(result.status, 'verified_waiting_initial_restore');
        assert.equal(result.deleted_count ?? 0, 0);
        assert.deepEqual(await json("select jsonb_build_object('rows',count(*)) from public.chart_snapshots;"), before);
        await api.markInitialVerified(batch.manifest_sha256);
        return batch;
      },
      async waitBlocked(pid) {
        const deadline = Date.now() + 5_000;
        while (Date.now() < deadline) {
          const state = await json(`select jsonb_build_object('blocked',coalesce((select
            wait_event_type='Lock' from pg_stat_activity where pid=${pid} and datname=current_database()),false));`);
          if (state.blocked) return;
          await new Promise(resolve => setTimeout(resolve, 10));
        }
        assert.fail(`Synthetic backend ${pid} never entered a proven lock wait.`);
      },
      finalizeSQL(batch) {
        const bytes = archives.get(batch.batch_id);
        assert.ok(bytes, 'Concurrent finalization requires actual synthetic archive bytes.');
        return `select public.finalize_owner_snapshot_archive(${lit(batch.batch_id)},${lit(sha(bytes))},
          ${bytes.length},${lit(batch.manifest_sha256)},${batch.row_count});`;
      }
    };
    await body(api);
  } finally {
    for (const s of sessions) s.stop();
    assert.match(db, /^ichart_retention_test_[a-z0-9]+$/);
    await program(join(bin, 'dropdb'), ['-h', clusterRoot, '-p', port, '-U', admin, '--if-exists', '--force', db]);
  }
}

test('missing/disabled singleton and client roles fail closed', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0);
  assert.equal((await f.plan()).status, 'disabled');
  await f.configure({ enabled: false });
  assert.equal((await f.plan()).status, 'disabled');
  await assert.rejects(f.sql('set role authenticated;select public.plan_owner_snapshot_retention(100);'), /permission denied|Service role/i);
  await assert.rejects(f.sql('set role anon;select public.owner_snapshot_retention_status();'), /permission denied|Service role/i);
  await assert.rejects(f.sql(`set role service_role;update ichart_snapshot_retention.policy set owner_id=${lit(ownerB)};`), /permission denied/i);
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 40);
}));

test('initial bootstrap archives and restores the complete owner history before any pruning', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0);
  await f.seed(ownerB, chartB, 100);
  await f.configure();
  const otherBefore = await f.json(`select jsonb_build_object('docs',(select jsonb_agg(to_jsonb(d) order by id)
    from public.chart_documents d where owner_id=${lit(ownerB)}),'snapshots',(select jsonb_agg(to_jsonb(s) order by id)
    from public.chart_snapshots s where owner_id=${lit(ownerB)}));`);
  const batch = await f.bootstrap();
  assert.equal(batch.row_count, 40, 'Bootstrap includes current/protected revisions too.');
  assert.ok(batch.rows.every(row => JSON.parse(row.row_text).owner_id === ownerA));
  const result = await f.finalize(batch);
  assert.equal(result.status, 'pruned');
  assert.ok(result.deleted_count > 0);
  const remaining = await f.json(`select jsonb_build_object('a',count(*) filter(where owner_id=${lit(ownerA)}),
    'b',count(*) filter(where owner_id=${lit(ownerB)})) from public.chart_snapshots;`);
  assert.equal(remaining.b, 40);
  assert.ok(remaining.a >= 10 && remaining.a < 40);
  assert.deepEqual(await f.json(`select jsonb_build_object('docs',(select jsonb_agg(to_jsonb(d) order by id)
    from public.chart_documents d where owner_id=${lit(ownerB)}),'snapshots',(select jsonb_agg(to_jsonb(s) order by id)
    from public.chart_snapshots s where owner_id=${lit(ownerB)}));`), otherBefore);
}));

test('current old head, NULL-head highest-version fallback and tombstone documents survive', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0);
  await f.seed(ownerA, chartB, 100);
  await f.seed(ownerA, chartC, 200);
  await f.sql(`update public.chart_documents set latest_snapshot_id=${lit(id(1))} where id=${lit(chartA)};
    update public.chart_documents set latest_snapshot_id=null where id=${lit(chartB)};
    update public.chart_snapshots set version=10000,created_at=clock_timestamp()-interval '100 days'
      where id=${lit(id(105))};
    update public.chart_documents set deleted_at=clock_timestamp()-interval '40 days',latest_snapshot_id=null
      where id=${lit(chartC)};`);
  await f.configure();
  // Force more than one bootstrap chunk, then verify the full initial set.
  let batches = [];
  for (let n = 0; n < 3; n += 1) {
    const batch = await f.plan();
    if (batch.status !== 'planned') break;
    await f.archiveAndRestore(batch); await f.finalize(batch); batches.push(batch);
  }
  await f.markInitialVerified();
  const before = await f.json(`select to_jsonb(d) from public.chart_documents d where id=${lit(chartC)};`);
  for (const batch of batches) await f.finalize(batch);
  const result = await f.json(`select jsonb_build_object('old_head',exists(select 1 from public.chart_snapshots where id=${lit(id(1))}),
    'legacy_fallback',exists(select 1 from public.chart_snapshots where id=${lit(id(105))}),
    'head',(select latest_snapshot_id from public.chart_documents where id=${lit(chartA)}));`);
  assert.equal(result.old_head, true); assert.equal(result.legacy_fallback, true); assert.equal(result.head, id(1));
  assert.deepEqual(await f.json(`select to_jsonb(d) from public.chart_documents d where id=${lit(chartC)};`), before);
}));

test('invalid archive evidence cannot authorize deletion', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure();
  const batch = await f.plan(); await f.archiveAndRestore(batch);
  for (const overrides of [{ archiveSHA: 'not-a-digest' }, { archiveBytes: 0 },
    { manifestSHA: '0'.repeat(64) }, { rowCount: batch.row_count - 1 }]) {
    await assert.rejects(f.finalize(batch, overrides));
  }
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 40);
  assert.ok((await f.status()).initial_remaining_rows > 0);
}));

test('payload backup-status-only and metadata changes invalidate planned receipt bytes', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure();
  const batch = await f.plan(); await f.archiveAndRestore(batch);
  await f.sql(`update public.chart_snapshots set chart_json=jsonb_set(chart_json,
    '{cloudBackupStatus,intent}','"excluded"'::jsonb) where id=${lit(id(1))};
    update public.chart_snapshots set client_updated_at=client_updated_at+interval '1 microsecond'
    where id=${lit(id(2))};`);
  const result = await f.finalize(batch);
  assert.equal(result.status, 'verified_waiting_initial_restore');
  await assert.rejects(f.markInitialVerified(), /Never bypass initial/);
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 40);
  assert.ok((await f.status()).initial_remaining_rows >= 2);
}));

test('UTC daily checkpoints and every24h row survive outside newest10', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0, 50);
  const utcBoundary = "((date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC')-interval '2 days')";
  await f.sql(`update public.chart_snapshots set created_at=${utcBoundary}-interval '1 second' where id=${lit(id(1))};
    update public.chart_snapshots set created_at=${utcBoundary}+interval '1 second' where id=${lit(id(2))};
    update public.chart_snapshots set created_at=${utcBoundary}-interval '2 seconds' where id=${lit(id(3))};
    update public.chart_snapshots set created_at=clock_timestamp()-interval '2 hours' where id=${lit(id(4))};
    update public.chart_snapshots set created_at=clock_timestamp()-interval '1 hour' where id=${lit(id(5))};`);
  await f.configure();
  const batch = await f.plan(100, 'America/Los_Angeles');
  await f.archiveAndRestore(batch); await f.finalize(batch, { timezone: 'America/Los_Angeles' });
  await f.markInitialVerified(batch.manifest_sha256);
  await f.finalize(batch, { timezone: 'America/Los_Angeles' });
  const result = await f.json(`select jsonb_build_object('ids',array_agg(id::text order by id))
    from public.chart_snapshots where id in (${[1, 2, 3, 4, 5].map(n => lit(id(n))).join(',')});`);
  assert.deepEqual(result.ids, [1, 2, 4, 5].map(id));
}));

test('a just-retired head remains pinned despite old source age', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure();
  await f.sql(`update public.chart_documents set latest_snapshot_id=${lit(id(1))} where id=${lit(chartA)};
    update public.chart_documents set latest_snapshot_id=${lit(id(40))} where id=${lit(chartA)};`);
  const batch = await f.bootstrap(); await f.finalize(batch);
  const result = await f.json(`select jsonb_build_object('retired_exists',exists(select 1 from public.chart_snapshots where id=${lit(id(1))}),
    'ordinary_old_exists',exists(select 1 from public.chart_snapshots where id=${lit(id(2))}));`);
  assert.equal(result.retired_exists, true); assert.equal(result.ordinary_old_exists, false);
}));

test('verified archive replay reuses exact bytes and never deletes twice', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure();
  const batch = await f.bootstrap();
  await assert.rejects(f.finalize(batch, { archiveSHA: '0'.repeat(64) }), /immutable|mismatch/i);
  const first = await f.finalize(batch);
  assert.ok(first.deleted_count > 0);
  const second = await f.finalize(batch);
  assert.equal(second.deleted_count, 0);
  // A formerly protected archived row becomes eligible after10 newer versions.
  await f.sql(`update ichart_snapshot_retention.head_pins set retain_until=clock_timestamp()-interval '1 second';
    insert into public.chart_snapshots(id,chart_id,owner_id,version,chart_json,created_at)
    select fixture.id(1000+n),${lit(chartA)},${lit(ownerA)},1000+n,
      jsonb_build_object('id',${lit(chartA)},'title','New unarchived history'),
      (date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC')-interval '4 days'+interval '20 hours'+n*interval '1 second'
    from generate_series(1,20)n;
    update public.chart_documents set latest_snapshot_id=fixture.id(1020) where id=${lit(chartA)};
    update ichart_snapshot_retention.head_pins set retain_until=clock_timestamp()-interval '1 second';`);
  const reused = await f.plan();
  assert.equal(reused.status, 'verified');
  assert.equal(reused.batch_id, batch.batch_id);
  assert.ok(reused.rows.every(row => row.row_text === null));
  await f.archiveAndRestore(reused);
  const result = await f.finalize(reused);
  assert.ok(result.deleted_count > 0);
  const unarchived = await f.json(`select jsonb_build_object('n',count(*)) from public.chart_snapshots where version>=1000;`);
  assert.equal(unarchived.n, 20, 'Existing receipt cannot authorize any newly created history.');
}));

test('a foreign-owner head committed during finalize lock wait is preserved', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.seed(ownerB, chartB, 100); await f.configure();
  const batch = await f.bootstrap();
  const linker = f.session('retention_cross_owner_linker');
  await linker.pid();
  await linker.sql(`begin;update public.chart_documents set latest_snapshot_id=${lit(id(1))} where id=${lit(chartB)};`);
  const finalizer = f.session('retention_cross_owner_finalizer');
  const pid = await finalizer.pid();
  const running = finalizer.sql(`set role service_role;${f.finalizeSQL(batch)}`, 20_000);
  await f.waitBlocked(pid);
  await linker.sql('commit;');
  const result = parseJSON(await running);
  assert.equal(result.status, 'pruned');
  const state = await f.json(`select jsonb_build_object('head',(select latest_snapshot_id from public.chart_documents where id=${lit(chartB)}),
    'target_exists',exists(select 1 from public.chart_snapshots where id=${lit(id(1))}),
    'foreign_snapshot_count',(select count(*) from public.chart_snapshots where owner_id=${lit(ownerB)}));`);
  assert.equal(state.head, id(1)); assert.equal(state.target_exists, true); assert.equal(state.foreign_snapshot_count, 40);
}));

test('target parent locking blocks its insert while another owner remains writable', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.seed(ownerB, chartB, 100); await f.configure();
  const batch = await f.bootstrap();
  const blocker = f.session('retention_target_snapshot_blocker'); await blocker.pid();
  await blocker.sql(`begin;select id from public.chart_snapshots where id=${lit(id(1))} for update;`);
  const finalizer = f.session('retention_target_finalizer'); const finalizePID = await finalizer.pid();
  const pruning = finalizer.sql(`set role service_role;${f.finalizeSQL(batch)}`, 20_000);
  await f.waitBlocked(finalizePID);
  const writer = f.session('retention_target_writer'); const writerPID = await writer.pid();
  const writing = writer.sql(`insert into public.chart_snapshots(id,chart_id,owner_id,version,chart_json)
    values(${lit(id(999))},${lit(chartA)},${lit(ownerA)},999,'{}');`, 20_000);
  await f.waitBlocked(writerPID);
  await f.sql(`set lock_timeout='1s';insert into public.chart_snapshots(id,chart_id,owner_id,version,chart_json)
    values(${lit(id(1999))},${lit(chartB)},${lit(ownerB)},999,'{}');`);
  await blocker.sql('commit;');
  assert.equal(parseJSON(await pruning).status, 'pruned'); await writing;
  const result = await f.json(`select jsonb_build_object('target_new',exists(select 1 from public.chart_snapshots where id=${lit(id(999))}),
    'foreign_new',exists(select 1 from public.chart_snapshots where id=${lit(id(1999))}));`);
  assert.equal(result.target_new, true); assert.equal(result.foreign_new, true);
}));

test('a payload change committed during snapshot-lock wait cannot use the old receipt', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure(); const batch = await f.bootstrap();
  const changer = f.session('retention_payload_changer'); await changer.pid();
  await changer.sql(`begin;update public.chart_snapshots set chart_json=jsonb_set(chart_json,
    '{cloudBackupStatus,intent}','"excluded"'::jsonb) where id=${lit(id(1))};`);
  const finalizer = f.session('retention_payload_finalizer'); const pid = await finalizer.pid();
  const running = finalizer.sql(`set role service_role;${f.finalizeSQL(batch)}`, 20_000);
  await f.waitBlocked(pid); await changer.sql('commit;'); await running;
  const row = await f.json(`select jsonb_build_object('exists',exists(select 1 from public.chart_snapshots where id=${lit(id(1))}),
    'intent',(select chart_json->'cloudBackupStatus'->>'intent' from public.chart_snapshots where id=${lit(id(1))}));`);
  assert.equal(row.exists, true); assert.equal(row.intent, 'excluded');
}));

test('a disappeared unarchived initial row keeps the global restore gate closed', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure();
  await f.sql(`delete from public.chart_snapshots where id=${lit(id(1))};`);
  const batch = await f.plan();
  assert.equal(batch.row_count, 39);
  await f.archiveAndRestore(batch); await f.finalize(batch);
  assert.equal((await f.status()).initial_remaining_rows, 1);
  await assert.rejects(f.sql(`update ichart_snapshot_retention.policy
    set initial_restore_verified_at=clock_timestamp(),initial_restore_manifest_sha256=${lit('1'.repeat(64))}
    where singleton;`), /incomplete|changed|initial/i);
  await assert.rejects(f.plan(), /initial|missing|disappeared/i);
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 39);
}));

test('privileged delete/reinsert of identical snapshot ID invalidates the old receipt', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure(); const batch = await f.bootstrap();
  const archived = batch.rows.find(row => row.snapshot_id === id(1));
  assert.ok(archived);
  await f.sql(`delete from public.chart_snapshots where id=${lit(id(1))};
    insert into public.chart_snapshots select (jsonb_populate_record(null::public.chart_snapshots,
      ${lit(archived.row_text)}::jsonb)).*;`);
  await f.finalize(batch);
  const state = await f.json(`select jsonb_build_object('exists',exists(select 1 from public.chart_snapshots where id=${lit(id(1))}),
    'invalidated',(select invalidated_at is not null from ichart_snapshot_retention.archive_items
      where batch_id=${lit(batch.batch_id)} and snapshot_id=${lit(id(1))}));`);
  assert.equal(state.exists, true); assert.equal(state.invalidated, true);
  const replacement = await f.plan();
  assert.equal(replacement.status, 'planned');
  assert.notEqual(replacement.batch_id, batch.batch_id);
  assert.deepEqual(replacement.rows.map(row => row.snapshot_id), [id(1)]);
  await f.archiveAndRestore(replacement); const result = await f.finalize(replacement);
  assert.equal(result.deleted_count, 1);
}));

test('archive planning obeys bounded bytes/rows and rejects an expired lease', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure();
  await f.sql('update ichart_snapshot_retention.policy set max_batch_rows=3,max_batch_bytes=1024 where singleton;');
  const batch = await f.plan();
  assert.ok(batch.row_count > 0 && batch.row_count <= 3);
  assert.ok(batch.uncompressed_bytes <= 1024);
  assert.equal((await f.plan()).status, 'busy');
  await f.archiveAndRestore(batch);
  await f.sql(`update ichart_snapshot_retention.archive_batches set lease_expires_at=clock_timestamp()-interval '1 second'
    where id=${lit(batch.batch_id)};`);
  await assert.rejects(f.finalize(batch), /expired/i);
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 40);
  const replacement = await f.plan();
  assert.equal(replacement.status, 'planned');
  assert.notEqual(replacement.batch_id, batch.batch_id);
  await f.archiveAndRestore(replacement);
}));

test('oversized first row and archive-item tampering fail closed', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure();
  await f.sql(`update ichart_snapshot_retention.policy set max_batch_bytes=1024 where singleton;
    update public.chart_snapshots set chart_json=chart_json||jsonb_build_object('synthetic_large_field',repeat('x',5000))
    where id=${lit(id(1))};`);
  await assert.rejects(f.plan(), /byte budget/i);
  await f.sql('update ichart_snapshot_retention.policy set max_batch_bytes=4194304 where singleton;');
  const batch = await f.plan(); await f.archiveAndRestore(batch);
  await f.sql(`update ichart_snapshot_retention.archive_items set row_sha256=${lit('0'.repeat(64))}
    where batch_id=${lit(batch.batch_id)} and snapshot_id=${lit(id(1))};`);
  await assert.rejects(f.finalize(batch), /manifest.*inconsistent/i);
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 40);
}));

test('wrong-owner helpers and snapshot schema drift are rejected', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.seed(ownerB, chartB, 100); await f.configure();
  await assert.rejects(f.sql(`set role service_role;select ichart_snapshot_retention.row_text(s)
    from public.chart_snapshots s where owner_id=${lit(ownerB)} limit 1;`), /confined.*owner/i);
  await assert.rejects(f.sql(`set role service_role;select * from ichart_snapshot_retention.keeper_ids(${lit(ownerB)},clock_timestamp());`), /confined.*owner/i);
  await f.sql('alter table public.chart_snapshots add column synthetic_unreviewed_column text;');
  await assert.rejects(f.plan(), /schema changed/i);
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 80);
}));

test('initial restore proof cannot be preseeded or later rewritten', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0);
  await assert.rejects(f.configure({ initialVerified: true }), /cannot be preseeded/i);
  assert.equal((await f.status()).status, 'unconfigured');
  await f.configure(); await f.bootstrap();
  await assert.rejects(f.sql(`update ichart_snapshot_retention.policy
    set initial_restore_manifest_sha256=${lit('0'.repeat(64))} where singleton;`), /immutable/i);
  await assert.rejects(f.sql('update ichart_snapshot_retention.policy set initial_restore_verified_at=null,initial_restore_manifest_sha256=null where singleton;'), /immutable/i);
  await f.sql('update ichart_snapshot_retention.policy set enabled=false where singleton;');
  assert.equal((await f.plan()).status, 'disabled');
}));

test('full hash validation closes a missed trigger-invalidation planning race', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure(); const batch = await f.plan();
  await f.archiveAndRestore(batch);
  // Model a source UPDATE that happened after planner's candidate read but
  // before it inserted archive_items: that UPDATE had no item to invalidate.
  // Clearing this synthetic marker recreates that possible ordering exactly.
  await f.sql(`update public.chart_snapshots set chart_json=chart_json||'{"synthetic_race":true}'::jsonb
    where id=${lit(id(1))};
    update ichart_snapshot_retention.archive_items set invalidated_at=null
    where batch_id=${lit(batch.batch_id)} and snapshot_id=${lit(id(1))};`);
  const result = await f.finalize(batch);
  assert.equal(result.status, 'verified_waiting_initial_restore');
  assert.equal((await f.status()).initial_remaining_rows, 1);
  const state = await f.json(`select jsonb_build_object('invalidated',(select invalidated_at is not null
    from ichart_snapshot_retention.archive_items where batch_id=${lit(batch.batch_id)} and snapshot_id=${lit(id(1))}),
    'count',(select count(*) from public.chart_snapshots));`);
  assert.equal(state.invalidated, true); assert.equal(state.count, 40);
  await assert.rejects(f.sql(`update ichart_snapshot_retention.policy set initial_restore_verified_at=clock_timestamp(),
    initial_restore_manifest_sha256=${lit(batch.manifest_sha256)} where singleton;`), /incomplete|changed/i);
}));

test('late suspended head link fails safely after pruning without nulling the current document', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure(); const batch = await f.bootstrap();
  const documentBefore = await f.json(`select to_jsonb(d) from public.chart_documents d where id=${lit(chartA)};`);
  const blocker = f.session('retention_late_link_blocker'); await blocker.pid();
  await blocker.sql(`begin;select id from public.chart_snapshots where id=${lit(id(1))} for update;`);
  const finalizer = f.session('retention_late_link_finalizer'); const finalizePID = await finalizer.pid();
  const pruning = finalizer.sql(`set role service_role;${f.finalizeSQL(batch)}`, 20_000);
  await f.waitBlocked(finalizePID);
  const linker = f.session('retention_late_head_linker'); const linkerPID = await linker.pid();
  const linking = linker.sql(`update public.chart_documents set latest_snapshot_id=${lit(id(1))}
    where id=${lit(chartA)};`, 20_000).then(output => ({ ok: true, output }), error => ({ ok: false, error }));
  await f.waitBlocked(linkerPID);
  await blocker.sql('commit;');
  assert.equal(parseJSON(await pruning).status, 'pruned');
  const linkResult = await linking;
  assert.equal(linkResult.ok, false, 'A suspended old write must not silently clear the current pointer.');
  assert.match(linkResult.error.message, /foreign key|row-level security/i);
  assert.deepEqual(await f.json(`select to_jsonb(d) from public.chart_documents d where id=${lit(chartA)};`), documentBefore);
  assert.equal((await f.json(`select jsonb_build_object('exists',exists(select 1 from public.chart_snapshots where id=${lit(id(1))}));`)).exists, false);
}));

test('defense in depth: synthetic privileged owner/receipt mutation cannot widen locked deletion IDs', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.seed(ownerB, chartB, 100); await f.configure();
  const batch = await f.bootstrap();
  // This deliberately privileged fixture is NOT a normal application path.
  // Ordinary owner flips already invalidate receipts. Resetting that marker
  // isolates the independent invariant: every deletion must be a locked ID.
  await f.sql(`update public.chart_snapshots set owner_id=${lit(ownerB)} where id=${lit(id(1))};
    update ichart_snapshot_retention.archive_items set invalidated_at=null where batch_id=${lit(batch.batch_id)} and snapshot_id=${lit(id(1))};`);
  const blocker = f.session('retention_locked_subset_blocker'); await blocker.pid();
  await blocker.sql(`begin;select id from public.chart_snapshots where id=${lit(id(2))} for update;`);
  const finalizer = f.session('retention_locked_subset_finalizer'); const pid = await finalizer.pid();
  const running = finalizer.sql(`set role service_role;${f.finalizeSQL(batch)}`, 20_000);
  await f.waitBlocked(pid);
  await f.sql(`set lock_timeout='1s';update public.chart_snapshots set owner_id=${lit(ownerA)} where id=${lit(id(1))};
    update ichart_snapshot_retention.archive_items set invalidated_at=null where batch_id=${lit(batch.batch_id)} and snapshot_id=${lit(id(1))};`);
  await blocker.sql('commit;'); await running;
  const state = await f.json(`select jsonb_build_object('unlocked_row_exists',exists(select 1 from public.chart_snapshots where id=${lit(id(1))}),
    'foreign_count',(select count(*) from public.chart_snapshots where owner_id=${lit(ownerB)}));`);
  assert.equal(state.unlocked_row_exists, true); assert.equal(state.foreign_count, 40);
}));

test('archive-bucket restrictive RLS defeats broad client grants without changing another bucket', t => fixture(t, async f => {
  await f.sql(`insert into storage.objects(bucket_id,name) values
    ('ichart-owner-snapshot-archives','synthetic-archive.jsonl.gz'),('fixture-other-bucket','other-object');`);
  for (const role of ['anon', 'authenticated']) {
    const visible = await f.json(`set role ${role};select coalesce(jsonb_agg(bucket_id order by bucket_id),'[]'::jsonb) from storage.objects;`);
    assert.deepEqual(visible, ['fixture-other-bucket']);
    await assert.rejects(f.sql(`set role ${role};insert into storage.objects(bucket_id,name)
      values('ichart-owner-snapshot-archives','forbidden-${role}');`), /row-level security/i);
    await f.sql(`set role ${role};update storage.objects set metadata='{"permitted":true}'::jsonb where bucket_id='fixture-other-bucket';
      update storage.objects set name='forbidden-change' where bucket_id='ichart-owner-snapshot-archives';
      delete from storage.objects where bucket_id='ichart-owner-snapshot-archives';`);
  }
  const result = await f.json(`select jsonb_build_object('archive_name',(select name from storage.objects where bucket_id='ichart-owner-snapshot-archives'),
    'other_metadata',(select metadata from storage.objects where bucket_id='fixture-other-bucket'));`);
  assert.equal(result.archive_name, 'synthetic-archive.jsonl.gz');
  assert.deepEqual(result.other_metadata, { permitted: true });
}));

test('current head payload stays share-locked throughout a blocked prune', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure(); const batch = await f.bootstrap();
  const blocker = f.session('retention_head_share_blocker'); await blocker.pid();
  await blocker.sql(`begin;select id from public.chart_snapshots where id=${lit(id(1))} for update;`);
  const finalizer = f.session('retention_head_share_finalizer'); const finalizePID = await finalizer.pid();
  const pruning = finalizer.sql(`set role service_role;${f.finalizeSQL(batch)}`, 20_000);
  await f.waitBlocked(finalizePID);
  const writer = f.session('retention_head_payload_writer'); const writerPID = await writer.pid();
  const writing = writer.sql(`update public.chart_snapshots set chart_json=chart_json||'{"synthetic_after_prune":true}'::jsonb
    where id=${lit(id(40))};`, 20_000);
  await f.waitBlocked(writerPID);
  await blocker.sql('commit;');
  assert.equal(parseJSON(await pruning).status, 'pruned'); await writing;
  const result = await f.json(`select jsonb_build_object('head',(select latest_snapshot_id from public.chart_documents where id=${lit(chartA)}),
    'resumed_change',(select chart_json->>'synthetic_after_prune' from public.chart_snapshots where id=${lit(id(40))}));`);
  assert.equal(result.head, id(40)); assert.equal(result.resumed_change, 'true');
}));

test('synthetic unexpected head payload mutation makes prune roll back completely', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure(); const batch = await f.bootstrap();
  const before = await f.json("select jsonb_agg(to_jsonb(s) order by id) from public.chart_snapshots s;");
  // Controlled fault injection validates the mandatory before/after full-row
  // hash invariant. It is not an existing production trigger or client defect.
  await f.sql(`create function fixture.mutate_head_during_delete() returns trigger language plpgsql as $$begin
    if old.id=${lit(id(1))}::uuid then
      update public.chart_snapshots set chart_json=chart_json||'{"synthetic_unexpected_mutation":true}'::jsonb
       where id=${lit(id(40))};
    end if;return old;end;$$;
    create trigger fixture_unexpected_head_mutation after delete on public.chart_snapshots
      for each row execute function fixture.mutate_head_during_delete();`);
  await assert.rejects(f.finalize(batch), /head|fallback|protected|rolling back/i);
  assert.deepEqual(await f.json("select jsonb_agg(to_jsonb(s) order by id) from public.chart_snapshots s;"), before);
  assert.equal((await f.json(`select jsonb_build_object('head',latest_snapshot_id) from public.chart_documents where id=${lit(chartA)};`)).head, id(40));
}));

test('archive deletion scope is service-only definer with independent role gate and NULL22004', t => fixture(t, async f => {
  const acl = await f.json(`select jsonb_build_object('service',has_function_privilege('service_role',
    'public.owner_snapshot_archive_deletion_scope(uuid)','EXECUTE'),
    'anon',has_function_privilege('anon','public.owner_snapshot_archive_deletion_scope(uuid)','EXECUTE'),
    'authenticated',has_function_privilege('authenticated','public.owner_snapshot_archive_deletion_scope(uuid)','EXECUTE'),
    'definer',prosecdef,'settings',proconfig) from pg_proc
    where oid='public.owner_snapshot_archive_deletion_scope(uuid)'::regprocedure;`);
  assert.equal(acl.service, true); assert.equal(acl.anon, false); assert.equal(acl.authenticated, false);
  assert.equal(acl.definer, true); assert.ok(acl.settings.includes('search_path=pg_catalog'));
  for (const role of ['anon', 'authenticated']) {
    await assert.rejects(f.sql(`set role ${role};select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)});`), /permission denied/i);
  }
  await assert.rejects(f.sql('\\set VERBOSITY verbose\nset role service_role;select public.owner_snapshot_archive_deletion_scope(null);'),
    /22004.*Verified owner is required|Verified owner is required[\s\S]*22004/i);
  // Defense against a future accidental EXECUTE grant: editable JWT metadata
  // is not authority to impersonate the protected Postgres service role.
  await f.sql('grant execute on function public.owner_snapshot_archive_deletion_scope(uuid) to authenticated;');
  await assert.rejects(f.sql(`set role authenticated;select set_config('request.jwt.claims','{"role":"service_role"}',false);
    select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)});`), /Service role required/i);
}));

test('archive deletion scope returns no-op for unconfigured and different owner without data-table reads', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.seed(ownerB, chartB, 100);
  const before = await f.json('select jsonb_agg(to_jsonb(s) order by id) from public.chart_snapshots s;');
  await f.sql(`revoke select on public.chart_snapshots,public.chart_documents,storage.objects,
    ichart_snapshot_retention.initial_inventory,ichart_snapshot_retention.archive_batches,
    ichart_snapshot_retention.archive_items from service_role;`);
  assert.deepEqual(await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)})`), { applies: false });
  await f.configure({ enabled: false });
  const policyBefore = await f.json('select to_jsonb(p) from ichart_snapshot_retention.policy p;');
  assert.deepEqual(await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerB)})`), { applies: false });
  assert.deepEqual(await f.json('select to_jsonb(p) from ichart_snapshot_retention.policy p;'), policyBefore);
  assert.deepEqual(await f.json('select jsonb_agg(to_jsonb(s) order by id) from public.chart_snapshots s;'), before);
}));

test('disabled configured owner fences its exact archive prefix without reading locked source tables', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure({ enabled: false });
  await f.sql(`revoke select on public.chart_snapshots,public.chart_documents,storage.objects,
    ichart_snapshot_retention.initial_inventory,ichart_snapshot_retention.archive_batches,
    ichart_snapshot_retention.archive_items from service_role;`);
  const blocker = f.session('retention_scope_source_blocker'); await blocker.pid();
  await blocker.sql(`begin;lock table public.chart_documents,public.chart_snapshots,
    ichart_snapshot_retention.initial_inventory,ichart_snapshot_retention.archive_items,storage.objects
    in access exclusive mode;`);
  assert.deepEqual(await f.service(`set lock_timeout='500ms';select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)})`), {
    applies: true, ready: true, owner_id: ownerA, bucket: 'ichart-owner-snapshot-archives', prefix: ownerA + '/'
  });
  assert.deepEqual(await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerB)})`), { applies: false });
  await blocker.sql('commit;');
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 40);
}));

test('deletion fence blocks new plans and waits for an active archive to acknowledge without pruning', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.seed(ownerB, chartB, 100); await f.configure();
  const before = await f.json('select jsonb_agg(to_jsonb(s) order by id) from public.chart_snapshots s;');
  const batch = await f.plan(); await f.archiveAndRestore(batch);
  const scope = await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)})`);
  assert.equal(scope.applies, true); assert.equal(scope.ready, false);
  const state = await f.json('select to_jsonb(p) from ichart_snapshot_retention.policy p;');
  assert.equal(state.enabled, false); assert.ok(state.deletion_requested_at);
  assert.equal((await f.plan()).status, 'disabled');
  assert.deepEqual(await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerB)})`), { applies: false });
  assert.deepEqual(await f.json('select to_jsonb(p) from ichart_snapshot_retention.policy p;'), state);
  const finalized = await f.finalize(batch);
  assert.equal(finalized.status, 'verified_waiting_account_deletion');
  assert.equal(finalized.deleted_count, 0);
  assert.equal((await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)})`)).ready, true);
  assert.deepEqual(await f.json('select jsonb_agg(to_jsonb(s) order by id) from public.chart_snapshots s;'), before);
  await assert.rejects(f.sql('update ichart_snapshot_retention.policy set enabled=true where singleton;'), /check constraint/i);
}));

test('ordinary disabled policy rejects finalization but deletion fence permits receipt-only acknowledgment', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure(); const batch = await f.plan(); await f.archiveAndRestore(batch);
  await f.sql('update ichart_snapshot_retention.policy set enabled=false where singleton;');
  await assert.rejects(f.finalize(batch), /disabled/i);
  assert.equal((await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)})`)).ready, false);
  assert.equal((await f.finalize(batch)).status, 'verified_waiting_account_deletion');
  assert.equal((await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)})`)).ready, true);
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 40);
}));

test('expired lease does not block deletion readiness and cannot later authorize finalization', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure(); const batch = await f.plan(); await f.archiveAndRestore(batch);
  await f.sql(`update ichart_snapshot_retention.archive_batches set lease_expires_at=clock_timestamp()-interval '1 second'
    where id=${lit(batch.batch_id)};`);
  assert.equal((await f.service(`select public.owner_snapshot_archive_deletion_scope(${lit(ownerA)})`)).ready, true);
  await assert.rejects(f.finalize(batch), /expired/i);
  assert.equal((await f.plan()).status, 'disabled');
  assert.equal((await f.json("select jsonb_build_object('n',count(*)) from public.chart_snapshots;")).n, 40);
}));

test('backdated row inserted after inventory capture is not falsely counted as initial history', t => fixture(t, async f => {
  await f.seed(ownerA, chartA, 0); await f.configure();
  await f.sql(`insert into public.chart_snapshots(id,chart_id,owner_id,version,chart_json,created_at)
    values(${lit(id(999))},${lit(chartA)},${lit(ownerA)},999,'{}',clock_timestamp()-interval '10 days');`);
  const batch = await f.plan();
  assert.equal(batch.mode, 'initial'); assert.equal(batch.row_count, 40);
  assert.ok(!batch.rows.some(row => row.snapshot_id === id(999)));
  await f.archiveAndRestore(batch); await f.finalize(batch);
  assert.equal((await f.status()).initial_remaining_rows, 0);
  await f.markInitialVerified(batch.manifest_sha256); await f.finalize(batch);
  assert.equal((await f.json(`select jsonb_build_object('exists',exists(select 1 from public.chart_snapshots where id=${lit(id(999))}));`)).exists, true);
}));
