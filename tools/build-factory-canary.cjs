// Deterministic adaptation of the approved E2E; no deployment or gate changes.
const fs=require('fs'),crypto=require('crypto');
const read=p=>fs.readFileSync(p,'utf8').replaceAll('\r\n','\n');
const source=read('supabase/staging/e2e-control.sql');
let s=source.replace('-- STAGING cmwervbwxyqzowntnxwe ONLY. Never install on production.',
'-- CANDIDATE: tested in staging only. Installation does not authorize/activate a canary.');
s=s.replace(' id boolean primary key default true check(id), enabled boolean not null default false,',' enabled boolean not null default false,');
s=s.replace('command_id uuid not null unique','command_id uuid primary key');
s=s.replace(' run_id uuid not null unique, plan_hash text not null, quality jsonb not null,',' run_id uuid not null unique, plan_hash text not null, quality jsonb not null,\n policy_epoch text not null, approval jsonb not null,');
s=s.replaceAll('sc_internal.e2e_window','sc_internal.factory_canaries')
.replaceAll('sc_internal.e2e_','sc_internal.canary_')
.replaceAll('public.sc_factory_e2e_progress','public.sc_factory_canary_progress')
.replaceAll('public.sc_factory_e2e_v1','public.sc_factory_canary_v1')
.replaceAll('public.sc_factory_staging_v1','sc_internal.factory_canary_start')
.replaceAll('sc.e2e_finalize','sc.canary_finalize')
.replaceAll('zz_e2e_admission','zz_canary_admission')
.replaceAll('e2e_no_post','canary_no_post').replaceAll('e2e_no_publish_guard','canary_no_publish_guard')
.replaceAll('e2e_fenced_completion','canary_fenced_completion')
.replaceAll("'staging_only':true","'staging_only':true")
.replaceAll('"staging_only":true,','')
.replaceAll('STAGING_E2E_READY','CANARY_READY_BLOCKED');
// Every runtime update is scoped to the command. No single mutable authorization slot.
s=s.replaceAll('where id for update','where command_id=(p_request->>\'command_id\')::uuid for update');
s=s.replaceAll('where id returning * into w','where command_id=w.command_id returning * into w');
s=s.replaceAll('where id;','where command_id=w.command_id;');
s=s.replaceAll('begin\n select * into w from sc_internal.factory_canaries',
'begin\n perform pg_catalog.pg_advisory_xact_lock(701628340);\n select * into w from sc_internal.factory_canaries');
const start=s.indexOf('create function sc_internal.canary_admission_guard()');
const end=s.indexOf('revoke all on function sc_internal.canary_admission_guard()',start);
s=s.slice(0,start)+read('supabase/candidate/canary-admission.sql')+'\n'+s.slice(end);
s=s.replace(" if public.sc_security_operation_gate_v1('FACTORY')->>'allowed' is distinct from 'true' then raise exception 'E2E_EMERGENCY_OFF';end if;",
` if public.sc_security_operation_gate_v1('FACTORY')->>'allowed' is distinct from 'true' then raise exception 'E2E_EMERGENCY_OFF';end if;
 if not exists(select 1 from public.sc_system_health where component='solar_quality_v2_production_flags'
 and status not like '%FROZEN%' and details->>'epoch'=w.policy_epoch
 and details->>'enabled'='true' and details#>>'{formats,image,kill_switch}'='false') then raise exception 'CANARY_QUALITY_FROZEN_OR_CHANGED';end if;`);
let bridge=read('supabase/staging/bridge.sql')
.replace('-- STAGING ONLY. Caller identity comes from verified Supabase JWT, not request JSON.','-- Existing authenticated start contract; private to the canary wrapper.')
.replaceAll('public.sc_factory_staging_v1','sc_internal.factory_canary_start')
.replace('grant execute on function sc_internal.factory_canary_start(jsonb) to authenticated;','revoke all on function sc_internal.factory_canary_start(jsonb) from authenticated;');
s=s.replace('create or replace function public.sc_factory_canary_v1',()=>bridge+'\ncreate or replace function public.sc_factory_canary_v1');
s+='\n'+read('supabase/candidate/canary-registry.sql');
fs.writeFileSync('supabase/candidate/factory-canary-install.sql',s);
let edge=read('supabase/staging/quality-renderer/e2e-worker.ts')
.replace("const URL='https://cmwervbwxyqzowntnxwe.supabase.co';",
"const project=Deno.env.get('FACTORY_CANARY_PROJECT_REF');\nconst URL=project?'https://'+project+'.supabase.co':'';")
.replace(" if(req.method!=='POST'||Deno.env.get('SUPABASE_URL')!==URL)",
" if(Deno.env.get('FACTORY_CANARY_ENABLED')!=='true')return Response.json({error:'CANARY_DISABLED'},{status:410});\n if(!/^[a-z]{20}$/.test(project||'')||req.method!=='POST'||Deno.env.get('SUPABASE_URL')!==URL)")
.replaceAll('sc_factory_e2e_v1','sc_factory_canary_v1').replaceAll('sc_factory_e2e_progress','sc_factory_canary_progress');
fs.writeFileSync('supabase/candidate/factory-canary-edge.ts',edge);
const manifest={source_commit:'8f73ae0b9a72501328eaa6f8737d7fff573471fb',generated_from_approved_e2e:true,activation:false,
 files:Object.fromEntries(['supabase/staging/e2e-control.sql','supabase/staging/bridge.sql','supabase/staging/quality-renderer/e2e-worker.ts','supabase/candidate/factory-canary-install.sql','supabase/candidate/factory-canary-edge.ts'].map(p=>[p,crypto.createHash('sha256').update(read(p)).digest('hex')]))};
fs.writeFileSync('supabase/candidate/factory-canary-manifest.json',JSON.stringify(manifest,null,2)+'\n');
