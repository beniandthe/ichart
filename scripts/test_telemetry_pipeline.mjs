// Native PostgreSQL integration tests; all data and identities are synthetic.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { cluster, setup, applyAutomaticContracts, applyExperienceContracts, event } from './lib/telemetry_pipeline_fixture.mjs';
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
    await t.test('selective render evidence creates distinct retained-source and leftover-consumed tasks',async()=>{
      const before=(await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n;
      for(const reason of ['render_retained_source_changed','render_consumed_source_remaining']){
        await event(db,{properties:violation({contract_id:'ink.render_preservation',reason,render_mode:'automatic'})});
      }
      await worker(db);
      const rows=await queue(db,"rule_id in ('contract.ink.render_preservation.render_retained_source_changed','contract.ink.render_preservation.render_consumed_source_remaining')");
      assert.equal(rows.length,2);
      assert.equal(rows.find(r=>r.rule_id.endsWith('render_retained_source_changed')).severity,'critical');
      assert.equal(rows.find(r=>r.rule_id.endsWith('render_consumed_source_remaining')).severity,'medium');
      assert.ok(rows.every(r=>r.evidence_kind==='contract_violation'&&r.category==='render_transaction'));
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+2);
      for(const reason of ['render_retained_source_changed','render_consumed_source_remaining']){
        for(const content_matches of [true,'false',null])await event(db,{properties:violation({contract_id:'ink.render_preservation',reason,render_mode:'automatic',content_matches})});
      }
      await event(db,{properties:violation({contract_id:'ink.render_preservation',reason:'render_complete',outcome:'passed',expected_count:3,actual_count:3,content_matches:true,render_mode:'automatic'})});
      await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+2);
    });
    await t.test('settled automatic refusals become bounded friction without claiming ink loss or accuracy',async()=>{
      const reasons=['automatic_no_read','automatic_recognition_review','automatic_needs_space','automatic_placement_unavailable','automatic_unrepresented_ink','automatic_adjacent_writing'];
      for(const reason of reasons){
        const clientID=randomUUID(),properties=violation({contract_id:'ink.automatic_render_completion',operation:'render',outcome:'protected_rejection',reason,render_mode:'automatic',actual_count:2,duration_ms:3000});
        await event(db,{clientID,properties});await event(db,{clientID,properties});
      }
      await event(db,{properties:violation({contract_id:'ink.automatic_render_completion',operation:'render',outcome:'protected_rejection',reason:'automatic_needs_space',render_mode:'reviewed_automatic',actual_count:1,duration_ms:4000.125})});
      // Native elapsed-time Doubles can retain more than six fractional digits.
      // Valid typed durations must not silently disappear at the detector gate.
      for(const duration_ms of [3000.123456789,3010.2375000016764]){
        await event(db,{properties:violation({contract_id:'ink.automatic_render_completion',operation:'render',outcome:'protected_rejection',reason:'automatic_no_read',render_mode:'automatic',actual_count:1,duration_ms})});
      }
      await worker(db);await worker(db);
      const rows=await queue(db,"rule_id like 'contract.ink.automatic_render_completion.%'");
      assert.equal(rows.length,6);
      assert.ok(rows.every(r=>r.severity==='medium'&&r.evidence_kind==='friction'&&r.category==='recognition_workflow'));
      assert.equal(rows.reduce((n,r)=>n+r.event_count,0),9);
      assert.match(rows.find(r=>r.rule_id.endsWith('automatic_needs_space')).title,/placement collision/);
      const before=(await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n;
      const base=violation({contract_id:'ink.automatic_render_completion',operation:'render',outcome:'protected_rejection',reason:'automatic_no_read',render_mode:'automatic',actual_count:1,duration_ms:3000});
      const controls=[{outcome:'passed',reason:'automatic_render_complete'}, {outcome:'violated'}, {outcome:'unknown'},
        {render_mode:'manual'}, {render_mode:null}, {render_mode:'arbitrary'}, {operation:'save'},
        {actual_count:0},{actual_count:'1'},{actual_count:-1},{actual_count:1.5},{actual_count:null},{actual_count:1_000_000_000_001},
        {duration_ms:2999.999},{duration_ms:'3000'},{duration_ms:null},{duration_ms:-1},{duration_ms:86_400_001},
        {operation_id:'malformed'},{contract_version:2},
        ...['waiting','reading','restored_ink','render_repeat_review_required','render_unresolved','render_empty','baseline_changed'].map(reason=>({reason}))];
      for(const control of controls)await event(db,{properties:{...base,...control}});
      const missingDuration={...base};delete missingDuration.duration_ms;await event(db,{properties:missingDuration});
      await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before);
    });
    await t.test('authoring, keyboard, navigation and rendered geometry failures create the right tasks',async()=>{
      const cases=[
        ['ink.authoring_integrity','write','authoring_completed_source_missing','critical','contract_violation','data_preservation',{}],
        ['ink.live_canvas_visibility','write','authoring_canvas_invisible','high','contract_violation','ink_geometry_visibility',{expected_count:1,actual_count:0,source_stroke_count:2,duration_ms:500}],
        ['ink.authoring_responsiveness','write','authoring_callback_stalled','medium','friction','ink_geometry_visibility',{actual_count:3,duration_ms:100}],
        ['editor.keyboard_reachability','review','keyboard_focused_field_occluded','medium','friction','ink_geometry_visibility',{}],
        ['editor.keyboard_reachability','review','keyboard_action_unreachable','medium','friction','ink_geometry_visibility',{}],
        ['editor.navigation_response','navigate','navigation_offset_mismatch','high','contract_violation','ink_geometry_visibility',{}],
        ['editor.navigation_response','navigate','navigation_policy_mismatch','high','contract_violation','ink_geometry_visibility',{}],
        ['ink.render_geometry','render','render_prior_geometry_changed','high','contract_violation','ink_geometry_visibility',{}],
        ['ink.render_geometry','render','render_new_overlap','high','contract_violation','ink_geometry_visibility',{expected_count:0,actual_count:1}],
      ];
      for(const [contract_id,operation,reason,_severity,_evidence,_category,extra] of cases){
        const clientID=randomUUID(),properties=violation({contract_id,operation,reason,...extra});
        await event(db,{clientID,properties});await event(db,{clientID,properties});
      }
      await worker(db);await worker(db);
      for(const [contract_id,,reason,severity,evidence_kind,category] of cases){
        const [row]=await queue(db,`rule_id='contract.${contract_id}.${reason}'`);
        assert.equal(row.severity,severity);assert.equal(row.evidence_kind,evidence_kind);assert.equal(row.category,category);
        assert.equal(row.event_count,1);assert.equal(row.installation_count,1);assert.equal(row.session_count,1);
      }
    });
    await t.test('live-canvas visibility needs stable-duration and positive source evidence rather than an empty assertion',async()=>{
      const base=violation({contract_id:'ink.live_canvas_visibility',operation:'write',reason:'authoring_canvas_invisible',expected_count:1,actual_count:0,source_stroke_count:3,duration_ms:500});
      const before=(await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n;
      await event(db,{properties:base});
      await event(db,{properties:{...base,source_stroke_count:1,duration_ms:500.123456789}});
      await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+2);
      const controls=[{source_stroke_count:0},{source_stroke_count:-1},{source_stroke_count:'3'},{source_stroke_count:true},
        {source_stroke_count:1.5},{source_stroke_count:1_000_000_000_001},{source_stroke_count:null},
        {duration_ms:499.999},{duration_ms:'500'},{duration_ms:null},{duration_ms:-1},{duration_ms:86_400_001},
        {expected_count:0},{expected_count:2},{expected_count:'1'},{actual_count:1},{actual_count:'0'},
        {content_matches:true},{content_matches:'false'},{content_matches:null},{operation:'navigate'},
        {outcome:'passed',reason:'authoring_canvas_visible'},{outcome:'unknown'},{outcome:'protected_rejection'},
        {operation_id:'malformed'},{contract_version:2}];
      for(const control of controls)await event(db,{properties:{...base,...control}});
      const noSource={...base};delete noSource.source_stroke_count;await event(db,{properties:noSource});
      await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+2);
      const [row]=await queue(db,"rule_id='contract.ink.live_canvas_visibility.authoring_canvas_invisible'");
      assert.equal(row.severity,'high');assert.equal(row.evidence_kind,'contract_violation');assert.equal(row.category,'ink_geometry_visibility');
    });
    await t.test('authoring responsiveness uses typed callback-count and maximum-duration boundaries',async()=>{
      const base=violation({contract_id:'ink.authoring_responsiveness',operation:'write',reason:'authoring_callback_stalled'});
      const before=(await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n;
      for(const [actual_count,duration_ms] of [[3,100],[1,500],[1,500.123456789],[3,100.2375000016764]]){
        await event(db,{properties:{...base,actual_count,duration_ms}});
      }
      await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+4);
      const controls=[{actual_count:3,duration_ms:99.999},{actual_count:2,duration_ms:499.999},
        {actual_count:0,duration_ms:9000},{actual_count:-1,duration_ms:9000},{actual_count:'3',duration_ms:9000},
        {actual_count:1.5,duration_ms:9000},{actual_count:1_000_000_000_001,duration_ms:9000},
        {actual_count:3,duration_ms:'100'},{actual_count:3,duration_ms:-1},{actual_count:3,duration_ms:86_400_001},
        {actual_count:3,duration_ms:null},{actual_count:null,duration_ms:500}];
      for(const control of controls)await event(db,{properties:{...base,...control}});
      await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before+4);
    });
    await t.test('experience contracts reject unsupported assertions and preserve successful or incomparable controls',async()=>{
      const cases=[
        {contract_id:'ink.authoring_integrity',operation:'write',reason:'authoring_completed_source_missing',pass:'authoring_source_preserved'},
        {contract_id:'ink.authoring_responsiveness',operation:'write',reason:'authoring_callback_stalled',actual_count:3,duration_ms:100,pass:'authoring_responsive'},
        {contract_id:'editor.keyboard_reachability',operation:'review',reason:'keyboard_focused_field_occluded',pass:'keyboard_controls_reachable'},
        {contract_id:'editor.navigation_response',operation:'navigate',reason:'navigation_offset_mismatch',pass:'navigation_response_matches'},
        {contract_id:'ink.render_geometry',operation:'render',reason:'render_prior_geometry_changed',pass:'render_geometry_preserved'},
      ];
      const before=(await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n;
      for(const {pass,...fields} of cases){
        const base=violation(fields);
        for(const extra of [{outcome:'passed',reason:pass},{outcome:'unknown'},{outcome:'protected_rejection'},
          {contract_version:2},{operation_id:'malformed'},{operation:'save'},{reason:'readback_mismatch'}]){
          await event(db,{properties:{...base,...extra}});
        }
        if(fields.contract_id!=='ink.authoring_responsiveness'){
          for(const content_matches of [true,'false',null])await event(db,{properties:{...base,content_matches}});
          const missing={...base};delete missing.content_matches;await event(db,{properties:missing});
        }
      }
      for(const contract_id of ['ink.authoring_integrity','editor.keyboard_reachability','editor.navigation_response','ink.render_geometry']){
        const fields=cases.find(c=>c.contract_id===contract_id);const {pass,...base}=fields;
        for(const extra of [{expected_count:0,actual_count:0},{expected_count:4,actual_count:4},{expected_count:1,actual_count:2},
          {expected_count:'4'},{actual_count:'2'},{expected_count:-1},{actual_count:-1},{expected_count:4.5},
          {actual_count:1.5},{expected_count:1_000_000_000_001},{expected_count:null},{actual_count:null}]){
          await event(db,{properties:violation({...base,...extra})});
        }
        for(const field of ['expected_count','actual_count']){
          const missing=violation(base);delete missing[field];await event(db,{properties:missing});
        }
      }
      for(const extra of [{expected_count:1,actual_count:2},{expected_count:0,actual_count:0},{expected_count:0,actual_count:'1'},
        {expected_count:0,actual_count:1,content_matches:true},{expected_count:null,actual_count:1}]){
        await event(db,{properties:violation({contract_id:'ink.render_geometry',operation:'render',reason:'render_new_overlap',...extra})});
      }
      await worker(db);
      assert.equal((await db.rows('select count(*)::int as n from private.telemetry_incident_events'))[0].n,before);
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


test('automatic-contract migration upgrades existing tasks without changing private access or worker registration',async()=>{
  const db=await cluster();let success=false;
  try{
    await setup(db,{automaticContracts:false});
    await event(db,{properties:violation({contract_id:'chart.save',reason:'save_failed'})});await worker(db);
    const before=await queue(db);
    const [aclBefore]=await db.rows("select has_schema_privilege('service_role','private','usage') as service_schema,has_function_privilege('authenticated','private.classify_telemetry_event(public.telemetry_events)','execute') as client_classifier");
    const jobsBefore=await db.rows('select * from cron.job');
    await applyAutomaticContracts(db);
    assert.deepEqual(await queue(db),before);
    assert.deepEqual(await db.rows('select * from cron.job'),jobsBefore);
    const [aclAfter]=await db.rows("select has_schema_privilege('service_role','private','usage') as service_schema,has_function_privilege('authenticated','private.classify_telemetry_event(public.telemetry_events)','execute') as client_classifier");
    assert.deepEqual(aclAfter,aclBefore);
    assert.deepEqual(aclAfter,{service_schema:false,client_classifier:false});
    await event(db,{properties:violation({contract_id:'ink.automatic_render_completion',operation:'render',outcome:'protected_rejection',reason:'automatic_needs_space',render_mode:'automatic',actual_count:1,duration_ms:3000})});
    await worker(db);
    const [item]=await queue(db,"rule_id='contract.ink.automatic_render_completion.automatic_needs_space'");
    assert.equal(item.evidence_kind,'friction');assert.equal(item.event_count,1);
    const [fn]=await db.rows("select p.prosecdef,array_to_string(p.proconfig,',') as settings from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='classify_telemetry_event'");
    assert.equal(fn.prosecdef,false);assert.equal(fn.settings,'search_path=""');
    success=true;
  }finally{await db.stop(success);}
});


test('experience-contract migration upgrades the deployed automatic pipeline without rewriting task state',async()=>{
  const db=await cluster();let success=false;
  try{
    await setup(db,{experienceContracts:false});
    await event(db,{properties:violation({contract_id:'ink.automatic_render_completion',operation:'render',outcome:'protected_rejection',reason:'automatic_needs_space',render_mode:'automatic',actual_count:1,duration_ms:3000})});
    await worker(db);
    const before=await queue(db),jobsBefore=await db.rows('select * from cron.job');
    const [accessBefore]=await db.rows("select has_schema_privilege('service_role','private','usage') as service_schema,has_function_privilege('authenticated','private.classify_telemetry_event(public.telemetry_events)','execute') as client_classifier");
    await applyExperienceContracts(db);
    assert.deepEqual(await queue(db),before);assert.deepEqual(await db.rows('select * from cron.job'),jobsBefore);
    const [accessAfter]=await db.rows("select has_schema_privilege('service_role','private','usage') as service_schema,has_function_privilege('authenticated','private.classify_telemetry_event(public.telemetry_events)','execute') as client_classifier");
    assert.deepEqual(accessAfter,accessBefore);assert.deepEqual(accessAfter,{service_schema:false,client_classifier:false});
    await event(db,{properties:violation({contract_id:'editor.navigation_response',operation:'navigate',reason:'navigation_policy_mismatch'})});
    await worker(db);const [row]=await queue(db,"rule_id='contract.editor.navigation_response.navigation_policy_mismatch'");
    assert.equal(row.event_count,1);assert.equal(row.severity,'high');
    const [fn]=await db.rows("select p.prosecdef,array_to_string(p.proconfig,',') as settings from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='classify_telemetry_event'");
    assert.equal(fn.prosecdef,false);assert.equal(fn.settings,'search_path=""');
    success=true;
  }finally{await db.stop(success);}
});
