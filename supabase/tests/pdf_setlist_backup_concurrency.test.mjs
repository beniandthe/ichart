import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import test from "node:test";

const databaseURL = process.env.ICHART_LOCAL_SETLIST_DATABASE_URL;
const owner = "e0360000-0000-4000-8000-000000000901";
const session = `set role authenticated; set request.jwt.claim.sub = '${owner}';`;
const empty = { schema_version: 1, setlists: [], pdfs: [] };

function localDatabase() {
  const url = new URL(databaseURL);
  const host = url.searchParams.get("host") ?? url.hostname;
  assert.ok(host === "127.0.0.1" || host === "localhost" || host.startsWith("/private/tmp/"),
    "The SQL concurrency fixture accepts only a local database");
  assert.match(url.pathname, /^\/ichart_(?:fix036|setlist_)/,
    "Use a disposable FIX-036 database, not the running app database");
}

function query(statement) {
  return new Promise((resolve, reject) => {
    const child = spawn("psql", ["-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1",
      "-v", "VERBOSITY=sqlstate", databaseURL, "-c", statement]);
    let output = "";
    let error = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { error += chunk; });
    child.on("error", reject);
    child.on("close", (status) => resolve({ status, output: output.trim(), error }));
  });
}

async function success(statement) {
  const result = await query(statement);
  assert.equal(result.status, 0, result.error);
  return result.output;
}

const serialized = (value) => `'${JSON.stringify(value)}'::jsonb`;

test("competing owner commits preserve exactly one CAS winner and reject a deletion-fenced retry", {
  skip: !databaseURL && "Set ICHART_LOCAL_SETLIST_DATABASE_URL to an isolated local database",
}, async () => {
  localDatabase();
  await success(`insert into auth.users(id,email_confirmed_at) values('${owner}',now());
    insert into public.subscriptions(owner_id,provider,plan,status,app_store_status,entitlement_expires_at,last_verified_at)
      values('${owner}','storekit','studioSubscription','active','active',now()+interval '1 day',now())
      on conflict(owner_id) do update set provider=excluded.provider, plan=excluded.plan, status=excluded.status,
        app_store_status=excluded.app_store_status, entitlement_expires_at=excluded.entitlement_expires_at,
        last_verified_at=excluded.last_verified_at;`);
  try {
    await success(`${session} select public.commit_pdf_setlist_backup('${owner}',0,${serialized(empty)});`);
    const workers = await Promise.all(["first", "second"].map((writer) => query(`begin; ${session}
      select public.commit_pdf_setlist_backup('${owner}',1,${serialized({ ...empty, writer })});
      select pg_sleep(0.15); commit;`)));
    assert.equal(workers.filter((result) => result.status === 0).length, 1);
    const rejected = workers.find((result) => result.status !== 0);
    assert.match(rejected.error, /40001/, "The stale writer must receive a conflict, not replace the winner");
    const current = JSON.parse(await success(`${session} select public.get_pdf_setlist_backup('${owner}');`));
    assert.equal(current.version, 2);
    assert.ok(["first", "second"].includes(current.manifest.writer));
    await success(`set role service_role; select public.begin_pdf_setlist_account_deletion('${owner}');`);
    const fenced = await query(`${session} select public.commit_pdf_setlist_backup('${owner}',2,${serialized(empty)});`);
    assert.notEqual(fenced.status, 0);
    assert.match(fenced.error, /42501/);
    assert.equal(await success(`select version from private.pdf_setlist_backups where owner_id='${owner}';`), "2");
  } finally {
    await success(`delete from public.subscriptions where owner_id='${owner}'; delete from auth.users where id='${owner}';`);
  }
});

async function waitForAdvisoryLock(applicationName, mode, granted) {
  const deadline = Date.now() + 5000;
  do {
    const visible = await success(`select exists(select 1 from pg_locks locks
      join pg_stat_activity activity on activity.pid=locks.pid
      where activity.application_name='${applicationName}' and locks.locktype='advisory'
        and locks.mode='${mode}' and locks.granted=${granted});`);
    if (visible === "t") return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  } while (Date.now() < deadline);
  assert.fail(`Expected ${applicationName} ${mode} granted=${granted}`);
}

for (const fenceFirst of [false, true]) {
  test(fenceFirst ? "an upload waiting for account deletion rechecks the committed fence"
    : "account deletion waits for an authorized upload before inventory", {
    skip: !databaseURL && "Set ICHART_LOCAL_SETLIST_DATABASE_URL to an isolated local database",
  }, async () => {
    localDatabase();
    const ownerID = fenceFirst ? "e0360000-0000-4000-8000-000000000903"
      : "e0360000-0000-4000-8000-000000000902";
    const suffix = fenceFirst ? "after-fence" : "before-fence";
    const uploadName = `ichart-setlist-upload-${suffix}`;
    const fenceName = `ichart-setlist-fence-${suffix}`;
    const objectPath = `${ownerID}/${"a".repeat(64)}.pdf`;
    const upload = `set application_name='${uploadName}'; begin; set role authenticated;
      set request.jwt.claim.sub='${ownerID}';
      insert into storage.objects(bucket_id,name,metadata)
        values('setlist-pdfs','${objectPath}','{"size":12,"mimetype":"application/pdf"}'::jsonb);
      ${fenceFirst ? "" : "select pg_sleep(1);"} commit;`;
    const fence = `set application_name='${fenceName}'; begin; set role service_role;
      select public.begin_pdf_setlist_account_deletion('${ownerID}');
      ${fenceFirst ? "select pg_sleep(1);" : ""} commit;`;
    await success(`insert into auth.users(id,email_confirmed_at) values('${ownerID}',now());
      insert into public.subscriptions(owner_id,provider,plan,status,app_store_status,entitlement_expires_at,last_verified_at)
        values('${ownerID}','storekit','studioSubscription','active','active',now()+interval '1 day',now())
        on conflict(owner_id) do update set provider=excluded.provider, plan=excluded.plan, status=excluded.status,
          app_store_status=excluded.app_store_status, entitlement_expires_at=excluded.entitlement_expires_at,
          last_verified_at=excluded.last_verified_at;`);
    let uploadTask;
    let fenceTask;
    try {
      if (fenceFirst) {
        fenceTask = query(fence);
        await waitForAdvisoryLock(fenceName, "ExclusiveLock", true);
        uploadTask = query(upload);
        await waitForAdvisoryLock(uploadName, "ShareLock", false);
      } else {
        uploadTask = query(upload);
        await waitForAdvisoryLock(uploadName, "ShareLock", true);
        fenceTask = query(fence);
        await waitForAdvisoryLock(fenceName, "ExclusiveLock", false);
      }
      const [uploaded, fenced] = await Promise.all([uploadTask, fenceTask]);
      assert.equal(fenced.status, 0, fenced.error);
      if (fenceFirst) {
        assert.notEqual(uploaded.status, 0, "A waiting upload must not escape the deletion fence");
        assert.match(uploaded.error, /42501/);
      } else {
        assert.equal(uploaded.status, 0, uploaded.error);
      }
      assert.equal(await success(`select count(*) from storage.objects
        where bucket_id='setlist-pdfs' and name='${objectPath}';`), fenceFirst ? "0" : "1");
      const late = await query(upload);
      assert.notEqual(late.status, 0);
      assert.match(late.error, /42501/);
    } finally {
      await Promise.allSettled([uploadTask, fenceTask].filter(Boolean));
      await success(`begin; set local storage.allow_delete_query=true;
        delete from storage.objects where bucket_id='setlist-pdfs' and name='${objectPath}';
        delete from public.subscriptions where owner_id='${ownerID}';
        delete from auth.users where id='${ownerID}'; commit;`);
    }
  });
}
