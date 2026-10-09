// Replays exported SQL, constraints, RLS, ACLs and triggers on loopback PostgreSQL.
// Synthetic rows only. This is NOT a Supabase Auth/Edge/Realtime runtime.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from '../artifacts/factory-db-test/node_modules/pg/lib/index.js';
assert.equal(process.env.FACTORY_TEST_NATIVE,'1');
const db=new pg.Client({host:'127.0.0.1',port:Number(process.env.FACTORY_TEST_PORT),user:'factory_test',database:'postgres'});
await db.connect();
const snapshot=JSON.parse(fs.readFileSync('supabase/staging/real-contracts.json'));
const privileges=JSON.parse(fs.readFileSync('supabase/staging/real-privileges.json'));
const q=sql=>db.query(sql),ident=s=>'"'+s.replaceAll('"','""')+'"';
const report=[];
try{
 await q('create schema sc_internal; create schema extensions; create schema auth; create extension pgcrypto with schema extensions; set check_function_bodies=off;');
 for(const r of privileges.roles)await q(`create role ${ident(r.name)} ${r.inherit?'inherit':'noinherit'} ${r.bypassrls?'bypassrls':'nobypassrls'} nologin`);
 await q('grant usage on schema public,sc_internal,extensions,auth to postgres; grant usage on schema public,extensions to anon,authenticated,service_role;');
 for(const t of snapshot.tables){
  for(const c of t.columns){const seq=c.default?.match(/nextval\('([^']+)'::regclass\)/)?.[1];if(seq)await q(`create sequence ${seq}`);}
  const fields=t.columns.map(c=>`${ident(c.name)} ${c.type}${c.identity?` generated ${c.identity==='a'?'always':'by default'} as identity`:c.default?' default '+c.default:''}${c.notnull?' not null':''}`);
  await q(`create table ${t.nspname}.${t.relname}(${fields.join(',')}); alter table ${t.nspname}.${t.relname} owner to postgres;`);
 }
 for(const t of snapshot.tables){
  const table=t.nspname+'.'+t.relname;
  for(const c of t.constraints||[])await q(`alter table ${table} add constraint ${ident(c.name)} ${c.def}`);
  for(const idx of t.indexes||[])await q(idx.replace(/^CREATE (UNIQUE )?INDEX /,'CREATE $1INDEX IF NOT EXISTS '));
  if(t.relrowsecurity)await q(`alter table ${table} enable row level security`);
  if(t.relforcerowsecurity)await q(`alter table ${table} force row level security`);
  assert.equal(t.policies,null,'new policies require explicit replay support');
  for(const acl of t.relacl.slice(1,-1).split(',')){
   const [role,permissions]=acl.split('=');const flags=permissions.split('/')[0];
   const map={a:'insert',r:'select',w:'update',d:'delete',D:'truncate',x:'references',t:'trigger',m:'maintain'};
   const rights=[...flags].filter(c=>map[c]).map(c=>map[c]);if(rights.length)await q(`grant ${rights.join(',')} on ${table} to ${ident(role)}`);
  }
 }
 for(const f of snapshot.functions)await q(f.def);
 for(const t of snapshot.tables)for(const tr of t.triggers||[]){await q(tr.function);await q(tr.def);}
 for(const f of privileges.functions){
  await q(`alter function public.${f.identity} owner to postgres; revoke all on function public.${f.identity} from public,anon,authenticated,service_role`);
  for(const acl of f.acl||[]){const role=acl.split('=')[0];await q(`grant execute on function public.${f.identity} to ${role?ident(role):'public'}`);}
 }
 // Auth tables here are placeholders solely to load candidate functions; no JWT PASS claim.
 await q(`create table auth.users(id uuid primary key,raw_app_meta_data jsonb); create table auth.sessions(id uuid primary key,user_id uuid);
 create function auth.uid() returns uuid language sql as $$select null::uuid$$;
 create function auth.jwt() returns jsonb language sql as $$select '{}'::jsonb$$;`);
 await q(`insert into sc_agent_config(id,config) values('solar_connects_v1','{"security_control_plane_v1":{"kill_switches":{"factory":{"allow":false},"publisher":{"allow":false},"meta_direct":{"allow":false},"external_write":{"allow":false}}},"publishing_policy":{"max_feed_posts_per_day":1}}');
 insert into sc_system_health(component,status,details) values('solar_quality_v2_production_flags','STAGE1_FROZEN_OBSERVATION','{"enabled":true,"formats":{"image":{"kill_switch":true},"carousel":{"kill_switch":true},"story":{"kill_switch":true},"reel":{"kill_switch":true}}}'),('solar_quality_v2_first_slot','CONFIRMED_FROZEN','{"enabled":true,"state":"CONFIRMED_FROZEN"}');`);
 async function run(){
  const id=randomUUID();await db.query(`insert into sc_creative_runs(id,run_key,idempotency_key,status,current_stage) values($1,$2,$2,'APPROVED','DONE')`,[id,'staging_'+id]);
  const slides=[{title:'Prueba local',body:'Contrato real',cta:'Leer',eyebrow:'SOLAR',fact_ids:[]}];
  const outputs=[['RADAR','radar-v1',{}],['EDITOR','editor-v2',{candidates:[{candidate_id:'test',format:'image',topic:'STAGING SYNTHETIC',caption:'Contenido sintético local',plan:{slides}}]}],['DIRECTOR','director-v2',{candidate_id:'test',format:'image',slides:[{template:'hero_question',theme:'solar',scene_key:'not-rendered'}]}]];
  for(const [stage,version,output] of outputs)await db.query(`insert into sc_creative_stage_outputs(run_id,stage,attempt,input_hash,schema_version,validation_status,output) values($1,$2,1,$3,$4,'VALID',$5)`,[id,stage,'a'.repeat(64),version,output]);
  return id;
 }
 const quality={pages:[{argument_key:'test',decision_key:'test',angle_key:'test',hook_family:'test',layout:'test'}]};
 async function asRole(role,sql,params){await q('set role '+ident(role));try{return await db.query(sql,params);}finally{await q('reset role');}}
 async function legacy(label){
  const id=await run();
  const shadow=(await asRole('service_role',`select sc_creative_materialize_job_v1($1,'SHADOW') r`,[id])).rows[0].r;
  assert.equal(shadow.state,'CREATED');
  const id2=await run();
  const adapter=(await asRole('postgres',`select sc_quality_factory_from_run_v2($1,$2,'{"enabled":true,"mode":"SHADOW","formats":["image"]}') r`,[id2,quality])).rows[0].r;
  assert.equal(adapter.ok,true);assert.equal(adapter.route,'QUALITY_V2_SHADOW');
  await asRole('postgres',`update sc_content_jobs set qa=qa||jsonb_build_object('creative_run_id',$1::text) where id=$2`,[id2,adapter.job_id]);
  const id3=await run();const production=(await asRole('service_role',`select sc_creative_materialize_job_v1($1,'PRODUCTION') r`,[id3])).rows[0].r;
  assert.equal(production.reason,'FACTORY_KILL_SWITCH');
  const route=(await asRole('postgres',`select sc_quality_factory_production_v2($1,$2,1,true) r`,[id3,quality])).rows[0].r;
  assert.equal(route.mode,'READ_ONLY');assert.equal(route.reason,'FORMAT_KILL_SWITCH');
  await assert.rejects(asRole('service_role',`insert into sc_content_jobs(content_plan,qa) values('{}','{}')`),/permission denied/);
  await assert.rejects(asRole('authenticated',`insert into sc_content_jobs(content_plan,qa) values('{}','{}')`),/permission denied/);
  await asRole('postgres',`insert into sc_content_jobs(content_plan,qa) values('{}','{}'),(jsonb_build_object('creative_run_id',$1::text),'{}')`,['legacy-'+randomUUID()]);
  await assert.rejects(db.query(`update sc_creative_stage_outputs set output='{}' where run_id=$1`,[id]),/append.only|immutable|UPDATE|APPEND/i);
  report.push({name:label,status:'PASS',checks:['V1 SHADOW via service_role','Quality V2 SHADOW via existing SQL owner','late creative_run_id annotation','V1 production denied','Quality freeze read-only route','service/authenticated direct insert denied','unreserved owner DML','real append-only trigger']});
 }
 await legacy('Baseline: real SQL before isolation');
 await q(fs.readFileSync('supabase/candidate/factory-isolation.sql','utf8'));
 await legacy('Regression: same real SQL after scoped isolation');
 await assert.rejects(q(`insert into sc_content_jobs(content_plan,qa) values('{}','{"factory_command_id":"fake"}')`),/UNBOUND_CONTROLLED_MARKER/);
 report.push({name:'forged controlled marker rejected',status:'PASS'});
 // Real ledger claim/audit (local only), reservation seeded by test DBA while gates remain OFF.
 const reserved=await run(),command=randomUUID(),actor=randomUUID();
 const claim=(await db.query(`select sc_v5_command_claim_v1($1,$2,'staging_reserved','factory.start','{"agent":"FACTORY","job_id":null}',$3,'REAL_EXECUTION','EXECUTE') r`,[command,actor,{creative_run_id:reserved}])).rows[0].r;
 assert.equal(claim.state,'CLAIMED');
 await db.query(`insert into sc_internal.factory_permits(command_id,creative_run_id,actor_user_id,idempotency_key,request_hash,compiled_plan,plan_sha256,quality_input,quality_slot,claim_token,lease_version,expires_at) select command_id,$2,actor_user_id,idempotency_key,request_hash,'{}',repeat('a',64),'{}',1,claim_token,lease_version,claim_expires_at from sc_internal.v5_commands where command_id=$1`,[command,reserved]);
 await assert.rejects(asRole('service_role',`select sc_creative_materialize_job_v1($1,'SHADOW')`,[reserved]),/TRANSACTION_PERMIT_REQUIRED/);
 await assert.rejects(asRole('postgres',`select sc_quality_factory_from_run_v2($1,$2,'{"enabled":true,"mode":"SHADOW","formats":["image"]}')`,[reserved,quality]),/TRANSACTION_PERMIT_REQUIRED/);
 await assert.rejects(db.query(`insert into sc_content_jobs(content_plan,qa) values('{}',jsonb_build_object('creative_run_id',$1::text))`,[reserved]),/TRANSACTION_PERMIT_REQUIRED/);
 report.push({name:'reserved run cannot bypass via real V1, real Quality V2 or direct insert',status:'PASS'});
 assert.equal((await q(`select count(*)::int n from sc_content_jobs where qa->>'creative_run_id'='${reserved}' or content_plan->>'creative_run_id'='${reserved}'`)).rows[0].n,0);
 assert.equal((await q('select count(*)::int n from sc_internal.security_mutation_audit')).rows[0].n,1);
 report.push({name:'existing V5 claim and audit reused, no duplicate job on rejected bypass',status:'PASS'});
 // Validate rollback using the REAL materializer, not a replacement fixture.
 const rollbackRun=await run();await q('begin');
 const rolled=(await asRole('service_role',`select sc_creative_materialize_job_v1($1,'SHADOW') r`,[rollbackRun])).rows[0].r;
 assert.equal(rolled.state,'CREATED');await q('rollback');
 assert.equal((await db.query(`select count(*)::int n from sc_content_jobs where content_plan->>'creative_run_id'=$1`,[rollbackRun])).rows[0].n,0);
 report.push({name:'real SHADOW materializer outer rollback leaves no job',status:'PASS'});
 await assert.rejects(asRole('authenticated','select * from sc_internal.factory_permits'),/permission denied/);
 await assert.rejects(asRole('service_role',`select sc_internal.factory_materialize($1,$2,1,repeat('a',64),'{}',1)`,[command,claim.claim_token]),/permission denied/);
 // RLS rather than just missing table privilege: a transaction-local test GRANT is rolled back.
 await q('begin');await q('grant select on sc_content_jobs to authenticated');
 assert.equal((await asRole('authenticated','select count(*)::int n from sc_content_jobs')).rows[0].n,0);
 await q('rollback');report.push({name:'real deny-by-default RLS and candidate private grants',status:'PASS'});
 await assert.rejects(db.query(`insert into sc_content_jobs(content_plan,qa) values(jsonb_build_object('creative_run_id',$1::text),jsonb_build_object('creative_run_id',$2::text))`,[randomUUID(),reserved]),/RUN_BINDING_CONFLICT/);
 await assert.rejects(db.query(`insert into sc_content_jobs(content_plan,qa) values(jsonb_build_object('creative_run_id',$1::text),jsonb_build_object('creative_run_id',$2::text))`,[randomUUID(),reserved.toUpperCase()]),/RUN_BINDING_CONFLICT/);
 report.push({name:'reserved identity hidden in secondary qa field cannot bypass guard',status:'PASS'});
 const attempts=await Promise.all(Array.from({length:16},async()=>{
 const c=new pg.Client({host:'127.0.0.1',port:Number(process.env.FACTORY_TEST_PORT),user:'factory_test',database:'postgres'});
 await c.connect();try{
 await c.query('set role postgres');
 try{await c.query(`select sc_quality_factory_from_run_v2($1,$2,'{"enabled":true,"mode":"SHADOW","formats":["image"]}')`,[reserved,quality]);return 'UNEXPECTED_SUCCESS';}
 catch(e){return e.message;}
 }finally{await c.end();}
 }));
 assert(attempts.every(s=>s.includes('TRANSACTION_PERMIT_REQUIRED')));
 assert.equal((await db.query(`select count(*)::int n from sc_content_jobs where content_plan->>'creative_run_id'=$1 or qa->>'creative_run_id'=$1`,[reserved])).rows[0].n,0);
 report.push({name:'16 independent connections: real Quality adapter cannot bypass reserved run',status:'PASS'});
 const gates=(await q(`select jsonb_object_agg(g,sc_security_operation_gate_v1(g)->'allowed') gates from unnest(array['FACTORY','PUBLISHER','META_DIRECT','EXTERNAL_WRITE'])g`)).rows[0].gates;
 assert.deepEqual(gates,{FACTORY:false,PUBLISHER:false,META_DIRECT:false,EXTERNAL_WRITE:false});
 const out={status:'PARTIAL_SQL_PASS_FULL_STAGING_BLOCKED',tests:report,gates,real_tables:snapshot.tables.length,real_functions:snapshot.functions.length,source:'read-only catalog export; synthetic test rows',not_validated:['real Supabase JWT/Auth','Edge/PostgREST bridge','Realtime delivery (original trigger catches absent realtime.send)','autonomous process end-to-end','production deployment'],production_writes:0};
 fs.writeFileSync('artifacts/factory-real-contracts-results.json',JSON.stringify(out,null,2));console.log(JSON.stringify(out,null,2));
}finally{await db.end();}
