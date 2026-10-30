// Replays an already anonymized event export into an isolated local PostgreSQL
// cluster. Does not connect to production or create/update remote tasks.
// ICHART_TELEMETRY_REPLAY_INPUT and OUTPUT must be absolute local paths.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { cluster, setup, event } from './lib/telemetry_pipeline_fixture.mjs';

const input=process.env.ICHART_TELEMETRY_REPLAY_INPUT,output=process.env.ICHART_TELEMETRY_REPLAY_OUTPUT;
assert.ok(typeof input==='string'&&isAbsolute(input),'Set absolute ICHART_TELEMETRY_REPLAY_INPUT.');
assert.ok(typeof output==='string'&&isAbsolute(output)&&input!==output,'Set a distinct absolute ICHART_TELEMETRY_REPLAY_OUTPUT.');
const text=await readFile(input,'utf8');assert.ok(Buffer.byteLength(text)<=20_000_000,'Replay input exceeds 20 MB.');
const rows=JSON.parse(text);assert.ok(Array.isArray(rows)&&rows.length<=25_000,'Replay requires an array of at most 25,000 events.');
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const fields=new Set(['client_event_id','event_name','installation_id','session_id','occurred_at','received_at','app_version','build_number','platform','properties']);
const properties=new Set(['error_code','decision','source','build_source','contract_id','contract_version','operation_id','outcome','reason',
  'expected_count','actual_count','expected_point_count','actual_point_count','expected_bytes','actual_bytes','content_matches','scope','duration_ms','layout_style']);
const names=new Set(['app.launched','feature.contract_checked','cloud.push_failed','cloud.restore_failed','chord.rendered_correction_applied']);
const literal=value=>`'${String(value).replaceAll("'","''")}'`;
for(const row of rows){
  assert.ok(row&&typeof row==='object'&&!Array.isArray(row));
  assert.ok(Object.keys(row).every(key=>fields.has(key)),'Unexpected event field: export only minimal anonymized rows.');
  for(const key of ['client_event_id','installation_id','session_id'])assert.ok(uuid.test(row[key]),`Invalid ${key}.`);
  assert.ok(names.has(row.event_name));assert.ok(['iPadOS','iOS'].includes(row.platform));
  assert.ok(typeof row.app_version==='string'&&/^[A-Za-z0-9._-]{1,32}$/.test(row.app_version));
  assert.ok(typeof row.build_number==='string'&&/^[A-Za-z0-9._-]{1,32}$/.test(row.build_number));
  for(const key of ['occurred_at','received_at'])assert.ok(typeof row[key]==='string'&&Number.isFinite(Date.parse(row[key])),`Invalid ${key}.`);
  assert.ok(row.properties&&typeof row.properties==='object'&&!Array.isArray(row.properties));
  assert.ok(Object.keys(row.properties).every(key=>properties.has(key)),'Unexpected property: do not include chart/chord content or raw diagnostics.');
  for(const value of Object.values(row.properties))assert.ok(value===null||typeof value==='boolean'||(typeof value==='number'&&Number.isFinite(value))||(typeof value==='string'&&value.length<=160),'Properties must be bounded scalars.');
}
const db=await cluster();let success=false;
try{
  await setup(db);
  for(const row of rows)await event(db,{name:row.event_name,clientID:row.client_event_id,install:row.installation_id,
    sessionID:row.session_id,properties:row.properties,build:row.build_number,appVersion:row.app_version,platform:row.platform,
    occurredSQL:literal(new Date(row.occurred_at).toISOString()),receivedSQL:literal(new Date(row.received_at).toISOString())});
  for(let round=0;round<101;round++){
    const [health]=await db.rows('select * from private.telemetry_pipeline_health');
    if(Number(health.pending_count)===0)break;
    await db.sql('select private.process_telemetry_evaluations(250);');
    assert.ok(round<100,'Replay exceeded bounded evaluator iterations.');
  }
  const [health]=await db.rows('select * from private.telemetry_pipeline_health');
  assert.equal(Number(health.pending_count),0,'Replay left pending evaluations.');
  assert.equal(Number(health.dead_letter_count),0,'Replay encountered evaluation failures.');
  const incidents=await db.rows('select * from private.telemetry_work_queue order by priority_rank,installation_count desc,event_count desc,rule_id,build_source');
  const replay_evidence=await db.rows(`select distinct e.id as raw_event_id,e.client_event_id
    from private.telemetry_incident_events d join public.telemetry_events e on e.id=d.raw_event_id order by e.id`);
  const snapshot={generated_at:new Date().toISOString(),
    replay_context:{mode:'local_replay',anonymized:true},
    health,incidents,replay_evidence};
  await writeFile(output,`${JSON.stringify(snapshot,null,2)}\n`,{mode:0o600,flag:'wx'});
  console.log(JSON.stringify({mode:'isolated-local-replay',input_events:rows.length,incidents:incidents.length,output}));
  success=true;
}finally{await db.stop(success);}
