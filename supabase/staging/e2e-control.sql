-- STAGING cmwervbwxyqzowntnxwe ONLY. Never install on production.
create table sc_internal.e2e_window(
 id boolean primary key default true check(id), enabled boolean not null default false,
 expires_at timestamptz not null, command_id uuid not null unique, actor uuid not null,
 run_id uuid not null unique, plan_hash text not null, quality jsonb not null,
 session_id uuid, step_token uuid, step_until timestamptz, step_operation text,
 expected_plan jsonb, readback_at timestamptz, completed boolean not null default false
);
alter table sc_internal.e2e_window enable row level security;
revoke all on sc_internal.e2e_window from public,anon,authenticated,service_role;

-- Active/expired window fails closed for all non-SHADOW producers.
-- Updates are included so late annotations cannot turn a SHADOW bypass into production.
create function sc_internal.e2e_admission_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare w sc_internal.e2e_window; safe_shadow boolean; p sc_internal.factory_permits; rid uuid;
begin
 select * into w from sc_internal.e2e_window where id for share;
 if w.command_id is null then return new;end if;
 if tg_table_name<>'sc_content_jobs' then
 if exists(select 1 from sc_internal.factory_permits where command_id=w.command_id and job_id=new.job_id) then raise exception 'E2E_PUBLICATION_FORBIDDEN';end if;
 return new;end if;
 safe_shadow:=coalesce(new.qa->>'shadow'='true' and new.qa->>'do_not_publish'='true'
 and new.qa->>'publish_blocked'='true' and new.qa->>'production_candidate'='false'
 and new.qa->>'release_gate'='HOLD' and new.status not in ('PUBLISHING','PUBLISHED')
 and new.instagram_result='{}'::jsonb,false);
 if w.enabled and not safe_shadow then raise exception 'E2E_ADMISSION_CLOSED_TO_LEGACY_PRODUCTION';end if;
 rid:=coalesce(sc_internal.factory_run_uuid(new.qa->>'creative_run_id'),sc_internal.factory_run_uuid(new.content_plan->>'creative_run_id'),
 sc_internal.factory_run_uuid(substring(new.content_plan->>'idempotency_key' from '^quality-v2-shadow:factory_run_([0-9a-f]{32})$')));
 select * into p from sc_internal.factory_permits where command_id=w.command_id;
 if w.enabled and (new.qa ? 'factory_command_id' or new.qa->>'quality_v2_production_draft'='true')
 and new.id is distinct from p.job_id then raise exception 'E2E_OTHER_CONTROLLED_PRODUCER';end if;
 if rid=w.run_id or new.id=p.job_id then
 if not safe_shadow then raise exception 'E2E_PUBLICATION_FORBIDDEN';end if;
 if tg_op='UPDATE' then
 if old.content_plan is distinct from new.content_plan then raise exception 'E2E_PLAN_IMMUTABLE';end if;
 if old.status='READY' and new is distinct from old then raise exception 'E2E_READY_SEALED';end if;
 if new.status='READY' and current_setting('sc.e2e_finalize',true) is distinct from w.command_id::text then raise exception 'E2E_FINALIZER_REQUIRED';end if;
 end if;
 end if;
 return new;
end $$;
revoke all on function sc_internal.e2e_admission_guard() from public,anon,authenticated,service_role;
create trigger zz_e2e_admission before insert or update on public.sc_content_jobs for each row execute function sc_internal.e2e_admission_guard();
create trigger e2e_no_post before insert or update on public.sc_content_posts for each row execute function sc_internal.e2e_admission_guard();
create trigger e2e_no_publish_guard before insert or update on public.sc_publish_guard for each row execute function sc_internal.e2e_admission_guard();

create function sc_internal.e2e_assert(p_command uuid,p_token uuid,p_version bigint) returns void
language plpgsql security definer set search_path='' as $$
declare w sc_internal.e2e_window; c sc_internal.v5_commands; p sc_internal.factory_permits; op text; m jsonb;
begin
 select * into w from sc_internal.e2e_window where command_id=p_command for update;
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
 if public.sc_creative_compile_carousel_v1(w.run_id) is distinct from p.compiled_plan
 or sc_internal.factory_plan_hash(p.compiled_plan) is distinct from w.plan_hash
 or p.quality_input is distinct from w.quality then raise exception 'E2E_SOURCE_CONFLICT';end if;
 if (select content_plan from public.sc_content_jobs where id=p.job_id) is distinct from w.expected_plan then raise exception 'E2E_PLAN_CONFLICT';end if;
end $$;
revoke all on function sc_internal.e2e_assert(uuid,uuid,bigint) from public,anon,authenticated,service_role;

create or replace function public.sc_factory_e2e_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w sc_internal.e2e_window; c sc_internal.v5_commands; p sc_internal.factory_permits;
 a text:=p_request->>'action'; b jsonb:=p_request->'request'; r jsonb; j public.sc_content_jobs;
 tok uuid:=(p_request->>'claim_token')::uuid; ver bigint:=(p_request->>'lease_version')::bigint; m jsonb;
begin
 select * into w from sc_internal.e2e_window where id for update;
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
 r:=public.sc_factory_staging_v1(b);
 select * into c from sc_internal.v5_commands where command_id=w.command_id for update;
 if c.status<>'EXECUTING' then raise exception 'E2E_MATERIALIZATION_FAILED';end if;
 select * into p from sc_internal.factory_permits where command_id=w.command_id;
 update sc_internal.e2e_window set session_id=(auth.jwt()->>'session_id')::uuid,
 expected_plan=(select content_plan from public.sc_content_jobs where id=p.job_id) where id;
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
 update sc_internal.e2e_window set session_id=(auth.jwt()->>'session_id')::uuid,step_token=null,step_until=null where id;
 perform sc_internal.e2e_assert(w.command_id,tok,ver);
 end if;
 if a in ('ACQUIRE','RENEW','FINISH') then
 perform sc_internal.e2e_assert(w.command_id,tok,ver);
 if a='RENEW' then
 update sc_internal.v5_commands set claim_expires_at=least(clock_timestamp()+interval '5 minutes',w.expires_at) where command_id=w.command_id;
 update sc_internal.factory_permits set expires_at=least(clock_timestamp()+interval '5 minutes',w.expires_at) where command_id=w.command_id;
 elsif a='ACQUIRE' then
 if p_request->>'operation' not in ('preflight','render','guardian') then raise exception 'E2E_OPERATION';end if;
 if w.step_until>clock_timestamp() then raise exception 'E2E_STEP_BUSY';end if;
 update sc_internal.e2e_window set step_token=extensions.gen_random_uuid(),step_until=least(clock_timestamp()+interval '90 seconds',c.claim_expires_at),step_operation=p_request->>'operation' where id returning * into w;
 elsif a='FINISH' then
 if w.step_token is not null then raise exception 'E2E_STEP_UNSETTLED';end if;
 select * into j from public.sc_content_jobs where id=p.job_id for update;
 if w.readback_at is null or w.readback_at<clock_timestamp()-interval '10 minutes' then raise exception 'E2E_FRESH_GUARDIAN';end if;
 r:=public.sc_quality_shadow_record_v2(j.id,j.qa#>'{quality_v2_runtime,guardian_pending_evidence}');
 if r->>'ok' is distinct from 'true' then raise exception 'E2E_GUARDIAN %',r;end if;
 perform set_config('sc.e2e_finalize',w.command_id::text,true);
 update public.sc_content_jobs set status='READY',qa=qa||'{"do_not_publish":true,"publish_blocked":true,"release_gate":"HOLD","staging_only":true,"production_candidate":false,"quality_v2_phase":"STAGING_E2E_READY"}',updated_at=now() where id=j.id;
 perform sc_internal.e2e_assert(w.command_id,tok,ver);
 r:=public.sc_v5_command_complete_v1(w.command_id,tok,true,jsonb_build_object('job_id',j.id,'status','READY','guardian','PASS_SHADOW','publication_allowed',false,'lease_version',ver),null);
 if r->>'state' is distinct from 'SUCCEEDED' then raise exception 'E2E_COMPLETION';end if;
 update sc_internal.factory_permits set revoked_at=clock_timestamp() where command_id=w.command_id;
 update sc_internal.e2e_window set completed=true where id;
 end if;
 end if;
 select * into c from sc_internal.v5_commands where command_id=w.command_id;
 select * into w from sc_internal.e2e_window where id;
 return jsonb_build_object('command_id',c.command_id,'state',c.status,'job_id',p.job_id,'job_status',(select status from public.sc_content_jobs where id=p.job_id),
 'claim_token',c.claim_token,'lease_version',c.lease_version,'expires_at',c.claim_expires_at,'step_token',case when a='ACQUIRE' then w.step_token else null end,'result',c.result);
end $$;
revoke all on function public.sc_factory_e2e_v1(jsonb) from public,anon,service_role;
grant execute on function public.sc_factory_e2e_v1(jsonb) to authenticated;

-- Only the Edge worker's service client can submit progress, with a live step capability.
create function public.sc_factory_e2e_progress(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w sc_internal.e2e_window; perm sc_internal.factory_permits; j public.sc_content_jobs;
begin
 select * into w from sc_internal.e2e_window where command_id=(p->>'command_id')::uuid for update;
 perform sc_internal.e2e_assert(w.command_id,(p->>'claim_token')::uuid,(p->>'lease_version')::bigint);
 if w.step_token is null or w.step_token is distinct from (p->>'step_token')::uuid or w.step_until<=clock_timestamp() then raise exception 'E2E_STEP_FENCE';end if;
 select * into perm from sc_internal.factory_permits where command_id=w.command_id;
 select * into j from public.sc_content_jobs where id=perm.job_id for update;
 if p ? 'runtime' then
 update public.sc_content_jobs set qa=qa||jsonb_build_object('quality_v2_runtime',p->'runtime') where id=j.id;
 end if;
 if p->>'done'='true' then
 update sc_internal.e2e_window set step_token=null,step_until=null,
 readback_at=case when step_operation='guardian' and p->>'guardian_pass'='true' then clock_timestamp() else readback_at end where id;
 end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.sc_factory_e2e_progress(jsonb) from public,anon,authenticated;
grant execute on function public.sc_factory_e2e_progress(jsonb) to service_role;

create function sc_internal.e2e_completion_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from sc_internal.e2e_window where command_id=new.command_id)
 and new.status in ('SUCCEEDED','FAILED') and old.status is distinct from new.status
 and current_setting('sc.e2e_finalize',true) is distinct from new.command_id::text then
 raise exception 'E2E_FENCED_COMPLETION_REQUIRED';end if;
 return new;
end $$;
revoke all on function sc_internal.e2e_completion_guard() from public,anon,authenticated,service_role;
create trigger e2e_fenced_completion before update on sc_internal.v5_commands for each row execute function sc_internal.e2e_completion_guard();
