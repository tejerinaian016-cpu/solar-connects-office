import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {pipelineAction} from './pipeline.ts';
const URL='https://cmwervbwxyqzowntnxwe.supabase.co';
Deno.serve(async req=>{
 if(req.method!=='POST'||Deno.env.get('SUPABASE_URL')!==URL)return Response.json({error:'STAGING_ONLY'},{status:403});
 const token=req.headers.get('authorization')?.replace(/^Bearer /,'');
 if(!token)return Response.json({error:'AUTH_REQUIRED'},{status:401});
 const client=createClient(URL,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:'Bearer '+token}},auth:{persistSession:false,autoRefreshToken:false}});
 const user=await client.auth.getUser(token);
 if(user.error||!user.data.user)return Response.json({error:'AUTH_INVALID'},{status:401});
 const m=user.data.user.app_metadata;
 if(m.command_center!==true||m.solar_role!=='v5_operator')return Response.json({error:'OPERATOR_REQUIRED'},{status:403});
 try{
 const body=await req.json();
 const call=async p=>{const r=await client.rpc('sc_factory_e2e_v1',{p_request:p});if(r.error)throw Error(r.error.message);return r.data;};
 if(body.action!=='STEP')return Response.json(await call(body));
 const lease=await call({...body,action:'ACQUIRE'});
 const admin=createClient(URL,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 const fence={command_id:body.command_id,claim_token:body.claim_token,lease_version:body.lease_version,step_token:lease.step_token};
 const progress=async patch=>{const r=await admin.rpc('sc_factory_e2e_progress',{p:{...fence,...patch}});if(r.error)throw Error(r.error.message);return r.data;};
 // Preserve authentic pipeline reads and route its progress writes through fencing.
 const sb={rpc:(...a)=>admin.rpc(...a),storage:admin.storage,from(name){
 const builder=admin.from(name);
 if(name!=='sc_content_jobs')return builder;
 return {select:(...a)=>builder.select(...a),update(value){
 const q={eq(){return q},then(resolve,reject){return progress({runtime:value.qa.quality_v2_runtime}).then(()=>resolve({error:null}),reject)}};
 return q;
 }};
 }};
 const result=await pipelineAction({mode:'SHADOW',operation:body.operation,job_id:lease.job_id,page_index:0,critiques:body.critiques,history:[]},sb);
 await progress({done:true,guardian_pass:result.guardian_state==='PASS_PENDING_DURABLE_COMMIT'});
 return Response.json(result);
 }catch(e){return Response.json({ok:false,error:String(e.message||e)},{status:409});}
});
