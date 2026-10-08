export const CONTRACT_VERSION = 'v5.1.1-learning-canary';
export const GENERAL_EXECUTION_ENABLED = false;
export const ALLOWED_ACTIONS = new Set([
  'factory.start',
  'publisher.publish',
  'recovery.run',
  'learning.rebuild'
]);
export const REAL_ACTION_ALLOWLIST = new Set(['learning.rebuild']);

const MAX=200;
const clean=(v,n=MAX)=>typeof v==='string'?v.trim().slice(0,n):'';

function auditBase({body,actor,now,status,reason}) {
  return {
    event_type:'V5_COMMAND_BOUNDARY',
    contract_version:CONTRACT_VERSION,
    occurred_at:now,
    command_id:clean(body?.command_id,120)||null,
    idempotency_key:clean(body?.idempotency_key,180)||null,
    requested_action:clean(body?.requested_action,100)||null,
    mode:clean(body?.mode,20)||null,
    actor_id:actor?.id||null,
    actor_class:actor?.actor_class||'UNKNOWN',
    authenticated:Boolean(actor?.authenticated),
    authorized:Boolean(actor?.authorized),
    real_learning_authorized:Boolean(actor?.real_learning_authorized),
    target_agent:clean(body?.target?.agent,80)||null,
    target_job_id:clean(body?.target?.job_id,120)||null,
    confirmation_intent:clean(body?.confirmation?.intent,80)||null,
    confirmation_present:Boolean(body?.confirmation?.token),
    status,reason,
    general_execution_enabled:false,
    production_write_attempted:false
  };
}
function invalid(reason,b,a,now,http_status=400,status='INVALID') {
  return {http_status,status,execution_state:'NO_OP',reason,
    audit_event:auditBase({body:b,actor:a,now,status,reason})};
}
export function processCommand(body,actor,ledger=new Map(),now=new Date().toISOString()) {
  const a=actor||{authenticated:false,authorized:false,real_learning_authorized:false,actor_class:'UNKNOWN',id:null};
  const b=body&&typeof body==='object'&&!Array.isArray(body)?body:{};
  if(!a.authenticated) return invalid('AUTH_REQUIRED',b,a,now,401,'DENIED');
  if(!a.authorized) return invalid('AUTHORIZATION_REQUIRED',b,a,now,403,'DENIED');

  const command_id=clean(b.command_id,120);
  const idempotency_key=clean(b.idempotency_key,180);
  const requested_action=clean(b.requested_action,100);
  const mode=clean(b.mode,20).toUpperCase();
  const targetAgent=clean(b?.target?.agent,80);
  const targetJob=clean(b?.target?.job_id,120);
  const intent=clean(b?.confirmation?.intent,80);
  const token=clean(b?.confirmation?.token,420);
  const confirmed=b?.confirmation?.confirmed===true;

  if(!command_id||command_id.length<8) return invalid('COMMAND_ID_REQUIRED',b,a,now);
  if(!idempotency_key||idempotency_key.length<8) return invalid('IDEMPOTENCY_KEY_REQUIRED',b,a,now);
  if(!ALLOWED_ACTIONS.has(requested_action)) return invalid('ACTION_NOT_ALLOWED',b,a,now,403,'DENIED');
  if(!['SIMULATE','EXECUTE'].includes(mode)) return invalid('MODE_INVALID',b,a,now);
  if(!targetAgent&&!targetJob) return invalid('TARGET_REQUIRED',b,a,now);
  if(!confirmed||!token||!intent) return invalid('CONFIRMATION_REQUIRED',b,a,now);

  if(mode==='SIMULATE') {
    const expected=`SIMULATE:${command_id}:${idempotency_key}`;
    if(intent!=='SIMULATE_ONLY'||token!==expected) return invalid('SIMULATION_CONFIRMATION_INVALID',b,a,now);
    return {
      http_status:202,status:'ACCEPTED_FOR_SIMULATION',execution_state:'NO_OP',
      reason:'SIMULATION_ACCEPTED_NO_OPERATION',execution_enabled:false,simulated:true,
      command:{command_id,idempotency_key,requested_action,target:{agent:targetAgent||null,job_id:targetJob||null}},
      audit_event:auditBase({body:b,actor:a,now,status:'ACCEPTED_FOR_SIMULATION',reason:'SIMULATION_ACCEPTED_NO_OPERATION'})
    };
  }

  if(!REAL_ACTION_ALLOWLIST.has(requested_action)) {
    return invalid('REAL_ACTION_NOT_ALLOWED',b,a,now,403,'DENIED');
  }
  if(!a.real_learning_authorized) {
    return invalid('REAL_OPERATOR_AUTHORIZATION_REQUIRED',b,a,now,403,'DENIED');
  }
  if(requested_action!=='learning.rebuild'||targetAgent!=='LEARNING'||targetJob) {
    return invalid('REAL_TARGET_NOT_ALLOWED',b,a,now,400,'INVALID');
  }
  const expectedReal=`REAL:${command_id}:${idempotency_key}:learning.rebuild`;
  if(intent!=='REAL_EXECUTION'||token!==expectedReal) {
    return invalid('REAL_CONFIRMATION_REQUIRED',b,a,now,400,'INVALID');
  }

  return {
    http_status:202,status:'REAL_CANARY_VALIDATED',execution_state:'PENDING',
    reason:'REAL_LEARNING_CANARY_VALIDATED',
    execution_enabled:false,
    command:{command_id,idempotency_key,requested_action,target:{agent:'LEARNING',job_id:null}},
    audit_event:auditBase({body:b,actor:a,now,status:'REAL_CANARY_VALIDATED',reason:'REAL_LEARNING_CANARY_VALIDATED'})
  };
}
