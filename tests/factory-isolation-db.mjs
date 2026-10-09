// PostgreSQL WASM in memory ONLY. Quality/compile/Auth schemas below are test fixtures.
// No production URL, credentials, network calls or real renderer exist in this test.
import {PGlite} from '../artifacts/factory-db-test/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const native=process.env.FACTORY_TEST_NATIVE==='1';
let pool;
if(native){
 const {default:pg}=await import('../artifacts/factory-db-test/node_modules/pg/lib/index.js');
 assert.match(process.env.FACTORY_TEST_PORT||'',/^\d+$/);
 pool=new pg.Pool({host:'127.0.0.1',port:Number(process.env.FACTORY_TEST_PORT),database:'postgres',user:'factory_test',max:36});
}
const main=native?await pool.connect():null;
const db=native?{exec:q=>main.query(q),query:q=>main.query(q),close:async()=>{main.release();await pool.end();}}:new PGlite();
process.on('uncaughtException',async e=>{console.error(e.message,e.cause?.message||'',e.where||'',e.position||'');await db.close();process.exitCode=1;});
const actor='11111111-1111-4111-8111-111111111111', run='22222222-2222-4222-8222-222222222222', command='33333333-3333-4333-8333-333333333333', token='44444444-4444-4444-8444-444444444444', session='55555555-5555-4555-8555-555555555555';
await db.exec(`
create schema sc_internal; create schema auth;
create role anon; create role authenticated; create role service_role;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql as $$select jsonb_build_object('session_id',current_setting('test.session',true))$$;
create table auth.users(id uuid primary key,raw_app_meta_data jsonb);
create table auth.sessions(id uuid primary key,user_id uuid);
create table sc_internal.v5_commands(command_id uuid primary key,actor_user_id uuid,idempotency_key text,request_hash text,command_type text,mode text,target jsonb,payload jsonb,confirmation_intent text,status text,claim_token uuid,lease_version bigint,claim_expires_at timestamptz,result jsonb,updated_at timestamptz);
create table public.sc_creative_runs(id uuid primary key,status text,created_at timestamptz);
create table public.sc_creative_stage_outputs(run_id uuid,stage text,attempt integer,validation_status text,schema_version text);
create table public.sc_content_jobs(id uuid primary key default gen_random_uuid(),content_plan jsonb,qa jsonb);
create table public.sc_agent_config(id text primary key,config jsonb);
create table public.sc_system_health(component text primary key,status text,details jsonb);
create table fixture(compiled jsonb,route text,preflight boolean,fail_after_insert boolean,expire_after_insert boolean,second_insert boolean);
create function public.sc_v5_command_request_hash_v1(text,jsonb,jsonb,text,text) returns text language sql as $$select encode(sha256(convert_to(jsonb_build_array($1,$2,$3,$4,$5)::text,'UTF8')),'hex')$$;
create function public.sc_security_operation_gate_v1(text) returns jsonb language sql as $$select jsonb_build_object('allowed',config->$1) from public.sc_agent_config where id='solar_connects_v1'$$;
create function public.sc_creative_compile_carousel_v1(uuid) returns jsonb language sql as $$select compiled from fixture$$;
create function public.sc_creative_render_preflight_v1(uuid) returns jsonb language sql as $$select jsonb_build_object('ok',preflight) from fixture$$;
create function public.sc_quality_factory_hook_v2(uuid,integer) returns jsonb language sql as $$select jsonb_build_object('route',route) from fixture$$;
create function public.sc_quality_factory_production_v2(uuid,jsonb,integer,boolean) returns jsonb language plpgsql as $$declare j uuid; begin
insert into public.sc_content_jobs(content_plan,qa) values(jsonb_build_object('idempotency_key','quality-v2-shadow:factory_run_'||replace($1::text,'-','')),'{}') returning id into j;
update public.sc_content_jobs set qa=qa||jsonb_build_object('creative_run_id',$1) where id=j;
if (select second_insert from fixture) then insert into public.sc_content_jobs(content_plan,qa) values(jsonb_build_object('creative_run_id',$1),'{}'); end if;
if (select expire_after_insert from fixture) then update sc_internal.v5_commands set claim_expires_at=clock_timestamp()-interval '1 second'; end if;
if (select fail_after_insert from fixture) then return '{"ok":false}'; end if;
return jsonb_build_object('ok',true,'job_id',j,'state','V2_DRAFT_BLOCKED');end$$;
alter function public.sc_creative_compile_carousel_v1(uuid) set search_path=public;
alter function public.sc_creative_render_preflight_v1(uuid) set search_path=public;
alter function public.sc_quality_factory_hook_v2(uuid,integer) set search_path=public;
alter function public.sc_quality_factory_production_v2(uuid,jsonb,integer,boolean) set search_path=public;
`);
await db.exec(fs.readFileSync('supabase/candidate/factory-isolation.sql','utf8'));
async function reset(){
 await db.exec(`truncate sc_internal.factory_permits,sc_internal.v5_commands,public.sc_creative_runs,public.sc_creative_stage_outputs,public.sc_content_jobs,auth.users,auth.sessions,public.sc_agent_config,public.sc_system_health,fixture;
 select set_config('test.actor','${actor}',false),set_config('test.session','${session}',false);
 insert into auth.users values('${actor}','{"command_center":true,"solar_role":"v5_operator"}');
 insert into auth.sessions values('${session}','${actor}');
 insert into sc_creative_runs values('${run}','APPROVED',clock_timestamp());
 insert into sc_creative_stage_outputs values('${run}','RADAR',1,'VALID','radar-v1'),('${run}','EDITOR',1,'VALID','editor-v2'),('${run}','DIRECTOR',1,'VALID','director-v2');
 insert into sc_agent_config values('solar_connects_v1','{"FACTORY":true,"PUBLISHER":false,"META_DIRECT":false,"EXTERNAL_WRITE":false}');
 insert into sc_system_health values('solar_quality_v2_production_flags','TEST_AUTHORIZED','{"enabled":true,"formats":{"image":{"kill_switch":false}}}'),('solar_quality_v2_first_slot','ARMED','{}');
 insert into fixture values('{"ok":true,"format":"image","content_plan":{"creative_run_id":"${run}","title":"TEST ONLY"}}','V2',true,false,false,false);
 insert into sc_internal.v5_commands values('${command}','${actor}','test_idempotency',null,'factory.start','EXECUTE','{"agent":"FACTORY","job_id":null}',
 jsonb_build_object('creative_run_id','${run}','compiled_plan_sha256',(select sc_internal.factory_plan_hash(compiled) from fixture),'plan_hash_algorithm','sha256-pg-jsonb-v1','max_jobs',1,'stop_at','READY','additional_paid_cost_usd',0),'REAL_EXECUTION','CLAIMED','${token}',1,clock_timestamp()+interval '5 minutes',null,clock_timestamp());
 update sc_internal.v5_commands set request_hash=sc_v5_command_request_hash_v1(command_type,target,payload,confirmation_intent,mode);
 insert into sc_internal.factory_permits(command_id,creative_run_id,actor_user_id,idempotency_key,request_hash,compiled_plan,plan_sha256,quality_input,quality_slot,claim_token,lease_version,expires_at)
 select command_id,'${run}',actor_user_id,idempotency_key,request_hash,compiled,sc_internal.factory_plan_hash(compiled),'{}',1,claim_token,lease_version,claim_expires_at from sc_internal.v5_commands cross join fixture;`);
}
const call=`select sc_internal.factory_materialize('${command}','${token}',1,(select plan_sha256 from sc_internal.factory_permits),'{}',1) r`;
const report=[];
async function counts(){return (await db.query('select (select count(*)::int from sc_content_jobs) jobs,(select count(*)::int from sc_internal.factory_permits where consumed_at is not null) consumed')).rows[0]}
async function reject(name,setup,pattern,query=call){await reset();if(setup)await db.exec(setup);await assert.rejects(db.query(query),pattern);assert.deepEqual(await counts(),{jobs:0,consumed:0});report.push({name,status:'PASS'});}
await reject('global FACTORY OFF',`update sc_agent_config set config=jsonb_set(config,'{FACTORY}','false')`,/FACTORY_OFF/);
await reject('Quality freeze despite globally enabled fixture',`update sc_system_health set status='STAGE1_FROZEN_OBSERVATION' where component='solar_quality_v2_production_flags'`,/QUALITY_V2_FROZEN/);
await reject('format kill switch',`update sc_system_health set details=jsonb_set(details,'{formats,image,kill_switch}','true') where component='solar_quality_v2_production_flags'`,/QUALITY_V2_FROZEN/);
await reject('no V1 fallback',`update fixture set route='V1'`,/QUALITY_V2_REQUIRED/);
await reject('revocation',`update sc_internal.factory_permits set revoked_at=clock_timestamp()`,/PERMIT_REVOKED/);
await reject('session revoked',`delete from auth.sessions`,/SESSION_REVOKED/);
await reject('insufficient permissions',`update auth.users set raw_app_meta_data='{}'`,/OPERATOR_REQUIRED/);
await reject('wrong actor',`select set_config('test.actor','${token}',false)`,/ACTOR_REQUIRED/);
await reject('expired lease',`update sc_internal.v5_commands set claim_expires_at=clock_timestamp()-interval '1 second'`,/LEASE_INVALID/);
await reject('changed lease version',`update sc_internal.v5_commands set lease_version=2`,/LEASE_INVALID/);
await reject('changed claim token',`update sc_internal.v5_commands set claim_token='${session}'`,/LEASE_INVALID/);
await reject('expired permit',`update sc_internal.factory_permits set expires_at=clock_timestamp()-interval '1 second'`,/LEASE_INVALID/);
await reject('quality inputs changed','',/QUALITY_BINDING_CONFLICT/,call.replace("'{}',1)","'{\"changed\":true}',1)"));
await reject('changed request payload',`update sc_internal.v5_commands set payload=payload||'{"stop_at":"PUBLISH"}'`,/COMMAND_BINDING_CONFLICT/);
await reject('compiled plan changed',`update fixture set compiled=compiled||'{"topic":"CHANGED"}'`,/PLAN_HASH_CONFLICT/);
await reject('invalid latest RADAR',`insert into sc_creative_stage_outputs values('${run}','RADAR',2,'INVALID','radar-v1')`,/LATEST_STAGE_INVALID/);
await reject('preflight rejected',`update fixture set preflight=false`,/PREFLIGHT_REJECTED/);
await reject('failure after insert rolls back job and permit',`update fixture set fail_after_insert=true`,/QUALITY_MATERIALIZATION_REJECTED/);
await reject('lease expires after insert rolls back',`update fixture set expire_after_insert=true`,/LEASE_INVALID/);
await reject('second insert in same transaction rejected',`update fixture set second_insert=true`,/TRANSACTION_PERMIT_REQUIRED/);
await reject('direct legacy insert has no transaction permit','',/TRANSACTION_PERMIT_REQUIRED/,`insert into sc_content_jobs(content_plan,qa) values('{"creative_run_id":"${run}"}','{}')`);
await reset();await db.query(`insert into sc_content_jobs(content_plan,qa) values('{}','{}')`);assert.deepEqual(await counts(),{jobs:1,consumed:0});report.push({name:'unreserved legacy insert remains allowed',status:'PASS'});
await reset();
const results=await Promise.all(Array.from({length:32},async()=>{
 if(!native)return db.query(call);
 const conn=await pool.connect();try{
 await conn.query(`select set_config('test.actor','${actor}',false),set_config('test.session','${session}',false)`);
 return await conn.query(call);
 }finally{conn.release();}
}));
assert.equal(results.filter(x=>x.rows[0].r.state==='V2_DRAFT_BLOCKED').length,1);
assert.equal(results.filter(x=>x.rows[0].r.state==='DUPLICATE').length,31);
assert.deepEqual(await counts(),{jobs:1,consumed:1});report.push({name:native?'32 independent concurrent connections: one job and 31 replays':'32 queued requests (single session)',status:'PASS'});
assert.deepEqual((await db.query('select qa from sc_content_jobs')).rows[0].qa.publish_blocked,true);
await reset();await db.exec('begin');await db.query(call);await db.exec('rollback');assert.deepEqual(await counts(),{jobs:0,consumed:0});report.push({name:'outer transaction rollback restores permit and ledger',status:'PASS'});
await reset();await db.exec('set role authenticated');await assert.rejects(db.query(call),/permission denied/);await db.exec('reset role');report.push({name:'candidate executor not accessible to authenticated role',status:'PASS'});
await reset();await db.query(call);await assert.rejects(db.query(`update sc_content_jobs set content_plan=content_plan||'{"creative_run_id":"${actor}"}'`),/CREATIVE_RUN_IMMUTABLE/);report.push({name:'run identity cannot be reassigned after materialization',status:'PASS'});
await reset();await assert.rejects(db.query(`insert into sc_internal.factory_permits select * from sc_internal.factory_permits`),/duplicate key/);report.push({name:'permit uniqueness rejects duplicate authorization',status:'PASS'});
await reset();await db.exec(`insert into sc_internal.v5_commands select '${session}',actor_user_id,'other_idempotency',request_hash,command_type,mode,target,payload,confirmation_intent,status,claim_token,lease_version,claim_expires_at,result,updated_at from sc_internal.v5_commands`);
await assert.rejects(db.query(`insert into sc_internal.factory_permits(command_id,creative_run_id,actor_user_id,idempotency_key,request_hash,compiled_plan,plan_sha256,quality_input,quality_slot,claim_token,lease_version,expires_at) select '${session}',creative_run_id,actor_user_id,'other_idempotency',request_hash,compiled_plan,plan_sha256,quality_input,quality_slot,claim_token,lease_version,expires_at from sc_internal.factory_permits`),/factory_permits_creative_run_id_key/);report.push({name:'different command cannot authorize the same creative run',status:'PASS'});
await reset();await db.exec('delete from sc_internal.factory_permits');
await assert.rejects(db.query(`select sc_internal.factory_authorize('${command}','${token}',1,'wrong','{}',1)`),/EXPLICIT_CONFIRMATION_REQUIRED/);
assert.equal((await db.query('select count(*)::int n from sc_internal.factory_permits')).rows[0].n,0);
const authorize=`select sc_internal.factory_authorize('${command}','${token}',1,'REAL:'||command_id||':'||idempotency_key||':factory.start:'||(payload->>'creative_run_id')||':'||(payload->>'compiled_plan_sha256'),'{}',1) from sc_internal.v5_commands`;
await db.query(authorize);await db.query(call);assert.deepEqual(await counts(),{jobs:1,consumed:1});report.push({name:'explicit four-part confirmation provisions exactly one bound permit',status:'PASS'});
await reset();await db.exec(`delete from sc_internal.factory_permits; update sc_agent_config set config=jsonb_set(config,'{FACTORY}','false')`);
await assert.rejects(db.query(authorize),/FACTORY_OFF/);assert.equal((await db.query('select count(*)::int n from sc_internal.factory_permits')).rows[0].n,0);report.push({name:'authorization under closed gate rolls back its permit',status:'PASS'});
if(native){
 async function blockedRace(name,mutation,expected){
 await reset();const blocker=await pool.connect(),waiter=await pool.connect();
 try{
 await blocker.query('begin');await blocker.query(mutation);
 await waiter.query(`select set_config('test.actor','${actor}',false),set_config('test.session','${session}',false)`);
 const pid=(await waiter.query('select pg_backend_pid() pid')).rows[0].pid;
 const pending=waiter.query(call).then(()=>({ok:true}),error=>({error}));
 let waiting=false;
 for(let i=0;i<100;i++){
 const s=(await db.query(`select wait_event_type from pg_stat_activity where pid=${pid}`)).rows[0];
 if(s?.wait_event_type==='Lock'){waiting=true;break;}
 await new Promise(r=>setTimeout(r,10));
 }
 assert.equal(waiting,true,'must prove actual lock contention');
 await blocker.query('commit');const outcome=await pending;assert.match(outcome.error?.message||'',expected);
 assert.deepEqual(await counts(),{jobs:0,consumed:0});report.push({name,status:'PASS'});
 }finally{await blocker.query('rollback');blocker.release();waiter.release();}
 }
 await blockedRace('revocation wins while executor waits',`update sc_internal.factory_permits set revoked_at=clock_timestamp()`,/PERMIT_REVOKED/);
 await blockedRace('emergency FACTORY closure wins while executor waits',`update sc_agent_config set config=jsonb_set(config,'{FACTORY}','false')`,/FACTORY_OFF/);
 await blockedRace('lease expiry rechecked after waiting',`update sc_internal.v5_commands set claim_expires_at=clock_timestamp()-interval '1 second'`,/LEASE_INVALID/);
}
const out={engine:native?'PostgreSQL 18.4 local, isolated cluster':'PGlite 0.3.14 in-memory',tests:report,multi_session_races:native?'PASS: 32 independent connections':'NOT TESTED: single connection',production_connections:0,production_writes:0};
fs.writeFileSync('artifacts/factory-isolation-results.json',JSON.stringify(out,null,2));console.log(JSON.stringify(out,null,2));await db.close();
