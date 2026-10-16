// Actual isolated PostgreSQL/RLS regression. External Auth and Storage service
// prerequisites are modeled; existing June/July + free-beta and atomic Forum
// migrations run unchanged. This single-session engine does not verify lock
// ordering across sessions. No customer DB, credentials, messages or billing is used.
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
const atomicForumMigration = "20261016022548_atomic_forum_publication.sql";
const a = "81000000-0000-4000-8000-000000000001";
const b = "81000000-0000-4000-8000-000000000002";
const chart = "82000000-0000-4000-8000-000000000001";
const snapshot = "83000000-0000-4000-8000-000000000001";
const song = "84000000-0000-4000-8000-000000000001";
const post = "85000000-0000-4000-8000-000000000001";
const validSHA256 = "a".repeat(64);

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
  await db.exec(await readFile(new URL(atomicForumMigration,migrations),"utf8"));
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

async function pendingPublication(db) {
  await db.exec(`reset role;
    insert into public.forum_songs(id,song_title,artist_name,normalized_song_title,normalized_artist_name,created_by)
      values ('${song}','Real Song','Artist','real song','artist','${a}');
    insert into public.forum_chart_posts(id,song_id,owner_id,chart_title,arranger_credit,creator_display_name,layout_style,pdf_storage_path)
      values ('${post}','${song}','${a}','Chart','Arranger','Alpha Tester','simpleChordSheet','${a}/${post}.pdf');
    insert into storage.objects(bucket_id,name,owner_id) values ('forum_chart_pdfs','${a}/${post}.pdf','${a}');`);
}
function publishSQL({postID=post,ownerID=a,byteSize="32000",sha256=`'${validSHA256}'`}={}) {
  return `select public.publish_forum_chart_post('${postID}'::uuid,'${ownerID}'::uuid,${byteSize},${sha256})`;
}
async function publicationState(db) {
  await db.exec("reset role");
  return { post:await scalar(db,`select to_jsonb(p) from public.forum_chart_posts p where id='${post}'`),
    provenance:(await db.query("select * from private.forum_chart_pdf_provenance")).rows };
}
async function rejectUnchangedPublication(db,query,code="42501") {
  const before=await publicationState(db);
  await db.exec("set local role service_role");
  await denied(db,query,code);
  assert.deepEqual(await publicationState(db),before,"Rejection must preserve post and provenance together");
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
  await scenario("phone-only confirmation is eligible and supports leave/rejoin without a paid receipt",async()=>{
    await db.exec(`update auth.users set email_confirmed_at=null,phone='+15555550101',phone_confirmed_at=now()
      where id='${a}'`);
    await owner(db);assert.equal((await status(db)).eligible,true);assert.equal((await status(db)).free_pro_access,true);
    assert.equal((await choose(db,false)).free_pro_access,false);
    assert.equal((await choose(db,true)).free_pro_access,true);
    assert.equal(await scalar(db,"select provider from public.subscriptions"),"none");
  });
  await scenario("expired ban no longer denies an otherwise verified account",async()=>{
    await db.exec(`update auth.users set banned_until=now()-interval '1 minute' where id='${a}'`);
    await owner(db);assert.equal((await status(db)).eligible,true);
    assert.equal(await scalar(db,"select public.current_user_has_active_pro()"),true);
    assert.equal((await choose(db,false)).free_pro_access,false);
    assert.equal((await choose(db,true)).free_pro_access,true);
  });
  for(const row of [
    {label:"default Basic billing",paid:false,leave:false,ineligible:false},
    {label:"active paid billing",paid:true,leave:false,ineligible:false},
    {label:"explicit Basic with active paid billing",paid:true,leave:true,ineligible:false},
    {label:"explicit Basic with no paid billing",paid:false,leave:true,ineligible:false},
    {label:"unconfirmed account",paid:true,leave:false,ineligible:true},
  ]) {
    await scenario(`status JSON and both helper decisions agree for ${row.label}`,async()=>{
      if(row.paid) await db.exec(`update public.subscriptions set plan='studioSubscription',status='active',
        provider='storekit',app_store_status='active',entitlement_expires_at=now()+interval '1 year'
        where owner_id='${a}'`);
      if(row.leave) { await owner(db);await choose(db,false);await db.exec("reset role"); }
      if(row.ineligible) await db.exec(`update auth.users set email_confirmed_at=null where id='${a}'`);
      await owner(db);const result=await status(db);
      assert.equal(result.owner_id,a);assert.equal(result.participating,!row.leave);
      assert.equal(result.eligible,!row.ineligible);
      const expected=result.beta_available&&result.eligible&&result.participating;
      assert.equal(result.free_pro_access,expected);
      assert.equal(await scalar(db,"select public.current_user_has_free_pro_access()"),expected);
      assert.equal(await scalar(db,"select public.current_user_has_active_pro()"),expected);
    });
  }
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
  await scenario("service-only atomic publication validates provenance and publishes with default membership and no enrollment",async()=>{
    await pendingPublication(db);
    const beforeBilling=await scalar(db,`select to_jsonb(s) from public.subscriptions s where owner_id='${a}'`);
    await db.exec("set local role service_role");
    const result=await scalar(db,publishSQL({sha256:`'  ${validSHA256.toUpperCase()}  '`}));
    assert.equal(result.id,post);assert.equal(result.owner_id,a);assert.equal(result.status,"published");
    assert.equal(result.pdf_provenance_status,"validated");
    assert.ok(Number.isFinite(Date.parse(result.pdf_validated_at)));
    assert.ok(Number.isFinite(Date.parse(result.published_at)));
    const state=await publicationState(db);
    assert.deepEqual(state.post,result);assert.equal(state.provenance.length,1);
    const provenance=state.provenance[0];
    assert.equal(provenance.post_id,post);assert.equal(provenance.owner_id,a);
    assert.equal(provenance.storage_path,`${a}/${post}.pdf`);
    assert.equal(Number(provenance.byte_size),32000);assert.equal(provenance.sha256,validSHA256);
    assert.equal(provenance.validated_by,"service_role");
    assert.equal(provenance.storage_object_id,await scalar(db,"select id from storage.objects"));
    assert.equal(await scalar(db,"select count(*)::int from private.free_pro_beta_memberships"),0);
    assert.deepEqual(await scalar(db,`select to_jsonb(s) from public.subscriptions s where owner_id='${a}'`),beforeBilling);
  });
  for(const paid of [false,true]) {
    await scenario(`atomic publication rejects opt-out with ${paid?"active paid":"Basic"} billing and keeps provenance pending`,async()=>{
      await pendingPublication(db);
      if(paid) await db.exec(`update public.subscriptions set plan='studioSubscription',status='active',
        provider='storekit',app_store_status='active',entitlement_expires_at=now()+interval '1 year' where owner_id='${a}'`);
      await owner(db);await choose(db,false);
      await rejectUnchangedPublication(db,publishSQL());
    });
  }
  for(const [label,mutation] of [
    ["phone-only confirmed","email_confirmed_at=null,phone_confirmed_at=now()"],
    ["expired ban","banned_until=now()-interval '1 minute'"],
  ]) {
    await scenario(`atomic publication permits eligible ${label} account`,async()=>{
      await pendingPublication(db);await db.exec(`update auth.users set ${mutation} where id='${a}'`);
      await db.exec("set local role service_role");
      assert.equal((await scalar(db,publishSQL())).status,"published");
      assert.equal((await publicationState(db)).provenance.length,1);
    });
  }
  for(const [label,mutation] of [
    ["unconfirmed","email_confirmed_at=null,phone_confirmed_at=null"],
    ["anonymous","is_anonymous=true"],["currently banned","banned_until=now()+interval '1 day'"],
    ["soft-deleted","deleted_at=now()"],
  ]) {
    await scenario(`atomic publication rejects ${label} account with no partial finalization`,async()=>{
      await pendingPublication(db);await db.exec(`update auth.users set ${mutation} where id='${a}'`);
      await rejectUnchangedPublication(db,publishSQL());
    });
  }
  await scenario("atomic publication rejects missing account without creating provenance",async()=>{
    await pendingPublication(db);await db.exec(`delete from auth.users where id='${b}'`);
    await rejectUnchangedPublication(db,publishSQL({ownerID:b}));
  });
  await scenario("atomic publication checks stored owner even when service supplies another eligible owner",async()=>{
    await pendingPublication(db);
    await rejectUnchangedPublication(db,publishSQL({ownerID:b}));
  });
  for(const status of ["removed","hidden"]) {
    await scenario(`atomic publication rejects ${status} status without rewriting post or provenance`,async()=>{
      await pendingPublication(db);await db.exec(`update public.forum_chart_posts set status='${status}' where id='${post}'`);
      await rejectUnchangedPublication(db,publishSQL(),"55000");
    });
  }
  await scenario("atomic publication rejects missing post without finalizing another post",async()=>{
    await pendingPublication(db);
    await rejectUnchangedPublication(db,publishSQL({postID:chart}),"55000");
  });
  for(const status of ["published","flagged"]) {
    await scenario(`atomic publication is idempotent for eligible ${status} post and preserves provenance`,async()=>{
      await pendingPublication(db);await db.exec("set local role service_role");await scalar(db,publishSQL());
      await db.exec(`reset role;update public.forum_chart_posts set status='${status}',published_at='2026-01-01T00:00:00Z'
        where id='${post}';update private.forum_chart_pdf_provenance set validated_at='2026-01-01T00:00:00Z'`);
      const before=await publicationState(db);await db.exec("set local role service_role");
      assert.deepEqual(await scalar(db,publishSQL({byteSize:"17",sha256:"repeat('b',64)"})),before.post);
      assert.deepEqual(await publicationState(db),before);
      await owner(db);await choose(db,false);
      await rejectUnchangedPublication(db,publishSQL());
    });
  }
  for(const [label,options] of [
    ["null size",{byteSize:"null"}],["zero size",{byteSize:"0"}],["negative size",{byteSize:"-1"}],
    ["oversized PDF",{byteSize:"10485761"}],["null checksum",{sha256:"null"}],
    ["short checksum",{sha256:"repeat('a',63)"}],["non-hex checksum",{sha256:"repeat('g',64)"}],
  ]) {
    await scenario(`atomic publication rejects ${label} with no provenance or publication`,async()=>{
      await pendingPublication(db);await rejectUnchangedPublication(db,publishSQL(options),"22023");
    });
  }
  await scenario("canonical stored PDF path is enforced before publication and no provenance is fabricated",async()=>{
    await pendingPublication(db);
    const before=await publicationState(db);
    await denied(db,`update public.forum_chart_posts set pdf_storage_path='${a}/wrong.pdf' where id='${post}'`,"23514");
    assert.deepEqual(await publicationState(db),before);
  });
  for(const mutation of ["delete", "rename", "wrong bucket"]) {
    await scenario(`atomic publication rejects ${mutation} of matching storage object without partial writes`,async()=>{
      await pendingPublication(db);
      if(mutation==="delete") await db.exec("delete from storage.objects");
      if(mutation==="rename") await db.exec(`update storage.objects set name='${a}/wrong.pdf'`);
      if(mutation==="wrong bucket") await db.exec("insert into storage.buckets(id,name) values ('other','other');update storage.objects set bucket_id='other'");
      await rejectUnchangedPublication(db,publishSQL(),"22023");
    });
  }
  await scenario("publication failure after finalization rolls back private provenance and public validation together",async()=>{
    await pendingPublication(db);
    await db.exec(`create function public.synthetic_reject_publication() returns trigger language plpgsql as $$
      begin if new.status='published' then raise exception 'Synthetic publication failure' using errcode='P0001'; end if;
      return new; end; $$;
      create trigger synthetic_reject_publication before update on public.forum_chart_posts
      for each row execute function public.synthetic_reject_publication()`);
    await rejectUnchangedPublication(db,publishSQL(),"P0001");
  });
  for(const role of ["anon","authenticated"]) {
    await scenario(`${role} cannot call either atomic RPC or spoof another publication owner`,async()=>{
      await pendingPublication(db);const before=await publicationState(db);
      for(const schema of ["public","private"]) {
        // Inspect ACL as fixture owner: clients cannot resolve the private
        // signature at all because schema USAGE is also denied.
        assert.equal(await scalar(db,`select has_function_privilege('${role}','${schema}.publish_forum_chart_post(uuid,uuid,bigint,text)','execute')`),false);
      }
      await owner(db);await db.exec(`set local role ${role}`);
      for(const schema of ["public","private"]) {
        for(const claimedOwner of [a,b]) await denied(db,publishSQL({ownerID:claimedOwner}).replace("public.publish_",`${schema}.publish_`));
      }
      await denied(db,`update public.forum_chart_posts set status='published' where id='${post}'`);
      assert.deepEqual(await publicationState(db),before);
    });
  }
  await scenario("serialized participation setter keeps its existing owner guard and restores publication after rejoin",async()=>{
    await pendingPublication(db);await owner(db);
    await denied(db,`select public.set_free_pro_beta_participation(null,'${a}'::uuid)`,"22004");
    await denied(db,`select public.set_free_pro_beta_participation(true,null)`);
    await denied(db,`select public.set_free_pro_beta_participation(true,'${b}'::uuid)`);
    assert.equal((await choose(db,false)).free_pro_access,false);
    await rejectUnchangedPublication(db,publishSQL());
    await owner(db);assert.equal((await choose(db,true)).free_pro_access,true);
    await db.exec("reset role;set local role service_role");
    assert.equal((await scalar(db,publishSQL())).status,"published");
    await db.exec("reset role");
    assert.equal(await scalar(db,"select count(*)::int from private.free_pro_beta_memberships"),1);
  });
});
