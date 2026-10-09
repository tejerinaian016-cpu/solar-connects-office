import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
const URL='https://cmwervbwxyqzowntnxwe.supabase.co';
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:{'cache-control':'no-store'}});
Deno.serve(async(req)=>{
 if(req.method!=='POST')return reply({error:'METHOD'},405);
 if(Deno.env.get('SUPABASE_URL')!==URL)return reply({error:'STAGING_PROJECT_REQUIRED'},503);
 const token=req.headers.get('authorization')?.replace(/^Bearer /,'');
 if(!token)return reply({error:'AUTH_REQUIRED'},401);
 const client=createClient(URL,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error}=await client.auth.getUser(token);
 if(error||!data.user)return reply({error:'AUTH_INVALID'},401);
 const m=data.user.app_metadata;
 if(m.command_center!==true||!(m.solar_role==='v5_operator'||m.roles?.includes('v5_operator')))return reply({error:'OPERATOR_REQUIRED'},403);
 let body;try{body=await req.json();}catch{return reply({error:'JSON_REQUIRED'},400);}
 const {data:result,error:rpcError}=await client.rpc('sc_factory_staging_v1',{p_request:body});
 if(rpcError)return reply({error:rpcError.message,code:rpcError.code},409);
 return reply(result);
});
