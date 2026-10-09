-- STAGING ONLY. Caller identity comes from verified Supabase JWT, not request JSON.
create function public.sc_factory_staging_v1(p_request jsonb) returns jsonb
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
revoke all on function public.sc_factory_staging_v1(jsonb) from public,anon,service_role;
grant execute on function public.sc_factory_staging_v1(jsonb) to authenticated;
