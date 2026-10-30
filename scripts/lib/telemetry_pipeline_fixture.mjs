// Native PostgreSQL integration tests for the actual telemetry migrations.
// Uses a private synthetic Unix-socket cluster; no customer URL/credentials/TCP.
// cron.schedule is a registration adapter, not a daemon or real Cron run.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomInt, randomUUID } from 'node:crypto';
import { access, chmod, mkdtemp, readFile, rm } from 'node:fs/promises';
import { constants } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { tmpdir } from 'node:os';

const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>!key.startsWith('PG')&&key!=='PSQLRC'));
Object.assign(env,{PGCONNECT_TIMEOUT:'5',LC_ALL:'C',TZ:'UTC'});
async function program(binary,args,timeout=30_000){
  return new Promise((resolve,reject)=>{
    const child=spawn(binary,args,{env,stdio:['ignore','pipe','pipe']});let out='';
    child.stdout.on('data',data=>{out+=data;});child.stderr.on('data',data=>{out+=data;});
    const timer=setTimeout(()=>child.kill('SIGKILL'),timeout);
    child.on('error',error=>{clearTimeout(timer);reject(error);});
    child.on('close',(code,signal)=>{clearTimeout(timer);code===0?resolve(out.trim()):reject(new Error(`${binary} (${signal??code}): ${out}`));});
  });
}
const lit=value=>`'${String(value).replaceAll("'","''")}'`;
export async function cluster(){
  const bin=process.env.ICHART_POSTGRES_BIN||await program('pg_config',['--bindir']);
  assert.ok(isAbsolute(bin));
  for(const binary of ['initdb','pg_ctl','psql'])await access(join(bin,binary),constants.X_OK);
  const version=await program(join(bin,'psql'),['--version']);
  assert.ok(Number(version.match(/PostgreSQL\) (\d+)/)?.[1])>=16,version);
  const parent=process.platform==='darwin'?'/private/tmp':tmpdir();
  const root=await mkdtemp(join(parent,'ichart-telemetry-test-'));await chmod(root,0o700);
  const data=join(root,'data'),log=join(root,'postgres.log'),port=String(randomInt(20_000,60_000));
  let started=false;
  async function stop(success){
    if(started)await program(join(bin,'pg_ctl'),['-D',data,'-m','fast','-t','15','-w','stop'],20_000);
    if(success){assert.ok(root.startsWith(join(parent,'ichart-telemetry-test-'))&&root!==parent);await rm(root,{recursive:true});}
    else console.error(`Failed synthetic fixture retained (server stopped): ${root}`);
  }
  try{
    await program(join(bin,'initdb'),['-D',data,'-U','ichart_test_owner','--auth-local=trust','--auth-host=reject','--no-locale','--encoding=UTF8']);
    await program(join(bin,'pg_ctl'),['-D',data,'-l',log,'-t','15','-w','-o',
      `-c listen_addresses='' -c unix_socket_directories='${root}' -c unix_socket_permissions=0700 -p ${port}`,'start'],20_000);started=true;
  }catch(error){await stop(false);throw error;}
  const args=['-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-h',root,'-p',port,'-U','ichart_test_owner','-d','postgres'];
  return{stop,sql:sql=>program(join(bin,'psql'),[...args,'-c',sql]),
    async rows(sql){const out=await program(join(bin,'psql'),[...args,'-c',`select coalesce(json_agg(result),'[]'::json) from (${sql}) result;`]);return JSON.parse(out);}};
}
const owner='11000000-0000-4000-8000-000000000001';
const installation='22000000-0000-4000-8000-000000000001';
const session='33000000-0000-4000-8000-000000000001';
export async function setup(db){
  await db.sql(`create role anon nologin;create role authenticated nologin;create role service_role nologin bypassrls;
    create schema auth;create table auth.users(id uuid primary key);insert into auth.users values('${owner}');
    create schema cron;create table cron.job(jobname text primary key,schedule text,command text);
    create function cron.schedule(text,text,text) returns bigint language plpgsql as $$begin
      insert into cron.job values($1,$2,$3) on conflict(jobname) do update set schedule=$2,command=$3;return 1;end;$$;`);
  for(const name of ['20260813192919_telemetry_foundation.sql','20261009230003_telemetry_privacy_retention_closeout.sql',
    '20261030151740_telemetry_feature_contract_pipeline.sql']){
    if(name==='20261030151740_telemetry_feature_contract_pipeline.sql'){
      // The recognition consent ledger intentionally removed this namespace
      // permission in production. Reproduce that boundary without importing or
      // changing any research data/schema into this synthetic telemetry fixture.
      await db.sql('revoke usage on schema private from service_role;');
    }
    await db.sql(await readFile(new URL(`../../supabase/migrations/${name}`,import.meta.url),'utf8'));
  }
}
export async function event(db,{name='feature.contract_checked',properties={},clientID=randomUUID(),
  install=installation,sessionID=session,ownerID=null,build='100',appVersion='test',platform='iPadOS',occurredSQL='now()',receivedSQL='now()',asServiceRole=false}={}){
  const insert=`insert into public.telemetry_events(client_event_id,owner_id,installation_id,session_id,event_name,
    occurred_at,received_at,app_version,build_number,platform,os_version,device_model,locale_language,time_zone_offset_minutes,properties)
    values(${lit(clientID)},${ownerID?lit(ownerID):'null'},${lit(install)},${lit(sessionID)},${lit(name)},
    ${occurredSQL},${receivedSQL},${lit(appVersion)},${lit(build)},${lit(platform)},'test','synthetic','en',0,${lit(JSON.stringify(properties))}::jsonb)
    on conflict(client_event_id) do nothing returning id;`;
  return db.sql(asServiceRole?`set role service_role;${insert}reset role;`:insert);
}
