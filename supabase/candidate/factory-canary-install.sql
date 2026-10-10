-- CANDIDATE: tested in staging only. Installation does not authorize/activate a canary.
create table sc_internal.factory_canaries(
 enabled boolean not null default false,
 expires_at timestamptz not null, command_id uuid primary key, actor uuid not null,
 run_id uuid not null unique, plan_hash text not null, quality jsonb not null,
 policy_epoch text not null, approval jsonb not null,
 session_id uuid, step_token uuid, step_until timestamptz, step_operation text,
 expected_plan jsonb, readback_at timestamptz, completed boolean not null default false
);
alter table sc_internal.factory_canaries enable row level security;
revoke all on sc_internal.factory_canaries from public,anon,authenticated,service_role;

-- Active/expired window fails closed for all non-SHADOW producers.
-- Updates are included so late annotations cannot turn a SHADOW bypass into production.
create function sc_internal.canary_admission_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare active sc_internal.factory_canaries; bound sc_internal.factory_canaries; permit_row sc_internal.factory_permits; safe_shadow boolean;
begin
 -- Activation takes the exclusive counterpart: no insert can cross an activation race.
 perform pg_catalog.pg_advisory_xact_lock_shared(701628340);
 select * into active from sc_internal.factory_canaries where enabled for share;
 if tg_table_name<>'sc_content_jobs' then
 if exists(select 1 from sc_internal.factory_canaries w join sc_internal.factory_permits p using(command_id) where p.job_id=new.job_id) then raise exception 'CANARY_PUBLICATION_FORBIDDEN';end if;
 return new;end if;
 select w.* into bound from sc_internal.factory_canaries w left join sc_internal.factory_permits p using(command_id)
 where p.job_id=new.id or w.run_id in(
 sc_internal.factory_run_uuid(new.qa->>'creative_run_id'),
 sc_internal.factory_run_uuid(new.content_plan->>'creative_run_id'),
 sc_internal.factory_run_uuid(substring(new.content_plan->>'idempotency_key' from '^quality-v2-shadow:factory_run_([0-9a-f]{32})$')))
 limit 1 for share of w;
 safe_shadow:=coalesce(new.qa->>'shadow'='true' and new.qa->>'do_not_publish'='true'
 and new.qa->>'publish_blocked'='true' and new.qa->>'production_candidate'='false'
 and new.qa->>'release_gate'='HOLD' and upper(new.status) not in ('PUBLISHING','PUBLISHED')
 and new.instagram_result='{}'::jsonb,false);
 if active.command_id is not null then
 if not safe_shadow then raise exception 'CANARY_LEGACY_ADMISSION_CLOSED';end if;
 if (new.qa ? 'factory_command_id' or new.qa->>'quality_v2_production_draft'='true')
 and bound.command_id is distinct from active.command_id then raise exception 'CANARY_OTHER_PRODUCER';end if;
 end if;
 if bound.command_id is not null then
 if not safe_shadow then raise exception 'CANARY_PUBLICATION_FORBIDDEN';end if;
 select * into permit_row from sc_internal.factory_permits where command_id=bound.command_id;
 if tg_op='INSERT' and (permit_row.active_xid is distinct from txid_current() or permit_row.job_id is distinct from new.id) then raise exception 'CANARY_TRANSACTION_PERMIT';end if;
 if tg_op='UPDATE' then
 if old.content_plan is distinct from new.content_plan then raise exception 'CANARY_PLAN_IMMUTABLE';end if;
 if old.status='READY' and new is distinct from old then raise exception 'CANARY_READY_SEALED';end if;
 if new.status='READY' and current_setting('sc.canary_finalize',true) is distinct from bound.command_id::text then raise exception 'CANARY_FINALIZER_REQUIRED';end if;
 end if;
 end if;
 return new;
end $$;

revoke all on function sc_internal.canary_admission_guard() from public,anon,authenticated,service_role;
create trigger zz_canary_admission before insert or update on public.sc_content_jobs for each row execute function sc_internal.canary_admission_guard();
create trigger canary_no_post before insert or update on public.sc_content_posts for each row execute function sc_internal.canary_admission_guard();
create trigger canary_no_publish_guard before insert or update on public.sc_publish_guard for each row execute function sc_internal.canary_admission_guard();

create function sc_internal.canary_assert(p_command uuid,p_token uuid,p_version bigint) returns void
language plpgsql security definer set search_path='' as $$
declare w sc_internal.factory_canaries; c sc_internal.v5_commands; p sc_internal.factory_permits; op text; m jsonb;
begin
 perform pg_catalog.pg_advisory_xact_lock(701628340);
 select * into w from sc_internal.factory_canaries where command_id=p_command for update;
 if w.command_id is null or not w.enabled or w.expires_at<=clock_timestamp() then raise exception 'E2E_WINDOW_CLOSED';end if;
 select * into c from sc_internal.v5_commands where command_id=p_command for update;
 select * into p from sc_internal.factory_permits where command_id=p_command for update;
 if c.status<>'EXECUTING' or c.actor_user_id<>w.actor or p.revoked_at is not null
 or c.claim_token is distinct from p_token or p.claim_token is distinct from p_token
 or c.lease_version is distinct from p_version or p.lease_version is distinct from p_version
 or c.claim_expires_at<=clock_timestamp() or p.expires_at<=clock_timestamp()
 then raise exception 'E2E_FENCE_OR_LEASE';end if;
 select raw_app_meta_data into m from auth.users where id=w.actor for share;
 if m->>'command_center' is distinct from 'true' or not coalesce(m->>'solar_role'='v5_operator' or m->'roles' ? 'v5_operator',false) then raise exception 'E2E_OPERATOR_REVOKED';end if;
 if not exists(select 1 from auth.sessions where id=w.session_id and user_id=w.actor and (not_after is null or not_after>clock_timestamp())) then raise exception 'E2E_SESSION_REVOKED';end if;
 foreach op in array array['PUBLISHER','META_DIRECT','EXTERNAL_WRITE'] loop
 if public.sc_security_operation_gate_v1(op)->>'allowed' is distinct from 'false' then raise exception 'E2E_PUBLICATION_GATE';end if;end loop;
 if public.sc_security_operation_gate_v1('FACTORY')->>'allowed' is distinct from 'true' then raise exception 'E2E_EMERGENCY_OFF';end if;
 if not exists(select 1 from public.sc_system_health where component='solar_quality_v2_production_flags'
 and status not like '%FROZEN%' and details->>'epoch'=w.policy_epoch
 and details->>'enabled'='true' and details#>>'{formats,image,kill_switch}'='false') then raise exception 'CANARY_QUALITY_FROZEN_OR_CHANGED';end if;
 if public.sc_creative_compile_carousel_v1(w.run_id) is distinct from p.compiled_plan
 or sc_internal.factory_plan_hash(p.compiled_plan) is distinct from w.plan_hash
 or p.quality_input is distinct from w.quality then raise exception 'E2E_SOURCE_CONFLICT';end if;
 if (select content_plan from public.sc_content_jobs where id=p.job_id) is distinct from w.expected_plan then raise exception 'E2E_PLAN_CONFLICT';end if;
end $$;
revoke all on function sc_internal.canary_assert(uuid,uuid,bigint) from public,anon,authenticated,service_role;

-- Existing authenticated start contract; private to the canary wrapper.
create function sc_internal.factory_canary_start(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b jsonb:=p_request->'command'; phase text:=p_request->>'phase';
 c sc_internal.v5_commands%rowtype; p sc_internal.factory_permits%rowtype;
 actor uuid:=auth.uid(); meta jsonb; hash text; claim jsonb; result jsonb; command uuid;
begin
 if actor is null then raise exception 'AUTH_REQUIRED'; end if;
 select raw_app_meta_data into meta from auth.users where id=actor for share;
 if meta->>'command_center' is distinct from 'true' or not coalesce(meta->>'solar_role'='v5_operator' or meta->'roles' ? 'v5_operator',false) then raise exception 'OPERATOR_REQUIRED'; end if;
 perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=actor and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise exception 'SESSION_REVOKED'; end if;
 command:=(b->>'command_id')::uuid;
 if b->>'requested_action' is distinct from 'factory.start' or b->>'mode' is distinct from 'EXECUTE'
 or b#>>'{confirmation,confirmed}' is distinct from 'true' or b#>>'{confirmation,intent}' is distinct from 'REAL_EXECUTION'
 or b#>>'{confirmation,token}' is distinct from 'REAL:'||command||':'||(b->>'idempotency_key')||':factory.start:'||(b#>>'{payload,creative_run_id}')||':'||(b#>>'{payload,compiled_plan_sha256}')
 then raise exception 'COMMAND_CONFIRMATION_REQUIRED'; end if;
 hash:=public.sc_v5_command_request_hash_v1('factory.start',b->'target',b->'payload','REAL_EXECUTION','EXECUTE');
 select * into c from sc_internal.v5_commands where actor_user_id=actor and idempotency_key=b->>'idempotency_key';
 if c.command_id is not null and (c.command_id<>command or c.request_hash<>hash) then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
 if phase in ('RECONCILE','CLOSE') then
 if c.command_id is null then return jsonb_build_object('ok',false,'state','NOT_FOUND'); end if;
 select * into p from sc_internal.factory_permits where command_id=command;
 if phase='CLOSE' and p.command_id is not null then
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('factory-run:'||p.creative_run_id,0));
 update sc_internal.factory_permits set revoked_at=coalesce(revoked_at,clock_timestamp()) where command_id=command;
 end if;
 return jsonb_build_object('ok',true,'state',case when phase='CLOSE' then 'CLOSED' else c.status end,'command_id',command,'job_id',p.job_id,'job_status',(select status from public.sc_content_jobs where id=p.job_id),'consumed',p.consumed_at is not null,'ready',false);
 end if;
 if phase is distinct from 'EXECUTE' then raise exception 'PHASE_INVALID'; end if;
 -- Existing result is reconciled, never re-materialized or reclaimed after ambiguity.
 if c.command_id is not null then
 select * into p from sc_internal.factory_permits where command_id=command;
 return jsonb_build_object('ok',true,'state',case when p.job_id is not null then 'DUPLICATE' else 'RECONCILE_REQUIRED' end,'job_id',p.job_id,'ready',false);
 end if;
 claim:=public.sc_v5_command_claim_v1(command,actor,b->>'idempotency_key','factory.start',b->'target',b->'payload','REAL_EXECUTION','EXECUTE',null,120);
 if claim->>'state' is distinct from 'CLAIMED' then return claim; end if;
 perform sc_internal.factory_authorize(command,(claim->>'claim_token')::uuid,(claim->>'lease_version')::bigint,b#>>'{confirmation,token}',p_request->'quality',(p_request->>'slot')::integer);
 result:=sc_internal.factory_materialize(command,(claim->>'claim_token')::uuid,(claim->>'lease_version')::bigint,b#>>'{payload,compiled_plan_sha256}',p_request->'quality',(p_request->>'slot')::integer);
 return result||jsonb_build_object('command_id',command,'ready',false);
 -- No catch: failed authorization/materialization rolls back the claim and audit too.
end $$;
revoke all on function sc_internal.factory_canary_start(jsonb) from public,anon,service_role;
revoke all on function sc_internal.factory_canary_start(jsonb) from authenticated;

create or replace function public.sc_factory_canary_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w sc_internal.factory_canaries; c sc_internal.v5_commands; p sc_internal.factory_permits;
 a text:=p_request->>'action'; b jsonb:=p_request->'request'; r jsonb; j public.sc_content_jobs;
 tok uuid:=(p_request->>'claim_token')::uuid; ver bigint:=(p_request->>'lease_version')::bigint; m jsonb;
begin
 perform pg_catalog.pg_advisory_xact_lock(701628340);
 select * into w from sc_internal.factory_canaries where command_id=(p_request->>'command_id')::uuid for update;
 if auth.uid() is null or auth.uid() is distinct from w.actor then raise exception 'E2E_ACTOR';end if;
 select raw_app_meta_data into m from auth.users where id=auth.uid() for share;
 if m->>'command_center' is distinct from 'true' or not coalesce(m->>'solar_role'='v5_operator' or m->'roles' ? 'v5_operator',false) then raise exception 'E2E_OPERATOR';end if;
 if not exists(select 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=auth.uid() and (not_after is null or not_after>clock_timestamp())) then raise exception 'E2E_SESSION';end if;
 if p_request->>'command_id' is distinct from w.command_id::text then raise exception 'E2E_COMMAND';end if;
 select * into c from sc_internal.v5_commands where command_id=w.command_id for update;
 if a='START' then
 if b#>>'{command,command_id}' is distinct from w.command_id::text
 or b#>>'{command,payload,creative_run_id}' is distinct from w.run_id::text
 or b#>>'{command,payload,compiled_plan_sha256}' is distinct from w.plan_hash
 or b->'quality' is distinct from w.quality or b->>'slot' is distinct from '1' then raise exception 'E2E_AUTHORIZATION_BINDING';end if;
 if c.command_id is null then
 if not w.enabled or w.expires_at<=clock_timestamp() then raise exception 'E2E_WINDOW_CLOSED';end if;
 r:=sc_internal.factory_canary_start(b);
 select * into c from sc_internal.v5_commands where command_id=w.command_id for update;
 if c.status<>'EXECUTING' then raise exception 'E2E_MATERIALIZATION_FAILED';end if;
 select * into p from sc_internal.factory_permits where command_id=w.command_id;
 update sc_internal.factory_canaries set session_id=(auth.jwt()->>'session_id')::uuid,
 expected_plan=(select content_plan from public.sc_content_jobs where id=p.job_id) where command_id=w.command_id;
 else
 if c.idempotency_key is distinct from b#>>'{command,idempotency_key}'
 or b#>>'{command,confirmation,token}' is distinct from 'REAL:'||c.command_id||':'||c.idempotency_key||':factory.start:'||w.run_id||':'||w.plan_hash
 then raise exception 'E2E_REPLAY_CONFLICT';end if;
 if c.request_hash is distinct from public.sc_v5_command_request_hash_v1('factory.start',b#>'{command,target}',b#>'{command,payload}','REAL_EXECUTION','EXECUTE') then raise exception 'E2E_REPLAY_CONFLICT';end if;
 end if;
 elsif a not in ('RECONCILE','ACQUIRE','RENEW','RECOVER','FINISH') then raise exception 'E2E_ACTION';end if;
 select * into p from sc_internal.factory_permits where command_id=w.command_id for update;
 if c.command_id is null or p.job_id is null then raise exception 'E2E_NO_JOB';end if;
 if a='FINISH' and c.status='SUCCEEDED' then
 if c.claim_token is distinct from tok or c.lease_version is distinct from ver then raise exception 'E2E_COMPLETED_FENCE';end if;
 if not exists(select 1 from public.sc_content_jobs where id=p.job_id and status='READY' and qa->>'publish_blocked'='true' and qa->>'do_not_publish'='true') then raise exception 'E2E_RESULT_CONFLICT';end if;
 a:='RECONCILE';
 end if;
 if a='RECOVER' then
 if not w.enabled or w.expires_at<=clock_timestamp() or p.revoked_at is not null then raise exception 'E2E_WINDOW_CLOSED';end if;
 if c.status<>'EXECUTING' or c.claim_token is distinct from tok or c.lease_version is distinct from ver
 or c.claim_expires_at>clock_timestamp() or w.step_until>clock_timestamp() then raise exception 'E2E_RECOVERY_FENCE';end if;
 tok:=extensions.gen_random_uuid();ver:=ver+1;
 update sc_internal.v5_commands set claim_token=tok,lease_version=ver,claim_expires_at=least(clock_timestamp()+interval '5 minutes',w.expires_at),updated_at=clock_timestamp() where command_id=w.command_id;
 update sc_internal.factory_permits set claim_token=tok,lease_version=ver,expires_at=least(clock_timestamp()+interval '5 minutes',w.expires_at) where command_id=w.command_id;
 update sc_internal.factory_canaries set session_id=(auth.jwt()->>'session_id')::uuid,step_token=null,step_until=null where command_id=w.command_id;
 perform sc_internal.canary_assert(w.command_id,tok,ver);
 end if;
 if a in ('ACQUIRE','RENEW','FINISH') then
 perform sc_internal.canary_assert(w.command_id,tok,ver);
 if a='RENEW' then
 update sc_internal.v5_commands set claim_expires_at=least(clock_timestamp()+interval '5 minutes',w.expires_at) where command_id=w.command_id;
 update sc_internal.factory_permits set expires_at=least(clock_timestamp()+interval '5 minutes',w.expires_at) where command_id=w.command_id;
 elsif a='ACQUIRE' then
 if p_request->>'operation' not in ('preflight','render','guardian') then raise exception 'E2E_OPERATION';end if;
 if w.step_until>clock_timestamp() then raise exception 'E2E_STEP_BUSY';end if;
 update sc_internal.factory_canaries set step_token=extensions.gen_random_uuid(),step_until=least(clock_timestamp()+interval '90 seconds',c.claim_expires_at),step_operation=p_request->>'operation' where command_id=w.command_id returning * into w;
 elsif a='FINISH' then
 if w.step_token is not null then raise exception 'E2E_STEP_UNSETTLED';end if;
 select * into j from public.sc_content_jobs where id=p.job_id for update;
 if w.readback_at is null or w.readback_at<clock_timestamp()-interval '10 minutes' then raise exception 'E2E_FRESH_GUARDIAN';end if;
 r:=public.sc_quality_shadow_record_v2(j.id,j.qa#>'{quality_v2_runtime,guardian_pending_evidence}');
 if r->>'ok' is distinct from 'true' then raise exception 'E2E_GUARDIAN %',r;end if;
 perform set_config('sc.canary_finalize',w.command_id::text,true);
 update public.sc_content_jobs set status='READY',qa=qa||'{"do_not_publish":true,"publish_blocked":true,"release_gate":"HOLD","production_candidate":false,"quality_v2_phase":"CANARY_READY_BLOCKED"}',updated_at=now() where id=j.id;
 perform sc_internal.canary_assert(w.command_id,tok,ver);
 r:=public.sc_v5_command_complete_v1(w.command_id,tok,true,jsonb_build_object('job_id',j.id,'status','READY','guardian','PASS_SHADOW','publication_allowed',false,'lease_version',ver),null);
 if r->>'state' is distinct from 'SUCCEEDED' then raise exception 'E2E_COMPLETION';end if;
 update sc_internal.factory_permits set revoked_at=clock_timestamp() where command_id=w.command_id;
 update sc_internal.factory_canaries set completed=true where command_id=w.command_id;
 end if;
 end if;
 select * into c from sc_internal.v5_commands where command_id=w.command_id;
 select * into w from sc_internal.factory_canaries where command_id=w.command_id;
 return jsonb_build_object('command_id',c.command_id,'state',c.status,'job_id',p.job_id,'job_status',(select status from public.sc_content_jobs where id=p.job_id),
 'claim_token',c.claim_token,'lease_version',c.lease_version,'expires_at',c.claim_expires_at,'step_token',case when a='ACQUIRE' then w.step_token else null end,'result',c.result);
end $$;
revoke all on function public.sc_factory_canary_v1(jsonb) from public,anon,service_role;
grant execute on function public.sc_factory_canary_v1(jsonb) to authenticated;

-- Only the Edge worker's service client can submit progress, with a live step capability.
create function public.sc_factory_canary_progress(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w sc_internal.factory_canaries; perm sc_internal.factory_permits; j public.sc_content_jobs;
begin
 perform pg_catalog.pg_advisory_xact_lock(701628340);
 select * into w from sc_internal.factory_canaries where command_id=(p->>'command_id')::uuid for update;
 perform sc_internal.canary_assert(w.command_id,(p->>'claim_token')::uuid,(p->>'lease_version')::bigint);
 if w.step_token is null or w.step_token is distinct from (p->>'step_token')::uuid or w.step_until<=clock_timestamp() then raise exception 'E2E_STEP_FENCE';end if;
 select * into perm from sc_internal.factory_permits where command_id=w.command_id;
 select * into j from public.sc_content_jobs where id=perm.job_id for update;
 if p ? 'runtime' then
 update public.sc_content_jobs set qa=qa||jsonb_build_object('quality_v2_runtime',p->'runtime') where id=j.id;
 end if;
 if p->>'done'='true' then
 update sc_internal.factory_canaries set step_token=null,step_until=null,
 readback_at=case when step_operation='guardian' and p->>'guardian_pass'='true' then clock_timestamp() else readback_at end where command_id=w.command_id;
 end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.sc_factory_canary_progress(jsonb) from public,anon,authenticated;
grant execute on function public.sc_factory_canary_progress(jsonb) to service_role;

create function sc_internal.canary_completion_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from sc_internal.factory_canaries where command_id=new.command_id)
 and new.status in ('SUCCEEDED','FAILED') and old.status is distinct from new.status
 and current_setting('sc.canary_finalize',true) is distinct from new.command_id::text then
 raise exception 'E2E_FENCED_COMPLETION_REQUIRED';end if;
 return new;
end $$;
revoke all on function sc_internal.canary_completion_guard() from public,anon,authenticated,service_role;
create trigger canary_fenced_completion before update on sc_internal.v5_commands for each row execute function sc_internal.canary_completion_guard();

create unique index factory_one_enabled_canary on sc_internal.factory_canaries(enabled) where enabled;

create function sc_internal.canary_registry_lock() returns trigger
language plpgsql set search_path='' as $$
begin perform pg_catalog.pg_advisory_xact_lock(701628340);return null;end $$;
revoke all on function sc_internal.canary_registry_lock() from public,anon,authenticated,service_role;
create trigger canary_registry_lock before insert or update or delete on sc_internal.factory_canaries
for each statement execute function sc_internal.canary_registry_lock();

create function sc_internal.canary_registry_guard() returns trigger
language plpgsql set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(701628340);
 if tg_op='DELETE' then raise exception 'CANARY_HISTORY_PERMANENT';end if;
 if tg_op='UPDATE' then
 if row(new.command_id,new.actor,new.run_id,new.plan_hash,new.quality,new.policy_epoch,new.approval,new.expires_at)
 is distinct from row(old.command_id,old.actor,old.run_id,old.plan_hash,old.quality,old.policy_epoch,old.approval,old.expires_at)
 then raise exception 'CANARY_AUTHORIZATION_IMMUTABLE';end if;
 if old.expected_plan is not null and new.expected_plan is distinct from old.expected_plan then raise exception 'CANARY_PLAN_IMMUTABLE';end if;
 end if;
 if new.enabled and (new.completed or exists(select 1 from sc_internal.factory_permits where command_id=new.command_id and revoked_at is not null)) then raise exception 'CANARY_CANNOT_REARM';end if;
 if new.enabled and (new.expires_at<=clock_timestamp() or new.approval->>'authorized' is distinct from 'true'
 or coalesce(new.approval->>'evidence_ref','')='' or new.approval->>'command_id' is distinct from new.command_id::text
 or new.approval->>'plan_hash' is distinct from new.plan_hash
 or new.approval->>'run_id' is distinct from new.run_id::text
 or new.approval->>'actor' is distinct from new.actor::text
 or new.approval->>'quality_sha256' is distinct from encode(extensions.digest(new.quality::text,'sha256'),'hex')
 or new.approval->>'policy_epoch' is distinct from new.policy_epoch
 or (new.approval->>'expires_at')::timestamptz is distinct from new.expires_at
 or new.approval->>'max_jobs' is distinct from '1' or new.approval->>'stop_at' is distinct from 'READY')
 then raise exception 'CANARY_EXPLICIT_APPROVAL_REQUIRED';end if;
 return new;
end $$;
revoke all on function sc_internal.canary_registry_guard() from public,anon,authenticated,service_role;
create trigger canary_registry_immutable before insert or update or delete on sc_internal.factory_canaries
for each row execute function sc_internal.canary_registry_guard();

-- No public provisioning, activation or expiry extension API. DBA approval transaction only.
