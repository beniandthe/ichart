// Actual isolated PostgreSQL/RLS regression. External Auth and Storage service
// prerequisites are modeled; existing June/July + both free-beta migrations run
// unchanged. No customer DB, credentials, messages, billing or network is used.
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";

const modulePath = process.env.ICHART_PGLITE_MODULE_PATH;
assert.ok(modulePath && isAbsolute(modulePath), "Set absolute ICHART_PGLITE_MODULE_PATH for pinned PGlite 0.5.8.");
assert.equal(JSON.parse(await readFile(new URL("../package.json", pathToFileURL(modulePath)), "utf8")).version, "0.5.8");
const { PGlite } = await import(pathToFileURL(modulePath).href);
const { pgcrypto } = await import(new URL("./contrib/pgcrypto.js", pathToFileURL(modulePath)).href);
const migrations = new URL("../supabase/migrations/", import.meta.url);
const freeMigration = "20261015203728_free_pro_access.sql";
const betaMigration = "20261015232153_voluntary_free_pro_beta.sql";
const a = "81000000-0000-4000-8000-000000000001";
const b = "81000000-0000-4000-8000-000000000002";
const chart = "82000000-0000-4000-8000-000000000001";
const snapshot = "83000000-0000-4000-8000-000000000001";

async function fixture() {
  const db = await PGlite.create({ extensions: { pgcrypto } });
  await db.exec(`
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
  for (const name of (await readdir(migrations)).filter(name => /^20260[67].*\.sql$/.test(name)).sort()) {
    await db.exec(await readFile(new URL(name,migrations),"utf8"));
  }
  await db.exec(await readFile(new URL(freeMigration,migrations),"utf8"));
  await db.exec(await readFile(new URL(betaMigration,migrations),"utf8"));
  await db.exec(`insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
    values ('${a}','beta-a@example.test',now(),'{"first_name":"Alpha","last_name":"Tester"}'),
      ('${b}','beta-b@example.test',now(),'{"first_name":"Beta","last_name":"Tester"}');
    insert into public.chart_documents(id,owner_id,title,layout_style)
      values ('${chart}','${a}','Keep this chart','simpleChordSheet');
    insert into public.chart_snapshots(id,chart_id,owner_id,version,chart_json)
      values ('${snapshot}','${chart}','${a}',1,'{}');`);
  return db;
}
async function owner(db,id=a) {
  await db.exec("set local role authenticated");
  await db.query("select set_config('request.jwt.claim.sub',$1,true)",[id]);
}
async function scalar(db,query) { return Object.values((await db.query(query)).rows[0])[0]; }
async function status(db) { return scalar(db,"select public.free_pro_beta_status()"); }
async function choose(db,participating,expectedOwner=a) {
  return Object.values((await db.query("select public.set_free_pro_beta_participation($1,$2)",[participating,expectedOwner])).rows[0])[0];
}
async function denied(db,query,code="42501") {
  await db.exec("savepoint expected_denial");
  try { await assert.rejects(db.exec(query),error=>error.code===code); }
  finally { await db.exec("rollback to savepoint expected_denial; release savepoint expected_denial"); }
}

test("voluntary beta participation uses real PostgreSQL account-bound access",async t=>{
  const db=await fixture(); t.after(()=>db.close());
  async function scenario(name,body) {
    await t.test(name,async()=>{await db.exec("begin");try{await body();}finally{await db.exec("rollback");}});
  }
  await scenario("default membership is Pro with exact one-object status and no fabricated consent/billing row",async()=>{
    await owner(db); const result=await status(db);
    assert.deepEqual(result,{owner_id:a,policy_id:"free-pro-2026-10-15",beta_available:true,eligible:true,
      participating:true,free_pro_access:true,notice_id:null,notice_title:null,notice_body:null,beta_ending_at:null});
    assert.equal(await scalar(db,"select plan from public.subscriptions"),"free");
    await db.exec("reset role");
    assert.equal(await scalar(db,"select count(*)::int from private.free_pro_beta_memberships"),0);
  });
  await scenario("leave returns Basic immediately and preserves all chart/snapshot/subscription evidence",async()=>{
    const before=await scalar(db,`select to_jsonb(s) from public.subscriptions s where owner_id='${a}'`);
    await owner(db); const result=await choose(db,false);
    assert.equal(result.owner_id,a); assert.equal(result.participating,false); assert.equal(result.free_pro_access,false);
    assert.equal(await scalar(db,"select public.current_user_has_free_pro_access()"),false);
    assert.equal(await scalar(db,"select public.current_user_has_active_pro()"),false);
    assert.equal(await scalar(db,"select count(*)::int from public.chart_documents"),0);
    await db.exec("reset role");
    assert.equal(await scalar(db,"select count(*)::int from public.chart_documents"),1);
    assert.equal(await scalar(db,"select count(*)::int from public.chart_snapshots"),1);
    assert.deepEqual(await scalar(db,`select to_jsonb(s) from public.subscriptions s where owner_id='${a}'`),before);
  });
  await scenario("rejoin restores same own chart while repeated choices stay idempotent",async()=>{
    await owner(db);
    for(const value of [false,false,true,true,false,true]) assert.equal((await choose(db,value)).participating,value);
    assert.equal((await status(db)).free_pro_access,true);
    assert.equal(await scalar(db,`select count(*)::int from public.chart_documents where id='${chart}'`),1);
    await db.exec("reset role");
    assert.equal(await scalar(db,"select count(*)::int from private.free_pro_beta_memberships"),1);
  });
  for(const lifecycle of ["active","expired","refunded","revoked"]) {
    await scenario(`explicit Basic choice wins over ${lifecycle} Apple billing state without rewriting it`,async()=>{
      await db.exec(`update public.subscriptions set provider='storekit',app_store_status='${lifecycle}',
        plan='studioSubscription',status='active',app_store_auto_renew_status=true,
        entitlement_expires_at=now()+interval '1 year' where owner_id='${a}'`);
      const before=await scalar(db,`select to_jsonb(s) from public.subscriptions s where owner_id='${a}'`);
      await owner(db); assert.equal((await choose(db,false)).free_pro_access,false);
      assert.equal(await scalar(db,"select public.current_user_has_active_pro()"),false);
      assert.equal(await scalar(db,"select count(*)::int from public.chart_snapshots"),0);
      assert.equal((await choose(db,true)).free_pro_access,true);
      await db.exec("reset role");
      assert.deepEqual(await scalar(db,`select to_jsonb(s) from public.subscriptions s where owner_id='${a}'`),before);
    });
  }
  await scenario("account choices cannot leak or overwrite another account",async()=>{
    await owner(db); await choose(db,false);
    await owner(db,b); assert.equal((await status(db)).owner_id,b); assert.equal((await status(db)).participating,true);
    assert.equal(await scalar(db,"select count(*)::int from public.chart_documents"),0);
    await choose(db,false,b); await choose(db,true,b);
    await owner(db); assert.equal((await status(db)).participating,false);
    await denied(db,`select public.set_free_pro_beta_participation(true,'${b}'::uuid)`);
    await denied(db,`select public.set_free_pro_beta_participation(true,'${a}'::uuid,'${b}'::uuid)`,"42883");
    await denied(db,`update private.free_pro_beta_memberships set participating=true where owner_id='${b}'`);
    await denied(db,`insert into private.free_pro_beta_memberships(owner_id,participating) values ('${b}',false)`);
    await denied(db,"select * from private.free_pro_beta_memberships");
  });
  await scenario("null and missing-session choices are rejected without enrollment writes",async()=>{
    await owner(db); await denied(db,`select public.set_free_pro_beta_participation(null,'${a}'::uuid)`,"22004");
    await denied(db,"select public.set_free_pro_beta_participation(true,null::uuid)");
    await denied(db,"select public.set_free_pro_beta_participation(true)","42883");
    await owner(db,""); await denied(db,"select public.free_pro_beta_status()");
    await denied(db,`select public.set_free_pro_beta_participation(false,'${a}'::uuid)`);
    await db.exec("reset role"); assert.equal(await scalar(db,"select count(*)::int from private.free_pro_beta_memberships"),0);
  });
  await scenario("A-intent request executing with B session is rejected before any membership mutation",async()=>{
    await owner(db,a);await choose(db,false,a);await db.exec("reset role");
    const before=await scalar(db,"select jsonb_agg(to_jsonb(m) order by owner_id) from private.free_pro_beta_memberships m");
    await owner(db,b);
    for(const value of [true,false]) {
      await denied(db,`select public.set_free_pro_beta_participation(${value},'${a}'::uuid)`);
    }
    assert.equal((await status(db)).owner_id,b);assert.equal((await status(db)).participating,true);
    await owner(db,a);assert.equal((await status(db)).participating,false);
    await db.exec("reset role");
    assert.deepEqual(await scalar(db,"select jsonb_agg(to_jsonb(m) order by owner_id) from private.free_pro_beta_memberships m"),before);
  });
  await scenario("anon and service roles cannot invoke customer participation RPCs",async()=>{
    for(const role of ["anon","service_role"]) {
      await db.exec(`set local role ${role}`);
      await denied(db,"select public.free_pro_beta_status()");
      await denied(db,`select public.set_free_pro_beta_participation(false,'${a}'::uuid)`);
      await db.exec("reset role");
    }
  });
  for(const [label,mutation] of [["unconfirmed","email_confirmed_at=null"],["anonymous","is_anonymous=true"],
    ["banned","banned_until=now()+interval '1 day'"],["deleted","deleted_at=now()"]]) {
    await scenario(`${label} identity cannot join or leave, and status does not grant access`,async()=>{
      await db.exec(`update auth.users set ${mutation} where id='${a}'`);
      await owner(db); const result=await status(db);
      assert.equal(result.owner_id,a);assert.equal(result.eligible,false);assert.equal(result.free_pro_access,false);
      await denied(db,`select public.set_free_pro_beta_participation(true,'${a}'::uuid)`);
      await denied(db,`select public.set_free_pro_beta_participation(false,'${a}'::uuid)`);
    });
  }
  await scenario("hard account deletion cascades only own membership, stale identity cannot rejoin",async()=>{
    await owner(db);await choose(db,false);await owner(db,b);await choose(db,false,b);
    await db.exec(`reset role;delete from auth.users where id='${a}'`);
    assert.equal(await scalar(db,"select count(*)::int from private.free_pro_beta_memberships"),1);
    await owner(db);await denied(db,"select public.free_pro_beta_status()");
    await denied(db,`select public.set_free_pro_beta_participation(true,'${a}'::uuid)`);
    await owner(db,b);assert.equal((await status(db)).participating,false);
  });
  await scenario("opt-out and refund never resume global retention deletion or access-loss email",async()=>{
    await owner(db);await choose(db,false);await db.exec("reset role");
    await db.exec(`update public.subscriptions set provider='storekit',status='inactive',app_store_status='refunded',
      revoked_at=now(),entitlement_expires_at=now()-interval '1 day',cloud_retention_deadline=now()-interval '1 day'
      where owner_id='${a}';
      insert into private.subscription_retention_events(owner_id,event_type,recipient_email,subject,body,dedupe_key)
      values ('${a}','expiration_warning','beta-a@example.test','must suppress','must suppress','beta-leave')`);
    await db.exec("set local role service_role");
    const result=await scalar(db,"select public.run_subscription_retention_jobs()");
    assert.equal(result.retention_status,"paused_free_access");assert.equal(result.cloud_deleted_events,0);
    assert.equal((await db.query("select * from public.claim_subscription_retention_events()")).rows.length,0);
    await db.exec("reset role");assert.equal(await scalar(db,"select count(*)::int from public.chart_documents"),1);
    assert.equal(await scalar(db,"select count(*)::int from public.chart_snapshots"),1);
    assert.equal(await scalar(db,"select suppressed_at is not null and sent_at is null and dispatch_attempt_count=0 from private.subscription_retention_events"),true);
  });
  await scenario("admin notice is nullable/bounded, setter cannot change it and elapsed date never ends access",async()=>{
    await db.exec(`update private.ichart_free_access_policy set beta_notice_id='synthetic-notice-v1',
      beta_notice_title='Synthetic test notice',beta_notice_body='No charge; future purchase needs explicit opt-in.',
      beta_ending_at=now()-interval '1 day'`);
    await owner(db);const result=await status(db);
    assert.equal(result.notice_id,"synthetic-notice-v1");assert.equal(typeof result.beta_ending_at,"string");
    assert.ok(Number.isFinite(Date.parse(result.beta_ending_at)));assert.equal(result.free_pro_access,true);
    await choose(db,false);const rejoined=await choose(db,true);
    assert.equal(rejoined.notice_body,result.notice_body);assert.equal(rejoined.beta_ending_at,result.beta_ending_at);
    assert.equal(rejoined.free_pro_access,true);
    await denied(db,"update private.ichart_free_access_policy set beta_notice_body='client override'");
    await denied(db,`select public.set_free_pro_beta_participation(true,'${a}'::uuid,'override')`,"42883");
    await db.exec("reset role;set local role service_role");
    await denied(db,"update private.ichart_free_access_policy set beta_notice_body='service override'");
  });
  await scenario("incomplete, oversized or infinite admin notice payload fails validation",async()=>{
    await denied(db,"update private.ichart_free_access_policy set beta_notice_id='incomplete'","23514");
    await denied(db,"update private.ichart_free_access_policy set beta_notice_id='id',beta_notice_title=repeat('a',121),beta_notice_body='body'","23514");
    await denied(db,"update private.ichart_free_access_policy set beta_notice_id='id',beta_notice_title='title',beta_notice_body=repeat('a',2001)","23514");
    await denied(db,"update private.ichart_free_access_policy set beta_notice_id='id',beta_notice_title='title',beta_notice_body='body',beta_ending_at='infinity'","23514");
  });
  await scenario("missing global policy cannot create a rejoin grant or revive retention",async()=>{
    await db.exec("delete from private.ichart_free_access_policy");
    await owner(db);const result=await status(db);
    assert.equal(result.beta_available,false);assert.equal(result.free_pro_access,false);
    await denied(db,`select public.set_free_pro_beta_participation(true,'${a}'::uuid)`,"55000");
    assert.equal((await choose(db,false)).participating,false);
    await db.exec("reset role");await denied(db,"select public.run_subscription_retention_jobs()","P0001");
  });
});
