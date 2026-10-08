/* Read-only, fail-closed preparation for the EXISTING V5 boundary.
 * NOT an executable production adapter: the live FACTORY gate is global.
 * No claim, materialization, renderer, gate update or publisher call is permitted here.
 */
export const PLAN_HASH_ALGORITHM = 'sha256-sorted-json-v1';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA = /^[0-9a-f]{64}$/;
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const result = (reason,http_status=409,extra={}) => ({status:'DENIED',reason,http_status,execution_state:'NO_OP',executed:false,production_writes:0,external_writes:0,...extra});
const exactKeys = (o,keys) => object(o) && Object.keys(o).every(k=>keys.includes(k));

export function confirmationToken(b) {
  return `REAL:${b.command_id}:${b.idempotency_key}:factory.start:${b.payload.creative_run_id}:${b.payload.compiled_plan_sha256}`;
}
export function validateFactoryCommand(b,user) {
  if(!user || !UUID.test(user.id || '')) return result('AUTH_REQUIRED',401);
  const app=user.app_metadata || {};
  if(app.command_center!==true || !(app.solar_role==='v5_operator' || (Array.isArray(app.roles)&&app.roles.includes('v5_operator')))) return result('REAL_OPERATOR_AUTHORIZATION_REQUIRED',403);
  if(!exactKeys(b,['command_id','idempotency_key','requested_action','mode','target','payload','confirmation'])) return result('REQUEST_FIELDS_INVALID',400);
  if(!UUID.test(b.command_id || '')) return result('COMMAND_ID_UUID_REQUIRED',400);
  if(typeof b.idempotency_key!=='string' || !/^[A-Za-z0-9_-]{8,160}$/.test(b.idempotency_key)) return result('IDEMPOTENCY_KEY_INVALID',400);
  if(b.requested_action!=='factory.start' || b.mode!=='EXECUTE') return result('FACTORY_REAL_CONTRACT_REQUIRED',400);
  if(!exactKeys(b.target,['agent','job_id']) || b.target.agent!=='FACTORY' || b.target.job_id!==null) return result('REAL_TARGET_NOT_ALLOWED',400);
  const p=b.payload;
  if(!exactKeys(p,['creative_run_id','compiled_plan_sha256','plan_hash_algorithm','max_jobs','stop_at','additional_paid_cost_usd']) || !UUID.test(p.creative_run_id || '') || !SHA.test(p.compiled_plan_sha256 || '') || p.plan_hash_algorithm!==PLAN_HASH_ALGORITHM) return result('PLAN_BINDING_REQUIRED',400);
  if(p.max_jobs!==1 || p.stop_at!=='READY' || p.additional_paid_cost_usd!==0) return result('SINGLE_JOB_READY_ZERO_COST_REQUIRED',400);
  if(!exactKeys(b.confirmation,['confirmed','intent','token']) || b.confirmation.confirmed!==true || b.confirmation.intent!=='REAL_EXECUTION' || b.confirmation.token!==confirmationToken(b)) return result('FACTORY_CONFIRMATION_BINDING_INVALID',400);
  return {ok:true};
}

function canonical(value) {
  if(value===null || typeof value==='string' || typeof value==='boolean')return JSON.stringify(value);
  if(typeof value==='number' && Number.isFinite(value))return JSON.stringify(value);
  if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
  if(object(value) && Object.getPrototypeOf(value)===Object.prototype)return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}';
  throw Error('NON_JSON_COMPILED_PLAN');
}
export async function compiledPlanHash(compiled) {
  const bytes=new TextEncoder().encode(canonical(compiled));
  const digest=await crypto.subtle.digest('SHA-256',bytes);
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
}

// Defense for the future atomic executor, using existing V5 ownership fields.
// This pure check alone is NOT a DB lock or permission to render/materialize.
export function validateFactoryLease(row,ownership,b,actorId,requestHash,now=Date.now()) {
  if(!row || row.command_id!==b.command_id || row.actor_user_id!==actorId || row.idempotency_key!==b.idempotency_key || row.command_type!=='factory.start' || row.mode!=='EXECUTE' || row.target?.agent!=='FACTORY' || row.target?.job_id!==null || row.confirmation_intent!=='REAL_EXECUTION' || row.request_hash!==requestHash || row.payload?.creative_run_id!==b.payload.creative_run_id || row.payload?.compiled_plan_sha256!==b.payload.compiled_plan_sha256) return result('COMMAND_CONTRACT_MISMATCH');
  if(row.status!=='CLAIMED' || !UUID.test(ownership?.claim_token || '') || row.claim_token!==ownership.claim_token || !Number.isSafeInteger(ownership.lease_version) || ownership.lease_version<1 || row.lease_version!==ownership.lease_version || !Number.isFinite(Date.parse(row.claim_expires_at)) || Date.parse(row.claim_expires_at)<=now) return result('STALE_OR_INVALID_CLAIM_OWNER');
  return {ok:true};
}

const READ_RPCS = new Set(['sc_v5_command_request_hash_v1','sc_v5_command_get_v1','sc_security_operation_gate_v1','sc_creative_compile_carousel_v1','sc_creative_render_preflight_v1','sc_quality_factory_hook_v2']);
export async function inspectFactoryStart(body,verifiedUser,service,now=Date.now()) {
  // verifiedUser must come from the existing auth.getUser(jwt), never request JSON.
  const validation=validateFactoryCommand(body,verifiedUser);if(!validation.ok)return validation;
  const b=structuredClone(body),p=b.payload;
  async function readRpc(name,args){
    if(!READ_RPCS.has(name))throw Error('MUTATING_RPC_FORBIDDEN');
    const {data,error}=await service.rpc(name,args);if(error)throw Error('READ_FAILED');
    return Array.isArray(data)?data[0]:data;
  }
  try {
    // Reuse the V5 request hash and durable ledger. Do not claim/reclaim a lease.
    const hash=await readRpc('sc_v5_command_request_hash_v1',{p_command_type:b.requested_action,p_target:b.target,p_payload:p,p_confirmation_intent:b.confirmation.intent,p_mode:b.mode});
    if(typeof hash!=='string' || !SHA.test(hash))return result('LEDGER_HASH_UNAVAILABLE',503);
    const prior=await readRpc('sc_v5_command_get_v1',{p_actor_user_id:verifiedUser.id,p_idempotency_key:b.idempotency_key});
    if(prior?.ok===true){
      if(prior.command_id!==b.command_id || prior.request_hash!==hash)return result('IDEMPOTENCY_KEY_REQUEST_MISMATCH');
      if(['SUCCEEDED','FAILED','ROLLED_BACK'].includes(prior.status))return result('IDEMPOTENT_REPLAY',200,{status:'DUPLICATE',execution_state:'PRIOR_RESULT',prior_status:prior.status,command_id:prior.command_id});
      if(['CLAIMED','EXECUTING'].includes(prior.status) && Date.parse(prior.claim_expires_at)>now)return result('LEASE_ACTIVE',202,{status:'IN_PROGRESS'});
      return result('MANUAL_RECONCILIATION_REQUIRED');
    }
    if(prior?.ok!==false || prior.reason!=='NOT_FOUND')return result('LEDGER_READ_UNAVAILABLE',503);
    const gates={};
    for(const op of ['FACTORY','PUBLISHER','META_DIRECT','EXTERNAL_WRITE']){
      const g=await readRpc('sc_security_operation_gate_v1',{p_operation:op});
      if(g?.operation!==op || typeof g.allowed!=='boolean')return result('GATE_EVIDENCE_UNAVAILABLE',503);
      gates[op]=g.allowed;
    }
    if(gates.PUBLISHER || gates.META_DIRECT || gates.EXTERNAL_WRITE)return result('PUBLICATION_GATES_NOT_CLOSED',423);
    if(gates.FACTORY)return result('UNSCOPED_FACTORY_GATE_OPEN',423);
    const {data:run,error:runError}=await service.from('sc_creative_runs').select('id,status,created_at').eq('id',p.creative_run_id).maybeSingle();
    if(runError || !run)return result('CREATIVE_RUN_UNAVAILABLE',404);
    if(run.status!=='APPROVED')return result('CREATIVE_RUN_NOT_APPROVED',422);
    const age=now-Date.parse(run.created_at);
    if(!Number.isFinite(age) || age<0 || age>86400000)return result('FRESH_CREATIVE_RUN_REQUIRED',422);
    // UUID validated above; no user-controlled filter syntax is permitted.
    const {data:existing,error:jobError}=await service.from('sc_content_jobs').select('id').or(`content_plan->>creative_run_id.eq.${p.creative_run_id},qa->>creative_run_id.eq.${p.creative_run_id}`).limit(1);
    if(jobError || !Array.isArray(existing))return result('JOB_EVIDENCE_UNAVAILABLE',503);
    if(existing.length)return result('CREATIVE_RUN_ALREADY_MATERIALIZED');
    const {data:stages,error:stageError}=await service.from('sc_creative_stage_outputs').select('stage,attempt,validation_status,schema_version').eq('run_id',p.creative_run_id).order('attempt',{ascending:false});
    if(stageError || !Array.isArray(stages))return result('STAGE_EVIDENCE_UNAVAILABLE',503);
    for(const [stage,version] of [['RADAR','radar-v1'],['EDITOR','editor-v2'],['DIRECTOR','director-v2']]){
      const latest=stages.find(s=>s.stage===stage);
      if(latest?.validation_status!=='VALID' || latest.schema_version!==version)return result('LATEST_CREATIVE_STAGE_NOT_VALID',422,{stage});
    }
    const compiled=await readRpc('sc_creative_compile_carousel_v1',{p_run_id:p.creative_run_id});
    if(compiled?.ok!==true || compiled.content_plan?.creative_run_id!==p.creative_run_id)return result('COMPILE_FAILED',422);
    if(await compiledPlanHash(compiled)!==p.compiled_plan_sha256)return result('COMPILED_PLAN_HASH_CONFLICT');
    const preflight=await readRpc('sc_creative_render_preflight_v1',{p_run_id:p.creative_run_id});
    if(preflight?.ok!==true)return result('RENDER_PREFLIGHT_FAILED',422);
    const quality=await readRpc('sc_quality_factory_hook_v2',{p_run_id:p.creative_run_id,p_slot:null});
    // Nothing in the present gate/Quality hook is an atomic, single-command permit.
    // Never fall back to V1 or invent a V2 PASS to turn this into an execution path.
    return result('FACTORY_SCOPE_NOT_ISOLATED',423,{status:'BLOCKED',read_only_preflight:true,quality_route:quality?.route||'UNKNOWN',compiled_plan_sha256:p.compiled_plan_sha256,command_id:b.command_id,creative_run_id:p.creative_run_id,additional_paid_cost_usd:0});
  } catch {return result('FACTORY_PREFLIGHT_FAIL_CLOSED',503)}
}
