// Native PostgreSQL integration tests; all data and identities are synthetic.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { cluster, setup, event } from './lib/telemetry_pipeline_fixture.mjs';
const owner='11000000-0000-4000-8000-000000000001';
const violation=(overrides={})=>({contract_id:'ink.reopen_preservation',contract_version:1,operation_id:randomUUID(),
  outcome:'violated',reason:'reopen_mismatch',content_matches:false,build_source:'release_build',expected_count:4,actual_count:2,...overrides});
const worker=db=>db.sql('select private.process_telemetry_evaluations(250);');
async function queue(db,where='true'){return db.rows(`select * from private.telemetry_work_queue where ${where} order by rule_id,build_source`);}

test('feature-contract pipeline executes real PostgreSQL rules, storage and lifecycle',async t=>{
  const db=await cluster();let success=false;
  try{
    await setup(db);
    await t.test('automatic outbox and idempotent evidence distinguish repeats from affected installations',async()=>{
      const id=randomUUID(),props=violation();
      await event(db,{clientID:id,properties:props});await event(db,{clientID:id,properties:props});
      await event(db,{properties:violation()});
      await event(db,{properties:violation(),install:randomUUID(),sessionID:randomUUID()});
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_evaluation_outbox'))[0].n,3);
      await worker(db);await worker(db);
      const [item]=await queue(db);assert.equal(item.event_count,3);assert.equal(item.installation_count,2);
      assert.equal(item.session_count,2);assert.equal(item.evidence_kind,'contract_violation');
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,3);
    });
    await t.test('debug, release and unknown are separate and a legacy launch can supply a label',async()=>{
      await event(db,{properties:violation({build_source:'debug_build'})});
      await event(db,{properties:violation({build_source:'invalid'})});
      const legacySession=randomUUID();
      await event(db,{name:'app.launched',sessionID:legacySession,properties:{source:'debug_build'}});
      const props=violation();delete props.build_source;await event(db,{sessionID:legacySession,properties:props});
      await worker(db);const rows=await queue(db,"rule_id='contract.ink.reopen_preservation.reopen_mismatch'");
      assert.deepEqual(rows.map(row=>row.build_source),['debug_build','release_build','unknown']);
      assert.equal(rows[0].event_count,2);
    });
    await t.test('safe rejections, unknowns and malformed evidence never become defects',async()=>{
      const before=(await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n;
      for(const properties of [violation({outcome:'passed'}),violation({outcome:'unknown',reason:'baseline_missing'}),
        violation({outcome:'protected_rejection',reason:'render_unresolved'}),violation({content_matches:true}),
        violation({contract_id:'unknown.feature'}),violation({operation_id:'malformed'}),violation({contract_version:'1'}),
        violation({contract_id:'ink.rotation_preservation',reason:'rotation_stroke_count_changed',expected_count:4,actual_count:4}),
        violation({contract_id:'ink.rotation_preservation',reason:'rotation_stroke_count_changed',expected_count:'4',actual_count:2})])await event(db,{properties});
      for(const properties of [{error_code:'cancelled'},{error_code:'offline'},{}])await event(db,{name:'cloud.push_failed',properties});
      await event(db,{name:'chord.rendered_correction_applied',properties:{decision:'equivalent_spelling'}});
      await event(db,{name:'chord.rendered_correction_applied',properties:{}});
      await worker(db);assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before);
      assert.ok((await db.rows('select * from private.telemetry_pipeline_health'))[0].rejected_count>=6);
    });
    await t.test('operation failures, cloud investigations and correction friction retain distinct evidence kinds',async()=>{
      await event(db,{properties:violation({contract_id:'chart.save',reason:'save_failed'})});
      await event(db,{properties:violation({contract_id:'chart.save_readback',outcome:'unknown',reason:'readback_failed',content_matches:true})});
      await event(db,{name:'cloud.restore_failed',properties:{error_code:'server'}});
      await event(db,{name:'chord.rendered_correction_applied',properties:{decision:'outside_candidates'}});
      await worker(db);const rows=await queue(db);
      assert.equal(rows.find(r=>r.rule_id==='contract.chart.save.save_failed').evidence_kind,'operation_failure');
      assert.equal(rows.find(r=>r.rule_id==='contract.chart.save_readback.readback_failed').evidence_kind,'operation_failure');
      assert.equal(rows.find(r=>r.rule_id==='contract.chart.save_readback.readback_failed').title,'Saved chart could not be read back');
      assert.equal(rows.find(r=>r.rule_id==='legacy.cloud.restore_failed.server').evidence_kind,'investigation');
      assert.equal(rows.find(r=>r.rule_id==='legacy.chord.rendered_correction').evidence_kind,'friction');
    });
    await t.test('every supported render/rotation/readback violation requires the actual typed comparison',async()=>{
      const cases=[
        violation({contract_id:'chart.save_readback',reason:'readback_mismatch'}),
        violation({contract_id:'ink.render_preservation',reason:'render_source_missing'}),
        violation({contract_id:'ink.render_preservation',reason:'render_rejected_mutated'}),
        violation({contract_id:'ink.render_preservation',reason:'render_canvas_not_cleared',expected_count:0,actual_count:2}),
        violation({contract_id:'ink.rotation_preservation',reason:'rotation_stroke_count_changed'}),
        violation({contract_id:'ink.rotation_preservation',reason:'rotation_point_count_changed',expected_count:4,actual_count:4,expected_point_count:100,actual_point_count:80}),
        violation({contract_id:'ink.rotation_preservation',reason:'rotation_nonfinite_geometry'}),
        violation({contract_id:'chart.export',reason:'export_failed'})];
      const before=(await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n;
      for(const properties of cases)await event(db,{properties});
      await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+cases.length);
      const invalid=[violation({contract_id:'ink.rotation_preservation',reason:'rotation_point_count_changed',expected_count:4,actual_count:2}),
        violation({contract_id:'ink.render_preservation',reason:'render_canvas_not_cleared',expected_count:4,actual_count:2}),
        violation({contract_id:'ink.rotation_preservation',reason:'rotation_nonfinite_geometry',content_matches:true})];
      for(const properties of invalid)await event(db,{properties});await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+cases.length);
    });
    await t.test('operation and chart linkage deduplicates scoped observations and exposes missing coverage',async()=>{
      const operationID=randomUUID(),chartReference='a'.repeat(64);
      const props=violation({contract_id:'ink.rotation_preservation',reason:'rotation_point_count_changed',
        expected_point_count:100,actual_point_count:80,build_source:'debug_build',
        operation_id:operationID,chart_reference:chartReference});
      await event(db,{properties:{...props,scope:'page'}});
      await event(db,{properties:{...props,scope:'chords',operation_id:operationID.toUpperCase(),chart_reference:chartReference.toUpperCase()}});
      await event(db,{properties:{...props,operation_id:randomUUID(),chart_reference:'b'.repeat(64)}});
      await worker(db);
      const [item]=await queue(db,"rule_id='contract.ink.rotation_preservation.rotation_point_count_changed' and build_source='debug_build'");
      assert.equal(item.event_count,3);assert.equal(item.operation_count,2);assert.equal(item.affected_chart_count,2);
      assert.equal(item.operation_linked_event_count,3);assert.equal(item.chart_linked_event_count,3);
      const [legacy]=await queue(db,"rule_id='legacy.cloud.restore_failed.server'");
      assert.equal(legacy.operation_count,null);assert.equal(legacy.affected_chart_count,null);
      assert.equal(legacy.operation_linked_event_count,0);assert.equal(legacy.chart_linked_event_count,0);
      await event(db,{name:'cloud.restore_failed',properties:{error_code:'server',operation_id:'malformed',chart_reference:'not-a-chart-reference'}});
      await worker(db);
      const [invalid]=await queue(db,"rule_id='legacy.cloud.restore_failed.server'");
      assert.equal(invalid.operation_count,null);assert.equal(invalid.affected_chart_count,null);
      assert.equal(invalid.operation_linked_event_count,0);assert.equal(invalid.chart_linked_event_count,0);
    });
    await t.test('resolution requires verification; only post-fix build recurrence reopens',async()=>{
      const [item]=await queue(db,"rule_id='contract.chart.save.save_failed'");
      await assert.rejects(db.sql(`update private.telemetry_incidents set status='resolved' where incident_id='${item.incident_id}';`),/Resolution requires/);
      await db.sql(`update private.telemetry_incidents set status='resolved',fixed_build_number='101',verification_ref='synthetic-test-evidence' where incident_id='${item.incident_id}';`);
      await assert.rejects(db.sql(`update private.telemetry_incidents set verification_ref=null where incident_id='${item.incident_id}';`),/Resolution requires/);
      await event(db,{properties:violation({contract_id:'chart.save',reason:'save_failed'}),build:'100'});
      await event(db,{properties:violation({contract_id:'chart.save',reason:'save_failed'}),build:'101',occurredSQL:"now()-interval '1 day'"});
      await worker(db);assert.equal((await queue(db,`incident_id='${item.incident_id}'`))[0].status,'resolved');
      await event(db,{properties:violation({contract_id:'chart.save',reason:'save_failed'}),build:'101'});
      await worker(db);const [reopened]=await queue(db,`incident_id='${item.incident_id}'`);
      assert.equal(reopened.status,'new');assert.equal(reopened.reopened_count,1);
      assert.equal((await db.rows(`select count(*)::int as n from private.telemetry_incident_history where incident_id='${item.incident_id}' and change_reason='verified_fix_recurrence'`))[0].n,1);
    });
    await t.test('late received events and concurrent workers are processed once without a cursor gap',async()=>{
      const before=(await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n;
      for(let i=0;i<20;i++)await event(db,{properties:violation(),receivedSQL:"now()-interval '2 days'",occurredSQL:"now()-interval '3 days'"});
      await Promise.all([worker(db),worker(db)]);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+20);
      assert.equal((await db.rows('select * from private.telemetry_pipeline_health'))[0].pending_count,0);
    });
    await t.test('failed evaluations rollback partial writes, retry and dead-letter without blocking other events',async()=>{
      await db.sql(`create function private.synthetic_fail_evidence() returns trigger language plpgsql as $$begin
        if (select properties->>'scope' from public.telemetry_events where id=new.raw_event_id)='synthetic_failure' then raise exception 'synthetic failure';end if;return new;end;$$;
        create trigger synthetic_failure before insert on private.telemetry_incident_events for each row execute function private.synthetic_fail_evidence();`);
      const bad=await event(db,{properties:violation({scope:'synthetic_failure'})});
      await event(db,{properties:violation()});
      for(let i=0;i<5;i++){await worker(db);await db.sql(`update private.telemetry_evaluation_outbox set next_attempt_at=now() where raw_event_id='${bad}';`);}
      const [failed]=await db.rows(`select * from private.telemetry_evaluation_outbox where raw_event_id='${bad}'`);
      assert.equal(failed.attempts,5);assert.ok(failed.dead_letter_at);assert.equal(failed.last_error_code,'evaluation_failed');
      assert.equal((await db.rows(`select count(*)::int as n from private.telemetry_incident_events where raw_event_id='${bad}'`))[0].n,0);
      const [health]=await db.rows('select * from private.telemetry_pipeline_health');assert.equal(health.dead_letter_count,1);assert.ok(health.last_run_at);
      await db.sql('drop trigger synthetic_failure on private.telemetry_incident_events;drop function private.synthetic_fail_evidence();');
    });
    await t.test('account deletion and retention cascade raw evidence/outbox without retaining identifiers in tasks',async()=>{
      const raw=await event(db,{ownerID:owner,properties:violation({contract_id:'chart.export',reason:'export_failed',build_source:'debug_build'})});await worker(db);
      const [ownedTask]=await db.rows(`select incident_id from private.telemetry_incident_events where raw_event_id='${raw}'`);
      await db.sql(`delete from auth.users where id='${owner}';`);
      assert.equal((await db.rows(`select count(*)::int as n from private.telemetry_incident_events where raw_event_id='${raw}'`))[0].n,0);
      assert.equal((await db.rows(`select count(*)::int as n from private.telemetry_evaluation_outbox where raw_event_id='${raw}'`))[0].n,0);
      const [retainedTask]=await queue(db,`incident_id='${ownedTask.incident_id}'`);
      assert.equal(retainedTask.evidence_available,false);assert.equal(retainedTask.event_count,0);assert.equal(retainedTask.session_count,0);
      assert.deepEqual(retainedTask.build_numbers,[]);assert.equal(retainedTask.latest_event_id,null);
      const expired=await event(db,{properties:violation(),receivedSQL:"now()-interval '181 days'"});await worker(db);
      await db.sql('select private.purge_old_telemetry_events(180);');
      assert.equal((await db.rows(`select count(*)::int as n from private.telemetry_incident_events where raw_event_id='${expired}'`))[0].n,0);
      assert.equal((await db.rows("select count(*)::int as n from information_schema.columns where table_schema='private' and table_name='telemetry_incidents' and column_name in ('owner_id','installation_id','session_id','properties')"))[0].n,0);
    });
    await t.test('private operator access stays isolated while service-role intake enqueues safely',async()=>{
      const [privileges]=await db.rows(`select has_schema_privilege('anon','private','usage') as anon_schema,
        has_schema_privilege('service_role','private','usage') as service_schema,
        has_table_privilege('authenticated','private.telemetry_work_queue','select') as client_read,
        has_function_privilege('anon','private.process_telemetry_evaluations(integer)','execute') as client_run,
        has_table_privilege('service_role','private.telemetry_work_queue','select') as server_read`);
      // Object ACLs do not override the intentionally denied schema namespace.
      assert.deepEqual(privileges,{anon_schema:false,service_schema:false,client_read:false,client_run:false,server_read:true});
      await assert.rejects(db.sql('set role service_role;select * from private.telemetry_work_queue;'),/permission denied for schema private/);
      await assert.rejects(db.sql('set role service_role;select private.process_telemetry_evaluations(250);'),/permission denied for schema private/);
      const raw=await event(db,{asServiceRole:true,properties:violation({contract_id:'chart.load',reason:'load_failed',build_source:'debug_build'})});
      assert.equal((await db.rows(`select count(*)::int as n from private.telemetry_evaluation_outbox where raw_event_id='${raw}'`))[0].n,1);
      // The trusted trigger and operator/Cron owner can use private objects;
      // signed service intake itself never gains namespace access.
      await worker(db);
      assert.equal((await db.rows(`select count(*)::int as n from private.telemetry_incident_events where raw_event_id='${raw}'`))[0].n,1);
      assert.ok((await queue(db)).length>0);
      const [job]=await db.rows("select * from cron.job where jobname='ichart-telemetry-feature-contracts'");
      assert.equal(job.schedule,'*/5 * * * *');assert.equal(job.command,'select private.process_telemetry_evaluations(250);');
      await assert.rejects(db.sql('select private.process_telemetry_evaluations(0);'),/batch_limit/);
      await assert.rejects(db.sql('select private.process_telemetry_evaluations(1001);'),/batch_limit/);
      const outcomes=await db.rows('select * from private.telemetry_contract_outcomes');
      assert.ok(outcomes.some(row=>row.outcome==='unknown'));assert.ok(outcomes.some(row=>row.outcome==='passed'));
    });
    await t.test('delivery health uses the latest cumulative counter report per installation without double counting',async()=>{
      const props={queue_overflow_count:4,queue_rejected_count:2,queue_quarantine_overflow_count:0,queue_unacknowledged_batch_count:1};
      await event(db,{name:'app.launched',properties:props,occurredSQL:"now()-interval '1 minute'"});
      await event(db,{name:'app.launched',properties:{...props,queue_overflow_count:7}});
      const [health]=await db.rows('select * from private.telemetry_pipeline_health');
      assert.equal(health.delivery_reporting_installation_count,1);assert.equal(health.queue_overflow_count,7);
      assert.equal(health.queue_rejected_count,2);assert.ok(health.last_delivery_reported_at);
    });
    success=true;
  }finally{await db.stop(success);}
});
