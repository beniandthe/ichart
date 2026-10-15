// Actual PostgreSQL/RLS execution in isolated PGlite 0.5.8, not a production
// Supabase/Auth/storage deployment test. All records below are synthetic. The
// repository's June/July migrations and new free-access migration run unchanged;
// only external Auth/Storage prerequisites are modeled by the fixture.
// ICHART_PGLITE_MODULE_PATH must name the installed pinned package's dist/index.js.
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";
import { applyFreeProAccessToOfferConfiguration, freeProAccessPolicy } from "../supabase/functions/_shared/free_pro_access_policy.mjs";
import { handleComplimentaryOfferRequest } from "../supabase/functions/_shared/complimentary_offer_campaign.mjs";
import { handleSubscriptionRetentionJobRequest } from "../supabase/functions/_shared/subscription_retention_jobs.mjs";

const modulePath = process.env.ICHART_PGLITE_MODULE_PATH;
assert.ok(modulePath && isAbsolute(modulePath), "Set absolute ICHART_PGLITE_MODULE_PATH for pinned PGlite 0.5.8.");
assert.equal(JSON.parse(await readFile(new URL("../package.json", pathToFileURL(modulePath)), "utf8")).version, "0.5.8",
  "The offline PostgreSQL fixture must use the reviewed pinned PGlite release.");
const { PGlite } = await import(pathToFileURL(modulePath).href);
const { pgcrypto } = await import(new URL("./contrib/pgcrypto.js", pathToFileURL(modulePath)).href);
const migrationDirectory = new URL("../supabase/migrations/", import.meta.url);
const freeMigration = "20261015203728_free_pro_access.sql";
const a = "11000000-0000-4000-8000-000000000001";
const b = "11000000-0000-4000-8000-000000000002";
const chart = "22000000-0000-4000-8000-000000000001";
const snapshot = "33000000-0000-4000-8000-000000000001";
const song = "44000000-0000-4000-8000-000000000001";
const post = "55000000-0000-4000-8000-000000000001";

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
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid; $$;
    grant usage on schema auth to authenticated, anon, service_role;
    create schema storage;
    create table storage.buckets(id text primary key, name text, public boolean,
      file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),
      bucket_id text references storage.buckets(id), name text, owner uuid,
      owner_id text, metadata jsonb default '{}', created_at timestamptz default now());
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated, service_role;
    grant select, insert, update, delete on storage.objects to authenticated, service_role;
    create function storage.foldername(path text) returns text[] language sql immutable
      as $$ select string_to_array(regexp_replace(path, '/[^/]*$', ''), '/'); $$;
    create function storage.extension(path text) returns text language sql immutable
      as $$ select regexp_replace(path, '^.*\\.', ''); $$;
  `);
  const names = (await readdir(migrationDirectory)).filter(name => /^20260[67].*\.sql$/.test(name)).sort();
  for (const name of names) {
    try { await db.exec(await readFile(new URL(name, migrationDirectory), "utf8")); }
    catch (error) { throw new Error(`Prerequisite migration ${name}: ${error.message}`, { cause: error }); }
  }
  await db.exec(`insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
    values ('${a}','a@example.test',now(),'{"first_name":"Alpha","last_name":"Tester"}'),
      ('${b}','b@example.test',now(),'{"first_name":"Beta","last_name":"Tester"}');
    insert into public.chart_documents(id,owner_id,title,layout_style)
      values ('${chart}','${a}','Preserve this chart','simpleChordSheet');
    insert into public.chart_snapshots(id,chart_id,owner_id,version,chart_json)
      values ('${snapshot}','${chart}','${a}',1,'{}');
    insert into private.subscription_retention_events(owner_id,event_type,subject,body,dedupe_key,recipient_email)
      values ('${a}','expiration_warning','stale warning','stale body','before-free','a@example.test');`);
  // Measure the unchanged pre-migration paid-mode rollback cap on this actual
  // PostgreSQL engine. Its candidate-row snapshot behavior can differ from the
  // external Supabase Storage service, which is intentionally not simulated.
  let baselineRollbackCap = 0;
  await db.exec(`begin; update public.subscriptions set plan='studioSubscription',status='active'
    where owner_id='${a}'`);
  await owner(db);
  for (let i = 0; i < 8; i += 1) {
    await db.exec("savepoint baseline_cap");
    try {
      await db.exec(`insert into storage.objects(bucket_id,name) values ('forum_chart_pdfs','${a}/baseline-${i}.pdf')`);
      baselineRollbackCap += 1;
      await db.exec("release savepoint baseline_cap");
    } catch (error) {
      assert.equal(error.code, "42501");
      await db.exec("rollback to savepoint baseline_cap; release savepoint baseline_cap");
      break;
    }
  }
  await db.exec("rollback");
  assert.ok(baselineRollbackCap > 0 && baselineRollbackCap < 8, "Existing rollback upload limit must be enforced.");
  await db.exec(await readFile(new URL(freeMigration, migrationDirectory), "utf8"));
  await db.exec(await readFile(new URL("20261015232153_voluntary_free_pro_beta.sql", migrationDirectory), "utf8"));
  return { db, baselineRollbackCap };
}

async function owner(db, id = a) {
  await db.exec("set local role authenticated");
  await db.query("select set_config('request.jwt.claim.sub', $1, true)", [id]);
}
async function scalar(db, query) { return Object.values((await db.query(query)).rows[0])[0]; }
async function denied(db, query, code = "42501") {
  await db.exec("savepoint expected_denial");
  try { await assert.rejects(db.exec(query), error => error.code === code); }
  finally { await db.exec("rollback to savepoint expected_denial; release savepoint expected_denial"); }
}

test("free-access migration executes with actual PostgreSQL semantics", async t => {
  const { db, baselineRollbackCap } = await fixture();
  t.after(() => db.close());
  async function scenario(name, body) {
    await t.test(name, async () => {
      await db.exec("begin");
      try { await body(); } finally { await db.exec("rollback"); }
    });
  }
  await scenario("new Basic account gets full access without a paid row or deadline", async () => {
    await owner(db);
    assert.equal(await scalar(db, "select public.current_user_has_free_pro_access()"), true);
    assert.equal(await scalar(db, "select public.current_user_has_active_pro()"), true);
    assert.equal(await scalar(db, "select plan from public.subscriptions"), "free");
    assert.equal(await scalar(db, "select provider from public.subscriptions"), "none");
    assert.equal(await scalar(db, "select entitlement_expires_at from public.subscriptions"), null);
  });
  for (const state of ["expired", "revoked", "refunded", "billing_retry", "grace", "active"]) {
    await scenario(`${state} Apple evidence stays truthful and does not remove free access`, async () => {
      await db.exec(`update public.subscriptions set provider='storekit', app_store_status='${state}',
        status='inactive', plan='free', entitlement_expires_at=now()-interval '1 day',
        cloud_retention_deadline=now()-interval '1 day', revoked_at=now() where owner_id='${a}'`);
      await owner(db);
      assert.equal(await scalar(db, "select public.current_user_has_free_pro_access()"), true);
      assert.equal(await scalar(db, "select app_store_status from public.subscriptions"), state);
      assert.equal(await scalar(db, "select status from public.subscriptions"), "inactive");
      await db.exec("reset role; set local role service_role");
      const result = await scalar(db, "select public.run_subscription_retention_jobs()");
      assert.equal(result.cloud_deleted_events, 0);
      assert.equal(result.expiration_warning_events, 0);
      await db.exec("reset role");
      assert.equal(await scalar(db, "select count(*)::int from public.chart_documents"), 1);
      assert.equal(await scalar(db, "select count(*)::int from public.chart_snapshots"), 1);
    });
  }
  await scenario("cancelled renewal emits no access-loss warning and marks no expiry", async () => {
    await db.exec(`update public.subscriptions set provider='storekit', status='active',
      plan='studioSubscription', app_store_status='active', app_store_auto_renew_status=false,
      entitlement_expires_at=now()+interval '1 hour' where owner_id='${a}'`);
    const result = await scalar(db, "select public.run_subscription_retention_jobs()");
    assert.equal(result.expiration_warning_events, 0);
    assert.equal(await scalar(db, `select expiration_warning_sent_at from public.subscriptions where owner_id='${a}'`), null);
  });
  await scenario("queued and newly queued expiry notices are suppressed, never marked sent", async () => {
    assert.equal(await scalar(db, "select suppressed_at is not null from private.subscription_retention_events where dedupe_key='before-free'"), true);
    await db.exec(`insert into private.subscription_retention_events(owner_id,event_type,subject,body,dedupe_key,recipient_email)
      values ('${a}','cloud_deleted','stale','stale','after-free','a@example.test')`);
    await db.exec("set local role service_role");
    assert.equal((await db.query("select * from public.claim_subscription_retention_events(25)")).rows.length, 0);
    assert.equal(await scalar(db, "select count(*)::int from private.subscription_retention_events where sent_at is not null or dispatch_attempt_count<>0"), 0);
    assert.equal(await scalar(db, "select count(*)::int from private.subscription_retention_events where suppressed_at is not null"), 2);
    await denied(db, "select private.run_subscription_retention_jobs_paid_parked()", "42501");
    await denied(db, "select * from private.claim_subscription_retention_events_paid_parked()", "42501");
  });
  for (const [label, mutation] of [
    ["unconfirmed", "email_confirmed_at=null"], ["anonymous", "is_anonymous=true"],
    ["banned", "banned_until=now()+interval '1 day'"], ["soft-deleted", "deleted_at=now()"],
  ]) {
    await scenario(`${label} account cannot gain free access even with paid metadata`, async () => {
      await db.exec(`update auth.users set ${mutation} where id='${a}';
        update public.subscriptions set plan='studioSubscription',status='active' where owner_id='${a}'`);
      await owner(db);
      assert.equal(await scalar(db, "select public.current_user_has_free_pro_access()"), false);
      assert.equal(await scalar(db, "select public.current_user_has_active_pro()"), false);
      assert.equal(await scalar(db, "select count(*)::int from public.chart_documents"), 0);
    });
  }
  await scenario("missing account or stale deleted-account JWT grants no access", async () => {
    await db.exec(`delete from auth.users where id='${a}'`);
    await owner(db);
    assert.equal(await scalar(db, "select public.current_user_has_free_pro_access()"), false);
    assert.equal(await scalar(db, "select public.current_user_has_active_pro()"), false);
    await db.exec("reset role");
    assert.equal(await scalar(db, "select count(*)::int from public.chart_documents"), 0);
  });
  await scenario("anon role and unauthenticated calls cannot execute access/retention RPCs", async () => {
    await db.exec("set local role anon");
    await denied(db, "select public.current_user_has_free_pro_access()");
    await denied(db, "select public.current_user_has_active_pro()");
    await denied(db, "select public.run_subscription_retention_jobs()");
    await denied(db, "select * from public.claim_subscription_retention_events()");
  });
  await scenario("free account can write own cloud chart, never another owner's chart or snapshot", async () => {
    await owner(db);
    await db.exec(`insert into public.chart_documents(owner_id,title,layout_style) values ('${a}','Own free chart','simpleChordSheet')`);
    await denied(db, `insert into public.chart_documents(owner_id,title,layout_style) values ('${b}','Wrong owner','simpleChordSheet')`);
    await denied(db, `insert into public.chart_snapshots(chart_id,owner_id,version,chart_json) values ('${chart}','${b}',2,'{}')`);
    await denied(db, `update public.chart_documents set owner_id='${b}' where id='${chart}'`);
    await owner(db, b);
    assert.equal(await scalar(db, "select count(*)::int from public.chart_documents"), 0);
    await db.exec(`update public.chart_documents set title='hijacked' where id='${chart}'; delete from public.chart_documents where id='${chart}'`);
    await db.exec("reset role");
    assert.equal(await scalar(db, `select title from public.chart_documents where id='${chart}'`), "Preserve this chart");
  });
  await scenario("free account cannot mutate policy or subscription billing authority", async () => {
    await owner(db);
    await denied(db, "delete from private.ichart_free_access_policy");
    await denied(db, "update private.ichart_free_access_policy set enabled=false");
    await denied(db, "update public.subscriptions set plan='studioSubscription'");
    await db.exec("reset role; set local role service_role");
    await denied(db, "delete from private.ichart_free_access_policy");
    await denied(db, "update private.ichart_free_access_policy set enabled=false");
    await db.exec("reset role");
    await denied(db, "update private.ichart_free_access_policy set enabled=false", "23514");
  });
  await scenario("missing policy fails retention closed, never resumes expired-row deletion", async () => {
    await db.exec("delete from private.ichart_free_access_policy");
    await denied(db, "select public.run_subscription_retention_jobs()", "P0001");
    await denied(db, "select * from public.claim_subscription_retention_events()", "P0001");
    assert.equal(await scalar(db, "select count(*)::int from public.chart_documents"), 1);
  });
  await scenario("forum visibility and moderation remain enforced for free accounts", async () => {
    await owner(db);
    await db.exec(`insert into public.forum_songs(id,song_title,artist_name,normalized_song_title,normalized_artist_name,created_by)
      values ('${song}','Real Song','Artist','real song','artist','${a}');
      insert into public.forum_chart_posts(id,song_id,owner_id,chart_title,arranger_credit,creator_display_name,layout_style,pdf_storage_path)
      values ('${post}','${song}','${a}','Chart','Arranger','Alpha Tester','simpleChordSheet','${a}/${post}.pdf')`);
    assert.equal(await scalar(db, "select status from public.forum_chart_posts"), "pending");
    await owner(db, b);
    assert.equal(await scalar(db, "select count(*)::int from public.forum_chart_posts"), 0);
    await db.exec(`reset role; update public.forum_chart_posts set status='published' where id='${post}'`);
    await owner(db, b);
    assert.equal(await scalar(db, "select count(*)::int from public.forum_chart_posts"), 1);
    await db.exec(`insert into public.forum_user_blocks(owner_id,blocked_owner_id) values ('${b}','${a}')`);
    assert.equal(await scalar(db, "select count(*)::int from public.forum_chart_posts"), 0);
    await db.exec(`reset role; update public.forum_chart_posts set status='hidden' where id='${post}'`);
    await owner(db);
    assert.equal(await scalar(db, "select count(*)::int from public.forum_chart_posts"), 0);
  });
  await scenario("forum PDF owner path, provenance and pre-existing rollback-buffer limit remain", async () => {
    await owner(db);
    await denied(db, `insert into storage.objects(bucket_id,name) values ('forum_chart_pdfs','${b}/wrong.pdf')`);
    await denied(db, `insert into storage.objects(bucket_id,name) values ('forum_chart_pdfs','${a}/wrong.txt')`);
    for (let i = 0; i < baselineRollbackCap; i += 1) {
      await db.exec(`insert into storage.objects(bucket_id,name) values ('forum_chart_pdfs','${a}/file-${i}.pdf')`);
    }
    await denied(db, `insert into storage.objects(bucket_id,name) values ('forum_chart_pdfs','${a}/excess.pdf')`);
    assert.equal(await scalar(db, "select count(*)::int from storage.objects"), 0);
    await denied(db, `select public.finalize_forum_chart_post_pdf('${post}',10,repeat('a',64))`);
  });
});

test("free product policy is immutable and overrides even a fully enabled offer config", () => {
  assert.equal(Object.isFrozen(freeProAccessPolicy), true);
  const result = applyFreeProAccessToOfferConfiguration({ enabled: true, environment: "production" });
  assert.equal(result.enabled, false);
  assert.equal(result.freeAccessPhaseActive, true);
  assert.equal(result.reason, "free_access_active");
});
for (const action of ["status", "prepare", "confirm"]) {
  test(`old-client offer ${action} returns no purchase/signature without Apple/store I/O`, async () => {
    const unexpected = () => { throw new Error("Unexpected billing or store I/O"); };
    const response = await handleComplimentaryOfferRequest(new Request("https://example.test/offers", {
      method: "POST", body: JSON.stringify({ schemaVersion: 1, action,
        productID: "com.ichart.app.pro.monthly", attemptID: b }),
    }), { authenticatedUserID: async () => a, readCampaignLedger: unexpected,
      reserveCampaignAttempt: unexpected, recordCampaignBenefit: unexpected,
      fetchFreshAppleSnapshot: unexpected, signPromotionalOffer: unexpected },
    applyFreeProAccessToOfferConfiguration({ enabled: true, campaignID: "old-campaign" }));
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.reason, "free_access_active");
    assert.equal(body.enabled, false);
    assert.equal(body.activation, null);
    assert.equal(body.freeAccess, true);
  });
}

test("free-phase retention worker never claims or dispatches queued access-loss mail", async () => {
  const unexpected = () => { throw new Error("Unexpected queued email dispatch"); };
  const response = await handleSubscriptionRetentionJobRequest(new Request("https://example.test/retention", {
    method: "POST", headers: { "x-ichart-retention-job-secret": "synthetic-local-only" }, body: "{}",
  }), { jobSecret: "synthetic-local-only", emailProviderConfigured: true,
    runRetentionJobs: async () => ({ retention_status: "paused_free_access", cloud_deleted_events: 0 }),
    claimEmailEvents: unexpected, sendEmail: unexpected,
    markEmailEventSent: unexpected, markEmailEventFailed: unexpected });
  const body = await response.json();
  assert.equal(response.status, 202);
  assert.equal(body.email_status, "suppressed_free_access");
  assert.equal(body.emails_attempted, 0);
  assert.equal(body.emails_sent, 0);
});
