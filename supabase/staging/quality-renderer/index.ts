// Isolated diagnostic ONLY; cannot modify jobs, issue permits or mark READY.
import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {renderAction,sha} from './quality-render.ts';
import {preflightSequence,evaluate,canonical} from './quality.mjs';
const BASE='https://cmwervbwxyqzowntnxwe.supabase.co',EXPECTED='__TEMPORARY_SHA256__';
const plan={format:'image',layout:'statement',intent:'decision',scene:'none',theme:'cream',
 title:'Antes de decidir, revisá el alcance',body:'Pedí una propuesta clara con las condiciones del servicio.',cta:'Consultá los detalles',eyebrow:'TU PRÓXIMO PASO',
 argument_key:'scope_review',decision_key:'request_proposal',angle_key:'clear_conditions',hook_family:'checklist',added_value:'Revisar alcance y condiciones antes de decidir',fact_ids:[],revision:0};
Deno.serve(async req=>{
 try{
 if(req.method!=='POST'||Deno.env.get('SUPABASE_URL')!==BASE)return Response.json({error:'STAGING_ONLY'},{status:403});
 if(await sha(new TextEncoder().encode(req.headers.get('x-render-token')||''))!==EXPECTED)return Response.json({error:'AUTH_REQUIRED'},{status:401});
 const body=await req.json();if(body.plan||body.job_id)return Response.json({error:'NO_JOB_OR_PLAN_OVERRIDE'},{status:422});
 const sb=createClient(BASE,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 if(body.action==='seed'){
 const receipts=[];
 for(const bucket of ['instagram-media','solar-connects-assets']){
 const got=await sb.storage.getBucket(bucket);if(got.error){const made=await sb.storage.createBucket(bucket,{public:true,fileSizeLimit:10485760});if(made.error)throw made.error;}
 }
 for(const [name,path] of [['Roboto-Bold.ttf','src/hinted/Roboto-Bold.ttf'],['Roboto-Regular.ttf','src/hinted/Roboto-Regular.ttf'],['LICENSE','LICENSE']]){
 const r=await fetch('https://raw.githubusercontent.com/googlefonts/roboto-2/main/'+path);if(!r.ok)throw Error('FONT_SOURCE_'+r.status);
 const bytes=new Uint8Array(await r.arrayBuffer()),hash=await sha(bytes);
 if(name==='Roboto-Regular.ttf'&&hash!=='56a45233d29f11b4dfb86d248e921939d115778f87325e7ae8cc108383d6664d')throw Error('FONT_HASH_CHANGED');
 const target='fonts/'+name,old=await sb.storage.from('solar-connects-assets').download(target);
 if(old.data){if(await sha(new Uint8Array(await old.data.arrayBuffer()))!==hash)throw Error('IMMUTABLE_FONT_CONFLICT');}
 else{const put=await sb.storage.from('solar-connects-assets').upload(target,bytes,{contentType:name==='LICENSE'?'text/plain':'font/ttf',upsert:false});if(put.error)throw put.error;}
 receipts.push({name,sha256:hash,bytes:bytes.length});
 }return Response.json({ok:true,receipts});
 }
 if(body.action==='preflight'){
 const j=await sb.from('sc_content_jobs').select('id,status,content_plan,qa').eq('id','85beaf87-34d1-4684-b5ed-519c955e6637').single();if(j.error)throw j.error;
 return Response.json({job_id:j.data.id,status:j.data.status,preflight:preflightSequence(j.data.content_plan.quality_v2.pages,'image',0),claims:j.data.qa.claims_ledger?.length||0,mutations:0});
 }
 if(body.action==='render')return Response.json({...await renderAction({mode:'SHADOW',plan},sb),scope:'UNBOUND_DIAGNOSTIC',job_id:null});
 if(body.action==='assess'){
 const ph=await sha(new TextEncoder().encode(canonical(plan))),hash=String(body.asset_sha256||'');
 if(!/^[a-f0-9]{64}$/.test(hash))throw Error('HASH_REQUIRED');
 const b=await sb.storage.from('instagram-media').download('quality-v2-shadow/renders/'+ph+'/'+hash+'.jpg');if(b.error||!b.data||await sha(new Uint8Array(await b.data.arrayBuffer()))!==hash)throw Error('ASSET_READBACK_FAILED');
 return Response.json({scope:'UNBOUND_DIAGNOSTIC',assessment:evaluate(plan,body.critique,[],{asset_sha256:hash,plan_sha256:ph}),job_mutations:0,ready:false});
 }
 return Response.json({error:'ACTION_INVALID'},{status:400});
 }catch(e){return Response.json({error:String(e.message||e)},{status:422});}
});
