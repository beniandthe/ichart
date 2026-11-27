// New migration execution on a disposable local PostgreSQL database. All data is
// synthetic. Select a local container or private ICHART_POSTGRES_BIN; never hosted.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, writeFile } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { createFixture, owner, other, seed, auth, strictPaid, assertHelpers } from './test_coordinated_paid_activation_support.mjs';

const phase = (enabled, revision = 1) => `set local role service_role;
 select public.set_product_access_phase(${revision},${enabled});reset role;`;
const truth = 'public.product_access_status()';
const legacy = 'public.free_pro_beta_status()';
const check = (condition, label) => `select pg_temp.check_true((${condition}),'${label}');`;
const deny = (statement, code = '42501') => `select pg_temp.expect_error($deny$${statement}$deny$,'${code}');`;
const consistent = value => `(${value}->>'free_pro_access')::boolean =
 ((${value}->>'beta_available')::boolean and (${value}->>'eligible')::boolean and (${value}->>'participating')::boolean)`;

test('coordinated activation and bounded legacy access execute on actual PostgreSQL', { timeout: 180000 }, async t => {
  const db = await createFixture(); const results = []; let failed = false;
  async function scenario(name, body) {
    await t.test(name, async () => {
      try { await db.query(`begin;set local plpgsql.check_asserts=on;${assertHelpers}${seed}${body}rollback;`); results.push({ name, passed: true }); }
      catch (error) { failed = true; results.push({ name, passed: false }); throw error; }
    });
  }
  try {
    t.diagnostic(`Owned local database ${db.database}; ${db.applied.length} unchanged application migrations applied`);
    await scenario('truthful flat v2 starts in beta with no paid authority or scheduled end', `
      ${auth()}
      ${check(`${truth}->>'schema_version'='1' and ${truth}->>'policy_id'='ichart-product-access-v1'`, 'versioned fixed identity')}
      ${check(`${truth}->>'owner_id'='${owner}' and ${truth}->>'phase'='free_beta' and ${truth}->>'policy_revision'='1'`, 'owner phase revision')}
      ${check(`(${truth}->>'server_now')::timestamptz >= (${truth}->>'policy_updated_at')::timestamptz`, 'coherent diagnostic times')}
      ${check(`${consistent(truth)} and (${truth}->>'free_pro_access')::boolean`, 'truthful beta formula')}
      ${check(`not (${truth} ? 'has_paid_pro') and not (${truth} ? 'storekit_product_id')`, 'phase never fabricates billing')}
      ${check(`(select provider='none' and plan='free' from public.subscriptions where owner_id=auth.uid())`, 'billing unchanged free')}
      reset role;update private.ichart_free_access_policy set beta_notice_id='informational-only',beta_notice_title='Test notice',beta_notice_body='Synthetic notice',beta_ending_at='2000-01-01Z';
      ${auth()}${check(`${truth}->>'phase'='free_beta' and (${truth}->>'free_pro_access')::boolean`, 'past notice date cannot activate paid')}
    `);
    await scenario('original beta join leave and owner guards remain truthful even with a paid row', `
      ${strictPaid}${auth()}
      select public.set_free_pro_beta_participation(false,'${owner}');
      ${check(`not (${truth}->>'participating')::boolean and not (${legacy}->>'free_pro_access')::boolean`, 'explicit Basic wins in beta')}
      ${check(`${legacy}->>'policy_id'='free-pro-2026-10-15' and ${consistent(legacy)}`, 'unchanged beta legacy identity and formula')}
      ${deny(`select public.set_free_pro_beta_participation(true,'${other}')`)}
      select public.set_free_pro_beta_participation(true,'${owner}');
      ${check(`(${truth}->>'participating')::boolean and (${truth}->>'free_pro_access')::boolean`, 'beta rejoin restored')}
    `);
    await scenario('CAS noops stale generations and both phase directions have monotonic revisions', `
      create temporary table initial_policy as select * from private.ichart_paid_feature_policy;
      ${phase(false)}${check(`(select policy_revision=1 and policy_updated_at=(select policy_updated_at from initial_policy) from private.ichart_paid_feature_policy)`, 'same-phase CAS preserves revision and time')}
      ${phase(true)}${check(`(select enabled and policy_revision=2 from private.ichart_paid_feature_policy)`, 'activation advances revision')}
      set local role service_role;${deny('select public.set_product_access_phase(1,true)', 'PT409')}
      ${deny('select public.set_product_access_phase(null,false)', '22023')}
      ${deny('select public.set_product_access_phase(0,false)', '22023')}
      ${deny('select public.set_product_access_phase(2,null)', '22023')}reset role;
      ${phase(false, 2)}${check(`(select not enabled and policy_revision=3 from private.ichart_paid_feature_policy)`, 'rollback advances revision')}
      set local role service_role;${deny('select public.set_product_access_phase(1,false)', 'PT409')}reset role;
      ${phase(false, 3)}${check(`(select policy_revision=3 from private.ichart_paid_feature_policy)`, 'idempotent rollback stays same generation')}
      ${auth()}${check(`${truth}->>'phase'='free_beta' and ${truth}->>'policy_revision'='3'`, 'client receives rollback revision')}
    `);
    await scenario('direct privileged updates cannot spoof metadata or reseed the policy', `
      update private.ichart_paid_feature_policy set enabled=true;
      ${check(`(select enabled and policy_revision=2 from private.ichart_paid_feature_policy)`, 'direct activation revision')}
      update private.ichart_paid_feature_policy set enabled=false;
      ${check(`(select not enabled and policy_revision=3 from private.ichart_paid_feature_policy)`, 'direct rollback revision')}
      ${deny('update private.ichart_paid_feature_policy set policy_revision=20', '22023')}
      ${deny("update private.ichart_paid_feature_policy set policy_updated_at=now()+interval '1 day'", '22023')}
      ${deny('delete from private.ichart_paid_feature_policy', '55000')}
      ${deny('truncate private.ichart_paid_feature_policy', '55000')}
      ${deny('insert into private.ichart_paid_feature_policy(singleton,enabled) values(true,true)', '55000')}
      alter table private.ichart_paid_feature_policy disable trigger product_access_policy_revision_guard;
      update private.ichart_paid_feature_policy set policy_revision=9223372036854775807;
      alter table private.ichart_paid_feature_policy enable trigger product_access_policy_revision_guard;
      ${deny('update private.ichart_paid_feature_policy set enabled=true', '22003')}
    `);
    await scenario('roles cannot change phase or invoke private builders and owner overrides do not exist', `
      ${check(`not has_table_privilege('service_role','private.ichart_paid_feature_policy','UPDATE')`, 'service has CAS not direct UPDATE')}
      ${check(`not has_table_privilege('authenticated','private.ichart_paid_feature_policy','UPDATE')`, 'client cannot change phase')}
      ${check(`(select pronargs=0 from pg_proc where oid='public.product_access_status()'::regprocedure)`, 'no owner version or phase status argument')}
      do $$declare f regprocedure;r text;begin
       foreach f in array array['private.build_product_access_status()'::regprocedure,'private.current_user_has_verified_paid_pro()'::regprocedure,'private.guard_product_access_policy_revision()'::regprocedure] loop
        foreach r in array array['anon','authenticated','service_role'] loop
         assert not has_function_privilege(r,f,'EXECUTE');
        end loop;
       end loop;
       foreach f in array array['public.product_access_status()'::regprocedure,'public.set_product_access_phase(bigint,boolean)'::regprocedure,'private.set_product_access_phase(bigint,boolean)'::regprocedure,'public.free_pro_beta_status()'::regprocedure,'public.set_free_pro_beta_participation(boolean,uuid)'::regprocedure,'private.build_product_access_status()'::regprocedure,'private.current_user_has_verified_paid_pro()'::regprocedure,'private.guard_product_access_policy_revision()'::regprocedure] loop
        assert (select proconfig @> array['search_path=""'] from pg_proc where oid=f);
       end loop;
      end$$;
      ${auth()}${deny('select public.set_product_access_phase(1,true)')}
      set local request.jwt.claim.role='service_role';${deny('select public.set_product_access_phase(1,true)')}
      reset role;set local role anon;${deny('select public.product_access_status()')}${deny('select public.free_pro_beta_status()')}
      reset role;set local role service_role;${deny('select public.product_access_status()')}
    `);
    await scenario('paid legacy projection protects paid owners without falsifying truthful v2 or membership', `
      ${strictPaid}insert into private.free_pro_beta_memberships(owner_id,participating) values('${owner}',false);
      ${phase(true)}${auth()}
      ${check(`${truth}->>'phase'='paid' and not (${truth}->>'beta_available')::boolean and not (${truth}->>'participating')::boolean and not (${truth}->>'free_pro_access')::boolean`, 'truthful paid status has actual recorded choice')}
      ${check(`${consistent(truth)} and ${consistent(legacy)}`, 'both decoding formulas remain valid')}
      ${check(`${legacy}->>'policy_id'='legacy-paid-access-compat-v1' and (${legacy}->>'free_pro_access')::boolean and not (${legacy}->>'recorded_participating')::boolean`, 'strict paid legacy projection is explicit')}
      ${check(`not public.current_user_has_free_pro_access() and public.current_user_has_active_pro()`, 'compatibility does not broaden free service authority')}
      ${check(`position('managed with Apple' in (${legacy}->>'notice_body'))>0 and position('may still label access as free' in (${legacy}->>'notice_body'))>0`, 'old UI limitation and Apple subscription stay explicit')}
      select public.commit_pdf_setlist_backup('${owner}',0,'{"schema_version":1,"setlists":[],"pdfs":[]}');
      reset role;${check(`not (select participating from private.free_pro_beta_memberships where owner_id='${owner}')`, 'membership record not rewritten')}
    `);
    await scenario('paid activation does not mint any paid receipt for a beta-only account', `
      ${phase(true)}${auth()}
      ${check(`not (${legacy}->>'free_pro_access')::boolean and ${consistent(legacy)}`, 'unpaid legacy response consistent and denied')}
      ${check(`not (${truth}->>'free_pro_access')::boolean and ${truth}->>'phase'='paid'`, 'phase not entitlement')}
      ${check(`not public.current_user_has_active_pro()`, 'unpaid server services denied')}
      ${check(`(select provider='none' and plan='free' from public.subscriptions where owner_id=auth.uid())`, 'billing still free and unclaimed')}
      ${deny(`select public.commit_pdf_setlist_backup('${owner}',0,'{"schema_version":1,"setlists":[],"pdfs":[]}')`)}
    `);
    const rejected = [
      ['expired', "entitlement_expires_at=now()-interval '1 second'"],
      ['exact expiry', 'entitlement_expires_at=now()'], ['missing expiry', 'entitlement_expires_at=null'],
      ['revoked', 'revoked_at=now()'], ['unverified authority', 'last_verified_at=null'],
      ['manual provider', "provider='manual'"], ['stripe provider', "provider='stripe'"],
      ['free plan', "plan='free'"], ['inactive', "status='inactive'"],
      ...['expired','revoked','refunded','billing_retry','grace'].map(s => [`Apple ${s}`, `app_store_status='${s}'`]),
    ];
    for (const [label, mutation] of rejected) await scenario(`strict projection and service reject ${label}`, `
      ${strictPaid}update public.subscriptions set ${mutation} where owner_id='${owner}';
      ${phase(true)}${auth()}
      ${check(`not (${legacy}->>'free_pro_access')::boolean and not public.current_user_has_active_pro() and not public.current_user_has_paid_setlist_cloud()`, 'invalid paid authority cannot unlock')}
      ${check(`${truth}->>'phase'='paid' and not (${truth}->>'free_pro_access')::boolean`, 'phase does not mint entitlement')}
    `);
    for (const [label, mutation] of [
      ['unverified account', 'email_confirmed_at=null'], ['banned account', "banned_until=now()+interval '1 hour'"],
      ['anonymous account', 'is_anonymous=true'], ['soft-deleted account', 'deleted_at=now()'],
    ]) await scenario(`strict projection rejects ${label} while v2 explicitly reports ineligibility`, `
      ${strictPaid}update auth.users set ${mutation},raw_user_meta_data='{"eligible":true,"paid":true,"email_confirmed":true}' where id='${owner}';
      ${phase(true)}${auth()}
      ${check(`not (${truth}->>'eligible')::boolean and not (${legacy}->>'free_pro_access')::boolean and not public.current_user_has_active_pro()`, 'live account authority beats user metadata')}
    `);
    await scenario('phone verification and canceled-but-paid-through authority remain eligible', `
      ${strictPaid}update auth.users set email_confirmed_at=null,phone_confirmed_at=now() where id='${owner}';
      update public.subscriptions set app_store_auto_renew_status=false where owner_id='${owner}';
      ${phase(true)}${auth()}
      ${check(`(${truth}->>'eligible')::boolean and (${legacy}->>'free_pro_access')::boolean and public.current_user_has_active_pro()`, 'cancellation retains paid through access')}
    `);
    await scenario('missing owner and missing phase authority fail closed', `
      ${auth('c1210000-0000-4000-8000-000000000999')}${deny(`select ${truth}`)}${deny(`select ${legacy}`)}
      reset role;delete from private.ichart_free_access_policy;${auth()}
      ${deny(`select ${truth}`, '55000')}${deny(`select ${legacy}`, '55000')}
    `);
    await scenario('both paid membership directions reject without altering billing content or recorded choice', `
      ${strictPaid}insert into private.free_pro_beta_memberships(owner_id,participating) values('${owner}',false);
      create temporary table before_billing as select to_jsonb(s) value from public.subscriptions s;
      create temporary table before_membership as select to_jsonb(m) value from private.free_pro_beta_memberships m;
      create temporary table before_content as select to_jsonb(s) value from public.chart_snapshots s;
      ${phase(true)}${auth()}
      ${deny(`select public.set_free_pro_beta_participation(true,'${owner}')`, '55000')}
      ${deny(`select public.set_free_pro_beta_participation(false,'${owner}')`, '55000')}
      reset role;
      ${check(`not exists((select to_jsonb(s) from public.subscriptions s except select value from before_billing) union all (select value from before_billing except select to_jsonb(s) from public.subscriptions s))`, 'billing exact after denied choices')}
      ${check(`(select to_jsonb(m)=b.value from private.free_pro_beta_memberships m cross join before_membership b)`, 'membership exact after denied choices')}
      ${check(`(select to_jsonb(s)=b.value from public.chart_snapshots s cross join before_content b)`, 'source snapshot exact after denied choices')}
      ${phase(false,2)}${auth()}
      ${check(`not (${truth}->>'participating')::boolean and not (${legacy}->>'free_pro_access')::boolean and ${legacy}->>'policy_id'='free-pro-2026-10-15'`, 'rollback restores actual Basic choice')}
      reset role;set local role service_role;
      ${check(`(public.run_subscription_retention_jobs()->>'cloud_deleted_events')::integer=0`, 'retention remains independently paused')}
    `);
    const pgTapAvailable = await db.query("select exists(select 1 from pg_available_extensions where name='pgtap');") === 't';
    if (pgTapAvailable) await db.query('create extension if not exists pgtap;');
    for (const name of ['free_pro_access_test.sql','forum_plan_access_test.sql','pdf_setlist_backups_test.psql']) {
      const supplemental = name !== 'pdf_setlist_backups_test.psql';
      const skip = supplemental && !pgTapAvailable ? 'Supplemental historical pgTAP extension is unavailable; mandatory coordination matrix and PDF regression still execute' : false;
      if (skip) results.push({ name, skipped: true, reason: skip });
      await t.test(`unchanged ${supplemental ? 'supplemental pgTAP' : 'mandatory PDF'} regression ${name}`, { skip }, async () => {
        try {
          const output = await db.query(await readFile(new URL(`../supabase/tests/${name}`, import.meta.url), 'utf8'));
          assert.doesNotMatch(output, /^not ok /m); results.push({ name, passed: true, tapPassed: (output.match(/^ok \d+/gm) ?? []).length });
        } catch (error) { failed = true; results.push({ name, passed: false }); throw error; }
      });
    }
  } finally {
    if (process.env.ICHART_COORDINATED_TEST_RECEIPT) {
      const path = process.env.ICHART_COORDINATED_TEST_RECEIPT;
      assert.ok(isAbsolute(path), 'Receipt must have an explicit absolute local path');
      await writeFile(path, JSON.stringify({ database: db.database, applied: db.applied, results, passed: !failed,
        observedUTC: new Date().toISOString(), syntheticOnly: true, hostedWrites: false }, null, 2), { flag: 'wx' });
    }
    await db.close(!failed);
  }
});
