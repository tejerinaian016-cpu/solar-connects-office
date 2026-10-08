import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {PLAN_HASH_ALGORITHM,confirmationToken,validateFactoryCommand,compiledPlanHash,validateFactoryLease,inspectFactoryStart} from '../supabase/functions/v5-command-boundary/factory-controlled.mjs';

const now=Date.parse('2026-10-08T16:10:00Z');
const actor={id:'11111111-1111-4111-8111-111111111111',app_metadata:{command_center:true,solar_role:'v5_operator'}};
const runId='22222222-2222-4222-8222-222222222222';
const compiled={ok:true,format:'image',content_plan:{creative_run_id:runId,slides:[{title:'TEST FIXTURE',scene_key:'fixture-only'}]},qa:{do_not_publish:true}};
const planHash=await compiledPlanHash(compiled);
const body={command_id:'33333333-3333-4333-8333-333333333333',idempotency_key:'test_factory_0001',requested_action:'factory.start',mode:'EXECUTE',target:{agent:'FACTORY',job_id:null},payload:{creative_run_id:runId,compiled_plan_sha256:planHash,plan_hash_algorithm:PLAN_HASH_ALGORITHM,max_jobs:1,stop_at:'READY',additional_paid_cost_usd:0},confirmation:{confirmed:true,intent:'REAL_EXECUTION'}};
body.confirmation.token=confirmationToken(body);
const requestHash='a'.repeat(64);
function fixture(overrides={}){
 const calls=[];
 const rows={
  sc_creative_runs:{id:runId,status:'APPROVED',created_at:new Date(now-1000).toISOString()},
  sc_creative_stage_outputs:[['RADAR','radar-v1'],['EDITOR','editor-v2'],['DIRECTOR','director-v2']].map(([stage,schema_version])=>({stage,schema_version,attempt:1,validation_status:'VALID'})),
  sc_content_jobs:[],...overrides.rows
 };
 const service={calls,async rpc(name,args){
  calls.push({name,args});
  const responses={sc_v5_command_request_hash_v1:requestHash,sc_v5_command_get_v1:{ok:false,reason:'NOT_FOUND'},sc_creative_compile_carousel_v1:compiled,sc_creative_render_preflight_v1:{ok:true},sc_quality_factory_hook_v2:{ok:true,route:'V1',reason:'ROLLOUT_DISABLED'},...overrides.rpc};
  if(name==='sc_security_operation_gate_v1')return {data:{operation:args.p_operation,allowed:false,...overrides.gates?.[args.p_operation]}};
  assert(name in responses,`Unexpected RPC ${name}`);
  if(overrides.throw===name)throw Error('Fixture timeout');
  return {data:responses[name]};
 },from(name){
  assert(name in rows);calls.push({table:name});
  const query={select(){return query},eq(){return query},or(){return query},async maybeSingle(){return {data:rows[name]}},async limit(){return {data:rows[name]}},async order(){return {data:rows[name]}}};return query;
 }};return service;
}
test('strict verified-user role, never user_metadata',()=>{
 assert.equal(validateFactoryCommand(body,null).http_status,401);
 for(const u of [{id:actor.id},{id:actor.id,user_metadata:actor.app_metadata},{...actor,app_metadata:{command_center:true}},{...actor,app_metadata:{solar_role:'v5_operator'}}])assert.equal(validateFactoryCommand(body,u).http_status,403);
 assert.equal(validateFactoryCommand(body,actor).ok,true);
});
test('confirmation binds all four identifiers without truncation',()=>{
 for(const [key,val] of [['command_id','44444444-4444-4444-8444-444444444444'],['idempotency_key','other_key_0001']]){
  const b=structuredClone(body);b[key]=val;assert.equal(validateFactoryCommand(b,actor).reason,'FACTORY_CONFIRMATION_BINDING_INVALID');
 }
 for(const [key,val] of [['creative_run_id','44444444-4444-4444-8444-444444444444'],['compiled_plan_sha256','b'.repeat(64)]]){
  const b=structuredClone(body);b.payload[key]=val;assert.equal(validateFactoryCommand(b,actor).reason,'FACTORY_CONFIRMATION_BINDING_INVALID');
 }
 const b=structuredClone(body);b.idempotency_key='x'.repeat(161);assert.equal(validateFactoryCommand(b,actor).reason,'IDEMPOTENCY_KEY_INVALID');
});
test('reject extra jobs, publishing, paid costs and injected scope flags',()=>{
 for(const [k,v] of [['max_jobs',2],['stop_at','PUBLISHED'],['additional_paid_cost_usd',1]]){const b=structuredClone(body);b.payload[k]=v;assert.equal(validateFactoryCommand(b,actor).reason,'SINGLE_JOB_READY_ZERO_COST_REQUIRED')}
 const b=structuredClone(body);b.payload.allow_global_factory=true;assert.equal(validateFactoryCommand(b,actor).reason,'PLAN_BINDING_REQUIRED');
});
test('hash is order-stable and changes for semantic/branding/asset changes',async()=>{
 assert.equal(await compiledPlanHash({b:2,a:1}),await compiledPlanHash({a:1,b:2}));
 for(const field of ['title','scene_key','branding']){const c=structuredClone(compiled);c.content_plan.slides[0][field]='CHANGED';assert.notEqual(await compiledPlanHash(c),planHash)}
 await assert.rejects(()=>compiledPlanHash({bad:NaN}));
});
test('validated preflight still blocks global gate with zero mutation paths',async()=>{
 const s=fixture();const r=await inspectFactoryStart(body,actor,s,now);
 assert.equal(r.reason,'FACTORY_SCOPE_NOT_ISOLATED');assert.equal(r.http_status,423);assert.equal(r.production_writes,0);
 assert(s.calls.every(x=>!x.name || ['sc_v5_command_request_hash_v1','sc_v5_command_get_v1','sc_security_operation_gate_v1','sc_creative_compile_carousel_v1','sc_creative_render_preflight_v1','sc_quality_factory_hook_v2'].includes(x.name)));
});
test('invalid operator cannot access service or ledger',async()=>{const s=fixture();assert.equal((await inspectFactoryStart(body,{id:actor.id},s,now)).http_status,403);assert.equal(s.calls.length,0)});
test('ledger terminal duplicate returns prior status, never re-executes',async()=>{
 const s=fixture({rpc:{sc_v5_command_get_v1:{ok:true,command_id:body.command_id,request_hash:requestHash,status:'SUCCEEDED'}}});
 const r=await inspectFactoryStart(body,actor,s,now);assert.equal(r.status,'DUPLICATE');assert.equal(r.executed,false);assert.equal(s.calls.length,2);
});
test('ledger idempotency hash and command-id conflicts fail closed',async()=>{
 for(const change of [{request_hash:'b'.repeat(64)},{command_id:runId}]){const s=fixture({rpc:{sc_v5_command_get_v1:{ok:true,command_id:body.command_id,request_hash:requestHash,status:'SUCCEEDED',...change}}});assert.equal((await inspectFactoryStart(body,actor,s,now)).reason,'IDEMPOTENCY_KEY_REQUEST_MISMATCH')}
});
test('active lease and expired/ambiguous lease never trigger a reclaim',async()=>{
 for(const delta of [60000,-1000]){const s=fixture({rpc:{sc_v5_command_get_v1:{ok:true,command_id:body.command_id,request_hash:requestHash,status:'EXECUTING',claim_expires_at:new Date(now+delta).toISOString()}}});assert.equal((await inspectFactoryStart(body,actor,s,now)).reason,delta>0?'LEASE_ACTIVE':'MANUAL_RECONCILIATION_REQUIRED');assert.equal(s.calls.length,2)}
});
test('global Factory open or any publication gate open refuses operation',async()=>{
 for(const op of ['FACTORY','PUBLISHER','META_DIRECT','EXTERNAL_WRITE']){const s=fixture({gates:{[op]:{allowed:true}}});assert.equal((await inspectFactoryStart(body,actor,s,now)).reason,op==='FACTORY'?'UNSCOPED_FACTORY_GATE_OPEN':'PUBLICATION_GATES_NOT_CLOSED')}
 const s=fixture({gates:{FACTORY:{allowed:null}}});assert.equal((await inspectFactoryStart(body,actor,s,now)).reason,'GATE_EVIDENCE_UNAVAILABLE');
});
test('never reuse materialized jobs or old creative runs',async()=>{
 assert.equal((await inspectFactoryStart(body,actor,fixture({rows:{sc_content_jobs:[{id:runId}]}}),now)).reason,'CREATIVE_RUN_ALREADY_MATERIALIZED');
 assert.equal((await inspectFactoryStart(body,actor,fixture({rows:{sc_creative_runs:{id:runId,status:'APPROVED',created_at:'2026-10-01'}}}),now)).reason,'FRESH_CREATIVE_RUN_REQUIRED');
});
test('RADAR required and latest invalid stage cannot use earlier valid output',async()=>{
 for(const stage of ['RADAR','EDITOR','DIRECTOR']){
  const stages=[{stage,attempt:2,validation_status:'INVALID'},...['RADAR','EDITOR','DIRECTOR'].map(x=>({stage:x,attempt:1,validation_status:'VALID',schema_version:x==='RADAR'?'radar-v1':x.toLowerCase()+'-v2'}))];
  assert.equal((await inspectFactoryStart(body,actor,fixture({rows:{sc_creative_stage_outputs:stages}}),now)).reason,'LATEST_CREATIVE_STAGE_NOT_VALID');
 }
 assert.equal((await inspectFactoryStart(body,actor,fixture({rows:{sc_creative_stage_outputs:[]}}),now)).reason,'LATEST_CREATIVE_STAGE_NOT_VALID');
});
test('plan hash conflict and current preflight rejection',async()=>{
 const changed=structuredClone(compiled);changed.format='carousel';assert.equal((await inspectFactoryStart(body,actor,fixture({rpc:{sc_creative_compile_carousel_v1:changed}}),now)).reason,'COMPILED_PLAN_HASH_CONFLICT');
 assert.equal((await inspectFactoryStart(body,actor,fixture({rpc:{sc_creative_render_preflight_v1:{ok:false}}}),now)).reason,'RENDER_PREFLIGHT_FAILED');
});
test('Quality V2 routing cannot bypass isolation or fabricate PASS',async()=>{
 const r=await inspectFactoryStart(body,actor,fixture({rpc:{sc_quality_factory_hook_v2:{ok:true,route:'V2'}}}),now);assert.equal(r.reason,'FACTORY_SCOPE_NOT_ISOLATED');assert.equal(r.quality_route,'V2');assert.equal(r.executed,false);
});
test('claim token, lease version, actor, target and expiry all fenced locally',()=>{
 const owner={claim_token:'55555555-5555-4555-8555-555555555555',lease_version:1};
 const row={...body,command_type:'factory.start',actor_user_id:actor.id,confirmation_intent:'REAL_EXECUTION',request_hash:requestHash,status:'CLAIMED',claim_expires_at:new Date(now+60000).toISOString(),...owner};
 assert.equal(validateFactoryLease(row,owner,body,actor.id,requestHash,now).ok,true);
 for(const change of [{claim_token:runId},{lease_version:2},{claim_expires_at:new Date(now).toISOString()},{status:'EXECUTING'},{actor_user_id:runId},{target:{agent:'PUBLISHER'}}])assert.notEqual(validateFactoryLease({...row,...change},owner,body,actor.id,requestHash,now).ok,true);
});
test('concurrent requests remain blocked with no materializer call',async()=>{
 const s=fixture();const r=await Promise.all(Array.from({length:32},()=>inspectFactoryStart(body,actor,s,now)));assert(r.every(x=>x.reason==='FACTORY_SCOPE_NOT_ISOLATED'&&x.production_writes===0));
});
test('read timeout fails closed without an ambiguous retry',async()=>{const s=fixture({throw:'sc_creative_compile_carousel_v1'});assert.equal((await inspectFactoryStart(body,actor,s,now)).reason,'FACTORY_PREFLIGHT_FAIL_CLOSED');assert.equal(s.calls.filter(x=>x.name==='sc_creative_compile_carousel_v1').length,1)});
test('existing learning/simulation core unchanged; factory dispatch after verified JWT',()=>{
 assert.equal(fs.readFileSync(new URL('../supabase/functions/v5-command-boundary/core.mjs',import.meta.url),'utf8'),fs.readFileSync(new URL('../supabase/recovery/v5-command-boundary-v6/core.mjs',import.meta.url),'utf8'));
 const index=fs.readFileSync(new URL('../supabase/functions/v5-command-boundary/index.ts',import.meta.url),'utf8');assert(index.indexOf('auth.getUser(token)')<index.indexOf('await inspectFactoryStart(body,authData.user,service)'));
});
