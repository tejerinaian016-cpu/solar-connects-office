import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { processCommand, CONTRACT_VERSION } from "./core.mjs";
const H={"content-type":"application/json","cache-control":"no-store","access-control-allow-origin":"*","access-control-allow-headers":"authorization, apikey, content-type","access-control-allow-methods":"POST, OPTIONS"};
const uuidRe=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function asObj(x:any){return Array.isArray(x)?x[0]:x}
function safeObj(x:any){return x&&typeof x==="object"&&!Array.isArray(x)?x:{}}
function response(body:any,status:number){return new Response(JSON.stringify(body),{status,headers:H})}
function actorFromUser(user:any){
  const app=user?.app_metadata||{};
  const roles=Array.isArray(app.roles)?app.roles.map((x:any)=>String(x)):[];
  const primary=String(app.solar_role||"");
  const simulationAuthorized=app.command_center===true||["solar_admin","solar_operator","v5_operator"].includes(primary)||roles.some((r:string)=>["solar_admin","solar_operator","v5_operator"].includes(r));
  const realLearningAuthorized=app.command_center===true&&(primary==="v5_operator"||roles.includes("v5_operator"));
  return {authenticated:true,authorized:simulationAuthorized,real_learning_authorized:realLearningAuthorized,id:user?.id||null,actor_class:simulationAuthorized?"AUTHORIZED_USER":"AUTHENTICATED_USER"};
}
async function durableClaim(service:any,body:any,userId:string,mode:string){
  const target={agent:String(body?.target?.agent||"")||null,job_id:String(body?.target?.job_id||"")||null};
  const payload=safeObj(body?.payload);
  const {data,error}=await service.rpc("sc_v5_command_claim_v1",{
    p_command_id:String(body.command_id),
    p_actor_user_id:userId,
    p_idempotency_key:String(body.idempotency_key||""),
    p_command_type:String(body.requested_action||""),
    p_target:target,
    p_payload:payload,
    p_confirmation_intent:String(body?.confirmation?.intent||""),
    p_mode:mode,
    p_correlation_id:crypto.randomUUID(),
    p_lease_seconds:120
  });
  if(error) throw new Error("durable_claim_rpc_failed");
  return asObj(data);
}
function claimResponse(claim:any){
  if(claim?.state==="CONFLICT") return response({status:"CONFLICT",reason:claim.reason,execution_state:"NO_OP",executed:false,durable:claim,contract_version:CONTRACT_VERSION},409);
  if(claim?.state==="DUPLICATE_TERMINAL") return response({status:"DUPLICATE",reason:claim.reason,execution_state:"PRIOR_RESULT",executed:false,durable:claim,contract_version:CONTRACT_VERSION,audit_persistence:"DATABASE_AND_EDGE_LOG"},200);
  if(claim?.state==="IN_PROGRESS") return response({status:"IN_PROGRESS",reason:claim.reason,execution_state:"NO_OP",executed:false,durable:claim,contract_version:CONTRACT_VERSION},202);
  return null;
}
Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:H});
  if(req.method!=="POST")return response({status:"INVALID",reason:"METHOD_NOT_ALLOWED",contract_version:CONTRACT_VERSION},405);
  try{
    const auth=req.headers.get("authorization")||"",token=auth.startsWith("Bearer ")?auth.slice(7):"";
    if(!token)return response({status:"DENIED",reason:"AUTH_REQUIRED",execution_enabled:false,production_writes:0,external_writes:0},401);
    const url=Deno.env.get("SUPABASE_URL")||"",anon=Deno.env.get("SUPABASE_ANON_KEY")||"",serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
    if(!url||!anon||!serviceKey)throw new Error("runtime_config_missing");

    const authClient=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data:authData,error:authErr}=await authClient.auth.getUser(token);
    if(authErr||!authData?.user)return response({status:"DENIED",reason:"AUTH_INVALID",execution_enabled:false,production_writes:0,external_writes:0},401);

    let body:any={};try{body=await req.json()}catch{body={}}
    const actor=actorFromUser(authData.user);
    const validation=processCommand(body,actor,new Map(),new Date().toISOString());
    if(!["ACCEPTED_FOR_SIMULATION","REAL_CANARY_VALIDATED"].includes(validation.status)){
      console.log(JSON.stringify({...validation.audit_event,durable_ledger:false}));
      return response({...validation,contract_version:CONTRACT_VERSION,production_writes:0,external_writes:0},validation.http_status);
    }

    const commandId=String(body?.command_id||"");
    if(!uuidRe.test(commandId))return response({status:"INVALID",reason:"COMMAND_ID_UUID_REQUIRED",execution_enabled:false,production_writes:0,external_writes:0},400);

    const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});

    if(validation.status==="ACCEPTED_FOR_SIMULATION"){
      const claim=await durableClaim(service,body,authData.user.id,"SIMULATE");
      const prior=claimResponse(claim);if(prior)return prior;
      if(claim?.ok!==true||claim?.state!=="CLAIMED"||!claim?.claim_token)return response({status:"DENIED",reason:claim?.reason||"DURABLE_CLAIM_DENIED",execution_state:"NO_OP",execution_enabled:false,production_writes:0,external_writes:0},409);

      const {data:execRaw,error:execErr}=await service.rpc("sc_v5_command_mark_executing_v1",{p_command_id:claim.command_id,p_claim_token:claim.claim_token,p_lease_seconds:90});
      if(execErr)throw new Error("durable_execute_transition_failed");
      const executing=asObj(execRaw);if(executing?.ok!==true)return response({status:"DENIED",reason:executing?.reason||"CLAIM_OWNERSHIP_LOST",execution_state:"NO_OP",execution_enabled:false,production_writes:0,external_writes:0},409);

      const simulationResult={simulated:true,requested_action:String(body.requested_action||""),target:safeObj(body.target),payload:safeObj(body.payload),execution_enabled:false,production_writes:0,external_writes:0};
      const {data:doneRaw,error:doneErr}=await service.rpc("sc_v5_command_complete_v1",{p_command_id:claim.command_id,p_claim_token:claim.claim_token,p_success:true,p_result:simulationResult,p_error:null});
      if(doneErr)throw new Error("durable_completion_failed");
      const done=asObj(doneRaw);if(done?.ok!==true)throw new Error("durable_completion_rejected");
      return response({status:"ACCEPTED_FOR_SIMULATION",execution_state:"NO_OP",reason:"SIMULATION_ACCEPTED_DURABLE_NO_OPERATION",execution_enabled:false,simulated:true,production_writes:0,external_writes:0,durable:done,contract_version:CONTRACT_VERSION,audit_persistence:"DATABASE_AND_EDGE_LOG"},202);
    }

    const {data:gateRaw,error:gateErr}=await service.rpc("sc_security_operation_gate_v1",{p_operation:"LEARNING_MUTATION"});
    if(gateErr)throw new Error("learning_gate_read_failed");
    const gate=asObj(gateRaw);
    if(gate?.allowed!==true)return response({status:"DISABLED",reason:"LEARNING_MUTATION_KILL_SWITCH",execution_state:"DISABLED",executed:false,execution_enabled:false,external_writes:0,gate,contract_version:CONTRACT_VERSION},423);

    const claim=await durableClaim(service,body,authData.user.id,"EXECUTE");
    const prior=claimResponse(claim);if(prior)return prior;
    if(claim?.ok!==true||claim?.state!=="CLAIMED"||!claim?.claim_token)return response({status:"DENIED",reason:claim?.reason||"DURABLE_CLAIM_DENIED",execution_state:"NO_OP",executed:false,external_writes:0},409);

    const {data:realRaw,error:realErr}=await service.rpc("sc_v5_execute_learning_rebuild_v1",{p_command_id:claim.command_id,p_claim_token:claim.claim_token});
    if(realErr)throw new Error("learning_rebuild_executor_rpc_failed");
    const real=asObj(realRaw);
    if(real?.ok!==true||real?.state!=="SUCCEEDED"){
      return response({status:real?.state||"FAILED",reason:real?.reason||"REAL_EXECUTION_FAILED",execution_state:"FAILED",executed:false,external_writes:0,durable:real,contract_version:CONTRACT_VERSION},409);
    }
    return response({status:"SUCCEEDED",execution_state:"REAL_EXECUTED",executed:true,requested_action:"learning.rebuild",external_writes:0,durable:real,contract_version:CONTRACT_VERSION,audit_persistence:"DATABASE_AND_EDGE_LOG"},200);
  }catch(e:any){
    return response({status:"DENIED",reason:"FAIL_CLOSED",execution_enabled:false,production_writes:0,external_writes:0,error_class:String(e?.name||"Error")},500);
  }
});
