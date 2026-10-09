// TEMPORARY staging-only fixture. Deployed with a random SHA256 guard, then disabled.
import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
const URL='https://cmwervbwxyqzowntnxwe.supabase.co';
const EXPECTED='__ONE_TIME_SHA256__';
Deno.serve(async req=>{
 if(Deno.env.get('SUPABASE_URL')!==URL||req.method!=='POST')return new Response('disabled',{status:403});
 const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(req.headers.get('x-fixture-token')||'')))].map(x=>x.toString(16).padStart(2,'0')).join('');
 if(hash!==EXPECTED)return new Response('denied',{status:403});
 const admin=createClient(URL,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 const sessions=[];
 for(const role of ['operator','viewer']){
 const password=crypto.randomUUID()+crypto.randomUUID();
 const email=`factory-staging-${role}-${crypto.randomUUID()}@example.invalid`;
 const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,app_metadata:role==='operator'?{command_center:true,solar_role:'v5_operator'}:{}});
 if(error)return Response.json({error:error.message},{status:500});
 const client=createClient(URL,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false}});
 const signed=await client.auth.signInWithPassword({email,password});
 if(signed.error)return Response.json({error:signed.error.message},{status:500});
 sessions.push({role,user_id:data.user.id,access_token:signed.data.session!.access_token});
 }
 return Response.json({sessions},{headers:{'cache-control':'no-store'}});
});
