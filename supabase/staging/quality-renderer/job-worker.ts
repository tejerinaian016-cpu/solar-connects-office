// STAGING ONLY, temporary restricted entry point. Close after the experiment.
import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {pipelineAction} from './pipeline.ts';
import {sha} from './quality-render.ts';
const BASE='https://cmwervbwxyqzowntnxwe.supabase.co',EXPECTED='__TEMPORARY_SHA256__';
Deno.serve(async req=>{
 try {
  if(req.method!=='POST'||Deno.env.get('SUPABASE_URL')!==BASE)return Response.json({error:'STAGING_ONLY'},{status:403});
  if(await sha(new TextEncoder().encode(req.headers.get('x-render-token')||''))!==EXPECTED)return Response.json({error:'AUTH_REQUIRED'},{status:401});
  const p=await req.json();
  if(p.mode!=='SHADOW'||!['preflight','render','guardian'].includes(p.operation))throw Error('OPERATION_DENIED');
  const sb=createClient(BASE,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  const binding=await sb.from('sc_system_health').select('details').eq('component','staging_ready_fixture').single();
  if(binding.error||p.job_id!==binding.data.details.job_id)throw Error('JOB_BINDING');
  const j=await sb.from('sc_content_jobs').select('content_plan').eq('id',p.job_id).single();
  if(j.error||JSON.stringify(j.data.content_plan.quality_v2.pages[0])!==JSON.stringify(binding.data.details.plan))throw Error('FIXTURE_PLAN_BINDING');
  const result=await pipelineAction(p,sb);
  if(result.guardian_state==='PASS_PENDING_DURABLE_COMMIT'){
   // Timestamp only after authentic Guardian completed fresh byte/hash readback.
   const row=await sb.from('sc_content_jobs').select('qa').eq('id',p.job_id).single();
   if(row.error)throw Error('READBACK_RECEIPT_READ');
   const qa=row.data.qa;
   const saved=await sb.from('sc_content_jobs').update({qa:{...qa,quality_v2_runtime:{...qa.quality_v2_runtime,staging_readback_at:new Date().toISOString()}}}).eq('id',p.job_id).eq('status','QUALITY_V2_SHADOW_RENDERING');
   if(saved.error)throw Error('READBACK_RECEIPT_WRITE');
  }
  return Response.json(result);
 }catch(e){return Response.json({ok:false,error:String(e.message||e)},{status:422});}
});
