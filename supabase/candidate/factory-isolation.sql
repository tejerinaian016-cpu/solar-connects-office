-- LOCAL CANDIDATE ONLY. Not a deployment migration. No gates/policies are updated.
-- Scoped to reserved runs/controlled markers; legacy unreserved producers retain their contracts.
begin;
create table sc_internal.factory_permits (
 command_id uuid primary key references sc_internal.v5_commands(command_id),
 creative_run_id uuid not null unique references public.sc_creative_runs(id),
 actor_user_id uuid not null,
 idempotency_key text not null,
 request_hash text not null,
 compiled_plan jsonb not null,
 plan_sha256 text not null check(plan_sha256 ~ '^[0-9a-f]{64}$'),
 quality_input jsonb not null,
 quality_slot integer not null check(quality_slot between 1 and 3),
 claim_token uuid not null,
 lease_version bigint not null check(lease_version > 0),
 expires_at timestamptz not null,
 revoked_at timestamptz,
 active_xid bigint,
 consumed_at timestamptz,
 job_id uuid unique,
 unique(actor_user_id,idempotency_key),
 check ((consumed_at is null) = (job_id is null))
);
alter table sc_internal.factory_permits enable row level security;
revoke all on sc_internal.factory_permits from public,anon,authenticated,service_role;
create unique index factory_one_active_per_transaction on sc_internal.factory_permits(active_xid) where active_xid is not null;

create function sc_internal.factory_run_uuid(value text) returns uuid
language sql immutable set search_path='' as $$
 select case when value ~* '^([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$' then value::uuid else null end
$$;

-- Native PG canonical jsonb text; intentionally versioned separately from JS hash v1.
create function sc_internal.factory_plan_hash(p jsonb) returns text
language sql immutable strict set search_path='' as $$
 select encode(sha256(convert_to(p::text,'UTF8')),'hex')
$$;

-- Called under locked command, permit, config and policy rows. Never uses user_metadata.
create function sc_internal.factory_assert(p_command uuid,p_token uuid,p_version bigint)
returns void language plpgsql security definer set search_path='' as $$
declare c sc_internal.v5_commands%rowtype; p sc_internal.factory_permits%rowtype;
 meta jsonb; policy jsonb; policy_status text; slot_status text; fmt text; op text;
begin
 select * into c from sc_internal.v5_commands where command_id=p_command for update;
 select * into p from sc_internal.factory_permits where command_id=p_command for update;
 if c.command_id is null or p.command_id is null then raise exception 'PERMIT_REQUIRED'; end if;
 if auth.uid() is null or auth.uid() is distinct from c.actor_user_id then raise exception 'ACTOR_REQUIRED'; end if;
 select raw_app_meta_data into meta from auth.users where id=auth.uid() for share;
 if meta->>'command_center' is distinct from 'true' or
    not coalesce(meta->>'solar_role'='v5_operator' or meta->'roles' ? 'v5_operator',false)
 then raise exception 'OPERATOR_REQUIRED'; end if;
 perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=auth.uid() for share;
 if not found then raise exception 'SESSION_REVOKED'; end if;
 if p.revoked_at is not null then raise exception 'PERMIT_REVOKED'; end if;
 if p.actor_user_id is distinct from c.actor_user_id or p.idempotency_key is distinct from c.idempotency_key
 or p.request_hash is distinct from c.request_hash
 or c.request_hash is distinct from public.sc_v5_command_request_hash_v1(c.command_type,c.target,c.payload,c.confirmation_intent,c.mode)
 or c.command_type is distinct from 'factory.start' or c.mode is distinct from 'EXECUTE'
 or c.confirmation_intent is distinct from 'REAL_EXECUTION'
 or c.target is distinct from '{"agent":"FACTORY","job_id":null}'::jsonb
 or c.payload->>'creative_run_id' is distinct from p.creative_run_id::text
 or c.payload->>'compiled_plan_sha256' is distinct from p.plan_sha256
 or c.payload->>'plan_hash_algorithm' is distinct from 'sha256-pg-jsonb-v1'
 or c.payload->>'max_jobs' is distinct from '1' or c.payload->>'stop_at' is distinct from 'READY'
 or c.payload->>'additional_paid_cost_usd' is distinct from '0'
 then raise exception 'COMMAND_BINDING_CONFLICT'; end if;
 if c.claim_token is distinct from p_token or p.claim_token is distinct from p_token
 or c.lease_version is distinct from p_version or p.lease_version is distinct from p_version
 or coalesce(c.status not in ('CLAIMED','EXECUTING'),true) or c.claim_expires_at is null
 or c.claim_expires_at<=clock_timestamp() or p.expires_at<=clock_timestamp()
 then raise exception 'LEASE_INVALID'; end if;
 -- Lock canonical gate row: concurrent emergency closure serializes with this short transaction.
 perform 1 from public.sc_agent_config where id='solar_connects_v1' for share;
 if public.sc_security_operation_gate_v1('FACTORY')->>'allowed' is distinct from 'true'
 then raise exception 'FACTORY_OFF'; end if;
 foreach op in array array['PUBLISHER','META_DIRECT','EXTERNAL_WRITE'] loop
 if public.sc_security_operation_gate_v1(op)->>'allowed' is distinct from 'false'
 then raise exception 'PUBLICATION_GATE_NOT_OFF'; end if; end loop;
 select details,status into policy,policy_status from public.sc_system_health
 where component='solar_quality_v2_production_flags' for share;
 select status into slot_status from public.sc_system_health
 where component='solar_quality_v2_first_slot' for share;
 fmt:=p.compiled_plan->>'format';
 if policy_status is null or slot_status is null or policy_status like '%FROZEN%' or slot_status like '%FROZEN%'
 or policy->>'enabled' is distinct from 'true'
 or policy#>>array['formats',fmt,'kill_switch'] is distinct from 'false'
 then raise exception 'QUALITY_V2_FROZEN_OR_UNKNOWN'; end if;
end $$;

-- Only a RESERVED run or controlled marker enters this new authorization path.
-- Legacy rows without a reservation retain existing RLS/triggers/producer gates.
create function sc_internal.factory_insert_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare run_id uuid; lock_run uuid; p sc_internal.factory_permits%rowtype; key_run text;
begin
 -- Quality V2's existing exact key identifies the run before late annotations.
 key_run:=substring(new.content_plan->>'idempotency_key' from '^quality-v2-shadow:factory_run_([0-9a-f]{32})$');
 run_id:=coalesce(sc_internal.factory_run_uuid(new.content_plan->>'creative_run_id'),sc_internal.factory_run_uuid(new.qa->>'creative_run_id'),sc_internal.factory_run_uuid(key_run));
 if run_id is null then
 if new.qa ? 'factory_command_id' or new.qa ? 'factory_plan_sha256' then raise exception 'UNBOUND_CONTROLLED_MARKER'; end if;
 return new;
 end if;
 -- Lock every supplied valid identity in order, including inconsistent aliases,
 -- so a concurrent authorization cannot reserve a run hidden in qa/key.
 for lock_run in select distinct sc_internal.factory_run_uuid(x) from unnest(array[new.content_plan->>'creative_run_id',new.qa->>'creative_run_id',key_run]) x
 where sc_internal.factory_run_uuid(x) is not null order by 1 loop
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('factory-run:'||lock_run,0));
 end loop;
 select * into p from sc_internal.factory_permits where creative_run_id=run_id for update;
 if p.command_id is null then
 if new.qa ? 'factory_command_id' or new.qa ? 'factory_plan_sha256' then raise exception 'UNBOUND_CONTROLLED_MARKER'; end if;
 -- Do not let inconsistent second identity conceal a reserved run.
 if exists(select 1 from sc_internal.factory_permits x where x.creative_run_id=sc_internal.factory_run_uuid(new.qa->>'creative_run_id')
 or x.creative_run_id=sc_internal.factory_run_uuid(key_run)) then raise exception 'RUN_BINDING_CONFLICT'; end if;
 return new;
 end if;
 if (new.content_plan->>'creative_run_id' is not null and (new.content_plan->>'creative_run_id')::uuid<>run_id)
 or (new.qa->>'creative_run_id' is not null and (new.qa->>'creative_run_id')::uuid<>run_id)
 or (key_run is not null and key_run::uuid<>run_id) then raise exception 'RUN_BINDING_CONFLICT'; end if;
 if p.command_id is null or p.active_xid is distinct from txid_current() or p.consumed_at is not null
 then raise exception 'TRANSACTION_PERMIT_REQUIRED'; end if;
 perform sc_internal.factory_assert(p.command_id,p.claim_token,p.lease_version);
 if exists(select 1 from public.sc_content_jobs j where j.content_plan->>'creative_run_id'=run_id::text or j.qa->>'creative_run_id'=run_id::text)
 then raise exception 'RUN_ALREADY_MATERIALIZED'; end if;
 new.content_plan:=coalesce(new.content_plan,'{}')||jsonb_build_object('creative_run_id',run_id);
 new.qa:=coalesce(new.qa,'{}')||jsonb_build_object('publish_blocked',true,'do_not_publish',true,
 'creative_run_id',run_id,'factory_command_id',p.command_id,'factory_plan_sha256',p.plan_sha256);
 update sc_internal.factory_permits set consumed_at=clock_timestamp(),job_id=new.id where command_id=p.command_id;
 return new;
end $$;
create trigger factory_controlled_insert before insert on public.sc_content_jobs
for each row execute function sc_internal.factory_insert_guard();

-- Protect controlled/reserved identities only; allow legacy late annotations.
create function sc_internal.factory_run_binding_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare rid uuid; controlled boolean:=false;
begin
 for rid in select distinct sc_internal.factory_run_uuid(x) from unnest(array[
 old.content_plan->>'creative_run_id',old.qa->>'creative_run_id',new.content_plan->>'creative_run_id',new.qa->>'creative_run_id',
 substring(old.content_plan->>'idempotency_key' from '^quality-v2-shadow:factory_run_([0-9a-f]{32})$'),
 substring(new.content_plan->>'idempotency_key' from '^quality-v2-shadow:factory_run_([0-9a-f]{32})$')]) x where sc_internal.factory_run_uuid(x) is not null order by 1 loop
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('factory-run:'||rid,0));
 controlled:=controlled or exists(select 1 from sc_internal.factory_permits where creative_run_id=rid);
 end loop;
 if not controlled and not (coalesce(old.qa,'{}') ? 'factory_command_id' or coalesce(new.qa,'{}') ? 'factory_command_id'
 or coalesce(old.qa,'{}') ? 'factory_plan_sha256' or coalesce(new.qa,'{}') ? 'factory_plan_sha256') then return new; end if;
 if old.content_plan->>'creative_run_id' is distinct from new.content_plan->>'creative_run_id'
 or old.qa->>'creative_run_id' is distinct from new.qa->>'creative_run_id'
 or old.content_plan->>'idempotency_key' is distinct from new.content_plan->>'idempotency_key'
 or old.qa->>'factory_command_id' is distinct from new.qa->>'factory_command_id'
 or old.qa->>'factory_plan_sha256' is distinct from new.qa->>'factory_plan_sha256'
 then raise exception 'CREATIVE_RUN_IMMUTABLE'; end if;
 return new;
end $$;
create trigger factory_controlled_run_update before update on public.sc_content_jobs
for each row execute function sc_internal.factory_run_binding_guard();

create function sc_internal.factory_materialize(p_command uuid,p_token uuid,p_version bigint,p_hash text,p_quality jsonb,p_slot integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p sc_internal.factory_permits%rowtype; compiled jsonb; r jsonb; stage_name text; evidence record;
begin
 -- Consistent lock order: run advisory -> command -> permit -> policy/config.
 select * into p from sc_internal.factory_permits where command_id=p_command;
 if p.command_id is null then raise exception 'PERMIT_REQUIRED'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('factory-run:'||p.creative_run_id,0));
 perform sc_internal.factory_assert(p_command,p_token,p_version);
 select * into p from sc_internal.factory_permits where command_id=p_command for update;
 if p_hash is distinct from p.plan_sha256 then raise exception 'PLAN_HASH_CONFLICT'; end if;
 if p_quality is distinct from p.quality_input or p_slot is distinct from p.quality_slot then raise exception 'QUALITY_BINDING_CONFLICT'; end if;
 if p.consumed_at is not null then return jsonb_build_object('ok',true,'state','DUPLICATE','job_id',p.job_id); end if;
 -- Table SHARE blocks stage inserts/updates until commit; short, no external work here.
 lock table public.sc_creative_stage_outputs in share mode;
 perform 1 from public.sc_creative_runs where id=p.creative_run_id and status='APPROVED'
 and created_at between clock_timestamp()-interval '24 hours' and clock_timestamp() for share;
 if not found then raise exception 'FRESH_APPROVED_RUN_REQUIRED'; end if;
 foreach stage_name in array array['RADAR','EDITOR','DIRECTOR'] loop
 select s.validation_status,s.schema_version into evidence from public.sc_creative_stage_outputs s
 where s.run_id=p.creative_run_id and s.stage=stage_name order by s.attempt desc limit 1;
 if not found or evidence.validation_status is distinct from 'VALID'
 or evidence.schema_version is distinct from (case stage_name when 'RADAR' then 'radar-v1' when 'EDITOR' then 'editor-v2' else 'director-v2' end)
 then raise exception 'LATEST_STAGE_INVALID'; end if;
 end loop;
 compiled:=public.sc_creative_compile_carousel_v1(p.creative_run_id);
 if compiled->>'ok' is distinct from 'true' or compiled is distinct from p.compiled_plan
 or sc_internal.factory_plan_hash(compiled) is distinct from p_hash then raise exception 'PLAN_HASH_CONFLICT'; end if;
 if public.sc_creative_render_preflight_v1(p.creative_run_id)->>'ok' is distinct from 'true'
 then raise exception 'PREFLIGHT_REJECTED'; end if;
 if public.sc_quality_factory_hook_v2(p.creative_run_id,p_slot)->>'route' is distinct from 'V2'
 then raise exception 'QUALITY_V2_REQUIRED'; end if;
 update sc_internal.factory_permits set active_xid=txid_current() where command_id=p_command;
 -- EXISTING Quality V2 validator/materializer. No V1 fallback, no copied production engine.
 r:=public.sc_quality_factory_production_v2(p.creative_run_id,p_quality,p_slot,true);
 select * into p from sc_internal.factory_permits where command_id=p_command;
 if r->>'ok' is distinct from 'true' or p.job_id is null or r->>'job_id' is distinct from p.job_id::text
 then raise exception 'QUALITY_MATERIALIZATION_REJECTED'; end if;
 perform sc_internal.factory_assert(p_command,p_token,p_version); -- clock checked AFTER work
 update sc_internal.factory_permits set active_xid=null where command_id=p_command;
 update sc_internal.v5_commands set status='EXECUTING',updated_at=clock_timestamp(),
 result=coalesce(result,'{}')||jsonb_build_object('factory_materialization',r,'stop_at','READY') where command_id=p_command;
 return r; -- Not SUCCEEDED/READY: renderer and Guardian remain separate existing steps.
 -- Any exception rolls back job + permit consumption + ledger changes together.
end $$;

-- Only DBA can provision/revoke a permit until explicit one-canary authorization.
-- No public RPC, no role grants, no Edge execution switch included in this candidate.
create function sc_internal.factory_authorize(p_command uuid,p_token uuid,p_version bigint,p_confirmation text,p_quality jsonb,p_slot integer)
returns void language plpgsql security definer set search_path='' as $$
declare c sc_internal.v5_commands%rowtype; compiled jsonb; run_id uuid; hash text;
begin
 select * into c from sc_internal.v5_commands where command_id=p_command;
 if c.command_id is null then raise exception 'COMMAND_REQUIRED'; end if;
 run_id:=(c.payload->>'creative_run_id')::uuid;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('factory-run:'||run_id,0));
 select * into c from sc_internal.v5_commands where command_id=p_command for update;
 if exists(select 1 from public.sc_content_jobs j where j.content_plan->>'creative_run_id'=run_id::text or j.qa->>'creative_run_id'=run_id::text
 or j.content_plan->>'idempotency_key'='quality-v2-shadow:factory_run_'||replace(run_id::text,'-',''))
 then raise exception 'RUN_ALREADY_MATERIALIZED'; end if;
 compiled:=public.sc_creative_compile_carousel_v1(run_id);
 hash:=sc_internal.factory_plan_hash(compiled);
 if compiled->>'ok' is distinct from 'true' or hash is distinct from c.payload->>'compiled_plan_sha256'
 or p_confirmation is distinct from 'REAL:'||p_command||':'||c.idempotency_key||':factory.start:'||run_id||':'||hash
 then raise exception 'EXPLICIT_CONFIRMATION_REQUIRED'; end if;
 insert into sc_internal.factory_permits(command_id,creative_run_id,actor_user_id,idempotency_key,request_hash,compiled_plan,plan_sha256,quality_input,quality_slot,claim_token,lease_version,expires_at)
 values(p_command,run_id,c.actor_user_id,c.idempotency_key,c.request_hash,compiled,hash,p_quality,p_slot,p_token,p_version,c.claim_expires_at);
 -- Authorization cannot even be provisioned while the global gate/freeze denies it.
 perform sc_internal.factory_assert(p_command,p_token,p_version);
end $$;
revoke all on function sc_internal.factory_authorize(uuid,uuid,bigint,text,jsonb,integer) from public,anon,authenticated,service_role;
revoke all on function sc_internal.factory_run_uuid(text) from public,anon,authenticated,service_role;
revoke all on function sc_internal.factory_plan_hash(jsonb) from public,anon,authenticated,service_role;
revoke all on function sc_internal.factory_assert(uuid,uuid,bigint) from public,anon,authenticated,service_role;
revoke all on function sc_internal.factory_insert_guard() from public,anon,authenticated,service_role;
revoke all on function sc_internal.factory_run_binding_guard() from public,anon,authenticated,service_role;
revoke all on function sc_internal.factory_materialize(uuid,uuid,bigint,text,jsonb,integer) from public,anon,authenticated,service_role;
commit;
