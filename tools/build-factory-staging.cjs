// Builds schema only from the already reviewed export. Never connects to a database.
const fs=require('node:fs');
const snapshot=JSON.parse(fs.readFileSync('supabase/staging/real-contracts.json'));
const privileges=JSON.parse(fs.readFileSync('supabase/staging/real-privileges.json'));
const ident=s=>'"'+s.replaceAll('"','""')+'"';
let sql=['-- STAGING ONLY cmwervbwxyqzowntnxwe. No production data.','create schema if not exists sc_internal; create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions; set check_function_bodies=off;'];
for(const t of snapshot.tables){
 for(const c of t.columns){const seq=c.default?.match(/nextval\('([^']+)'::regclass\)/)?.[1];if(seq)sql.push(`create sequence ${seq};`);}
 sql.push(`create table ${t.nspname}.${t.relname}(${t.columns.map(c=>`${ident(c.name)} ${c.type}${c.identity?` generated ${c.identity==='a'?'always':'by default'} as identity`:c.default?' default '+c.default:''}${c.notnull?' not null':''}`).join(',')});`);
}
for(const t of snapshot.tables){
 const table=t.nspname+'.'+t.relname;
 for(const c of t.constraints||[])sql.push(`alter table ${table} add constraint ${ident(c.name)} ${c.def};`);
 for(const idx of t.indexes||[])sql.push(idx.replace(/^CREATE (UNIQUE )?INDEX /,'CREATE $1INDEX IF NOT EXISTS ')+';');
 if(t.relrowsecurity)sql.push(`alter table ${table} enable row level security;`);
 if(t.relforcerowsecurity)sql.push(`alter table ${table} force row level security;`);
 if(t.policies)throw Error('Policy replay requires review');
 sql.push(`revoke all on ${table} from public,anon,authenticated,service_role;`);
 for(const acl of t.relacl.slice(1,-1).split(',')){
 const [role,p]=acl.split('=');const map={a:'insert',r:'select',w:'update',d:'delete',D:'truncate',x:'references',t:'trigger',m:'maintain'};
 const rights=[...p.split('/')[0]].filter(c=>map[c]).map(c=>map[c]);if(rights.length)sql.push(`grant ${rights.join(',')} on ${table} to ${ident(role)};`);
 }
}
for(const f of snapshot.functions)sql.push(f.def+';');
for(const t of snapshot.tables)for(const tr of t.triggers||[])sql.push(tr.function+';',tr.def+';');
for(const f of privileges.functions){
 sql.push(`revoke all on function public.${f.identity} from public,anon,authenticated,service_role;`);
 for(const acl of f.acl||[]){const role=acl.split('=')[0];sql.push(`grant execute on function public.${f.identity} to ${role?ident(role):'public'};`);}
}
sql.push(`insert into public.sc_agent_config(id,config) values('solar_connects_v1','{"security_control_plane_v1":{"kill_switches":{"factory":{"allow":false},"publisher":{"allow":false},"meta_direct":{"allow":false},"external_write":{"allow":false}}},"publishing_policy":{"max_feed_posts_per_day":1}}');
insert into public.sc_system_health(component,status,details) values('solar_quality_v2_production_flags','STAGE1_FROZEN_OBSERVATION','{"enabled":true,"formats":{"image":{"kill_switch":true},"carousel":{"kill_switch":true},"story":{"kill_switch":true},"reel":{"kill_switch":true}}}'),('solar_quality_v2_first_slot','CONFIRMED_FROZEN','{"enabled":true,"state":"CONFIRMED_FROZEN"}');`);
fs.writeFileSync('supabase/staging/bootstrap.sql',sql.join('\n'));
